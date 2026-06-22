extends Node2D

# Node references
@onready var game_state_node = $GameState
@onready var battle_grid_node = $BattleGrid
@onready var auto_battle_manager_node = $AutoBattleManager

# UI references
@onready var gold_label = $UI/TopBar/GoldLabel
@onready var crystals_label = $UI/TopBar/CrystalsLabel
@onready var round_label = $UI/TopBar/RoundLabel
@onready var state_label = $UI/TopBar/StateLabel
@onready var info_label = $UI/BottomBar/InfoLabel

@onready var change_element_btn = $UI/ActionPanel/VBoxContainer/ChangeElementBtn
@onready var spawn_hero_btn = $UI/ActionPanel/VBoxContainer/spawn_heroBtn
@onready var use_items_btn = $UI/ActionPanel/VBoxContainer/UseItemsBtn
@onready var ready_btn = $UI/ActionPanel/VBoxContainer/ReadyBtn

# Unit details panel
@onready var unit_details_panel = $UI/UnitDetailsPanel
@onready var details_title = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/TitleBar/TitleLabel
@onready var details_close_btn = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/TitleBar/CloseBtn
@onready var details_unit_name = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/UnitName
@onready var details_class = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/ClassLabel
@onready var details_element = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/ElementLabel
@onready var details_level = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/LevelLabel
@onready var details_hp = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/HPLabel
@onready var details_mana = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/ManaLabel
@onready var details_str = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/StrLabel
@onready var details_dex = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/DexLabel
@onready var details_int = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/IntLabel
@onready var details_res = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/ResLabel
@onready var details_attack = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/AttackLabel
@onready var details_magic = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/MagicLabel
@onready var details_defense = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/DefenseLabel
@onready var details_move_speed = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/MoveSpeedLabel
@onready var details_attack_range = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/AttackRangeLabel

# Offensive affinity labels
@onready var off_normal = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/OffNormalLabel
@onready var off_fire = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/OffFireLabel
@onready var off_water = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/OffWaterLabel
@onready var off_earth = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/OffEarthLabel
@onready var off_air = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/OffAirLabel
@onready var off_lightning = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/OffLightningLabel

# Defensive affinity labels
@onready var def_normal = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/DefNormalLabel
@onready var def_fire = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/DefFireLabel
@onready var def_water = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/DefWaterLabel
@onready var def_earth = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/DefEarthLabel
@onready var def_air = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/DefAirLabel
@onready var def_lightning = $UI/UnitDetailsPanel/ScrollContainer/VBoxContainer/DefLightningLabel

# Game components
var game_state: GameState
var battle_grid: BattleGrid
var auto_battle_manager: AutoBattleManager

# Projectile container
var projectile_container: Node2D
var damage_text_container: Node2D

# Unit management
var player_units: Array = []
var enemy_units: Array = []
var shop_open: bool = false

func _ready():
	initialize_game_components()
	connect_signals()
	start_new_game()

func initialize_game_components() -> void:
	# Create and attach GameState
	game_state = GameState.new()
	game_state_node.add_child(game_state)
	
	# Create and attach BattleGrid
	battle_grid = BattleGrid.new()
	battle_grid.grid_width = 22
	battle_grid.grid_height = 14
	battle_grid.cell_size = 64
	battle_grid_node.add_child(battle_grid)
	
	# Create projectile container
	projectile_container = Node2D.new()
	projectile_container.name = "ProjectileContainer"
	battle_grid_node.add_child(projectile_container)
	
	# Create damage text container
	damage_text_container = Node2D.new()
	damage_text_container.name = "DamageTextContainer"
	battle_grid_node.add_child(damage_text_container)

	# Create skill effect container
	var skill_effect_container := Node2D.new()
	skill_effect_container.name = "SkillEffectContainer"
	battle_grid_node.add_child(skill_effect_container)

	# Create and attach AutoBattleManager
	auto_battle_manager = AutoBattleManager.new()
	auto_battle_manager_node.add_child(auto_battle_manager)
	auto_battle_manager.initialize(battle_grid, game_state)
	auto_battle_manager.projectile_container = projectile_container
	auto_battle_manager.skill_effect_container = skill_effect_container

	# Integrate any pre-placed unit nodes in the scene into the runtime grid
	_integrate_scene_units()

func connect_signals() -> void:
	# Game state signals
	game_state.state_changed.connect(_on_state_changed)
	game_state.battle_round_started.connect(_on_battle_round_started)
	
	# Battle manager signals
	auto_battle_manager.battle_started.connect(_on_battle_started)
	auto_battle_manager.battle_ended.connect(_on_battle_ended)
	auto_battle_manager.unit_action.connect(_on_unit_action)
	
	# Grid signals
	battle_grid.cell_clicked.connect(_on_cell_clicked)
	battle_grid.unit_placed.connect(_on_unit_placed)
	
	# UI button signals
	change_element_btn.pressed.connect(_on_change_element_pressed)
	spawn_hero_btn.pressed.connect(_on_spawn_hero_pressed)
	use_items_btn.pressed.connect(_on_use_items_pressed)
	ready_btn.pressed.connect(_on_ready_pressed)
	details_close_btn.pressed.connect(_on_details_close_pressed)


