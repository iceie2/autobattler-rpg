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

@onready var action_panel       = $UI/ActionPanel
@onready var action_toggle_btn  = $UI/ActionPanel/VBoxContainer/ActionToggleBtn
@onready var spawn_hero_btn     = $UI/ActionPanel/VBoxContainer/spawn_heroBtn
@onready var use_items_btn      = $UI/ActionPanel/VBoxContainer/UseItemsBtn
@onready var classes_btn        = $UI/ActionPanel/VBoxContainer/ClassesBtn
@onready var roster_btn         = $UI/ActionPanel/VBoxContainer/RosterBtn
@onready var ready_btn          = $UI/ActionPanel/VBoxContainer/ReadyBtn

const ACTION_PANEL_EXPANDED_BOTTOM  := 218.0
const ACTION_PANEL_COLLAPSED_BOTTOM := 42.0
var _action_panel_expanded := true
var _action_panel_style: StyleBoxFlat   # held in GDScript to survive layout changes

# Team status panel
@onready var team_stats_panel = $UI/TeamStatsPanel
@onready var team_toggle_btn  = $UI/TeamStatsPanel/VBox/TeamToggleBtn
@onready var player_hp_bar    = $UI/TeamStatsPanel/VBox/PlayerHPBar
@onready var player_hp_label  = $UI/TeamStatsPanel/VBox/PlayerHPLabel
@onready var player_unit_list = $UI/TeamStatsPanel/VBox/PlayerUnitList
@onready var enemy_hp_bar     = $UI/TeamStatsPanel/VBox/EnemyHPBar
@onready var enemy_hp_label   = $UI/TeamStatsPanel/VBox/EnemyHPLabel
@onready var enemy_unit_list  = $UI/TeamStatsPanel/VBox/EnemyUnitList

const TEAM_PANEL_COLLAPSED_BOTTOM := 278.0
const TEAM_PANEL_EXPANDED_BOTTOM  := 880.0
var _team_panel_expanded := false

# Damage meter
@onready var damage_meter_panel = $UI/DamageMeterPanel
@onready var dm_toggle_btn      = $UI/DamageMeterPanel/DMVBox/DMToggleBtn
@onready var dm_tab_row         = $UI/DamageMeterPanel/DMVBox/DMTabRow
@onready var dm_list            = $UI/DamageMeterPanel/DMVBox/DMList
@onready var dm_ally_btn        = $UI/DamageMeterPanel/DMVBox/DMTabRow/AllyTabBtn
@onready var dm_enemy_btn       = $UI/DamageMeterPanel/DMVBox/DMTabRow/EnemyTabBtn
const DM_COLLAPSED_BOTTOM := 942.0
const DM_EXPANDED_BOTTOM  := 1200.0
var _dm_expanded := false
var _dm_show_allies := true

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
var _panel_dragging: bool = false
var _character_menu: CharacterMenu
var _class_browser: ClassBrowser
var _hero_shop: HeroShop
var _game_over_screen: GameOverScreen

