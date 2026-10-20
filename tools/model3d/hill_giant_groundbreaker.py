"""Author the Hill Giant's Groundbreaker clips (slam / stuck / yank). Blender script.

Owner design 2026-10-06 (round-5 elite): two club swings, then GROUNDBREAKER --
a two-handed overhead windup and a slam into the ground in front of him -- then
STUCK CLUB (it lodges; he heaves on it, can't act) and a YANK free.

  slam   the body (spine, hips, legs) follows the Meshy `ult` smash, eased in
         from idle; BOTH hands are steered along an authored path -- up from
         his sides to a point centred over his head, a cocked beat at the top,
         then driven down to the ground centred in front. The left hand rides
         just below the right on the shaft. The clip ENDS on contact; the game
         plays it timed to the windup, so contact == damage.
  stuck  a loop from the contact pose: both hands stay on the planted handle
         while the spine and hips heave back twice per loop with a shudder --
         the club doesn't move, he does.
  CLUB AIM (2026-10-06 fix): the club rides weapon_r under RightHand, so after
         the arms reach, the WRIST is turned to aim the club head -- up and
         back overhead, whipping forward, and at contact the head is planted IN
         the ground in front (hands up the handle, not on the turf). Stuck keeps
         the head planted on that same point while he heaves.
  yank   one last heave, the club rips out, the body overshoots back and
         settles into idle frame 0.

WHY A HAND-ROLLED SOLVER (measured 2026-10-06): this Meshy rig's bone TAILS
are corrupt (the forearm's tail sits tens of metres away) and Blender's IK
constraint stops reaching its target as soon as one of these imported clips is
active (hand gap 0.15 m with no clip, 0.6-0.8 m with idle/ult). So each frame is
posed, then the upper arm and forearm are rotated by a few CCD passes until the
hand's HEAD lands on its target, and the result is keyed directly.

Every original clip is kept; the output is a NEW file.

  blender -b --python hill_giant_groundbreaker.py -- --model hill_giant_v001.glb --out hill_giant_v002.glb
"""
import bpy, sys, math
from mathutils import Vector, Quaternion, Matrix

CONTACT = 20          # ult frame where its club meets the ground
SLAM_RISE = 10        # frames easing from idle up into the overhead start
STUCK_LEN = 24        # one stuck loop (two heaves); the game loops/times it
YANK_LEN = 14
CHAINS = {"RightHand": ("RightForeArm", "RightArm"), "LeftHand": ("LeftForeArm", "LeftArm")}


def opts():
    a = sys.argv[sys.argv.index("--") + 1:]
    return {a[i][2:]: a[i + 1] for i in range(0, len(a), 2)}


def set_action(arm, act):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    if act is not None and hasattr(ad, "action_slot") and getattr(act, "slots", None) and len(act.slots):
        ad.action_slot = act.slots[0]


def sample(arm, act, frame):
    """{bone: (location, quaternion)} of `act` at `frame` (pose space)."""
    set_action(arm, act)
    bpy.context.scene.frame_set(int(frame))
    out = {}
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        out[pb.name] = (pb.location.copy(), pb.rotation_quaternion.copy())
    return out


def lerp_pose(a, b, t):
    return {n: (a[n][0].lerp(b[n][0], t), a[n][1].slerp(b[n][1], t)) for n in a}


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def world_delta(arm, pose, bone, axis, deg):
    """Rotate `bone` in `pose` by `deg` about a WORLD axis (rest-frame converted,
    the creature_rig.py convention)."""
    rest = arm.pose.bones[bone].bone.matrix_local.to_3x3()
    local = (rest.inverted() @ Vector(axis)).normalized()
    loc, q = pose[bone]
    pose[bone] = (loc, q @ Quaternion(local, math.radians(deg)))


def apply_pose(arm, pose):
    set_action(arm, None)
    for pb in arm.pose.bones:
        loc, q = pose[pb.name]
        pb.rotation_mode = "QUATERNION"
        pb.location = loc
        pb.rotation_quaternion = q
    bpy.context.view_layer.update()


def reach(arm, hand, target_world, iters=12):
    """CCD: rotate the hand's chain (forearm, then upper arm) so the hand's HEAD
    lands on target_world. Works in armature space on posed matrices."""
    tgt = arm.matrix_world.inverted() @ target_world
    for _ in range(iters):
        for bone in CHAINS[hand]:
            pb = arm.pose.bones[bone]
            head = pb.head.copy()
            v1 = arm.pose.bones[hand].head - head
            v2 = tgt - head
            if v1.length < 1e-6 or v2.length < 1e-6:
                continue
            q = v1.rotation_difference(v2)
            pb.matrix = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ pb.matrix
            bpy.context.view_layer.update()
    return (arm.matrix_world @ arm.pose.bones[hand].head - target_world).length


