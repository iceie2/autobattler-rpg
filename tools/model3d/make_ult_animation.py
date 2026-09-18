"""Author Bouncer's "Gravity Drop" ultimate as a new clip. Blender script.

Meshy cannot produce this: the whole character GROWS and snaps back, and a
text-to-animation service animates a fixed skeleton — it emits bone rotations,
never scale. So the clip is built here instead.

The body is not invented from nothing. Full-body poses are SAMPLED out of the
clips the character already has, which keeps every pose anatomically plausible:

    gather  = victory @ 25    both arms up in a wide V
    tight   = attack  @ 1     guard, arms drawn in to the chest
    base    = idle    @ 1     neutral

The arc is: arms fly WIDE as he grows, then snap TIGHT as he shrinks. That reads
as dragging the whole board into himself, which is what Gravity Drop does.

TIMED TO THE EXISTING VFX. skill_effect.gd's GRAVITY_DROP already runs three
phases, and the body must land on the same beats or they fight each other:

    0.00 - 0.35   ring EXPANDS   -> plant, arms open, grow to full size
    0.35 - 0.75   ring CONTRACTS -> arms snap in, shrink hard (the pull)
    0.75 - 1.00   impact         -> settle back to neutral

Growth is animated on the ARMATURE OBJECT's scale, not on the Hips bone. The
object's origin sits at the character's feet, so object scale grows him from the
ground up with his feet planted; scaling Hips instead pivots about the pelvis and
drives the feet through the floor. Object scale is a plain glTF node animation,
so it exports cleanly.

  blender --background --python make_ult_animation.py -- \
      --model "assets/3d pipeline/hero/bouncer/bouncer.glb" \
      [--name ult] [--frames 50] [--scale 3.0] [--out other.glb] [--force]
"""
import sys
import bpy
from mathutils import Vector

DEFAULTS = {
    "name": "ult",
    "frames": 50,      # ~2.1s at 24fps
    "scale": 1.20,     # OVERALL size. Small on purpose — the WIDTH comes from
                       # the `bulk` morph target, not from scaling him up.
    "bulk": "bulk",    # shape key driven alongside the beats (add_bulk_shapekey.py)     # OVERALL size bump. Deliberately small: the read comes
                       # from BULK widening him, not from scaling him up.
}
# Where each pose comes from. Sampled, never invented — inventing full-body
# rotations blind produces broken anatomy.
#   ("clip", frame)                      -> that pose
#   ("clipA", fA, "clipB", fB, t)        -> slerp between two poses
#
# The CHARGE pose is a blend, because no single clip has a flex. attack@1 is
# elbows-in/forearms-up and victory@25 is arms-up-and-out; 35% between them lands
# on arms out to the sides with elbows bent — a double-biceps power-up pose.
POSES = {
    "base":   ("idle", 1),
    "gather": ("attack", 1, "victory", 25, 0.35),
    "tight":  ("attack", 1),
}

