# Relic Milestones - design worksheet

Status: ACCEPTED by the owner 2026-09-27 (all rows, two tiers, remove the tree
nodes, end-of-run collection screen); building. Decision recorded in
`VERTICAL_DEPTH_BACKLOG.md` **VD-20**. Unlock conditions are moves, so the owner
keeps, changes or cuts each row; thresholds are numbers and can be tuned.

## The idea (owner, 2026-09-27)

> "so we have relics locked behind crystal tree. i thin we should move those to
> milestone unlocks. either from beating certain waves/bosses or if they do a
> certain team comp etc. and once u unlock them they are in future runs"

Relics stop being crystal purchases and become things you **earn by playing a
certain way**. Once earned, a relic is in the pool for every future run.

## What is gated today

46 crystal-tree nodes (the owner's save owns none of them):

- **32 single-relic nodes** in 8 mechanic families: Execute, First Strike, Gold
  Scale, Momentum, Opening, Row, Ult Refund, Underdog - mostly one node per grade.
- **14 ladder bundles**, each unlocking the upper rungs of one stat relic line
  (33 relics): HP, Attack, Magic, Attack Speed, Crit Chance, Crit Damage, Armor,
  Lifesteal, Gold, Boss Damage, Double Attack, On-Kill, Start Shield, Ult Charge.
- Found while mapping: A- and S-grade First Strike say "requires crystal tree
  unlock" but are not in `RELIC_UNLOCK_KEYS`, so nothing gates them.

## Design rules (proposed)

1. **The condition teaches the relic.** Momentum (attack speed that ramps in long
   fights) unlocks by winning a long fight; Opening (burst in the first seconds)
   by winning a fast one. By the time you see the relic, you already know when
   it is good. This is Balatro's unlock pattern.
2. **Unlock by family, in two tiers.** The easy version unlocks the family's low
   grades (D-B); a harder version unlocks A-S. 22 families/ladders -> ~40
   milestones instead of 46 separate purchases.
3. **Mix progress and play style.** Some milestones are bosses and difficulty;
   most are how you won - fight length, formation, team makeup, a hero's stats.
4. **Tier 1 should happen in normal play within the first few runs**, so a new
   account watches its pool grow; tier 2 is the long goal.
5. **Players must be able to see what to chase.** A collection screen lists every
   locked relic with its condition, and an unlock banner fires the moment one is
   earned. Without both, unlocks read as random.
6. **Remove the 46 tree nodes** (owner's earlier call on the synergy nodes: "we
   have SOOO many nodes"). No refunds needed - the owner's save owns none.

## Draft mapping - mechanic families

Signals marked * need a small new per-fight counter; everything else is already
known at the end of a fight.

| Family (what it does) | Tier 1: D-B grades | Tier 2: A-S grades | State |
|---|---|---|---|
| Opening (bonus damage for the first seconds) | Win a fight in under 6 s | Beat an elite in under 10 s | accepted |
| Momentum (attack speed ramps as the fight goes) | Win a fight that lasts 40+ s | Beat a decade boss in a fight lasting 60+ s | accepted |
| Row (front-row heroes deal more) | Win with 4+ heroes in the front row | Beat a decade boss with 4+ heroes in the front row | accepted |
| Execute (bonus damage to low-HP enemies) | Beat your first decade boss (wave 10) | Beat a decade boss on Brutal | accepted |
| First Strike (first attack is a guaranteed crit) | Kill an enemy in the first 2 s of a fight | Kill an elite in the first 5 s of a fight | accepted |
| Ult Refund (kills refund ult charge) | Cast 4 ultimates in one fight* | Cast 10 ultimates in one fight* | accepted |
| Underdog (stronger per dead ally; A/S only) | - | Win a fight after losing half your team | accepted |
| Gold Scale (damage grows with gold held; A/S only) | - | Start a fight holding 150+ gold | accepted |

## Draft mapping - stat ladders (upper rungs)

Where a ladder matches a role, the condition is a **team comp** (owner asked for
comps); otherwise it is one hero reaching the stat.

| Ladder | Unlock | State |
|---|---|---|
| Armor | Win a fight with 3+ Tanks | accepted |
| HP | A hero reaches 3,000 max HP | accepted |
| Magic | Win a fight with 3+ Mages | accepted |
| Attack | Win a fight with 3+ Fighters | accepted |
| Attack Speed | Win a fight with 3+ Ranged heroes | accepted |
| Lifesteal | Win a fight with 2+ Healers | accepted |
| Crit Chance | A hero reaches 40% crit chance | accepted |
| Crit Damage | A hero reaches 3x crit damage | accepted |
| Gold | Finish a fight holding 200+ gold | accepted |
| Boss Damage | Beat 3 decade bosses (any runs) | accepted |
| Double Attack | 15 double attacks in one fight* | accepted |
| On-Kill | One hero gets 8 kills in one fight | accepted |
| Start Shield | Win a fight where shields absorb 1,000 damage* | accepted |
| Ult Charge | One hero casts 3 ultimates in one fight* | accepted |

Element comps ("win with 4 Fire heroes") are left out on purpose until the
element synergy question settles; hero-verb comps can unlock archetype pieces
later (e.g. "win with Coal, Sear and Ember" -> Kindred Flames).

## Build notes (no design decisions)

- `Progression` keeps an `unlocked_relic_milestones` set in the save;
  `is_relic_unlocked` / `is_ladder_unlocked` read it instead of tree levels.
- One `RelicMilestones` checker runs at the end of every won fight with the facts
  above; it records new unlocks, fires the banner and logs telemetry.
- Tree removal goes through the generator AND surgical data edits (the live tree
  carries post-generation nodes - see the crystal-tree memory).
- Collection screen + unlock banner are UI the owner reviews.

## Open questions

1. Unlock by family in two tiers (recommended), or each of the 46 relics on its
   own condition?
2. Keep, change or cut each row above.
3. Remove the 46 tree nodes (recommended), or keep them as an alternative way to
   buy an unlock?
4. Does a milestone count on any difficulty, or only on the difficulty named?
