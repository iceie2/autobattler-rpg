extends CanvasLayer
class_name ClassBrowser

# ── Class data ────────────────────────────────────────────────────────────────
# Sprite folder names matching assets/sprites/generated/{folder}/0/single.png
# idle south standing frame = Rect2(0, 640, 64, 64) in every LPC sheet
const CLASS_SPRITE_FOLDERS := [
	"warrior", "archer", "monk", "thief", "black_mage", "white_mage", "red_mage",
	"warrior", "monk", "archer"   # bloodhound, bouncer, headhunter (placeholder sprites)
]
const IDLE_SOUTH_FRAME := Rect2(0, 640, 64, 64)

const CLASSES := [
	{
		"name": "Warrior",
		"color": Color(0.9, 0.5, 0.1),
		"role": "Front-line melee brawler",
		"hp": 1200, "mana": 300,
		"str": 15, "dex": 8, "int": 5, "res": 12,
		"atk": 19, "mag": 9, "def": 15,
		"move": 2, "range": 1,
		"skill": "Whirlwind",
		"skill_color": Color(1.0, 0.7, 0.1),
		"skill_desc": (
			"Spins in place and slashes all enemies standing in adjacent cells, " +
			"dealing 120% attack damage to each. Great for clearing clusters.\n\n" +
			"Cooldown: 3 turns  ·  Range: 1  ·  Damage: 120% ATK"
		),
		"lore": "A seasoned fighter who charges into the heart of battle, trading blows " +
			"until only one side is left standing. Tough, reliable, relentless."
	},
	{
		"name": "Ranger",
		"color": Color(0.2, 0.85, 0.3),
		"role": "Long-range physical attacker",
		"hp": 900, "mana": 400,
		"str": 10, "dex": 16, "int": 8, "res": 7,
		"atk": 18, "mag": 11, "def": 9,
		"move": 3, "range": 4,
		"skill": "Arrow Rain",
		"skill_color": Color(0.3, 1.0, 0.4),
		"skill_desc": (
			"Fires a volley into the air that rains down arrows over a wide zone, " +
			"dealing 80% attack damage to all enemies within range.\n\n" +
			"Cooldown: 4 turns  ·  Range: 5  ·  Damage: 80% ATK (multi-target)"
		),
		"lore": "Swift and precise, the Ranger stays at the back line and peppers enemies " +
			"from a safe distance. Excels at thinning out clusters before they reach your front line."
	},
	{
		"name": "Monk",
		"color": Color(0.95, 0.9, 0.3),
		"role": "Balanced fighter with healing",
		"hp": 1000, "mana": 500,
		"str": 12, "dex": 12, "int": 10, "res": 10,
		"atk": 18, "mag": 14, "def": 12,
		"move": 3, "range": 1,
		"skill": "Chi Burst",
		"skill_color": Color(1.0, 0.95, 0.4),
		"skill_desc": (
			"Releases an expanding wave of chi energy that deals 100% attack damage " +
			"to nearby enemies and restores HP equal to 30% of damage dealt to nearby allies.\n\n" +
			"Cooldown: 4 turns  ·  Range: 2  ·  Damage: 100% ATK + ally heal"
		),
		"lore": "Disciplined monks channel inner energy into both offense and support, " +
			"keeping nearby allies healthy while punishing enemies who get too close."
	},
	{
		"name": "Thief",
		"color": Color(0.6, 0.2, 0.9),
		"role": "High-damage single-target assassin",
		"hp": 800, "mana": 350,
		"str": 8, "dex": 18, "int": 10, "res": 6,
		"atk": 17, "mag": 12, "def": 7,
		"move": 5, "range": 1,
		"skill": "Shadow Strike",
		"skill_color": Color(0.8, 0.3, 1.0),
		"skill_desc": (
			"Vanishes into shadow and reappears behind the target, dealing a devastating " +
			"critical hit for 250% attack damage. The element of surprise strikes hard.\n\n" +
			"Cooldown: 5 turns  ·  Range: 2  ·  Damage: 250% ATK (single target)"
		),
		"lore": "Glass cannon with the fastest movement in the roster. Best used to " +
			"eliminate high-priority enemy casters before they can turn the tide."
	},
	{
		"name": "Black Mage",
		"color": Color(0.85, 0.15, 0.15),
		"role": "High-damage area mage",
		"hp": 700, "mana": 800,
		"str": 5, "dex": 7, "int": 18, "res": 8,
		"atk": 8, "mag": 20, "def": 9,
		"move": 2, "range": 5,
		"skill": "Inferno",
		"skill_color": Color(1.0, 0.4, 0.0),
		"skill_desc": (
			"Calls down a column of fire that erupts outward, dealing 200% magic power " +
			"as fire damage across a wide radius. Devastating against bunched enemies.\n\n" +
			"Cooldown: 4 turns  ·  Range: 5  ·  Damage: 200% MAG (fire AOE)"
		),
		"lore": "Fragile but terrifyingly powerful. Keep Black Mages in the back row where " +
			"they can rain destruction safely. One Inferno can shift the entire battle."
	},
	{
		"name": "White Mage",
		"color": Color(0.92, 0.92, 1.0),
		"role": "Full-team healer and support",
		"hp": 750, "mana": 750,
		"str": 6, "dex": 8, "int": 16, "res": 12,
		"atk": 10, "mag": 18, "def": 14,
		"move": 2, "range": 5,
		"skill": "Holy Light",
		"skill_color": Color(1.0, 0.95, 0.6),
		"skill_desc": (
			"Channels divine light to restore HP to every allied unit on the field. " +
			"The heal amount scales with magic power. Turns the tide of long battles.\n\n" +
			"Cooldown: 5 turns  ·  Range: All allies  ·  Effect: Global heal"
		),
		"lore": "A White Mage in your roster dramatically extends your team's staying power. " +
			"Pair with tanks and front-liners who can benefit most from repeated heals."
	},
	{
		"name": "Red Mage",
		"color": Color(0.95, 0.2, 0.6),
		"role": "Versatile hybrid caster",
		"hp": 850, "mana": 650,
		"str": 10, "dex": 10, "int": 14, "res": 10,
		"atk": 15, "mag": 17, "def": 12,
		"move": 2, "range": 5,
		"skill": "Chaos Bolt",
		"skill_color": Color(1.0, 0.3, 0.8),
		"skill_desc": (
			"Fires an unstable bolt that randomly shifts element on each cast, dealing " +
			"180% magic damage. The unpredictable element can exploit enemy weaknesses.\n\n" +
			"Cooldown: 3 turns  ·  Range: 4  ·  Damage: 180% MAG (random element)"
		),
		"lore": "Jack of all trades with rapid skill cooldowns. Red Mages work well in any " +
			"composition and are especially effective when element matchups are in their favor."
	},
	{
		"name": "Bloodhound", "color": Color(0.75, 0.2, 0.15),
		"role": "Tanky melee fighter that rages at low HP",
		"hp": 1100, "mana": 400,
		"str": 14, "dex": 12, "int": 6, "res": 14,
		"atk": 20, "mag": 10, "def": 16,
		"move": 3, "range": 1,
		"skill": "Blood Frenzy  /  Bite  /  Pounce",
		"skill_color": Color(0.9, 0.3, 0.2),
		"skill_desc": (
			"[PASSIVE] Blood Frenzy — below 45% HP: locked onto highest-threat enemy, " +
			"+2 move speed and faster attacks.\n\n" +
			"[ACTIVE – 50 MP] Bite — lunges at the nearest enemy dealing 130% ATK " +
			"and healing Bloodhound for 30% of damage dealt.\n\n" +
			"[ULTIMATE – 300 charge] Pounce — leaps to the enemy that has dealt the " +
			"most damage to Bloodhound, stunning them for 1 turn and dealing 250% ATK."
		),
		"lore": "A relentless predator that grows more dangerous the more it bleeds. " +
			"Place Bloodhound at the front where it absorbs punishment and builds rage."
	},
	{
		"name": "Bouncer", "color": Color(0.3, 0.5, 0.9),
		"role": "Magic-damage tank that pulls enemies in",
		"hp": 1300, "mana": 600,
		"str": 8, "dex": 6, "int": 16, "res": 16,
		"atk": 12, "mag": 20, "def": 18,
		"move": 2, "range": 2,
		"skill": "Presence  /  Slam  /  Gravity Drop",
		"skill_color": Color(0.4, 0.65, 1.0),
		"skill_desc": (
			"[PASSIVE] Presence — each unit within 2 tiles grants +5% magic damage " +
			"(max +30%). The more crowded the battlefield, the harder Bouncer hits.\n\n" +
			"[ACTIVE – 80 MP] Slam — leaps to the nearest enemy, stunning them for " +
			"1 turn and dealing 100% MAG damage.\n\n" +
			"[ULTIMATE – 350 charge] Gravity Drop — bounces and creates a shockwave " +
			"that pulls all units in a 4×4 area to the nearest open cell beside Bouncer, " +
			"dealing 150% MAG to every enemy caught."
		),
		"lore": "A wall of muscle and magic that drags the entire battlefield to itself. " +
			"Use Bouncer to disrupt enemy formations and protect your back line."
	},
	{
		"name": "Headhunter", "color": Color(0.4, 0.85, 0.6),
		"role": "Long-range glass cannon sniper",
		"hp": 600, "mana": 350,
		"str": 14, "dex": 20, "int": 12, "res": 5,
		"atk": 24, "mag": 16, "def": 6,
		"move": 3, "range": 6,
		"skill": "Seventh Shot  /  Rapid Fire  /  Snipe",
		"skill_color": Color(0.5, 1.0, 0.65),
		"skill_desc": (
			"[PASSIVE] Seventh Shot — every 7th auto-attack is a guaranteed critical " +
			"hit dealing 3× damage. Keep the Headhunter alive and the crits roll in.\n\n" +
			"[ACTIVE – 60 MP] Rapid Fire — for the next 3 turns, attacks hit 1 extra " +
			"target and gain +2 attack range. Perfect for hitting the back line.\n\n" +
			"[ULTIMATE – 400 charge] Snipe — locks onto the farthest enemy and fires " +
			"a high-velocity shot for 400% ATK. The bullet can be intercepted by any " +
			"enemy standing in the line of fire."
		),
		"lore": "Devastating from afar but paper-thin up close. Keep the Headhunter " +
			"in the back row and pair with tanks who can soak incoming fire."
	},
]

