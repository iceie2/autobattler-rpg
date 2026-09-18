extends Node2D
class_name GoblinVFX

# Goblin-specific procedural language: dirty ochre dust, rusty red steel and a
# sharp yellow-white focal glint. It deliberately avoids the purple thief burst
# Shank previously borrowed from SHADOW_STRIKE.
enum Mode { PACK_AURA, AUTO_IMPACT, SHANK_WINDUP, SHANK_IMPACT }

const OCHRE := Color(0.72, 0.48, 0.12)
const RUST := Color(0.68, 0.18, 0.07)
const GOBLIN_GREEN := Color(0.48, 0.62, 0.16)
const CORE := Color(1.0, 0.94, 0.52)

var mode := Mode.SHANK_IMPACT
var elapsed := 0.0
var lifetime := 0.45
var target: Node2D = null
var strength := 0.0

func setup_point(kind: Mode, world_pos: Vector2, life: float) -> void:
	mode = kind
	global_position = world_pos
	lifetime = life
	z_index = 4
	queue_redraw()

func setup_pack(owner: Node2D) -> void:
	mode = Mode.PACK_AURA
	target = owner
	lifetime = INF
	z_index = -1
	queue_redraw()

func set_pack_strength(value: float) -> void:
	strength = clampf(value, 0.0, 1.0)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if mode == Mode.PACK_AURA:
		if not (target and is_instance_valid(target)) or target.current_hp <= 0:
			queue_free()
			return
		global_position = target.global_position
	else:
		if elapsed >= lifetime:
			queue_free()
			return
	queue_redraw()

func _draw() -> void:
	match mode:
		Mode.PACK_AURA: _draw_pack()
		Mode.AUTO_IMPACT: _draw_auto_impact()
		Mode.SHANK_WINDUP: _draw_windup()
		Mode.SHANK_IMPACT: _draw_impact()

func _draw_pack() -> void:
	if strength <= 0.01:
		return
	var pulse := 0.82 + sin(elapsed * (5.0 + strength * 4.0)) * 0.18
	var a := strength * pulse
	# Broad, quiet ground presence; readable without obscuring the sprite/bar.
	draw_circle(Vector2(0, 35), 30.0, Color(OCHRE.r, OCHRE.g, OCHRE.b, 0.055 * a))
	draw_arc(Vector2(0, 35), 25.0, PI * 0.08, PI * 0.92, 22,
		Color(GOBLIN_GREEN.r, GOBLIN_GREEN.g, GOBLIN_GREEN.b, 0.42 * a), 3.0)
	# Two eye-like focal sparks make the state identifiable as pack courage.
	for x in [-7.0, 7.0]:
		draw_circle(Vector2(x, 20), 4.5, Color(OCHRE.r, OCHRE.g, OCHRE.b, 0.20 * a))
		draw_circle(Vector2(x, 20), 1.8, Color(CORE.r, CORE.g, CORE.b, 0.88 * a))

func _fade() -> float:
	return clampf(1.0 - elapsed / maxf(lifetime, 0.001), 0.0, 1.0)

func _draw_windup() -> void:
	var t := clampf(elapsed / maxf(lifetime, 0.001), 0.0, 1.0)
	var gather := sin(t * PI)
	draw_circle(Vector2.ZERO, 30.0 * gather, Color(OCHRE.r, OCHRE.g, OCHRE.b, 0.10 * gather))
	draw_arc(Vector2.ZERO, 20.0 + 10.0 * t, -2.7, -0.45, 20,
		Color(RUST.r, RUST.g, RUST.b, 0.78 * gather), 5.0)
	draw_circle(Vector2(18, -12), 3.5 * gather, Color(CORE.r, CORE.g, CORE.b, gather))

func _draw_auto_impact() -> void:
	var t := clampf(elapsed / maxf(lifetime, 0.001), 0.0, 1.0)
	var a := _fade()
	draw_circle(Vector2.ZERO, 16.0 + 12.0 * t, Color(OCHRE.r, OCHRE.g, OCHRE.b, 0.10 * a))
	draw_line(Vector2(-15, 12), Vector2(18, -15), Color(RUST.r, RUST.g, RUST.b, 0.72 * a), 5.0)
	draw_line(Vector2(-15, 12), Vector2(18, -15), Color(CORE.r, CORE.g, CORE.b, a), 1.4)
	draw_circle(Vector2.ZERO, 5.0 * a, Color(CORE.r, CORE.g, CORE.b, 0.75 * a))

func _draw_impact() -> void:
	var t := clampf(elapsed / maxf(lifetime, 0.001), 0.0, 1.0)
	var a := _fade()
	# Broad low-alpha dust, readable rust blade body, bright contact core.
	draw_circle(Vector2.ZERO, 28.0 * (0.5 + t), Color(OCHRE.r, OCHRE.g, OCHRE.b, 0.13 * a))
	var p0 := Vector2(-24, 20).lerp(Vector2(-12, 10), t)
	var p1 := Vector2(25, -22).lerp(Vector2(35, -30), t)
	draw_line(p0, p1, Color(RUST.r, RUST.g, RUST.b, 0.34 * a), 11.0)
	draw_line(p0, p1, Color(0.95, 0.52, 0.16, 0.92 * a), 5.0)
	draw_line(p0, p1, Color(CORE.r, CORE.g, CORE.b, a), 1.8)
	if t < 0.35:
		var flash := 1.0 - t / 0.35
		draw_circle(Vector2.ZERO, 10.0 * flash, Color(CORE.r, CORE.g, CORE.b, 0.9 * flash))
	for i in range(5):
		var ang := -2.6 + float(i) * 0.42
		var tip := Vector2(cos(ang), sin(ang)) * (18.0 + 25.0 * t)
		draw_circle(tip, 2.5 * a, Color(OCHRE.r, OCHRE.g, OCHRE.b, 0.8 * a))
