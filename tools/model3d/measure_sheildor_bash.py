"""Print evaluated per-frame bounds for Sheildor's attack meshes."""
import sys
import bpy
from mathutils import Vector

path = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
arm = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
action = bpy.data.actions["attack"]
arm.animation_data_create()
arm.animation_data.action = action
if getattr(action, "slots", None):
    arm.animation_data.action_slot = action.slots[0]

for frame in (0, 4, 7, 9, 13, 19):
    bpy.context.scene.frame_set(frame)
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    print("FRAME", frame)
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(dg)
        coords = [ev.matrix_world @ vertex.co for vertex in ev.to_mesh().vertices]
        lo = Vector(tuple(min(point[i] for point in coords) for i in range(3)))
        hi = Vector(tuple(max(point[i] for point in coords) for i in range(3)))
        print(" ", obj.name, "size", tuple(round(v, 4) for v in hi - lo),
              "centre", tuple(round(v, 4) for v in (hi + lo) / 2))
        ev.to_mesh_clear()
