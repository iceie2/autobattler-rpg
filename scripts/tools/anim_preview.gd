extends CanvasLayer
class_name AnimPreview
# ══════════════════════════════════════════════════════════════════════════════
# ANIMATION / ABILITY PREVIEW — standalone dev tool. Pick any hero or monster,
# play any of its generated animations, or fire its real ability (via a real
# AutoBattleManager + BattleGrid, same code path combat uses) without starting
# a match. Run this scene directly (F6) — no autoloads or game state needed
# beyond the project's own Progression singleton.
#
# CONTROLS
#   type in search   filter the unit list         ← / →   cycle filtered list
#   1-9              play that numbered anim      L       replay current anim
#   Space            cast ACTIVE ability          U       cast ULTIMATE
#   T                tick PASSIVE (1s slice)      R       reset caster+dummies
#   P                pause / resume               [ / ]   step 1 frame (paused)
#   H                hide/show the UI panel       B       cycle background
#   F12              save a screenshot            scroll  zoom (over stage only)
#
# WHY THIS TICKS THE MANAGER MANUALLY (_process below): several abilities don't
# resolve instantly — Nemi's Tide chain, Tidal Wave, Zolt's storms and every
# board field play out over real seconds inside AutoBattleManager's
# _tick_global_effects(). That only runs from the manager's own _process(),
# which early-returns unless `battle_active` is true. Rather than flip that flag
# (which would also run _tick_unit on everything and turn this into a live
# brawl where units walk off and fight), we drive just the global-effect and
# movement ticks ourselves. "Live AI" opts into the full sim when you do want
# to watch a real fight.
#
# Still not a full combat sim: abilities that lean on board-wide state a single
# 9x9 grid can't provide may print a script error to the Output panel instead of
# rendering. Everything else fires exactly as it does in a real battle.
# ══════════════════════════════════════════════════════════════════════════════

# Monster type strings — must match EnemyFactory._create_by_type_dispatch()'s
# match arms (scripts/units/enemy_factory.gd). No enum exists for these, so
# this list is hand-kept; a monster added there needs adding here too.
const MONSTER_TYPES := [
	"goblin", "goblin_archer",
	"goblin_shaman_normal", "goblin_shaman_fire", "goblin_shaman_water",
	"goblin_shaman_earth", "goblin_shaman_air", "goblin_shaman_lightning",
	"orc_normal", "orc_fire", "orc_water", "orc_earth", "orc_air", "orc_lightning",
	"hill_giant", "gale_warden", "tidecaller", "terracotta_colossus",
	"magma_heart", "tempest_conduit", "mirrorplate_warden", "aspect_devourer",
	"slime_normal", "slime_fire", "slime_water", "slime_earth", "slime_air", "slime_lightning",
	"lizard_normal", "lizard_fire", "lizard_water", "lizard_earth", "lizard_air", "lizard_lightning",
	"bear_normal", "bear_fire", "bear_water", "bear_earth", "bear_air", "bear_lightning",
	"troll_normal", "troll_fire", "troll_water", "troll_earth", "troll_air", "troll_lightning",
	"windup_bot_normal", "windup_bot_fire", "windup_bot_water", "windup_bot_earth",
	"windup_bot_air", "windup_bot_lightning",
	"hydra_normal", "hydra_fire", "hydra_water", "hydra_earth", "hydra_air", "hydra_lightning",
	"skeleton", "rat", "triarch", "stat_stealer", "ant_hill", "khagan",
	"skyrender", "drowned_maw", "cloven_titan", "emberhollow", "ember_heart",
	"arcfang", "gravekeeper", "the_architect",
	"ogre", "minotaur", "gargoyle", "stone_golem", "crystal_crab", "root_walker",
	"fire_giant", "hellhound", "ember_phoenix", "storm_giant", "storm_crow",
	"sky_wyvern", "tidepool_horror", "harpy", "coral_husk",
]

const ANIM_BUTTONS := [
	"idle_south", "idle_north",
	"walk_south", "walk_north", "walk_east", "walk_west",
	"attack", "hurt", "death",
]

const ELEMENT_NAMES := ["Normal", "Fire", "Water", "Earth", "Air", "Lightning"]
const PLAY_ALL_DELAY := 0.9
const SETTINGS_PATH := "user://anim_preview.cfg"
const SHOT_DIR := "user://anim_shots"

# Backgrounds worth checking art against — a sprite that reads fine on the dark
# game backdrop can have muddy outlines or leftover matte fringe that only shows
# up on white or a saturated colour. Cycle with B.
const BACKGROUNDS := [
	{"name": "dark (game)", "color": Color(0.09, 0.09, 0.11)},
	{"name": "mid grey",    "color": Color(0.45, 0.45, 0.47)},
	{"name": "white",       "color": Color(0.95, 0.95, 0.95)},
	{"name": "magenta",     "color": Color(1.0, 0.0, 1.0)},
	{"name": "arena sand",  "color": Color(0.62, 0.52, 0.36)},
]

# ── UI refs ──────────────────────────────────────────────────────────────────
var panel: VBoxContainer
var category_box: OptionButton
var search_box: LineEdit
var unit_box: OptionButton
var prev_btn: Button
var next_btn: Button
var element_box: OptionButton
var enemy_side_check: CheckBox
var live_ai_check: CheckBox
var loop_check: CheckBox
var speed_slider: HSlider
var speed_label: Label
var zoom_slider: HSlider
var zoom_label: Label
var status_label: Label
var info_label: Label
var frame_label: Label
var pause_btn: Button
var bg_btn: Button
var anim_buttons: Dictionary = {}   # anim name -> Button
var anim_flow: GridContainer        # holds them; rebuilt per unit
var _anim_names: Array = []         # the names currently on show
var ability_btn: Button
var ultimate_btn: Button
var passive_btn: Button
var ability_names_label: Label
var play_all_btn: Button
var bg_rect: ColorRect

