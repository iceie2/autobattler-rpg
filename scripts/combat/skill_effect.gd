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
	GRAVITY_DROP,  # Bouncer  — inward pull with warning ring
	ABSORBED,      # Small absorption burst (hit by Gravity Drop)
	OVERDRIVE,     # Shauna ultimate — spinning energy burst
	TIDE_WAVE,     # Nemi active — bouncing wave
	TIDAL_WAVE,    # Nemi ultimate — wide ocean wave
	# ── Roster expansion VFX ──
	LIGHTNING,     # Zolt / Static — jagged bolt burst
	BURN,          # Coal / Sear / Ember — flame licks
	NATURE,        # June / Spore — green spore/thorn burst
}

var effect_type: Type = Type.WHIRLWIND
var lifetime: float = 0.8
var elapsed: float = 0.0
var radius: float = 48.0      # base visual radius

# Random seeds for particles so each effect looks slightly different
var _seeds: Array[float] = []

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
		Type.GRAVITY_DROP:  _draw_gravity_drop(t, inv)
		Type.ABSORBED:      _draw_absorbed(t, inv)
		Type.OVERDRIVE:     _draw_overdrive(t, inv)
		Type.TIDE_WAVE:     _draw_tide_wave(t, inv)
		Type.TIDAL_WAVE:    _draw_tidal_wave(t, inv)
		Type.LIGHTNING:     _draw_lightning(t, inv)
		Type.BURN:          _draw_burn(t, inv)
		Type.NATURE:        _draw_nature(t, inv)


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
		var seed_x: float = _seeds[i] * 2.0 - 1.0
		var seed_t: float = _seeds[(i + count) % _seeds.size()]
		var phase: float  = fmod(t * 1.5 + seed_t, 1.0)
		var x: float      = seed_x * radius
		var y: float      = -radius + phase * radius * 2.0
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
		var angle: float = _seeds[i] * TAU
		var phase: float = fmod(t * 2.0 + _seeds[i], 1.0)
		var r1: float    = phase * radius * 0.3
		var r2: float    = phase * radius
		var alpha: float = (1.0 - phase) * inv
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
	var core_r: float = radius * min(t * 2.0, 1.0)
	draw_circle(Vector2.ZERO, core_r, Color(1.0, 0.4, 0.0, inv * 0.6))
	draw_circle(Vector2.ZERO, core_r * 0.6, Color(1.0, 0.8, 0.2, inv * 0.8))
	# Flame tendrils
	var count := 12
	for i in range(count):
		var base_a: float = _seeds[i] * TAU
		var wobble: float = sin(t * 15.0 + i) * 0.3
		var angle: float  = base_a + wobble
		var dist: float   = (0.5 + _seeds[i] * 0.5) * radius * min(t * 2.5, 1.0)
		var tip: Vector2  = Vector2(cos(angle), sin(angle)) * dist
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
		var angle: float   = _seeds[i] * TAU
		var height: float  = radius * 1.8 * t
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * (radius * 0.25 * _seeds[i])
		var base: Vector2  = offset
		var tip: Vector2   = offset + Vector2(0.0, -height)
		var alpha: float   = inv * 0.7 * (1.0 - abs(sin(angle)) * 0.3)
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
		var angle: float  = _seeds[i] * TAU + t * TAU * (1.5 + _seeds[i])
		var dist: float   = _seeds[i] * radius * t
		var pos: Vector2  = Vector2(cos(angle), sin(angle)) * dist
		var hue: float    = fmod(_seeds[i] + t * 0.5, 1.0)
		var col: Color    = Color.from_hsv(hue, 0.9, 1.0, inv * 0.85)
		draw_circle(pos, (3.0 + _seeds[i] * 4.0) * inv, col)
		# Spark trail
		var trail: Vector2 = pos * 0.6
		draw_line(trail, pos, Color(col.r, col.g, col.b, inv * 0.4), 1.5)
	# Central swirl
	draw_circle(Vector2.ZERO, 14.0 * inv, Color(0.8, 0.3, 1.0, inv * 0.8))