# BULK: per-bone scale at full charge. Blender bones run along their local Y, so
# (k, 1, k) thickens a bone WITHOUT lengthening it. That is the whole point here:
# uniform object scale just made him a taller man. He should get WIDE.
#
# The shoulders are the exception and the trick — scaling their Y lengthens the
# collarbone, which pushes the whole arm outboard and widens the silhouette
# without inflating anything.
#
# Hands are counter-scaled: they sit at the end of the spine->shoulder->arm chain
# and inherit every girth factor above them, which balloons the gloves (the same
# failure measured on the punch, where the glove hit x3.91).
# Per-bone girth scaling was TRIED AND ABANDONED — see the note in
# 3D_PIPELINE.md. Non-uniform scale in a rotated bone hierarchy shears and
# compounds: three spine bones at 1.7 gave the chest 1.7^3 and a pancake head;
# adding counters at the neck/shoulders then stretched the arms into flat planks
# and squashed the gloves into discs. The width comes from the POSE instead.
BULK = {}
# (fraction of clip, pose, size) — the three VFX phases.
# `grow` is 0 = normal size, 1 = full --scale. It is NOT a size multiplier.
BEATS = [
    (0.00, "base",   0.00),   # normal
    (0.12, "tight",  0.15),   # anticipation: coils in, just starts to swell
    (0.35, "gather", 1.00),   # fully open, fully grown  <- end of ring expand
    (0.50, "gather", 1.00),   # held at full size
    (0.75, "tight",  -0.05),  # snapped in, slight undershoot <- end of contract
    (0.88, "tight",  0.00),   # impact beat, back to true size
    (1.00, "base",   0.00),
]


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(DEFAULTS)
    o["model"], o["out"], o["force"] = None, None, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--force":
            o["force"] = True; i += 1; continue
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:], argv[i + 1]
            if k == "frames":
                v = int(v)
            elif k == "scale":
                v = float(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def assign(arm, action):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = action
    # Blender 4.4+ slotted actions: an unbound slot animates nothing while still
    # looking correctly assigned.
    if hasattr(ad, "action_slot") and getattr(action, "slots", None):
        ad.action_slot = action.slots[0]


def _read(arm, clip, frame):
    action = bpy.data.actions.get(clip)
    if action is None:
        raise SystemExit("missing source clip %r" % clip)
    assign(arm, action)
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    return {pb.name: (pb.location.copy(),
                      pb.rotation_quaternion.copy(),
                      pb.scale.copy()) for pb in arm.pose.bones}


def sample(arm, spec):
    """One pose, or a slerp between two — see POSES."""
    if len(spec) == 2:
        return _read(arm, spec[0], spec[1])
    ca, fa, cb, fb, t = spec
    a, b = _read(arm, ca, fa), _read(arm, cb, fb)
    out = {}
    for name in a:
        al, ar, asc = a[name]
        bl, br, bsc = b[name]
        out[name] = (al.lerp(bl, t), ar.slerp(br, t), asc.lerp(bsc, t))
    return out


def _fold_split_clips(path, name):
    """Merge `<name>.001` back into `<name>` in the exported .glb.

    Blender keeps the armature animation and the shape-key animation in two
    separate actions, and refuses to let them share a name — so renaming the
    second to match yields "ult.001". The glTF exporter groups by action NAME, so
    the morph weights ship as their own clip that nothing ever plays: the body
    grows but never widens, with no error anywhere.

    Merging at the file level is deterministic and needs no exporter coaxing.
    Sampler indices are local to an animation, so the incoming channels are
    re-pointed as their samplers are appended.
    """
    import json as _json, struct as _struct
    raw = open(path, "rb").read()
    off, js, bin_ = 12, None, b""
    while off < len(raw):
        ln, ty = _struct.unpack_from("<II", raw, off)
        off += 8
        chunk = raw[off:off + ln]; off += ln
        if ty == 0x4E4F534A:
            js = _json.loads(chunk)
        elif ty == 0x004E4942:
            bin_ = chunk

    anims = js.get("animations", [])
    target = next((a for a in anims if a.get("name") == name), None)
    extras = [a for a in anims if str(a.get("name", "")).startswith(name + ".")]
    if target is None or not extras:
        return

    for extra in extras:
        base = len(target["samplers"])
        target["samplers"].extend(extra["samplers"])
        for ch in extra["channels"]:
            ch = dict(ch)
            ch["sampler"] = ch["sampler"] + base
            target["channels"].append(ch)
        anims.remove(extra)
        print("  folded %r into %r (+%d channels)"
              % (extra.get("name"), name, len(extra["channels"])))

    jb = _json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * (-len(jb) % 4)
    bb = bytes(bin_) + bytes((-len(bin_)) % 4)   # bytes(n) == n zero bytes
    with open(path, "wb") as f:
        f.write(b"glTF" + _struct.pack("<II", 2, 12 + 8 + len(jb) + 8 + len(bb)))
        f.write(_struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(_struct.pack("<II", len(bb), 0x004E4942) + bb)


def _bulk_key(mesh, name):
    keys = mesh.data.shape_keys
    return keys.key_blocks.get(name) if keys else None


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")
    mesh = next(ob for ob in bpy.data.objects if ob.type == "MESH")
    for t in (arm.animation_data.nla_tracks if arm.animation_data else []):
        t.mute = True

    if bpy.data.actions.get(o["name"]) and not o["force"]:
        print("clip %r already exists. Use --force to rebuild." % o["name"])
        return

    poses = {k: sample(arm, spec) for k, spec in POSES.items()}
    for k, spec in POSES.items():
        print("  pose %-7s = %s" % (k, "%s@%d" % spec[:2] if len(spec) == 2
                                    else "%s@%d -> %s@%d @ %.0f%%"
                                         % (spec[0], spec[1], spec[2], spec[3], spec[4] * 100)))

    rest_scale = arm.scale.copy()          # Meshy rigs sit at 0.01 object scale
    span = o["frames"]

    old = bpy.data.actions.get(o["name"])
    if old:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(o["name"])
    action.use_fake_user = True
    assign(arm, action)

    for frac, pose_key, grow in BEATS:
        f = 1 + round(frac * (span - 1))
        bpy.context.scene.frame_set(f)
        pose = poses[pose_key]
        for pb in arm.pose.bones:
            loc, rot, scl = pose[pb.name]
            pb.location, pb.rotation_quaternion = loc, rot
            # Bulk rides ON TOP of whatever scale the sampled pose had, blended
            # in by `grow` so it swells and deflates with the beat.
            bulk = BULK.get(pb.name)
            if bulk and grow > 0.0:
                pb.scale = Vector((scl[i] * (1.0 + (bulk[i] - 1.0) * grow)
                                   for i in range(3)))
            else:
                pb.scale = scl
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("scale", frame=f)
        # Object-level growth: origin is at the feet, so he grows off the ground.
        s = 1.0 + (o["scale"] - 1.0) * grow
        arm.scale = rest_scale * s
        arm.keyframe_insert("scale", frame=f)

        # WIDTH comes from the morph target, which deforms the mesh directly and
        # therefore cannot shear or compound the way bone scale does.
        kb = _bulk_key(mesh, o["bulk"])
        if kb is not None:
            kb.value = max(0.0, grow)
            kb.keyframe_insert("value", frame=f)

    arm.scale = rest_scale
    print("built %r: %d frames, peak x%.1f, beats at %s"
          % (o["name"], span, o["scale"],
             ", ".join(str(1 + round(b[0] * (span - 1))) for b in BEATS)))

    # The shape key gets its OWN Blender action. Rename it to match the armature
    # action: the glTF exporter groups by action NAME, so a mismatch ships the
    # morph animation as a separate, never-played clip.
    sk = mesh.data.shape_keys
    if sk and sk.animation_data and sk.animation_data.action:
        sk.animation_data.action.name = o["name"]
        sk.animation_data.action.use_fake_user = True

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB",
                              export_morph=True, export_morph_animation=True)
    _fold_split_clips(dest, o["name"])
    print("wrote %s" % dest)


main()
