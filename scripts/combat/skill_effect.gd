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
	DASH_STEP,     # Shauna active (Kite) — quick teal blink-step with afterimage trail
	TIDE_WAVE,     # Nemi active — bouncing wave
	TIDE_LINK,     # Nemi active — connecting trail between two bounce points
	TIDAL_WAVE,    # Nemi ultimate — wide ocean wave
	WAVE_WAKE,     # Nemi ultimate — small fading ripple left behind in the wave's wake
	# ── Roster expansion VFX ──
	LIGHTNING,     # Zolt / Static — jagged bolt burst
	BURN,          # Coal / Sear / Ember — flame licks
	NATURE,        # June / Spore — green spore/thorn burst
	WIND_GLIMMER,  # Vail passive — light aura mote on a buffed ally
	TORNADO,       # Vail active — spinning funnel the target gets whirled into
	DOWNBURST,     # Vail ultimate — wind slams down and blasts outward
	SERUM_SPRAY,   # Doc active (Inject) — green serum jet fired at an ally
}

var effect_type: Type = Type.WHIRLWIND
var lifetime: float = 0.8
var elapsed: float = 0.0
var radius: float = 48.0      # base visual radius

# TIDAL_WAVE only: radians/sec the crest pattern's sampling phase scrolls —
# the "moving still image" trick (pan the view across a fixed pattern instead
# of redrawing new content each frame). Tuned so the current visibly flows
# without outrunning the eye at TIDAL_WAVE_DURATION's timescale.
const SCROLL_SPEED := 3.4

# Random seeds for particles so each effect looks slightly different
var _seeds: Array[float] = []

# TIDE_LINK only: the far endpoint, in local space relative to global_position
# (which is set to the near endpoint). Lets one Node2D draw a two-point trail
# without a second position field on every other effect type.
var _link_target: Vector2 = Vector2.ZERO

func setup(type: Type, world_pos: Vector2, r: float = 48.0, life: float = 0.8) -> void:
	effect_type = type
	radius = r
	lifetime = life
	global_position = world_pos
	_seeds.clear()
	for i in range(20):
		_seeds.append(randf())
	queue_redraw()

# Connecting trail between two bounce points (e.g. Nemi's Tide chain), so a
# multi-hit chain actually reads as one wave traveling between targets instead
# of a string of unrelated splashes.
func setup_link(from_pos: Vector2, to_pos: Vector2, r: float = 48.0, life: float = 0.8) -> void:
	effect_type = Type.TIDE_LINK
	radius = r
	lifetime = life
	global_position = from_pos
	_link_target = to_pos - from_pos
	_seeds.clear()
	for i in range(20):
		_seeds.append(randf())
	queue_redraw()

# Doc's Inject: a jet of luminous serum fired from his syringe to an ally.
# Two-point like TIDE_LINK and for the same reason — a heal that pops on top of
# the target reads as "something happened to him", while one that visibly
# travels reads as "Doc did that to him", which is the whole point of a support
# unit whose contribution is otherwise invisible on the board.
func setup_spray(from_pos: Vector2, to_pos: Vector2, r: float = 40.0, life: float = 0.45) -> void:
	effect_type = Type.SERUM_SPRAY
	radius = r
	lifetime = life
	global_position = from_pos
	_link_target = to_pos - from_pos
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
		Type.DASH_STEP:     _draw_dash_step(t, inv)
		Type.TIDE_WAVE:     _draw_tide_wave(t, inv)
		Type.TIDE_LINK:     _draw_tide_link(t, inv)
		Type.SERUM_SPRAY:   _draw_serum_spray(t, inv)
		Type.TIDAL_WAVE:    _draw_tidal_wave(t, inv)
		Type.WAVE_WAKE:     _draw_wave_wake(t, inv)
		Type.LIGHTNING:     _draw_lightning(t, inv)
		Type.BURN:          _draw_burn(t, inv)
		Type.NATURE:        _draw_nature(t, inv)
		Type.WIND_GLIMMER:  _draw_wind_glimmer(t, inv)
		Type.TORNADO:       _draw_tornado(t, inv)
		Type.DOWNBURST:     _draw_downburst(t, inv)


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


