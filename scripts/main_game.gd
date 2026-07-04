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
var _action_panel_style: StyleBox   # held in GDScript to survive layout changes (dobo texture panel)

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

# Wave difficulty panel
var difficulty_panel: DifficultyPanel
var current_difficulty: int = WaveScaler.Difficulty.EASY

# Unit details panel
@onready var unit_details_panel = $UI/UnitDetailsPanel
@onready var _dpanel_root: VBoxContainer = $UI/UnitDetailsPanel/Margin/ScrollContainer/Root
# Details-panel internals moved to UnitDetailsController (2026-07-04 refactor).
# main_game keeps only what its own wiring needs: the close button (signal
# connection) and the name label (asserted by scenes/ui_smoke.tscn).
@onready var details_close_btn = _dpanel_root.get_node("TitleBar/CloseBtn")
@onready var details_unit_name: Label = _dpanel_root.get_node("Header/HeaderInfo/UnitName")

# Held-items bag lives in the scene (ItemBag GridContainer); slots filled at runtime.

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
var _round_reward_screen: RoundRewardScreen
var _pending_round_reward: Dictionary = {}
var _rolled_rewards: Dictionary = {}   # {difficulty: reward} — rolled once per round, shown in full
var _wave_director := WaveDirector.new()   # wave specs + enemy creation (shared logic w/ arena)
var _coin_system: GoldCoinSystem       # gold drops on the field (see gold_coin_system.gd)

# ── Combat-UI refresh throttle (perf fix 2026-07-04, see _on_unit_action) ──
const COMBAT_UI_REFRESH_INTERVAL := 0.25
var _combat_ui_dirty := false
var _eh_dirty := false
var _ui_refresh_accum := 0.0
var _perf_overlay_lbl: Label = null    # F3 debug overlay (FPS / frame ms / node count)
var _equipment_inventory: EquipmentInventory
var _equipment_panel: EquipmentPanel
var _event_panel: EventPanel
var _game_over_screen: GameOverScreen
var _relic_screen: RelicScreen
var _relic_inventory: RelicInventory
var _relic_grid: GridContainer = null      # RELICS section in the left sidebar
var _relic_heading: Control = null

# Run tracking (reset each new game)
var _run_kills: int = 0
# Which relic-waves (1/11/21) have already handed out their pick this run.
var _relic_waves_done: Dictionary = {}

# ── Sidebar layout ────────────────────────────────────────────────────────────
# Parchment-and-gold theme (2026-07-04): panels/headers are now light cream
# (see UITheme), so text colors flipped from light-gold-on-dark to
# dark-brown-on-cream. _PANEL_DARK/_PANEL_MID (old bg colors) removed —
# both call sites already switched to UITheme.panel_box()/header_box().
const SIDEBAR_W  := 285.0
const _GOLD_COL   := UITheme.TEXT_HEADER
const _GOLD_DIM   := Color(0.42, 0.29, 0.12, 0.55)

# ITEM_ICONS moved to EquipmentManager.ITEM_ICONS so it's shared with other UI
# (e.g. the round-reward preview in difficulty_panel.gd).

var _left_panel:     PanelContainer
var _right_panel:    PanelContainer
var _synergy_list:   VBoxContainer   # rebuilt when player roster changes
var _inventory_grid: GridContainer   # bag display rebuilt on inventory_changed
var _synergy_tracker: SynergyTracker = SynergyTracker.new()
var _synergies_applied: bool = false   # guards the battle-start apply / battle-end revert

# Item hover tooltip
var _item_tip_layer: CanvasLayer = null
var _item_tip:           PanelContainer = null
var _item_tip_name_lbl:  Label = null
var _item_tip_stats_vb:  VBoxContainer = null
var _item_tip_passive_lbl:  Label = null
var _item_tip_passive_desc: Label = null
var _badge_tip_active: bool = false   # item tooltip is currently shown by a board badge hover
# Bag drag-to-equip state
var _drag_candidate: EquipmentItem = null
var _dragged_item:   EquipmentItem = null
var _drag_layer:     CanvasLayer   = null
var _drag_panel:     Panel         = null
var _drag_press_pos: Vector2       = Vector2.ZERO

# Row-bonus tooltip (floats above grid on mouse hover)
var _row_tip:       Panel
var _row_tip_title: Label
var _row_tip_heal:  Label
var _row_tip_xp:    Label
var _row_tip_last:  int = -1   # last cell_y we displayed, avoids redundant updates

# Live unit details panel
var _details: UnitDetailsController = null   # details-panel logic (scripts/ui/)

# Sidebar-native widgets (built fresh in code so sizing is reliable)
var _sb_player_hp:    ProgressBar
var _sb_player_lbl:   Label
var _sb_player_ulist: VBoxContainer
var _sb_enemy_hp:     ProgressBar
var _sb_enemy_lbl:    Label
var _sb_enemy_ulist:  VBoxContainer
var _sb_dm_list:      VBoxContainer


# ── INITIALIZATION ─────────────────────────────────────────────────────────
func _ready():
	initialize_game_components()
	# Details controller needs _dpanel_root (@onready) resolved — safe here.
	_details = UnitDetailsController.new(self)
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

	# Gold coins dropped by kills/rewards (2026-07-03 economy — see GoldCoinSystem)
	_coin_system = GoldCoinSystem.new()
	_coin_system.name = "GoldCoinSystem"
	battle_grid_node.add_child(_coin_system)
	_coin_system.battle_grid = battle_grid
	_coin_system.coin_collected.connect(_on_coin_collected)

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
	game_state.player_leveled_up.connect(_on_player_leveled_up)
	
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
	use_items_btn.text = "Equipment"
	use_items_btn.pressed.connect(_on_equipment_pressed)
	classes_btn.pressed.connect(_on_classes_pressed)
	roster_btn.pressed.connect(_on_roster_pressed)
	ready_btn.pressed.connect(_on_ready_pressed)
	details_close_btn.pressed.connect(_on_details_close_pressed)
	unit_details_panel.gui_input.connect(_on_details_panel_input)
	# Cache the action panel's stylebox so we can re-apply it after every offset
	# change (Godot 4 drops theme_override_styles on layout updates).
	# UI theme pass 2026-07-03: dobo card panel instead of the old flat navy box.
	_action_panel_style = UITheme.panel_box()

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

	_round_reward_screen = RoundRewardScreen.new()
	add_child(_round_reward_screen)

	_equipment_inventory = EquipmentInventory.new()
	_equipment_inventory.inventory_changed.connect(_rebuild_inventory_grid)
	_equipment_inventory.hero_equipment_changed.connect(_on_hero_equipment_changed)
	_equipment_panel = EquipmentPanel.new()
	add_child(_equipment_panel)

	_event_panel = EventPanel.new()
	_event_panel.event_choice_made.connect(_on_event_choice_made)
	add_child(_event_panel)

	_relic_inventory = RelicInventory.new()
	_relic_screen = RelicScreen.new()
	_relic_screen.chosen.connect(_on_relic_chosen)
	add_child(_relic_screen)

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


var max_player_units: int = 27   # base cap; increased by Roster Expansion upgrade

# ── Player level / team-size curve (2026-07-04) ───────────────────────────────
# Base team size at player_level 1, +1 per level, capped once the ceiling
# matches the old flat 27 (so a long enough run always converges back to the
# same "full roster" feeling — this just gates how much of it you start with).
const TEAM_SIZE_BASE := 4
const TEAM_SIZE_LEVEL_CAP := 24   # levels beyond this stop granting more slots

