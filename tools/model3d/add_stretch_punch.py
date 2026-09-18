"""Splice a rubber-hose arm stretch into a punch clip. Blender script.

Meshy animates a FIXED skeleton — it emits bone rotations, never bone lengths —
so no generated clip can contain a stretch. This inserts one, as real keyframes
in the .glb, so it is visible in the Blender review stage and is exactly what
ships. (It used to be applied in Godot at load time, which meant reviewing a
punch that was not the punch that played.)

The insert is self-contained: the original animation is untouched, a gap is
opened after frame `--at`, and inside that gap the arm extends and returns. What
was frame `at + 1` still follows immediately after the arm is back, so the rest
of the punch plays exactly as authored.

The body HOLDS STILL during the stretch (the pose at `--at` is duplicated at the
end of the gap) — that is the cartoon read, and it is what makes a self-contained
insert work instead of looking like a stutter.

Clip length is deliberately NOT a consideration: playback rate is driven by
attack speed (see 3D_PIPELINE.md section 6), so animations are authored for how
they look.

  blender --background --python add_stretch_punch.py -- \
      --model "assets/3d pipeline/hero/bouncer/bouncer.glb" \
      [--clip attack] [--at 12] [--frames 10] [--amount 1.65]
      [--bone LeftArm] [--counter LeftForeArm] [--out other.glb] [--force]

Writes in place unless --out is given. Refuses to run twice on the same clip
without --force, because a second pass would multiply the stretch.
"""
import sys
import bpy
from mathutils import Quaternion