def club_head_local(arm, club):
    """The club head's centre in RightHand pose space (constant: the club is
    rigid on weapon_r under RightHand). Head = the far 15% of the club's
    vertices measured from the hand."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = club.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [club.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    hand = arm.matrix_world @ arm.pose.bones["RightHand"].head
    far = max((p - hand).length for p in pts)
    head = [p for p in pts if (p - hand).length > far * 0.85]
    c = sum(head, Vector()) / len(head)
    pb = arm.pose.bones["RightHand"]
    return pb.matrix.inverted() @ (arm.matrix_world.inverted() @ c), (c - hand).length


def club_head(arm, head_local):
    return arm.matrix_world @ (arm.pose.bones["RightHand"].matrix @ head_local)


def aim(arm, head_local, target_world=None, direction=None):
    """Turn the right wrist so the club head points at target_world (or along a
    world direction). Returns the club head's world position afterwards."""
    pb = arm.pose.bones["RightHand"]
    mwi = arm.matrix_world.inverted()
    h = pb.head.copy()
    cur = pb.matrix @ head_local - h
    want = (mwi @ target_world - h) if target_world is not None         else (mwi.to_3x3() @ Vector(direction))
    q = cur.rotation_difference(want)
    pb.matrix = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ pb.matrix
    bpy.context.view_layer.update()
    return club_head(arm, head_local)


def key_current(arm, act, frame):
    """Key the pose as it stands now (after the reach solver) into `act`.
    Captured first: assigning the action re-evaluates the pose from it."""
    pose = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy()) for pb in arm.pose.bones}
    set_action(arm, act)
    for pb in arm.pose.bones:
        loc, q = pose[pb.name]
        pb.location = loc
        pb.rotation_quaternion = q
        pb.keyframe_insert("location", frame=frame)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    set_action(arm, None)