# ── Shauna Kite: quick teal blink-step with an afterimage trail ─────────────
# Distinct from Overdrive's spinning rings (which used to be reused here too)
# — this reads as a snap dodge/reposition, not a spin-up. Fast: a bright
# flash that immediately splits into fading afterimage silhouettes trailing
# back the way she came, plus short outward speed-lines to sell "instant."
func _draw_dash_step(t: float, inv: float) -> void:
	var teal := Color(0.1, 0.9, 0.85)
	var white := Color(1.0, 1.0, 1.0)

	# Bright flash at the instant of the step, gone fast.
	if t < 0.2:
		draw_circle(Vector2.ZERO, radius * 0.5 * (1.0 - t / 0.2), Color(white.r, white.g, white.b, (1.0 - t / 0.2) * 0.9))

	# 3 afterimage rings receding outward — reads as "she was just here."
	for i in range(3):
		var phase: float = clamp(t * 2.2 - i * 0.16, 0.0, 1.0)
		if phase <= 0.0:
			continue
		var r: float = radius * 0.3 * (1.0 + i * 0.3)
		var a: float = (1.0 - phase) * inv * (0.7 - i * 0.15)
		draw_arc(Vector2.ZERO, r, 0, TAU, 20, Color(teal.r, teal.g, teal.b, a), 2.5)

	# Short outward speed-lines, tighter and snappier than Overdrive's spokes.
	var count := 8
	for i in range(count):
		var ang: float = _seeds[i] * TAU
		var len: float = radius * 0.5 * (1.0 - t) * (0.6 + _seeds[i] * 0.5)
		var tip: Vector2 = Vector2(cos(ang), sin(ang)) * len
		draw_line(Vector2.ZERO, tip, Color(teal.r, teal.g, teal.b, inv * 0.6), 2.0)

	draw_circle(Vector2.ZERO, 5.0 * inv, Color(white.r, white.g, white.b, inv * 0.8))


# Cheap fake-gradient helper: N concentric circles stepping down in both size
# and alpha so a splash/glow reads as soft-edged instead of a flat disc with a
# hard cutoff. Used across all three Nemi effects below.
func _draw_soft_glow(center: Vector2, r: float, col: Color, layers: int = 5) -> void:
	for i in range(layers, 0, -1):
		var frac: float = float(i) / layers
		draw_circle(center, r * frac, Color(col.r, col.g, col.b, col.a * (1.0 - frac) * 0.9))


# ── Nemi Tide: splash impact on a bounce target ──────────────────────────────
func _draw_tide_wave(t: float, inv: float) -> void:
	var deep := Color(0.1, 0.45, 0.95)
	var foam := Color(0.85, 0.98, 1.0)

	# Impact core: fast bright flash that collapses into a soft glow.
	var impact: float = clamp(t / 0.25, 0.0, 1.0)
	_draw_soft_glow(Vector2.ZERO, radius * 0.45 * (0.4 + 0.6 * impact), Color(deep.r, deep.g, deep.b, inv))

	# Three expanding ripple rings, thick-to-thin as they grow (like a real
	# water ring rather than a wireframe circle).
	for i in range(3):
		var phase: float = clamp(t * 1.6 - i * 0.18, 0.0, 1.0)
		if phase <= 0.0:
			continue
		var r: float = phase * radius * 1.3
		draw_arc(Vector2.ZERO, r, 0, TAU, 32,
			Color(foam.r, foam.g, foam.b, (1.0 - phase) * inv * 0.8), 4.0 * (1.0 - phase * 0.6))

	# Droplets bursting outward and arcing down under gravity (a real splash
	# silhouette, not a flat radial spray).
	var count := 10
	for i in range(count):
		var ang: float = (_seeds[i] - 0.5) * PI * 1.6 - PI * 0.5   # mostly upward cone
		var speed: float = (0.6 + _seeds[i] * 0.7) * radius * 1.8
		var out: Vector2 = Vector2(cos(ang), sin(ang)) * speed
		var drop_t: float = clamp(t * (1.1 + _seeds[i] * 0.4), 0.0, 1.0)
		var pos: Vector2 = out * drop_t
		pos.y += 260.0 * drop_t * drop_t * (radius / 160.0)   # gravity arc, scaled to size
		var a: float = inv * (1.0 - drop_t) * 0.9
		draw_circle(pos, (3.0 + _seeds[i] * 3.0) * inv, Color(foam.r, foam.g, foam.b, a))

	draw_circle(Vector2.ZERO, radius * 0.06 * inv, Color(1.0, 1.0, 1.0, inv * 0.85))


