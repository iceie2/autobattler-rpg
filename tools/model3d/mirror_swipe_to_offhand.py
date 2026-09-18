"""Copy one arm's swing onto the other, mirrored and time-offset. Blender
script.

Built for Bloodhound's `attack`: the right arm's swipe is good, the left
arm's motion in the same clip is comparatively weak, and the ask was "make
the left mimic the right, just offset so they don't overlap" (user,
2026-09-06) — a two-fisted swipe instead of a one-sided one.

WHY A MIRROR, NOT A COPY. The left and right arm bones are NOT interchangeable
— naively copying RightArm's rotation onto LeftArm swings it the wrong way,
because the two sides' rest orientations are reflections of each other, not
copies. Measured on this rig: RightArm's and LeftArm's rest-local matrices
match to ~2 decimal places under `S @ R @ S` with `S = diag(-1, 1, 1)` (a
reflection through the character's own sagittal plane). Given that, a pose
DELTA (the `rotation_quaternion` Blender stores per bone — itself already a
delta from rest, not an absolute orientation) mirrors the same way: convert it
to a matrix, conjugate by the same `S`, convert back. This is done with an
actual matrix conjugation in the script, not a hand-derived quaternion sign
flip, because guessing the sign pattern wrong is a silent failure — the arm
would swing somewhere plausible-looking but not the true mirror image, and
nothing would flag it.

THE OFFSET is a plain time-shift when sourcing the right arm's pose (reading
frame `f - offset` instead of `f`), clamped to the clip's own frame range so
the ends hold rather than wrapping into garbage. This staggers the two arms'
swipes without changing either one's own shape.

  blender --background --python mirror_swipe_to_offhand.py -- \
      --model "assets/3d pipeline/hero/bloodhound/bloodhound.glb" \
      --clip attack --offset 10
      [--bones RightShoulder,RightArm,RightForeArm,RightHand]
      [--out other.glb] [--force]

NOT IDEMPOTENT — running it twice overwrites the left side with a mirror of
whatever the right side currently is, which is fine to re-run, but re-running
after some OTHER edit to the left arm will discard that edit.
"""
import sys
import bpy
from mathutils import Matrix

DEFAULTS = {
    "clip": "attack",
    "offset": 10,
    "bones": "RightShoulder,RightArm,RightForeArm,RightHand",
}
# Reflection through the character's sagittal (left-right) plane. Verified
# against this rig's own rest pose — see docstring — not a generic assumption.
MIRROR = Matrix.Diagonal((-1.0, 1.0, 1.0))


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(DEFAULTS)
    o["model"], o["out"] = None, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:], argv[i + 1]
            if k == "offset":
                v = int(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def mirror_quat(q):
    m = q.to_matrix()
    m2 = MIRROR @ m @ MIRROR
    return m2.to_quaternion()


def right_to_left(name):
    if name.startswith("Right"):
        return "Left" + name[len("Right"):]
    raise ValueError("not a Right-side bone: %r" % name)


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return
    r_bones = [b for b in o["bones"].split(",") if b]

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
    lo, hi = int(lo), int(hi)

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

    for rname in r_bones:
        lname = right_to_left(rname)
        if lname not in arm.pose.bones:
            print("  ! no bone named %s, skipping" % lname)
            continue
        # Clear the existing left-side rotation first. Densely re-keying every
        # integer frame would otherwise leave any of the ORIGINAL clip's own
        # keys that happen to sit off-integer (this pipeline has seen 0.8-frame
        # import artifacts before) still in the curve, causing a tiny glitch
        # right where they land.
        lpath = 'pose.bones["%s"].rotation_quaternion' % lname
        for fc in list(fcurves_of(action)):
            if fc.data_path == lpath:
                fc.keyframe_points.clear()
        for f in range(lo, hi + 1):
            src_f = max(lo, min(hi, f - o["offset"]))
            bpy.context.scene.frame_set(src_f)
            bpy.context.view_layer.update()
            rq = arm.pose.bones[rname].rotation_quaternion.copy()
            lq = mirror_quat(rq)
            bpy.context.scene.frame_set(f)
            pb = arm.pose.bones[lname]
            pb.rotation_quaternion = lq
            pb.keyframe_insert("rotation_quaternion", frame=f)
        print("  %s -> %s, offset %d frames, %d keys" % (rname, lname, o["offset"], hi - lo + 1))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
