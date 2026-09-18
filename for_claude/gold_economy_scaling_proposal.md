# SUPERSEDED 2026-08-07 — do not apply this proposal's diffs

The user redirected after reading this: coin/crystal drop chance must be
**fixed** (not round-scaled) with the only buff path being crystal-tree nodes
(Bounty/Crystal Surge), and `ROUND_WIN_GOLD` should carry most of a run's
income instead. That is the OPPOSITE of section 2 below (which proposed
tapering `COIN_CHANCE_CAP` — a round-scaled RNG chance — rather than removing
it). Applied instead: `COIN_CHANCE_PER_ROUND`/`COIN_CHANCE_CAP` deleted
entirely (chance is now always `COIN_CHANCE_BASE`), `ROUND_WIN_GOLD` 2 → 3,
relic base prices ~1.8x'd, `ShopGenerator.ROUND_PRICE_SCALE` 0.04 → 0.05. See
`Balance.gd` and [[gold_economy]] memory for what's actually live. `HERO_COST`
was NOT round-scaled per section 1 below — the user's later message didn't
revisit it, so it's still flat 10g; flag if that should change too.

The measurement method and numbers below are still accurate as a description
of the PRE-fix state — kept for reference, not as a to-do list.

---

# Gold economy: measured problem + proposed fix (research only, NOT applied)

Method mirrors the xpcurve fix: added `--mode=goldcurve` to
`scripts/arena/arena_main.gd` (`_run_goldcurve` + `_expected_gold_for_unit`),
battle-free, walks `WaveDirector.generate_wave_spec`/`create_enemy_for_entry`
for rounds 1-100 and sums **expected** gold income per round using the exact
formula in `WaveScaler.gold_drops_for_unit` (chance turned into an EV instead
of `randf()`, so runs are deterministic/repeatable). It also folds in
`ROUND_WIN_GOLD` and, optionally, the crystal-tree gold nodes (Head Start
levels, Bounty levels) as CLI args, so a fresh account and a maxed account can
be compared on the same axis.

Command used:
```
GODOT="../Godot_v4.5.1-stable_mono_win64_console.exe"
"$GODOT" --headless --fixed-fps 30 res://scenes/arena.tscn -- \
  --mode=goldcurve --to=100 --difficulty=normal --headstart=0 --bounty=0 --out=goldcurve_fresh.json --quit
"$GODOT" --headless --fixed-fps 30 res://scenes/arena.tscn -- \
  --mode=goldcurve --to=100 --difficulty=normal --headstart=10 --bounty=4 --out=goldcurve_maxed.json --quit
```

**Important caveat / undercount:** this EV excludes `relic_gold` (relic
`gold_per_round` bonuses), round-reward gold (`round_reward.gd`), and the
10%-of-gold-on-hand **interest** (`main_game.gd` ~line 1554, capped at 5/round
but compounds on whatever surplus is sitting idle). All three are additional
income the live game grants that this measurement does NOT include — so the
real in-game curve is *worse* (more surplus) than the numbers below.

## Measured: round income vs a flat HERO_COST=10

| Round | Fresh acct: round_gold | Maxed acct (Head Start 10 + Bounty 4): round_gold |
|---|---|---|
| 3   | 3.10 | 14.20 |
| 5   | 4.33 | 14.65 |
| 10  | 6.00 | 16.00 |
| 20  | 6.00 | 16.00 |
| 30  | 6.00 | 16.00 |
| 50  | 6.00 | 16.00 |
| 70  | 6.00 | 16.00 |
| 100 | 6.00 | 16.00 |

Cumulative over 100 rounds vs. cumulative cost of buying one hero every round
(unrealistic buying pattern, used purely as a fixed yardstick since HERO_COST
never changes):

| Account | final_cum_gold (100 rounds) | cum cost @ flat 10/round |
|---|---|---|
| Fresh (0 tree levels) | 733 | 1000 |
| Maxed (Head Start 10, Bounty 4) | 2198 | 1000 |

**The mechanism, confirmed by the flat lines above:** `COIN_CHANCE_BASE +
round*COIN_CHANCE_PER_ROUND` hits its `COIN_CHANCE_CAP=0.75` at round 22
(`(0.75-0.20)/0.025 = 22`) and **never moves again for the other 78 rounds of
the run**. Head Start (+1 gold/round/level, flat) and Bounty (+25%/level
chance, flat %) are likewise round-invariant once bought. So round-income is a
flat plateau from wave ~22 onward while `HERO_COST=10` is *also* a flat
plateau for the whole 100 rounds — nothing in the system ever separates them
again. A maxed-tree account is earning 16g/round net of a 10g hero (60%
surplus) at wave 30 AND at wave 100, identically — that flat 6g/round margin
just accumulates into the "so much gold" pile the user is seeing, and real
play adds interest/relic/reward income on top that this table excludes.

This also shows HERO_COST doesn't need owned-hero-count scaling nearly as
much as it needs *round* scaling — count scaling would hurt the early build
(2nd/3rd hero) same as round scaling would if misapplied at low rounds, so
either dial has to start near-zero before wave ~10 and ramp after.

## Proposed fix

