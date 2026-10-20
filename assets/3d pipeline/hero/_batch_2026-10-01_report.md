# Sear / Spore / Pastor — 3D batch, 2026-10-01

**Three candidates pending human visual approval.** No production asset was
replaced; all three are wired as versioned candidates (`<hero>_v001.glb`) in
`VisualUnit.HERO_MODEL_PATHS`, each reversible by deleting one line. Their 2D
sprites are untouched.

## Cost

**105 credits of a 112 expiring balance. 7 left, 4 after one reject.**

| step | each | total |
|---|---|---|
| concept (Gemini, owner-generated) | 0 | **0** |
| body (`image-to-3d`, meshy-t2 smart-topology, 10k) | 15 | 45 |
| rig (returns walking + running free) | 5 | 15 |
| 5 paid clips (attack/skill/ult/hurt/death) | 15 | 45 |
| Sear replacement ult (action 130) | 3 | 3 |

Two savings made this fit — three heroes at the full 6-clip spec would have been
114, over the 112 available:

- **Idles are synthesized**, not bought (`freeze_pose.py`), saving 9.
- **No props.** All three concepts are empty-handed by design, saving 15.

## Inventory

| | tris | clips | file |
|---|---|---|---|
| Sear | 10,223 | 8 | 2.3 MB |
| Spore | 10,407 | 7 | 2.3 MB |
| Pastor | 10,415 | 7 | 1.9 MB |

All three: exact 24-bone rig name-set match, texture downscaled to 1024 at
merge, facing verified **+Z before rigging**, no sockets, no props.

## The designs

**Sear** — hooded human fire magus, kept close to his 2D art but with the
floor-length robe cut to mid-shin so both boots are visible. Not a redesign.

**Spore** — a REDESIGN. His 2D art is a hooded figure whose robe ends in root
tendrils with no feet, which the fixed 24-bone rig cannot represent at all (the
same wall Vail's legless tornado hit). He is now a solid bark-and-moss creature
on two real root legs, mushroom cap worn as a helmet, black hollow face with two
violet points. Identity preserved; the unriggable parts designed out.

**Pastor** — the one that needed two rounds. The joke is that he is a DEVIL
dressed as an ordinary preacher, almost passing. Round 1 came back in a runed
cult robe with a rope belt, which killed the gag entirely — it read as a cult
demon, not a disguise. Round 2 bans runes, sigils and rope belts outright and
puts him in a plain black cassock with a crisp white dog collar and spectacles,
so the horns and cloven hooves are the only things out of place.

## Clip picks, and the cloth rule

Sear and Pastor wear mid-shin robes, so they take PLANTED casts only. Spore has
no cloth, so he takes the lunging actions (131/133/135) that Vail's report
rejected for gowns. Measured hand travel over the trimmed window:

| | attack | skill | ult |
|---|---|---|---|
| Spore | 6.30 | 4.56 | 6.96 |
| Pastor | 2.05 | 1.32 | **5.87** |
| Sear | **0.95** | **0.84** | 3.69 |

Pastor's ult is action 51 *Shouting Angrily* — both arms thrown wide in a
proclamation, which is exactly what his ult does (every enemy weakened for the
round). It is the best-matched clip in the batch.

Every ability key carries a **per-hero suffix**, renamed in each hero's
`raw/_merge` staged copy. That is not caution for its own sake:
`mage_soell_cast_5` is used by Sear AND Pastor *in this same batch*, and
`_7`/`_8`/`Charged_Spell_Cast` already belong to Vail, Reed and Cross.
`NAME_MAP` is one dict — unsuffixed keys would have silently overwritten each
other, the exact failure that broke Lumen's re-merge when Reed landed. Audited
after: 58 entries, **0 harmful collisions**.

## Three clips tore, and were fixed

`skirt_stress.py` caught all three before they shipped:

| clip | before | after | fix |
|---|---|---|---|
| Sear ult | **2.84x**, 10 frames past 2.6 | **2.23x** | action swapped |
| Pastor walk | **2.74x** | **2.23x** | walk cycle instead of run |
| Spore walk | **3.36x** | **2.28x** | walk cycle instead of run |

**Spore is not immune to the cloth rule**, which is worth recording — he has no
garment, but his layered bark leg plates are skinned to the legs and stretch
exactly like cloth. Assuming otherwise would have shipped a 3.36x tear.

**Sear's ult took a real decision.** Action 125 (the window Lumen uses) tore his
robe. `blend_stationary_attack.py` barely helped — 2.84 to 2.79 — because the
tear is driven by the TORSO pitching, and `Hips` is deliberately excluded from
that tool's lower-body set. That is the same wall Vail's ult hit, and the same
answer: replace the action. Action 130 gathers low then flings WIDE, which is
also the better read for Conflagration — it SPREADS the burn to every enemy
rather than dropping something on one. 3 credits.

The walk fix breaks the house "run IS walk" rule for Pastor and Spore
deliberately: both are **move 2**, the slowest tier, so a walking gait is the
honest read for them anyway. Sear is move 3 and keeps the run (2.42x, marginal
but not torn).

**Final state: all 21 clips under 2.6, zero frames over, anywhere.**

## New tool — `tools/model3d/add_breathing_idle.py`

Synthesized idles saved 9 credits and then **failed the gate**:

```
ANIM_PREVIEW_SMOKE FAIL  SEAR: clip 'idle' STARTED BUT THE SKELETON DID NOT
MOVE (max bone travel 0.00000 < 0.00400)
```

The gate is right. The engine's procedural bob/breathe (`visual_unit.gd`
`_bob_offset` / `_breathe_scale`) moves the SPRITE, not the skeleton, so a frozen
idle really is a statue being nudged. Bloodhound hit this and was given a real
breathing idle in v003; this tool is that, generalised.