# ── Shauna Overdrive: spinning teal energy rings ──────────────────────────────
func _draw_overdrive(t: float, inv: float) -> void:
	var teal := Color(0.1, 0.9, 0.85)
	var gold := Color(1.0, 0.85, 0.2)
	# 3 spinning rings at different speeds
	for i in range(3):
		var rot: float = t * TAU * (2.0 + i * 0.7)
		var r: float = radius * (0.4 + i * 0.25)
		var a: float = inv * (0.7 - i * 0.15)
		draw_arc(Vector2.ZERO, r, rot, rot + TAU * 0.65, 24,
			Color(teal.r, teal.g, teal.b, a), 3.0 - i * 0.5)
	# Gold speed-line spokes
	for i in range(6):
		var ang: float = i * (TAU / 6.0) + t * TAU * 3.0
		var tip: Vector2 = Vector2(cos(ang), sin(ang)) * radius * 1.2
		draw_line(Vector2.ZERO, tip, Color(gold.r, gold.g, gold.b, inv * 0.6), 2.0)
	# Central bright core
	draw_circle(Vector2.ZERO, 10.0 * sin(t * TAU * 4.0 + 1.0), Color(1.0, 1.0, 0.9, inv * 0.8))


# ── Nemi Tide: bouncing blue-green wave ───────────────────────────────────────
func _draw_tide_wave(t: float, inv: float) -> void:
	var blue := Color(0.15, 0.6, 1.0)
	var teal := Color(0.1, 0.9, 0.75)
	# Expanding circles like a water drop
	for i in range(3):
		var phase: float = fmod(t * 2.0 + i * 0.33, 1.0)
		var r: float = phase * radius * 1.5
		draw_arc(Vector2.ZERO, r, 0, TAU, 28,
			Color(blue.r, blue.g, blue.b, (1.0 - phase) * inv * 0.75), 2.5)
	# Wavy horizontal lines
	for i in range(4):
		var y: float = -radius * 0.6 + i * (radius * 0.4)
		var pts := PackedVector2Array()
		for x_step in range(20):
			var x: float = -radius + x_step * (radius / 9.0)
			var wave_y: float = y + sin((x / radius) * PI * 3.0 + t * TAU * 2.0) * 6.0
			pts.append(Vector2(x, wave_y))
		for j in range(pts.size() - 1):
			draw_line(pts[j], pts[j+1], Color(teal.r, teal.g, teal.b, inv * 0.5), 1.5)
	draw_circle(Vector2.ZERO, 8.0 * inv, Color(0.5, 0.9, 1.0, inv * 0.7))


# ── Nemi Tidal Wave: wide ocean surge ────────────────────────────────────────
func _draw_tidal_wave(t: float, inv: float) -> void:
	var deep  := Color(0.05, 0.35, 0.85)
	var crest := Color(0.7,  0.92, 1.0)
	var foam  := Color(1.0,  1.0,  1.0)

	# Wave wall moving outward (3 stacked wave layers)
	for layer in range(3):
		var layer_t: float = fmod(t + layer * 0.2, 1.0)
		var wave_x: float = (-radius * 1.5) + layer_t * radius * 3.0
		var pts := PackedVector2Array()
		for step in range(32):
			var frac: float = step / 31.0
			var y: float = -radius + frac * radius * 2.0
			var curl: float = sin(frac * PI * 4.0 + t * TAU + layer) * (radius * 0.18)
			pts.append(Vector2(wave_x + curl, y))
		for j in range(pts.size() - 1):
			var alpha: float = inv * (0.6 - layer * 0.15)
			draw_line(pts[j], pts[j+1],
				Color(deep.r, deep.g, deep.b, alpha), 4.0 - layer)

	# Foam crest at leading edge
	var crest_x: float = (-radius * 1.5) + t * radius * 3.0
	for i in range(5):
		var cy: float = -radius * 0.8 + i * (radius * 0.4)
		draw_circle(Vector2(crest_x, cy), 5.0 * inv, Color(foam.r, foam.g, foam.b, inv * 0.85))

	# Wide horizontal glow behind crest
	draw_line(Vector2(crest_x - radius * 0.4, 0), Vector2(crest_x, 0),
		Color(crest.r, crest.g, crest.b, inv * 0.5), radius * 0.4)