func _team_size_for_level(lvl: int) -> int:
	return TEAM_SIZE_BASE + mini(lvl - 1, TEAM_SIZE_LEVEL_CAP - 1)

var _event_team_size_bonus: int = 0   # persistent per-run "Reinforcements" event bonus

func _recompute_max_player_units() -> void:
	max_player_units = _team_size_for_level(game_state.player_level) \
			+ Progression.get_bonus("hero_slots") + _event_team_size_bonus

# Share of a kill's hero-XP that also feeds the player-level pool (EV-modeled
# 2026-07-04 to roughly match the existing economy pace: ~level 5 by wave 5,
# ~level 8 by wave 10, ~level 13 by wave 30 — see balance journal for the model).
const PLAYER_XP_SHARE := 0.5

func _on_player_leveled_up(new_level: int) -> void:
	_recompute_max_player_units()
	info_label.text = "Level up! Team size is now %d." % max_player_units
	update_ui()

# Wave locking system
var _current_wave_spec: Array = []  # locked enemy roster for this wave (before instantiation)
var _locked_difficulty: int = -1    # locked difficulty for this wave (-1 = not locked yet)

func start_new_game() -> void:
	# Economy v3 (2026-07-03): 50 → 10 starting gold, heroes cost 10 — the whole
	# economy moved to coin-drop scale (see GoldCoin / gold_drops_for_unit).
	game_state.gold = 10 + Progression.starting_gold_bonus()
	game_state.crystals = 0
	_run_kills = 0
	game_state.reset_player_level()
	_event_team_size_bonus = 0
	_recompute_max_player_units()
	_relic_inventory = RelicInventory.new()
	_relic_waves_done.clear()
	_rebuild_relic_bar()
	game_state.start_battle_round()
	open_shop()


# ── STATE MACHINE & UI UPDATE ──────────────────────────────────────────────
func update_ui() -> void:
	# Coin/gem art is part of the currency plates (see UITheme) — number only.
	gold_label.text = "%d" % game_state.gold
	crystals_label.text = "%d" % game_state.crystals
	round_label.text = "Round: %d  ·  Lv %d  ·  Team %d/%d" % [
		game_state.battle_round, game_state.player_level,
		player_units.size(), max_player_units]
	
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
	# Enemy units are never player-controlled — always keep them locked,
	# regardless of the requested state.
	for unit in enemy_units:
		if unit and is_instance_valid(unit) and unit is VisualUnit:
			unit.can_be_dragged = false

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


# ── BATTLE ROUND LIFECYCLE ─────────────────────────────────────────────────
func _on_battle_round_started(round_number: int) -> void:
	update_ui()
	print("Battle round %d started!" % round_number)
	# Generate and lock wave 1 at EASY difficulty
	_locked_difficulty = WaveScaler.Difficulty.EASY
	current_difficulty = WaveScaler.Difficulty.EASY
	_current_wave_spec = _generate_wave_spec(_locked_difficulty)
	_instantiate_wave_from_spec(_current_wave_spec)
	# Roll this round's reward for ALL 3 difficulties up front and show them in
	# full — the player picks a difficulty knowing exactly what they'd win, not
	# just vague odds. The roll doesn't change no matter how many times you flip
	# between difficulties this round.
	_rolled_rewards = {
		WaveScaler.Difficulty.EASY:   RoundReward.roll(WaveScaler.Difficulty.EASY, round_number),
		WaveScaler.Difficulty.NORMAL: RoundReward.roll(WaveScaler.Difficulty.NORMAL, round_number),
		WaveScaler.Difficulty.HARD:   RoundReward.roll(WaveScaler.Difficulty.HARD, round_number),
	}
	if difficulty_panel:
		difficulty_panel.current_difficulty = current_difficulty
		difficulty_panel.update_display(_all_difficulty_power(), _rolled_rewards)
		difficulty_panel.set_panel_visible(true)

	if WaveScaler.is_boss_round(round_number):
		info_label.text = "⚠ BOSS WAVE %d — a towering Hill Giant leads the assault. Prepare!" % round_number

	# Relic pick at the start of waves 1 / 11 / 21 — a modal over the prep phase.
	# Effects apply immediately (retroactively to units on the team, and to any
	# hero recruited afterwards), so there's no strict ordering vs. the shop.
	if round_number in Relic.RELIC_WAVES and not _relic_waves_done.has(round_number):
		_relic_waves_done[round_number] = true
		var offers: Array = Relic.roll_offers(round_number, _relic_inventory.owned_ids())
		if not offers.is_empty():
			_relic_screen.present(offers, round_number)

func _on_relic_chosen(relic: Dictionary) -> void:
	# Store it, then apply retroactively to heroes already on the team. Newly
	# recruited heroes pick it up in _on_hero_chosen.
	var owned_copy: Dictionary = _relic_inventory.add_relic(relic)
	_relic_inventory.apply_relic_to_units(owned_copy, player_units)
	_rebuild_relic_bar()
	update_ui()
	update_team_health_bars()
	if _details and _details.current_unit and is_instance_valid(_details.current_unit):
		_update_details_panel()
	info_label.text = "Relic acquired: %s" % relic.get("name", "?")

# The relics picked this run, shown as grade-bordered icons in the left sidebar
# (RELICS section, above the bag). Hover an icon for its name + effect.
const RELIC_SLOT := 34

func _rebuild_relic_bar() -> void:
	if not _relic_grid:
		return
	for c in _relic_grid.get_children():
		c.queue_free()

	# Hide the whole RELICS section (heading + grid) until the first relic drops.
	var has_relics: bool = _relic_inventory != null and not _relic_inventory.is_empty()
	if _relic_heading:
		_relic_heading.visible = has_relics
	_relic_grid.visible = has_relics
	if not has_relics:
		return

	for r in _relic_inventory.owned:
		var grade: String = r.get("grade", "D")
		var col: Color = Relic.grade_color(grade)
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(RELIC_SLOT, RELIC_SLOT)
		var cs := StyleBoxFlat.new()
		cs.bg_color = col.darkened(0.62)
		cs.border_color = col
		cs.set_border_width_all(2)
		cs.set_corner_radius_all(5)
		slot.add_theme_stylebox_override("panel", cs)
		slot.tooltip_text = "%s  [%s-rank]\n%s" % [r.get("name", ""), grade, r.get("desc", "")]
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var icon_path: String = Relic.icon_path(r)
		if icon_path != "":
			var tex := TextureRect.new()
			tex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.texture      = load(icon_path) as Texture2D
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(tex)
		else:
			# Fallback: first letters of the relic name if art is missing.
			var lbl := Label.new()
			lbl.text = str(r.get("name", "?")).substr(0, 2)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 14)
			lbl.add_theme_color_override("font_color", col.lightened(0.4))
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(lbl)
		_relic_grid.add_child(slot)

func _on_battle_started() -> void:
	if difficulty_panel:
		difficulty_panel.set_panel_visible(false)
	enable_unit_dragging(false)
	_apply_team_synergies()
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
	# UI theme pass 2026-07-03: dobo card panel for the floating battle controls.
	_battle_controls.add_theme_stylebox_override("panel", UITheme.panel_box())
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

	# 0.25× is the slow play-by-play mode; 4× fast-forwards. Labels stay the
	# familiar "1×"/"2×"/etc. (the user's mental model of "normal speed"), but
	# every tier is actually scaled by AutoBattleManager.BASE_TIME_SCALE under
	# the hood (the game-wide -10% pacing cut), so "1×" now means the new,
	# slightly slower baseline rather than literally 1.0.
	_speed_buttons.clear()
	for scale in SPEED_OPTIONS:
		var label := ("%.2f×" % scale) if scale < 1.0 else ("%d×" % int(scale))
		var btn := _make_ctrl_btn(label, 66)
		var actual_scale: float = scale * AutoBattleManager.BASE_TIME_SCALE
		btn.pressed.connect(func(): auto_battle_manager.set_time_scale(actual_scale))
		hbox.add_child(btn)
		_speed_buttons[actual_scale] = btn

