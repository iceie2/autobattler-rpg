extends Node2D

# Arena art prep — run this on each decade's raw generated art to produce the
# game-ready files BackgroundLayer actually loads. Raw sources are left
# untouched; output goes to <range>/ready/.
#
#   1. Set DECADE below. Name the raw files by PROP KIND — grass_1, grass_2,
#      flower_1, branch_1, dirt_1, rock_1 … (kinds come from
#      BackgroundLayer.PROP_KINDS) and the base tile `tile` or anything
#      containing "Gemini_Generated". Everything else is discovered.
#   2. Run:  godot --path . scenes/tools/arena_art_prep.tscn
#   3. Run:  godot --headless --path . --import      (so Godot imports the new
#            PNGs — until it does, load() can't see them)
#
# No code change is needed to add a decade: BackgroundLayer probes
# <kind>_1..<kind>_8 per decade folder and uses whatever exists.
#
# Three jobs, all of which caused visible bugs when missing:
#  1. Strip Gemini's sparkle watermark. It sits in the lower-right of every
#     generated image, and on a tiled base texture it repeats across the whole
#     board (4 evenly-spaced sparkles at the 512px tile period).
#  2. Key the flat magenta background out of the decals into real alpha, with
#     spill suppression so anti-aliased edges don't keep a pink fringe.
#  3. Downscale to sane runtime sizes (2048² RGBA is ~16MB of VRAM each).

const DECADE := "1-10"

const SRC := "res://assets/UI/arena/" + DECADE + "/"
const OUT := "res://assets/UI/arena/" + DECADE + "/ready/"

# A file is treated as the BASE TILE if its name is tile.png or still has the
# raw generator name; everything else in the folder is treated as a decal.
const BASE_HINTS := ["tile", "Gemini_Generated"]

func _scan() -> Dictionary:
	var out := { "base": "", "decals": [] }
	var dir := DirAccess.open(ProjectSettings.globalize_path(SRC))
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.to_lower().ends_with(".png") or f.ends_with(".import"):
			continue
		var is_base := false
		for hint in BASE_HINTS:
			if f.contains(hint):
				is_base = true
		if is_base:
			out["base"] = f
		else:
			out["decals"].append(f.get_basename())
	out["decals"].sort()
	return out

const KEY := Vector3(1.0, 0.0, 1.0)   # magenta #FF00FF
const FULL_CUT := 0.30                # <= this distance from magenta = transparent
const SOFT_CUT := 0.62                # ramp to opaque by here

# Colour detection found the watermark at a consistent (1752,1752) 112x112 in
# these 2048² generations, so when the colour test misses it (it does on the
# lower-contrast files) fall back to that spot as a fraction of image size.
# The decals are centred art, so this corner is background either way.
const WM_POS_FRAC  := 0.849
const WM_SIZE_FRAC := 0.070

func _fallback_watermark(img: Image) -> Rect2i:
	var w := img.get_width()
	var p := int(w * WM_POS_FRAC)
	var s := int(w * WM_SIZE_FRAC)
	return Rect2i(p, p, min(s, w - p), min(s, w - p))

# The watermark is a light, desaturated glyph in the lower-right. Its exact
# position shifts between generations, so find it by colour rather than
# hardcoding a box. Thresholds come from sampling the actual files, NOT from
# guesswork — an earlier guess of v>0.72 sat just above the real value (the
# watermark over grass only reaches v≈0.69) and silently detected nothing.
#
# `on_magenta` picks the test: over flat magenta the glyph is a whitish-pink
# far less saturated than the s≈0.90 background; over grass it is simply the
# brightest, most desaturated thing in the region.
func _find_watermark(img: Image, on_magenta: bool) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(w * 0.60)
	var y0 := int(h * 0.60)

	var peak := 0.0
	if not on_magenta:
		for y in range(y0, h):
			for x in range(x0, w):
				var c := img.get_pixel(x, y)
				if c.s < 0.40:
					peak = max(peak, c.v)
		if peak < 0.55:
			return Rect2i(0, 0, 0, 0)

	var minx := w
	var miny := h
	var maxx := -1
	var maxy := -1
	for y in range(y0, h):
		for x in range(x0, w):
			var c := img.get_pixel(x, y)
			var hit := false
			if on_magenta:
				# whitish-pink: bright, both r and b high (so not the green
				# art), and clearly less saturated than pure magenta
				hit = c.v > 0.85 and c.s < 0.80 and c.r > 0.70 and c.b > 0.70
			else:
				hit = c.s < 0.40 and c.v >= peak - 0.05
			if hit:
				minx = min(minx, x); miny = min(miny, y)
				maxx = max(maxx, x); maxy = max(maxy, y)
	if maxx < 0:
		return Rect2i(0, 0, 0, 0)
	var pad := 8
	minx = max(0, minx - pad); miny = max(0, miny - pad)
	maxx = min(w - 1, maxx + pad); maxy = min(h - 1, maxy + pad)
	var box := Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)
	# Sanity clamp: a runaway box means the test matched real art, so bail out
	# rather than clone-stamping over a large chunk of the image.
	if box.size.x > int(w * 0.28) or box.size.y > int(h * 0.28):
		return Rect2i(0, 0, 0, 0)
	return box

