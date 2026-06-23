extends UnitBase
class_name VisualUnit

@export var shape_size: float = 40.0
@export var outline_width: float = 3.0
var sprite_variant: int = -1  # set by factory; -1 = pick randomly in _ready

# Drag and drop
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO       # local coords saved on drag start
var original_global_pos: Vector2 = Vector2.ZERO    # global coords saved on drag start
var can_be_dragged: bool = true
var mouse_down_position: Vector2 = Vector2.ZERO
var drag_threshold: float = 5.0

# Components
var health_bar: HealthBar
var animated_sprite: LPCAnimatedSprite2D
var element_glow: Sprite2D

# Animation state
var last_move_direction: Vector2 = Vector2.ZERO
var fill_color: Color = Color(1, 1, 1, 1)


func get_class_sprite_folder() -> String:
	match unit_class:
		UnitBase.UnitClass.WARRIOR:    return "warrior"
		UnitBase.UnitClass.RANGER:     return "archer"
		UnitBase.UnitClass.MONK:       return "monk"
		UnitBase.UnitClass.THIEF:      return "thief"
		UnitBase.UnitClass.BLACK_MAGE: return "black_mage"
		UnitBase.UnitClass.WHITE_MAGE: return "white_mage"
		UnitBase.UnitClass.RED_MAGE:   return "red_mage"
		UnitBase.UnitClass.BLOODHOUND: return "warrior"
		UnitBase.UnitClass.BOUNCER:    return "monk"
		UnitBase.UnitClass.HEADHUNTER: return "archer"
		UnitBase.UnitClass.SHAUNA:    return "shauna"
		UnitBase.UnitClass.NEMI:      return "nemi"
		_: return ""

func get_enemy_sprite_override() -> String:
	# Enemy units can override the class-based folder via metadata
	if has_meta("sprite_folder"):
		return str(get_meta("sprite_folder"))
	return ""


func _ready():
	super._ready()

	if sprite_variant == -1:
		sprite_variant = randi() % 3

	element_glow = Sprite2D.new()
	element_glow.texture = _create_glow_texture()
	element_glow.scale = Vector2(1.5, 1.5)
	add_child(element_glow)

	_setup_lpc_sprite()

	fill_color = get_element_color()
	if element_glow:
		element_glow.modulate = fill_color
		element_glow.modulate.a = 0.4

	health_bar = HealthBar.new()
	add_child(health_bar)
	health_bar.update_hp(current_hp, max_hp)
	health_bar.update_mp(current_mana, max_mana)
	health_bar.update_ult(ultimate_charge, max(ultimate_charge_max, 1))

	health_changed.connect(_on_health_changed)
	mana_changed.connect(_on_mana_changed)
	update_visuals()


func _sprite_variant_count(folder: String) -> int:
	if folder == "hill_giant": return 1
	return 3

func _setup_lpc_sprite() -> void:
	var folder: String = get_meta("sprite_folder") if has_meta("sprite_folder") else get_class_sprite_folder()
	if folder == "":
		return
	var v: int = sprite_variant % _sprite_variant_count(folder)
	var sprite_path: String = "res://assets/sprites/generated/%s/%d" % [folder, v]

	var lpc = LPCAnimatedSprite2D.new()
	lpc.sprite_frames = SpriteFrames.new()
	lpc.z_index = 1
	lpc.spritesheets_path = sprite_path
	lpc.animation_data = LPCGeneratedAnimData.new()
	add_child(lpc)

	# walk_south is always present in the generated 6-animation sheets
	if lpc.sprite_frames and lpc.sprite_frames.has_animation("walk_south"):
		animated_sprite = lpc
		var idle := "idle_south" if is_player_unit else "idle_north"
		lpc.play(idle)
		# 2×2 units: scale 2× so the 64px frame fills the full 128px block
		if cell_size == 2:
			lpc.scale = Vector2(2.0, 2.0)
	else:
		lpc.queue_free()
		if cell_size == 2:
			shape_size = 80.0


func _on_health_changed(current: int, maximum: int) -> void:
	if health_bar:
		health_bar.update_hp(current, maximum)

func _on_mana_changed(current: int, maximum: int) -> void:
	if health_bar:
		health_bar.update_mp(current, maximum)