# ── Live state ───────────────────────────────────────────────────────────────
var stage: Node2D
var ground: ColorRect
var grid: BattleGrid
var mgr: AutoBattleManager
var skill_fx_layer: Node2D
var projectile_layer: Node2D

var caster: VisualUnit = null
var dummy_ally: VisualUnit = null
var dummy_enemy: VisualUnit = null
var dummy_ally_label: Label
var dummy_enemy_label: Label

var _all_heroes: Array = []
var _all_monsters: Array = MONSTER_TYPES
var _filtered_heroes: Array = []
var _filtered_monsters: Array = []

var _play_all_running: bool = false
var _pending_restore_name: String = ""
var _paused: bool = false
var _bg_index: int = 0
var _section_open: Dictionary = {}   # section title -> bool, persisted
var _current_anim: String = ""

func _ready() -> void:
	for name_str in UnitBase.UnitClass.keys():
		var cls: UnitBase.UnitClass = UnitBase.UnitClass[name_str]
		if UnitFactory.CLASS_BASE_STATS.has(cls):
			_all_heroes.append({"name": name_str.capitalize(), "cls": cls})

	# Section open/closed must be known BEFORE the UI is built (the headers are
	# created already-expanded-or-not), so it's read separately and earlier than
	# the rest of the settings, which need the widgets to exist first.
	_load_section_state()
	_build_ui()
	_build_combat_rig()
	_load_settings()
	_apply_background()
	_on_category_changed(0)

# Drives the time-based half of the ability system by hand — see the header
# note. Deliberately skips _tick_unit()/check_battle_end() so units don't start
# walking around and fighting unless "Live AI" is on.
func _process(delta: float) -> void:
	if mgr and not _paused:
		if live_ai_check and live_ai_check.button_pressed:
			mgr.battle_active = true   # full sim: manager's own _process drives everything
		else:
			mgr.battle_active = false
			mgr._tick_global_effects(delta)
			for storm in mgr.storms:
				if storm and is_instance_valid(storm):
					storm.tick(delta)
			mgr.update_unit_movements(delta)
	_update_frame_readout()

func _update_frame_readout() -> void:
	if caster and is_instance_valid(caster) and caster.model3d:
		var ap: AnimationPlayer = caster.model3d._anim
		var len3: float = caster.model3d.animation_length(_current_anim)
		frame_label.text = "%s — %.2fs / %.2fs%s" % [
			_current_anim, ap.current_animation_position, len3,
			("   [PAUSED]" if _paused else "")]
		return
	if not (caster and is_instance_valid(caster) and caster.animated_sprite):
		frame_label.text = ""
		return
	var sf: SpriteFrames = caster.animated_sprite.sprite_frames
	var a: String = caster.animated_sprite.animation
	if not sf or a == "" or not sf.has_animation(a):
		frame_label.text = ""
		return
	frame_label.text = "%s — frame %d / %d   @ %.0f fps%s" % [
		a, caster.animated_sprite.frame + 1, sf.get_frame_count(a),
		sf.get_animation_speed(a), ("   [PAUSED]" if _paused else ""),
	]

# ── Combat rig ───────────────────────────────────────────────────────────────
func _build_combat_rig() -> void:
	grid = BattleGrid.new()
	grid.visible = false
	add_child(grid)

	mgr = AutoBattleManager.new()
	add_child(mgr)
	mgr.battle_grid = grid
	skill_fx_layer = Node2D.new()
	projectile_layer = Node2D.new()
	stage.add_child(skill_fx_layer)
	stage.add_child(projectile_layer)
	mgr.skill_effect_container = skill_fx_layer
	mgr.projectile_container = projectile_layer

# ── UI construction ────────────────────────────────────────────────────────
# Godot has no <details> equivalent, so a "section" is just a flat header
# Button that toggles a VBoxContainer body. Open/closed state persists via
# _save_settings() so the panel comes back the way you left it.
func _add_section(title: String, start_open: bool = true) -> VBoxContainer:
	var open: bool = _section_open.get(title, start_open)
	var hdr := Button.new()
	hdr.focus_mode = Control.FOCUS_NONE
	hdr.flat = true
	hdr.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hdr.add_theme_font_size_override("font_size", 14)
	panel.add_child(hdr)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.visible = open
	panel.add_child(body)

	hdr.text = ("▼  " if open else "▶  ") + title
	hdr.pressed.connect(func():
		body.visible = not body.visible
		hdr.text = ("▼  " if body.visible else "▶  ") + title
		_section_open[title] = body.visible
		_save_settings()
	)
	_section_open[title] = open
	return body

