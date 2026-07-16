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
# 2nd hero ~wave 3, 3rd ~wave 5, 4th-5th by wave 10 (Easy). Don't loosen it
# casually, and mark theorycrafted numbers for playtest confirmation.
# ══════════════════════════════════════════════════════════════════════════════

# ── Run economy (v3, 2026-07-03: coin-drop scale — see balance journal) ───────
# STARTING_GOLD removed 2026-07-10: Call to Arms (the crystal-shop tree's
# always-active root node) replaces it — every run now starts with 1 free
# recruited hero instead (see main_game.start_new_game()).
const HERO_COST := 10              # hero shop recruit price
const BENCH_BASE_SLOTS := 4        # sideboard capacity before Warm Bench upgrades (2026-07-10)
const ROUND_WIN_GOLD := 2          # flat coin burst on winning a round

# Physical coin drops on kill (gold_drops_for_unit in wave_scaler.gd):
# basic kills are a CHANCE at 1 coin that rises with the wave; elites/bosses
# drop a fixed handful; summons drop 0 (Ant Hill would be a gold printer).
const BOSS_COIN_DROP := 4
const ELITE_COIN_DROP := 2         # +1 from round 15 on (ELITE_COIN_LATE_BONUS_ROUND)
const ELITE_COIN_LATE_BONUS_ROUND := 15
# EV-modeled 2026-07-03 to hit the early curve above; cap softens late-game
# re-acceleration until the planned TFT-style team-size gate exists.
const COIN_CHANCE_BASE := 0.20
const COIN_CHANCE_PER_ROUND := 0.025
const COIN_CHANCE_CAP := 0.75

# ── Combat baselines ──────────────────────────────────────────────────────────
const CRIT_CHANCE_BASE := 0.0      # nothing grants crit chance yet (future gear/relics)
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

# ── Run structure (which rounds do what) ──────────────────────────────────────
const VICTORY_ROUND := 30                              # clearing this round wins the run
const BOSS_ROUND_INTERVAL := 10                        # bosses at 10/20/30 (Khagan @10, Triarch @20, Hydra @30)
const ELITE_ROUNDS: Array[int] = [5, 15, 25]           # elite mob rounds
const RELIC_WAVES: Array[int] = [1, 11, 21]            # forced pick-1-of-3 relic screens

# ── Elite mob knobs ───────────────────────────────────────────────────────────
# ── Elemental affinity rework (2026-07-16, user spec) ─────────────────────────
# Every unit (ally, enemy, any element incl. Normal) gets these deltas applied
# on top of its class-base affinity RATINGS (100 = neutral):
const AFFINITY_OWN_OFF_BONUS       := 50.0   # own element: hit that element harder
const AFFINITY_OWN_DEF_BONUS       := 25.0   # own element: block that element better
const AFFINITY_OFFELEM_DEF_PENALTY := 15.0   # every other element: defended worse

const ANT_HILL_SPAWN_INTERVAL := 1.0   # seconds between ant spawns (3.5 → 1.0
	# in the 2026-07-15 elite rebalance: at 3.5s the swarm never outpaced a
	# round-15 team's kill rate — every ant died on arrival, all 7 heroes
	# finished at 100% HP — so the DPS check was toothless)
const ANT_HILL_MAX_ANTS := 20          # alive-ant cap per hill
