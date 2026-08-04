# Mob Passive Ability Icons — image-gen prompts (2026-07-24)

Icons for the 11 basic-mob signature passives added 2026-07-24. Each mob now has
one active skill (already iconed/planned) **and** one passive — these are the
passive icons. Mirrors the elemental-sprite prompt style in
`assets/sprites/100_monster_elemental_prompts.txt`.

Drop generated PNGs in `assets/using/status_icons/` (or `assets/icons/`), one
per passive, named by the key in the table. The combat UI already reserves an
icon slot next to every ability name (see CONVENTIONS.md §6), so these slot in
without code changes once the files exist.

## Shared style (prepend/keep consistent across all 11)

> A single square game ability icon, 256×256, centered emblem on a solid green
> background (for easy keying), thick black outline, flat cel-shaded colors, high
> contrast, chunky toon fantasy video-game art style. No text, no border frame,
> no drop shadow — just the icon symbol filling ~80% of the frame. Readable at
> small size (reads clearly at 48×48).

## The 11 icons

Generate as one 3×4 sheet or individually. Each line is the emblem to place in
the shared style above.

| # | Mob | Passive | File name | Emblem prompt |
|---|-----|---------|-----------|---------------|
| 1 | Goblin | Pack Courage | `passive_goblin_pack` | Three small snarling green goblin heads clustered tight together, the middle one raised with a jagged little dagger, radiating a faint yellow courage glow — strength-in-numbers. |
| 2 | Goblin Archer | Focus Fire | `passive_archer_focus` | A red concentric target reticle with a single arrow buried dead-center in the bullseye, three motion streaks showing repeated hits stacking on the same spot. |
| 3 | Goblin Shaman | Spirit Link | `passive_shaman_link` | A glowing green spirit wisp with soft healing tendrils arcing outward to two faint allied silhouettes, gentle restorative light, a small totem at the base. |
| 4 | Orc | Bloodrage | `passive_orc_rage` | A snarling orc tusked jaw with furious red glowing eyes, cracked skin leaking rage-red energy, a spatter of blood — a wounded beast getting angrier. |
| 5 | Slime | Split | `passive_slime_split` | One green blob slime mid-division, splitting into two smaller wobbling slimes with a stretchy connecting strand between them, droplets flying. |
| 6 | Lizard | Cold Blood | `passive_lizard_coldblood` | A calm reptilian eye with a vertical slit pupil set in scaly cold-blue skin, faint green regenerative shimmer, a curled tail resting — patient and recovering. |
| 7 | Bear | Fury | `passive_bear_fury` | A roaring bear head with bared fangs, motion-blur speed lines around it and red fury aura, claw slashes streaking across — rage rising with each wound. |
| 8 | Troll | Regeneration | `passive_troll_regen` | A green troll fist knitting back together from a wound with glowing regenerative sinew, a small crossed-out flame-and-lightning mark in the corner to signal the fire/lightning weakness. |
| 9 | Wind-Up Bot | Overclock | `passive_windup_overclock` | A brass clockwork gear spinning fast with heat glowing orange-red at its teeth, small steam puffs and electric sparks, a rising speed arrow — a machine redlining. |
| 10 | Skeleton | Undying | `passive_skeleton_undying` | A cracked white skull reassembling itself, loose bone fragments swirling back into place on a pale necrotic glow, one eye socket relighting — refusing to stay dead. |
| 11 | Rat | Infestation | `passive_rat_infest` | A pack of three beady-eyed rats swarming over each other with sickly green disease vapor rising, bared yellow teeth, a small biohazard-ish plague motif. |

## Notes for whoever generates these

- Keep the **solid green background** so they key cleanly like the sprite sheets.
- If generating a sheet, use the same 2-rows-of-three framing convention as the
  monster sheets; an 11-icon set works as a 3×4 grid (leave one cell blank).
- Element variants (fire/water/etc. slimes, orcs, bears…) all **share** their
  base mob's passive icon — no per-element passive icons needed.
- These are passive/status icons, distinct from the active-skill icons (Shank,
  Corrosive Goo, etc.) still on the planned asset list.
