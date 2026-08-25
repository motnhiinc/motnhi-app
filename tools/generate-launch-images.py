#!/usr/bin/env python3
"""Write the launch-screen mascot bitmaps for iOS and Android.

No package manages these — flutter_launcher_icons only touches app icons — so
they are generated here from the same assets/icon/app_icon.svg.

The mascot is emitted with a transparent background and sits on a theme-aware
colour supplied by each platform (LaunchBackground.colorset on iOS,
@color/launch_background on Android). Those colours are the *app's* background
(#FFF8F5 / #27223E from lib/core/theme/app_theme.dart), not the icon's cream —
matching the app means the launch screen hands off to the first frame without a
visible colour jump.

macOS only: it reuses the qlmanage-based renderer in generate-icon-layers.py.
Run from the repo root:

    python3 tools/generate-launch-images.py
"""
from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent

spec = importlib.util.spec_from_file_location("icon_layers", Path(__file__).with_name("generate-icon-layers.py"))
icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons)

LOGO_POINTS = 180  # mascot height in pt (iOS) / dp (Android)

IOS_SET = ROOT / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"

IOS_SCALES = {"LaunchImage.png": 1, "LaunchImage@2x.png": 2, "LaunchImage@3x.png": 3}
ANDROID_SCALES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def mascot() -> Image.Image:
    """The artwork at its native scale, transparent, cropped to its own bounds."""
    svg = icons.SOURCE_SVG.read_text().replace(
        f'<rect width="{icons.CANVAS}" height="{icons.CANVAS}" fill="#FFF3DF"/>', ""
    )
    with tempfile.TemporaryDirectory() as tmp:
        art = icons.render(svg, Path(tmp), "launch")
    alpha = np.asarray(art.split()[3])
    ys, xs = np.nonzero(alpha > 8)
    if not len(xs):
        sys.exit("launch: rendered artwork is empty")
    return art.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def scaled(art: Image.Image, factor: float) -> Image.Image:
    height = round(LOGO_POINTS * factor)
    width = max(1, round(art.width * height / art.height))
    return art.resize((width, height), Image.LANCZOS)


def main() -> None:
    art = mascot()
    base = scaled(art, 1.0)
    print(f"mascot cropped to {art.width}x{art.height}; intrinsic size {base.width}x{base.height} pt")

    if not IOS_SET.is_dir():
        sys.exit(f"missing {IOS_SET}")
    for name, factor in IOS_SCALES.items():
        image = scaled(art, factor)
        image.save(IOS_SET / name)
        print(f"  ios  {name:22} {image.width}x{image.height}")

    for bucket, factor in ANDROID_SCALES.items():
        target = ANDROID_RES / f"drawable-{bucket}"
        target.mkdir(parents=True, exist_ok=True)
        image = scaled(art, factor)
        image.save(target / "launch_image.png")
        print(f"  android drawable-{bucket:<8} {image.width}x{image.height}")

    print(
        f"\nLaunchScreen.storyboard must declare the intrinsic size: "
        f'<image name="LaunchImage" width="{base.width}" height="{base.height}"/>'
    )


if __name__ == "__main__":
    main()