# Run tracking (reset each new game)
var _run_kills: int = 0

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
	battle_grid.grid_width = 20
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

	pass  # no pre-placed units

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
	spawn_hero_btn.pressed.connect(_on_spawn_hero_pressed)
	use_items_btn.pressed.connect(_on_use_items_pressed)
	classes_btn.pressed.connect(_on_classes_pressed)
	roster_btn.pressed.connect(_on_roster_pressed)
	ready_btn.pressed.connect(_on_ready_pressed)
	details_close_btn.pressed.connect(_on_details_close_pressed)
	unit_details_panel.gui_input.connect(_on_details_panel_input)
	# Cache the action panel's StyleBoxFlat so we can re-apply it after
	# every offset change (Godot 4 drops theme_override_styles on layout updates)
	var raw: StyleBox = action_panel.get_theme_stylebox("panel")
	if raw is StyleBoxFlat:
		_action_panel_style = (raw as StyleBoxFlat).duplicate()
	else:
		_action_panel_style = StyleBoxFlat.new()
		_action_panel_style.bg_color    = Color(0.12, 0.12, 0.18, 0.95)
		_action_panel_style.border_color = Color(0.4, 0.4, 0.5, 1)
		_action_panel_style.border_width_left   = 2
		_action_panel_style.border_width_right  = 2
		_action_panel_style.border_width_top    = 2
		_action_panel_style.border_width_bottom = 2
		_action_panel_style.corner_radius_top_left     = 4
		_action_panel_style.corner_radius_top_right    = 4
		_action_panel_style.corner_radius_bottom_left  = 4
		_action_panel_style.corner_radius_bottom_right = 4

	action_toggle_btn.pressed.connect(_on_action_toggle)
	team_toggle_btn.pressed.connect(_on_team_toggle)
	_set_team_panel_content_visible(false)
	dm_toggle_btn.pressed.connect(_on_dm_toggle)
	dm_ally_btn.pressed.connect(func(): _dm_show_allies = true;  _rebuild_damage_meter())
	dm_enemy_btn.pressed.connect(func(): _dm_show_allies = false; _rebuild_damage_meter())

	# All three panels are draggable
	action_panel.gui_input.connect(_make_panel_drag_handler(action_panel))
	team_stats_panel.gui_input.connect(_make_panel_drag_handler(team_stats_panel))
	damage_meter_panel.gui_input.connect(_make_panel_drag_handler(damage_meter_panel))

	var cm_scene := load("res://scenes/character_menu.tscn") as PackedScene
	_character_menu = cm_scene.instantiate() as CharacterMenu
	add_child(_character_menu)

	var cb_scene := load("res://scenes/class_browser.tscn") as PackedScene
	_class_browser = cb_scene.instantiate() as ClassBrowser
	add_child(_class_browser)

	var hs_scene := load("res://scenes/hero_shop.tscn") as PackedScene
	_hero_shop = hs_scene.instantiate() as HeroShop
	_hero_shop.hero_chosen.connect(_on_hero_chosen)
	add_child(_hero_shop)

	var go_scene := load("res://scenes/game_over_screen.tscn") as PackedScene
	_game_over_screen = go_scene.instantiate() as GameOverScreen
	add_child(_game_over_screen)


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


var max_player_units: int = 6   # base cap; increased by Roster Expansion upgrade

func start_new_game() -> void:
	game_state.gold = 50 + Progression.starting_gold_bonus()
	game_state.crystals = 0
	_run_kills = 0
	max_player_units = 6 + Progression.get_bonus("hero_slots")
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
	spawn_hero_btn.disabled = not enabled
	use_items_btn.disabled = not enabled
	ready_btn.disabled = not enabled
	# Info buttons always accessible
	classes_btn.disabled = false
	roster_btn.disabled = false

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
	update_team_health_bars()
	if _dm_expanded:
		_rebuild_damage_meter()

const VICTORY_ROUND := 7   # completing this round triggers the victory screen

func _on_battle_ended(player_won: bool) -> void:
	if player_won:
		# Check if the player just cleared the final scripted wave
		if game_state.battle_round >= VICTORY_ROUND:
			Progression.add_crystals(game_state.crystals)
			var total_dmg := 0
			for pu in player_units:
				if pu and is_instance_valid(pu):
					total_dmg += pu.damage_dealt
			_game_over_screen.show_victory(
				game_state.crystals, game_state.battle_round, total_dmg, _run_kills)
			return

		info_label.text = "Victory! You won the battle. +50 gold!"
		game_state.add_gold(50)
		clear_enemy_units()
		reset_player_positions()
	else:
		# Save crystals earned this run to the persistent wallet
		Progression.add_crystals(game_state.crystals)

		var total_dmg := 0
		for pu in player_units:
			if pu and is_instance_valid(pu):
				total_dmg += pu.damage_dealt

		_game_over_screen.show_defeat(
			game_state.crystals,       # earned this run
			game_state.battle_round,
			total_dmg,
			_run_kills
		)
		return

	update_ui()
	await get_tree().create_timer(2.0).timeout
	game_state.start_battle_round()