# ── Nemi Tide: connecting trail between consecutive bounce points ───────────
# Drawn from ZERO (near endpoint, = global_position) to _link_target (far
# endpoint in local space). A droplet travels along the line so the chain
# reads as one wave surging from target to target, not isolated splashes.
func _draw_tide_link(t: float, inv: float) -> void:
	var deep := Color(0.1, 0.45, 0.95)
	var foam := Color(0.85, 0.98, 1.0)
	var to := _link_target
	var perp := to.orthogonal().normalized() if to.length() > 0.01 else Vector2.RIGHT

	# The beam GROWS from the near endpoint (ZERO) out to wherever the leading
	# edge (drop_t) currently is — it does not exist past that point yet. This
	# is what actually sells travel time; drawing the full line every frame and
	# only moving a dot on top of it (the old approach) reads as instant no
	# matter how long the effect's lifetime is, since the "water" itself never
	# appears to be in transit.
	var drop_t: float = clamp(t, 0.0, 1.0)
	var segs := 24
	var lead_seg: int = maxi(1, int(ceil(drop_t * segs)))

	# Layered glow trail: 3 overlapping strokes (wide+faint under, narrow+bright
	# over), each only drawn up to the current leading edge, with a comet-style
	# fade so the tail (further behind the leading edge) dims out instead of
	# staying uniformly bright — reinforces "this is flowing," not "this is lit."
	for layer in range(3):
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in range(lead_seg + 1):
			var frac: float = minf(float(i) / segs, drop_t)
			var base: Vector2 = to * frac
			var wobble: float = sin(frac * PI * 3.5 + t * TAU * 1.2) * (5.0 * inv) * (1.0 - frac * 0.3)
			pts.append(base + perp * wobble)
			# How far behind the leading edge this point is, 0 = at the tip.
			var behind: float = clamp((drop_t - frac) / maxf(drop_t, 0.001), 0.0, 1.0)
			var tail_fade: float = 1.0 - behind * 0.75
			var a: float = inv * (0.45 + layer * 0.15) * tail_fade
			cols.append(Color(deep.r, deep.g, deep.b, a))
		if pts.size() >= 2:
			var width: float = (9.0 - layer * 2.5) * inv
			draw_polyline_colors(pts, cols, width, true)

	# Bright leading tip riding right at the edge of the growing beam, with a
	# soft glow so it reads as the active "front" of the water.
	var tip_pos: Vector2 = to * drop_t
	_draw_soft_glow(tip_pos, radius * 0.11 * inv, Color(foam.r, foam.g, foam.b, inv * 0.8), 3)
	draw_circle(tip_pos, radius * 0.045 * inv, Color(1.0, 1.0, 1.0, inv * 0.95))


