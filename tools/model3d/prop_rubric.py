#!/usr/bin/env python3
"""Does this prop actually read as a WEAPON BEING HELD? Blender script.

WHY THIS EXISTS. The pipeline's four gates -- `--import`, recruit_smoke,
anim_preview_smoke and the arena probe -- assert that the game does not crash.
Every one of them passes with the weapon absent from the file, welded to the
character's face, or buried in his chest. They were quoted as "verification" for
Cross's maul through four rounds of review while the maul was mounted along his
forearm with the striking head at his elbow (2026-09-09). They are wiring tests.
This is the check that has an opinion about geometry.

Each rule is a NUMBER with a THRESHOLD, and every rule is evaluated and printed
every run. A previous version of this listed five criteria and computed three of
them, then reported "passes" -- which is worse than having no check at all,
because it launders a guess as a measurement.

THE RUBRIC (rest pose unless stated)

  GRIP -- is it in his hand at all?
    G1 fist-to-haft-axis distance      <= GRIP_ON_AXIS
       The haft has to pass THROUGH the fist, not near it.
    G2 fist position along the haft     within GRIP_FRAC
       Measured from the butt. A hand at 50% is holding it like a barbell.
    G3 nearest prop vertex to the fist  <= GRIP_CONTACT
       Catches a weapon that is on the right line but floating off the end.

  ANATOMY -- is it held, or is it strapped to the arm?
    A1 head is distal: d(head,elbow) > d(fist,elbow)
       The striking end must be past the hand, never back up the arm.
    A2 weapon-segment to forearm-segment distance >= LIMB_CLEAR
       A weapon lying along the forearm satisfies A1 and still looks welded on.

  BODY
    B1 nearest prop vertex to body mesh >= BODY_CLEAR, EXCLUDING a sphere around
       the grip (the hand is supposed to touch it).

  GRAVITY -- would this pose hold itself up?
    P1 in a RELAXED idle, a heavy head hangs. The weapon axis must lie within
       GRAVITY_CONE of straight down, measured from the grip to the head.
       A maul held out horizontally on a straight relaxed arm is a static-load
       failure: nothing in the pose is producing the torque to keep it there.
       This is the rule whose absence let three "passing" binds look wrong.

Axes are BLENDER space after glTF import: Z up, character faces -Y.

  blender --background --python prop_rubric.py -- \
      --model "assets/3d pipeline/hero/cross/cross.glb" \
      --prop Weapon_Held --grip RightHand --parent RightForeArm [--clip idle]

Exit code is 0 only when every rule passes, so it can gate a build.
"""
import sys

import bpy
import numpy as np

GRIP_ON_AXIS = 0.035     # fist must sit within this of the haft's centre line
GRIP_FRAC = (0.05, 0.35)  # fraction along the haft, measured from the butt
GRIP_CONTACT = 0.055     # nearest prop vertex to the fist
LIMB_CLEAR = 0.040       # weapon segment vs forearm segment
BODY_CLEAR = 0.015       # nearest prop vertex to body, outside the grip sphere
GRIP_SPHERE = 0.200      # ignore geometry this close to the fist -- must be
                         # big enough to contain the HAND MESH, not just the
                         # hand BONE. At 0.13 it covered the bone but not the
                         # fingers, so B1 measured weapon-against-hand and sat
                         # pinned at 0.001 for every bind direction tried.
GRAVITY_CONE = 55.0      # degrees from straight down, for a relaxed idle


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "prop": "Weapon_Held", "grip": "RightHand",
         "parent": "RightForeArm", "clip": "", "frame": 1, "gravity": "1"}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            o[argv[i][2:].replace("-", "_")] = argv[i + 1]
            i += 2
        else:
            i += 1
    return o


def seg_seg_dist(p1, p2, q1, q2):
    """Shortest distance between two 3D segments."""
    u, v, w = p2 - p1, q2 - q1, p1 - q1
    a, b, c = u @ u, u @ v, v @ v
    d, e = u @ w, v @ w
    den = a * c - b * b
    if den < 1e-9:
        sc, tc = 0.0, (e / c if c > 1e-9 else 0.0)
    else:
        sc = (b * e - c * d) / den
        tc = (a * e - b * d) / den
    sc, tc = max(0.0, min(1.0, sc)), max(0.0, min(1.0, tc))
    return float(np.linalg.norm((p1 + sc * u) - (q1 + tc * v)))


