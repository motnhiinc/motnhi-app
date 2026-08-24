# scan_any_page_character.usdz

- Source: Quaternius — Ultimate Animated Animal Pack ("Fox")
- Source URL: https://quaternius.com/packs/ultimateanimatedanimals.html
- License: CC0 1.0 Universal (public domain dedication)
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Retrieved: 2026-08-22
- Distribution status: approved for TestFlight, App Store and redistribution.
  CC0 requires no attribution; this file records provenance only.

## Modifications

Converted from the pack's `glTF/Fox.gltf` with the macOS system USD tools:
`usdcat` (glTF -> .usdc) then `usdzip` (-> .usdz). `usdchecker --arkit` passes.

Before conversion the `Idle` clip was moved from index 5 to index 0. USD bakes a
single timeline, and the converter takes glTF animation index 0 — the pack ships
`Attack` at index 0 and `Death` at index 1. The resulting timeline is 3.333 s,
matching the `Idle` clip exactly. Android renders the same clip from
`android/app/src/debug/assets/scan_any_page_character.glb`.

This file replaced `toy_drummer.usdz`, an Apple AR Quick Look sample that was
prototype-only and could not be distributed.