It adds a slow sinusoidal pitch down the spine chain, weighted so motion
accumulates upward (hips barely move, chest and head carry it), looping
seamlessly. Rotations are composed in **armature space via `pose_bone.matrix`,
never as bone-local Euler** — these rigs report 29-unit bone lengths on a
1.7-unit character, so bone-local axes are meaningless.

Cost: 0 credits, versus 9 to buy three real idles I could not afford. It also
unblocks Headhunter, whose existing `.glb` has the same problem.

## Gates

| gate | result |
|---|---|
| `--headless --import --quit` | exit 0, **0** script/parse errors |
| `recruit_smoke.tscn` | **ALL PASS (26 heroes)** — Sear, Spore, Pastor all report `3d` |
| `anim_preview_smoke.tscn` (WINDOWED) | **ALL PASS** after the breathing fix |
| `arena.tscn --mode=probe` | `"errors": 0`, 113 probed |

## ⚠ The contrast sweep was NOT successfully measured

All six biomes were captured for all three heroes (18 files under
`captures/renders/<biome>/`), but **the perceptual-ΔE metric used in the Lumen
and Lordee reports is not sound, and no number from it is quoted here.**

Three separate contaminations, found by noticing that different characters were
returning *identical* figures:

1. The crop included the board's **gold rail**, so every "bright" sample was
   RGB (255,229,127) — the rail, not the hero. This is what the `dE_bright`
   column measured in **Lumen's and Lordee's reports; those values are wrong.**
2. Excluding the rail, the "dark" sample became the shared **2px black toon
   outline**, identical on every unit.
3. Excluding both, on the pale AIR board the detector picks up the
   checkerboard's other square, returning a "body" median of RGB (165,153,154)
   for near-black Lumen — obviously the board, not him.

The `dE_dark` figures previously reported for Lumen and Lordee were real
figure-vs-tile measurements and both still cleared the threshold on those alone,
so **no shipped conclusion changes** — but the method needs rebuilding before it
is quoted again. The honest fix is to render each hero against a known flat key
colour, or to capture with alpha, so the figure can be isolated without guessing.

Until then the six-biome sheets are the evidence, and they are handed over
rather than scored.

## What a human still has to judge

- **Sear's attack and skill barely move** (0.95 and 0.84 hand travel, against
  Spore's 6.30). Action 134 is the only non-lunging cast still unused, and it is
  a 275-frame planted gesture loop — there is no punchier window in it. His
  attack is the clip a player sees most. **4 credits remain**, enough for one
  replacement if wanted; the lunging alternatives would need a skirt_stress
  re-check on his robe first.
- Several clips sit in the 2.2–2.6 "marginal, look before shipping" band:
  Sear walk 2.42 / skill 2.27 / ult 2.23, Spore walk 2.28 / attack 2.28 /
  ult 2.52, Pastor walk 2.23. Under the torn line, but the tool is explicit that
  a pass is a screen, not a verdict.
- Whether the three read as distinct. **Sear, Pastor and Spore are all robed
  casters, and Necro is a fourth** — this batch concentrates that silhouette.
- Whether Pastor's disguise gag lands at 115 px, where the white dog collar is
  only a few pixels.
- The synthesized-plus-breathing idles are a 2.2° spine pitch. Whether that
  reads as alive, or as subtle to the point of static, is a taste call.

## Notes

No `source/<hero>_master_v001.blend` saved for any of the three: none carries
Blender-side state (no sockets, no props, no hand-authored edits), and every clip
is a raw Meshy export, a recorded trim window, or a tool pass reproducible from
`raw/`. Each `raw/_merge/` holds the exact files its merge consumed, with its own
`.gdignore`.
