"""Reduce Sheildor's shield-bash silhouette inflation.

Creates a new versioned Blender master and GLB. The attack's ShieldBash control
keeps its authored translation, but its scale cue is removed and a small
vertical-axis turn is added around impact so the shield is not presented flat
to the gameplay camera.

  blender --background sheildor_master_v041.blend --python refine_sheildor_bash.py -- \
      --save-blend sheildor_master_v042.blend --out sheildor_v039.glb
"""
import math
import sys

import bpy


def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    result = {"save-blend": None, "out": None, "angle": -20.0,
              "translation-factor": 0.12}
    for index in range(0, len(argv) - 1, 2):
        result[argv[index].removeprefix("--")] = argv[index + 1]
    result["angle"] = float(result["angle"])
    result["translation-factor"] = float(result["translation-factor"])
    return result


def fcurves_of(action):
    if hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for channelbag in getattr(strip, "channelbags", []) or []:
                    yield from channelbag.fcurves
    else:
        yield from action.fcurves


def curve_map(action, path):
    return {curve.array_index: curve for curve in fcurves_of(action)
            if curve.data_path == path}


def replace_keys(curve, values):
    curve.keyframe_points.clear()
    for frame, value in values:
        point = curve.keyframe_points.insert(frame, value)
        point.interpolation = "BEZIER"
    curve.update()


def main():
    opts = arguments()
    if not opts["save-blend"] or not opts["out"]:
        raise RuntimeError("--save-blend and --out are required")

    action = bpy.data.actions.get("attack")
    armature = next((obj for obj in bpy.data.objects if obj.type == "ARMATURE"), None)
    if action is None or armature is None or "ShieldBash" not in armature.pose.bones:
        raise RuntimeError("attack action, armature, or ShieldBash bone missing")

    scale_path = 'pose.bones["ShieldBash"].scale'
    scale_curves = curve_map(action, scale_path)
    if len(scale_curves) != 3:
        raise RuntimeError("ShieldBash scale curves missing")
    scale_frames = sorted({point.co[0] for point in scale_curves[0].keyframe_points})
    for curve in scale_curves.values():
        replace_keys(curve, [(frame, 1.0) for frame in scale_frames])

    # The apparent "shield growth" is chiefly the helmet: this source master
    # contains a corrupt cumulative Head scale track which exports from 1.638x
    # at frame 0 to 178.406x at frame 19. Keep the authored enlarged head in
    # its rest transform, but remove all animated scale from the attack pose.
    head_scale_path = 'pose.bones["Head"].scale'
    head_scale_curves = curve_map(action, head_scale_path)
    if len(head_scale_curves) != 3:
        raise RuntimeError("Head scale curves missing")
    head_frames = sorted({point.co[0] for point in head_scale_curves[0].keyframe_points})
    for curve in head_scale_curves.values():
        replace_keys(curve, [(frame, 1.0) for frame in head_frames])
    head_location_path = 'pose.bones["Head"].location'
    head_location_curves = curve_map(action, head_location_path)
    if len(head_location_curves) != 3:
        raise RuntimeError("Head location curves missing")
    for curve in head_location_curves.values():
        frames = [point.co[0] for point in curve.keyframe_points]
        rest = curve.keyframe_points[0].co[1]
        replace_keys(curve, [(frame, rest) for frame in frames])

    # v037 introduced a world-space push on this control. Because this rig's
    # bone rest lengths are corrupt (the same Meshy/glTF hazard documented in
    # 3D_HERO_PIPELINE.md), export converts that modest Blender-space motion to
    # a roughly 45-unit glTF excursion. Preserve the timing and rest position,
    # but damp every delta from the first key so the shield remains a bash prop
    # rather than crossing most of the viewport.
    location_path = 'pose.bones["ShieldBash"].location'
    location_curves = curve_map(action, location_path)
    if len(location_curves) != 3:
        raise RuntimeError("ShieldBash location curves missing")
    factor = opts["translation-factor"]
    for curve in location_curves.values():
        points = [(point.co[0], point.co[1]) for point in curve.keyframe_points]
        rest = points[0][1]
        replace_keys(curve, [(frame, rest + (value - rest) * factor)
                             for frame, value in points])

    rotation_path = 'pose.bones["ShieldBash"].rotation_quaternion'
    rotation_curves = curve_map(action, rotation_path)
    if len(rotation_curves) != 4:
        raise RuntimeError("ShieldBash quaternion curves missing")
    # Ease into the requested yaw at the two impact frames and return cleanly.
    angle = math.radians(opts["angle"])
    angle_keys = [(0, 0.0), (4, angle * 0.2), (7, angle), (9, angle),
                  (13, angle * 0.2), (19, 0.0)]
    quaternion_keys = []
    for frame, radians in angle_keys:
        quaternion_keys.append((frame, (math.cos(radians / 2.0), 0.0, 0.0,
                                         math.sin(radians / 2.0))))
    for component, curve in rotation_curves.items():
        replace_keys(curve, [(frame, quat[component])
                             for frame, quat in quaternion_keys])

    for action_item in bpy.data.actions:
        action_item.use_fake_user = True
    bpy.context.scene.render.fps = 24
    bpy.ops.wm.save_as_mainfile(filepath=opts["save-blend"])
    bpy.ops.export_scene.gltf(filepath=opts["out"], export_format="GLB",
                              export_animations=True, export_skins=True,
                              export_morph=True)
    print("Removed ShieldBash scale cue, damped translation to %.1f%%, and added %.1f-degree impact turn"
          % (factor * 100.0, opts["angle"]))


main()
