extends Node2D
class_name StatusBadge

# One status icon in the row under a unit (ENEMY_FEEL_AUDIT.md §2.1, 2026-09-26).
# A bubble in the stun sheet's style + a per-status glyph + a ring that drains
# with the status's remaining time, so "for how long" is readable, not just "is".
#
# Glyphs are drawn in code so every status has an icon today. A status can swap
# to real art later by adding a sheet in VisualUnit.STATUS_ICON_SHEETS — the
# sheet then replaces the glyph and the ring stays.

const OUTLINE := Color(0.08, 0.07, 0.10)
const BUBBLE := Color(0.96, 0.95, 0.92)
const RING_BG := Color(0.08, 0.07, 0.10, 0.55)

var key := ""
var size := 30.0
var frac := 1.0              # remaining / peak duration, drives the ring
var _atlas: AtlasTexture = null
var _frames := 1
var _fps := 6.0
var _t := 0.0

func setup(status_key: String, px: float, sheet: Dictionary = {}) -> void:
	key = status_key
	size = px
	z_index = 6
	if not sheet.is_empty():
		var tex: Texture2D = load(sheet.get("path", "")) as Texture2D
		if tex:
			_frames = maxi(1, int(sheet.get("frames", 1)))
			var fw: int = int(sheet.get("frame_w", 0))
			var fh: int = int(sheet.get("frame_h", 0))
			if fw <= 0 or fh <= 0:
				fw = tex.get_width() / _frames
				fh = tex.get_height()
			_atlas = AtlasTexture.new()
			_atlas.atlas = tex
			_atlas.region = Rect2(0, 0, fw, fh)
	visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _atlas:
		var f: int = int(_t * _fps) % _frames
		_atlas.region.position.x = f * _atlas.region.size.x
	queue_redraw()

func _draw() -> void:
	var rad: float = size * 0.5
	# Duration ring: dark track, then the remaining arc in the status colour,
	# draining clockwise from 12 o'clock.
	var col: Color = glyph_color(key)
	draw_arc(Vector2.ZERO, rad + 2.5, 0, TAU, 32, RING_BG, 3.5)
	if frac > 0.0:
		draw_arc(Vector2.ZERO, rad + 2.5, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0),
			32, col, 3.0)
	if _atlas:
		var s: float = size * 1.05
		draw_texture_rect(_atlas, Rect2(-s * 0.5, -s * 0.5, s, s), false)
		return
	draw_circle(Vector2.ZERO, rad, OUTLINE)
	draw_circle(Vector2.ZERO, rad - 2.0, BUBBLE)
	_draw_glyph(rad - 3.0, col)

static func glyph_color(k: String) -> Color:
	match k:
		"stun":     return Color(0.70, 0.40, 0.95)
		"burn":     return Color(1.0, 0.45, 0.08)
		"disease":  return Color(0.55, 0.62, 0.20)
		"venom":    return Color(0.62, 0.28, 0.85)
		"bleed":    return Color(0.80, 0.08, 0.12)
		"slow":     return Color(0.30, 0.62, 0.95)
		"root":     return Color(0.55, 0.34, 0.14)
		"taunt":    return Color(0.95, 0.15, 0.12)
		"heal_cut": return Color(0.58, 0.22, 0.70)
		"weaken":   return Color(0.45, 0.45, 0.55)
		"corroded": return Color(0.40, 0.62, 0.18)
		"dread":    return Color(0.62, 0.25, 0.90)
		"blind":    return Color(0.16, 0.12, 0.28)
		"exposed":  return Color(0.88, 0.42, 0.14)
	return Color.WHITE

func _poly(pts: Array, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), c)

func _stroke(pts: Array, c: Color, w: float) -> void:
	draw_polyline(PackedVector2Array(pts), OUTLINE, w + 2.5)
	draw_polyline(PackedVector2Array(pts), c, w)

func _drop(c: Color, s: float, center: Vector2 = Vector2.ZERO) -> void:
	var pts: Array = [center + Vector2(0, -s)]
	for i in 11:
		var ang: float = -PI * 0.15 + PI * 1.3 * float(i) / 10.0
		pts.append(center + Vector2(cos(ang), sin(ang)) * s * 0.62 + Vector2(0, s * 0.25))
	_poly(pts, OUTLINE)
	var inner: Array = []
	for p in pts: inner.append(center + (p - center) * 0.78)
	_poly(inner, c)

