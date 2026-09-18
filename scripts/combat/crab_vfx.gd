extends Node2D
class_name CrabVFX

# The Crystal Crab's visual language: FACETED MINERAL PLATES.
# Hard straight edges and flat facets — deliberately unlike every soft/organic
# effect so far (the Slime's droplets, the Rat's motes, the Phoenix's sparks).
#
# DELIBERATE DEVIATION, flagged for review: Crystalline Shell still applies
# INSTANTLY, against the standing "move away from instant" direction. It is a
# defensive SELF-buff shared by four mobs (Skeleton / Stone Golem / Crystal Crab
# / Coral Husk); adding a wind-up would be a real unrequested nerf to all four,
# since the shield would arrive later than it does today. What was actually
# missing is the PERSISTENT half: a shielded crab looked identical to an
# unshielded one, and the shield breaking was silent. Both are fixed here.

enum Mode { SHELL_FORM, SHELL_ACTIVE, SHELL_BREAK }

const CRYSTAL := Color(0.52, 0.84, 0.86)
const DEEP := Color(0.12, 0.28, 0.34)
const FACET := Color(0.86, 0.98, 1.0)

var mode: Mode = Mode.SHELL_FORM
var elapsed := 0.0
var lifetime := 0.5
var host = null
var reach := 96.0
var strength := 1.0          # SHELL_ACTIVE: shield / max_shield seen, 0..1
var _t := 0.0

func setup_on(kind: Mode, unit, size: float, life: float) -> void:
	mode = kind
	host = unit
	reach = size
	lifetime = life
	z_index = 3
	queue_redraw()

func set_strength(v: float) -> void:
	strength = clampf(v, 0.0, 1.0)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	_t += delta
	if host != null:
		if not is_instance_valid(host):
			queue_free()
			return
		global_position = host.global_position
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()

# A ring of flat facets — the shell. `n` plates, each a short chord, so the
# silhouette reads as cut stone rather than a smooth bubble.
func _facets(r: float, n: int, phase: float, col: Color, w: float) -> void:
	for i in range(n):
		var a0: float = phase + float(i) * TAU / float(n)
		var a1: float = a0 + TAU / float(n) * 0.72
		draw_line(Vector2(cos(a0), sin(a0)) * r, Vector2(cos(a1), sin(a1)) * r, col, w)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.SHELL_FORM:   _draw_form(t)
		Mode.SHELL_ACTIVE: _draw_active()
		Mode.SHELL_BREAK:  _draw_break(t)

# ── Plates slam shut around the body ───────────────────────────────────────
func _draw_form(t: float) -> void:
	var r: float = reach * 0.5
	# Plates fly IN from outside and lock at the shell radius.
	var rr: float = lerp(r * 1.5, r * 0.82, t)
	draw_circle(Vector2.ZERO, rr, Color(CRYSTAL.r, CRYSTAL.g, CRYSTAL.b, 0.10 * t))
	_facets(rr, 8, _t * 0.6, Color(CRYSTAL.r, CRYSTAL.g, CRYSTAL.b, 0.45 + 0.5 * t), 3.4)
	_facets(rr * 0.96, 8, _t * 0.6 + 0.2, Color(DEEP.r, DEEP.g, DEEP.b, 0.55 * t), 2.0)
	# Lock-in flash on the last beat.
	if t > 0.75:
		var f: float = (t - 0.75) / 0.25
		draw_arc(Vector2.ZERO, r * 0.82, 0.0, TAU, 32,
			Color(FACET.r, FACET.g, FACET.b, 0.8 * (1.0 - f)), 3.0)

# ── Persistent: this crab is currently shelled ─────────────────────────────
# The one real gap. A shielded crab was visually identical to an unshielded one
# — the only tell was the health bar's shield segment. Kept thin and hugging the
# silhouette so it never obscures the body or the bar.
func _draw_active() -> void:
	if strength <= 0.0:
		return
	var r: float = reach * 0.5 * 0.82
	var shimmer: float = 0.5 + 0.5 * sin(_t * 2.4)
	# Thickness and brightness track how much shield is LEFT, so the plates
	# visibly thin out as it is chipped away.
	var a: float = 0.28 + 0.42 * strength
	draw_circle(Vector2.ZERO, r, Color(CRYSTAL.r, CRYSTAL.g, CRYSTAL.b, 0.07 * strength))
	_facets(r, 8, _t * 0.25, Color(CRYSTAL.r, CRYSTAL.g, CRYSTAL.b, a), 2.0 + 2.0 * strength)
	_facets(r * 0.93, 8, -_t * 0.18, Color(DEEP.r, DEEP.g, DEEP.b, a * 0.7), 1.6)
	# A highlight travelling around the rim — reads as polished mineral.
	var ha: float = _t * 1.1
	draw_line(Vector2(cos(ha), sin(ha)) * r * 0.97,
		Vector2(cos(ha + 0.5), sin(ha + 0.5)) * r * 0.97,
		Color(FACET.r, FACET.g, FACET.b, (0.35 + 0.35 * shimmer) * strength), 3.0)

# ── The shell finally gives ────────────────────────────────────────────────
# Shield hitting zero was completely silent; this is the payoff for chewing
# through it.
func _draw_break(t: float) -> void:
	var fade: float = 1.0 - t
	var r: float = reach * 0.5 * 0.82
	# Plates shatter outward as discrete shards, not a soft puff.
	for i in range(10):
		var a: float = float(i) * TAU / 10.0 + 0.2
		var d := Vector2(cos(a), sin(a))
		var p: Vector2 = d * r * (1.0 + 0.9 * t)
		var tip: Vector2 = p + d * (7.0 + 5.0 * t)
		draw_line(p, tip, Color(DEEP.r, DEEP.g, DEEP.b, 0.9 * fade), 4.5 * fade + 1.0)
		draw_line(p, tip, Color(CRYSTAL.r, CRYSTAL.g, CRYSTAL.b, 0.95 * fade), 2.4 * fade + 0.6)
	draw_arc(Vector2.ZERO, r * (1.0 + 0.6 * t), 0.0, TAU, 28,
		Color(FACET.r, FACET.g, FACET.b, 0.7 * fade), 2.6 * fade + 0.8)
