# Vertical Depth Baseline

Measured 2026-09-21 against tag `pre-verticality-baseline` / commit `ef9976c3`.
This document is the comparison point for the vertical-depth work. It records
the current game without proposing stat changes.

## Verification state

- Import/parse: pass.
- Boot smoke: pass.
- UI smoke: pass.
- Event smoke: 182 checks / 37 events, pass.
- Map smoke: 23 steps, pass.
- Map generation: 2,000 maps, zero violations.
- Ability probe: 113 kits, zero errors, zero silent abilities.

## What real-run history currently records

`RunHistory` keeps outcome, terminal wave, total kills, crystals, meta investment,
difficulty trace, final team/levels, relic ids, equipment rarity counts, fusion
choices and terminal death cause.

The field named `damage` is **not run damage**. It is the damage from the final
battle only. Per-battle after-action rows already exist in memory (damage,
healing, attributed damage taken and first-contribution time), but ordinary
battles discard them after producing one heuristic sentence.

The minimum observational upgrade before mechanical tuning is a schema-v2
`battles` array containing:

- build id and run seed;
- wave, map node tier, battle seed and encounter roster;
- outcome, simulated/real duration and survivors;
- team damage, healing and damage taken;
- per-hero class, level, alive state, formation position and existing
  after-action fields.

This instrumentation must not change calculations, RNG, targeting or timing.

## Waves 1-10: measured power

Power is `WaveDirector.score_spec`; it does not value every boss mechanic.

| Wave | Normal | Veteran | Brutal |
|---:|---:|---:|---:|
| 1 | 367 | 642 | 735 |
| 2 | 877 | 1,327 | 1,793 |
| 3 | 1,755 | 2,671 | 3,587 |
| 4 | 2,244 | 3,361 | 4,505 |
| 5 | 4,568 | 6,750 | 9,135 |
| 6 | 3,768 | 5,644 | 7,514 |
| 7 | 3,430 | 5,145 | 6,898 |
| 8 | 4,204 | 6,387 | 8,403 |
| 9 | 6,140 | 9,205 | 12,308 |
| 10 | 4,832 | 7,300 | 9,488 |

The numeric curve is not a continuous escalation: wave 5 is followed by two
lower-power waves, and the displayed wave-10 threat is 21% below wave 9. Khagan
has multi-phase mechanics/possession that the score omits, so the displayed
threat is not a truthful boss comparison.

Difficulty filler may introduce creatures before their authored debut. Observed
first-biome examples include Storm Crow, Tidepool Horror, Fire/Storm Giant and
Sky Wyvern. Harder tiers therefore mean different mechanics, not simply more
of the enemies the biome taught.

Fixed `WaveData` names describe the Normal roster and become false on harder
tiers. Example: `First contact — a lone goblin` may contain two enemies.

## Wave-one starting-hero baseline

Thirty deterministic simulations per cell; one level-1 starting hero, default
formation, wave 1.

| Hero | Tier | Win rate | Avg seconds | Avg ending HP |
|---|---|---:|---:|---:|
| Bloodhound | Normal | 100% | 7.86 | 92% |
| Bloodhound | Veteran | 100% | 14.23 | 85% |
| Bloodhound | Brutal | 100% | 11.07 | 78% |
| Nemi | Normal | 100% | 7.61 | 99% |
| Nemi | Veteran | 100% | 14.78 | 91% |
| Nemi | Brutal | 100% | 12.29 | 85% |
| Pastor | Normal | 100% | 10.18 | 86% |
| Pastor | Veteran | 100% | 21.82 | 71% |
| Pastor | Brutal | 100% | 16.98 | 59% |

All three tiers are safe for all three starters in this fixture. Veteran taking
longer than Brutal despite lower scored power demonstrates why roster mechanics,
duration and survival margin must accompany the power number.

## Progression/economy baseline

The existing gold and XP curves assume all ten battles are fought. The map can
replace fights with event/camp/merchant nodes, so these are optimistic
all-combat, no-spend bounds rather than representative paths.

- Full-combat cumulative gold EV through wave 10: Normal 43, Veteran 48,
  Brutal 50, excluding node rewards, interest, events and merchant spending.
- Normal full-combat XP reaches account/team cap 3 by wave 10; Veteran and
  Brutal reach cap 4.
- This conflicts with the documented expectation of fielding four to five
  heroes by wave 10 on Normal.
- Higher tiers compound their advantage: stronger node rewards plus more kill
  XP, gold and drop opportunities. Preserve and measure this snowball before
  adjusting rewards.

## Combat comprehension baseline

Already visible:

- direct damage/heal numbers, distinct crits, HP/MP/ultimate bars and hit reacts;
- authored Goblin Shank and Slime Goo windups/impacts;
- Slime Split burst/logging;
- optional prep target arrows;
- collapsed combat history and live damage meter;
- in-memory after-action damage/healing/taken/first-contribution rows.

Major attribution gaps:

- named active/ultimate casts are not captioned over their caster;
- only stun has a general named status icon;
- Blood Frenzy, Nemi Resonance, Pastor buffs, relic triggers and synergy effects
  are largely silent;
- delayed abilities can be logged before their actual result;
- damage meter omits healing/taken and loses dead heroes;
- post-battle UI reduces the existing after-action rows to one sentence.

## Locked regression scenarios

1. Fixed-seed power/composition snapshot for every tier, waves 1-10.
2. Gold/XP all-combat bounds, explicitly labelled as such.
3. Fixed map seeds for minimum-combat, maximum-combat and merchant-spend paths.
4. Wave-5 legal starter duos/trios at level 2 across tiers and formations.
5. Same legal level-3 teams on wave 9 and wave 10; record boss phase transitions,
   duration and survival, not only `score_spec`.
6. Fresh-account roster sampling constrained by real unlocks, economy and cap.
7. Premature-debut check for difficulty filler.
8. Presentation-layer determinism check: same seed with narration enabled and
   disabled must produce identical targets, hit timing, HP, winner and rewards.

## Next implementation slice

Implement the observational schema-v2 battle history first. Then capture real
waves 1-10 before adding the balance-neutral wave-one comprehension layer:
cast captions, a small set of consequential state indicators and a compact
post-fight contribution card. No stats, cooldowns, targeting or encounter
compositions should change in that slice.
