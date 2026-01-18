extends UnitBase
class_name VisualUnit

# Visual settings
@export var shape_size: float = 40.0
@export var outline_width: float = 3.0


# Drag and drop
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO
var can_be_dragged: bool = true
var mouse_down_position: Vector2 = Vector2.ZERO
var drag_threshold: float = 5.0  # Minimum distance to start drag

# Components
var health_bar: HealthBar
var animated_sprite: LPCAnimatedSprite2D
var element_glow: Sprite2D
var sprite_frame_size: Vector2 = Vector2.ZERO

# Animation state
var current_direction: String = "South"
var last_move_direction: Vector2 = Vector2.ZERO

# Inspector overrides removed — shape-only visuals in effect
var fill_color: Color = Color(1,1,1,1)



func _ready():
	super._ready()

	# Create element glow (behind sprite)
	element_glow = Sprite2D.new()
	element_glow.texture = create_glow_texture()
	element_glow.modulate = get_element_color()
	element_glow.modulate.a = 0.4  # Semi-transparent
	element_glow.scale = Vector2(1.5, 1.5)
	if element_glow and not element_glow.get_parent():
		add_child(element_glow)
	
		# Get the LPCAnimatedSprite2D child node if this is a warrior
	# Get the LPCAnimatedSprite2D child node if this is a warrior
	if unit_class == UnitBase.UnitClass.WARRIOR:
		animated_sprite = get_node_or_null("LPCAnimatedSprite2D")
		if animated_sprite:
			print("Found LPCAnimatedSprite2D!")
			animated_sprite.visible = true  # Make sure it's visible
			animated_sprite.modulate = Color.WHITE  # Make sure it's not transparent
			animated_sprite.z_index = 1  # Put it above other elements
			# Pick a good animation and start playback
			_select_and_play_animation_for_sprite(animated_sprite)
		else:
			print("WARNING: LPCAnimatedSprite2D not found on warrior!")
	else:
		# For non-warriors, use shape visuals
		fill_color = get_element_color()
		if element_glow:
			element_glow.modulate = fill_color
			element_glow.modulate.a = 0.4

	# Use simple shape visuals for all units (no sprites)
	fill_color = get_element_color()
	# ensure element glow reflects current element
	if element_glow:
		element_glow.modulate = fill_color
		element_glow.modulate.a = 0.4
		if not element_glow.get_parent():
			add_child(element_glow)

	# Create health bar (on top)
	health_bar = HealthBar.new()
	if health_bar and not health_bar.get_parent():
		add_child(health_bar)
		health_bar.update_health(current_hp, max_hp)

	# Connect to health changes
	health_changed.connect(_on_health_changed)

	update_visuals()
	# No sprite scanning in shape-only mode


func _on_health_changed(current: int, maximum: int) -> void:
	if health_bar:
		health_bar.update_health(current, maximum)



