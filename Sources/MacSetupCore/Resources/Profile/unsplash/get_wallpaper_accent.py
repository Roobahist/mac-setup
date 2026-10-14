#!/usr/bin/env python3
"""Select one salient, readable SketchyBar accent from image bytes.

The privacy-approved watcher reads the Unsplash file and invokes this program
with ``-`` so neither Python nor ImageMagick needs access to Unsplash's
protected app container.
"""

from __future__ import annotations

import shutil
import colorsys
import math
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


MAGICK = shutil.which("magick") or "magick"
MAGICK_STAGE_TIMEOUT = 18
PREPARE_TIMEOUT = 32


def prepare_image(image_data: bytes) -> bytes:
    """Decode the source once to avoid repeatedly processing a huge wallpaper."""
    result = subprocess.run(
        [MAGICK, "-", "-auto-orient", "-resize", "1600x1600>", "png:-"],
        input=image_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=PREPARE_TIMEOUT,
    )
    if not result.stdout:
        raise ValueError("ImageMagick produced an empty normalized wallpaper")
    return result.stdout


@dataclass(frozen=True)
class Swatch:
    fraction: float
    red: float
    green: float
    blue: float
    hue: float
    saturation: float
    value: float
    luminance: float


def run_magick(image_data: bytes, *arguments: str) -> str:
    command = [MAGICK, "-", "-auto-orient", *arguments]
    return subprocess.run(
        command,
        input=image_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=MAGICK_STAGE_TIMEOUT,
    ).stdout.decode("utf-8", errors="strict").strip()


def relative_luminance(red: float, green: float, blue: float) -> float:
    def linear(channel: float) -> float:
        return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4

    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)


def contrast_ratio(first: float, second: float) -> float:
    lighter, darker = max(first, second), min(first, second)
    return (lighter + 0.05) / (darker + 0.05)


def oklab(red: float, green: float, blue: float) -> tuple[float, float, float]:
    """Convert sRGB to OKLab for perceptual colour-distance comparisons."""
    def linear(channel: float) -> float:
        return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4

    red, green, blue = linear(red), linear(green), linear(blue)
    light = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
    medium = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
    short = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
    light, medium, short = light ** (1 / 3), medium ** (1 / 3), short ** (1 / 3)
    return (
        0.2104542553 * light + 0.7936177850 * medium - 0.0040720468 * short,
        1.9779984951 * light - 2.4285922050 * medium + 0.4505937099 * short,
        0.0259040371 * light + 0.7827717662 * medium - 0.8086757660 * short,
    )


def perceptual_distance(first: tuple[float, float, float], second: tuple[float, float, float]) -> float:
    return math.sqrt(sum((left - right) ** 2 for left, right in zip(oklab(*first), oklab(*second))))


def parse_rgb(value: str) -> tuple[float, float, float]:
    match = re.fullmatch(r"#?([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})(?:[0-9A-Fa-f]{2})?", value)
    if not match:
        raise ValueError(f"unexpected ImageMagick colour: {value!r}")
    return tuple(int(component, 16) / 255.0 for component in match.groups())


def scene_samples(image_data: bytes) -> tuple[
    float,
    tuple[float, float, float],
    list[tuple[float, float, float]],
]:
    # Mean whole-image lightness drives the required light-on-dark or
    # dark-on-light polarity. Workspace labels occupy roughly the top-left
    # fifth of the display and one menu-bar height, so sample that complete
    # region rather than averaging the full screen width or a deep top strip.
    output = run_magick(
        image_data,
        "-resize", "180x180>",
        "-colorspace", "sRGB",
        "-format", "%[fx:mean] %[hex:p{0,0}]",
        "info:",
    )
    mean_text, _ = output.split(maxsplit=1)
    region_text = run_magick(
        image_data,
        "-gravity", "northwest",
        "-crop", "20%x2.5%+0+0", "+repage",
        # Horizontal samples model every possible workspace-label position;
        # three rows retain local texture across the bar's full height.
        "-scale", "20x3!",
        "-depth", "8",
        "txt:-",
    )
    region_pixels = [parse_rgb(value) for value in re.findall(r"#[0-9A-Fa-f]{6,8}", region_text)]
    if not region_pixels:
        raise ValueError("could not sample the workspace backdrop")
    overlay_alpha = 0x35 / 255.0
    backdrops = [
        tuple(channel * (1.0 - overlay_alpha) for channel in pixel)
        for pixel in region_pixels
    ]
    bar_rgb = tuple(sum(pixel[channel] for pixel in backdrops) / len(backdrops) for channel in range(3))
    return float(mean_text), bar_rgb, backdrops


