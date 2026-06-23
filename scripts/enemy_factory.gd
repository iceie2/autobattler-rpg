extends Node
class_name EnemyFactory

# ── Goblin (weak melee) ───────────────────────────────────────────────────────
static func create_goblin(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Goblin"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 350
	u.current_hp      = 350
	u.max_mana        = 20
	u.current_mana    = 20
	u.strength        = 8
	u.dexterity       = 7
	u.intelligence    = 2
	u.resistance      = 5
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 15
	u.crystal_reward  = 0
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "goblin")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Goblin Archer (weak ranged) ───────────────────────────────────────────────
static func create_goblin_archer(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Goblin Archer"
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 220
	u.current_hp      = 220
	u.max_mana        = 30
	u.current_mana    = 30
	u.strength        = 5
	u.dexterity       = 11
	u.intelligence    = 3
	u.resistance      = 3
	u.movement_speed  = 2
	u.attack_range    = 4
	u.gold_reward     = 15
	u.crystal_reward  = 0
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "goblin_archer")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Hill Giant (stationary 2×2 boss, round 3) ────────────────────────────────
static func create_hill_giant(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Hill Giant"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.cell_size       = 2          # occupies a 2×2 area
	u.max_hp          = 2800
	u.current_hp      = 2800
	u.max_mana        = 100
	u.current_mana    = 100
	u.strength        = 22
	u.dexterity       = 4
	u.intelligence    = 3
	u.resistance      = 18
	u.movement_speed  = 1          # slow but does walk toward players
	u.attack_range    = 2
	u.gold_reward     = 60
	u.crystal_reward  = 2
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "hill_giant")
	u.skill_name      = "Boulder Smash"
	u.skill_damage_multiplier = 2.0
	u.skill_range     = 2
	u.skill_cooldown_max = 4
	u.ultimate_charge_max = 0
	if lvl > 1: u.set_level(lvl)
	return u

# ── Goblin Shaman (ranged magic caster) ──────────────────────────────────────
static func create_goblin_shaman(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Goblin Shaman"
	u.unit_class      = UnitBase.UnitClass.BLACK_MAGE
	u.current_element = UnitBase.Element.FIRE
	u.is_player_unit  = false
	u.max_hp = 280; u.current_hp = 280
	u.max_mana = 180; u.current_mana = 180
	u.strength = 4; u.dexterity = 6; u.intelligence = 14; u.resistance = 5; u.spirit = 8
	u.movement_speed = 2; u.attack_range = 4
	u.gold_reward = 20; u.crystal_reward = 1
	u.sprite_variant = randi() % 3
	u.set_meta("sprite_folder", "goblin_archer")
	u.skill_name = "Hex Bolt"; u.skill_damage_multiplier = 1.8
	u.skill_range = 4; u.skill_cooldown_max = 3; u.skill_mana_cost = 60
	u.ultimate_charge_max = 0
	if lvl > 1: u.set_level(lvl)
	return u

# ── Orc Brute (heavy slow melee tank) ────────────────────────────────────────
static func create_orc_brute(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Orc Brute"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.max_hp = 700; u.current_hp = 700
	u.max_mana = 50; u.current_mana = 50
	u.strength = 16; u.dexterity = 5; u.intelligence = 3; u.resistance = 14; u.spirit = 5
	u.movement_speed = 1; u.attack_range = 1
	u.gold_reward = 25; u.crystal_reward = 0
	u.sprite_variant = randi() % 3
	u.set_meta("sprite_folder", "goblin")
	u.skill_name = "Cleave"; u.skill_damage_multiplier = 1.4
	u.skill_range = 1; u.skill_cooldown_max = 4; u.ultimate_charge_max = 0
	if lvl > 1: u.set_level(lvl)
	return u
