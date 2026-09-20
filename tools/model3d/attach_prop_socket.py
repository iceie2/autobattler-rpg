#!/usr/bin/env python3
"""Convert a full-body-skinned prop into a single dedicated attachment bone.

Blender script. Migrates a held prop from "skinned to all 24 rig bones" (what
rig_weapon.py produces) to "rigidly weighted 1.0 to one hand-child bone", which
is the glTF-native equivalent of an attachment socket.

WHY A BONE AND NOT A REAL SOCKET. Blender's `parent_type='BONE'` is the obvious
answer and is REJECTED here on recorded evidence: rig_weapon.py documents that a
bone-parented export re-imported with translations "in the TENS" on this rig
family, because Blender's glTF export path uses bone rest LENGTH internally --
and these rigs carry 29-unit bones on a 1.7-unit character. Constraints
(Child-Of, Copy Transforms) are rejected for a simpler reason: glTF has no
constraint concept, so they export as nothing at all.

HOW THE PROP KEEPS ITS EXACT PLACE. Linear-blend skinning moves a vertex by
`bone_pose @ bone_rest^-1`. At REST, pose == rest, so that product is the
identity and a vertex weighted 1.0 to ANY bone does not move. So: enter Edit
Mode at rest, create the bone there (its rest matrix is therefore its own bind
matrix), assign weight 1.0, and the prop's world placement is conserved by
construction rather than by choosing angles. The script then ASSERTS that, per
vertex, to 1e-5.

The bone's head/tail are derived from the prop's existing geometry -- nearest
point on the prop to the grip bone, and the prop's own principal axis. That is
a PLACEMENT CANDIDATE for human review, NOT evidence the character holds the
prop correctly. This script makes no claim about how anything looks.

TWO MODES, both selected by --map (NAME:BONE:PARENT[:FILE]):

  MIGRATE a prop already skinned to the whole body -- omit FILE. This is what
  Cross needed: rig_weapon.py had bound his maul and shield with weights on all
  24 bones, so they deformed with the torso instead of riding the hand.

      --map Weapon_Held:weapon_r:RightHand,Shield_Held:shield_l:LeftHand

  ATTACH a standalone prop mesh from its own .glb -- give FILE. This is the
  path for a NEW humanoid: generate and rig the body, generate weapon and
  shield as separate text-to-3d props, then bind both in one call.

      --map "Weapon_Held:weapon_r:RightHand:raw/maul.glb,Shield_Held:shield_l:LeftHand:raw/shield.glb"

  blender --background --python attach_prop_socket.py --       --in  <body.blend|body.glb>       --out <out.glb>       --map <entries>       --json <report.json> [--save-blend <out.blend>]

The attachment bone is created as a child of PARENT, in EDIT mode at REST, and
positioned from the prop's own geometry. Every assertion in the JSON report must
pass before the result is used -- the rest-pose displacement check in particular
proves the prop did not move when it was rebound.
"""
import json
import sys

import bpy
import numpy as np
from mathutils import Vector

EPS = 1e-5
TAIL_FRAC = 0.15


