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
const STARTING_GOLD := 10          # + Progression.starting_gold_bonus()
const HERO_COST := 10              # hero shop recruit price
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
const BASE_TIME_SCALE := 0.9       # all sim speed derives from this; UI speed buttons multiply on top

# ── Run structure (which rounds do what) ──────────────────────────────────────
const VICTORY_ROUND := 30                              # clearing this round wins the run
const BOSS_ROUND_INTERVAL := 10                        # bosses at 10/20/30 (Khagan @10, Triarch @20/30)
const ELITE_ROUNDS: Array[int] = [5, 15, 25]           # elite mob rounds
const RELIC_WAVES: Array[int] = [1, 11, 21]            # forced pick-1-of-3 relic screens

# ── Elite mob knobs ───────────────────────────────────────────────────────────
const ANT_HILL_SPAWN_INTERVAL := 4.5   # seconds between ant spawns
const ANT_HILL_MAX_ANTS := 20          # alive-ant cap per hill