func _build_ui() -> void:
	bg_rect = ColorRect.new()
	bg_rect.color = BACKGROUNDS[0]["color"]
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg_rect)

	ground = ColorRect.new()
	ground.color = Color(1, 1, 1, 0.1)
	ground.position = Vector2(-2000, 619)
	ground.size = Vector2(4000, 2)
	add_child(ground)

	stage = Node2D.new()
	stage.position = Vector2(620, 620)
	stage.scale = Vector2(2.5, 2.5)
	add_child(stage)

	panel = VBoxContainer.new()
	panel.position = Vector2(940, 20)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_constant_override("separation", 8)
	add_child(panel)

	var title := Label.new()
	title.text = "Animation / Ability Preview"
	title.add_theme_font_size_override("font_size", 22)
	panel.add_child(title)

	var legend := Label.new()
	legend.text = "search to filter · ←/→ unit · 1-9 anim · L replay · Space active · U ultimate · T passive · R reset · P pause · [ ] step · H hide UI · B background · F12 shot · scroll zoom"
	legend.add_theme_font_size_override("font_size", 12)
	legend.modulate = Color(1, 1, 1, 0.55)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(legend)

	# ── Unit & spawn ────────────────────────────────────────────────────────
	var sec_unit := _add_section("Unit & spawn")

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	sec_unit.add_child(row1)

	category_box = OptionButton.new()
	category_box.focus_mode = Control.FOCUS_NONE
	category_box.add_item("Hero")
	category_box.add_item("Monster")
	category_box.select(0)
	category_box.item_selected.connect(_on_category_changed)
	row1.add_child(category_box)

	search_box = LineEdit.new()
	search_box.placeholder_text = "search..."
	search_box.custom_minimum_size = Vector2(140, 0)
	search_box.text_changed.connect(_on_search_changed)
	row1.add_child(search_box)

	prev_btn = Button.new()
	prev_btn.text = "<"
	prev_btn.focus_mode = Control.FOCUS_NONE
	prev_btn.pressed.connect(func(): _cycle_unit(-1))
	row1.add_child(prev_btn)

	unit_box = OptionButton.new()
	unit_box.focus_mode = Control.FOCUS_NONE
	unit_box.custom_minimum_size = Vector2(220, 0)
	unit_box.item_selected.connect(func(_i): _spawn_selected())
	row1.add_child(unit_box)

	next_btn = Button.new()
	next_btn.text = ">"
	next_btn.focus_mode = Control.FOCUS_NONE
	next_btn.pressed.connect(func(): _cycle_unit(1))
	row1.add_child(next_btn)

	# Element + side + sim toggles
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	sec_unit.add_child(row2)

	var elem_lbl := Label.new()
	elem_lbl.text = "Element:"
	row2.add_child(elem_lbl)

	element_box = OptionButton.new()
	element_box.focus_mode = Control.FOCUS_NONE
	for e in ELEMENT_NAMES:
		element_box.add_item(e)
	element_box.select(0)
	element_box.item_selected.connect(func(_i): _spawn_selected())
	row2.add_child(element_box)

	enemy_side_check = CheckBox.new()
	enemy_side_check.focus_mode = Control.FOCUS_NONE
	enemy_side_check.text = "Enemy-side"
	enemy_side_check.toggled.connect(func(_v): _spawn_selected())
	row2.add_child(enemy_side_check)

	live_ai_check = CheckBox.new()
	live_ai_check.focus_mode = Control.FOCUS_NONE
	live_ai_check.text = "Live AI"
	live_ai_check.tooltip_text = "Run the FULL battle sim — units retarget, move and attack on their own. Off = frozen stage, only what you trigger."
	live_ai_check.toggled.connect(_on_live_ai_toggled)
	row2.add_child(live_ai_check)

	# Always-visible readouts — compact and the whole point of the tool, so they
	# sit outside every collapsible section and can't be hidden by accident.
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.modulate = Color(0.6, 0.85, 1.0)
	panel.add_child(info_label)

	frame_label = Label.new()
	frame_label.add_theme_font_size_override("font_size", 13)
	frame_label.modulate = Color(1.0, 0.85, 0.5)
	panel.add_child(frame_label)

	# ── Animations ──────────────────────────────────────────────────────────
	var sec_anim := _add_section("Animations")

	var anim_hdr := Label.new()
	anim_hdr.text = "grey = not generated for this unit yet"
	anim_hdr.add_theme_font_size_override("font_size", 12)
	anim_hdr.modulate = Color(1, 1, 1, 0.6)
	sec_anim.add_child(anim_hdr)

	# The button set is REBUILT per unit (_rebuild_anim_buttons): a 2D unit has
	# the fixed directional sheet names, a 3D one has whatever clips its .glb
	# shipped with, and those two lists have nothing in common.
	anim_flow = GridContainer.new()
	anim_flow.columns = 5
	anim_flow.add_theme_constant_override("h_separation", 6)
	anim_flow.add_theme_constant_override("v_separation", 6)
	sec_anim.add_child(anim_flow)
	_rebuild_anim_buttons(ANIM_BUTTONS)

	var row_pb := HBoxContainer.new()
	row_pb.add_theme_constant_override("separation", 6)
	sec_anim.add_child(row_pb)

	play_all_btn = Button.new()
	play_all_btn.focus_mode = Control.FOCUS_NONE
	play_all_btn.text = "▶ Play All"
	play_all_btn.pressed.connect(_on_play_all_pressed)
	row_pb.add_child(play_all_btn)

	var replay_btn := Button.new()
	replay_btn.focus_mode = Control.FOCUS_NONE
	replay_btn.text = "↻ Replay  (l)"
	replay_btn.tooltip_text = "Restart the current animation from frame 0 — one-shots (attack/hurt/death) hold on their last frame, so this is how you watch them again."
	replay_btn.pressed.connect(_replay_current)
	row_pb.add_child(replay_btn)

	pause_btn = Button.new()
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.text = "❚❚ Pause  (p)"
	pause_btn.pressed.connect(_toggle_pause)
	row_pb.add_child(pause_btn)

	var step_back := Button.new()
	step_back.focus_mode = Control.FOCUS_NONE
	step_back.text = "["
	step_back.tooltip_text = "Step back one frame (pauses first)"
	step_back.pressed.connect(func(): _step_frame(-1))
	row_pb.add_child(step_back)

	var step_fwd := Button.new()
	step_fwd.focus_mode = Control.FOCUS_NONE
	step_fwd.text = "]"
	step_fwd.tooltip_text = "Step forward one frame (pauses first)"
	step_fwd.pressed.connect(func(): _step_frame(1))
	row_pb.add_child(step_fwd)

	loop_check = CheckBox.new()
	loop_check.focus_mode = Control.FOCUS_NONE
	loop_check.text = "Force loop"
	loop_check.tooltip_text = "Make one-shots (attack/hurt/death) loop so you can study them without re-clicking"
	loop_check.toggled.connect(_on_force_loop_toggled)
	row_pb.add_child(loop_check)

	# ── Abilities ───────────────────────────────────────────────────────────
	var sec_abil := _add_section("Abilities")

	ability_names_label = Label.new()
	ability_names_label.add_theme_font_size_override("font_size", 12)
	ability_names_label.modulate = Color(0.75, 0.7, 1.0)
	ability_names_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	ability_names_label.custom_minimum_size = Vector2(540, 0)
	sec_abil.add_child(ability_names_label)

	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 6)
	sec_abil.add_child(row4)

	ability_btn = Button.new()
	ability_btn.focus_mode = Control.FOCUS_NONE
	ability_btn.text = "Active  (space)"
	ability_btn.custom_minimum_size = Vector2(130, 36)
	ability_btn.pressed.connect(_on_ability_pressed)
	row4.add_child(ability_btn)

	ultimate_btn = Button.new()
	ultimate_btn.focus_mode = Control.FOCUS_NONE
	ultimate_btn.text = "★ Ultimate  (u)"
	ultimate_btn.custom_minimum_size = Vector2(150, 36)
	ultimate_btn.tooltip_text = "Fires _use_ultimate() — the same call the battle makes the instant the charge bar fills."
	ultimate_btn.pressed.connect(_on_ultimate_pressed)
	row4.add_child(ultimate_btn)

	passive_btn = Button.new()
	passive_btn.focus_mode = Control.FOCUS_NONE
	passive_btn.text = "Passive tick  (t)"
	passive_btn.custom_minimum_size = Vector2(140, 36)
	passive_btn.tooltip_text = "Runs one 1.0s slice of _tick_passive(). Passives are continuous in combat, so most only show an effect via stacking buffs/auras rather than a visible burst."
	passive_btn.pressed.connect(_on_passive_pressed)
	row4.add_child(passive_btn)

	var row4b := HBoxContainer.new()
	row4b.add_theme_constant_override("separation", 6)
	sec_abil.add_child(row4b)

	var reset_btn := Button.new()
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.text = "Reset All  (r)"
	reset_btn.tooltip_text = "Clears HP/mana/stun/shields/status metas on the caster AND both dummies, and wipes lingering board effects"
	reset_btn.pressed.connect(_reset_all)
	row4b.add_child(reset_btn)

	var full_btn := Button.new()
	full_btn.focus_mode = Control.FOCUS_NONE
	full_btn.text = "▶ Full kit (passive → active → ultimate)"
	full_btn.tooltip_text = "Fires all three tiers in sequence with a pause between, so you can see a unit's whole kit in one go."
	full_btn.pressed.connect(_run_full_kit)
	row4b.add_child(full_btn)

	# ── View & display (collapsed by default — set once, rarely touched) ─────
	var sec_view := _add_section("View & display", false)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	sec_view.add_child(row3)

	var speed_lbl := Label.new()
	speed_lbl.text = "Speed:"
	row3.add_child(speed_lbl)

	speed_slider = HSlider.new()
	speed_slider.focus_mode = Control.FOCUS_NONE
	speed_slider.min_value = 0.1
	speed_slider.max_value = 3.0
	speed_slider.step = 0.1
	speed_slider.value = 1.0
	speed_slider.custom_minimum_size = Vector2(120, 0)
	speed_slider.value_changed.connect(_on_speed_changed)
	row3.add_child(speed_slider)

	speed_label = Label.new()
	speed_label.text = "1.0x"
	speed_label.custom_minimum_size = Vector2(38, 0)
	row3.add_child(speed_label)

	var zoom_lbl := Label.new()
	zoom_lbl.text = "  Zoom:"
	row3.add_child(zoom_lbl)

	zoom_slider = HSlider.new()
	zoom_slider.focus_mode = Control.FOCUS_NONE
	zoom_slider.min_value = 0.5
	zoom_slider.max_value = 5.0
	zoom_slider.step = 0.1
	zoom_slider.value = 2.5
	zoom_slider.custom_minimum_size = Vector2(120, 0)
	zoom_slider.value_changed.connect(_on_zoom_changed)
	row3.add_child(zoom_slider)

	zoom_label = Label.new()
	zoom_label.text = "2.5x"
	zoom_label.custom_minimum_size = Vector2(38, 0)
	row3.add_child(zoom_label)

	var row5 := HBoxContainer.new()
	row5.add_theme_constant_override("separation", 8)
	sec_view.add_child(row5)

	bg_btn = Button.new()
	bg_btn.focus_mode = Control.FOCUS_NONE
	bg_btn.text = "BG: dark (game)  (b)"
	bg_btn.tooltip_text = "Cycle backdrop — checks outlines/matte fringe that only show up on light or saturated backgrounds"
	bg_btn.pressed.connect(_cycle_background)
	row5.add_child(bg_btn)

	var hide_btn := Button.new()
	hide_btn.focus_mode = Control.FOCUS_NONE
	hide_btn.text = "Hide UI  (h)"
	hide_btn.pressed.connect(func(): panel.visible = false)
	row5.add_child(hide_btn)

	var shot_btn := Button.new()
	shot_btn.focus_mode = Control.FOCUS_NONE
	shot_btn.text = "Screenshot  (f12)"
	shot_btn.pressed.connect(_save_screenshot)
	row5.add_child(shot_btn)

	status_label = Label.new()
	status_label.text = "Ready."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.custom_minimum_size = Vector2(540, 0)
	panel.add_child(status_label)

