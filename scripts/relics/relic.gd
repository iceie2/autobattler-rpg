extends RefCounted
class_name Relic

# Run-wide passive picks offered via gacha every 10 waves (1, 11, … 91). Grades D–S
# (no F): even a D relic should feel like *something*, unlike an F stat roll.
# Each relic has a FIXED grade — the gacha rolls a grade per offer slot (odds
# skew toward higher grades on later waves), then draws a random relic OF that
# grade, so later picks surface inherently stronger effects.

# ── Gacha grade odds per relic-wave (each row sums to 100) ────────────────────
# Keyed by the wave the pick happens on. Each of the 3 offer slots rolls its
# grade independently off this table.
#
# The ladder is stretched across the full 1–100 run: S-grade relics are a
# late-run payoff (a trickle from 41, meaningful only from 71 up), so an early
# screen can never hand out a run-defining effect the way 1/11/21 used to.
const WAVE_ODDS := {
	1:  {"D": 80, "C": 15, "B": 4,  "A": 1,  "S": 0},
	11: {"D": 45, "C": 40, "B": 13, "A": 2,  "S": 0},
	21: {"D": 20, "C": 45, "B": 28, "A": 7,  "S": 0},
	31: {"D": 8,  "C": 35, "B": 42, "A": 15, "S": 0},
	41: {"D": 2,  "C": 22, "B": 50, "A": 25, "S": 1},
	51: {"D": 0,  "C": 12, "B": 48, "A": 36, "S": 4},
	61: {"D": 0,  "C": 5,  "B": 40, "A": 45, "S": 10},
	71: {"D": 0,  "C": 0,  "B": 30, "A": 52, "S": 18},
	81: {"D": 0,  "C": 0,  "B": 18, "A": 54, "S": 28},
	91: {"D": 0,  "C": 0,  "B": 8,  "A": 52, "S": 40},
}

# Waves that trigger a relic pick — tune in balance.gd.
const RELIC_WAVES: Array[int] = Balance.RELIC_WAVES

# Weakest → strongest (used for the odds walk and for exhausted-tier fallback).
const GRADE_ORDER: Array[String] = ["D", "C", "B", "A", "S"]

# Reuse the shared gacha palette (grey→green→blue→purple→gold) so relic grades
# read the same as recruit-roll and level-up-perk grades.
static func grade_color(grade: String) -> Color:
	return UnitFactory.GRADE_COLORS.get(grade, Color(0.86, 0.86, 1.0))

# Icon file per relic (named by id, see assets/icons/Relics/<id>.png). Returns ""
# if the art isn't present so callers can fall back to a text chip.
const ICON_DIR := "res://assets/icons/Relics/"
static func icon_path(relic: Dictionary) -> String:
	var p: String = ICON_DIR + str(relic.get("id", "")) + ".png"
	return p if ResourceLoader.exists(p) else ""