func _draw_glyph(s: float, c: Color) -> void:
	match key:
		"burn":
			_drop(c, s * 0.95)
			_drop(Color(1.0, 0.9, 0.55), s * 0.45, Vector2(0, s * 0.22))
		"bleed":
			_drop(c, s * 0.9)
		"disease":
			_drop(c, s * 0.9)
			draw_circle(Vector2(-s * 0.12, s * 0.05), s * 0.12, OUTLINE)
			draw_circle(Vector2(s * 0.14, -s * 0.12), s * 0.08, OUTLINE)
		"venom":
			_drop(c, s * 0.9)
			_stroke([Vector2(-s * 0.2, s * 0.15), Vector2(s * 0.2, s * 0.15)], Color.WHITE, 1.5)
		"slow":
			# Hourglass.
			_poly([Vector2(-s * 0.55, -s * 0.7), Vector2(s * 0.55, -s * 0.7), Vector2(0, 0)], c)
			_poly([Vector2(-s * 0.55, s * 0.7), Vector2(s * 0.55, s * 0.7), Vector2(0, 0)], c)
			_stroke([Vector2(-s * 0.55, -s * 0.7), Vector2(s * 0.55, -s * 0.7), Vector2(-s * 0.55, s * 0.7),
				Vector2(s * 0.55, s * 0.7), Vector2(-s * 0.55, -s * 0.7)], c, 1.5)
		"root":
			var pts: Array = []
			for i in 9:
				var f: float = float(i) / 8.0
				pts.append(Vector2(sin(f * 9.0) * s * 0.45, s * 0.8 - f * s * 1.6))
			_stroke(pts, c, 3.0)
			_stroke([Vector2(-s * 0.7, s * 0.8), Vector2(s * 0.7, s * 0.8)], c, 3.0)
		"taunt":
			StatusFX.anger_vein(self, Vector2.ZERO, s * 0.55, OUTLINE, c, 4.0, 2.2)
		"heal_cut":
			_stroke([Vector2(0, -s * 0.7), Vector2(0, s * 0.7)], Color(0.3, 0.75, 0.35), 3.5)
			_stroke([Vector2(-s * 0.7, 0), Vector2(s * 0.7, 0)], Color(0.3, 0.75, 0.35), 3.5)
			_stroke([Vector2(-s * 0.75, -s * 0.75), Vector2(s * 0.75, s * 0.75)], c, 3.0)
		"weaken", "corroded":
			_stroke([Vector2(0, -s * 0.75), Vector2(0, s * 0.6)], c, 3.0)
			_stroke([Vector2(-s * 0.5, s * 0.1), Vector2(0, s * 0.65), Vector2(s * 0.5, s * 0.1)], c, 3.0)
		"dread":
			# A staring eye with a slit pupil.
			var lid: Array = []
			for i in 13:
				var f: float = float(i) / 12.0
				lid.append(Vector2(lerpf(-s * 0.8, s * 0.8, f), -sin(f * PI) * s * 0.5))
			for i in range(11, 0, -1):
				var f: float = float(i) / 12.0
				lid.append(Vector2(lerpf(-s * 0.8, s * 0.8, f), sin(f * PI) * s * 0.5))
			_poly(lid, OUTLINE)
			var inner: Array = []
			for p in lid: inner.append(p * 0.78)
			_poly(inner, c)
			_poly([Vector2(0, -s * 0.36), Vector2(s * 0.12, 0), Vector2(0, s * 0.36), Vector2(-s * 0.12, 0)],
				Color(1.0, 0.88, 0.35))
		"exposed":
			# A shield cracked down the middle: its defenses are down.
			var sh: Array = [Vector2(-s * 0.6, -s * 0.65), Vector2(s * 0.6, -s * 0.65),
				Vector2(s * 0.55, s * 0.1), Vector2(0, s * 0.75), Vector2(-s * 0.55, s * 0.1)]
			_poly(sh, OUTLINE)
			var inner: Array = []
			for p in sh: inner.append(p * 0.78)
			_poly(inner, c)
			_stroke([Vector2(0, -s * 0.62), Vector2(-s * 0.15, -s * 0.2), Vector2(s * 0.12, s * 0.1),
				Vector2(-s * 0.05, s * 0.6)], OUTLINE, 2.5)
		"blind":
			# An ink splat: a blot with three drips.
			draw_circle(Vector2(0, -s * 0.1), s * 0.62, OUTLINE)
			draw_circle(Vector2(0, -s * 0.1), s * 0.5, c)
			for dx in [-0.35, 0.0, 0.3]:
				draw_circle(Vector2(s * dx, s * 0.5), s * 0.16, c)
			draw_circle(Vector2(-s * 0.15, -s * 0.28), s * 0.12, Color(0.55, 0.45, 0.80))
		_:
			draw_circle(Vector2.ZERO, s * 0.4, c)
