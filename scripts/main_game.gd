extends Node2D

# Node references
@onready var game_state_node = $GameState
@onready var battle_grid_node = $BattleGrid
@onready var auto_battle_manager_node = $AutoBattleManager
@onready var background_layer = $Background

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

# Panel sizes are RELATIVE heights (added to each panel's offset_top), so you can
# freely move the panels in the editor and collapse/expand will follow.
const ACTION_PANEL_EXPANDED_HEIGHT  := 212.0
const ACTION_PANEL_COLLAPSED_HEIGHT := 36.0
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

const TEAM_PANEL_COLLAPSED_HEIGHT := 42.0
const TEAM_PANEL_EXPANDED_HEIGHT  := 644.0
var _team_panel_expanded := false

# Damage meter
@onready var damage_meter_panel = $UI/DamageMeterPanel
@onready var dm_toggle_btn      = $UI/DamageMeterPanel/DMVBox/DMToggleBtn
@onready var dm_tab_row         = $UI/DamageMeterPanel/DMVBox/DMTabRow
@onready var dm_scroll          = $UI/DamageMeterPanel/DMVBox/DMScroll
@onready var dm_list            = $UI/DamageMeterPanel/DMVBox/DMScroll/DMList
@onready var dm_ally_btn        = $UI/DamageMeterPanel/DMVBox/DMTabRow/AllyTabBtn
@onready var dm_enemy_btn       = $UI/DamageMeterPanel/DMVBox/DMTabRow/EnemyTabBtn
const DM_COLLAPSED_HEIGHT := 42.0
const DM_EXPANDED_HEIGHT  := 300.0
var _dm_expanded := false
# Damage-meter tab: 0 = Allies, 1 = Enemies
var _dm_tab := 0

# Event history (its own panel, below the damage meter)
@onready var event_history_panel = $UI/EventHistoryPanel
@onready var eh_toggle_btn       = $UI/EventHistoryPanel/EHVBox/EHToggleBtn
@onready var eh_scroll           = $UI/EventHistoryPanel/EHVBox/EHScroll
@onready var eh_list             = $UI/EventHistoryPanel/EHVBox/EHScroll/EHList
const EH_COLLAPSED_HEIGHT := 42.0
const EH_EXPANDED_HEIGHT  := 440.0
var _eh_expanded := false
var _event_log: Array = []   # [{text, is_player}, ...]

# Battle playback controls (built in code, shown only during AUTO_BATTLE)
var _battle_controls: Panel
var _btn_pause: Button
var _speed_buttons: Dictionary = {}   # scale (float) -> Button
const SPEED_OPTIONS: Array[float] = [0.25, 1.0, 2.0, 4.0]

# Wave difficulty panel (shown during prep phase each round)
var _difficulty_panel: Panel
var _diff_btns: Array = []
var _diff_power_lbl: Label
var current_difficulty: int = WaveScaler.Difficulty.EASY

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
var _level_up_screen: LevelUpScreen
var _equipment_inventory: EquipmentInventory
var _equipment_panel: EquipmentPanel
var _event_panel: EventPanel
var _game_over_screen: GameOverScreen

# Run tracking (reset each new game)
var _run_kills: int = 0

# ── Sidebar layout ────────────────────────────────────────────────────────────
const SIDEBAR_W  := 285.0
const _PANEL_DARK := Color(0.07, 0.06, 0.11, 0.94)
const _PANEL_MID  := Color(0.11, 0.09, 0.17, 0.94)
const _GOLD_COL   := Color(0.83, 0.69, 0.22, 1.0)
const _GOLD_DIM   := Color(0.83, 0.69, 0.22, 0.45)

var _left_panel:   PanelContainer
var _right_panel:  PanelContainer
var _synergy_list: VBoxContainer   # rebuilt when player roster changes

# Row-bonus tooltip (floats above grid on mouse hover)
var _row_tip:       Panel
var _row_tip_title: Label
var _row_tip_heal:  Label
var _row_tip_xp:    Label
var _row_tip_last:  int = -1   # last cell_y we displayed, avoids redundant updates

# Live unit details panel
var _details_unit:    UnitBase = null
var _details_hp_bar:  ProgressBar
var _details_mp_bar:  ProgressBar
var _details_xp_bar:  ProgressBar
var _details_xp_lbl:  Label

# Sidebar-native widgets (built fresh in code so sizing is reliable)
var _sb_player_hp:    ProgressBar
var _sb_player_lbl:   Label
var _sb_player_ulist: VBoxContainer
var _sb_enemy_hp:     ProgressBar
var _sb_enemy_lbl:    Label
var _sb_enemy_ulist:  VBoxContainer
var _sb_dm_list:      VBoxContainer

func _ready():
	initialize_game_components()
	connect_signals()
	_center_battlefield()
	get_viewport().size_changed.connect(_center_battlefield)
	battle_grid_node.y_sort_enabled = true
	_style_team_bar(player_hp_bar, Color(0.15, 0.78, 0.30, 1))
	_style_team_bar(enemy_hp_bar,  Color(0.88, 0.18, 0.18, 1))
	_build_new_layout()
	get_viewport().size_changed.connect(_position_sidebars)
	_create_row_tooltip()
	start_new_game()

# Centre the board within the usable area between the two sidebars.
func _center_battlefield() -> void:
	var board := Vector2(battle_grid.grid_width * battle_grid.cell_size,
						 battle_grid.grid_height * battle_grid.cell_size)
	var vp    := Vector2(get_viewport_rect().size)
	# Horizontal: centre in the strip between the two sidebars
	var usable_x := vp.x - SIDEBAR_W * 2.0
	var origin_x := SIDEBAR_W + (usable_x - board.x) / 2.0
	# Vertical: centre in the full height
	var origin_y := (vp.y - board.y) / 2.0
	var origin   := Vector2(origin_x, origin_y).round()
	background_layer.position = origin
	battle_grid_node.position = origin

func initialize_game_components() -> void:
	# Create and attach GameState
	game_state = GameState.new()
	game_state_node.add_child(game_state)
	
	# Create and attach BattleGrid
	battle_grid = BattleGrid.new()
	battle_grid.grid_width = 9
	battle_grid.grid_height = 9
	battle_grid.cell_size = 110
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
	auto_battle_manager.background_layer = background_layer

	pass  # no pre-placed units

