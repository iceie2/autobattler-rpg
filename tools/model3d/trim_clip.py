"""Trim a single-clip glTF export down to a frame range, rebased to start at 0,
and re-export as its own standalone .glb (for feeding into replace_clip.py).
Blender script.

Built for Headhunter's "Rifle_Aim_Turn_Right" export: the clip turns the body
to face the aim direction over its first ~30 frames, then holds a settled
aim pose through the end (frame 44) — measured by sampling Hips yaw and
LeftHand height across the clip. Only that settled tail is wanted as the
game's "aim" pose; the turn itself isn't a state this game has (units turn
via face_direction()/model3d_sprite.gd, not a baked turning animation).

  blender --background --python trim_clip.py -- \
      --model "...Rifle_Aim_Turn_Right_withSkin.glb" \
      --start 30 --end 44 --out "...trimmed.glb"
"""
import sys
import bpy


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "start": 0, "end": None, "out": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:], argv[i + 1]
            if k in ("start", "end"):
                v = int(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def main():
    o = args()
    if not (o["model"] and o["out"] and o["end"] is not None):
        print(__doc__)
        return

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")
    act = bpy.data.actions[0]
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    if hasattr(ad, "action_slot") and getattr(act, "slots", None):
        ad.action_slot = act.slots[0]

    def fcurves_of(a):
        if hasattr(a, "layers"):
            for layer in a.layers:
                for strip in layer.strips:
                    for cb in getattr(strip, "channelbags", []) or []:
                        for fc in cb.fcurves:
                            yield fc
        else:
            for fc in a.fcurves:
                yield fc

    lo, hi = o["start"], o["end"]
    for fc in list(fcurves_of(act)):
        # Drop keys outside [lo, hi], then shift the survivors so lo -> 0.
        # Blender 5.2: removing a keyframe invalidates the OTHER RNA pointers
        # held in a cached list, so "for kp in list(pts): pts.remove(kp)" dies
        # with "Keyframe not in F-Curve" on the second removal. Walk indices
        # backwards instead -- a reverse index stays valid as later entries go.
        pts = fc.keyframe_points
        for i in range(len(pts) - 1, -1, -1):
            if pts[i].co[0] < lo or pts[i].co[0] > hi:
                pts.remove(pts[i])
        for kp in fc.keyframe_points:
            kp.co[0] -= lo
            kp.handle_left[0] -= lo
            kp.handle_right[0] -= lo
        fc.update()

    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = hi - lo
    print("trimmed to frames [%d, %d] -> [0, %d]" % (lo, hi, hi - lo))

    bpy.ops.export_scene.gltf(filepath=o["out"], export_format="GLB")
    print("wrote %s" % o["out"])


main()