# ── Bouncer Gravity Drop: three phases ───────────────────────────────────────
func _draw_gravity_drop(t: float, inv: float) -> void:
	var blue  := Color(0.3,  0.55, 1.0)
	var white := Color(0.8,  0.9,  1.0)
	var gold  := Color(1.0,  0.85, 0.2)

	# Phase 1 (0 → 0.35): expanding warning ring telegraphs the pull area
	if t < 0.35:
		var p: float = t / 0.35
		var r: float = radius * 2.2 * p
		# Outer ring
		draw_arc(Vector2.ZERO, r, 0, TAU, 40,
			Color(blue.r, blue.g, blue.b, p * 0.65), 3.0)
		# 8 radial tick marks at the perimeter
		for i in range(8):
			var ang: float = i * (TAU / 8.0)
			var outer: Vector2 = Vector2(cos(ang), sin(ang)) * r
			var inner: Vector2 = outer * 0.82
			draw_line(inner, outer, Color(gold.r, gold.g, gold.b, p * 0.9), 2.5)
		# Pulsing core
		draw_circle(Vector2.ZERO, 10.0 * p, Color(blue.r, blue.g, blue.b, p * 0.5))

	# Phase 2 (0.35 → 0.75): ring contracts with inward-pointing arrows — the pull
	elif t < 0.75:
		var p: float = (t - 0.35) / 0.40
		var r: float = radius * 2.2 * (1.0 - p * 0.85)
		# Contracting outer ring (thickens as it closes in)
		draw_arc(Vector2.ZERO, r, 0, TAU, 40,
			Color(blue.r, blue.g, blue.b, inv * 0.85), 4.0 + p * 3.0)

		# Inward arrows along the ring
		var num_arrows := 10
		for i in range(num_arrows):
			var ang: float = i * (TAU / num_arrows) + t * TAU * 0.5
			var tip: Vector2  = Vector2(cos(ang), sin(ang)) * (r * 0.15)
			var tail: Vector2 = Vector2(cos(ang), sin(ang)) * r
			draw_line(tail, tip, Color(white.r, white.g, white.b, inv * 0.75), 2.5)
			# Arrowhead at the inner end
			var perp: Vector2 = Vector2(-sin(ang), cos(ang))
			draw_line(tip + perp * 7, tip, Color(gold.r, gold.g, gold.b, inv), 2.0)
			draw_line(tip - perp * 7, tip, Color(gold.r, gold.g, gold.b, inv), 2.0)

		# Ripple rings moving inward
		for i in range(4):
			var ripple_t: float = fmod(p * 2.0 + i * 0.25, 1.0)
			var rr: float = r * (1.0 - ripple_t * 0.9)
			draw_arc(Vector2.ZERO, rr, 0, TAU, 28,
				Color(blue.r, blue.g, blue.b, (1.0 - ripple_t) * inv * 0.4), 1.5)

		# Growing central core
		draw_circle(Vector2.ZERO, 18.0 * p, Color(white.r, white.g, white.b, p * 0.7))

	# Phase 3 (0.75 → 1.0): central impact burst
	else:
		var p: float = (t - 0.75) / 0.25
		var core_r: float = p * radius * 0.7
		draw_circle(Vector2.ZERO, core_r, Color(white.r, white.g, white.b, inv * 0.9))
		draw_circle(Vector2.ZERO, core_r * 0.55, Color(1.0, 1.0, 1.0, inv))
		# Shockwave ring expanding outward
		draw_arc(Vector2.ZERO, p * radius * 1.4, 0, TAU, 32,
			Color(blue.r, blue.g, blue.b, (1.0 - p) * inv * 0.8), 3.5)
		# 6 energy spikes bursting out
		for i in range(6):
			var ang: float = i * (TAU / 6.0) + p * PI * 0.5
			var spike: Vector2 = Vector2(cos(ang), sin(ang)) * (p * radius)
			draw_line(Vector2.ZERO, spike,
				Color(gold.r, gold.g, gold.b, (1.0 - p) * inv * 0.9), 3.0)