def regional_separation(
    colour: tuple[float, float, float],
    backdrops: list[tuple[float, float, float]],
) -> float:
    """Return conservative readability across the full workspace region.

    The low-percentile score makes a candidate work at workspaces 0–4 instead
    of only against the region's average. A small percentile, rather than the
    single worst pixel, prevents one photographic highlight from dictating the
    entire palette.
    """
    luminance = relative_luminance(*colour)
    values = sorted(
        perceptual_distance(colour, backdrop) * 2.4
        + max(0.0, contrast_ratio(luminance, relative_luminance(*backdrop)) - 1.0) * 0.16
        for backdrop in backdrops
    )
    return values[max(0, math.floor((len(values) - 1) * 0.10))]


def histogram(
    image_data: bytes,
    exclude_top: bool = False,
    preserve_details: bool = False,
) -> list[Swatch]:
    crop = ["-gravity", "south", "-crop", "100%x88%+0+0", "+repage"] if exclude_top else []
    sampling = ["-sample", "660x660>"] if preserve_details else ["-resize", "220x220>"]
    colour_count = "512" if preserve_details else "192"
    output = run_magick(
        image_data,
        *crop,
        *sampling,
        "-colors", colour_count,
        "-depth", "8",
        "-format", "%c",
        "histogram:info:-",
    )
    pattern = re.compile(
        r"^\s*(\d+):\s*\([^)]*\)\s*#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})",
        re.MULTILINE,
    )
    raw = [(int(count), int(red, 16), int(green, 16), int(blue, 16))
           for count, red, green, blue in pattern.findall(output)]
    total = sum(count for count, *_ in raw)
    if not total:
        return []

    result: list[Swatch] = []
    for count, red_8, green_8, blue_8 in raw:
        red, green, blue = (red_8 / 255.0, green_8 / 255.0, blue_8 / 255.0)
        hue, saturation, value = colorsys.rgb_to_hsv(red, green, blue)
        result.append(Swatch(
            fraction=count / total,
            red=red,
            green=green,
            blue=blue,
            hue=hue,
            saturation=saturation,
            value=value,
            luminance=relative_luminance(red, green, blue),
        ))
    return result


def light_variant(swatch: Swatch) -> tuple[float, float, float]:
    # This is the maximum permitted correction, not the default rendering.
    # Keep the source hue and bound saturation/value changes so an accent
    # remains recognisably sampled from the wallpaper.
    if swatch.saturation < 0.25:
        saturation = min(swatch.saturation + 0.10, swatch.saturation * 1.30 + 0.02)
    else:
        saturation = min(0.94, swatch.saturation + 0.16, swatch.saturation * 1.22)
    minimum_value = 0.62 if swatch.saturation >= 0.30 else 0.50
    value = min(0.97, max(minimum_value, swatch.value * 1.15, swatch.value + 0.16))
    return colorsys.hsv_to_rgb(swatch.hue, saturation, value)


def hue_distance(first: float, second: float) -> float:
    difference = abs(first - second)
    return min(difference, 1.0 - difference)


def colour_families(swatches: list[Swatch]) -> list[Swatch]:
    """Merge nearby hues so coherent regions beat isolated quantized pixels."""
    colourful = [swatch for swatch in swatches if swatch.saturation >= 0.12 and swatch.value >= 0.15]
    families: list[Swatch] = []
    for seed in colourful:
        members = [swatch for swatch in colourful if hue_distance(seed.hue, swatch.hue) <= 12 / 360]
        if not members:
            continue
        # Chroma-weighted circular averaging keeps muted background neutrals
        # from pulling a real accent toward beige or gray.
        weights = [member.fraction * member.saturation ** 1.35 * (0.35 + 0.65 * member.value)
                   for member in members]
        total_weight = sum(weights)
        if total_weight <= 0:
            continue
        sine = sum(weight * math.sin(member.hue * math.tau) for member, weight in zip(members, weights))
        cosine = sum(weight * math.cos(member.hue * math.tau) for member, weight in zip(members, weights))
        hue = (math.atan2(sine, cosine) / math.tau) % 1.0
        family_fraction = sum(member.fraction for member in members)
        # The family area establishes that the hue is real and coherent, but
        # its average is often muddy because it includes shadows and edge
        # pixels. Render from a well-supported vivid member of the same family
        # so the accent represents colour that is actually visible.
        minimum_core_area = family_fraction * 0.0005
        core_members = [member for member in members if member.fraction >= minimum_core_area] or members
        core = max(
            core_members,
            key=lambda member: (
                member.saturation ** 1.35
                * member.value
                * min(member.fraction, 0.003) ** 0.08
            ),
        )
        saturation = core.saturation
        value = core.value
        red, green, blue = colorsys.hsv_to_rgb(hue, saturation, value)
        families.append(Swatch(
            fraction=family_fraction,
            red=red,
            green=green,
            blue=blue,
            hue=hue,
            saturation=saturation,
            value=value,
            luminance=relative_luminance(red, green, blue),
        ))
    return families


