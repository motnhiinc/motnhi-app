#!/usr/bin/env python3
"""Derive the launcher-icon layers from assets/icon/app_icon.svg.

Writes three PNGs that `flutter_launcher_icons` consumes:

  app_icon.png              full-bleed 1024, no alpha  (iOS + macOS + Android legacy)
  app_icon_foreground.png   transparent, artwork pulled into the adaptive safe zone
  app_icon_monochrome.png   transparent silhouette for Android 13 themed icons

Two things are worth knowing before editing this file.

**Safe zone.** An adaptive icon is 108dp but only the centre 72dp is guaranteed
visible, so the foreground has to sit inside a circle of radius 341 on a 1024
canvas. The source art is drawn at scale 0.82, which puts the bottom corners of
the book at radius ~496 — they get sliced off by any circular mask. FOREGROUND_SCALE
is the largest scale that keeps every corner inside; the assertion below re-checks
it rather than trusting the constant.

**Rasteriser.** There is no librsvg/Inkscape here and ImageMagick has no SVG
delegate, so this shells out to macOS `qlmanage`, which renders SVG through
WebKit (verified at RMSE 0.0006 against the artist's own export). qlmanage
flattens onto opaque white and cannot be told otherwise, so transparency is
recovered exactly by rendering each layer twice — once over white, once over
black — and solving W = aC + (1-a)·255, B = aC for a and C. That is exact for
antialiased edges too, which a fuzz-based background removal is not.

macOS only, because of qlmanage. Run from the repo root:

    python3 tools/generate-icon-layers.py
"""
from __future__ import annotations

import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "assets" / "icon"
SOURCE_SVG = ICON_DIR / "app_icon.svg"

CANVAS = 1024
SOURCE_SCALE = 0.82       # the scale the artwork ships at, full-bleed
FOREGROUND_SCALE = 0.95   # see TOOL_INSET — this is pre-inset, not the final size
SAFE_RADIUS = CANVAS * (72 / 108) / 2

# flutter_launcher_icons wraps both adaptive layers in <inset android:inset="16%">,
# so whatever this script emits is shrunk to 68% of the layer before Android ever
# masks it. That inset is regenerated on every run, so hand-editing the XML back
# out does not survive — the scale is compensated here instead. Net effect at
# FOREGROUND_SCALE 0.95: the art fills ~72% of the visible circle, and its
# corners land inside the safe radius with a little room to spare.
TOOL_INSET = 0.16
EFFECTIVE = 1.0 - 2 * TOOL_INSET

BOOK = (
    "M 512 720 C 430 668, 320 652, 205 682 C 188 686, 179 700, 183 716 "
    "L 222 850 C 226 866, 241 874, 257 869 C 350 845, 445 850, 512 878 Z"
)
MIRROR = "translate(1024,0) scale(-1,1)"


def render(svg_text: str, work: Path, stem: str) -> Image.Image:
    """Rasterise `svg_text` to RGBA, recovering alpha qlmanage won't preserve."""
    out = {}
    for tag, ground in (("w", None), ("b", "#000000")):
        body = svg_text
        if ground:
            body = body.replace("<defs>", f'<rect width="{CANVAS}" height="{CANVAS}" fill="{ground}"/><defs>', 1)
            if ground not in body:  # no <defs> in this layer
                body = body.replace(">", f'><rect width="{CANVAS}" height="{CANVAS}" fill="{ground}"/>', 1)
        path = work / f"{stem}_{tag}.svg"
        path.write_text(body)
        subprocess.run(
            ["qlmanage", "-t", "-s", str(CANVAS), "-o", str(work), str(path)],
            check=True, capture_output=True,
        )
        rendered = work / f"{path.name}.png"
        if not rendered.exists():
            sys.exit(f"qlmanage produced no output for {path.name}")
        out[tag] = np.asarray(Image.open(rendered).convert("RGB"), dtype=np.float64)

    white, black = out["w"], out["b"]
    alpha = np.clip(1.0 - np.clip((white - black).mean(axis=2), 0, 255) / 255.0, 0.0, 1.0)
    divisor = np.where(alpha > 1e-4, alpha, 1.0)[..., None]
    colour = np.where(alpha[..., None] > 1e-4, np.clip(black / divisor, 0, 255), 0)
    return Image.fromarray(np.dstack([colour, alpha * 255.0]).round().astype(np.uint8), "RGBA")


def foreground_svg() -> str:
    src = SOURCE_SVG.read_text()
    # Drop the cream ground — the background is a colour resource, not pixels.
    src = src.replace(f'<rect width="{CANVAS}" height="{CANVAS}" fill="#FFF3DF"/>', "")
    return src.replace(
        f"translate(512,512) scale({SOURCE_SCALE}) translate(-512,-512)",
        f"translate(512,512) scale({FOREGROUND_SCALE}) translate(-512,-512)",
    )