One sentence: give `HERO_COST` the same round-scaling shape
`shop_generator._price()` already uses for the event shop, gentle enough to
protect the wave 3/5/10 recruit targets, and separately soften the LATE
income side by tapering `COIN_CHANCE_PER_ROUND` toward a lower cap instead of
holding at a flat 0.75 forever — both dials contribute to the same gap, and
fixing only one leaves the plateau-vs-plateau mismatch that caused this.

### 1. `HERO_COST` → round-scaled (new `Balance.hero_price(round)`)

Mirror `shop_generator._price()`'s multiplicative shape, but far gentler
since this shop is rolled every round (not every 4-6 rounds like the event
shop): `+1.2%/round` instead of event shop's `+4%/round`. At round 3-10 this
changes nothing measurable (10 → 10-11g, rounds to the same int), so the
"2nd hero ~wave 3, 3rd ~wave 5" target is untouched. By wave 50 it's 16g,
by wave 100 it's ~22g — back above the maxed-account's flat 16g/round income,
restoring a real buying decision instead of "always affordable."

```diff
--- a/scripts/core/balance.gd
+++ b/scripts/core/balance.gd
@@
 const HERO_COST := 10              # hero shop recruit price
+# Round-scaled hero price (2026-08-07, gold-economy pass): flat 10g forever
+# meant a fully-progressed account (Head Start+Bounty maxed, ~16g/round net
+# income after wave 22 per --mode=goldcurve) could always afford a hero for
+# free while gold plateaued in the bank. +1.2%/round is ~14x gentler than the
+# event shop's ROUND_PRICE_SCALE (0.04) because this shop rolls every round,
+# not every 4-6 — verified this does NOT move the int price before round ~8,
+# so the "2nd hero ~wave 3, 3rd ~wave 5" curve is untouched.
+const HERO_PRICE_ROUND_SCALE := 0.012
 const REROLL_COST := 2             # gold to refresh the hero shop offers (2026-07-17)
 const SELL_REFUND := 5             # gold back when selling/dismissing a hero
+
+static func hero_price(round: int) -> int:
+	return int(round(float(HERO_COST) * (1.0 + maxf(0.0, float(round) - 5.0) * HERO_PRICE_ROUND_SCALE)))
```

(The `maxf(round-5, 0)` start offset keeps rounds 1-5 exactly at 10 — the
window the "2nd hero ~wave 3" target lives in — instead of scaling from
round 1.)

`scripts/ui/hero_shop.gd` currently reads `const HERO_COST :=
Balance.HERO_COST` at const-init time; it would need the current round number
threaded in (main_game already knows it when opening the shop) and switched
to `Balance.hero_price(round)` at the 3 call sites (line 92 tooltip text,
wherever the actual charge happens, line 184 sub-label). Left un-diffed here
since it touches UI wiring, not just balance.gd — flag for the follow-up pass.

### 2. Taper `COIN_CHANCE` instead of holding a flat cap

The cap existing at all is deliberate (comment: "cap softens late-game
re-acceleration until the planned TFT-style team-size gate exists" — that
gate now exists, `MAX_TEAM_SIZE`/team-size-by-player-level, per the
XP-curve fix). Lower the cap moderately now that a real late-game structural
gate is in place elsewhere:

```diff
--- a/scripts/core/balance.gd
+++ b/scripts/core/balance.gd
@@
 const COIN_CHANCE_BASE := 0.20
 const COIN_CHANCE_PER_ROUND := 0.025
-const COIN_CHANCE_CAP := 0.75
+# 0.75 -> 0.55 (2026-08-07): the team-size/player-level gate (Balance.MAX_TEAM_SIZE,
+# see PLAYER_XP_GROWTH fix) is now the intended late-game structural brake, so
+# the coin-chance cap no longer needs to do that job alone. Still caps at
+# round 14 ((0.55-0.20)/0.025=14) instead of round 22, and the per-enemy EV
+# at cap drops ~27% (0.75->0.55), directly shrinking the round-22-to-100
+# plateau measured by --mode=goldcurve.
+const COIN_CHANCE_CAP := 0.55
```

### Do NOT touch (checked, not the problem)

- `BOSS_COIN_DROP`/`ELITE_COIN_DROP` — flat per-boss/elite bursts are a small
  fraction of total income (a handful of bosses/elites over 100 rounds vs.
  ~9 basic kills/round); not worth the complexity of scaling.
- `ROUND_WIN_GOLD=2` — tiny relative to the other terms, leave alone.
- Head Start / Bounty node *shapes* — leave the crystal-tree catalogue
  numbers as-is; they're a legitimate reward for investing in the tree. The
  round-scaled hero price is what should catch up to them, not the reverse.

## Re-measure after applying (follow-up pass)

Re-run both `--mode=goldcurve` commands above with the new constants, and add
a hero-cost column so the tables can be diffed directly:
```
"$GODOT" --headless --fixed-fps 30 res://scenes/arena.tscn -- \
  --mode=goldcurve --to=100 --difficulty=normal --headstart=10 --bounty=4 --out=goldcurve_maxed_v2.json --quit
```
Confirm: (a) rounds 1-10 `affordable_heroes_this_round` for a fresh account
is unchanged from this proposal's baseline, (b) the maxed-account
`surplus_vs_flat_cost` curve at round 100 is meaningfully smaller than the
+1198 measured here (target: single digits to low tens, not hundreds).
