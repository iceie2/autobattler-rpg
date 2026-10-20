extends StyleBox
class_name ChamferBox

# A rectangle with its four corners cut at 45 degrees instead of rounded: the
# fantasy-UI "beveled plate" look, for buttons and list rows that must NOT read
# as pills. StyleBoxFlat can only round corners, hence a small custom StyleBox.
#
#   fill / border / border_width   the plate and its outline
#   cut                            corner cut in px (3-6 keeps the pixel-art feel)
#   highlight / shadow             1px inner edge light (top) and dark (bottom):
#                                  the bevel that makes a plate look raised
#   glow                           optional 2px outer halo (hover / selected)
#
# Set content margins with set_content_margin_all() like any StyleBox.

var fill: Color = Color(0.1, 0.1, 0.15)
var border: Color = Color(0.3, 0.28, 0.4)
var border_width: float = 2.0
var cut: float = 4.0
var highlight: Color = Color(0, 0, 0, 0)
var shadow: Color = Color(0, 0, 0, 0)
var glow: Color = Color(0, 0, 0, 0)
# Outline only (focus rings): the border is stroked, the middle stays clear.
var hollow: bool = false

static func make(p_fill: Color, p_border: Color, p_cut: float = 4.0, p_border_width: float = 2.0,
		p_highlight: Color = Color(0, 0, 0, 0), p_shadow: Color = Color(0, 0, 0, 0),
		p_glow: Color = Color(0, 0, 0, 0)) -> ChamferBox:
	var b := ChamferBox.new()
	b.fill = p_fill
	b.border = p_border
	b.cut = p_cut
	b.border_width = p_border_width
	b.highlight = p_highlight
	b.shadow = p_shadow
	b.glow = p_glow
	b.set_content_margin_all(8.0)
	return b

func _draw(ci: RID, rect: Rect2) -> void:
	if hollow:
		var r := rect.grow(-border_width * 0.5)
		var pts := _points(r, cut)
		pts.append(pts[0])
		RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([border]), border_width)
		return
	if glow.a > 0.0:
		_poly(ci, rect.grow(2.0), cut + 2.0, glow)
	_poly(ci, rect, cut, border)
	var inner := rect.grow(-border_width)
	var inner_cut := maxf(cut - border_width * 0.5, 1.0)
	_poly(ci, inner, inner_cut, fill)
	if highlight.a > 0.0:
		RenderingServer.canvas_item_add_line(ci,
			Vector2(inner.position.x + inner_cut, inner.position.y + 0.5),
			Vector2(inner.end.x - inner_cut, inner.position.y + 0.5), highlight, 1.0)
	if shadow.a > 0.0:
		RenderingServer.canvas_item_add_line(ci,
			Vector2(inner.position.x + inner_cut, inner.end.y - 0.5),
			Vector2(inner.end.x - inner_cut, inner.end.y - 0.5), shadow, 1.0)

func _poly(ci: RID, r: Rect2, c: float, col: Color) -> void:
	RenderingServer.canvas_item_add_polygon(ci, _points(r, c), PackedColorArray([col]))

func _points(r: Rect2, c: float) -> PackedVector2Array:
	c = minf(c, minf(r.size.x, r.size.y) * 0.5)
	return PackedVector2Array([
		Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y),
		Vector2(r.end.x, r.position.y + c), Vector2(r.end.x, r.end.y - c),
		Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c)])