def select_detail_focal(
    swatches: list[Swatch],
    bar_rgb: tuple[float, float, float],
) -> Swatch | None:
    """Recover a compact vivid detail without averaging away its colour.

    The normal histogram deliberately smooths the image so large regions are
    stable. On an otherwise neutral image that can dilute a tiny focal object.
    This pass uses nearest-neighbour sampling, requires a coherent hue family
    across multiple sampled pixels, then represents that family by its vivid
    core rather than its pale anti-aliased boundary.
    """
    vivid = [swatch for swatch in swatches if swatch.saturation >= 0.50 and swatch.value >= 0.45]
    candidates: list[tuple[float, Swatch]] = []
    bar_luminance = relative_luminance(*bar_rgb)
    for seed in vivid:
        members = [swatch for swatch in vivid if hue_distance(seed.hue, swatch.hue) <= 18 / 360]
        area = sum(member.fraction for member in members)
        if not 0.00008 <= area <= 0.020:
            continue
        core = max(members, key=lambda member: member.saturation ** 1.5 * member.value)
        preview = light_variant(core)
        distance = perceptual_distance(preview, bar_rgb)
        contrast = contrast_ratio(relative_luminance(*preview), bar_luminance)
        separation = distance * 2.4 + max(0.0, contrast - 1.0) * 0.16
        if separation < 0.30:
            continue
        representative = Swatch(
            fraction=area,
            red=core.red,
            green=core.green,
            blue=core.blue,
            hue=core.hue,
            saturation=core.saturation,
            value=core.value,
            luminance=core.luminance,
        )
        score = core.saturation ** 2.0 * core.value * area ** 0.12 * separation
        candidates.append((score, representative))
    return max(candidates, key=lambda item: item[0])[1] if candidates else None