# ── Relic pool ────────────────────────────────────────────────────────────────
# Each entry: id, name, grade, desc, effects[ {type, ...}, ... ] (a relic may
# stack several sub-effects, e.g. Glass Cannon = more damage + more damage taken).
#
# Per-unit effect types (applied to each hero, once, by RelicInventory):
#   stat_mult       {stat, value}          — multiply one stat
#   stat_mult_multi {stats:[...], value}   — multiply several stats
#   stat_add        {stat, value}          — add flat to one stat
#   element_mult    {stat, element, base, matched}
#                                          — multiply `stat` by `base` for all,
#                                            by `matched` if the unit's element ==
#                                            `element` (element is a UnitBase.Element)
#   lifesteal    {value}   — heal `value` fraction of damage dealt
#   outgoing     {value}   — multiply all outgoing damage
#   dmg_taken    {value}   — multiply all incoming damage
#   vs_boss      {value}   — extra outgoing multiplier vs boss enemies
#   ult_charge   {value}   — multiply ultimate charge rate
#   double_atk   {value}   — chance (0–1) to strike twice per attack
#   start_shield {value}   — battle-start shield = `value` fraction of max HP
#   regen_pct    {value}   — regenerate `value` fraction of max HP per second
#   free_ult     {}        — start each battle with the ultimate charged
#   revive       {value}   — cheat death once per battle, revive at `value` HP frac
#   on_kill_atk  {value}   — each kill permanently grants +`value` frac attack dmg
#   execute_pct  {hp_threshold_pct, dmg_bonus_pct}
#                                          — bonus outgoing dmg while target HP% is
#                                            at/below hp_threshold_pct
#   first_strike_crit {first_strike_crit_mult}
#                                          — the first attack each fight is a
#                                            guaranteed crit, dealing
#                                            first_strike_crit_mult (default
#                                            2.0) x damage instead of the
#                                            normal crit_damage multiplier
#   row_stat_mult {front_mult, back_mult} — outgoing dmg mult, front row vs back row
#   battle_start_dmg_window {dmg_bonus_pct, seconds}
#                                          — bonus outgoing dmg for the first
#                                            `seconds` of each fight, then reverts
#   ult_refund_kill {value} — killing blow refunds `value` frac of max ult charge
#   gold_scaling_dmg {value} — bonus outgoing dmg mult per gold currently held
#   momentum     {pct_per_sec} — attack speed ramps by this frac per second survived
#                                 in a fight (resets each fight, caps at +100%)
#   underdog     {dmg_per_dead, res_per_dead}
#                                          — bonus outgoing dmg / incoming dmg
#                                            reduction per dead ally this fight
# Run-economy / meta effect types (scanned on the inventory, not per-unit):
#   gold_round   {value}   — +gold granted each round
#   shop_slots   {value}   — +N extra hero cards in the shop
#
# ── Metadata fields (2026-08-05) ────────────────────────────────────────────
#   category      "stat_ladder" | "mechanic" | "element" | "combo"
#   ladder        one of the 14 stat-ladder keys (only on category
#                 "stat_ladder" relics): atk_dmg, max_hp, magic_power,
#                 attack_speed, crit_chance, crit_damage, armor_dual,
#                 lifesteal, gold_econ, vs_boss, double_atk, on_kill_atk,
#                 start_shield, ult_charge
#   ladder_gated  true only on the 33-relic ladder-fill pass; those relics are
#                 gated EXCLUSIVELY by Progression.is_ladder_unlocked(ladder),
#                 ignoring any per-id relic_unlock_* gate. Older ladder rungs
#                 (no ladder_gated) stay free/ungated as they always were —
#                 see Relic._draw_one.
const POOL: Array[Dictionary] = [
	# ── D — small, reliable nudges ──
	{"id": "d_hp",    "name": "Worn Talisman",  "grade": "D", "desc": "+12% team max HP",       "category": "stat_ladder", "ladder": "max_hp", "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.12}]},
	{"id": "d_atk",   "name": "Chipped Fang",   "grade": "D", "desc": "+10% team attack damage","category": "stat_ladder", "ladder": "atk_dmg", "effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.10}]},
	{"id": "d_mag",   "name": "Cracked Orb",    "grade": "D", "desc": "+12% team magic power",  "category": "stat_ladder", "ladder": "magic_power", "effects": [{"type": "stat_mult", "stat": "magic_power", "value": 1.12}]},
	{"id": "d_gold",  "name": "Cracked Coin",   "grade": "D", "desc": "+1 gold each round",     "category": "stat_ladder", "ladder": "gold_econ", "effects": [{"type": "gold_round", "value": 1}]},
	{"id": "d_aspd",  "name": "Quickstep Charm","grade": "D", "desc": "+10% team attack speed", "category": "stat_ladder", "ladder": "attack_speed", "effects": [{"type": "stat_mult", "stat": "attack_speed", "value": 1.10}]},
	{"id": "d_crit",  "name": "Jagged Shard",   "grade": "D", "desc": "+8% team crit chance",   "category": "stat_ladder", "ladder": "crit_chance", "effects": [{"type": "stat_add", "stat": "crit_chance", "value": 0.08}]},
	{"id": "d_res",   "name": "Dented Plate",   "grade": "D", "desc": "+25% armor and magic armor", "category": "stat_ladder", "ladder": "armor_dual", "effects": [{"type": "stat_mult_multi", "stats": ["resistance", "magic_resist"], "value": 1.25}]},
	{"id": "d_mana",  "name": "Chipped Focus",  "grade": "D", "desc": "+30% mana regeneration", "category": "combo", "effects": [{"type": "stat_mult", "stat": "mana_regen", "value": 1.30}]},
	{"id": "d_regen", "name": "Mossy Idol",     "grade": "D", "desc": "+2 HP regenerated per second", "category": "combo", "effects": [{"type": "stat_add", "stat": "hp_regen", "value": 2.0}]},
	{"id": "d_shield","name": "Scarred Buckler","grade": "D", "desc": "Team starts each fight with a shield worth 6% of max HP", "category": "stat_ladder", "ladder": "start_shield", "effects": [{"type": "start_shield", "value": 0.06}]},
	{"id": "d_ult",   "name": "Cracked Sigil",  "grade": "D", "desc": "Ultimates charge 10% faster", "category": "stat_ladder", "ladder": "ult_charge", "effects": [{"type": "ult_charge", "value": 1.10}]},

	# ── C — solid ──
	{"id": "c_hp",    "name": "Iron Charm",     "grade": "C", "desc": "+20% team max HP",        "category": "stat_ladder", "ladder": "max_hp", "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.20}]},
	{"id": "c_atk",   "name": "Warblade",       "grade": "C", "desc": "+18% team attack damage", "category": "stat_ladder", "ladder": "atk_dmg", "effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.18}]},
	{"id": "c_std",   "name": "Battle Standard","grade": "C", "desc": "+12% attack damage and +12% max HP", "category": "combo", "effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.12}, {"type": "stat_mult", "stat": "max_hp", "value": 1.12}]},
	{"id": "c_ledger","name": "Merchant's Ledger","grade": "C", "desc": "+2 gold each round, and the shop shows 4 heroes", "category": "stat_ladder", "ladder": "gold_econ", "effects": [{"type": "gold_round", "value": 2}, {"type": "shop_slots", "value": 1}]},
	{"id": "c_tide",  "name": "Tidal Charm",    "grade": "C", "desc": "+6% max HP for all; Water units get +20% instead", "category": "element", "effects": [{"type": "element_mult", "stat": "max_hp", "element": UnitBase.Element.WATER, "base": 1.06, "matched": 1.20}]},
	{"id": "c_mag",   "name": "Scholar's Codex","grade": "C", "desc": "+20% team magic power", "category": "stat_ladder", "ladder": "magic_power", "effects": [{"type": "stat_mult", "stat": "magic_power", "value": 1.20}]},
	{"id": "c_crit",  "name": "Hunter's Eye",   "grade": "C", "desc": "+10% crit chance and +15% crit damage", "category": "combo", "effects": [{"type": "stat_add", "stat": "crit_chance", "value": 0.10}, {"type": "stat_add", "stat": "crit_damage", "value": 0.15}]},
	{"id": "c_vamp",  "name": "Bloodthorn",     "grade": "C", "desc": "Team heals 7% of the damage it deals", "category": "stat_ladder", "ladder": "lifesteal", "effects": [{"type": "lifesteal", "value": 0.07}]},
	{"id": "c_ward",  "name": "Warding Candle", "grade": "C", "desc": "+45% armor and magic armor", "category": "stat_ladder", "ladder": "armor_dual", "effects": [{"type": "stat_mult_multi", "stats": ["resistance", "magic_resist"], "value": 1.45}]},
	{"id": "c_gale",  "name": "Gale Feather",   "grade": "C", "desc": "+6% attack speed for all; Air units get +22% instead", "category": "element", "effects": [{"type": "element_mult", "stat": "attack_speed", "element": UnitBase.Element.AIR, "base": 1.06, "matched": 1.22}]},
	{"id": "c_stone", "name": "Stonebound Idol","grade": "C", "desc": "+8% max HP for all; Earth units get +25% instead", "category": "element", "effects": [{"type": "element_mult", "stat": "max_hp", "element": UnitBase.Element.EARTH, "base": 1.08, "matched": 1.25}]},

	# ── B — build-shaping ──
	{"id": "b_atk",   "name": "Warlord's Edge", "grade": "B", "desc": "+30% team attack damage", "category": "stat_ladder", "ladder": "atk_dmg", "effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.30}]},
	{"id": "b_vamp",  "name": "Vampiric Sigil", "grade": "B", "desc": "Team heals 12% of the damage it deals", "category": "stat_ladder", "ladder": "lifesteal", "effects": [{"type": "lifesteal", "value": 0.12}]},
	{"id": "b_shield","name": "Bulwark Crest",  "grade": "B", "desc": "Team starts each fight with a shield worth 15% of max HP", "category": "stat_ladder", "ladder": "start_shield", "effects": [{"type": "start_shield", "value": 0.15}]},
	{"id": "b_ult",   "name": "Overcharged Core","grade": "B", "desc": "Ultimates charge 25% faster", "category": "stat_ladder", "ladder": "ult_charge", "effects": [{"type": "ult_charge", "value": 1.25}]},
	{"id": "b_ember", "name": "Emberheart",     "grade": "B", "desc": "+8% damage for all; Fire units get +25% instead", "category": "element", "effects": [{"type": "element_mult", "stat": "attack_damage", "element": UnitBase.Element.FIRE, "base": 1.08, "matched": 1.25}]},
	{"id": "b_hp",    "name": "Aegis Heart",    "grade": "B", "desc": "+35% team max HP", "category": "stat_ladder", "ladder": "max_hp", "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.35}]},
	{"id": "b_mag",   "name": "Archon Prism",   "grade": "B", "desc": "+32% team magic power", "category": "stat_ladder", "ladder": "magic_power", "effects": [{"type": "stat_mult", "stat": "magic_power", "value": 1.32}]},
	{"id": "b_crit",  "name": "Widowmaker",     "grade": "B", "desc": "+15% crit chance and +40% crit damage", "category": "combo", "effects": [{"type": "stat_add", "stat": "crit_chance", "value": 0.15}, {"type": "stat_add", "stat": "crit_damage", "value": 0.40}]},
	{"id": "b_stand", "name": "Stalwart Banner","grade": "B", "desc": "+18% max HP and +60% armor and magic armor", "category": "combo", "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.18}, {"type": "stat_mult_multi", "stats": ["resistance", "magic_resist"], "value": 1.60}]},
	{"id": "b_hoard", "name": "Dragon's Hoard", "grade": "B", "desc": "+4 gold each round, and the shop shows 4 heroes", "category": "stat_ladder", "ladder": "gold_econ", "effects": [{"type": "gold_round", "value": 4}, {"type": "shop_slots", "value": 1}]},
	{"id": "b_frenzy","name": "Berserker's Chain","grade": "B", "desc": "+25% attack speed but the team takes +10% damage", "category": "combo", "effects": [{"type": "stat_mult", "stat": "attack_speed", "value": 1.25}, {"type": "dmg_taken", "value": 1.10}]},

	# ── A — powerful / conditional ──
	{"id": "a_glass", "name": "Glass Cannon",   "grade": "A", "desc": "Team deals +35% damage but takes +20% damage", "category": "combo", "effects": [{"type": "outgoing", "value": 1.35}, {"type": "dmg_taken", "value": 1.20}]},
	{"id": "a_titan", "name": "Titan's Heart",  "grade": "A", "desc": "+45% max HP and regenerate 3% max HP per second", "category": "combo", "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.45}, {"type": "regen_pct", "value": 0.03}]},
	{"id": "a_exec",  "name": "Executioner",    "grade": "A", "desc": "+30% damage dealt to bosses", "category": "stat_ladder", "ladder": "vs_boss", "effects": [{"type": "vs_boss", "value": 1.30}]},
	{"id": "a_twin",  "name": "Twin Fang",      "grade": "A", "desc": "20% chance for each attack to strike twice", "category": "stat_ladder", "ladder": "double_atk", "ladder_gated": true, "effects": [{"type": "double_atk", "value": 0.20}]},
	{"id": "a_storm", "name": "Stormcore",      "grade": "A", "desc": "+10% attack speed for all; Lightning units get +30% instead", "category": "element", "effects": [{"type": "element_mult", "stat": "attack_speed", "element": UnitBase.Element.LIGHTNING, "base": 1.10, "matched": 1.30}]},
	{"id": "a_vamp",  "name": "Sanguine Crown", "grade": "A", "desc": "Team heals 25% of the damage it deals", "category": "stat_ladder", "ladder": "lifesteal", "effects": [{"type": "lifesteal", "value": 0.25}]},
	{"id": "a_bast",  "name": "Adamant Bastion","grade": "A", "desc": "+70% armor and magic armor, and a battle-start shield worth 20% of max HP", "category": "combo", "effects": [{"type": "stat_mult_multi", "stats": ["resistance", "magic_resist"], "value": 1.70}, {"type": "start_shield", "value": 0.20}]},
	{"id": "a_crit",  "name": "Kingslayer",     "grade": "A", "desc": "+20% crit chance and +80% crit damage", "category": "combo", "effects": [{"type": "stat_add", "stat": "crit_chance", "value": 0.20}, {"type": "stat_add", "stat": "crit_damage", "value": 0.80}]},
	{"id": "a_siege", "name": "Siege Engine",   "grade": "A", "desc": "+28% attack damage and +28% magic power", "category": "combo", "effects": [{"type": "stat_mult_multi", "stats": ["attack_damage", "magic_power"], "value": 1.28}]},
	{"id": "a_reap",  "name": "Reaper's Tally", "grade": "A", "desc": "Each kill permanently grants that hero +1% attack damage (stacks all run)", "category": "stat_ladder", "ladder": "on_kill_atk", "effects": [{"type": "on_kill_atk", "value": 0.01}]},
	{"id": "a_deep",  "name": "Deepfreeze Sigil","grade": "A", "desc": "+8% magic power for all; Water units get +30% instead", "category": "element", "effects": [{"type": "element_mult", "stat": "magic_power", "element": UnitBase.Element.WATER, "base": 1.08, "matched": 1.30}]},

	# ── S — run-defining ──
	{"id": "s_god",   "name": "Godshard",       "grade": "S", "desc": "+30% attack damage, magic power, and max HP", "category": "combo", "effects": [{"type": "stat_mult_multi", "stats": ["attack_damage", "magic_power", "max_hp"], "value": 1.30}]},
	{"id": "s_chrono","name": "Chrono Core",    "grade": "S", "desc": "+40% team attack speed", "category": "stat_ladder", "ladder": "attack_speed", "effects": [{"type": "stat_mult", "stat": "attack_speed", "value": 1.40}]},
	{"id": "s_over",  "name": "Overclocked",    "grade": "S", "desc": "Every hero starts each fight with their ultimate fully charged", "category": "combo", "effects": [{"type": "free_ult"}]},
	{"id": "s_soul",  "name": "Soul Harvest",   "grade": "S", "desc": "Each kill permanently grants that hero +2% attack damage (stacks all run)", "category": "stat_ladder", "ladder": "on_kill_atk", "effects": [{"type": "on_kill_atk", "value": 0.02}]},
	{"id": "s_phoenix","name": "Phoenix Pact",  "grade": "S", "desc": "Each hero cheats death once per fight, reviving at 40% HP", "category": "combo", "effects": [{"type": "revive", "value": 0.40}]},
	{"id": "s_avatar","name": "Avatar Engine",  "grade": "S", "desc": "+25% attack speed and +25% damage dealt", "category": "combo", "effects": [{"type": "stat_mult", "stat": "attack_speed", "value": 1.25}, {"type": "outgoing", "value": 1.25}]},
	{"id": "s_coil",  "name": "Immortal Coil",  "grade": "S", "desc": "Team heals 20% of the damage it deals, and each hero cheats death once per fight at 25% HP", "category": "combo", "effects": [{"type": "lifesteal", "value": 0.20}, {"type": "revive", "value": 0.25}]},
	{"id": "s_tyrant","name": "Tyrant's Crown", "grade": "S", "desc": "+45% attack damage and +20% crit chance", "category": "combo", "effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.45}, {"type": "stat_add", "stat": "crit_chance", "value": 0.20}]},
	{"id": "s_break", "name": "Worldbreaker",   "grade": "S", "desc": "+20% damage dealt, and +60% damage dealt to bosses", "category": "combo", "effects": [{"type": "outgoing", "value": 1.20}, {"type": "vs_boss", "value": 1.60}]},
	{"id": "s_gemini","name": "Gemini Fang",    "grade": "S", "desc": "40% chance for each attack to strike twice", "category": "stat_ladder", "ladder": "double_atk", "ladder_gated": true, "effects": [{"type": "double_atk", "value": 0.40}]},
	{"id": "s_bastion","name": "Worldroot Aegis","grade": "S", "desc": "+50% max HP, regenerate 4% max HP per second, and take 15% less damage", "category": "combo", "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.50}, {"type": "regen_pct", "value": 0.04}, {"type": "dmg_taken", "value": 0.85}]},

	# ── D (new) — always available ──
	{"id": "d_critdmg", "name": "Honed Edge",     "grade": "D", "desc": "+20% crit damage",         "category": "stat_ladder", "ladder": "crit_damage", "effects": [{"type": "stat_add", "stat": "crit_damage", "value": 0.20}]},
	{"id": "d_move",    "name": "Light Boots",    "grade": "D", "desc": "+1 movement speed",        "category": "combo", "effects": [{"type": "stat_add", "stat": "movement_speed", "value": 1}]},
	{"id": "d_range",   "name": "Long Barrel",    "grade": "D", "desc": "+1 attack range",           "category": "combo", "effects": [{"type": "stat_add", "stat": "attack_range", "value": 1}]},
	{"id": "d_twinfont","name": "Twin Font",      "grade": "D", "desc": "+15% max mana and +15% max HP", "category": "combo", "effects": [{"type": "stat_mult_multi", "stats": ["max_mana", "max_hp"], "value": 1.15}]},
	{"id": "d_lifeline","name": "Budding Idol",   "grade": "D", "desc": "+1.5 HP regen and +0.5 mana regen per second", "category": "combo", "effects": [{"type": "stat_add", "stat": "hp_regen", "value": 1.5}, {"type": "stat_add", "stat": "mana_regen", "value": 0.5}]},
	{"id": "d_tusk",    "name": "Boar Tusk",      "grade": "D", "desc": "+10% damage dealt to bosses", "category": "stat_ladder", "ladder": "vs_boss", "effects": [{"type": "vs_boss", "value": 1.10}]},
	{"id": "d_twinspark","name": "Twinspark",     "grade": "D", "desc": "8% chance for each attack to strike twice", "category": "stat_ladder", "ladder": "double_atk", "effects": [{"type": "double_atk", "value": 0.08}]},
	{"id": "d_grit",    "name": "Iron Grit",      "grade": "D", "desc": "Team takes 5% less damage", "category": "combo", "effects": [{"type": "dmg_taken", "value": 0.95}]},
	{"id": "d_leech",   "name": "Leech Fang",     "grade": "D", "desc": "Team heals 4% of the damage it deals", "category": "stat_ladder", "ladder": "lifesteal", "effects": [{"type": "lifesteal", "value": 0.04}]},

	# ── C (new) ──
	{"id": "c_critdmg", "name": "Sharpened Fang", "grade": "C", "desc": "+30% crit damage",         "category": "stat_ladder", "ladder": "crit_damage", "effects": [{"type": "stat_add", "stat": "crit_damage", "value": 0.30}]},
	{"id": "c_doubleatk","name": "Twinfang Charm","grade": "C", "desc": "15% chance for each attack to strike twice", "category": "stat_ladder", "ladder": "double_atk", "effects": [{"type": "double_atk", "value": 0.15}]},
	{"id": "c_trophy",  "name": "Trophy Hunter",  "grade": "C", "desc": "Each kill permanently grants that hero +0.8% attack damage (stacks all run)", "category": "stat_ladder", "ladder": "on_kill_atk", "effects": [{"type": "on_kill_atk", "value": 0.008}]},
	{"id": "c_sturdy",  "name": "Sturdy Font",    "grade": "C", "desc": "+25% max mana and +15% max HP", "category": "combo", "effects": [{"type": "stat_mult", "stat": "max_mana", "value": 1.25}, {"type": "stat_mult", "stat": "max_hp", "value": 1.15}]},
	{"id": "c_execute", "name": "Coup de Grace",  "grade": "C", "desc": "+25% damage to enemies below 15% HP (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "execute_pct", "hp_threshold_pct": 0.15, "dmg_bonus_pct": 0.25}]},
	{"id": "c_firststrike","name": "Ambush Blade","grade": "C", "desc": "The first attack each fight is a guaranteed crit (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "first_strike_crit", "first_strike_crit_mult": 2.0}]},
	{"id": "c_row",     "name": "Vanguard Standard","grade": "C", "desc": "Front-row heroes deal +15% damage (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "row_stat_mult", "front_mult": 1.15, "back_mult": 1.0}]},
	{"id": "c_range",   "name": "Extended Reach", "grade": "C", "desc": "+1 attack range and +10% attack speed", "category": "combo", "effects": [{"type": "stat_add", "stat": "attack_range", "value": 1}, {"type": "stat_mult", "stat": "attack_speed", "value": 1.10}]},

	# ── B (new) ──
	{"id": "b_doubleatk2","name": "Whirlwind Fang", "grade": "B", "desc": "17.5% chance for each attack to strike twice", "category": "stat_ladder", "ladder": "double_atk", "effects": [{"type": "double_atk", "value": 0.175}]},
	{"id": "b_execute", "name": "Executioner's Whisper", "grade": "B", "desc": "+35% damage to enemies below 25% HP (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "execute_pct", "hp_threshold_pct": 0.25, "dmg_bonus_pct": 0.35}]},
	{"id": "b_firststrike","name": "First Blood",  "grade": "B", "desc": "The first attack each fight is a guaranteed crit (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "first_strike_crit", "first_strike_crit_mult": 2.3}]},
	{"id": "b_row",     "name": "Phalanx Core",    "grade": "B", "desc": "Front-row heroes deal +30% damage (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "row_stat_mult", "front_mult": 1.30, "back_mult": 1.0}]},
	{"id": "b_opening", "name": "Opening Gambit",  "grade": "B", "desc": "+30% damage for the first 4 seconds of each fight (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "battle_start_dmg_window", "dmg_bonus_pct": 0.30, "seconds": 4.0}]},
	{"id": "b_momentum","name": "Flywheel",        "grade": "B", "desc": "Attack speed ramps up the longer a fight goes, capping at +100% (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "momentum", "pct_per_sec": 0.03}]},
	{"id": "b_ultrefund","name": "Soulsiphon Blade","grade": "B", "desc": "Killing blows refund 15% of the killer's ultimate charge (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "ult_refund_kill", "value": 0.15}]},
	{"id": "b_underdog","name": "Last Stand Banner","grade": "B", "desc": "+8% damage dealt and 5% less damage taken per dead ally this fight", "category": "mechanic", "effects": [{"type": "underdog", "dmg_per_dead": 0.08, "res_per_dead": 0.05}]},
	{"id": "b_goldscale","name": "Miser's Edge",   "grade": "B", "desc": "Damage scales with the run's current gold total", "category": "mechanic", "effects": [{"type": "gold_scaling_dmg", "value": 0.0003}]},
	{"id": "b_critres", "name": "Battleworn Plate","grade": "B", "desc": "+10% crit chance and the team takes 10% less damage", "category": "combo", "effects": [{"type": "stat_add", "stat": "crit_chance", "value": 0.10}, {"type": "dmg_taken", "value": 0.90}]},

	# ── A (new) ──
	{"id": "a_execute", "name": "Culling Blade",  "grade": "A", "desc": "+55% damage to enemies below 30% HP (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "execute_pct", "hp_threshold_pct": 0.30, "dmg_bonus_pct": 0.55}]},
	{"id": "a_row",     "name": "Battleline Discipline","grade": "A", "desc": "Front-row heroes deal +45% damage; back-row +10% (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "row_stat_mult", "front_mult": 1.45, "back_mult": 1.10}]},
	{"id": "a_opening", "name": "Alpha Strike",    "grade": "A", "desc": "+45% damage for the first 5 seconds of each fight (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "battle_start_dmg_window", "dmg_bonus_pct": 0.45, "seconds": 5.0}]},
	{"id": "a_momentum","name": "Overdrive Engine","grade": "A", "desc": "Attack speed ramps up faster the longer a fight goes, capping at +100% (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "momentum", "pct_per_sec": 0.05}]},
	{"id": "a_ultrefund","name": "Reaper's Bargain","grade": "A", "desc": "Killing blows refund 30% of the killer's ultimate charge (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "ult_refund_kill", "value": 0.30}]},
	{"id": "a_underdog","name": "Martyr's Resolve","grade": "A", "desc": "+15% damage dealt and 10% less damage taken per dead ally this fight (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "underdog", "dmg_per_dead": 0.15, "res_per_dead": 0.10}]},
	{"id": "a_goldscale","name": "Midas Touch",    "grade": "A", "desc": "Damage scales strongly with the run's current gold total (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "gold_scaling_dmg", "value": 0.0006}]},
	{"id": "a_firststrike","name": "Vanguard's Gambit","grade": "A", "desc": "The first attack each fight is a guaranteed crit (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "first_strike_crit", "first_strike_crit_mult": 2.6}]},

	# ── S (new) ──
	{"id": "s_execute", "name": "Deathmark",       "grade": "S", "desc": "+80% damage to enemies below 35% HP (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "execute_pct", "hp_threshold_pct": 0.35, "dmg_bonus_pct": 0.80}]},
	{"id": "s_row",     "name": "Immortal Formation","grade": "S", "desc": "Front-row heroes deal +60% damage; back-row +25% (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "row_stat_mult", "front_mult": 1.60, "back_mult": 1.25}]},
	{"id": "s_opening", "name": "First Light",      "grade": "S", "desc": "+60% damage for the first 6 seconds of each fight (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "battle_start_dmg_window", "dmg_bonus_pct": 0.60, "seconds": 6.0}]},
	{"id": "s_momentum","name": "Perpetual Motion", "grade": "S", "desc": "Attack speed ramps up rapidly the longer a fight goes, capping at +100% (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "momentum", "pct_per_sec": 0.08}]},
	{"id": "s_ultrefund","name": "Endless Reaping", "grade": "S", "desc": "Killing blows refund 50% of the killer's ultimate charge (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "ult_refund_kill", "value": 0.50}]},
	{"id": "s_underdog","name": "Last Light",       "grade": "S", "desc": "+25% damage dealt and 18% less damage taken per dead ally this fight (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "underdog", "dmg_per_dead": 0.25, "res_per_dead": 0.18}]},
	{"id": "s_goldscale","name": "Dragon's Avarice","grade": "S", "desc": "Damage scales heavily with the run's current gold total (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "gold_scaling_dmg", "value": 0.0010}]},
	{"id": "s_firststrike","name": "Alpha Predator","grade": "S", "desc": "The first attack each fight is a guaranteed crit (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "first_strike_crit", "first_strike_crit_mult": 3.0}]},
	{"id": "s_allstat", "name": "Ascendant Core",   "grade": "S", "desc": "+20% attack damage, magic power, max HP, and attack speed", "category": "combo", "effects": [{"type": "stat_mult_multi", "stats": ["attack_damage", "magic_power", "max_hp", "attack_speed"], "value": 1.20}]},

	# ── Mechanic-ladder low rungs (2026-08-05) — fills D/C beneath the B-S mechanic relics above ──
	{"id": "d_execute", "name": "Faltering Blow",   "grade": "D", "desc": "+15% damage to enemies below 10% HP (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "execute_pct", "hp_threshold_pct": 0.10, "dmg_bonus_pct": 0.15}]},
	{"id": "d_firststrike", "name": "Sudden Strike", "grade": "D", "desc": "The first attack each fight is a guaranteed crit (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "first_strike_crit", "first_strike_crit_mult": 1.8}]},
	{"id": "d_row",     "name": "Skirmish Line",    "grade": "D", "desc": "Front-row heroes deal +8% damage (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "row_stat_mult", "front_mult": 1.08, "back_mult": 1.0}]},
	{"id": "d_opening", "name": "Quickdraw",        "grade": "D", "desc": "+15% damage for the first 3 seconds of each fight (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "battle_start_dmg_window", "dmg_bonus_pct": 0.15, "seconds": 3.0}]},
	{"id": "c_opening", "name": "Ambuscade",        "grade": "C", "desc": "+22% damage for the first 3.5 seconds of each fight (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "battle_start_dmg_window", "dmg_bonus_pct": 0.22, "seconds": 3.5}]},
	{"id": "d_momentum","name": "Spinup Coil",      "grade": "D", "desc": "Attack speed ramps up the longer a fight goes, capping at +100% (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "momentum", "pct_per_sec": 0.015}]},
	{"id": "c_momentum","name": "Ramping Gear",     "grade": "C", "desc": "Attack speed ramps up the longer a fight goes, capping at +100% (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "momentum", "pct_per_sec": 0.022}]},
	{"id": "d_ultrefund","name": "Faint Echo",      "grade": "D", "desc": "Killing blows refund 6% of the killer's ultimate charge (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "ult_refund_kill", "value": 0.06}]},
	{"id": "c_ultrefund","name": "Soulspark Blade",  "grade": "C", "desc": "Killing blows refund 10% of the killer's ultimate charge (requires crystal tree unlock)", "category": "mechanic", "effects": [{"type": "ult_refund_kill", "value": 0.10}]},
	{"id": "d_goldscale","name": "Penny Pincher",   "grade": "D", "desc": "Damage scales with the run's current gold total", "category": "mechanic", "effects": [{"type": "gold_scaling_dmg", "value": 0.00012}]},
	{"id": "c_goldscale","name": "Coinbiter's Edge","grade": "C", "desc": "Damage scales with the run's current gold total", "category": "mechanic", "effects": [{"type": "gold_scaling_dmg", "value": 0.0002}]},
	{"id": "d_underdog","name": "Grim Resolve",     "grade": "D", "desc": "+4% damage dealt and 2% less damage taken per dead ally this fight", "category": "mechanic", "effects": [{"type": "underdog", "dmg_per_dead": 0.04, "res_per_dead": 0.02}]},
	{"id": "c_underdog","name": "Defiant Stand",    "grade": "C", "desc": "+6% damage dealt and 3.5% less damage taken per dead ally this fight", "category": "mechanic", "effects": [{"type": "underdog", "dmg_per_dead": 0.06, "res_per_dead": 0.035}]},

	# ── Stat-ladder gap-fill relics (2026-08-05), gated behind their ladder bundle unlock ──
	{"id": "a_hp", "name": "Titanforged Charm", "grade": "A", "desc": "+55% team max HP", "category": "stat_ladder", "ladder": "max_hp", "ladder_gated": true, "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.55}]},
	{"id": "s_hp", "name": "Worldheart Relic", "grade": "S", "desc": "+70% team max HP", "category": "stat_ladder", "ladder": "max_hp", "ladder_gated": true, "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.70}]},
	{"id": "a_atk", "name": "Executioner's Blade", "grade": "A", "desc": "+45% team attack damage", "category": "stat_ladder", "ladder": "atk_dmg", "ladder_gated": true, "effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.45}]},
	{"id": "s_atk", "name": "Godslayer Edge", "grade": "S", "desc": "+60% team attack damage", "category": "stat_ladder", "ladder": "atk_dmg", "ladder_gated": true, "effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.60}]},
	{"id": "a_mag", "name": "Archmage Prism", "grade": "A", "desc": "+45% team magic power", "category": "stat_ladder", "ladder": "magic_power", "ladder_gated": true, "effects": [{"type": "stat_mult", "stat": "magic_power", "value": 1.45}]},
	{"id": "s_mag", "name": "Astral Core", "grade": "S", "desc": "+60% team magic power", "category": "stat_ladder", "ladder": "magic_power", "ladder_gated": true, "effects": [{"type": "stat_mult", "stat": "magic_power", "value": 1.60}]},
	{"id": "c_aspd", "name": "Fleetfoot Sigil", "grade": "C", "desc": "+16% team attack speed", "category": "stat_ladder", "ladder": "attack_speed", "ladder_gated": true, "effects": [{"type": "stat_mult", "stat": "attack_speed", "value": 1.16}]},
	{"id": "b_aspd", "name": "Windrunner Core", "grade": "B", "desc": "+26% team attack speed", "category": "stat_ladder", "ladder": "attack_speed", "ladder_gated": true, "effects": [{"type": "stat_mult", "stat": "attack_speed", "value": 1.26}]},
	{"id": "a_aspd", "name": "Tempest Engine", "grade": "A", "desc": "+34% team attack speed", "category": "stat_ladder", "ladder": "attack_speed", "ladder_gated": true, "effects": [{"type": "stat_mult", "stat": "attack_speed", "value": 1.34}]},
	{"id": "c_critchance", "name": "Falcon's Eye", "grade": "C", "desc": "+12% team crit chance", "category": "stat_ladder", "ladder": "crit_chance", "ladder_gated": true, "effects": [{"type": "stat_add", "stat": "crit_chance", "value": 0.12}]},
	{"id": "b_critchance", "name": "Deadeye Lens", "grade": "B", "desc": "+16% team crit chance", "category": "stat_ladder", "ladder": "crit_chance", "ladder_gated": true, "effects": [{"type": "stat_add", "stat": "crit_chance", "value": 0.16}]},
	{"id": "a_critchance", "name": "Marksman's Focus", "grade": "A", "desc": "+20% team crit chance", "category": "stat_ladder", "ladder": "crit_chance", "ladder_gated": true, "effects": [{"type": "stat_add", "stat": "crit_chance", "value": 0.20}]},
	{"id": "s_critchance", "name": "Omniscient Eye", "grade": "S", "desc": "+25% team crit chance", "category": "stat_ladder", "ladder": "crit_chance", "ladder_gated": true, "effects": [{"type": "stat_add", "stat": "crit_chance", "value": 0.25}]},
	{"id": "b_critdmg", "name": "Serrated Fang", "grade": "B", "desc": "+45% crit damage", "category": "stat_ladder", "ladder": "crit_damage", "ladder_gated": true, "effects": [{"type": "stat_add", "stat": "crit_damage", "value": 0.45}]},
	{"id": "a_critdmg", "name": "Butcher's Edge", "grade": "A", "desc": "+65% crit damage", "category": "stat_ladder", "ladder": "crit_damage", "ladder_gated": true, "effects": [{"type": "stat_add", "stat": "crit_damage", "value": 0.65}]},
	{"id": "s_critdmg", "name": "Annihilator's Fang", "grade": "S", "desc": "+90% crit damage", "category": "stat_ladder", "ladder": "crit_damage", "ladder_gated": true, "effects": [{"type": "stat_add", "stat": "crit_damage", "value": 0.90}]},
	{"id": "b_res", "name": "Sanctified Plate", "grade": "B", "desc": "+65% armor and magic armor", "category": "stat_ladder", "ladder": "armor_dual", "ladder_gated": true, "effects": [{"type": "stat_mult_multi", "stats": ["resistance", "magic_resist"], "value": 1.65}]},
	{"id": "a_res", "name": "Aegis of the Unbroken", "grade": "A", "desc": "+90% armor and magic armor", "category": "stat_ladder", "ladder": "armor_dual", "ladder_gated": true, "effects": [{"type": "stat_mult_multi", "stats": ["resistance", "magic_resist"], "value": 1.90}]},
	{"id": "s_res", "name": "Bulwark Eternal", "grade": "S", "desc": "+120% armor and magic armor", "category": "stat_ladder", "ladder": "armor_dual", "ladder_gated": true, "effects": [{"type": "stat_mult_multi", "stats": ["resistance", "magic_resist"], "value": 2.20}]},
	{"id": "s_leech", "name": "Crimson Sovereign", "grade": "S", "desc": "Team heals 35% of the damage it deals", "category": "stat_ladder", "ladder": "lifesteal", "ladder_gated": true, "effects": [{"type": "lifesteal", "value": 0.35}]},
	{"id": "a_hoard", "name": "King's Ransom", "grade": "A", "desc": "+7 gold each round, and the shop shows 5 heroes", "category": "stat_ladder", "ladder": "gold_econ", "ladder_gated": true, "effects": [{"type": "gold_round", "value": 7}, {"type": "shop_slots", "value": 2}]},
	{"id": "s_hoard", "name": "Endless Vault", "grade": "S", "desc": "+10 gold each round, and the shop shows 5 heroes", "category": "stat_ladder", "ladder": "gold_econ", "ladder_gated": true, "effects": [{"type": "gold_round", "value": 10}, {"type": "shop_slots", "value": 2}]},
	{"id": "c_vsboss", "name": "Wyrmspike", "grade": "C", "desc": "+16% damage dealt to bosses", "category": "stat_ladder", "ladder": "vs_boss", "ladder_gated": true, "effects": [{"type": "vs_boss", "value": 1.16}]},
	{"id": "b_vsboss", "name": "Giant Slayer", "grade": "B", "desc": "+22% damage dealt to bosses", "category": "stat_ladder", "ladder": "vs_boss", "ladder_gated": true, "effects": [{"type": "vs_boss", "value": 1.22}]},
	{"id": "s_vsboss", "name": "Godkiller", "grade": "S", "desc": "+45% damage dealt to bosses", "category": "stat_ladder", "ladder": "vs_boss", "ladder_gated": true, "effects": [{"type": "vs_boss", "value": 1.45}]},
	{"id": "d_onkill", "name": "Trophy Fang", "grade": "D", "desc": "Each kill permanently grants that hero +0.4% attack damage (stacks all run)", "category": "stat_ladder", "ladder": "on_kill_atk", "ladder_gated": true, "effects": [{"type": "on_kill_atk", "value": 0.004}]},
	{"id": "b_onkill", "name": "Headhunter's Chain", "grade": "B", "desc": "Each kill permanently grants that hero +1.4% attack damage (stacks all run)", "category": "stat_ladder", "ladder": "on_kill_atk", "ladder_gated": true, "effects": [{"type": "on_kill_atk", "value": 0.014}]},
	{"id": "c_shield", "name": "Guarded Sigil", "grade": "C", "desc": "Team starts each fight with a shield worth 10% of max HP", "category": "stat_ladder", "ladder": "start_shield", "ladder_gated": true, "effects": [{"type": "start_shield", "value": 0.10}]},
	{"id": "a_shield", "name": "Rampart Core", "grade": "A", "desc": "Team starts each fight with a shield worth 22% of max HP", "category": "stat_ladder", "ladder": "start_shield", "ladder_gated": true, "effects": [{"type": "start_shield", "value": 0.22}]},
	{"id": "s_shield", "name": "Absolute Barrier", "grade": "S", "desc": "Team starts each fight with a shield worth 30% of max HP", "category": "stat_ladder", "ladder": "start_shield", "ladder_gated": true, "effects": [{"type": "start_shield", "value": 0.30}]},
	{"id": "c_ult", "name": "Resonant Sigil", "grade": "C", "desc": "Ultimates charge 17% faster", "category": "stat_ladder", "ladder": "ult_charge", "ladder_gated": true, "effects": [{"type": "ult_charge", "value": 1.17}]},
	{"id": "a_ult", "name": "Hypercharged Core", "grade": "A", "desc": "Ultimates charge 35% faster", "category": "stat_ladder", "ladder": "ult_charge", "ladder_gated": true, "effects": [{"type": "ult_charge", "value": 1.35}]},
	{"id": "s_ult", "name": "Singularity Core", "grade": "S", "desc": "Ultimates charge 50% faster", "category": "stat_ladder", "ladder": "ult_charge", "ladder_gated": true, "effects": [{"type": "ult_charge", "value": 1.50}]},
]

# ── Gacha rolling ─────────────────────────────────────────────────────────────

# Roll a grade for one offer slot off the given wave's odds.
static func roll_grade(wave: int) -> String:
	var odds: Dictionary = WAVE_ODDS.get(wave, WAVE_ODDS[1])
	var total := 0
	for w in odds.values():
		total += int(w)
	if total <= 0:
		return "D"
	var r := randi() % total
	var acc := 0
	for grade in GRADE_ORDER:
		acc += int(odds.get(grade, 0))
		if r < acc:
			return grade
	return "D"

# Roll `count` relic offers for a wave. Each slot rolls its grade independently,
# then draws a random relic of that grade. Never offers the same relic twice on
# one screen, and prefers relics the player doesn't already own.
static func roll_offers(wave: int, owned_ids: Array = [], count: int = 3) -> Array:
	var offers: Array = []
	var used_ids: Array = []
	for _i in range(count):
		var relic := _draw_one(wave, owned_ids, used_ids)
		if relic.is_empty():
			continue
		used_ids.append(relic["id"])
		offers.append(relic)
	return offers

# Roll a grade, then draw an unused relic of that grade. If the rolled grade is
# exhausted this screen, fan outward to adjacent grades so the slot still fills.
static func _draw_one(wave: int, owned_ids: Array, used_ids: Array) -> Dictionary:
	var grade := roll_grade(wave)
	for g in _grade_search_order(grade):
		var fresh: Array = []
		var owned: Array = []
		for relic in POOL:
			if relic["grade"] != g:
				continue
			if relic["id"] in used_ids:
				continue
			# Ladder-bundle relics (2026-08-05) are gated purely by their
			# ladder's bundle unlock, regardless of any per-id gate; everything
			# else keeps the original per-id gate (free unless individually
			# listed in Progression.RELIC_UNLOCK_KEYS).
			if relic.get("ladder_gated", false):
				if not Progression.is_ladder_unlocked(relic.get("ladder", "")):
					continue
			elif not Progression.is_relic_unlocked(relic["id"]):
				continue
			if relic["id"] in owned_ids:
				owned.append(relic)
			else:
				fresh.append(relic)
		var pick_from: Array = fresh if not fresh.is_empty() else owned
		if not pick_from.is_empty():
			return (pick_from[randi() % pick_from.size()] as Dictionary).duplicate(true)
	return {}

# Search the rolled grade first, then fan outward (nearer grades first) so an
# exhausted tier yields a neighbouring relic instead of an empty card.
# ── Crystal-tree unlock text ──────────────────────────────────────────────────
# The tree's relic-unlock nodes describe themselves from the pool rather than
# carrying their own copy of the wording, so retuning a relic's numbers here
# updates the shop blurb too (2026-08-05). Progression.display_desc routes any
# "relic_unlock_*" key through here; a tree/catalogue override still wins.

# The trailing "(requires crystal tree unlock)" is for the player reading the
# relic in a run. On the unlock node itself it's circular, so it's dropped.
const _UNLOCK_SUFFIX := " (requires crystal tree unlock)"

# Roughly what fits in CrystalShop's 700x54 word-wrapped detail label at 13px
# before the text clips. Ladder blurbs longer than this fall back to a summary.
const _DESC_BUDGET := 200

static func by_id(relic_id: String) -> Dictionary:
	for r in POOL:
		if r["id"] == relic_id:
			return r
	return {}

static func _effect_text(relic: Dictionary) -> String:
	return String(relic.get("desc", "")).trim_suffix(_UNLOCK_SUFFIX)

# Every relic a ladder bundle actually adds — the pre-existing low rungs are
# free, so only the ladder_gated ones are what the purchase buys.
static func ladder_relics(ladder_key: String) -> Array:
	var out: Array = []
	for r in POOL:
		if r.get("ladder", "") == ladder_key and r.get("ladder_gated", false):
			out.append(r)
	return out

static func unlock_desc(unlock_key: String) -> String:
	if not unlock_key.begins_with("relic_unlock_"):
		return ""
	if unlock_key.begins_with("relic_unlock_ladder_"):
		var members := ladder_relics(unlock_key.trim_prefix("relic_unlock_ladder_"))
		if members.is_empty():
			return ""
		var noun := "relic" if members.size() == 1 else "relics"
		var parts: PackedStringArray = []
		var grades: PackedStringArray = []
		for r in members:
			parts.append("%s (%s) %s" % [r["name"], r["grade"], _effect_text(r)])
			grades.append(String(r["grade"]))
		var full := "Adds %d %s to the pool — %s" % [members.size(), noun, " · ".join(parts)]
		# The shop's detail blurb is a three-line label. Rungs of one ladder all
		# restate the same stat, so a long list is mostly repetition — past the
		# line budget, quote the top rung and let the grades carry the rest.
		if full.length() <= _DESC_BUDGET:
			return full
		var top: Dictionary = members[-1]
		return "Adds %d %s to the pool (%s) — up to %s: %s" % [
			members.size(), noun, ", ".join(grades), top["name"], _effect_text(top)]
	var relic := by_id(unlock_key.trim_prefix("relic_unlock_"))
	if relic.is_empty():
		return ""
	return "%s-grade relic — %s" % [relic["grade"], _effect_text(relic)]

static func _grade_search_order(grade: String) -> Array:
	var i := GRADE_ORDER.find(grade)
	if i == -1:
		return GRADE_ORDER.duplicate()
	var order: Array = [grade]
	var off := 1
	while order.size() < GRADE_ORDER.size():
		if i - off >= 0:
			order.append(GRADE_ORDER[i - off])
		if i + off < GRADE_ORDER.size():
			order.append(GRADE_ORDER[i + off])
		off += 1
	return order
