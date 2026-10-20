extends Node2D
class_name StatusFX

# The SHARED status layer's body marks (ENEMY_FEEL_AUDIT.md §2.1, 2026-09-26).
# One node per (unit, status), created and freed by
# AutoBattleManager._sync_status_marks() while that status's timer is running.
#
# Covers every status that had NO look on the victim: fire burn, slow, root,
# taunt, heal-cut and weaken. A status an ability already dresses bespoke (Sear's
# burn mark, June's root cuffs, the Slime's corrosion, the Rat's disease...) is
# skipped by the sync, so this never paints over a hero's own language.
#
# Board is GRASS: nothing here is green, and every bright stroke sits on a dark
# under-stroke so it survives sunlit tiles (see the Fire Giant / Gargoyle notes).
# Origin is the unit's HIP; the feet sit at ground_y (shape_size * 0.72).

enum Kind { BURN, SLOW, ROOT, TAUNT, HEAL_CUT, WEAKEN }

const EMBER_DARK := Color(0.30, 0.07, 0.02)
const FLAME := Color(1.0, 0.50, 0.10)
const FLAME_HOT := Color(1.0, 0.93, 0.70)
const FROST_DARK := Color(0.06, 0.12, 0.28)
const FROST := Color(0.62, 0.86, 1.0)
const BARK_DARK := Color(0.16, 0.09, 0.04)
const BARK := Color(0.55, 0.36, 0.18)
const BARK_LIGHT := Color(0.86, 0.70, 0.46)
const TAUNT_DARK := Color(0.25, 0.02, 0.02)
const TAUNT := Color(1.0, 0.22, 0.18)
const CURSE_DARK := Color(0.10, 0.03, 0.12)
const CURSE := Color(0.72, 0.36, 0.86)
const WEAK_DARK := Color(0.05, 0.05, 0.07)
const WEAK := Color(0.93, 0.93, 1.0)

var kind: Kind = Kind.BURN
var host = null
var ground_y := 46.0
var r := 33.0                # half body width
var strength := 1.0          # SLOW: slow_pct mapped 0..1
var _t := 0.0
var _fade := 0.0             # 0 → 1 over the first 0.15s so marks don't pop

func setup_on(k: Kind, unit) -> void:
	kind = k
	host = unit
	z_index = 3
	if unit and "shape_size" in unit:
		ground_y = float(unit.shape_size) * 0.72
		r = float(unit.shape_size) * 0.5
	global_position = unit.global_position
	queue_redraw()

func set_strength(v: float) -> void:
	strength = clampf(v, 0.0, 1.0)

func _process(delta: float) -> void:
	_t += delta
	_fade = minf(1.0, _fade + delta / 0.15)
	if not (host and is_instance_valid(host)):
		queue_free()
		return
	global_position = host.global_position
	queue_redraw()

func _draw() -> void:
	match kind:
		Kind.BURN:     _draw_burn()
		Kind.SLOW:     _draw_slow()
		Kind.ROOT:     _draw_root()
		Kind.TAUNT:    _draw_taunt()
		Kind.HEAL_CUT: _draw_heal_cut()
		Kind.WEAKEN:   _draw_weaken()

func _ca(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a * _fade)

# A flame silhouette: round belly at the base, tapering into a swaying tip.
# Three nested layers — dark rim, orange body, white-hot core.
func _flame(base: Vector2, h: float, w: float, sway: float) -> void:
	for layer in 3:
		var s: float = [1.0, 0.78, 0.42][layer]
		var c: Color = [EMBER_DARK, FLAME, FLAME_HOT][layer]
		var a: float = [0.70, 0.90, 0.95][layer]
		var hh: float = h * s
		var ww: float = w * s
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for i in 11:
			var f: float = float(i) / 10.0
			var hw: float = ww * pow(1.0 - f, 0.75) * minf(1.0, 0.55 + f * 3.0)
			var cx: float = sway * f * f * s
			var y: float = base.y - f * hh
			left.append(Vector2(base.x + cx - hw, y))
			right.append(Vector2(base.x + cx + hw, y))
		right.reverse()
		var pts := left + right
		draw_colored_polygon(pts, _ca(c, a))

# ── Burn: flames licking up the body while the fire ticks ───────────────────
func _draw_burn() -> void:
	# Heat glow behind the torso so the fire reads as ON the unit.
	draw_circle(Vector2(0, -r * 0.55), r * 0.75, _ca(FLAME, 0.14))
	for i in 3:
		var fx: float = (float(i) - 1.0) * r * 0.42
		var flick: float = 0.8 + 0.2 * sin(_t * 11.0 + float(i) * 2.1)
		var base := Vector2(fx, -r * 0.05 + absf(fx) * 0.25)
		var h: float = r * (1.05 if i == 1 else 0.75) * flick
		_flame(base, h, r * 0.26, sin(_t * 6.0 + float(i) * 1.7) * r * 0.22)
	# Embers rising off the top.
	for i in 5:
		var ph: float = fposmod(_t * 0.9 + float(i) * 0.21, 1.0)
		var p := Vector2(sin(float(i) * 3.7 + _t * 2.0) * r * 0.45, -r * 0.5 - ph * r * 1.1)
		draw_circle(p, 2.2 * (1.0 - ph) + 0.8, _ca(FLAME_HOT, 0.85 * (1.0 - ph)))

