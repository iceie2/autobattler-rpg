class_name MapRouteArt
extends RefCounted
# ══════════════════════════════════════════════════════════════════════════════
# The RUN MAP's drawing helpers, shared (2026-10-07, extracted for the run recap).
#
# The recap replays the run over the same route art the map draws, so the two
# must never become two styles. The ASSET TABLES stay where they always were, on
# RunMapScreen (BACKDROP_*, ICON_*, GLYPHS, TIER_COLORS, ROAD_GOLD, FLOW_*); this
# file only holds the drawing routines both screens call. RunMapScreen's own
# _silhouette_mask / _is_cutout / _draw_flow delegate here unchanged in behaviour.
# ══════════════════════════════════════════════════════════════════════════════

# A WHITE stamp of a sprite's shape is built at most this big (see silhouette_mask).
const MASK_MAX_PX := 128

static var _tex_cache: Dictionary = {}
static var _mask_cache: Dictionary = {}    # sprite path -> white stamp of its shape
static var _cutout_cache: Dictionary = {}  # sprite path -> is it a cut-out?

static func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex_cache[path] = t
	return t

static func biome_slug(biome: int) -> String:
	return RunMapScreen.BACKDROP_ORDER[maxi(0, biome) % RunMapScreen.BACKDROP_ORDER.size()]

# The decade's painted plate - the same one the map and the arena strips use.
static func backdrop(biome: int) -> Texture2D:
	return tex("%s%s_backdrop.png" % [RunMapScreen.BACKDROP_DIR, biome_slug(biome)])

static func tier_color(tier: int) -> Color:
	return RunMapScreen.TIER_COLORS[clampi(tier, 0, RunMapScreen.TIER_COLORS.size() - 1)]

# The drawn emblem for a non-fight stop (event / merchant / camp / start), with
# the map's per-biome start override. null when the art isn't there.
static func stop_emblem(type: int, biome: int) -> Texture2D:
	var slug: String = String(RunMapScreen.ICON_SLUGS.get(type, ""))
	if slug == "":
		return null
	if slug == "node_start":
		var bespoke := tex("%s%s_%s.png" % [RunMapScreen.ICON_DIR, slug, biome_slug(biome)])
		if bespoke:
			return bespoke
	return tex("%s%s.png" % [RunMapScreen.ICON_DIR, slug])

static func glyph(type: int) -> String:
	return String(RunMapScreen.GLYPHS.get(type, "?"))

# A fight's creature, only when it is a cut-out (full-bleed boss plates are not -
# drawn dark they made solid bars; the map falls back to its glyph for them).
static func creature(path: String) -> Texture2D:
	var t := tex(path)
	return t if t != null and is_cutout(t) else null

# A WHITE stamp of a sprite's shape, so modulate can flood it with a tier colour
# instead of multiplying into the sprite's own paint. Shrunk to MASK_MAX_PX first:
# boss plates are 1408x768 and are drawn at ~90 px. Cached per resource path.
static func silhouette_mask(t: Texture2D) -> Texture2D:
	var key: String = t.resource_path
	if key != "" and _mask_cache.has(key):
		return _mask_cache[key]
	var out: Texture2D = null
	var src: Image = t.get_image()
	if src != null:
		# Never mutate the texture's own image - other screens draw from it.
		var img := Image.new()
		img.copy_from(src)
		if not img.is_compressed() or img.decompress() == OK:
			var longest: int = maxi(img.get_width(), img.get_height())
			if longest > MASK_MAX_PX:
				var k: float = float(MASK_MAX_PX) / float(longest)
				img.resize(maxi(1, int(img.get_width() * k)),
					maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
			img.convert(Image.FORMAT_RGBA8)
			for y in range(img.get_height()):
				for x in range(img.get_width()):
					img.set_pixel(x, y, Color(1, 1, 1, img.get_pixel(x, y).a))
			out = ImageTexture.create_from_image(img)
	if key != "":
		_mask_cache[key] = out
	return out

# Cut-out creature or full-bleed painted plate? Every cut-out in the project reads
# alpha 0 at all four corners; a plate is opaque there.
static func is_cutout(t: Texture2D) -> bool:
	var key: String = t.resource_path
	if key != "" and _cutout_cache.has(key):
		return bool(_cutout_cache[key])
	var ok: bool = true
	var img: Image = t.get_image()
	if img == null:
		ok = false
	else:
		# Imported textures usually arrive VRAM-compressed; get_pixel on one is
		# garbage. Decompress a copy or decline to guess.
		if img.is_compressed() and img.decompress() != OK:
			ok = false
		else:
			var w: int = img.get_width()
			var h: int = img.get_height()
			for p: Vector2i in [Vector2i(0, 0), Vector2i(w - 1, 0),
					Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
				if img.get_pixelv(p).a > 0.06:
					ok = false
					break
	if key != "":
		_cutout_cache[key] = ok
	return ok

# Dashes marching along a polyline, measured by ARC LENGTH so their spacing is
# even however the curve bends. Call from inside `ci`'s own draw.
static func draw_flow(ci: CanvasItem, pts: PackedVector2Array, phase: float, col: Color,
		width: float, dash: float = RunMapScreen.FLOW_DASH, gap: float = RunMapScreen.FLOW_GAP) -> void:
	var period: float = dash + gap
	var s: float = 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if seg <= 0.001:
			continue
		var d: float = 0.0
		while d < seg:
			var local: float = fposmod(s + d - phase, period)
			var dashing: bool = local < dash
			var step: float = maxf(0.01, (dash - local) if dashing else (period - local))
			var d2: float = minf(seg, d + step)
			if dashing:
				ci.draw_line(a.lerp(b, d / seg), a.lerp(b, d2 / seg), col, width, true)
			d = d2
		s += seg

# A creature drawn the map's way: the white stamp flooded with `ink` over a thin
# dark outline. Returns false when there is no usable stamp (caller falls back).
static func draw_creature(ci: CanvasItem, t: Texture2D, centre: Vector2, fit: Vector2,
		ink: Color, outline_alpha: float, transform_scale: Vector2 = Vector2.ONE) -> bool:
	var mask := silhouette_mask(t)
	if mask == null:
		return false
	var aspect: float = t.get_width() / maxf(1.0, float(t.get_height()))
	var sh: float = minf(fit.y, fit.x / maxf(0.01, aspect))
	var size := Vector2(sh * aspect, sh) * transform_scale
	var body := Rect2(centre - size * 0.5, size)
	var line := Color(0.03, 0.03, 0.05, outline_alpha)
	for o in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		ci.draw_texture_rect(mask, Rect2(body.position + o, body.size), false, line)
	ci.draw_texture_rect(mask, body, false, ink)
	return true