func _integrate_scene_units() -> void:
	# Move any UnitBase-derived nodes under the runtime battle_grid and normalize them
	for child in battle_grid_node.get_children():
		if child == battle_grid:
			continue
		if child and child is UnitBase:
			var unit = child
			# Normalize element to NORMAL
			unit.current_element = UnitBase.Element.NORMAL
			# Compute grid position from current world position (if possible)
			var grid_pos = battle_grid.world_to_grid(unit.position)
			unit.grid_position = grid_pos
			# Determine ownership by row if not explicitly set
			if not unit:
				pass
			if grid_pos.y >= 10:
				unit.is_player_unit = true
			else:
				unit.is_player_unit = false
			# Reparent under the runtime battle_grid for consistent transforms
			unit.reparent(battle_grid)
			# Place into grid data structure
			if battle_grid.place_unit(unit, grid_pos):
				if unit.is_player_unit:
					player_units.append(unit)
				else:
					enemy_units.append(unit)
				unit.died.connect(_on_unit_died.bind(unit))
				unit.battle_manager = auto_battle_manager
				unit.damage_text_container = damage_text_container
				unit.update_visuals()


func start_new_game() -> void:
	game_state.gold = 10000
	game_state.crystals = 0
	game_state.start_battle_round()
	open_shop()

func update_ui() -> void:
	gold_label.text = "Gold: %d" % game_state.gold
	crystals_label.text = "Crystals: %d" % game_state.crystals
	round_label.text = "Round: %d" % game_state.battle_round
	
	match game_state.current_state:
		GameState.State.PLAYER_TURN:
			state_label.text = "PLAYER TURN"
			state_label.modulate = Color.GREEN
			enable_action_buttons(true)
		GameState.State.AUTO_BATTLE:
			state_label.text = "AUTO BATTLE"
			state_label.modulate = Color.ORANGE
			enable_action_buttons(false)
		GameState.State.ENEMY_TURN:
			state_label.text = "ENEMY TURN"
			state_label.modulate = Color.RED
			enable_action_buttons(false)
		GameState.State.GAME_OVER:
			state_label.text = "GAME OVER"
			state_label.modulate = Color.DARK_RED
			enable_action_buttons(false)

func enable_action_buttons(enabled: bool) -> void:
	change_element_btn.disabled = not enabled
	spawn_hero_btn.disabled = not enabled
	use_items_btn.disabled = not enabled
	ready_btn.disabled = not enabled

func enable_unit_dragging(enabled: bool) -> void:
	for unit in player_units:
		if unit and is_instance_valid(unit) and unit is VisualUnit:
			unit.can_be_dragged = enabled
	for unit in enemy_units:
		if unit and is_instance_valid(unit) and unit is VisualUnit:
			unit.can_be_dragged = enabled

# Signal handlers
func _on_state_changed(new_state: GameState.State) -> void:
	update_ui()
	
	match new_state:
		GameState.State.PLAYER_TURN:
			if not shop_open:
				open_shop()
			enable_unit_dragging(true)
			info_label.text = "Your turn! Buy units, drag them to position (bottom 4 rows), and click READY."
		GameState.State.AUTO_BATTLE:
			enable_unit_dragging(false)
			info_label.text = "Auto battle in progress... No player actions allowed."
		GameState.State.ENEMY_TURN:
			enable_unit_dragging(false)
			info_label.text = "Enemy turn in progress..."

func _on_battle_round_started(round_number: int) -> void:
	update_ui()
	print("Battle round %d started!" % round_number)

func _on_battle_started() -> void:
	enable_unit_dragging(false)
	info_label.text = "Battle started! Units are fighting automatically."
	close_shop()

func _on_battle_ended(player_won: bool) -> void:
	if player_won:
		info_label.text = "Victory! You won the battle. +50 gold!"
		game_state.add_gold(50)
		clear_enemy_units()
	else:
		info_label.text = "Defeat! Your units were destroyed."
		game_state.change_state(GameState.State.GAME_OVER)
		return
	
	update_ui()
	# Wait a moment then start next round
	await get_tree().create_timer(2.0).timeout
	game_state.start_battle_round()

func _on_unit_action(_unit, _action_type: String) -> void:
	# Visual feedback for unit actions could go here
	pass

