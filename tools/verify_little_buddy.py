"""Round-trip both static AR exports in Blender; no phone compatibility claim.

Run using the same bpy environment as create_little_buddy.py.
"""
import json
from pathlib import Path
import struct
import zipfile

import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parents[1] / "assets/characters/little_buddy"


def bounds():
    bpy.context.view_layer.update()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    assert meshes, "No meshes imported"
    assert not any(obj.type in ("LIGHT", "CAMERA") for obj in bpy.context.scene.objects)
    corners = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    return [[min(p[i] for p in corners), max(p[i] for p in corners)] for i in range(3)]


raw = (OUT / "little_buddy.glb").read_bytes()
magic, version, length = struct.unpack_from("<4sII", raw)
assert (magic, version, length) == (b"glTF", 2, len(raw))
json_length, chunk_type = struct.unpack_from("<I4s", raw, 12)
assert chunk_type == b"JSON"
gltf = json.loads(raw[20:20 + json_length])
assert not gltf.get("animations"), "This milestone is intentionally static"
assert not gltf.get("images"), "Solid materials should need no external textures"
assert all("uri" not in buffer for buffer in gltf["buffers"]), "GLB must be self-contained"

with zipfile.ZipFile(OUT / "little_buddy.usdz") as archive:
    assert archive.namelist()[0].endswith((".usd", ".usdc", ".usda"))
    assert all(info.compress_type == zipfile.ZIP_STORED for info in archive.infolist())
    for info in archive.infolist():
        with (OUT / "little_buddy.usdz").open("rb") as source:
            source.seek(info.header_offset)
            header = source.read(30)
        filename_length, extra_length = struct.unpack_from("<HH", header, 26)
        assert (info.header_offset + 30 + filename_length + extra_length) % 64 == 0, "USDZ entry not aligned"

round_trips = {}
for extension in ("glb", "usdz"):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    path = str(OUT / f"little_buddy.{extension}")
    if extension == "glb":
        bpy.ops.import_scene.gltf(filepath=path)
    else:
        bpy.ops.wm.usd_import(filepath=path)
    box = bounds()
    assert .19 < box[2][1] - box[2][0] < .22, f"Unexpected meter-scale height: {box}"
    assert abs(box[2][0]) < .001, f"Feet should sit on the origin plane: {box}"
    round_trips[extension] = box

for first, second in zip(round_trips["glb"], round_trips["usdz"]):
    for a, b in zip(first, second):
        assert abs(a - b) < .0001, "GLB / USDZ bounds differ by over 0.1 mm"

result = {"glb_self_contained": True, "usdz_archive_alignment": True,
          "blender_round_trip": round_trips, "matching_bounds": True,
          "phone_tested": False}
(OUT / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
