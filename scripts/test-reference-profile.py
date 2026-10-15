#!/usr/bin/env python3
"""Verify source compilation without executing shell or reading beyond the allowlist."""
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sync_dotfiles", root / "scripts/sync-dotfiles.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
recorded = json.loads(module.REFERENCE.read_text())
paths = list(recorded["files"])
assert module.reference_profile(module.PROFILE, paths, recorded["revision"]) == recorded

with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / "Profile"
    shutil.copytree(module.PROFILE, source)
    bar = source / "sketchybar/sketchybarrc"
    original = bar.read_text()
    bar.write_text(original.replace('ICON_MUSIC="􀑬"', 'ICON_MUSIC="M"').replace("blur_radius=50", "blur_radius=15"))
    result = module.reference_profile(source, paths, recorded["revision"])
    music = next(w for w in result["layout"]["workspaces"] if w["id"] == "music")
    assert music["icon"]["symbol"] == "M", "Source glyph changes must reach editor defaults"
    assert result["layout"]["barStyle"]["blurRadius"] == 15
    assert result["files"] != recorded["files"], "Content drift must change source hashes"
    bar.write_text(original.replace('ICON_MUSIC="􀑬"', 'ICON_MUSIC="$(id)"'))
    try:
        module.reference_profile(source, paths, recorded["revision"])
    except ValueError:
        pass
    else:
        raise AssertionError("Dynamic shell must be rejected, never executed while compiling defaults")
    for unsafe in ["../private.json", "/tmp/private.json", "karabiner/../../private.json"]:
        try:
            module.reference_profile(source, [unsafe], recorded["revision"])
        except ValueError:
            pass
        else:
            raise AssertionError("Unsafe reference path accepted: " + unsafe)
print("Reference defaults, glyph changes, palette changes, source hashes and path boundaries verified.")
