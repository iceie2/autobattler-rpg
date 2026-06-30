extends Node
class_name EnemyFactory

# ── Goblin (weak melee) ───────────────────────────────────────────────────────
static func create_goblin(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Goblin"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 150
	u.current_hp      = 150
	u.max_mana        = 20
	u.current_mana    = 20
	u.strength        = 17
	u.dexterity       = 9
	u.intelligence    = 3
	u.resistance      = 6
	u.movement_speed  = 4
	u.attack_range    = 1
	u.gold_reward     = 15
	u.crystal_reward  = 1
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
	u.max_hp          = 120
	u.current_hp      = 120
	u.max_mana        = 30
	u.current_mana    = 30
	u.strength        = 20
	u.dexterity       = 35
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

# ── Goblin Shaman (ranged magic support) ─────────────────────────────────────
static func create_goblin_shaman(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Goblin Shaman"
	u.unit_class      = UnitBase.UnitClass.BLACK_MAGE
	u.current_element = UnitBase.Element.FIRE
	u.is_player_unit  = false
	u.max_hp          = 300
	u.current_hp      = 240
	u.max_mana        = 60
	u.current_mana    = 30
	u.strength        = 5
	u.dexterity       = 8
	u.intelligence    = 18
	u.resistance      = 8
	u.movement_speed  = 2
	u.attack_range    = 4
	u.gold_reward     = 18
	u.crystal_reward  = 1
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "goblin_shaman")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Orc Brute (heavy melee bruiser) ──────────────────────────────────────────
static func create_orc_brute(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Orc Brute"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.max_hp          = 750
	u.current_hp      = 750
	u.max_mana        = 20
	u.current_mana    = 20
	u.strength        = 28
	u.dexterity       = 7
	u.intelligence    = 3
	u.resistance      = 14
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 25
	u.crystal_reward  = 1
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "orc_brute")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Slime (slow, tanky, low damage) ──────────────────────────────────────────
static func create_slime(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Slime"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.current_element = UnitBase.Element.WATER
	u.is_player_unit  = false
	u.max_hp          = 220
	u.current_hp      = 220
	u.max_mana        = 0
	u.current_mana    = 0
	u.strength        = 12
	u.dexterity       = 4
	u.intelligence    = 1
	u.resistance      = 14          # naturally tough, hits weak
	u.movement_speed  = 2           # sluggish
	u.attack_range    = 1
	u.gold_reward     = 12
	u.crystal_reward  = 0
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "slime")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Skeleton (fragile but hits hard, medium range) ────────────────────────────
static func create_skeleton(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Skeleton"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 110
	u.current_hp      = 110
	u.max_mana        = 0
	u.current_mana    = 0
	u.strength        = 22
	u.dexterity       = 12
	u.intelligence    = 2
	u.resistance      = 4           # brittle bones — low res
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 13
	u.crystal_reward  = 0
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "skeleton")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Rat (fast, very low HP, weak hit — swarms in numbers) ────────────────────
static func create_rat(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Rat"
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 75
	u.current_hp      = 75
	u.max_mana        = 0
	u.current_mana    = 0
	u.strength        = 10
	u.dexterity       = 28          # fast attacker
	u.intelligence    = 1
	u.resistance      = 3
	u.movement_speed  = 5           # fastest basic enemy
	u.attack_range    = 1
	u.gold_reward     = 10
	u.crystal_reward  = 0
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "rat")
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
	u.movement_speed  = 0          # stationary — attacks anything in range
	u.attack_range    = 2
	u.gold_reward     = 60
	u.crystal_reward  = 2
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "hill_giant")
	u.skill_name      = "Boulder Smash"
	u.skill_damage_multiplier = 2.0
	u.skill_range     = 2
	u.skill_cooldown_max = 4
	u.ultimate_charge_max = 0     # no ult
	if lvl > 1: u.set_level(lvl)
	return u
