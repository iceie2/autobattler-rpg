# Vertical Depth Backlog

Source of truth for the vertical-depth pass. **This file outranks any chat
transcript.** If a decision is not written here, it is not decided.

Findings come from `VERTICAL_DEPTH_BASELINE.md` (measured 2026-09-21 against
tag `pre-verticality-baseline` / commit `ef9976c3`). Owner decisions were given
2026-09-21 and are recorded below in the owner's own framing.

## Standing context - do not re-derive

- **This is a roguelite.** The crystal tree is permanent between-run
  progression. Any model that assumes a single power baseline is wrong.
- **A fresh account is one cohort, not the baseline.** Every analysis compares
  at least: fresh, economy-focused, roster/XP-focused, combat-focused, and
  high-investment tree builds.
- **Difficulty tiers are progression targets.** Content a fresh account loses
  to is working as designed. "Fresh account cannot win Brutal" is not
  automatically a bug - it may be the point.
- Rule for any implementation slice: **write the decision here and commit it
  before writing code.** Implementation commits reference the VD id.

## Status legend

`OPEN` not started - `ACTIVE` in progress - `PARTIAL` foundation landed, work
remains - `DONE` closed - `DEFERRED` intentionally postponed with a trigger -
`N/A` owner declined

---

## VD-01 - Run history does not support comparison - status: PARTIAL

**Finding.** `RunHistory.damage` stores the *final battle's* damage, not run
damage. Battle duration is discarded. Per-hero after-action rows (damage,
healing, attributed damage taken, first-contribution time) already exist in
memory but are thrown away after producing one heuristic sentence.

**Owner decision.** Agreed, and tied to Slay the Spire 2 tracking everything
from the beginning. Logs were attempted earlier but never produced anything
usable. Owner wants this tackled.

**Landed.** Telemetry v2 on `feature/telemetry-v2`, commit `47e6dae` - crystal
tree loadout at run start/end, map choices plus alternatives offered, hero/relic
offers and rerolls, event choices and resolved effects, merchant activity,
difficulty commitments, full battle rosters/seeds/duration/survivors/after-action,
stable run id across save-resume, JSONL export via Run History.

**Remains.**
- Aggregation/reporting that turns JSONL into cohort comparisons.
  *(in progress - `scripts/core/telemetry_report.gd`, uncommitted as of
  2026-09-21)*
- Real playtest data. The schema is untested against actual runs.

**Done when.** A report can answer "what did cohort X's wave-10 roster, gold and
survival look like" from logged runs without hand-reading JSONL.

---

## VD-02 - Waves 1-10 power curve is uneven - status: N/A

**Finding.** Wave 5 is followed by two lower-power waves; wave 9 is the
numerical peak; wave 10 scores 21% *below* wave 9 because Khagan's
possession/phase mechanics are not represented in `score_spec`.

**Owner decision.** N/A - declined as a standalone item.

**Note.** The wave-10 half of this is not really a curve problem, it is a
scoring problem, and it is covered by VD-04. Do not re-open VD-02 separately;
fold any curve concern into VD-04's replacement metric.

---

## VD-03 - Wave 1 is safe at every difficulty - status: ACTIVE

**Finding.** Bloodhound, Nemi and Pastor each won 30/30 at level 1 on Normal,
Veteran *and* Brutal. Difficulty still changes duration and ending HP (Pastor
ends Brutal at 59% vs 86% Normal), but the wave-1 difficulty choice is
currently a pure reward optimisation with no risk attached.

**Owner decision.** Explicitly 50/50, and the tension is stated as:

> "in a traditional game it makes no sense to have a level you could never win.
> but in our game, a roguelite where you get stronger between runs, having that
> hard brutal fight you couldn't beat before but now that you have this update
> you can beat wave 1 brutal."

So: a fresh account losing Brutal wave 1 is an acceptable - possibly desirable -
outcome, **provided** the game communicates that it is a progression gate and
not a fair fight the player misplayed. Owner flagged the risk as instructional:
if every starter loses Brutal, a new player may read it as the game being broken.

