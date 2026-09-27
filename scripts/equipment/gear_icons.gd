extends RefCounted
class_name GearIcons

# Composite icons for component equipment (icon model, EQUIPMENT_GREEN_PAIRS.md;
# every tier is an OBJECT since 2026-09-26):
#   grey   = the component's item object
#   green  = a crafted object built from its two greys (passive_<key>.png)
#   blue+  = the highest-level passive's object in a tier frame, level pips, and
#            every other passive as a mini object in a rim notch (top, bottom, left)
# Art comes from assets/using/equipment_icons/<key>.png (tools/sprite_pipeline/
# equipment_icons.py). Until a file exists, a placeholder is drawn: the old 64px
# item art for objects, and the passive's two family colours for emblems. Legacy
# items fall through to EquipmentManager.ITEM_ICONS unchanged.

const DIR := "res://assets/using/equipment_icons/"
const SIZE := 64

const FAMILY_COLOR := {
	"HP": Color(0.86, 0.16, 0.22), "ATK": Color(0.93, 0.50, 0.16),
	"Magic": Color(0.62, 0.36, 0.95), "CDR": Color(0.18, 0.70, 0.66),
	"AS": Color(1.0, 0.78, 0.20), "Crit": Color(0.93, 0.93, 0.96),
	"Defense": Color(0.55, 0.58, 0.63), "Regen": Color(0.36, 0.80, 0.30),
}
const COMPONENT_COLOR := {
	"hp": Color(0.86, 0.16, 0.22), "atk": Color(0.93, 0.50, 0.16),
	"magic": Color(0.62, 0.36, 0.95), "cdr": Color(0.18, 0.70, 0.66),
	"aspd": Color(1.0, 0.78, 0.20), "crit": Color(0.93, 0.93, 0.96),
	"res": Color(0.55, 0.58, 0.63), "magic_resist": Color(0.32, 0.30, 0.78),
	"hpregen": Color(0.36, 0.80, 0.30), "manaregen": Color(0.45, 0.72, 1.0),
}
# Placeholder object art for greys (old 64px pack), until grey_<stat>.png lands.
const PLACEHOLDER := {
	"hp": "Ring", "atk": "Sword", "magic": "Staff", "cdr": "Amulet", "aspd": "Gloves",
	"crit": "Bow", "res": "Shield", "magic_resist": "Cloak", "hpregen": "Robe",
	"manaregen": "Boots",
}
const FRAME := {EquipmentItem.Rarity.RARE: "frame_blue", EquipmentItem.Rarity.EPIC: "frame_purple",
	EquipmentItem.Rarity.LEGENDARY: "frame_gold"}
const NOTCH_POS := [Vector2i(32, 5), Vector2i(32, 59), Vector2i(5, 32)]   # top, bottom, left

static var _cache: Dictionary = {}
static var _images: Dictionary = {}

static func icon_for(item: EquipmentItem) -> Texture2D:
	if item == null:
		return null
	if not (item is ComponentEquipmentItem):
		var p: String = EquipmentManager.ITEM_ICONS.get(item.name, "")
		return load(p) as Texture2D if p != "" else null
	var ci := item as ComponentEquipmentItem
	var sig := "%d|%s|%s" % [ci.rarity, str(ComponentEquipmentRules._ordered(ci.passive_levels)),
		str(ci.composition.keys())]
	if _cache.has(sig):
		return _cache[sig]
	var tex := ImageTexture.create_from_image(_compose(ci))
	_cache[sig] = tex
	return tex

# Emblem for one passive (cue pops, merge menu rows). Placeholder if missing.
static func emblem(key: String) -> Texture2D:
	var sig := "emblem|" + key
	if _cache.has(sig):
		return _cache[sig]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	_draw_emblem(img, key, Rect2i(0, 0, SIZE, SIZE))
	var tex := ImageTexture.create_from_image(img)
	_cache[sig] = tex
	return tex

