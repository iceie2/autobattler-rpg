#!/usr/bin/env python3
"""Merge a Meshy per-animation GLB export into ONE rigged .glb for Godot.

Meshy ships each animation as its own ~23 MB .glb that re-embeds the same mesh,
skin and 4K texture. Godot would import 11 copies of the character. This walks
the set, keeps one file as the base (mesh + skin + skeleton) and copies only the
animation data out of the rest, remapping every channel target by NODE NAME so
it survives a re-ordered node array.

It also downscales the embedded texture: these characters render ~120 px tall in
a 2.5D board, so a 4096px albedo is ~20 MB of nothing.

It can also HARDEN skin weights on named bones (--harden-bones). Meshy's
auto-rigging bleeds forearm influence into the boxing gloves — measured at 45-49%
of the glove's vertices sharing weight with the forearm — so the gloves droop and
lag instead of moving as one rigid block with the hand. Hardening is part of the
merge rather than a separate patch because a fresh Meshy export would otherwise
silently lose the fix.

Usage:
  py -3 glb_merge_anims.py <src_dir> <out.glb> [--tex 1024] [--no-tex-resize]
                           [--harden-bones RightHand,LeftHand] [--harden-at 0.5]
                           [--drop block,victory]

<src_dir> may also be a SINGLE .glb file. Meshy's "Single file" + "All Added"
export option (2026-09-06, Bloodhound) pre-merges every animation into one
file itself — one mesh, one skin, one texture, all clips as separate actions
already targeting the same nodes. That is exactly this tool's OUTPUT shape, so
there is nothing to copy between files: every animation is kept and just
renamed/hardened/resized in place. Still worth running this tool rather than
using the file as-is, because Meshy's merge does not rename clips to the
game's convention, does not harden bones, and does not downscale the texture.

--drop leaves clips OUT of the merged file. Do it here rather than deleting the
action in Blender: the raw Meshy exports stay untouched in raw/, so re-running
the merge is how the decision survives — a Blender-side delete is undone the next
time anyone re-merges or Meshy re-exports.

Animation names are cleaned to the game's convention (idle/walk/run/attack/...)
via NAME_MAP; anything unmapped keeps a snake_cased version of its Meshy name.
"""
import io
import json
import os
import re
import struct
import sys
import glob

# Clips the GAME plays by name. Everything else is optional flavour a character
# may or may not have (run / skill / block / victory / attack_alt ...).
#   idle, walk        -> Model3DSprite._update_model3d_animation
#   attack/hurt/death -> VisualUnit._play_oneshot
REQUIRED_CLIPS = ["idle", "walk", "attack", "hurt", "death"]

