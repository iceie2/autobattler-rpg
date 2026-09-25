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

**Owner framing added 2026-09-23 - what the higher tiers are FOR.**

> "your 100% correct normal is the regular game. but with crystal upgrades and
> our players going from weak to gods with a full crystal upgrade. we need ways
> for the player to have fun/get value out of clearing waves 1 -50 when they are
> pushing new high scores of wave 60-70 etc. thats the point of the higher
> difficulties so trying to find a happy medium."

Two consequences for this item. (1) The owner first floated a 4th tier *between*
Normal and Veteran; that is replaced by **re-spacing the three wave tiers**
(open question 2 above) - the Normal->Veteran step (+50%) is the steepest in the
ladder. (2) A fixed multiplier cannot keep early waves meaningful across a
fresh-to-god power range at all; that job moves to a player-priced tier, **VD-13**.

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

### Finding F - Veteran and Brutal wave 1 are the SAME fight (2026-09-22)

Owner spotted it in-game: the wave-1 Brutal prep screen reads THREAT 735 over
two goblins. Confirmed from `--mode=power`:

```
normal  w1: power 367 | {'M': 1}
veteran w1: power 735 | {'M': 2}
brutal  w1: power 735 | {'M': 2}
```

**Veteran and Brutal wave 1 are byte-identical encounters.** Since Brutal pays
the richer reward table for the same fight, **Brutal strictly dominates Veteran
at wave 1** - there is no reason to ever pick the middle lane. That is a
dominance bug, not just a flatness problem.

**Root cause: budget granularity.** `fill_to_score` can only spend in whole
bodies, and at round 1 the cheapest body the scorer will price is the goblin at
**367 - exactly the entire Normal wave**. So the tier ladder's resolution at
wave 1 is 100% of the wave. Veteran wants +50% and Brutal wants +100%; both
round to "+1 goblin".