# ── Nemi Tidal Wave: a wave-front that actually travels the board ────────────
# The travel itself is driven externally — the caller moves this node's
# global_position one row at a time as the wave crosses the field (see
# _tick_nemi_tidal_waves in auto_battle_manager.gd). This draw function only
# renders the cross-section (a 5-tile-wide surging band) at wherever the node
# currently sits, so the "sweep" reads as real motion across the grid instead
# of a fixed-position animation playing in place over Nemi's head.
func _draw_tidal_wave(t: float, _inv_unused: float) -> void:
	var deep  := Color(0.04, 0.28, 0.75)
	var mid   := Color(0.15, 0.55, 0.95)
	var crest := Color(0.75, 0.95, 1.0)
	var foam  := Color(1.0,  1.0,  1.0)

	# Override the base inv (1.0 - t across the WHOLE multi-second crossing,
	# which faded the wave to near-nothing well before it reached the far
	# wall). It should stay fully solid for the entire traversal and only
	# fade in the last stretch, right as it hits the edge.
	var inv: float = 1.0 if t < 0.85 else clamp((1.0 - t) / 0.15, 0.0, 1.0)

	# `radius` is passed in as 2.5 grid cells (half of the 5-tile-wide hit
	# column), so derive one tile's size from it rather than eyeballing a
	# fraction of radius — that's what kept the silhouette from actually
	# matching the 5-wide/1-tall footprint it's supposed to represent.
	var half_w: float = radius
	var tile: float = radius / 2.5
	var segs := 40

	# Per-cast randomised (via _seeds, rolled fresh in setup()) — every Tidal
	# Wave gets its own frequency/phase/amplitude so two casts never look
	# identical.
	# Scaled up from the original 3-tile tuning (2.0–3.3) by 5/3 so crest
	# density per tile stays the same now that the band is 5 tiles wide.
	var freq: float = 3.3 + _seeds[0] * 2.2          # 3.3–5.5 crests across the band
	var phase: float = _seeds[1] * TAU
	var amp: float = tile * (0.16 + _seeds[2] * 0.14) # 0.16–0.30 tile amplitude

	# Scrolling-texture trick: the crest pattern is infinite in x, and we just
	# slide the sampling phase to the right over time — same illusion as
	# panning a still image sideways instead of redrawing new content. The
	# envelope (±amp around the baseline) never changes, so the silhouette's
	# footprint stays exactly what the 3-wide/1-tall check above measured;
	# only the current WITHIN that footprint appears to flow.
	var scroll: float = t * SCROLL_SPEED

	var top := PackedVector2Array()
	for step in range(segs + 1):
		var frac: float = float(step) / segs
		var x: float = -half_w + frac * half_w * 2.0
		var curl: float = sin(frac * PI * freq + phase + scroll) * amp
		top.append(Vector2(x, curl - tile * 0.15))
	var poly := PackedVector2Array()
	poly.append_array(top)
	poly.append(Vector2(half_w, tile * 0.5))
	poly.append(Vector2(-half_w, tile * 0.5))

	draw_colored_polygon(poly, Color(deep.r, deep.g, deep.b, inv * 0.6))

	# Mid-tone band just under the crest line for a sense of depth. Drawn with
	# draw_polyline (not per-segment draw_line) so the joints stay smooth
	# instead of fringing into a sawtooth edge at high curvature.
	var mid_line := PackedVector2Array()
	for p in top:
		mid_line.append(p + Vector2(0, tile * 0.16))
	draw_polyline(mid_line, Color(mid.r, mid.g, mid.b, inv * 0.5), tile * 0.12, true)

	# Bright crest line riding the very top of the water mass.
	draw_polyline(top, Color(crest.r, crest.g, crest.b, inv * 0.9), tile * 0.05, true)

	# Shimmer: 3 thin, near-transparent streaks riding just above the crest,
	# animated with `t` at TINY amplitude (a fraction of the crest's own
	# amplitude). This is what makes the surface read as live, moving water
	# instead of a static painted shape — without altering the actual
	# silhouette/footprint the shape check above cares about.
	for s in range(3):
		var s_seed: float = _seeds[(4 + s) % _seeds.size()]
		var s_pts := PackedVector2Array()
		for step in range(24):
			var frac: float = float(step) / 23.0
			var x: float = -half_w + frac * half_w * 2.0
			var base_y: float = sin(frac * PI * freq + phase + scroll) * amp - tile * 0.15
			# Faster secondary scroll on the detail layer — reads as small
			# ripples flowing over the bigger current underneath.
			var shimmer: float = sin(frac * PI * 9.0 + scroll * 1.7 + s_seed * TAU) * tile * 0.035
			s_pts.append(Vector2(x, base_y - tile * 0.05 * (s + 1) + shimmer))
		draw_polyline(s_pts, Color(foam.r, foam.g, foam.b, inv * 0.18), tile * 0.02, true)



