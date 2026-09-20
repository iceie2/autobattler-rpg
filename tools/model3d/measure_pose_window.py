#!/usr/bin/env python3
"""Measure a clip's ACTIVE WINDOW from bone world positions. Blender script.

Why this exists. `trim_and_graft_action.py --auto` finds a window by sampling a
PROP's centroid, which is the right probe for Cross's maul and useless for a
caster who carries nothing: Lumen's hands are the moving thing. Raw quaternion
travel is not a substitute -- it fired above threshold across 90%+ of every
Lumen clip, because Meshy's dead hold still carries small continuous drift.

So this measures what a viewer actually reads: the world-space position of each
hand relative to the hips, per frame. It reports

  - hand height and lateral spread per frame, so a gesture can be identified
  - the best contiguous WINDOW of `--want` frames by summed hand travel,
    which is the 20-30 frame / 0.8-1.2s target the pipeline asks for

Prints a table and the recommended --start/--end to hand to trim_clip.py.

  blender --background --python measure_pose_window.py -- \
      --model "assets/3d pipeline/hero/lumen/raw/lumen_ult.glb" --want 25
"""
import sys
import bpy
import numpy as np


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "want": 25, "every": 1}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            k, v = argv[i][2:], argv[i + 1]
            o[k] = int(v) if k in ("want", "every") else v
            i += 2
        else:
            i += 1
    return o


def main():
    o = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == 'ARMATURE')
    act = arm.animation_data.action
    f0, f1 = (int(round(x)) for x in act.frame_range)
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = f0, f1

    rows = []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        M = arm.matrix_world
        hip = M @ arm.pose.bones["Hips"].head
        lh = M @ arm.pose.bones["LeftHand"].head
        rh = M @ arm.pose.bones["RightHand"].head
        hd = M @ arm.pose.bones["Head"].head
        rows.append((f, lh.z - hip.z, rh.z - hip.z,
                     abs(lh.x - rh.x), hd.z - hip.z,
                     np.array([lh.x, lh.y, lh.z, rh.x, rh.y, rh.z])))

    P = np.array([r[5] for r in rows])
    step = np.zeros(len(rows))
    step[1:] = np.linalg.norm(P[1:] - P[:-1], axis=1)

    want = min(o["want"], len(rows))
    sums = np.array([step[i:i + want].sum() for i in range(len(rows) - want + 1)])
    b = int(sums.argmax())
    print(f"\nMODEL {o['model']}")
    print(f"frames {f0}..{f1}  ({f1 - f0 + 1})")
    print(f"{'f':>5} {'Lhand_z':>8} {'Rhand_z':>8} {'spread':>7} {'head_z':>7} {'travel':>7}")
    for i, r in enumerate(rows):
        if r[0] % o["every"]:
            continue
        print(f"{r[0]:5d} {r[1]:8.3f} {r[2]:8.3f} {r[3]:7.3f} {r[4]:7.3f} {step[i]:7.4f}")
    print(f"\nBEST {want}-frame window by hand travel: "
          f"--start {rows[b][0]} --end {rows[b][0] + want - 1}  "
          f"(travel {sums[b]:.3f}, {want / 30.0:.2f}s @30fps)")
    print(f"peak single-frame travel at f{rows[int(step.argmax())][0]}")


main()
