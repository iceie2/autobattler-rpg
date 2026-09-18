#!/usr/bin/env python3
"""Trim a raw Meshy motion to its active window and graft it onto a master.

Blender script. Second half of the bespoke-animation path: `meshy_api.py`
generates the motion and applies it to the rig, this turns the result into a
usable game clip on the character that has sockets and props.

WHY TRIMMING IS ALWAYS NEEDED. Meshy's `duration` is clamped to 2.0-10.0s in
0.5s steps and is not honoured regardless: Cross's 2.0s request came back as
191 frames / 7.97s containing a strike, an idle drift, a second unrelated move,
and static filler. The usable attack was frames 13-37 -- 13% of what was paid
for. Assume the same shape every time.

FIND THE WINDOW BY MEASURING. --auto samples the prop's centroid travel per
frame, finds the peak, and keeps the contiguous run around it -- which
isolated 13-31 out of 192 on Cross. Pass --from/--to instead to override it. Either way the chosen window
is printed and written to the report so the cut is auditable and re-cuttable;
those two numbers are the knob if the strike reads as starting late or ending
early.

RETARGETING IS FREE. Meshy hands back a whole armature+mesh copy alongside the
animation. Only the ACTION is kept -- actions address bones by name
(pose.bones["RightArm"]), and the socketed master keeps all 24 original bone
names, so the clip retargets with no channel remapping. The imported armature
and mesh are deleted.

  blender --background --python trim_and_graft_action.py -- \\
      --master  "assets/3d pipeline/hero/cross/source/cross_master_v002.blend" \\
      --motion  "<raw motion>.glb" \\
      --name    attack \\
      --auto --prop Weapon_Held \\
      --out-blend out.blend --out-glb out.glb --json report.json

  # explicit window instead of measuring
      --from 13 --to 37

An existing action of the same name is RENAMED (never deleted) to
`<name>_prev_N`, so a previous candidate stays available for comparison in
anim_preview rather than being lost.
"""
import json
import sys

import bpy
import numpy as np


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"master": None, "motion": None, "name": "attack", "prop": "Weapon_Held",
         "from": None, "to": None, "thresh": "0.10", "auto": False,
         "out_blend": None, "out_glb": None, "json": None}
    i = 0
    while i < len(argv):
        if argv[i] == "--auto":
            o["auto"] = True; i += 1; continue
        if argv[i].startswith("--") and i + 1 < len(argv):
            o[argv[i][2:].replace("-", "_")] = argv[i + 1]; i += 2
        else:
            i += 1
    return o


def fcurve_count(act):
    n = len(getattr(act, "fcurves", []) or [])
    for lay in getattr(act, "layers", []):
        for st in getattr(lay, "strips", []):
            for cb in getattr(st, "channelbags", []):
                n += len(cb.fcurves)
    return n


