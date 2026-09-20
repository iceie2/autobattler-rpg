#!/usr/bin/env python3
"""Lower over-raised arms on a NON-HUMAN-proportioned rig. Blender script.

WHY THIS EXISTS. Meshy's 678-action library is authored on a human-proportioned
biped and applied to every character as bone ROTATIONS. A rotation is
proportion-independent; where the HAND ENDS UP is not. Measured on Reed, an
anthropomorphic frog whose head is ~29% of his total height:

    hero    arm length      head base height
    Reed    39.4% of h      70.9% of h     <- shoulders 11 points lower
    Vail    29.3%           81.9%
    Cross   34.9%           81.4%

His head is so large that his shoulders start low, and his arms are long. Every
library action places hands around z 1.3-1.6 on a 1.7 rig — human chest height,
and ABOVE Reed's head base at 1.205. The result is a character who performs
every single clip with his hands on top of his head.

This is NOT fixable by choosing different actions. It was tried: action 132,
which reads as a low forward push on a human, still lands hands at 1.3-1.6,
because the whole library shares the same authoring proportions. Any character
whose head-to-body ratio is far from human hits this, and an elemental roster
will keep producing them.

WHAT IT DOES. Per frame, per arm, in ARMATURE SPACE (never bone-local — this
rig family's bone axes are corrupt; see 3D_HERO_PIPELINE.md):

    v      = hand - shoulder
    theta  = the arm's ELEVATION ANGLE above horizontal, asin(v.z / |v|)
    theta' = theta * k                                 [only when theta > 0]
    v'     = same azimuth, elevation theta', same length
    rotate the Arm bone about the shoulder by the rotation taking v to v'

So the arm swings DOWN while its compass direction and its length are both
preserved. That matters: damping the whole pose toward rest would collapse a
gesture's spread, and Reed's ultimate is "arms thrown WIDE open to the team" —
the width has to survive. Only the vertical overshoot is corrected.

DO NOT "just scale v.z" — it silently does almost nothing. An arm is a fixed
length, so the corrected vector must be renormalised back to |v|, and for a
near-vertical arm that renormalisation stretches the height straight back:
measured on Reed's skill clip, v.z 50.6 scaled by 0.4 to 20.2 came back to
47.8 after renormalising, moving the hand 2.8 units out of a needed 31. The
elevation angle is the quantity that behaves.

Arms already at or below shoulder height are left untouched: they were never
the problem, and an idle with hands at the belt must not drift.

  blender --background --python retarget_arms.py -- \\
      --model "assets/3d pipeline/hero/reed/reed_v001.glb" \\
      [--k 0.4] [--clips attack,skill] [--force]

k is the fraction of the original above-shoulder height that is KEPT.
1.0 is a no-op; 0.0 pins hands level with the shoulder. 0.4 was the value
measured to bring Reed's hands from above his crown to beside his head.
"""
import math
import sys

import bpy
from mathutils import Matrix, Vector

DEFAULT_PAIRS = "LeftArm:LeftHand,RightArm:RightHand"
MARKER = "_arms_retargeted_k"


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "k": 0.4, "pairs": DEFAULT_PAIRS, "clips": "", "force": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--force":
            o["force"] = True
            i += 1
            continue
        if a.startswith("--") and i + 1 < len(argv):
            k = a[2:]
            v = argv[i + 1]
            o[k] = float(v) if k == "k" else v
            i += 2
        else:
            i += 1
    return o


def assign(arm, action):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = action
    if hasattr(ad, "action_slot") and getattr(action, "slots", None):
        ad.action_slot = action.slots[0]