# Meshy clip name (the middle field of "Armature|<clip>|baselayer") -> game name.
# EVERY new character adds entries here: Meshy names clips after the motion it
# generated ("Left_Jab_from_Guard"), not after the game's slots, and the names
# differ per character. An unmapped clip is kept under a snake_cased name and
# then never plays, which the check at the end of main() reports.
NAME_MAP = {
    "Idle_5": "idle",
    # The RUN cycle is the game's movement animation (user call 2026-09-05) —
    # units cross a 9x9 board fast enough that Meshy's walk reads as sluggish.
    # The game only ever plays "walk", so the run clip takes that name and
    # Meshy's actual walk is dropped at merge.
    "running": "walk",
    "walking_man": "walk_slow",
    "Left_Jab_from_Guard": "attack",
    "Face_Punch_Reaction": "hurt",
    "Knock_Down": "death",
    "Victory_Cheer": "victory",
    # Riot (2026-09-18). Anthropomorphic pig riot officer; the jab IS his baton
    # thrust, and it keeps the left hand up where the shield sockets.
    #
    # NOTE ON Right_Jab_from_Guard: it used to map to "attack_alt" as a spare for
    # Cross/Bouncer. It is Riot's PRIMARY attack, so it maps to "attack" now. No
    # raw directory contains both jabs (Cross ships Left_Jab, Riot ships Right_),
    # so nothing collides — but if a future character generates BOTH, one of them
    # needs renaming before merging or the second will overwrite the first.
    "Idle_02": "idle",
    "Shield_Push_Left": "skill",
    "Shouting_Angrily": "ult",
    "Hit_Reaction": "hurt",
    "Right_Jab_from_Guard": "attack",
    "Boxing_Guard_Prep_Straight_Punch": "attack_heavy",
    "Punch_Combo_1": "skill",
    "Block3": "block",

    # Bloodhound (2026-09-06). Source was Meshy's "Single file" + "All Added"
    # export — one pre-merged .glb, plain clip names (no "Armature|x|baselayer"
    # wrapper), see the single-file branch in main(). No idle in the export;
    # one is synthesized after this merge (see tools/model3d/freeze_pose.py).
    "Dead": "death",
    "Hit_Reaction_1": "hurt",
    "Running": "walk",           # the movement clip, same "run IS walk" call as Bouncer
    "Walking": "walk_slow",      # kept but unused, matching Bouncer's walk_slow
    "RunFast": "run",            # windup source for the run-and-leap ult
    "Weapon_Combo_2": "attack",  # a full ~4.5s combo — user call 2026-09-06:
                                 # fine as-is, reads as a fast swipe once attack
                                 # speed compresses playback (open item, section 6)

    # Headhunter (2026-09-06). Same single-file Meshy export as Bloodhound.
    # No idle either — synthesized from the aim pose (see freeze_pose.py),
    # which fits his kit better than a walk-freeze anyway: he's always aiming.
    "Hit_Reaction_1": "hurt",
    "Running": "walk",
    "Walking": "walk_slow",
    "Shot_and_Fall_Backward": "death",
    "Walk_Backward_While_Shooting_inplace": "attack",  # an actual firing/recoil
                                                        # loop Meshy already
                                                        # generated — no need
                                                        # to hand-author one
    "Walk_Backward_with_Bow_Aimed": "aim",  # "Bow" is Meshy's mislabel; this is
                                             # the rifle-aimed stance. Frame 1
                                             # frozen becomes "idle".

    # Cross (2026-09-09). First character built from the Meshy ANIMATION LIBRARY
    # via the API (tools/model3d/meshy_api.py) rather than hand-picked exports,
    # so these keys are the library's own `key` field and are stable across
    # characters -- any later hero reusing action 128 gets "attack" for free.
    "Idle_9": "idle",
    "Heavy_Hammer_Swing": "attack",       # action 128, he carries a maul
    "Hit_Reaction": "hurt",               # action 178
    "Charged_Spell_Cast": "skill",        # action 125 -- Absolution (cleanse+heal)
    "Charged_Ground_Slam": "ult",         # action 127 -- Judgment. "ult" is the
                                          # name VisualUnit._play_ult_clip looks
                                          # for (visual_unit.gd), not "ultimate".
    # "Knock_Down" -> death, "Running" -> walk and "Walking" -> walk_slow are
    # already mapped above and apply unchanged.

    # Vail (2026-09-19). Air-support healer, range 4. Every pick was
    # constrained by her ankle-length wrap gown: the gown is skinned to the
    # legs, so lunges, high knees and wide stances tear it. That rejected most
    # of the CastingSpell set (126/131/132/133/135 all lunge) in favour of the
    # planted, upright ones.
    "Idle_7": "idle",                     # action 247
    "mage_soell_cast_7": "attack",        # action 136 -- an upright two-hand
                                          # push, not a swing: she is range 4
                                          # at aspd 0.70, so a slow cast.
    "mage_soell_cast": "skill",           # action 129 -- Updraft. The arm
                                          # sweeps 0.67 -> 1.79 in 9 frames,
                                          # which IS the ally being lifted.
    "dying_backwards": "death",           # action 189 -- legs stay together
                                          # through the fall, unlike Knock_Down
    "Grip_and_Throw_Down": "ult",         # action 389 -- Downburst. Cross's
                                          # Charged_Ground_Slam (127) was tried
                                          # first and rejected: the slam pitches
                                          # the whole torso over and tore the
                                          # gown at 2.91x (tools/model3d/
                                          # skirt_stress.py). This one throws
                                          # downward from a standing pose --
                                          # hips drop 6% against the slam's
                                          # 49% -- so the gesture survives.
    # "Charged_Ground_Slam" -> ult (Cross's action 127, reused here as
    # Downburst: raise and slam = enemies grounded) and "Hit_Reaction_1" ->
    # hurt and "running" -> walk are already mapped above.

    # Lumen (2026-09-19). Lightning magic carry, range 5 -- the longest in the
    # roster -- at aspd 0.72, so every offensive clip is a planted ranged CAST,
    # never a melee swing. His kit is one light source split many ways (passive
    # arcs to a 2nd enemy, skill chains 5 at -15%/bounce, ult hits the whole
    # field), so the three casts were picked to read apart BY MEASUREMENT, not
    # by eye -- hand spread and hand height over the hips, per frame:
    #     attack  spread 0.25 (hands together)  z 0.62   forward channel
    #     skill   spread 1.33 (arms wide)       z 0.45   beam fanning out
    #     ult     spread 0.65                   z 0.92   raised overhead
    # A 5x spread split and a 2x height split is what makes them distinguishable
    # at 115 px; Vail's report left exactly this question open with no numbers.
    "Idle_11": "idle",                    # action 251 -- stands dead still,
                                          # arms at sides. He is a hollow suit
                                          # of armour; a human weight-shift
                                          # idle would read as someone alive
                                          # being inside it.
    # BOTH KEYS BELOW CARRY A "_lumen" SUFFIX, renamed in his raw/_merge staged
    # copies. The bare names collided with Reed, added later the same week:
    # Reed maps bare "mage_soell_cast_8" -> skill and bare "mage_soell_cast_1"
    # -> ult. NAME_MAP is one dict, so the later entries won and a Lumen re-merge
    # would have lost "attack" entirely. His shipped .glb predates Reed and is
    # correct; this keeps the merge REPRODUCIBLE. Same fix as the ult key below.
    "mage_soell_cast_8_lumen": "attack",  # action 137, trimmed f2-f26
    "mage_soell_cast_1_lumen": "skill",   # action 130, trimmed f13-f37 -- the
                                          # window where the arms FLING wide
                                          # (spread 0.55 -> 1.27), not the
                                          # later frames where they merely sit
                                          # wide. You have to see them travel.
    "Electrocuted_Fall": "death",         # action 181 -- an electric construct
                                          # losing its arc. Trimmed f88-f113:
                                          # the source holds 28 frames of dead
                                          # static after f126.
    "Charged_Spell_Cast_lumen": "ult",    # action 125, trimmed f38-f62.
                                          # RENAMED IN THE STAGED COPY, not
                                          # here: the raw key "Charged_Spell_Cast"
                                          # is already Cross's SKILL above, and
                                          # NAME_MAP is global, so mapping the
                                          # bare key to "ult" would silently
                                          # change Cross. The raw f20-f36 is
                                          # dead hold (travel 0.006-0.03) and
                                          # f16-f36 is a deep kneel; the trim
                                          # window skips both and keeps only
                                          # the overhead raise.
    # "Hit_Reaction_1" -> hurt, "running" -> walk and "walking_man" -> walk_slow
    # are already mapped above and apply unchanged.

    # Reed (2026-09-19). Anthropomorphic frog river hermit, WATER healer,
    # range 4 at aspd 0.66 -- the slowest attacker on the roster, so his auto is
    # a measured cast, not a swing. Picks deliberately avoid Vail's so the two
    # casters do not share motion. His robe ends mid-shin with the feet clear,
    # so he tolerates a wider stance than her floor-length gown does.
    "Long_Breathe_and_Look_Around": "idle",   # action 336 -- still and upright
    "mage_soell_cast_3": "attack",            # action 132 -- a directed forward
                                              # push. Replaced action 134
                                              # ("mage_soell_cast_5", kept in
                                              # raw/ as the alternative), which
                                              # reads as a hunch on him even
                                              # after the arm retarget: the
                                              # problem there is the TORSO, and
                                              # retarget_arms.py only fixes arms.
    "mage_soell_cast_8": "skill",             # action 137 -- Cleanse. A calm
                                              # HOLD, not a big gesture: the
                                              # hands travel only 0.1 units
                                              # across the whole clip, so the
                                              # VFX has to carry this beat.
    "mage_soell_cast_1": "ult",               # action 130 -- Confluence. Arms
                                              # throw WIDE open to the team.
    # No key collides with Vail's (_7 attack, bare skill) or Lumen's.
    # "dying_backwards" -> death is already mapped above.
    #
    # CORRECTION 2026-09-20: the line above was wrong -- bare "mage_soell_cast_8"
    # and "mage_soell_cast_1" DID collide with Lumen, who had them as attack and
    # skill. NAME_MAP is one dict, so these later entries won and a Lumen re-merge
    # lost "attack". Fixed by suffixing LUMEN's two keys "_lumen" (see his block);
    # Reed's bare keys here are unchanged and still correct for Reed.

    # Lordee (2026-09-20). Undead pirate captain -- a hollow suit of clothes with
    # a violet soul inside. FIGHTER, range 1 melee, cutlass on weapon_r. First
    # MELEE hero built since the coat-vs-lunge problem was understood, so every
    # pick was screened against his knee-length coat tail from the free preview
    # GIFs BEFORE spending:
    #   238 Axe Spin Attack was the natural fit for the skill (a spin reads as
    #   "slams everything within 2 tiles") and was REJECTED UNSPENT -- it pitches
    #   the torso fully over, which is what collapsed Vail's gown at 2.91x.
    # The three picks below all keep the torso upright and the feet close.
    "Right_Hand_Sword_Slash": "attack",   # action 219 -- right-handed, which is
                                          # the hand weapon_r hangs off. Measured
                                          # RightHand height peaks 0.62 while the
                                          # hand spread narrows to 0.13: the
                                          # sword arm extends, the off hand tucks.
                                          # Trimmed f5-f29.
    "Charged_Slash": "skill",             # action 242 -- a wide horizontal sweep
                                          # from a PLANTED stance, spread cycling
                                          # 0.10 <-> 0.98. Trimmed f9-f33.
    "Thrust_Slash": "ult",                # action 240 -- a forward run-through,
                                          # which is the blink-in ATK steal.
                                          # Trimmed f15-f39.
    # "Idle_7" -> idle, "Hit_Reaction_1" -> hurt, "dying_backwards" -> death,
    # "running" -> walk and "walking_man" -> walk_slow are already mapped above.
    # dying_backwards is doubly right here: it keeps the legs together through
    # the fall (kind to the coat), and a hollow suit of clothes dropping flat
    # when the soul leaves it is the death this character should have.
}


