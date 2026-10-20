extends Node2D
class_name TempestSnakeBody

# Render-only sections. Their occupied cells, HP and status owner are the
# head's UnitBase; these nodes never enter either combat roster.
const ROOT := "res://assets/3d pipeline/enemy/tempest_conduit/"
const FILES := ["tempest_body_1_v004.glb", "tempest_body_2_v004.glb", "tempest_body_3_v004.glb", "tempest_body_4_v004.glb", "tempest_tail_v004.glb"]
var serpent: VisualUnit
var parts: Array[Model3DSprite] = []
var bases: Array[Vector2] = []
var t := 0.0
var dying := false
var hit_flashes: Dictionary = {}

func setup(unit: VisualUnit) -> void:
	serpent = unit
	z_as_relative = false
	z_index = 2
	serpent.segment_length_changed.connect(sync_length)
	sync_length()
	serpent.died.connect(_die)

func _add_part(file: String, tail: bool) -> void:
	var part := Model3DSprite.new()
	part.name = "Tail" if tail else "Body"
	part.toon = false
	part.z_as_relative = false
	add_child(part)
	if part.setup(ROOT+file, 48.0 if tail else 64.0):
		var index: int = parts.size() if tail else maxi(0, parts.size()-1)
		parts.insert(index,part)
		bases.insert(index,part.get_sprite().scale)
		part.play("idle")
	else: part.queue_free()

func sync_length() -> void:
	# The initial models load before grid placement establishes the six cells.
	var wanted: int = maxi(6, serpent.segment_cells.size())-1
	if parts.is_empty():
		_add_part(FILES[-1],true)
	while parts.size() < wanted:
		var count_before := parts.size()
		_add_part(FILES[(parts.size()-1) % 4],false)
		if parts.size() == count_before: break
	while parts.size() > wanted:
		var index := parts.size()-2
		parts[index].queue_free(); parts.remove_at(index); bases.remove_at(index)
	hit_flashes.clear()

func _process(dt: float) -> void:
	if not is_instance_valid(serpent): return
	var grid := serpent.combat_grid
	visible = is_instance_valid(grid) and serpent.segment_cells.size() >= 6
	if not visible: return
	var pace: float = serpent.battle_manager.time_scale if serpent.battle_manager else 1.0
	if serpent.battle_manager and serpent.battle_manager.paused: pace = 0.0
	t += dt*pace
	for i in parts.size():
		var part := parts[i]
		var index := i+1
		part.global_position = serpent.section_canvas_position(index)
		var row := float(serpent.segment_cells[index].y)
		if serpent.is_moving and serpent.segment_previous_cells.size() == serpent.segment_cells.size():
			row = lerpf(float(serpent.segment_previous_cells[index].y), row, serpent.move_progress)
		var depth := BoardPerspective.row_scale(row, grid.grid_height)
		var sprite := part.get_sprite()
		sprite.scale = bases[i]*depth
		# Match the head's cell foot line; hover above it by a few pixels.
		sprite.position = part.bottom_anchor_offset(BoardPerspective.foot_offset(roundi(row), grid.grid_height, grid.cell_size, 1)) + Vector2(0, -8 + sin(t*3.2-i*0.7)*3)
		part.z_index = 3+roundi(row)
		part.set_paused(pace == 0)
		var flash: float = maxf(0.0, float(hit_flashes.get(index, 0.0))-dt*pace)
		hit_flashes[index] = flash
		part.modulate = Color(1,1,1).lerp(Color(2.3,2.3,2.3), flash/0.16)
		part.modulate.a = serpent._death_alpha
		if not dying and not part.is_oneshot_playing():
			part.play("walk" if serpent.is_moving else "idle")
		if serpent.is_moving and not dying and not part.is_oneshot_playing():
			part.face_direction(serpent.section_canvas_position(index-1)-part.global_position)
	queue_redraw()

func fire_tail(target: UnitBase) -> void:
	if parts.is_empty() or dying: return
	var tail := parts[-1]
	tail.face_direction(target.combat_aim_position(tail.global_position)-tail.global_position)
	tail.play_oneshot("attack", "walk")

func flash_section(index: int) -> void:
	hit_flashes[index] = 0.16

func _die() -> void:
	dying = true
	for part in parts: part.play_oneshot("death", "")

func _draw() -> void:
	if not visible or not is_instance_valid(serpent): return
	for i in serpent.segment_cells.size()-1:
		var a := to_local(serpent.section_canvas_position(i)) + Vector2(0, 5)
		var b := to_local(serpent.section_canvas_position(i+1)) + Vector2(0, 5)
		var line := PackedVector2Array([a])
		var normal := (b-a).orthogonal().normalized()
		for j in range(1, 7):
			var f := float(j)/7
			line.append(a.lerp(b, f) + normal*sin(t*18+i*2+j*2.7)*4*sin(f*PI))
		line.append(b)
		draw_polyline(line, Color(0.1,0.7,1,0.22*serpent._death_alpha), 7, true)
		draw_polyline(line, Color(0.4,0.95,1,0.85*serpent._death_alpha), 2, true)