var _idx := 0
signal closed()

# UI refs
var _panel: Panel
var _portrait_bg: ColorRect
var _portrait: TextureRect
var _class_idx_lbl: Label
var _class_name_lbl: Label
var _role_lbl: Label
var _lore_lbl: Label
var _stat_lbl: Label
var _skill_name_lbl: Label
var _skill_desc_lbl: Label

func _ready() -> void:
	_build_ui()

func open(start_idx: int = 0) -> void:
	_idx = clamp(start_idx, 0, CLASSES.size() - 1)
	visible = true
	_refresh()

func _build_ui() -> void:
	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	# Main panel — wider to give room for lore + skill desc
	_panel = Panel.new()
	_panel.size = Vector2(720, 600)
	_panel.add_theme_stylebox_override("panel",
		_flat(Color(0.09, 0.09, 0.15, 0.98), Color(0.4, 0.4, 0.65), 2, 10))
	overlay.add_child(_panel)

	# Title
	_lbl(_panel, "CLASS COMPENDIUM", 20, Color(0.8, 0.8, 1.0),
		Vector2(0, 14), Vector2(720, 36), true)

	# Close button
	var close_btn := _btn("✕", Rect2(678, 8, 34, 34))
	close_btn.pressed.connect(_close)
	_panel.add_child(close_btn)

	var _sep_top := _hsep(_panel, 58, 720)

	# ── Portrait area (left column) ───────────────────────────────────────────
	# Dark tinted background behind the sprite
	_portrait_bg = ColorRect.new()
	_portrait_bg.position = Vector2(24, 72)
	_portrait_bg.size = Vector2(140, 140)
	_portrait_bg.color = Color(0.08, 0.08, 0.14)
	_panel.add_child(_portrait_bg)

	# Actual LPC sprite (zoomed in, centered)
	_portrait = TextureRect.new()
	_portrait.position = Vector2(24, 72)
	_portrait.size = Vector2(140, 140)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_panel.add_child(_portrait)

	# Class number badge on portrait
	_class_idx_lbl = _lbl(_panel, "", 13, Color(0, 0, 0, 0.85),
		Vector2(24, 202), Vector2(140, 22), true)

	# ── Name, role, lore (right of portrait) ─────────────────────────────────
	_class_name_lbl = _lbl(_panel, "", 30, Color(1.0, 0.9, 0.6),
		Vector2(180, 68), Vector2(480, 44))
	_role_lbl = _lbl(_panel, "", 14, Color(0.65, 0.75, 0.95),
		Vector2(180, 112), Vector2(480, 24))
	_lore_lbl = _lbl(_panel, "", 12, Color(0.65, 0.65, 0.75),
		Vector2(180, 140), Vector2(480, 68))
	_lore_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ── Stats row ─────────────────────────────────────────────────────────────
	var _sep_stat := _hsep(_panel, 228, 720)
	_lbl(_panel, "BASE STATS", 12, Color(0.55, 0.6, 0.85),
		Vector2(24, 238), Vector2(200, 20))
	_stat_lbl = _lbl(_panel, "", 13, Color(0.82, 0.82, 0.95),
		Vector2(24, 260), Vector2(672, 80))

	# ── Skill section ─────────────────────────────────────────────────────────
	var _sep_skill := _hsep(_panel, 352, 720)
	_lbl(_panel, "CLASS SKILL", 12, Color(0.55, 0.6, 0.85),
		Vector2(24, 362), Vector2(200, 20))
	_skill_name_lbl = _lbl(_panel, "", 20, Color(1.0, 0.85, 0.3),
		Vector2(24, 384), Vector2(672, 30))
	_skill_desc_lbl = _lbl(_panel, "", 12, Color(0.72, 0.72, 0.82),
		Vector2(24, 418), Vector2(672, 130))
	_skill_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ── Navigation ────────────────────────────────────────────────────────────
	var _sep_nav := _hsep(_panel, 560, 720)
	var prev_btn := _btn("◀  Previous", Rect2(24, 570, 160, 22))
	prev_btn.pressed.connect(_prev)
	_panel.add_child(prev_btn)
	var next_btn := _btn("Next  ▶", Rect2(536, 570, 160, 22))
	next_btn.pressed.connect(_next)
	_panel.add_child(next_btn)

	visible = false
	_center_panel()

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1800, 1080)
	_panel.position = (vp - _panel.size) / 2.0