func _make_ctrl_btn(text: String, width: float = 90.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 36)
	b.add_theme_font_size_override("font_size", 17)
	# UI theme pass 2026-07-03: dobo-pack button plates (hover=blue, press=purple).
	UITheme.style_button(b)
	return b

func _on_pace_changed(is_paused: bool, scale: float) -> void:
	# Highlight pause when frozen, else the active speed button.
	if _btn_pause:
		_btn_pause.modulate = Color(1.0, 0.85, 0.4) if is_paused else Color(1, 1, 1)
	for s in _speed_buttons:
		var active: bool = (not is_paused) and is_equal_approx(s, scale)
		_speed_buttons[s].modulate = Color(0.5, 1.0, 0.6) if active else Color(1, 1, 1)

const VICTORY_ROUND := 30  # completing this round triggers the victory screen
						   # (bosses at 10/20/30; relic picks at 1/11/21)

# ── Wave difficulty section (embedded in left sidebar) ────────────────────────
func _build_difficulty_panel_ui(parent_vb: VBoxContainer) -> void:
	difficulty_panel = DifficultyPanel.new()
	difficulty_panel.difficulty_selected.connect(_on_difficulty_panel_selected)
	parent_vb.add_child(difficulty_panel)

func _on_difficulty_panel_selected(diff: int) -> void:
	current_difficulty = diff
	# Preview only — show what enemies would spawn at this difficulty, but don't lock it
	spawn_enemies(current_difficulty)
	difficulty_panel.update_display(_all_difficulty_power(), _rolled_rewards)

# Power for all 3 difficulties at once (dry-run — no units touch the battlefield)
# so the panel can show every option side by side instead of just the active preview.
func _all_difficulty_power() -> Dictionary:
	return {
		WaveScaler.Difficulty.EASY:   _estimate_wave_power(WaveScaler.Difficulty.EASY),
		WaveScaler.Difficulty.NORMAL: _estimate_wave_power(WaveScaler.Difficulty.NORMAL),
		WaveScaler.Difficulty.HARD:   _estimate_wave_power(WaveScaler.Difficulty.HARD),
	}

# ── Gold coin drops (economy v3) ──────────────────────────────────────────────
# Mechanics live in GoldCoinSystem (2026-07-04 refactor); main_game only
# supplies the vacuum target (gold counter) and banks arriving coins.
func _spawn_gold_coins(world_pos: Vector2, count: int) -> void:
	if count > 0 and _coin_system:
		_coin_system.spawn_coins(world_pos, count)

func _on_coin_collected(v: int) -> void:
	game_state.add_gold(v)
	update_ui()

func _spawn_coin_burst(count: int) -> void:
	if _coin_system:
		_coin_system.spawn_burst(count)

func _vacuum_all_coins() -> void:
	if _coin_system:
		_coin_system.vacuum_all(gold_label.get_global_rect().get_center())

func _on_battle_ended(player_won: bool) -> void:
	# Strip the battle-only synergy bonuses first so between-round stats/displays
	# show base values (they recompute fresh next fight).
	_revert_team_synergies()
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

		# Economy v3 (2026-07-03, per user): gold is now PHYSICAL — kills dropped
		# coins during the fight, and the round-win bonus + relic income + any
		# rolled GOLD reward rain onto the field here. Nothing is credited until
		# the vacuum (below) actually pulls each coin into the counter.
		const ROUND_WIN_GOLD := 2
		var relic_gold: int = _relic_inventory.gold_per_round() if _relic_inventory else 0
		_spawn_coin_burst(ROUND_WIN_GOLD + relic_gold)
		var reward_gold := 0
		if _pending_round_reward.get("type", RoundReward.Type.NOTHING) == RoundReward.Type.GOLD:
			reward_gold = int(_pending_round_reward.get("gold", 0))
			_spawn_coin_burst(reward_gold)
			_pending_round_reward = {}   # consumed as coins — _grant_round_reward skips it
		if relic_gold > 0 or reward_gold > 0:
			info_label.text = "Victory! %dg scattered on the field (+%d relic, +%d reward)." \
					% [ROUND_WIN_GOLD + relic_gold + reward_gold, relic_gold, reward_gold]
		else:
			info_label.text = "Victory! Collecting the spoils..."
		clear_enemy_units()
		_despawn_summons()
		reset_player_positions()
		_grant_between_round_bonuses()
		# THE vacuum: every coin on the field spirals into the gold counter.
		await get_tree().create_timer(0.7).timeout   # a beat to see the field of gold
		_vacuum_all_coins()
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
	await _grant_round_reward()
	# Show level-up perk choices for any hero that leveled up this round
	var leveled: Array = player_units.filter(
		func(u): return u and is_instance_valid(u) and u.perk_points > 0)
	if not leveled.is_empty():
		_level_up_screen.present(leveled)
		await _level_up_screen.all_done
	game_state.start_battle_round()

# Grants the reward rolled at "Ready for Battle" time for the round that was
# just cleared. STAT_BONUS pauses on a pick-a-card/pick-a-hero screen; the rest
# apply immediately with just an info-label message.
func _grant_round_reward() -> void:
	var reward: Dictionary = _pending_round_reward
	_pending_round_reward = {}
	if reward.is_empty():
		return
	match reward.get("type", RoundReward.Type.NOTHING):
		RoundReward.Type.GOLD:
			var amt: int = reward.get("gold", 0)
			game_state.add_gold(amt)
			info_label.text = "Round reward: +%d gold!" % amt
			update_ui()
		RoundReward.Type.ITEM:
			var item: EquipmentItem = reward.get("item")
			if item:
				_equipment_inventory.add_item(item)
				info_label.text = "Round reward: %s (%s)!" % [item.name, item.get_rarity_name()]
		RoundReward.Type.STAT_BONUS:
			var alive_units: Array = player_units.filter(
				func(u): return u and is_instance_valid(u))
			if alive_units.is_empty():
				return
			_round_reward_screen.present(reward, alive_units)
			await _round_reward_screen.done
		_:
			pass   # NOTHING

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

# PERF (2026-07-04): this fires for EVERY attack/skill/ult of EVERY unit. It
# used to rebuild the team lists + damage meter synchronously each time —
# ~500+ Control nodes created/freed per action at 15v14, measured at 156ms/frame
# (6 fps) in the perf probe. Now it only marks the combat UI dirty; the actual
# rebuild runs at most 4x/sec from _process, and only for visible panels.
func _on_unit_action(_unit, _action_type: String) -> void:
	_combat_ui_dirty = true



