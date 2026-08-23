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
