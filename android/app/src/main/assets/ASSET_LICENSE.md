# scan_any_page_character.glb

- Source: Quaternius — Ultimate Animated Animal Pack ("Fox")
- Source URL: https://quaternius.com/packs/ultimateanimatedanimals.html
- License: CC0 1.0 Universal (public domain dedication)
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Retrieved: 2026-08-22
- Distribution status: approved for release, store distribution and redistribution.
  CC0 requires no attribution; this file records provenance only.

## Modifications

Repacked from the pack's `glTF/Fox.gltf` into a single-file `.glb`, with the
`Idle` clip moved from index 5 to index 0. No geometry, rig, material or
keyframe data was changed, and all 12 original clips are retained.

The move is required: `CharacterReaderScene` renders with
`ModelNode(autoAnimate = true)`, which plays animation index 0 on loop, and the
pack ships `Attack` at index 0 and `Death` at index 1.

# Cute Doll Variants

- Source: purchased asset package (`model-motnhi-upload.zip`)
- Purchase price: $25
- Purchased by: [team/member/account]
- Purchase date: [fill in]
- License/source URL: [fill in from marketplace receipt]
- Distribution status: pending confirmation for App Store / Play Store redistribution
- Included variants: cute_doll_v01 ... cute_doll_v06

## Modifications

Repacked from the package's `glTF_export_V01/Doll_V01.gltf` …
`glTF_export_V06/Doll_V06.gltf` into six single-file `.glb` files
(`cute_doll_v01.glb` … `cute_doll_v06.glb`) with `@gltf-transform/cli`. Before
conversion the `Idle` clip was moved to animation index 0 in every variant;
each ships 26 clips and none shipped an idle at index 0. The same
`ModelNode(autoAnimate = true)` requirement applies as above. No geometry,
rig, material or keyframe data was changed.
