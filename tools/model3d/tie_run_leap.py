"""Tie a fast-run clip into a running-jump clip to build a "sprint and leap"
ultimate. Blender script.

Built for Bloodhound's Pounce: "he runs and leaps at someone" (user spec,
2026-09-06) — Meshy generated the two halves as separate clips (`run`,
12 frames, and `run_and_jump`, 56 frames) with no way to ask it for one
continuous action, since each generation is a single text prompt. This
concatenates them into one clip instead of writing a new animation from
scratch: both halves are already good full-body motion, they just need
joining.

STRUCTURE: `run` plays for `--repeats` cycles (a windup — several strides at
full sprint before the leap commits, so the leap doesn't look like it fires
from a standing start), then blends over `--blend` frames into `run_and_jump`,
which then plays to its end untouched.

THE BLEND is a straight per-bone quaternion/location slerp between the last
sampled run frame and the first jump frame, growing from 0 to 1 across the
window — the same technique make_ult_animation.py uses for Bouncer's gather
pose, just applied continuously across a whole window of frames instead of at
a single beat, because both source poses here are already full clips rather
than single sampled frames.

  blender --background --python tie_run_leap.py -- \
      --model "assets/3d pipeline/hero/bloodhound/bloodhound.glb" \
      [--windup run] [--leap run_and_jump] [--name ult]
      [--repeats 2] [--blend 6] [--out other.glb] [--force]
"""
import sys
import bpy

DEFAULTS = {
    "windup": "run",
    "leap": "run_and_jump",
    "name": "ult",
    "repeats": 2,   # windup cycles before the leap commits
    "blend": 6,     # frames to cross-fade from windup into leap
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
            k, v = a[2:], argv[i + 1]
            if k in ("repeats", "blend"):
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


def sample(arm, action, frame):
    assign(arm, action)
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    return {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy())
            for pb in arm.pose.bones}


def write_pose(arm, out_action, pose, f):
    # MUST re-assign before every write: sample() leaves `arm`'s active action
    # pointed at whichever source clip it just read, and keyframe_insert()
    # writes into THAT action, not into whichever one you meant. Measured the
    # hard way: without this, the windup/blend/leap poses landed back inside
    # the original `run`/`run_and_jump` actions instead of the new `ult` one,
    # silently corrupting both source clips while `ult` stayed empty.
    assign(arm, out_action)
    for pb in arm.pose.bones:
        loc, rot, scl = pose[pb.name]
        pb.location, pb.rotation_quaternion, pb.scale = loc, rot, scl
        pb.keyframe_insert("location", frame=f)
        pb.keyframe_insert("rotation_quaternion", frame=f)
        pb.keyframe_insert("scale", frame=f)


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")

    if bpy.data.actions.get(o["name"]) and not o["force"]:
        print("clip %r already exists. Use --force to rebuild." % o["name"])
        return

    windup = bpy.data.actions.get(o["windup"])
    leap = bpy.data.actions.get(o["leap"])
    if windup is None or leap is None:
        print("missing source clip(s): windup=%r leap=%r (have: %s)"
              % (o["windup"], leap, ", ".join(sorted(a.name for a in bpy.data.actions))))
        return

    w_lo, w_hi = windup.frame_range
    w_lo, w_hi = int(w_lo), int(w_hi)
    w_len = w_hi - w_lo
    l_lo, l_hi = leap.frame_range
    l_lo, l_hi = int(l_lo), int(l_hi)

    old = bpy.data.actions.get(o["name"])
    if old:
        bpy.data.actions.remove(old)
    out = bpy.data.actions.new(o["name"])
    out.use_fake_user = True

    f = 1
    # 1. Windup: the run cycle repeated whole, back to back.
    for rep in range(o["repeats"]):
        for wf in range(w_lo, w_hi):   # exclude wf==w_hi: it's the same pose as w_lo (loop seam)
            pose = sample(arm, windup, wf)
            write_pose(arm, out, pose, f)
            f += 1
    last_windup_pose = sample(arm, windup, w_hi - 1)

    # 2. Blend: slerp from the windup's last stride into the leap's first frame,
    #    growing over `blend` frames so the transition doesn't pop.
    first_leap_pose = sample(arm, leap, l_lo)
    blend_start = f
    for i in range(o["blend"]):
        t = (i + 1) / o["blend"]
        pose = {}
        for name in last_windup_pose:
            al, ar, asc = last_windup_pose[name]
            bl, br, bsc = first_leap_pose[name]
            pose[name] = (al.lerp(bl, t), ar.slerp(br, t), asc.lerp(bsc, t))
        write_pose(arm, out, pose, f)
        f += 1

    # 3. The leap, played through untouched from just after its first frame
    #    (already covered by the blend) to its end.
    for lf in range(l_lo + 1, l_hi + 1):
        pose = sample(arm, leap, lf)
        write_pose(arm, out, pose, f)
        f += 1

    print("built %r: %d frames (windup x%d = %d frames, blend %d-%d, leap to %d)"
          % (o["name"], f - 1, o["repeats"], o["repeats"] * w_len,
             blend_start, blend_start + o["blend"] - 1, f - 1))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
