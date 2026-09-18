"""Compute the yaw bias that makes a held weapon's BARREL point at the target.

Blender script. Prints the number to put in Model3DSprite.clip_yaw_bias_deg
for a given clip.

WHY THIS EXISTS: face_direction() rotates the model so its canonical forward
points at the target, and every clip needs a per-clip correction because Meshy
authors each clip facing an arbitrary direction. For locomotion that correction
can be eyeballed — if the walk looks like it's heading the right way, it is.

For an AIMING clip you cannot eyeball it, and trying to is how this went wrong
(2026-09-09): a bias was picked because the pose looked good from the game
camera, but "looks good" and "the barrel points where the projectile goes" are
different constraints. A pose chosen for looks leaves the barrel at a FIXED
offset from the target for every shot — he'd fire visibly sideways while the
projectile flew true, on every attack, forever.

So the correction is derived instead of judged: measure where the barrel
actually points at the hold frame, and return the rotation that lands it on
canonical forward. The result is correct by construction and falsifiable —
aim the finished model N/E/S/W and the barrel tracks, or the number is wrong.

Barrel direction is measured from the weapon mesh's own geometry (its longest
principal axis), evaluated WITH the armature deform applied at the reference
frame, so it reflects where the gun really ends up in the posed rig rather than
where the bind matrix nominally put it. Muzzle-vs-stock is resolved by
cross-sectional radius: a rifle is thin at the muzzle, thick at the stock.

*** THIS NUMBER IS A STARTING POINT, NOT THE ANSWER. *** On Headhunter's rifle
it came out ~53 deg off the truth, consistently, because the mesh includes a
SLING looping below the weapon: those vertices drag the principal axis away
from the barrel line. Any weapon with a strap, bipod, drum magazine or big
scope will skew the same way, and the skew is invisible from the number alone.

GROUND TRUTH is the render test, which needs no trust in the geometry at all:
render the weapon ALONE (hide the body) across 8 target yaws, measure the
projected pixel extent of the blob at each, and fit

    f(a) = sqrt(sin^2 a + sin^2(pitch) cos^2 a)

for the offset. A correctly calibrated barrel peaks in extent at due east/west
(broadside to camera) and bottoms out at north/south (end-on); the 180 flip is
resolved by which end is thinner at the most side-on sample. That fit is what
produced Headhunter's verified -13.0, and it reported +1.0 residual afterward.

A STATIC hold clip is a precondition. If the clip still moves, barrel yaw
changes frame to frame and no single bias exists — Headhunter's raw aim clip
swept ~60 deg across its supposedly-settled tail, which is why it was frozen
(tools/model3d/freeze_pose.py) before any of this was meaningful.

  blender --background --python aim_yaw.py -- \
      --model "assets/3d pipeline/hero/headhunter/headhunter.glb" \
      --weapon Weapon_Aim --clip aim --frame 11
"""
import sys
import math

import bpy
from mathutils import Vector


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "weapon": "Weapon_Aim", "clip": "aim",
         "frame": 11, "chest_bone": "Spine02"}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:].replace("-", "_"), argv[i + 1]
            if k == "frame":
                v = int(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])

    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")
    gun = bpy.data.objects.get(o["weapon"])
    if gun is None:
        print("no object named %r (have: %s)"
              % (o["weapon"], sorted(x.name for x in bpy.data.objects)))
        return

    act = bpy.data.actions.get(o["clip"])
    if act is None:
        print("no clip %r (have: %s)"
              % (o["clip"], sorted(a.name for a in bpy.data.actions)))
        return
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    if hasattr(ad, "action_slot") and getattr(act, "slots", None):
        ad.action_slot = act.slots[0]
    bpy.context.scene.frame_set(o["frame"])
    bpy.context.view_layer.update()

    # Evaluate the gun WITH its armature modifier applied, so we measure where
    # the barrel actually is in this pose, not at bind.
    dg = bpy.context.evaluated_depsgraph_get()
    gun_eval = gun.evaluated_get(dg)
    mesh = gun_eval.to_mesh()
    pts = [gun_eval.matrix_world @ v.co for v in mesh.vertices]
    gun_eval.to_mesh_clear()
    if len(pts) < 2:
        print("weapon mesh has no geometry")
        return

    # Longest principal axis via PCA. NOT the extreme-point pair: that picks
    # the single farthest-apart vertex pair, which on this rifle runs
    # diagonally from the muzzle tip to the bottom-rear corner of the stock
    # rather than down the barrel — measured 45 deg off the true axis
    # (2026-09-09), which is exactly the error this tool exists to prevent.
    import numpy as np
    arr = np.array([[p.x, p.y, p.z] for p in pts], dtype=float)
    arr -= arr.mean(axis=0)
    _w, vecs = np.linalg.eigh(np.cov(arr.T))
    axis = Vector(vecs[:, -1]).normalized()   # largest eigenvalue = long axis

    # Which end is the muzzle: a rifle is thin at the muzzle and thick at the
    # stock, so compare cross-sectional radius in the outer fifth of each end.
    centre = sum(pts, Vector((0, 0, 0))) / len(pts)
    t = [(p - centre).dot(axis) for p in pts]
    lo, hi = min(t), max(t)
    span = (hi - lo) / 5.0

    def radius(sel):
        rs = [((p - centre) - axis * ti).length
              for p, ti in zip(pts, t) if sel(ti)]
        return sum(rs) / len(rs) if rs else 0.0

    r_pos = radius(lambda ti: ti >= hi - span)
    r_neg = radius(lambda ti: ti <= lo + span)
    barrel = axis if r_pos < r_neg else -axis
    muzzle = centre + barrel * (hi if r_pos < r_neg else -lo)
    stock = centre - barrel * ((hi - lo) - (hi if r_pos < r_neg else -lo))
    print("end radii: +axis %.3f, -axis %.3f  (muzzle = thinner)" % (r_pos, r_neg))

    print("barrel dir (blender):  (%.3f, %.3f, %.3f)" % tuple(barrel))
    print("muzzle (blender):      (%.3f, %.3f, %.3f)" % tuple(muzzle))
    print("stock  (blender):      (%.3f, %.3f, %.3f)" % tuple(stock))
    print("gun length:            %.3f" % (muzzle - stock).length)

    # Blender (X, Y, Z up) -> glTF/Godot (X, Z, -Y up). Ground plane in Godot
    # is XZ, so the barrel's ground direction is (bx, -by).
    gx, gz = barrel.x, -barrel.y
    if math.hypot(gx, gz) < 1e-6:
        print("barrel is vertical — no meaningful yaw")
        return

    # Model3DSprite: rest-forward (0,0,1) maps to (sin y, cos y), so a
    # direction's own yaw is atan2(x, z). face_direction() sets
    #   pivot.y = atan2(d.x, d.y) + bias
    # so bias = -(barrel's own yaw) leaves the barrel on the target exactly.
    barrel_yaw = math.degrees(math.atan2(gx, gz))
    bias = -barrel_yaw
    while bias <= -180.0:
        bias += 360.0
    while bias > 180.0:
        bias -= 360.0

    print()
    print("barrel yaw (godot):    %.1f deg" % barrel_yaw)
    print("=> clip_yaw_bias_deg[%r] = %.1f" % (o["clip"], bias))
    print("   barrel pitch:       %.1f deg above horizontal"
          % math.degrees(math.asin(max(-1.0, min(1.0, barrel.z)))))


main()
