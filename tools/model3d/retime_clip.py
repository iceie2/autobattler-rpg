"""Speed up (or slow down) an existing clip by rescaling its keyframe times.
Blender script.

Same poses, same number of swipes, just compressed into less time — this
moves every keyframe on every fcurve by the same factor around the clip's own
start frame, so the shape of the motion is untouched and only its duration
changes. Not a substitute for the attack-speed/playback-rate system in
3D_PIPELINE.md section 6 (still not built) — that would do this per-unit at
runtime from attack speed; this bakes ONE fixed speed into the clip itself,
which is the right tool when the ask is "this specific clip should just be
faster," not "playback should track a stat."

  blender --background --python retime_clip.py -- \
      --model "assets/3d pipeline/hero/bloodhound/bloodhound.glb" \
      --clip attack --factor 0.5 [--out other.glb] [--force]

--factor 0.5 halves the clip's length (2x speed). --factor 2.0 would double
it (half speed).

NOT IDEMPOTENT, and there is no reliable way to make it so: once this has
round-tripped through a glTF export there is nothing left in the file that
says "already retimed" versus "just naturally this fast" (same situation as
add_wrist_twist.py). Running it twice compounds. To back out a retime, run it
again with the reciprocal factor (0.5 then 2.0 gets back to the original
length, modulo float rounding) — or better, re-derive from the raw/ source.
"""
import sys
import bpy

DEFAULTS = {
    "clip": "attack",
    "factor": 0.5,
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(DEFAULTS)
    o["model"], o["out"] = None, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:], argv[i + 1]
            if k == "factor":
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


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])

    action = bpy.data.actions.get(o["clip"])
    if action is None:
        print("no clip named %r (have: %s)"
              % (o["clip"], ", ".join(sorted(a.name for a in bpy.data.actions))))
        return

    lo, hi = action.frame_range
    origin = lo
    factor = o["factor"]
    moved = 0
    for fc in fcurves_of(action):
        for k in fc.keyframe_points:
            k.co[0] = origin + (k.co[0] - origin) * factor
            k.handle_left[0] = origin + (k.handle_left[0] - origin) * factor
            k.handle_right[0] = origin + (k.handle_right[0] - origin) * factor
            moved += 1
        fc.update()

    lo2, hi2 = action.frame_range
    print("retimed '%s' x%.2f: %.1f-%.1f frames -> %.1f-%.1f frames (%d keys moved)"
          % (o["clip"], factor, lo, hi, lo2, hi2, moved))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
