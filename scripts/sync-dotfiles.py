#!/usr/bin/env python3
"""Refresh bundled setup profiles from the canonical public dot-files repository."""
import argparse
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "Sources/MacSetupCore/Resources/Profile"
SOURCE_URL = "https://github.com/Roobahist/dot-files.git"
SHARED_DIRS = {"aerospace", "alacritty", "atuin", "karabiner", "sketchybar", "unsplash"}


def run(args, *, env=None):
    subprocess.run(args, check=True, env=env)


def manifest_paths(repository):
    manifest = repository / "mac-setup-files.txt"
    if not manifest.is_file() or manifest.is_symlink():
        raise ValueError("Public source manifest is missing or a symlink")
    paths = [line.strip() for line in manifest.read_text().splitlines()
             if line.strip() and not line.startswith("#")]
    if len(set(paths)) != len(paths) or not paths:
        raise ValueError("Missing or duplicate manifest paths")
    for name in paths:
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or relative.parts[0] not in SHARED_DIRS:
            raise ValueError("Unsafe path in manifest: " + name)
        item = repository / relative
        if not item.is_file() or item.is_symlink() or not item.resolve().is_relative_to(repository.resolve()):
            raise ValueError("Missing or unsafe source file: " + name)
    return paths


def build_profile(repository, destination):
    paths = manifest_paths(repository)
    destination.mkdir(parents=True)
    for name in paths:
        source = repository / name
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    # The compiled host-geometry adapter belongs to the installer profile.
    adapter = PROFILE / "sketchybar/plugins/geometry.sh"
    if adapter.is_file():
        shutil.copy2(adapter, destination / "sketchybar/plugins/geometry.sh")
    # This app's portable settings are managed by mac-setup, not dot-files.
    shutil.copytree(PROFILE / "vorssaint", destination / "vorssaint")
    env = dict(os.environ, MAC_SETUP_PROFILE_ROOT=str(destination))
    run([sys.executable, str(ROOT / "scripts/check-profile.py")], env=env)
    return len(paths)


def snapshot(directory):
    return {path.relative_to(directory).as_posix(): (path.read_bytes(), bool(path.stat().st_mode & 0o111))
            for path in directory.rglob("*") if path.is_file()}


def synchronize(source, *, check_only):
    with tempfile.TemporaryDirectory(prefix=".dotfiles-sync-", dir=PROFILE.parent) as tmp:
        workspace = Path(tmp)
        clone = workspace / "source"
        if source is None:
            run(["git", "clone", "--quiet", "--depth", "1", "--branch", "main",
                 "--", SOURCE_URL, str(clone)])
        else:
            clone = source.resolve()
        candidate = workspace / "Profile"
        count = build_profile(clone, candidate)
        changed = snapshot(candidate) != snapshot(PROFILE)
        if check_only:
            if changed:
                print("Bundled profiles differ from public dot-files source")
                return 1
            print("Bundled profiles match public dot-files")
            return 0
        if not changed:
            print("No dot-files profile changes")
            return 0

        old = workspace / "old-profile"
        PROFILE.rename(old)
        try:
            candidate.rename(PROFILE)
        except BaseException:
            old.rename(PROFILE)
            raise
        print(f"Updated bundled profiles from {count} allowlisted public files")
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Use a local dot-files checkout")
    parser.add_argument("--check", action="store_true", help="Report drift without modifying files")
    args = parser.parse_args()
    try:
        return synchronize(args.source, check_only=args.check)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Cannot synchronize profiles: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
