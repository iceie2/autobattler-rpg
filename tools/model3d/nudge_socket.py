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
    # The glTF exporter SAMPLES the evaluated depsgraph, so an armature left in
    # REST — which is how attach_prop_socket.py used to hand over its master —
    # writes a flat channel for every bone and the character ships motionless.
    # Forced here as well as upstream, because this script is also run against
    # hand-edited masters whose mode nobody has checked.
    for ob2 in bpy.data.objects:
        if ob2.type == "ARMATURE":
            ob2.data.pose_position = "POSE"
    bpy.context.view_layer.update()

    if o["out_blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=o["out_blend"])
    if o["out_glb"]:
        bpy.ops.export_scene.gltf(filepath=o["out_glb"], export_format="GLB",
                                  export_animations=True, use_selection=False)
        print("  wrote %s" % o["out_glb"])
        moved = _export_moves(o["out_glb"])
        print("  export_animation_moves: %s  %s"
              % ("PASS" if moved["pass"] else "FAIL", moved["per_clip"]))
        if not moved["pass"]:
            sys.exit("nudge_socket: the written glb has clips with NO motion — "
                     "the armature was exported in REST mode")


def _export_moves(path, min_channels=8, min_degrees=5.0):
    """Re-read the WRITTEN glb and confirm its clips still move.

    Same guard as attach_prop_socket.py. Parses the file on disk rather than
    inspecting Blender state, because the whole failure mode is "the scene was
    right and the export was not".
    """
    import json as _json
    import math
    import struct
    try:
        with open(path, "rb") as f:
            f.read(12)
            jlen, _ = struct.unpack("<II", f.read(8))
            j = _json.loads(f.read(jlen))
            blen, _ = struct.unpack("<II", f.read(8))
            blob = f.read(blen)
    except Exception as e:                                  # pragma: no cover
        return {"pass": False, "per_clip": {"error": str(e)}}

    def samples(idx):
        a = j["accessors"][idx]
        bv = j["bufferViews"][a["bufferView"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        return [struct.unpack_from("<" + "f" * n, blob, off + k * n * 4)
                for k in range(a["count"])]

    out = {}
    for anim in j.get("animations", []):
        moving, peak = 0, 0.0
        for ch in anim["channels"]:
            if ch["target"]["path"] != "rotation":
                continue
            vs = samples(anim["samplers"][ch["sampler"]]["output"])
            q0 = vs[0]
            dev = max(2.0 * math.degrees(math.acos(
                min(1.0, abs(sum(a * b for a, b in zip(q0, q)))))) for q in vs)
            if dev > 1.0:
                moving += 1
                peak = max(peak, dev)
        out[anim.get("name", "?")] = (moving, round(peak, 1))
    bad = {k: v for k, v in out.items()
           if v[0] < min_channels or v[1] < min_degrees}
    return {"pass": not bad, "per_clip": out, "failing": bad}


if __name__ == "__main__":
    main()
