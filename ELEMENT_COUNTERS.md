# Element Counters — design doc

Status: Troll counters BUILT 2026-09-24. Rest of the family is design.

## The idea

Some enemies have a passive that specific elements **shut off**. Hitting the
enemy with a counter element turns the passive off for a short time. The player
gets a reason to care which elements are on their team, and the enemy side
carries the rule, so heroes keep their own identity (see why the element-wide
status system was scrapped, 2026-08-02).

## Rules (owner, 2026-09-24)

1. **The two counters depend on the enemy's element.**
2. **An enemy's own element never counters it.**
3. **Totals balance across the whole lineup.** One enemy may lean on an element,
   but each element should counter about equally often overall (tally below).
4. **This is a family of passives**, meant to become a core part of the loop.
5. **Don't assume an existing ability belongs to this system** just because it
   looks similar. Decide per enemy.

## Passive catalogue

| Key | Passive | Counter hit does | Status |
|---|---|---|---|
| `troll_regen` | Regenerates 1.5% max HP/s | blocks regen for 2s | BUILT, per-element pairs |
| — | Shield / damage barrier | ? | idea |
| — | Enrage / stacking buff | ? | idea |

## Counter table

Data: `UnitBase.REGEN_COUNTERS` (scripts/units/unit_base.gd). The Troll's
tooltip text is built from it. `troll_kit_probe` checks rules 2 and 3.

| Enemy | Element | Counter A | Counter B |
|---|---|---|---|
| Troll | Normal | Fire | Lightning |
| Troll | Air | Earth | Water |
| Troll | Water | Lightning | Earth |
| Troll | Earth | Water | Air |
| Troll | Fire | Air | Normal |
| Troll | Lightning | Normal | Fire |

## Elite counters (2026-09-30)

Not a passive-shutoff like the Trolls: a hit of a counter element ERODES a stat.

| Enemy | Element | Effect | Counter A | Counter B |
|---|---|---|---|---|
| Terracotta Colossus (elite) | Earth | each hit strips 6 of its stacked armor ("wet clay crumbles") | Water | Air |

## Tally (times each element appears as a counter)

| Normal | Air | Water | Earth | Fire | Lightning |
|---|---|---|---|---|---|
| 2 | 3 | 3 | 2 | 2 | 2 |

(Tally = the six Trolls plus the Colossus row above: Air and Water each +1.)

## Not in this system (own passives, 2026-09-24)

- **Gargoyle — Stone Ward:** at 50% HP, the next 4 hits deal no damage, however
  big. 4 stone pips on its HP bar. Once per fight. Not element-based.
- **Ember Phoenix — Rebirth:** the first death rebuilds it to 25% HP over 1.2s
  (immune and can't act meanwhile). Once per fight.

## Open items

- Tutorial (later, not now): the first time the player meets a counter passive
  (~wave 3-4 Troll), a popup explains it and names its two counter elements.