# ── Settings persistence ────────────────────────────────────────────────────
func _load_section_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var saved = cfg.get_value("s", "sections", {})
	if saved is Dictionary:
		_section_open = saved.duplicate()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	category_box.select(cfg.get_value("s", "category", 0))
	element_box.select(cfg.get_value("s", "element", 0))
	enemy_side_check.button_pressed = cfg.get_value("s", "enemy_side", false)
	speed_slider.value = cfg.get_value("s", "speed", 1.0)
	zoom_slider.value = cfg.get_value("s", "zoom", 2.5)
	_bg_index = cfg.get_value("s", "bg", 0)
	_pending_restore_name = cfg.get_value("s", "unit_name", "")

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("s", "category", category_box.selected)
	cfg.set_value("s", "element", element_box.selected)
	cfg.set_value("s", "enemy_side", enemy_side_check.button_pressed)
	cfg.set_value("s", "speed", speed_slider.value)
	cfg.set_value("s", "zoom", zoom_slider.value)
	cfg.set_value("s", "bg", _bg_index)
	cfg.set_value("s", "sections", _section_open)
	if unit_box.selected >= 0:
		cfg.set_value("s", "unit_name", unit_box.get_item_text(unit_box.selected))
	cfg.save(SETTINGS_PATH)

# ── View helpers ────────────────────────────────────────────────────────────
func _apply_background() -> void:
	_bg_index = _bg_index % BACKGROUNDS.size()
	var b: Dictionary = BACKGROUNDS[_bg_index]
	bg_rect.color = b["color"]
	# Keep the ground line readable against light backdrops.
	var light: bool = b["color"].get_luminance() > 0.5
	ground.color = Color(0, 0, 0, 0.25) if light else Color(1, 1, 1, 0.1)
	bg_btn.text = "BG: %s  (b)" % b["name"]

