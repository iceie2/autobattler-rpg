# Ember — audit and 3D plan (October 4, 2026)

**Status:** Ember is a fire ranged carry: range 5, move 3, attack-damage
scaling, the FIRE aspect. She is one of the last 2D heroes. This audit is read
from the code and the art; nothing has been changed yet.

## 1. Audit

### Art
- **Current 2D art** (`assets/using/ember.png`): a human fire archer with flame
  hair, a gold circlet, an elf ear, a long split wrap dress with flame trim, sun
  bracers, bare feet and a flaming bow at full draw.
- **The locked design rule disagrees.** The character-design rule lists
  *"Ember = small fire elemental, body made of flame."* Her 2D art predates that
  rule, so the 3D conversion is the moment to choose.

### Things the fixed 24-bone Meshy rig can't handle
| Feature in the 2D art | Problem in 3D | Fix |
|---|---|---|
| Long split wrap skirt | No cloth bones: skirts are skinned to the legs and tear on an archer's wide stance (Vail lost 3 of 7 clips to this) | Short tunic over fitted leggings, or no cloth at all |
| Waist-length flowing hair | No hair bones: it rides the head and spine and swings through the arms | Shoulder-length hair or a flame crest |
| Bow held mid-draw | No finger bones, so a hand can't grip; held items must be separate props | Concept empty-handed in an A-pose; bow as a separate prop on a socket (`Bow_Held`, the goblin archer's recipe) |
| A "body made of flame" | Mist and flame can't be outlined or rigged | The element must be the solid material she's made of |

### Kit (`ability_formulas.gd`, `auto_battle_manager.gd`)
- **Passive, Burning Arrows:** every basic attack burns the target for
  0.12× attack damage per tick for 3 s.
- **Skill, Cinder Shot:** 1.0× skill damage to every enemy within 2 tiles of
  the nearest foe, and burns them.
- **Ult, Wildfire:** every burning enemy explodes (1.5-tile blast) for 0.5×
  attack damage plus 4× its burn per second.
- **Bug:** neither the skill nor the ult plays an animation, because there are
  no `play_skill_oneshot` / `play_ult_oneshot` calls. Spore had the same bug.
  A 3D model would show nothing while she casts, so this gets fixed at wiring
  time.
- **No effects of her own:** Cinder Shot draws the generic `BURN` effect, which
  Sear's skill also uses. Wildfire uses `_explosion`'s generic `INFERNO`. This
  breaks the rule that a hero's effects style is her identity. **Out of scope
  for the conversion**; it would be an `EmberVFX` pass afterwards, like Spore's,
  if wanted.
- **Overlap:** Coal, Sear and Ember all apply burn. Her identity is **arrows**:
  she is the only fire hero who fights at range 5 with a bow.

### Animation
These Meshy library actions are free to preview and 3 credits each:
- 224–227 *Archery Shot* (basic attack)
- 222 / 223 / 229 *Draw and Shoot from Back* (skill: drawing from the quiver
  reads as a "special shot")
- 150 *Hit Reaction with Bow* (hurt)
- An ult and a death clip still need picking.

**Every archer action uses a wide stance**, which is a second reason to keep
skirts off her.

## 2. Design options (owner picks)

The concept image is generated free by the owner in Gemini, the same as for
Sear, Spore and Pastor, so it costs 0 Meshy credits.

**A — Fire archer, kept (closest to the 2D art).** Same face, flame-tipped hair
cut to the shoulders, gold circlet, sun bracers, and a fitted short tunic over
leggings and wrapped boots. Lowest risk; she stays a person.

**B — Ember-glass fire sprite (follows the locked rule).** A small, slight
elemental whose body is solid molten glass: orange-gold, glowing from inside,
with dark cooled seams, a flame-shaped crest instead of hair, and bracers. She
stays distinct from Coal (bulky black rock golem) through size and material,
and from Sear (robed human). Glow can be added in-engine as emission.

**C — Salamander archer (creature with a job).** An upright fire salamander:
ember-orange scales, a black-spotted back, a short stub tail and a leather
archer's harness. Non-human anatomy usually comes back cleanest from
generation. The tail has no bones, so it must stay short.

## 3. Pipeline and budget (balance 277; hard stop at 100)

