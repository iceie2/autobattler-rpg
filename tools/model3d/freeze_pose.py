"""Freeze one frame of an existing clip into a new static clip. Blender script.

For characters whose Meshy export has no dedicated idle. Not every generation
run gets one — Bloodhound's did not — and regenerating costs a Meshy credit
and a review pass for something the game only ever holds still on. A single
frame from an existing cycle, chosen where the pose already reads as neutral
(feet together, arms relaxed), is a legitimate stand-in and can be swapped for
a real idle later without touching anything else.

FRAME CHOICE. Not guessed: for Bloodhound, every frame of `walk_slow` (25.6
frames) was sampled for the distance between the two feet — the number that
actually tells you "mid-stride" from "standing." Frame 1 measured 0.39, the
tightest stance in the whole cycle (peak stride was 0.66 at frame 8), so that
is the frame this was built from.

The output holds for a couple of frames rather than one, because a
single-keyframe action has a frame_range of (f, f) and several places in this
pipeline (blender_review.py's `_action_range`, the merge's frame math) assume
a clip spans more than an instant.

  blender --background --python freeze_pose.py -- \
      --model "assets/3d pipeline/hero/bloodhound/bloodhound.glb" \
      --source walk_slow --frame 1 [--name idle] [--hold 4]
      [--out other.glb] [--force]
"""
import sys
import bpy

DEFAULTS = {
    "source": "walk_slow",
    "frame": 1,
    "name": "idle",
    "hold": 4,   # frames the frozen pose spans, for tools that need > an instant
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
            if k in ("frame", "hold"):
                v = int(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def fcurves_of(action):
    if hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for cb in getattr(strip, "channelbags", []) or []:
                    for fc in cb.fcurves:
                        yield fc
    else:
        for fc in action.fcurves:
            yield fc


def channelbag(action):
    for layer in action.layers:
        for strip in layer.strips:
            for cb in getattr(strip, "channelbags", []) or []:
                return cb
    return None


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

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")

    if bpy.data.actions.get(o["name"]) and not o["force"]:
        print("clip %r already exists. Use --force to rebuild." % o["name"])
        return

    src = bpy.data.actions.get(o["source"])
    if src is None:
        print("no clip named %r (have: %s)"
              % (o["source"], ", ".join(sorted(a.name for a in bpy.data.actions))))
        return
    assign(arm, src)
    bpy.context.scene.frame_set(o["frame"])
    bpy.context.view_layer.update()
    pose = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy())
            for pb in arm.pose.bones}

    old = bpy.data.actions.get(o["name"])
    if old:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(o["name"])
    action.use_fake_user = True
    assign(arm, action)

    for pb in arm.pose.bones:
        loc, rot, scl = pose[pb.name]
        pb.location, pb.rotation_quaternion, pb.scale = loc, rot, scl
        for f in (1, o["hold"]):
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("scale", frame=f)

    print("froze %r frame %d -> new static clip %r (%d-%d)"
          % (o["source"], o["frame"], o["name"], 1, o["hold"]))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