# ── Lightning: jagged yellow-white bolts radiating out + flash ───────────────
func _draw_lightning(t: float, inv: float) -> void:
	var num_bolts := 6
	for i in range(num_bolts):
		var ang: float = _seeds[i] * TAU + i * (TAU / num_bolts)
		var segs := 5
		var prev := Vector2.ZERO
		var col := Color(1.0, 1.0, 0.4, inv * 0.9)
		for s in range(1, segs + 1):
			var frac: float = float(s) / segs
			var jitter: float = (_seeds[(i + s) % _seeds.size()] - 0.5) * radius * 0.35
			var perp := Vector2(-sin(ang), cos(ang)) * jitter
			var nxt := Vector2(cos(ang), sin(ang)) * (radius * frac) + perp
			draw_line(prev, nxt, col, 3.0 * inv)
			prev = nxt
	# Bright core flash early
	if t < 0.3:
		draw_circle(Vector2.ZERO, radius * 0.4 * (1.0 - t / 0.3), Color(1.0, 1.0, 0.85, inv))
	draw_circle(Vector2.ZERO, 9.0 * inv, Color(0.9, 0.95, 1.0, inv * 0.8))


# ── Burn: orange/red flame licks flickering upward ───────────────────────────
func _draw_burn(t: float, inv: float) -> void:
	var count := 9
	for i in range(count):
		var sx: float = (_seeds[i] - 0.5) * radius * 1.2
		var phase: float = fmod(t * 1.8 + _seeds[i], 1.0)
		var base := Vector2(sx, radius * 0.4)
		var height: float = radius * (0.6 + _seeds[i] * 0.6) * (1.0 - phase * 0.4)
		var flick: float = sin(t * 18.0 + i) * 4.0
		var tip := base + Vector2(flick, -height)
		var col := Color(1.0, 0.35 + _seeds[i] * 0.4, 0.0, inv * (1.0 - phase) * 0.85)
		draw_line(base, tip, col, 3.0 * inv)
		draw_circle(tip, 3.0 * inv, Color(1.0, 0.8, 0.2, inv * (1.0 - phase) * 0.7))
	draw_circle(Vector2(0, radius * 0.35), 10.0 * inv, Color(1.0, 0.5, 0.1, inv * 0.5))


# ── Nature: green spore/thorn burst with drifting motes ──────────────────────
func _draw_nature(t: float, inv: float) -> void:
	# Expanding green ring
	draw_arc(Vector2.ZERO, radius * t, 0, TAU, 28, Color(0.4, 0.9, 0.3, inv * 0.6), 2.5)
	var count := 12
	for i in range(count):
		var ang: float = _seeds[i] * TAU
		var dist: float = (0.3 + _seeds[i] * 0.7) * radius * t
		var pos := Vector2(cos(ang), sin(ang)) * dist
		var drift := Vector2(sin(t * 3.0 + i) * 3.0, cos(t * 2.0 + i) * 3.0)
		var col := Color(0.45, 0.85 - _seeds[i] * 0.3, 0.3, inv * 0.8)
		draw_circle(pos + drift, (2.0 + _seeds[i] * 2.5) * inv, col)
	draw_circle(Vector2.ZERO, 8.0 * inv, Color(0.6, 1.0, 0.5, inv * 0.7))


# ── Absorbed: small blue implosion on each pulled enemy ──────────────────────
func _draw_absorbed(t: float, inv: float) -> void:
	var r: float = radius * (1.0 - t) * 0.8
	draw_arc(Vector2.ZERO, r, 0, TAU, 20, Color(0.3, 0.6, 1.0, inv * 0.8), 2.5)
	draw_circle(Vector2.ZERO, r * 0.4, Color(0.6, 0.8, 1.0, inv * 0.6))
	# 4 inward dashes
	for i in range(4):
		var ang: float = i * (TAU / 4.0)
		var outer: Vector2 = Vector2(cos(ang), sin(ang)) * r
		draw_line(outer, outer * 0.3, Color(1.0, 1.0, 1.0, inv * 0.7), 2.0)