def main():
    o = args()
    R = {"master": o["master"], "motion": o["motion"], "clip_name": o["name"]}

    bpy.ops.wm.open_mainfile(filepath=o["master"])
    arm = next(x for x in bpy.data.objects if x.type == "ARMATURE")
    sc = bpy.context.scene
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    # ---- import the motion, keep only its action -------------------------
    before_objs = {x.name for x in bpy.data.objects}
    before_acts = {x.name for x in bpy.data.actions}
    bpy.ops.import_scene.gltf(filepath=o["motion"])
    new_acts = [x for x in bpy.data.actions if x.name not in before_acts]
    new_objs = [x for x in bpy.data.objects if x.name not in before_objs]
    if not new_acts:
        sys.exit("no action found in " + o["motion"])
    for x in new_acts:
        print("  candidate action %-30s range %.1f..%.1f"
              % (x.name, x.frame_range[0], x.frame_range[1]))
    raw = max(new_acts, key=lambda x: x.frame_range[1] - x.frame_range[0])
    raw_name = "__raw_motion"
    raw.name = raw_name
    raw.use_fake_user = True
    # Capture names as STRINGS first: deleting the imported armature purges the
    # action it owned and invalidates any live reference held in new_acts.
    stale = [x.name for x in new_acts if x.name != raw_name]
    for ob in new_objs:
        bpy.data.objects.remove(ob, do_unlink=True)
    for n in stale:
        x = bpy.data.actions.get(n)
        if x is not None:
            bpy.data.actions.remove(x)

    def use(act):
        arm.animation_data_create()
        arm.animation_data.action = act
        if hasattr(arm.animation_data, "action_slot") and act.slots:
            arm.animation_data.action_slot = act.slots[0]
        arm.data.pose_position = "POSE"

    raw = bpy.data.actions[raw_name]
    use(raw)
    f0, f1 = int(raw.frame_range[0]), int(raw.frame_range[1])
    R["raw_range"] = [f0, f1]
    R["raw_duration_sec"] = round((f1 - f0) / sc.render.fps, 3)

    # ---- locate the active window ----------------------------------------
    prop = bpy.data.objects.get(o["prop"])
    profile = []
    if o["auto"]:
        if prop is None:
            sys.exit("--auto needs --prop naming a mesh in the master (got %r)" % o["prop"])
        prev = None
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            ev = prop.evaluated_get(dg)
            me = ev.to_mesh()
            c = np.array([list(ev.matrix_world @ v.co) for v in me.vertices]).mean(0)
            ev.to_mesh_clear()
            d = 0.0 if prev is None else float(np.linalg.norm(c - prev)) * 100
            prev = c
            profile.append((f, round(d, 2)))
        peak = max(d for _, d in profile) or 1.0
        thr = peak * float(o["thresh"])
        active = [f for f, d in profile if d > thr]
        if not active:
            sys.exit("no frame exceeded %.1f%% of peak travel" % (float(o["thresh"]) * 100))
        # Take the contiguous run CONTAINING THE PEAK, not first-to-last active
        # frame. Meshy clips hold several beats: on Cross, first-to-last spanned
        # 13..138 (5.2s) because it swallowed a second, unrelated move at
        # 109..133. Walking out from the peak and stopping at a real gap
        # isolates the one beat that was asked for -> 13..31, 0.75s
        # (a hand cut of 13..37 kept a little more recovery tail; --from/--to
        # overrides when the auto window trims the settle too tightly).
        GAP = 4          # frames below threshold tolerated inside one beat
        by_frame = dict(profile)
        pk = max(profile, key=lambda t: t[1])[0]
        a0 = a1 = pk
        gap = 0
        f = pk
        while f > f0:
            f -= 1
            if by_frame.get(f, 0.0) > thr:
                a0 = f; gap = 0
            else:
                gap += 1
                if gap > GAP:
                    break
        gap = 0
        f = pk
        while f < f1:
            f += 1
            if by_frame.get(f, 0.0) > thr:
                a1 = f; gap = 0
            else:
                gap += 1
                if gap > GAP:
                    break
        R["peak_frame"] = pk
        R["profile_peak_cm_per_frame"] = round(peak, 2)
        R["auto_window"] = [a0, a1]
    else:
        a0, a1 = int(o["from"]), int(o["to"])
        R["auto_window"] = None
    if o["from"] is not None and o["to"] is not None:
        a0, a1 = int(o["from"]), int(o["to"])
    R["window"] = [a0, a1]
    R["window_frames"] = a1 - a0 + 1
    R["window_duration_sec"] = round((a1 - a0) / sc.render.fps, 3)
    print("  window %d..%d  = %d frames = %.2fs"
          % (a0, a1, a1 - a0 + 1, (a1 - a0) / sc.render.fps))

    # ---- sample the window, rebased to frame 0 ---------------------------
    pose = {}
    for f in range(a0, a1 + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        pose[f] = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(),
                             pb.scale.copy()) for pb in arm.pose.bones}

    # keep any previous clip of this name rather than destroying it
    if o["name"] in bpy.data.actions:
        k = 1
        while "%s_prev_%d" % (o["name"], k) in bpy.data.actions:
            k += 1
        old = "%s_prev_%d" % (o["name"], k)
        bpy.data.actions[o["name"]].name = old
        R["previous_clip_renamed_to"] = old

    new = bpy.data.actions.new(o["name"])
    new.use_fake_user = True
    arm.animation_data.action = new
    if hasattr(arm.animation_data, "action_slot"):
        try:
            arm.animation_data.action_slot = new.slots.new(id_type="OBJECT", name="Legacy")
        except Exception:
            pass
    for f in range(a0, a1 + 1):
        nf = f - a0
        sc.frame_set(nf)
        for pb in arm.pose.bones:
            l, r, s = pose[f][pb.name]
            pb.location, pb.rotation_quaternion, pb.scale = l.copy(), r.copy(), s.copy()
        bpy.context.view_layer.update()
        for pb in arm.pose.bones:
            pb.keyframe_insert("location", frame=nf)
            pb.keyframe_insert("rotation_quaternion", frame=nf)
            pb.keyframe_insert("scale", frame=nf)

    # Keep the untrimmed motion under a readable name: re-cutting the window
    # later then costs nothing and needs no new Meshy call.
    if raw_name in bpy.data.actions:
        bpy.data.actions[raw_name].name = o["name"] + "_raw_untrimmed"
        R["raw_kept_as"] = o["name"] + "_raw_untrimmed"
    for act in bpy.data.actions:
        act.use_fake_user = True
    if "idle" in bpy.data.actions:
        use(bpy.data.actions["idle"])

    body = next((x for x in bpy.data.objects if x.type == "MESH"
                 and not x.name.endswith("_Held")), None)
    R["fps"] = sc.render.fps
    R["fcurves"] = fcurve_count(new)
    R["bones"] = len(arm.data.bones)
    R["actions"] = sorted(x.name for x in bpy.data.actions)
    R["meshes"] = [x.name for x in bpy.data.objects if x.type == "MESH"]
    R["prop_groups"] = {x.name: [g.name for g in x.vertex_groups]
                        for x in bpy.data.objects
                        if x.type == "MESH" and x.name.endswith("_Held")}
    if body:
        R["body_verts"] = len(body.data.vertices)
    if profile:
        R["travel_profile"] = profile

    if o["out_blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=o["out_blend"])
    if o["out_glb"]:
        bpy.ops.export_scene.gltf(filepath=o["out_glb"], export_format="GLB",
                                  export_animations=True, use_selection=False)
        R["exported_glb"] = o["out_glb"]
    if o["json"]:
        json.dump(R, open(o["json"], "w"), indent=1)
    print(json.dumps({k: v for k, v in R.items() if k != "travel_profile"}, indent=1))


if __name__ == "__main__":
    main()
