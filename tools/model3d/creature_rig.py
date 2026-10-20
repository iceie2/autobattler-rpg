"""Rig + animate a NON-BIPED Meshy body (bird / quadruped). Blender script.

Meshy's auto-rig only ever builds its fixed 24-bone humanoid (see
3D_HERO_PIPELINE.md §1), so birds, beasts and fish cannot go through it.
Owner-approved route (2026-10-02, enemy conversion): generate the BODY on Meshy
(meshy-t2, 15 credits, no Meshy rig) and build the skeleton + clips here, free.

  blender -b --python creature_rig.py -- --model body.glb --kind bird|quad|octopus|crabrider \
          --out creature.glb [--json report.json] [--fly 1] [--dive 1] [--blend out.blend]

What it does, in order:
  1. Joins the body, drops it onto the ground (min z = 0), centres x/y.
     Front is Blender -Y (== glTF +Z), which every Meshy body already faces.
  2. Finds LANDMARKS from geometry (wings = verts far out in |x|, legs = verts
     near the ground split by side/quadrant, head = top/front cluster, jaw =
     front verts below the mouth line, ...). Every landmark is printed and
     written to --json so a wrong guess is visible, not silent.
  3. Builds the armature. The root bone is named `Hips` because
     VisualUnit._strip_horizontal_root_motion() pins that bone's X/Z.
  4. Skins with its OWN weights: each vertex may only bind to the bones of its
     region (a wing vert never takes leg weight), blended 1/d^4 over the two
     nearest allowed bones. Blender's bone-heat is not used -- it fails on
     Meshy's non-manifold meshes.
  5. Authors procedural clips per kind, sampled every frame at 30 fps:
       idle (loops) walk (loops) attack skill hurt death   [+ fly for birds]
     Attack impact lands at ~40% of the clip; death ends lying still.
  6. Exports one .glb with every clip as its own animation.

Rotations are authored about WORLD axes and converted into each bone's local
frame, so they are independent of how a bone happens to be rolled. This rig's
bones are ours and their rest frames are sane -- the "corrupt bone tails"
warning in the pipeline doc applies to Meshy's rig, not this one.
"""
import bpy, sys, math, json
from mathutils import Vector, Quaternion, Matrix

FPS = 30


def opts():
    a = sys.argv[sys.argv.index("--") + 1:]
    o = {"model": None, "kind": None, "out": None, "json": None, "fly": "0", "dive": "0", "legs": "3", "blend": None}
    i = 0
    while i < len(a):
        o[a[i][2:]] = a[i + 1]
        i += 2
    return o


# ── mesh prep ────────────────────────────────────────────────────────────────