func connect_signals() -> void:
	# Game state signals
	game_state.state_changed.connect(_on_state_changed)
	game_state.battle_round_started.connect(_on_battle_round_started)
	game_state.battle_round_started.connect(func(round_num): background_layer.set_biome_from_round(round_num))
	
	# Battle manager signals
	auto_battle_manager.battle_started.connect(_on_battle_started)
	auto_battle_manager.battle_ended.connect(_on_battle_ended)
	auto_battle_manager.unit_action.connect(_on_unit_action)
	auto_battle_manager.action_logged.connect(_on_action_logged)
	auto_battle_manager.pace_changed.connect(_on_pace_changed)
	auto_battle_manager.unit_summoned.connect(_on_unit_summoned)
	
	# Grid signals
	battle_grid.cell_clicked.connect(_on_cell_clicked)
	battle_grid.unit_placed.connect(_on_unit_placed)
	
	# UI button signals
	spawn_hero_btn.pressed.connect(_on_spawn_hero_pressed)
	use_items_btn.pressed.connect(_on_use_items_pressed)
	classes_btn.pressed.connect(_on_classes_pressed)
	roster_btn.pressed.connect(_on_roster_pressed)

	# Add equipment button to action panel
	# TODO: Re-enable synergy button after fixing syntax errors
	#var synergy_btn = Button.new()
	#synergy_btn.text = "Synergies"
	#synergy_btn.custom_minimum_size = Vector2(90, 36)
	#synergy_btn.add_theme_font_size_override("font_size", 12)
	#synergy_btn.pressed.connect(_on_synergies_pressed)
	#action_panel.get_node("VBoxContainer").add_child(synergy_btn)

	var equipment_btn = Button.new()
	equipment_btn.text = "Equipment"
	equipment_btn.custom_minimum_size = Vector2(90, 36)
	equipment_btn.add_theme_font_size_override("font_size", 12)
	equipment_btn.pressed.connect(_on_equipment_pressed)
	action_panel.get_node("VBoxContainer").add_child(equipment_btn)
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
	dm_ally_btn.pressed.connect(func(): _dm_tab = 0; _rebuild_damage_meter())
	dm_enemy_btn.pressed.connect(func(): _dm_tab = 1; _rebuild_damage_meter())
	eh_toggle_btn.pressed.connect(_on_eh_toggle)

	# Size each panel relative to its editor position so repositioning "just works"
	_apply_panel_height(action_panel, _action_panel_expanded, ACTION_PANEL_COLLAPSED_HEIGHT, ACTION_PANEL_EXPANDED_HEIGHT)
	_apply_panel_height(team_stats_panel, _team_panel_expanded, TEAM_PANEL_COLLAPSED_HEIGHT, TEAM_PANEL_EXPANDED_HEIGHT)
	_apply_panel_height(damage_meter_panel, _dm_expanded, DM_COLLAPSED_HEIGHT, DM_EXPANDED_HEIGHT)
	_apply_panel_height(event_history_panel, _eh_expanded, EH_COLLAPSED_HEIGHT, EH_EXPANDED_HEIGHT)
	action_panel.add_theme_stylebox_override("panel", _action_panel_style)

	# All three panels are draggable
	action_panel.gui_input.connect(_make_panel_drag_handler(action_panel))
	team_stats_panel.gui_input.connect(_make_panel_drag_handler(team_stats_panel))
	damage_meter_panel.gui_input.connect(_make_panel_drag_handler(damage_meter_panel))

	_build_battle_controls()
	_build_difficulty_panel()

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

	var lu_scene := load("res://scenes/level_up_screen.tscn") as PackedScene
	_level_up_screen = lu_scene.instantiate() as LevelUpScreen
	add_child(_level_up_screen)

	_equipment_inventory = EquipmentInventory.new()
	_equipment_panel = EquipmentPanel.new()
	add_child(_equipment_panel)

	_event_panel = EventPanel.new()
	_event_panel.event_choice_made.connect(_on_event_choice_made)
	add_child(_event_panel)

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
			# Snap units sitting on the dividing row (y=4) into the front player row
			if grid_pos.y == battle_grid.grid_height - 5:
				grid_pos.y = battle_grid.grid_height - 4
			unit.grid_position = grid_pos
			# Bottom 4 rows = player zone; top 4 rows = enemy zone; middle row blocked
			if grid_pos.y >= battle_grid.grid_height - 4:
				unit.is_player_unit = true
			elif grid_pos.y < 4:
				unit.is_player_unit = false
			else:
				unit.queue_free()   # on the dividing row after snap — discard
				continue
			# Reparent under the runtime battle_grid for consistent transforms
			unit.reparent(battle_grid)
			# Place into grid data structure
			if battle_grid.place_unit(unit, grid_pos):
				if unit.is_player_unit:
					unit.home_position = grid_pos
					player_units.append(unit)
					_rebuild_synergy_display()
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
	gold_label.text = "💰 %d" % game_state.gold
	crystals_label.text = "💎 %d" % game_state.crystals
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
			background_layer.set_enemy_zone_visible(true)
			info_label.text = "Your turn! Buy units, drag them to position (bottom 4 rows), and click READY."
		GameState.State.AUTO_BATTLE:
			enable_unit_dragging(false)
			background_layer.set_enemy_zone_visible(false)
			info_label.text = "Auto battle in progress... No player actions allowed."
			if _battle_controls:
				_battle_controls.visible = true
		GameState.State.ENEMY_TURN:
			enable_unit_dragging(false)
			background_layer.set_enemy_zone_visible(false)
			info_label.text = "Enemy turn in progress..."

	# Hide battle controls outside of auto-battle
	if new_state != GameState.State.AUTO_BATTLE and _battle_controls:
		_battle_controls.visible = false

func _on_battle_round_started(round_number: int) -> void:
	update_ui()
	print("Battle round %d started!" % round_number)
	current_difficulty = WaveScaler.Difficulty.EASY
	clear_enemy_units()
	spawn_enemies(current_difficulty)
	if _difficulty_panel:
		_difficulty_panel.visible = true
		_update_difficulty_panel()

func _on_battle_started() -> void:
	if _difficulty_panel:
		_difficulty_panel.visible = false
	enable_unit_dragging(false)
	info_label.text = "Battle started! Units are fighting automatically."
	close_shop()
	update_team_health_bars()
	_event_log.clear()   # fresh log per battle
	if _battle_controls:
		_battle_controls.visible = true
	if _dm_expanded:
		_rebuild_damage_meter()

