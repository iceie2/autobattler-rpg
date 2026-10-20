extends Node2D
class_name EmberVFX

# Molten glass: straight gold arrow shafts, lozenge facets, radial shard fans.
# No smoke curls, nature threads or jagged lightning paths.
enum Mode { IMPACT, MARK, CAST, CINDER, WILDFIRE }
const GROUND_Z := 1
const GOLD := Color(1.0, 0.72, 0.22)
const GLASS := Color(1.0, 0.29, 0.07)
const CORE := Color(1.0, 0.96, 0.76)
const DARK := Color(0.16, 0.045, 0.035)
var mode: Mode = Mode.IMPACT
var elapsed := 0.0
var lifetime := 0.6
var radius := 70.0
var bm: Node = null
var target: Node2D = null

static func has_ember_burn(u) -> bool:
	if not is_instance_valid(u) or u.burn_time <= 0.0: return false
	var part: Array = u.burn_parts.get(int(UnitBase.UnitClass.EMBER), [])
	if not part.is_empty() and float(part[1]) > 0.0: return true
	return is_instance_valid(u.burn_source) and u.burn_source.unit_class == UnitBase.UnitClass.EMBER and u.burn_flavor == "fire"

func setup(kind: Mode, at: Vector2, manager: Node, life: float, size: float) -> void:
	mode = kind
	bm = manager
	global_position = at
	lifetime = life
	radius = size
	z_index = GROUND_Z if kind in [Mode.MARK, Mode.CINDER, Mode.WILDFIRE] else 20
	queue_redraw()

func _clock() -> float:
	if not is_instance_valid(bm): return 1.0
	return 0.0 if bm.paused else bm.time_scale

func _process(delta: float) -> void:
	if mode == Mode.MARK:
		if not is_instance_valid(target) or target.current_hp <= 0 or not has_ember_burn(target):
			queue_free()
			return
		global_position = target.global_position + Vector2(0, target.ground_offset() if target.has_method("ground_offset") else 0.0)
	var dt := delta * _clock()
	if dt <= 0.0: return
	elapsed += dt
	if elapsed >= lifetime:
		queue_free()
		return
	# Burn facets are static; only transform follows the marked unit.
	if mode != Mode.MARK: queue_redraw()

static func draw_arrow(canvas: Node2D, direction: Vector2) -> void:
	var d := direction if direction != Vector2.ZERO else Vector2.RIGHT
	var n := d.orthogonal()
	canvas.draw_line(-d * 52.0, d * 12.0, DARK, 7.0)
	canvas.draw_line(-d * 44.0, d * 12.0, GOLD, 3.0)
	canvas.draw_line(-d * 24.0, d * 14.0, CORE, 1.2)
	var facet := PackedVector2Array([d * 23.0, d * 8.0 + n * 6.0, d * 2.0, d * 8.0 - n * 6.0])
	canvas.draw_colored_polygon(facet, GLASS)
	canvas.draw_line(d * 8.0 - n * 6.0, d * 23.0, CORE, 1.5)
	canvas.draw_line(-d * 23.0, -d * 32.0 + n * 5.0, GOLD, 2.0)
	canvas.draw_line(-d * 23.0, -d * 32.0 - n * 5.0, GOLD, 2.0)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if mode != Mode.MARK else 0.0
	var alpha := 1.0 - t
	var count := 12 if mode == Mode.WILDFIRE else (9 if mode == Mode.CINDER else 5)
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in count:
		var angle := TAU * float(i) / count - PI * 0.5
		var d := Vector2.from_angle(angle)
		var spread := radius * (0.16 + t * 0.84)
		var pos := d * spread
		if mode in [Mode.MARK, Mode.CINDER, Mode.WILDFIRE]: pos.y *= 0.42
		if mode == Mode.MARK: pos = Vector2((i - 2) * 9, -6 - abs(i - 2) * 3)
		if mode == Mode.CAST: pos = Vector2((i - 2) * 8, -20 - t * radius)
		var size := (13.0 if mode == Mode.WILDFIRE else 8.0) * (1.0 - t * 0.65)
		var side := d.orthogonal()
		# Two batched triangle passes: dark silhouette then glass inset.
		for layer in 2:
			var k := 1.25 if layer == 0 else 0.85
			var base := points.size()
			for q in [pos + d * size * k, pos + side * size * 0.38 * k, pos - d * size * k, pos - side * size * 0.38 * k]:
				points.append(q)
				var c := DARK if layer == 0 else (GOLD if i % 2 == 0 else GLASS)
				c.a = alpha
				colors.append(c)
			indices.append_array(PackedInt32Array([base, base+1, base+2, base, base+2, base+3]))
		if mode != Mode.MARK:
			var end := pos - d * size
			draw_line(end - d * (12.0 + t * 18.0), end, Color(GOLD, alpha * 0.8), 2.0)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)