func create_glow_texture() -> Texture2D:
	# Create a simple circular glow
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center = Vector2(32, 32)
	var radius = 28.0
	
	for y in range(64):
		for x in range(64):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)
			var alpha = clamp(1.0 - (dist / radius), 0.0, 1.0)
			# Smooth falloff
			alpha = pow(alpha, 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	
	return ImageTexture.create_from_image(img)

# Select a multi-frame animation when possible and start playback safely
func _select_and_play_animation_for_sprite(sprite: AnimatedSprite2D) -> void:
	if not sprite:
		return
	var frames = sprite.sprite_frames
	if not frames:
		return

	# Prefer idle animation based on ownership if it exists and has >1 frames
	var prefer = "idle_south" if is_player_unit else "idle_north"
	var chosen = ""
	if frames.has_animation(prefer) and frames.get_frame_count(prefer) > 1:
		chosen = prefer
	else:
		# Find the first animation with more than one frame
		var anims = frames.get_animation_names()
		for a in anims:
			if frames.get_frame_count(a) > 1:
				chosen = a
				break
		# Fallback to any available animation
		if chosen == "" and anims.size() > 0:
			chosen = anims[0]

	if chosen == "":
		# No animations available
		print("LPCAnimatedSprite2D: no animations found to play")
		return

	# Apply chosen animation and reset progress
	sprite.animation = chosen
	sprite.frame_progress = 0.0
	# Start playback via play() (correct for Godot 4)
	sprite.play(chosen)

	# Set speed_scale using SpriteFrames animation speed if available, use sensible default otherwise
	var speed = 1.0
	if frames.has_method("get_animation_speed"):
		var s = frames.get_animation_speed(chosen)
		if typeof(s) in [TYPE_INT, TYPE_FLOAT] and s > 0:
			speed = s
	sprite.speed_scale = speed

func _process(delta: float) -> void:
	update_animation()

func update_animation() -> void:
	if unit_class != UnitBase.UnitClass.WARRIOR or not animated_sprite:
		return

	var frames = animated_sprite.sprite_frames
	var curr = animated_sprite.animation
	# If current animation is non-looping and not finished, don't interrupt
	if frames and curr != "" and not frames.get_animation_loop(curr):
		var fc = frames.get_frame_count(curr)
		if animated_sprite.frame < fc - 1:
			return

	# Determine facing direction from last_move_direction if available
	var direction_suffix = "south"
	if last_move_direction.length() > 0:
		if abs(last_move_direction.x) > abs(last_move_direction.y):
			direction_suffix = "east" if last_move_direction.x > 0 else "west"
		else:
			direction_suffix = "south" if last_move_direction.y > 0 else "north"

	# If moving, prefer walk/run animation
	if is_moving and move_target_pos != move_start_pos:
		var prefix = "run" if movement_speed >= 3 else "walk"
		var anim_name = prefix + "_" + direction_suffix
		# Fallbacks if missing
		if frames:
			if not frames.has_animation(anim_name):
				if frames.has_animation("walk_" + direction_suffix):
					anim_name = "walk_" + direction_suffix
				elif frames.has_animation("run_" + direction_suffix):
					anim_name = "run_" + direction_suffix
				elif frames.has_animation("walk_south"):
					anim_name = "walk_south"
		# Switch only when changed
		if anim_name != curr:
			animated_sprite.play(anim_name)
		return

	# Otherwise idle
	var prefer_idle = "idle_south" if is_player_unit else "idle_north"
	var idle_name = prefer_idle
	if frames and not frames.has_animation(prefer_idle):
		var anims = frames.get_animation_names()
		if anims.size() > 0:
			idle_name = anims[0]
	if idle_name != curr:
		animated_sprite.play(idle_name)



func _draw():
	# Shape-only visuals
	# Warriors use LPCAnimatedSprite2D, skip shape rendering
	if unit_class == UnitBase.UnitClass.WARRIOR:
		return
	var color = fill_color if fill_color else get_element_color()
	var outline_color = Color.WHITE

	match unit_class:
		UnitBase.UnitClass.RANGER:
			draw_triangle(color, outline_color)
		UnitBase.UnitClass.MONK:
			draw_circle_shape(color, outline_color)
		UnitBase.UnitClass.THIEF:
			draw_diamond(color, outline_color)
		UnitBase.UnitClass.BLACK_MAGE:
			draw_pentagon(color, outline_color)
		UnitBase.UnitClass.WHITE_MAGE:
			draw_hexagon(color, outline_color)
		UnitBase.UnitClass.RED_MAGE:
			draw_star(color, outline_color)
		_:
			draw_square(color, outline_color)

func draw_square(color: Color, outline_color: Color) -> void:
	var half_size = shape_size / 2
	var points = PackedVector2Array([
		Vector2(-half_size, -half_size),
		Vector2(half_size, -half_size),
		Vector2(half_size, half_size),
		Vector2(-half_size, half_size)
	])
	
	# Fill
	draw_colored_polygon(points, color)
	# Outline
	for i in range(points.size()):
		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]
		draw_line(p1, p2, outline_color, outline_width)

func draw_triangle(color: Color, outline_color: Color) -> void:
	var height = shape_size
	var half_base = shape_size * 0.866  # sqrt(3)/2 for equilateral
	
	var points = PackedVector2Array([
		Vector2(0, -height * 0.577),  # Top
		Vector2(half_base, height * 0.433),  # Bottom right
		Vector2(-half_base, height * 0.433)  # Bottom left
	])
	
	draw_colored_polygon(points, color)
	for i in range(points.size()):
		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]
		draw_line(p1, p2, outline_color, outline_width)

func draw_circle_shape(color: Color, outline_color: Color) -> void:
	var radius = shape_size / 2
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, outline_color, outline_width)

func draw_diamond(color: Color, outline_color: Color) -> void:
	var half_size = shape_size / 2
	var points = PackedVector2Array([
		Vector2(0, -half_size),  # Top
		Vector2(half_size, 0),   # Right
		Vector2(0, half_size),   # Bottom
		Vector2(-half_size, 0)   # Left
	])
	
	draw_colored_polygon(points, color)
	for i in range(points.size()):
		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]
		draw_line(p1, p2, outline_color, outline_width)