static func _compose(item: ComponentEquipmentItem) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var levels := item.passive_levels
	var center := ComponentEquipmentRules.dominant_passive(levels)
	var inner := Rect2i(8, 8, 48, 48)
	if center == "":
		var fam := ComponentEquipmentRules.dominant_family(item.composition)
		var art: Image = _art("grey_" + fam)
		if art == null:
			art = _legacy(str(PLACEHOLDER.get(fam, "Ring")))
		_fill_rounded(img, Rect2i(4, 4, 56, 56), Color(0.08, 0.08, 0.11))
		if art:
			_blit(img, art, inner)
	else:
		_draw_emblem(img, center, Rect2i(4, 4, 56, 56))
	# Tier frame (art or a drawn rarity border).
	var frame: Image = _art(str(FRAME.get(item.rarity, "")))
	if frame:
		_blit(img, frame, Rect2i(0, 0, SIZE, SIZE))
	else:
		_border(img, item.icon_color, 3 if item.rarity >= EquipmentItem.Rarity.RARE else 2)
	# (No stat badges: since 2026-09-26 a green's art is a crafted object built
	# from its two greys, so the recipe is already visible in the object.)
	# Blue+: level pips for the centre, notches for the rest.
	if item.rarity >= EquipmentItem.Rarity.RARE and center != "":
		var n := int(levels[center])
		for i in range(n):
			_disc(img, Vector2i(SIZE - 10 - i * 7, SIZE - 12), 2, Color(1, 1, 1))
		var slot := 0
		for key in levels:
			if key == center or slot >= NOTCH_POS.size():
				continue
			var pos: Vector2i = NOTCH_POS[slot]
			_disc(img, pos, 8, Color(0.05, 0.05, 0.07))
			_draw_emblem(img, str(key), Rect2i(pos.x - 7, pos.y - 7, 14, 14))
			slot += 1
	return img

# Emblem art, else a placeholder split disc in the passive's two family colours.
static func _draw_emblem(img: Image, key: String, rect: Rect2i) -> void:
	var art: Image = _art("passive_" + key)
	if art:
		_blit(img, art, rect)
		return
	var fams := GearCatalog.families_of(key)
	var a: Color = FAMILY_COLOR.get(fams[0] if fams.size() > 0 else "", Color.WHITE)
	var b: Color = FAMILY_COLOR.get(fams[1] if fams.size() > 1 else "", a)
	var c := rect.get_center()
	var r := int(rect.size.x * 0.42)
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				var px := c + Vector2i(x, y)
				if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height():
					img.set_pixelv(px, a if x < 0 else b)
	# Worksheet number as dots is unreadable; a dark core ring keeps it iconic.
	_ring(img, c, r, Color(0, 0, 0))

static func _art(key: String) -> Image:
	if key == "":
		return null
	if _images.has(key):
		return _images[key]
	var path := DIR + key + ".png"
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
	_images[key] = _norm(img)
	return _images[key]

static func _legacy(name: String) -> Image:
	var key := "legacy|" + name
	if _images.has(key):
		return _images[key]
	var p: String = EquipmentManager.ITEM_ICONS.get(name, "")
	var img: Image = null
	if p != "" and ResourceLoader.exists(p):
		var tex := load(p) as Texture2D
		if tex:
			img = tex.get_image()
	_images[key] = _norm(img)
	return _images[key]

static func _norm(img: Image) -> Image:
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img

static func _blit(dst: Image, src: Image, rect: Rect2i) -> void:
	var s := src.duplicate()
	s.resize(rect.size.x, rect.size.y, Image.INTERPOLATE_BILINEAR)
	dst.blend_rect(s, Rect2i(Vector2i.ZERO, rect.size), rect.position)

static func _fill_rounded(img: Image, rect: Rect2i, col: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var dx := mini(x - rect.position.x, rect.end.x - 1 - x)
			var dy := mini(y - rect.position.y, rect.end.y - 1 - y)
			if dx + dy >= 3:
				img.set_pixel(x, y, col)

static func _border(img: Image, col: Color, w: int) -> void:
	for y in range(SIZE):
		for x in range(SIZE):
			if x < w or y < w or x >= SIZE - w or y >= SIZE - w:
				img.set_pixel(x, y, col)

static func _disc(img: Image, c: Vector2i, r: int, col: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				var p := c + Vector2i(x, y)
				if p.x >= 0 and p.y >= 0 and p.x < SIZE and p.y < SIZE:
					img.set_pixelv(p, col)

static func _ring(img: Image, c: Vector2i, r: int, col: Color) -> void:
	for i in range(64):
		var a := TAU * i / 64.0
		var p := c + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
		if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
			img.set_pixelv(p, col)
