#!/usr/bin/env python3
"""Build simple hand props from primitives instead of generating them.

Blender script. A knife, a bow and a quiver are a handful of stretched
cylinders and boxes; paying a text-to-3d call for one buys an unpredictable
mesh whose grip point then has to be found and re-centred afterwards
(prop_edit.py --recentre exists because of exactly that). Authoring them here
costs no credits and fixes the two things that actually matter:

  ORIGIN IS THE GRIP. rig_weapon.py sends a prop's ORIGIN to the grip bone, so
  every shape here is built with the hand at (0,0,0). No bounding-box centring,
  no re-centre pass, no handle buried in the wrist.

  +X IS FORWARD. The blade points +X, the arrow flies +X, the quiver's mouth
  faces +X. So every prop binds with `--forward-axis X` and the same aim-vector
  maths, whatever its shape.

Sizes are WORLD units against a 1.7-unit character, so no --scale at bind time
either. --size rescales the whole prop for a character of a different height.

  blender -b --python make_prop.py -- --kind knife  --out knife.glb
  blender -b --python make_prop.py -- --kind bow    --out bow.glb --length 0.95
  blender -b --python make_prop.py -- --kind quiver --out quiver.glb
"""
import sys
import math

import bpy
import bmesh
from mathutils import Vector, Matrix


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"kind": "knife", "out": None, "size": 1.0, "length": 0.0, "name": "",
         "density": 1.0, "bevel": 1.0, "shade": "smooth"}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            k, v = argv[i][2:].replace("-", "_"), argv[i + 1]
            o[k] = float(v) if k in ("size", "length", "density", "bevel") else v
            i += 2
        else:
            i += 1
    return o


def mat(name, rgb, rough=0.55):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    if b:
        b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        if "Roughness" in b.inputs:
            b.inputs["Roughness"].default_value = rough
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    return m


def _merge(bm, tmp_bm, matrix):
    bmesh.ops.transform(tmp_bm, matrix=matrix, verts=tmp_bm.verts)
    tmp = bpy.data.meshes.new("t")
    tmp_bm.to_mesh(tmp)
    tmp_bm.free()
    bm.from_mesh(tmp)
    bpy.data.meshes.remove(tmp)


def box(bm, centre, size, rot=None):
    t = bmesh.new()
    bmesh.ops.create_cube(t, size=1.0)
    m = Matrix.Translation(centre)
    if rot is not None:
        m = m @ rot
    _merge(bm, t, m @ Matrix.Diagonal(Vector(size).to_4d()))


def cyl(bm, centre, radius, depth, axis="Z", segs=10, rot=None):
    t = bmesh.new()
    bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=radius, radius2=radius, depth=depth)
    base = {"Z": Matrix.Identity(4),
            "X": Matrix.Rotation(math.radians(90), 4, "Y"),
            "Y": Matrix.Rotation(math.radians(-90), 4, "X")}[axis]
    m = Matrix.Translation(centre)
    if rot is not None:
        m = m @ rot
    _merge(bm, t, m @ base)


def assign(ob, slot, pred):
    """Put every face whose centre satisfies pred() into material slot."""
    for p in ob.data.polygons:
        c = sum((ob.data.vertices[i].co for i in p.vertices),
                Vector()) / len(p.vertices)
        if pred(c):
            p.material_index = slot


# -- the props ---------------------------------------------------------------
# Each returns (bmesh, [materials], [(slot, predicate)]) with the grip at the
# origin and forward = +X.