# ── Battle pace controls (Pause + 0.25× / 1× / 2× / 4× time scale) ────────────
func _build_battle_controls() -> void:
	_battle_controls = Panel.new()
	_battle_controls.name = "BattleControls"
	_battle_controls.size = Vector2(360, 48)
	_battle_controls.position = Vector2((1280 - 360) / 2.0, 66)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.16, 0.95)
	style.border_color = Color(0.4, 0.4, 0.55, 1)
	style.border_width_left = 2; style.border_width_right = 2
	style.border_width_top = 2; style.border_width_bottom = 2
	style.corner_radius_top_left = 6; style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6; style.corner_radius_bottom_right = 6
	_battle_controls.add_theme_stylebox_override("panel", style)
	_battle_controls.visible = false
	$UI.add_child(_battle_controls)

	var hbox := HBoxContainer.new()
	hbox.position = Vector2(8, 6)
	hbox.size = Vector2(344, 36)
	hbox.add_theme_constant_override("separation", 6)
	_battle_controls.add_child(hbox)

	_btn_pause = _make_ctrl_btn("⏸", 44)
	_btn_pause.pressed.connect(func(): auto_battle_manager.set_paused(true))
	hbox.add_child(_btn_pause)

	# 0.25× is the slow play-by-play mode; 4× fast-forwards.
	_speed_buttons.clear()
	for scale in SPEED_OPTIONS:
		var label := ("%.2f×" % scale) if scale < 1.0 else ("%d×" % int(scale))
		var btn := _make_ctrl_btn(label, 66)
		btn.pressed.connect(func(): auto_battle_manager.set_time_scale(scale))
		hbox.add_child(btn)
		_speed_buttons[scale] = btn

func _make_ctrl_btn(text: String, width: float = 90.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 36)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	return b

func _on_pace_changed(is_paused: bool, scale: float) -> void:
	# Highlight pause when frozen, else the active speed button.
	if _btn_pause:
		_btn_pause.modulate = Color(1.0, 0.85, 0.4) if is_paused else Color(1, 1, 1)
	for s in _speed_buttons:
		var active: bool = (not is_paused) and is_equal_approx(s, scale)
		_speed_buttons[s].modulate = Color(0.5, 1.0, 0.6) if active else Color(1, 1, 1)

const VICTORY_ROUND := 10  # completing this round triggers the victory screen

# ── Wave difficulty panel ─────────────────────────────────────────────────────
func _build_difficulty_panel() -> void:
	_difficulty_panel = Panel.new()
	_difficulty_panel.name = "DifficultyPanel"
	_difficulty_panel.size = Vector2(400, 86)
	_difficulty_panel.position = Vector2((1280 - 400) / 2.0, 66)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.14, 0.96)
	style.border_color = Color(0.55, 0.4, 0.65, 1)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6; style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6; style.corner_radius_bottom_right = 6
	_difficulty_panel.add_theme_stylebox_override("panel", style)
	_difficulty_panel.visible = false

	var title := Label.new()
	title.text = "ENEMY DIFFICULTY"
	title.position = Vector2(0, 5)
	title.size = Vector2(400, 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.8, 0.7, 1.0))
	_difficulty_panel.add_child(title)

	var diff_labels: Array = ["★ Easy", "★★ Normal", "★★★ Hard"]
	var btn_w: float = 110.0
	var btn_spacing: float = 14.0
	var total_w: float = btn_w * 3.0 + btn_spacing * 2.0
	var start_x: float = (400.0 - total_w) / 2.0
	_diff_btns = []
	for i in range(3):
		var btn := Button.new()
		btn.text = diff_labels[i]
		btn.position = Vector2(start_x + i * (btn_w + btn_spacing), 24)
		btn.size = Vector2(btn_w, 28)
		btn.pressed.connect(_on_difficulty_selected.bind(i))
		_difficulty_panel.add_child(btn)
		_diff_btns.append(btn)

	_diff_power_lbl = Label.new()
	_diff_power_lbl.text = ""
	_diff_power_lbl.position = Vector2(0, 60)
	_diff_power_lbl.size = Vector2(400, 18)
	_diff_power_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diff_power_lbl.add_theme_font_size_override("font_size", 11)
	_diff_power_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_difficulty_panel.add_child(_diff_power_lbl)

	$UI.add_child(_difficulty_panel)

func _update_difficulty_panel() -> void:
	if not _difficulty_panel:
		return
	var diff_colors: Array = [Color(0.2, 0.75, 0.3), Color(0.9, 0.65, 0.1), Color(0.9, 0.2, 0.15)]
	for i in range(_diff_btns.size()):
		var btn: Button = _diff_btns[i]
		btn.modulate = diff_colors[i] if i == current_difficulty else Color(0.5, 0.5, 0.5)

	var total_power: float = 0.0
	for unit in enemy_units:
		if unit and is_instance_valid(unit):
			total_power += WaveScaler.score_unit(unit)
	var diff_names: Array = ["Easy", "Normal", "Hard"]
	_diff_power_lbl.text = "%s — Enemy Power: %d" % [diff_names[current_difficulty], int(total_power)]

func _on_difficulty_selected(diff: int) -> void:
	if diff == current_difficulty:
		return
	current_difficulty = diff
	clear_enemy_units()
	spawn_enemies(current_difficulty)
	_update_difficulty_panel()

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
		_despawn_summons()
		reset_player_positions()
		_grant_between_round_bonuses()
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
	# Show level-up perk choices for any hero that leveled up this round
	var leveled: Array = player_units.filter(
		func(u): return u and is_instance_valid(u) and u.perk_points > 0)
	if not leveled.is_empty():
		_level_up_screen.present(leveled)
		await _level_up_screen.all_done
	game_state.start_battle_round()

func _on_unit_summoned(unit: UnitBase) -> void:
	if not (unit and is_instance_valid(unit)):
		return
	battle_grid_node.add_child(unit)
	unit.battle_manager = auto_battle_manager
	unit.damage_text_container = damage_text_container
	unit.died.connect(_on_unit_died.bind(unit))
	# Track summons in the local rosters so _despawn_summons() cleans them at
	# round end (it removes is_summoned units before reset_player_positions runs).
	if unit.is_player_unit:
		if unit not in player_units:
			player_units.append(unit)
	else:
		if unit not in enemy_units:
			enemy_units.append(unit)

func _despawn_summons() -> void:
	# Remove all summoned units from the grid and scene at round end.
	var to_remove: Array = []
	for unit in player_units:
		if unit and is_instance_valid(unit) and unit.is_summoned:
			to_remove.append(unit)
	for unit in enemy_units:
		if unit and is_instance_valid(unit) and unit.is_summoned:
			to_remove.append(unit)
	for unit in to_remove:
		battle_grid.remove_unit(unit.grid_position)
		if unit in player_units:
			player_units.erase(unit)
		if unit in enemy_units:
			enemy_units.erase(unit)
		if is_instance_valid(unit):
			unit.queue_free()

func _on_unit_action(_unit, _action_type: String) -> void:
	update_team_health_bars()
	_rebuild_damage_meter()