def load_body(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Icosphere") or ob.type not in ("MESH",):
            if ob.type != "MESH":
                bpy.data.objects.remove(ob, do_unlink=True)
    meshes = [ob for ob in bpy.data.objects if ob.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for ob in meshes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    V = [v.co for v in body.data.vertices]
    mn = Vector((min(v.x for v in V), min(v.y for v in V), min(v.z for v in V)))
    mx = Vector((max(v.x for v in V), max(v.y for v in V), max(v.z for v in V)))
    shift = Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
    body.data.transform(Matrix.Translation(shift))
    body.name = "Body"
    return body


def centroid(pts):
    if not pts:
        return None
    return sum(pts, Vector()) / len(pts)


# ── landmarks ────────────────────────────────────────────────────────────────

def bird_landmarks(V):
    H = max(v.z for v in V)
    W = max(abs(v.x) for v in V)
    ymin, ymax = min(v.y for v in V), max(v.y for v in V)
    D = ymax - ymin
    # Wings: everything far out to the side. Spread wings (Gale Warden) reach
    # ~1.0 of the half-width; folded ones (Skyrender) hug the body, so the cut
    # is relative to the core body's width measured at mid height.
    mid = [v for v in V if 0.35 * H < v.z < 0.6 * H]
    core = sorted(abs(v.x) for v in mid)
    core_w = core[int(len(core) * 0.55)] if core else 0.25 * W
    wx = max(core_w, 0.28 * W)
    body = [v for v in V if abs(v.x) < wx]
    # Body landmarks are measured against the BODY's height, not the whole
    # mesh's: raised spread wings (Skyrender v002, 2026-10-04) tower above the
    # head, and "head = top quarter of H" then found nothing but sky.
    H = max(v.z for v in body)
    L = {"H": H, "W": W, "wing_cut_x": wx}
    L["hips"] = centroid([v for v in body if 0.2 * H < v.z < 0.45 * H])
    L["chest"] = centroid([v for v in body if 0.45 * H < v.z < 0.65 * H])
    head = [v for v in body if v.z > 0.75 * H]
    L["head"] = centroid(head)
    L["head_top"] = Vector((L["head"].x, L["head"].y, H))
    L["beak"] = min(head, key=lambda v: v.y).copy()
    tail = [v for v in body if v.y > ymin + 0.72 * D and v.z < 0.55 * H]
    L["tail"] = centroid(tail) if len(tail) > 30 else None
    if L["tail"] is not None:
        L["tail_tip"] = max(tail, key=lambda v: (v - L["hips"]).length).copy()
    feet = [v for v in body if v.z < 0.12 * H]
    for side, sgn in (("Left", 1), ("Right", -1)):     # character's left == +X
        f = [v for v in feet if v.x * sgn > 0]
        L["foot_" + side] = centroid(f) or Vector((0.1 * sgn, 0, 0))
        w = sorted([v for v in V if v.x * sgn > wx], key=lambda v: abs(v.x))
        if len(w) < 30:                       # no wing found on this side
            w = sorted([v for v in V if v.x * sgn > 0.6 * wx], key=lambda v: abs(v.x))
        root = centroid(w[: max(10, len(w) // 10)])
        tip = centroid(w[-max(10, len(w) // 20):])
        L["wing_root_" + side] = Vector((wx * 0.8 * sgn, root.y, root.z))
        L["wing_tip_" + side] = tip
    return L


def quad_landmarks(V):
    H = max(v.z for v in V)
    W = max(abs(v.x) for v in V)
    ymin, ymax = min(v.y for v in V), max(v.y for v in V)
    D = ymax - ymin
    L = {"H": H, "W": W, "ymin": ymin, "ymax": ymax}
    trunk = [v for v in V if v.z > 0.25 * H]
    L["hips"] = centroid([v for v in trunk if v.y > ymin + 0.6 * D]) or Vector((0, ymax * 0.5, 0.45 * H))
    L["chest"] = centroid([v for v in trunk if ymin + 0.25 * D < v.y < ymin + 0.6 * D])
    front = [v for v in V if v.y < ymin + 0.3 * D and v.z > 0.15 * H]
    L["head"] = centroid(front)
    # Lure / antenna: anything that rises clearly above the trunk's back line.
    back_z = sorted(v.z for v in trunk)[int(len(trunk) * 0.97)]
    lure = [v for v in V if v.z > back_z and v.y < ymin + 0.6 * D]
    if len(lure) > 30:
        L["lure_base"] = min(lure, key=lambda v: v.z).copy()
        L["lure_tip"] = min(lure, key=lambda v: v.y).copy()
    # Mouth line: the jaw hinges at the rear of the front block, at its mid height.
    fz = sorted(v.z for v in front)
    L["mouth_z"] = fz[len(fz) // 2] if fz else 0.45 * H
    L["jaw_pivot"] = Vector((0, ymin + 0.42 * D, L["mouth_z"]))
    L["jaw_tip"] = Vector((0, ymin, L["mouth_z"] - 0.15 * H))
    feet = [v for v in V if v.z < 0.14 * H]
    yc = (ymin + ymax) / 2
    for name, sx, front_leg in (("FrontLeft", 1, True), ("FrontRight", -1, True),
                                ("BackLeft", 1, False), ("BackRight", -1, False)):
        f = [v for v in feet if v.x * sx > 0.05 * W and ((v.y < yc) == front_leg)]
        L["foot_" + name] = centroid(f) or Vector((0.6 * W * sx, yc + (-0.3 if front_leg else 0.3) * D, 0))
    return L


# ── armature ─────────────────────────────────────────────────────────────────

def build_armature(bones):
    """bones: list of (name, head, tail, parent)."""
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    for name, h, t, parent in bones:
        b = eb.new(name)
        b.head, b.tail = h, t
        if (b.tail - b.head).length < 1e-3:
            b.tail = b.head + Vector((0, 0, 0.02))
        if parent:
            b.parent = eb[parent]
    # Leaf END bones, like Meshy's head_end. Model3DSprite.character_bounds()
    # measures bone ORIGINS (heads) only, so without these the head top, wing
    # tips and feet are not counted, the body measures short, and the engine
    # scales it up -- Skyrender rendered ~1.5x too big before these existed.
    # They carry no weights (skin() only binds a vertex to its region's bones).
    parents = {b.parent.name for b in eb if b.parent}
    for name in [b.name for b in eb if b.name not in parents]:
        src = eb[name]
        e = eb.new(name + "_end")
        e.head = src.tail.copy()
        e.tail = src.tail + (src.tail - src.head).normalized() * 0.01
        e.parent = src
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def skin(body, arm, region_of):
    """region_of(v) -> list of bone names this vertex may bind to."""
    segs = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm.data.bones}
    groups = {n: body.vertex_groups.new(name=n) for n in segs}
    for v in body.data.vertices:
        allowed = region_of(v.co)
        ds = sorted((seg_dist(v.co, *segs[n]), n) for n in allowed)[:2]
        ws = [(1.0 / max(d, 1e-4) ** 4, n) for d, n in ds]
        tot = sum(w for w, _ in ws)
        for w, n in ws:
            if w / tot > 0.02:
                groups[n].add([v.index], w / tot, "REPLACE")
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    body.parent = arm


# ── animation helpers ────────────────────────────────────────────────────────

class Clip:
    def __init__(self, arm, name, frames, loop=False):
        self.arm, self.name, self.frames, self.loop = arm, name, frames, loop

    def bake(self, pose_fn):
        """pose_fn(t in [0,1]) -> {bone: (world_axis, deg)} or {bone: [(axis,deg),..]}
        plus optional '_hips' -> world offset Vector."""
        arm = self.arm
        act = bpy.data.actions.new(self.name)
        act.use_fake_user = True
        ad = arm.animation_data or arm.animation_data_create()
        ad.action = act
        if hasattr(ad, "action_slot") and getattr(act, "slots", None) and len(act.slots):
            ad.action_slot = act.slots[0]
        n = self.frames
        for f in range(n + 1):
            t = f / n
            pose = pose_fn(t)
            for pb in arm.pose.bones:
                rest = pb.bone.matrix_local.to_3x3()
                q = Quaternion()
                spec = pose.get(pb.name, [])
                if spec and not isinstance(spec, list):
                    spec = [spec]
                for axis, deg in spec:
                    local_axis = (rest.inverted() @ Vector(axis)).normalized()
                    q = q @ Quaternion(local_axis, math.radians(deg))
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = q
                pb.location = Vector()
                if pb.name == "Hips" and "_hips" in pose:
                    pb.location = rest.inverted() @ Vector(pose["_hips"])
                pb.scale = Vector(pose["_scale"]) if (pb.name == "Hips" and "_scale" in pose) else Vector((1, 1, 1))
                # '_bscale' {bone: s}: UNIFORM per-bone scale (children inherit it).
                # Uniform only -- a non-uniform parent scale shears rotated
                # children, which glTF bone TRS cannot represent.
                if pb.name in pose.get("_bscale", {}):
                    pb.scale = Vector((1, 1, 1)) * float(pose["_bscale"][pb.name])
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
                pb.keyframe_insert("scale", frame=f)
        if hasattr(ad, "action_slot") and len(act.slots):
            ad.action_slot = act.slots[0]
        return act


def ease(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def pulse(t, a, peak, b):
    """0 before a, rises to 1 at peak, back to 0 at b (smooth)."""
    if t <= a or t >= b:
        return 0.0
    return ease((t - a) / (peak - a)) if t < peak else 1.0 - ease((t - peak) / (b - peak))


def ramp(t, a, b):
    return ease((t - a) / max(b - a, 1e-6))


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
S = math.sin
TAU = 2 * math.pi


# ── BIRD ─────────────────────────────────────────────────────────────────────

def rig_bird(body, fly, spread=False):
    V = [v.co.copy() for v in body.data.vertices]
    L = bird_landmarks(V)
    H = L["H"]
    hips, chest, head = L["hips"], L["chest"], L["head"]
    neck = chest.lerp(head, 0.45)
    bones = [
        ("Hips", hips, chest.lerp(hips, 0.5), None),
        ("Spine", chest.lerp(hips, 0.5), neck, "Hips"),
        ("Head", neck, L["head_top"].lerp(L["beak"], 0.5), "Spine"),
    ]
    if L["tail"] is not None:
        bones.append(("Tail", hips, L["tail_tip"], "Hips"))
    for side in ("Left", "Right"):
        r, tip = L["wing_root_" + side], L["wing_tip_" + side]
        m = r.lerp(tip, 0.5)
        bones += [(side + "Wing1", r, m, "Spine"), (side + "Wing2", m, tip, side + "Wing1")]
        ft = L["foot_" + side]
        knee = Vector((ft.x, ft.y, 0.28 * H))
        bones += [(side + "Leg", Vector((ft.x * 0.8, hips.y, hips.z * 0.9)), knee, "Hips"),
                  (side + "Foot", knee, Vector((ft.x, ft.y - 0.05 * H, 0.0)), side + "Leg")]
    arm = build_armature(bones)
    wx = L["wing_cut_x"]
    has_tail = L["tail"] is not None

    def region(p):
        side = "Left" if p.x > 0 else "Right"
        if abs(p.x) > wx * 0.85 and p.z > 0.25 * H:
            return ["Spine", side + "Wing1", side + "Wing2"]
        if p.z < 0.3 * H and abs(p.x) > 0.02:
            base = ["Hips", side + "Leg", side + "Foot"]
            return base + (["Tail"] if has_tail else [])
        base = ["Hips", "Spine", "Head"]
        return base + (["Tail"] if has_tail else [])
    skin(body, arm, region)

    # `--spread 1` (Skyrender v002, 2026-10-04): the body was generated with
    # its wings SPREAD (and raised), so on the ground every clip carries a
    # resting DROOP -- the half-lowered "mantling" of a vulture over its kill --
    # and only the flight clip flaps from the true open span. A folded-wing body
    # (Gale Warden, Skyrender v001) keeps rest 0 and behaves exactly as before.
    REST_UP, REST_TIP = (-48.0, -18.0) if spread else (0.0, 0.0)

    def wings(up_deg, sweep_deg=0.0, tip_deg=None, rest=True):
        # +up raises the wing. Left wing raises by rotating about -Y (front axis
        # is -Y, so about +Y would drop it); mirrored for the right.
        tip = up_deg * 0.6 if tip_deg is None else tip_deg
        if rest:
            up_deg += REST_UP
            tip += REST_TIP
        return {"LeftWing1": [(Y, -up_deg), (Z, sweep_deg)], "LeftWing2": (Y, -tip),
                "RightWing1": [(Y, up_deg), (Z, -sweep_deg)], "RightWing2": (Y, tip)}

    clips = []

    def idle(t):
        b = S(TAU * t)
        p = wings(4 * b, tip_deg=3 * b)
        p.update({"Spine": (X, 2.5 * b), "Head": [(X, -2 * b), (Z, 6 * S(TAU * t + 1.0))],
                  "Tail": (X, 3 * S(TAU * t + 0.6)), "_hips": (0, 0, 0.012 * H * b)})
        return p
    clips.append(("idle", 48, idle))

    def walk(t):           # flapping hop -- birds cross the board airborne
        f = S(TAU * 2 * t)
        p = wings(38 * f, tip_deg=25 * S(TAU * 2 * t - 0.8))
        p.update({"Spine": (X, 8), "Head": (X, -6), "Tail": (X, -6 * f),
                  "LeftLeg": (X, -25), "RightLeg": (X, -25), "LeftFoot": (X, 30), "RightFoot": (X, 30),
                  "_hips": (0, 0, H * (0.10 + 0.05 * abs(S(TAU * 2 * t))))})
        return p
    clips.append(("walk", 24, walk))

    def attack(t):         # rear back, then lunge-strike with the beak + wing flare
        back = pulse(t, 0.0, 0.3, 0.45)
        hit = pulse(t, 0.3, 0.42, 0.85)
        p = wings(30 * back + 45 * hit, sweep_deg=-20 * hit, tip_deg=20 * back + 30 * hit)
        p.update({"Spine": (X, -18 * back + 30 * hit), "Head": (X, -10 * back + 25 * hit),
                  "Tail": (X, 10 * back - 12 * hit),
                  "_hips": (0, -0.12 * H * hit + 0.05 * H * back, 0.03 * H * hit)})
        return p
    clips.append(("attack", 26, attack))

    def skill(t):          # one huge downbeat: wings high, then a hard gust forward
        up = pulse(t, 0.0, 0.35, 0.5)
        down = pulse(t, 0.38, 0.5, 0.95)
        p = wings(75 * up - 35 * down, sweep_deg=25 * down, tip_deg=50 * up - 30 * down)
        p.update({"Spine": (X, -12 * up + 14 * down), "Head": (X, -8 * up + 10 * down),
                  "Tail": (X, 15 * down), "_hips": (0, 0.03 * H * down, 0.12 * H * up)})
        return p
    clips.append(("skill", 30, skill))

    def hurt(t):
        k = pulse(t, 0.0, 0.25, 1.0)
        p = wings(25 * k, sweep_deg=10 * k)
        p.update({"Spine": (X, -16 * k), "Head": [(X, -20 * k), (Z, 12 * k)],
                  "_hips": (0, 0.06 * H * k, 0)})
        return p
    clips.append(("hurt", 15, hurt))

    def death(t):          # wings droop, the body keels over sideways and lies still
        k = ramp(t, 0.0, 0.75)
        flop = pulse(t, 0.0, 0.2, 0.5)
        p = wings(30 * flop - 50 * k, tip_deg=-30 * k)
        p.update({"Hips": (Y, 80 * k), "Spine": (X, 20 * k), "Head": [(X, 35 * k), (Z, 20 * k)],
                  "LeftLeg": (X, 30 * k), "RightLeg": (X, 30 * k),
                  "_hips": (0, 0, H * (0.08 * flop - 0.22 * k))})
        return p
    clips.append(("death", 30, death))

    if fly:
        def flyc(t):       # hover loop for an aloft window
            f = S(TAU * 2 * t)
            if spread:     # full wingbeats from the open span: high up, hard down
                p = wings(-8 + 42 * f, tip_deg=-6 + 32 * S(TAU * 2 * t - 0.8), rest=False)
            else:
                p = wings(45 * f, tip_deg=30 * S(TAU * 2 * t - 0.8))
            p.update({"Spine": (X, 6), "LeftLeg": (X, -35), "RightLeg": (X, -35),
                      "LeftFoot": (X, 40), "RightFoot": (X, 40), "Tail": (X, -5 * f),
                      "_hips": (0, 0, H * (0.30 + 0.04 * f))})
            return p
        clips.append(("fly", 24, flyc))
    return arm, L, clips


# ── QUADRUPED (with jaw + optional lure) ─────────────────────────────────────

def rig_quad(body, dive=False):
    V = [v.co.copy() for v in body.data.vertices]
    L = quad_landmarks(V)
    H = L["H"]
    hips, chest, head = L["hips"], L["chest"], L["head"]
    bones = [
        # Three spine segments (Hips/Spine/Chest), not two, so the body can
        # FLEX -- a breach needs the spine to bend through the arc (2026-10-02).
        ("Hips", hips, hips.lerp(chest, 0.34), None),
        ("Spine", hips.lerp(chest, 0.34), hips.lerp(chest, 0.67), "Hips"),
        ("Chest", hips.lerp(chest, 0.67), chest, "Spine"),
        ("Head", chest, Vector((head.x, head.y, head.z + 0.1 * H)), "Chest"),
        ("Jaw", L["jaw_pivot"], L["jaw_tip"], "Head"),
    ]
    if "lure_base" in L:
        lm = L["lure_base"].lerp(L["lure_tip"], 0.5) + Vector((0, 0, 0.06 * H))
        bones += [("Lure1", L["lure_base"], lm, "Head"), ("Lure2", lm, L["lure_tip"], "Lure1")]
    for leg in ("FrontLeft", "FrontRight", "BackLeft", "BackRight"):
        ft = L["foot_" + leg]
        par = "Chest" if leg.startswith("Front") else "Hips"
        top = Vector((ft.x * 0.75, ft.y, 0.42 * H))
        bones += [(leg + "Leg", top, Vector((ft.x, ft.y, 0.0)), par)]
    arm = build_armature(bones)
    ymin, ymax = L["ymin"], L["ymax"]
    D = ymax - ymin
    has_lure = "lure_base" in L
    lure_z = L["lure_base"].z if has_lure else 9e9

    def region(p):
        if has_lure and p.z >= lure_z - 0.01 * H and p.y < ymin + 0.6 * D:
            return ["Lure1", "Lure2", "Head"]
        if p.z < 0.2 * H and abs(p.x) > 0.25 * L["W"]:
            leg = ("Front" if p.y < (ymin + ymax) / 2 else "Back") + ("Left" if p.x > 0 else "Right")
            return [leg + "Leg", "Chest" if leg.startswith("Front") else "Hips"]
        if p.y < L["jaw_pivot"].y and p.z < L["mouth_z"]:
            return ["Jaw", "Head"]
        if p.y < ymin + 0.45 * D:
            return ["Head", "Chest"]
        return ["Hips", "Spine", "Chest"]
    skin(body, arm, region)

    def legs(phase, amp):
        out = {}
        for leg, off in (("FrontLeft", 0.0), ("BackRight", 0.0), ("FrontRight", 0.5), ("BackLeft", 0.5)):
            out[leg + "Leg"] = (X, amp * S(TAU * (phase + off)))
        return out

    def lure(t, amp):
        return {"Lure1": (X, amp * S(TAU * t)), "Lure2": (X, amp * 1.4 * S(TAU * t - 0.7))} if has_lure else {}

    clips = []

    def idle(t):
        b = S(TAU * t)
        p = {"Spine": (X, 1.5 * b), "Head": (X, -1.5 * b), "Jaw": (X, 4 + 4 * (0.5 + 0.5 * b)),
             "_hips": (0, 0, 0.01 * H * b)}
        p.update(lure(t, 10))
        return p
    clips.append(("idle", 60, idle))

    def walk(t):
        p = legs(2 * t, 22)
        p.update({"Spine": (Z, 4 * S(TAU * 2 * t)), "Head": (Z, -4 * S(TAU * 2 * t)),
                  "Jaw": (X, 6), "_hips": (0, 0, 0.025 * H * abs(S(TAU * 2 * t)))})
        p.update(lure(2 * t, 14))
        return p
    clips.append(("walk", 30, walk))

    def attack(t):         # gape wide, lunge and SNAP shut at ~40%
        gape = pulse(t, 0.0, 0.32, 0.42)
        lunge = pulse(t, 0.25, 0.42, 0.9)
        p = {"Jaw": (X, 45 * gape + 3), "Head": (X, -12 * gape + 10 * lunge),
             "Spine": (X, 6 * lunge), "FrontLeftLeg": (X, -15 * lunge), "FrontRightLeg": (X, -15 * lunge),
             "_hips": (0, -0.12 * H * lunge + 0.03 * H * gape, -0.03 * H * lunge)}
        p.update(lure(t, 20 * lunge))
        return p
    clips.append(("attack", 26, attack))

    def skill(t):          # rear up and roar, lure flaring
        rise = pulse(t, 0.0, 0.35, 0.9)
        roar = pulse(t, 0.25, 0.4, 0.85)
        p = {"Spine": (X, -14 * rise), "Head": (X, -18 * rise), "Jaw": (X, 55 * roar),
             "FrontLeftLeg": (X, -25 * rise), "FrontRightLeg": (X, -25 * rise),
             "_hips": (0, 0, 0.05 * H * rise)}
        p.update(lure(t * 3, 25 * roar))
        return p
    clips.append(("skill", 34, skill))

    def hurt(t):
        k = pulse(t, 0.0, 0.25, 1.0)
        return {"Spine": (X, -8 * k), "Head": [(X, -14 * k), (Z, 10 * k)], "Jaw": (X, 20 * k),
                "_hips": (0, 0.05 * H * k, 0)}
    clips.append(("hurt", 15, hurt))

    def death(t):          # legs give, it rolls onto its side, jaw slack
        k = ramp(t, 0.05, 0.8)
        p = {"Hips": (Y, -75 * k), "Head": (X, 15 * k), "Jaw": (X, 30 * k),
             "FrontLeftLeg": (X, 30 * k), "FrontRightLeg": (X, -20 * k),
             "BackLeftLeg": (X, 25 * k), "BackRightLeg": (X, -25 * k),
             "_hips": (0, 0, -0.1 * H * k)}
        if has_lure:
            p.update({"Lure1": (X, 40 * k), "Lure2": (X, 30 * k)})
        return p
    clips.append(("death", 32, death))

    if dive:
        # Drowned Maw "Abyssal Breach" (owner design 2026-10-02, reworked same
        # day: "he should slowly go down, not just disappear" / "it looks like
        # we're just raising and lowering the character"). The board is the
        # water; Model3DSprite.set_waterline() hides everything below it, so
        # these clips really travel THROUGH the surface.
        #
        # Both are driven by the body's own physics instead of a lift:
        #   - the ROOT follows a projectile arc (breach) or a forward plunge (dive)
        #   - PITCH follows the arc's velocity -- nose up while rising, nose down
        #     while falling -- distributed down the spine with the HEAD LEADING
        #     and the HIPS TRAILING, so the body flexes through the motion like a
        #     fish/whale breach instead of rotating as one block
        #   - legs, jaw and lure react to the phase (tucked while airborne,
        #     reaching on landing, kicking while sinking)
        # Pitching about the hips would swing the whole body around its rear, so
        # every pitch is compensated to rotate about the body's CENTRE.
        centre = hips.lerp(chest, 0.5)

        def about_centre(deg):
            # world offset that makes a root pitch of `deg` pivot at the centre
            r = Matrix.Rotation(math.radians(deg), 3, Vector(X))
            v = centre - hips
            return -(r @ v - v)

        def spine_pitch(total, lead):
            # split a body pitch down the chain; `lead` (deg) extra on the
            # front bones and less on the back gives the travelling flex.
            return {"Spine": (X, 0.22 * total + 0.5 * lead), "Chest": (X, 0.22 * total + lead),
                    "Head": (X, 0.16 * total + 1.2 * lead)}

        def dive_c(t):
            # 0-0.25 rear up and gape | 0.25-0.45 tip forward over the surface |
            # 0.45-1.0 slide down through it nose-first, hind legs kicking.
            rear = pulse(t, 0.0, 0.22, 0.42)
            tip = ramp(t, 0.22, 0.5)
            sink = ramp(t, 0.35, 1.0) ** 1.4
            body = -22 * rear + 48 * tip                    # nose down as it goes under
            flex = 10 * S(TAU * 2.2 * t) * ramp(t, 0.4, 0.6)
            p = {"Hips": (X, 0.4 * body)}
            p.update(spine_pitch(body, flex))
            off = about_centre(0.4 * body)
            p["_hips"] = (off.x, off.y - 0.18 * H * tip - 0.12 * H * sink,
                          off.z + 0.07 * H * rear - 1.55 * H * sink)
            p["Jaw"] = (X, 6 + 30 * rear + 10 * tip * (1 - sink))
            kick = 28 * S(TAU * 3.0 * t) * ramp(t, 0.45, 0.6)
            p.update({"FrontLeftLeg": (X, -30 * rear - 25 * tip), "FrontRightLeg": (X, -30 * rear - 25 * tip),
                      "BackLeftLeg": (X, 15 * rear + 20 * tip + kick), "BackRightLeg": (X, 15 * rear + 20 * tip - kick)})
            if has_lure:   # the lure whips back and is the last thing to go under
                p.update({"Lure1": (X, -25 * tip - 10 * sink), "Lure2": (X, -35 * tip + 12 * S(TAU * 3 * t))})
            return p
        clips.append(("dive", 36, dive_c))

        # Projectile root: under the surface -> peak ~0.31H -> lands at s = 1.
        Z0, A, B = -1.4, -3.5, 4.9        # z(s) = (A s^2 + B s + Z0) * H, peak at s = 0.7
        T0, T1 = 0.06, 0.44               # launch .. impact (AutoBattleManager.MAW_BREACH_IMPACT)

        def breach_c(t):
            s = max(0.0, min(1.0, (t - T0) / (T1 - T0)))
            z = (A * s * s + B * s + Z0) * H if t < T1 else 0.0
            vz = (2 * A * s + B)                            # d z / d s, in H units
            airborne = 1.0 if T0 <= t < T1 else 0.0
            body = -max(-28.0, min(62.0, vz * 13.0)) * airborne   # nose up rising, down falling
            if t < T0:
                body = -62.0
            # head leads the turn over the crest: look ahead along the arc
            s2 = min(1.0, s + 0.12)
            lead = (-max(-28.0, min(62.0, (2 * A * s2 + B) * 13.0)) - body) * airborne
            land = pulse(t, T1 - 0.01, T1 + 0.06, 0.75)      # impact squash, then rebound
            wob = S(TAU * 3.0 * (t - T1)) * (1 - ramp(t, T1, 0.85)) if t >= T1 else 0.0
            body += 12 * land + 6 * wob
            p = {"Hips": (X, 0.4 * body)}
            p.update(spine_pitch(body, lead + 8 * S(TAU * 2.5 * t) * airborne))
            p["Head"] = [p["Head"], (Z, 10 * wob)]          # head shake on landing
            off = about_centre(0.4 * body)
            p["_hips"] = (off.x, off.y + 0.25 * H * (1 - s) * airborne,
                          off.z + z - 0.07 * H * land)
            gape = ramp(t, 0.0, 0.2) * (1 - ramp(t, T1 - 0.08, T1))
            p["Jaw"] = (X, 6 + 34 * gape + 6 * land)
            tuck = airborne * (1 - ramp(t, T1 - 0.12, T1))
            reach = pulse(t, T1 - 0.12, T1, T1 + 0.25)
            p.update({"FrontLeftLeg": (X, 35 * tuck - 30 * reach), "FrontRightLeg": (X, 35 * tuck - 30 * reach),
                      "BackLeftLeg": (X, -40 * tuck + 15 * land), "BackRightLeg": (X, -40 * tuck + 15 * land)})
            if has_lure:   # lure streams back in the air, snaps forward on impact
                p.update({"Lure1": (X, -30 * tuck + 25 * land), "Lure2": (X, -40 * tuck + 35 * land + 15 * wob)})
            return p
        clips.append(("breach", 36, breach_c))
    return arm, L, clips


# ── shared: limb chains ──────────────────────────────────────────────────────

def chain_joints(pts, root, n_bones=3):
    """Joints for a limb made of `pts`: order them by distance from `root`
    (where the limb leaves the body) and take centroids of distance quantiles.
    Curled tips pull the last joint inward a little -- fine for a wiggle."""
    if len(pts) < 12:
        return None
    ds = sorted(pts, key=lambda p: (p - root).length)
    n = len(ds)
    qs = [0.0] + [(i + 1) / n_bones for i in range(n_bones)]
    joints = []
    for i, q in enumerate(qs):
        a = int(max(0, (q - 0.08) * n)) if i else 0
        b = int(min(n, (q + 0.08) * n)) if i else max(4, int(0.08 * n))
        joints.append(centroid(ds[a:max(b, a + 1)]))
    return joints


def sector_of(p, c, n):
    ang = math.atan2(p.y - c.y, p.x - c.x) % TAU
    return int(ang / (TAU / n)) % n


def add_chain(bones, name, joints, parent):
    for i in range(len(joints) - 1):
        bones.append((f"{name}_{i + 1}", joints[i], joints[i + 1], parent if i == 0 else f"{name}_{i}"))
    return [f"{name}_{i + 1}" for i in range(len(joints) - 1)]


def wave_chain(names, t, amp, axis, phase=0.0, speed=1.0, lag=0.9):
    """A travelling wave down a chain: each bone bends a little more and a
    little later than its parent, so the limb curls instead of swinging stiff."""
    return {n: (axis, amp * (0.6 + 0.4 * i) * S(TAU * (speed * t + phase) - lag * i))
            for i, n in enumerate(names)}


def stepping_gait(legs, lift_axis, t, lift_deg, swing_deg, knee=0.7):
    """A real stepping cycle for many-legged bodies (crab, ant...), 2026-10-03.

    The old gaits only LIFTED each leg up and down in place -- it read as a
    twitch (owner: "like 20% of what it should be"). Here each leg runs a full
    step: SWING (first half: lifts high and sweeps forward, knee folding) then
    STANCE (second half: planted, sweeps back under the body as it pushes).
    Legs alternate in two groups -- tetrapod for 8 legs, tripod for 6 -- by
    slot parity crossed with side, so neighbours and opposite legs counter-step.

      legs       {(side, slot): [bone names, root first]}
      lift_axis  {(side, slot): world axis that LIFTS that leg (outward_axis)}
      t          cycle position; one full step per 1.0
    """
    p = {}
    for (side, slot), names in legs.items():
        ph = ((slot % 2) + (0 if side == "Left" else 1)) % 2 * 0.5
        s = (t + ph) % 1.0
        if s < 0.5:                       # swing: up and forward
            u = s / 0.5
            lift = math.sin(math.pi * u)
            sweep = -math.cos(math.pi * u)        # -1 (back) -> +1 (front)
        else:                             # stance: down, sweeping back
            u = (s - 0.5) / 0.5
            lift = 0.0
            sweep = math.cos(math.pi * u)         # +1 -> -1
        yaw = swing_deg * sweep * (1 if side == "Left" else -1)
        p[names[0]] = [(lift_axis[(side, slot)], lift_deg * lift), (Z, yaw)]
        if len(names) > 1:
            p[names[1]] = (lift_axis[(side, slot)], -knee * lift_deg * lift)
    return p


def outward_axis(root, c):
    """Horizontal axis that LIFTS a limb pointing away from c (perpendicular to
    its direction, in the ground plane)."""
    d = Vector((root.x - c.x, root.y - c.y, 0.0))
    if d.length < 1e-4:
        d = Vector((1, 0, 0))
    d.normalize()
    return tuple(Vector((0, 0, 1)).cross(d))


# ── OCTOPUS (Khagan phase 2, also the phase-3 rider) ─────────────────────────

def rig_octopus(body):
    V = [v.co.copy() for v in body.data.vertices]
    H = max(v.z for v in V)
    # Head sphere from its TOP CAP: chord radius a at depth h below the crown
    # gives r = (a^2 + h^2) / 2h. Raised arm-tentacles reach the head's equator,
    # so measuring the equator directly would swallow them.
    h = 0.12 * H
    cap = [v for v in V if v.z > H - h]
    cc = centroid(cap)
    a = sorted(math.hypot(v.x - cc.x, v.y - cc.y) for v in cap)[int(len(cap) * 0.95)]
    r = (a * a + h * h) / (2 * h)
    hc = Vector((cc.x, cc.y, H - r))
    head_bottom = hc.z - 0.85 * r
    L = {"H": H, "head_centre": hc, "head_r": r, "head_bottom": head_bottom}

    def horiz(p):
        return math.hypot(p.x - hc.x, p.y - hc.y)

    def is_arm(p):
        return p.z > head_bottom and horiz(p) > r * 1.06

    def in_head(p):
        return (p - hc).length < r * 1.02 and not is_arm(p)

    NS = 8
    bones = [("Hips", Vector((hc.x, hc.y, head_bottom)), Vector((hc.x, hc.y, hc.z)), None),
             ("Head", Vector((hc.x, hc.y, hc.z)), Vector((hc.x, hc.y, H)), "Hips")]
    arms, tents = {}, {}
    for side, sgn in (("Left", 1), ("Right", -1)):
        pts = [v for v in V if is_arm(v) and (v.x - hc.x) * sgn > 0]
        root = Vector((hc.x + sgn * r * 0.9, hc.y, head_bottom + 0.3 * r))
        j = chain_joints(pts, root)
        if j:
            j[0] = root
            arms[side] = add_chain(bones, side + "Arm", j, "Hips")
    low_root = Vector((hc.x, hc.y, head_bottom))
    for k in range(NS):
        pts = [v for v in V if not is_arm(v) and not in_head(v) and v.z < head_bottom + 0.2 * r
               and sector_of(v, hc, NS) == k]
        j = chain_joints(pts, low_root)
        if j:
            ang = (k + 0.5) * TAU / NS
            j[0] = low_root + Vector((math.cos(ang), math.sin(ang), 0)) * r * 0.35
            tents[k] = add_chain(bones, f"T{k}", j, "Hips")
    L["arms"] = list(arms)
    L["tentacles"] = sorted(tents)
    arm = build_armature(bones)

    def region(p):
        if is_arm(p):
            side = "Left" if p.x > hc.x else "Right"
            if side in arms:
                return ["Hips"] + arms[side]
        if in_head(p) or p.z >= head_bottom + 0.2 * r:
            return ["Hips", "Head"]
        k = sector_of(p, hc, NS)
        return ["Hips"] + tents.get(k, [])
    skin(body, arm, region)

    lift = {k: outward_axis(bones[[b[0] for b in bones].index(n[0])][1], hc) for k, n in tents.items()}
    arm_axis = {"Left": (0, 1, 0), "Right": (0, -1, 0)}   # +rotation curls the arm UP

    def base(t, amp=10.0, speed=1.0):
        p = {}
        for k, names in tents.items():
            p.update(wave_chain(names, t, amp, lift[k], phase=k / NS, speed=speed))
        return p

    clips = []

    def idle(t):
        p = base(t, 8)
        for side, names in arms.items():
            p.update(wave_chain(names, t, 12, arm_axis[side], phase=0.3 if side == "Left" else 0.8))
        p["Head"] = [(X, 3 * S(TAU * t)), (Z, 5 * S(TAU * t + 1))]
        p["_hips"] = (0, 0, 0.02 * H * S(TAU * t))
        return p
    clips.append(("idle", 48, idle))

    def walk(t):
        # lower tentacles push in a ripple around the ring; body bobs twice a cycle
        # Lower tentacles INTERWEAVE at the base, so neighbours bending apart
        # tear the skin between them -- keep their motion small and let the
        # arms + body bounce sell the movement (2026-10-02, measured on renders).
        p = base(t * 2, 9, speed=1.0)
        for side, names in arms.items():
            p.update(wave_chain(names, t * 2, 18, arm_axis[side], phase=0.5 if side == "Left" else 0.0))
        p["Hips"] = (X, 6)
        p["_hips"] = (0, 0, 0.05 * H * abs(S(TAU * 2 * t)))
        return p
    clips.append(("walk", 24, walk))

    def whip(t, side, a0, peak, a1, amt):
        # coil back, then lash forward: the chain bends down-forward about X
        coil = pulse(t, a0, (a0 + peak) / 2, peak)
        lash = pulse(t, peak - 0.04, peak, a1)
        names = arms.get(side, [])
        return {n: [(arm_axis[side], amt * (55 * coil - 20 * lash) * (0.7 + 0.3 * i)),
                    (X, amt * 70 * lash * (0.6 + 0.4 * i))] for i, n in enumerate(names)}

    def attack(t):         # right arm whips at the target, impact ~0.4
        p = base(t, 8)
        p.update(whip(t, "Right", 0.0, 0.4, 0.8, 1.0))
        lean = pulse(t, 0.2, 0.4, 0.8)
        p["Hips"] = (X, 12 * lean)
        p["_hips"] = (0, -0.08 * H * lean, 0)
        return p
    clips.append(("attack", 26, attack))

    def skill(t):          # Flowing Strikes: left, then right, then both
        p = base(t, 12, speed=1.5)
        l1 = whip(t, "Left", 0.0, 0.25, 0.5, 1.0)
        r1 = whip(t, "Right", 0.2, 0.45, 0.7, 1.0)
        for k in set(l1) | set(r1):
            p[k] = (l1.get(k, []) or []) + (r1.get(k, []) or [])
        lean = pulse(t, 0.1, 0.45, 0.9)
        p["Hips"] = [(X, 14 * lean), (Z, 10 * S(TAU * 2 * t) * lean)]
        p["_hips"] = (0, -0.1 * H * lean, 0.03 * H * lean)
        return p
    clips.append(("skill", 36, skill))

    def hurt(t):
        k = pulse(t, 0.0, 0.25, 1.0)
        p = base(t, 8)
        for side, names in arms.items():
            for i, n in enumerate(names):
                p[n] = (arm_axis[side], 35 * k)
        p["Hips"] = (X, -14 * k)
        p["Head"] = (Z, 12 * k)
        p["_hips"] = (0, 0.06 * H * k, 0)
        return p
    clips.append(("hurt", 15, hurt))

    def death(t):          # tentacles go limp and splay, the head slumps and sinks
        k = ramp(t, 0.0, 0.8)
        p = {}
        for kk, names in tents.items():
            for i, n in enumerate(names):
                p[n] = (lift[kk], -9 * k * (0.5 + 0.5 * i))
        for side, names in arms.items():
            for i, n in enumerate(names):
                p[n] = (arm_axis[side], -60 * k)
        p["Hips"] = [(X, 25 * k), (Y, 15 * k)]
        p["Head"] = (X, 20 * k)
        p["_hips"] = (0, 0, -0.25 * H * k)
        return p
    clips.append(("death", 30, death))

    def cling(t):          # phase 3: clamped on a hero's head, tentacles wrapped down
        p = {}
        for kk, names in tents.items():
            for i, n in enumerate(names):
                p[n] = (lift[kk], -6 - 4 * S(TAU * t - 0.6 * i))
        for side, names in arms.items():
            for i, n in enumerate(names):
                p[n] = (arm_axis[side], -50 + 10 * S(TAU * t + i))
        p["Head"] = [(X, 4 * S(TAU * t)), (Z, 8 * S(TAU * t * 2))]
        p["_hips"] = (0, 0, 0.02 * H * S(TAU * 2 * t))
        return p
    clips.append(("cling", 40, cling))
    return arm, L, clips


# ── CRAB with a RIDER (Khagan phase 1) ───────────────────────────────────────

def rig_crabrider(body, grip=None):
    V = [v.co.copy() for v in body.data.vertices]
    H = max(v.z for v in V)
    ymin, ymax = min(v.y for v in V), max(v.y for v in V)
    D = ymax - ymin
    W = max(abs(v.x) for v in V)
    # The shell is the widest solid band of the crab body: measure where the
    # mid-width body sits. Rider = everything above the shell's top surface
    # near the middle; legs = everything below the shell's underside.
    core = [v for v in V if abs(v.x) < 0.45 * W and abs(v.y - (ymin + ymax) / 2) < 0.3 * D]
    zs = sorted(v.z for v in core)
    shell_bot = zs[int(len(zs) * 0.10)]
    mid = [v for v in core if abs(v.x) < 0.2 * W]
    shell_top = sorted(v.z for v in mid if v.z < 0.65 * H)[-1] if mid else 0.5 * H
    c = Vector((0, (ymin + ymax) / 2, (shell_bot + shell_top) / 2))
    claw_y = ymin + 0.28 * D
    L = {"H": H, "shell_bot": shell_bot, "shell_top": shell_top, "centre": c}

    def is_claw(p):
        return p.y < claw_y and abs(p.x) > 0.12 * W and p.z < 0.85 * H and p.z > 0.02 * H

    def is_rider(p):
        return p.z > shell_top - 0.02 * H and not is_claw(p) and abs(p.x) < 0.75 * W

    def is_leg(p):
        return p.z < shell_bot + 0.03 * H and not is_claw(p) and math.hypot(p.x, p.y - c.y) > 0.25 * W

    def leg_slot(p):
        side = "Left" if p.x > 0 else "Right"
        ang = math.atan2(p.y - c.y, abs(p.x))           # -90 front .. +90 back
        return side, max(0, min(3, int((ang + math.pi / 2) / (math.pi / 4))))

    bones = [("Hips", Vector((c.x, c.y + 0.15 * D, c.z)), Vector((c.x, c.y - 0.15 * D, c.z)), None)]
    legs = {}
    for side, sgn in (("Left", 1), ("Right", -1)):
        for slot in range(4):
            pts = [v for v in V if is_leg(v) and leg_slot(v) == (side, slot)]
            ang = -math.pi / 2 + (slot + 0.5) * math.pi / 4
            root = Vector((c.x + sgn * 0.3 * W * math.cos(ang), c.y + 0.3 * W * math.sin(ang), shell_bot))
            j = chain_joints(pts, root, 2)
            if j:
                j[0] = root
                legs[(side, slot)] = add_chain(bones, f"{side}Leg{slot}", j, "Hips")
    claws = {}
    for side, sgn in (("Left", 1), ("Right", -1)):
        pts = [v for v in V if is_claw(v) and v.x * sgn > 0]
        root = Vector((sgn * 0.3 * W, claw_y + 0.05 * D, c.z))
        j = chain_joints(pts, root, 2)
        if j:
            j[0] = root
            claws[side] = add_chain(bones, f"{side}Claw", j, "Hips")
    rider_pts = [v for v in V if is_rider(v)]
    rtop = max(rider_pts, key=lambda p: p.z)
    rc = centroid([v for v in rider_pts if v.z > shell_top + 0.55 * (rtop.z - shell_top)])
    bones += [("Rider", Vector((rc.x, rc.y, shell_top)), Vector((rc.x, rc.y, rc.z)), "Hips"),
              ("RiderHead", Vector((rc.x, rc.y, rc.z)), Vector((rc.x, rc.y, rtop.z)), "Rider")]
    head_low = shell_top + 0.45 * (rtop.z - shell_top)
    rtents = {}
    RS = 6
    for k in range(RS):
        pts = [v for v in rider_pts if v.z < head_low and sector_of(v, rc, RS) == k
               and math.hypot(v.x - rc.x, v.y - rc.y) > 0.08 * W]
        j = chain_joints(pts, Vector((rc.x, rc.y, head_low)))
        if j:
            ang = (k + 0.5) * TAU / RS
            j[0] = Vector((rc.x, rc.y, head_low)) + Vector((math.cos(ang), math.sin(ang), 0)) * 0.06 * W
            rtents[k] = add_chain(bones, f"RT{k}", j, "Rider")
    L.update({"legs": len(legs), "claws": list(claws), "rider_tentacles": len(rtents)})
    arm = build_armature(bones)

    def region(p):
        if is_claw(p):
            side = "Left" if p.x > 0 else "Right"
            if side in claws:
                return ["Hips"] + claws[side]
        if is_rider(p):
            if p.z >= head_low or math.hypot(p.x - rc.x, p.y - rc.y) <= 0.08 * W:
                return ["Rider", "RiderHead"]
            chain = rtents.get(sector_of(p, rc, RS), [])
            # Mantle skin near an arm's root binds to the root segment only, so
            # the grip's grown outer segments (GRIP_REACH) can't drag the head
            # out into a brim.
            if math.hypot(p.x - rc.x, p.y - rc.y) <= 0.16 * W:
                return ["Rider"] + chain[:1]
            return ["Rider"] + chain
        if is_leg(p):
            names = legs.get(leg_slot(p))
            if names:
                return ["Hips"] + names
        return ["Hips"]
    skin(body, arm, region)

    lift = {key: outward_axis(bones[[b[0] for b in bones].index(n[0])][1], c) for key, n in legs.items()}
    claw_up = {"Left": (0, 1, 0), "Right": (0, -1, 0)}

    # Grip (owner 2026-10-03, v002): the rider CONTROLS the crab, so its arms
    # are wrapped over the shell instead of waving in the air -- each chain is
    # bent down (root -> tip, degrees, cumulative down the chain) so it drapes
    # over the shell and the tip curls under the rim. The wave on top is kept
    # small: a squeeze, not a wave.
    # The Meshy arms are short (0.2-0.4 vs a ~0.9-wide shell) and start just
    # above the shell top: bending the ROOT down only sinks them into it. So
    # the root stays nearly flat along the shell, the outer joints bend down
    # over the rim, and the outer part is grown (uniform, GRIP_REACH) so it
    # actually reaches the edge.
    # GRIP_REACH > 1 reaches the rim but pulls the mantle into a brim even with
    # root-only mantle weights (tested 1.3/1.45, 2026-10-03) -- left at 1.0.
    # GRIP_REACH > 1 reaches the rim but pulls the mantle into a brim even with
    # root-only mantle weights (tested 1.3/1.45, 2026-10-03) -- left at 1.0.
    # An automatic geometry drape was tried (2026-10-03) and dropped: the arms
    # curl up to head height, so no rule separated arm verts from the face.
    GRIP_DEG = (6.0, 45.0, 70.0)
    GRIP_REACH = 1.0
    # `--grip a,b,c` overrides: a body whose arms are ALREADY modelled wrapped
    # (khagan_phase1 v003, 2026-10-03) wants ~0 -- only a squeeze on top.
    if grip:
        GRIP_DEG = grip

    def rider(t, amp=8.0, sway=4.0):
        p = {"_bscale": {}}
        for k, names in rtents.items():
            if len(names) > 1:
                p["_bscale"][names[1]] = GRIP_REACH
            ax = outward_axis(Vector((rc.x + math.cos((k + .5) * TAU / RS),
                              rc.y + math.sin((k + .5) * TAU / RS), 0)), rc)
            w = wave_chain(names, t, amp * 0.3, ax, phase=k / RS)
            for i, n in enumerate(names):
                # +deg about outward_axis bends DOWN for these chains (the
                # tentacles root at the mantle and run outward; -deg cages the head)
                p[n] = [(ax, GRIP_DEG[min(i, len(GRIP_DEG) - 1)]), w[n]]
        p["Rider"] = (Z, sway * S(TAU * t))
        p["RiderHead"] = (X, 3 * S(TAU * t + 0.5))
        return p

    def gait(t, amp):
        # alternating tetrapod: legs 0,2 on one side step with 1,3 on the other
        p = {}
        for (side, slot), names in legs.items():
            ph = ((slot % 2) + (0 if side == "Left" else 1)) % 2 * 0.5
            up = max(0.0, S(TAU * (t + ph)))
            p[names[0]] = (lift[(side, slot)], amp * up)
            if len(names) > 1:
                p[names[1]] = (lift[(side, slot)], -0.6 * amp * up)
        return p

    def claws_pose(l, r):
        p = {}
        for side, deg in (("Left", l), ("Right", r)):
            for i, n in enumerate(claws.get(side, [])):
                p[n] = (claw_up[side], deg * (1.0 if i == 0 else 0.5))
        return p

    clips = []

    def idle(t):
        p = rider(t)
        p.update(claws_pose(4 * S(TAU * t), 6 * S(TAU * t + 0.8)))
        p["_hips"] = (0, 0, 0.012 * H * S(TAU * t))
        return p
    clips.append(("idle", 48, idle))

    def walk(t):
        p = rider(t * 2, 10, 6)
        # Full stepping cycle (was gait(t*2, 22): a lift-only twitch).
        p.update(stepping_gait(legs, lift, t * 2, 48.0, 26.0))
        p.update(claws_pose(8, 10))
        p["Hips"] = (Y, 3 * S(TAU * 2 * t))
        p["_hips"] = (0, 0, 0.02 * H * abs(S(TAU * 2 * t)))
        return p
    clips.append(("walk", 24, walk))

    def attack(t):         # the big claw rears and SNAPS down on the target ~0.4
        rear = pulse(t, 0.0, 0.28, 0.4)
        snap = pulse(t, 0.36, 0.42, 0.85)
        p = rider(t)
        big = "Left" if "Left" in claws else "Right"
        names = claws.get(big, [])
        for i, n in enumerate(names):
            p[n] = [(claw_up[big], (40 * rear - 25 * snap) * (1.0 if i == 0 else 0.6)), (X, 30 * snap)]
        p["Hips"] = (X, -5 * rear + 8 * snap)
        p["_hips"] = (0, -0.05 * H * snap, 0)
        return p
    clips.append(("attack", 26, attack))

    def skill(t):          # Shell Slam: the front rears up, then the whole shell slams down
        up = pulse(t, 0.0, 0.35, 0.45)
        slam = pulse(t, 0.4, 0.45, 0.9)
        p = rider(t, 14, 8)
        p.update(claws_pose(35 * up, 35 * up))
        for (side, slot), names in legs.items():
            p[names[0]] = (lift[(side, slot)], 18 * slam * (1 if slot < 2 else 0.6))
        p["Hips"] = (X, -22 * up + 6 * slam)
        p["Rider"] = (X, 10 * up - 8 * slam)
        p["_hips"] = (0, 0, 0.12 * H * up - 0.06 * H * slam)
        return p
    clips.append(("skill", 34, skill))

    def hurt(t):
        k = pulse(t, 0.0, 0.25, 1.0)
        p = rider(t, 12, 10 * k)
        p.update(claws_pose(20 * k, 20 * k))
        p["Hips"] = [(X, -8 * k), (Y, 6 * k)]
        p["_hips"] = (0, 0.04 * H * k, 0)
        return p
    clips.append(("hurt", 15, hurt))

    def death(t):          # legs buckle, the shell drops, the rider is thrown back
        k = ramp(t, 0.0, 0.7)
        p = {}
        for (side, slot), names in legs.items():
            p[names[0]] = (lift[(side, slot)], -30 * k)
        p.update(claws_pose(-30 * k, -30 * k))
        p["Rider"] = (X, -35 * k)
        p["_hips"] = (0, 0, -0.18 * H * k)
        return p
    clips.append(("death", 30, death))
    return arm, L, clips


# ── INSECT (ant, beetle): N legs per side + a head that bites ───────────────

def rig_insect(body, per_side=3):
    V = [v.co.copy() for v in body.data.vertices]
    H = max(v.z for v in V)
    ymin, ymax = min(v.y for v in V), max(v.y for v in V)
    D = ymax - ymin
    W = max(abs(v.x) for v in V)
    yc = (ymin + ymax) / 2
    # body core = the central band; legs = thin parts out to the sides near
    # the ground; head = the front block of the core.
    core = [v for v in V if abs(v.x) < 0.3 * W]
    cz = sorted(v.z for v in core)[len(core) // 2]
    c = Vector((0, yc, cz))
    head_y = ymin + 0.28 * D
    L = {"H": H, "centre": c}

    def is_leg(p):
        return abs(p.x) > 0.3 * W and p.z < 0.75 * H

    def slot(p):
        side = "Left" if p.x > 0 else "Right"
        ang = math.atan2(p.y - yc, abs(p.x))
        return side, max(0, min(per_side - 1, int((ang + math.pi / 2) / (math.pi / per_side))))

    hc = centroid([v for v in core if v.y < head_y]) or Vector((0, ymin + 0.1 * D, cz))
    bones = [("Hips", Vector((0, yc + 0.25 * D, cz)), Vector((0, head_y, cz)), None),
             ("Head", Vector((0, head_y, cz)), Vector((hc.x, ymin, hc.z)), "Hips")]
    legs = {}
    for side, sgn in (("Left", 1), ("Right", -1)):
        for k in range(per_side):
            pts = [v for v in V if is_leg(v) and slot(v) == (side, k)]
            ang = -math.pi / 2 + (k + 0.5) * math.pi / per_side
            root = Vector((sgn * 0.28 * W * math.cos(ang), yc + 0.28 * W * math.sin(ang), cz))
            j = chain_joints(pts, root, 2)
            if j:
                j[0] = root
                legs[(side, k)] = add_chain(bones, f"{side}Leg{k}", j, "Hips")
    L["legs"] = len(legs)
    arm = build_armature(bones)

    def region(p):
        if is_leg(p):
            names = legs.get(slot(p))
            if names:
                return ["Hips"] + names
        if p.y < head_y:
            return ["Head", "Hips"]
        return ["Hips"]
    skin(body, arm, region)
    lift = {key: outward_axis(bones[[b[0] for b in bones].index(n[0])][1], c) for key, n in legs.items()}

    def gait(t, amp):
        p = {}
        for (side, k), names in legs.items():
            ph = ((k % 2) + (0 if side == "Left" else 1)) % 2 * 0.5   # alternating tripod
            up = max(0.0, S(TAU * (t + ph)))
            p[names[0]] = [(lift[(side, k)], amp * up), (Z, (12 if side == "Left" else -12) * S(TAU * (t + ph)))]
            if len(names) > 1:
                p[names[1]] = (lift[(side, k)], -0.5 * amp * up)
        return p

    clips = []
    clips.append(("idle", 48, lambda t: {"Head": [(X, 3 * S(TAU * t)), (Z, 4 * S(TAU * t + 1))],
                                         "_hips": (0, 0, 0.01 * H * S(TAU * t))}))

    def walk(t):
        p = gait(t * 2, 25)
        p["Head"] = (Z, 4 * S(TAU * 2 * t))
        p["_hips"] = (0, 0, 0.015 * H * abs(S(TAU * 2 * t)))
        return p
    clips.append(("walk", 24, walk))

    def attack(t):         # rear the head back, then lunge-bite ~0.4
        rear = pulse(t, 0.0, 0.3, 0.42)
        bite = pulse(t, 0.36, 0.42, 0.85)
        return {"Head": (X, -20 * rear + 25 * bite), "Hips": (X, -8 * rear + 10 * bite),
                "_hips": (0, -0.12 * H * bite, 0.04 * H * rear)}
    clips.append(("attack", 26, attack))

    def skill(t):          # rear the whole front up, then crash down
        up = pulse(t, 0.0, 0.35, 0.5)
        slam = pulse(t, 0.45, 0.5, 0.9)
        p = gait(t * 3, 15 * up)
        p.update({"Hips": (X, -25 * up + 8 * slam), "Head": (X, -15 * up + 15 * slam),
                  "_hips": (0, 0, 0.12 * H * up - 0.04 * H * slam)})
        return p
    clips.append(("skill", 32, skill))

    def hurt(t):
        k = pulse(t, 0.0, 0.25, 1.0)
        return {"Hips": [(X, -8 * k), (Y, 6 * k)], "Head": (Z, 12 * k), "_hips": (0, 0.04 * H * k, 0)}
    clips.append(("hurt", 15, hurt))

    def death(t):          # flips over, legs curl
        k = ramp(t, 0.0, 0.7)
        p = {"Hips": (Y, 160 * k), "_hips": (0, 0, 0.3 * H * pulse(t, 0.0, 0.35, 0.7))}
        for (side, kk), names in legs.items():
            for i, n in enumerate(names):
                p[n] = (lift[(side, kk)], 45 * ramp(t, 0.4, 1.0))
        return p
    clips.append(("death", 30, death))
    return arm, L, clips


# ── SERPENT: rigid coil + a raised neck chain that sways and strikes ─────────

def rig_serpent(body):
    V = [v.co.copy() for v in body.data.vertices]
    H = max(v.z for v in V)
    # the coil is the wide low mass; the neck is everything above it
    low = [v for v in V if v.z < 0.3 * H]
    coil_w = sorted(math.hypot(v.x, v.y) for v in low)[int(len(low) * 0.9)] if low else 0.3
    coil_top = 0.32 * H
    neck = [v for v in V if v.z > coil_top]
    base = centroid([v for v in neck if v.z < coil_top + 0.08 * H]) or Vector((0, 0, coil_top))
    top = max(neck, key=lambda v: v.z)
    head = centroid([v for v in neck if v.z > 0.82 * H]) or top
    pts = sorted(neck, key=lambda v: v.z)
    n = len(pts)
    joints = [base] + [centroid(pts[int(n * q):int(n * (q + 0.08)) + 1]) for q in (0.3, 0.55, 0.78)] + [head]
    bones = [("Hips", Vector((0, 0, 0)), Vector((0, 0, coil_top)), None)]
    names = add_chain(bones, "Neck", joints, "Hips")
    L = {"H": H, "coil_w": coil_w, "neck_bones": len(names)}
    arm = build_armature(bones)
    zs = [j.z for j in joints]

    def region(p):
        if p.z < coil_top - 0.04 * H:
            return ["Hips"]
        return ["Hips"] + names
    skin(body, arm, region)

    def sway(t, amp, speed=1.0):
        return {nm: [(Z, amp * (0.5 + 0.25 * i) * S(TAU * speed * t - 0.7 * i)),
                     (X, 0.4 * amp * S(TAU * speed * t * 2 - 0.5 * i))] for i, nm in enumerate(names)}

    clips = []
    clips.append(("idle", 48, lambda t: {**sway(t, 6), "_hips": (0, 0, 0)}))
    clips.append(("walk", 24, lambda t: {**sway(t * 2, 12), "Hips": (Z, 6 * S(TAU * 2 * t)),
                                         "_hips": (0, 0, 0.01 * H * abs(S(TAU * 2 * t)))}))

    def strike(t, a0, peak, a1, amt):
        coil = pulse(t, a0, (a0 + peak) / 2, peak)
        hit = pulse(t, peak - 0.05, peak, a1)
        return {nm: (X, amt * (-18 * coil + 24 * hit) * (0.6 + 0.3 * i)) for i, nm in enumerate(names)}

    clips.append(("attack", 26, lambda t: {**strike(t, 0.0, 0.4, 0.85, 1.0),
                                           "_hips": (0, -0.05 * H * pulse(t, 0.35, 0.42, 0.85), 0)}))

    def skill(t):          # rears up tall, sways, then a double strike
        p = sway(t, 10, 2)
        s1 = strike(t, 0.1, 0.45, 0.7, 1.2)
        for k in s1:
            p[k] = [p[k][0], s1[k]]
        return p
    clips.append(("skill", 34, skill))
    clips.append(("hurt", 15, lambda t: {nm: (X, -14 * pulse(t, 0.0, 0.25, 1.0) * (0.5 + 0.3 * i))
                                         for i, nm in enumerate(names)}))

    def death(t):          # the neck topples forward onto the coil
        k = ramp(t, 0.0, 0.8)
        return {nm: (X, 28 * k * (0.6 + 0.3 * i)) for i, nm in enumerate(names)} | {"_hips": (0, 0, -0.05 * H * k)}
    clips.append(("death", 30, death))
    return arm, L, clips


# ── STATIC object (cage, mound): one bone, motion is pulse / squash / sink ───

def rig_static(body):
    V = [v.co.copy() for v in body.data.vertices]
    H = max(v.z for v in V)
    bones = [("Hips", Vector((0, 0, 0)), Vector((0, 0, 0.5 * H)), None),
             ("Top", Vector((0, 0, 0.5 * H)), Vector((0, 0, H)), "Hips")]
    arm = build_armature(bones)
    skin(body, arm, lambda p: ["Hips", "Top"])
    clips = [
        ("idle", 48, lambda t: {"_hips": (0, 0, 0), "_scale": (1 + 0.025 * S(TAU * t), 1 + 0.025 * S(TAU * t), 1 - 0.02 * S(TAU * t))}),
        ("walk", 24, lambda t: {"_hips": (0, 0, 0.04 * H * abs(S(TAU * 2 * t))), "Top": (Y, 4 * S(TAU * 2 * t))}),
        ("attack", 24, lambda t: {"_scale": (1 + 0.12 * pulse(t, 0.25, 0.4, 0.8),) * 2 + (1 - 0.1 * pulse(t, 0.25, 0.4, 0.8),)}),
        ("skill", 30, lambda t: {"_scale": (1 + 0.18 * pulse(t, 0.2, 0.45, 0.9),) * 3,
                                 "_hips": (0, 0, 0.05 * H * pulse(t, 0.2, 0.45, 0.9))}),
        ("hurt", 15, lambda t: {"Top": [(X, -8 * pulse(t, 0, 0.25, 1)), (Y, 6 * pulse(t, 0, 0.25, 1))]}),
        ("death", 30, lambda t: {"_scale": (1 - 0.3 * ramp(t, 0.1, 1.0),) * 2 + (1 - 0.75 * ramp(t, 0.1, 1.0),),
                                 "Top": (Y, 15 * ramp(t, 0, 0.6))}),
    ]
    return arm, {"H": H}, clips


# ── HYDRA: four legs + tail + THREE independent neck chains ─────────────────

def rig_hydra(body):
    V = [v.co.copy() for v in body.data.vertices]
    H = max(v.z for v in V)
    ymin, ymax = min(v.y for v in V), max(v.y for v in V)
    D = ymax - ymin
    W = max(abs(v.x) for v in V)
    yc = (ymin + ymax) / 2
    # trunk height: the body mass between the legs and the neck roots
    trunk = [v for v in V if 0.2 * H < v.z < 0.5 * H and ymin + 0.25 * D < v.y < ymin + 0.75 * D]
    tz = sorted(v.z for v in trunk)[len(trunk) // 2] if trunk else 0.35 * H
    shoulder = centroid([v for v in trunk if v.y < yc]) or Vector((0, ymin + 0.35 * D, tz))
    hip = centroid([v for v in trunk if v.y >= yc]) or Vector((0, ymin + 0.65 * D, tz))
    neck_z = tz + 0.18 * H

    def is_neck(p):
        return p.z > neck_z and p.y < yc + 0.1 * D

    def is_tail(p):
        return p.y > ymin + 0.72 * D and p.z < 0.55 * H and not is_neck(p)

    def is_leg(p):
        return p.z < 0.2 * H and not is_tail(p)

    necks_v = [v for v in V if is_neck(v)]
    xs = sorted(v.x for v in necks_v)
    # three clusters along x (1-D k-means from the quantiles)
    cents = [xs[int(len(xs) * q)] for q in (0.12, 0.5, 0.88)]
    for _ in range(8):
        groups = [[], [], []]
        for v in necks_v:
            groups[min(range(3), key=lambda i: abs(v.x - cents[i]))].append(v)
        cents = [sum(g_.x for g_ in g) / len(g) if g else cents[i] for i, g in enumerate(groups)]
    order = sorted(range(3), key=lambda i: -cents[i])         # +X first = character's LEFT
    neck_names = ("NeckL", "NeckC", "NeckR")
    bones = [("Hips", hip, shoulder, None)]
    necks = {}
    for nm, gi in zip(neck_names, order):
        g = groups[gi]
        root = Vector((cents[gi] * 0.6, shoulder.y, neck_z))
        j = chain_joints(g, root, 3)
        if j:
            j[0] = root
            necks[nm] = add_chain(bones, nm, j, "Hips")
    tail_v = [v for v in V if is_tail(v)]
    tail = []
    if len(tail_v) > 30:
        j = chain_joints(tail_v, Vector((0, hip.y, tz)), 3)
        j[0] = Vector((0, hip.y, tz))
        tail = add_chain(bones, "Tail", j, "Hips")
    legs = {}
    for name, sx, front in (("FrontLeft", 1, True), ("FrontRight", -1, True),
                            ("BackLeft", 1, False), ("BackRight", -1, False)):
        f = [v for v in V if is_leg(v) and v.x * sx > 0 and ((v.y < yc) == front)]
        ft = centroid(f) or Vector((0.6 * W * sx, yc + (-0.25 if front else 0.25) * D, 0))
        top = Vector((ft.x * 0.8, ft.y, tz))
        bones.append((name + "Leg", top, Vector((ft.x, ft.y, 0.0)), "Hips"))
        legs[name] = name + "Leg"
    L = {"H": H, "necks": list(necks), "neck_x": [round(c, 3) for c in cents], "tail": len(tail)}
    arm = build_armature(bones)

    def region(p):
        if is_neck(p):
            gi = min(range(3), key=lambda i: abs(p.x - cents[i]))
            nm = neck_names[order.index(gi)]
            if nm in necks:
                return ["Hips"] + necks[nm]
        if is_tail(p) and tail:
            return ["Hips"] + tail
        if is_leg(p):
            leg = ("Front" if p.y < yc else "Back") + ("Left" if p.x > 0 else "Right") + "Leg"
            return ["Hips", leg]
        return ["Hips"]
    skin(body, arm, region)

    def neck_pose(nm, sway, pitch, ph=0.0):
        return {b: [(Z, sway * (0.5 + 0.3 * i)), (X, pitch * (0.5 + 0.35 * i))]
                for i, b in enumerate(necks.get(nm, []))}

    def tail_pose(t, amp):
        return {b: (Z, amp * (0.6 + 0.4 * i) * S(TAU * t - 0.8 * i)) for i, b in enumerate(tail)}

    def idle_necks(t, amp=7):
        p = {}
        for k, nm in enumerate(neck_names):
            p.update(neck_pose(nm, amp * S(TAU * t + k * 2.1), 3 * S(TAU * t * 2 + k)))
        return p

    clips = []

    def idle(t):
        p = idle_necks(t)
        p.update(tail_pose(t, 8))
        p["_hips"] = (0, 0, 0.01 * H * S(TAU * t))
        return p
    clips.append(("idle", 48, idle))

    def walk(t):
        p = idle_necks(t * 2, 5)
        p.update(tail_pose(t * 2, 12))
        for leg, off in (("FrontLeft", 0.0), ("BackRight", 0.0), ("FrontRight", 0.5), ("BackLeft", 0.5)):
            p[legs[leg]] = (X, 20 * S(TAU * (2 * t + off)))
        p["_hips"] = (0, 0, 0.02 * H * abs(S(TAU * 2 * t)))
        return p
    clips.append(("walk", 30, walk))

    def strike(nm, t, a0, peak, a1):
        rear = pulse(t, a0, (a0 + peak) / 2, peak)
        hit = pulse(t, peak - 0.05, peak, a1)
        return neck_pose(nm, 0, -25 * rear + 35 * hit)

    def attack(t):         # the centre head strikes ~0.4, the others sway aside
        p = idle_necks(t, 5)
        p.update(strike("NeckC", t, 0.0, 0.4, 0.85))
        p.update(tail_pose(t, 6))
        p["_hips"] = (0, -0.04 * H * pulse(t, 0.35, 0.42, 0.8), 0)
        return p
    clips.append(("attack", 26, attack))

    def skill(t):          # all three strike in a rolling chain: L, C, R
        p = tail_pose(t, 10)
        p.update(strike("NeckL", t, 0.0, 0.3, 0.55))
        p.update(strike("NeckC", t, 0.15, 0.45, 0.7))
        p.update(strike("NeckR", t, 0.3, 0.6, 0.85))
        p["Hips"] = (X, 5 * pulse(t, 0.25, 0.5, 0.9))
        return p
    clips.append(("skill", 36, skill))

    def hurt(t):
        k = pulse(t, 0.0, 0.25, 1.0)
        p = {}
        for kk, nm in enumerate(neck_names):
            p.update(neck_pose(nm, (12 if kk != 1 else 0) * k * (1 if kk == 0 else -1), -18 * k))
        p["_hips"] = (0, 0.04 * H * k, 0)
        return p
    clips.append(("hurt", 15, hurt))

    def death(t):          # the necks fall one after another, the body sinks onto its side
        p = {}
        for kk, nm in enumerate(neck_names):
            p.update(neck_pose(nm, (20 if kk == 0 else -20 if kk == 2 else 0) * ramp(t, 0.1 * kk, 0.5 + 0.1 * kk),
                               55 * ramp(t, 0.1 * kk, 0.5 + 0.1 * kk)))
        k = ramp(t, 0.3, 0.9)
        p["Hips"] = (Y, 25 * k)
        p["_hips"] = (0, 0, -0.12 * H * k)
        return p
    clips.append(("death", 34, death))
    return arm, L, clips


def main():
    o = opts()
    body = load_body(o["model"])
    if o["kind"] == "bird":
        arm, L, clips = rig_bird(body, o["fly"] == "1", o.get("spread") == "1")
    elif o["kind"] == "quad":
        arm, L, clips = rig_quad(body, o["dive"] == "1")
    elif o["kind"] == "octopus":
        arm, L, clips = rig_octopus(body)
    elif o["kind"] == "crabrider":
        grip = tuple(float(x) for x in o["grip"].split(",")) if o.get("grip") else None
        arm, L, clips = rig_crabrider(body, grip)
    elif o["kind"] == "insect":
        arm, L, clips = rig_insect(body, int(o.get("legs", "3")))
    elif o["kind"] == "serpent":
        arm, L, clips = rig_serpent(body)
    elif o["kind"] == "static":
        arm, L, clips = rig_static(body)
    elif o["kind"] == "hydra":
        arm, L, clips = rig_hydra(body)
    else:
        raise SystemExit("--kind must be bird, quad, octopus, crabrider, insect, serpent, static or hydra")
    # BOUNDS markers: unweighted bones at the mesh's crown and base. The engine
    # sizes a model from bone ORIGINS (Model3DSprite.character_bounds), and on
    # a domed body (beetle shell, tortoise, dirt mound) no limb bone reaches the
    # top -- the body measured short and rendered 2-3x too big (2026-10-03).
    zs = [v.co.z for v in body.data.vertices]
    ys = [v.co.y for v in body.data.vertices]
    yc = (min(ys) + max(ys)) / 2
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for nm, z in (("BoundsTop", max(zs)), ("BoundsBase", min(zs))):
        b = eb.new(nm)
        b.head = Vector((0, yc, z))
        b.tail = Vector((0, yc, z + 0.01))
        b.parent = eb["Hips"]
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.scene.render.fps = FPS
    for name, frames, fn in clips:
        Clip(arm, name, frames).bake(fn)
    arm.animation_data.action = bpy.data.actions["idle"]
    if hasattr(arm.animation_data, "action_slot") and len(bpy.data.actions["idle"].slots):
        arm.animation_data.action_slot = bpy.data.actions["idle"].slots[0]
    rep = {k: ([round(c, 4) for c in v] if isinstance(v, Vector) else v) for k, v in L.items()}
    rep["bones"] = [b.name for b in arm.data.bones]
    rep["clips"] = [c[0] for c in clips]
    rep["tris"] = sum(len(p.vertices) - 2 for p in body.data.polygons)
    unweighted = sum(1 for v in body.data.vertices if not any(g.weight > 0 for g in v.groups))
    rep["unweighted_verts"] = unweighted
    print("LANDMARKS", json.dumps(rep))
    if o["json"]:
        json.dump(rep, open(o["json"], "w"), indent=1)
    if o["blend"]:
        bpy.ops.wm.save_as_mainfile(filepath=o["blend"])
    bpy.ops.export_scene.gltf(filepath=o["out"], export_format="GLB", export_animations=True)
    print("wrote", o["out"])


if __name__ == "__main__":
    main()