def read_glb(path):
    b = open(path, "rb").read()
    if b[:4] != b"glTF":
        raise ValueError(path + " is not a binary glTF")
    off, js, bin_ = 12, None, b""
    while off < len(b):
        ln, ty = struct.unpack_from("<II", b, off)
        off += 8
        chunk = b[off:off + ln]
        off += ln
        if ty == 0x4E4F534A:
            js = json.loads(chunk)
        elif ty == 0x004E4942:
            bin_ = chunk
    return js, bytearray(bin_)


def write_glb(path, js, bin_):
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * (-len(jb) % 4)
    bb = bytes(bin_) + b"\x00" * (-len(bin_) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    with open(path, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(bb), 0x004E4942) + bb)


def clip_name(raw):
    """'Armature|Left_Jab_from_Guard|baselayer' -> 'attack'."""
    parts = raw.split("|")
    mid = parts[1] if len(parts) > 2 else parts[-1]
    if mid in NAME_MAP:
        return NAME_MAP[mid]
    return re.sub(r"[^a-z0-9]+", "_", mid.lower()).strip("_")


def copy_animation(dst_js, dst_bin, src_js, src_bin, anim, name):
    """Deep-copy one animation (samplers -> accessors -> bufferViews -> bytes)."""
    dst_names = {}
    for i, n in enumerate(dst_js["nodes"]):
        dst_names[n.get("name")] = i
    acc_map = {}

    def copy_accessor(ai):
        if ai in acc_map:
            return acc_map[ai]
        acc = dict(src_js["accessors"][ai])
        if "bufferView" in acc:
            bv = dict(src_js["bufferViews"][acc["bufferView"]])
            start = bv.get("byteOffset", 0)
            data = src_bin[start:start + bv["byteLength"]]
            # 4-byte align the destination offset; glTF requires it for accessors.
            while len(dst_bin) % 4:
                dst_bin.append(0)
            bv["byteOffset"] = len(dst_bin)
            bv["buffer"] = 0
            bv.pop("target", None)
            dst_bin.extend(data)
            dst_js["bufferViews"].append(bv)
            acc["bufferView"] = len(dst_js["bufferViews"]) - 1
        dst_js["accessors"].append(acc)
        acc_map[ai] = len(dst_js["accessors"]) - 1
        return acc_map[ai]

    samplers, channels, smap = [], [], {}
    for ci, ch in enumerate(anim.get("channels", [])):
        tgt = ch.get("target", {})
        if "node" not in tgt:
            continue
        src_node_name = src_js["nodes"][tgt["node"]].get("name")
        if src_node_name not in dst_names:
            print("    ! channel %d: node %r missing in base, skipped" % (ci, src_node_name))
            continue
        si = ch["sampler"]
        if si not in smap:
            s = dict(anim["samplers"][si])
            s["input"] = copy_accessor(s["input"])
            s["output"] = copy_accessor(s["output"])
            samplers.append(s)
            smap[si] = len(samplers) - 1
        channels.append({
            "sampler": smap[si],
            "target": {"node": dst_names[src_node_name], "path": tgt["path"]},
        })
    dst_js.setdefault("animations", []).append(
        {"name": name, "samplers": samplers, "channels": channels})
    return len(channels)


