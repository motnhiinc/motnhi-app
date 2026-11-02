# RealityKit animation resource enumeration

Date: 2026-10-22. Xcode 27.1 (27A9275), macOS 27.0.1 (26A434).
This supplements the static [Phase 1 asset audit](2026-10-22-ar-phase-1.md).

## Reproduce

Compile the read-only tool into a directory outside the repository:

```sh
xcrun swiftc -parse-as-library tools/ar_enumerate_realitykit.swift \
  -o /path/to/ar-enumerate
/path/to/ar-enumerate ios/Runner/CharacterReader/*.usdz \
  > /path/to/realitykit-inventory.json
```

This actually calls `Entity.load`, recursively enumerates animation owners/names,
and obtains durations from paused playback controllers (stopped immediately).
It hashes the input files, never re-exports them, and does not render or certify
any loop. JSON is written to stdout; supply a new destination to retain previous
evidence.

## Observed contract

All seven loaded roots have an **empty entity name**, represented as owner path
`[""]`. Each exposes both `global scene animation` and `default subtree animation`
with the duration below. These are aggregate/alias resources, **not two distinct
authored clips**. Descendant aliases also occur; selecting the first recursive
animation would not be a deliberate clip contract.

| Asset | Duration of each loaded-root resource (seconds) | Recursive resource entries |
|---|---:|---:|
| `cute_doll_v01.usdz` | 16.633333206176758 | 67 |
| `cute_doll_v02.usdz` | 16.633333206176758 | 67 |
| `cute_doll_v03.usdz` | 16.633333206176758 | 67 |
| `cute_doll_v04.usdz` | 16.633333206176758 | 67 |
| `cute_doll_v05.usdz` | 16.633333206176758 | 67 |
| `cute_doll_v06.usdz` | 16.633333206176758 | 67 |
| `scan_any_page_character.usdz` | 3.3333332538604736 | 157 |

Input SHA-256 values:

```text
cute_doll_v01 50978db74a5d21d1be746a1fd57f0e68058454e945e147a96f5a2584c08919cb
cute_doll_v02 b5f7d7edcc544e9691e5214dc408b48d2dbd8f69829a09001700bbc72908dd1c
cute_doll_v03 a5f958809658b17272eb05473e03da36cdabf3f8cb6bee7852ff6ec6795893a0
cute_doll_v04 1b2a0131f39beb57401754214776619332f37c179d863f1b1b9b765f208a98ec
cute_doll_v05 db09aab40bd0e34cf1a8f12a36059c3056f37c3b6a194c86a3ffb497988e6235
cute_doll_v06 1c87772eb3cd7257cc1cf100ad68783443e2b6202d23b8d38e91c7e2a86f100d
scan_any_page_character fd82abb9662d721ed919d7247d8c5f00ae7ca8e85d1f59656458d0a39434644a
```

The iOS implementation agent also enumerated all seven assets using actual
`Entity.load` in an iOS 27.0 simulator and reported matching loaded-root names and
durations. The reader independently requires a unique matching name on the exact
loaded root and a finite expected duration (0.01 s tolerance) before playback;
other import behavior falls back to a stable pose. No clip-order contract is used.

## Interpretation and remaining acceptance

Combined with the static baked SkelAnim/root-channel audit, these observations
allow explicit Idle-like loop selection without inventing USDZ named-clip parity.
Idle and speaking deliberately share this loop; paused/lifecycle/Move states hold
the existing iOS controller rather than restarting it. Android selects exact GLB
`Idle`. Neither format has acquired a dedicated speech clip or facial rig.

**Still unverified:** visual/semantic bone parity, animated foot contact, loop
seams, actual initial facing, phase retention after reparenting, and physical-device
performance. macOS or simulator enumeration does not establish these outcomes or
guarantee identical importer names on every supported iOS version. Runtime
contract validation is the compatibility fallback, not a visual quality test.