func _cycle_background() -> void:
	_bg_index = (_bg_index + 1) % BACKGROUNDS.size()
	_apply_background()
	_save_settings()

func _save_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var unit_name: String = unit_box.get_item_text(unit_box.selected) if unit_box.selected >= 0 else "unit"
	var fname: String = "%s_%s_%d.png" % [unit_name.to_lower().replace(" ", "_"), _current_anim, Time.get_ticks_msec()]
	var path: String = SHOT_DIR + "/" + fname
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(path)
	if err == OK:
		status_label.text = "Saved screenshot → %s" % ProjectSettings.globalize_path(path)
	else:
		status_label.text = "Screenshot failed (err %d)." % err

func _on_speed_changed(v: float) -> void:
	speed_label.text = "%.1fx" % v
	if caster and caster.model3d and not _paused:
		caster.model3d.set_speed_scale(v)
	if caster and caster.animated_sprite:
		caster.animated_sprite.speed_scale = v
	_save_settings()

func _on_zoom_changed(v: float) -> void:
	zoom_label.text = "%.1fx" % v
	stage.scale = Vector2(v, v)
	_reposition_dummies()
	_save_settings()

func _on_live_ai_toggled(on: bool) -> void:
	# Live AI needs the real per-unit tick, which drives its own animation state
	# machine — so the preview lock has to come off or the sprite would freeze
	# on whatever we last clicked while the unit actually walks and fights.
	if caster and is_instance_valid(caster):
		if on:
			caster.remove_meta("anim_preview_lock")
		else:
			caster.set_meta("anim_preview_lock", true)
	status_label.text = ("Live AI ON — units act on their own; anim buttons will be overridden by the AI."
			if on else "Live AI off — stage frozen, only what you trigger runs.")

func _on_force_loop_toggled(on: bool) -> void:
	if caster and caster.model3d:
		# 3D clips carry their loop flag on the Animation, so just replay the
		# current one under the new setting.
		if _current_anim != "":
			_play_anim(_current_anim)
		status_label.text = "One-shot looping %s." % ("ON" if on else "OFF")
		return
	if not (caster and caster.animated_sprite and caster.animated_sprite.sprite_frames):
		return
	var sf: SpriteFrames = caster.animated_sprite.sprite_frames
	for anim in ["attack", "hurt", "death"]:
		if sf.has_animation(anim):
			sf.set_animation_loop(anim, on)
	status_label.text = "One-shot looping %s." % ("ON" if on else "OFF")

func _reposition_dummies() -> void:
	var s: float = max(stage.scale.x, 0.01)
	if dummy_ally and is_instance_valid(dummy_ally):
		dummy_ally.position = Vector2(-160, 0) / s
	if dummy_enemy and is_instance_valid(dummy_enemy):
		dummy_enemy.position = Vector2(160, 0) / s
	if dummy_ally_label:
		dummy_ally_label.position = Vector2(-160, 0) / s + Vector2(-50, -90) / s
		dummy_ally_label.scale = Vector2(1, 1) / s
	if dummy_enemy_label:
		dummy_enemy_label.position = Vector2(160, 0) / s + Vector2(-55, -90) / s
		dummy_enemy_label.scale = Vector2(1, 1) / s

# ── Category / search / unit list ───────────────────────────────────────────
func _on_category_changed(_idx: int) -> void:
	element_box.visible = category_box.selected == 0
	search_box.text = ""
	_rebuild_unit_list("")

func _on_search_changed(t: String) -> void:
	_rebuild_unit_list(t)

func _rebuild_unit_list(filter_text: String) -> void:
	unit_box.clear()
	var f := filter_text.to_lower()
	if category_box.selected == 0:
		_filtered_heroes.clear()
		for h in _all_heroes:
			if f == "" or f in String(h["name"]).to_lower():
				_filtered_heroes.append(h)
				unit_box.add_item(h["name"])
	else:
		_filtered_monsters.clear()
		for t in _all_monsters:
			if f == "" or f in String(t).to_lower():
				_filtered_monsters.append(t)
				unit_box.add_item(t)
	if unit_box.item_count > 0:
		var restore_idx := 0
		if _pending_restore_name != "":
			for i in unit_box.item_count:
				if unit_box.get_item_text(i) == _pending_restore_name:
					restore_idx = i
					break
			_pending_restore_name = ""
		unit_box.select(restore_idx)
		_spawn_selected()
	else:
		status_label.text = "No match for \"%s\"." % filter_text

func _cycle_unit(delta: int) -> void:
	if unit_box.item_count == 0:
		return
	var n := unit_box.item_count
	unit_box.select((unit_box.selected + delta + n) % n)
	_spawn_selected()