| Step | Credits |
|---|---|
| Concept (owner, Gemini) | 0 |
| Body, `image-to-3d` meshy-t2 smart topology, ~10k faces | 15 |
| Bow prop (text-to-3d untextured) **or** built in Blender | 5 or 0 |
| Rig (walk and run come free) | 5 |
| Clips: attack, skill, ult, hurt, death (idle synthesized) | 15 |
| **Total** | **35–40** |

**Then:**
1. Check facing is +Z before rigging.
2. Socket the bow, fitted at rest and anchored to the fist.
3. Trim each clip to one beat.
4. Run `skirt_stress` on every clip.
5. Add per-hero `NAME_MAP` suffixes.
6. Wire as `ember_v001.glb`. The 2D sprite stays as the fallback.
7. Add the skill and ult animation calls.
8. Run the four mechanical gates.
9. Render on all six biomes for owner approval.

## Progress — October 4, 2026 (paused at the usage limit)

**Owner picked design B.** The concept is `assets/3d pipeline/hero/ember/raw/ember_body_concept_v001.jpg`.

**Done:**
- **Body:** meshy-t2, 10,671 triangles, facing +Z (checked).
  - Body task `01a10646-5063-72f2-87f7-42cf8222e996`.
  - File: `raw/ember_body_textured_v001.glb`.
- **Rig:** task `01a10647-f67a-7330-b4e1-5139e9eef950`.
  - Files: `raw/ember_rigged_v001.glb`, plus walk and run free.
- **Credits:** 20 spent, balance 257.

**Clip picks (chosen from the free preview GIFs, not bought yet):**
| Clip | Action | Why |
|---|---|---|
| attack | 225 *Archery Shot 1* | 26 frames: reach to the quiver, nock, draw |
| skill | 222 *Draw and Shoot from Back* | bigger reach-back and full draw |
| ult | 125 *Charged Spell Cast* | crouch-charge, then arms flung up: the detonation |
| hurt | 150 *Hit Reaction with Bow* | |
| death | 185 *Shot and Slow Fall Backward* | she has no cloth, so a topple is safe |

Use per-hero `NAME_MAP` suffixes (`_ember`): action 125 is already used by Lumen and Vail.

**Next:**
1. Buy the 5 clips (15 credits) against the rig task.
2. Trim each clip to one beat; synthesize the idle with freeze plus breathe.
3. Bow prop: build it in Blender (0 credits) and socket it as `Bow_Held` on the left hand.
4. Merge and wire as `ember_v001.glb` in `HERO_MODEL_PATHS`, with an emission override for her inner glow.
5. Add the skill and ult animation calls.
6. Run the gates and the six-biome review.

## Built — October 4, 2026 (pending owner art review)

**Live file:** `ember_v001.glb`, wired in `VisualUnit.HERO_MODEL_PATHS`. The 2D sprite stays as the fallback.
- 10,671 triangles; 8 clips: idle (synthesized breathing), walk (the run cycle), walk_slow, attack, skill, ult, hurt and death.
- The bow is a `make_prop.py` primitive bound to `LeftHand` (`Bow_Held`) at full draw, turned 180° so the string faces her.

**Engine:**
- Her body glows from its own texture used as the emission map (multiply, energy 0.55).
- The bow's "Wood" material is tinted ember-gold.
- `_ember_cinder` and `_ember_wildfire` now play the skill and ult clips.

**Merge:** `NAME_MAP` gained `*_ember` keys. Unsuffixed `Charged_Spell_Cast` already maps to `skill` for another hero, so it would have collided. The audit found 0 conflicting keys.

**Gates:** import has 0 script errors; recruit smoke passes for all 26 heroes; anim preview passes with Ember in 3D on 8 clips; the arena probe's only silent result is drowned_maw, another agent's enemy. Six-biome review: `captures/renders/ember_3d_20261004/six_biomes.png`.

**Cost:** 35 credits (body 15, rig 5, clips 15); balance 242.

**Open:**
- **Arrow timing.** Her basic-attack arrow fires at the start of the clip, while the draw finishes at the end. The goblin archer has release-frame timing (`play_goblin_bow_shot`); Ember needs the same.
- **Fire board.** The fire biome gives the weakest contrast (orange on lava).
- **Idle bow.** At idle the bow hangs edge-on and reads thin.
- **No effects of her own yet.** She still borrows the generic BURN and INFERNO effects (see §1).

Backups: `autobattler-rpg/backups/ember-3d-20261004/`. The pre-bow merge is `raw/ember_merged.glb`.