**Root cause (measured 2026-09-21).** The tier ladder is a flat scored-power
budget multiplier of **1.0 / 1.5 / 2.0** (`wave_scaler.gd`, 2026-09-20 pass).
Wave 1 Normal is 367 power; Brutal is a true 2x at 735. But 2x of a base that
small is still far below what a level-1 hero handles, so the tier is invisible
at wave 1. **The multiplier is not mistuned - it is wave-independent, applied to
a base too small for multiplication to mean anything.** Tier separation
therefore scales with the base curve instead of with design intent.

Difficulty is also a **per-node lane choice** on the run map
(`run_map_screen.gd`, lanes top-easy to bottom-brutal), not a run-wide setting.
Picking Brutal is a route commitment made with the prep screen visible.

**Owner decision - scope widened 2026-09-21.**

> "i like hard gate but i think its bigger to focus on the entire game so 100
> waves or at least 10. but yeah i think brutal level 1 could be a bit tough."

Direction: **hard gate is the preferred flavour** - Brutal should be content a
fresh account comes back for after crystal-tree investment. But the deliverable
is **not** a wave-1 tuning patch. It is a difficulty intent curve for the whole
run - waves 1-10 firmly, 1-100 in shape - stating what each tier means at each
stage, per cohort. Wave-1 Brutal being "a bit tough" falls out of that curve
rather than being hand-set.

**Open questions.**
1. What does each tier *mean* at each stage of the run, per cohort? (the curve)
2. Does the flat 1.0/1.5/2.0 shape survive, or does the multiplier need to vary
   by wave so Brutal bites early as well as late?
3. Does the prep screen need to say a lane is above the player's current
   investment, so a gate loss reads as a gate and not a bug?

**Dependency, newly identified.** A difficulty intent curve cannot be stated in
`score_spec` units, because VD-04 establishes that score is not truthful. The
curve must be expressed in *measured* terms (win rate and ending HP per cohort)
and the measurement is the arena harness. **VD-03 and VD-04 are one piece of
work**: the curve defines what to measure, the metric makes it measurable.

**Done when.** A per-cohort, per-tier difficulty intent curve for waves 1-10 is
written into this file, expressed in measured win rate / ending HP, and the
arena harness confirms the live game matches it.

### Measured fresh-cohort curve, waves 1-10 (2026-09-21)

Method: `--mode=sim`, 20 runs, seed 1337, default formation. Team size and hero
level per wave taken from `--mode=xpcurve` for that tier, so each column is
"a fresh account that stayed in this lane all run". Roster drawn from the real
`STARTER_HEROES` pool (Nemi, Bloodhound, Shauna, Headhunter).

**Floor, not prediction.** Sim teams carry no equipment, no relics and no row
bonuses, and the map replaces some fights with non-combat nodes. Absolute win
rates are therefore pessimistic. The *shape* is the finding.

| Wave | Normal win/HP | Veteran win/HP | Brutal win/HP |
|---:|---:|---:|---:|
| 1 | 100% / 99% | 100% / 89% | 100% / 84% |
| 2 | 100% / 71% | 100% / 53% | **15% / 19%** |
| 3 | 65% / 18% | 100% / 54% | 65% / 22% |
| 4 | 100% / 80% | 100% / 44% | **5% / 44%** |
| 5 | **0%** | **0%** | **0%** |
| 6 | **0%** | 40% / 25% | 60% / 32% |
| 7 | **5%** | **0%** | **0%** |
| 8 | 100% / 60% | **5%** | 40% / 27% |
| 9 | 80% / 28% | 60% / 24% | 10% / 14% |
| 10 | **0%** | 90% / 16% | 70% / 15% |

**Finding A - the tier ladder is not monotonic.** At waves 6, 8 and 10 the
*harder* lane has the *higher* win rate. Cause: harder tiers grant more XP, so
the Brutal column fields 4 heroes at L4 on wave 10 while Normal fields 3 at L3.
The reward curve outruns the threat curve. Tier choice is not currently a
risk/reward trade - at several waves it is strictly better.

**Finding B - wave 5 is a wall at every tier, and wave 5 Brutal is malformed.**
Composition dump: wave 5 Brutal is `{"G": 2}` - **two Hill Giants**, two bodies,
both 2x2, nothing else. The tier budget spent its 2.0x by buying a second copy
of the elite. A 2-hero L2 team cannot kill two Hill Giants. Elite waves need a
rule forbidding the budget from duplicating the elite.