# ── TEAM HEALTH & COMBAT FEEDBACK ──────────────────────────────────────────
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
	# PERF: a hidden list (collapsed panel / closed accordion) keeps its stale
	# content instead of paying ~16 nodes per unit per rebuild. Expanding a
	# panel repaints within 0.25s via the dirty-flag throttle in _process.
	if not container.is_visible_in_tree():
		return
	for child in container.get_children():
		child.queue_free()

	for unit in units:
		if not (unit and is_instance_valid(unit)):
			continue

		# Unit header: name + level
		var header := Label.new()
		header.text = "● %s   Lv.%d" % [unit.unit_name, unit.level]
		header.add_theme_font_size_override("font_size", 15)
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
		current, maximum, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	# Fixed-width stat label (HP / MP / XP)
	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.custom_minimum_size = Vector2(20, 12)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color.lightened(0.25))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	# Current / max numbers (format floats with 1 decimal, ints as-is)
	var nums := Label.new()
	var cur_str := "%.1f" % current if current is float and current != int(current) else str(int(current))
	var max_str := "%.1f" % maximum if maximum is float and maximum != int(maximum) else str(int(maximum))
	nums.text = "%s / %s" % [cur_str, max_str]
	nums.custom_minimum_size = Vector2(90, 12)
	nums.add_theme_font_size_override("font_size", 12)
	nums.add_theme_color_override("font_color", Color(0.72, 0.72, 0.85, 1))
	nums.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nums.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(nums)

	# Bar
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	bar.max_value = maxf(float(maximum), 1.0)
	bar.value     = float(current)
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


# ── UNIT PLACEMENT & GRID INPUT ────────────────────────────────────────────
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



# ── SHOP & HERO MANAGEMENT ─────────────────────────────────────────────────
func _on_spawn_hero_pressed() -> void:
	if not shop_open:
		info_label.text = "Shop is closed!"
		return
	if game_state.gold < HeroShop.HERO_COST:
		info_label.text = "Not enough gold! Need %d gold." % HeroShop.HERO_COST
		return
	var shop_slots: int = 3 + (_relic_inventory.shop_slot_bonus() if _relic_inventory else 0)
	_hero_shop.open(game_state.gold, shop_slots)

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
	# Grant every relic picked so far to this new hire (each applies at most once).
	if _relic_inventory:
		_relic_inventory.apply_all_to_unit(unit)
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
				unit.attack_damage = int(unit.attack_damage * effects["team_dmg_mult"])

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
		# Persistent per-run bonus — max_player_units gets RECOMPUTED from level
		# on every level-up (see _recompute_max_player_units), which would
		# otherwise silently erase this the next time the player leveled up.
		_event_team_size_bonus += int(effects["max_units"])
		_recompute_max_player_units()

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
	if difficulty_panel:
		difficulty_panel.set_panel_visible(false)

	# Lock in the currently selected difficulty and generate+instantiate the final wave roster
	_locked_difficulty = current_difficulty
	_current_wave_spec = _generate_wave_spec(_locked_difficulty)
	_instantiate_wave_from_spec(_current_wave_spec)

	# Use the reward already rolled (and shown) for this difficulty when the
	# round started — the player picked this difficulty knowing exactly what
	# they'd win, so commit to that exact result, not a fresh roll.
	_pending_round_reward = _rolled_rewards.get(_locked_difficulty, {})

	# Trigger random event between rounds (25% chance)
	if randf() < 0.25 and game_state.battle_round > 1:
		var event = EventGenerator.generate_event(game_state.battle_round)
		_event_panel.show_event(event)
	else:
		game_state.player_ready_for_battle()

# Unit Details Panel

# ── UNIT DETAILS PANEL ─────────────────────────────────────────────────────
# Logic lives in UnitDetailsController (scripts/ui/, 2026-07-04 refactor).
# These delegates keep every existing call site / signal connection working.
func show_unit_details(unit: UnitBase) -> void:
	_details.show_unit(unit)

func _on_hero_equipment_changed(unit_id: String) -> void:
	_details.on_hero_equipment_changed(unit_id)

func _on_details_close_pressed() -> void:
	_details.close()


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


# ── DAMAGE METER & EVENT LOG ───────────────────────────────────────────────
func _on_action_logged(text: String, is_player: bool) -> void:
	_event_log.append({"text": text, "is_player": is_player})
	if _event_log.size() > 200:
		_event_log = _event_log.slice(_event_log.size() - 200)
	# PERF (2026-07-04): rendering rebuilt up to 200 Labels PER LOGGED ACTION
	# (and every attack logs). Now data-only here; render is throttled+gated.
	_eh_dirty = true

func _rebuild_damage_meter() -> void:
	# Write to the sidebar-native list; fall back to the scene list if not built yet
	var target: VBoxContainer = _sb_dm_list if _sb_dm_list else dm_list
	# PERF: skip entirely while the meter isn't on screen (throttle repaints it
	# within 0.25s of being expanded during battle).
	if not target.is_visible_in_tree():
		return
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
		name_lbl.add_theme_font_size_override("font_size", 13)
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
		num_lbl.add_theme_font_size_override("font_size", 12)
		num_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
		row.add_child(num_lbl)

		target.add_child(row)
		rank += 1

	if sorted.is_empty():
		var lbl := Label.new()
		lbl.text = "No data yet — start a battle."
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		target.add_child(lbl)

func _render_event_log() -> void:
	# PERF: rebuilding up to 200 Labels is pointless while the log is hidden.
	if not eh_list.is_visible_in_tree():
		return
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
		lbl.add_theme_font_size_override("font_size", 13)
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
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		eh_list.add_child(empty)

func _on_team_toggle() -> void:
	_team_panel_expanded = not _team_panel_expanded
	_set_team_panel_content_visible(_team_panel_expanded)
	team_toggle_btn.text = "TEAM STATUS  %s" % ("▼" if _team_panel_expanded else "▶")
	_apply_panel_height(team_stats_panel, _team_panel_expanded, TEAM_PANEL_COLLAPSED_HEIGHT, TEAM_PANEL_EXPANDED_HEIGHT)
	if _team_panel_expanded:
		update_team_health_bars()   # repaint immediately — lists were skipped while hidden

func _set_team_panel_content_visible(show: bool) -> void:
	var vbox := team_stats_panel.get_node("VBox")
	for i in range(1, vbox.get_child_count()):
		vbox.get_child(i).visible = show

func _on_details_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_panel_dragging = event.pressed
	elif event is InputEventMouseMotion and _panel_dragging:
		unit_details_panel.position += event.relative

# Shop and spawning functions

# ── SHOP CONTROL & ENEMY SPAWNING ──────────────────────────────────────────
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

# Wave spec generation + enemy creation live in WaveDirector (2026-07-04
# refactor) — scene-independent and shared with the arena harness, so the
# simulator can never drift from the live game's waves again.
func _generate_wave_spec(difficulty: int) -> Array:
	return _wave_director.generate_wave_spec(
			game_state.battle_round, difficulty, battle_grid.grid_width)

func _estimate_wave_power(difficulty: int) -> float:
	return _wave_director.estimate_wave_power(
			game_state.battle_round, difficulty, battle_grid.grid_width)

# Instantiate a wave spec onto the board. roll_item=false for the difficulty
# preview (so scouting can't free-reroll held-item drops); true for the real
# locked wave.
func _instantiate_wave_from_spec(spec: Array, roll_item: bool = true) -> void:
	clear_enemy_units()
	for entry: Dictionary in spec:
		var unit: VisualUnit = _wave_director.create_enemy_for_entry(entry, game_state.battle_round)
		if not unit:
			continue
		var grid_pos: Vector2i = entry.get("pos", Vector2i(-1, -1))
		if grid_pos != Vector2i(-1, -1):
			_place_at(unit, grid_pos, roll_item)
		else:
			_place_enemy(unit, roll_item)

