#!/usr/bin/env python3
"""Headless turntable / clip-strip renderer for review. Blender script.

Exists because the review protocol for every converted hero asks for the same
three things -- a multi-angle turntable, a frame strip per clip, and one shot at
true game scale -- and there was no way to produce any of them without opening
the GUI. `blender_review.py` is interactive; `aim_yaw.py` renders but only to
measure projected extent for one specific calibration.

THE CAMERA IS THE GAME'S CAMERA, not a flattering one:
  - ORTHOGRAPHIC. The board fakes perspective in 2D (BoardPerspective); the
    character viewport does not.
  - PITCH 28 deg, read from board_perspective.gd's PITCH_DEG, which
    VisualUnit.MODEL_CAMERA_PITCH_DEG also derives from. Do not "improve" this
    to a nicer angle -- the whole point is that a problem visible here is a
    problem the player will see.
  - --game-scale renders at MODEL_RENDER_H (138 px tall, visual_unit.gd) so
    silhouettes are judged at the size they actually ship at. A model that
    reads at 800px and turns to mush at 138 is a failed model, and that is the
    single most common way a render flatters something.

  blender --background --python turntable.py -- \
      --model "assets/3d pipeline/hero/cross/raw/cross_maul_prop.glb" \
      --out <scratchpad>/cross_maul.png --angles 8

  blender --background --python turntable.py -- \
      --model "assets/3d pipeline/hero/cross/cross.glb" \
      --clip attack --frames 8 --out <scratchpad>/cross_attack.png

Renders go to the SCRATCHPAD, never into the project.
"""
import sys
import math
import os

import bpy
from mathutils import Vector