`fill_to_score` already has an explicit fallback for this, and its comment names
the exact case ("wave 1 is ONE goblin, so Veteran's half-a-goblin of headroom
buys nothing... take the cheapest body available and overshoot rather than sell
a difficulty tier for nothing"). The fallback fires correctly - it just has
nothing cheap to reach for, so overshooting lands Veteran precisely on Brutal.

**The Rat is the body that should have filled this gap and does not.** `R` is in
`FILLER_POOL`, is mapped in `CODE_TO_TYPE` to a real spawnable `rat`, and is
priced 15 in `UNIT_POWER` - the cheapest in the game. Measured head to head at
wave 1 against a level-1 Nemi: rat dies in 3.7s dealing 25, goblin takes 8.7s
dealing 43. The rat genuinely fights like half a goblin.

But the fallback picks the **minimum-cost** entry by construction, and it picked
the goblin - so `score_code("R", 1) >= 367`. The rat is priced at or above a
goblin while fighting like half of one. Whether that is a `score_unit`
mispricing or a stat-block problem is not yet determined, but it is the same
class of defect as VD-04 (score not describing the fight), showing up in
composition instead of ordering.

**Candidate fixes, not decided.**
- Diagnose the rat's score. If it is mispriced, fixing it restores granularity
  at the bottom of the curve for free and may affect other cheap bodies too.
- Give wave 1's Normal comp a second body so the tiers have something to
  differentiate with. Changes the first fight of the game - a feel decision.
- An additive floor on the low-wave tier budget instead of a pure multiplier.

**Tooling added 2026-09-22:** `--mode=prices --from=N` lists every body legal at
a round with its `score_code` price and its `UNIT_POWER` tag, flags codes that
price at 0 (silently dropped from the budget), and reports `granularity_pct` -
the cheapest body as a share of the Normal wave.

### Finding G - `score_unit` is additive where the game is multiplicative

Measured with the new mode, round 1:

| code | score | UNIT_POWER | hp | dmg | spd | DPS | DPS x HP |
|---|---:|---:|---:|---:|---:|---:|---:|
| M goblin | **367** | 30 | 150 | 21 | 0.68 | 14.3 | 2142 |
| R rat | **387** | 15 | 75 | 24 | 1.06 | 25.4 | 1908 |
| SK skeleton | 450 | 25 | 110 | 28 | 0.74 | 20.7 | 2279 |

True fighting power (DPS x HP) orders these **R < M < SK**, which matches the
measured fight exactly - against a level-1 Nemi the rat dies in 3.7s dealing 25,
the goblin takes 8.7s dealing 43. `score_unit` orders them **M < R < SK**. The
rat and the goblin are inverted.

`score_unit` is a weighted sum:

```
s = max_hp*0.15 + attack_damage*10 + attack_speed*60 + magic_power*8 + resistance*5
```

Two structural problems:

1. **Damage and attack speed are ADDED; the game MULTIPLIES them.** Output is
   `damage x speed`, so a fast/weak body and a slow/strong body price alike
   while dealing very different DPS.
2. **HP is weighted 0.15 against damage's 10**, so one point of attack damage is
   worth ~67 points of HP. In a real fight HP buys uptime - it is the term that
   decides how much of that DPS ever lands. The rat's half-HP costs it only 11
   points while its +3 damage earns +30, so the glass cannon prices *above* the
   body that actually beats it.

This is the root cause behind VD-04 (ordering) and plausibly behind VD-10
(swarm vs anchor), and it is why wave 1 has no cheap body: every round-1 body
prices 367-705, a 1.9x spread, while `UNIT_POWER` spreads them 6.7x.

**Granularity consequence.** Cheapest legal body at round 1 is 367 = **100% of
the Normal wave**, so no tier step below +100% is expressible. That is Finding F.

### IMPLEMENTED 2026-09-22 - and the headline goal was NOT met

Owner approved the rewrite. `score_unit` is now
`sqrt((attack_damage + magic_power) * attack_speed * max_hp * (100+resistance)/100) * K`,
with `K = 6.55` fitted so a level-1 goblin still scores 367 and every earlier
measurement stays comparable. Range and cell-size multipliers are unchanged.

`magic_power` is inside the throughput term deliberately: a pure attack-DPS form
prices the Goblin Shaman (dps 5.9, magic 19) as the cheapest body on the board,
and the budget would have bought nothing but healers. The sqrt keeps the result
linear in level, as the old sum was, so wave magnitudes and the elite-vs-fodder
relationship inside a round are preserved.

**What it fixed - all verified:**

| | before | after |
|---|---|---|
| rat vs goblin price | 387 vs 367 (wrong) | **321 vs 367** |
| round-1 price spread | 1.92x | **2.98x** |
| wave-1 granularity | 100% of the wave | **88%** |
| Veteran wave 1 | `{M:2}` = Brutal | **`{M:1, R:1}`** |
| ordering vs hand-authored UNIT_POWER | contradicts it | near-identical |
| tier ratios, waves 3-10 | - | **1.00 / 1.50 / 2.01** |

Finding F is closed: Veteran and Brutal wave 1 are now different fights.

**What it did NOT fix - the reason it was undertaken.** Inversion rate, two
repeats per tier, old against new:

| tier | OLD | NEW | change |
|---|---:|---:|---:|
| Normal | 0.286, 0.286 | 0.256, 0.256 | -10% |
| Veteran | 0.293, 0.263 | 0.306, 0.306 | **+10%** |
| Brutal | 0.216, 0.194 | 0.229, 0.107 | -18%, but the two passes disagree by 2x |

**Wave-to-wave threat ordering did not measurably improve.** Normal is a little
better, Veteran is a little worse, Brutal is too noisy to call. This is a
negative result and is recorded as one.

**Why, and what it means for VD-04.** Per-unit pricing was never the main driver
of ordering error. The inversions that remain are caused by what NEITHER formula
can see: abilities and boss phases (wave 10's Khagan), and body count relative
to team size (VD-10). Wave 7 is still the clearest case - five far-range burst
snipers that no per-unit price can describe as a wall.

So VD-04's remaining work is not a better per-unit formula. It is either
(a) pricing mechanics explicitly, or (b) accepting `score_spec` as a rough
number and leaning on `--mode=threatcheck` as the gate that keeps it honest.
The rewrite was still worth doing - it fixed two provable bugs - but it should
not be recorded as having solved VD-04.

**Superseded proposal, kept for the record.** Move `score_unit` toward an
effective-power shape, roughly `(damage x speed) x effective_hp`, normalised so
existing waves land near their current numbers. This changes wave composition
across all 100 rounds, so it must be gated: `--mode=threatcheck` exists
precisely to prove the new metric orders waves correctly where the old one does
not, and `--mode=power` can confirm decade totals do not move.

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

## VD-04 - Threat score is unreliable - status: GATE LANDED, METRIC OPEN

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

### Implemented 2026-09-21 - `--mode=threatcheck` calibration gate

**Design decision.** A simulation cannot replace `score_spec`. The prep-screen
threat readout and the filler budget both need an answer in microseconds; a
battle sim takes seconds. So the fast heuristic stays, and what gets added is a
gate that notices when it stops describing the game - which is precisely how it
rotted the first time, silently, across the resistance pass, the 30-to-100
expansion and the hero-kit work.

This is the direct answer to the owner's condition, *"just need a way of doing
it that we don't run into this issue again"*: `score_spec` is allowed to be
approximate. It is not allowed to be **backwards**, and now it cannot become
backwards without a gate going red.

An **inversion** is a pair of waves where score ordering contradicts measured
ordering. Hardness = `(1 - win_rate) * 2 + (1 - ending_hp)`; the ending-HP term
is a tie-break, without which every saturated cell would compare equal.
Near-ties on both axes are ignored (5% of score, 0.15 hardness) so noise cannot
fail a build. The team at each round is the **cohort** team, derived with the
same math as `--mode=xpcurve`, so a wave is measured against the roster a player
walking that lane would actually hold. `--xpbonus/--slots/--events` select the
cohort.

### Measured result - `score_spec` is backwards in 9-10 places per tier

| Tier | Cohort | Inversions |
|---|---|---:|
| Normal | fresh | **9** |
| Veteran | fresh | **10** |
| Brutal | fresh | 1 *(saturated - see below)* |
| Brutal | invested (xpbonus 150, slots 3) | **4** |

Worst offenders: score calls round 10 harder than rounds 4, 5 and 6 on Veteran
while the fight calls it far easier; on Normal, score calls round 9 harder than
rounds 5 and 6 while round 9 wins 80% and both of those win 0%.

**The Brutal fresh number is a trap, and the tool says so.** One inversion is
not health - waves 5-10 all read 0%, so hardness ties at 3.00 and the ordering
check has nothing to compare. Saturation must be broken with the cohort dials
before the number means anything. This is documented in CONVENTIONS.md next to
the command, because a future reader will otherwise see "1 inversion" and
conclude Brutal is fine.

### What the measurement exposed beyond the metric

- **Normal waves 5, 6 and 10 are 0% for a bare fresh cohort.** No filler is
  involved at any of them - this is the authored base curve, and it is
  independent of VD-06 and VD-10. Sims carry no equipment or relics, so this is
  a floor, but three zeroes in ten waves on the *easiest* lane is worth a look.
- **Wave 7 is a wall for everyone.** 5% even for an invested 7-hero L4 cohort.
  Composition is `{BN:2, LZN:5}` - five far-range burst snipers. `score_spec`
  prices a lizard at 40 and cannot see that five of them delete a team before it
  closes the distance. This is the cleanest single example of why VD-04 needed a
  measured gate rather than a recalibration.
- **Wave 9 Brutal is 0% even for the invested cohort** (8 heroes at L5). Bears
  on VD-08: Brutal may be doing too much rather than not enough at the top of
  biome 1.

**Remains.** The gate reports the disagreement; it does not fix it. Deciding
what `score_spec` should become - or what constraint the budget gets (VD-10) -
is the open design work, and it is now evidence-backed rather than guessed.

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

### Related change 2026-09-22 - player XP retune (owner request)

Owner: *"bring our required player xp down a bit so we hit our second hero
consistently on the hill giant wave"*, asking whether Brutal fights should grant
more player XP.

**Brutal already does.** Player XP is summed enemy `xp_reward`, and harder tiers
field more bodies, so wave 1 pays 25 on Normal and 50 on Brutal. No new
mechanism was needed.

**The XP curve was not the problem either.** On a full-clear path level 2
already landed at wave 4 (Normal) / wave 3 (Brutal) - before the Hill Giant.
The cause is the **map**: `MAX_UTILITY_NODES_PER_BIOME` is 4 and the elite is
protected but waves 1-4 are not, so a player can reach wave 5 having fought as
few as one battle. Cumulative Normal player XP is 25 / 80 / 190 / 335 across
waves 1-4, so at `PLAYER_XP_BASE = 300` any single skipped fight in 1-4 left the
player at 190-255 and still level 1.

**Changed:** `PLAYER_XP_BASE` 300 -> 180, `PLAYER_XP_GROWTH` 1.9 -> 2.0.

The growth change is **required, not optional** - lowering base alone gives a
fresh account team 9/9/10 at wave 100 against a spec of 8. Re-fitted with
`--mode=xpcurve` over 100 waves; every landing spot the old fit was chosen for
is reproduced exactly: fresh 8/9/9, full tree 17, full tree + 3 events 20.
Measured on tier 0, the true post-rename baseline - `balance.gd`'s own note
warns that an earlier 2.0 fit was invalidated by reading the wrong tier.

Level 2 now lands at **wave 3 on all three tiers**.

**Knock-on, and it lands on this item (VD-08).** Wave-10 team size rises by one:
Normal 3 -> 4, Brutal 4 -> 5. Reaching level 2 a wave earlier keeps the player a
level ahead through the early-mid run; the curves reconverge by wave 100. Any
VD-08 measurement taken before 2026-09-22 is stale by one hero at wave 10.

**Not done:** the underlying variance. A player who skips two of waves 1-4 can
still arrive at the Hill Giant under-levelled, because the binding factor is how
many battles the map offered, not the cost curve. Granting player XP at
non-combat nodes would fix it at the source, but that is a mechanic change and
was not requested.

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

## VD-11 - Biome element identity dissolves on harder tiers - status: LANDED, RESIDUAL OPEN

**Owner question 2026-09-22:** *"do we ever get around to making it so enemies
follow the biome's element more"*. Answer: **no, and VD-06 does not do it.**
VD-06's debut gate is a one-way ratchet - it stops early waves receiving later
creatures, but places no constraint on later waves fielding earlier ones. So a
Fire-decade wave may legally field the entire Normal/Air/Water/Earth roster.

**Measured 2026-09-22** (`--mode=power --from=1 --to=60`, off-element body share
per biome, boss/elite bodies excluded):

| Biome | Normal tier | Brutal tier |
|---|---:|---:|
| 1 Normal | 5% | 2% |
| 2 Air | 14% | **29%** |
| 3 Water | 14% | **46%** |
| 4 Earth | 5% | **48%** |
| 5 Fire | 0% | **44%** |
| 6 Lightning | 2% | **38%** |

**The authored waves are fine.** The 2026-08-02 retint did its job - Normal tier
is 0-14% off-element. It is the *difficulty filler* that dissolves the theme,
and filler is most of what a harder tier is made of. The harder you play, the
less the biome means. On Brutal, roughly half the board in the Water, Earth and
Fire decades is the wrong element.

Concrete examples: `LZA` (Air lizard) appears in **every** Fire wave 41-49.
Wave 42 Brutal fields `TH` (the Water anchor) and `GSE` (Earth shaman) inside
the Fire decade. Wave 49 is an eleven-code rainbow.

**Second, separate cause - boss honour guards are hardcoded Normal.**
`WaveScaler.build_boss_formation` builds its guard from `M`, `B`, `BRN`, `TLN`,
`GSN`, `LZN` - all Normal-element codes - at every tier and in every decade. So
wave 50, the *Fire* boss, fields `M:7, BN:2, BRN:2, GSN:2, LZN:2, TLN:2, SK:1`
around Emberhollow. Every decade boss fights with a Normal-element escort.

**Why the fix is cheap: it is power-neutral by construction.** Every mob family
carries six element variants that share one stat block (WaveData's retint note
says so explicitly, and it is why the 2026-08-02 retint preserved the power
curve without re-tuning). Swapping filler and guards to the on-element variant
of the same family therefore changes theme without changing balance. This can
ship without disturbing VD-03/VD-04/VD-10.

**Scope note.** The owner's VD-06 decision stands: *"once we get to biome 6 or 7
we will go multi element."* So biomes 1-5 should read pure and deliberate
mixing starts later - which makes the current 44-48% accidental mixing in
biomes 3-5 the opposite of the intent.

**Candidate fix, not decided.**
- Filler prefers the decade's element variant when the family has one; falls
  back to Normal when it does not (goblins have no Water variant - wave 24's
  authored comment already documents that exact hole).
- `build_boss_formation` derives its guard's element from the decade.
- A purity check in the harness alongside the premature-debut check.

### Implemented 2026-09-22 - `retint_counts()` + decade-aware boss guards

`WaveScaler.ELEMENT_VARIANTS` / `CODE_FAMILY` / `decade_element()` /
`retint_counts()`. Applied in `_topped_up` to **the filler and the boss honour
guard only**. `base_counts` - the authored wave - is deliberately left alone:
those comps already went through the 2026-08-02 retint and their remaining
off-element bodies are intentional (wave 12 keeps `SLN` x3, wave 24 keeps four
`A` archers, both documented in WaveData). Retinting them would overrule the
author silently.

The family tables are written out rather than derived by prefix, because the
codes are not regular - Water slime is `SL` not `SLW`, Fire shaman is `S`, Earth
orc is `B`, and a `B` prefix would also swallow the Bear family. Prefix matching
would have mis-tinted three families.

**Measured result - off-element body share, Brutal:**

| Biome | Before | After |
|---|---:|---:|
| 2 Air | 29% | **15%** |
| 3 Water | 46% | **19%** |
| 4 Earth | 48% | **15%** |
| 5 Fire | 44% | **15%** |
| 6 Lightning | 38% | **20%** |

Normal tier unchanged (0-14%), as intended - authored waves were never the
problem.

**Power neutrality verified, not assumed.** Measured with the change reverted
and re-applied: decade power totals moved by -0.33%, -0.25%, -0.02%, +0.83%,
+0.01%, +0.10%. All inside the fill tolerance, which is the trim pass landing on
a different combination, not variants pricing differently.

Wave 50's guard went from `M:7, BN:2, BRN:2, GSN:2, LZN:2, TLN:2` to
`BF:2, BRF:2, LZF:5, TLF:3, S:2` - Emberhollow is finally escorted by fire.

Biome 1 win rates are unchanged within noise; its only movement is wave 10's
guard, which contained `B`, the EARTH orc, and is now `BN`.

### Residual - the remaining 15-20% is bodies with no element variant

Three groups, in descending visibility:

1. **Cross-decade 2x2 anchors.** Filler can still buy another decade's anchor:
   `TH` (Water) appears in Fire waves 42 and 47, `G` (Earth) in 45 and 50.
   These are large, centred and the most visible bodies on the board, so this is
   the residual worth fixing first.
2. **Beast tier** - `OG`, `MT`, `GY`, `SG`, `CC`, `RW` each own one element and
   have no siblings.
3. **Goblins, rat, skeleton** - `M`, `A`, `R`, `SK` have no variants at all.
   WaveData's wave-24 note already documents this hole ("goblins have no Water
   variant").

Group 1 is a filler rule (do not buy an anchor belonging to a different
decade). Groups 2 and 3 need new art/bodies, so they are a content question,
not a code one.

**Ordering note.** This landed before VD-10. Power is preserved, so VD-10's
body-count finding holds; its sweep was re-run and biome 1 is unchanged.

---

## VD-12 - The map can deal a row with no fight a fresh account can take - status: DONE

**Finding (2026-09-23, owner screenshot).** A 2-wide battle row that receives a
side node has exactly one fight, and that fight's tier is rolled at random
(`RunMap._distinct_tiers(1)`), so about a third of those rows offer Brutal and
nothing else. The owner's map showed wave 3 as *side node or Brutal*.

Separately, when two equal-width rows meet, `_wire_edges` picks one of several
maximal wirings by coin flip, and the mercy pass (RUN_MAP_PLAN §19) accepts an
*equal*-tier child as an escape. For 3 -> 3 (every elite and boss transition)
only 1 wiring in 4 gives every lane a strictly easier option.

**Owner decision.**

> "first thing i notice i dont like is wave 3 event or hard fight. so my first
> thought to say is it should always have a easy or medium fight aswell. but if
> it chooses medium and its wave 5. i dont think anyteam can beat wave 5 medium
> with no crystal shop updates. so since our game is a roguelite we either
> always need the easy option for players that dont have crystal upgrades.
> unless we did different map paths by crystals invested but that feels weird."

> "it should be easy to easy. medium to easy and medium. hard to medium and
> hard. remember we want the player to always have ways to go easier in
> difficulty."

**Decided.**
1. **Every battle row contains a Normal fight.** A side node replaces a harder
   tier, never Normal. No crystal-gated map paths - the map is the same for
   every account; the account is what changes.
2. **Every lane above Normal has a strictly easier way forward** (an easier
   fight or a side node) wherever the no-crossing rule allows it; the Normal
   lane needs a Normal fight or a side node. Wiring tie-breaks lean downhill:
   a node shared by two lanes goes to the harder lane as its way down.

**Consequence, accepted.** In equal-width row pairs nobody can step UP - an
easy->medium path and a medium->easy path cross, so "always a way down" rules
out climbing there. Climbing happens where rows widen and at the biome's
opening fan, and the easy lane cannot reach the hard elite. This is the
crossing rule, not a tuning choice; the map harness reports how much climbing
is left so it stays a number.

**Files.** `scripts/waves/run_map.gd`, map metrics in `scripts/arena/arena_main.gd`,
`scripts/arena/map_smoke.gd`. No overlap with the VD-03/04/06/10 files
(`wave_scaler.gd`, `wave_director.gd`).

**Done when.** `RunMap.validate()` enforces both rules and `--mode=map` passes
2000 maps with 0 violations; the harness reports nodes with no way down (strict)
and nodes that can still step up, before and after.

**Landed 2026-09-23.** `_distinct_tiers` always includes Normal; the mercy pass
uses a strict `_is_way_down` (an easier fight or a side node; Normal for the
Normal lane) instead of "not harder"; wiring ties and jitter lean downhill.
`validate()` fails a battle row with no Normal fight and any node that could be
given a way down without a crossing. Measured, `--mode=map`, 2000 maps:

| | before | after |
|---|---:|---:|
| battle rows with no Normal fight | 1.49/map | **0** |
| nodes with no strictly easier way forward | 7.07/map | **0** |
| nodes that can still step up | 9.46/map | 4.36/map |
| paths drawn / paths missing | 47.2 / 0 | 47.1 / 0 |
| violations | 0 | 0 |

The old metric reported 0.97/map "hard only" because it counted an equal-tier
child as an escape - it was hiding most of the problem. Climbing roughly halved,
which is the accepted consequence above, now visible as `can_climb_nodes`.

---

## VD-13 - Nothing keeps waves 1-50 worth playing for a strong account - status: OPEN

**Owner framing.** Quoted under VD-03 (2026-09-23): the higher difficulties
exist so a player who has gone "from weak to gods" still gets fun and value
from waves 1-50 while pushing records at 60-70. Direction approved 2026-09-23:
*"sure i like your ideas you can proceed"*.

**Why the current ladder can't do it.** Normal/Veteran/Brutal are flat
multipliers of the WAVE's budget (1.0/1.5/2.0). A near-maxed account flattens
2x of wave 10; no fixed multiplier spans a fresh-to-god power range.

**Direction agreed.**
- Normal / Veteran / Brutal stay anchored to the **wave** - same map, same
  fights for every account; Normal is the regular game.
- A 4th tier, working name **Nemesis**, is anchored to the **player**: priced at
  roughly 1.1x the player's own team power, so it is a real fight for a fresh
  account and for a god alike.
- **It pays like the fight it is** - rewards scale with its actual price, most
  naturally in crystals. Otherwise a god earns wave-5 loot for a god-sized fight.
- **Priced once, when the biome's map is generated** (snapshot of team power at
  biome start). The dossier's promise stays fixed and benching heroes or
  unequipping before the node can't game it.
- **Opt-in only** - one node among the fixed tiers, chosen for the payout. That
  is what separates it from level-scaling treadmills.
- **Elite and boss rows gain a Nemesis node.** Owner was 50/50 on four
  elite/boss options; a boss scaled to your own team is the argument for.
- **Colours.** Owner: *"the map has been planned since the start but no one has
  played it"* - recolouring costs nothing learned. Today's green/blue tiers
  collide with the C/B reward-grade rings drawn on the same node. Tiers move to
  one warm ramp that avoids the loot-rarity palette the grade ring uses; pips
  1-4 as the non-colour fallback. A swatch sheet at node size goes to the owner
  before anything is committed.

**Colour swatch produced 2026-09-23 - awaiting owner pick.** Rendered at real
node size (1080p, 85%) with a goblin silhouette against the C / B / S grade
rings. It confirms the collision: in today's palette the green Normal creature
merges with a C ring and the blue Veteran with a B ring. Candidates (RGB 0-1):

| | Normal | Veteran | Brutal | Nemesis |
|---|---|---|---|---|
| A heat, crimson Nemesis | 0.93,0.89,0.80 | 0.98,0.62,0.22 | 0.92,0.27,0.24 | 0.80,0.16,0.45 |
| B heat, cold Nemesis | 0.93,0.89,0.80 | 0.98,0.62,0.22 | 0.92,0.27,0.24 | 0.25,0.85,0.90 |
| C heat, deeper steps | 0.96,0.93,0.86 | 0.99,0.72,0.30 | 0.95,0.40,0.16 | 0.72,0.10,0.20 |

Measurable notes for the pick: Veteran orange sits nearest the S (gold) ring in
all three, closest in C; C's Nemesis is the least separated from its Brutal.
The recolour is independent of Nemesis's pricing and can land before it.

**Pitfalls to design against.** A mispriced Nemesis is either trivial or
impossible, so pricing is only as good as the power metric across the WHOLE
fresh-to-god range. Crystal payouts must be sized against the locked
termination ladder and tree pricing (`BALANCE_PLAN.md`).

**Blocked on.** VD-04 (a truthful power metric), and a crystal-loadout injection
for the arena (`BALANCE_PLAN.md` Phase 0 `--meta=`; the existing `--xpbonus/
--slots/--events` cohort dials cover XP and team size only, not the combat tree).

**Done when.** A Nemesis node's measured win rate stays inside a stated band
(e.g. 40-70%) for fresh, mid and high-investment cohorts at waves 1-50, and its
payout is sized against the termination ladder.

---

## VD-14 - Map rows up to 5 wide - status: DONE

**Owner decision.**

> "i also kinda think we should add a 4th difficulty between normal and vet.
> and also thinking of changing the max row witdth to 5. so we can fit more
> events/rest/shop on our map."

> "im okay with making the nodes like 80-90% size so 5 can fit better. maybe we
> need to add a scroll or zoom feature too"

**Measured constraint (2026-09-23).** Lane spacing on the map screen is set by
the WIDEST row on the whole map, so one 5-wide row tightens every lane in the
biome. At today's node size the gap between node discs goes ~98px -> ~56px at
1080p and ~52px -> ~25px at 1366x768. Node size itself comes from horizontal
spacing and doesn't shrink on its own.

**Decided.** `MAX_WIDTH` 5. Until VD-13 adds a 4th tier a 5-wide row is three
fights plus two side nodes (then four fights plus one). Nodes drop to ~85% of
today's size. Scroll/zoom only if the 1366x768 render is still cramped after
that - checked, not assumed.

**Files.** `scripts/waves/run_map.gd`, `scripts/ui/run_map_screen.gd`. Lands
after VD-12 (same file).

**Done when.** 5-wide rows generate and pass `validate()` (including VD-12's
rules); 1080p and 1366x768 renders show no node, badge or pip collisions.

**Landed 2026-09-23.** `MAX_WIDTH` 5, `WIDTH_WEIGHTS` {2:22, 3:34, 4:26, 5:18};
a row owes `utilities_for_width` side nodes (4-wide: 1, 5-wide: 2, preferring
two different offers); `validate()` checks the owed count. Maps containing a
5-wide row draw nodes, badges included, at `NODE_SCALE_WIDE` 0.85; other maps
keep full size. Measured, `--mode=map`, 2000 maps:

| | before | after |
|---|---:|---:|
| side nodes per map | 4.06 (2.40 event, 0.66 camp, 1 shop) | **5.95** (3.40 event, 1.55 camp, 1 shop) |
| paths per map | 47.1 | 53.3 |
| no-Normal rows / nodes with no way down | 0 / 0 | 0 / 0 |
| violations | 0 | 0 |

**Zoom/scroll: not needed - checked, not assumed.** Seed 23 (three 5-wide rows)
rendered at 1920x1080 and 1366x768, at 100% and 85%: no collisions in any of
the four; 85% adds breathing room. `run_map_capture` gained `--size=WxH` and
prints the map's row widths, so a layout check can't pass by omission (the
first render tried, seed 12345, had no 5-wide row at all).

---

## VD-16 - Runs have no build identity - status: OPEN (Burn pieces accepted; tree synergy +1 decided)

**Owner framing (2026-09-25).**

> "we have rouguelite down pretty well. but not so much roguelike. some examples
> that come to mind is slay the spire u build ur deck so u create a custom
> loop/build. tft is items/team comp we now have both items i think decent but
> team comp/elements not at all."

> "how do we tackle this the right where a run feels like a certain path or
> build u went where u want to do that again or try a different path"

**Finding (read from code 2026-09-25).** Almost every in-run reward pays out
the same way - a bigger number for the whole team - so each choice screen has
one right answer and every run plays alike.

- About 145 relics, nearly all team-wide % or effects that work for any team,
  most as D-to-S ladders of one effect. Only 6 care which heroes you field, and
  they still give everyone a share ("+6% HP for all, Water +20%"). Level-up
  perks, round rewards and recruit rolls are also a stat with a grade.
- Both element systems push toward one hero of each element. Synergy
  thresholds are 2/3 and duplicates count; the tree's `synergy_<element>_1..3`
  nodes add +3 whenever you field one hero of that element, so **six heroes
  light every element at tier 2**. The Troll counters reward covering
  elements. Nothing pays for going deep.
- No early direction: the wave-1 relic is 80% D-grade.
- No way to hunt for pieces: the hero shop draws uniformly from the unlocked
  pool at a flat 10g, relics arrive on fixed waves, and the map sets
  difficulty, not direction. A run to wave 30 sees ~12 relic cards, so 4 Burn
  relics in a pool of ~150 would show up about once every three runs.
- Burn specifically: `apply_burn` keeps the stronger burn and the longer
  duration, so a second burner on the same enemy adds nothing, and burn damage
  is credited to whoever applied a burn last. The Coal -> Sear -> Ember combo
  (Coal's big burn, Sear's ult copies it to every enemy, Ember's ult detonates
  every burning enemy) already exists in the kits; nothing announces it.

**Owner decisions (2026-09-25).** Reply to the four proposals, verbatim:

> "i agree with 2 3 and 4 oh and 1 forsure too okay u got me all of them haha
> 1 sure?
> 2 maybe +3 for each element in crystal tree is too much idk
> 3 i worry its just more upgrades but yeah im okay with a good start to set
> the round direction
> 4 sure."

1. **DECIDED - hero verbs are the archetype layer; elements are the coverage
   axis.** Build pieces amplify verbs heroes already have. They never grant a
   verb to a whole element - the 2026-08-02 scrap stands. Elements keep
   affinity, stat synergy and the enemy counter passives (`ELEMENT_COUNTERS.md`).
2. **DECIDED later the same day (+1 per element - see "Item 2 decided"
   below) - element synergy must stop being free.** The owner suspects the
   tree's +3 per element is too much and has not picked a fix. Recommendation
   on file: the tree's count applies only to elements fielded 2+ times (options
   table in `BUILD_ARCHETYPES.md`). Deeper thresholds for 16-20 hero boards
   belong to a later synergy numbers pass.