def select_swatch(
    swatches: list[Swatch],
    bar_rgb: tuple[float, float, float],
    bar_backdrops: list[tuple[float, float, float]],
    detail_swatches: list[Swatch] | None = None,
    scene_mean: float | None = None,
) -> Swatch | None:
    bar_luminance = relative_luminance(*bar_rgb)
    vivid = [swatch for swatch in swatches if swatch.saturation >= 0.22 and swatch.value >= 0.16]
    if not vivid:
        return None

    def preview_separation(swatch: Swatch) -> float:
        preview = light_variant(swatch)
        return regional_separation(preview, bar_backdrops)

    def source_separation(swatch: Swatch) -> float:
        source = (swatch.red, swatch.green, swatch.blue)
        return regional_separation(source, bar_backdrops)

    families = colour_families(swatches)
    if not families:
        families = vivid
    dominant = max(families, key=lambda swatch: swatch.fraction)
    bar_lightness = oklab(*bar_rgb)[0]
    bar_hue, bar_saturation, _ = colorsys.rgb_to_hsv(*bar_rgb)

    def score(swatch: Swatch) -> float:
        # Families receive credit for meaningful image area and for already
        # being bright/colourful in the source. A coherent colour distinct from
        # the dominant background receives a strong salience bonus: this is
        # what lets lightning, stars, foliage, and light trails beat a large
        # field of blue/gray without hard-coding any preferred hue.
        novelty = hue_distance(swatch.hue, dominant.hue) * 2.0
        source_contrast = min(
            contrast_ratio(swatch.luminance, relative_luminance(*backdrop))
            for backdrop in bar_backdrops
        )
        source_distance = min(
            perceptual_distance((swatch.red, swatch.green, swatch.blue), backdrop)
            for backdrop in bar_backdrops
        )
        bar_hue_distance = hue_distance(swatch.hue, bar_hue) * 2.0
        local_hue_factor = 1.0
        if bar_saturation >= 0.08 and source_distance < 0.16 and source_contrast < 1.8:
            # A blue on a blue-gray bar (or analogous same-hue pairing) can
            # technically differ yet remain visually lost. Reward a real
            # candidate from elsewhere in the image when luminance alone does
            # not provide a decisive boundary.
            local_hue_factor = 0.55 + 0.90 * bar_hue_distance
        # A light bar benefits from a genuinely darker source colour. Elsewhere
        # brightness remains useful because the bar itself is dark.
        if bar_lightness >= 0.60:
            saturation_power, value_power = 1.50, 1.00
            polarity_bonus = source_contrast ** 2.5
        else:
            saturation_power, value_power = 1.80, 1.50
            polarity_bonus = 1.0
        return (
            min(swatch.fraction, 0.06) ** 0.80
            * swatch.saturation ** saturation_power
            * swatch.value ** value_power
            # Separation is a gate, not a contest to be maximized forever.
            # Once a family clearly pops on the bar, stronger contrast should
            # not let a small garish region beat a better-supported accent.
            * min(preview_separation(swatch), 1.0) ** 1.10
            * (1.0 + 0.25 * novelty)
            * local_hue_factor
            * polarity_bonus
        )

    selection_pool = families
    if bar_lightness >= 0.60:
        # On a light bar, do not let a tiny dark object win solely through
        # contrast; require the darker family to occupy a real image region.
        supported = [family for family in families if family.fraction >= 0.030]
        if supported:
            selection_pool = supported
    selected = max(selection_pool, key=score)
    detail_families = colour_families(detail_swatches or [])

    # In a generally dark composition, a compact bright colour that differs
    # from the background is normally the visual subject (lightning, stars,
    # light trails, a sunset edge). Validate it as a multi-pixel hue family,
    # then let local salience override sheer background area.
    if scene_mean is None:
        scene_mean = sum(swatch.fraction * swatch.value for swatch in swatches)
    if scene_mean < 0.55:
        focal = [
            family for family in detail_families
            if 0.00008 <= family.fraction <= 0.040
            and family.value >= 0.65
            and family.saturation >= 0.12
            and hue_distance(family.hue, dominant.hue) * 2.0 >= 0.15
        ]
        if focal:
            def focal_score(family: Swatch) -> float:
                novelty = hue_distance(family.hue, dominant.hue) * 2.0
                return (
                    family.value ** 2.0
                    # A compact, highly chromatic subject should beat a much
                    # larger set of scattered warm lights. Hue novelty still
                    # matters, but it must not outweigh focal saturation.
                    * family.saturation ** 2.2
                    * novelty ** 0.75
                    * min(family.fraction, 0.010) ** 0.08
                    * min(preview_separation(family), 1.0)
                )
            best_focal = max(focal, key=focal_score)
            # A compact region overrides the main candidate only when it is a
            # genuinely different accent (eyes, lightning, light trails) or a
            # materially brighter expression of that hue. A smaller, darker
            # swatch from the same family is not more salient.
            hue_change = hue_distance(best_focal.hue, selected.hue) * 360
            materially_brighter = best_focal.value >= selected.value + 0.10
            focal_is_readable = source_separation(best_focal) >= 0.42
            focal_is_vivid = best_focal.saturation * best_focal.value >= 0.30
            if (hue_change >= 8.0 or materially_brighter) and focal_is_readable and focal_is_vivid:
                # The focal pass chooses a hue family, not the final pixel.
                # Continue into refinement so a supported bright core can beat
                # an oversaturated edge from that same subject.
                selected = best_focal

    # Use the detailed pass to recover the vivid interior of the selected
    # region, but only within the already-selected hue family.
    refinements = [
        family for family in detail_families
        if family.fraction >= 0.001
        and hue_distance(family.hue, selected.hue) <= 8 / 360
    ]
    if refinements:
        if bar_lightness >= 0.60:
            # Keep the chosen hue, but on a light/translucent bar prefer a
            # naturally darker member of that same image family.  This avoids
            # taking a perfectly good orange/brown, selecting its pale edge,
            # and then trying to manufacture contrast by further editing it.
            # Real objects can span a modest warm/cool gradient (for example,
            # sunlit tan rock into burnt-orange shadow), so this darker search
            # gets a slightly wider hue window than ordinary refinement.
            darker_readable = [
                family for family in detail_families
                if family.fraction >= 0.001
                and hue_distance(family.hue, selected.hue) <= 16 / 360
                if oklab(family.red, family.green, family.blue)[0] <= bar_lightness - 0.08
                # Do not solve contrast by choosing a near-shadow swatch; it
                # reads as mud at workspace-label size even when its contrast
                # ratio is high.
                and family.value >= 0.45
                and source_separation(family) >= 0.42
            ]
            if darker_readable:
                selected = max(
                    darker_readable,
                    key=lambda family: (
                        min(family.fraction, 0.03) ** 0.15
                        * family.saturation
                        * contrast_ratio(family.luminance, bar_luminance)
                    ),
                )
            else:
                selected = max(refinements, key=lambda family: family.saturation * family.value)
        else:
            # On a dark bar, prefer the supported sunlit core of the chosen
            # family instead of its most saturated edge. Tiny labels read
            # brightness more strongly than chroma, and the brighter core is
            # often the colour a person identifies in foliage, water, or sky.
            bright_cores = [
                swatch for swatch in (detail_swatches or [])
                if swatch.fraction >= 0.00030
                and hue_distance(swatch.hue, selected.hue) <= 12 / 360
                and swatch.saturation >= 0.30
                and swatch.value <= 0.98
                and source_separation(swatch) >= 0.46
            ] or refinements
            selected = max(
                bright_cores,
                key=lambda family: (
                    family.saturation ** 0.45
                    * family.value ** 2.2
                    * min(family.fraction, 0.005) ** 0.12
                ),
            )
    return selected