**Finding C - walls are composition, not power, confirming VD-04.** Wave 7
Brutal scores **6898**, *below* wave 6's 7538, yet wins 0% against wave 6's 60%.
Score is locally anti-correlated with measured difficulty. `score_spec` cannot
be recalibrated into truth here; it is measuring the wrong thing.

**Finding D - VD-06 is not hypothetical, it is causing the walls.** Wave 6's
lead is `WY` (Sky Wyvern) and wave 7's is `FG` (Fire Giant) - both later-biome
creatures, both in the first ten waves. The two hardest non-elite waves in
biome 1 are hard *because* of premature debuts.

**Finding E - wave 5 Brutal has no name at all** (`"name": ""`), a stronger form
of VD-05 than "the name is inaccurate".

**Consequence for the roadmap.** VD-03 cannot be delivered as a wave-1 tuning
patch. The ordered dependency is now:

1. **VD-06 un-defer for waves 1-10** - stop premature debuts. Findings D says
   this alone reshapes waves 6 and 7.
2. **Elite-duplication rule** - wave 5's second Hill Giant (Finding B).
3. **VD-04 measured threat metric** - Finding C proves score cannot lead.
4. **Tier reward/threat coupling** - Finding A: harder lanes must not also be
   the faster-XP lanes without paying for it.
5. *Then* the difficulty intent curve, including wave-1 Brutal.

---

## VD-04 - Threat score is unreliable - status: OPEN

**Finding.** `WaveDirector.score_spec` is the only threat number and it is not
trustworthy. Pastor averages 21.82s against Veteran but only 16.98s against
Brutal, despite Brutal scoring higher power. Boss phases are invisible to it.

**Owner decision.** The function is **dated** - it was written before
resistances existed, before the run expanded from 30 waves to 100, and before
most heroes had working kits. Owner is open to adjusting it, with one explicit
condition:

> "just need a way of doing it that we don't run into this issue again"

That condition is the actual requirement. A recalibration that hardcodes today's
roster will rot exactly the same way. Prefer a metric that is *measured* (the
arena harness already simulates encounters) over one that is *estimated* from
stat arithmetic, or at minimum one that self-checks against simulation.

**Blocked on.** Nothing hard, but simulated time-to-kill is the obvious
replacement input and VD-01 telemetry makes it verifiable against real runs.

**Done when.** Threat for a wave is derived from something that stays true when
a new enemy, resistance or boss phase is added, and waves 5-10 no longer invert.

---

## VD-05 - Encounter names are false outside Normal - status: OPEN

**Finding.** `WaveData` names describe the Normal roster only. "First contact -
a lone goblin" can contain two enemies on Veteran/Brutal. The contradiction is
visible on the prep screen.

**Owner decision.** Understandable and fixable. The harder-difficulty wave
composition work happened recently; this naming function was simply never
updated to the new scope.

**Done when.** The displayed name is generated from the actual rolled roster,
or is written so it stays true at every tier. Prep screen never contradicts the
board.

---

## VD-06 - Difficulty filler pulls enemies from later biomes - status: LANDED, NOT SHIPPABLE ALONE

> **Un-deferred 2026-09-21.** VD-03's measured sweep (Finding D) showed the two
> hardest non-elite waves in biome 1 are hard *because* of premature debuts:
> wave 6 is led by Sky Wyvern, wave 7 by Fire Giant. This is no longer a
> biome-6-7 polish item for waves 1-10; it is a live cause of the difficulty
> inversions. The multi-element work stays deferred to biome 6-7 as the owner
> decided - only the waves 1-10 containment is pulled forward.

**Finding.** Harder tiers in waves 1-10 can spawn Storm Crow, Tidepool Horror,
Fire/Storm Giant and Sky Wyvern - creatures that debut in later biomes. This
undermines the first biome's teaching structure: harder means *different
mechanics*, not more of what the biome taught.

**Owner decision.** Agreed, and already on the owner's mind - particularly once
the Air and Water biomes land.

> "once we get to biome 6 or 7 we will go multi element."

**Constraint.** Filler must stay within the current biome's roster. Multi-element
mixing remains deferred to biome 6-7 per the owner's decision.

**Done when.** A premature-debut check (already listed as locked regression
scenario 7 in the baseline) passes for waves 1-10 at all tiers.

### Implemented 2026-09-21 - `WaveScaler.DEBUT_ROUND` + `legal_filler(round)`

