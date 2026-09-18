"""Make all four limbs shoot out long as Bouncer falls, in the `death` clip.

Same rubber-hose technique as add_stretch_punch.py — only the UPPER segment of
each limb (upper arm, thigh) is scaled along its local Y (bone-length axis),
and the segment below it (forearm, shin) is counter-scaled by the exact
inverse, so the hand/foot rides outward on a longer limb instead of
inheriting the stretch and ballooning. See that file for why: scaling both
segments (or not counter-scaling) was measured to blow the glove out to
x3.91, because bone scale inherits down the chain.

UNLIKE the punch, this is NOT a splice — death's timing (launch, fall, land)
is already good, so nothing is inserted or held. This just overlays new scale
keyframes on TOP of the clip's existing rotation/location keyframes, the same
way add_hurt_flinch.py overlays the shape key: the existing animation is
untouched, the limbs simply get longer as playback reaches those frames.

TIMING. Measured, not guessed: sampled Hips world Z across the clip. He's
launched upward by the hit (apex ~1.40 at frame 12), falls, and slams down
hard between frames 22-26 (Z drops from 0.53 to 0.15 — the fastest drop in
the clip). So the stretch is mostly still gathering while he is airborne, and
snaps to full length right on that impact, then STAYS full-length: he does
not spring back, because he is dead and left splayed out.

  blender --background --python add_limb_stretch_death.py -- \
      --model "assets/3d pipeline/hero/bouncer/bouncer.glb" \
      [--clip death] [--amount 1.8] [--out other.glb] [--force]
"""
import sys
import bpy

DEFAULTS = {
    "clip": "death",
    "amount": 1.80,   # extra length at full reach, as a multiple of rest length
}
# (bone, counter) pairs — only the upper segment stretches, its child is
# counter-scaled so the hand/foot keeps its own size. Hips/feet are never
# touched, so he still lands on the ground plane.
LIMBS = [
    ("LeftArm", "LeftForeArm"),
    ("RightArm", "RightForeArm"),
    ("LeftUpLeg", "LeftLeg"),
    ("RightUpLeg", "RightLeg"),
]
# (frame, strength 0..1) against the measured 0-60 death clip. Gathers slowly
# while airborne, snaps to full length right on the frame-22-26 impact, and
# then HOLDS — no snap-back, because he stays down.
CURVE = [
    (0,  0.00),
    (6,  0.00),   # still normal as the launch begins
    (14, 0.30),   # starting to noodle out mid-air
    (22, 0.80),   # almost full reach, just ahead of impact
    (26, 1.00),   # full length, right on the slam
    (60, 1.00),   # stays splayed out to the end
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


def fcurves_of(action):
    """Blender 4.4+ actions are slotted: layers -> strips -> channelbags."""
    if hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for cb in getattr(strip, "channelbags", []) or []:
                    for fc in cb.fcurves:
                        yield fc
    else:
        for fc in action.fcurves:
            yield fc


def channelbag(action):
    for layer in action.layers:
        for strip in layer.strips:
            for cb in getattr(strip, "channelbags", []) or []:
                return cb
    return None


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return
    amount = o["amount"]

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])

    action = bpy.data.actions.get(o["clip"])
    if action is None:
        print("no clip named %r (have: %s)"
              % (o["clip"], ", ".join(sorted(a.name for a in bpy.data.actions))))
        return

    # Idempotency guard: a second pass would multiply the stretch.
    for fc in fcurves_of(action):
        if fc.data_path.endswith(".scale") and any(b in fc.data_path for b, _ in LIMBS):
            if any(abs(k.co[1] - 1.0) > 0.01 for k in fc.keyframe_points):
                if not o["force"]:
                    print("'%s' already has a limb stretch. Use --force to redo."
                          % o["clip"])
                    return

    cb = channelbag(action)
    made = 0
    for bone, counter in LIMBS:
        for bname, invert in ((bone, False), (counter, True)):
            path = 'pose.bones["%s"].scale' % bname
            fc = None
            for existing in fcurves_of(action):
                if existing.data_path == path and existing.array_index == 1:
                    fc = existing
                    break
            if fc is None:
                fc = cb.fcurves.new(path, index=1) if cb else action.fcurves.new(path, index=1)
            else:
                fc.keyframe_points.clear()
            for f, strength in CURVE:
                v = 1.0 + amount * strength
                fc.keyframe_points.insert(f, (1.0 / v) if invert else v)
            fc.update()
            made += 1

    print("stretched %d limb bones x%.2f peak in '%s'" % (made, 1.0 + amount, o["clip"]))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
