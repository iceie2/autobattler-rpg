#!/usr/bin/env python3
"""Per-frame stretch scan over a skinned region. Blender script.

WHY THIS EXISTS. Meshy's fixed 24-bone biped has no cloth bones, so a gown or
skirt is skinned straight to the legs. It therefore survives a clip or tears in
it, and nothing in the pipeline could tell you which: `clip_clearance.py`
answers a prop-vs-body question, `prop_rubric.py` looks at one frame, and a
frame strip catches a tear only if the worst frame happens to be one of the
eight sampled. Stitch's v003 review left exactly this as an open question
("does the skirt clipping remain acceptable?") with no way to answer it.

WHAT IT MEASURES. Edge stretch, which is what tearing actually is. Every mesh
edge whose midpoint sits below --below of the character's height at REST is
taken as skirt geometry. For each frame, each such edge's deformed length is
divided by its rest length. A ratio of 1.0 is rigid; the hem of a walk cycle
will always exceed that somewhat, because the legs do move under it. What you
are looking for is the frame where the ratio runs away.

THRESHOLDS, calibrated on Vail 2026-09-19 by scoring every clip and then
rendering the same frames to see which actually ripped:

    <= 2.2   holds. Observed clean: idle 1.55, hurt 1.56, skill 1.80,
             death 1.80, ult 1.59, glide-walk 1.97, attack 2.22.
    2.2-2.6  marginal; look before shipping it.
    > 2.6    torn. Observed: the run-cycle walk peaked 3.16x and the hem
             visibly rips; the Charged_Ground_Slam ult peaked 2.91x and the
             gown collapses from the frame it crosses ~2.65.

THREE LIMITS, all real:

1. It measures STRETCH, not self-intersection. A character lying horizontal
   can score well under the threshold while the skirt folds through itself
   into a blob -- Vail's `death` scores 1.80 and still looks wrong on the
   ground. Stretch is necessary, not sufficient.
2. It is a screen, not a verdict. A passing scan means no edge exceeded the
   threshold. It says nothing about whether the motion reads. Never report a
   pass as "the clip looks fine" -- render it and let a human look.

--above raises the FLOOR of the band, for a character whose cloth does not
reach the ground (Reed's robe stops mid-shin over bare legs). Use it to keep
bare anatomy out of a cloth measurement.

3. A HIGH SCORE CAN BE BAD AUTO-WEIGHTS RATHER THAN A BAD CLIP. Reed scored
   3.2-7.5x on EVERY clip including an idle he barely moves in, while the robe
   was visibly intact at render size. Neither the clip nor the band was at
   fault: listing the offending edges by dominant vertex group showed hem
   vertices at 21% height weighted to `Spine`, next to neighbours weighted to
   `RightLeg`, plus hip vertices weighted to `RightShoulder`. Meshy's
   auto-weighting had bound distant bones to the lower robe, so those edges are
   stretched between bones that move independently — genuinely torn geometry,
   just confined to 187 edges out of 19,004 (~1%), which is why the eye misses
   it and why the p99.5 statistic catches it.

   So when a score is high but the render looks fine, do not assume the metric
   is wrong. Print the worst edges' dominant vertex groups first. If they name
   bones that have no business there, the fix is the WEIGHTS, not the clip and
   not the threshold.

  blender --background --python skirt_stress.py -- \\
      --model "assets/3d pipeline/hero/vail/vail_v001.glb" \\
      [--clip ult] [--below 0.55] [--above 0.22] [--top 20]
"""
import sys

import bpy
from mathutils import Vector


WARN = 2.2
TORN = 2.6


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "clip": "", "below": 0.55, "above": 0.0, "top": 20,
         "mesh": ""}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            k, v = argv[i][2:], argv[i + 1]
            o[k] = float(v) if k in ("below", "above") else int(v) if k == "top" else v
            i += 2
        else:
            i += 1
    return o


