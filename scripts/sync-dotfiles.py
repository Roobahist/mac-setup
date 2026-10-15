#!/usr/bin/env python3
"""Refresh bundled setup profiles from the canonical public dot-files repository."""
import argparse
import hashlib
import fcntl
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "Sources/MacSetupCore/Resources/Profile"
SOURCE_URL = "https://github.com/Roobahist/dot-files.git"
SHARED_DIRS = {"aerospace", "alacritty", "atuin", "karabiner", "sketchybar", "unsplash"}
REFERENCE = ROOT / "Sources/MacSetupCore/Resources/ReferenceProfile.json"


def reference_profile(repository, paths, revision):
    """Compile editor defaults from the same files we ship, without running shell."""
    import re
    for name in paths:
        relative = PurePosixPath(name)
        target = repository / relative
        if (relative.is_absolute() or ".." in relative.parts or not relative.parts
                or relative.parts[0] not in SHARED_DIRS or target.is_symlink()
                or not target.is_file() or not target.resolve().is_relative_to(repository.resolve())):
            raise ValueError("Unsafe reference file: " + name)
    aerospace = tomllib.loads((repository / "aerospace/aerospace.toml").read_text())
    bindings = aerospace["mode"]["main"]["binding"]
    bar = (repository / "sketchybar/sketchybarrc").read_text()
    variables = {}
    def literal(expression):
        text = expression.strip().strip('"')
        if re.fullmatch(r"\$[A-Z_]+", text):
            return variables[text[1:]]
        if "$" in text or "`" in text or "\\" in text:
            raise ValueError("Unsupported dynamic workspace icon/font: " + expression)
        return text
    for key, value in re.findall(r'^([A-Z_]+)=("[^"\n]*")', bar, re.M):
        if key.startswith(("ICON_", "FONT_", "FA_")):
            variables[key] = literal(value)
    icon_body = bar.split('workspace_icon() {', 1)[1].split('\n}', 1)[0]
    icons = {key: literal(value) for key, value in
             re.findall(r'^\s*([a-zA-Z0-9_-]+)\)\s*echo\s+("[^"]*")\s*;;', icon_body, re.M)}
    font_body = bar.split('workspace_font() {', 1)[1].split('\n}', 1)[0]
    fonts = {}
    for keys, value in re.findall(r'^\s*([a-zA-Z0-9_|*-]+)\)\s*echo\s+("[^"]*")\s*;;', font_body, re.M):
        for key in keys.split('|'):
            fonts[key] = literal(value)
    postscript_names = {("SF Pro", "Regular"): "SFPro-Regular",
                        ("Hack Nerd Font", "Bold"): "HackNF-Bold"}
    labels = {"chatgpt": ("AI", "robot"), "ai": ("AI", "robot"), "music": ("Music", "music"),
              "messages": ("Messages", "chat"), "notes": ("Notes", "notes"),
              "timer": ("Pomodoro", "clock")}
    workspaces = []
    keymap = None
    for source_id in aerospace["persistent-workspaces"]:
        name, glyph = labels.get(source_id, (source_id, source_id if source_id.isdigit() else "star"))
        switches = [key.split("-") for key, value in bindings.items() if value == "workspace " + source_id]
        moves = [key.split("-") for key, value in bindings.items()
                 if isinstance(value, list) and value and value[0] == "move-node-to-workspace " + source_id]
        if len(switches) != 1 or len(moves) != 1 or switches[0][-1] != moves[0][-1]:
            raise ValueError("Expected one shared destination key for " + source_id)
        current_keymap = dict(switchModifiers=switches[0][:-1], moveModifiers=moves[0][:-1])
        if keymap is not None and current_keymap != keymap:
            raise ValueError("Source workspace modifiers are not shared; update the editor model before syncing")
        keymap = current_keymap
        family, font_style, size = fonts.get(source_id, fonts["*"]).split(":")
        if size != "14.5" or (family, font_style) not in postscript_names:
            raise ValueError("Update the editor font model for source font " + fonts.get(source_id, fonts["*"]))
        symbol = icons[source_id]
        if len(symbol) != 1:
            raise ValueError("Source workspace icon must be one Unicode character")
        icon = dict(symbol=symbol, font=dict(family=family, style=font_style,
                                           postScriptName=postscript_names[family, font_style]))
        apps = []
        for rule in aerospace.get("on-window-detected", []):
            actions = rule["run"] if isinstance(rule["run"], list) else [rule["run"]]
            if "move-node-to-workspace " + source_id in actions:
                match = re.fullmatch(r"test %\{app-bundle-id\} = ([\w.-]+)", rule["if"])
                if not match:
                    raise ValueError("Unsupported routing condition: " + str(rule["if"]))
                apps.append(match[1])
        # Explicit presentation migration; every generated reference uses ai.
        workspaces.append(dict(id="ai" if source_id == "chatgpt" else source_id,
                               name=name, glyph=glyph, icon=icon, apps=apps, shortcutKey=switches[0][-1],
                               monitor=aerospace.get("workspace-to-monitor-force-assignment", {}).get(source_id, "automatic")))
    karabiner = json.loads((repository / "karabiner/karabiner.json").read_text())
    profile = next(p for p in karabiner["profiles"] if p.get("selected"))
    shortcuts = []
    modifiers = {"command": "cmd", "control": "ctrl", "option": "alt", "shift": "shift"}
    for rule in profile["complex_modifications"]["rules"]:
        if rule["description"] not in {"Alacritty", "Visual Studio Code", "Finder", "Telegram", "WhatsApp"}:
            continue
        manipulator, = rule["manipulators"]
        names = {"Alacritty": "alacritty", "Visual Studio Code": "vscode", "Finder": "finder", "Telegram": "telegram", "WhatsApp": "whatsapp"}
        key = manipulator["from"]["key_code"]
        shortcuts.append(dict(id="karabiner:" + names[rule["description"]], provider="Karabiner",
                              action=rule["description"], enabled=rule.get("enabled", True),
                              shortcut=dict(key="enter" if key == "return_or_enter" else key,
                                            modifiers=[modifiers[m] for m in manipulator["from"]["modifiers"]["mandatory"]])))
    if len(shortcuts) != 5:
        raise ValueError("Missing reference application shortcuts")
    palette = (repository / "sketchybar/plugins/colors.sh").read_text()
    def setting(source, pattern):
        values = re.findall(pattern, source, re.M)
        if len(values) != 1:
            raise ValueError("Missing or ambiguous source setting: " + pattern)
        return values[0]
    workspace_items = bar.split("# Create workspace items", 1)[1].split("##### Clock #####", 1)[0]
    style = dict(itemWidth=int(setting(workspace_items, r"^\s*label\.width=(\d+)")),
                 blurRadius=int(setting(bar, r"^\s*blur_radius=(\d+)")),
                 backgroundColor=setting(palette, r"^export BAR_COLOR=(0x[0-9a-fA-F]{8})$"),
                 occupiedColor=setting(palette, r"^export BASE_WHITE=(0x[0-9a-fA-F]{8})$"),
                 emptyColor=setting(palette, r"^export BASE_GRAY=(0x[0-9a-fA-F]{8})$"))
    return dict(repository=SOURCE_URL, revision=revision,
                files={name: hashlib.sha256((repository / name).read_bytes()).hexdigest() for name in paths},
                layout=dict(workspaces=workspaces, keymap=keymap, barStyle=style), karabinerShortcuts=shortcuts)


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
    with (ROOT / ".sync-dotfiles.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("Another profile synchronization is running; retry after it finishes")
        return synchronize_locked(source, check_only=check_only)


def synchronize_locked(source, *, check_only):
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
        paths = manifest_paths(clone)
        if subprocess.run(["git", "-C", str(clone), "diff", "--quiet", "HEAD", "--",
                           "mac-setup-files.txt", *paths], check=False).returncode != 0:
            raise ValueError("Source has uncommitted profile changes; commit the reviewed source before syncing")
        revision = subprocess.check_output(["git", "-C", str(clone), "rev-parse", "HEAD"], text=True).strip()
        reference = json.dumps(reference_profile(clone, paths, revision), indent=2, sort_keys=True) + "\n"
        changed = snapshot(candidate) != snapshot(PROFILE) or not REFERENCE.exists() or REFERENCE.read_text() != reference
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
        candidate_reference = workspace / "ReferenceProfile.json"
        candidate_reference.write_text(reference)
        PROFILE.rename(old)
        try:
            candidate.rename(PROFILE)
            os.replace(candidate_reference, REFERENCE)
        except BaseException:
            if PROFILE.exists():
                shutil.rmtree(PROFILE)
            old.rename(PROFILE)
            raise
        print(f"Updated bundled profiles from {count} allowlisted public files")
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Use a local dot-files checkout")
    parser.add_argument("--check", action="store_true", help="Report drift without modifying files")
    parser.add_argument("--verify-bundled", action="store_true", help="Verify shipped files and editor defaults against the recorded source")
    args = parser.parse_args()
    try:
        if args.verify_bundled:
            recorded = json.loads(REFERENCE.read_text())
            expected_paths = set(recorded["files"]) | {"sketchybar/plugins/geometry.sh", "vorssaint/preferences.plist"}
            if set(snapshot(PROFILE)) != expected_paths:
                raise ValueError("Bundled profile contains unexpected or missing files; synchronize from the allowlist")
            actual = reference_profile(PROFILE, list(recorded["files"]), recorded["revision"])
            if actual != recorded:
                raise ValueError("Bundled profiles or editor defaults drifted from their recorded source; run sync-dotfiles.py")
            print("Bundled profiles and editor defaults match source " + recorded["revision"])
            return 0
        return synchronize(args.source, check_only=args.check)
    except (ValueError, OSError, KeyError, TypeError, IndexError, subprocess.CalledProcessError) as error:
        print(f"Cannot synchronize profiles: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
