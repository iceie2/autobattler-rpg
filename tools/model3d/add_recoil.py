"""Build a rifle-recoil clip from a STATIC aim pose. Blender script.

Meshy generated an aim pose for Headhunter but no shooting animation, so
`attack` was literally a byte-for-byte copy of `aim` — the character held
still and a projectile appeared, with nothing on the body selling the shot.
This bakes the missing beat.

WHAT RECOIL ACTUALLY IS, and why it rotates the SPINE and not the arms: the
rifle is skinned 100% to one hand bone, but it is held in BOTH hands. Rotating
the gun arm alone would swing the weapon out of the other hand — the off hand
would visibly detach from the forestock. The only way to move gun and both
hands as one rigid unit is to rotate a bone ABOVE both shoulders. On this rig
that chain is Hips -> Spine02 -> Spine01 -> Spine -> {LeftShoulder,
RightShoulder}, so `Spine` carries the whole firing platform, and the two
lower spine bones let the torso absorb the kick instead of hinging at one
joint. Weights are applied ROOT-OUTWARD so they accumulate down the chain and
sum to the requested muzzle rise.

The rotation axis is derived from where the barrel actually points, so the
muzzle climbs in the vertical plane it is aimed along rather than some fixed
world axis. Pass --barrel-yaw as the VERIFIED barrel heading in Godot degrees
(that is the negation of the calibrated clip_yaw_bias_deg — see aim_yaw.py,
and do NOT take it from that tool's own geometry guess, which a weapon sling
skews badly).

Timing is the classic shape: snap out over a frame or two, ease back over
several. Author it at a comfortable frame count here and compress the finished
clip with retime_clip.py rather than trying to keyframe a 3-frame action.

  blender --background --python add_recoil.py -- \
      --model "assets/3d pipeline/hero/headhunter/headhunter.glb" \
      --source aim --name attack --barrel-yaw 13.0 \
      [--angle 12] [--kick 2] [--settle 8] [--force]
"""
import math
import sys

import bpy
from mathutils import Matrix, Vector

DEFAULTS = {
    "source": "aim",
    "name": "attack",
    "barrel_yaw": 0.0,   # Godot degrees; = -clip_yaw_bias_deg
    "angle": 12.0,       # degrees of muzzle rise at peak
    "kick": 2,           # frames to reach peak
    "settle": 8,         # frames to return to the aim pose
    # Root-outward, summing to 1.0: most of the rise at the top of the chain,
    # the rest absorbed lower down so the whole torso participates.
    "weights": "Spine02:0.15,Spine01:0.30,Spine:0.55",
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
            if k in ("kick", "settle"):
                v = int(v)
            elif k in ("angle", "barrel_yaw"):
                v = float(v)
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


def recoil_curve(f, kick, settle):
    """0 -> 1 fast, then ease back to 0. The asymmetry IS the shot."""
    if f <= 0:
        return 0.0
    if f <= kick:
        return (f / float(kick)) ** 0.55        # snap out
    t = (f - kick) / float(max(settle, 1))
    if t >= 1.0:
        return 0.0
    return (1.0 - t) ** 2 * (1.0 + 0.25 * math.sin(t * math.pi * 2.0))


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return

    weights = []
    for part in o["weights"].split(","):
        if not part.strip():
            continue
        name, w = part.split(":")
        weights.append((name.strip(), float(w)))

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")

    src = bpy.data.actions.get(o["source"])
    if src is None:
        print("no clip %r (have: %s)"
              % (o["source"], ", ".join(sorted(a.name for a in bpy.data.actions))))
        return
    for name, _ in weights:
        if name not in arm.pose.bones:
            print("no bone %r on this rig" % name)
            return

    # Sample the static aim pose once.
    assign(arm, src)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    pose = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy())
            for pb in arm.pose.bones}

    # Barrel heading: Godot yaw -> Blender horizontal direction.
    # Godot (x, z) = (sin y, cos y); Blender (x, y) = (gltf.x, -gltf.z).
    gy = math.radians(o["barrel_yaw"])
    barrel_h = Vector((math.sin(gy), -math.cos(gy), 0.0)).normalized()
    up = Vector((0.0, 0.0, 1.0))
    axis = barrel_h.cross(up).normalized()   # +angle raises the muzzle
    print("barrel heading (blender): (%.3f, %.3f)   rotation axis: (%.3f, %.3f, %.3f)"
          % (barrel_h.x, barrel_h.y, axis.x, axis.y, axis.z))

    old = bpy.data.actions.get(o["name"])
    if old:
        if not o["force"] and old.get("_recoil_from"):
            print("%r already has recoil. Use --force." % o["name"])
            return
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(o["name"])
    action.use_fake_user = True
    assign(arm, action)

    total = o["kick"] + o["settle"]
    peak_deg = o["angle"]
    for f in range(0, total + 1):
        bpy.context.scene.frame_set(f)
        # Reset every bone to the aim pose; only the spine chain deviates.
        for pb in arm.pose.bones:
            loc, rot, scl = pose[pb.name]
            pb.location, pb.rotation_quaternion, pb.scale = loc.copy(), rot.copy(), scl.copy()
        bpy.context.view_layer.update()

        amt = recoil_curve(f, o["kick"], o["settle"]) * peak_deg
        if abs(amt) > 1e-6:
            # Root-outward so each bone's rotation compounds through its
            # children; the top of the chain ends up rotated by the total.
            for name, w in weights:
                pb = arm.pose.bones[name]
                bpy.context.view_layer.update()
                pivot = (arm.matrix_world @ pb.matrix).translation
                rot = Matrix.Rotation(math.radians(amt * w), 4, axis)
                world = arm.matrix_world @ pb.matrix
                new_world = (Matrix.Translation(pivot) @ rot
                             @ Matrix.Translation(-pivot) @ world)
                pb.matrix = arm.matrix_world.inverted() @ new_world
            bpy.context.view_layer.update()

        for pb in arm.pose.bones:
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("scale", frame=f)

    action["_recoil_from"] = o["source"]
    print("built %r: %d frames, peak %.1f deg muzzle rise (kick %d / settle %d)"
          % (o["name"], total + 1, peak_deg, o["kick"], o["settle"]))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