def harden_weights(js, bin_, bone, threshold):
    """Make every vertex already mostly owned by `bone` owned by it entirely.

    Deliberately threshold-based rather than "select the glove": there is no
    reliable way to identify glove polygons from the file (one material, one
    mesh), but "the hand already has the majority of this vertex" is exactly the
    set that should be rigid. Vertices below the threshold keep their blend, so
    the wrist still transitions smoothly instead of forming a hard seam.
    """
    comp = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
            5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
    names = [n.get("name") for n in js["nodes"]]
    if not js.get("skins"):
        return
    jnames = [names[j] for j in js["skins"][0]["joints"]]
    if bone not in jnames:
        print("  ! harden: no joint named %s" % bone)
        return
    target = jnames.index(bone)

    changed = 0
    for mesh in js.get("meshes", []):
        for prim in mesh.get("primitives", []):
            attrs = prim.get("attributes", {})
            if "JOINTS_0" not in attrs or "WEIGHTS_0" not in attrs:
                continue
            jacc = js["accessors"][attrs["JOINTS_0"]]
            wacc = js["accessors"][attrs["WEIGHTS_0"]]
            jbv = js["bufferViews"][jacc["bufferView"]]
            wbv = js["bufferViews"][wacc["bufferView"]]
            jfmt, jsz = comp[jacc["componentType"]]
            wfmt, wsz = comp[wacc["componentType"]]
            jstride = jbv.get("byteStride") or 4 * jsz
            wstride = wbv.get("byteStride") or 4 * wsz
            jbase = jbv.get("byteOffset", 0) + jacc.get("byteOffset", 0)
            wbase = wbv.get("byteOffset", 0) + wacc.get("byteOffset", 0)
            scale = {5121: 255.0, 5123: 65535.0}.get(wacc["componentType"], 1.0)
            norm = wacc["componentType"] != 5126

            for vi in range(wacc["count"]):
                jo = jbase + vi * jstride
                wo = wbase + vi * wstride
                jj = struct.unpack_from("<" + jfmt * 4, bin_, jo)
                ww = struct.unpack_from("<" + wfmt * 4, bin_, wo)
                w = [x / scale for x in ww] if norm else list(ww)
                tw = sum(w[k] for k in range(4) if jj[k] == target)
                if tw < threshold or tw >= 0.999:
                    continue
                struct.pack_into("<" + jfmt * 4, bin_, jo, target, 0, 0, 0)
                if norm:
                    struct.pack_into("<" + wfmt * 4, bin_, wo,
                                     int(round(scale)), 0, 0, 0)
                else:
                    struct.pack_into("<" + wfmt * 4, bin_, wo, 1.0, 0.0, 0.0, 0.0)
                changed += 1
    print("  hardened %-14s %5d vertices to 100%% (threshold %.2f)"
          % (bone, changed, threshold))