func _style_team_bar(bar: ProgressBar, fill_color: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.07, 1)
	bg.border_color = Color(0.0, 0.0, 0.0, 1)
	bg.set_border_width_all(1)
	bg.corner_radius_top_left    = 3
	bg.corner_radius_top_right   = 3
	bg.corner_radius_bottom_left = 3
	bg.corner_radius_bottom_right = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.corner_radius_top_left    = 3
	fill.corner_radius_top_right   = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)

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

	# Sidebar-native widgets
	if _sb_player_hp:
		_sb_player_hp.max_value = max(p_max, 1)
		_sb_player_hp.value     = p_cur
		if p_max > 0:
			_sb_player_lbl.text = "%d / %d HP  ·  %d units  ·  %d%%" % [p_cur, p_max, p_alive, int(float(p_cur)/p_max*100)]
		else:
			_sb_player_lbl.text = "No player units"
		_rebuild_unit_list(_sb_player_ulist, player_units, Color(0.35, 0.92, 0.45, 1))
	if _sb_enemy_hp:
		_sb_enemy_hp.max_value = max(e_max, 1)
		_sb_enemy_hp.value     = e_cur
		if e_max > 0:
			_sb_enemy_lbl.text = "%d / %d HP  ·  %d units  ·  %d%%" % [e_cur, e_max, e_alive, int(float(e_cur)/e_max*100)]
		else:
			_sb_enemy_lbl.text = "No enemy units"
		_rebuild_unit_list(_sb_enemy_ulist, enemy_units, Color(0.95, 0.4, 0.4, 1))

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

func _on_unit_placed(placed_unit, grid_pos: Vector2i) -> void:
	info_label.text = "Unit placed at: (%d, %d)" % [grid_pos.x, grid_pos.y]
	# Only lock in home_position during the prep phase — battle movement also fires
	# this signal but must not overwrite the player's chosen row.
	if placed_unit and is_instance_valid(placed_unit) and not auto_battle_manager.battle_active:
		placed_unit.home_position = grid_pos

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

func _on_hero_chosen(unit_class: UnitBase.UnitClass, element: UnitBase.Element, rolls: Dictionary) -> void:
	if not game_state.spend_gold(HeroShop.HERO_COST):
		info_label.text = "Not enough gold!"
		return
	var unit := UnitFactory.create_unit(unit_class, element, true)
	UnitFactory.apply_recruit_rolls(unit, rolls)
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
		unit.home_position = spawn_pos
		player_units.append(unit)
		_rebuild_synergy_display()
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

#func _on_synergies_pressed() -> void:
#	_hero_synergy_panel.open(player_units)

func _on_equipment_pressed() -> void:
	_equipment_panel.open(_equipment_inventory, player_units)

func _on_event_choice_made(choice_index: int) -> void:
	if not _event_panel._current_event:
		return
	var choice = _event_panel._current_event.choices[choice_index]
	var effects = choice.effects

	# Apply effects
	if effects.has("gold"):
		game_state.add_gold(effects["gold"])

	if effects.has("heal_all"):
		for unit in player_units:
			if unit and is_instance_valid(unit):
				unit.current_hp = unit.max_hp

	if effects.has("restore_mana"):
		for unit in player_units:
			if unit and is_instance_valid(unit):
				unit.current_mana = unit.max_mana

	if effects.has("hero_damage"):
		var damage_ratio = abs(effects["hero_damage"])
		for unit in player_units:
			if unit and is_instance_valid(unit):
				unit.current_hp = int(unit.current_hp * (1.0 - damage_ratio))

	if effects.has("team_dmg_mult"):
		for unit in player_units:
			if unit and is_instance_valid(unit):
				unit.strength = int(unit.strength * effects["team_dmg_mult"])

	if effects.has("team_def_mult"):
		for unit in player_units:
			if unit and is_instance_valid(unit):
				unit.resistance = int(unit.resistance * effects["team_def_mult"])

	if effects.has("team_spd_mult"):
		for unit in player_units:
			if unit and is_instance_valid(unit):
				unit.movement_speed = max(1, int(unit.movement_speed * effects["team_spd_mult"]))

	if effects.has("max_hp_mult"):
		for unit in player_units:
			if unit and is_instance_valid(unit):
				unit.max_hp = max(1, int(unit.max_hp * effects["max_hp_mult"]))
				unit.current_hp = min(unit.current_hp, unit.max_hp)

	if effects.has("max_units"):
		max_player_units += int(effects["max_units"])

	# "Invest in training" — no level cap exists to raise, so level the team up now.
	if effects.has("max_level"):
		for unit in player_units:
			if unit and is_instance_valid(unit):
				for _i in range(int(effects["max_level"])):
					unit.level_up()

	# Gamble: 50/50 roll between the win and lose payouts.
	if effects.has("gold_if_win") or effects.has("gold_if_lose"):
		if randf() < 0.5:
			var won := int(effects.get("gold_if_win", 0))
			game_state.add_gold(won)
			info_label.text = "Gamble won! +%dg" % won
		else:
			var lost := int(effects.get("gold_if_lose", 0))
			game_state.add_gold(lost)   # lost is negative
			info_label.text = "Gamble lost! %dg" % lost

	update_ui()
	game_state.player_ready_for_battle()

func _on_ready_pressed() -> void:
	if player_units.is_empty():
		info_label.text = "You need at least one unit to battle!"
		return

	close_shop()
	if _difficulty_panel:
		_difficulty_panel.visible = false

	# Trigger random event between rounds (25% chance)
	if randf() < 0.25 and game_state.battle_round > 1:
		var event = EventGenerator.generate_event(game_state.battle_round)
		_event_panel.show_event(event)
	else:
		game_state.player_ready_for_battle()

# Unit Details Panel
func _make_details_bar(fill_col: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 10)
	bar.show_percentage = false
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_col
	fg.corner_radius_top_left = 3; fg.corner_radius_top_right = 3
	fg.corner_radius_bottom_left = 3; fg.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("fill", fg)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.12, 1)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _ensure_details_bars() -> void:
	if _details_hp_bar:
		return
	var vb = details_hp.get_parent()
	# HP bar after HPLabel
	_details_hp_bar = _make_details_bar(Color(0.18, 0.75, 0.28))
	vb.add_child(_details_hp_bar)
	vb.move_child(_details_hp_bar, details_hp.get_index() + 1)
	# MP bar after ManaLabel
	_details_mp_bar = _make_details_bar(Color(0.22, 0.45, 0.90))
	vb.add_child(_details_mp_bar)
	vb.move_child(_details_mp_bar, details_mana.get_index() + 1)
	# XP label + bar (inserted after ResLabel)
	_details_xp_lbl = Label.new()
	_details_xp_lbl.add_theme_font_size_override("font_size", 11)
	_details_xp_lbl.add_theme_color_override("font_color", Color(0.83, 0.69, 0.22))
	vb.add_child(_details_xp_lbl)
	vb.move_child(_details_xp_lbl, details_res.get_index() + 1)
	_details_xp_bar = _make_details_bar(Color(0.83, 0.69, 0.22))
	vb.add_child(_details_xp_bar)
	vb.move_child(_details_xp_bar, _details_xp_lbl.get_index() + 1)


