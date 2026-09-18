extends Node2D
class_name ArenaOverlay

# Full-board persistent visual state layer — closes the "0/3 reads" gap named
# in BOSS_SPECTACLE_PLAN.md §2e (a boss state like Skyrender's wind window has
# no class that can draw it: SkillEffect/TexturedSkillEffect are point-sized
# and one-shot, StormHazard/KhaganArenaOverlay are local rings). This is the
# board-sized, code-drawn equivalent, sized to BackgroundLayer's grid
# (990x990) and parented the same way KhaganArenaOverlay is — a child of
# skill_effect_container, which already sits at the grid's local origin (see
# AutoBattleManager._spawn_khagan_overlay_if_present).
#
# One instance per battle, owned by AutoBattleManager, spawned unconditionally
# in start_battle() and freed in end_battle() — invisible (alpha 0) whenever
# no boss state is active, so it costs nothing for encounters that never use
# it. States are fire-and-forget: fade_in(state) / fade_out(), both idempotent
# and tween-driven.

const BOARD_W := 990.0
const BOARD_H := 990.0
const FADE_TIME := 0.5
const REDRAW_INTERVAL := 1.0 / 30.0

const STREAK_COUNT := 14
const STREAK_SPEED := 640.0        # px/s, left-to-right
const STREAK_LEN := 90.0
const STREAK_THICKNESS := 2.0

# Per-state visual recipe. Only "windswept" (Skyrender aloft) is used today;
# the dictionary shape exists because BOSS_SPECTACLE_PLAN.md §2e already names
# the next three states (flooded, molten, charged) with this same
# tint+streak structure — adding one is a new entry here, not new code.
const STATES := {
	"windswept": {
		"tint": Color(0.55, 0.6, 0.65, 0.16),
		"streak_color": Color(0.85, 0.9, 0.95, 0.55),
	},
}

var _state: String = ""
var _alpha: float = 0.0            # master fade, tweened
var _streak_t: float = 0.0
var _redraw_accum: float = 0.0
var _streak_offsets: Array = []    # per-streak phase so they don't move in lockstep

func _ready() -> void:
	z_index = 0   # under units (z=1); ties with BackgroundLayer/skill_effect_container
	              # broken by tree order, same reasoning as KhaganArenaOverlay.setup().
	for i in range(STREAK_COUNT):
		_streak_offsets.append(float(i) / float(STREAK_COUNT))

func fade_in(state: String) -> void:
	if not STATES.has(state):
		push_warning("ArenaOverlay.fade_in: unknown state '%s'" % state)
		return
	if _state == state and _alpha >= 1.0:
		return   # idempotent — already fully in this state
	_state = state
	var t := create_tween()
	t.tween_method(_set_alpha, _alpha, 1.0, FADE_TIME)

func fade_out() -> void:
	if _state == "" and _alpha <= 0.0:
		return   # idempotent — no-op if already off
	var t := create_tween()
	t.tween_method(_set_alpha, _alpha, 0.0, FADE_TIME)
	t.tween_callback(func(): _state = "")

func _set_alpha(v: float) -> void:
	_alpha = v
	queue_redraw()

func _process(delta: float) -> void:
	if _alpha <= 0.0:
		return
	_streak_t += delta
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()

func _draw() -> void:
	if _alpha <= 0.0 or _state == "" or not STATES.has(_state):
		return
	var recipe: Dictionary = STATES[_state]

	var tint: Color = recipe["tint"]
	draw_rect(Rect2(0.0, 0.0, BOARD_W, BOARD_H), Color(tint.r, tint.g, tint.b, tint.a * _alpha), true)

	var streak_col: Color = recipe["streak_color"]
	var col := Color(streak_col.r, streak_col.g, streak_col.b, streak_col.a * _alpha)
	for phase in _streak_offsets:
		var row: float = phase * BOARD_H
		var x: float = fmod((_streak_t * STREAK_SPEED) + phase * BOARD_W * 3.0, BOARD_W + STREAK_LEN) - STREAK_LEN
		draw_line(Vector2(x, row), Vector2(x + STREAK_LEN, row), col, STREAK_THICKNESS)
