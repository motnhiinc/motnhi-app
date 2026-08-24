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

# Cute Doll Variants

- Source: purchased asset package (`model-motnhi-upload.zip`)
- Purchase price: $25
- Purchased by: [team/member/account]
- Purchase date: [fill in]
- License/source URL: [fill in from marketplace receipt]
- Distribution status: pending confirmation for App Store / Play Store redistribution
- Included variants: cute_doll_v01 ... cute_doll_v06

## Modifications

Converted from the package's `glTF_export_V01/Doll_V01.gltf` …
`glTF_export_V06/Doll_V06.gltf` with the macOS system USD tools: `usdcat`
(glTF -> .usdc) then `usdzip --asset` (-> .usdz, packaging the three referenced
PNG textures). `usdchecker --arkit` passes for all six. Unlike the fox glTF,
these variants reference external texture files, so dependency-localizing
`--asset` mode is required for a self-contained package.

As above, before conversion the `Idle` clip was moved to glTF animation index 0
in every variant (26 clips each), so the single baked USD timeline is `Idle`
(≈16.6 s). Output files are `cute_doll_v01.usdz` … `cute_doll_v06.usdz`.