func show_unit_details(unit: UnitBase) -> void:
	_details_unit = unit
	unit_details_panel.visible = true
	_ensure_details_bars()

	# Static info (only changes on level-up)
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
	_details_unit = null

# Sets a panel's bottom relative to its current top, so the panel can be freely
# repositioned in the editor without breaking the collapse/expand behaviour.
func _apply_panel_height(panel: Control, expanded: bool, collapsed_h: float, expanded_h: float) -> void:
	panel.offset_bottom = panel.offset_top + (expanded_h if expanded else collapsed_h)

func _on_action_toggle() -> void:
	_action_panel_expanded = not _action_panel_expanded
	var vbox := action_panel.get_node("VBoxContainer")
	for i in range(1, vbox.get_child_count()):
		vbox.get_child(i).visible = _action_panel_expanded
	action_toggle_btn.text = "PLAYER ACTIONS  %s" % ("▼" if _action_panel_expanded else "▶")
	_apply_panel_height(action_panel, _action_panel_expanded, ACTION_PANEL_COLLAPSED_HEIGHT, ACTION_PANEL_EXPANDED_HEIGHT)
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
	dm_scroll.visible  = _dm_expanded
	dm_toggle_btn.text = "DAMAGE METER  %s" % ("▼" if _dm_expanded else "▶")
	_apply_panel_height(damage_meter_panel, _dm_expanded, DM_COLLAPSED_HEIGHT, DM_EXPANDED_HEIGHT)
	if _dm_expanded:
		_rebuild_damage_meter()

func _on_eh_toggle() -> void:
	_eh_expanded = not _eh_expanded
	eh_scroll.visible = _eh_expanded
	eh_toggle_btn.text = "EVENT HISTORY  %s" % ("▼" if _eh_expanded else "▶")
	_apply_panel_height(event_history_panel, _eh_expanded, EH_COLLAPSED_HEIGHT, EH_EXPANDED_HEIGHT)
	if _eh_expanded:
		_render_event_log()

func _on_action_logged(text: String, is_player: bool) -> void:
	_event_log.append({"text": text, "is_player": is_player})
	if _event_log.size() > 200:
		_event_log = _event_log.slice(_event_log.size() - 200)
	_render_event_log()

func _rebuild_damage_meter() -> void:
	# Write to the sidebar-native list; fall back to the scene list if not built yet
	var target: VBoxContainer = _sb_dm_list if _sb_dm_list else dm_list
	for child in target.get_children():
		target.remove_child(child)
		child.free()

	var units := player_units if _dm_tab == 0 else enemy_units
	var name_col := Color(0.35, 0.92, 0.45) if _dm_tab == 0 else Color(0.95, 0.38, 0.38)

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

		target.add_child(row)
		rank += 1

	if sorted.is_empty():
		var lbl := Label.new()
		lbl.text = "No data yet — start a battle."
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		target.add_child(lbl)

func _render_event_log() -> void:
	# Clear the event-history list first
	for child in eh_list.get_children():
		eh_list.remove_child(child)
		child.free()
	# Most recent events at the top
	var shown := 0
	for i in range(_event_log.size() - 1, -1, -1):
		if shown >= 60:
			break
		var e: Dictionary = _event_log[i]
		var lbl := Label.new()
		lbl.text = str(e["text"])
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var is_round := str(e["text"]).begins_with("—")
		if is_round:
			lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.85))
		elif bool(e["is_player"]):
			lbl.add_theme_color_override("font_color", Color(0.45, 0.9, 0.55))
		else:
			lbl.add_theme_color_override("font_color", Color(0.95, 0.5, 0.5))
		eh_list.add_child(lbl)
		shown += 1
	if _event_log.is_empty():
		var empty := Label.new()
		empty.text = "No actions yet. Start a battle to see the log."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		eh_list.add_child(empty)

func _on_team_toggle() -> void:
	_team_panel_expanded = not _team_panel_expanded
	_set_team_panel_content_visible(_team_panel_expanded)
	team_toggle_btn.text = "TEAM STATUS  %s" % ("▼" if _team_panel_expanded else "▶")
	_apply_panel_height(team_stats_panel, _team_panel_expanded, TEAM_PANEL_COLLAPSED_HEIGHT, TEAM_PANEL_EXPANDED_HEIGHT)

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
		unit.home_position = spawn_pos
		player_units.append(unit)
		_rebuild_synergy_display()
		unit.died.connect(_on_unit_died.bind(unit))
		unit.battle_manager = auto_battle_manager  # Set reference
		unit.damage_text_container = damage_text_container  # Set reference
	else:
		unit.queue_free()

func spawn_enemies(difficulty: int = WaveScaler.Difficulty.EASY) -> void:
	var round := game_state.battle_round
	var formation_data: Array = WaveScaler.build_formation(round, difficulty, battle_grid.grid_width)

	if formation_data.is_empty():
		# Procedural round (round 11+): scaled by difficulty
		var base_count: int = min(3 + (round - 1) * 2, 10)
		var count: int = WaveScaler.procedural_count(base_count, difficulty)
		for i in range(count):
			var is_last := (i == count - 1)
			var lvl := _enemy_level_for_round(round, is_last)
			var unit := UnitFactory.create_random_class_unit(false)
			if lvl > 1: unit.set_level(lvl)
			_place_enemy(unit)
		return

	for entry: Dictionary in formation_data:
		var code: String = entry["code"]
		var grid_pos: Vector2i = entry["pos"]
		match code:
			"M":  _place_at(EnemyFactory.create_goblin(), grid_pos)
			"A":  _place_at(EnemyFactory.create_goblin_archer(), grid_pos)
			"S":  _place_at(EnemyFactory.create_goblin_shaman(), grid_pos)
			"B":  _place_at(EnemyFactory.create_orc_brute(), grid_pos)
			"G":  _place_at(EnemyFactory.create_hill_giant(), grid_pos)
			"SL": _place_at(EnemyFactory.create_slime(), grid_pos)
			"SK": _place_at(EnemyFactory.create_skeleton(), grid_pos)
			"R":  _place_at(EnemyFactory.create_rat(), grid_pos)

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

	# Remove units from wherever battle left them
	for unit in player_units:
		if unit and is_instance_valid(unit):
			battle_grid.remove_unit(unit.grid_position)

	# Restore each unit to the exact cell the player chose (home_position).
	# home_position is only written when the player places or drags a unit —
	# it never changes during battle, so this preserves the player's layout.
	for unit in player_units:
		if not (unit and is_instance_valid(unit)):
			continue
		var slot: Vector2i = unit.home_position
		# Fallback: if home_position is still zero (unit placed before this system),
		# find any free slot but don't overwrite home_position.
		if slot == Vector2i.ZERO or battle_grid.is_cell_occupied(slot):
			for y in range(battle_grid.grid_height - 4, battle_grid.grid_height):
				for x in range(battle_grid.grid_width):
					var p := Vector2i(x, y)
					if not battle_grid.is_cell_occupied(p):
						slot = p
						break
				if slot != unit.home_position:
					break
		if slot == Vector2i(-1, -1):
			continue
		unit.grid_position = slot
		unit.position = battle_grid.grid_to_world(slot)
		battle_grid.place_unit(unit, slot)
		# Clear leftover movement state from battle
		unit.is_moving = false
		unit.move_progress = 0.0
		unit.move_start_pos = unit.position
		unit.move_target_pos = unit.position