# Base texture must stay seamless, so the watermark is covered by cloning a
# clean block from elsewhere in the image rather than cropped out.
func _patch(img: Image, box: Rect2i) -> void:
	var from := Rect2i(box.position - Vector2i(box.size.x + 40, 0), box.size)
	if from.position.x < 0:
		from.position.x = box.position.x + box.size.x + 40
	img.blit_rect(img, from, box.position)

func _erase(img: Image, box: Rect2i) -> void:
	for y in range(box.position.y, box.position.y + box.size.y):
		for x in range(box.position.x, box.position.x + box.size.x):
			img.set_pixel(x, y, Color(1, 0, 1, 1))   # back to key colour

func _key_magenta(img: Image) -> float:
	# Key at 512 rather than the native 2048: 4.2M GDScript pixel ops per file
	# is slow, and keying *after* the final downscale would blend magenta into
	# the art and leave a hard pink halo.
	img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var cut := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var d := Vector3(c.r, c.g, c.b).distance_to(KEY)
			if d <= FULL_CUT:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				cut += 1
				continue
			if d < SOFT_CUT:
				var a := (d - FULL_CUT) / (SOFT_CUT - FULL_CUT)
				# Spill suppression: a pinkish edge pixel has r and b above g;
				# pull them toward g so the fringe reads neutral, not pink.
				var g := c.g
				var r2: float = min(c.r, g + (c.r - g) * a)
				var b2: float = min(c.b, g + (c.b - g) * a)
				img.set_pixel(x, y, Color(r2, g, b2, a))
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	return 100.0 * float(cut) / (512.0 * 512.0)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	var found := _scan()
	var decals: Array = found["decals"]
	var base_src: String = found["base"]
	print("== %s: %d decal(s), base %s ==" % [DECADE, decals.size(),
		("MISSING" if base_src == "" else base_src)])

	for name in decals:
		var img := Image.load_from_file(ProjectSettings.globalize_path(SRC + name + ".png"))
		if img == null:
			print("MISSING  ", name)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var wm := _find_watermark(img, true)
		var how := "detected"
		if wm.size.x == 0:
			wm = _fallback_watermark(img)
			how = "fallback"
		_erase(img, wm)
		var pct := _key_magenta(img)
		img.save_png(OUT + name + ".png")
		print("%-10s wm %-9s %-26s keyed %5.1f%%  -> ready/%s.png 256px"
			% [name, how, str(wm), pct, name])

	if base_src == "":
		get_tree().quit()
		return
	var base := Image.load_from_file(ProjectSettings.globalize_path(SRC + base_src))
	if base == null:
		print("could not read base tile ", base_src)
		get_tree().quit()
		return
	base.convert(Image.FORMAT_RGBA8)
	var bwm := _find_watermark(base, false)
	var bhow := "detected"
	if bwm.size.x == 0:
		bwm = _fallback_watermark(base)
		bhow = "fallback"
	_patch(base, bwm)
	base.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	base.save_png(OUT + "tile.png")
	print("tile       wm %-9s %-26s patched         -> ready/tile.png 512px"
		% [bhow, str(bwm)])
	get_tree().quit()