def _assert_export_moves(path, min_channels=8, min_degrees=5.0):
    """Re-read the EXPORTED glb and confirm its animation actually moves.

    Pure struct/json parsing — no Blender state involved — because the whole
    point is to check the artefact on disk rather than the scene we think we
    exported. Counts rotation channels whose quaternion samples deviate from
    their first key; a rest-mode export yields exactly zero.
    """
    import math
    import struct
    try:
        with open(path, "rb") as f:
            f.read(12)
            jlen, _ = struct.unpack("<II", f.read(8))
            j = json.loads(f.read(jlen))
            blen, _ = struct.unpack("<II", f.read(8))
            blob = f.read(blen)
    except Exception as e:                                  # pragma: no cover
        return {"pass": False, "error": "could not re-read export: %s" % e}

    def samples(idx):
        a = j["accessors"][idx]
        bv = j["bufferViews"][a["bufferView"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        return [struct.unpack_from("<" + "f" * n, blob, off + k * n * 4)
                for k in range(a["count"])]

    worst = {}
    for anim in j.get("animations", []):
        moving, peak = 0, 0.0
        for ch in anim["channels"]:
            if ch["target"]["path"] != "rotation":
                continue
            vs = samples(anim["samplers"][ch["sampler"]]["output"])
            q0 = vs[0]
            dev = max(2.0 * math.degrees(math.acos(
                min(1.0, abs(sum(a * b for a, b in zip(q0, q)))))) for q in vs)
            if dev > 1.0:
                moving += 1
                peak = max(peak, dev)
        worst[anim.get("name", "?")] = {"moving": moving, "peak_deg": round(peak, 1)}

    bad = {k: v for k, v in worst.items()
           if v["moving"] < min_channels or v["peak_deg"] < min_degrees}
    return {"pass": not bad, "per_clip": worst, "failing": bad,
            "note": ("a clip with 0 moving channels means the armature was "
                     "exported in REST mode")}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"in": None, "out": None, "map": "", "json": None, "save_blend": ""}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            o[argv[i][2:].replace("-", "_")] = argv[i + 1]
            i += 2
        else:
            i += 1
    return o


def world_verts(ob, dg):
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    pts = np.array([list(ev.matrix_world @ v.co) for v in me.vertices])
    ev.to_mesh_clear()
    return pts


def action_inventory():
    def nfc(act):
        n = len(getattr(act, "fcurves", []) or [])
        for lay in getattr(act, "layers", []):
            for st in getattr(lay, "strips", []):
                for cb in getattr(st, "channelbags", []):
                    n += len(cb.fcurves)
        return n
    return {a.name: {"frame_start": round(a.frame_range[0], 3),
                     "frame_end": round(a.frame_range[1], 3),
                     "fcurves": nfc(a)}
            for a in sorted(bpy.data.actions, key=lambda x: x.name)}


def main():
    o = args()
    R = {"input": o["in"], "output": o["out"], "assertions": {}, "props": {}}

    bpy.ops.wm.read_factory_settings(use_empty=True)
    if o["in"].lower().endswith(".blend"):
        bpy.ops.wm.open_mainfile(filepath=o["in"])
    else:
        bpy.ops.import_scene.gltf(filepath=o["in"])
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Icosphere"):
            bpy.data.objects.remove(ob, do_unlink=True)

    arm = next(x for x in bpy.data.objects if x.type == "ARMATURE")
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()

    R["blender"] = bpy.app.version_string
    R["bones_before"] = [b.name for b in arm.data.bones]
    R["actions_before"] = action_inventory()

    # ---- baseline capture, at REST, before any change --------------------
    body = bpy.data.objects["char1"]
    R["char1_before"] = {
        "verts": len(body.data.vertices),
        "polys": len(body.data.polygons),
        "materials": [m.name if m else None for m in body.data.materials],
        "modifiers": [(m.type, m.object.name if getattr(m, "object", None) else None)
                      for m in body.modifiers],
        "vertex_groups": [g.name for g in body.vertex_groups],
    }
    bb = world_verts(body, dg)
    R["char1_before"]["rest_bounds"] = [list(np.round(bb.min(0), 6)),
                                        list(np.round(bb.max(0), 6))]

    # --map entries are  NAME:BONE:PARENT[:FILE]
    # With FILE the prop mesh is IMPORTED from a standalone .glb (the shape
    # text-to-3d produces), renamed to NAME and bound. Without it, NAME must
    # already exist in the scene -- the migration case, converting a prop that
    # was previously skinned to the whole body.
    jobs = []
    for entry in o["map"].split(","):
        bits = entry.split(":")
        if len(bits) == 3:
            pname, bname, parent = bits
            src_file = None
        elif len(bits) == 4:
            pname, bname, parent, src_file = bits
        else:
            raise SystemExit("bad --map entry %r; want NAME:BONE:PARENT[:FILE]" % entry)
        if src_file:
            before = {x.name for x in bpy.data.objects}
            bpy.ops.import_scene.gltf(filepath=src_file)
            fresh = [x for x in bpy.data.objects
                     if x.name not in before and x.type == "MESH"]
            if not fresh:
                raise SystemExit("no mesh imported from " + src_file)
            prop_ob = fresh[0]
            prop_ob.name = pname
            # A freshly imported prop has no armature modifier; give it one so
            # the single-bone bind below actually deforms with the rig.
            if not any(m.type == "ARMATURE" for m in prop_ob.modifiers):
                md = prop_ob.modifiers.new("Armature", "ARMATURE")
                md.object = arm
            prop_ob.parent = arm
            # MUST cancel the armature's own object transform. These rigs carry
            # a 0.01 object scale, so a plain parent shrinks the prop 100x and
            # moves it -- caught by the rest-displacement assertion, which
            # reported 0.495 and bounds of +-0.005 before this line existed.
            prop_ob.matrix_parent_inverse = arm.matrix_world.inverted()
            print("imported prop %s from %s" % (pname, src_file))
        jobs.append((pname, bname, parent))

    before_pts = {}
    for pname, bname, parent in jobs:
        p = bpy.data.objects[pname]
        before_pts[pname] = world_verts(p, dg)

    # ---- create attachment bones, in EDIT mode, at REST -------------------
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for pname, bname, parent in jobs:
        pts = before_pts[pname]
        pb = arm.pose.bones[parent]
        grip = np.array(list(arm.matrix_world @ pb.matrix.translation))
        # head: the prop vertex nearest the grip bone -- a CANDIDATE anchor.
        head = pts[int(np.argmin(np.linalg.norm(pts - grip, axis=1)))]
        # tail: along the prop's own principal axis, so the bone has a real
        # length and orientation instead of a degenerate zero-length stub.
        c = pts.mean(0)
        ax = np.linalg.svd(pts - c)[2][0]
        span = float((pts - c).dot(ax).max() - (pts - c).dot(ax).min())
        tail = head + ax * (span * TAIL_FRAC)

        eb = arm.data.edit_bones.new(bname)
        # edit_bone coords are ARMATURE space; convert from world.
        inv = arm.matrix_world.inverted()
        eb.head = inv @ Vector(head.tolist())
        eb.tail = inv @ Vector(tail.tolist())
        eb.parent = arm.data.edit_bones[parent]
        eb.use_connect = False
        eb.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()

    # ---- re-weight props to exactly one bone ------------------------------
    for pname, bname, parent in jobs:
        p = bpy.data.objects[pname]
        removed = [g.name for g in p.vertex_groups]
        for g in list(p.vertex_groups):
            p.vertex_groups.remove(g)
        vg = p.vertex_groups.new(name=bname)
        vg.add(range(len(p.data.vertices)), 1.0, "REPLACE")
        R["props"][pname] = {"bone": bname, "parent_bone": parent,
                             "groups_removed": removed,
                             "groups_after": [g.name for g in p.vertex_groups]}

    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()

    # ---- ASSERTIONS -------------------------------------------------------
    A = R["assertions"]

    for pname, bname, parent in jobs:
        p = bpy.data.objects[pname]
        # single influence, weight 1.0
        gi = {g.index: g.name for g in p.vertex_groups}
        bad = 0
        maxw = 0.0
        for v in p.data.vertices:
            nz = [g for g in v.groups if g.weight > 0.0]
            if len(nz) != 1 or gi[nz[0].group] != bname or abs(nz[0].weight - 1.0) > 1e-6:
                bad += 1
            for g in v.groups:
                maxw = max(maxw, g.weight)
        A[f"{pname}_single_influence_{bname}_w1"] = {
            "pass": bad == 0, "bad_vertices": bad,
            "verts": len(p.data.vertices), "max_weight": round(maxw, 6)}
        A[f"{pname}_no_original_24bone_influence"] = {
            "pass": all(g.name == bname for g in p.vertex_groups),
            "groups": [g.name for g in p.vertex_groups]}

        after = world_verts(p, dg)
        disp = float(np.abs(after - before_pts[pname]).max()) if after.shape == before_pts[pname].shape else 9.9
        A[f"{pname}_rest_displacement_lt_1e-5"] = {
            "pass": disp < EPS, "max_abs_displacement": disp}
        R["props"][pname]["rest_bounds"] = [list(np.round(after.min(0), 6)),
                                            list(np.round(after.max(0), 6))]
        R["props"][pname]["object_local"] = {
            "location": [round(v, 6) for v in p.location],
            "rotation_euler_deg": [round(np.degrees(v), 6) for v in p.rotation_euler],
            "scale": [round(v, 6) for v in p.scale]}
        b = arm.data.bones[bname]
        R["props"][pname]["bone_rest"] = {
            "head_local": [round(v, 6) for v in b.head_local],
            "tail_local": [round(v, 6) for v in b.tail_local],
            "length": round(b.length, 6),
            "matrix_local": [[round(v, 6) for v in row] for row in b.matrix_local],
            "parent": b.parent.name if b.parent else None}

    # char1 untouched
    ba = world_verts(body, dg)
    same_bounds = np.allclose(np.array(R["char1_before"]["rest_bounds"]),
                              np.array([ba.min(0), ba.max(0)]), atol=1e-6)
    A["char1_unchanged"] = {
        "pass": bool(
            len(body.data.vertices) == R["char1_before"]["verts"]
            and len(body.data.polygons) == R["char1_before"]["polys"]
            and [m.name if m else None for m in body.data.materials] == R["char1_before"]["materials"]
            and [g.name for g in body.vertex_groups] == R["char1_before"]["vertex_groups"]
            and same_bounds),
        "verts": len(body.data.vertices), "polys": len(body.data.polygons),
        "materials": [m.name if m else None for m in body.data.materials],
        "vertex_groups": len(body.vertex_groups),
        "rest_bounds_match": bool(same_bounds)}

    # Exactly one new bone per --map entry, and nothing else touched. This was
    # hardcoded to 26 (Cross: 24 + weapon_r + shield_l), which then failed on
    # every hero with a different socket count -- a false alarm that hides real
    # ones. Expect the count the map asked for.
    want = len(R["bones_before"]) + len(jobs)
    A["bones_expected"] = {"pass": len(arm.data.bones) == want,
                           "count": len(arm.data.bones), "expected": want,
                           "added": [b.name for b in arm.data.bones
                                     if b.name not in R["bones_before"]]}

    after_actions = action_inventory()
    A["actions_intact"] = {"pass": after_actions == R["actions_before"],
                           "before": R["actions_before"], "after": after_actions}

    # BACK TO POSE BEFORE THE SAVE, not just before the export. Everything above
    # runs in REST because that is what makes a socket bone's rest matrix its own
    # bind matrix. But a master saved in REST hands REST to every tool that opens
    # it afterwards — nudge_socket.py then re-exports flat, and the fix applied
    # only at export time here is silently undone one step later. Measured on
    # Riot, 2026-09-18: the socket export was correct and the nudge that followed
    # was dead.
    arm.data.pose_position = "POSE"
    bpy.context.view_layer.update()

    if o["save_blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=o["save_blend"])
        R["saved_blend"] = o["save_blend"]

    # ---- export -----------------------------------------------------------
    # BACK TO POSE FIRST. Everything above runs with pose_position = "REST",
    # because that is what makes the socket bone's rest matrix its own bind
    # matrix and conserves the prop's placement exactly. But the glTF exporter
    # SAMPLES the evaluated depsgraph: exporting while still in REST writes a
    # flat channel for every bone on every frame, so the model arrives in Godot
    # animated-but-motionless.
    #
    # This is not hypothetical. Riot shipped that way on 2026-09-18 — 78
    # channels present, 0 of them moving, 48 identical cells in the probe sheet
    # — and Rift lost days to the identical failure upstream. `actions_intact`
    # does NOT catch it: the Blender actions really are intact, it is only the
    # EXPORT that is dead. Hence the assertion below, which measures the file
    # that was actually written.
    arm.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    try:
        bpy.ops.export_scene.gltf(filepath=o["out"], export_format="GLB",
                                  export_animations=True, use_selection=False)
        A["export_glb"] = {"pass": True, "path": o["out"]}
    except Exception as e:
        A["export_glb"] = {"pass": False, "error": str(e)}

    # Prove the written GLB still MOVES. Re-reads the exported file and counts
    # rotation channels whose samples actually vary, so "the export is flat" can
    # never pass silently again.
    if A.get("export_glb", {}).get("pass"):
        A["export_animation_moves"] = _assert_export_moves(o["out"])

    R["all_pass"] = all(v.get("pass") for v in A.values())
    if o["json"]:
        json.dump(R, open(o["json"], "w"), indent=1)
    print(json.dumps({k: v.get("pass") for k, v in A.items()}, indent=1))
    print("ALL_PASS", R["all_pass"])


if __name__ == "__main__":
    main()