3. **DECIDED - a wave-1 seed pick sets the run's direction.** The owner's
   concern ("just more upgrades") is recorded as two constraints: **no new
   reward screens** (seeds replace the wave-1 relic screen's contents; later
   build pieces take one of the existing three cards), and **the direction
   test** - a build piece must change which heroes or items you want next, or
   it is an upgrade and stays in the generic pool.
4. **DECIDED - Burn is the first slice.**

**Worksheet.** `BUILD_ARCHETYPES.md`: verb tags for all 26 heroes, how burn
works today, five Burn pieces (B1-B5) for review, seed and reserved-slot rules,
gates. Burn piece effects are moves - the owner keeps, changes or cuts each
before code.

**Owner review of B1-B5 (2026-09-25).**

> "okay i like these b4 i worry we create an infinite ult burn loop"

**DECIDED - B1-B5 accepted.** On the loop worry, measured from code: ult
charge comes only from a hero's own basic attacks (1/4 of damage), damage it
takes (1:1) and basic-attack kill refunds. Burn ticks never fill the burner's
bar and no ult refunds charge, so B4 alone is bounded (worst case a flat +25%
ult rate). The real runaway is **B2 + Sear's ult**: copying a stacked total
back in as a new burn ratchets it up every cast, and B3's leap has the same
shape. Closed by four rules in the worksheet's "Loop safety" section - per
hero-type burn entries, spreads/leaps copy single-hero burns never totals,
payoffs never create burn, total capped at 2x the strongest single burn - and a
180 s arena loop gate that must pass before the slice ships.