func spawn_enemies(difficulty: int = WaveScaler.Difficulty.EASY) -> void:
	# Difficulty PREVIEW — same spec generator as the real wave (so boss rounds and
	# every difficulty preview exactly), but never rolls held items.
	_instantiate_wave_from_spec(_generate_wave_spec(difficulty), false)

# Place any unit at an explicit grid position (respects cell_size for 2×2 units).
# roll_item=false is used by the difficulty PREVIEW so switching difficulty back
# and forth can't be used to free-scout (and re-roll) held-item drops before
# committing — items only ever roll on the real, locked wave instantiation.
func _place_at(unit: VisualUnit, grid_pos: Vector2i, roll_item: bool = true) -> void:
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
		if roll_item:
			_roll_held_item(unit)
	else:
		unit.queue_free()

# Enemies can spawn already wielding a dropped item — stat bonuses apply for the
# whole fight, and the exact same item drops on death (what you see is what you loot).
const HELD_ITEM_BASE_CHANCE := 0.12
func _roll_held_item(unit: VisualUnit) -> void:
	if unit.is_player_unit:
		return
	var chance: float = HELD_ITEM_BASE_CHANCE + game_state.battle_round * 0.015
	if randf() >= chance:
		return
	var item := EquipmentManager.generate_item(game_state.battle_round, EquipmentItem.Rarity.RARE)
	EquipmentManager.apply_to_unit(unit, item)
	unit.held_items.append(item)
	if unit.health_bar:
		unit.health_bar.update_hp(unit.current_hp, unit.max_hp)
		unit.health_bar.update_mp(unit.current_mana, unit.max_mana)
	var icon_path: String = EquipmentManager.ITEM_ICONS.get(item.name, "")
	if icon_path != "":
		var tex: Texture2D = load(icon_path)
		if tex and unit is VisualUnit:
			unit.show_held_item_icon(tex, item.icon_color)

# Slot-fill for procedural rounds (keeps existing behaviour)
func _place_enemy(unit: VisualUnit, roll_item: bool = true) -> void:
	var spawn_pos := find_empty_enemy_slot()
	if spawn_pos == Vector2i(-1, -1):
		unit.queue_free()
		return
	unit.can_be_dragged = false
	_place_at(unit, spawn_pos, roll_item)

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


# ── BETWEEN-ROUND BONUSES ──────────────────────────────────────────────────
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
		var base_xp: float = float(unit.damage_dealt) / float(XP_PER_DMG) + unit.kill_xp
		var xp_gained: float = base_xp * xp_mult
		if xp_gained > 0:
			unit.grant_xp(xp_gained)
		_log_between_round(unit, heal_amt, xp_gained, front_t)

		# Reset per-battle trackers for next round
		unit.damage_dealt = 0
		unit.kill_count   = 0
		unit.kill_xp      = 0

	update_team_health_bars()
	_rebuild_damage_meter()


func _log_between_round(unit: UnitBase, heal: int, xp: float, front_t: float) -> void:
	var row_label := "back" if front_t < 0.35 else ("mid" if front_t < 0.65 else "front")
	var xp_str: String = "%.1f" % xp if xp != int(xp) else str(int(xp))
	_on_action_logged(
		"[%s] %s row → +%d HP healed, +%s XP (Lv.%d)" % [
			unit.unit_name, row_label, heal, xp_str, unit.level],
		true)



# ── UNIT DEATH & SUMMONS ───────────────────────────────────────────────────
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
		# Economy v3: kills drop physical coins on the field (collected by the
		# round-end vacuum) instead of crediting gold instantly.
		# NOTE: `unit.position` (local to battle_grid_node), not global_position.
		# GoldCoinSystem is battle_grid_node's sibling-under-the-same-parent, so
		# spawn_coins() treats its `world_pos` arg as local-to-battle_grid_node
		# (see spawn_burst()'s use of grid_to_world(), which is local too).
		# Passing global_position here double-counted battle_grid_node's own
		# centering offset (_center_battlefield), flinging every drop off the
		# visible board (2026-07-04 user report).
		_spawn_gold_coins(unit.position,
				WaveScaler.gold_drops_for_unit(unit, game_state.battle_round))
		var crystal_bonus: int = Progression.get_bonus("crystal_drop")
		var crystals: int = WaveScaler.crystals_for_unit(unit) + crystal_bonus
		if crystals > 0:
			game_state.add_crystals(crystals)
		update_ui()
		# Kill credit goes to whoever dealt the most damage to this enemy
		var _mdl = unit.most_damage_dealer if is_instance_valid(unit) else null
		if _mdl and is_instance_valid(_mdl) and _mdl.is_player_unit:
			_mdl.kill_count += 1

		# Distribute kill XP equally among all living player heroes
		var living_heroes: int = 0
		for hero in player_units:
			if hero and is_instance_valid(hero):
				living_heroes += 1

		if living_heroes > 0:
			var xp_per_hero: float = float(unit.xp_reward) / float(living_heroes)
			for hero in player_units:
				if hero and is_instance_valid(hero):
					hero.kill_xp += xp_per_hero

		# Player/account level (2026-07-04): a SHARE of every kill's total XP also
		# feeds the account-wide pool that grows team size — see game_state.gd.
		game_state.add_player_xp(float(unit.xp_reward) * PLAYER_XP_SHARE)

		# Loot ONLY drops from enemies that were actually wielding an item — the
		# exact item you saw on it mid-fight, no re-roll. Enemies that spawned
		# empty-handed drop nothing (no separate random death-drop roll).
		if not unit.held_items.is_empty():
			for held in unit.held_items:
				_equipment_inventory.add_item(held)

	update_team_health_bars()


# ════════════════════════════════════════════════════════════════════════════
# ROW BONUS TOOLTIP
# ════════════════════════════════════════════════════════════════════════════


# ── ROW BONUS TOOLTIP ──────────────────────────────────────────────────────
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

	_row_tip_title = _tip_lbl(18, Color(0.83, 0.69, 0.22), Vector2(10, 7))
	_row_tip_heal  = _tip_lbl(14, Color(0.35, 0.92, 0.45), Vector2(10, 28))
	_row_tip_xp    = _tip_lbl(14, Color(0.90, 0.78, 0.30), Vector2(10, 50))
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



# ── PROCESS LOOP ───────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	_update_row_tooltip()
	_update_details_panel()
	_update_bag_drag()
	_update_held_item_tooltip()
	# Throttled combat-UI refresh (see _on_unit_action perf note): rebuild the
	# heavy lists at most 4x/sec, and each rebuilder skips panels that aren't
	# visible. During battle actions fire constantly, so a panel expanded
	# mid-fight repaints within a quarter second anyway.
	_ui_refresh_accum += _delta
	if _ui_refresh_accum >= COMBAT_UI_REFRESH_INTERVAL:
		_ui_refresh_accum = 0.0
		if _combat_ui_dirty:
			_combat_ui_dirty = false
			update_team_health_bars()
			_rebuild_damage_meter()
		if _eh_dirty:
			_eh_dirty = false
			_render_event_log()
		if _perf_overlay_lbl and _perf_overlay_lbl.visible:
			_perf_overlay_lbl.text = "FPS %d   %.1f ms   nodes %d" % [
				Performance.get_monitor(Performance.TIME_FPS),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT)]