func _on_unit_action(_unit, _action_type: String) -> void:
	update_team_health_bars()
	if _dm_expanded:
		_rebuild_damage_meter()


func update_team_health_bars() -> void:
	var p_cur := 0
	var p_max := 0
	var p_alive := 0
	for unit in player_units:
		if unit and is_instance_valid(unit):
			p_cur += unit.current_hp
			p_max += unit.max_hp
			p_alive += 1

	var e_cur := 0
	var e_max := 0
	var e_alive := 0
	for unit in enemy_units:
		if unit and is_instance_valid(unit):
			e_cur += unit.current_hp
			e_max += unit.max_hp
			e_alive += 1

	if p_max > 0:
		player_hp_bar.max_value = p_max
		player_hp_bar.value = p_cur
		var pct := int(float(p_cur) / p_max * 100)
		player_hp_label.text = "%d / %d HP  |  %d units  |  %d%%" % [p_cur, p_max, p_alive, pct]
	else:
		player_hp_bar.value = 0
		player_hp_label.text = "No units"

	if e_max > 0:
		enemy_hp_bar.max_value = e_max
		enemy_hp_bar.value = e_cur
		var pct := int(float(e_cur) / e_max * 100)
		enemy_hp_label.text = "%d / %d HP  |  %d units  |  %d%%" % [e_cur, e_max, e_alive, pct]
	else:
		enemy_hp_bar.value = 0
		enemy_hp_label.text = "No units"

	_rebuild_unit_list(player_unit_list, player_units, Color(0.35, 0.92, 0.45, 1))
	_rebuild_unit_list(enemy_unit_list,  enemy_units,  Color(0.95, 0.4,  0.4,  1))

func _rebuild_unit_list(container: VBoxContainer, units: Array, name_color: Color) -> void:
	for child in container.get_children():
		child.queue_free()

	for unit in units:
		if not (unit and is_instance_valid(unit)):
			continue

		# Unit header: name + level
		var header := Label.new()
		header.text = "● %s   Lv.%d" % [unit.unit_name, unit.level]
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", name_color)
		container.add_child(header)

		# HP / MP / XP bars stacked
		_add_stat_bar(container, "HP", unit.current_hp,   unit.max_hp,      Color(0.2,  0.78, 0.3,  1))
		_add_stat_bar(container, "MP", unit.current_mana, unit.max_mana,    Color(0.25, 0.4,  0.9,  1))
		_add_stat_bar(container, "XP", unit.current_xp,   unit.xp_to_level, Color(0.85, 0.65, 0.1,  1))

		# Small gap between units
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 5)
		container.add_child(gap)

func _add_stat_bar(container: VBoxContainer, lbl_text: String,
		current: int, maximum: int, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	# Fixed-width stat label (HP / MP / XP)
	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.custom_minimum_size = Vector2(20, 12)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", color.lightened(0.25))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	# Current / max numbers
	var nums := Label.new()
	nums.text = "%d / %d" % [current, maximum]
	nums.custom_minimum_size = Vector2(90, 12)
	nums.add_theme_font_size_override("font_size", 10)
	nums.add_theme_color_override("font_color", Color(0.72, 0.72, 0.85, 1))
	nums.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nums.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(nums)

	# Bar
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	bar.max_value = max(maximum, 1)
	bar.value     = current
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 2; fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2; fill.corner_radius_bottom_right = 2
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(color.r * 0.18, color.g * 0.18, color.b * 0.18)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)

	container.add_child(row)

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


func _on_spawn_hero_pressed() -> void:
	if not shop_open:
		info_label.text = "Shop is closed!"
		return
	if game_state.gold < HeroShop.HERO_COST:
		info_label.text = "Not enough gold! Need %d gold." % HeroShop.HERO_COST
		return
	_hero_shop.open(game_state.gold)