# ── Spawning ─────────────────────────────────────────────────────────────────
func _spawn_selected() -> void:
	_teardown_units()

	var is_hero := category_box.selected == 0
	var is_enemy_side := enemy_side_check.button_pressed
	var idx: int = unit_box.selected

	if is_hero:
		if idx < 0 or idx >= _filtered_heroes.size():
			return
		var cls: UnitBase.UnitClass = _filtered_heroes[idx]["cls"]
		var elem: UnitBase.Element = UnitBase.Element.values()[element_box.selected]
		caster = UnitFactory.create_unit(cls, elem, not is_enemy_side)
	else:
		if idx < 0 or idx >= _filtered_monsters.size():
			return
		caster = EnemyFactory.create_by_type(_filtered_monsters[idx])
		if caster:
			caster.is_player_unit = not is_enemy_side

	if not caster:
		status_label.text = "Failed to construct that unit — check Output panel."
		return

	stage.add_child(caster)
	caster.position = Vector2.ZERO
	caster.grid_position = Vector2i(4, 4)
	grid.place_unit(caster, caster.grid_position)
	# See visual_unit.gd::_update_animation() — stops the per-frame walk/idle
	# state machine from overriding our manual anim-button clicks every frame.
	if not (live_ai_check and live_ai_check.button_pressed):
		caster.set_meta("anim_preview_lock", true)

	dummy_ally = UnitFactory.create_unit(UnitBase.UnitClass.BLOODHOUND,
			UnitFactory.element_for_class(UnitBase.UnitClass.BLOODHOUND), not is_enemy_side)
	dummy_enemy = EnemyFactory.create_by_type("goblin")
	if dummy_enemy:
		dummy_enemy.is_player_unit = is_enemy_side

	stage.add_child(dummy_ally)
	stage.add_child(dummy_enemy)
	dummy_ally.grid_position = Vector2i(1, 4)
	grid.place_unit(dummy_ally, dummy_ally.grid_position)
	dummy_ally.modulate.a = 0.55

	dummy_enemy.grid_position = Vector2i(7, 4)
	grid.place_unit(dummy_enemy, dummy_enemy.grid_position)
	dummy_enemy.modulate.a = 0.55

	dummy_ally_label = Label.new()
	dummy_ally_label.text = "ALLY (dummy)"
	dummy_ally_label.add_theme_font_size_override("font_size", 14)
	dummy_ally_label.modulate = Color(0.6, 1.0, 0.6)
	stage.add_child(dummy_ally_label)

	dummy_enemy_label = Label.new()
	dummy_enemy_label.text = "ENEMY (dummy)"
	dummy_enemy_label.add_theme_font_size_override("font_size", 14)
	dummy_enemy_label.modulate = Color(1.0, 0.6, 0.6)
	stage.add_child(dummy_enemy_label)

	_reposition_dummies()

	if is_enemy_side:
		mgr.enemy_units = [caster]
		mgr.player_units = [dummy_ally, dummy_enemy]
	else:
		mgr.player_units = [caster]
		mgr.enemy_units = [dummy_ally, dummy_enemy]

	if caster.animated_sprite:
		caster.animated_sprite.speed_scale = speed_slider.value

	_refresh_anim_buttons()
	if loop_check.button_pressed:
		_on_force_loop_toggled(true)

	var label: String = unit_box.get_item_text(unit_box.selected)
	# _anim_names, NOT ANIM_BUTTONS: for a 3D unit the buttons hold that model's
	# clip names and every 2D sheet name would be a missing dictionary key.
	var missing: Array = []
	for anim in _anim_names:
		if anim_buttons[anim].disabled:
			missing.append(anim)
	status_label.text = "Spawned %s.%s%s" % [
		label,
		(" (enemy-side)" if is_enemy_side else ""),
		("  Missing sheets: " + ", ".join(missing)) if not missing.is_empty() else "  All 9 sheets present.",
	]
	info_label.text = "%s  —  HP %d/%d   Mana %d/%d   ATK %d   MAG %d   range %d   %s" % [
		label, caster.current_hp, caster.max_hp,
		caster.current_mana, caster.max_mana,
		caster.attack_damage, caster.magic_power,
		caster.attack_range,
		("%dx%d cells" % [caster.cell_size, caster.cell_size]),
	]

	_refresh_ability_names()

	# 3D models ship a single "idle"; 2D units have per-direction idle sheets.
	var start_anim := "idle_north" if is_enemy_side else "idle_south"
	if caster and caster.model3d:
		start_anim = "idle"
	if anim_buttons.has(start_anim) and not anim_buttons[start_anim].disabled:
		_play_anim(start_anim)
	elif anim_buttons.has("walk_south") and not anim_buttons["walk_south"].disabled:
		_play_anim("walk_south")

	_save_settings()

func _refresh_ability_names() -> void:
	if not caster:
		ability_names_label.text = ""
		return
	# Mobs dispatch their active/passive off `mob_skill`/`mob_passive` metas, but
	# _use_ultimate() only ever matches on unit_class — and mobs piggyback hero
	# classes for stats/sprites. So a mob's "ultimate" is either the hero
	# ultimate of whatever class it borrowed, or nothing at all. Say so rather
	# than letting a misleading result look authoritative.
	var is_mob: bool = caster.has_meta("mob_skill") or caster.has_meta("mob_passive")
	var ult_note := ""
	if is_mob:
		ult_note = "  ⚠ mob — no mob-specific ultimate path; this falls through to its borrowed hero class"
		ultimate_btn.modulate = Color(1.0, 0.8, 0.5)
	else:
		ultimate_btn.modulate = Color(1, 1, 1)
	ability_names_label.text = "passive: %s   ·   active: %s   ·   ultimate: %s%s" % [
		_name_or(caster.passive_name, "—"),
		_name_or(caster.skill_name, "—"),
		_name_or(caster.ultimate_name, "—"),
		ult_note,
	]

func _teardown_units() -> void:
	_play_all_running = false
	if play_all_btn:
		play_all_btn.text = "▶ Play All"
	for u in [caster, dummy_ally, dummy_enemy]:
		if u and is_instance_valid(u):
			grid.purge_unit(u)
			u.queue_free()
	for lbl in [dummy_ally_label, dummy_enemy_label]:
		if lbl and is_instance_valid(lbl):
			lbl.queue_free()
	caster = null
	dummy_ally = null
	dummy_enemy = null
	dummy_ally_label = null
	dummy_enemy_label = null
	_current_anim = ""
	mgr.player_units = []
	mgr.enemy_units = []
	_clear_board_effects()
	for c in skill_fx_layer.get_children():
		c.queue_free()
	for c in projectile_layer.get_children():
		c.queue_free()