# Hovering an enemy's held-item badge on the battlefield shows the same item
# tooltip (name / rarity / stats / passive) as the Unit Details bag. The badge is
# a Sprite2D (no Control hover), so we hit-test the mouse against it here — the
# codebase already polls the mouse in _process for the row/bag tooltips.
func _update_held_item_tooltip() -> void:
	if not _item_tip or _dragged_item:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var hovered: EquipmentItem = null
	for u in enemy_units:
		if not (u and is_instance_valid(u) and u is VisualUnit):
			continue
		var badge: Sprite2D = u.held_item_badge
		if not (badge and badge.visible and badge.texture and not u.held_items.is_empty()):
			continue
		var xform := badge.get_global_transform_with_canvas()
		var half: Vector2 = (badge.texture.get_size() * 0.5) * xform.get_scale() * 1.3
		var rect := Rect2(xform.origin - half, half * 2.0)
		if rect.has_point(mouse):
			hovered = u.held_items[0]
			break
	if hovered:
		_show_item_tooltip(hovered, mouse)
		_reposition_item_tooltip(mouse)
		_badge_tip_active = true
	elif _badge_tip_active:
		# Only hide tooltips this poll opened — leave Unit-Details-bag hovers alone.
		_hide_item_tooltip()
		_badge_tip_active = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _dragged_item:
			_end_item_drag()
		else:
			_drag_candidate = null

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			_on_spawn_hero_pressed()
		elif event.keycode == KEY_ESCAPE:
			_close_top_menu()
		elif event.keycode == KEY_F3:
			_toggle_perf_overlay()

# F3 debug overlay: FPS / process ms / live node count, updated 4x/sec from the
# combat-UI throttle tick. Added with the 2026-07-04 perf fix so lag reports
# can come with numbers instead of vibes.
func _toggle_perf_overlay() -> void:
	if _perf_overlay_lbl == null:
		var layer := CanvasLayer.new()
		layer.layer = 99
		add_child(layer)
		_perf_overlay_lbl = Label.new()
		_perf_overlay_lbl.position = Vector2(8, 4)
		_perf_overlay_lbl.add_theme_font_size_override("font_size", 14)
		_perf_overlay_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
		_perf_overlay_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_perf_overlay_lbl.add_theme_constant_override("outline_size", 4)
		layer.add_child(_perf_overlay_lbl)
	else:
		_perf_overlay_lbl.visible = not _perf_overlay_lbl.visible

# Esc closes whichever browse-style menu is currently open (topmost first).
# Forced-choice screens (level up, round reward, event) are deliberately not
# included here — dismissing them would skip a choice the player still owes.
func _close_top_menu() -> void:
	if unit_details_panel.visible:
		_details.close()
	elif _hero_shop and _hero_shop.visible:
		_hero_shop.visible = false
	elif _class_browser and _class_browser.visible:
		_class_browser.visible = false
	elif _character_menu and _character_menu.visible:
		_character_menu.visible = false
	elif _equipment_panel and _equipment_panel.visible:
		_equipment_panel.visible = false


func _update_bag_drag() -> void:
	# Promote candidate to active drag once the threshold is crossed
	if _drag_candidate and not _dragged_item:
		if get_viewport().get_mouse_position().distance_to(_drag_press_pos) > 8.0:
			_dragged_item   = _drag_candidate
			_drag_candidate = null
			_create_drag_preview(_dragged_item)
	# Move drag preview with the cursor
	if _drag_panel:
		_drag_panel.position = get_viewport().get_mouse_position() - Vector2(24, 24)
	# Keep item tooltip positioned under cursor
	if _item_tip and _item_tip.visible and not _dragged_item:
		_reposition_item_tooltip(get_viewport().get_mouse_position())


func _update_details_panel() -> void:
	if _details:
		_details.refresh_live()


func _update_row_tooltip() -> void:
	if not _row_tip or not battle_grid:
		return
	# Hide while any full-screen overlay is open so it doesn't bleed through
	if (_hero_shop and _hero_shop.visible) \
			or (_level_up_screen and _level_up_screen.visible) \
			or unit_details_panel.visible:
		_row_tip.visible = false
		_row_tip_last = -1
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


# ── SIDEBAR LAYOUT CONSTRUCTION ────────────────────────────────────────────
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
	_build_item_tooltip()


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


# ── Left panel: synergies + bag ──────────────────────────────────────────────
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

	vb.add_child(_sb_sep())
	_build_difficulty_panel_ui(vb)
	vb.add_child(_sb_sep())

	# RELICS (above the bag) — hidden until the first relic is picked.
	_relic_heading = _sb_heading("RELICS")
	vb.add_child(_relic_heading)
	_relic_grid = GridContainer.new()
	_relic_grid.columns = 6
	_relic_grid.add_theme_constant_override("h_separation", 4)
	_relic_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(_relic_grid)
	_rebuild_relic_bar()
	vb.add_child(_sb_sep())

	vb.add_child(_sb_heading("BAG"))

	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 5
	_inventory_grid.add_theme_constant_override("h_separation", 4)
	_inventory_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(_inventory_grid)
	_rebuild_inventory_grid()


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
	# UI theme pass 2026-07-03: currency plates from the dobo pack — the coin/gem
	# art is baked into the plate's left side, so update_ui shows just the number.
	gold_label.add_theme_font_size_override("font_size", 21)
	gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_label.add_theme_stylebox_override("normal", UITheme.coin_label_box())
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.reparent(econ)
	crystals_label.add_theme_font_size_override("font_size", 21)
	crystals_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crystals_label.add_theme_stylebox_override("normal", UITheme.gem_label_box())
	crystals_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crystals_label.reparent(econ)

	# Stacked, not side-by-side (2026-07-04 user report): squeezing both into
	# one HBox left ~130px each, too narrow for "Round: 1 · Lv 1 · Team 0/4" —
	# it overflowed into state_label's slot and both got hard-clipped by the
	# panel's edge. Each now gets the full sidebar width on its own line.
	round_label.add_theme_font_size_override("font_size", 17)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_label.clip_text = true   # ellipsize as a safety net at high round/level numbers
	round_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	round_label.reparent(vb)
	state_label.add_theme_font_size_override("font_size", 17)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_label.reparent(vb)
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
		# Ellipsize instead of forcing the sidebar wider than SIDEBAR_W (see
		# _sb_panel's clip_contents note) — a graceful truncation, not a
		# mid-letter hard clip, if a button's text ever outgrows 285px again.
		btn.clip_text = true
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
	info_label.add_theme_font_size_override("font_size", 12)
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
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.80))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl


# ── Synergy display ───────────────────────────────────────────────────────────
# Counts TraitClass across deployed player_units and draws TFT-style rows.
# Call this whenever the roster changes.

