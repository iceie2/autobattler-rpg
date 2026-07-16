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
}

# Returns a NEW level-1 unit for a wave-code or type string; caller applies
# set_level() afterwards (matches main_game's flow — never level inside the
# factory, phase-boss snapshots depend on external leveling; see Triarch notes).
static func create_by_type(type: String) -> VisualUnit:
	var u := _create_by_type_dispatch(type)
	if u:
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
	u.resistance      = 1
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
	u.skill_description = "Quick lunge dealing 140% ATK. · 5s CD"
	u.set_meta("mob_skill", "goblin_shank")
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
	u.attack_damage   = 37
	u.magic_power     = 9
	u.resistance      = 3
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 1.2
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
	u.set_meta("mob_skill", "archer_cripple")
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
	u.current_hp      = 240
	u.max_mana        = 60
	u.current_mana    = 30
	u.attack_damage   = 9
	u.magic_power     = 19
	u.resistance      = 8
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
	u.resistance      = 10
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
	u.set_meta("mob_skill", "brute_crush")
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
	u.resistance      = 2        # naturally tough, hits weak
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
	u.set_meta("mob_skill", "slime_goo")
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
	u.resistance      = 10
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
	u.skill_range = 5
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Fires a piercing shot at the current target for 220% ATK. · 6s CD"
	u.set_meta("mob_skill", "lizard_snipe")
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
	u.resistance      = 26
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
	u.set_meta("mob_skill", "bear_swipe")
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
	u.resistance      = 10
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
	u.skill_description = "Boost a random ally's (or its own) attack speed by 35% (scales with own elemental affinity) for 10s. · 5s CD"
	u.set_meta("mob_skill", "troll_enrage")
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
	u.resistance      = 6
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
	u.skill_description = "Deal 150% ATK (scales with own elemental affinity) and stun for 1s. · 6s CD"
	u.set_meta("mob_skill", "windup_punch")
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
	u.resistance      = 4           # brittle bones — low res
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
	u.set_meta("mob_skill", "skeleton_boneshield")
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
	u.resistance      = 3
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
	u.set_meta("mob_skill", "rat_bite")
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
	u.max_hp          = 3800
	u.current_hp      = 3800
	u.max_mana        = 100
	u.current_mana    = 100
	# 150 → 115 (2026-07-16): the affinity rework dropped off-element defense
	# to 68 (×1.32 taken), which turned the giant's 150 atk into an 8/8 wipe
	# of average round-5 comps. 115 restores a real-but-beatable spike.
	u.attack_damage   = 115
	u.magic_power     = 9
	u.resistance      = 15
	u.magic_resist    = u.resistance   # defense split 2026-07-16: start equal, tune later
	u.attack_speed    = 0.6
	u.hp_regen        = 0.55
	u.mana_regen      = 0.5
	u.movement_speed  = 2          # arena sims: at move 1 ranged comps kite it
								   # to death without taking a single hit
	u.attack_range    = 2
	u.gold_reward     = 0
	u.crystal_reward  = 2
	u.xp_reward       = 200
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "hill_giant")
	u.skill_name      = "Boulder Smash"
	u.skill_damage_multiplier = 2.0
	u.skill_range     = 2
	u.skill_cooldown_max = 4
	u.ultimate_charge_max = 0     # no ult
	u.is_elite        = true
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
	u.resistance      = 20
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

	u.skill_name = "Cleaving Strike"
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
	u.resistance      = 20
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

	u.skill_name = "Siphon Ward"
	u.skill_damage_multiplier = 0.0   # utility skill, no direct damage
	u.skill_range = 0
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 40

	u.ultimate_name = "Essence Drain"
	u.ultimate_damage_mult = 0.0      # utility ultimate, no direct damage
	u.ultimate_range = 6
	u.ultimate_charge_max = 350

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
	u.growth_base     = {"hp": 300, "mana": 0, "atk": 1, "magic": 0, "res": 1, "aspd": 0.0, "hpregen": 0.2, "manaregen": 0.0}
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
	u.resistance      = 24         # tanky: rewards focusing it down, punishes ignoring it
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
	u.is_elite        = true
	u.ultimate_charge_max = 0     # no skill/ultimate — purely the passive spawn behavior

	if lvl > 1: u.set_level(lvl)
	return u

# ── Khagan (wave-10 boss — mount-swap fight) ─────────────────────────────────
# Phase 1: mounted (tanky, 2×2, "khagan_phase1" art). Phase 2: dismounted and
# fighting alone (faster, squishier, 1×1, "khagan_phase2" art) — reached the
# same way Triarch reaches its phases, by transforming in place instead of
# really dying. Phase 3 is different in kind: instead of a third self-
# transform, Khagan's "death" at the end of phase 2 channels his essence into
# one of the PLAYER's own heroes (highest attack_damage — turns your best carry
# against you) via AutoBattleManager.start_khagan_possession(), pinning his
# phase-2 sprite above them as the "who's possessed" tell (2026-07-08 user
# spec — phase 3 has no dedicated art of its own, just this icon on the
# possessed unit), and Khagan's own body then dies for real. The player must
# fight that possessed hero down to exactly 1 HP (no partial-heal floor — the
# normal between-round row heal tops it up afterward like any other survivor)
# to break the control and end the fight (see the "khagan_puppet" check in
# UnitBase/VisualUnit.die() and AutoBattleManager.end_khagan_possession).
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
	u.resistance      = 22
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

	u.skill_name = "Shell Slam"
	u.skill_damage_multiplier = 1.7
	u.skill_range = 1
	u.skill_cooldown_max = 3
	u.skill_mana_cost = 0

	if lvl > 1: u.set_level(lvl)
	u.set_meta("khagan_phase", 1)
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
			bg.remove_unit(anchor)
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
		if unit.has_method("rebuild_sprite"):
			unit.rebuild_sprite()
		return true

	elif phase == 2:
		if unit.battle_manager and unit.battle_manager.has_method("start_khagan_possession"):
			unit.battle_manager.start_khagan_possession(unit)
		return false   # Khagan's own body really dies now — the puppet carries the fight

	return false

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
	u.resistance      = 24
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
	# (own-element affinity now comes from set_affinity_profile — 2026-07-16)

	u.skill_name = "Serpent Strike"
	u.skill_damage_multiplier = 1.2
	u.skill_range = 1
	u.skill_cooldown_max = 5
	u.skill_mana_cost = 0
	u.skill_description = "Each head bites a different nearby target for 120% ATK (scales with own elemental affinity). Grows another head every 20s survived, up to 4. · 5s CD"
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