func _grant_between_round_bonuses() -> void:
	# Player zone: y=5 (front, closest to middle) to y=8 (back, farthest from middle).
	# Front row: 10% heal, +40% XP.  Back row: 40% heal, +10% XP.
	const PLAYER_Y_FRONT   := 5          # grid row closest to the middle dividing line
	const PLAYER_Y_BACK    := 8          # grid row farthest from the middle
	const HEAL_BACK        := 0.40
	const HEAL_FRONT       := 0.10
	const XP_MULT_BACK     := 1.10
	const XP_MULT_FRONT    := 1.40
	const XP_PER_DMG       := 8          # 1 XP per N damage dealt
	const XP_PER_KILL      := 80         # flat XP per kill

	for unit in player_units:
		if not (unit and is_instance_valid(unit)):
			continue

		var row_y: int     = clampi(unit.home_position.y, PLAYER_Y_FRONT, PLAYER_Y_BACK)
		# front_t 1.0 = front row (low heal, high XP), 0.0 = back row (high heal, low XP)
		var front_t: float = float(PLAYER_Y_BACK - row_y) / float(PLAYER_Y_BACK - PLAYER_Y_FRONT)

		# Heal
		var heal_pct: float = lerpf(HEAL_BACK, HEAL_FRONT, front_t)
		var heal_amt: int   = int(unit.max_hp * heal_pct)
		unit.current_hp = min(unit.current_hp + heal_amt, unit.max_hp)

		# XP from output this battle
		var xp_mult: float = lerpf(XP_MULT_BACK, XP_MULT_FRONT, front_t)
		var base_xp: int   = int(unit.damage_dealt / XP_PER_DMG) + unit.kill_count * XP_PER_KILL
		var xp_gained: int = int(base_xp * xp_mult)
		if xp_gained > 0:
			unit.grant_xp(xp_gained)
		_log_between_round(unit, heal_amt, xp_gained, front_t)

		# Reset per-battle trackers for next round
		unit.damage_dealt = 0
		unit.kill_count   = 0

	update_team_health_bars()
	_rebuild_damage_meter()


func _log_between_round(unit: UnitBase, heal: int, xp: int, front_t: float) -> void:
	var row_label := "back" if front_t < 0.35 else ("mid" if front_t < 0.65 else "front")
	_on_action_logged(
		"[%s] %s row → +%d HP healed, +%d XP (Lv.%d)" % [
			unit.unit_name, row_label, heal, xp, unit.level],
		true)


func _on_unit_died(unit) -> void:
	var was_enemy := enemy_units.has(unit)
	var dead_level: int = unit.level if (unit and is_instance_valid(unit)) else 1

	player_units.erase(unit)
	enemy_units.erase(unit)
	_rebuild_synergy_display()
	if unit and is_instance_valid(unit):
		battle_grid.remove_unit(unit.grid_position)

	if was_enemy and unit and is_instance_valid(unit):
		_run_kills += 1
		game_state.add_gold(WaveScaler.gold_for_unit(unit))
		var crystal_bonus: int = Progression.get_bonus("crystal_drop")
		var crystals: int = WaveScaler.crystals_for_unit(unit) + crystal_bonus
		if crystals > 0:
			game_state.add_crystals(crystals)
		update_ui()
		# Kill credit goes to whoever dealt the most damage to this enemy
		var _mdl = unit.most_damage_dealer if is_instance_valid(unit) else null
		if _mdl and is_instance_valid(_mdl) and _mdl.is_player_unit:
			_mdl.kill_count += 1

		# Generate item drops (30% chance per kill, scales with round)
		if randf() < 0.3 + (game_state.battle_round * 0.05):
			var item = EquipmentManager.generate_item(game_state.battle_round)
			_equipment_inventory.add_item(item)

	update_team_health_bars()


# ════════════════════════════════════════════════════════════════════════════
# ROW BONUS TOOLTIP
# ════════════════════════════════════════════════════════════════════════════

func _create_row_tooltip() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	_row_tip = Panel.new()
	_row_tip.size = Vector2(190, 76)
	_row_tip.visible = false
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(0.05, 0.05, 0.09, 0.93)
	s.border_color = Color(0.83, 0.69, 0.22, 0.75)
	s.set_border_width_all(1)
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	_row_tip.add_theme_stylebox_override("panel", s)
	layer.add_child(_row_tip)

	_row_tip_title = _tip_lbl(14, Color(0.83, 0.69, 0.22), Vector2(10, 7))
	_row_tip_heal  = _tip_lbl(12, Color(0.35, 0.92, 0.45), Vector2(10, 28))
	_row_tip_xp    = _tip_lbl(12, Color(0.90, 0.78, 0.30), Vector2(10, 50))
	_row_tip.add_child(_row_tip_title)
	_row_tip.add_child(_row_tip_heal)
	_row_tip.add_child(_row_tip_xp)