func _refresh() -> void:
	var c: Dictionary = CLASSES[_idx]

	# Load the idle-south standing frame from the LPC sprite sheet
	_portrait_bg.color = c["color"].darkened(0.55)
	var folder: String = CLASS_SPRITE_FOLDERS[_idx]
	var sheet_path := "res://assets/sprites/generated/%s/0/single.png" % folder
	var sheet := load(sheet_path) as Texture2D
	if sheet:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = IDLE_SOUTH_FRAME
		_portrait.texture = atlas
	else:
		_portrait.texture = null

	_class_idx_lbl.text  = "%s  (%d / %d)" % [c["name"], _idx + 1, CLASSES.size()]
	_class_name_lbl.text = c["name"]
	_class_name_lbl.add_theme_color_override("font_color", c["color"])
	_role_lbl.text  = c["role"]
	_lore_lbl.text  = c["lore"]

	_stat_lbl.text = (
		"HP: %-6d  Mana: %-6d  Move: %-3d  Range: %d\n" +
		"STR: %-5d  DEX: %-5d  INT: %-5d  RES: %-5d\n" +
		"Attack: %-4d  Magic: %-4d  Defense: %d"
	) % [c["hp"], c["mana"], c["move"], c["range"],
		 c["str"], c["dex"], c["int"], c["res"],
		 c["atk"], c["mag"], c["def"]]

	_skill_name_lbl.text = c["skill"]
	_skill_name_lbl.add_theme_color_override("font_color", c["skill_color"])
	_skill_desc_lbl.text = c["skill_desc"]

