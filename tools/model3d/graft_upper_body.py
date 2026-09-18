"""Combine a static weapon pose with another clip's limb motion, offline.

This is the baked equivalent of a shooter's layered blend per bone: lower body
runs locomotion, upper body independently holds a weapon pose, so one walk
cycle plus one aim pose covers walking-while-aiming. Model3DSprite drives a
plain AnimationPlayer with no blend tree, so the combination is baked into its
own clip rather than mixed live.

THE GRAFT MUST BE IN WORLD SPACE, and doing it in local space is the trap.
Meshy authors every clip with its own arbitrary root orientation (measured on
Headhunter, Hips euler was (-81, -52, 92) in `aim` versus (52, -124, 48) in
`walk`). Bone locals are relative to the parent, so pasting the aim pose's
LOCAL rotations under the walk clip's pelvis rotates the whole upper body by
however far those two roots differ — the rifle swung down until the firing
hand sat at hip height, while every individual bone value was "correct."
Inverting it (aim as the base, walk's leg locals grafted on) fails the same
way in mirror image: the legs splayed and the feet lifted 20-40cm off the
ground, because "down" for the legs is defined by the pelvis they hang from.

Either direction needs a correction at the junction, so this applies it to
whichever side is smaller: the lower body is left ENTIRELY untouched (hips
translation, hips rotation, both legs — so the walk is exactly the authored
walk and the feet stay planted), and the split bone's WORLD rotation is set to
the static pose's world rotation, with its descendants keeping the static
pose's locals so the torso shape is exact.

Two things fall out of that, both wanted. The weapon holds precisely the
orientation it has in the static pose, every frame, so the clip inherits that
pose's already-verified clip_yaw_bias_deg rather than needing its own
calibration, and the barrel does not sway over the stride. And the waist ends
up counter-rotating against the hips by however much the pelvis swings, which
is exactly what a person does walking with a weapon held on target.

  blender --background --python graft_upper_body.py -- \
      --model "assets/3d pipeline/hero/headhunter/headhunter.glb" \
      --static aim --motion walk --split Spine02 --name walk_aim \
      [--static-frame 1] [--force]
"""
import sys

import bpy
from mathutils import Matrix

DEFAULTS = {
    "static": "aim",
    "motion": "walk",
    "split": "Spine02",   # this bone and everything under it comes from `static`
    "name": "walk_aim",
    "static_frame": 1,
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(DEFAULTS)
    o["model"], o["out"], o["force"] = None, None, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--force":
            o["force"] = True
            i += 1
            continue
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:].replace("-", "_"), argv[i + 1]
            if k == "static_frame":
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


def subtree(bone):
    out = [bone.name]
    for c in bone.children:
        out.extend(subtree(c))
    return out


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")

    static = bpy.data.actions.get(o["static"])
    motion = bpy.data.actions.get(o["motion"])
    if static is None or motion is None:
        print("missing clip(s): %r=%s %r=%s"
              % (o["static"], static, o["motion"], motion))
        return

    split = o["split"]
    if split not in arm.data.bones:
        print("no bone %r" % split)
        return
    upper = set(subtree(arm.data.bones[split]))
    print("upper body (%d bones from %r): %s"
          % (len(upper), o["static"], ", ".join(sorted(upper))))

    existing = bpy.data.actions.get(o["name"])
    if existing and not o["force"]:
        print("clip %r already exists. Use --force." % o["name"])
        return

    # Static pose: the split bone's WORLD rotation (armature space), plus its
    # descendants' locals so the torso keeps its exact authored shape.
    assign(arm, static)
    bpy.context.scene.frame_set(o["static_frame"])
    bpy.context.view_layer.update()
    split_world_rot = arm.pose.bones[split].matrix.to_3x3().copy()
    upper_locals = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(),
                              pb.scale.copy())
                    for pb in arm.pose.bones if pb.name in upper and pb.name != split}

    # The walk, sampled in full BEFORE anything is written.
    assign(arm, motion)
    lo, hi = motion.frame_range
    lo, hi = int(lo), int(hi)
    per_frame = {}
    for f in range(lo, hi + 1):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        per_frame[f] = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(),
                                  pb.scale.copy())
                        for pb in arm.pose.bones}

    if existing:
        bpy.data.actions.remove(existing)
    action = bpy.data.actions.new(o["name"])
    action.use_fake_user = True
    assign(arm, action)

    for f in range(lo, hi + 1):
        bpy.context.scene.frame_set(f)
        # 1. Whole body = the walk, untouched.
        for pb in arm.pose.bones:
            loc, rot, scl = per_frame[f][pb.name]
            pb.location, pb.rotation_quaternion, pb.scale = loc.copy(), rot.copy(), scl.copy()
        bpy.context.view_layer.update()

        # 2. Pin the split bone's WORLD rotation to the static pose's, keeping
        #    the translation it inherits from the walking pelvis.
        pb = arm.pose.bones[split]
        pb.matrix = Matrix.Translation(pb.matrix.translation) @ split_world_rot.to_4x4()
        bpy.context.view_layer.update()

        # 3. Descendants keep the static pose's locals, so the torso, arms and
        #    weapon are shaped exactly as they are in that pose.
        for name, (loc, rot, scl) in upper_locals.items():
            t = arm.pose.bones[name]
            t.location, t.rotation_quaternion, t.scale = loc.copy(), rot.copy(), scl.copy()
        bpy.context.view_layer.update()

        for b in arm.pose.bones:
            b.keyframe_insert("location", frame=f)
            b.keyframe_insert("rotation_quaternion", frame=f)
            b.keyframe_insert("scale", frame=f)

    action["_grafted"] = "%s+%s" % (o["static"], o["motion"])
    print("built %r: %d frames, lower body from %r, %s-and-above pinned to %r"
          % (o["name"], hi - lo + 1, o["motion"], split, o["static"]))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
