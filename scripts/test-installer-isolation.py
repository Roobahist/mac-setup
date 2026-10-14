#!/usr/bin/env python3
"""Regression: installing the app must not operate the optional watcher."""

import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
script = (repo / "scripts/install.sh").read_text(encoding="utf-8")

# Registration or migrations belong to an explicit in-app or CLI action.
assert "watcher-enable" not in script
assert "launchctl" not in script


def install_case(preconfigured: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="mac-setup-installer-test-") as base:
        root = Path(base)
        home, source = root / "home", root / "release"
        home.mkdir()
        source.mkdir()

        # The executable fails if the installer tries any CLI action.
        spy = root / "unexpected-cli-invocations.log"
        for binary in ("mac-setup", "mac-setup-display", "mac-setup-wallpaper-watcher"):
            program = source / binary
            program.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$*" >> "$MAC_SETUP_INSTALL_SPY"\nexit 97\n',
                encoding="utf-8",
            )
            program.chmod(0o755)
        (source / "MacSetup_MacSetupCore.bundle").mkdir()
        (source / "MacSetup_MacSetupCore.bundle" / "dummy").write_text("resource")
        helper = source / "Mac Setup.app" / "Contents" / "Helpers"
        helper.mkdir(parents=True)
        (helper / "mac-setup-wallpaper-watcher").write_text("bundled helper")

        agents = home / "Library" / "LaunchAgents"
        original_agents = {}
        if preconfigured:
            agents.mkdir(parents=True)
            for label in (
                "com.roobahist.wallpaper-watcher",
                "io.github.roobahist.mac-setup.wallpaper",
            ):
                plist = agents / (label + ".plist")
                plist.write_text(f"original: {label}\n")
                original_agents[plist.name] = plist.read_bytes()

        env = os.environ.copy()
        env.update({
            "HOME": str(home),
            "ZDOTDIR": str(home),
            "MAC_SETUP_PREFIX": str(home / ".local"),
            "MAC_SETUP_SOURCE_DIR": str(source),
            "MAC_SETUP_INSTALL_SPY": str(spy),
        })

        # Test fresh installs and repeat upgrades with existing configuration.
        for _ in range(2):
            result = subprocess.run(
                ["bash", str(repo / "scripts/install.sh")],
                env=env, cwd=repo, text=True, capture_output=True,
            )
            if result.returncode:
                raise AssertionError(result.stdout + result.stderr)
            assert not spy.exists(), "Installer unexpectedly executed mac-setup CLI"
            assert "Enabled." not in result.stdout
            assert (home / "Applications" / "Mac Setup.app").is_symlink()
            assert (home / ".local" / "lib" / "mac-setup" / "current"
                    / "mac-setup-wallpaper-watcher").exists()
            current_agents = (
                {p.name: p.read_bytes() for p in agents.glob("*.plist")}
                if agents.is_dir() else {}
            )
            assert current_agents == original_agents, (
                "Installing Mac Setup changed a watcher LaunchAgent"
            )


install_case(preconfigured=False)
install_case(preconfigured=True)
print("App install and upgrade leave the wallpaper watcher opt-in and untouched.")