def build_knife(o):
    """A goblin cleaver: wrapped grip, tapered chipped blade."""
    L = o["length"] or 0.40
    D = o["density"]
    grip_l = L * 0.28
    blade_l = L * 0.72
    seg = max(8, int(14 * D))
    bm = bmesh.new()
    # The grip runs BACK from the origin so the hand closes on its middle.
    # Stacked rings rather than one tube, so the wrap has thickness variation
    # instead of reading as a dowel.
    rings = max(4, int(7 * D))
    for i in range(rings):
        t = i / float(rings - 1)
        r = L * (0.032 + 0.006 * math.sin(t * math.pi * 3.0))
        cyl(bm, Vector((-grip_l * (0.08 + 0.62 * t), 0, 0)), r,
            grip_l / rings * 1.35, axis="X", segs=seg)
    cyl(bm, Vector((-grip_l * 0.78, 0, 0)), L * 0.052, L * 0.04,
        axis="X", segs=seg)
    box(bm, Vector((0.006, 0, 0)), (L * 0.035, L * 0.12, L * 0.058))
    # Blade as a lofted taper: wide at the guard, narrowing to the point, with
    # a spine offset so it is a blade and not a rectangle.
    steps = max(6, int(12 * D))
    prev = None
    x0 = grip_l * 0.5
    for i in range(steps + 1):
        t = i / float(steps)
        x = x0 + blade_l * t
        w = L * (0.026 - 0.016 * t * t)
        h = L * (0.150 - 0.075 * t * t * t)
        zc = L * 0.02 * (1.0 - t)
        ring = [bm.verts.new(Vector((x, sy * w, zc + sz * h)))
                for sy, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        if prev is not None:
            for k in range(4):
                k2 = (k + 1) % 4
                bm.faces.new((prev[k], prev[k2], ring[k2], ring[k]))
        else:
            bm.faces.new(tuple(reversed(ring)))
        prev = ring
    bm.faces.new(tuple(prev))
    mats = [mat("Steel", (0.60, 0.63, 0.68), 0.35),
            mat("Leather", (0.28, 0.19, 0.12), 0.85)]
    return bm, mats, [(1, lambda c: c.x < 0.004)]


def build_bow(o):
    """Recurve bow: limbs arc along Z, arrow flies +X, riser at the origin.

    The limb is LOFTED -- rings of vertices swept along the arc and bridged --
    not a chain of stretched cylinders. The cylinder version is the obvious
    approach and it looks wrong: each segment keeps its own flat end caps, and
    where two rotated segments meet the caps poke out through the surface, so
    the outer edge of the bow reads as a row of lumps rather than a smooth
    stave. Visible even at board size.
    """
    L = o["length"] or 0.95
    bm = bmesh.new()
    half = L * 0.5
    steps = max(10, int(26 * o["density"]))
    ring_n = max(6, int(11 * o["density"]))

    def limb(sign):
        rings = []
        for i in range(steps + 1):
            t = i / float(steps)
            z = half * t * sign
            x = -L * 0.13 * (t * t)
            # tangent of the arc, so each ring stays perpendicular to the stave
            dz = half * sign
            dx = -L * 0.13 * 2.0 * t
            tang = Vector((dx, 0.0, dz)).normalized()
            up = Vector((0.0, 1.0, 0.0))
            side = tang.cross(up).normalized()
            r = L * (0.022 - 0.013 * t)
            ring = []
            for k in range(ring_n):
                a = math.tau * k / ring_n
                off = side * (math.cos(a) * r) + up * (math.sin(a) * r)
                ring.append(bm.verts.new(Vector((x, 0.0, z)) + off))
            rings.append(ring)
        bm.verts.ensure_lookup_table()
        for i in range(steps):
            for k in range(ring_n):
                k2 = (k + 1) % ring_n
                bm.faces.new((rings[i][k], rings[i][k2],
                              rings[i + 1][k2], rings[i + 1][k]))
        bm.faces.new(tuple(reversed(rings[0])))
        bm.faces.new(tuple(rings[-1]))

    limb(1)
    limb(-1)
    for i in range(max(3, int(6 * o["density"]))):
        t = i / 5.0
        cyl(bm, Vector((0, 0, L * (t - 0.5) * 0.15)),
            L * (0.034 + 0.004 * math.sin(t * math.pi * 2.0)), L * 0.032,
            axis="Z", segs=max(8, int(14 * o["density"])))
    # String: a straight line between the two nocks, in front of the riser.
    cyl(bm, Vector((-L * 0.13, 0, 0)), L * 0.005, L, axis="Z",
        segs=max(4, int(8 * o["density"])))
    mats = [mat("Wood", (0.36, 0.25, 0.15), 0.75),
            mat("Cord", (0.82, 0.78, 0.68), 0.9)]
    return bm, mats, [(1, lambda c: c.x < -L * 0.115)]


def build_quiver(o):
    """Back quiver: tube plus protruding arrow shafts and fletching."""
    L = o["length"] or 0.34
    bm = bmesh.new()
    D = o["density"]
    seg = max(10, int(20 * D))
    cyl(bm, Vector((0, 0, 0)), L * 0.16, L, axis="X", segs=seg)
    for i in range(max(2, int(4 * D))):
        cyl(bm, Vector((L * (i / 3.0 - 0.45), 0, 0)), L * 0.172, L * 0.05,
            axis="X", segs=seg)
    for dy, dz in ((0.05, 0.05), (-0.05, 0.03), (0.0, -0.06),
                   (0.06, -0.02), (-0.03, -0.05)):
        cyl(bm, Vector((L * 0.42, L * dy, L * dz)), L * 0.015, L * 0.78,
            axis="X", segs=max(6, int(10 * D)))
        box(bm, Vector((L * 0.78, L * dy, L * dz)),
            (L * 0.17, L * 0.007, L * 0.075))
    mats = [mat("Leather", (0.30, 0.20, 0.13), 0.85),
            mat("Fletch", (0.72, 0.68, 0.58), 0.9)]
    return bm, mats, [(1, lambda c: c.x > L * 0.62)]


BUILDERS = {"knife": build_knife, "bow": build_bow, "quiver": build_quiver}


def main():
    o = args()
    if o["kind"] not in BUILDERS:
        sys.exit("--kind must be one of %s" % sorted(BUILDERS))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm, mats, preds = BUILDERS[o["kind"]](o)

    me = bpy.data.meshes.new(o["name"] or o["kind"].capitalize())
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(me.name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        me.materials.append(m)
    for slot, pred in preds:
        assign(ob, slot, pred)
    if o["size"] != 1.0:
        me.transform(Matrix.Scale(o["size"], 4))
    me.validate()
    # A light bevel on every edge. Without it these shapes read as flat-shaded
    # boxes however many segments they have -- the silhouette is fine, but the
    # edges catch no light at all, which is what makes primitive geometry look
    # like programmer art.
    if o["bevel"] > 0.0:
        bm2 = bmesh.new()
        bm2.from_mesh(me)
        bmesh.ops.bevel(bm2, geom=list(bm2.verts) + list(bm2.edges),
                        offset=0.0018 * o["bevel"], segments=2, affect="EDGES",
                        offset_type="OFFSET", clamp_overlap=True)
        bm2.to_mesh(me)
        bm2.free()
    smooth = o["shade"] == "smooth"
    for p in me.polygons:
        p.use_smooth = smooth

    co = [v.co for v in me.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    print("PROP %s  verts %d  polys %d  size %.3f %.3f %.3f"
          % (me.name, len(me.vertices), len(me.polygons),
             hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))
    print("  bounds min %s max %s   (origin = grip, +X = forward)"
          % (tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi)))
    print("  materials %s" % [m.name for m in me.materials])
    if o["out"]:
        bpy.ops.export_scene.gltf(filepath=o["out"], export_format="GLB",
                                  use_selection=False)
        print("  wrote %s" % o["out"])


if __name__ == "__main__":
    main()