# ── Nemi Tidal Wave: small fading ripple left behind in the wave's wake ──────
# Spawned periodically as the wave travels (see _tick_nemi_tidal_waves) so it
# leaves a short trailing wake instead of gliding across the field in silence.
func _draw_wave_wake(t: float, inv: float) -> void:
	var col := Color(0.6, 0.9, 1.0)
	var r: float = radius * (0.3 + 0.7 * t)
	draw_arc(Vector2.ZERO, r, 0, TAU, 20, Color(col.r, col.g, col.b, inv * 0.55), 2.5 * inv)
	draw_circle(Vector2.ZERO, radius * 0.15 * inv, Color(1.0, 1.0, 1.0, inv * 0.5))


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


# ── Vail Far Winds: a small orbiting glimmer + drifting feather on a buffed ally ──
# Deliberately subtle — this fires every AURA_TICK_INTERVAL on every ally in
# range, so it needs to read as "this unit is charmed by the wind" at a glance
# without becoming visual noise on a full row of buffed units.
func _draw_wind_glimmer(t: float, inv: float) -> void:
	var pale := Color(0.85, 1.0, 1.0)
	var white := Color(1.0, 1.0, 1.0)

	# Two motes orbiting in a tight ring, opposite phase.
	for i in range(2):
		var ang: float = t * TAU * 1.6 + i * PI
		var orbit_r: float = radius * 0.5
		var pos := Vector2(cos(ang), sin(ang) * 0.55) * orbit_r  # flattened ellipse orbit
		var a: float = inv * 0.75
		_draw_soft_glow(pos, radius * 0.16, Color(pale.r, pale.g, pale.b, a), 3)
		draw_circle(pos, 2.2 * inv, Color(white.r, white.g, white.b, a))

	# A tiny feather sliver drifting upward and curling sideways — echoes
	# Vail's own design detail (the loose feather beside her static art).
	var drift_t: float = t
	var fx: float = sin(drift_t * TAU * 0.8) * radius * 0.35
	var fy: float = radius * 0.55 - drift_t * radius * 1.3
	var feather_ang: float = sin(drift_t * TAU * 1.4) * 0.6 - 0.4
	var feather_pos := Vector2(fx, fy)
	var quill: Vector2 = Vector2(cos(feather_ang), sin(feather_ang)) * 9.0 * inv
	draw_line(feather_pos - quill, feather_pos + quill, Color(pale.r, pale.g, pale.b, inv * 0.7), 2.0)
	var barb_perp: Vector2 = quill.orthogonal().normalized() * 3.5 * inv
	draw_line(feather_pos, feather_pos + barb_perp - quill * 0.3, Color(white.r, white.g, white.b, inv * 0.5), 1.2)
	draw_line(feather_pos, feather_pos - barb_perp - quill * 0.3, Color(white.r, white.g, white.b, inv * 0.5), 1.2)

	# Faint ground halo so it still reads at a glance even without watching the orbit.
	draw_arc(Vector2.ZERO, radius * 0.35, 0, TAU, 20, Color(pale.r, pale.g, pale.b, inv * 0.3), 1.5)


