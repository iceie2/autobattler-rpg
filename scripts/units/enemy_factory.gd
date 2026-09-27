extends Node
class_name EnemyFactory

# ── Code → factory dispatch (single source of truth) ─────────────────────────
# Wave codes (WaveScaler formations) and type strings (wave specs) both resolve
# here. main_game.gd and the arena harness (scripts/arena/) share this — when
# adding a new enemy: add its factory below, then register it in BOTH dicts
# here, plus WaveScaler's CODE_ROLE/CODE_IS_LARGE/UNIT_POWER.
const CODE_TO_TYPE := {
	"M": "goblin", "A": "goblin_archer",
	"G": "hill_giant", "SK": "skeleton", "R": "rat",
	"TRI": "triarch", "SS": "stat_stealer", "AH": "ant_hill", "KHA": "khagan",
	"SKR": "skyrender",   # wave-20 Air boss (2026-07-27)
	"DMW": "drowned_maw", # wave-30 Water boss (2026-07-28)
	"CLT": "cloven_titan", # wave-40 Earth boss (2026-07-28)
	"EMB": "emberhollow", "EMH": "ember_heart", # wave-50 Fire boss + its adds (2026-07-28)
	"ARC": "arcfang",     # wave-60 Lightning boss (2026-07-29)
	"GRV": "gravekeeper", # wave-90 mixed boss (2026-07-29)
	"ARCH": "the_architect", # wave-100 FINALE — the only 3×3 (2026-07-29)
	# Elemental elites (2026-07-27) — one per decade, see WaveScaler.ELITE_BY_ROUND.
	"GW": "gale_warden", "TC": "tidecaller", "TCC": "terracotta_colossus",
	"MH": "magma_heart", "TPC": "tempest_conduit",
	"MW": "mirrorplate_warden", "AD": "aspect_devourer",
	# Goblin Shaman — 6 elemental variants. "S" keeps its old code/slot (was
	# hardcoded FIRE); it's now just the Fire Goblin Shaman so existing WaveData
	# entries ("S": n in fixed early waves) don't need touching. New variants use
	# a "GS" prefix (not "S*") since "SL"/"SLN"/etc are already Slime's codes.
	"S": "goblin_shaman_fire", "GSN": "goblin_shaman_normal", "GSW": "goblin_shaman_water",
	"GSE": "goblin_shaman_earth", "GSA": "goblin_shaman_air", "GSL": "goblin_shaman_lightning",
	# Orc — 6 elemental variants. "B" keeps its old code/slot (was Orc Brute,
	# hardcoded EARTH); it's now just the Earth Orc so existing WaveData entries
	# ("B": n in fixed early waves) don't need touching.
	"B": "orc_earth", "BN": "orc_normal", "BF": "orc_fire", "BW": "orc_water",
	"BA": "orc_air", "BL": "orc_lightning",
	# Slime — 6 elemental variants. "SL" keeps its old code/slot (was hardcoded
	# WATER) for the same reason.
	"SL": "slime_water", "SLN": "slime_normal", "SLF": "slime_fire",
	"SLE": "slime_earth", "SLA": "slime_air", "SLL": "slime_lightning",
	# Lizard — 6 elemental variants, brand new (no prior single-unit to fold
	# into, unlike Orc/Slime), so all 6 codes are fresh.
	"LZN": "lizard_normal", "LZF": "lizard_fire", "LZW": "lizard_water",
	"LZE": "lizard_earth", "LZA": "lizard_air", "LZL": "lizard_lightning",
	# Bear — 6 elemental variants, brand new.
	"BRN": "bear_normal", "BRF": "bear_fire", "BRW": "bear_water",
	"BRE": "bear_earth", "BRA": "bear_air", "BRL": "bear_lightning",
	# Troll — 6 elemental variants, brand new.
	"TLN": "troll_normal", "TLF": "troll_fire", "TLW": "troll_water",
	"TLE": "troll_earth", "TLA": "troll_air", "TLL": "troll_lightning",
	# Wind-Up Bot — 6 elemental variants, brand new.
	"WUN": "windup_bot_normal", "WUF": "windup_bot_fire", "WUW": "windup_bot_water",
	"WUE": "windup_bot_earth", "WUA": "windup_bot_air", "WUL": "windup_bot_lightning",
	# Hydra — wave-30 final boss, 6 elemental variants (player picks which one fights).
	"HYN": "hydra_normal", "HYF": "hydra_fire", "HYW": "hydra_water",
	"HYE": "hydra_earth", "HYA": "hydra_air", "HYL": "hydra_lightning",
	# Beast tier (2026-07-24) — single-element heavies, one notch above the Bear/
	# Wind-Up Bot ceiling (UNIT_POWER 90-100) and below the elite-heavy tier
	# (Hill Giant 300 / Stat Stealer 150). Built to thin later-wave body counts
	# further (see [[feedback_elites_exclusive]]) and to seed wave 31+ content.
	# No new combat mechanics — every skill/passive below reuses an existing
	# mob_skill/mob_passive key (see auto_battle_manager._use_mob_skill /
	# _tick_mob_passive) with new stat budgets, per the "ask before inventing
	# ability mechanics" rule.
	"OG": "ogre", "MT": "minotaur", "GY": "gargoyle", "SG": "stone_golem",
	# Earth-decade variety (2026-07-24, wave 31-40) — same reuse-only pattern as
	# Beast tier, from the same prompt sheet. "CC"/"RW" not "C"/"R" since "R" is
	# already Rat.
	"CC": "crystal_crab", "RW": "root_walker",
	# Fire-decade roster (2026-07-24, wave 41-50). FG is the decade's 2×2 power
	# ANCHOR — see the create_fire_giant notes for why each elemental decade
	# needs its own large body instead of reusing the (Earth-flavored) Hill Giant.
	"FG": "fire_giant", "HH": "hellhound", "EP": "ember_phoenix",
	# Lightning-decade roster (2026-07-24, wave 51-60). STG is the decade's 2×2
	# anchor — note the code is STG, not SG: "SG" is already Stone Golem.
	"STG": "storm_giant", "SC": "storm_crow",
	# Air/Water-decade 2×2 anchors (2026-08-02, waves 11-20 / 21-30) — the two
	# slots the "own giant per decade" rule was missing. See create_sky_wyvern.
	"WY": "sky_wyvern", "TH": "tidepool_horror",
	# Air/Water flavour bodies (2026-08-02) — each foreshadows its decade's elite.
	"HRP": "harpy", "CH": "coral_husk",
}

# Returns a NEW level-1 unit for a wave-code or type string; caller applies
# set_level() afterwards (matches main_game's flow — never level inside the
# factory, phase-boss snapshots depend on external leveling; see Triarch notes).
# ── Tenacity by tier (2026-08-07) ─────────────────────────────────────────────
# Tenacity shortens incoming CC on the armor curve (100/(100+ten), see
# UnitBase.status_duration_mult) and can never fully block it. The reason the
# stat exists: stun duration used to be absolute, so stun-lock scaled with team
# size and attack speed while a single-body boss had no defense at all — every
# boss and elite fight was decided by whether the player could chain-stun rather
# than by the encounter's mechanics.
#   normal 20 → 0.83x    elite 60 → 0.63x    boss 180 → 0.36x
# FIRST-CUT NUMBERS, not a balance claim — tune from arena runs (non-boss waves
# only; the boss-round harness is currently untrustworthy).
const TENACITY_NORMAL := 20
const TENACITY_ELITE  := 60
const TENACITY_BOSS   := 180

# Fills in a tier default for anything that didn't set its own tenacity. A
# constructor that wants a bespoke value just assigns u.tenacity and a non-zero
# value is left alone here.
static func apply_tier_tenacity(u: VisualUnit) -> void:
	if u == null or u.tenacity != 0:
		return
	if u.is_boss:
		u.tenacity = TENACITY_BOSS
	elif u.is_elite:
		u.tenacity = TENACITY_ELITE
	else:
		u.tenacity = TENACITY_NORMAL

static func create_by_type(type: String) -> VisualUnit:
	var u := _create_by_type_dispatch(type)
	if u:
		apply_tier_tenacity(u)
		# Affinity rework (2026-07-16): every enemy gets the neutral 100/100
		# base plus the shared own-element ±deltas (Balance.AFFINITY_*). Must
		# run AFTER the factory func so current_element is already set.
		u.set_affinity_profile(100.0, 100.0)
	return u

static func _create_by_type_dispatch(type: String) -> VisualUnit:
	match type:
		"goblin":        return create_goblin()
		"goblin_archer": return create_goblin_archer()
		"goblin_shaman_normal":    return create_goblin_shaman_normal()
		"goblin_shaman_fire":      return create_goblin_shaman_fire()
		"goblin_shaman_water":     return create_goblin_shaman_water()
		"goblin_shaman_earth":     return create_goblin_shaman_earth()
		"goblin_shaman_air":       return create_goblin_shaman_air()
		"goblin_shaman_lightning": return create_goblin_shaman_lightning()
		"orc_normal":    return create_orc_normal()
		"orc_fire":      return create_orc_fire()
		"orc_water":     return create_orc_water()
		"orc_earth":     return create_orc_earth()
		"orc_air":       return create_orc_air()
		"orc_lightning": return create_orc_lightning()
		"hill_giant":    return create_hill_giant()
		"gale_warden":   return create_gale_warden()
		"tidecaller":    return create_tidecaller()
		"terracotta_colossus": return create_terracotta_colossus()
		"magma_heart":   return create_magma_heart()
		"tempest_conduit": return create_tempest_conduit()
		"mirrorplate_warden": return create_mirrorplate_warden()
		"aspect_devourer": return create_aspect_devourer()
		"slime_normal":    return create_slime_normal()
		"slime_fire":      return create_slime_fire()
		"slime_water":     return create_slime_water()
		"slime_earth":     return create_slime_earth()
		"slime_air":       return create_slime_air()
		"slime_lightning": return create_slime_lightning()
		"lizard_normal":    return create_lizard_normal()
		"lizard_fire":      return create_lizard_fire()
		"lizard_water":     return create_lizard_water()
		"lizard_earth":     return create_lizard_earth()
		"lizard_air":       return create_lizard_air()
		"lizard_lightning": return create_lizard_lightning()
		"bear_normal":    return create_bear_normal()
		"bear_fire":      return create_bear_fire()
		"bear_water":     return create_bear_water()
		"bear_earth":     return create_bear_earth()
		"bear_air":       return create_bear_air()
		"bear_lightning": return create_bear_lightning()
		"troll_normal":    return create_troll_normal()
		"troll_fire":      return create_troll_fire()
		"troll_water":     return create_troll_water()
		"troll_earth":     return create_troll_earth()
		"troll_air":       return create_troll_air()
		"troll_lightning": return create_troll_lightning()
		"windup_bot_normal":    return create_windup_bot_normal()
		"windup_bot_fire":      return create_windup_bot_fire()
		"windup_bot_water":     return create_windup_bot_water()
		"windup_bot_earth":     return create_windup_bot_earth()
		"windup_bot_air":       return create_windup_bot_air()
		"windup_bot_lightning": return create_windup_bot_lightning()
		"hydra_normal":    return create_hydra_normal()
		"hydra_fire":      return create_hydra_fire()
		"hydra_water":     return create_hydra_water()
		"hydra_earth":     return create_hydra_earth()
		"hydra_air":       return create_hydra_air()
		"hydra_lightning": return create_hydra_lightning()
		"skeleton":      return create_skeleton()
		"rat":           return create_rat()
		"triarch":       return create_triarch()
		"stat_stealer":  return create_stat_stealer()
		"ant_hill":      return create_ant_hill()
		"khagan":        return create_khagan()
		"skyrender": return create_skyrender()
		"drowned_maw": return create_drowned_maw()
		"cloven_titan": return create_cloven_titan()
		"emberhollow": return create_emberhollow()
		"ember_heart": return create_ember_heart()
		"arcfang": return create_arcfang()
		"gravekeeper": return create_gravekeeper()
		"the_architect": return create_the_architect()
		"ogre":          return create_ogre()
		"minotaur":      return create_minotaur()
		"gargoyle":      return create_gargoyle()
		"stone_golem":   return create_stone_golem()
		"crystal_crab":  return create_crystal_crab()
		"root_walker":   return create_root_walker()
		"fire_giant":    return create_fire_giant()
		"hellhound":     return create_hellhound()
		"ember_phoenix": return create_ember_phoenix()
		"storm_giant":   return create_storm_giant()
		"storm_crow":    return create_storm_crow()
		"sky_wyvern":      return create_sky_wyvern()
		"tidepool_horror": return create_tidepool_horror()
		"harpy":           return create_harpy()
		"coral_husk":      return create_coral_husk()
	return null

static func create_by_code(code: String) -> VisualUnit:
	return create_by_type(CODE_TO_TYPE.get(code, ""))

# ── Goblin (weak melee) ───────────────────────────────────────────────────────
static func create_goblin(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Goblin"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 150
	u.current_hp      = 150
	u.max_mana        = 20
	u.current_mana    = 20
	u.attack_damage   = 21
	u.magic_power     = 8
	u.resistance      = 6
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.68
	u.hp_regen        = 0.42
	u.mana_regen      = 0.5
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 0
	u.crystal_reward  = 1
	u.xp_reward       = 50
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "goblin")
	u.skill_name = "Shank"
	u.skill_damage_multiplier = 2.0
	u.skill_range = 1
	u.skill_cooldown_max = 5
	u.skill_mana_cost = 0
	u.skill_description = "Lunge at an adjacent enemy for 200% ATK. · 5s CD"
	# Basic mobs have no ultimate. Leaving UnitBase's inherited 300 charge here
	# made the Goblin silently cast a second, unnamed Shank when the bar filled.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "goblin_shank")
	u.set_meta("mob_passive", "goblin_pack")
	u.set_meta("passive_name", "Pack Courage")
	u.set_meta("passive_desc", "+6% attack speed per other Goblin within 3 tiles (max +30%). Pathetic alone, dangerous in a mob.")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Goblin Archer (weak ranged) ───────────────────────────────────────────────
static func create_goblin_archer(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Goblin Archer"
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 120
	u.current_hp      = 120
	u.max_mana        = 30
	u.current_mana    = 30
	u.attack_damage   = 20
	u.magic_power     = 9
	u.resistance      = 8
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 1.3
	u.hp_regen        = 0.5
	u.mana_regen      = 0.5
	u.movement_speed  = 1
	u.attack_range    = 4
	u.gold_reward     = 0
	u.crystal_reward  = 0
	u.xp_reward       = 60
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "goblin_archer")
	u.skill_name = "Crippling Arrow"
	u.skill_damage_multiplier = 1.2
	u.skill_range = 4
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Deal 120% ATK and slow the target 30% for 2s. · 6s CD"
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "archer_cripple")
	u.set_meta("mob_passive", "archer_focus")
	u.set_meta("passive_name", "Focus Fire")
	u.set_meta("passive_desc", "+8% damage each consecutive hit on the same target (max +40%); resets on switching targets.")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Goblin Shaman (ranged magic support) — 6 elemental variants ─────────────
# Same pattern as Orc/Slime/Bear/etc: one stat block, element + sprite vary.
# "S" keeps its old code/slot (was hardcoded FIRE); it's now just the Fire
# Goblin Shaman so existing WaveData entries ("S": n in fixed early waves)
# don't need touching. Mend deals no damage, so there's no affinity-scaling
# concern here (that convention only applies to damaging mob skills).
const GOBLIN_SHAMAN_ELEMENT_NAMES := {
	UnitBase.Element.NORMAL:    "Normal",
	UnitBase.Element.FIRE:      "Fire",
	UnitBase.Element.WATER:     "Water",
	UnitBase.Element.EARTH:     "Earth",
	UnitBase.Element.AIR:       "Air",
	UnitBase.Element.LIGHTNING: "Lightning",
}
const GOBLIN_SHAMAN_SPRITE_FOLDERS := {
	UnitBase.Element.NORMAL:    "goblin_shaman_normal",
	UnitBase.Element.FIRE:      "goblin_shaman_fire",
	UnitBase.Element.WATER:     "goblin_shaman_water",
	UnitBase.Element.EARTH:     "goblin_shaman_earth",
	UnitBase.Element.AIR:       "goblin_shaman_air",
	UnitBase.Element.LIGHTNING: "goblin_shaman_lightning",
}

