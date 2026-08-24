#!/usr/bin/env bash
#
# Renders appstore-screenshots.html to App Store-sized PNGs.
#
#   ./tools/export-appstore-shots.sh                 # both languages, all panels
#   ./tools/export-appstore-shots.sh 3               # panel 3, both languages
#   LANGS=vi ./tools/export-appstore-shots.sh        # Vietnamese only
#
# Output: build/appstore/<lang>/screenshot-N.png
# Panels are laid out at 430x932 CSS px and exported at 3x = 1290x2796
# (the 6.7"/6.9" iPhone slot). For 1320x2868, set --pw:440 / --ph:956 in the
# HTML and W=440 / H=956 below.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAGE="$ROOT/appstore-screenshots.html"
OUT="$ROOT/build/appstore"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

W=430
H=932
SCALE=3

[[ -x "$CHROME" ]] || { echo "Chrome not found at: $CHROME (override with CHROME=...)" >&2; exit 1; }
[[ -f "$PAGE" ]]   || { echo "Missing $PAGE" >&2; exit 1; }

PANELS=("$@")
[[ ${#PANELS[@]} -eq 0 ]] && PANELS=(1 2 3 4 5)

read -r -a LANG_LIST <<< "${LANGS:-en vi}"

for lang in "${LANG_LIST[@]}"; do
  mkdir -p "$OUT/$lang"
  for n in "${PANELS[@]}"; do
    "$CHROME" \
      --headless=new \
      --disable-gpu \
      --hide-scrollbars \
      --allow-file-access-from-files \
      --force-device-scale-factor="$SCALE" \
      --window-size="$W,$H" \
      --virtual-time-budget=3000 \
      --screenshot="$OUT/$lang/screenshot-$n.png" \
      "file://$PAGE?panel=$n&lang=$lang" >/dev/null 2>&1
    echo "  $OUT/$lang/screenshot-$n.png"
  done
done

echo
echo "Done. Verify sizes:"
echo "  sips -g pixelWidth -g pixelHeight $OUT/*/*.png"