**Item 2 decided (2026-09-25).** Asked whether the recommendation meant
"we dont get bonus synergies unless we actually field them", the owner chose a
different fix:

> "yeah no i think the best route is still drop each element to +1 at most
> those +2 can go to other things like relics or events."

**DECIDED - the tree's element synergy bonus is +1 per element.** Keep
`synergy_<element>_1`; nodes `_2` and `_3` (12 in all, 1200 crystals each) are
freed for relic or event nodes - which ones is open. The tree change waits for
that answer so no purchasable node is ever left doing nothing. The tree is
generated (`tools/crystal_tree/gen_crystal_tree.py`), so the change goes
through the generator, not hand-edited JSON.

**Correction, same day.** The worksheet first said a Burn team speeds up
enemy ults. The owner pushed back - *"i feel like burn teams would have the
enmies ult bar go up more consistantly not more overall compared to other
comps"* - and is right: victims charge 1:1 from any damage taken, so burn
charges enemy ults exactly like hits per point of damage. Only damage *spread*
changes enemy ult timing, and that is true of any AoE comp.

**Blocked on.** What the 12 freed tree nodes become. Verb tags beyond Burn stay
proposals. Code touches `auto_battle_manager.gd` and `unit_base.gd`, which
carry another session's uncommitted gear-passive work (last edited 2026-09-25
04:16) - commit or coordinate before editing them.

**Done when.** The Burn slice ships - verb tags as data, a Burn seed at wave 1,
Burn pieces reachable through the existing screens, the build named in the
synergy pop and run recap - and the arena shows each Burn piece worth at least
2x more on a 3-burner team than on a 1-burner team, and better on-build than a
generic relic one grade higher.

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

**Map track (added 2026-09-23)** - independent of the balance chain above; its
files don't overlap it.
- **VD-12** a Normal fight in every row, and always a way down. *DONE 2026-09-23.*
- **VD-14** rows up to 5 wide, nodes ~85%. *DONE 2026-09-23.*
- **VD-13** the player-priced Nemesis tier. *After VD-04 and a crystal-loadout
  arena injection; re-spacing the three wave tiers belongs to VD-03.*

**Build identity track (added 2026-09-25)** - independent of the balance chain
and the map track.
- **VD-16** Burn slice. *After the owner's review of `BUILD_ARCHETYPES.md`.*
  Expected files: `relic.gd`, `relic_screen.gd`, `hero_shop.gd`,
  `synergy_tracker.gd`, and the burn functions in `auto_battle_manager.gd` -
  which had uncommitted edits from another session on 2026-09-25, so check
  `git status` before touching it.
