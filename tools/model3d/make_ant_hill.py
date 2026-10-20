"""Procedural Ant Hill mound (2026-10-03). Blender script.

The Meshy concept for the Ant Hill came back as a dwarf standing beside a
mound; rather than re-spend on what is a lump of dirt, this builds it: a wide
low dome with layered noise displacement, darker tunnel mouths pressed into
the slopes, and dirt / crust / pebble / tunnel materials per face, so it reads
in the same lit PBR presentation as the rest of the 3D roster.

  blender -b --python tools/model3d/make_ant_hill.py -- --out mound.glb
"""
import bpy, bmesh, sys, math, random
from mathutils import Vector, noise

out = sys.argv[sys.argv.index("--out") + 1]
random.seed(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=1.0)
ob = bpy.context.active_object
ob.name = "AntHill"
me = ob.data
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()

# tunnel mouths: (azimuth, elevation-fraction, radius)
holes = [(random.uniform(0, math.tau), random.uniform(0.25, 0.75), random.uniform(0.12, 0.2)) for _ in range(7)]
holes.append((0.0, 1.0, 0.18))        # one at the crown


def hole_depth(p):
    d = 0.0
    for az, el, r in holes:
        hp = Vector((math.cos(az) * math.sin(el * math.pi / 2), math.sin(az) * math.sin(el * math.pi / 2), 0))
        hp.z = math.cos(el * math.pi / 2) if el < 1.0 else 1.0
        dist = (Vector((p.x, p.y, max(p.z, 0))).normalized() - hp.normalized()).length
        if dist < r:
            d = max(d, (1 - dist / r) ** 1.5)
    return d


for v in bm.verts:
    p = v.co.copy()
    if p.z < 0:
        p.z = 0.0                                   # flat base
    else:
        p.z = p.z ** 1.25 * 0.55                    # low wide dome
    n = noise.noise(p * 3.0) * 0.08 + noise.noise(p * 9.0) * 0.025
    r = math.hypot(p.x, p.y)
    p.x *= 1.0 + n
    p.y *= 1.0 + n
    if p.z > 0:
        p.z += n * 0.6
        p.z -= hole_depth(v.co) * 0.12
    v.co = p
bm.to_mesh(me)
bm.free()

# Per-FACE materials, not vertex colours: Godot's glTF import does not use
# COLOR_0 as albedo by default, so a vertex-coloured mound came out flat tan
# in-engine (2026-10-03 board render).
def mat(name, rgb, rough=0.95):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    me.materials.append(m)
    return len(me.materials) - 1

DIRT = mat("Dirt", (0.16, 0.09, 0.045))
CRUST = mat("Crust", (0.26, 0.16, 0.08))
PEBBLE = mat("Pebble", (0.30, 0.28, 0.24), 0.8)
HOLE = mat("Tunnel", (0.012, 0.008, 0.006))
for poly in me.polygons:
    c = poly.center
    h = hole_depth(Vector((c.x, c.y, c.z / 0.55 if c.z > 0 else 0)))
    if h > 0.25:
        poly.material_index = HOLE
    elif noise.noise(c * 25.0) > 0.45:
        poly.material_index = PEBBLE
    elif c.z > 0.32 + noise.noise(c * 6.0) * 0.06:
        poly.material_index = CRUST
    else:
        poly.material_index = DIRT
bpy.ops.object.shade_smooth()
# face +Z like every Meshy body; size ~ a 2x2 unit
ob.scale = (0.5, 0.5, 0.5)
bpy.ops.object.transform_apply(scale=True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB")
print("wrote", out)