func _apply_progression_bonuses(unit: VisualUnit) -> void:
	var hp_bonus: int = Progression.get_bonus("team_hp")
	if hp_bonus > 0:
		unit.max_hp += hp_bonus
		unit.current_hp += hp_bonus

func _on_hero_chosen(unit_class: UnitBase.UnitClass, element: UnitBase.Element) -> void:
	if not game_state.spend_gold(HeroShop.HERO_COST):
		info_label.text = "Not enough gold!"
		return
	var unit := UnitFactory.create_unit(unit_class, element, true)
	_apply_progression_bonuses(unit)
	var spawn_pos := find_empty_player_slot()
	if spawn_pos == Vector2i(-1, -1):
		info_label.text = "No room for more units!"
		# Refund
		game_state.add_gold(HeroShop.HERO_COST)
		return
	unit.grid_position = spawn_pos
	unit.position = battle_grid.grid_to_world(spawn_pos)
	battle_grid_node.add_child(unit)
	if battle_grid.place_unit(unit, spawn_pos):
		player_units.append(unit)
		unit.died.connect(_on_unit_died.bind(unit))
		unit.battle_manager = auto_battle_manager
		unit.damage_text_container = damage_text_container
		info_label.text = "Added %s to your team!" % unit.unit_name
	else:
		unit.queue_free()
		game_state.add_gold(HeroShop.HERO_COST)
	update_ui()


func _on_use_items_pressed() -> void:
	info_label.text = "Use Items - Not yet implemented"

func _on_classes_pressed() -> void:
	_class_browser.open(0)

func _on_roster_pressed() -> void:
	_character_menu.open(player_units, enemy_units, true)

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

func _on_action_toggle() -> void:
	_action_panel_expanded = not _action_panel_expanded
	var vbox := action_panel.get_node("VBoxContainer")
	for i in range(1, vbox.get_child_count()):
		vbox.get_child(i).visible = _action_panel_expanded
	action_toggle_btn.text = "PLAYER ACTIONS  %s" % ("▼" if _action_panel_expanded else "▶")
	action_panel.offset_bottom = ACTION_PANEL_EXPANDED_BOTTOM if _action_panel_expanded else ACTION_PANEL_COLLAPSED_BOTTOM
	# Re-apply panel style — Godot 4 drops theme_override_styles on offset changes
	action_panel.add_theme_stylebox_override("panel", _action_panel_style)
	action_toggle_btn.release_focus()

# Shared draggable panel handler — returns a callable bound to the given panel
func _make_panel_drag_handler(panel: Control) -> Callable:
	var dragging := [false]
	return func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging[0] = event.pressed
		elif event is InputEventMouseMotion and dragging[0]:
			panel.position += event.relative

func _on_dm_toggle() -> void:
	_dm_expanded = not _dm_expanded
	dm_tab_row.visible = _dm_expanded
	dm_list.visible    = _dm_expanded
	dm_toggle_btn.text = "DAMAGE METER  %s" % ("▼" if _dm_expanded else "▶")
	damage_meter_panel.offset_bottom = DM_EXPANDED_BOTTOM if _dm_expanded else DM_COLLAPSED_BOTTOM
	if _dm_expanded:
		_rebuild_damage_meter()