`_fill_budget` and `fill_to_score` both drew from the whole `FILLER_POOL` at
every round, and both prefer the strongest affordable body, so early Veteran/
Brutal nodes bought the 2x2 decade anchors. Both now draw from
`legal_filler(round)`.

`DEBUT_ROUND` is **derived, not authored**: every entry is the first round that
code appears in `WaveData.get_wave()`. Eight pool codes never appear in an
authored wave and are assigned by family - `R/SK/BRN/GSN/TLN` to round 1 (the
biome-1 normal-element family, whose siblings `M/A/S/WUN/BN/LZN` debut rounds
1-7) and `SG/RW/GY` to round 31 (beast tier; WaveData's Act-4 header names Stone
Golem and Root Walker as Earth-decade bodies).

**Measured effect on composition (biome 1, Brutal).**

| Wave | Lead before | Lead after |
|---:|---|---|
| 5 | `{G: 2}` - two Hill Giants | `{G:1, BRN:1, GSN:1, TLN:5}` |
| 6 | `WY` Sky Wyvern (Air anchor) | `WUN` wind-up bots |
| 7 | `FG` Fire Giant (Fire anchor) | `LZN`/`BN` |

Zero premature debuts in waves 1-10 at any tier. Scored power held within ~2%
at every wave, so the budget still hits its target - the *cast* changed, not the
amount. **Finding B (wave 5 buying a second Hill Giant) is fixed as a side
effect**: `G`'s derived debut is 31, so filler can no longer buy one. The elite
path still places the first.

### BLOCKER - the gate alone makes the game harder

Re-running the VD-03 sweep after the gate:

| Wave | Normal | Veteran | Brutal |
|---:|---:|---:|---:|
| 2 | 100% | 100% | 15% -> **45%** |
| 3 | 65% | 100% | 65% -> **80%** |
| 4 | 100% | 100% | 5% -> **30%** |
| 6 | 0% | 40% -> **25%** | 60% -> **0%** |
| 8 | 100% | 5% -> **25%** | 40% -> **0%** |
| 9 | 80% | 60% -> **5%** | 10% -> **0%** |
| 10 | 0% | 90% -> **85%** | 70% -> **10%** |

Early waves got easier (the gate removed bodies the budget could not otherwise
afford). Late biome-1 waves got **much harder**. Cause: with the anchors gone,
the scored budget converts into **body count**. Wave 9 Brutal is now 18 bodies,
10 of them ranged, against a 4-hero team; before the gate it was 6-7 bodies
around one big premature heavy.

**This is VD-04 restated with evidence.** `score_spec` sums per-unit scores and
is blind to body count relative to team size. Eighteen small bodies and one
giant can price identically and play nothing alike. The budget will keep finding
the cheapest-per-point body unless something constrains shape, not just total.

**Therefore.** The gate is correct and stays - it delivers exactly what VD-06
asked for. It must NOT ship as a standalone difficulty change, because measured
Brutal win rate in waves 6-10 drops to ~0% for a bare fresh team. It ships
together with the VD-04 work that gives the budget a shape constraint.

**New open item, VD-10** (below): the budget needs a body-count / composition
constraint, not only a power target.

---

## VD-07 - Economy projections assume all ten fights - status: OPEN

**Finding.** Gold/XP curves assume ten battles. The map replaces fights with
event, camp and merchant nodes, so the published numbers are optimistic
all-combat, no-spend bounds: cumulative gold EV through wave 10 of Normal 43 /
Veteran 48 / Brutal 50, excluding node rewards, interest, events and spending.

**Owner decision.** Hard to judge in isolation, because crystal-tree upgrades
skew gold and crystal income more than anything else. The standing rule:

> "all of our systems have to be built with those possible upgrades in mind."

So there is no single economy curve to fix - there is a **family of curves, one
per tree configuration**, and any economy target must name which cohort it is
for.

**Blocked on.** VD-01 reporting, to compare modelled EV against logged runs.

**Done when.** Economy projections are published per cohort and per map path
(minimum-combat / maximum-combat / merchant-spend), and labelled as such.

---

## VD-08 - Team size at wave 10 - status: OPEN

**Finding as filed.** Normal progression reaches a three-hero field cap by wave
10, conflicting with documentation claiming four to five.

**Owner correction - the finding had it backwards.**