def main():
    o = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Icosphere"):
            bpy.data.objects.remove(ob, do_unlink=True)

    arm = next(x for x in bpy.data.objects if x.type == "ARMATURE")
    if o["clip"]:
        act = next((a for a in bpy.data.actions if a.name == o["clip"]), None)
        arm.animation_data_create()
        arm.animation_data.action = act
        bpy.context.scene.frame_set(int(o["frame"]))
    else:
        arm.data.pose_position = "REST"
    bpy.context.view_layer.update()

    prop = next(x for x in bpy.data.objects if x.name == o["prop"])
    body = next(x for x in bpy.data.objects
                if x.type == "MESH" and x.name != o["prop"]
                and not x.name.endswith("_Held") or x.name == "char1")

    # Read DEFORMED vertices. prop.data.vertices is the base mesh and does not
    # move under the armature modifier, so in any posed clip it reports the prop
    # sitting where it was bound rather than where it actually is -- which shows
    # up as a spurious "weapon is 1.18 units from the hand" catastrophe.
    dg = bpy.context.evaluated_depsgraph_get()

    def world_verts(ob):
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        pts = np.array([list(ev.matrix_world @ v.co) for v in me.vertices])
        ev.to_mesh_clear()
        return pts

    P = world_verts(prop)
    c = P.mean(0)
    ax = np.linalg.svd(P - c)[2][0]
    t = (P - c) @ ax
    r = np.linalg.norm((P - c) - np.outer(t, ax), axis=1)
    span = t.max() - t.min()
    thick_hi = r[t > t.max() - span * 0.2].mean()
    thick_lo = r[t < t.min() + span * 0.2].mean()
    head_t, butt_t = (t.max(), t.min()) if thick_hi > thick_lo else (t.min(), t.max())
    head, butt = c + ax * head_t, c + ax * butt_t

    def bone(n):
        b = arm.pose.bones[n]
        return np.array(list(arm.matrix_world @ b.matrix.translation))

    fist, elbow = bone(o["grip"]), bone(o["parent"])

    fails = []

    def chk(tag, ok, msg):
        print(f"  [{'PASS' if ok else 'FAIL'}] {tag:4s} {msg}")
        if not ok:
            fails.append(tag)

    print(f"=== {o['prop']} on {o['grip']} "
          f"({o['clip'] or 'REST'}) ===")

    # G1 -- fist distance to the haft's infinite axis
    d_axis = float(np.linalg.norm(np.cross(fist - butt, ax)))
    chk("G1", d_axis <= GRIP_ON_AXIS,
        f"fist to haft axis {d_axis:.3f} (<= {GRIP_ON_AXIS})")

    # G2 -- where along the haft, measured from the butt
    frac = abs(float((fist - butt) @ ax)) / span
    chk("G2", GRIP_FRAC[0] <= frac <= GRIP_FRAC[1],
        f"grip at {frac * 100:.1f}% from butt (want {GRIP_FRAC[0] * 100:.0f}-{GRIP_FRAC[1] * 100:.0f}%)")

    # G3 -- actual contact
    d_near = float(np.linalg.norm(P - fist, axis=1).min())
    chk("G3", d_near <= GRIP_CONTACT,
        f"nearest prop vertex to fist {d_near:.3f} (<= {GRIP_CONTACT})")

    # A1 -- striking end past the hand
    dhe, dfe = float(np.linalg.norm(head - elbow)), float(np.linalg.norm(fist - elbow))
    chk("A1", dhe > dfe,
        f"head->elbow {dhe:.3f} vs fist->elbow {dfe:.3f} (head must be farther)")

    # A2 -- not lying along the forearm.
    #
    # Measured only on the part of the weapon BEYOND the grip. The first
    # version of this used the whole weapon segment against the whole forearm
    # segment, which is unsatisfiable by construction: the weapon is held AT
    # the fist and the fist is an endpoint of the forearm, so the two segments
    # share a point and the distance is always ~0. Every bind "failed" A2 --
    # not because every bind was wrong, but because the rule could never be
    # passed by anything. A rule no geometry can satisfy is not a strict rule,
    # it is a broken one.
    beyond = P[np.linalg.norm(P - fist, axis=1) > GRIP_SPHERE]
    if len(beyond):
        d_limb = float(min(
            seg_seg_dist(p, p, fist, elbow) for p in beyond))
    else:
        d_limb = 9.0
    chk("A2", d_limb >= LIMB_CLEAR,
        f"weapon-beyond-grip to forearm {d_limb:.3f} (>= {LIMB_CLEAR})")

    # B1 -- body clearance outside the grip sphere
    B = world_verts(body)
    # Exclude the grip region from BOTH sides: weapon vertices near the fist
    # (the haft he is holding) and body vertices near the fist (the hand doing
    # the holding). Excluding only one side measures the weapon against the
    # hand and reports a collision that is the entire point of the prop.
    far = P[np.linalg.norm(P - fist, axis=1) > GRIP_SPHERE]
    Bfar = B[np.linalg.norm(B - fist, axis=1) > GRIP_SPHERE]
    if len(far) and len(Bfar):
        dmin = float(min(np.linalg.norm(Bfar - p, axis=1).min() for p in far))
    else:
        dmin = 9.0
    chk("B1", dmin >= BODY_CLEAR,
        f"prop-to-body (outside grip) {dmin:.3f} (>= {BODY_CLEAR})")

    # P1 -- gravity plausibility
    if o["gravity"] != "0":
        wv = head - fist
        wv = wv / np.linalg.norm(wv)
        down = np.array([0.0, 0.0, -1.0])
        ang = float(np.degrees(np.arccos(max(-1.0, min(1.0, wv @ down)))))
        chk("P1", ang <= GRAVITY_CONE,
            f"head hangs {ang:.1f} deg from straight down (<= {GRAVITY_CONE})")

    print(f"RUBRIC: {'ALL PASS' if not fails else 'FAILED ' + ','.join(fails)}")
    sys.exit(0 if not fails else 1)


if __name__ == "__main__":
    main()
