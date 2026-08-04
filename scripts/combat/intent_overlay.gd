class_name IntentOverlay
extends Node2D

# ── Enemy intent lines (prep phase) ───────────────────────────────────────────
# Draws, for every enemy, an arrow to the hero it will open the fight on, plus a
# count over each hero showing how many enemies are converging on it.
#
# Why this exists: targeting is nearest-enemy (AutoBattleManager._choose_target),
# so in this game GEOMETRY IS THE TARGETING SYSTEM — and it is the player's
# single most powerful lever. Measured on an identical team, formation alone
# swung the win rate from 0% to ~85%, and which formation is correct flips with
# the matchup. None of that was visible: the player dragged units around with no
# way to see what the arrangement actually did. These arrows make the invisible
# rule directly observable, and because the overlay recomputes every frame they
# update live WHILE dragging — you watch five arrows swing onto a hero the moment
# you place them too far forward.
#
# Strictly read-only: it never writes to a unit, never touches battle state, and
# is hidden the instant the battle starts (predictions would be noise once units
# move and taunts/frenzy override the nearest-target rule). Balance-neutral by
# construction.
#
# Deliberately not prescriptive — it reports who is being targeted, never
# suggests a formation. There is no universally correct one.

@export var font: Font = preload("res://assets/Fonts/LeagueGothic-Regular.otf")

const LINE_COLOR      := Color(0.88, 0.32, 0.28, 0.34)   # muted red — many at once must not shout
const LINE_COLOR_HOT  := Color(0.95, 0.45, 0.22, 0.55)   # 3+ attackers converging
const LINE_WIDTH      := 3.0
const HEAD_LEN        := 14.0
const HEAD_HALF_W     := 6.0
const GAP_FROM_UNIT   := 26.0    # keep the arrow off the sprites at both ends
const COUNT_FONT_SIZE := 30
const COUNT_OFFSET    := Vector2(0, -104.0)
const HOT_THRESHOLD   := 3       # attackers on one hero before it reads as "hot"

var enemies: Array = []
var players: Array = []
var battle_manager = null        # AutoBattleManager — reused for the targeting rule
var active: bool = false

func _ready() -> void:
	z_index = 1          # above the grid/backdrop, below units (units sit higher)
	visible = false

func set_active(v: bool) -> void:
	active = v
	visible = v
	queue_redraw()

func _process(_delta: float) -> void:
	# Cheap (enemies × heroes distance checks) and it must track a unit being
	# dragged, which has no completion signal until the drop.
	if active:
		queue_redraw()

# The hero this enemy would open on. Delegates to the manager so the prediction
# can never drift from the live rule. Only the nearest-target base case applies
# here: taunt / frenzy / Lordee-chase overrides in _choose_target all need combat
# state that doesn't exist yet during prep.
func _predicted_target(enemy) -> Node:
	if battle_manager == null or not is_instance_valid(battle_manager):
		return null
	return battle_manager.find_nearest_enemy(enemy, players)

func _draw() -> void:
	if not active:
		return
	var live_players: Array = []
	for p in players:
		if p and is_instance_valid(p) and not p.is_dragging:
			live_players.append(p)
	if live_players.is_empty():
		return

	# Pass 1 — resolve every enemy's target and tally converging attackers.
	var pairs: Array = []
	var counts: Dictionary = {}
	for e in enemies:
		if not (e and is_instance_valid(e)):
			continue
		var t = _predicted_target(e)
		if t == null or not is_instance_valid(t):
			continue
		pairs.append([e, t])
		counts[t] = int(counts.get(t, 0)) + 1

	# Pass 2 — arrows, tinted by how crowded their target already is.
	for pair in pairs:
		var hot: bool = int(counts.get(pair[1], 0)) >= HOT_THRESHOLD
		_draw_arrow(pair[0].position, pair[1].position,
				LINE_COLOR_HOT if hot else LINE_COLOR)

	# Pass 3 — attacker count over each targeted hero. This is the number that
	# actually drives a decision ("four of them open on Riot"), so it outranks
	# the arrows visually.
	for t in counts:
		if not is_instance_valid(t):
			continue
		var n: int = int(counts[t])
		var hot: bool = n >= HOT_THRESHOLD
		var col: Color = Color(1.0, 0.55, 0.25, 0.95) if hot else Color(0.95, 0.85, 0.70, 0.9)
		var txt: String = str(n)
		var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE).x
		var at: Vector2 = t.position + COUNT_OFFSET - Vector2(w * 0.5, 0)
		# Cheap outline so the digit stays legible over any sprite.
		for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
			draw_string(font, at + o, txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
					COUNT_FONT_SIZE, Color(0, 0, 0, 0.85))
		draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE, col)

func _draw_arrow(from: Vector2, to: Vector2, col: Color) -> void:
	var dir: Vector2 = (to - from)
	var dist: float = dir.length()
	if dist <= GAP_FROM_UNIT * 2.0 + HEAD_LEN:
		return                      # adjacent units — an arrow would just be clutter
	dir = dir / dist
	var a: Vector2 = from + dir * GAP_FROM_UNIT
	var b: Vector2 = to - dir * GAP_FROM_UNIT
	var shaft_end: Vector2 = b - dir * HEAD_LEN
	draw_line(a, shaft_end, col, LINE_WIDTH, true)
	var perp: Vector2 = Vector2(-dir.y, dir.x) * HEAD_HALF_W
	draw_colored_polygon(
			PackedVector2Array([b, shaft_end + perp, shaft_end - perp]), col)