def resize_texture(js, bin_, max_px):
    """Shrink embedded images, then rebuild the blob so no dead bytes remain."""
    from PIL import Image
    replacements = {}
    for img in js.get("images", []):
        if "bufferView" not in img:
            continue
        bv = js["bufferViews"][img["bufferView"]]
        off = bv.get("byteOffset", 0)
        raw = bytes(bin_[off:off + bv["byteLength"]])
        im = Image.open(io.BytesIO(raw))
        if max(im.size) <= max_px:
            continue
        im = im.convert("RGBA") if im.mode in ("RGBA", "LA", "P") else im.convert("RGB")
        im.thumbnail((max_px, max_px), Image.LANCZOS)
        out = io.BytesIO()
        im.save(out, format="PNG", optimize=True)
        # Godot chooses the extracted file extension from this MIME type.
        # Keeping image/jpeg after encoding PNG produces unreadable .jpg files.
        img["mimeType"] = "image/png"
        replacements[img["bufferView"]] = out.getvalue()
        print("  texture %s: -> %dpx, %.1f MB -> %.1f MB"
              % (img.get("name"), im.size[0], len(raw) / 1e6, len(out.getvalue()) / 1e6))
    if not replacements:
        return bin_
    new_bin = bytearray()
    for i, bv in enumerate(js["bufferViews"]):
        data = replacements.get(i)
        if data is None:
            off = bv.get("byteOffset", 0)
            data = bytes(bin_[off:off + bv["byteLength"]])
        while len(new_bin) % 4:
            new_bin.append(0)
        bv["byteOffset"] = len(new_bin)
        bv["byteLength"] = len(data)
        new_bin.extend(data)
    return new_bin