func _tip_lbl(size: int, col: Color, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.size     = Vector2(170, 18)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _process(_delta: float) -> void:
	_update_row_tooltip()
	_update_details_panel()


func _update_details_panel() -> void:
	if not unit_details_panel.visible:
		return
	if not _details_unit or not is_instance_valid(_details_unit):
		_details_unit = null
		unit_details_panel.visible = false
		return
	var u := _details_unit
	details_hp.text   = "HP: %d / %d" % [u.current_hp, u.max_hp]
	details_mana.text = "Mana: %d / %d" % [u.current_mana, u.max_mana]
	details_level.text = "Level: %d" % u.level
	if _details_hp_bar:
		_details_hp_bar.max_value = u.max_hp
		_details_hp_bar.value    = u.current_hp
	if _details_mp_bar:
		_details_mp_bar.max_value = u.max_mana
		_details_mp_bar.value    = u.current_mana
	if _details_xp_bar and _details_xp_lbl:
		_details_xp_lbl.text     = "XP: %d / %d" % [u.current_xp, u.xp_to_level]
		_details_xp_bar.max_value = u.xp_to_level
		_details_xp_bar.value    = u.current_xp


func _update_row_tooltip() -> void:
	if not _row_tip or not battle_grid:
		return

	var mouse: Vector2 = get_viewport().get_mouse_position()
	var local: Vector2 = mouse - Vector2(battle_grid_node.position)
	var cx: int = int(local.x / battle_grid.cell_size)
	var cy: int = int(local.y / battle_grid.cell_size)

	# Player zone: bottom 4 rows (y = grid_height-4 to grid_height-1)
	var py_front: int = battle_grid.grid_height - 4   # = 5, closest to middle
	var py_back:  int = battle_grid.grid_height - 1   # = 8, farthest from middle
	if cx < 0 or cx >= battle_grid.grid_width or cy < py_front or cy > py_back:
		_row_tip.visible = false
		_row_tip_last    = -1
		return

	# Skip redraw if same row as last frame
	if cy == _row_tip_last:
		_reposition_tooltip(mouse)
		return
	_row_tip_last = cy

	# front_t 1.0 = front (closest to middle), 0.0 = back
	var front_t: float = float(py_back - cy) / float(py_back - py_front)
	var heal_pct: int  = int(lerpf(40.0, 10.0, front_t))
	var xp_bonus: int  = int(lerpf(10.0, 40.0, front_t))

	# Row 1 = front (closest to middle), Row 4 = back (safest)
	var row_num: int = cy - py_front + 1   # 1=front … 4=back
	var row_name: String
	match row_num:
		1: row_name = "Row 1  —  Front Line"
		4: row_name = "Row 4  —  Back Line"
		_: row_name = "Row %d" % row_num

	_row_tip_title.text = row_name

	_row_tip_heal.text  = "Heal  %d%%  per round" % heal_pct
	_row_tip_xp.text    = "XP  +%d%%  bonus" % xp_bonus

	# Lerp heal label from green (safe) → orange (risky)
	_row_tip_heal.add_theme_color_override("font_color",
		Color(0.30, 0.92, 0.40).lerp(Color(0.95, 0.42, 0.18), front_t))
	# Lerp XP label from dim gold (safe) → bright gold (risky)
	_row_tip_xp.add_theme_color_override("font_color",
		Color(0.65, 0.58, 0.25).lerp(Color(1.00, 0.88, 0.20), front_t))

	_reposition_tooltip(mouse)
	_row_tip.visible = true


func _reposition_tooltip(mouse: Vector2) -> void:
	var vp   := get_viewport().get_visible_rect().size
	var tip  := _row_tip.size
	var pos  := mouse + Vector2(16, -tip.y - 10)
	pos.x = clamp(pos.x, 4, vp.x - tip.x - 4)
	pos.y = clamp(pos.y, 4, vp.y - tip.y - 4)
	_row_tip.position = pos


# ════════════════════════════════════════════════════════════════════════════
# SIDEBAR UI — left panel (synergies / events) + right panel (economy / menus)
# ════════════════════════════════════════════════════════════════════════════

func _build_new_layout() -> void:
	# Hide old panel shells — their child nodes will be reparented below
	for path in ["UI/TopBar", "UI/ActionPanel", "UI/TeamStatsPanel",
				 "UI/DamageMeterPanel", "UI/EventHistoryPanel", "UI/BottomBar"]:
		var n := get_node_or_null(path)
		if n:
			n.visible = false

	_left_panel  = _sb_panel()
	_right_panel = _sb_panel()
	$UI.add_child(_left_panel)
	$UI.add_child(_right_panel)
	_position_sidebars()

	_build_left_panel()
	_build_right_panel()


func _position_sidebars() -> void:
	if not (_left_panel and _right_panel):
		return
	var vp := get_viewport().get_visible_rect().size
	_left_panel.set_position(Vector2(0, 0))
	_left_panel.set_size(Vector2(SIDEBAR_W, vp.y))
	_right_panel.set_position(Vector2(vp.x - SIDEBAR_W, 0))
	_right_panel.set_size(Vector2(SIDEBAR_W, vp.y))
	if battle_grid:
		_center_battlefield()


# ── Left panel: synergies + events ───────────────────────────────────────────
func _build_left_panel() -> void:
	var mg := _sb_margin(_left_panel)
	var vb := VBoxContainer.new()
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	mg.add_child(vb)

	vb.add_child(_sb_heading("SET BONUSES"))
	_synergy_list = VBoxContainer.new()
	_synergy_list.add_theme_constant_override("separation", 4)
	vb.add_child(_synergy_list)
	_rebuild_synergy_display()


# ── Right panel: economy header + scrollable accordion menus ─────────────────
func _build_right_panel() -> void:
	var mg := _sb_margin(_right_panel)
	var vb := VBoxContainer.new()
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	mg.add_child(vb)

	# Economy header — reparent simple text labels (they adapt fine)
	var econ := HBoxContainer.new()
	econ.add_theme_constant_override("separation", 6)
	vb.add_child(econ)
	gold_label.add_theme_font_size_override("font_size", 17)
	gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_label.reparent(econ)
	crystals_label.add_theme_font_size_override("font_size", 17)
	crystals_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crystals_label.reparent(econ)

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 6)
	vb.add_child(meta_row)
	round_label.add_theme_font_size_override("font_size", 13)
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_label.reparent(meta_row)
	state_label.add_theme_font_size_override("font_size", 13)
	state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_label.reparent(meta_row)
	vb.add_child(_sb_sep())

	# Scrollable accordion container
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 2)
	scroll.add_child(sv)

	# ── Player Actions (reparent buttons — they adapt fine) ───────────────────
	var act_body := VBoxContainer.new()
	act_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act_body.add_theme_constant_override("separation", 5)
	sv.add_child(_sb_accordion("PLAYER ACTIONS", act_body, true))
	sv.add_child(act_body)
	for btn in [ready_btn, spawn_hero_btn, use_items_btn, classes_btn, roster_btn]:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.reparent(act_body)
	sv.add_child(_sb_sep())

	# ── Team Status (fresh native widgets — scene nodes have fixed sizes) ─────
	var team_body := VBoxContainer.new()
	team_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_body.add_theme_constant_override("separation", 5)
	sv.add_child(_sb_accordion("TEAM STATUS", team_body, true))
	sv.add_child(team_body)

	_sb_player_hp  = _make_sb_bar(Color(0.15, 0.78, 0.30, 1))
	_sb_player_lbl = _make_sb_lbl("No player units")
	_sb_player_ulist = VBoxContainer.new()
	_sb_player_ulist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_body.add_child(_sb_player_hp)
	team_body.add_child(_sb_player_lbl)
	team_body.add_child(_sb_player_ulist)
	team_body.add_child(_sb_sep())

	_sb_enemy_hp  = _make_sb_bar(Color(0.88, 0.18, 0.18, 1))
	_sb_enemy_lbl = _make_sb_lbl("No enemy units")
	_sb_enemy_ulist = VBoxContainer.new()
	_sb_enemy_ulist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_body.add_child(_sb_enemy_hp)
	team_body.add_child(_sb_enemy_lbl)
	team_body.add_child(_sb_enemy_ulist)
	sv.add_child(_sb_sep())

	# ── Damage Meter (fresh list + reparent tab buttons) ─────────────────────
	var dm_body := VBoxContainer.new()
	dm_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(_sb_accordion("DAMAGE METER", dm_body))
	sv.add_child(dm_body)
	dm_body.visible = false
	dm_tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dm_tab_row.reparent(dm_body)
	var dm_inner_scroll := ScrollContainer.new()
	dm_inner_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dm_inner_scroll.custom_minimum_size = Vector2(0, 200)
	dm_inner_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dm_body.add_child(dm_inner_scroll)
	_sb_dm_list = VBoxContainer.new()
	_sb_dm_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sb_dm_list.add_theme_constant_override("separation", 3)
	dm_inner_scroll.add_child(_sb_dm_list)
	sv.add_child(_sb_sep())

	# ── Combat History (reparent eh_scroll — contains eh_list VBox) ──────────
	var ch_body := VBoxContainer.new()
	ch_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(_sb_accordion("COMBAT HISTORY", ch_body, true))
	sv.add_child(ch_body)
	eh_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eh_scroll.custom_minimum_size = Vector2(0, 260)
	eh_scroll.reparent(ch_body)
	eh_scroll.visible = true   # old toggle system left this false
	_render_event_log()

	# Info strip at bottom of the outer VBox (outside scroll)
	vb.add_child(_sb_sep())
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", Color(0.58, 0.58, 0.68, 1))
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.reparent(vb)

	update_team_health_bars()


