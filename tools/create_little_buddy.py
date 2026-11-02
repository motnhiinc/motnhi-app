"""Build the original, static Little Buddy concept using Blender 4.5.

Run in Blender's scripting workspace, or with a Python environment containing
bpy==4.5.3: python tools/create_little_buddy.py
Outputs are deliberately NOT installed in the app's native asset bundles.
"""

from pathlib import Path
import json
import math

import bpy
from mathutils import Vector


OUT = Path(__file__).resolve().parents[1] / "assets/characters/little_buddy"
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0


def material(name, color, roughness=0.65):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    return mat


# Linear values corresponding approximately to the approved HTML palette.
def rgb(hex_color):
    channels = [int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + .055) / 1.055) ** 2.4 for c in channels)


moss = material("Moss green · body", rgb("86bc84"))
light = material("Tender green · muzzle", rgb("b9dda0"))
dark = material("Fern green · back plates", rgb("599568"))
cream = material("Warm cream · belly and toes", rgb("f9e8b9"))
ink = material("Deep forest · eyes and smile", rgb("293e33"), .3)
white = material("Ivory · eyes", rgb("fcfff2"), .35)
peach = material("Peach · cheeks", rgb("eeac91"))
nostril = material("Soft green · nostrils", rgb("729564"))
parts = []


def ellipsoid(name, location, scale, mat, rotation=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    if rotation:
        obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    parts.append(obj)
    return obj


def stroke(name, points, radius, mat):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 12
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coord in zip(spline.bezier_points, points):
        point.co = coord
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    parts.append(bpy.context.object)
    return bpy.context.object


def make_tail():
    centers = [(0, .025, .049), (.018, .046, .043), (.043, .060, .039),
               (.065, .059, .043), (.079, .050, .055), (.084, .044, .066)]
    radii = [.022, .020, .015, .010, .005, .001]
    vertices, faces = [], []
    count = 16
    for i, (center, radius) in enumerate(zip(centers, radii)):
        tangent = Vector(centers[min(i + 1, len(centers) - 1)]) - Vector(centers[max(0, i - 1)])
        tangent.normalize()
        u = tangent.cross(Vector((0, 0, 1))).normalized()
        v = tangent.cross(u).normalized()
        for j in range(count):
            angle = 2 * math.pi * j / count
            vertices.append(Vector(center) + radius * (math.cos(angle) * u + math.sin(angle) * v))
        if i:
            for j in range(count):
                a, b = (i - 1) * count + j, (i - 1) * count + (j + 1) % count
                c, d = i * count + (j + 1) % count, i * count + j
                faces.append((a, b, c, d))
    faces.extend([tuple(reversed(range(count))), tuple(range((len(centers) - 1) * count, len(centers) * count))])
    mesh = bpy.data.meshes.new("Tail mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Tail · soft upward curl", mesh)
    scene.collection.objects.link(obj)
    obj.data.materials.append(moss)
    for face in mesh.polygons:
        face.use_smooth = True
    parts.append(obj)
    modifier = obj.modifiers.new("Rounded tail", "SUBSURF")
    modifier.levels = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


make_tail()
ellipsoid("Body · pear-shaped torso", (0, .006, .071), (.039, .032, .050), moss)
ellipsoid("Belly · cream oval", (0, -.022, .069), (.028, .012, .037), cream)
for side, x in (("Left", -.024), ("Right", .024)):
    ellipsoid(f"{side} foot", (x, -.010, .014), (.021, .029, .014), moss)
    for offset in (-.006, .006):
        ellipsoid(f"{side} toe {offset:+}", (x + offset, -.035, .012), (.0035, .005, .003), cream)
    ellipsoid(f"{side} arm", (x * 1.68, -.004, .084), (.012, .014, .022), moss,
              (0, -.45 if x < 0 else .45, 0))

# All plates are rounded ellipsoids, not sharp horns.
for i, (y, z, size) in enumerate(((.009, .192, .014), (.030, .179, .013),
                                  (.040, .158, .011), (.038, .131, .010),
                                  (.033, .105, .009), (.037, .082, .008))):
    ellipsoid(f"Back plate {i + 1:02}", (0, y, z), (.008, size * .73, size), dark)

ellipsoid("Head · oversized round silhouette", (0, -.006, .151), (.052, .041, .047), moss)
ellipsoid("Muzzle · rounded tooth-free snout", (0, -.041, .132), (.043, .023, .024), light)
for side, sign in (("Left", -1), ("Right", 1)):
    x = .023 * sign
    ellipsoid(f"{side} eye · ivory", (x, -.042, .164), (.012, .007, .015), white)
    ellipsoid(f"{side} eye · pupil", (x + .001, -.0485, .164), (.007, .003, .010), ink)
    ellipsoid(f"{side} eye · highlight", (x - .001, -.0514, .168), (.0025, .001, .003), white)
    ellipsoid(f"{side} cheek", (.037 * sign, -.0405, .143), (.009, .003, .005), peach)
    ellipsoid(f"{side} nostril", (.010 * sign, -.0625, .140), (.002, .0013, .0016), nostril)
    stroke(f"{side} friendly eyebrow", [(x - .007, -.038, .182), (x, -.040, .184),
                                        (x + .006, -.038, .1825)], .0012, dark)

stroke("Smile · recessed-look curved line", [(-.016, -.0598, .127), (-.009, -.0627, .122),
                                             (0, -.0632, .120), (.009, -.0627, .122),
                                             (.016, -.0598, .127)], .0011, ink)

root = bpy.data.objects.new("Little Buddy · 20 cm · static concept", None)
scene.collection.objects.link(root)
root["description"] = "Original baby dinosaur based on ar-buddy-concept.html. Static, unrigged prototype."
root["units"] = "meters"
root["front"] = "-Y in Blender; +Z after glTF export"
for obj in parts:
    obj.parent = root

# Freeze model selection separately from the presentation setup.
def select_character():
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root


select_character()
bpy.ops.export_scene.gltf(filepath=str(OUT / "little_buddy.glb"), export_format="GLB",
                          use_selection=True, export_animations=False, export_yup=True,
                          export_cameras=False, export_lights=False)

# Blender's USDZ packager embeds its USD stage and materials in one archive.
usd_options = dict(filepath=str(OUT / "little_buddy.usdz"), selected_objects_only=True,
                   export_animation=False, export_materials=True, generate_preview_surface=True,
                   export_cameras=False, export_lights=False)
available = bpy.ops.wm.usd_export.get_rna_type().properties.keys()
bpy.ops.wm.usd_export(**{key: value for key, value in usd_options.items() if key in available})

# Studio objects belong only to the editable .blend / preview, never to AR exports.
floor_mat = material("STUDIO · warm paper", rgb("eaf0df"), .9)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.001))
floor = bpy.context.object
floor.name = "STUDIO · ground (not exported)"
floor.data.materials.append(floor_mat)
scene.world.color = (.35, .35, .35)


