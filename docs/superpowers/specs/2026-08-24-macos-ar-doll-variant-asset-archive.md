# macOS AR Doll Variant Asset Preparation + Archive Spec

**Date:** 2026-08-24  
**Audience:** teammate preparing the purchased doll assets on macOS  
**Project:** `app-book` / `storybook_ar`  
**Goal:** convert all six purchased doll variants into app-ready AR assets and package a clean handoff archive for engineering.

---

## 1. Source package

Use the Google Drive file Frank shared:

```text
model-motnhi-upload.zip
```

Expected size:

```text
~39 MB / 40,863,380 bytes
```

The package contains six ready glTF exports:

```text
glTF_export_V01/Doll_V01.gltf
glTF_export_V02/Doll_V02.gltf
glTF_export_V03/Doll_V03.gltf
glTF_export_V04/Doll_V04.gltf
glTF_export_V05/Doll_05.gltf
glTF_export_V06/Doll_V06.gltf
```

Each variant includes:

```text
*.gltf
*.bin
Body_01.png
Eye_01.png
Mouth_01.png
```

Each variant has 26 animations, including:

```text
Idle
HappyIdle
Walking
RunForward
Catwalk
Happy
Reaction
Tpose
```

---

## 2. Required outputs

Prepare these final files:

### Android / ARCore

```text
cute_doll_v01.glb
cute_doll_v02.glb
cute_doll_v03.glb
cute_doll_v04.glb
cute_doll_v05.glb
cute_doll_v06.glb
```

These will go into the app at:

```text
android/app/src/main/assets/
```

### iOS / ARKit

```text
cute_doll_v01.usdz
cute_doll_v02.usdz
cute_doll_v03.usdz
cute_doll_v04.usdz
cute_doll_v05.usdz
cute_doll_v06.usdz
```

These will go into the app at:

```text
ios/Runner/CharacterReader/
```

### Handoff archive

Create one final zip:

```text
cute-doll-ar-variants-app-ready.zip
```

with this structure:

```text
cute-doll-ar-variants-app-ready/
  android/
    cute_doll_v01.glb
    cute_doll_v02.glb
    cute_doll_v03.glb
    cute_doll_v04.glb
    cute_doll_v05.glb
    cute_doll_v06.glb
  ios/
    cute_doll_v01.usdz
    cute_doll_v02.usdz
    cute_doll_v03.usdz
    cute_doll_v04.usdz
    cute_doll_v05.usdz
    cute_doll_v06.usdz
  docs/
    ASSET_PROVENANCE.md
    conversion-notes.md
    checksums-sha256.txt
  previews/
    optional-preview-images-or-screen-recordings
```

---

## 3. License/provenance requirement

Because this was bought for `$25`, include purchase/license proof before handing off.

Create:

```text
docs/ASSET_PROVENANCE.md
```

Template:

```markdown
# Cute Doll AR Variants Provenance

- Asset package: model-motnhi-upload.zip
- Purchase price: $25
- Purchased by: [name/account]
- Purchase date: [date]
- Marketplace/source URL: [URL]
- Receipt/invoice file: [filename or link]
- License terms: [paste or link]
- Redistribution allowed in mobile apps: yes/no/pending
- App Store / Play Store distribution allowed: yes/no/pending
- Notes: [anything important]

## Included variants

- cute_doll_v01
- cute_doll_v02
- cute_doll_v03
- cute_doll_v04
- cute_doll_v05
- cute_doll_v06
```

Do **not** mark this production-ready until redistribution rights are confirmed.

---

## 4. macOS setup

Install required tools:

```bash
brew install node
npm install -g @gltf-transform/cli
```

Install Apple tools:

- Install Xcode from App Store or Apple Developer site.
- Open Xcode once and accept license.
- Install Apple Reality Converter if available from Apple Developer downloads.

Verify:

```bash
node --version
npm --version
gltf-transform --version
xcode-select -p
```

Optional but helpful:

```bash
which usdchecker || true
which usdzip || true
which xcrun || true
```

---

## 5. Working folder setup

```bash
mkdir -p ~/Desktop/cute-doll-ar-work
cd ~/Desktop/cute-doll-ar-work
unzip /path/to/model-motnhi-upload.zip -d source
mkdir -p build/android build/ios docs previews scripts
```

Expected source folders:

```bash
ls source/glTF_export_V01
ls source/glTF_export_V02
ls source/glTF_export_V03
ls source/glTF_export_V04
ls source/glTF_export_V05
ls source/glTF_export_V06
```

---

## 6. Reorder animation so Idle is first

The app currently auto-plays the first animation:

- Android: `ModelNode(autoAnimate = true)` plays animation index `0`.
- iOS: RealityKit plays `availableAnimations.first`.

So each glTF should have `Idle` or `HappyIdle` as animation index `0` before conversion.

