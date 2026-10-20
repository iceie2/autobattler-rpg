extends Node2D
class_name StaticWireSparks
## The live wire's electricity, drawn in 2D over Static's 3D body (2026-10-01).
##
## The voltage forks are ~3 px at 115 px tall, so geometry alone never read as
## "this cable is live". This adds Static's own lightning language (StaticVFX:
## jagged forks, YELLOW/CYAN core over a VIOLET backing, the white-hot packet
## from his tripwire) on the simulated rope from Model3DCable:
##   - idle: a steady spark at the fork tips, an occasional crackle, and every
##     few seconds a packet that races down the cable into the plug
##   - attack / skill / ult: constant crackle plus arcs jumping off the cable
##
## NOT additive like CrossHaloGlow: additive yellow/cyan disappears on the pale
## air board, and the violet backing pass has to be able to darken.
## Sizes are in board pixels at the shipped 115 px height and scale with the
## model's render_height, so close-up review renders keep proportions. (The
## first cut scaled by the projected plug->tip span; that collapses whenever the
## fist turns toward camera and halved every spark.)

const YELLOW := StaticVFX.YELLOW
const CYAN := StaticVFX.CYAN
const VIOLET := StaticVFX.VIOLET
const WHITE_HOT := StaticVFX.WHITE_HOT
const REF_H := 115.0           ## VisualUnit.MODEL_RENDER_H
const CAST_CLIPS := ["attack", "skill", "ult"]

var unit: Node2D = null
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _crackles: Array = []      ## [{"pts": PackedVector2Array (tip-relative, unscaled), "age", "life"}]
var _arcs: Array = []          ## [{"i": cable index, "pts": PackedVector2Array, "age", "life"}]
var _packets: Array = []       ## [{"age", "life"}]
var _next_crackle := 0.6
var _next_packet := 1.5
var _next_arc := 0.0

func setup(p_unit: Node2D) -> void:
	unit = p_unit
	z_index = 3                 # over his own sprite (+1), still under the next row
	_rng.randomize()

func _model():
	return unit.get("model3d") if unit and is_instance_valid(unit) else null

func _casting() -> bool:
	var m = _model()
	return m != null and str(m.get("_current")) in CAST_CLIPS

func _process(delta: float) -> void:
	if not (unit and is_instance_valid(unit)):
		queue_free()
		return
	visible = not bool(unit.get("_is_dying"))
	if not visible:
		return
	_t += delta
	var cast := _casting()
	_next_crackle -= delta
	if _next_crackle <= 0.0:
		_crackles.append({"pts": _fork(), "age": 0.0, "life": _rng.randf_range(0.07, 0.12)})
		_next_crackle = _rng.randf_range(0.04, 0.09) if cast else _rng.randf_range(0.5, 1.4)
	_next_packet -= delta
	if _next_packet <= 0.0:
		_packets.append({"age": 0.0, "life": 0.22 if cast else 0.38})
		_next_packet = _rng.randf_range(0.25, 0.4) if cast else _rng.randf_range(2.2, 3.6)
	_next_arc -= delta
	if cast and _next_arc <= 0.0:
		_arcs.append({"i": _rng.randi_range(2, 11), "pts": _fork(2, 7.0, 12.0, true),
			"age": 0.0, "life": _rng.randf_range(0.05, 0.09)})
		_next_arc = _rng.randf_range(0.03, 0.07)
	for list in [_crackles, _arcs, _packets]:
		for e in list:
			e["age"] += delta
		for i in range(list.size() - 1, -1, -1):
			if list[i]["age"] >= list[i]["life"]:
				if list == _packets:
					_crackles.append({"pts": _fork(), "age": 0.0, "life": 0.10})
				list.remove_at(i)
	queue_redraw()

## A jagged fork in tip-relative, unscaled px: `n` segments of `lo..hi` total
## length, aimed up/out unless `any_dir`. Pre-rolled so it holds still while it lives.
func _fork(n: int = 3, lo: float = 9.0, hi: float = 16.0, any_dir: bool = false) -> PackedVector2Array:
	var ang := _rng.randf_range(0.0, TAU) if any_dir else _rng.randf_range(-PI * 0.95, -PI * 0.05)
	var dir := Vector2(cos(ang), sin(ang))
	var side := dir.orthogonal()
	var total := _rng.randf_range(lo, hi)
	var pts := PackedVector2Array([Vector2.ZERO])
	for k in range(1, n + 1):
		var f := float(k) / n
		var jag := 0.0 if k == n else _rng.randf_range(-0.45, 0.45) * total / n * 1.6
		pts.append(dir * total * f + side * jag)
	return pts

func _bolt(origin: Vector2, pts: PackedVector2Array, k: float, a: float) -> void:
	var p := PackedVector2Array()
	for q in pts:
		p.append(origin + q * k)
	draw_polyline(p, Color(VIOLET, 0.5 * a), 4.5 * k)
	draw_polyline(p, Color(CYAN, 0.95 * a), 2.5 * k)
	draw_polyline(p, Color(WHITE_HOT, a), 1.2 * k)

func _draw() -> void:
	var m = _model()
	if m == null or not m.has_cable():
		return
	var tip: Vector2 = to_local(m.cable_tip_canvas())
	var cable: PackedVector2Array = m.cable_canvas_points()
	if cable.size() < 2:
		return
	var k := float(m.render_height) / REF_H
	# Always-on: the forks are live. A small hot core with a flickering halo.
	var flick := 0.75 + 0.25 * sin(_t * 23.0) * sin(_t * 7.0)
	var lvl := 1.6 if _casting() else 1.0
	draw_circle(tip, 5.0 * k * lvl, Color(VIOLET, 0.30 * flick))
	draw_circle(tip, 3.2 * k * lvl, Color(CYAN, 0.65 * flick))
	draw_circle(tip, 1.6 * k * lvl, Color(WHITE_HOT, 0.95))
	for c in _crackles:
		_bolt(tip, c["pts"], k, 1.0 - c["age"] / c["life"] * 0.5)
	for e in _arcs:
		var idx: int = mini(e["i"], cable.size() - 1)
		_bolt(to_local(cable[idx]), e["pts"], k, 1.0)
	# Packets run belt -> plug, i.e. along the cable from its far end to index 0.
	for pk in _packets:
		var f: float = clampf(pk["age"] / pk["life"], 0.0, 1.0)
		var pos_f := (1.0 - f) * (cable.size() - 1)
		var i0 := int(floor(pos_f))
		var i1 := mini(i0 + 1, cable.size() - 1)
		var p := to_local(cable[i0].lerp(cable[i1], pos_f - i0))
		draw_circle(p, 4.5 * k, Color(VIOLET, 0.40))
		draw_circle(p, 3.0 * k, Color(CYAN, 0.9))
		draw_circle(p, 1.6 * k, WHITE_HOT)
