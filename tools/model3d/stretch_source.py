#!/usr/bin/env python3
"""Locate WHY skirt_stress is flagging a model: where the stretched edges are,
and which bones they are weighted to. Blender script.

The companion to skirt_stress.py. That tool tells you a clip scores badly; this
one tells you whether the cause is the motion or the SKINNING. Reed scored
3.2-7.5x on every clip including a near-motionless idle, with a visibly intact
robe; this listing showed hem vertices at 21% of height weighted to `Spine`
beside neighbours weighted to `RightLeg`, and hip vertices weighted to
`RightShoulder`. Meshy's auto-weighting had bound distant bones to the lower
robe, which tears those edges between bones that move independently.

If the dominant-bone pairs name bones that have no business being adjacent, the
fix is the weights, not the clip and not the threshold.

  blender --background --python stretch_source.py -- \
      --model "<glb>" --clip idle [--frame 141]
"""
import sys
import bpy


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {}
    i = 0
    while i < len(argv):
        o[argv[i].lstrip("-")] = argv[i + 1]
        i += 2
    return o


def ev(ob, dg):
    e = ob.evaluated_get(dg)
    m = e.to_mesh()
    mw = ob.matrix_world
    pts = [mw @ v.co.copy() for v in m.vertices]
    e.to_mesh_clear()
    return pts


o = args()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=o["model"])
dg = bpy.context.evaluated_depsgraph_get()
arm = next(x for x in bpy.data.objects if x.type == "ARMATURE")
mesh = max((x for x in bpy.data.objects if x.type == "MESH"),
           key=lambda x: len(x.data.vertices))
ad = arm.animation_data or arm.animation_data_create()
ad.action = None
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
dg.update()
rest = ev(mesh, dg)
zs = [p.z for p in rest]
lo, hi = min(zs), max(zs)

act = next(a for a in bpy.data.actions if o["clip"] in a.name)
ad.action = act
if hasattr(ad, "action_slot") and getattr(act, "slots", None):
    ad.action_slot = act.slots[0]
bpy.context.scene.frame_set(int(o.get("frame", 140)))
dg.update()
now = ev(mesh, dg)

gname = {g.index: g.name for g in mesh.vertex_groups}


def dom(vi):
    best, bn = 0.0, "?"
    for g in mesh.data.vertices[vi].groups:
        if g.weight > best:
            best, bn = g.weight, gname.get(g.group, "?")
    return bn


rows = []
for e in mesh.data.edges:
    a, b = e.vertices
    d0 = (rest[a] - rest[b]).length
    if d0 < 1e-6:
        continue
    r = (now[a] - now[b]).length / d0
    rows.append((r, (rest[a].z + rest[b].z) * 0.5, a, b, d0))
rows.sort(reverse=True)
print(f"height {hi - lo:.3f}  frame {o.get('frame', 140)}  clip {act.name}")
print(f"{'ratio':>7} {'mid z':>7} {'z%':>5} {'restlen':>8}  bones")
for r, z, a, b, d0 in rows[:25]:
    print(f"{r:7.2f} {z:7.3f} {(z - lo) / (hi - lo):5.0%} {d0:8.4f}  {dom(a)} / {dom(b)}")
big = [x for x in rows if x[0] > 2.0]
print(f"\n{len(big)} edges over 2x of {len(rows)}")
from collections import Counter
c = Counter()
for r, z, a, b, d0 in big:
    c[(dom(a), dom(b))] += 1
for k, n in c.most_common(8):
    print(f"  {n:5d}  {k[0]} / {k[1]}")