func draw_pentagon(color: Color, outline_color: Color) -> void:
	var points = create_regular_polygon(5, shape_size / 2)
	draw_colored_polygon(points, color)
	for i in range(points.size()):
		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]
		draw_line(p1, p2, outline_color, outline_width)

func draw_hexagon(color: Color, outline_color: Color) -> void:
	var points = create_regular_polygon(6, shape_size / 2)
	draw_colored_polygon(points, color)
	for i in range(points.size()):
		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]
		draw_line(p1, p2, outline_color, outline_width)

func draw_star(color: Color, outline_color: Color) -> void:
	var outer_radius = shape_size / 2
	var inner_radius = outer_radius * 0.4
	var points = PackedVector2Array()
	
	for i in range(5):
		# Outer point
		var angle_out = -PI / 2 + (i * TAU / 5)
		points.append(Vector2(cos(angle_out), sin(angle_out)) * outer_radius)
		
		# Inner point
		var angle_in = -PI / 2 + (i * TAU / 5) + (TAU / 10)
		points.append(Vector2(cos(angle_in), sin(angle_in)) * inner_radius)
	
	draw_colored_polygon(points, color)
	for i in range(points.size()):
		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]
		draw_line(p1, p2, outline_color, outline_width)

func create_regular_polygon(sides: int, radius: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(sides):
		var angle = -PI / 2 + (i * TAU / sides)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func update_visuals() -> void:
	# Shape-only visuals: update fill color and glow
	fill_color = get_element_color()
	if element_glow:
		element_glow.modulate = fill_color
		element_glow.modulate.a = 0.4
	queue_redraw()

func change_element(new_element: Element) -> void:
	super.change_element(new_element)
	update_visuals()

func _input(event: InputEvent) -> void:
	if not can_be_dragged:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var anim_name = "IdleSouth" # Always use South-facing animation
			var mouse_pos = get_global_mouse_position()
			var distance = global_position.distance_to(mouse_pos)
			if distance <= shape_size:
				mouse_down_position = mouse_pos
				drag_offset = global_position - mouse_pos
				original_position = position
				# Don't set handled yet - allow click to pass through
		else:
			if is_dragging:
				is_dragging = false
				try_place_at_mouse_position()
				get_viewport().set_input_as_handled()
			# If not dragging, let the click through for unit details
	
	if event is InputEventMouseMotion:
		# Only start dragging if mouse moved beyond threshold
		if not is_dragging and mouse_down_position != Vector2.ZERO:
			var mouse_pos = get_global_mouse_position()
			if mouse_down_position.distance_to(mouse_pos) > drag_threshold:
				is_dragging = true
				get_viewport().set_input_as_handled()
		
		if is_dragging:
			var mouse_pos = get_global_mouse_position()
			global_position = mouse_pos + drag_offset
			get_viewport().set_input_as_handled()
		
		# Reset mouse down when button released
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			mouse_down_position = Vector2.ZERO

func try_place_at_mouse_position() -> void:
	if not battle_manager:
		return
	
	var battle_grid = battle_manager.battle_grid
	if not battle_grid:
		return
	
	var mouse_pos = get_global_mouse_position()
	var new_grid_pos = battle_grid.world_to_grid(mouse_pos)
	
	# Check if position is valid for this unit's team
	if not is_valid_placement_position(new_grid_pos, battle_grid):
		# Snap back to original position
		position = original_position
		return
	
	# Remove from old position
	battle_grid.remove_unit(grid_position)
	
	# Try to place at new position
	if battle_grid.place_unit(self, new_grid_pos):
		grid_position = new_grid_pos
		position = battle_grid.grid_to_world(new_grid_pos)
	else:
		# Position occupied, snap back
		battle_grid.place_unit(self, grid_position)  # Re-place at old position
		global_position = original_position

func is_valid_placement_position(pos: Vector2i, battle_grid) -> bool:
	if not battle_grid.is_valid_position(pos):
		return false
	
	# Player units can only be in rows 10-13 (bottom 4 rows)
	if is_player_unit:
		return pos.y >= 10 and pos.y < 14
	# Enemy units can only be in rows 0-3 (top 4 rows)
	else:
		return pos.y >= 0 and pos.y < 4
