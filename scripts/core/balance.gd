extends Object
class_name Balance
# ══════════════════════════════════════════════════════════════════════════════
# CENTRAL BALANCE FILE (2026-07-04, user request) — the game's cross-file
# tuning knobs live HERE, so a balance pass touches one file instead of
# hunting through main_game / hero_shop / wave_scaler / auto_battle_manager.
#
# What belongs here: run-economy scalars, spawn cadence, combat baselines —
# any single number a playtest might move.
# What does NOT belong here: per-class stat/growth tables (unit_factory.gd),
# per-enemy stats (enemy_factory.gd), relic/equipment pools — those are data
# tables with their own registration points (see CONVENTIONS.md section 3).
#
# Balance philosophy is in CONVENTIONS.md section 5 + the balance journal
# (memory). Economy is deliberately stingy post-2026-07-02: target curve =
# 2nd hero ~wave 3, 3rd ~wave 5, 4th-5th by wave 10 (Normal). Don't loosen it
# casually, and mark theorycrafted numbers for playtest confirmation.
# ══════════════════════════════════════════════════════════════════════════════

# ── Run economy (v3, 2026-07-03: coin-drop scale — see balance journal) ───────
# STARTING_GOLD removed 2026-07-10: Call to Arms (the crystal-shop tree's
# always-active root node) replaces it — every run now starts with 1 free
# recruited hero instead (see main_game.start_new_game()).
# ── Team size / player level (2026-08-07 user spec, REPLACES the 2026-08-07
# "cap 10 + Ascension" pass which mis-read the spec) ──────────────────────────
# The model, in the user's words: "no crystal tree max player level and team
# size 8 ... with all player exp nodes and +1 size nodes most runs will be
# 16-18; if you get lucky with events you can get to team size of 20."
#
# So team size = player level + hero_slots nodes + event bonuses, and 20 is a
# HARD CLAMP that only a lucky run touches. Crucially, player level is gated by
# the XP CURVE, not by a level-cap constant — a fresh account simply cannot earn
# past ~8 in a full run. That is why there is no PLAYER_LEVEL_CAP upgrade node:
# the crystal tree buys XP RATE (bonus_xp) and SLOTS (hero_slots), never a
# ceiling. Fit any change to these with `--mode=xpcurve` (see arena_main.gd).
# HARD clamp on fielded heroes. Player LEVEL is deliberately uncapped (it keeps
# climbing past 20 on a monster run); this clamps the BOARD only, and it applies
# after slot nodes AND event bonuses are added, so nothing can smuggle a 21st
# hero in. See main_game._recompute_max_player_units and GameState.add_player_xp.
const MAX_TEAM_SIZE := 20
const TEAM_SIZE_BASE := 1          # team size at player level 1 (field cap IS your level)
# Player-XP pool: share of each kill's hero XP that feeds the account level,
# and the per-level cost curve. GROWTH was 3.2 (geometric) — so steep that the
# whole ladder above ~level 8 was unreachable and XP nodes/difficulty barely
# moved it. Retuned so the tiers above are actually hit; verified by xpcurve.
const PLAYER_XP_SHARE := 0.5
# 300 -> 180 (2026-09-22): the second hero was not landing reliably before the
# Hill Giant at wave 5. The full-clear curve was never the problem — it reaches
# level 2 at wave 4 on Normal. The MAP is: MAX_UTILITY_NODES_PER_BIOME is 4, the
# elite is protected but waves 1-4 are not, so a player can reach wave 5 having
# fought as few as one battle. At 300, a Normal player who skipped any single
# fight in 1-4 arrived with 190-255 XP and stayed level 1.
# Cumulative Normal player XP is 25 / 80 / 190 / 335 across waves 1-4, so the
# binding path is "fought 1,2,3, skipped 4" = 190. 180 clears it with slack;
# 190 exactly would be brittle now that VD-06/VD-11 shift wave composition.
const PLAYER_XP_BASE := 180.0
# 3.2 -> 1.9, FITTED (not guessed) with --mode=xpcurve over real wave specs,
# full clears, 100 waves. Measured landing spots, TEAM SIZE:
#   fresh account, no tree   Normal 8 / Veteran 8 / Brutal 9   <- spec: "team size 8"
#   full tree (+500% xp, +6 slots), Normal          17         <- spec: "most runs 16-18"
#   ... plus 3 event pickups                        20         <- spec: "lucky -> 20"
# At the old 3.2 a full baseline run reached level SIX, and +500% XP bought
# under two levels — the ladder above ~8 was mathematically unreachable, which
# is the actual reason team size never behaved like the spec.
# NOTE: 2.0 was fitted first and looked right, but that fit was read off the
# tier then called "normal" — which the 2026-08-07 rename turned into VETERAN.
# Re-fitted against the true baseline tier; check which tier a target refers to
# before trusting any pre-rename measurement.
# 1.9 -> 2.0 (2026-09-22), REQUIRED by the base cut above, not a free choice.
# Lowering base alone gives a fresh account team 9/9/10 at wave 100 against a
# spec of 8. Re-fitted with --mode=xpcurve to 100 waves; 180/2.0 reproduces
# EVERY landing spot the 1.9 fit was chosen for, exactly:
#   fresh, no tree            Normal 8 / Veteran 9 / Brutal 9
#   full tree (+500%, +6)     Normal 17
#   ... plus 3 event pickups  Normal 20
# Read off tier 0 (the true baseline). The note above about 2.0 being rejected
# refers to a fit taken from the tier that the 2026-08-07 rename turned into
# VETERAN; this one is not that measurement.
const PLAYER_XP_GROWTH := 2.0

