#!/usr/bin/env python3
"""Per-frame prop-vs-body penetration scan over one clip. Blender script.

prop_rubric.py has an opinion about a SINGLE frame's grip. This answers the
other question -- "does the prop pass through him at any point while the clip
plays" -- which a rest-pose check cannot see and a frame strip only catches by
luck, because the worst frame is rarely one of the eight that got sampled.

INSIDE, NOT NEAR. Distance alone is the wrong test: a syringe held tight
against the apron is 2mm away and correct, while one whose needle has entered
the ribcage may also be 2mm from the nearest surface. So each prop vertex is
classified by RAY PARITY against the body mesh (odd crossings = inside). Depth
is then how far inside the deepest vertex is.

THE GRIP IS EXEMPT. Vertices within --grip-sphere of the grip bone are skipped:
the hand is supposed to intersect the prop there, and Cross's rubric wasted a
review round reporting that intended contact as a fault.

  blender -b --python clip_clearance.py -- --model doc.glb \
      --clip attack --prop Syringe_Held --grip RightHand --json out.json

Reports the worst frame and every frame over --tol. A pass here means no
penetration was measured; it says nothing about whether the motion reads well.
"""
import json
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "clip": "attack", "prop": "Weapon_Held",
         "grip": "RightHand", "grip_sphere": "0.20", "tol": "0.004",
         "body": "char1", "exempt_groups": "", "json": None}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            o[argv[i][2:].replace("-", "_")] = argv[i + 1]
            i += 2
        else:
            i += 1
    return o


def ev_mesh(ob, dg):
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    verts = [ev.matrix_world @ v.co for v in me.vertices]
    polys = [list(p.vertices) for p in me.polygons]
    dom = []
    for v in me.vertices:
        dom.append(max(v.groups, key=lambda g: g.weight).group if v.groups else -1)
    ev.to_mesh_clear()
    return verts, polys, dom


def main():
    o = args()
    R = {"model": o["model"], "clip": o["clip"], "prop": o["prop"]}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    for x in list(bpy.data.objects):
        if x.name.startswith("Icosphere"):
            bpy.data.objects.remove(x, do_unlink=True)

    arm = next(x for x in bpy.data.objects if x.type == "ARMATURE")
    prop = bpy.data.objects[o["prop"]]
    body = bpy.data.objects.get(o["body"]) or next(
        x for x in bpy.data.objects
        if x.type == "MESH" and x.name != o["prop"])

    act = next((a for a in bpy.data.actions
                if a.name == o["clip"] or o["clip"] in a.name), None)
    if act is None:
        sys.exit("no action %r; have %s"
                 % (o["clip"], sorted(a.name for a in bpy.data.actions)))
    arm.animation_data_create()
    arm.animation_data.action = act
    if hasattr(arm.animation_data, "action_slot") and act.slots:
        arm.animation_data.action_slot = act.slots[0]
    arm.data.pose_position = "POSE"

    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    sphere = float(o["grip_sphere"])
    tol = float(o["tol"])
    # WHICH BODY PARTS ARE ALLOWED TO INTERSECT THE PROP. The hand and forearm
    # are: that is the grip. Everything else is a fault.
    #
    # This is done by classifying the SURFACE THE PROP ENTERED, not by deleting
    # the torso from the mesh first. Deleting faces was the obvious approach and
    # it is wrong -- ray parity needs a CLOSED surface, and a mesh with the arms
    # cut out is full of holes, so "inside" becomes meaningless. It reported a
    # 0.75-unit penetration depth on a 1.7-unit character, which is not a
    # geometric possibility. The body mesh stays watertight here.
    exempt = set()
    if o["exempt_groups"]:
        names = [x.strip() for x in o["exempt_groups"].split(",")]
        idx = {g.name: g.index for g in body.vertex_groups}
        missing = [n for n in names if n not in idx]
        if missing:
            sys.exit("no such vertex groups: %s" % missing)
        exempt = {idx[n] for n in names}
        R["exempt_groups"] = names

    sc = bpy.context.scene
    rows = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        bv, bp, bdom = ev_mesh(body, dg)
        tree = BVHTree.FromPolygons(bv, bp)
        pv, _, _ = ev_mesh(prop, dg)
        grip = arm.matrix_world @ arm.pose.bones[o["grip"]].matrix.translation

        worst, n_in = 0.0, 0
        where = {}
        for p in pv:
            if (p - grip).length < sphere:
                continue
            # ray parity: an odd number of crossings going out = inside
            hits, orig, d = 0, Vector(p), Vector((0.577, 0.577, 0.577))
            while True:
                loc, nor, idx, dist = tree.ray_cast(orig, d)
                if loc is None:
                    break
                hits += 1
                orig = loc + d * 1e-5
            if hits % 2 == 1:
                near = tree.find_nearest(p)
                if near[0] is None:
                    continue
                if exempt and near[2] is not None:
                    face = bp[near[2]]
                    if any(bdom[i] in exempt for i in face):
                        continue          # inside the hand -- that is the grip
                n_in += 1
                worst = max(worst, (Vector(near[0]) - p).length)
                if near[2] is not None:
                    for i in bp[near[2]]:
                        g = bdom[i]
                        if g >= 0:
                            where[g] = where.get(g, 0) + 1
        gname = {g.index: g.name for g in body.vertex_groups}
        top = sorted(where.items(), key=lambda kv: -kv[1])[:3]
        rows.append([f, n_in, round(worst, 5),
                     [gname.get(g, str(g)) for g, _ in top]])

    bad = [r for r in rows if r[2] > tol]
    R["frames"] = [f0, f1]
    R["grip_sphere"] = sphere
    R["tolerance"] = tol
    R["per_frame"] = rows
    R["frames_over_tolerance"] = bad
    R["worst"] = max(rows, key=lambda r: r[2]) if rows else None
    R["pass"] = not bad
    print("clip %s frames %d..%d  grip-sphere %.3f  tol %.4f"
          % (act.name, f0, f1, sphere, tol))
    print("worst frame %s (frame, verts_inside, depth)" % (R["worst"],))
    for r in bad:
        print("  OVER  frame %3d  %5d verts inside  depth %.4f  into %s"
              % (r[0], r[1], r[2], ", ".join(r[3])))
    print("PASS" if R["pass"] else "FAIL (%d frames)" % len(bad))
    if o["json"]:
        json.dump(R, open(o["json"], "w"), indent=1)


if __name__ == "__main__":
    main()
