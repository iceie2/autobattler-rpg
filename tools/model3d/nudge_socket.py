#!/usr/bin/env python3
"""Move a socketed PROP inside a finished master, without rebinding.

Blender script. A prop that hangs into the character's own thigh is a
PLACEMENT problem, and once clips are grafted the expensive fix is to rebind
from scratch and re-graft every clip. This does it in place instead.

WHY THIS IS SAFE. attach_prop_socket.py weights the prop 100% to one bone, and
linear-blend skinning moves a vertex by `bone_pose @ bone_rest^-1`. Translating
the bone in EDIT mode changes head and tail together, so rest and pose move as
one and the prop follows rigidly in EVERY clip -- no channel is touched, no
action is rewritten, and the animation on the body is untouched because nothing
else is weighted to that bone.

Offsets are WORLD units. The armature object on these rigs carries a 0.01
scale, so the vector is converted through the armature matrix rather than being
applied to edit-bone coordinates directly -- applying it raw moves the bone 100x
too far.

  blender -b --python nudge_socket.py -- --blend master.blend \\
      --move weapon_r:-0.055,-0.04,0 --move weapon_l:0.075,-0.03,0 \\
      --out-blend master_v2.blend --out-glb out.glb
"""
import sys

import bpy
from mathutils import Vector


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"blend": None, "move": [], "rotate": [], "out_blend": None,
         "out_glb": None}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            k, v = argv[i][2:].replace("-", "_"), argv[i + 1]
            if k in ("move", "rotate"):
                o[k].append(v)
            else:
                o[k] = v
            i += 2
        else:
            i += 1
    return o


def main():
    o = args()
    bpy.ops.wm.open_mainfile(filepath=o["blend"])

    import numpy as np

    def bounds(ob):
        pts = np.array([list(ob.matrix_world @ v.co) for v in ob.data.vertices])
        return pts.min(0), pts.max(0)

    for spec in o["move"]:
        name, vec = spec.split(":")
        ob = bpy.data.objects.get(name)
        if ob is None or ob.type != "MESH":
            sys.exit("no mesh object %r; have %s"
                     % (name, [x.name for x in bpy.data.objects if x.type == "MESH"]))
        world = Vector([float(x) for x in vec.split(",")])
        lo0, hi0 = bounds(ob)
        # world delta -> the prop's own local space
        local = ob.matrix_world.inverted().to_3x3() @ world
        for v in ob.data.vertices:
            v.co += local
        ob.data.update()
        bpy.context.view_layer.update()
        lo1, hi1 = bounds(ob)
        moved = float(np.linalg.norm(((lo1 + hi1) - (lo0 + hi0)) * 0.5))
        print("  %-12s min %s -> %s   (moved %.4f, asked %.4f)"
              % (name, tuple(np.round(lo0, 4)), tuple(np.round(lo1, 4)),
                 moved, world.length))
        if abs(moved - world.length) > 1e-3:
            sys.exit("prop did not move by the requested amount")

    # --rotate NAME:AXIS:DEG, pivoting on the prop's own socket bone head.
    # Translation cannot fix a collision that only happens in some poses -- the
    # idle clip swings the arm inward, so a knife hanging straight down grazes
    # the thigh wherever it is shifted to. Tipping it forward moves it out of
    # the leg's way in every pose instead.
    import math
    from mathutils import Matrix
    arm = next(x for x in bpy.data.objects if x.type == "ARMATURE")
    for spec in o["rotate"]:
        name, axis, deg = spec.split(":")
        ob = bpy.data.objects[name]
        vg = [g.name for g in ob.vertex_groups]
        if len(vg) != 1:
            sys.exit("%s is not single-socket bound (groups %s)" % (name, vg))
        pivot_w = arm.matrix_world @ arm.data.bones[vg[0]].head_local
        inv = ob.matrix_world.inverted()
        pivot = inv @ pivot_w
        R = Matrix.Rotation(math.radians(float(deg)), 4, axis.upper())
        M = Matrix.Translation(pivot) @ R @ Matrix.Translation(-pivot)
        ob.data.transform(M)
        ob.data.update()
        print("  %-12s rotated %s%s about %s"
              % (name, deg, axis.upper(), tuple(round(v, 3) for v in pivot_w)))
    bpy.context.view_layer.update()

    if o["out_blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=o["out_blend"])
    if o["out_glb"]:
        bpy.ops.export_scene.gltf(filepath=o["out_glb"], export_format="GLB",
                                  export_animations=True, use_selection=False)
        print("  wrote %s" % o["out_glb"])


if __name__ == "__main__":
    main()