def point_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for name, location, power, size in (("Key", (-.25, -.35, .50), 12, .35),
                                    ("Fill", (.30, -.10, .30), 5, .30),
                                    ("Rim", (.05, .30, .40), 10, .25)):
    bpy.ops.object.light_add(type="AREA", location=location)
    lamp = bpy.context.object
    lamp.name = f"STUDIO · {name}"
    lamp.data.energy = power
    lamp.data.shape = "DISK"
    lamp.data.size = size
    point_at(lamp, (0, 0, .10))

bpy.ops.object.camera_add(location=(.29, -.56, .27))
camera = bpy.context.object
camera.name = "STUDIO · three-quarter camera"
camera.data.type = "ORTHO"
camera.data.ortho_scale = .29
point_at(camera, (.008, 0, .100))
scene.camera = camera
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 1000
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"

triangle_count = sum(len(p.vertices) - 2 for obj in parts for p in obj.data.polygons)
corners = [obj.matrix_world @ Vector(corner) for obj in parts for corner in obj.bound_box]
bounds = {axis: [round(min(v[i] for v in corners), 5), round(max(v[i] for v in corners), 5)]
          for i, axis in enumerate("xyz")}
report = {"blender_version": bpy.app.version_string, "static": True, "rigged": False,
          "units": "meters", "bounds": bounds, "mesh_objects": len(parts),
          "triangles": triangle_count, "materials": 8,
          "device_tested": False, "installed_in_app": False}
(OUT / "build-report.json").write_text(json.dumps(report, indent=2) + "\n")
select_character()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "little_buddy.blend"))
scene.render.filepath = str(OUT / "preview-three-quarter.png")
bpy.ops.render.render(write_still=True)
camera.location = (0, -.60, .17)
point_at(camera, (0, 0, .100))
scene.render.filepath = str(OUT / "preview-front.png")
bpy.ops.render.render(write_still=True)
print(json.dumps(report, indent=2))