# ── Vail Updraft: a spinning wind funnel the target is whirled up into ──────
# Spawned at the target's ground position for the whole untargetable window
# (visual_unit.gd separately tweens the sprite itself upward+spinning inside
# this funnel via play_updraft_lift). Solid through the middle, fading only at
# the very start/end so it doesn't flicker during the short 1s window.
func _draw_tornado(t: float, _inv_unused: float) -> void:
	var inv: float = clamp(t / 0.15, 0.0, 1.0) * clamp((1.0 - t) / 0.2, 0.0, 1.0) + (1.0 if t > 0.15 and t < 0.8 else 0.0)
	inv = clamp(inv, 0.0, 1.0)
	var pale := Color(0.8, 0.98, 1.0)
	var deep := Color(0.55, 0.85, 0.95)
	var white := Color(1.0, 1.0, 1.0)

	var height: float = radius * 3.0
	var spin: float = t * TAU * 5.0

	# Stacked, narrowing bands from base to tip — a funnel silhouette built out
	# of rotating ellipses rather than a static cone, so it visibly churns.
	var bands := 7
	for b in range(bands):
		var frac: float = float(b) / (bands - 1)          # 0 at base, 1 at tip
		var y: float = -frac * height
		var band_r: float = radius * (0.85 - frac * 0.65)  # narrows going up
		var wobble: float = sin(spin * 0.6 + frac * 6.0) * band_r * 0.12
		var a: float = inv * (0.55 - frac * 0.25)
		draw_arc(Vector2(wobble, y), band_r, spin + frac * 4.0, spin + frac * 4.0 + TAU * 0.82, 16,
			Color(pale.r, pale.g, pale.b, a), 2.5 * (1.0 - frac * 0.4))

	# Swirling debris motes climbing the funnel.
	var count := 10
	for i in range(count):
		var seed_i: float = _seeds[i]
		var climb: float = fmod(t * 1.8 + seed_i, 1.0)
		var frac: float = climb
		var y: float = -frac * height
		var band_r: float = radius * (0.85 - frac * 0.65) * (0.7 + seed_i * 0.3)
		var ang: float = spin * (1.2 + seed_i * 0.6) + seed_i * TAU
		var pos := Vector2(cos(ang) * band_r, y + sin(ang) * band_r * 0.25)
		var a: float = inv * (1.0 - frac) * 0.85
		draw_circle(pos, (1.5 + seed_i * 2.0), Color(white.r, white.g, white.b, a))

	# Ground swirl at the base — sells "rooted to this tile."
	draw_arc(Vector2.ZERO, radius * 0.9, spin * 1.4, spin * 1.4 + TAU * 0.75, 24,
		Color(deep.r, deep.g, deep.b, inv * 0.45), 3.0)
	_draw_soft_glow(Vector2.ZERO, radius * 0.35, Color(pale.r, pale.g, pale.b, inv), 4)


# ── Vail Downburst: wind slams down from above then blasts outward ──────────
# Two phases: (1) a converging downward gust telegraphing the strike, (2) a
# ground-level shockwave + horizontal debris blast at impact. Mirrors Bouncer's
# Gravity Drop shape (converge → impact) but inverted — this pushes OUT along
# the ground instead of pulling IN, matching "downburst" rather than "vortex."
func _draw_downburst(t: float, inv: float) -> void:
	var sky := Color(0.75, 0.92, 1.0)
	var white := Color(1.0, 1.0, 1.0)
	var dust := Color(0.85, 0.8, 0.7)

	if t < 0.3:
		# Phase 1: streaks of wind converging downward onto the target.
		var p: float = t / 0.3
		var count := 8
		for i in range(count):
			var seed_i: float = _seeds[i]
			var x: float = (seed_i - 0.5) * radius * 1.6
			var start_y: float = -radius * 1.8 * (1.0 - p) - radius * 0.4
			var end_y: float = start_y + radius * 0.9
			var a: float = p * 0.8
			draw_line(Vector2(x, start_y), Vector2(x, end_y), Color(sky.r, sky.g, sky.b, a), 2.5)
		draw_circle(Vector2.ZERO, radius * 0.18 * p, Color(white.r, white.g, white.b, p * 0.6))
	else:
		# Phase 2: ground shockwave ring expanding outward + low horizontal
		# debris streaks blown flat along the ground — the "downburst spreads
		# out" beat that makes this read as distinct from an inward pull.
		var p: float = clamp((t - 0.3) / 0.7, 0.0, 1.0)

		# Bright impact flash, quick.
		if p < 0.25:
			draw_circle(Vector2.ZERO, radius * 0.5 * (1.0 - p / 0.25), Color(white.r, white.g, white.b, (1.0 - p / 0.25) * 0.9))

		# Two expanding rings, thick-to-thin, hugging the ground.
		for i in range(2):
			var ring_p: float = clamp(p * 1.3 - i * 0.25, 0.0, 1.0)
			if ring_p <= 0.0:
				continue
			var r: float = ring_p * radius * 1.6
			draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(sky.r, sky.g, sky.b, (1.0 - ring_p) * inv * 0.7), 3.0 * (1.0 - ring_p * 0.5))

		# Debris blown outward low and flat (squashed ellipsoid spread, not a
		# radial sphere) so it reads as ground-hugging wind, not an explosion.
		var count := 10
		for i in range(count):
			var seed_i: float = _seeds[i]
			var ang: float = seed_i * TAU
			var dist: float = (0.4 + seed_i * 0.7) * radius * 1.4 * p
			var pos := Vector2(cos(ang) * dist, sin(ang) * dist * 0.35)
			var a: float = (1.0 - p) * inv * 0.75
			draw_line(pos, pos - Vector2(cos(ang), sin(ang) * 0.35) * 8.0, Color(dust.r, dust.g, dust.b, a), 2.0)

	# Downward chevrons telegraphing "this pushes down and out," visible for
	# the first half of the effect only.
	if t < 0.5:
		var chevron_a: float = (1.0 - t / 0.5) * 0.7
		for i in range(3):
			var y: float = -radius * 0.6 + i * radius * 0.35
			draw_line(Vector2(-10, y), Vector2(0, y + 12), Color(white.r, white.g, white.b, chevron_a), 2.0)
			draw_line(Vector2(10, y), Vector2(0, y + 12), Color(white.r, white.g, white.b, chevron_a), 2.0)


