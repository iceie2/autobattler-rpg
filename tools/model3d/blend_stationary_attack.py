"""Replace a clip's LOWER-body motion with a frozen static pose, keeping its
UPPER-body motion untouched. Blender script.

Built for Headhunter: his only "shooting" source material Meshy generated is
Walk_Backward_While_Shooting_inplace — a walk-in-place cycle. Since combat
never actually lets a unit attack while moving (is_moving must be false
before a swing/shot fires — see auto_battle_manager.gd's `in_range and not
unit.is_moving` gate), that walking motion serves no real gameplay state; it
only ever plays while he's standing still, so it just reads as marching in
place while firing (user report 2026-09-07).

This is a standard partial-body blend: the LOWER body (hips + legs) is held
at a single frozen reference pose for the whole clip, while the UPPER body
(spine up through the hands and head — the actual aim/recoil motion) keeps
playing its original per-frame animation untouched. The result is a
plausible planted stance that still recoils and aims with the source clip's
own upper-body motion — no new source material needed, no hand-authored
animation, just recombining what Meshy already gave us.

  blender --background --python blend_stationary_attack.py -- \
      --model "assets/3d pipeline/hero/headhunter/headhunter.glb" \
      --clip attack --pose-source idle --pose-frame 0
      [--out other.glb] [--force]
"""
import sys
import bpy

DEFAULTS = {
    "clip": "attack",
    "pose_source": "attack",
    "pose_frame": 0,
    # Hips deliberately excluded: it's the skeleton ROOT that Spine01 (kept
    # animating, upper body) is parented off. Freezing Hips to a DIFFERENT
    # clip's orientation (idle) diverges from what Spine01's own per-frame
    # LOCAL rotation was authored against, and the coat/cloak mesh — skinned
    # across both bones — tore into a huge warped blade shape at the waist
    # (user report 2026-09-08, screenshot showed it near his legs/crotch,
    # mistaken for a misplaced weapon). Using pose_source=attack (this SAME
    # clip's own frame 0) instead of idle keeps Hips's frozen orientation
    # consistent with Spine01's continuing motion, and leaving Hips out of
    # `lower_body` entirely removes the mismatch at its root.
    "lower_body": "LeftUpLeg,LeftLeg,LeftFoot,LeftToeBase,"
                  "RightUpLeg,RightLeg,RightFoot,RightToeBase",
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(DEFAULTS)
    o["model"], o["out"], o["force"] = None, None, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--force":
            o["force"] = True; i += 1; continue
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:].replace("-", "_"), argv[i + 1]
            if k == "pose_frame":
                v = int(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def assign(arm, action):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = action
    if hasattr(ad, "action_slot") and getattr(action, "slots", None):
        ad.action_slot = action.slots[0]


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return
    lower = set(b for b in o["lower_body"].split(",") if b)

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")

    src_act = bpy.data.actions.get(o["clip"])
    pose_act = bpy.data.actions.get(o["pose_source"])
    if src_act is None or pose_act is None:
        print("missing clip(s): %r=%s %r=%s" % (o["clip"], src_act, o["pose_source"], pose_act))
        return

    marker = "_lower_frozen_from"
    if src_act.get(marker) == o["pose_source"] and not o["force"]:
        print("'%s' already has its lower body frozen from %r. Use --force to redo."
              % (o["clip"], o["pose_source"]))
        return

    # Sample the frozen reference pose ONCE, for every bone in the rig (not
    # just lower_body) — upper-body bones need their own attack-clip values
    # read back out below anyway, but this is the simplest way to capture a
    # full, valid pose dict without special-casing.
    assign(arm, pose_act)
    bpy.context.scene.frame_set(o["pose_frame"])
    bpy.context.view_layer.update()
    frozen = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy())
              for pb in arm.pose.bones}

    lo, hi = src_act.frame_range
    lo, hi = int(lo), int(hi)

    # Sample the attack clip's own per-frame pose for every bone, at every
    # frame, BEFORE writing anything — writing into src_act while also
    # reading it back per-frame would read our own just-written frozen values
    # on the next iteration instead of the clip's real original motion.
    assign(arm, src_act)
    per_frame_upper = {}
    for f in range(lo, hi + 1):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        per_frame_upper[f] = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy())
                               for pb in arm.pose.bones if pb.name not in lower}

    # Now overwrite: lower body frozen at every frame, upper body keeps its
    # sampled original motion. Clearing existing keys first so this is safe
    # to re-run (--force) without stacking old keyframes underneath.
    assign(arm, src_act)

    def fcurves_of(act):
        if hasattr(act, "layers"):
            for layer in act.layers:
                for strip in layer.strips:
                    for cb in getattr(strip, "channelbags", []) or []:
                        for fc in cb.fcurves:
                            yield fc
        else:
            for fc in act.fcurves:
                yield fc

    for fc in list(fcurves_of(src_act)):
        # pose.bones["Name"].prop -> Name
        path = fc.data_path
        if 'pose.bones["' in path:
            bname = path.split('pose.bones["')[1].split('"]')[0]
            if bname in lower:
                fc.keyframe_points.clear()

    for f in range(lo, hi + 1):
        for pb in arm.pose.bones:
            if pb.name in lower:
                loc, rot, scl = frozen[pb.name]
            else:
                loc, rot, scl = per_frame_upper[f][pb.name]
            pb.location, pb.rotation_quaternion, pb.scale = loc, rot, scl
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("scale", frame=f)

    src_act[marker] = o["pose_source"]
    print("froze lower body (%d bones) on '%s' from '%s' frame %d, kept upper body's own motion (%d frames)"
          % (len(lower), o["clip"], o["pose_source"], o["pose_frame"], hi - lo + 1))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