def new_action(name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    return act


def main():
    o = opts()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    sc = bpy.context.scene
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")
    acts = {a.name: a for a in bpy.data.actions}
    for a in acts.values():
        a.use_fake_user = True
    idle, ult = acts["idle"], acts["ult"]

    p_idle = sample(arm, idle, 0)
    apply_pose(arm, p_idle)
    head_top = (arm.matrix_world @ arm.pose.bones["head_end"].head).z   # Head.tail is corrupt (Meshy)
    rh0 = arm.matrix_world @ arm.pose.bones["RightHand"].head
    lh0 = arm.matrix_world @ arm.pose.bones["LeftHand"].head
    club = bpy.data.objects["Club_Held"]
    head_local, club_len = club_head_local(arm, club)
    feet_z = min((arm.matrix_world @ arm.pose.bones[b].head).z for b in ("LeftToeBase", "RightToeBase"))
    print("CLUB length %.3f m, feet z %.3f" % (club_len, feet_z))

    # ── slam ──
    over = Vector((0.0, 0.10, head_top + 0.30))     # centred overhead
    cock = Vector((0.0, 0.28, head_top + 0.38))     # cocked back at the top
    # Contact: the club HEAD is planted in the turf in front (sunk a little
    # below the feet); the shaft leans back up toward him, hands on the handle.
    impact = Vector((0.0, -1.15, feet_z - 0.06))
    d_hit = Vector((0.0, -0.55, -0.83)).normalized()    # hand -> club head at contact
    ground = impact - d_hit * club_len                  # where the right hand ends up
    d_over = Vector((0.0, 0.40, 0.92)).normalized()     # overhead: head up and back
    d_cock = Vector((0.0, 0.85, 0.35)).normalized()     # cocked: head dropped behind
    def grip_off_for(d):
        # left hand further down the handle (away from the head), slightly left
        return -d * 0.16 + Vector((0.08, 0.0, 0.0))

    def path(f):
        if f <= SLAM_RISE:
            return rh0.lerp(over, ease(f / SLAM_RISE))
        u = (f - SLAM_RISE) / float(CONTACT)
        if u < 0.45:
            return over.lerp(cock, ease(u / 0.45))
        k = (u - 0.45) / 0.55
        return cock.lerp(ground, k * k)             # accelerates into the ground

    def club_dir(f):
        if f <= SLAM_RISE:
            return d_over
        u = (f - SLAM_RISE) / float(CONTACT)
        if u < 0.45:
            return d_over.slerp(d_cock, ease(u / 0.45))
        k = (u - 0.45) / 0.55
        return d_cock.slerp(d_hit, k ** 1.6)        # the head whips through late

    p_ult = {f: sample(arm, ult, f) for f in range(0, CONTACT + 1)}
    slam = new_action("slam")
    slam_end = SLAM_RISE + CONTACT
    worst = 0.0
    for f in range(0, slam_end + 1):
        body = lerp_pose(p_idle, p_ult[0], ease(f / SLAM_RISE)) if f <= SLAM_RISE \
            else p_ult[f - SLAM_RISE]
        apply_pose(arm, body)
        pr = path(f)
        d = club_dir(f)
        pl = lh0.lerp(pr + grip_off_for(d), ease(f / SLAM_RISE)) if f < SLAM_RISE else pr + grip_off_for(d)
        worst = max(worst, reach(arm, "RightHand", pr), reach(arm, "LeftHand", pl))
        # Rise: blend the wrist from its natural carry into the aimed grip.
        if f < SLAM_RISE:
            nat = (club_head(arm, head_local) - (arm.matrix_world @ arm.pose.bones["RightHand"].head)).normalized()
            d = nat.slerp(d, ease(f / SLAM_RISE))
        tip = aim(arm, head_local, direction=d)
        key_current(arm, slam, f)
    print("SLAM worst hand gap %.3f m, contact club head %s (target %s)" % (worst, tuple(round(x, 2) for x in tip),
          tuple(round(x, 2) for x in impact)))

    # ── stuck: hands stay on the planted handle, body heaves ──
    apply_pose(arm, p_ult[CONTACT])
    reach(arm, "RightHand", ground); reach(arm, "LeftHand", ground + grip_off_for(d_hit))
    aim(arm, head_local, target_world=impact)
    p_contact = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy()) for pb in arm.pose.bones}
    stuck = new_action("stuck")
    X = (1, 0, 0); Z = (0, 0, 1)
    worst = 0.0
    drift = 0.0
    for f in range(0, STUCK_LEN + 1):
        t = f / STUCK_LEN
        heave = max(0.0, math.sin(2 * math.tau * t))          # two heaves per loop
        shud = math.sin(9 * math.tau * t) * 1.2               # strain shudder
        p = {n: (v[0].copy(), v[1].copy()) for n, v in p_contact.items()}
        # Lean BACK (front is -Y, so back is -deg about +X) up the spine --
        # big enough to read at board scale.
        for bone, share in (("Spine02", 0.35), ("Spine01", 0.35), ("Spine", 0.3)):
            world_delta(arm, p, bone, X, -34.0 * share * heave + shud * share)
        world_delta(arm, p, "Head", X, -18.0 * heave)
        world_delta(arm, p, "Hips", X, -10.0 * heave)                  # sits back into it
        world_delta(arm, p, "Hips", Z, 4.0 * math.sin(math.tau * t))   # weight shift
        hl, hq = p["Hips"]
        p["Hips"] = (hl + Vector((0, 0, 0.05 * heave)), hq)
        apply_pose(arm, p)
        worst = max(worst, reach(arm, "RightHand", ground), reach(arm, "LeftHand", ground + grip_off_for(d_hit)))
        tip = aim(arm, head_local, target_world=impact)   # the head never leaves the hole
        drift = max(drift, (tip - impact).length)
        key_current(arm, stuck, f)
    print("STUCK worst hand gap %.3f m, club head drift %.3f m" % (worst, drift))

    # ── yank: last heave, rip free, overshoot back, settle to idle ──
    p_stuck = sample(arm, stuck, 0)
    yank = new_action("yank")
    for f in range(0, YANK_LEN + 1):
        t = f / YANK_LEN
        p = lerp_pose(p_stuck, p_idle, ease((t - 0.15) / 0.85))
        rip = math.sin(math.pi * min(1.0, t / 0.7))           # back-lean overshoot
        for bone, share in (("Spine02", 0.35), ("Spine01", 0.35), ("Spine", 0.3)):
            world_delta(arm, p, bone, X, -24.0 * share * rip)
        world_delta(arm, p, "RightArm", X, -35.0 * rip)        # club comes up with him
        apply_pose(arm, p)
        key_current(arm, yank, f)

    set_action(arm, idle)
    bpy.ops.export_scene.gltf(filepath=o["out"], export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS")
    print("CLIPS", sorted(a.name for a in bpy.data.actions))
    print("wrote", o["out"])


main()