Create:

```text
scripts/move_idle_animation_first.py
```

```python
#!/usr/bin/env python3
import json
import sys
from pathlib import Path

if len(sys.argv) != 3:
    print("Usage: move_idle_animation_first.py INPUT.gltf OUTPUT.gltf")
    sys.exit(2)

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
data = json.loads(src.read_text())
animations = data.get("animations", [])

if not animations:
    raise SystemExit(f"No animations found: {src}")

preferred = ["Idle", "HappyIdle"]
index = None
for name in preferred:
    for i, anim in enumerate(animations):
        if anim.get("name") == name:
            index = i
            break
    if index is not None:
        break

if index is None:
    names = [anim.get("name") for anim in animations]
    raise SystemExit(f"No Idle/HappyIdle animation found in {src}. Found: {names}")

animations.insert(0, animations.pop(index))
data["animations"] = animations

dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_text(json.dumps(data, indent=2))
print(f"Wrote {dst}; first animation = {data['animations'][0].get('name')}")
```

Run:

```bash
chmod +x scripts/move_idle_animation_first.py

python3 scripts/move_idle_animation_first.py source/glTF_export_V01/Doll_V01.gltf build/Doll_V01.idle-first.gltf
python3 scripts/move_idle_animation_first.py source/glTF_export_V02/Doll_V02.gltf build/Doll_V02.idle-first.gltf
python3 scripts/move_idle_animation_first.py source/glTF_export_V03/Doll_V03.gltf build/Doll_V03.idle-first.gltf
python3 scripts/move_idle_animation_first.py source/glTF_export_V04/Doll_V04.gltf build/Doll_V04.idle-first.gltf
python3 scripts/move_idle_animation_first.py source/glTF_export_V05/Doll_05.gltf  build/Doll_V05.idle-first.gltf
python3 scripts/move_idle_animation_first.py source/glTF_export_V06/Doll_V06.gltf build/Doll_V06.idle-first.gltf
```

Important: the modified `.gltf` still points to the original `.bin` and texture files. Before converting, copy each modified `.gltf` back into its source folder temporarily or convert from a folder that also contains the `.bin` and images.

Recommended folder preparation:

```bash
mkdir -p build/working_v01 build/working_v02 build/working_v03 build/working_v04 build/working_v05 build/working_v06

cp source/glTF_export_V01/* build/working_v01/
cp build/Doll_V01.idle-first.gltf build/working_v01/Doll_V01.gltf

cp source/glTF_export_V02/* build/working_v02/
cp build/Doll_V02.idle-first.gltf build/working_v02/Doll_V02.gltf

cp source/glTF_export_V03/* build/working_v03/
cp build/Doll_V03.idle-first.gltf build/working_v03/Doll_V03.gltf

cp source/glTF_export_V04/* build/working_v04/
cp build/Doll_V04.idle-first.gltf build/working_v04/Doll_V04.gltf

cp source/glTF_export_V05/* build/working_v05/
cp build/Doll_V05.idle-first.gltf build/working_v05/Doll_05.gltf

cp source/glTF_export_V06/* build/working_v06/
cp build/Doll_V06.idle-first.gltf build/working_v06/Doll_V06.gltf
```

---

## 7. Convert Android GLB files

Use `gltf-transform copy` to package each glTF + `.bin` + textures into one `.glb`.

```bash
gltf-transform copy build/working_v01/Doll_V01.gltf build/android/cute_doll_v01.glb
gltf-transform copy build/working_v02/Doll_V02.gltf build/android/cute_doll_v02.glb
gltf-transform copy build/working_v03/Doll_V03.gltf build/android/cute_doll_v03.glb
gltf-transform copy build/working_v04/Doll_V04.gltf build/android/cute_doll_v04.glb
gltf-transform copy build/working_v05/Doll_05.gltf  build/android/cute_doll_v05.glb
gltf-transform copy build/working_v06/Doll_V06.gltf build/android/cute_doll_v06.glb
```

Inspect each output:

```bash
gltf-transform inspect build/android/cute_doll_v01.glb
gltf-transform inspect build/android/cute_doll_v02.glb
gltf-transform inspect build/android/cute_doll_v03.glb
gltf-transform inspect build/android/cute_doll_v04.glb
gltf-transform inspect build/android/cute_doll_v05.glb
gltf-transform inspect build/android/cute_doll_v06.glb
```

Expected:

- no missing resources
- one skinned doll mesh
- animations present
- first animation is `Idle` or `HappyIdle`

Do **not** aggressively simplify/decimate yet. First hand off faithful versions. Optimization can be a separate pass if app size/performance is a problem.

---

## 8. Convert iOS USDZ files

Preferred path: use Apple Reality Converter on macOS.

For each working folder:

