extends RefCounted
class_name GradeRoll
# ══════════════════════════════════════════════════════════════════════════════
# Reusable "slot machine" reveal animation (2026-07-21, expanded same day).
#
# Cycles ANY visual (a letter, a stat number, a portrait texture) through
# random candidates, decelerating like a real slot reel, before landing on the
# actual rolled value. Pure Godot — no new art: grade letters are plain
# colored text everywhere already, and portrait "cycling" just swaps between
# textures that already exist (hero sprites), so this is 100% animation code.
#
# spin() is the generic engine — it doesn't know what a "grade" or "hero" is,
# it just repeatedly calls a caller-supplied `paint` callback with pool items,
# decelerating, then calls it once more with the real final value. roll() and
# roll_texture() are thin convenience wrappers around it for the two most
# common cases (a colored text label, a texture swap); anything more bespoke
# (e.g. hero_shop's combined portrait+name+element reveal, where all three
# have to change in lockstep on the same tick) should call spin() directly
# with its own paint closure — see hero_shop.gd for that pattern.
# ══════════════════════════════════════════════════════════════════════════════

const GRADE_SEQUENCE := ["F", "D", "C", "B", "A", "S"]

# ── Generic engine ────────────────────────────────────────────────────────────
# anchor:  any Node whose validity gates the whole coroutine (usually the node
#          `paint` writes into) — spin() bails cleanly if it's freed mid-spin.
# pool:    candidate values flashed at random while spinning (any type; empty
#          pool just holds on final_value the whole time, still useful for a
#          delayed reveal with a punch).
# paint:   Callable(value) — do whatever's needed to display one candidate.
# punch:   optional Callable() fired once landed, for a scale-punch/flash/etc.
static func spin(anchor: Object, pool: Array, final_value, paint: Callable,
		delay: float = 0.0, ticks: int = 14,
		start_interval: float = 0.04, growth: float = 1.15,
		punch: Callable = Callable()) -> void:
	if not is_instance_valid(anchor):
		return
	# The anchor is typically still an orphan (part of a card not yet
	# add_child()'d into the tree) when spin() is first called, so
	# anchor.get_tree() would be null — Engine.get_main_loop() works
	# regardless of tree membership. By the time `punch` needs a real
	# tree-bound node (create_tween()), several ticks have elapsed and the
	# card has long since entered the tree.
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return

	# Paint a placeholder immediately so a staggered reel (delay > 0) reads as
	# "about to spin" during its wait, not blank/broken.
	if pool.size() > 0:
		paint.call(pool[randi() % pool.size()])
	if delay > 0.0:
		await tree.create_timer(delay).timeout
		if not is_instance_valid(anchor):
			return

	var interval := start_interval
	for i in range(ticks):
		if not is_instance_valid(anchor):
			return
		# Last tick always shows the real value so the reel "settles" onto it
		# rather than hard-cutting from a random flicker.
		var v = final_value if (i >= ticks - 1 or pool.is_empty()) else pool[randi() % pool.size()]
		paint.call(v)
		await tree.create_timer(interval).timeout
		interval *= growth

	if not is_instance_valid(anchor):
		return
	paint.call(final_value)
	if punch.is_valid():
		punch.call()

# ── Convenience: colored text reel (grade letters, growth %, any label) ───────
static func roll(label: Label, final_grade: String, color_fn: Callable,
		delay: float = 0.0, ticks: int = 14,
		start_interval: float = 0.04, growth: float = 1.15) -> void:
	var paint := func(g: String) -> void:
		label.text = g
		label.add_theme_color_override("font_color", color_fn.call(g))
	var punch := func() -> void: _land_punch(label)
	await spin(label, GRADE_SEQUENCE, final_grade, paint, delay, ticks, start_interval, growth, punch)

# ── Convenience: texture reel (a portrait cycling through other sprites) ──────
static func roll_texture(rect: TextureRect, pool: Array, final_tex: Texture2D,
		delay: float = 0.0, ticks: int = 14,
		start_interval: float = 0.04, growth: float = 1.15) -> void:
	var paint := func(tex: Texture2D) -> void: rect.texture = tex
	var punch := func() -> void: _land_punch(rect)
	await spin(rect, pool, final_tex, paint, delay, ticks, start_interval, growth, punch)

# Small overshoot scale-punch the instant a reel lands, so the stop reads as
# an event instead of the value quietly stopping. Public so bespoke spin()
# call sites (hero_shop's combined portrait/name/element reel) can reuse it.
static func _land_punch(ctrl: Control) -> void:
	ctrl.pivot_offset = ctrl.size * 0.5
	var base_scale: Vector2 = ctrl.scale
	var tw := ctrl.create_tween()
	tw.tween_property(ctrl, "scale", base_scale * 1.4, 0.09) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "scale", base_scale, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

static func land_punch(ctrl: Control) -> void:
	_land_punch(ctrl)