def monochrome_svg() -> str:
    """A single-colour silhouette that still reads as a bespectacled reader.

    Android tints this layer's alpha channel flat, so anything that relies on
    fill colour to separate — frames against head, pages against cover —
    disappears. The mask punches those separations back in as holes: a gap
    ringing each frame so the glasses read, and a thin outline along the page
    edge so the book reads as an open book rather than two swooshes.
    """
    frames = "".join(
        f'<circle cx="{cx}" cy="404" r="106" fill="#000"/>'   # gap outside the frame
        f'<circle cx="{cx}" cy="404" r="93"  fill="#fff"/>'   # frame itself stays solid
        f'<circle cx="{cx}" cy="404" r="71"  fill="#000"/>'   # lens interior
        for cx in (420, 604)
    )
    page_edge = (
        f'<path d="{BOOK}" fill="none" stroke="#000" stroke-width="18" '
        f'transform="translate(512,878) scale(0.85) translate(-512,-878)"/>'
    )
    mask = f"""
      <rect width="{CANVAS}" height="{CANVAS}" fill="#fff"/>
      {frames}
      <circle cx="432" cy="412" r="42" fill="#fff"/><circle cx="592" cy="412" r="42" fill="#fff"/>
      <circle cx="418" cy="398" r="15" fill="#000"/><circle cx="578" cy="398" r="15" fill="#000"/>
      <path d="M 476 516 Q 512 566 548 516 Z" fill="#000"/>
      {page_edge}<g transform="{MIRROR}">{page_edge}</g>
      <circle cx="512" cy="866" r="30" fill="#fff"/>"""
    art = f"""
      <rect x="428" y="500" width="168" height="270" rx="84"/>
      <path d="{BOOK}"/><g transform="{MIRROR}"><path d="{BOOK}"/></g>
      <path d="M 452 244 C 430 190, 412 168, 392 150" stroke="#000" stroke-width="26" fill="none" stroke-linecap="round"/>
      <path d="M 574 244 C 596 192, 616 170, 638 154" stroke="#000" stroke-width="26" fill="none" stroke-linecap="round"/>
      <circle cx="386" cy="140" r="27"/><circle cx="644" cy="146" r="27"/>
      <circle cx="512" cy="398" r="228"/>
      <circle cx="420" cy="404" r="82" fill="none" stroke="#000" stroke-width="22"/>
      <circle cx="604" cy="404" r="82" fill="none" stroke="#000" stroke-width="22"/>
      <path d="M 338 396 L 300 380" stroke="#000" stroke-width="20" stroke-linecap="round"/>
      <path d="M 686 396 L 724 380" stroke="#000" stroke-width="20" stroke-linecap="round"/>
      <path d="M 772,188 C 783.16,232.64 789.36,238.84 834,250 C 789.36,261.16 783.16,267.36 772,312
               C 760.84,267.36 754.64,261.16 710,250 C 754.64,238.84 760.84,232.64 772,188 Z"/>"""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" '
        f'width="{CANVAS}" height="{CANVAS}">'
        f'<defs><mask id="h">{mask}</mask></defs>'
        f'<g transform="translate(512,512) scale({FOREGROUND_SCALE}) translate(-512,-512)">'
        f'<g mask="url(#h)" fill="#000">{art}</g></g></svg>'
    )


def assert_inside_safe_zone(image: Image.Image, label: str) -> None:
    alpha = np.asarray(image.split()[3])
    ys, xs = np.nonzero(alpha > 8)
    if not len(xs):
        sys.exit(f"{label}: layer is empty")
    corners = [(xs.min(), ys.min()), (xs.max(), ys.min()), (xs.min(), ys.max()), (xs.max(), ys.max())]
    # Measure after the inset the tool will apply, not before it.
    worst = max(math.hypot(x - CANVAS / 2, y - CANVAS / 2) for x, y in corners) * EFFECTIVE
    fill = (ys.max() - ys.min()) * EFFECTIVE / (SAFE_RADIUS * 2)
    print(f"  {label}: worst corner {worst:.0f} / safe {SAFE_RADIUS:.0f}, fills {fill:.0%} of visible")
    if worst > SAFE_RADIUS:
        sys.exit(f"{label}: art escapes the adaptive safe zone — lower FOREGROUND_SCALE")


def main() -> None:
    if not shutil.which("qlmanage"):
        sys.exit("qlmanage not found — this script is macOS only")
    if not SOURCE_SVG.exists():
        sys.exit(f"missing {SOURCE_SVG}")

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        print("rendering layers")
        fg = render(foreground_svg(), work, "foreground")
        mono = render(monochrome_svg(), work, "monochrome")

    assert_inside_safe_zone(fg, "foreground")
    assert_inside_safe_zone(mono, "monochrome")

    fg.save(ICON_DIR / "app_icon_foreground.png")
    mono.save(ICON_DIR / "app_icon_monochrome.png")

    # iOS rejects an alpha channel on the marketing icon, so keep this one flat.
    full = Image.open(ICON_DIR / "app_icon.png")
    if full.mode != "RGB":
        full.convert("RGB").save(ICON_DIR / "app_icon.png")
        print("  app_icon.png: flattened to RGB (iOS forbids alpha)")

    print(f"wrote {ICON_DIR.relative_to(ROOT)}/app_icon_foreground.png and app_icon_monochrome.png")


if __name__ == "__main__":
    main()