func _rebuild_damage_meter() -> void:
	# Remove immediately (not deferred) so new labels aren't mixed with old ones
	for child in dm_list.get_children():
		dm_list.remove_child(child)
		child.free()
	var units := player_units if _dm_show_allies else enemy_units
	var name_col := Color(0.35, 0.92, 0.45) if _dm_show_allies else Color(0.95, 0.38, 0.38)

	# Sort by damage_dealt descending
	var sorted := units.filter(func(u): return u and is_instance_valid(u))
	sorted.sort_custom(func(a, b): return a.damage_dealt > b.damage_dealt)
	var total_dmg := 0
	for u in sorted:
		total_dmg += u.damage_dealt

	var rank := 1
	for u in sorted:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		# Rank + name
		var name_lbl := Label.new()
		name_lbl.text = "#%d  %s" % [rank, u.unit_name]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", name_col)
		row.add_child(name_lbl)

		# Damage bar
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(80, 10)
		bar.size_flags_horizontal = 0
		bar.max_value = max(total_dmg, 1)
		bar.value = u.damage_dealt
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(1.0, 0.65, 0.1)
		fill.corner_radius_top_left = 2; fill.corner_radius_top_right = 2
		fill.corner_radius_bottom_left = 2; fill.corner_radius_bottom_right = 2
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.18, 0.12, 0.04)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		row.add_child(bar)

		# Damage number + share
		var pct := int(float(u.damage_dealt) / max(total_dmg, 1) * 100)
		var num_lbl := Label.new()
		num_lbl.text = "  %d  (%d%%)" % [u.damage_dealt, pct]
		num_lbl.custom_minimum_size = Vector2(100, 0)
		num_lbl.add_theme_font_size_override("font_size", 10)
		num_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
		row.add_child(num_lbl)

		dm_list.add_child(row)
		rank += 1

func _on_team_toggle() -> void:
	_team_panel_expanded = not _team_panel_expanded
	_set_team_panel_content_visible(_team_panel_expanded)
	team_toggle_btn.text = "TEAM STATUS  %s" % ("▼" if _team_panel_expanded else "▶")
	team_stats_panel.offset_bottom = TEAM_PANEL_EXPANDED_BOTTOM if _team_panel_expanded else TEAM_PANEL_COLLAPSED_BOTTOM

func _set_team_panel_content_visible(show: bool) -> void:
	var vbox := team_stats_panel.get_node("VBox")
	for i in range(1, vbox.get_child_count()):
		vbox.get_child(i).visible = show

func _on_details_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_panel_dragging = event.pressed
	elif event is InputEventMouseMotion and _panel_dragging:
		unit_details_panel.position += event.relative

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
	info_label.text = "Shop open! Buy heroes then click READY FOR BATTLE."
	update_ui()

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
	var round := game_state.battle_round
	var formation := WaveData.get_wave(round)

	if formation.is_empty():
		# Round 4+: procedural scaling
		var count: int = min(3 + (round - 1) * 2, 10)
		for i in range(count):
			var is_last := (i == count - 1)
			var lvl := _enemy_level_for_round(round, is_last)
			var unit := UnitFactory.create_random_class_unit(false)
			if lvl > 1: unit.set_level(lvl)
			_place_enemy(unit)
		return

	# ── Parse the formation grid ───────────────────────────────────────────
	# Each row string is split by spaces; tokens map to grid columns.
	# The token array is centred in the 22-wide battle grid automatically.
	for row_idx in range(formation.size()):
		var row_str: String = formation[row_idx]
		if row_str.strip_edges() == "":
			continue

		var tokens := row_str.split(" ", false)
		var width: int = tokens.size()
		var start_x: int = int(battle_grid.grid_width / 2) - width / 2

		for col_idx in range(width):
			var code: String = tokens[col_idx]
			var grid_pos := Vector2i(start_x + col_idx, row_idx)

			match code:
				".", "0":
					pass   # empty cell
				"M":
					_place_at(EnemyFactory.create_goblin(), grid_pos)
				"A":
					_place_at(EnemyFactory.create_goblin_archer(), grid_pos)
				"S":
					_place_at(EnemyFactory.create_goblin_shaman(), grid_pos)
				"B":
					_place_at(EnemyFactory.create_orc_brute(), grid_pos)
				"G":
					_place_at(EnemyFactory.create_hill_giant(), grid_pos)