PITCH_DEG = 28.0     # board_perspective.gd PITCH_DEG
GAME_H = 138         # visual_unit.gd MODEL_RENDER_H


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "out": None, "clip": "", "angles": 8, "frames": 0,
         "res": 320, "game_scale": False, "pitch": PITCH_DEG, "yaw0": 0.0,
         "hide": ""}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--game-scale":
            o["game_scale"] = True
            i += 1
            continue
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:].replace("-", "_"), argv[i + 1]
            if k in ("angles", "frames", "res"):
                v = int(v)
            elif k in ("pitch", "yaw0"):
                v = float(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load(path):
    bpy.ops.import_scene.gltf(filepath=path)
    # Blender's glTF importer adds a 42-vert Icosphere in `glTF_not_exported`
    # that is 2.0 units across -- bigger than a 1.54 character, so it ENCLOSES
    # the model and every render comes out a featureless grey ball.
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Icosphere"):
            bpy.data.objects.remove(ob, do_unlink=True)
    return [o for o in bpy.data.objects if o.type == "MESH"]


def bounds(meshes):
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for ob in meshes:
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def setup(meshes, res, pitch):
    lo, hi = bounds(meshes)
    ctr = (lo + hi) / 2
    size = max(hi[i] - lo[i] for i in range(3))

    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    bpy.context.collection.objects.link(sun)
    bpy.context.scene.world = bpy.data.worlds.new("W")
    bpy.context.scene.world.use_nodes = True
    bpy.context.scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6

    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = size * 1.25
    cam = bpy.data.objects.new("Cam", cam_d)
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    sc = bpy.context.scene
    # Engine id has churned across Blender versions (BLENDER_EEVEE ->
    # BLENDER_EEVEE_NEXT); probe the enum rather than hardcoding or introspecting
    # RenderEngine subclasses (HydraRenderEngine has no bl_idname and blows up).
    engines = sc.render.bl_rna.properties["engine"].enum_items.keys()
    for want in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        if want in engines:
            sc.render.engine = want
            break
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    return cam, ctr, size


def place(cam, ctr, size, yaw_deg, pitch_deg):
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    d = size * 3
    cam.location = ctr + Vector((math.sin(yaw) * math.cos(pitch),
                                 -math.cos(yaw) * math.cos(pitch),
                                 math.sin(pitch))) * d
    direction = ctr - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def shot(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    o = args()
    if not o["model"] or not o["out"]:
        sys.exit("need --model and --out")
    clean()
    meshes = load(o["model"])
    # Review the same prop variant that runtime selects for this clip.
    hidden = set(filter(None, o["hide"].split(",")))
    for ob in bpy.data.objects:
        if ob.name in hidden:
            ob.hide_render = True
            for child in ob.children_recursive:
                child.hide_render = True
    meshes = [ob for ob in meshes if not ob.hide_render]
    if not meshes:
        sys.exit("no mesh in " + o["model"])
    # Blender's glTF importer assigns the first action to the armature, so a
    # plain turntable would silently render frame 1 of whatever clip happens to
    # sort first rather than the rest pose -- and you would be judging geometry
    # through an animation. Clear it unless a clip was explicitly asked for.
    if not o["clip"]:
        for ob in bpy.data.objects:
            if ob.type == "ARMATURE":
                if ob.animation_data:
                    ob.animation_data.action = None
                # Clearing the action is NOT enough -- the pose bones keep the
                # transforms they were last evaluated at, so the model still
                # renders posed. pose_position="REST" is what actually shows
                # the bind pose.
                ob.data.pose_position = "REST"
        bpy.context.view_layer.update()

    res = GAME_H if o["game_scale"] else o["res"]
    cam, ctr, size = setup(meshes, res, o["pitch"])

    tmp = os.path.join(os.path.dirname(o["out"]),
                       os.path.splitext(os.path.basename(o["out"]))[0] + "_frames")
    os.makedirs(tmp, exist_ok=True)
    tiles = []

    if o["clip"]:
        # Frame strip through one animation clip.
        arm = next((x for x in bpy.data.objects if x.type == "ARMATURE"), None)
        act = next((a for a in bpy.data.actions if a.name == o["clip"]), None)
        if not act:
            sys.exit(f"clip {o['clip']!r} not found; have: "
                     + ", ".join(a.name for a in bpy.data.actions))
        arm.animation_data_create()
        arm.animation_data.action = act
        if getattr(act, "slots", None):
            arm.animation_data.action_slot = act.slots[0]
        f0, f1 = (int(x) for x in act.frame_range)
        n = o["frames"] or 8

        # Frame the WHOLE clip, not the rest pose. A travelling clip (death is a
        # knock-down, hurt staggers backward) otherwise walks straight out of a
        # camera fitted to the bind pose, and the strip shows an empty box --
        # which reads as a broken model when it is only a badly aimed camera.
        dg = bpy.context.evaluated_depsgraph_get()
        lo = Vector((1e9,) * 3)
        hi = Vector((-1e9,) * 3)
        for i in range(n):
            bpy.context.scene.frame_set(int(f0 + i * (f1 - f0) / max(1, n - 1)))
            dg.update()
            for ob in meshes:
                ev = ob.evaluated_get(dg)
                for c in ev.bound_box:
                    w = ev.matrix_world @ Vector(c)
                    for k in range(3):
                        lo[k] = min(lo[k], w[k])
                        hi[k] = max(hi[k], w[k])
        ctr = (lo + hi) / 2
        size = max(hi[k] - lo[k] for k in range(3))
        cam.data.ortho_scale = size * 1.25
        place(cam, ctr, size, o["yaw0"], o["pitch"])
        for i in range(n):
            bpy.context.scene.frame_set(int(f0 + i * (f1 - f0) / max(1, n - 1)))
            p = os.path.join(tmp, f"f{i:02d}.png")
            shot(p)
            tiles.append(p)
        label = f"{o['clip']}  {f1 - f0 + 1}f"
    else:
        for i in range(o["angles"]):
            place(cam, ctr, size, o["yaw0"] + i * 360.0 / o["angles"], o["pitch"])
            p = os.path.join(tmp, f"a{i:02d}.png")
            shot(p)
            tiles.append(p)
        label = f"turntable {o['angles']} angles  pitch {o['pitch']:.0f}"

    # Contact sheet, stitched with Blender's own image API so this needs no PIL
    # inside Blender's bundled python.
    imgs = [bpy.data.images.load(p) for p in tiles]
    w, h = imgs[0].size
    sheet = bpy.data.images.new("sheet", w * len(imgs), h)
    buf = [0.0] * (w * len(imgs) * h * 4)
    for k, im in enumerate(imgs):
        px = list(im.pixels)
        for y in range(h):
            src = y * w * 4
            dst = (y * w * len(imgs) + k * w) * 4
            buf[dst:dst + w * 4] = px[src:src + w * 4]
    sheet.pixels = buf
    sheet.filepath_raw = o["out"]
    sheet.file_format = "PNG"
    sheet.save()
    print(f"WROTE {o['out']}  {w * len(imgs)}x{h}  ({label})")


if __name__ == "__main__":
    main()
