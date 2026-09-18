"""Cut a clip short partway through and ease the remainder back to its own
start pose, instead of hard-stopping mid-motion. Blender script.

Built for Bloodhound's `attack` (2026-09-07, user spec): the clip as generated
is a 4-hit right-arm combo with mirror_swipe_to_offhand.py's offset copy
layered onto the left arm, so a single AUTO-ATTACK plays through what reads as
an 8-strike flurry (right-left-right-left...). The ask was "use the current
animation but only the first 2 swipes — quick right swipe then left swipe —
made to look natural", i.e. keep frames 0..--end (right's first punch +
its mirrored left echo) and drop everything after, but a raw truncation at
--end just freezes on a mid-swing pose the instant the clip loops back to
idle — this blends it back to the clip's OWN frame-0 pose instead, over
--tail frames, so the cut reads as the swipe settling rather than snapping.

WHY BLEND TO FRAME 0 SPECIFICALLY, not a generic rest/idle pose: frame 0 of
`attack` is already the pose the clip was authored to begin from (see
tie_run_leap.py's own use of "blend into the next clip" for the same
reasoning) — settling there guarantees the loop back into idle has nowhere
left to jump.

METHOD mirrors tie_run_leap.py: sample every pose bone's rotation_quaternion
(and location, for any bone that has it — root/hip motion) at the kept end
frame and at frame 0, delete keyframes past --end, then keyframe a slerp/lerp
from the end-frame pose to the frame-0 pose across the tail window.

  blender --background --python trim_clip_tail.py -- \
      --model "assets/3d pipeline/hero/bloodhound/bloodhound.glb" \
      --clip attack --end 24 --tail 8 [--out other.glb] [--force]

NOT IDEMPOTENT — re-running re-derives the tail from whatever's currently at
--end, which is fine on a fresh export but will re-blend an already-blended
tail if pointed at one.
"""
import sys
import bpy
from mathutils import Quaternion, Vector

DEFAULTS = {
    "clip": "attack",
    "end": 24,
    "tail": 8,
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(DEFAULTS)
    o["model"], o["out"] = None, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:], argv[i + 1]
            if k in ("end", "tail"):
                v = int(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def fcurves_of(action):
    """Blender 4.4+ actions are slotted: layers -> strips -> channelbags."""
    if hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for cb in getattr(strip, "channelbags", []) or []:
                    for fc in cb.fcurves:
                        yield fc
    else:
        for fc in action.fcurves:
            yield fc


def ease(t):
    # Smoothstep — starts and ends the blend at zero velocity so it reads as
    # a settle, not a linear slide.
    return t * t * (3.0 - 2.0 * t)


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")

    action = bpy.data.actions.get(o["clip"])
    if action is None:
        print("no clip named %r (have: %s)"
              % (o["clip"], ", ".join(sorted(a.name for a in bpy.data.actions))))
        return

    ad = arm.animation_data or arm.animation_data_create()
    ad.action = action
    if hasattr(ad, "action_slot") and getattr(action, "slots", None):
        ad.action_slot = action.slots[0]

    lo, hi = action.frame_range
    lo = int(lo)
    cut = o["end"]
    tail = o["tail"]
    if cut >= hi:
        print("--end %d is past the clip's own end (%d) — nothing to trim" % (cut, hi))
        return

    bone_names = [pb.name for pb in arm.pose.bones]

    def sample_pose(frame):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        rot, loc = {}, {}
        for name in bone_names:
            pb = arm.pose.bones[name]
            rot[name] = pb.rotation_quaternion.copy()
            loc[name] = pb.location.copy()
        return rot, loc

    rest_rot, rest_loc = sample_pose(lo)
    cut_rot, cut_loc = sample_pose(cut)

    # Drop everything past the cut on every fcurve in the action (any bone,
    # any channel) so nothing from the dropped combo swings survives.
    removed = 0
    for fc in list(fcurves_of(action)):
        # Remove back-to-front — removing by reference while iterating
        # forward (even over a snapshot list) invalidates later references
        # into the same fcurve's internal keyframe array.
        pts = list(fc.keyframe_points)
        for k in reversed(pts):
            if k.co[0] > cut:
                fc.keyframe_points.remove(k)
                removed += 1
        fc.update()

    for t in range(1, tail + 1):
        frame = cut + t
        a = ease(t / float(tail))
        bpy.context.scene.frame_set(frame)
        for name in bone_names:
            pb = arm.pose.bones[name]
            pb.rotation_quaternion = cut_rot[name].slerp(rest_rot[name], a)
            pb.location = cut_loc[name].lerp(rest_loc[name], a)
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("location", frame=frame)

    lo2, hi2 = action.frame_range
    print("trimmed '%s': kept 0-%d, removed %d keys past the cut, added %d-frame settle tail -> new range %.1f-%.1f"
          % (o["clip"], cut, removed, tail, lo2, hi2))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