DEFAULTS = {
    "clip": "attack",
    "at": 12,          # last frame of the original animation before the insert
    "frames": 10,      # length of the inserted window
    "amount": 1.65,    # extra length at full reach, as a multiple of rest length
    # LEFT arm: the clip is Meshy's "Left_Jab_from_Guard". Check which arm the
    # punch actually uses before assuming — they are not all the same hand.
    #
    # ONLY THE UPPER ARM LENGTHENS. The forearm is counter-scaled by exactly the
    # inverse so it keeps its natural size, and the hand is never touched at all,
    # so the forearm and glove simply ride outward on a longer upper arm.
    #
    # This shape was chosen by measurement. Scaling both arm bones (the obvious
    # approach) balloons the glove to x3.91, because bone scale INHERITS down the
    # chain and the hand compounds everything above it. Blender can switch that
    # off with inherit_scale='NONE' — but glTF has no such concept and the
    # exporter does not bake it, so it silently reverts on export. Counter-scaling
    # is the only version that survives the round-trip.
    "bone": "LeftArm",
    "counter": "LeftForeArm",
    # The fist corkscrews as it drives forward — a boxer's actual punch roll,
    # not just a straight jab. Degrees of extra rotation around the forearm's
    # own long axis (local Y), added on top of the held pose so it doesn't
    # fight the existing hand orientation. 0 disables it.
    "roll_bone": "LeftHand",
    "roll": 50.0,
    # The glove itself swells at the peak — a separate, isolated effect from
    # the arm-length stretch above, added 2026-09-06 to punch up the impact
    # read. Safe to do independently: LeftForeArm's counter-scale already
    # cancels the upper-arm's stretch before it ever reaches LeftHand (that's
    # the whole point of counter-scaling), so LeftHand's OWN scale channel is
    # untouched net-1.0 going in — adding a uniform (all 3 axes, not just the
    # bone-length axis) scale here inflates the glove as a ball, on top of
    # nothing, instead of compounding with the arm reach the way naively
    # scaling both arm bones did (the x3.91 balloon in the note above).
    "glove_bone": "LeftHand",
    "glove_amount": 0.25,   # +25% at peak, uniform on all 3 axes
}
# Shape of the extension across the gap, as (fraction of gap, scale multiplier).
# Out fast, hold at full reach, snap back — the asymmetry IS the punch; a
# symmetric curve reads as the arm breathing rather than striking.
#
# RECALIBRATED 2026-09-06: extend/hold at 25%/35% as before, but retract now
# eases out over 0.35-0.65 (3 of the 10 gap frames) instead of 0.35-0.40 (half
# a frame). That first pass crammed the retract into less than a frame, which
# is not a snap, it's a pop — the arm just vanished back to normal between two
# adjacent frames with nothing readable in between. 3 frames is fast enough to
# still read as a whip-back, not a held return, but slow enough to actually
# see the arm travel.
CURVE = [(0.00, 0.0), (0.25, 1.0), (0.35, 1.0), (0.65, 0.0), (1.00, 0.0)]
# Same shape, applied to the roll instead of the stretch — the fist twists in
# sync with the reach rather than on its own timing.
ROLL_CURVE = CURVE


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = dict(DEFAULTS)
    out["model"], out["out"], out["force"] = None, None, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--force":
            out["force"] = True
            i += 1
            continue
        key = a[2:] if a.startswith("--") else None
        if key is not None and i + 1 < len(argv):
            val = argv[i + 1]
            if key in ("at", "frames"):
                val = int(val)
            elif key in ("amount", "roll", "glove_amount"):
                val = float(val)
            out[key] = val
            i += 2
        else:
            i += 1
    return out


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
    bone, counter = o["bone"], o["counter"]
    at, span, amount = o["at"], o["frames"], o["amount"]

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])

    action = bpy.data.actions.get(o["clip"])
    if action is None:
        print("no clip named %r (have: %s)"
              % (o["clip"], ", ".join(sorted(a.name for a in bpy.data.actions))))
        return

    # Already spliced from a prior run? RETIME instead of re-inserting: the
    # gap is real timeline now (frames at..at+span physically exist), so a
    # second splice would double the insert. Retiming just replaces the
    # stretch/roll curves living inside that existing window.
    already_spliced = any(
        fc.data_path.endswith(".scale") and bone in fc.data_path
        and any(abs(k.co[1] - 1.0) > 0.01 for k in fc.keyframe_points)
        for fc in fcurves_of(action)
    )
    if already_spliced and not o["force"]:
        print("'%s' already has a stretch on %s. Use --force to redo (retimes in place)."
              % (o["clip"], bone))
        return
    retime = already_spliced

    lo, hi = action.frame_range
    if retime:
        print("clip '%s': frames %.1f-%.1f, RETIMING existing insert at %d-%d"
              % (o["clip"], lo, hi, at, at + span))
    else:
        print("clip '%s': frames %.1f-%.1f, inserting %d frames after %d"
              % (o["clip"], lo, hi, span, at))

    # 1. Remember the pose at `at`, so the body can be held across the gap.
    #    Works identically whether the gap is new or already exists: at `at`
    #    itself the pose is the same real pre-punch frame either way.
    held = {}
    for fc in fcurves_of(action):
        held[(fc.data_path, fc.array_index)] = fc.evaluate(at)

    moved = 0
    if not retime:
        # 2. Open the gap: everything after `at` slides right.
        for fc in fcurves_of(action):
            for k in fc.keyframe_points:
                if k.co[0] > at:
                    k.co[0] += span
                    k.handle_left[0] += span
                    k.handle_right[0] += span
                    moved += 1
            fc.update()

        # 3. Freeze the body: hold the `at` pose until the gap closes.
        for fc in fcurves_of(action):
            fc.keyframe_points.insert(at + span, held[(fc.data_path, fc.array_index)])
            fc.update()

    # 4. The stretch itself. Blender bones run along their LOCAL Y, so scaling
    #    index 1 lengthens the bone without fattening it.
    cb = channelbag(action)
    made = 0
    for bname, invert in ((bone, False), (counter, True)):
        path = 'pose.bones["%s"].scale' % bname
        fc = None
        for existing in fcurves_of(action):
            if existing.data_path == path and existing.array_index == 1:
                fc = existing
                break
        if fc is None:
            fc = cb.fcurves.new(path, index=1) if cb else action.fcurves.new(path, index=1)
        elif retime:
            # These keys only ever exist because a prior run of THIS script
            # added them, so a full clear-and-rebuild is safe here (unlike
            # rotation below, which also carries real authored animation).
            fc.keyframe_points.clear()
        for frac, strength in CURVE:
            v = 1.0 + amount * strength
            fc.keyframe_points.insert(at + span * frac, (1.0 / v) if invert else v)
        fc.update()
        made += 1

    # 4b. The glove swell: uniform (all 3 axes) scale on the hand bone itself,
    #     same curve/timing as the arm stretch, so it swells and settles in
    #     sync with the reach instead of on its own schedule.
    glove_bone, glove_amount = o["glove_bone"], o["glove_amount"]
    if glove_bone and glove_amount:
        path = 'pose.bones["%s"].scale' % glove_bone
        for idx in range(3):
            fc = None
            for existing in fcurves_of(action):
                if existing.data_path == path and existing.array_index == idx:
                    fc = existing
                    break
            if fc is None:
                fc = cb.fcurves.new(path, index=idx) if cb else action.fcurves.new(path, index=idx)
            elif retime:
                fc.keyframe_points.clear()
            for frac, strength in CURVE:
                fc.keyframe_points.insert(at + span * frac, 1.0 + glove_amount * strength)
            fc.update()
        made += 1

    # 5. The glove roll: a corkscrew twist added ON TOP of the held rotation,
    #    around the hand's own local Y (the forearm's long axis), so it reads
    #    as the fist rotating as it drives forward rather than replacing the
    #    punch's existing hand pose.
    roll_bone, roll_deg = o["roll_bone"], o["roll"]
    if roll_bone and roll_deg:
        path = 'pose.bones["%s"].rotation_quaternion' % roll_bone
        base = Quaternion((
            held.get((path, 0), 1.0), held.get((path, 1), 0.0),
            held.get((path, 2), 0.0), held.get((path, 3), 0.0),
        ))
        fcs = {}
        for existing in fcurves_of(action):
            if existing.data_path == path:
                fcs[existing.array_index] = existing
        for idx in range(4):
            if idx not in fcs:
                fcs[idx] = cb.fcurves.new(path, index=idx) if cb else action.fcurves.new(path, index=idx)
            elif retime:
                # Only strip keys STRICTLY inside the gap — this fcurve also
                # carries the real authored punch pose outside it, which must
                # survive a retime untouched.
                for k in list(fcs[idx].keyframe_points):
                    if at < k.co[0] < at + span:
                        fcs[idx].keyframe_points.remove(k)
        import math
        twist = Quaternion((0.0, 1.0, 0.0), 0.0)
        for frac, strength in ROLL_CURVE:
            twist = Quaternion((0.0, 1.0, 0.0), math.radians(roll_deg * strength))
            q = twist @ base
            f = at + span * frac
            for idx in range(4):
                fcs[idx].keyframe_points.insert(f, q[idx])
        for fc in fcs.values():
            fc.update()
        made += 1

    lo2, hi2 = action.frame_range
    print("  moved %d keys, %s x%.2f (counter %s)"
          % (moved, bone, 1.0 + amount, counter))
    if glove_bone and glove_amount:
        print("  %s swells x%.2f" % (glove_bone, 1.0 + glove_amount))
    if roll_bone and roll_deg:
        print("  %s roll +/-%.0f deg" % (roll_bone, roll_deg))
    print("  clip is now frames %.1f-%.1f" % (lo2, hi2))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