> "we have events and more importantly roguelite (crystal shop). a fully
> upgraded crystal shop with the right event can have like 10-11 heroes by wave
> 10 so it's actually the opposite of what you think. that's why brutal was
> added. but that may not even be enough and that's a whole different problem to
> tackle."

The three-hero number is the *fresh-account* floor, not the ceiling. The real
spread at wave 10 is roughly **3 heroes fresh to 10-11 heroes fully invested**,
and that spread is intended.

**The actual open problem.** Brutal was added as the answer to high-investment
rosters and may not be sufficient. A ~3x roster size swing at the same wave is
an enormous difficulty range for one tier ladder to cover.

**Blocked on.** VD-01 telemetry - specifically, how fast each cohort reaches 6+
and 10+ heroes. This is the item that most needs real data before any decision.

**Done when.** Measured roster-size-by-wave-10 per cohort exists, and there is a
decision on whether the tier ladder needs a fourth rung or a different axis.

---

## VD-09 - Combat attribution is invisible - status: OPEN

**Finding.** Combat already shows more than it appears to: damage/heal numbers,
distinct crits, HP/MP/ultimate bars, hit reacts, authored Goblin Shank and Slime
Goo windups, Slime Split logging, prep target arrows, collapsed combat history,
live damage meter, in-memory after-action rows.

The weakness is **attribution**, not volume:
- named active/ultimate casts are not captioned over their caster;
- only stun has a general named status icon;
- Blood Frenzy, Nemi Resonance, Pastor buffs, relic triggers and synergy effects
  are largely silent;
- delayed abilities can be logged before their result actually lands;
- the damage meter omits healing and damage taken, and loses dead heroes;
- post-battle UI compresses the existing after-action rows into one sentence.

**Owner decision.** Agreed, verbatim, on the attribution framing.

**Constraint.** Balance-neutral. Locked regression scenario 8 applies: the same
seed with narration enabled and disabled must produce identical targets, hit
timing, HP, winner and rewards.

**Done when.** A player can watch one wave-1 fight and correctly name what
killed what, which support contributed, and which relic/synergy fired.

---

## VD-10 - The scored budget buys body count - status: OPEN

**Discovered 2026-09-21 while implementing VD-06.** `fill_to_score` hits its
power target by adding bodies, and nothing bounds how many. Once VD-06 stops it
buying 2x2 anchors early, it spends the same budget on a swarm: wave 9 Brutal
goes from 6-7 bodies to 18, at the same score.

Against a 3-4 hero fresh team, body count is worth far more than score credits
it - every extra attacker adds damage while the player's action economy is
fixed. This is the same blindness as VD-04 (score ignores mechanics) on a
different axis (score ignores shape).

**Candidate directions - NOT decided, owner call.**
- A body-count ceiling per wave, scaled to expected team size.
- A minimum spend-per-body, so the budget cannot buy only fodder.
- Composition targets (melee/ranged/support ratios) as a budget constraint.

WaveData's authored comments already talk about capping swarms ("swarm spike,
capped"), so the concept exists in the authored table but not in the filler.

**Blocked on.** Nothing, but it is the same conversation as VD-04 and should be
designed with it.

---

## Sequence

Revised 2026-09-21 after VD-03's measured sweep. VD-03 is now the *last* step of
its own chain, not the first - the sweep showed its inputs are broken.

1. **VD-01** finish reporting *(Codex, stranded at usage limit - 325 lines
   uncommitted on `feature/telemetry-v2`)*
2. **VD-06 (waves 1-10 containment only)** - stop premature debuts. Cheapest
   fix with the largest measured effect on the biome-1 curve.
3. **Elite-duplication rule** - wave 5 Brutal buys a second Hill Giant. Filed
   under VD-03 Finding B; small, self-contained.
4. **VD-05** honest encounter names - independent, and wave 5 currently has no
   name at all.
5. **VD-04** measured threat metric - must precede any difficulty-curve target,
   because score is locally anti-correlated with measured difficulty.
6. **VD-03** the difficulty intent curve, including wave-1 Brutal. Needs 2-5.
7. **VD-09** combat attribution layer - independent of all the above.
8. **VD-07** / **VD-08** - both want real telemetry data first.

Steps 2, 3, 4 and 7 are independent of telemetry and of each other.