def fcurves_of(act):
    if hasattr(act, "layers"):
        for layer in act.layers:
            for strip in layer.strips:
                for cb in getattr(strip, "channelbags", []) or []:
                    for fc in cb.fcurves:
                        yield fc
    else:
        for fc in act.fcurves:
            yield fc


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return
    k = float(o["k"])
    pairs = []
    for p in o["pairs"].split(","):
        if ":" in p:
            a, h = p.split(":")
            pairs.append((a.strip(), h.strip()))

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")

    wanted = [c.strip() for c in o["clips"].split(",") if c.strip()]
    acts = [a for a in bpy.data.actions
            if not wanted or any(w in a.name for w in wanted)]
    if not acts:
        print("no matching clips; have: " + ", ".join(a.name for a in bpy.data.actions))
        return

    for pair in pairs:
        if pair[0] not in arm.pose.bones or pair[1] not in arm.pose.bones:
            print("rig has no %s / %s — nothing to do" % pair)
            return

    total_before = []
    total_after = []

    for act in acts:
        if act.get(MARKER) is not None and not o["force"]:
            print("SKIP %s (already retargeted at k=%s; --force to redo)"
                  % (act.name, act[MARKER]))
            continue
        assign(arm, act)
        lo, hi = (int(round(v)) for v in act.frame_range)

        # Sample the whole pose for every frame FIRST. Writing into the action
        # while also reading it back would feed corrected values into the next
        # frame's computation instead of the clip's real motion — the same trap
        # blend_stationary_attack.py documents.
        sampled = {}
        for f in range(lo, hi + 1):
            bpy.context.scene.frame_set(f)
            bpy.context.view_layer.update()
            sampled[f] = {pb.name: (pb.location.copy(),
                                    pb.rotation_quaternion.copy(),
                                    pb.scale.copy())
                          for pb in arm.pose.bones}

        # Only the arm bones' curves are cleared; every other bone keeps its
        # original keys untouched, which keeps the blast radius small.
        for fc in list(fcurves_of(act)):
            path = fc.data_path
            if 'pose.bones["' in path:
                bname = path.split('pose.bones["')[1].split('"]')[0]
                if any(bname == a for a, _ in pairs):
                    fc.keyframe_points.clear()

        moved = []
        for f in range(lo, hi + 1):
            for pb in arm.pose.bones:
                loc, rot, scl = sampled[f][pb.name]
                pb.location, pb.rotation_quaternion, pb.scale = loc, rot, scl
            bpy.context.view_layer.update()

            for arm_name, hand_name in pairs:
                apb = arm.pose.bones[arm_name]
                hpb = arm.pose.bones[hand_name]
                s = apb.head.copy()
                h = hpb.head.copy()
                v = h - s
                if v.length < 1e-5:
                    continue
                total_before.append(h.z)
                length = v.length
                theta = math.asin(max(-1.0, min(1.0, v.z / length)))
                if theta > 0.0:
                    horiz = Vector((v.x, v.y, 0.0))
                    if horiz.length < 1e-4:
                        # Arm pointing straight up: no azimuth to preserve, so
                        # swing it out to the character's own side, taken from
                        # the shoulder's offset from the spine rather than a
                        # hard-coded axis (this rig is not guaranteed to be
                        # world-aligned).
                        root = arm.pose.bones.get("Spine02") or arm.pose.bones.get("Hips")
                        away = s - root.head if root else Vector((1.0, 0.0, 0.0))
                        horiz = Vector((away.x, away.y, 0.0))
                        if horiz.length < 1e-4:
                            horiz = Vector((1.0, 0.0, 0.0))
                    horiz.normalize()
                    t2 = theta * k
                    v2 = (horiz * math.cos(t2) + Vector((0.0, 0.0, math.sin(t2)))) * length
                    rot_q = v.rotation_difference(v2)
                    T = Matrix.Translation(s)
                    apb.matrix = (T @ rot_q.to_matrix().to_4x4()
                                  @ T.inverted() @ apb.matrix)
                    bpy.context.view_layer.update()
                    moved.append(h.z - arm.pose.bones[hand_name].head.z)
                total_after.append(arm.pose.bones[hand_name].head.z)

            for arm_name, _ in pairs:
                pb = arm.pose.bones[arm_name]
                pb.keyframe_insert("location", frame=f)
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("scale", frame=f)

        act[MARKER] = k
        drop = (sum(moved) / len(moved)) if moved else 0.0
        print("%-34s %3d frames, %3d arm poses lowered, mean drop %.3f"
              % (act.name, hi - lo + 1, len(moved), drop))

    if total_before:
        print("\nhand height across every corrected frame:")
        print("  before  max %.3f  mean %.3f" % (max(total_before),
                                                 sum(total_before) / len(total_before)))
        print("  after   max %.3f  mean %.3f" % (max(total_after),
                                                 sum(total_after) / len(total_after)))

    bpy.ops.export_scene.gltf(filepath=o["model"], export_format="GLB",
                              export_animations=True)
    print("wrote %s" % o["model"])


main()