def tune(
    swatch: Swatch,
    bar_rgb: tuple[float, float, float],
    bar_backdrops: list[tuple[float, float, float]],
) -> str:
    source = (swatch.red, swatch.green, swatch.blue)
    source_separation = regional_separation(source, bar_backdrops)
    # A naturally readable source colour is emitted unchanged. Only colours
    # below the readability target receive the bounded correction above.
    red, green, blue = source if source_separation >= 0.46 else light_variant(swatch)
    _, saturation, _ = colorsys.rgb_to_hsv(red, green, blue)
    bar_lightness = oklab(*bar_rgb)[0]
    accent_lightness = oklab(red, green, blue)[0]

    # A vivid hue can still look muddy when its tone sits only slightly above
    # the translucent bar. If the bright form is already on the light side of
    # the bar, preserve that polarity and give it a clear perceptual-lightness
    # margin. Mixing toward white keeps the selected hue, and the saturation
    # floor prevents the correction from washing a real accent into a pastel.
    # Candidates on the dark side are left alone: crossing through the bar's
    # tone would reduce contrast (notably for blue on a light gray bar).
    minimum_light_margin = 0.11
    if saturation < 0.72 and 0.0 < accent_lightness - bar_lightness < minimum_light_margin:
        original = (red, green, blue)
        for white_mix_percent in range(1, 11):
            white_mix = white_mix_percent / 100.0
            trial = tuple(channel + (1.0 - channel) * white_mix for channel in original)
            trial_saturation = colorsys.rgb_to_hsv(*trial)[1]
            if trial_saturation < 0.50:
                break
            red, green, blue = trial
            if oklab(*trial)[0] - bar_lightness >= minimum_light_margin:
                break

    # Keep a light accent visibly distinct from SketchyBar's white labels and
    # icons. This is deliberately a soft guard: it activates only when a colour
    # is both extremely light and weakly chromatic, then preserves its hue while
    # lowering HSV value modestly. Light pinks, golds, and other colourful
    # highlights below this near-white corner are left unchanged.
    accent_lab = oklab(red, green, blue)
    accent_chroma = math.hypot(accent_lab[1], accent_lab[2])
    if accent_lab[0] > 0.85 and accent_chroma < 0.10:
        hue, saturation, value = colorsys.rgb_to_hsv(red, green, blue)
        saturation = max(saturation, 0.18)
        value = min(value, 0.92)
        red, green, blue = colorsys.hsv_to_rgb(hue, saturation, value)

    # Small focused labels need to look coloured, not merely off-white.  A
    # bright source may be genuinely present in the image yet still compete
    # with SketchyBar's white occupied-workspace labels. Preserve its hue and
    # luminance direction, but prefer extra chroma over a pastel/white result.
    accent_lightness = oklab(red, green, blue)[0]
    hue, saturation, value = colorsys.rgb_to_hsv(red, green, blue)
    if accent_lightness >= 0.73 and saturation < 0.58:
        saturation = min(0.62, max(0.58, saturation + 0.12))
        red, green, blue = colorsys.hsv_to_rgb(hue, saturation, value)

    return "#{:02X}{:02X}{:02X}".format(round(red * 255), round(green * 255), round(blue * 255))


