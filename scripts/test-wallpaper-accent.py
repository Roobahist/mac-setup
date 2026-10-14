#!/usr/bin/env python3
"""Check that large-wallpaper preprocessing and ImageMagick stages remain bounded."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

# Tests import a profile script directly. Never leave .pyc files inside the
# public profile, where portability validation expects portable text files.
sys.dont_write_bytecode = True

SOURCE = Path(__file__).resolve().parents[1] / (
    "Sources/MacSetupCore/Resources/Profile/unsplash/get_wallpaper_accent.py"
)
spec = importlib.util.spec_from_file_location("wallpaper_accent", SOURCE)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def verify_preprocessing() -> None:
    result = subprocess.CompletedProcess(args=[], returncode=0, stdout=b"normalized PNG")
    with patch.object(module.subprocess, "run", return_value=result) as mocked:
        assert module.prepare_image(b"huge-image") == b"normalized PNG"
        args = mocked.call_args.args[0]
        assert "-resize" in args and "1600x1600>" in args
        assert mocked.call_args.kwargs["timeout"] == module.PREPARE_TIMEOUT
        assert mocked.call_args.kwargs["input"] == b"huge-image"


def verify_stages() -> None:
    result = subprocess.CompletedProcess(args=[], returncode=0, stdout=b"#0088cc\n")
    with patch.object(module.subprocess, "run", return_value=result) as mocked:
        assert module.run_magick(b"small-image", "info:") == "#0088cc"
        assert mocked.call_args.kwargs["timeout"] == module.MAGICK_STAGE_TIMEOUT


def verify_timeout() -> None:
    with patch.object(module.subprocess, "run",
                      side_effect=subprocess.TimeoutExpired(cmd=["magick"], timeout=0.1)):
        try:
            module.prepare_image(b"image")
        except subprocess.TimeoutExpired:
            pass
        else:
            raise AssertionError("ImageMagick timeouts must propagate to the error handler")


if __name__ == "__main__":
    verify_preprocessing()
    verify_stages()
    verify_timeout()
    print("Wallpaper accent pipeline checks passed.")
