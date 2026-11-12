#!/usr/bin/env python3
"""Check that large-wallpaper preprocessing and ImageMagick stages remain bounded."""

from __future__ import annotations

import importlib.util
import colorsys
import subprocess
import sys
import unittest
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


def swatch(hex_color: str, fraction: float):
    rgb = module.parse_rgb(hex_color)
    hue, saturation, value = colorsys.rgb_to_hsv(*rgb)
    return module.Swatch(fraction, *rgb, hue, saturation, value,
                         module.relative_luminance(*rgb))


class ColorSelectionTests(unittest.TestCase):
    def test_small_dark_subject_beats_light_bar_background(self):
        # A pale blue sky and a dark road with narrow ochre markings. The old
        # 3% area gate discarded the markings before comparing readability.
        backdrop = module.parse_rgb("#90A2B0")
        sky = swatch("#7D99AE", 0.406)
        road = swatch("#202020", 0.580)
        yellow = swatch("#87632A", 0.014)
        selected = module.select_swatch([sky, road, yellow], backdrop,
                                        [backdrop] * 60, scene_mean=0.376)
        self.assertIsNotNone(selected)
        color = module.tune(selected, backdrop, [backdrop] * 60)
        hue, saturation, value = colorsys.rgb_to_hsv(*module.parse_rgb(color))
        self.assertTrue(35 <= hue * 360 <= 60, color)
        self.assertGreaterEqual(saturation, 0.45)
        self.assertGreaterEqual(value, 0.90)
        self.assertGreaterEqual(module.regional_separation(
            module.parse_rgb(color), [backdrop] * 60), 0.46)

    def test_light_bar_refinement_keeps_lit_paint_instead_of_brown_shadow(self):
        backdrop = module.parse_rgb("#90A2B0")
        sky = swatch("#7D99AE", 0.406)
        yellow = swatch("#87632A", 0.014)
        lit_paint = swatch("#9A7433", 0.000035)
        shadow = swatch("#80520D", 0.0074)
        selected = module.select_swatch([sky, yellow], backdrop,
                                        [backdrop] * 60,
                                        [sky, lit_paint, shadow], scene_mean=0.376)
        color = module.tune(selected, backdrop, [backdrop] * 60)
        self.assertEqual((selected.red, selected.green, selected.blue),
                         (lit_paint.red, lit_paint.green, lit_paint.blue))
        self.assertAlmostEqual(colorsys.rgb_to_hsv(*module.parse_rgb(color))[0],
                               lit_paint.hue, delta=1 / 360)

    def test_readable_muted_source_is_still_made_vivid(self):
        backdrop = module.parse_rgb("#90A2B0")
        source = swatch("#9A7433", 0.014)
        color = module.tune(source, backdrop, [backdrop] * 60)
        hue, saturation, value = colorsys.rgb_to_hsv(*module.parse_rgb(color))
        self.assertGreaterEqual(saturation, 0.90)
        self.assertGreaterEqual(value, 0.94)
        self.assertAlmostEqual(hue, source.hue, delta=1 / 360)
        lab = module.oklab(*module.parse_rgb(color))
        self.assertGreaterEqual((lab[1] ** 2 + lab[2] ** 2) ** 0.5, 0.15)

    def test_vivid_tuning_applies_across_hues(self):
        backdrop = module.parse_rgb("#90A2B0")
        for hex_color in ["#657F99", "#688D59", "#9A5679", "#9A7433"]:
            with self.subTest(source=hex_color):
                source = swatch(hex_color, 0.03)
                color = module.tune(source, backdrop, [backdrop] * 60)
                hue, saturation, value = colorsys.rgb_to_hsv(*module.parse_rgb(color))
                self.assertGreaterEqual(saturation, 0.90)
                self.assertGreaterEqual(value, 0.94)
                self.assertAlmostEqual(hue, source.hue, delta=1 / 360)

    def test_already_vivid_color_is_preserved(self):
        backdrop = module.parse_rgb("#14202C")
        self.assertEqual(module.tune(swatch("#FFB000", 0.03), backdrop,
                                     [backdrop] * 60), "#FFB000")

    def test_one_pixel_noise_does_not_replace_supported_subject(self):
        backdrop = module.parse_rgb("#90A2B0")
        sky = swatch("#7D99AE", 0.98)
        yellow = swatch("#87632A", 0.01999)
        noise = swatch("#F000E0", 0.00001)
        selected = module.select_swatch([sky, yellow, noise], backdrop,
                                        [backdrop] * 60, scene_mean=0.7)
        self.assertLess(module.hue_distance(selected.hue, yellow.hue), 8 / 360)

    def test_dark_bar_retains_bright_subject(self):
        backdrop = module.parse_rgb("#14202C")
        blue = swatch("#29415E", 0.97)
        gold = swatch("#EFB638", 0.03)
        selected = module.select_swatch([blue, gold], backdrop,
                                        [backdrop] * 60, scene_mean=0.2)
        self.assertLess(module.hue_distance(selected.hue, gold.hue), 8 / 360)

    def test_monochrome_image_uses_neutral_accent(self):
        backdrop = module.parse_rgb("#B0B0B0")
        entries = [swatch("#B0B0B0", 0.9), swatch("#303030", 0.1)]
        self.assertIsNone(module.select_swatch(entries, backdrop, [backdrop] * 60))
        color = module.neutral_accent(entries, backdrop, [backdrop] * 60)
        self.assertEqual(colorsys.rgb_to_hsv(*module.parse_rgb(color))[1], 0)

    def test_image_pipeline_selects_small_ochre_road_markings(self):
        # Exercise ImageMagick, both histograms, family selection, refinement
        # and final tuning with a portable generated image (no private photo).
        width, height = 400, 240
        pixels = bytearray()
        for y in range(height):
            for x in range(width):
                rgb = (180, 202, 220) if y < 100 else (32, 32, 32)
                if y >= 100 and 190 <= x < 200:
                    rgb = (135, 99, 42)
                pixels.extend(rgb)
        image = f"P6\n{width} {height}\n255\n".encode() + pixels
        color = module.accent(module.prepare_image(image))
        hue, saturation, value = colorsys.rgb_to_hsv(*module.parse_rgb(color))
        self.assertTrue(35 <= hue * 360 <= 60, color)
        self.assertGreaterEqual(saturation, 0.45)
        self.assertGreaterEqual(value, 0.90)


if __name__ == "__main__":
    verify_preprocessing()
    verify_stages()
    verify_timeout()
    print("Wallpaper accent pipeline checks passed.")
    unittest.main()