1. Open Reality Converter.
2. Drag in the `.gltf` file from the working folder, e.g.:

```text
build/working_v01/Doll_V01.gltf
```

3. Confirm textures load correctly.
4. Confirm animation preview works, preferably idle loop first.
5. Export as USDZ:

```text
build/ios/cute_doll_v01.usdz
```

Repeat for all six:

```text
build/ios/cute_doll_v01.usdz
build/ios/cute_doll_v02.usdz
build/ios/cute_doll_v03.usdz
build/ios/cute_doll_v04.usdz
build/ios/cute_doll_v05.usdz
build/ios/cute_doll_v06.usdz
```

If command-line USD tools are installed, optionally validate:

```bash
usdchecker --arkit build/ios/cute_doll_v01.usdz || true
usdchecker --arkit build/ios/cute_doll_v02.usdz || true
usdchecker --arkit build/ios/cute_doll_v03.usdz || true
usdchecker --arkit build/ios/cute_doll_v04.usdz || true
usdchecker --arkit build/ios/cute_doll_v05.usdz || true
usdchecker --arkit build/ios/cute_doll_v06.usdz || true
```

If Reality Converter is unavailable, note the exact tool used in `docs/conversion-notes.md` and include any warnings/errors.

---

## 9. Basic file checks

Run:

```bash
ls -lh build/android/*.glb
ls -lh build/ios/*.usdz

file build/android/*.glb
file build/ios/*.usdz
```

Expected:

- `.glb` files start with `glTF` binary header.
- `.usdz` files are zip-like USDZ packages.
- Files are non-empty and not HTML/download-error pages.

Create checksums:

```bash
(
  cd build
  shasum -a 256 android/*.glb ios/*.usdz
) > docs/checksums-sha256.txt
```

---

## 10. Optional local app placement check

If teammate has the `app-book` repo locally, copy files into the repo:

```bash
cp build/android/cute_doll_v*.glb /path/to/app-book/android/app/src/main/assets/
cp build/ios/cute_doll_v*.usdz /path/to/app-book/ios/Runner/CharacterReader/
```

Do not commit yet unless engineering confirms code-side selection is ready.

---

## 11. Device validation checklist

After engineering wires selection UI, validate on real devices:

### Android

- Install debug build on ARCore-supported Android device.
- Open any story.
- Tap AR.
- Select Doll 1.
- Place character on a table.
- Confirm Doll 1 appears and idles.
- Repeat for Doll 2–6.
- Confirm story narration and next/previous page still work.

### iOS

- Install on ARKit-supported iPhone/iPad.
- Open any story.
- Tap AR.
- Select Doll 1.
- Place character on a table.
- Confirm Doll 1 appears and idles.
- Repeat for Doll 2–6.
- Confirm story narration and next/previous page still work.

Record blockers with:

```text
variant:
platform:
device:
OS version:
issue:
screenshot/video:
```

---

## 12. Final archive command

Create handoff folder:

```bash
mkdir -p cute-doll-ar-variants-app-ready/android
mkdir -p cute-doll-ar-variants-app-ready/ios
mkdir -p cute-doll-ar-variants-app-ready/docs
mkdir -p cute-doll-ar-variants-app-ready/previews

cp build/android/cute_doll_v*.glb cute-doll-ar-variants-app-ready/android/
cp build/ios/cute_doll_v*.usdz cute-doll-ar-variants-app-ready/ios/
cp docs/ASSET_PROVENANCE.md cute-doll-ar-variants-app-ready/docs/
cp docs/conversion-notes.md cute-doll-ar-variants-app-ready/docs/ 2>/dev/null || true
cp docs/checksums-sha256.txt cute-doll-ar-variants-app-ready/docs/
```

Zip it:

```bash
zip -r cute-doll-ar-variants-app-ready.zip cute-doll-ar-variants-app-ready
```

Verify zip:

```bash
unzip -l cute-doll-ar-variants-app-ready.zip
```

Send this final file to engineering:

```text
cute-doll-ar-variants-app-ready.zip
```

---

## 13. Handoff notes for engineering

Engineering will wire these filenames:

```text
cute_doll_v01
cute_doll_v02
cute_doll_v03
cute_doll_v04
cute_doll_v05
cute_doll_v06
```

Android app will append `.glb`.  
iOS app will append `.usdz`.

So filenames must match exactly:

```text
cute_doll_v01.glb / cute_doll_v01.usdz
cute_doll_v02.glb / cute_doll_v02.usdz
cute_doll_v03.glb / cute_doll_v03.usdz
cute_doll_v04.glb / cute_doll_v04.usdz
cute_doll_v05.glb / cute_doll_v05.usdz
cute_doll_v06.glb / cute_doll_v06.usdz
```

Do not use spaces, hyphens, uppercase letters, or arbitrary paths.