func _make_sb_bar(fill_col: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size   = Vector2(0, 14)
	bar.show_percentage       = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_col
	fill.corner_radius_top_left = 2; fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2; fill.corner_radius_bottom_right = 2
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.06, 0.10)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _make_sb_lbl(placeholder: String) -> Label:
	var lbl := Label.new()
	lbl.text = placeholder
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.80))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl


# ── Synergy display ───────────────────────────────────────────────────────────
# Counts TraitClass across deployed player_units and draws TFT-style rows.
# Call this whenever the roster changes. Wire to synergy_tracker when re-enabled.
func _rebuild_synergy_display() -> void:
	if not _synergy_list:
		return
	for c in _synergy_list.get_children():
		c.queue_free()

	var counts: Dictionary = {}
	for unit in player_units:
		if unit and is_instance_valid(unit):
			counts[unit.trait_class] = counts.get(unit.trait_class, 0) + 1

	const TRAIT_NAMES := {
		UnitBase.TraitClass.TANK:    "Tank",
		UnitBase.TraitClass.MAGE:    "Mage",
		UnitBase.TraitClass.FIGHTER: "Fighter",
		UnitBase.TraitClass.RANGED:  "Ranged",
		UnitBase.TraitClass.HEALER:  "Healer",
	}
	const THRESHOLDS := {
		UnitBase.TraitClass.TANK:    [2, 4],
		UnitBase.TraitClass.MAGE:    [2, 4],
		UnitBase.TraitClass.FIGHTER: [2, 4],
		UnitBase.TraitClass.RANGED:  [2, 3],
		UnitBase.TraitClass.HEALER:  [1, 2],
	}
	const TIPS := {
		UnitBase.TraitClass.TANK:    "2: +15% DEF all Tanks\n4: +30% DEF + taunt nearby enemies",
		UnitBase.TraitClass.MAGE:    "2: +20% Magic Power\n4: +40% MP + chain cast on kill",
		UnitBase.TraitClass.FIGHTER: "2: +15% ATK\n4: +30% ATK + fury on low HP",
		UnitBase.TraitClass.RANGED:  "2: +2 attack range\n3: +4 range + snipe (ignore dodge)",
		UnitBase.TraitClass.HEALER:  "1: regen on kill\n2: team-wide HP regen per second",
	}

	if counts.is_empty():
		var ph := Label.new()
		ph.text = "Deploy units to see\nactive synergies"
		ph.add_theme_font_size_override("font_size", 10)
		ph.add_theme_color_override("font_color", Color(0.42, 0.42, 0.52, 1))
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_synergy_list.add_child(ph)
		return

	for trait_id in counts:
		var count: int  = counts[trait_id]
		var tname: String = TRAIT_NAMES.get(trait_id, "?")
		var tiers: Array  = THRESHOLDS.get(trait_id, [99])
		var active: bool  = count >= tiers[0]
		var at_max: bool  = count >= tiers[-1]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.tooltip_text  = TIPS.get(trait_id, "")
		row.mouse_filter  = Control.MOUSE_FILTER_STOP

		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(8, 14)
		pip.color = _GOLD_COL if active else Color(0.28, 0.28, 0.38, 1)
		row.add_child(pip)

		var lbl := Label.new()
		var suffix: String = " MAX" if at_max else "/%d" % tiers[-1]
		lbl.text = "%s  %d%s" % [tname, count, suffix]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color",
			_GOLD_COL if active else Color(0.50, 0.50, 0.60, 1))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		_synergy_list.add_child(row)


# ── Shared sidebar helpers ────────────────────────────────────────────────────
func _sb_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color     = _PANEL_DARK
	s.border_color = _GOLD_DIM
	s.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", s)
	return p


func _sb_margin(parent: Control) -> MarginContainer:
	var mg := MarginContainer.new()
	mg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mg.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	for k in ["margin_left","margin_right","margin_top","margin_bottom"]:
		mg.add_theme_constant_override(k, 10)
	parent.add_child(mg)
	return mg


func _sb_heading(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", _GOLD_COL)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl


func _sb_sep() -> HSeparator:
	var sep := HSeparator.new()
	var s := StyleBoxFlat.new()
	s.bg_color = _GOLD_DIM
	sep.add_theme_stylebox_override("separator", s)
	return sep


func _sb_accordion(title: String, body: Control, open: bool = false) -> Button:
	body.visible = open
	var btn := Button.new()
	btn.text      = title + ("  ▼" if open else "  ▶")
	btn.flat      = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", _GOLD_COL)
	var s := StyleBoxFlat.new()
	s.bg_color     = _PANEL_MID
	s.border_color = _GOLD_DIM
	s.set_border_width_all(1)
	s.corner_radius_top_left     = 3
	s.corner_radius_top_right    = 3
	s.corner_radius_bottom_left  = 3
	s.corner_radius_bottom_right = 3
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, s)
	btn.pressed.connect(func():
		body.visible = not body.visible
		btn.text = title + ("  ▼" if body.visible else "  ▶")
	)
	return btn