# Green serum jet + impact splash. Colours match Model3DSprite's glow_by_clip
# entry for Doc's "skill" so the fluid in the syringe and the fluid in the air
# are visibly the same substance.
func _draw_serum_spray(t: float, inv: float) -> void:
	var pale := Color(0.72, 1.0, 0.78)
	var core := Color(0.30, 1.0, 0.40)
	var to := _link_target
	if to.length() < 0.01:
		return
	var perp := to.orthogonal().normalized()
	# The jet only exists as far as its leading edge, same as TIDE_LINK: a full
	# line drawn from frame one reads as instantaneous however long it lives.
	var head: float = clamp(t / 0.7, 0.0, 1.0)
	var segs := 18
	var lead: int = maxi(1, int(ceil(head * segs)))
	for layer in range(2):
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in range(lead + 1):
			var frac: float = minf(float(i) / segs, head)
			# Slight sag then rise: a squirt of liquid, not a laser.
			var sag: float = sin(frac * PI) * radius * 0.18
			var wob: float = sin(frac * PI * 4.0 + t * TAU) * 3.0 * inv
			pts.append(to * frac + perp * wob + Vector2(0.0, sag))
			var behind: float = head - frac
			var a: float = clampf(1.0 - behind * 2.2, 0.0, 1.0) * inv
			cols.append(Color(pale.r, pale.g, pale.b, a * 0.45) if layer == 0
					else Color(core.r, core.g, core.b, a * 0.9))
		if pts.size() >= 2:
			# Widths measured against the board, not picked: a 7 px jet was
			# barely visible next to a 138 px character, so the soft under-
			# stroke carries the mass and the core sits inside it.
			draw_polyline_colors(pts, cols, 13.0 - layer * 6.0, true)

	# Droplets shed along the jet, so it breaks up like liquid rather than
	# holding a clean edge.
	for i in range(10):
		var f: float = _seeds[i] * head
		var d: Vector2 = to * f + perp * (_seeds[i + 8] - 0.5) * radius * 0.5
		draw_circle(d + Vector2(0.0, sin(f * PI) * radius * 0.18),
				2.5 + _seeds[i] * 3.0, Color(core.r, core.g, core.b, inv * 0.95))

	# Impact: expands once the jet lands, not before.
	if t > 0.55:
		var bt: float = (t - 0.55) / 0.45
		var br: float = radius * (0.25 + bt * 0.85)
		draw_arc(to, br, 0.0, TAU, 22, Color(pale.r, pale.g, pale.b,
				(1.0 - bt) * 0.95), 5.0, true)
		for i in range(6):
			var ang: float = TAU * (float(i) / 6.0 + _seeds[i] * 0.2)
			draw_circle(to + Vector2(cos(ang), sin(ang)) * br,
					4.0 * (1.0 - bt), Color(core.r, core.g, core.b, (1.0 - bt) * 0.95))