static func _create_goblin_shaman(element: UnitBase.Element, lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "%s Goblin Shaman" % GOBLIN_SHAMAN_ELEMENT_NAMES[element]
	u.unit_class      = UnitBase.UnitClass.BLACK_MAGE
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = element
	u.is_player_unit  = false
	u.max_hp          = 300
	u.current_hp      = 300
	u.max_mana        = 60
	u.current_mana    = 30
	u.attack_damage   = 9
	u.magic_power     = 19
	u.resistance      = 13
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.66
	u.hp_regen        = 0.12
	u.mana_regen      = 3.0
	u.movement_speed  = 2
	u.attack_range    = 4
	u.gold_reward     = 18
	u.crystal_reward  = 1
	u.xp_reward       = 70
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", GOBLIN_SHAMAN_SPRITE_FOLDERS[element])
	u.skill_name = "Mend"
	u.skill_damage_multiplier = 0.0
	u.skill_range = 6
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Heal the most-wounded ally for 150% MAG. · 6s CD"
	u.set_meta("mob_skill", "shaman_mend")
	u.set_meta("mob_passive", "shaman_link")
	u.set_meta("passive_name", "Spirit Link")
	u.set_meta("passive_desc", "Other allies within 3 tiles regenerate +0.5 HP/s (stacks with its active heal).")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_goblin_shaman_normal(lvl: int = 1) -> VisualUnit:    return _create_goblin_shaman(UnitBase.Element.NORMAL, lvl)
static func create_goblin_shaman_fire(lvl: int = 1) -> VisualUnit:      return _create_goblin_shaman(UnitBase.Element.FIRE, lvl)
static func create_goblin_shaman_water(lvl: int = 1) -> VisualUnit:     return _create_goblin_shaman(UnitBase.Element.WATER, lvl)
static func create_goblin_shaman_earth(lvl: int = 1) -> VisualUnit:     return _create_goblin_shaman(UnitBase.Element.EARTH, lvl)
static func create_goblin_shaman_air(lvl: int = 1) -> VisualUnit:       return _create_goblin_shaman(UnitBase.Element.AIR, lvl)
static func create_goblin_shaman_lightning(lvl: int = 1) -> VisualUnit: return _create_goblin_shaman(UnitBase.Element.LIGHTNING, lvl)

# ── Orc (heavy melee bruiser) — 6 elemental variants ─────────────────────────
# Same base stat block for all 6 (only element + sprite differ, per design
# call 2026-07-06); skill damage already scales with the caster's own
# current_element via the generic take_damage(dmg, caster.current_element)
# path in AutoBattleManager, so setting current_element here is all "Crushing
# Blow" needs to hit as that element's type. "orc_earth" is the direct
# successor to the old "Orc Brute" (same stats/name pattern/code "B").
const ORC_ELEMENT_NAMES := {
	UnitBase.Element.NORMAL:    "Normal",
	UnitBase.Element.FIRE:      "Fire",
	UnitBase.Element.WATER:     "Water",
	UnitBase.Element.EARTH:     "Earth",
	UnitBase.Element.AIR:       "Air",
	UnitBase.Element.LIGHTNING: "Lightning",
}
const ORC_SPRITE_FOLDERS := {
	UnitBase.Element.NORMAL:    "orc_normal",
	UnitBase.Element.FIRE:      "orc_fire",
	UnitBase.Element.WATER:     "orc_water",
	UnitBase.Element.EARTH:     "orc_earth",
	UnitBase.Element.AIR:       "orc_air",
	UnitBase.Element.LIGHTNING: "orc_lightning",
}

static func _create_orc(element: UnitBase.Element, lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "%s Orc" % ORC_ELEMENT_NAMES[element]
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = element
	u.is_player_unit  = false
	u.max_hp          = 750
	u.current_hp      = 750
	u.max_mana        = 20
	u.current_mana    = 20
	u.attack_damage   = 31
	u.magic_power     = 11
	u.resistance      = 15
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.64
	u.hp_regen        = 0.7
	u.mana_regen      = 0.5
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 25
	u.crystal_reward  = 1
	u.xp_reward       = 100
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", ORC_SPRITE_FOLDERS[element])
	# is_boss removed 2026-07-03: leftover from when the orc WAS a wave boss.
	# It made "vs boss" relic damage apply to every orc, and would have given
	# each fodder orc a boss-tier coin drop in the new gold economy.
	u.skill_name = "Crushing Blow"
	u.skill_damage_multiplier = 1.6
	u.skill_range = 1
	u.skill_cooldown_max = 7
	u.skill_mana_cost = 0
	u.skill_description = "Deal 160% ATK and stun for 1s. · 7s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool (~2.5 free Crushing
	# Blows per fight at 750 HP). See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "brute_crush")
	# Slam/Bloodrage visuals, sized to this body. See _crush_vfx_reach: the Ogre
	# sets its own larger value because its ability is named identically; the
	# Fire Giant and Tidepool Horror share the key but not the names, so they
	# opt out until their own passes.
	u.set_meta("crush_vfx_reach", 104.0)
	u.set_meta("mob_passive", "orc_rage")
	u.set_meta("passive_name", "Bloodrage")
	u.set_meta("passive_desc", "Below 50% HP: +20% attack damage and +15% attack speed. A wounded orc is scarier.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_orc_normal(lvl: int = 1) -> VisualUnit:    return _create_orc(UnitBase.Element.NORMAL, lvl)
static func create_orc_fire(lvl: int = 1) -> VisualUnit:      return _create_orc(UnitBase.Element.FIRE, lvl)
static func create_orc_water(lvl: int = 1) -> VisualUnit:     return _create_orc(UnitBase.Element.WATER, lvl)
static func create_orc_earth(lvl: int = 1) -> VisualUnit:     return _create_orc(UnitBase.Element.EARTH, lvl)
static func create_orc_air(lvl: int = 1) -> VisualUnit:       return _create_orc(UnitBase.Element.AIR, lvl)
static func create_orc_lightning(lvl: int = 1) -> VisualUnit: return _create_orc(UnitBase.Element.LIGHTNING, lvl)

# ── Slime (slow, tanky, low damage) — 6 elemental variants ───────────────────
# Same pattern as the Orc above: one stat block, element + sprite vary.
# "slime_water" is the direct successor to the old plain "Slime" (code "SL").
const SLIME_ELEMENT_NAMES := {
	UnitBase.Element.NORMAL:    "Normal",
	UnitBase.Element.FIRE:      "Fire",
	UnitBase.Element.WATER:     "Water",
	UnitBase.Element.EARTH:     "Earth",
	UnitBase.Element.AIR:       "Air",
	UnitBase.Element.LIGHTNING: "Lightning",
}
const SLIME_SPRITE_FOLDERS := {
	UnitBase.Element.NORMAL:    "slime_normal",
	UnitBase.Element.FIRE:      "slime_fire",
	UnitBase.Element.WATER:     "slime_water",
	UnitBase.Element.EARTH:     "slime_earth",
	UnitBase.Element.AIR:       "slime_air",
	UnitBase.Element.LIGHTNING: "slime_lightning",
}

static func _create_slime(element: UnitBase.Element, lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "%s Slime" % SLIME_ELEMENT_NAMES[element]
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = element
	u.is_player_unit  = false
	u.max_hp          = 220
	u.current_hp      = 220
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 14
	u.magic_power     = 4
	u.resistance      = 7        # naturally tough, hits weak
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.58
	u.hp_regen        = 0.3
	u.mana_regen      = 0.17
	u.movement_speed  = 2           # sluggish
	u.attack_range    = 1
	u.gold_reward     = 12
	u.crystal_reward  = 0
	u.xp_reward       = 50
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", SLIME_SPRITE_FOLDERS[element])
	u.skill_name = "Corrosive Goo"
	u.skill_damage_multiplier = 0.0
	u.skill_range = 1
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Weaken the target: -25% outgoing damage for 3s. · 6s CD"
	# Declares no ultimate but inherits UnitBase's 300 charge pool, so it charged
	# one from damage taken and re-fired Corrosive Goo off-cooldown through
	# _use_ultimate's fallback. ~0.7 free casts/fight at 220 HP. See the Rat for
	# the full note; bosses/elites are deliberately left alone.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "slime_goo")
	u.set_meta("mob_passive", "slime_split")
	u.set_meta("passive_name", "Split")
	u.set_meta("passive_desc", "On death, splits into two smaller slimes (40% HP, 60% stats). One generation only.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_slime_normal(lvl: int = 1) -> VisualUnit:    return _create_slime(UnitBase.Element.NORMAL, lvl)
static func create_slime_fire(lvl: int = 1) -> VisualUnit:      return _create_slime(UnitBase.Element.FIRE, lvl)
static func create_slime_water(lvl: int = 1) -> VisualUnit:     return _create_slime(UnitBase.Element.WATER, lvl)
static func create_slime_earth(lvl: int = 1) -> VisualUnit:     return _create_slime(UnitBase.Element.EARTH, lvl)
static func create_slime_air(lvl: int = 1) -> VisualUnit:       return _create_slime(UnitBase.Element.AIR, lvl)
static func create_slime_lightning(lvl: int = 1) -> VisualUnit: return _create_slime(UnitBase.Element.LIGHTNING, lvl)

# ── Lizard (far-range sniper, barely moves) — 6 elemental variants ───────────
# Brand new mob (2026-07-06), no prior single-unit precedent to fold into
# (unlike Orc/Slime), so all 6 codes/variants are fresh. Same pattern as the
# other elemental families: one stat block, element + sprite vary. Its
# signature move (Precision Shot) is a plain high-multiplier single-target
# snipe — the extra damage automatically carries the lizard's own element via
# the same generic take_damage(dmg, caster.current_element) path every mob
# skill uses, so an Ice Lizard's shot already scales off its Water affinity
# with zero extra plumbing (see _use_mob_skill's "lizard_snipe" case).
const LIZARD_ELEMENT_NAMES := {
	UnitBase.Element.NORMAL:    "Normal",
	UnitBase.Element.FIRE:      "Fire",
	UnitBase.Element.WATER:     "Water",
	UnitBase.Element.EARTH:     "Earth",
	UnitBase.Element.AIR:       "Air",
	UnitBase.Element.LIGHTNING: "Lightning",
}
const LIZARD_SPRITE_FOLDERS := {
	UnitBase.Element.NORMAL:    "lizard_normal",
	UnitBase.Element.FIRE:      "lizard_fire",
	UnitBase.Element.WATER:     "lizard_water",
	UnitBase.Element.EARTH:     "lizard_earth",
	UnitBase.Element.AIR:       "lizard_air",
	UnitBase.Element.LIGHTNING: "lizard_lightning",
}

static func _create_lizard(element: UnitBase.Element, lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "%s Lizard" % LIZARD_ELEMENT_NAMES[element]
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = element
	u.is_player_unit  = false
	u.max_hp          = 200
	u.current_hp      = 200
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 60
	u.magic_power     = 6
	u.resistance      = 15
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 2.0
	u.hp_regen        = 0.35
	u.mana_regen      = 0.17
	u.movement_speed  = 1           # barely moves — leans entirely on its range
	u.attack_range    = 8           # far range — outranges every other basic mob
	u.gold_reward     = 17
	u.crystal_reward  = 0
	u.xp_reward       = 60
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", LIZARD_SPRITE_FOLDERS[element])
	u.skill_name = "Precision Shot"
	u.skill_damage_multiplier = 2.2
	# Aligned to attack_range (2026-09-17). It was 5 against an attack_range of 8,
	# so the Lizard outranged its own signature by 3 tiles — invisible only because
	# the skill had no range gate at all and fired from anywhere. Gating it at 8
	# preserves the behaviour players actually saw while making the number honest.
	u.skill_range = 8
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	# Now literally true: it pierces the target's whole row (user direction
	# 2026-09-17). Previously said "piercing" but hit exactly one unit.
	u.skill_description = "Pierces the target's entire row for 220% ATK. · 6s CD"
	u.set_meta("mob_skill", "lizard_snipe")
	# Marks the real Lizard: the shared lizard_snipe key is also the Ember
	# Phoenix's Cinder Lance, which keeps its single-target instant behaviour.
	u.set_meta("lizard_sniper", true)
	# See the Rat for the full note: declares no ultimate but inherits a 300
	# charge pool and re-fires its skill off-cooldown through _use_ultimate's
	# fallback. ~0.7 free casts/fight at 200 HP.
	u.ultimate_charge_max = 0
	u.set_meta("mob_passive", "lizard_coldblood")
	u.set_meta("passive_name", "Cold Blood")
	u.set_meta("passive_desc", "Regenerates 3% max HP/s while it hasn't been hit for 3s. Punishes ignoring the backline.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_lizard_normal(lvl: int = 1) -> VisualUnit:    return _create_lizard(UnitBase.Element.NORMAL, lvl)
static func create_lizard_fire(lvl: int = 1) -> VisualUnit:      return _create_lizard(UnitBase.Element.FIRE, lvl)
static func create_lizard_water(lvl: int = 1) -> VisualUnit:     return _create_lizard(UnitBase.Element.WATER, lvl)
static func create_lizard_earth(lvl: int = 1) -> VisualUnit:     return _create_lizard(UnitBase.Element.EARTH, lvl)
static func create_lizard_air(lvl: int = 1) -> VisualUnit:       return _create_lizard(UnitBase.Element.AIR, lvl)
static func create_lizard_lightning(lvl: int = 1) -> VisualUnit: return _create_lizard(UnitBase.Element.LIGHTNING, lvl)

# ── Bear (beefy tank, low damage) — 6 elemental variants ─────────────────────
# Brand new mob (2026-07-06). Its signature move (Rending Swipe) reads the
# caster's own-element offensive affinity — since the 2026-07-16 affinity
# rework every unit gets its own-element +50 rating from set_affinity_profile
# (applied in create_by_type), so the old per-bear ELEMENTAL_SELF_AFFINITY
# assignment is gone; the swipe's element scaling now rides the shared system.

const BEAR_ELEMENT_NAMES := {
	UnitBase.Element.NORMAL:    "Normal",
	UnitBase.Element.FIRE:      "Fire",
	UnitBase.Element.WATER:     "Water",
	UnitBase.Element.EARTH:     "Earth",
	UnitBase.Element.AIR:       "Air",
	UnitBase.Element.LIGHTNING: "Lightning",
}
const BEAR_SPRITE_FOLDERS := {
	UnitBase.Element.NORMAL:    "bear_normal",
	UnitBase.Element.FIRE:      "bear_fire",
	UnitBase.Element.WATER:     "bear_water",
	UnitBase.Element.EARTH:     "bear_earth",
	UnitBase.Element.AIR:       "bear_air",
	UnitBase.Element.LIGHTNING: "bear_lightning",
}

static func _create_bear(element: UnitBase.Element, lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "%s Bear" % BEAR_ELEMENT_NAMES[element]
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = element
	u.is_player_unit  = false
	u.max_hp          = 1200         # beefiest 1×1 tank in the roster
	u.current_hp      = 1200
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 18           # deliberately low — the whole point is the tank, not the hit
	u.magic_power     = 5
	u.resistance      = 31
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.5
	u.hp_regen        = 0.9
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 30
	u.crystal_reward  = 1
	u.xp_reward       = 110
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", BEAR_SPRITE_FOLDERS[element])
	# (own-element affinity now comes from set_affinity_profile — 2026-07-16)
	u.skill_name = "Rending Swipe"
	u.skill_damage_multiplier = 1.3
	u.skill_range = 1
	u.skill_cooldown_max = 7
	u.skill_mana_cost = 0
	u.skill_description = "Swipe for 130% ATK (scales with own elemental affinity) and open a bleed: 30% ATK/s for 4s, doubled while the target moves. · 7s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool. At 1200 HP that is
	# ~4 free Rending Swipes per fight on the beefiest 1x1 body in the roster.
	# See the Rat for the full note; bosses/elites stay untouched.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "bear_swipe")
	# Marks the Bear proper: bear_swipe is shared with the Gargoyle and Harpy,
	# bear_fury with the Minotaur, Crystal Crab and Sky Wyvern.
	u.set_meta("bear", true)
	u.set_meta("mob_passive", "bear_fury")
	u.set_meta("passive_name", "Fury")
	u.set_meta("passive_desc", "Attack speed ramps with missing HP, up to +30% near death. Chip it and it rages.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_bear_normal(lvl: int = 1) -> VisualUnit:    return _create_bear(UnitBase.Element.NORMAL, lvl)
static func create_bear_fire(lvl: int = 1) -> VisualUnit:      return _create_bear(UnitBase.Element.FIRE, lvl)
static func create_bear_water(lvl: int = 1) -> VisualUnit:     return _create_bear(UnitBase.Element.WATER, lvl)
static func create_bear_earth(lvl: int = 1) -> VisualUnit:     return _create_bear(UnitBase.Element.EARTH, lvl)
static func create_bear_air(lvl: int = 1) -> VisualUnit:       return _create_bear(UnitBase.Element.AIR, lvl)
static func create_bear_lightning(lvl: int = 1) -> VisualUnit: return _create_bear(UnitBase.Element.LIGHTNING, lvl)

# ── Troll (ranged support — buffs attack speed) — 6 elemental variants ───────
# Brand new mob (2026-07-06). Its signature move (Enrage) targets the
# hardest-hitting ally in range (itself if nothing better is around, same
# heuristic as Pastor's Sermon) and boosts attack speed. Like the Bear, the
# RATIO of the buff scales with the Troll's own offensive affinity in its own
# element — the 10s duration itself is fixed, only the magnitude scales
# (2026-07-06 user request, explicit about that distinction).
const TROLL_ELEMENT_NAMES := {
	UnitBase.Element.NORMAL:    "Normal",
	UnitBase.Element.FIRE:      "Fire",
	UnitBase.Element.WATER:     "Water",
	UnitBase.Element.EARTH:     "Earth",
	UnitBase.Element.AIR:       "Air",
	UnitBase.Element.LIGHTNING: "Lightning",
}
const TROLL_SPRITE_FOLDERS := {
	UnitBase.Element.NORMAL:    "troll_normal",
	UnitBase.Element.FIRE:      "troll_fire",
	UnitBase.Element.WATER:     "troll_water",
	UnitBase.Element.EARTH:     "troll_earth",
	UnitBase.Element.AIR:       "troll_air",
	UnitBase.Element.LIGHTNING: "troll_lightning",
}

static func _create_troll(element: UnitBase.Element, lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "%s Troll" % TROLL_ELEMENT_NAMES[element]
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = element
	u.is_player_unit  = false
	u.max_hp          = 480
	u.current_hp      = 480
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 30
	u.magic_power     = 10
	u.resistance      = 15
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.62
	u.hp_regen        = 0.5
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 4
	u.gold_reward     = 22
	u.crystal_reward  = 1
	u.xp_reward       = 80
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", TROLL_SPRITE_FOLDERS[element])
	# (own-element affinity now comes from set_affinity_profile — 2026-07-16)
	u.skill_name = "Enrage"
	u.skill_damage_multiplier = 0.0   # utility skill, no direct damage
	u.skill_range = 6
	u.skill_cooldown_max = 5          # 10s buff / 5s CD — can keep 2 targets enraged at once
	u.skill_mana_cost = 0
	# Was printed as 35%, which is the pre-affinity BASE. Every Troll waves spawn
	# has 150 own-element offensive affinity, so the buff it actually delivers is
	# +87.5%. Numbers are staying as they are (user, 2026-09-18) — the description
	# is what was wrong, so it now prints the value the player actually receives.
	u.skill_description = "Boost a random ally's (or its own) attack speed by 87.5% for 10s. · 5s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool (~1.6 free Enrages
	# per fight at 480 HP). See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "troll_enrage")
	# Marks the Troll proper: troll_regen is shared with the Gargoyle and the
	# Ember Phoenix (which has its own ember readout).
	u.set_meta("troll", true)
	u.set_meta("mob_passive", "troll_regen")
	u.set_meta("passive_name", "Regeneration")
	var counters: Array = UnitBase.REGEN_COUNTERS[element]
	u.set_meta("passive_desc", "Regenerates 1.5%% max HP/s. A %s or %s hit disables regen for 2s." % [
		str(UnitBase.Element.keys()[counters[0]]).capitalize(),
		str(UnitBase.Element.keys()[counters[1]]).capitalize()])
	if lvl > 1: u.set_level(lvl)
	return u

static func create_troll_normal(lvl: int = 1) -> VisualUnit:    return _create_troll(UnitBase.Element.NORMAL, lvl)
static func create_troll_fire(lvl: int = 1) -> VisualUnit:      return _create_troll(UnitBase.Element.FIRE, lvl)
static func create_troll_water(lvl: int = 1) -> VisualUnit:     return _create_troll(UnitBase.Element.WATER, lvl)
static func create_troll_earth(lvl: int = 1) -> VisualUnit:     return _create_troll(UnitBase.Element.EARTH, lvl)
static func create_troll_air(lvl: int = 1) -> VisualUnit:       return _create_troll(UnitBase.Element.AIR, lvl)
static func create_troll_lightning(lvl: int = 1) -> VisualUnit: return _create_troll(UnitBase.Element.LIGHTNING, lvl)

# ── Wind-Up Bot (light melee striker) — 6 elemental variants ─────────────────
# Brand new mob (2026-07-07). Its signature move (Wind-Up Punch) is a hit +
# 1s stun, same shape as the Orc's Crushing Blow, but — per user request that
# every mob skill's damage stay tied to affinity — it scales with the bot's
# own elemental affinity like Bear's Rending Swipe and Troll's Enrage do,
# rather than being a flat multiplier the way the Orc's is.
const WINDUP_BOT_ELEMENT_NAMES := {
	UnitBase.Element.NORMAL:    "Normal",
	UnitBase.Element.FIRE:      "Fire",
	UnitBase.Element.WATER:     "Water",
	UnitBase.Element.EARTH:     "Earth",
	UnitBase.Element.AIR:       "Air",
	UnitBase.Element.LIGHTNING: "Lightning",
}
const WINDUP_BOT_SPRITE_FOLDERS := {
	UnitBase.Element.NORMAL:    "windup_bot_normal",
	UnitBase.Element.FIRE:      "windup_bot_fire",
	UnitBase.Element.WATER:     "windup_bot_water",
	UnitBase.Element.EARTH:     "windup_bot_earth",
	UnitBase.Element.AIR:       "windup_bot_air",
	UnitBase.Element.LIGHTNING: "windup_bot_lightning",
}

static func _create_windup_bot(element: UnitBase.Element, lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "%s Wind-Up Bot" % WINDUP_BOT_ELEMENT_NAMES[element]
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = element
	u.is_player_unit  = false
	u.max_hp          = 600
	u.current_hp      = 600
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 60
	u.magic_power     = 15
	u.resistance      = 11
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.85          # quick clockwork striker — faster than the Orc, lighter than the Bear
	u.hp_regen        = 0.3
	u.mana_regen      = 0.0
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 20
	u.crystal_reward  = 1
	u.xp_reward       = 85
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", WINDUP_BOT_SPRITE_FOLDERS[element])
	# (own-element affinity now comes from set_affinity_profile — 2026-07-16)
	u.skill_name = "Wind-Up Punch"
	u.skill_damage_multiplier = 1.5
	u.skill_range = 1
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Deal 150% ATK (scales with own elemental affinity), punch the target into the air and stun for 1.5s. · 6s CD"
	# This mob declares NO ultimate, but UnitBase defaults ultimate_charge_max to
	# 300 — so it was quietly charging one from damage dealt and taken, showing an
	# ultimate strip under its cooldown bar, and on full the manager's legacy
	# WARRIOR fallback re-ran _use_skill(): a second, unnamed Wind-Up Punch that
	# ignored the 6s cooldown. The arena probe missed it because ultimate_name is
	# empty, so it reported NO_KIT rather than looking at live behaviour.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "windup_punch")
	# Marks this unit as the Wind-Up Bot proper. The `windup_punch` key is SHARED
	# with the Minotaur's Gore Rush and the Storm Giant's Thunderclap, so the
	# knock-up, the 1.5s stun and the clockwork VFX hang off the UNIT, not the
	# key — those two keep their own 1.0s stun and their own visuals untouched.
	u.set_meta("windup_bot", true)
	u.set_meta("windup_stun", 1.5)
	u.set_meta("mob_passive", "windup_overclock")
	u.set_meta("passive_name", "Overclock")
	u.set_meta("passive_desc", "+5% attack speed every 3s of battle (max +50%). Slow to start, a DPS check if the fight drags.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_windup_bot_normal(lvl: int = 1) -> VisualUnit:    return _create_windup_bot(UnitBase.Element.NORMAL, lvl)
static func create_windup_bot_fire(lvl: int = 1) -> VisualUnit:      return _create_windup_bot(UnitBase.Element.FIRE, lvl)
static func create_windup_bot_water(lvl: int = 1) -> VisualUnit:     return _create_windup_bot(UnitBase.Element.WATER, lvl)
static func create_windup_bot_earth(lvl: int = 1) -> VisualUnit:     return _create_windup_bot(UnitBase.Element.EARTH, lvl)
static func create_windup_bot_air(lvl: int = 1) -> VisualUnit:       return _create_windup_bot(UnitBase.Element.AIR, lvl)
static func create_windup_bot_lightning(lvl: int = 1) -> VisualUnit: return _create_windup_bot(UnitBase.Element.LIGHTNING, lvl)

# ── Skeleton (fragile but hits hard, medium range) ────────────────────────────
static func create_skeleton(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Skeleton"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 110
	u.current_hp      = 110
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 28
	u.magic_power     = 8
	u.resistance      = 9           # brittle bones — low res
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.74
	u.hp_regen        = 0.55
	u.mana_regen      = 0.33
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 13
	u.crystal_reward  = 0
	u.xp_reward       = 32
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "skeleton")
	u.skill_name = "Bone Shield"
	u.skill_damage_multiplier = 0.0
	u.skill_range = 1
	u.skill_cooldown_max = 8
	u.skill_mana_cost = 0
	u.skill_description = "Shield self for 25% max HP. · 8s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool. Small here (~0.37
	# free casts at 110 HP) but cleared for consistency. See the Rat.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "skeleton_boneshield")
	# Rib-cage shield + the Undying reassembly beat. boneshield is shared with the
	# Stone Golem, Crystal Crab and Coral Husk, which keep their own looks.
	u.set_meta("skeleton", true)
	u.set_meta("mob_passive", "skeleton_undying")
	u.set_meta("passive_name", "Undying")
	u.set_meta("passive_desc", "The first time it would die, it reassembles once at 35% HP.")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Rat (fast, very low HP, weak hit — swarms in numbers) ────────────────────
static func create_rat(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Rat"
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 75
	u.current_hp      = 75
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 24
	u.magic_power     = 4
	u.resistance      = 8
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 1.06        # fast attacker
	u.hp_regen        = 0.25
	u.mana_regen      = 0.17
	u.movement_speed  = 5           # fastest basic enemy
	u.attack_range    = 1
	u.gold_reward     = 10
	u.crystal_reward  = 0
	u.xp_reward       = 22
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "rat")
	u.skill_name = "Infected Bite"
	u.skill_damage_multiplier = 1.1
	u.skill_range = 1
	u.skill_cooldown_max = 5
	u.skill_mana_cost = 0
	u.skill_description = "Deal 110% ATK and infect: 35% ATK/s disease for 3s. · 5s CD"
	# Declares no ultimate, but UnitBase defaults ultimate_charge_max to 300, so
	# it quietly charged one (full value on damage TAKEN) and on full re-ran
	# _use_skill via _use_ultimate's fallback — a free Infected Bite ignoring the
	# 5s cooldown, plus an ultimate strip under its bar. Measured 2026-09-17: at
	# 75 max HP the Rat earns ~0.2 of these per fight, so clearing it is
	# effectively balance-neutral here. 68 other enemies still have this; the
	# tanky ones (Khagan ~13/fight, The Architect ~30) are a deliberate balance
	# decision and are being left alone until that pass.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "rat_bite")
	# The shared rat_bite key is also the Hellhound's fire and the Sky Wyvern's
	# venom. Flavour lives on the UNIT so each reads as its own fiction while the
	# numbers stay identical.
	u.set_meta("dot_flavor", "disease")
	u.set_meta("mob_passive", "rat_infest")
	u.set_meta("passive_name", "Infestation")
	u.set_meta("passive_desc", "With 2+ other Rats within 2 tiles: +15% damage and disease bites last 50% longer.")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Hill Giant (2×2 elite — spawns in rounds 5/15/25, see WaveScaler) ────────
static func create_hill_giant(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Hill Giant"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	# Elite-sized growth (2026-07-12): the shared hero-class tables (+25 hp/lvl)
	# are noise on a 2400-hp body — elite_level() leveling did nothing real.
	# res stays +1/lvl everywhere: resistance is a FLAT subtraction, and stacking
	# it makes low-damage teams hit for 1 forever (stall risk), see UnitBase.
	u.growth_base     = {"hp": 260, "mana": 5, "atk": 5, "magic": 1, "res": 1, "aspd": 0.01, "hpregen": 0.1, "manaregen": 0.05}
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.cell_size       = 2          # occupies a 2×2 area
	# 2026-07-15 rebalance: elites own ONE fixed round now (G = round 5, see
	# WaveScaler.ELITE_BY_ROUND) so this statline is tuned against a ~4-hero
	# level-3 team. Also compensates the collect_units dedup fix — the giant
	# previously fought with 4× ticked cooldowns/regen and was tuned to that.
	#
	# 2026-08-04 (BALANCE_PLAN.md §1.6): 3800 → 3600. Arena sweep showed round 5
	# was a ROSTER-SIZE check, not a difficulty check — at 3800 HP the win rate
	# was 0% with 2 heroes, ~55% with 3, 100% with 4. The statline above says it's
	# tuned for 4 heroes, but Balance's economy spec delivers the 3rd hero around
	# wave 5 and the 4th by wave 10 — so the fight was balanced against a roster
	# the player provably does not have yet, and coin-drop RNG decided the run
	# before it started. 45% of the user's 33 logged runs ended here.
	# Retuned to its ACTUAL audience (3 heroes): ~85% at 3, still lethal at 2.
	u.max_hp          = 3500
	u.current_hp      = 3500
	u.max_mana        = 100
	u.current_mana    = 100
	# 150 → 115 (2026-07-16): the affinity rework dropped off-element defense
	# to 68 (×1.32 taken), which turned the giant's 150 atk into an 8/8 wipe
	# of average round-5 comps. 115 restores a real-but-beatable spike.
	u.attack_damage   = 110
	u.magic_power     = 9
	u.resistance      = 20
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.5
	u.hp_regen        = 0.55
	u.mana_regen      = 0.5
	u.movement_speed  = 2          # arena sims: at move 1 ranged comps kite it
								   # to death without taking a single hit
	# Melee only (2026-07-22): was 2 (ranged, fired a projectile). Now that
	# the giant has a real club-swing attack sheet it should be adjacent-only —
	# 1 is "next tile over" in this engine's Chebyshev grid distance (0 would
	# mean same-cell, i.e. never in range). unit_base.attack() only spawns a
	# projectile when attack_range > 1, so dropping to 1 removes it for free.
	u.attack_range    = 1
	u.gold_reward     = 0
	u.crystal_reward  = 2
	u.xp_reward       = 200
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "hill_giant")
	u.set_meta("mob_skill", "hill_giant_smash")
	u.skill_name      = "Boulder Smash"
	u.skill_damage_multiplier = 2.0
	u.skill_range     = 1
	u.skill_cooldown_max = 4
	u.skill_description = "Smash every adjacent enemy for 200% ATK. · 4s CD"
	u.ultimate_charge_max = 0     # no ult
	u.is_elite        = true
	u.tenacity        = TENACITY_ELITE
	if lvl > 1: u.set_level(lvl)
	return u

# ── The Triarch (round 30 final boss — cycles through every attack type) ─────
# Phase 1 (Melee) is this unit's baseline form, built directly in create_triarch.
# Phases 2/3 are reached by "dying" at 0 HP while a phase remains — see
# advance_triarch_phase(), hooked into VisualUnit.die(). Each transform:
#   - re-derives stats as a multiplier on the PHASE-1 (already level-scaled)
#     baseline snapshotted in the "triarch_base_stats" meta, so boss_level
#     scaling (see WaveScaler.boss_level) carries through every phase
#   - swaps unit_class, which changes which skill effect _use_skill() dispatches
#     to AND which LPC sprite folder the unit renders as (warrior/archer/
#     black_mage all have generated sheets) — one field drives combat behavior,
#     UI class label, and silhouette all at once
#   - fully heals the new phase (this IS the "fresh health bar" per phase)
#   - clears every status-effect/proc field so the transform is a clean slate
# Only entries [1] and [2] are read by advance_triarch_phase (index 0 documents
# the melee baseline for reference; its real values live in create_triarch).
const TRIARCH_PHASES: Array[Dictionary] = [
	{
		"name": "Melee Form", "unit_class": UnitBase.UnitClass.WARRIOR,
		"hp_mult": 1.0, "mana_mult": 1.0, "atk_mult": 1.0, "magic_mult": 1.0, "res_mult": 1.0,
		"aspd_mult": 1.0, "hpregen_mult": 1.0, "manaregen_mult": 1.0,
		"move": 3, "range": 1,
		"skill_name": "Cleaving Strike", "skill_dmg": 1.3, "skill_range": 1, "skill_cd": 3, "skill_mana": 0,
	},
	{
		"name": "Ranger Form", "unit_class": UnitBase.UnitClass.RANGER,
		"hp_mult": 1.0, "mana_mult": 1.2, "atk_mult": 0.85, "magic_mult": 1.0, "res_mult": 0.85,
		"aspd_mult": 1.15, "hpregen_mult": 1.0, "manaregen_mult": 1.3,
		"move": 4, "range": 5,
		"skill_name": "Piercing Volley", "skill_dmg": 1.0, "skill_range": 6, "skill_cd": 4, "skill_mana": 0,
	},
	{
		"name": "Arcane Form", "unit_class": UnitBase.UnitClass.BLACK_MAGE,
		"hp_mult": 0.85, "mana_mult": 2.0, "atk_mult": 0.4, "magic_mult": 2.4, "res_mult": 0.9,
		"aspd_mult": 0.85, "hpregen_mult": 1.0, "manaregen_mult": 1.8,
		"move": 2, "range": 5,
		"skill_name": "Meteor Storm", "skill_dmg": 2.2, "skill_range": 6, "skill_cd": 5, "skill_mana": 25,
	},
]

static func create_triarch(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "The Triarch — Melee Form"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	# Boss-sized growth (2026-07-12) — see the Hill Giant note. boss_level(20)=12
	# rides this; phases 2/3 multiply the leveled snapshot so it carries through.
	# atk/aspd carry the threat, not HP: sims showed a bigger HP pool just makes
	# a longer grind that sustain comps heal through — the boss has to be able
	# to kill heroes faster than the team can patch them up.
	u.growth_base     = {"hp": 420, "mana": 8, "atk": 9, "magic": 4, "res": 1, "aspd": 0.02, "hpregen": 0.15, "manaregen": 0.08}
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 2200
	u.current_hp      = 2200
	u.max_mana        = 150
	u.current_mana    = 150
	u.attack_damage   = 40
	u.magic_power     = 16
	u.resistance      = 25
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.62
	u.hp_regen        = 0.6
	u.mana_regen      = 1.0
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 100
	u.crystal_reward  = 3
	u.xp_reward       = 350
	u.sprite_variant  = 0
	u.is_boss         = true
	u.tenacity        = TENACITY_BOSS

	u.skill_name = "Cleaving Strike"
	u.skill_description = "Heavy melee blow for 130% ATK. · 3s CD"
	u.skill_damage_multiplier = 1.3
	u.skill_range = 1
	u.skill_cooldown_max = 3
	u.skill_mana_cost = 0

	if lvl > 1: u.set_level(lvl)

	# NOTE: the phase-1 baseline snapshot (used to derive phases 2/3) is taken
	# LAZILY on the first phase transition, not here — main_game.gd's spawn path
	# applies boss-tier leveling via an EXTERNAL unit.set_level(lvl) call *after*
	# this factory function returns (matching the existing Hill Giant pattern),
	# so snapshotting here would capture pre-level stats. By the time the boss
	# ever reaches 0 HP the external leveling has long since happened, so the
	# lazy snapshot in advance_triarch_phase() always sees the real scaled stats.
	u.set_meta("triarch_phase", 1)
	u.set_meta("passive_name", "Three Forms")
	u.set_meta("passive_desc", "Each time it falls it rises again at full health in a new form: Melee, then Ranger, then Arcane.")
	return u

# Called from VisualUnit.die() when a Triarch's HP hits 0. Transforms it into
# the next phase in place (no death, no removal from the fight) and returns
# true, or returns false once the final phase has actually been defeated so
# the normal death flow proceeds.
static func advance_triarch_phase(unit: VisualUnit) -> bool:
	var phase: int = int(unit.get_meta("triarch_phase", 1))
	if phase >= TRIARCH_PHASES.size():
		return false
	var next_phase: int = phase + 1
	var cfg: Dictionary = TRIARCH_PHASES[next_phase - 1]

	# Lazily snapshot the phase-1 baseline the first time we transform — see the
	# note in create_triarch() for why this can't be captured at creation time.
	if not unit.has_meta("triarch_base_stats"):
		unit.set_meta("triarch_base_stats", {
			"hp": unit.max_hp, "mana": unit.max_mana, "atk": unit.attack_damage,
			"magic": unit.magic_power, "res": unit.resistance,
			"aspd": unit.attack_speed, "hpregen": unit.hp_regen, "manaregen": unit.mana_regen,
		})
	var base: Dictionary = unit.get_meta("triarch_base_stats", {})

	unit.unit_class = cfg["unit_class"]
	unit.max_hp        = maxi(1, int(round(float(base.get("hp", unit.max_hp)) * float(cfg["hp_mult"]))))
	unit.current_hp    = unit.max_hp
	unit.max_mana      = maxi(0, int(round(float(base.get("mana", unit.max_mana)) * float(cfg["mana_mult"]))))
	unit.current_mana  = unit.max_mana
	unit.attack_damage = maxi(1, int(round(float(base.get("atk", unit.attack_damage)) * float(cfg["atk_mult"]))))
	unit.magic_power   = maxi(0, int(round(float(base.get("magic", unit.magic_power)) * float(cfg["magic_mult"]))))
	unit.resistance    = maxi(0, int(round(float(base.get("res", unit.resistance)) * float(cfg["res_mult"]))))
	unit.attack_speed  = float(base.get("aspd", unit.attack_speed)) * float(cfg["aspd_mult"])
	unit.hp_regen      = float(base.get("hpregen", unit.hp_regen)) * float(cfg["hpregen_mult"])
	unit.mana_regen    = float(base.get("manaregen", unit.mana_regen)) * float(cfg["manaregen_mult"])
	unit.movement_speed = int(cfg["move"])
	unit.attack_range   = int(cfg["range"])

	unit.skill_name = cfg["skill_name"]
	unit.skill_damage_multiplier = float(cfg["skill_dmg"])
	unit.skill_range = int(cfg["skill_range"])
	unit.skill_cooldown_max = int(cfg["skill_cd"])
	unit.skill_mana_cost = int(cfg["skill_mana"])
	unit.skill_cd_time = 0.0   # the new form opens with an immediate cast

	# Clean slate: clear shields/cooldowns/status effects so nothing carries
	# across the transformation.
	unit.current_shield = 0
	unit.attack_cooldown = 0.0
	unit.stun_time = 0.0
	unit.burn_time = 0.0; unit.burn_dps = 0.0; unit.burn_accum = 0.0; unit.burn_source = null
	unit.bleed_time = 0.0; unit.bleed_dps = 0.0; unit.bleed_accum = 0.0; unit.bleed_source = null
	unit.slow_time = 0.0; unit.slow_pct = 0.0
	unit.root_time = 0.0
	unit.taunt_time = 0.0; unit.taunt_source = null
	unit.untargetable_time = 0.0
	unit.outgoing_dmg_mult = 1.0; unit.outgoing_dmg_time = 0.0
	unit.bonus_aspd_pct = 0.0; unit.bonus_aspd_time = 0.0
	unit.weakened_pct = 0.0; unit.weakened_time = 0.0
	unit.rapid_fire_time = 0.0
	unit.overdrive_time = 0.0
	unit.frenzy_active = false

	unit.unit_name = "The Triarch — %s" % cfg["name"]
	unit.set_meta("triarch_phase", next_phase)

	if unit.health_bar:
		unit.health_bar.update_hp(unit.current_hp, unit.max_hp)
		unit.health_bar.update_mp(unit.current_mana, unit.max_mana)
		unit.health_bar.update_ult(0, unit.ultimate_charge_max)
		unit.health_bar.update_shield(0, unit.max_hp)
	if unit.has_method("rebuild_sprite"):
		unit.rebuild_sprite()
	return true

# ── Stat Stealer (elite — spawns in rounds 5/15/25, see WaveScaler) ──────────
# Active: shields itself for 25% of its own max HP (spends mana — see
# AutoBattleManager._use_skill). Ultimate: drains a random stat off its target
# over 10 seconds (10%/sec — see AutoBattleManager._stat_steal_drain), holding
# the stolen amount on itself until it dies, at which point the theft reverts.
static func create_stat_stealer(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Stat Stealer"
	u.unit_class      = UnitBase.UnitClass.STAT_STEALER
	# Elite-sized growth (2026-07-12) — see the Hill Giant note.
	u.growth_base     = {"hp": 150, "mana": 15, "atk": 3, "magic": 3, "res": 1, "aspd": 0.01, "hpregen": 0.1, "manaregen": 0.1}
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	# 2026-07-15 rebalance: SS owns round 25 (WaveScaler.ELITE_BY_ROUND) —
	# tuned against a ~9-hero level-12 team, sitting just under the wave 24-26
	# no-upgrade wall. Late-game mults (round 25: ~2.5× HP, ~2.05× dmg) apply
	# on top of level 16 growth at spawn.
	u.max_hp          = 2600
	u.current_hp      = 2600
	u.max_mana        = 250
	u.current_mana    = 250
	u.attack_damage   = 80
	u.magic_power     = 45
	u.resistance      = 25
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 1.0
	u.hp_regen        = 0.6
	u.mana_regen      = 1.5
	u.movement_speed  = 3
	u.attack_range    = 2
	u.gold_reward     = 50
	u.crystal_reward  = 2
	u.xp_reward       = 150
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "stat_stealer")
	u.is_elite        = true
	u.tenacity        = TENACITY_ELITE

	u.skill_name = "Siphon Ward"
	u.skill_description = "Shield itself for 25% of its max HP. · 6s CD"
	u.skill_damage_multiplier = 0.0   # utility skill, no direct damage
	u.skill_range = 0
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 40

	u.ultimate_name = "Essence Drain"
	u.ultimate_damage_mult = 0.0      # utility ultimate, no direct damage
	u.ultimate_range = 6
	u.ultimate_charge_max = 350
	u.set_meta("ultimate_desc", "Drains a random stat off its target over 10s (up to %d%% of it) and keeps it until it dies." \
			% roundi(AutoBattleManager.DRAIN_MAX_STEAL_PCT * 100.0))

	if lvl > 1: u.set_level(lvl)
	return u

# ── Ant Hill (elite — spawns in rounds 5/15/25, see WaveScaler) ──────────────
# A stationary 2×2 spawner: weak on its own, but periodically spawns Ants (see
# AutoBattleManager._tick_passive's ANT_HILL case + _spawn_ant) that stack a
# permanent +1-per-bite vulnerability on whoever they hit — a DPS check. Kill
# the hill fast to shut off the swarm before the stacks get out of hand.
static func create_ant_hill(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Ant Hill"
	u.unit_class      = UnitBase.UnitClass.ANT_HILL
	# Elite-sized growth (2026-07-12) — see the Hill Giant note. HP/regen only:
	# the hill's threat is its ant swarm, not its own damage.
	u.growth_base     = {"hp": 200, "mana": 0, "atk": 10, "magic": 0, "res": 1, "aspd": 0.0, "hpregen": 0.2, "manaregen": 0.0}
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.cell_size       = 2          # a wide mound, not a single-tile creature
	# 2026-07-15 rebalance: AH owns round 15 (WaveScaler.ELITE_BY_ROUND) — bulk
	# tuned against a ~7-hero level-8 team so the DPS check is real; the ant
	# statline itself lives in UnitFactory (ANT row), tuned for the same round.
	u.max_hp          = 3400
	u.current_hp      = 3400
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 8          # minor — the ants are the real threat
	u.magic_power     = 0
	u.resistance      = 29         # tanky: rewards focusing it down, punishes ignoring it
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.3
	u.hp_regen        = 1.2
	u.mana_regen      = 0.0
	u.movement_speed  = 0          # stationary — it's a hill, not a creature
	u.attack_range    = 0
	u.gold_reward     = 45
	u.crystal_reward  = 2
	u.xp_reward       = 130
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "ant_hill")
	u.set_meta("passive_name", "Swarm")
	u.set_meta("passive_desc", "Spawns an Ant every %.1fs (up to %d alive). Every Ant bite makes every Ant hit harder, with no cap. Kill the hill fast." % [
		Balance.ANT_HILL_SPAWN_INTERVAL, Balance.ANT_HILL_MAX_ANTS])
	u.is_elite        = true
	u.tenacity        = TENACITY_ELITE
	u.ultimate_charge_max = 0     # no skill/ultimate — purely the passive spawn behavior

	if lvl > 1: u.set_level(lvl)
	return u

# ── Gale Warden (elite — owns round 15, the AIR decade) ─────────────────────
# The Air decade's mini-boss (2026-07-27 elemental-elite pass, took round 15 over
# from the Ant Hill, which moved out to round 65). A skirmisher, not an anchor:
# it is not especially tanky, but it is genuinely HARD TO HIT — a flat evasion
# chance reusing the existing "Evasion" equipment_passive (see UnitBase.take_damage,
# which already rolls that dict for every non-true hit), so no new dodge plumbing.
# Signature: "Cyclone Shove" (mob_skill) — damage plus a physical SHOVE that drags
# the victim a tile further from the Warden, breaking the player's carefully
# arranged formation. It's the first elite whose answer is positioning rather
# than raw damage, which is what the Air decade should be teaching.
const GALE_WARDEN_EVASION := 0.30   # 30% of direct hits whiff entirely
static func create_gale_warden(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Gale Warden"
	# Piggybacks MONK for stats/sprite the same way every basic mob piggybacks a
	# hero class — the real behaviour dispatches off the mob_skill meta below, so
	# no MONK hero passive can leak in (see AutoBattleManager._use_skill).
	u.unit_class      = UnitBase.UnitClass.MONK
	# Elite-sized growth — same shape as the Stat Stealer's (see its note).
	u.growth_base     = {"hp": 150, "mana": 15, "atk": 3, "magic": 3, "res": 1, "aspd": 0.01, "hpregen": 0.1, "manaregen": 0.1}
	u.current_element = UnitBase.Element.AIR
	u.is_player_unit  = false
	# Tuned against the same ~7-hero level-8 team the Ant Hill was tuned for at
	# round 15, measured in the arena against the Hill's own round-15 encounter.
	# First pass (2400 hp / 18 res / 25% evasion) died in ~16s against the Hill's
	# ~68s: a lone 1×1 body simply cannot hold a round the way a 2×2 endless
	# spawner does, because the Hill's real HP pool is its ant stream. Raised bulk
	# to close most of that gap while keeping the dodge-not-soak identity — armor
	# stays deliberately low and the staying power comes from evasion instead.
	u.max_hp          = 7500
	u.current_hp      = 7500
	u.max_mana        = 200
	u.current_mana    = 200
	u.attack_damage   = 85
	u.magic_power     = 30
	u.resistance      = 34         # low armor — it dodges instead of soaking
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 1.5
	u.hp_regen        = 0.5
	u.mana_regen      = 1.5
	u.movement_speed  = 5          # fast — it closes and repositions
	u.attack_range    = 1
	u.gold_reward     = 45
	u.crystal_reward  = 2
	u.xp_reward       = 130
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "gale_warden")
	u.is_elite        = true
	u.tenacity        = TENACITY_ELITE
	# Reuses the player-equipment evasion roll — enemies read the same dict.
	u.equipment_passives["Evasion"] = GALE_WARDEN_EVASION
	u.set_meta("passive_name", "Windborne")
	u.set_meta("passive_desc", "%d%% of direct hits against it miss entirely." % roundi(GALE_WARDEN_EVASION * 100.0))

	u.set_meta("mob_skill", "gale_shove")
	u.skill_name = "Cyclone Shove"
	u.skill_description = "Deal 140% ATK and physically shove the target one tile further away. · 7s CD"
	u.skill_damage_multiplier = 1.4
	u.skill_range = 1
	u.skill_cooldown_max = 7
	u.skill_mana_cost = 45

	u.ultimate_charge_max = 0     # no ultimate — the skill IS the signature

	if lvl > 1: u.set_level(lvl)
	return u

# ── Tidecaller (elite — owns round 25, the WATER decade) ────────────────────
# The Water decade's mini-boss (2026-07-27 elemental-elite pass, took round 25
# over from the Stat Stealer, which moved out to round 75). Deliberately the
# first elite that is NOT the biggest threat on the board: its own damage is
# minor, but it regenerates its whole escort ("Tide Font" passive) and hard-
# shields whoever is worst hurt ("Tidal Ward" skill). Ignore it and the wave
# stops dying; focus it and the wave folds. That target-priority decision IS
# the encounter — the same lesson the Water decade's shaman-heavy waves lean on.
static func create_tidecaller(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Tidecaller"
	# Piggybacks WHITE_MAGE for stats/sprite; behaviour dispatches off the
	# mob_passive/mob_skill metas, so no hero arm can leak in.
	u.unit_class      = UnitBase.UnitClass.WHITE_MAGE
	u.growth_base     = {"hp": 150, "mana": 15, "atk": 2, "magic": 4, "res": 1, "aspd": 0.01, "hpregen": 0.1, "manaregen": 0.1}
	u.current_element = UnitBase.Element.WATER
	u.is_player_unit  = false
	# Tuned against the ~9-hero level-12 team the Stat Stealer was measured with
	# at round 25 (its encounter ran ~67s; waves 24/26 run ~44s/~77s). Bulk sits
	# high for a support because the whole encounter is "can you reach it" — but
	# its attack_damage is deliberately small so it never doubles as a bruiser.
	u.max_hp          = 5200
	u.current_hp      = 5200
	u.max_mana        = 260
	u.current_mana    = 260
	u.attack_damage   = 30         # token — the support kit is the threat
	u.magic_power     = 70
	u.resistance      = 30
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.9
	u.hp_regen        = 1.0
	u.mana_regen      = 2.0
	u.movement_speed  = 3
	u.attack_range    = 4          # hangs back behind its escort, like a shaman
	u.gold_reward     = 50
	u.crystal_reward  = 2
	u.xp_reward       = 150
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "tidecaller")
	u.is_elite        = true
	u.tenacity        = TENACITY_ELITE

	u.set_meta("mob_passive", "tide_font")
	u.set_meta("passive_name", "Tide Font")
	u.set_meta("passive_desc", "Allies within %d tiles regenerate %.1f%% of their max HP per second." % [
		int(AutoBattleManager.TIDE_FONT_RANGE), AutoBattleManager.TIDE_FONT_PCT_PER_SEC * 100.0])
	u.set_meta("mob_skill", "tide_ward")
	u.skill_name = "Tidal Ward"
	u.skill_description = "Shield the most-wounded ally in range (itself included) for 20% of their max HP. · 7s CD"
	u.skill_damage_multiplier = 0.0   # utility skill, no direct damage
	u.skill_range = 5
	u.skill_cooldown_max = 7
	u.skill_mana_cost = 55

	u.ultimate_charge_max = 0     # no ultimate — passive + skill are the kit

	if lvl > 1: u.set_level(lvl)
	return u

# ── Terracotta Colossus (elite — owns round 35, the EARTH decade) ───────────
# The Earth decade's mini-boss (2026-07-27 elemental-elite pass). A 2×2 wall
# that HARDENS as the fight drags on: "Set in Stone" adds armor every second
# (see AutoBattleManager's terracotta_harden passive), so every second you spend
# not killing it makes it permanently harder to kill. That's the Earth decade's
# burst check — the answer is front-loaded damage, not a long grind.
# The ramp is capped (TERRACOTTA_ARMOR_CAP) rather than unbounded: armor uses the
# diminishing-returns curve so it can never reach immunity, but an uncapped ramp
# still drives fights toward the documented high-round stall problem.
static func create_terracotta_colossus(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Terracotta Colossus"
	u.unit_class      = UnitBase.UnitClass.WARRIOR   # stats/sprite host; see the Gale Warden note
	u.growth_base     = {"hp": 200, "mana": 0, "atk": 6, "magic": 0, "res": 2, "aspd": 0.0, "hpregen": 0.15, "manaregen": 0.0}
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.cell_size       = 2          # a 2×2 wall — the decade's anchor silhouette
	# Tuned against a ~10-hero level-20 team, the same fixture waves 34/36 were
	# measured with (~52s / ~50s each).
	u.max_hp          = 9000
	u.current_hp      = 9000
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 120
	u.magic_power     = 0
	u.resistance      = 30         # STARTS ordinary — the passive is what makes it a wall
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.7        # slow, heavy swings
	u.hp_regen        = 1.0
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 55
	u.crystal_reward  = 2
	u.xp_reward       = 170
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "terracotta_colossus")
	u.is_elite        = true
	u.tenacity        = TENACITY_ELITE

	u.set_meta("mob_passive", "terracotta_harden")
	u.set_meta("passive_name", "Set in Stone")
	u.set_meta("passive_desc", "Gains +%d armor every second it lives, up to +%d. Kill it fast." % [
		int(AutoBattleManager.TERRACOTTA_ARMOR_PER_SEC), int(AutoBattleManager.TERRACOTTA_ARMOR_CAP)])
	u.ultimate_charge_max = 0     # no skill/ultimate — the hardening passive IS the kit

	if lvl > 1: u.set_level(lvl)
	return u

# ── Magma Heart (elite — owns round 45, the FIRE decade) ────────────────────
# The Fire decade's mini-boss (2026-07-27 elemental-elite pass). Stationary and
# harmless in melee — it has no attack at all. Its entire threat is "Eruption":
# every few seconds it burns the ENTIRE enemy team at once, and each pulse burns
# hotter than the last (see AutoBattleManager's magma_pulse passive). There is no
# positioning answer and nothing to dodge — the only counterplay is killing it
# before the pulses outscale your healing. That makes it the decade's pure race
# check, and it's why the escalation is capped: an unbounded ramp would stop
# being a race and start being a timer nobody can beat.
static func create_magma_heart(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Magma Heart"
	u.unit_class      = UnitBase.UnitClass.BLACK_MAGE   # stats/sprite host; see the Gale Warden note
	u.growth_base     = {"hp": 220, "mana": 0, "atk": 0, "magic": 6, "res": 2, "aspd": 0.0, "hpregen": 0.15, "manaregen": 0.0}
	u.current_element = UnitBase.Element.FIRE
	u.is_player_unit  = false
	u.cell_size       = 2          # a 2×2 vent in the ground, not a creature
	# Tuned against the ~10-hero level-30 fixture waves 44/46 were measured with.
	u.max_hp          = 11000      # tanky: the whole encounter is "can you kill it in time"
	u.current_hp      = 11000
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 0          # no attack whatsoever — the pulse is the kit
	u.magic_power     = 150        # scales the burn (see MAGMA_PULSE_* knobs)
	u.resistance      = 40
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.1
	u.hp_regen        = 1.5
	u.mana_regen      = 0.0
	u.movement_speed  = 0          # stationary — it's a vent, not a creature (cf. Ant Hill)
	u.attack_range    = 0
	u.gold_reward     = 60
	u.crystal_reward  = 3
	u.xp_reward       = 190
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "magma_heart")
	u.is_elite        = true
	u.tenacity        = TENACITY_ELITE

	u.set_meta("mob_passive", "magma_pulse")
	u.set_meta("passive_name", "Eruption")
	u.set_meta("passive_desc", "Every %ds it burns your whole team, each pulse hotter than the last (+%d%% MAG burn per pulse, up to %d pulses). It has no attack." % [
		int(AutoBattleManager.MAGMA_PULSE_INTERVAL), roundi(AutoBattleManager.MAGMA_PULSE_DPS_PCT * 100.0),
		AutoBattleManager.MAGMA_PULSE_MAX_STACKS])
	u.ultimate_charge_max = 0     # no skill/ultimate — the pulse passive IS the kit

	if lvl > 1: u.set_level(lvl)
	return u

# ── Tempest Conduit (elite — owns round 55, the LIGHTNING decade) ───────────
# The Lightning decade's mini-boss (2026-07-27 elemental-elite pass). Its
# "Chain Discharge" strikes one hero and then arcs outward to every hero packed
# near the one before it — so the damage it does is a direct function of how
# tightly the player's formation is bunched. Spread out and it's an ordinary
# bruiser; clump up (which every other wave rewards, since clumping protects
# your backline) and it hits the whole team at once. It's the only elite whose
# difficulty the player sets themselves, at placement time, before the fight.
static func create_tempest_conduit(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Tempest Conduit"
	u.unit_class      = UnitBase.UnitClass.BLACK_MAGE   # stats/sprite host; see the Gale Warden note
	u.growth_base     = {"hp": 170, "mana": 15, "atk": 4, "magic": 6, "res": 2, "aspd": 0.01, "hpregen": 0.1, "manaregen": 0.15}
	u.current_element = UnitBase.Element.LIGHTNING
	u.is_player_unit  = false
	# Tuned against the ~10-hero level-36 fixture used for waves 54/56.
	u.max_hp          = 12000
	u.current_hp      = 12000
	u.max_mana        = 300
	u.current_mana    = 300
	u.attack_damage   = 150
	u.magic_power     = 190        # scales the arc (see TEMPEST_ARC_* knobs)
	u.resistance      = 38
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 1.1
	u.hp_regen        = 1.2
	u.mana_regen      = 2.5
	u.movement_speed  = 4
	u.attack_range    = 3
	u.gold_reward     = 60
	u.crystal_reward  = 3
	u.xp_reward       = 200
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "tempest_conduit")
	u.is_elite        = true
	u.tenacity        = TENACITY_ELITE

	u.set_meta("mob_skill", "tempest_arc")
	u.skill_name = "Chain Discharge"
	u.skill_description = "Lightning arcs hero to hero, up to 5 links, dealing 100% MAG and losing 25% per jump. · 6s CD"
	u.skill_damage_multiplier = 1.0
	u.skill_range = 6
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 60

	u.ultimate_charge_max = 0     # no ultimate — the chain IS the signature

	if lvl > 1: u.set_level(lvl)
	return u

# ── Mirrorplate Warden (elite — owns round 85, mixed endgame) ───────────────
# 2026-07-27 elemental-elite pass. "Mirrorplate": a flat share of every hit it
# takes is thrown straight back at whoever threw it. The counterplay is spread
# damage instead of one oversized carry dumping everything into it — hence the
# overkill check. Crucially the reflect can NEVER kill (see
# AutoBattleManager.propagate_damage_links, which clamps it to leave the attacker
# at 1 HP): losing your carry to your own attack with no way to see it coming is
# exactly the agency-removing feel-bad this project has ruled out for bosses.
static func create_mirrorplate_warden(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Mirrorplate Warden"
	u.unit_class      = UnitBase.UnitClass.WARRIOR   # stats/sprite host; see the Gale Warden note
	u.growth_base     = {"hp": 210, "mana": 0, "atk": 5, "magic": 0, "res": 2, "aspd": 0.0, "hpregen": 0.15, "manaregen": 0.0}
	u.current_element = UnitBase.Element.NORMAL   # mixed endgame — no decade to match
	u.is_player_unit  = false
	u.cell_size       = 2
	# 26000/260 → 20000/185 (2026-07-27): with the reflect cap settled, the round
	# still lost while its neighbours 84/86 won 3/3 with the same team. Elite
	# formations field FEWER bodies than a normal wave (7 vs 9), so the power sits
	# concentrated in this one 2×2 — which the team has to stand next to, and
	# which reflects while they do. Trimming the body is what actually moved it.
	u.max_hp          = 20000
	u.current_hp      = 20000
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 185
	u.magic_power     = 0
	u.resistance      = 55
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.8
	u.hp_regen        = 2.0
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 70
	u.crystal_reward  = 3
	u.xp_reward       = 240
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "mirrorplate_warden")
	u.is_elite        = true
	u.tenacity        = TENACITY_ELITE
	# Read by AutoBattleManager.propagate_damage_links. A meta rather than a real
	# field so no new UnitBase state has to be reset in _init_unit_timers.
	# 0.25 → 0.15 (2026-07-27 tuning): reflect scales off the PLAYER's damage, so
	# unlike a flat statline it gets harsher the stronger the team gets. At 25% a
	# level-55 arena team lost round 85 three times out of three while the
	# strictly-bigger round-95 elite was winnable — the reflect, not the body, was
	# doing the killing. 15% keeps it a real overkill tax without out-scaling.
	u.set_meta("mob_reflect", 0.15)
	u.set_meta("passive_name", "Mirrorplate")
	u.set_meta("passive_desc", "Throws 15%% of every hit it takes back at the attacker (at most %.1f%% of the attacker's max HP per hit). The reflect can never kill." \
			% (AutoBattleManager.MIRROR_REFLECT_MAX_HP_PCT * 100.0))
	u.ultimate_charge_max = 0     # no skill/ultimate — the reflect IS the kit

	if lvl > 1: u.set_level(lvl)
	return u

# ── Aspect Devourer (elite — owns round 95, the capstone before wave 100) ────
# 2026-07-27 elemental-elite pass. The last encounter before the final boss, and
# a deliberate exam on the system the whole run has been teaching: every
# ASPECT_CYCLE_INTERVAL seconds it DEVOURS a new element, swapping current_element
# and re-deriving its affinity profile with it (see the aspect_devour passive).
# A mono-element team watches its damage swing between strong and awful on a
# timer it doesn't control; a team carrying mixed damage types barely notices.
# The swap is announced in the action log so it always reads as telegraphed
# rather than random.
static func create_aspect_devourer(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Aspect Devourer"
	u.unit_class      = UnitBase.UnitClass.BLACK_MAGE   # stats/sprite host; see the Gale Warden note
	u.growth_base     = {"hp": 200, "mana": 15, "atk": 5, "magic": 7, "res": 2, "aspd": 0.01, "hpregen": 0.15, "manaregen": 0.15}
	u.current_element = UnitBase.Element.NORMAL   # cycles from here — see the passive
	u.is_player_unit  = false
	u.cell_size       = 2
	u.max_hp          = 30000
	u.current_hp      = 30000
	u.max_mana        = 320
	u.current_mana    = 320
	u.attack_damage   = 280
	u.magic_power     = 300
	u.resistance      = 55
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 1.0
	u.hp_regen        = 2.0
	u.mana_regen      = 2.0
	u.movement_speed  = 3
	u.attack_range    = 2
	u.gold_reward     = 80
	u.crystal_reward  = 4
	u.xp_reward       = 280
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "aspect_devourer")
	u.is_elite        = true
	u.tenacity        = TENACITY_ELITE

	u.set_meta("mob_passive", "aspect_devour")
	u.set_meta("passive_name", "Devour Aspect")
	u.set_meta("passive_desc", "Every %ds it devours a new element and becomes it, changing what hurts it. Mixed damage types handle it best." % int(AutoBattleManager.ASPECT_CYCLE_INTERVAL))
	u.ultimate_charge_max = 0     # no skill/ultimate — the element cycle IS the kit

	if lvl > 1: u.set_level(lvl)
	return u

# ── Khagan (wave-10 boss — mount-swap fight) ─────────────────────────────────
# Phase 1: mounted (tanky, 2×2, "khagan_phase1" art). Phase 2: dismounted and
# fighting alone (faster, squishier, 1×1, "khagan_phase2" art) — reached the
# same way Triarch reaches its phases, by transforming in place instead of
# really dying. Phase 3 is different in kind: instead of a third self-
# transform, Khagan's "death" at the end of phase 2 channels his essence into
# one of the PLAYER's own heroes (the #2 damage dealer — turns a carry against
# you) via AutoBattleManager.start_khagan_possession(), pinning his phase-2
# sprite above them as the "who's possessed" tell (2026-07-08 user spec — phase
# 3 has no dedicated art of its own, just this icon), and Khagan's own body then
# dies for real. The possession is a fair, bounded set-piece (timed-survival
# rework 2026-07-24): the puppet is detuned (sustain stripped, damage capped,
# reduced HP) and you WIN by outlasting a survival timer — bursting it to 0 HP
# just frees it early. See AutoBattleManager.start_khagan_possession /
# _tick_khagan_possession / end_khagan_possession and the "khagan_puppet" die()
# intercept in UnitBase/VisualUnit.
const KHAGAN_PHASE_2 := {
	"name": "Dismounted", "unit_class": UnitBase.UnitClass.MONK, "element": UnitBase.Element.AIR,
	"hp_mult": 0.70, "mana_mult": 1.0, "atk_mult": 1.25, "magic_mult": 1.0, "res_mult": 0.55,
	"aspd_mult": 1.4, "hpregen_mult": 1.0, "manaregen_mult": 1.0,
	"move": 4, "range": 1,
	"skill_name": "Flowing Strikes", "skill_dmg": 1.4, "skill_range": 1, "skill_cd": 3, "skill_mana": 0,
}

static func create_khagan(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Khagan — Mounted"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	# Boss-sized growth (2026-07-12) — see the Hill Giant note. Deliberately the
	# gentlest boss table: at boss_level(10)=3 this adds ~500 hp / +8 atk, keeping
	# wave 10 first-try beatable with no crystal upgrades (the run target).
	u.growth_base     = {"hp": 250, "mana": 5, "atk": 4, "magic": 2, "res": 1, "aspd": 0.01, "hpregen": 0.15, "manaregen": 0.05}
	u.current_element = UnitBase.Element.WATER
	u.is_player_unit  = false
	u.cell_size       = 2          # riding a turtle mount
	u.max_hp          = 4000
	u.current_hp      = 2000
	u.max_mana        = 100
	u.current_mana    = 100
	u.attack_damage   = 50
	u.magic_power     = 10
	u.resistance      = 27
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.55
	u.hp_regen        = 1.0
	u.mana_regen      = 0.5
	u.movement_speed  = 3
	u.attack_range    = 2
	u.gold_reward     = 0
	u.crystal_reward  = 1
	u.xp_reward       = 320
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "khagan_phase1")
	u.is_boss         = true
	u.tenacity        = TENACITY_BOSS

	u.skill_name = "Shell Slam"
	u.skill_description = "Slams its armoured shell into the target for 170% ATK. · 3s CD"
	u.skill_damage_multiplier = 1.7
	u.skill_range = 1
	u.skill_cooldown_max = 3
	u.skill_mana_cost = 0

	if lvl > 1: u.set_level(lvl)
	u.set_meta("khagan_phase", 1)
	u.set_meta("passive_name", "Horde Lord")
	u.set_meta("passive_desc", "When its mount falls it fights on dismounted, faster and squishier. When that body falls it possesses one of your heroes: survive the timer (or burst the puppet) to win.")
	return u

# Called from VisualUnit.die() when Khagan's HP hits 0. Phase 1→2: transforms
# in place (dismount) and returns true. Phase 2: triggers the possession
# side-effect then returns false so Khagan's body really dies.
static func advance_khagan_phase(unit: VisualUnit) -> bool:
	var phase: int = int(unit.get_meta("khagan_phase", 1))
	if phase == 1:
		# Lazily snapshot the phase-1 baseline (same reasoning as the Triarch:
		# main_game.gd applies boss-tier leveling via an EXTERNAL set_level()
		# call AFTER this factory function returns, so snapshotting eagerly at
		# creation time would miss that scaling).
		if not unit.has_meta("khagan_base_stats"):
			unit.set_meta("khagan_base_stats", {
				"hp": unit.max_hp, "mana": unit.max_mana, "atk": unit.attack_damage,
				"magic": unit.magic_power, "res": unit.resistance,
				"aspd": unit.attack_speed, "hpregen": unit.hp_regen, "manaregen": unit.mana_regen,
			})
		var base: Dictionary = unit.get_meta("khagan_base_stats")
		var cfg: Dictionary = KHAGAN_PHASE_2

		unit.unit_class      = cfg["unit_class"]
		unit.current_element = cfg["element"]
		# Shrink the battle_grid occupancy footprint FIRST, before touching
		# cell_size — remove_unit() looks up the unit by its currently-
		# registered cells (still the full 2×2 block) and clears all of them;
		# place_unit() then re-registers using the NEW (1×1) cell_size. Skipping
		# this left the other 3 cells permanently marked occupied for the rest
		# of the fight — an invisible wall that blocked movement (but not
		# ranged attacks, which don't consult grid occupancy) right where
		# Khagan dismounted (2026-07-10 user report).
		var bg: BattleGrid = unit.battle_manager.battle_grid if unit.battle_manager else null
		var anchor: Vector2i = unit.grid_position
		if bg:
			bg.purge_unit(unit)
		unit.cell_size        = 1   # dismounted — no longer a 2×2 mount
		if bg:
			bg.place_unit(unit, anchor)
		unit.max_hp        = maxi(1, int(round(float(base["hp"]) * float(cfg["hp_mult"]))))
		unit.current_hp    = unit.max_hp
		unit.max_mana      = maxi(0, int(round(float(base["mana"]) * float(cfg["mana_mult"]))))
		unit.current_mana  = unit.max_mana
		unit.attack_damage = maxi(1, int(round(float(base["atk"]) * float(cfg["atk_mult"]))))
		unit.magic_power   = maxi(0, int(round(float(base["magic"]) * float(cfg["magic_mult"]))))
		unit.resistance    = maxi(0, int(round(float(base["res"]) * float(cfg["res_mult"]))))
		unit.magic_resist  = unit.resistance   # defense split: phases keep the stats equal
		unit.attack_speed  = float(base["aspd"]) * float(cfg["aspd_mult"])
		unit.hp_regen      = float(base["hpregen"]) * float(cfg["hpregen_mult"])
		unit.mana_regen    = float(base["manaregen"]) * float(cfg["manaregen_mult"])
		unit.movement_speed = int(cfg["move"])
		unit.attack_range   = int(cfg["range"])

		unit.skill_name = cfg["skill_name"]
		unit.skill_damage_multiplier = float(cfg["skill_dmg"])
		unit.skill_range = int(cfg["skill_range"])
		unit.skill_cooldown_max = int(cfg["skill_cd"])
		unit.skill_mana_cost = int(cfg["skill_mana"])
		unit.skill_cd_time = 0.0   # opens with an immediate strike, like the Triarch

		unit.current_shield = 0
		unit.attack_cooldown = 0.0
		unit.unit_name = "Khagan — %s" % cfg["name"]
		unit.set_meta("khagan_phase", 2)
		unit.set_meta("sprite_folder", "khagan_phase2")

		if unit.health_bar:
			# Re-derive the bar size for the new (smaller) footprint — it was
			# sized for cell_size=2 at spawn and won't auto-update otherwise.
			unit.health_bar.bar_width = 70.0 + (unit.cell_size - 1) * 120.0
			unit.health_bar.offset_y  = 60.0 + (unit.cell_size - 1) * 35.0
			unit.health_bar.update_hp(unit.current_hp, unit.max_hp)
			unit.health_bar.update_mp(unit.current_mana, unit.max_mana)
			unit.health_bar.update_ult(0, unit.ultimate_charge_max)
			unit.health_bar.update_shield(0, unit.max_hp)
		# All stats/grid/skill data above are already applied synchronously —
		# only the sprite swap itself is deferred, timed to the dismount beat's
		# flash peak so the texture change is hidden inside the whiteout instead
		# of popping on the same frame. Presentation only (visual_unit.gd's
		# play_dismount_transform); falls back to an immediate swap if the unit
		# has no dismount-beat support.
		# The arena-overlay/body-pulse Phase-2 escalation rides the SAME callback
		# as the sprite swap — both fire together at the dismount flash peak, so
		# the ground visibly escalates at the exact moment Khagan changes form,
		# not at the start of this function's stat/grid math above.
		if unit.has_method("play_dismount_transform"):
			unit.play_dismount_transform(func():
				if unit.has_method("rebuild_sprite"):
					unit.rebuild_sprite()
				if unit.battle_manager and unit.battle_manager.has_method("escalate_khagan_overlay_phase2"):
					unit.battle_manager.escalate_khagan_overlay_phase2(unit))
		elif unit.has_method("rebuild_sprite"):
			unit.rebuild_sprite()
		return true

	elif phase == 2:
		if unit.battle_manager and unit.battle_manager.has_method("start_khagan_possession"):
			unit.battle_manager.start_khagan_possession(unit)
		return false   # Khagan's own body really dies now — the puppet carries the fight

	return false

# ── Skyrender (wave-20 boss — the Air decade capstone) ────────────────
# Replaces The Triarch at wave 20 (2026-07-27): the Triarch is an archetype
# fight with no elemental identity, so it moved out to the mixed endgame (round
# 70) and each decade's capstone now matches that decade's element.
#
# The fight asks ONE question: did you bring damage that reaches? Cyclone Ascent
# cycles it between grounded and aloft on a fixed timer (AutoBattleManager's
# SKYRENDER_GROUND_TIME / SKYRENDER_ALOFT_TIME); while aloft, melee attackers can't
# target it at all while it keeps hitting back. Distinct from the round-15 Gale
# Warden, which tests FORMATION rather than reach.
#
# Single-phase by design — Khagan (10) and the Triarch (20's old occupant) are
# both transform fights, so a third in a row would read as the game's only trick.
# Its durability comes from the aloft windows instead of extra health bars,
# which is why the raw HP pool below sits nearer one Triarch phase than the sum
# of three.
static func create_skyrender(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Skyrender"
	u.unit_class      = UnitBase.UnitClass.RANGER
	# Boss growth table, sized against the Triarch's (the wave-20 anchor it
	# replaces) — boss_level(20) = 14 rides this, and the run target for wave 20
	# is "beatable, but only on a stars-align run with no crystal upgrades".
	# HP raised from 3000/430 growth after arena calibration (2026-07-27): at the
	# original numbers a mixed level-11 team killed it solo in ~15s, against ~32s
	# for the 3-phase Triarch it replaces. A single-phase boss shouldn't match a
	# three-healthbar fight, but 15s made the decade capstone a footnote next to
	# its own escort. Retuned to land around ~22s.
	u.growth_base     = {"hp": 620, "mana": 8, "atk": 9, "magic": 5, "res": 1, "aspd": 0.02, "hpregen": 0.15, "manaregen": 0.08}
	u.current_element = UnitBase.Element.AIR
	u.is_player_unit  = false
	u.cell_size       = 2          # a storm given a body — the decade's big silhouette
	u.max_hp          = 4400
	u.current_hp      = 4400
	u.max_mana        = 150
	u.current_mana    = 150
	u.attack_damage   = 42
	u.magic_power     = 20
	u.resistance      = 22         # squishier than a ground boss — it dodges by leaving
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.72       # fast, like everything Air
	u.hp_regen        = 0.6
	u.mana_regen      = 1.0
	u.movement_speed  = 4
	u.attack_range    = 1          # melee only — the Long Fall's approach now does the reach work

	u.gold_reward     = 100
	u.crystal_reward  = 3
	u.xp_reward       = 350
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "skyrender")
	u.is_boss         = true
	u.tenacity        = TENACITY_BOSS

	u.skill_name = "Gale Lance"
	u.skill_damage_multiplier = 1.35
	u.skill_range = 3
	u.skill_cooldown_max = 3
	u.skill_mana_cost = 0
	u.skill_description = "A lance of compressed wind for 135% ATK at up to 3 tiles. · 3s CD"
	u.set_meta("mob_passive", "skyrender_ascent")
	u.set_meta("passive_name", "Cyclone Ascent")
	u.set_meta("passive_desc", "Grounded for %ds, then aloft for %ds, where melee can't reach it. Below %d%% HP it gains +%d%% damage and +%d%% attack speed." % [
		int(AutoBattleManager.SKYRENDER_GROUND_TIME), int(AutoBattleManager.SKYRENDER_ALOFT_TIME),
		roundi(AutoBattleManager.SKYRENDER_ENRAGE_HP_PCT * 100.0), roundi(AutoBattleManager.SKYRENDER_ENRAGE_DMG * 100.0),
		roundi(AutoBattleManager.SKYRENDER_ENRAGE_ASPD * 100.0)])
	u.set_meta("skyrender_aloft", false)
	u.set_meta("skyrender_timer", 0.0)

	if lvl > 1: u.set_level(lvl)
	return u

# ── The Drowned Maw (wave-30 boss — the Water decade capstone) ───────────────
# Takes wave 30 over from the Hydra, which moves out to round 80 where its
# "player picks my element" mechanic fits the theme-free mixed endgame.
#
# The question: can your comp win with its sustain turned off? Riptide is a
# board-wide aura scaling all healing your side RECEIVES to DROWNED_HEAL_MULT
# for as long as the Maw lives (see the "drowned_riptide" passive). It doesn't
# out-damage you — it out-LASTS you, so a team leaning on a healer to survive
# the escort grinds down while a team with real damage kills it and the aura
# lifts with it.
#
# Deliberately not a radius or a targeted debuff: this game gives the player no
# in-battle lever, so the only fair question is a DRAFT question. Board-wide is
# also honest — you can read it off the wave dossier before you commit.
static func create_drowned_maw(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "The Drowned Maw"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	# Sized off Skyrender's table (the wave-20 capstone) and nudged up — this is
	# the round-30 gate, whose run target is "shouldn't fall without crystal
	# upgrades". Attrition boss: a deep HP pool is the POINT here, unlike the
	# Triarch note about pools just making grinds, because the aura is what makes
	# the grind dangerous rather than merely long.
	u.growth_base     = {"hp": 700, "mana": 0, "atk": 10, "magic": 4, "res": 1, "aspd": 0.015, "hpregen": 0.3, "manaregen": 0.0}
	u.current_element = UnitBase.Element.WATER
	u.is_player_unit  = false
	u.cell_size       = 2
	u.max_hp          = 5200
	u.current_hp      = 5200
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 46
	u.magic_power     = 14
	u.resistance      = 30
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.5        # slow, heavy bites
	u.hp_regen        = 1.5        # it out-lasts you; this is the flavour AND the threat
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 120
	u.crystal_reward  = 3
	u.xp_reward       = 400
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "drowned_maw")
	u.is_boss         = true
	u.tenacity        = TENACITY_BOSS

	u.skill_name = "Undertow"
	u.skill_damage_multiplier = 1.5
	u.skill_range = 1
	u.skill_cooldown_max = 4
	u.skill_mana_cost = 0
	# Built by concatenation, not the % operator — the literal "150% ATK" in the
	# text is itself a format specifier and makes `%` throw a parse error.
	u.skill_description = "Crushing bite for 150% ATK. · 4s CD"
	u.set_meta("mob_passive", "drowned_riptide")
	u.set_meta("passive_name", "Riptide")
	u.set_meta("passive_desc", "While it lives, all healing your team receives is cut to %d%%." \
			% roundi(AutoBattleManager.DROWNED_HEAL_MULT * 100.0))

	if lvl > 1: u.set_level(lvl)
	return u

# ── The Cloven Titan (wave-40 boss — the Earth decade capstone) ──────────────
# The question: can you finish the job? Killing it doesn't end it — the crack
# already running down its middle gives way and it comes apart into two 1×1
# halves that keep fighting (AutoBattleManager.spawn_cloven_halves, dispatched
# from the "cloven_split" meta in VisualUnit.die()).
#
# It punishes a team that dumps everything into one big burst and has nothing
# left, and rewards sustained output — the opposite ask from Skyrender's reach
# check and the Drowned Maw's sustain check, so the three Earth-side decades
# don't repeat a question.
#
# NOT a kill-order puzzle: the halves are simply the rest of the fight, with no
# "kill the right one first" demand — the player has no targeting lever, so that
# kind of check is unanswerable here (see the boss-design notes).
static func create_cloven_titan(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Cloven Titan"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = {"hp": 780, "mana": 0, "atk": 11, "magic": 3, "res": 1, "aspd": 0.015, "hpregen": 0.2, "manaregen": 0.0}
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.cell_size       = 2
	u.max_hp          = 5600
	u.current_hp      = 5600
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 50
	u.magic_power     = 8
	u.resistance      = 34         # granite — the tankiest boss statline so far
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.45       # slow, enormous swings
	u.hp_regen        = 0.8
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 130
	u.crystal_reward  = 3
	u.xp_reward       = 430
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "cloven_titan")
	u.is_boss         = true
	u.tenacity        = TENACITY_BOSS

	u.skill_name = "Fault Line"
	u.skill_damage_multiplier = 1.6
	u.skill_range = 1
	u.skill_cooldown_max = 4
	u.skill_mana_cost = 0
	u.skill_description = "Splitting overhead blow for 160% ATK. · 4s CD"
	u.set_meta("passive_name", "Split in Two")
	u.set_meta("passive_desc", "On death it breaks into two halves (%d%% of its max HP each) that fight on." \
			% roundi(AutoBattleManager.CLOVEN_HALF_HP * 100.0))
	u.set_meta("cloven_split", true)

	if lvl > 1: u.set_level(lvl)
	return u

# ── Emberhollow + Ember Hearts (wave-50 boss — the Fire decade capstone) ─────
# The question: kill order — WITHOUT asking the player to control targeting.
#
# Emberhollow's chest is an open iron cage with nothing in it (that's literally
# what the sprite shows). Its two Ember Hearts are what belong there. While
# either Heart still burns, killing the body only banks it: it revives once at
# EMBERHOLLOW_REVIVE_HP. Kill both Hearts first and the body stays down.
#
# The reason this is fair here when a "kill the healer" check would not be: the
# Hearts are placed as FRONT-row units, so they stand BETWEEN the player and the
# boss. Nearest-enemy targeting (the only targeting this game has) sends the
# team into them automatically. The player never has to issue an order — the
# geometry answers the question for them, and the fight just reads as a
# two-stage set-piece. Design geometry, not orders.
static func create_ember_heart(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Ember Heart"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = {"hp": 130, "mana": 0, "atk": 4, "magic": 2, "res": 1, "aspd": 0.01, "hpregen": 0.0, "manaregen": 0.0}
	u.current_element = UnitBase.Element.FIRE
	u.is_player_unit  = false
	u.max_hp          = 900
	u.current_hp      = 900
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 18         # barely fights — it's a fuse, not a threat
	u.magic_power     = 10
	u.resistance      = 14
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.45
	u.hp_regen        = 0.0
	u.mana_regen      = 0.0
	u.movement_speed  = 1          # a brazier on stubby legs
	u.attack_range    = 1
	u.gold_reward     = 0
	u.crystal_reward  = 0
	u.xp_reward       = 40
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "ember_heart")
	u.set_meta("ember_heart", true)   # read by the Emberhollow revive check

	u.skill_name = "Cinder Spit"
	u.skill_damage_multiplier = 1.1
	u.skill_range = 2
	u.skill_cooldown_max = 4
	u.skill_mana_cost = 0
	u.skill_description = "Coughs an ember for 110% ATK. · 4s CD"
	u.set_meta("passive_name", "Kindling")
	u.set_meta("passive_desc", "While any Ember Heart still burns, Emberhollow can return from death once.")

	if lvl > 1: u.set_level(lvl)
	return u

static func create_emberhollow(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Emberhollow"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = {"hp": 700, "mana": 0, "atk": 12, "magic": 5, "res": 1, "aspd": 0.018, "hpregen": 0.2, "manaregen": 0.0}
	u.current_element = UnitBase.Element.FIRE
	u.is_player_unit  = false
	u.cell_size       = 2
	u.max_hp          = 5000
	u.current_hp      = 5000
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 54
	u.magic_power     = 16
	u.resistance      = 28
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.55
	u.hp_regen        = 0.5
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 140
	u.crystal_reward  = 3
	u.xp_reward       = 460
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "emberhollow")
	u.is_boss         = true
	u.tenacity        = TENACITY_BOSS

	u.skill_name = "Backdraft"
	u.skill_damage_multiplier = 1.5
	u.skill_range = 1
	u.skill_cooldown_max = 4
	u.skill_mana_cost = 0
	u.skill_description = "Furnace blast for 150% ATK. · 4s CD"
	u.set_meta("passive_name", "Hollow Return")
	u.set_meta("passive_desc", "Returns once at %d%% health unless both Ember Hearts are out." \
			% roundi(AutoBattleManager.EMBERHOLLOW_REVIVE_HP * 100.0))
	u.set_meta("emberhollow_revive", true)

	if lvl > 1: u.set_level(lvl)
	return u

# ── Arcfang (wave-60 boss — the Lightning decade capstone) ───────────────────
# The question: is your carry protected? Thunder Run teleports it beside whoever
# is dealing the most damage on your side every ARCFANG_BLINK_INTERVAL seconds,
# straight past whatever frontline you built (see _arcfang_blink).
#
# Distinct from the round-55 Tempest Conduit, which chains between ADJACENT
# heroes and punishes clumping — Arcfang punishes the opposite arrangement, a
# carry left alone in open space. The two Lightning encounters therefore pull
# your formation in different directions instead of asking the same thing twice.
#
# Statline is a glass cannon by boss standards: it hits hard and fast but has the
# thinnest pool and armour of any decade boss, because it deliberately puts
# itself next to your damage.
static func create_arcfang(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Arcfang"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = {"hp": 600, "mana": 0, "atk": 14, "magic": 6, "res": 1, "aspd": 0.025, "hpregen": 0.2, "manaregen": 0.0}
	u.current_element = UnitBase.Element.LIGHTNING
	u.is_player_unit  = false
	u.cell_size       = 2
	u.max_hp          = 4600
	u.current_hp      = 4600
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 62         # highest raw attack of any decade boss
	u.magic_power     = 20
	u.resistance      = 24         # …and the thinnest armour, to match
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.85       # fastest, too
	u.hp_regen        = 0.4
	u.mana_regen      = 0.0
	u.movement_speed  = 5          # it runs down anything that tries to walk away
	u.attack_range    = 1
	u.gold_reward     = 150
	u.crystal_reward  = 3
	u.xp_reward       = 490
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "arcfang")
	u.is_boss         = true
	u.tenacity        = TENACITY_BOSS

	u.skill_name = "Sunder Bite"
	u.skill_damage_multiplier = 1.45
	u.skill_range = 1
	u.skill_cooldown_max = 3
	u.skill_mana_cost = 0
	u.skill_description = "Savage bite for 145% ATK. · 3s CD"
	u.set_meta("mob_passive", "arcfang_blink")
	u.set_meta("passive_name", "Thunder Run")
	u.set_meta("passive_desc", "Every %ds it flashes across the field beside your strongest attacker, past your frontline." \
			% int(AutoBattleManager.ARCFANG_BLINK_INTERVAL))
	u.set_meta("arcfang_timer", 0.0)

	if lvl > 1: u.set_level(lvl)
	return u

# ── The Gravekeeper (wave-90 boss — mixed endgame) ───────────────────────────
# The question: can you get through without losing anyone? Every hero that falls
# rises as a detuned shade on its side (see AutoBattleManager.gravekeeper_raise_shade,
# dispatched from the "gravekeeper" meta check in VisualUnit.die()).
#
# Sits one round before the finale as the attrition capstone: the earlier decade
# bosses each test one property of your comp, this one tests whether the comp
# HOLDS. Statline is deliberately unremarkable — the threat is the mechanic, not
# the body, so a team that takes no losses fights a fairly ordinary boss.
static func create_gravekeeper(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "The Gravekeeper"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = {"hp": 720, "mana": 0, "atk": 12, "magic": 4, "res": 1, "aspd": 0.016, "hpregen": 0.25, "manaregen": 0.0}
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.cell_size       = 2
	u.max_hp          = 5400
	u.current_hp      = 5400
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 56
	u.magic_power     = 14
	u.resistance      = 30
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.55
	u.hp_regen        = 0.6
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 170
	u.crystal_reward  = 4
	u.xp_reward       = 560
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "gravekeeper")
	u.is_boss         = true
	u.tenacity        = TENACITY_BOSS

	u.skill_name = "Grave Toll"
	u.skill_damage_multiplier = 1.5
	u.skill_range = 1
	u.skill_cooldown_max = 4
	u.skill_mana_cost = 0
	u.skill_description = "Spade sweep for 150% ATK. · 4s CD"
	u.set_meta("passive_name", "Grave Call")
	u.set_meta("passive_desc", "Every hero that falls rises as a shade on its side (%d%% HP, %d%% attack, up to %d at once)." % [
		roundi(AutoBattleManager.GRAVE_SHADE_HP * 100.0), roundi(AutoBattleManager.GRAVE_SHADE_DMG * 100.0),
		AutoBattleManager.GRAVE_SHADE_MAX])
	u.set_meta("gravekeeper", true)

	if lvl > 1: u.set_level(lvl)
	return u

# ── The Architect (wave-100 — THE FINALE) ────────────────────────────────────
# The first and only 3×3 unit in the game. That footprint alone is the statement:
# every other boss occupies a 2×2 block, so the finale is visibly a different
# order of thing before it does anything at all. (Grid, placement, world-centring,
# sprite scale and score_unit were all generalised from hardcoded 2×2 to N×N on
# 2026-07-29 to make this possible — see WaveScaler.cell_size_for_code.)
#
# Its mechanic is a REPRISE, not a seventh new gimmick: it cycles the three
# threats the run already taught you, one per third of its health, so the finale
# reads as an exam over the whole run rather than a fresh puzzle at the last
# moment. Implemented as the "architect_phases" passive:
#   above 66%  — Aloft, like Skyrender (melee can't reach it)
#   66% – 33%  — Riptide, like the Drowned Maw (your healing is cut)
#   below 33%  — Thunder Run, like Arcfang (it blinks onto your carry)
# Nothing here is new to the player, which is the point — they have already been
# taught every answer, and the finale asks for all of them at once.
static func create_the_architect(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "The Architect"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = {"hp": 1100, "mana": 0, "atk": 16, "magic": 8, "res": 2, "aspd": 0.018, "hpregen": 0.4, "manaregen": 0.0}
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.cell_size       = 3          # THE 3×3 — nothing else in the game is this big
	u.max_hp          = 9000
	u.current_hp      = 9000
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 74
	u.magic_power     = 26
	u.resistance      = 38
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.6
	u.hp_regen        = 1.0
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 2          # its reach matches its bulk
	u.gold_reward     = 250
	u.crystal_reward  = 6
	u.xp_reward       = 900
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "the_architect")
	u.is_boss         = true
	u.tenacity        = TENACITY_BOSS

	u.skill_name = "Cornerstone"
	u.skill_damage_multiplier = 1.7
	u.skill_range = 2
	u.skill_cooldown_max = 4
	u.skill_mana_cost = 0
	u.skill_description = "Monolithic slam for 170% ATK. · 4s CD"
	u.set_meta("mob_passive", "architect_phases")
	u.set_meta("passive_name", "The Three Trials")
	u.set_meta("passive_desc", "Changes trial as its health falls: above 66% it is aloft (melee can't reach it), then your healing is cut, then below 33% it blinks onto your strongest attacker.")
	u.set_meta("architect_phase", 0)
	u.set_meta("arcfang_timer", 0.0)      # reused by the phase-3 blink

	if lvl > 1: u.set_level(lvl)
	return u

# ── Hydra (wave-30 final boss — player-chosen element) ───────────────────────
# The player picks which element the Hydra fights as before the battle (see
# main_game.gd's element-pick screen + WaveScaler.boss_code_for's chosen_element
# param) — the pick is a matchup/strategy call, not a difficulty toggle; the
# Hydra hits just as hard whichever element you choose. Its threat scales with
# TIME instead of HP thresholds like the other bosses: every
# AutoBattleManager.HYDRA_REGROW_INTERVAL seconds it survives, it grows another
# head (up to HYDRA_MAX_HEADS) — see AutoBattleManager._hydra_regrow_tick,
# dispatched every tick from _tick_passive. Each head bites a different nearby
# target simultaneously on its "Serpent Strike" skill (see the "hydra_strike"
# case in _use_mob_skill), so a slow fight snowballs into being hit from
# several sides at once — a DPS race, not a gimmick fight like Khagan/Triarch.
const HYDRA_ELEMENT_NAMES := {
	UnitBase.Element.NORMAL:    "Normal",
	UnitBase.Element.FIRE:      "Fire",
	UnitBase.Element.WATER:     "Water",
	UnitBase.Element.EARTH:     "Earth",
	UnitBase.Element.AIR:       "Air",
	UnitBase.Element.LIGHTNING: "Lightning",
}
const HYDRA_SPRITE_FOLDERS := {
	UnitBase.Element.NORMAL:    "hydra_normal",
	UnitBase.Element.FIRE:      "hydra_fire",
	UnitBase.Element.WATER:     "hydra_water",
	UnitBase.Element.EARTH:     "hydra_earth",
	UnitBase.Element.AIR:       "hydra_air",
	UnitBase.Element.LIGHTNING: "hydra_lightning",
}

static func _create_hydra(element: UnitBase.Element, lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "%s Hydra" % HYDRA_ELEMENT_NAMES[element]
	u.unit_class      = UnitBase.UnitClass.HYDRA
	# Boss-sized growth (2026-07-12) — see the Hill Giant note. The steepest
	# table in the game: at boss_level(30)=20 (plus the late-wave multiplier)
	# the Hydra is MEANT to be unbeatable without crystal upgrades.
	u.growth_base     = {"hp": 550, "mana": 0, "atk": 9, "magic": 4, "res": 1, "aspd": 0.018, "hpregen": 0.3, "manaregen": 0.0}
	u.current_element = element
	u.is_player_unit  = false
	u.cell_size       = 2          # colossal multi-headed bulk
	u.max_hp          = 4800
	u.current_hp      = 4800
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 48
	u.magic_power     = 16
	u.resistance      = 29
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.55
	u.hp_regen        = 1.0
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 120
	u.crystal_reward  = 3
	u.xp_reward       = 400
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", HYDRA_SPRITE_FOLDERS[element])
	u.is_boss         = true
	u.tenacity        = TENACITY_BOSS
	# (own-element affinity now comes from set_affinity_profile — 2026-07-16)

	u.skill_name = "Serpent Strike"
	u.skill_damage_multiplier = 1.2
	u.skill_range = 1
	u.skill_cooldown_max = 5
	u.skill_mana_cost = 0
	u.skill_description = "Each head bites a different nearby target for 120% ATK (scales with own elemental affinity). · 5s CD"
	u.set_meta("passive_name", "Regrowth")
	u.set_meta("passive_desc", "Grows another head every %ds it survives, up to %d, and hits a little harder each time." % [
		int(AutoBattleManager.HYDRA_REGROW_INTERVAL), AutoBattleManager.HYDRA_MAX_HEADS])
	u.set_meta("mob_skill", "hydra_strike")
	u.set_meta("hydra_heads", 1)
	u.set_meta("hydra_regrow_accum", 0.0)

	if lvl > 1: u.set_level(lvl)
	return u

static func create_hydra_normal(lvl: int = 1) -> VisualUnit:    return _create_hydra(UnitBase.Element.NORMAL, lvl)
static func create_hydra_fire(lvl: int = 1) -> VisualUnit:      return _create_hydra(UnitBase.Element.FIRE, lvl)
static func create_hydra_water(lvl: int = 1) -> VisualUnit:     return _create_hydra(UnitBase.Element.WATER, lvl)
static func create_hydra_earth(lvl: int = 1) -> VisualUnit:     return _create_hydra(UnitBase.Element.EARTH, lvl)
static func create_hydra_air(lvl: int = 1) -> VisualUnit:       return _create_hydra(UnitBase.Element.AIR, lvl)
static func create_hydra_lightning(lvl: int = 1) -> VisualUnit: return _create_hydra(UnitBase.Element.LIGHTNING, lvl)

# ── Beast tier (2026-07-24) ────────────────────────────────────────────────────
# Single-element heavies, one power notch above the basic-mob ceiling (Bear/
# Wind-Up Bot ~90-100) and below the elite-heavy tier (Hill Giant 300 / Stat
# Stealer 150) — built so wave comps can drop 2-3 fodder bodies for ONE of
# these and hold the same difficulty (see WaveScaler.UNIT_POWER), and to seed
# fresh roster for wave 31+ once that content ships. Standard WARRIOR growth
# table (matches Orc/Bear/Slime — these scale with the normal level curve, not
# a custom elite curve). Sprite folder slugs match the monster prompt sheet
# (tools/sprite_pipeline/GEMINI_MONSTER_PROMPTS.md) so dropped Gemini art lines
# up directly — art is pending, falls back to the generic warrior LPC sheet
# until then (see VisualUnit._setup_lpc_sprite).
# Every skill/passive below reuses an EXISTING mob_skill/mob_passive dispatch
# key (auto_battle_manager._use_mob_skill / _tick_mob_passive) — no new combat
# mechanics, just new stat budgets wearing established moves (per the "ask
# before inventing ability mechanics" rule).

static func create_ogre(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Ogre"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.max_hp          = 900
	u.current_hp      = 900
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 40
	u.magic_power     = 6
	u.resistance      = 22
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.62
	u.hp_regen        = 0.5
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 40
	u.crystal_reward  = 1
	u.xp_reward       = 140
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "ogre")
	u.skill_name = "Crushing Blow"
	u.skill_damage_multiplier = 1.8
	u.skill_range = 1
	u.skill_cooldown_max = 8
	u.skill_mana_cost = 0
	u.skill_description = "Deal 180% ATK and stun for 1s. · 8s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool (~3 free Crushing
	# Blows per fight at 900 HP). See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "brute_crush")       # reused key — see Orc's brute_crush
	# Its skill and passive are named EXACTLY as the Orc's, so it gets the same
	# visual language rather than an invented different one — just bigger, to
	# match a 900hp body against the Orc's 750.
	u.set_meta("crush_vfx_reach", 132.0)
	u.set_meta("mob_passive", "orc_rage")        # reused key — below 50% hp: +20% dmg / +15% aspd
	u.set_meta("passive_name", "Bloodrage")
	u.set_meta("passive_desc", "Below 50% HP: +20% damage and +15% attack speed.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_minotaur(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Minotaur"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.FIRE
	u.is_player_unit  = false
	u.max_hp          = 750
	u.current_hp      = 750
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 46
	u.magic_power     = 6
	u.resistance      = 18
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.72
	u.hp_regen        = 0.4
	u.mana_regen      = 0.0
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 38
	u.crystal_reward  = 1
	u.xp_reward       = 135
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "minotaur")
	u.skill_name = "Gore Rush"
	u.skill_damage_multiplier = 1.5
	u.skill_range = 1
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Deal 150% ATK (scales with own elemental affinity) and stun for 1s. · 6s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool (~2.5 free Gore Rushes
	# per fight at 750 HP). See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "windup_punch")      # reused key — see Wind-Up Bot's windup_punch
	# Identity marker. Gore Rush/Savage Charge reuse the Wind-Up Bot's and Bear's
	# keys, so it already has their bug fixes — this only selects its own VFX.
	u.set_meta("minotaur", true)
	u.set_meta("mob_passive", "bear_fury")       # reused key — aspd ramps with missing hp, up to +30%
	u.set_meta("passive_name", "Savage Charge")
	u.set_meta("passive_desc", "Attack speed ramps with missing HP, up to +30% near death.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_gargoyle(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Gargoyle"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.AIR
	u.is_player_unit  = false
	u.max_hp          = 1000
	u.current_hp      = 1000
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 30
	u.magic_power     = 6
	u.resistance      = 30
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.55
	u.hp_regen        = 0.6
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 36
	u.crystal_reward  = 1
	u.xp_reward       = 150
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "gargoyle")
	u.skill_name = "Talon Rake"
	u.skill_damage_multiplier = 1.4
	u.skill_range = 1
	u.skill_cooldown_max = 7
	u.skill_mana_cost = 0
	u.skill_description = "Rake for 140% ATK (scales with own elemental affinity) and open a bleed: 30% ATK/s for 4s, doubled while the target moves. · 7s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool (~3.3 free Talon Rakes
	# per fight at 1000 HP). See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "bear_swipe")        # reused key — see Bear's bear_swipe
	# Its skill is named "Talon Rake" exactly as the Harpy's, so it opts into the
	# SAME talon visual, sized for a heavier body (Harpy 84).
	u.set_meta("talon_vfx_reach", 100.0)
	# Its passive is named "Stone Skin" (not the Troll's "Regeneration" or the
	# Phoenix's "Rekindle"), so it gets its own masonry fiction.
	u.set_meta("gargoyle", true)
	# Stone Ward (2026-09-24, owner design — replaced the reused troll_regen):
	# at half HP it turns to stone. The ward eats the next 4 HITS whatever their
	# damage, so it rewards many small hits over one big one.
	u.set_meta("mob_passive", "gargoyle_ward")
	u.set_meta("passive_name", "Stone Ward")
	u.set_meta("passive_desc", "At 50% HP it turns to stone: the next 4 hits deal no damage, however hard they land. Once per fight.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_stone_golem(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Stone Golem"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.max_hp          = 1500
	u.current_hp      = 1500
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 22
	u.magic_power     = 4
	u.resistance      = 35
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.45
	u.hp_regen        = 0.8
	u.mana_regen      = 0.0
	u.movement_speed  = 1
	u.attack_range    = 1
	u.gold_reward     = 45
	u.crystal_reward  = 2
	u.xp_reward       = 170
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "stone_golem")
	u.skill_name = "Granite Shell"
	u.skill_damage_multiplier = 0.0
	u.skill_range = 0
	u.skill_cooldown_max = 9
	u.skill_mana_cost = 0
	u.skill_description = "Raises a shield worth 25% max HP. · 9s CD"
	u.set_meta("mob_skill", "skeleton_boneshield")   # reused key — see Skeleton's boneshield
	# No passive by design (matches Hill Giant/Skeleton/Rat precedent) — the
	# whole identity is the wall statline, not an extra mechanic.
	if lvl > 1: u.set_level(lvl)
	return u

# ── Earth-decade variety (2026-07-24, wave 31-40) ─────────────────────────────
# Same reuse-only pattern as Beast tier above — new silhouettes/stat budgets,
# zero new mob_skill/mob_passive keys. Priced near the basic-mob band (Bear/
# Wind-Up Bot ~90-100) rather than the Beast-tier heavy band, so they slot in
# as fresh-feeling FODDER/UTILITY variety alongside the existing "_earth"
# elemental variants (orc_earth, bear_earth, etc.) rather than as anchors —
# Ogre/Stone Golem already cover the Earth decade's heavy-anchor role.

static func create_crystal_crab(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Crystal Crab"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.max_hp          = 620
	u.current_hp      = 620
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 26
	u.magic_power     = 4
	u.resistance      = 26
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.58
	u.hp_regen        = 0.4
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 30
	u.crystal_reward  = 1
	u.xp_reward       = 105
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "crystal_crab")
	u.skill_name = "Crystalline Shell"
	u.skill_damage_multiplier = 0.0
	u.skill_range = 0
	u.skill_cooldown_max = 9
	u.skill_mana_cost = 0
	u.skill_description = "Raises a shield worth 25% max HP. · 9s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool. At 620 HP that is
	# ~2.1 free Crystalline Shells per fight, on a mob whose whole identity is
	# being hard to chew through. See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "skeleton_boneshield")   # reused key — hard shell, same as Skeleton/Stone Golem
	# Marks the crab: the shared boneshield key also serves the Skeleton, Stone
	# Golem and Coral Husk, which keep their original burst.
	u.set_meta("crystal_crab", true)
	u.set_meta("mob_passive", "bear_fury")           # reused key — aspd ramps with missing hp, up to +30%
	u.set_meta("passive_name", "Frenzied Clacking")
	u.set_meta("passive_desc", "Attack speed ramps with missing HP, up to +30% near death.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_root_walker(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Root Walker"
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.max_hp          = 340
	u.current_hp      = 340
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 20
	u.magic_power     = 8
	u.resistance      = 14
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.85
	u.hp_regen        = 0.3
	u.mana_regen      = 0.0
	u.movement_speed  = 2
	u.attack_range    = 3
	u.gold_reward     = 24
	u.crystal_reward  = 1
	u.xp_reward       = 78
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "root_walker")
	u.skill_name = "Entangling Roots"
	u.skill_damage_multiplier = 1.1
	u.skill_range = 3
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Deal 110% ATK and root: -30% movement speed for 2s. · 6s CD"
	u.set_meta("mob_skill", "archer_cripple")        # reused key — dmg + slow, see Goblin Archer
	u.set_meta("mob_passive", "shaman_link")         # reused key — nearby allies regen +0.5 hp/s
	u.set_meta("passive_name", "Nature's Blessing")
	u.set_meta("passive_desc", "Allies within 3 tiles regenerate +0.5 HP/s.")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Fire decade roster (2026-07-24, wave 41-50) ───────────────────────────────
# Same reuse-only pattern as everything above — no new mob_skill/mob_passive
# keys, only new bodies and stat budgets.

# The Fire decade's 2×2 POWER ANCHOR. Every elemental decade needs its own large
# body: score_unit()'s ×2.5 cell_size multiplier means a 2×2 unit contributes
# more power than any stack of 1×1 heavies can (learned building the Earth
# decade — see wave_data's Act 4 notes), so each decade's waves must be anchored
# by SOMETHING large. Reusing the Hill Giant everywhere would work numerically
# but reads wrong — it's an Earth creature by element and by art. So each
# elemental decade gets its own themed giant from the prompt sheet: Fire Giant
# here, Storm Giant for Lightning (51-60).
# Statline is deliberately ~60% of the Hill Giant's: G is an ELITE, so when it
# appears in a normal wave WaveDirector demotes it by HEAVY_STAT_MULT (0.6).
# Fire Giant is NOT in ELITE_POOL (it's a regular wave unit, never a round-5/15/
# 25 elite), so it spawns at full stats — building it at 60% of G lands it in
# the same effective power slot a demoted Hill Giant occupies. Growth is scaled
# the same way (elite-sized 260 hp/lvl × 0.6) so the two stay matched as the
# level curve climbs.
static func create_fire_giant(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Fire Giant"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = {"hp": 156, "mana": 3, "atk": 3, "magic": 1, "res": 1, "aspd": 0.01, "hpregen": 0.06, "manaregen": 0.03}
	u.current_element = UnitBase.Element.FIRE
	u.is_player_unit  = false
	u.cell_size       = 2          # occupies a 2×2 area — the decade's anchor
	u.max_hp          = 2300
	u.current_hp      = 2300
	u.max_mana        = 60
	u.current_mana    = 60
	u.attack_damage   = 70
	u.magic_power     = 12
	u.resistance      = 20
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.6
	u.hp_regen        = 0.35
	u.mana_regen      = 0.3
	u.movement_speed  = 2          # same as Hill Giant — at move 1 ranged comps kite it forever
	u.attack_range    = 1
	u.gold_reward     = 55
	u.crystal_reward  = 1
	u.xp_reward       = 190
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "fire_giant")
	u.skill_name = "Molten Smash"
	u.skill_damage_multiplier = 1.8
	u.skill_range = 1
	u.skill_cooldown_max = 8
	u.skill_mana_cost = 0
	u.skill_description = "Deal 180% ATK and stun for 1s. · 8s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool. At 2300 HP that is
	# ~7.7 free Molten Smashes per fight, tied with the Storm Giant for the
	# largest leak found. See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "brute_crush")       # reused key — big hit + stun
	u.set_meta("mob_passive", "orc_rage")        # reused key — below 50% hp: +20% dmg / +15% aspd
	u.set_meta("passive_name", "Forge Fury")
	# Its own visual fiction: "Molten Smash"/"Forge Fury" are NOT the Orc's
	# "Crushing Blow"/"Bloodrage", so it must not borrow the Orc's slam. It
	# deliberately does NOT set crush_vfx_reach (that meta means "draw the Orc's
	# effect at this size") — see FireGiantVFX.
	u.set_meta("fire_giant", true)
	u.set_meta("passive_desc", "Below 50% HP: +20% damage and +15% attack speed.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_hellhound(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Hellhound"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.FIRE
	u.is_player_unit  = false
	u.max_hp          = 380
	u.current_hp      = 380
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 34
	u.magic_power     = 6
	u.resistance      = 14
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.95       # fast pack hunter
	u.hp_regen        = 0.3
	u.mana_regen      = 0.0
	u.movement_speed  = 4          # closes distance fast
	u.attack_range    = 1
	u.gold_reward     = 26
	u.crystal_reward  = 1
	u.xp_reward       = 88
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "hellhound")
	u.skill_name = "Searing Bite"
	u.skill_damage_multiplier = 1.1
	u.skill_range = 1
	u.skill_cooldown_max = 5
	u.skill_mana_cost = 0
	u.skill_description = "Deal 110% ATK and set alight: 35% ATK/s burn for 3s. · 5s CD"
	u.set_meta("mob_skill", "rat_bite")          # reused key — hit + burn DoT
	u.set_meta("mob_passive", "goblin_pack")     # reused key — +6% aspd per nearby packmate, cap +30%
	u.set_meta("passive_name", "Hunting Pack")
	u.set_meta("passive_desc", "+6% attack speed per other Hellhound within 3 tiles, up to +30%.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_ember_phoenix(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Ember Phoenix"
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.FIRE
	u.is_player_unit  = false
	u.max_hp          = 300
	u.current_hp      = 300
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 28
	u.magic_power     = 14
	u.resistance      = 12
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.8
	u.hp_regen        = 0.4
	u.mana_regen      = 0.0
	u.movement_speed  = 3
	u.attack_range    = 4          # ranged — stays behind the frontline
	u.gold_reward     = 30
	u.crystal_reward  = 1
	u.xp_reward       = 96
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "ember_phoenix")
	u.skill_name = "Cinder Lance"
	u.skill_damage_multiplier = 1.7
	u.skill_range = 4
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "A high-multiplier ranged burst for 170% ATK. · 6s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool (~1.0 free Cinder
	# Lances per fight at 300 HP). See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "lizard_snipe")      # reused key — cooldown-gated ranged burst
	# Marks the Phoenix: the shared key is also the Lizard's row-piercing
	# Precision Shot, which is unaffected by anything here.
	u.set_meta("phoenix", true)
	# Rebirth (2026-09-24, owner design — replaced the reused troll_regen): the
	# first death rebuilds it from the ashes to 25% HP instead. Once per fight.
	u.set_meta("mob_passive", "phoenix_rebirth")
	u.set_meta("passive_name", "Rebirth")
	u.set_meta("passive_desc", "The first time it would die, it rapidly rebuilds itself from the ashes to 25% HP. Once per fight.")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Lightning decade roster (2026-07-24, wave 51-60) ──────────────────────────
# Same reuse-only pattern. The existing "_lightning" variant families (BL/BRL/
# TLL/LZL/WUL/SLL/GSL) already cover most of this decade's bodies, so it only
# needs the 2×2 anchor plus one flavor unit.

# The Lightning decade's 2×2 POWER ANCHOR — same role Fire Giant plays for
# 41-50, statted the same way (~60% of Hill Giant, since G gets demoted by
# HEAVY_STAT_MULT in normal waves and this one doesn't). See create_fire_giant
# for the full reasoning on why each elemental decade needs its own large body.
# Kit deliberately differs from Fire Giant's for variety: a charge-up striker
# (Overclock aspd ramp + stunning strike) rather than a rage bruiser.
static func create_storm_giant(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Storm Giant"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = {"hp": 148, "mana": 3, "atk": 3, "magic": 1, "res": 1, "aspd": 0.01, "hpregen": 0.06, "manaregen": 0.03}
	u.current_element = UnitBase.Element.LIGHTNING
	u.is_player_unit  = false
	u.cell_size       = 2          # occupies a 2×2 area — the decade's anchor
	u.max_hp          = 2150
	u.current_hp      = 2150
	u.max_mana        = 60
	u.current_mana    = 60
	u.attack_damage   = 74
	u.magic_power     = 14
	u.resistance      = 18
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.65
	u.hp_regen        = 0.3
	u.mana_regen      = 0.3
	u.movement_speed  = 2          # same as the other giants — move 1 gets kited forever
	u.attack_range    = 1
	u.gold_reward     = 55
	u.crystal_reward  = 1
	u.xp_reward       = 190
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "storm_giant")
	u.skill_name = "Thunderclap"
	u.skill_damage_multiplier = 1.6
	u.skill_range = 1
	u.skill_cooldown_max = 7
	u.skill_mana_cost = 0
	u.skill_description = "Deal 160% ATK (scales with own elemental affinity) and stun for 1s. · 7s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool. At 2150 HP that is
	# ~7.2 free Thunderclaps per fight — the largest such leak found so far.
	# See the Rat for the full note; bosses/elites stay untouched.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "windup_punch")        # reused key — affinity-scaled hit + 1s stun
	# Its abilities have their OWN names (Thunderclap / Gathering Storm), so it
	# gets its own visual language rather than the Wind-Up Bot's clockwork.
	u.set_meta("storm_giant", true)
	u.set_meta("mob_passive", "windup_overclock")  # reused key — +5%/3s aspd, cap +50%
	u.set_meta("passive_name", "Gathering Storm")
	u.set_meta("passive_desc", "Attack speed builds +5% every 3s as the storm gathers, up to +50%.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_storm_crow(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Storm Crow"
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.LIGHTNING
	u.is_player_unit  = false
	u.max_hp          = 260
	u.current_hp      = 260
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 30
	u.magic_power     = 10
	u.resistance      = 10
	u.magic_resist    = u.resistance
	u.attack_speed    = 1.0        # fast harasser
	u.hp_regen        = 0.25
	u.mana_regen      = 0.0
	u.movement_speed  = 4          # flies in fast
	u.attack_range    = 3
	u.gold_reward     = 26
	u.crystal_reward  = 1
	u.xp_reward       = 84
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "storm_crow")
	u.skill_name = "Static Shriek"
	u.skill_damage_multiplier = 1.2
	u.skill_range = 3
	u.skill_cooldown_max = 5
	u.skill_mana_cost = 0
	u.skill_description = "Deal 120% ATK and slow the target by 30% for 2s. · 5s CD"
	u.set_meta("mob_skill", "archer_cripple")    # reused key — ranged hit + slow
	u.set_meta("mob_passive", "goblin_pack")     # reused key — +6% aspd per nearby flockmate, cap +30%
	u.set_meta("passive_name", "Murder")
	u.set_meta("passive_desc", "+6% attack speed per other Storm Crow within 3 tiles, up to +30%.")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Air / Water decade anchors (2026-08-02, waves 11-20 / 21-30) ──────────────
# Waves 11-30 predate the "each elemental decade gets its OWN 2×2 giant" rule
# (see create_fire_giant) — both decades were anchored on the Hill Giant, an
# EARTH creature by element and by art, which is exactly the mismatch that rule
# exists to prevent. These two fill the missing slots so all five elemental
# decades follow the same pattern: Air 11-20, Water 21-30, Earth 31-40 (G, which
# is genuinely Earth), Fire 41-50 (FG), Lightning 51-60 (STG).
#
# Both bodies come from the EXISTING unused prompt sheet rather than new art
# direction — wyvern (Wave 10 tier) and tidepool_horror (Wave 5 tier).
#
# Statted in the same band as FG/STG: ~60% of Hill Giant's hp/atk so they land
# in the slot a HEAVY_STAT_MULT-demoted G used to fill, with res left at G's
# level (that mult scales hp/atk/magic only — see WaveDirector). Growth is 60%
# of G's elite-sized table so they track the level curve identically.
#
# NEITHER has a regen passive, deliberately. These anchor EVERY wave in their
# decade, and a self-regenerating 2×2 in every comp is the exact sustain-density
# that produced the documented high-round stalls (see wave_data Act 6 notes).

static func create_sky_wyvern(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Sky Wyvern"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = {"hp": 145, "mana": 3, "atk": 3, "magic": 1, "res": 1, "aspd": 0.01, "hpregen": 0.06, "manaregen": 0.03}
	u.current_element = UnitBase.Element.AIR
	u.is_player_unit  = false
	u.cell_size       = 2          # occupies a 2×2 area — the Air decade's anchor
	# hp/atk trimmed from 2200/72 after measuring the retinted decade against its
	# own baseline — the first pass scored ~4-6% above the demoted Hill Giant it
	# replaces on the waves where the anchor is the only change (13/14/17).
	u.max_hp          = 2120
	u.current_hp      = 2120
	u.max_mana        = 60
	u.current_mana    = 60
	u.attack_damage   = 69
	u.magic_power     = 12
	u.resistance      = 16
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.7        # faster than the other giants — an aerial predator
	u.hp_regen        = 0.3
	u.mana_regen      = 0.3
	u.movement_speed  = 3          # flies in; the other giants move 2
	u.attack_range    = 1
	u.gold_reward     = 55
	u.crystal_reward  = 1
	u.xp_reward       = 190
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "sky_wyvern")
	u.skill_name = "Venom Stinger"
	u.skill_damage_multiplier = 1.3
	u.skill_range = 1
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Deal 130% ATK and envenom: 35% ATK/s poison for 3s. · 6s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool. At 2120 HP that is
	# ~7 free Venom Stingers per fight. See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "rat_bite")          # reused key — hit + damage-over-time
	# Its DoT used to fall through to the DEFAULT "fire" flavour, so the poison
	# its description promises rendered as a fire burn. Third fiction on this key
	# after the Rat's disease and the Hellhound's (correct) fire.
	u.set_meta("dot_flavor", "venom")
	u.set_meta("sky_wyvern", true)
	u.set_meta("mob_passive", "bear_fury")       # reused key — aspd ramps with missing hp
	u.set_meta("passive_name", "Wounded Dive")
	u.set_meta("passive_desc", "Attack speed ramps with missing HP, up to +30% near death.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_tidepool_horror(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Tidepool Horror"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = {"hp": 158, "mana": 3, "atk": 3, "magic": 1, "res": 1, "aspd": 0.01, "hpregen": 0.06, "manaregen": 0.03}
	u.current_element = UnitBase.Element.WATER
	u.is_player_unit  = false
	u.cell_size       = 2          # occupies a 2×2 area — the Water decade's anchor
	# hp/atk trimmed from 2500/62 — same measurement as the Sky Wyvern above. The
	# Water decade runs TWO anchors on most waves, so the overshoot doubled there.
	u.max_hp          = 2350       # still the bulkiest of the decade anchors, and the slowest
	u.current_hp      = 2350
	u.max_mana        = 60
	u.current_mana    = 60
	u.attack_damage   = 58
	u.magic_power     = 14
	u.resistance      = 22
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.55
	u.hp_regen        = 0.3
	u.mana_regen      = 0.3
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 55
	u.crystal_reward  = 1
	u.xp_reward       = 190
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "tidepool_horror")
	u.skill_name = "Pincer Slam"
	u.skill_damage_multiplier = 1.8
	u.skill_range = 1
	u.skill_cooldown_max = 8
	u.skill_mana_cost = 0
	u.skill_description = "Deal 180% ATK and stun for 1s. · 8s CD"
	u.set_meta("mob_skill", "brute_crush")       # reused key — big hit + stun
	u.set_meta("mob_passive", "archer_focus")    # reused key — ramps on a held target
	u.set_meta("passive_name", "Deathgrip")
	u.set_meta("passive_desc", "+8% damage each consecutive hit on the same target (max +40%); resets on switching targets.")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Air / Water decade flavour bodies (2026-08-02) ────────────────────────────
# The 1×1 counterparts to the anchors above. Every other elemental decade has a
# bespoke creature or two (Earth: Ogre/Golem/Crab/Root Walker · Fire: Hellhound/
# Ember Phoenix · Lightning: Storm Crow); Air and Water ran entirely on recolored
# shared families, so neither decade had a face of its own. Both bodies come from
# the existing unused prompt sheet — "harpy" and "coral_husk".
#
# Both are deliberate FORESHADOWS of the elite their decade builds toward: each
# carries a small version of the mechanic the elite runs at full strength, so the
# player meets the idea on a body they can kill before it's the whole encounter.
#   Harpy      → Gale Warden (round 15): evasion
#   Coral Husk → Tidecaller  (round 25): shields
# Priced in the basic-mob band (Storm Crow 90 / Crystal Crab 105) — these are
# flavour and variety, NOT anchors and NOT heavies.

static func create_harpy(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Harpy"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.AIR
	u.is_player_unit  = false
	u.max_hp          = 300        # frail — it survives by not being hit
	u.current_hp      = 300
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 32
	u.magic_power     = 8
	u.resistance      = 11         # low armor on purpose, same identity as the Warden
	u.magic_resist    = u.resistance
	u.attack_speed    = 1.05       # fast swooping harasser
	u.hp_regen        = 0.25
	u.mana_regen      = 0.0
	u.movement_speed  = 5          # dives in; the fastest body in the decade
	u.attack_range    = 1
	u.gold_reward     = 26
	u.crystal_reward  = 1
	u.xp_reward       = 84
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "harpy")
	# THE FORESHADOW: the same equipment_passives["Evasion"] roll the Gale Warden
	# runs at 30% two rounds later (see GALE_WARDEN_EVASION). A small taste on a
	# killable body, so "my hits are whiffing" isn't a new idea at the elite.
	u.equipment_passives["Evasion"] = 0.12
	u.skill_name = "Talon Rake"
	u.skill_damage_multiplier = 1.15
	u.skill_range = 1
	u.skill_cooldown_max = 5
	u.skill_mana_cost = 0
	u.skill_description = "Deal 115% ATK and open a bleed. · 5s CD"
	# Declares no ultimate but inherits UnitBase's 300 pool (~1 free Talon Rake
	# per fight at 300 HP). See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "bear_swipe")        # reused key — hit + bleed
	# "Talon Rake" is shared by NAME with the Gargoyle, so both use one talon
	# visual sized per body. The Bear rides the same key but its move is
	# "Rending Swipe" and keeps its own claw look.
	u.set_meta("talon_vfx_reach", 84.0)
	u.set_meta("passive_name", "Windborne")
	u.set_meta("passive_desc", "12% of direct hits miss entirely — it simply isn't where the blow lands.")
	if lvl > 1: u.set_level(lvl)
	return u

static func create_coral_husk(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Coral Husk"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.WATER
	u.is_player_unit  = false
	u.max_hp          = 480
	u.current_hp      = 480
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 26         # low output — it's a wall, not a threat
	u.magic_power     = 8
	u.resistance      = 20
	u.magic_resist    = u.resistance
	u.attack_speed    = 0.7
	u.hp_regen        = 0.25       # NO regen passive — see the anchor notes above
	u.mana_regen      = 0.0
	u.movement_speed  = 2          # slow; it advances like a reef, not a raider
	u.attack_range    = 1
	u.gold_reward     = 28
	u.crystal_reward  = 1
	u.xp_reward       = 90
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "coral_husk")
	u.skill_name = "Calcify"
	u.skill_damage_multiplier = 0.0
	u.skill_range = 1
	u.skill_cooldown_max = 7
	u.skill_mana_cost = 0
	u.skill_description = "Hardens its shell, absorbing the next burst of damage. · 7s CD"
	# THE FORESHADOW: a self-shield, two rounds before the Tidecaller starts
	# shielding its ENTIRE wave. Same reused key the Stone Golem/Crystal Crab use.
	# Declares no ultimate but inherits UnitBase's 300 pool (~1.6 free Calcifies
	# per fight at 480 HP). See the Rat for the full note.
	u.ultimate_charge_max = 0
	u.set_meta("mob_skill", "skeleton_boneshield")
	# Calcify / Slow Tide are named differently from the keys' owners, so it gets
	# its own reef language rather than the Skeleton's ribs or the Bot's gears.
	u.set_meta("coral_husk", true)
	u.set_meta("mob_passive", "windup_overclock")  # reused key — +5%/3s aspd, cap +50%
	u.set_meta("passive_name", "Slow Tide")
	u.set_meta("passive_desc", "Attack speed builds +5% every 3s as it grinds forward, up to +50%.")
	if lvl > 1: u.set_level(lvl)
	return u
