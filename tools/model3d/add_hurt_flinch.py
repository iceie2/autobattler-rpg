"""Drive the `bulk` shape key across the existing `hurt` clip. Blender script.

No new pose is authored here — hurt already has a good flinch. This just adds
a light, brief swell timed to the impact: he puffs up on the hit and settles
back down, "not much, a little" (the user's own phrasing). It reuses the same
`bulk` morph target add_bulk_shapekey.py already built for the ult, so this is
cheap: one new shape-key action, folded into the existing clip.

IMPACT FRAME. Measured, not guessed: sampled every pose bone's world position
across the clip and summed per-frame displacement. Movement peaks hard at
frames 14-18 (bone-position deltas 1.0-1.57, versus <0.1 everywhere else in a
0-68 clip) and is highest at frame 17 — that is the flinch snap, so the swell
is keyed to land there.

  blender --background --python add_hurt_flinch.py -- \
      --model "assets/3d pipeline/hero/bouncer/bouncer.glb" \
      [--clip hurt] [--amount 0.30] [--key bulk] [--out other.glb] [--force]
"""
import sys
import bpy

DEFAULTS = {
    "clip": "hurt",
    "key": "bulk",
    "amount": 0.30,   # light — this is a flinch, not the ult's full swell
}
# (frame, value-as-fraction-of-amount). Fast in, fast out: a flinch reads as a
# flash of impact, not a breathing swell. Frames are absolute against the
# measured 0-68 hurt clip; the impact snap is at frame 17.
BEATS = [
    (0,  0.00),
    (10, 0.00),   # anticipation: nothing yet
    (15, 1.00),   # rising in fast just ahead of the snap
    (17, 1.00),   # held exactly on the measured impact frame
    (24, 0.00),   # shrink back down, "not much, a little"
    (68, 0.00),
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
            if k == "amount":
                v = float(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def _fold_split_clips(path, name):
    """Merge `<name>.001` back into `<name>` in the exported .glb.

    Same fold as make_ult_animation.py: Blender keeps the shape-key animation
    in a separate action that cannot be renamed to match (two actions can't
    share a name), so the exporter ships it as its own never-played clip
    unless the glTF-level animations are merged by hand after export.
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
    bb = bytes(bin_) + bytes((-len(bin_)) % 4)
    with open(path, "wb") as f:
        f.write(b"glTF" + _struct.pack("<II", 2, 12 + 8 + len(jb) + 8 + len(bb)))
        f.write(_struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(_struct.pack("<II", len(bb), 0x004E4942) + bb)


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    mesh = next(ob for ob in bpy.data.objects if ob.type == "MESH")

    keys = mesh.data.shape_keys
    kb = keys.key_blocks.get(o["key"]) if keys else None
    if kb is None:
        print("no shape key %r on the mesh. Run add_bulk_shapekey.py first."
              % o["key"])
        return

    clip = o["clip"]
    existing_extra = bpy.data.actions.get(clip + ".001")
    if existing_extra is not None and not o["force"]:
        print("clip %r already has a folded shape-key action. Use --force to redo."
              % clip)
        return

    old_ad = keys.animation_data
    if old_ad and old_ad.action and old_ad.action.name.startswith(clip):
        old_ad.action.use_fake_user = False
        bpy.data.actions.remove(old_ad.action)

    ad = keys.animation_data or keys.animation_data_create()
    action = bpy.data.actions.new(clip)
    action.use_fake_user = True
    ad.action = action

    for f, frac in BEATS:
        kb.value = o["amount"] * frac
        kb.keyframe_insert("value", frame=f)
    kb.value = 0.0

    print("keyed %r on %r: %d beats, peak %.2f at frame %d"
          % (o["key"], clip, len(BEATS), o["amount"],
             next(f for f, v in BEATS if v == 1.0)))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB",
                              export_morph=True, export_morph_animation=True)
    _fold_split_clips(dest, clip)
    print("wrote %s" % dest)


main()
