#!/usr/bin/env python3
"""Read-only GLB/USDZ inventory. Requires usd-core; no renderer/device claims.

Run from any directory: python tools/ar_asset_audit.py --output <report.json>
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile

from pxr import Gf, Usd, UsdGeom, UsdSkel

ROOT = Path(__file__).resolve().parents[1]
FORMATS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def json_value(value):
    if isinstance(value, dict):
        return {k: json_value(v) for k, v in value.items()}
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return [json_value(v) for v in value]


def bounds(values):
    values = list(values)
    if not values:
        return None
    return {"min": [min(v[i] for v in values) for i in range(len(values[0]))],
            "max": [max(v[i] for v in values) for i in range(len(values[0]))]}


def motion(values):
    values = list(values)
    return {"range": bounds(values), "end_minus_start": [b - a for a, b in zip(values[0], values[-1])]} if values else None


def png_size(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return list(struct.unpack_from(">II", data, 16))
    return None  # Unknown formats explicitly remain unknown, not guessed.


def joint_root_indices(joints):
    return [i for i, joint in enumerate(joints) if joint.rsplit("/", 1)[0] not in joints
            or "/" not in joint]


def read_glb(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError(f"Invalid GLB header: {path}")
    chunks, offset = {}, 12
    while offset < length:
        size, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        if offset + size > length:
            raise ValueError("Truncated GLB chunk")
        chunks[kind] = data[offset:offset + size]
        offset += size
    return json.loads(chunks[0x4E4F534A]), chunks.get(0x004E4942, b"")


def accessor(doc, blob, index):
    """Decode actual values, including byte strides, sparse overrides, normalization."""
    a = doc["accessors"][index]
    width, fmt = WIDTHS[a["type"]], FORMATS[a["componentType"]]
    item_size = struct.calcsize("<" + fmt * width)

    def unpack(view_index, offset, count, code, components):
        view = doc["bufferViews"][view_index]
        if "EXT_meshopt_compression" in view.get("extensions", {}):
            raise ValueError("Meshopt decoding unavailable")
        if view.get("buffer", 0) != 0:
            raise ValueError("External/multiple buffers not supported")
        layout = "<" + code * components
        step = view.get("byteStride", struct.calcsize(layout))
        start = view.get("byteOffset", 0) + offset
        if offset + (count - 1) * step + struct.calcsize(layout) > view["byteLength"]:
            raise ValueError("Accessor exceeds buffer view")
        return [struct.unpack_from(layout, blob, start + i * step) for i in range(count)]

    values = (unpack(a["bufferView"], a.get("byteOffset", 0), a["count"], fmt, width)
              if "bufferView" in a else [(0,) * width for _ in range(a["count"])])
    if "sparse" in a:
        s = a["sparse"]
        indices = unpack(s["indices"]["bufferView"], s["indices"].get("byteOffset", 0),
                         s["count"], FORMATS[s["indices"]["componentType"]], 1)
        replacements = unpack(s["values"]["bufferView"], s["values"].get("byteOffset", 0), s["count"], fmt, width)
        for (i,), value in zip(indices, replacements):
            values[i] = value
    if a.get("normalized") and a["componentType"] != 5126:
        bits = 8 * (item_size // width)
        signed = fmt.islower()
        divisor = 2 ** (bits - (1 if signed else 0)) - 1
        values = [tuple(max(-1, x / divisor) if signed else x / divisor for x in v) for v in values]
    return values


def node_matrix(node):
    # glTF column-major arrays map directly to Gf row-vector matrix rows.
    if "matrix" in node:
        return Gf.Matrix4d(*node["matrix"])
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    r = Gf.Matrix4d(1).SetRotate(Gf.Quatd(w, Gf.Vec3d(x, y, z)))
    return (Gf.Matrix4d(1).SetScale(Gf.Vec3d(*node.get("scale", [1, 1, 1]))) * r *
            Gf.Matrix4d(1).SetTranslate(Gf.Vec3d(*node.get("translation", [0, 0, 0]))))


def glb_audit(path):
    d, blob = read_glb(path)
    nodes = d.get("nodes", [])
    parents = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    matrices = {}

    def world(i):
        if i not in matrices:
            matrices[i] = node_matrix(nodes[i]) * (world(parents[i]) if i in parents else Gf.Matrix4d(1))
        return matrices[i]

    skin_roots = set()
    for skin in d.get("skins", []):
        skin_roots.update(i for i in skin["joints"] if parents.get(i) not in skin["joints"])
    root_targets = set(skin_roots)
    for i in skin_roots:
        while i in parents:
            i = parents[i]
            root_targets.add(i)
    all_points, meshes, triangles = [], [], 0
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        for primitive in d["meshes"][n["mesh"]]["primitives"]:
            if primitive.get("extensions", {}).get("KHR_draco_mesh_compression"):
                raise ValueError("Draco decoding unavailable; do not report compressed geometry as inspected")
            points = [tuple(world(i).Transform(Gf.Vec3d(*p))) for p in accessor(d, blob, primitive["attributes"]["POSITION"])]
            all_points.extend(points)
            count = d["accessors"][primitive["indices"]]["count"] if "indices" in primitive else len(points)
            mode = primitive.get("mode", 4)
            tri = count // 3 if mode == 4 else max(0, count - 2) if mode in (5, 6) else 0
            triangles += tri
            meshes.append({"node": i, "material": primitive.get("material"), "vertices": len(points),
                           "triangles": tri, "unskinned_world_bounds": bounds(points),
                           "vertex_mean": [sum(p[k] for p in points) / len(points) for k in range(3)],
                           "morph_target_count": len(primitive.get("targets", []))})
    animations = []
    for a in d.get("animations", []):
        times, roots = [], []
        for c in a["channels"]:
            s = a["samplers"][c["sampler"]]
            t = [v[0] for v in accessor(d, blob, s["input"])]
            times.extend(t)
            target = c["target"]
            if target.get("node") in root_targets and target["path"] in ("translation", "rotation", "scale"):
                values = accessor(d, blob, s["output"])
                if s.get("interpolation") == "CUBICSPLINE":
                    values = values[1::3]  # exclude in/out tangents; extrema between keys remain unverified
                roots.append({"node": target["node"], "name": nodes[target["node"]].get("name"),
                              "path": target["path"], "key_values": motion(values),
                              "interpolation": s.get("interpolation", "LINEAR")})
        animations.append({"name": a.get("name"), "start_seconds": min(times), "end_seconds": max(times),
                           "duration_seconds": max(times) - min(times), "channel_count": len(a["channels"]),
                           "root_and_ancestor_channels_local_space": roots})
    images = []
    for image in d.get("images", []):
        if "bufferView" not in image:
            raise ValueError("External images require an explicit resolver")
        v = d["bufferViews"][image["bufferView"]]
        start = v.get("byteOffset", 0)
        content = blob[start:start + v["byteLength"]]
        images.append({"name": image.get("name"), "mime_type": image.get("mimeType"),
                       "bytes": len(content), "dimensions": png_size(content)})
    return {"generator": d["asset"], "scene": d.get("scene"), "scenes": d.get("scenes"),
            "coordinate_system": "glTF: right-handed, +Y up; visual forward not encoded",
            "nodes": [{"index": i, "parent": parents.get(i), **n} for i, n in enumerate(nodes)],
            "skins": d.get("skins", []), "triangles": triangles, "primitives": meshes,
            "unskinned_world_bounds": bounds(all_points), "images": images,
            "materials": d.get("materials", []), "textures": d.get("textures", []),
            "extensions_used": d.get("extensionsUsed", []), "animations": animations}


def usdz_audit(path):
    stage = Usd.Stage.Open(str(path))
    if not stage:
        raise ValueError(f"Cannot open {path}")
    result = {"up_axis": str(UsdGeom.GetStageUpAxis(stage)), "meters_per_unit": UsdGeom.GetStageMetersPerUnit(stage),
              "start_time_code": stage.GetStartTimeCode(), "end_time_code": stage.GetEndTimeCode(),
              "time_codes_per_second": stage.GetTimeCodesPerSecond(), "frames_per_second": stage.GetFramesPerSecond(),
              "custom_layer_data": json_value(dict(stage.GetRootLayer().customLayerData)),
              "hierarchy": [], "skeletons": [], "animations": [], "meshes": [], "shader_inputs": [], "images": []}
    for p in stage.TraverseAll():
        result["hierarchy"].append({"path": str(p.GetPath()), "type": p.GetTypeName(),
                                    "variant_sets": p.GetVariantSets().GetNames(),
                                    "animation_source": [str(x) for x in UsdSkel.BindingAPI(p).GetAnimationSourceRel().GetTargets()]})
        if p.IsA(UsdGeom.Xformable):
            xf = UsdGeom.Xformable(p)
            matrix = xf.GetLocalTransformation(Usd.TimeCode.Default())
            result["hierarchy"][-1]["default_local_matrix_rows"] = [list(row) for row in matrix]
            result["hierarchy"][-1]["transform_time_sample_count"] = len(xf.GetTimeSamples())
        if p.IsA(UsdSkel.Skeleton):
            sk = UsdSkel.Skeleton(p)
            result["skeletons"].append({"path": str(p.GetPath()), "joints": list(sk.GetJointsAttr().Get() or []),
                                        "joint_names": list(sk.GetJointNamesAttr().Get() or [])})
        if p.IsA(UsdSkel.Animation):
            a = UsdSkel.Animation(p)
            joints = list(a.GetJointsAttr().Get() or [])
            roots = joint_root_indices(joints)
            channels = []
            for attr in [a.GetTranslationsAttr(), a.GetRotationsAttr(), a.GetScalesAttr()]:
                samples = attr.GetTimeSamples()
                for i in roots:
                    values = [attr.Get(t)[i] for t in samples]
                    if attr.GetName() == "rotations":
                        values = [(*v.GetImaginary(), v.GetReal()) for v in values]
                    channels.append({"joint": joints[i], "attribute": attr.GetName(), "sample_count": len(samples),
                                     "key_values": motion(values)})
            times = sorted(set(t for attr in p.GetAttributes() for t in attr.GetTimeSamples()))
            result["animations"].append({"path": str(p.GetPath()), "joint_count": len(joints),
                                          "sample_count": len(times), "start": min(times) if times else None,
                                          "end": max(times) if times else None,
                                          "blend_shapes": list(a.GetBlendShapesAttr().Get() or []),
                                          "root_channels_local_space": channels})
        if p.IsA(UsdGeom.Mesh):
            m = UsdGeom.Mesh(p)
            points = m.GetPointsAttr().Get(Usd.TimeCode.Default())
            transform = UsdGeom.XformCache(Usd.TimeCode.Default()).GetLocalToWorldTransform(p)
            world_points = [tuple(transform.Transform(Gf.Vec3d(v))) for v in points]
            result["meshes"].append({"path": str(p.GetPath()), "vertices": len(points),
                                      "triangulated_face_count": sum(max(0, n - 2) for n in m.GetFaceVertexCountsAttr().Get()),
                                      "unskinned_world_bounds": bounds(world_points),
                                      "vertex_mean": [sum(v[k] for v in world_points) / len(world_points) for k in range(3)],
                                      "double_sided": m.GetDoubleSidedAttr().Get(),
                                      "blend_shapes": list(UsdSkel.BindingAPI(p).GetBlendShapesAttr().Get() or [])})
        if p.GetTypeName() == "Shader":
            values = {a.GetName(): str(a.Get()) for a in p.GetAttributes()
                      if a.GetName().startswith(("inputs:", "info:")) and a.HasAuthoredValueOpinion()}
            connections = {a.GetName(): [str(x) for x in a.GetConnections()] for a in p.GetAttributes() if a.GetConnections()}
            result["shader_inputs"].append({"path": str(p.GetPath()), "values": values, "connections": connections})
    with zipfile.ZipFile(path) as z:
        result["archive"] = [{"name": x.filename, "bytes": x.file_size} for x in z.infolist()]
        result["images"] = [{"name": n, "dimensions": png_size(z.read(n))} for n in z.namelist() if n.lower().endswith('.png')]
    return result


def audit(root=ROOT):
    files = sorted((root / "android/app/src/main/assets").glob("*.glb")) + sorted((root / "ios/Runner/CharacterReader").glob("*.usdz"))
    return {"schema_version": 1, "openusd_version": list(Usd.GetVersion()),
            "limitations": ["Bounds are static unskinned geometry, not posed/animated runtime bounds.",
                            "Root motion is sampled local-space root/ancestor TRS, not skinned foot or world-space displacement.",
                            "Quaternion component ranges are not angular drift; interpolation extrema are not sampled.",
                            "USD composed active/default variants inspected; runtime RealityKit availableAnimations not measured.",
                            "No visual forward-axis, frame pacing, thermal, runtime capability or rendering claims."],
            "assets": [{"file": str(p.relative_to(root)), "bytes": p.stat().st_size,
                        "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
                        "format": p.suffix[1:], "metadata": glb_audit(p) if p.suffix == '.glb' else usdz_audit(p)} for p in files]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", type=Path, help="Compare against checked-in report (including hashes and OpenUSD version)")
    args = parser.parse_args()
    report = audit()
    if args.check and report != json.loads(args.check.read_text()):
        sys.exit("Asset audit differs; regenerate and review metadata/mappings")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    elif not args.check:
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
