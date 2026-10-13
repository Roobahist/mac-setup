#!/usr/bin/env python3
"""Check that public configuration stays portable and excludes private data."""
import json
import os
import pathlib
import plistlib
import re
import tomllib

root = pathlib.Path(os.environ.get("MAC_SETUP_PROFILE_ROOT", pathlib.Path(__file__).resolve().parents[1] / "Sources/MacSetupCore/Resources/Profile"))
for path in root.rglob("*"):
    if not path.is_file():
        continue
    text = path.read_text()
    assert "/Users/" not in text, f"Personal path in {path}"
    assert not re.search(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", text), f"Email address in {path}"
    assert not re.search(r"-----BEGIN .*PRIVATE KEY-----|github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9]+|AKIA[A-Z0-9]{16}", text), f"Credential pattern in {path}"
    assert "automatic_backups" not in path.parts and "backups" not in path.parts
    if path.suffix == ".toml":
        tomllib.loads(text)

karabiner = json.loads((root / "karabiner/karabiner.json").read_text())
for profile in karabiner["profiles"]:
    assert all(not rule["description"].startswith("Grading:") for rule in profile["complex_modifications"]["rules"])

vorssaint = plistlib.loads((root / "vorssaint/preferences.plist").read_bytes())
for forbidden in ["shelfItems", "textSnippets", "commandBarUsage", "commandBarQueryHabitKey", "notchDownloadsFolderBookmark", "appVolumes", "NSOSPLastRootDirectory"]:
    assert forbidden not in vorssaint, f"Private Vorssaint field: {forbidden}"
assert all(isinstance(value, (bool, int, float, str)) for value in vorssaint.values())
assert vorssaint["autoQuitEnabled"] is True
print("Public profile checks passed. These checks do not replace a full secret review.")