# ── Slow: frost gathering at the feet, the body dragging downward ───────────
func _draw_slow() -> void:
	var a: float = 0.45 + 0.4 * strength
	# Frost ring on the ground.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.36))
	draw_arc(Vector2.ZERO, r * 0.95, 0, TAU, 32, _ca(FROST_DARK, a * 0.8), 6.0)
	draw_arc(Vector2.ZERO, r * 0.95, 0, TAU, 32, _ca(FROST, a), 2.5)
	for i in 6:
		var ang: float = TAU * float(i) / 6.0 + _t * 0.3
		var p := Vector2(cos(ang), sin(ang)) * r * 0.95
		draw_line(p, p * 1.22, _ca(FROST, a), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Heavy chevrons sinking down the body — slow tempo on purpose.
	for i in 2:
		var ph: float = fposmod(_t * 0.45 + float(i) * 0.5, 1.0)
		var y: float = -r * 1.1 + ph * r * 1.1
		var w: float = r * 0.32
		var al: float = a * sin(ph * PI)
		for layer in 2:
			var c: Color = FROST_DARK if layer == 0 else FROST
			var th: float = 6.0 if layer == 0 else 2.5
			draw_polyline(PackedVector2Array([Vector2(-w, y - w * 0.5), Vector2(0, y),
				Vector2(w, y - w * 0.5)]), _ca(c, al), th)

# ── Root: bark vines coiled up the legs ──────────────────────────────────────
func _draw_root() -> void:
	var grow: float = minf(1.0, _t / 0.25)
	for i in 4:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var x0: float = side * r * (0.25 + 0.2 * float(i / 2))
		var pts := PackedVector2Array()
		for s in 9:
			var f: float = float(s) / 8.0 * grow
			pts.append(Vector2(x0 * (1.0 - f * 0.6) + sin(f * 7.0 + float(i)) * r * 0.16,
				ground_y + r * 0.08 - f * r * 0.85))
		draw_polyline(pts, _ca(BARK_DARK, 0.9), 7.0)
		draw_polyline(pts, _ca(BARK, 0.95), 4.0)
		draw_polyline(pts, _ca(BARK_LIGHT, 0.7), 1.5)
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.36))
	draw_arc(Vector2.ZERO, r * 0.6, 0, TAU, 28, _ca(BARK_DARK, 0.7), 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ── Taunt: an angry mark over the head, and a thread to whoever holds it ─────
func _draw_taunt() -> void:
	var src = host.taunt_source if host else null
	if src and is_instance_valid(src):
		var to: Vector2 = src.global_position - global_position
		var n: int = int(to.length() / 14.0)
		for i in range(n):
			if (i + int(_t * 8.0)) % 2 == 0:
				var a: Vector2 = to * (float(i) / float(maxi(n, 1)))
				var b: Vector2 = to * (float(i) + 0.6) / float(maxi(n, 1))
				draw_line(a + Vector2(0, -r * 0.6), b + Vector2(0, -r * 0.6), _ca(TAUNT, 0.35), 2.0)
	anger_vein(self, Vector2(r * 0.6, -r * 1.6), r * 0.42 * (1.0 + 0.12 * sin(_t * 9.0)),
		_ca(TAUNT_DARK, 0.95), _ca(TAUNT, 0.95), 7.0, 3.5)

# The manga anger mark: four arcs bowing in toward a shared centre. Static so
# the badge glyph draws the exact same symbol.
static func anger_vein(ci: CanvasItem, c: Vector2, s: float, dark: Color, col: Color,
		dark_w: float, w: float) -> void:
	for layer in 2:
		for q in 4:
			var ang: float = PI * 0.25 + PI * 0.5 * float(q)
			var d := Vector2(cos(ang), sin(ang))
			ci.draw_arc(c + d * s * 1.05, s * 0.62, ang + PI - 0.95, ang + PI + 0.95, 10,
				dark if layer == 0 else col, dark_w if layer == 0 else w)

# ── Heal-cut: a cracked cross on the chest — healing won't take ─────────────
func _draw_heal_cut() -> void:
	var c := Vector2(0, -r * 0.75)
	var s: float = r * 0.42
	var pulse: float = 0.7 + 0.3 * sin(_t * 4.0)
	for layer in 2:
		var col: Color = CURSE_DARK if layer == 0 else CURSE
		var th: float = 8.0 if layer == 0 else 4.0
		draw_line(c + Vector2(0, -s), c + Vector2(0, s), _ca(col, 0.8 * pulse), th)
		draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), _ca(col, 0.8 * pulse), th)
		draw_line(c + Vector2(-s * 1.1, -s * 1.1), c + Vector2(s * 1.1, s * 1.1),
			_ca(col, 0.95), th * 0.8)

# ── Weaken: grey motes and arrows draining down, a dull pool at the feet ────
func _draw_weaken() -> void:
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, r * 0.7, _ca(WEAK_DARK, 0.30))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 3:
		var ph: float = fposmod(_t * 0.6 + float(i) / 3.0, 1.0)
		var x: float = (float(i) - 1.0) * r * 0.45
		var y: float = -r * 1.2 + ph * r * 1.2
		var al: float = sin(ph * PI) * 0.9
		var w: float = r * 0.17
		for layer in 2:
			var col: Color = WEAK_DARK if layer == 0 else WEAK
			var th: float = 7.0 if layer == 0 else 3.0
			draw_line(Vector2(x, y - w * 2.0), Vector2(x, y), _ca(col, al), th)
			draw_polyline(PackedVector2Array([Vector2(x - w, y - w), Vector2(x, y),
				Vector2(x + w, y - w)]), _ca(col, al), th)