# ── SYNERGY DISPLAY ────────────────────────────────────────────────────────
# Shows the ACTIVE element + trait synergies for the current roster (each row is
# the real stat bonus that will apply in battle). Bonuses themselves are applied
# at battle start (see _apply_team_synergies).
func _rebuild_synergy_display() -> void:
	if not _synergy_list:
		return
	for c in _synergy_list.get_children():
		c.queue_free()

	_synergy_tracker.update_from_team(player_units)

	if _synergy_tracker.active.is_empty():
		var ph := Label.new()
		ph.text = "Match elements or stack a\nrole to trigger synergies"
		ph.add_theme_font_size_override("font_size", 12)
		ph.add_theme_color_override("font_color", Color(0.42, 0.42, 0.52, 1))
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_synergy_list.add_child(ph)
		return

	for syn in _synergy_tracker.active:
		var col: Color = syn["color"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.tooltip_text = "%s ×%d  (tier %d)\n%s" % [syn["name"], syn["count"], syn["tier"], syn["desc"]]
		row.mouse_filter = Control.MOUSE_FILTER_STOP

		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(8, 14)
		pip.color = col if syn["tier"] >= 2 else col.darkened(0.25)
		row.add_child(pip)

		var lbl := Label.new()
		lbl.text = "%s ×%d — %s" % [syn["name"], syn["count"], syn["desc"]]
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", col.lightened(0.15))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		_synergy_list.add_child(row)

# ── Synergy combat bonuses (battle-start apply / battle-end revert) ───────────
# Applied to every player unit at battle start and reverted at battle end, so
# they recompute fresh each fight (post level-ups / relics / items) and never
# compound. Each unit backs up the touched stats in meta.
func _apply_team_synergies() -> void:
	if _synergies_applied:
		return
	_synergy_tracker.update_from_team(player_units)
	var b: Dictionary = _synergy_tracker.team_bonuses()
	for u in player_units:
		if not (u and is_instance_valid(u)):
			continue
		u.set_meta("syn_backup", {
			"attack_damage": u.attack_damage, "magic_power": u.magic_power,
			"resistance": u.resistance, "max_hp": u.max_hp,
			"attack_speed": u.attack_speed, "attack_range": u.attack_range,
		})
		u.attack_damage = maxi(1, int(round(u.attack_damage * b["attack_damage"])))
		u.magic_power   = maxi(0, int(round(u.magic_power   * b["magic_power"])))
		u.resistance    = maxi(0, int(round(u.resistance    * b["resistance"])))
		u.attack_speed  = u.attack_speed * float(b["attack_speed"])
		u.attack_range  = maxi(1, u.attack_range + int(b["range_add"]))
		if float(b["max_hp"]) != 1.0:
			u.max_hp = maxi(1, int(round(u.max_hp * float(b["max_hp"]))))
			u.current_hp = clampi(int(round(u.current_hp * float(b["max_hp"]))), 1, u.max_hp)
			if u.health_bar:
				u.health_bar.update_hp(u.current_hp, u.max_hp)
	_synergies_applied = true

func _revert_team_synergies() -> void:
	if not _synergies_applied:
		return
	for u in player_units:
		if not (u and is_instance_valid(u) and u.has_meta("syn_backup")):
			continue
		var bk: Dictionary = u.get_meta("syn_backup")
		u.attack_damage = int(bk["attack_damage"])
		u.magic_power   = int(bk["magic_power"])
		u.resistance    = int(bk["resistance"])
		u.attack_speed  = float(bk["attack_speed"])
		u.attack_range  = int(bk["attack_range"])
		u.max_hp        = int(bk["max_hp"])
		u.current_hp    = mini(u.current_hp, u.max_hp)
		u.remove_meta("syn_backup")
	_synergies_applied = false


# ── Bag / inventory grid ──────────────────────────────────────────────────────
# Redraws 30 fixed slots: filled slots show a coloured tile with a short label,
# empty slots show a dim placeholder. Clicking any filled slot opens the equipment panel.
func _rebuild_inventory_grid() -> void:
	if not _inventory_grid:
		return
	for c in _inventory_grid.get_children():
		c.queue_free()

	const SLOT_SIZE := Vector2(44, 44)
	const MAX_SLOTS := 30

	var items: Array = _equipment_inventory.items if _equipment_inventory else []

	for i in range(MAX_SLOTS):
		var slot_bg := StyleBoxFlat.new()
		slot_bg.corner_radius_top_left     = 4
		slot_bg.corner_radius_top_right    = 4
		slot_bg.corner_radius_bottom_left  = 4
		slot_bg.corner_radius_bottom_right = 4

		if i < items.size():
			var item: EquipmentItem = items[i]
			var btn := Button.new()
			btn.custom_minimum_size = SLOT_SIZE
			btn.mouse_filter = Control.MOUSE_FILTER_STOP

			# Background tinted to rarity colour (dimmed)
			slot_bg.bg_color     = item.icon_color.darkened(0.55)
			slot_bg.border_color = item.icon_color
			slot_bg.set_border_width_all(1)
			btn.add_theme_stylebox_override("normal", slot_bg)

			var hover_bg := slot_bg.duplicate() as StyleBoxFlat
			hover_bg.bg_color = item.icon_color.darkened(0.35)
			btn.add_theme_stylebox_override("hover", hover_bg)

			# Load icon texture
			var icon_path: String = EquipmentManager.ITEM_ICONS.get(item.name, "")
			if icon_path != "":
				var tex: Texture2D = load(icon_path)
				if tex:
					btn.icon = tex
					btn.expand_icon = true

			# Passive indicator: tiny gold dot in corner
			if item.passive_effect != "":
				var dot := ColorRect.new()
				dot.color = Color(1, 0.9, 0.3)
				dot.custom_minimum_size = Vector2(6, 6)
				dot.position = Vector2(SLOT_SIZE.x - 8, SLOT_SIZE.y - 8)
				dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(dot)

			# Hover tooltip + drag-to-equip (click with no drag opens equipment panel)
			var captured_item := item
			btn.mouse_entered.connect(func():
				_show_item_tooltip(captured_item, get_viewport().get_mouse_position()))
			btn.mouse_exited.connect(func(): _hide_item_tooltip())
			btn.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
					if event.pressed:
						_drag_candidate = captured_item
						_drag_press_pos = get_viewport().get_mouse_position()
					elif _dragged_item == null and _drag_candidate == captured_item:
						_drag_candidate = null
						_equipment_panel.open(_equipment_inventory, player_units)
			)
			_inventory_grid.add_child(btn)
		else:
			# Empty slot
			var ph := Panel.new()
			ph.custom_minimum_size = SLOT_SIZE
			slot_bg.bg_color     = Color(0.10, 0.10, 0.16, 0.6)
			slot_bg.border_color = Color(0.22, 0.22, 0.32, 0.5)
			slot_bg.set_border_width_all(1)
			ph.add_theme_stylebox_override("panel", slot_bg)
			ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_inventory_grid.add_child(ph)


# ── Shared sidebar helpers ────────────────────────────────────────────────────

# ── SIDEBAR WIDGET HELPERS ─────────────────────────────────────────────────
func _sb_panel() -> PanelContainer:
	# UI theme pass 2026-07-03: dobo-pack card panel instead of flat navy box.
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_box())
	# PanelContainer does NOT clip its children by default — a child whose
	# auto-sized minimum width exceeds SIDEBAR_W (e.g. a button whose text got
	# a font bump) just renders past the panel's own edge instead of shrinking.
	# Since the right sidebar sits flush against the screen's right edge, that
	# overflow ran straight off-screen (2026-07-04 user report). This clips
	# it to the panel's actual bounds no matter what content changes later.
	p.clip_contents = true
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
	lbl.add_theme_font_size_override("font_size", UITheme.header_font(15))
	lbl.add_theme_color_override("font_color", _GOLD_COL)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# UI theme pass 2026-07-03: header plate from the dobo pack behind the text.
	lbl.add_theme_stylebox_override("normal", UITheme.header_box())
	return lbl


func _sb_sep() -> HSeparator:
	var sep := HSeparator.new()
	var s := StyleBoxFlat.new()
	s.bg_color = _GOLD_DIM
	sep.add_theme_stylebox_override("separator", s)
	return sep


