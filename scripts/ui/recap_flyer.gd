class_name RecapFlyer
extends Control
# ══════════════════════════════════════════════════════════════════════════════
# Encounter icons "bopped" off the route and FALLING INTO the defeat parade
# (2026-10-07, owner: "when it gets bopped off it falls into" the strip).
#
# A full-screen overlay above the route, parade and chart, so an icon can travel
# from its route node down into its wave's place in the parade. The screen owns
# timing and positions (it knows where each node is right now and where each
# wave's group sits in the parade); this only draws:
#   squash  SQUASH_T  the icon compresses on its node
#   hold    HOLD_T    a ~50 ms pause
#   fall    FALL_T    bopped up HOP px, then gravity carries it down into the
#                     parade (one parabola: slow over the top, fast at the end),
#                     shrinking and turning a little, with a short fading trail
#                     so the drop reads as motion even in a still frame; it fades
#                     as the wave's sprites appear
# Purely visual: nothing here counts anything. The parade only ever shows
# recorded defeats - the icon is not one of them.
# ══════════════════════════════════════════════════════════════════════════════

const SQUASH_T := 0.07
const HOLD_T := 0.05
const FALL_T := 0.50
const TOTAL_T := SQUASH_T + HOLD_T + FALL_T
const HOP := 56.0                     # px the icon is bopped up before it falls
const TRAIL_STEP := 0.035             # s between trail copies

# [{from: Vector2, to: Vector2, age: float, icon: String, tier: int, r: float}]
# in this control's coordinates. Rebuilt by the screen every frame.
var flights: Array = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

static func landed(age: float) -> bool:
	return age >= TOTAL_T

# Position / scale / rotation / alpha at `age` along the from -> to path.
static func state(from: Vector2, to: Vector2, age: float) -> Dictionary:
	if age < SQUASH_T:
		var k: float = age / SQUASH_T
		return {"pos": from, "scale": Vector2(1.0 + 0.18 * k, 1.0 - 0.28 * k), "rot": 0.0, "alpha": 1.0}
	if age < SQUASH_T + HOLD_T:
		return {"pos": from, "scale": Vector2(1.18, 0.72), "rot": 0.0, "alpha": 1.0}
	var u: float = clampf((age - SQUASH_T - HOLD_T) / FALL_T, 0.0, 1.0)
	var sc: float = lerpf(1.0, 0.42, u)
	return {"pos": arc(from, to, u), "scale": Vector2(sc, sc), "rot": -0.6 * u,
		"alpha": 1.0 - clampf((u - 0.82) / 0.18, 0.0, 1.0)}

# A thrown object's path: x moves evenly, y follows one parabola that rises HOP
# above the start and lands on the target at u = 1.
static func arc(from: Vector2, to: Vector2, u: float) -> Vector2:
	var x: float = lerpf(from.x, to.x, u)
	var dy: float = to.y - from.y
	if dy <= 1.0:
		return Vector2(x, lerpf(from.y, to.y, u) - 4.0 * HOP * u * (1.0 - u))
	var ua: float = (-HOP + sqrt(HOP * HOP + dy * HOP)) / dy     # time of the apex
	var g: float = 2.0 * HOP / (ua * ua)
	return Vector2(x, from.y - g * ua * u + 0.5 * g * u * u)

func _draw() -> void:
	for f in flights:
		var age: float = float(f["age"])
		if age < 0.0 or landed(age):
			continue
		for k in [3, 2, 1]:
			var ga: float = age - float(k) * TRAIL_STEP
			if ga > SQUASH_T + HOLD_T:
				_draw_icon(f, state(f["from"], f["to"], ga), 0.5 - 0.13 * float(k))
		_draw_icon(f, state(f["from"], f["to"], age), 1.0)

func _draw_icon(f: Dictionary, st: Dictionary, fade: float) -> void:
	var r: float = float(f.get("r", 30.0))
	var a: float = float(st["alpha"]) * fade
	var col := MapRouteArt.tier_color(int(f.get("tier", 0)))
	col.a = a
	draw_set_transform(st["pos"], float(st["rot"]), st["scale"])
	var icon := MapRouteArt.creature(String(f.get("icon", "")))
	var drawn := false
	if icon:
		drawn = MapRouteArt.draw_creature(self, icon, Vector2.ZERO, Vector2(r * 2.3, r * 2.1), col, 0.9 * a)
	if not drawn:
		draw_circle(Vector2.ZERO, r, Color(col.darkened(0.55), a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
