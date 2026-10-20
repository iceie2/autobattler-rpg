"""Render every clip of a rigged creature .glb as a contact sheet. Blender script.

One row per clip, `--cols` evenly spaced moments across it, front view in an
orthographic camera framed on the whole clip set -- so motion (a wingbeat, a
gait, a lunge) can be reviewed from one image instead of judged from a still.
Built for Skyrender v002 (2026-10-04); works on any creature_rig.py output.

  blender -b --python clip_sheet.py -- --model creature.glb --out sheet.png [--cols 6] [--size 220]
"""
import bpy, sys, math
from mathutils import Vector


def opts():
    a = sys.argv[sys.argv.index("--") + 1:]
    return {a[i][2:]: a[i + 1] for i in range(0, len(a), 2)}


def main():
    o = opts()
    cols = int(o.get("cols", "6"))
    size = int(o.get("size", "220"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")
    meshes = [ob for ob in bpy.data.objects if ob.type == "MESH"]
    actions = sorted(bpy.data.actions, key=lambda a: a.name)
    ad = arm.animation_data or arm.animation_data_create()
    sc = bpy.context.scene

    # Frame on the union of every clip's sampled pose -- except death, whose
    # sprawl would shrink everything else to specks (it may crop at the edges).
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for act in actions:
        if act.name == "death" and len(actions) > 1:
            continue
        ad.action = act
        if hasattr(ad, "action_slot") and getattr(act, "slots", None) and len(act.slots):
            ad.action_slot = act.slots[0]
        f0, f1 = act.frame_range
        for i in range(cols):
            sc.frame_set(int(f0 + (f1 - f0) * i / max(cols - 1, 1)))
            dg = bpy.context.evaluated_depsgraph_get()
            for m in meshes:
                ev = m.evaluated_get(dg)
                for v in ev.to_mesh().vertices:
                    w = m.matrix_world @ v.co
                    lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
                    hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
                ev.to_mesh_clear()
    centre = (lo + hi) / 2
    extent = max(hi.x - lo.x, hi.z - lo.z) * 1.08

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = extent
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    # glTF +Z (creature front) lands on Blender -Y: look from -Y toward +Y.
    cam.location = Vector((centre.x, lo.y - 5.0, centre.z))
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.rotation_euler = (math.radians(50), math.radians(-20), math.radians(-30))
    sc.collection.objects.link(sun)
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [
        e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x = size
    sc.render.resolution_y = size
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("W")
    sc.world.color = (0.12, 0.13, 0.16)

    tiles = []
    tmp = o["out"] + ".tile.png"
    for act in actions:
        ad.action = act
        if hasattr(ad, "action_slot") and getattr(act, "slots", None) and len(act.slots):
            ad.action_slot = act.slots[0]
        f0, f1 = act.frame_range
        row = []
        for i in range(cols):
            sc.frame_set(int(f0 + (f1 - f0) * i / max(cols - 1, 1)))
            sc.render.filepath = tmp
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(tmp)
            row.append(list(img.pixels))
            bpy.data.images.remove(img)
        tiles.append((act.name, row))

    W, Hh = size * cols, size * len(tiles)
    sheet = bpy.data.images.new("sheet", W, Hh)
    px = [0.0] * (W * Hh * 4)
    for r, (_name, row) in enumerate(tiles):
        oy = (len(tiles) - 1 - r) * size          # Blender images are bottom-up
        for c, tp in enumerate(row):
            ox = c * size
            for y in range(size):
                src = y * size * 4
                dst = ((oy + y) * W + ox) * 4
                px[dst:dst + size * 4] = tp[src:src + size * 4]
    sheet.pixels = px
    sheet.filepath_raw = o["out"]
    sheet.file_format = "PNG"
    sheet.save()
    print("rows (top to bottom):", ", ".join(n for n, _ in tiles))
    print("wrote", o["out"])


main()