func _build_item_tooltip() -> void:
	_item_tip_layer = CanvasLayer.new()
	_item_tip_layer.layer = 28
	add_child(_item_tip_layer)

	_item_tip = PanelContainer.new()
	_item_tip.custom_minimum_size = Vector2(190, 0)
	_item_tip.visible = false
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(0.06, 0.05, 0.10, 0.97)
	s.border_color = Color(0.50, 0.42, 0.72, 0.9)
	s.set_border_width_all(1)
	s.corner_radius_top_left = 5; s.corner_radius_top_right = 5
	s.corner_radius_bottom_left = 5; s.corner_radius_bottom_right = 5
	_item_tip.add_theme_stylebox_override("panel", s)
	_item_tip_layer.add_child(_item_tip)

	var mg := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mg.add_theme_constant_override(k, 8)
	_item_tip.add_child(mg)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	mg.add_child(vb)

	_item_tip_name_lbl = Label.new()
	_item_tip_name_lbl.add_theme_font_size_override("font_size", 15)
	vb.add_child(_item_tip_name_lbl)

	var sep := HSeparator.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.4, 0.35, 0.55, 0.6)
	sep.add_theme_stylebox_override("separator", ss)
	vb.add_child(sep)

	_item_tip_stats_vb = VBoxContainer.new()
	_item_tip_stats_vb.add_theme_constant_override("separation", 2)
	vb.add_child(_item_tip_stats_vb)

	_item_tip_passive_lbl = Label.new()
	_item_tip_passive_lbl.add_theme_font_size_override("font_size", 13)
	_item_tip_passive_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_item_tip_passive_lbl.visible = false
	vb.add_child(_item_tip_passive_lbl)

	_item_tip_passive_desc = Label.new()
	_item_tip_passive_desc.add_theme_font_size_override("font_size", 12)
	_item_tip_passive_desc.add_theme_color_override("font_color", Color(0.70, 0.70, 0.82))
	_item_tip_passive_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_tip_passive_desc.custom_minimum_size = Vector2(174, 0)
	_item_tip_passive_desc.visible = false
	vb.add_child(_item_tip_passive_desc)


func _show_item_tooltip(item: EquipmentItem, mouse_pos: Vector2) -> void:
	if not _item_tip or _dragged_item:
		return
	_item_tip_name_lbl.text = "%s  ·  %s" % [item.name, item.get_rarity_name()]
	_item_tip_name_lbl.add_theme_color_override("font_color", item.icon_color.lightened(0.25))

	for c in _item_tip_stats_vb.get_children():
		c.free()
	const STAT_NAMES := {
		"hp": "HP", "mana": "Mana", "atk": "ATK",
		"magic": "Magic Power", "res": "Defense",
		"aspd": "Attack Speed", "hpregen": "HP Regen", "manaregen": "MP Regen"
	}
	const FLOAT_STATS := ["aspd", "hpregen", "manaregen"]
	for stat in ["hp", "mana", "atk", "magic", "res", "aspd", "hpregen", "manaregen"]:
		var raw: float = float(item.stat_bonus.get(stat, 0))
		if raw > 0:
			var lbl := Label.new()
			if stat in FLOAT_STATS:
				lbl.text = "+%.2f  %s" % [raw, STAT_NAMES.get(stat, stat.to_upper())]
			else:
				lbl.text = "+%d  %s" % [int(raw), STAT_NAMES.get(stat, stat.to_upper())]
			lbl.add_theme_font_size_override("font_size", 13)
			lbl.add_theme_color_override("font_color", Color(0.82, 0.96, 0.72))
			_item_tip_stats_vb.add_child(lbl)

	if item.passive_effect != "":
		_item_tip_passive_lbl.text = "◆ " + item.passive_effect
		_item_tip_passive_lbl.visible = true
		_item_tip_passive_desc.text = item.description
		_item_tip_passive_desc.visible = true
	else:
		_item_tip_passive_lbl.visible = false
		_item_tip_passive_desc.visible = false

	_item_tip.visible = true
	_reposition_item_tooltip(mouse_pos)


func _hide_item_tooltip() -> void:
	if _item_tip:
		_item_tip.visible = false


func _reposition_item_tooltip(mouse_pos: Vector2) -> void:
	if not _item_tip:
		return
	var vp  := get_viewport().get_visible_rect().size
	var ts  := _item_tip.size
	if ts == Vector2.ZERO:
		ts = _item_tip.get_minimum_size()
	var pos := mouse_pos + Vector2(16, -ts.y * 0.5)
	pos.x = clamp(pos.x, 4, vp.x - ts.x - 4)
	pos.y = clamp(pos.y, 4, vp.y - ts.y - 4)
	_item_tip.position = pos


func _create_drag_preview(item: EquipmentItem) -> void:
	_hide_item_tooltip()
	if _drag_layer:
		_drag_layer.queue_free()

	_drag_layer = CanvasLayer.new()
	_drag_layer.layer = 35
	add_child(_drag_layer)

	_drag_panel = Panel.new()
	_drag_panel.size = Vector2(48, 48)
	_drag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_panel.modulate = Color(1, 1, 1, 0.82)
	var s := StyleBoxFlat.new()
	s.bg_color     = item.icon_color.darkened(0.45)
	s.border_color = item.icon_color
	s.set_border_width_all(2)
	s.corner_radius_top_left = 4; s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
	_drag_panel.add_theme_stylebox_override("panel", s)

	var icon_path: String = EquipmentManager.ITEM_ICONS.get(item.name, "")
	if icon_path != "":
		var tex: Texture2D = load(icon_path)
		if tex:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_drag_panel.add_child(tr)

	_drag_layer.add_child(_drag_panel)


func _end_item_drag() -> void:
	var item := _dragged_item
	_dragged_item  = null
	_drag_candidate = null
	if _drag_layer:
		_drag_layer.queue_free()
		_drag_layer = null
		_drag_panel = null

	if not item:
		return

	var mouse     := get_viewport().get_mouse_position()
	var grid_local := mouse - Vector2(battle_grid_node.global_position)
	var cx := int(grid_local.x / battle_grid.cell_size)
	var cy := int(grid_local.y / battle_grid.cell_size)

	if cx < 0 or cx >= battle_grid.grid_width or cy < 0 or cy >= battle_grid.grid_height:
		return
	var unit = battle_grid.get_unit_at(Vector2i(cx, cy))
	if unit and is_instance_valid(unit) and unit.is_player_unit:
		if not _equipment_inventory.apply_to_hero(item, unit):
			info_label.text = "%s already has 6 items!" % unit.unit_name
	else:
		info_label.text = "Drop on a hero to equip."


func _sb_accordion(title: String, body: Control, open: bool = false) -> Button:
	body.visible = open
	var btn := Button.new()
	btn.text      = title + ("  ▼" if open else "  ▶")
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", UITheme.header_font(14))
	btn.add_theme_color_override("font_color", _GOLD_COL)
	# UI theme pass 2026-07-03: dobo header plate for section accordions.
	# NOT flat — flat buttons only draw a stylebox while hovered/pressed/
	# focused, so with `flat=true` the header plate was only ever visible on
	# whichever accordion was last clicked (it keeps focus after the click)
	# and every other header rendered with no background at all (2026-07-04
	# user report: "TeamStatus has the UI but only when it's the last thing
	# you clicked"). focus_mode is also disabled so a click doesn't leave
	# any lingering focus-only visual state.
	btn.focus_mode = Control.FOCUS_NONE
	var s := UITheme.header_box()
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, s)
	btn.pressed.connect(func():
		body.visible = not body.visible
		btn.text = title + ("  ▼" if body.visible else "  ▶")
	)
	return btn
