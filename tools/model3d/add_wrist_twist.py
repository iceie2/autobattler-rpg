"""Turn the boxing gloves slightly inward through a clip, without moving the
arms. Blender script.

Meshy's run cycle swings the arms with the gloves facing straight ahead. This
adds a constant inward twist of the WRIST on top of that — the fists roll in
toward a guard-ish angle while running, same read as the punch's corkscrew
roll (add_stretch_punch.py) but held steady instead of timed to a strike.

CONSTANT, not curved: every existing keyframe on the wrist bone's rotation
gets the same fixed extra rotation multiplied in, so the arm's own swing
timing is completely untouched — only the glove's facing changes.

NOT IDEMPOTENT. Unlike the other tools here, there is no reliable way to tell
"twisted" apart from "just posed that way" once this has round-tripped through
a glTF export — the operation is a plain quaternion multiply with no other
footprint. Running it twice compounds the twist. To change the angle, pass
the DIFFERENCE (e.g. already ran +25, want +40: run again with --degrees 15),
or re-run with a negative --degrees equal to the last run to undo first.

  blender --background --python add_wrist_twist.py -- \
      --model "assets/3d pipeline/hero/bouncer/bouncer.glb" \
      [--clip walk] [--bones LeftHand,RightHand] [--degrees 25]
      [--out other.glb]
"""
import sys
import math
import bpy
from mathutils import Quaternion

DEFAULTS = {
    "clip": "walk",     # this is the file's actual RUN cycle, just named walk
    "bones": "LeftHand,RightHand",
    "degrees": 25.0,    # inward twist, around the wrist's own local Y (the
                        # forearm's long axis) — same axis add_stretch_punch.py
                        # rolls the glove around during the punch.
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
            if k == "degrees":
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
    bones = [b for b in o["bones"].split(",") if b]
    twist = Quaternion((0.0, 1.0, 0.0), math.radians(o["degrees"]))

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])

    action = bpy.data.actions.get(o["clip"])
    if action is None:
        print("no clip named %r (have: %s)"
              % (o["clip"], ", ".join(sorted(a.name for a in bpy.data.actions))))
        return

    for bname in bones:
        path = 'pose.bones["%s"].rotation_quaternion' % bname
        fcs = {fc.array_index: fc for fc in fcurves_of(action) if fc.data_path == path}
        if len(fcs) != 4:
            print("  ! %s has no rotation_quaternion animation, skipping" % bname)
            continue

        frames = sorted({k.co[0] for k in fcs[0].keyframe_points})
        for f in frames:
            base = Quaternion((fcs[0].evaluate(f), fcs[1].evaluate(f),
                                fcs[2].evaluate(f), fcs[3].evaluate(f)))
            q = twist @ base
            for idx in range(4):
                fcs[idx].keyframe_points.insert(f, q[idx])
        for fc in fcs.values():
            fc.update()
        print("  twisted %s +%.0f deg across %d frames" % (bname, o["degrees"], len(frames)))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


main()
