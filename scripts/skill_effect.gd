extends Node2D
class_name SkillEffect

enum Type {
	WHIRLWIND,    # Warrior  — spinning blades
	ARROW_RAIN,   # Ranger   — falling arrow shards
	CHI_BURST,    # Monk     — expanding ring pulse
	SHADOW_STRIKE,# Thief    — shadow flash
	INFERNO,      # BlackMage — fire explosion
	HOLY_LIGHT,   # WhiteMage — rising light beams
	CHAOS_BOLT,   # RedMage  — swirling sparks
}

var effect_type: Type = Type.WHIRLWIND
var lifetime: float = 0.8
var elapsed: float = 0.0
var radius: float = 48.0      # base visual radius

# Random seeds for particles so each effect looks slightly different
var _seeds: Array = []

func setup(type: Type, world_pos: Vector2, r: float = 48.0) -> void:
	effect_type = type
	radius = r
	global_position = world_pos
	_seeds.clear()
	for i in range(20):
		_seeds.append(randf())
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var t := elapsed / lifetime          # 0 → 1 normalised time
	var inv := 1.0 - t                   # fade-out factor

	match effect_type:
		Type.WHIRLWIND:     _draw_whirlwind(t, inv)
		Type.ARROW_RAIN:    _draw_arrow_rain(t, inv)
		Type.CHI_BURST:     _draw_chi_burst(t, inv)
		Type.SHADOW_STRIKE: _draw_shadow_strike(t, inv)
		Type.INFERNO:       _draw_inferno(t, inv)
		Type.HOLY_LIGHT:    _draw_holy_light(t, inv)
		Type.CHAOS_BOLT:    _draw_chaos_bolt(t, inv)


# ── Warrior: orange spinning sword arcs ──────────────────────────────────────
func _draw_whirlwind(t: float, inv: float) -> void:
	var num_arcs := 5
	var rot_speed := t * TAU * 2.5
	for i in range(num_arcs):
		var base_angle := rot_speed + i * (TAU / num_arcs)
		var r := radius * (0.3 + 0.7 * t)
		var a := Color(1.0, 0.55, 0.05, inv * 0.85)
		var arc_len := PI * 0.45
		draw_arc(Vector2.ZERO, r, base_angle, base_angle + arc_len, 20, a, 4.0 * inv)
		# spark at tip
		var tip := Vector2(cos(base_angle + arc_len), sin(base_angle + arc_len)) * r
		draw_circle(tip, 4.0 * inv, Color(1.0, 0.85, 0.4, inv))
	# Central flash
	draw_circle(Vector2.ZERO, 12 * inv, Color(1.0, 0.8, 0.3, inv * 0.7))


# ── Ranger: bright green arrow shards raining down ───────────────────────────
func _draw_arrow_rain(t: float, inv: float) -> void:
	var count := 8
	for i in range(count):
		var seed_x := _seeds[i] * 2.0 - 1.0
		var seed_t := _seeds[i + count % _seeds.size()]
		var phase   := fmod(t * 1.5 + seed_t, 1.0)
		var x       := seed_x * radius
		var y       := -radius + phase * radius * 2.0
		var alpha   := inv * (1.0 - phase * 0.5)
		var col     := Color(0.2, 1.0, 0.35, alpha)
		# Arrow body
		draw_line(Vector2(x, y - 14), Vector2(x, y + 8), col, 2.5)
		# Arrowhead
		draw_line(Vector2(x, y - 14), Vector2(x - 5, y - 6), col, 2.0)
		draw_line(Vector2(x, y - 14), Vector2(x + 5, y - 6), col, 2.0)
	# Impact ring at bottom
	if t > 0.4:
		var ring_r := (t - 0.4) / 0.6 * radius
		draw_arc(Vector2(0, radius * 0.4), ring_r, 0, TAU, 24,
			Color(0.3, 1.0, 0.4, inv * 0.6), 2.0)


# ── Monk: expanding concentric rings (gold/white healing pulse) ───────────────
func _draw_chi_burst(t: float, inv: float) -> void:
	for i in range(3):
		var phase := fmod(t + i * 0.33, 1.0)
		var r     := phase * radius * 1.4
		var alpha := (1.0 - phase) * inv
		draw_arc(Vector2.ZERO, r, 0, TAU, 32,
			Color(1.0, 0.95, 0.5, alpha), 3.0 * (1.0 - phase))
	# Inner glow
	draw_circle(Vector2.ZERO, 18 * inv, Color(1.0, 1.0, 0.7, inv * 0.6))
	# 8 radiating spokes
	for i in range(8):
		var angle := i * (TAU / 8.0) + t * PI
		var spoke_end := Vector2(cos(angle), sin(angle)) * radius * t
		draw_line(Vector2.ZERO, spoke_end,
			Color(1.0, 0.9, 0.4, inv * 0.5), 1.5)