func _create_glow_texture() -> Texture2D:
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center = Vector2(32, 32)
	var radius = 28.0
	for y in range(64):
		for x in range(64):
			var dist = Vector2(x, y).distance_to(center)
			var alpha = pow(clamp(1.0 - dist / radius, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	_update_animation()
	if health_bar and ultimate_charge_max > 0:
		health_bar.update_ult(ultimate_charge, ultimate_charge_max)


func _update_animation() -> void:
	if not animated_sprite:
		return
	var frames = animated_sprite.sprite_frames
	if not frames:
		return

	var curr = animated_sprite.animation

	if curr != "" and not frames.get_animation_loop(curr):
		if animated_sprite.frame < frames.get_frame_count(curr) - 1:
			return

	var dir_suffix = "south"
	if last_move_direction.length() > 0:
		if abs(last_move_direction.x) > abs(last_move_direction.y):
			dir_suffix = "east" if last_move_direction.x > 0 else "west"
		else:
			dir_suffix = "south" if last_move_direction.y > 0 else "north"

	if is_moving and move_target_pos != move_start_pos:
		var want = "walk_" + dir_suffix
		if not frames.has_animation(want):
			want = "walk_south"
		if want != curr:
			animated_sprite.play(want)
		return

	var idle = "idle_south" if is_player_unit else "idle_north"
	if not frames.has_animation(idle):
		idle = "walk_south"
	if idle != curr:
		animated_sprite.play(idle)


func _draw():
	if animated_sprite:
		return
	var color = fill_color if fill_color else get_element_color()
	var outline = Color.WHITE
	match unit_class:
		UnitBase.UnitClass.RANGER:     _draw_triangle(color, outline)
		UnitBase.UnitClass.MONK:       _draw_circle(color, outline)
		UnitBase.UnitClass.THIEF:      _draw_diamond(color, outline)
		UnitBase.UnitClass.BLACK_MAGE: _draw_polygon(5, color, outline)
		UnitBase.UnitClass.WHITE_MAGE: _draw_polygon(6, color, outline)
		UnitBase.UnitClass.RED_MAGE:      _draw_star(color, outline)
		UnitBase.UnitClass.BLOODHOUND:    _draw_triangle(color, outline)
		UnitBase.UnitClass.BOUNCER:       _draw_circle(color, outline)
		UnitBase.UnitClass.HEADHUNTER:    _draw_diamond(color, outline)
		UnitBase.UnitClass.SHAUNA:        _draw_triangle(color, outline)
		UnitBase.UnitClass.NEMI:          _draw_hexagon(color, outline)
		_:                                _draw_square(color, outline)


func _draw_square(color: Color, outline: Color) -> void:
	var h = shape_size / 2
	var pts = PackedVector2Array([Vector2(-h,-h), Vector2(h,-h), Vector2(h,h), Vector2(-h,h)])
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_triangle(color: Color, outline: Color) -> void:
	var h = shape_size
	var hb = shape_size * 0.866
	var pts = PackedVector2Array([Vector2(0, -h*0.577), Vector2(hb, h*0.433), Vector2(-hb, h*0.433)])
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_circle(color: Color, outline: Color) -> void:
	var r = shape_size / 2
	draw_circle(Vector2.ZERO, r, color)
	draw_arc(Vector2.ZERO, r, 0, TAU, 32, outline, outline_width)

func _draw_diamond(color: Color, outline: Color) -> void:
	var h = shape_size / 2
	var pts = PackedVector2Array([Vector2(0,-h), Vector2(h,0), Vector2(0,h), Vector2(-h,0)])
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_polygon(sides: int, color: Color, outline: Color) -> void:
	var pts = PackedVector2Array()
	for i in sides:
		var a = -PI/2 + i * TAU / sides
		pts.append(Vector2(cos(a), sin(a)) * (shape_size / 2))
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_star(color: Color, outline: Color) -> void:
	var outer = shape_size / 2
	var inner = outer * 0.4
	var pts = PackedVector2Array()
	for i in 5:
		var ao = -PI/2 + i * TAU / 5
		pts.append(Vector2(cos(ao), sin(ao)) * outer)
		var ai = ao + TAU / 10
		pts.append(Vector2(cos(ai), sin(ai)) * inner)
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)


func update_visuals() -> void:
	fill_color = get_element_color()
	if element_glow:
		element_glow.modulate = fill_color
		element_glow.modulate.a = 0.4
	queue_redraw()

func change_element(new_element: Element) -> void:
	super.change_element(new_element)
	update_visuals()


# ── Drag & drop ────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not can_be_dragged:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mouse_pos = get_global_mouse_position()
			if global_position.distance_to(mouse_pos) <= shape_size:
				mouse_down_position = mouse_pos
				drag_offset = global_position - mouse_pos
				original_position = position
				original_global_pos = global_position
		else:
			if is_dragging:
				is_dragging = false
				_try_place_at_mouse()
				get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if not is_dragging and mouse_down_position != Vector2.ZERO:
			if mouse_down_position.distance_to(get_global_mouse_position()) > drag_threshold:
				is_dragging = true
				get_viewport().set_input_as_handled()
		if is_dragging:
			global_position = get_global_mouse_position() + drag_offset
			get_viewport().set_input_as_handled()
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			mouse_down_position = Vector2.ZERO


func _try_place_at_mouse() -> void:
	if not battle_manager:
		global_position = original_global_pos
		return
	var bg = battle_manager.battle_grid
	if not bg:
		global_position = original_global_pos
		return
	var new_pos = bg.world_to_grid(get_global_mouse_position())
	if not _is_valid_placement(new_pos, bg):
		global_position = original_global_pos
		return
	bg.remove_unit(grid_position)
	if bg.place_unit(self, new_pos):
		grid_position = new_pos
		position = bg.grid_to_world(new_pos)
	else:
		bg.place_unit(self, grid_position)
		global_position = original_global_pos


func _is_valid_placement(pos: Vector2i, bg) -> bool:
	if not bg.is_valid_position(pos):
		return false
	# Player zone = bottom 4 rows; enemy zone = top 4 rows
	var gh: int = bg.grid_height if bg else 20
	return (pos.y >= gh - 4 and pos.y < gh) if is_player_unit else (pos.y >= 0 and pos.y < 4)