const HERO_COST := 10              # hero shop recruit price
const REROLL_COST := 2             # gold to refresh the hero shop offers (2026-07-17)
const SELL_REFUND := 5             # gold back when selling/dismissing a hero
const BENCH_BASE_SLOTS := 4        # sideboard capacity before Warm Bench upgrades (2026-07-10)
# 2 -> 3 (2026-08-07 user spec: "round gold should be the main income for most
# waves"). With COIN_CHANCE no longer ramping (see below), kill-gold plateaus
# around ~1g/round by wave 8+ (measured via --mode=goldcurve) — 3 keeps
# ROUND_WIN_GOLD the clear majority of every round's income at every wave,
# not just late ones, without needing a scaling curve of its own. The ONLY way
# to raise it further is the Head Start crystal-tree node (+1/round/level,
# additive at payout — see main_game.gd ~line 1558), matching the "buffed only
# via crystal tree" rule below.
const ROUND_WIN_GOLD := 3

# Physical coin drops on kill (gold_drops_for_unit in wave_scaler.gd):
# basic kills are a FIXED chance, same at wave 1 and wave 100 — NOT a ramp.
# 2026-08-07 user spec: "coin and crystal drops should both be fixed and if
# ever buffed it's done as an upgrade in the crystal tree." Crystals already
# worked this way (crystals_for_unit is score-threshold gated, never round-
# scaled); gold's COIN_CHANCE_PER_ROUND ramp (0.20 -> 0.75 by round 22, then
# flat for the remaining 78 rounds) was the one exception, and the plateau
# it created — chance capped identically at wave 30 and wave 100 while
# nothing else ever re-tightened — was the actual "so much gold" mechanism
# (measured: a maxed account nets +1198 surplus over 100 rounds vs a flat
# hero-cost yardstick). The ramp/cap constants are gone; the ONLY way to
# raise this chance now is the Bounty crystal-tree node (+25%/level, applied
# as an independent bonus chance in main_game.gd — untouched, already
# tree-gated correctly).
const BOSS_COIN_DROP := 4
const ELITE_COIN_DROP := 2         # +1 from round 15 on (ELITE_COIN_LATE_BONUS_ROUND)
const ELITE_COIN_LATE_BONUS_ROUND := 15
const COIN_CHANCE_BASE := 0.20

# ── Combat baselines ──────────────────────────────────────────────────────────
const CRIT_CHANCE_BASE := 0.10     # everyone (heroes AND enemies) crits 10% of hits by default (2026-07-24)
const CRIT_DAMAGE_BASE := 2.0      # crit = double damage
const BASE_TIME_SCALE := 0.8       # all sim speed derives from this; UI speed buttons multiply on top

# ── Late-game enemy scaling (2026-07-12, waves 11-30 pass) ────────────────────
# Flat per-level growth alone can't make act 2/3 threatening: mobs share the
# small hero-class growth tables (+25 hp/level on a 4800-hp Hydra is noise), so
# past round 10 every enemy also gets a linear stat multiplier, applied at the
# single spawn choke point (WaveDirector.create_enemy_for_entry — shared by the
# live game AND the arena, so sims always see it). Calibrated by arena sims to
# the run targets: wave 10 first-try clearable with no crystal upgrades, wave 20
# a stars-align no-upgrade clear, wave 30 impossible without upgrades.
# Round 20 → HP ×2.0 / DMG ×1.7;  round 30 → HP ×3.0 / DMG ×2.4.
const ENEMY_LATE_SCALE_START_ROUND := 10   # rounds AFTER this get the multiplier
const ENEMY_LATE_HP_PER_ROUND := 0.10
# DMG slope deliberately hotter relative to its starting point than a pure
# HP-wall approach: sustain comps (heals/shields/revives) simply outlast big
# HP pools, so late-game pressure has to come from enemy damage output.
const ENEMY_LATE_DMG_PER_ROUND := 0.07