# Lingering board state from a previous cast would otherwise keep ticking (and
# keep damaging) across a unit swap, since this rig never ends a "round".
# Delegates to the manager's own round-end teardown so we inherit its handling
# for free — notably it frees the tidal-wave effect nodes, which a hand-rolled
# version here leaked.
func _clear_board_effects() -> void:
	mgr._clear_board_effects()
	mgr.afterimage_time = 0.0     # not covered by the manager's version
	mgr.afterimage_actor = null

const _RESETTABLE_METAS := ["presence_bonus"]

func _reset_one_unit(u: VisualUnit) -> void:
	if not u or not is_instance_valid(u):
		return
	u.current_hp = u.max_hp
	u.current_mana = u.max_mana
	u.current_shield = 0
	u.stun_time = 0.0
	u.untargetable_time = 0.0
	if "melee_untargetable_time" in u:
		u.melee_untargetable_time = 0.0
	for m in _RESETTABLE_METAS:
		if u.has_meta(m):
			u.remove_meta(m)

func _reset_all() -> void:
	_reset_one_unit(caster)
	_reset_one_unit(dummy_ally)
	_reset_one_unit(dummy_enemy)
	_clear_board_effects()
	status_label.text = "Reset caster + dummies (HP/mana/shield/stun/metas) and cleared board effects."

# ── Animation control ────────────────────────────────────────────────────────
func _rebuild_anim_buttons(names: Array) -> void:
	for c in anim_flow.get_children():
		anim_flow.remove_child(c)
		c.queue_free()
	anim_buttons.clear()
	_anim_names = names.duplicate()
	for i in names.size():
		var anim: String = names[i]
		var b := Button.new()
		b.text = ("%d. %s" % [i + 1, anim]) if i < 9 else anim
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = true
		b.pressed.connect(_on_anim_pressed.bind(anim))
		anim_flow.add_child(b)
		anim_buttons[anim] = b

func _refresh_anim_buttons() -> void:
	# A 3D unit advertises its own clip list; a 2D one uses the fixed sheet names.
	# The two share no names at all, so the button row is rebuilt on the switch.
	if caster and caster.model3d:
		var clips: Array = Array(caster.model3d.get_animation_list())
		if clips != _anim_names:
			_rebuild_anim_buttons(clips)
		for anim in _anim_names:
			anim_buttons[anim].disabled = false
			anim_buttons[anim].tooltip_text = "%.2fs" % caster.model3d.animation_length(anim)
		return

	if _anim_names != ANIM_BUTTONS:
		_rebuild_anim_buttons(ANIM_BUTTONS)
	for anim in _anim_names:
		var b: Button = anim_buttons[anim]
		var has_it: bool = caster and caster.animated_sprite and caster.animated_sprite.sprite_frames \
			and caster.animated_sprite.sprite_frames.has_animation(anim)
		b.disabled = not has_it
		b.tooltip_text = "" if has_it else "No %s.png generated for this unit yet" % anim

func _on_anim_pressed(anim: String) -> void:
	_play_anim(anim)

func _play_anim(anim: String) -> void:
	if caster and caster.model3d:
		# Force-loop makes a one-shot (attack/hurt/death) repeat so it can be
		# studied; otherwise it plays once and holds, like it does in combat.
		var loop: bool = loop_check and loop_check.button_pressed
		if not caster.model3d.play(anim, loop):
			status_label.text = "No '%s' clip in this model." % anim
			return
		_current_anim = anim
		if _paused:
			caster.model3d.set_speed_scale(0.0)
		status_label.text = "Playing: %s  (%.2fs)" % [anim, caster.model3d.animation_length(anim)]
		return
	if not caster or not caster.animated_sprite or not caster.animated_sprite.sprite_frames:
		return
	if not caster.animated_sprite.sprite_frames.has_animation(anim):
		status_label.text = "No %s animation generated for this unit." % anim
		return
	_current_anim = anim
	caster.animated_sprite.play(anim)
	caster.animated_sprite.frame = 0
	if _paused:
		caster.animated_sprite.pause()
	status_label.text = "Playing: %s" % anim

func _replay_current() -> void:
	if _current_anim == "":
		return
	if _paused:
		_toggle_pause()
	_play_anim(_current_anim)

func _toggle_pause() -> void:
	_paused = not _paused
	pause_btn.text = "▶ Resume  (p)" if _paused else "❚❚ Pause  (p)"
	if caster and caster.model3d:
		# No frame concept on a skeletal clip — freeze it by zeroing playback.
		caster.model3d.set_speed_scale(0.0 if _paused else speed_slider.value)
	if caster and caster.animated_sprite:
		if _paused:
			caster.animated_sprite.pause()
		else:
			caster.animated_sprite.play()
	status_label.text = "Paused." if _paused else "Resumed."

func _step_frame(delta: int) -> void:
	if caster and caster.model3d:
		if not _paused:
			_toggle_pause()
		# Skeletal clips are continuous, so "a frame" is a 30fps time slice.
		var ap: AnimationPlayer = caster.model3d._anim
		var len3: float = caster.model3d.animation_length(_current_anim)
		if len3 <= 0.0:
			return
		var t: float = fposmod(ap.current_animation_position + delta / 30.0, len3)
		ap.seek(t, true)
		return
	if not (caster and caster.animated_sprite and caster.animated_sprite.sprite_frames):
		return
	if not _paused:
		_toggle_pause()
	var sf: SpriteFrames = caster.animated_sprite.sprite_frames
	var a: String = caster.animated_sprite.animation
	if a == "" or not sf.has_animation(a):
		return
	var n: int = sf.get_frame_count(a)
	caster.animated_sprite.frame = (caster.animated_sprite.frame + delta + n) % n