# Place any unit at an explicit grid position (respects cell_size for 2×2 units)
func _place_at(unit: VisualUnit, grid_pos: Vector2i) -> void:
	unit.grid_position = grid_pos
	var world := battle_grid.grid_to_world(grid_pos)
	# 2×2 units: offset visual centre so sprite aligns to the middle of the 2×2 block
	if unit.cell_size == 2:
		world += Vector2(battle_grid.cell_size * 0.5, battle_grid.cell_size * 0.5)
	unit.position = world
	battle_grid_node.add_child(unit)
	if battle_grid.place_unit(unit, grid_pos):
		enemy_units.append(unit)
		unit.died.connect(_on_unit_died.bind(unit))
		unit.battle_manager = auto_battle_manager
		unit.damage_text_container = damage_text_container
	else:
		unit.queue_free()

# Slot-fill for procedural rounds (keeps existing behaviour)
func _place_enemy(unit: VisualUnit) -> void:
	var spawn_pos := find_empty_enemy_slot()
	if spawn_pos == Vector2i(-1, -1):
		unit.queue_free()
		return
	_place_at(unit, spawn_pos)

func _enemy_level_for_round(round: int, is_elite: bool) -> int:
	if is_elite and round % 5 == 0:
		return min(round / 5 + 2, 8)
	if is_elite and round >= 4:
		return min(round / 2, 5)
	if round <= 2: return 1
	return 1 + randi() % min(round / 2, 3)

func find_empty_player_slot() -> Vector2i:
	if player_units.size() >= max_player_units:
		return Vector2i(-1, -1)
	for y in range(battle_grid.grid_height - 4, battle_grid.grid_height):
		for x in range(battle_grid.grid_width):
			var p := Vector2i(x, y)
			if not battle_grid.is_cell_occupied(p):
				return p
	return Vector2i(-1, -1)

func find_empty_enemy_slot() -> Vector2i:
	# Top 4 rows of the grid (rows 0-3)
	for y in range(4):
		for x in range(battle_grid.grid_width):
			var p := Vector2i(x, y)
			if not battle_grid.is_cell_occupied(p):
				return p
	return Vector2i(-1, -1)

func clear_enemy_units() -> void:
	for unit in enemy_units:
		if unit and is_instance_valid(unit):
			battle_grid.remove_unit(unit.grid_position)
			unit.queue_free()
	enemy_units.clear()

func reset_player_positions() -> void:
	# Clear stale battle-manager path cache
	auto_battle_manager.unit_paths.clear()

	# Pull every player unit out of wherever it ended up in the grid
	for unit in player_units:
		if unit and is_instance_valid(unit):
			battle_grid.remove_unit(unit.grid_position)

	# Re-place each unit in a fresh player-zone slot and snap its visual position
	for unit in player_units:
		if not (unit and is_instance_valid(unit)):
			continue
		var slot := find_empty_player_slot()
		if slot == Vector2i(-1, -1):
			continue
		unit.grid_position = slot
		unit.position = battle_grid.grid_to_world(slot)
		battle_grid.place_unit(unit, slot)
		# Clear any leftover movement state from battle
		unit.is_moving = false
		unit.move_progress = 0.0
		unit.move_start_pos = unit.position
		unit.move_target_pos = unit.position

func _on_unit_died(unit) -> void:
	var was_enemy := enemy_units.has(unit)
	var dead_level: int = unit.level if (unit and is_instance_valid(unit)) else 1

	player_units.erase(unit)
	enemy_units.erase(unit)
	if unit and is_instance_valid(unit):
		battle_grid.remove_unit(unit.grid_position)

	if was_enemy and unit and is_instance_valid(unit):
		_run_kills += 1
		if unit.gold_reward > 0:
			game_state.add_gold(unit.gold_reward)
		var crystal_bonus: int = Progression.get_bonus("crystal_drop")
		if unit.crystal_reward + crystal_bonus > 0:
			game_state.add_crystals(unit.crystal_reward + crystal_bonus)
		update_ui()
		var xp_reward: int = 60 + (dead_level - 1) * 40
		for pu in player_units:
			if pu and is_instance_valid(pu):
				pu.grant_xp(xp_reward)

	update_team_health_bars()