def neutral_accent(
    swatches: list[Swatch],
    bar_rgb: tuple[float, float, float],
    bar_backdrops: list[tuple[float, float, float]],
) -> str:
    """Choose a supported neutral from a monochrome image, opposite the bar tone.

    A coloured fallback invents a hue that is absent from the wallpaper and can
    still blend into the translucent bar.  For genuinely achromatic images,
    retain an actual gray family and let luminance contrast do the work.
    """
    bar_luminance = relative_luminance(*bar_rgb)
    bar_lightness = oklab(*bar_rgb)[0]
    neutrals = [
        swatch for swatch in swatches
        # Thin architectural edges and shadows can be the only dark tones in
        # a high-key monochrome image, so retain coherent quantized entries
        # down to roughly two pixels in the coarse sample.
        if swatch.saturation <= 0.18 and swatch.fraction >= 0.00002
    ]
    if not neutrals:
        return "#242424" if bar_lightness >= 0.60 else "#D0D0D0"

    if bar_lightness >= 0.60:
        opposite = [swatch for swatch in neutrals if swatch.value <= 0.45]
    else:
        # Prefer a light gray rather than a white-looking workspace label.
        opposite = [swatch for swatch in neutrals if 0.62 <= swatch.value <= 0.92]
    pool = opposite or neutrals

    def score(swatch: Swatch) -> float:
        support = min(swatch.fraction, 0.10) ** 0.28
        contrast = min(
            contrast_ratio(swatch.luminance, relative_luminance(*backdrop))
            for backdrop in bar_backdrops
        )
        chroma_penalty = 1.0 - min(swatch.saturation, 0.18)
        return contrast ** 1.8 * support * chroma_penalty

    selected = max(pool, key=score)
    red, green, blue = selected.red, selected.green, selected.blue
    if bar_lightness >= 0.60 and selected.value > 0.34:
        # Keep the source neutral but deepen it modestly so it cannot resemble
        # the translucent inactive labels on a light gray bar.
        scale = 0.34 / selected.value
        red, green, blue = red * scale, green * scale, blue * scale
    elif bar_lightness < 0.60 and selected.value > 0.72:
        # Avoid a focused neutral becoming indistinguishable from occupied
        # white labels on a dark bar.
        scale = 0.72 / selected.value
        red, green, blue = red * scale, green * scale, blue * scale
    return "#{:02X}{:02X}{:02X}".format(
        round(red * 255),
        round(green * 255),
        round(blue * 255),
    )


def accent(image_data: bytes) -> str:
    scene_mean, bar_rgb, bar_backdrops = scene_samples(image_data)
    # Candidate colours come from below the bar. This makes a colour family
    # that lives elsewhere in the composition more valuable than one already
    # occupying the bar's backdrop.
    coarse_swatches = histogram(image_data, exclude_top=True)
    detail_swatches = histogram(image_data, exclude_top=True, preserve_details=True)
    swatch = select_swatch(coarse_swatches, bar_rgb, bar_backdrops, detail_swatches, scene_mean)
    if swatch is None:
        return neutral_accent(coarse_swatches, bar_rgb, bar_backdrops)
    return tune(swatch, bar_rgb, bar_backdrops)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} IMAGE_OR_DASH", file=sys.stderr)
        return 2
    try:
        image_data = sys.stdin.buffer.read() if sys.argv[1] == "-" else Path(sys.argv[1]).read_bytes()
        if not image_data:
            raise ValueError("image input is empty")
        print(accent(prepare_image(image_data)))
        return 0
    except subprocess.TimeoutExpired as error:
        print(f"accent extraction timed out in ImageMagick ({error.timeout}s); try a smaller wallpaper image", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        details = (error.stderr or b"").decode("utf-8", errors="replace").strip()
        print(f"ImageMagick stage failed (exit {error.returncode}): {details[:800] or error.cmd}", file=sys.stderr)
        return 1
    except (OSError, ValueError) as error:
        print(f"accent extraction failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