func _on_play_all_pressed() -> void:
	if _play_all_running:
		_play_all_running = false
		play_all_btn.text = "▶ Play All"
		status_label.text = "Play All stopped."
		return
	_run_play_all()

func _run_play_all() -> void:
	_play_all_running = true
	play_all_btn.text = "■ Stop"
	for anim in _anim_names:
		if not _play_all_running:
			return
		if anim_buttons[anim].disabled:
			continue
		_play_anim(anim)
		await get_tree().create_timer(PLAY_ALL_DELAY).timeout
	_play_all_running = false
	play_all_btn.text = "▶ Play All"
	status_label.text = "Play All finished."

# ── Ability casting ──────────────────────────────────────────────────────────
func _sides() -> Array:
	var opponents: Array = mgr.enemy_units if caster in mgr.player_units else mgr.player_units
	var allies: Array = mgr.player_units if caster in mgr.player_units else mgr.enemy_units
	return [opponents, allies]

func _snapshot_hp() -> Dictionary:
	var before: Dictionary = {}
	for u in [caster, dummy_ally, dummy_enemy]:
		if u and is_instance_valid(u):
			before[u] = u.current_hp
	return before

# Some abilities resolve over seconds (Tide chains, Tidal Wave, storms), so an
# instant diff would under-report them — wait a beat, then measure. See the
# _process() note about why those sequences advance at all in this tool.
func _report_result(what: String, before: Dictionary) -> void:
	await get_tree().create_timer(0.35).timeout
	if not is_instance_valid(caster):
		return
	var deltas: Array = []
	for u in [caster, dummy_ally, dummy_enemy]:
		if u and is_instance_valid(u) and before.has(u):
			var d: int = u.current_hp - before[u]
			if d != 0:
				var who := "caster" if u == caster else ("ally-dummy" if u == dummy_ally else "enemy-dummy")
				deltas.append("%s %s%d HP" % [who, ("+" if d > 0 else ""), d])
	# _nemi_pending_ult_casts matters here: Tidal Wave first queues a reposition
	# WALK and only becomes a real wave once that finishes, so omitting it made
	# the ultimate report a misleading "no HP change" during its wind-up.
	var pending: int = mgr._nemi_tide_seqs.size() + mgr._nemi_tidal_waves.size() \
		+ mgr._nemi_pending_ult_casts.size() + mgr.storms.size()
	var tail := ""
	if not deltas.is_empty():
		tail = " — " + ", ".join(deltas)
	elif pending > 0:
		tail = " — %d timed effect(s) still playing out..." % pending
	else:
		tail = " — no HP change (buff/summon/no-target, or check Output panel)"
	status_label.text = "%s%s" % [what, tail]

func _on_ability_pressed() -> void:
	if not caster or not mgr:
		return
	var s := _sides()
	var before := _snapshot_hp()
	mgr._use_skill(caster, s[0], s[1])
	_report_result("Active: %s" % _name_or(caster.skill_name, "(unnamed)"), before)

func _on_ultimate_pressed() -> void:
	if not caster or not mgr:
		return
	var s := _sides()
	var before := _snapshot_hp()
	# Mirror what _tick_unit does the moment the charge bar fills, so the
	# ultimate looks exactly like it does in a real fight (cast particles + the
	# charge actually being spent), not just the raw damage call.
	mgr._use_ultimate(caster, s[0], s[1])
	if caster.has_method("cast_particles"):
		caster.cast_particles()
	caster.ultimate_ready = false
	caster.ultimate_charge = 0
	_report_result("★ Ultimate: %s" % _name_or(caster.ultimate_name, "(unnamed)"), before)

func _on_passive_pressed() -> void:
	if not caster or not mgr:
		return
	var s := _sides()
	var before := _snapshot_hp()
	mgr._tick_passive(caster, s[0], s[1], 1.0)
	_report_result("Passive tick (1.0s): %s" % _name_or(caster.passive_name, "(unnamed)"), before)

func _run_full_kit() -> void:
	if not caster or not mgr:
		return
	_on_passive_pressed()
	await get_tree().create_timer(1.1).timeout
	if not is_instance_valid(caster): return
	_on_ability_pressed()
	await get_tree().create_timer(1.4).timeout
	if not is_instance_valid(caster): return
	_on_ultimate_pressed()

func _name_or(s: String, fallback: String) -> String:
	return s if s != "" else fallback

# ── Input ────────────────────────────────────────────────────────────────────
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if search_box.has_focus():
		return  # never hijack typing
	var k: InputEventKey = event
	match k.keycode:
		KEY_LEFT:      _cycle_unit(-1)
		KEY_RIGHT:     _cycle_unit(1)
		KEY_SPACE:     _on_ability_pressed()
		KEY_U:         _on_ultimate_pressed()
		KEY_T:         _on_passive_pressed()
		KEY_R:         _reset_all()
		KEY_L:         _replay_current()
		KEY_P:         _toggle_pause()
		KEY_H:         panel.visible = not panel.visible
		KEY_B:         _cycle_background()
		KEY_F12:       _save_screenshot()
		KEY_BRACKETLEFT:  _step_frame(-1)
		KEY_BRACKETRIGHT: _step_frame(1)
		_:
			if k.keycode >= KEY_1 and k.keycode <= KEY_9:
				var i: int = k.keycode - KEY_1
				if i < _anim_names.size() and not anim_buttons[_anim_names[i]].disabled:
					_play_anim(_anim_names[i])

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Only zoom when the cursor is over the stage, so scrolling the panel
		# (or a dropdown list) doesn't yank the camera around underneath it.
		if panel.visible and event.position.x >= panel.position.x:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_slider.value = clamp(zoom_slider.value + 0.2, zoom_slider.min_value, zoom_slider.max_value)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_slider.value = clamp(zoom_slider.value - 0.2, zoom_slider.min_value, zoom_slider.max_value)
