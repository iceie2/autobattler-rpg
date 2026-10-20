#!/usr/bin/env python3
"""Turn a FROZEN idle into a breathing one. Blender script.

WHY THIS EXISTS. `freeze_pose.py` builds an idle by holding one frame of an
existing cycle, which costs no Meshy credit. But `anim_preview_smoke` rejects
it outright:

    ANIM_PREVIEW_SMOKE FAIL  SEAR: clip 'idle' STARTED BUT THE SKELETON DID NOT
    MOVE (max bone travel 0.00000 < 0.00400)

and the gate is right to. The engine's procedural bob/breathe (visual_unit.gd
_bob_offset / _breathe_scale) moves the SPRITE, not the skeleton, so a frozen
idle really is a statue that happens to be nudged up and down. Bloodhound hit
this and was given a real breathing idle in v003; this is that, as a tool.

WHAT IT DOES. Adds a slow sinusoidal pitch down the spine chain, weighted so
the motion accumulates upward (hips barely move, chest and head carry it), and
loops seamlessly because the curve is a whole sine over the frame count.

ROTATIONS ARE COMPOSED IN ARMATURE SPACE, via pose_bone.matrix, NEVER as
bone-local Euler values. 3D_HERO_PIPELINE.md s1: these rigs report bone lengths
of 29 on a 1.7-unit character, so bone-local axes are meaningless. Bones are
walked root-first with a depsgraph update between each, so a parent's new pose
is already baked in when its child is positioned.

  blender --background --python add_breathing_idle.py -- \
      --model "assets/3d pipeline/hero/sear/sear_v001.glb" \
      [--clip idle] [--frames 48] [--amp-deg 2.2] [--out other.glb]
"""
import sys
import math

import bpy
from mathutils import Matrix, Vector

# Root-first. The weight is how much of the amplitude each joint takes; summing
# up the chain is what makes the chest rise rather than the whole body tilt.
CHAIN = [("Spine", 0.25), ("Spine01", 0.45), ("Spine02", 0.70),
         ("neck", 0.45), ("Head", 0.30)]


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "clip": "idle", "frames": 48, "amp_deg": 2.2, "out": None}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            k, v = argv[i][2:].replace("-", "_"), argv[i + 1]
            o[k] = int(v) if k == "frames" else (float(v) if k == "amp_deg" else v)
            i += 2
        else:
            i += 1
    return o


def main():
    o = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(x for x in bpy.data.objects if x.type == "ARMATURE")
    act = next((a for a in bpy.data.actions if o["clip"] in a.name), None)
    if act is None:
        print("clip %r not found; have: %s" % (o["clip"], [a.name for a in bpy.data.actions]))
        sys.exit(1)
    arm.animation_data.action = act
    bpy.context.view_layer.objects.active = arm

    n = int(o["frames"])
    amp = math.radians(float(o["amp_deg"]))
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 0, n

    # The frozen source pose, read once in armature space.
    bpy.context.scene.frame_set(0)
    base = {b: arm.pose.bones[b].matrix.copy() for b, _ in CHAIN if b in arm.pose.bones}

    for b in arm.pose.bones:
        b.rotation_mode = 'QUATERNION'

    for f in range(n + 1):
        bpy.context.scene.frame_set(f)
        phase = math.sin(2.0 * math.pi * float(f) / float(n))
        for name, w in CHAIN:
            pb = arm.pose.bones.get(name)
            if pb is None:
                continue
            m = base[name]
            head = m.to_translation()
            # Pitch about the ARMATURE X axis, taken through the bone's own head
            # so the joint rotates in place instead of orbiting the origin.
            R = (Matrix.Translation(head)
                 @ Matrix.Rotation(amp * w * phase, 4, Vector((1.0, 0.0, 0.0)))
                 @ Matrix.Translation(-head))
            pb.matrix = R @ m
            bpy.context.view_layer.update()
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)

    out = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB',
                              export_animations=True, export_yup=True)
    print("wrote", out, "(%d frames, %.1f deg)" % (n, o["amp_deg"]))


main()