func _on_cell_clicked(grid_pos: Vector2i) -> void:
	# Right-click to show unit details
	if battle_grid.is_cell_occupied(grid_pos):
		var unit = battle_grid.get_unit_at(grid_pos)
		if unit and unit is UnitBase:
			show_unit_details(unit)
		return
	
	info_label.text = "Right-clicked grid cell: (%d, %d)" % [grid_pos.x, grid_pos.y]

func _on_unit_placed(_unit, grid_pos: Vector2i) -> void:
	info_label.text = "Unit placed at: (%d, %d)" % [grid_pos.x, grid_pos.y]

# Action button handlers
func _on_change_element_pressed() -> void:
		info_label.text = "Use Items - Not yet implemented"

func _on_spawn_hero_pressed() -> void:
	if not shop_open:
		info_label.text = "Shop is closed!"
		return
	
	var cost = 30
	if game_state.spend_gold(cost):
		spawn_random_player_unit()
		info_label.text = "Bought a random unit for %d gold!" % cost
		update_ui()
	else:
		info_label.text = "Not enough gold! Need %d gold." % cost


func _on_use_items_pressed() -> void:
	info_label.text = "Use Items - Not yet implemented"

func _on_ready_pressed() -> void:
	if player_units.is_empty():
		info_label.text = "You need at least one unit to battle!"
		return
	
	close_shop()
	spawn_enemies()
	game_state.player_ready_for_battle()

# Unit Details Panel
func show_unit_details(unit: UnitBase) -> void:
	unit_details_panel.visible = true
	
	# Update all labels
	details_unit_name.text = unit.unit_name
	details_class.text = "Class: " + unit.get_class_name_string()
	details_element.text = "Element: " + unit.get_element_name_string()
	details_level.text = "Level: %d" % unit.level
	
	details_hp.text = "HP: %d / %d" % [unit.current_hp, unit.max_hp]
	details_mana.text = "Mana: %d / %d" % [unit.current_mana, unit.max_mana]
	details_str.text = "STR: %d" % unit.strength
	details_dex.text = "DEX: %d" % unit.dexterity
	details_int.text = "INT: %d" % unit.intelligence
	details_res.text = "RES: %d" % unit.resistance
	
	details_attack.text = "Attack Damage: %d" % unit.attack_damage
	details_magic.text = "Magic Power: %d" % unit.magic_power
	details_defense.text = "Defense: %d" % unit.defense
	
	details_move_speed.text = "Movement Speed: %d" % unit.movement_speed
	details_attack_range.text = "Attack Range: %d" % unit.attack_range
	
	# Display offensive affinity for each element with colors
	update_affinity_label(off_normal, "Normal", unit.offensive_affinity[UnitBase.Element.NORMAL], UnitBase.Element.NORMAL, true)
	update_affinity_label(off_fire, "Fire", unit.offensive_affinity[UnitBase.Element.FIRE], UnitBase.Element.FIRE, true)
	update_affinity_label(off_water, "Water", unit.offensive_affinity[UnitBase.Element.WATER], UnitBase.Element.WATER, true)
	update_affinity_label(off_earth, "Earth", unit.offensive_affinity[UnitBase.Element.EARTH], UnitBase.Element.EARTH, true)
	update_affinity_label(off_air, "Air", unit.offensive_affinity[UnitBase.Element.AIR], UnitBase.Element.AIR, true)
	update_affinity_label(off_lightning, "Lightning", unit.offensive_affinity[UnitBase.Element.LIGHTNING], UnitBase.Element.LIGHTNING, true)
	
	# Display defensive affinity for each element with colors
	update_affinity_label(def_normal, "Normal", unit.defensive_affinity[UnitBase.Element.NORMAL], UnitBase.Element.NORMAL, false)
	update_affinity_label(def_fire, "Fire", unit.defensive_affinity[UnitBase.Element.FIRE], UnitBase.Element.FIRE, false)
	update_affinity_label(def_water, "Water", unit.defensive_affinity[UnitBase.Element.WATER], UnitBase.Element.WATER, false)
	update_affinity_label(def_earth, "Earth", unit.defensive_affinity[UnitBase.Element.EARTH], UnitBase.Element.EARTH, false)
	update_affinity_label(def_air, "Air", unit.defensive_affinity[UnitBase.Element.AIR], UnitBase.Element.AIR, false)
	update_affinity_label(def_lightning, "Lightning", unit.defensive_affinity[UnitBase.Element.LIGHTNING], UnitBase.Element.LIGHTNING, false)

func _on_details_close_pressed() -> void:
	unit_details_panel.visible = false