def main():
    argv = sys.argv[1:]
    args = [a for a in argv if not a.startswith("--")]
    max_px, resize = 1024, "--no-tex-resize" not in argv
    harden_bones, harden_at, drop = [], 0.5, set()
    if "--tex" in argv:
        max_px = int(argv[argv.index("--tex") + 1])
        args = [a for a in args if a != str(max_px)]
    if "--harden-bones" in argv:
        raw = argv[argv.index("--harden-bones") + 1]
        harden_bones = [b for b in raw.split(",") if b]
        args = [a for a in args if a != raw]
    if "--harden-at" in argv:
        raw2 = argv[argv.index("--harden-at") + 1]
        harden_at = float(raw2)
        args = [a for a in args if a != raw2]
    if "--drop" in argv:
        raw3 = argv[argv.index("--drop") + 1]
        drop = {d for d in raw3.split(",") if d}
        args = [a for a in args if a != raw3]
    if len(args) < 2:
        print(__doc__)
        return 1
    src_dir, out_path = args[0], args[1]

    if os.path.isfile(src_dir) and src_dir.lower().endswith(".glb"):
        # Already-merged single-file export: nothing to copy between files,
        # every animation already targets this file's own nodes. Just rename,
        # drop, harden and resize in place.
        js, bin_ = read_glb(src_dir)
        print("base: " + os.path.basename(src_dir) + "  (single pre-merged file)")
        kept = []
        for a in js.get("animations", []):
            nm = clip_name(a.get("name", ""))
            if nm in drop:
                print("  - %-14s dropped" % nm)
                continue
            a["name"] = nm
            kept.append(a)
            print("  = %-14s (%d channels)" % (nm, len(a.get("channels", []))))
        js["animations"] = kept
    else:
        files = sorted(glob.glob(os.path.join(src_dir, "*.glb")))

        # raw/ is not only animation exports any more. Since the Meshy API work
        # (2026-09-09) it also holds standalone WEAPON PROPS -- Cross's maul and
        # shield are generated by text-to-3d and have no skin, no rig and no
        # animations at all -- and occasionally a rejected body preview kept for
        # comparison. This branch assumes every file carries a clip, so an
        # animation-less .glb either crashes it or, worse, gets picked as `base`
        # and silently produces a character with no clips. Skip them by the only
        # thing that actually matters here: does it contain an animation.
        anim_files = []
        for f in files:
            try:
                probe, _ = read_glb(f)
            except ValueError:
                print("  ! %s is not a binary glTF, skipped" % os.path.basename(f))
                continue
            if probe.get("animations"):
                anim_files.append(f)
            else:
                print("  . %s has no animations (prop/static), skipped"
                      % os.path.basename(f))
        files = anim_files

        if not files:
            print("no .glb files with animations in " + src_dir)
            return 1

        # Base = whichever file holds the idle clip if we can find it, else the first.
        base = files[0]
        for f in files:
            if "Idle" in os.path.basename(f):
                base = f
                break
        js, bin_ = read_glb(base)
        print("base: " + os.path.basename(base))

        base_anim = js["animations"][0]
        base_anim["name"] = clip_name(base_anim.get("name", "idle"))
        print("  kept animation '%s' (%d channels)" % (base_anim["name"], len(base_anim["channels"])))

        for f in files:
            if f == base:
                continue
            sjs, sbin = read_glb(f)
            for a in sjs.get("animations", []):
                nm = clip_name(a.get("name", os.path.basename(f)))
                if nm in drop:
                    print("  - %-14s dropped" % nm)
                    continue
                n = copy_animation(js, bin_, sjs, sbin, a, nm)
                print("  + %-14s (%d channels)  <- %s" % (nm, n, os.path.basename(f)))

        # The base file was chosen for its mesh and skeleton; if its CLIP was dropped,
        # remove just the animation and keep everything else.
        if base_anim["name"] in drop:
            js["animations"] = [a for a in js["animations"] if a is not base_anim]
            print("  - %-14s dropped (base file's clip)" % base_anim["name"])

    if harden_bones:
        for b in harden_bones:
            harden_weights(js, bin_, b, harden_at)

    if resize:
        bin_ = resize_texture(js, bin_, max_px)

    # ── Loud failure on a name mismatch ──────────────────────────────────────
    # The game looks up clips BY NAME (Model3DSprite plays "idle"/"walk" and
    # one-shots "attack"/"hurt"/"death"). A clip Meshy named something NAME_MAP
    # doesn't cover gets snake_cased and silently never plays — the character
    # just stands in its idle forever, with no error anywhere. That is the single
    # easiest way to ship a broken character, so it is checked here rather than
    # discovered on the board.
    have = {a["name"] for a in js["animations"]}
    missing = [c for c in REQUIRED_CLIPS if c not in have]
    unmapped = sorted(have - set(NAME_MAP.values()))
    if unmapped:
        print("\n  NOTE: clips with no NAME_MAP entry (kept under a generated name):")
        for u in unmapped:
            print("    %s   <- add to NAME_MAP if this is one of the game's clips" % u)
    if missing:
        print("\n  *** MISSING REQUIRED CLIPS: %s" % ", ".join(missing))
        print("      The game plays these by name. Add the Meshy clip name to")
        print("      NAME_MAP, or generate the missing animation.")

    js["buffers"] = [{"byteLength": len(bin_)}]
    out_dir = os.path.dirname(os.path.abspath(out_path))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    write_glb(out_path, js, bin_)
    print("\nwrote %s  (%.1f MB, %d animations)"
          % (out_path, os.path.getsize(out_path) / 1e6, len(js["animations"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