def evaluated_verts(ob, dg):
    """World-space vertex positions WITH the armature modifier applied."""
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ob.matrix_world
    pts = [mw @ v.co.copy() for v in me.vertices]
    ev.to_mesh_clear()
    return pts


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    scene = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get()

    arm = next(x for x in bpy.data.objects if x.type == "ARMATURE")
    # Pick the BODY, not a socketed prop. Two heuristics were tried and BOTH
    # measured the wrong object on Lordee 2026-09-20:
    #   vertex count  -- Meshy's untextured props come back unwelded (his cutlass
    #                    is 6,228 tris but 17,983 verts, ~3 per tri), so the SWORD
    #                    outweighed the 8,301-vert body.
    #   vertex-group count -- the prop object still carries a group for all 24
    #                    bones plus its socket; groups exist without weights.
    # Either way every clip scored a meaningless rigid 1.00x, which is the giveaway:
    # a run cycle cannot be perfectly rigid. The discriminator that is actually
    # true is NONZERO WEIGHT -- attach_prop_socket.py weights a prop 100% to ONE
    # bone, while the body is genuinely skinned across the whole 24-bone rig.
    _meshes = [x for x in bpy.data.objects if x.type == "MESH"]

    def _live_bones(ob):
        live = set()
        for v in ob.data.vertices:
            for g in v.groups:
                if g.weight > 1e-4:
                    live.add(g.group)
        return len(live)

    if o.get("mesh"):
        mesh = next(x for x in _meshes if x.name == o["mesh"])
    else:
        mesh = max(_meshes, key=lambda x: (_live_bones(x), len(x.data.vertices)))
    print(f"measuring mesh {mesh.name!r} ({len(mesh.data.vertices)} verts, "
          f"{_live_bones(mesh)} bones with real weight)"
          + (f"; ignoring " + ", ".join(f"{x.name!r}({_live_bones(x)} bones)"
                                        for x in _meshes if x is not mesh)
             if len(_meshes) > 1 else ""))

    acts = [a for a in bpy.data.actions
            if not o["clip"] or o["clip"] in a.name]
    if not acts:
        print(f"clip {o['clip']!r} not found; have: "
              + ", ".join(a.name for a in bpy.data.actions))
        return

    # Rest geometry. Clearing the action is NOT enough: pose bones keep
    # whatever transform was last evaluated, so the "rest" pose silently
    # becomes the last frame of the last clip and every ratio comes out
    # nonsense (measured: a standing frame scoring 4.5x). Reset the pose
    # explicitly.
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    dg.update()
    rest = evaluated_verts(mesh, dg)
    zs = [p.z for p in rest]
    lo, hi = min(zs), max(zs)
    cut = lo + (hi - lo) * o["below"]

    floor = lo + (hi - lo) * o["above"]
    cand = []
    for e in mesh.data.edges:
        a, b = e.vertices
        mid = (rest[a].z + rest[b].z) * 0.5
        if floor <= mid < cut:
            d = (rest[a] - rest[b]).length
            if d > 1e-6:
                cand.append((a, b, d))
    # Drop degenerate slivers. A rest edge far shorter than its neighbours
    # yields a huge ratio from a tiny absolute movement, so a plain max() is
    # dominated by two or three of them and cannot tell a clean idle from a
    # torn walk -- measured: idle scored 2.60x on max, the same band as the
    # walk that visibly rips.
    med = sorted(d for _, _, d in cand)[len(cand) // 2] if cand else 0.0
    edges = [t for t in cand if t[2] >= med * 0.25]
    print(f"height {hi - lo:.3f}; band {o['above']:.0%}-{o['below']:.0%} "
          f"({floor:.3f} <= z < {cut:.3f}); {len(edges)} edges "
          f"({len(cand) - len(edges)} slivers dropped) "
          f"of {len(mesh.data.edges)}")

    for act in acts:
        ad.action = act
        if hasattr(ad, "action_slot") and getattr(act, "slots", None):
            ad.action_slot = act.slots[0]
        f0, f1 = (int(round(v)) for v in act.frame_range)
        print(f"\nCLIP {act.name}  frames {f0}..{f1}")
        print(f"  {'f':>4}  {'p99.5':>6}  {'>2x':>7}")
        rows = []
        for f in range(f0, f1 + 1):
            scene.frame_set(f)
            dg.update()
            now = evaluated_verts(mesh, dg)
            rs = sorted((now[a] - now[b]).length / d for a, b, d in edges)
            p995 = rs[min(len(rs) - 1, int(len(rs) * 0.995))]
            frac = sum(1 for r in rs if r > 2.0) / len(rs)
            rows.append((f, p995, frac))
        for f, w, fr in rows:
            bar = "#" * min(50, int((w - 1.0) * 25))
            flag = "  TORN" if w > TORN else ("  warn" if w > WARN else "")
            print(f"  {f:4d}  {w:6.2f}x  {fr:6.2%} {bar}{flag}")
        pk = max(rows, key=lambda r: r[1])
        bad = [f for f, w, _ in rows if w > TORN]
        print(f"  peak {pk[1]:.2f}x at frame {pk[0]} "
              f"({pk[2]:.2%} of skirt edges past 2x); "
              f"{len(bad)} frame(s) over {TORN}"
              + (f" -> {bad[0]}..{bad[-1]}" if bad else ""))


main()