func update_affinity_label(label: RichTextLabel, element_name: String, value: float, element: UnitBase.Element, is_offensive: bool) -> void:
	var color = get_element_color_hex(element)
	
	if is_offensive:
		# Offensive: show as percentage
		label.text = "[color=%s]%s: +%.0f%%[/color]" % [color, element_name, value]
	else:
		# Defensive: show value and reduction percentage
		var reduction_pct = (1.0 - (1.0 - (value / (value + 100.0)))) * 100
		label.text = "[color=%s]%s: %.0f (%.1f%% reduction)[/color]" % [color, element_name, value, reduction_pct]

func get_element_color_hex(element: UnitBase.Element) -> String:
	match element:
		UnitBase.Element.FIRE:
			return "#FF4D00"  # Orange-red
		UnitBase.Element.WATER:
			return "#33AAFF"  # Blue
		UnitBase.Element.EARTH:
			return "#B38052"  # Brown
		UnitBase.Element.AIR:
			return "#CCFFFF"  # Light cyan
		UnitBase.Element.LIGHTNING:
			return "#FFFF33"  # Yellow
		UnitBase.Element.NORMAL:
			return "#FFFFFF"  # White
		_:
			return "#FFFFFF"

# Shop and spawning functions
func open_shop() -> void:
	shop_open = true
	info_label.text = "Shop is open! Click 'Change Element' to buy random units (30 gold each)"
	update_ui()
	
	# If this is the first round, give player 3 free starting units
	if game_state.battle_round == 1 and player_units.is_empty():
		for i in range(3):
			spawn_random_player_unit()
		info_label.text = "You start with 3 random units! Buy more or click READY to fight."

func close_shop() -> void:
	shop_open = false

func spawn_random_player_unit() -> void:
	# Find empty slot in player area (left side of grid)
	var spawn_pos = find_empty_player_slot()
	if spawn_pos == Vector2i(-1, -1):
		info_label.text = "No room for more units!"
		return

	# Create random player unit via factory
	var unit = UnitFactory.create_random_class_unit(true)

	unit.grid_position = spawn_pos
	var world_pos = battle_grid.grid_to_world(spawn_pos)
	unit.position = world_pos

	battle_grid_node.add_child(unit)
	if battle_grid.place_unit(unit, spawn_pos):
		player_units.append(unit)
		unit.died.connect(_on_unit_died.bind(unit))
		unit.battle_manager = auto_battle_manager  # Set reference
		unit.damage_text_container = damage_text_container  # Set reference
	else:
		unit.queue_free()

func spawn_enemies() -> void:
	# Spawn 3 random enemy units on right side
	for i in range(3):
		var spawn_pos = find_empty_enemy_slot()
		if spawn_pos == Vector2i(-1, -1):
			continue
		
		var unit = UnitFactory.create_random_class_unit(false)
		unit.grid_position = spawn_pos
		
		var world_pos = battle_grid.grid_to_world(spawn_pos)
		unit.position = world_pos
		
		battle_grid_node.add_child(unit)
		if battle_grid.place_unit(unit, spawn_pos):
			enemy_units.append(unit)
			unit.died.connect(_on_unit_died.bind(unit))
			unit.battle_manager = auto_battle_manager  # Set reference
			unit.damage_text_container = damage_text_container  # Set reference
		else:
			unit.queue_free()

func find_empty_player_slot() -> Vector2i:
	# Player units in center-bottom area (rows 10-13, middle columns)
	var center_x = int(battle_grid.grid_width / 2)
	var search_width = 10  # Search within 10 columns centered
	var start_x = center_x - search_width / 2
	
	# Search bottom 4 rows (rows 10-13)
	for y in range(10, 14):
		for offset in range(search_width):
			var x = start_x + offset
			if x >= 0 and x < battle_grid.grid_width:
				var pos = Vector2i(x, y)
				if not battle_grid.is_cell_occupied(pos):
					return pos
	return Vector2i(-1, -1)

func find_empty_enemy_slot() -> Vector2i:
	# Enemy units in center-top area (rows 0-3, middle columns)
	var center_x = int(battle_grid.grid_width / 2)
	var search_width = 10  # Search within 10 columns centered
	var start_x = center_x - search_width / 2
	
	# Search top 4 rows (rows 0-3)
	for y in range(4):
		for offset in range(search_width):
			var x = start_x + offset
			if x >= 0 and x < battle_grid.grid_width:
				var pos = Vector2i(x, y)
				if not battle_grid.is_cell_occupied(pos):
					return pos
	return Vector2i(-1, -1)

func clear_enemy_units() -> void:
	for unit in enemy_units:
		if unit and is_instance_valid(unit):
			battle_grid.remove_unit(unit.grid_position)
			unit.queue_free()
	enemy_units.clear()

func _on_unit_died(unit) -> void:
	player_units.erase(unit)
	enemy_units.erase(unit)
	if unit and is_instance_valid(unit):
		battle_grid.remove_unit(unit.grid_position)