func _prev() -> void:
	_idx = (_idx - 1 + CLASSES.size()) % CLASSES.size()
	_refresh()

func _next() -> void:
	_idx = (_idx + 1) % CLASSES.size()
	_refresh()

func _close() -> void:
	visible = false
	closed.emit()

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _panel.get_rect().has_point(_panel.get_local_mouse_position()):
			_close()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("ui_cancel"): _close()
	if event.is_action_pressed("ui_left"):   _prev()
	if event.is_action_pressed("ui_right"):  _next()

# ── Helpers ───────────────────────────────────────────────────────────────────
func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text; b.position = rect.position; b.size = rect.size
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	b.add_theme_stylebox_override("normal",  _flat(Color(0.18, 0.18, 0.28), Color(0.45, 0.45, 0.6), 1, 4))
	b.add_theme_stylebox_override("hover",   _flat(Color(0.26, 0.26, 0.38), Color(0.6, 0.6, 0.8),  1, 4))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.12, 0.12, 0.22), Color(0.3, 0.3, 0.5),  1, 4))
	return b

func _hsep(parent: Node, y: float, width: float) -> HSeparator:
	var s := HSeparator.new()
	s.position = Vector2(0, y); s.size = Vector2(width, 4)
	parent.add_child(s)
	return s

func _flat(bg: Color, border: Color = Color.TRANSPARENT,
		bw: int = 0, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.border_width_left = bw; s.border_width_right = bw
	s.border_width_top = bw;  s.border_width_bottom = bw
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	return s