# ── Thief: dark purple shadow burst then afterimage slashes ───────────────────
func _draw_shadow_strike(t: float, inv: float) -> void:
	# Dark shadow blast early
	if t < 0.4:
		var early := t / 0.4
		draw_circle(Vector2.ZERO, radius * early, Color(0.3, 0.0, 0.5, (1.0 - early) * 0.7))
	# Slash streaks
	var num := 6
	for i in range(num):
		var angle := _seeds[i] * TAU
		var phase  := fmod(t * 2.0 + _seeds[i], 1.0)
		var r1     := phase * radius * 0.3
		var r2     := phase * radius
		var alpha  := (1.0 - phase) * inv
		var col    := Color(0.7, 0.1, 1.0, alpha)
		draw_line(
			Vector2(cos(angle), sin(angle)) * r1,
			Vector2(cos(angle), sin(angle)) * r2,
			col, 3.0 * (1.0 - phase)
		)
	# Brief white impact flash
	if t < 0.15:
		draw_circle(Vector2.ZERO, 20 * (1.0 - t / 0.15), Color(1.0, 1.0, 1.0, 0.8))


# ── Black Mage: fiery explosion ───────────────────────────────────────────────
func _draw_inferno(t: float, inv: float) -> void:
	# Growing fireball core
	var core_r := radius * min(t * 2.0, 1.0)
	draw_circle(Vector2.ZERO, core_r, Color(1.0, 0.4, 0.0, inv * 0.6))
	draw_circle(Vector2.ZERO, core_r * 0.6, Color(1.0, 0.8, 0.2, inv * 0.8))
	# Flame tendrils
	var count := 12
	for i in range(count):
		var base_a := _seeds[i] * TAU
		var wobble  := sin(t * 15.0 + i) * 0.3
		var angle   := base_a + wobble
		var dist    := (0.5 + _seeds[i] * 0.5) * radius * min(t * 2.5, 1.0)
		var tip     := Vector2(cos(angle), sin(angle)) * dist
		var col     := Color(1.0, 0.3 + _seeds[i] * 0.4, 0.0, inv * 0.7)
		draw_line(Vector2.ZERO, tip, col, 3.0 * inv)
		draw_circle(tip, 4.0 * inv, Color(1.0, 0.7, 0.1, inv * 0.5))
	# Shockwave ring
	if t > 0.2:
		var ring_t := (t - 0.2) / 0.8
		draw_arc(Vector2.ZERO, ring_t * radius * 1.5, 0, TAU, 32,
			Color(0.9, 0.3, 0.0, (1.0 - ring_t) * inv), 2.0)


# ── White Mage: golden light beams rising upward ─────────────────────────────
func _draw_holy_light(t: float, inv: float) -> void:
	# Ground halo
	var halo_r := radius * (0.4 + t * 0.6)
	draw_arc(Vector2.ZERO, halo_r, 0, TAU, 32, Color(1.0, 0.9, 0.5, inv * 0.4), 2.0)
	# Rising beams
	var count := 7
	for i in range(count):
		var angle  := _seeds[i] * TAU
		var height := radius * 1.8 * t
		var offset := Vector2(cos(angle), sin(angle)) * (radius * 0.25 * _seeds[i])
		var base   := offset
		var tip    := offset + Vector2(0, -height)
		var alpha  := inv * 0.7 * (1.0 - abs(sin(angle)) * 0.3)
		var col    := Color(1.0, 0.95, 0.6, alpha)
		draw_line(base, tip, col, (2.0 + _seeds[i] * 2.0) * inv)
	# Star burst
	var star_r := 16.0 * sin(t * PI)
	for i in range(8):
		var a := i * (TAU / 8.0)
		draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * star_r,
			Color(1.0, 1.0, 0.8, inv * 0.9), 2.0)
	draw_circle(Vector2.ZERO, 8.0 * inv, Color(1.0, 1.0, 1.0, inv))


# ── Red Mage: chaotic rainbow sparks ─────────────────────────────────────────
func _draw_chaos_bolt(t: float, inv: float) -> void:
	# Swirling outer ring
	var ring_r := radius * (0.6 + sin(t * TAU * 3.0) * 0.1)
	draw_arc(Vector2.ZERO, ring_r, t * TAU * 4.0, t * TAU * 4.0 + TAU * 0.7, 24,
		Color(0.9, 0.2, 0.8, inv * 0.7), 3.0)
	# Multi-color sparks flying outward
	var count := 14
	for i in range(count):
		var angle  := _seeds[i] * TAU + t * TAU * (1.5 + _seeds[i])
		var dist   := _seeds[i] * radius * t
		var pos    := Vector2(cos(angle), sin(angle)) * dist
		var hue    := fmod(_seeds[i] + t * 0.5, 1.0)
		var col    := Color.from_hsv(hue, 0.9, 1.0, inv * 0.85)
		draw_circle(pos, (3.0 + _seeds[i] * 4.0) * inv, col)
		# Spark trail
		var trail  := pos * 0.6
		draw_line(trail, pos, Color(col.r, col.g, col.b, inv * 0.4), 1.5)
	# Central swirl
	draw_circle(Vector2.ZERO, 14.0 * inv, Color(0.8, 0.3, 1.0, inv * 0.8))