static func enemy_late_hp_mult(round: int) -> float:
	return 1.0 + maxi(round - ENEMY_LATE_SCALE_START_ROUND, 0) * ENEMY_LATE_HP_PER_ROUND

static func enemy_late_dmg_mult(round: int) -> float:
	return 1.0 + maxi(round - ENEMY_LATE_SCALE_START_ROUND, 0) * ENEMY_LATE_DMG_PER_ROUND

# ── Battle enrage (anti-stall, 2026-07-24) ───────────────────────────────────
# A battle only ends when one side is wiped (AutoBattleManager.check_battle_end)
# — there is no timer — so a fight where neither side can finish the other runs
# forever and softlocks the run. That became reachable once waves extended past
# 30: at round 40+ enemy HP pools carry a ×4-10 late-game multiplier, while some
# heroes have ZERO attack growth per level (e.g. Sheildor's atk stays at its
# base 14 — see UnitFactory.CLASS_GROWTH_PER_LEVEL). Armor is a diminishing-
# returns curve, not a flat subtraction, so such a unit still lands ~9 damage a
# hit — it just needs ~40 real-world MINUTES to chew through a 28k-HP giant.
# Reproduced in the arena: a round-42 run left Sheildor alive at 100% HP with 3
# enemies up and no resolution after 250 simulated seconds.
# Fix: after ENRAGE_START seconds, ALL damage on BOTH sides is multiplied by a
# figure that doubles every ENRAGE_DOUBLE_EVERY seconds. Because both sides
# scale identically it never changes WHO wins — it only forces the fight to
# actually finish. Normal fights resolve in 20-40s and never see it.
const BATTLE_ENRAGE_START := 60.0          # seconds of battle before enrage starts
const BATTLE_ENRAGE_DOUBLE_EVERY := 15.0   # damage multiplier doubles this often
const BATTLE_ENRAGE_MAX := 1024.0          # hard cap (keeps the float sane)

# ── Run structure (which rounds do what) ──────────────────────────────────────
# VICTORY_ROUND 30 → 100 (2026-07-24): the run used to END at wave 30, which
# made every wave authored past it unreachable in the live game. See
# WaveData.get_wave for the 1-100 decade structure.
const VICTORY_ROUND := 100                             # clearing this round wins the run
const BOSS_ROUND_INTERVAL := 10                        # bosses every 10 rounds (10/20/…/100)
const ELITE_ROUND_INTERVAL := 10                       # elites every 10 rounds…
const ELITE_ROUND_OFFSET := 5                          # …offset by 5 → 5/15/25/…/95
const RELIC_WAVES: Array[int] = [1, 11, 21, 31, 41, 51, 61, 71, 81, 91]  # forced pick-1-of-3 relic screens

# Elite rounds are now derived rather than a hardcoded [5,15,25] literal — that
# list silently stopped producing elites past round 25, so rounds 35/45/… fell
# through to procedural random waves instead. Built once at load.
const ELITE_ROUNDS: Array[int] = [
	5, 15, 25, 35, 45, 55, 65, 75, 85, 95,
]

# ── Elite mob knobs ───────────────────────────────────────────────────────────
# ── Elemental affinity rework (2026-07-16, user spec) ─────────────────────────
# Every unit (ally, enemy, any element incl. Normal) gets these deltas applied
# on top of its class-base affinity RATINGS (100 = neutral):
const AFFINITY_OWN_OFF_BONUS       := 50.0   # own element: hit that element harder
const AFFINITY_OWN_DEF_BONUS       := 25.0   # own element: block that element better
const AFFINITY_OFFELEM_DEF_PENALTY := 15.0   # every other element: defended worse

const ANT_HILL_SPAWN_INTERVAL := 1.5   # seconds between ant spawns (3.5 → 1.0
	# in the 2026-07-15 elite rebalance: at 3.5s the swarm never outpaced a
	# round-15 team's kill rate — every ant died on arrival, all 7 heroes
	# finished at 100% HP — so the DPS check was toothless)
const ANT_HILL_MAX_ANTS := 20          # alive-ant cap per hill
