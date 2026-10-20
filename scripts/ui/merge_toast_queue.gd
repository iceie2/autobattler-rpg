extends CanvasLayer
class_name MergeToastQueue

signal toast_started(kind: String)
signal drained   # the last toast has finished and nothing is waiting

# Plays merge toasts (hero + equipment) one after another WITHOUT ever blocking
# the player (owner requests 2026-09-30). The merge itself is instant and already
# applied; the toast is only a celebration, so:
#
#   - clicking the playing card skips it; clicks outside the card still reach
#     the game (every Control is mouse_filter IGNORE);
#   - it is a CAROUSEL of the real toast cards: the merge that is playing sits in
#     the CENTRE; merges that arrive meanwhile are built straight away as the
#     same tall card, parked to its RIGHT (slightly dimmed), one slot each;
#   - when the centre card finishes and fades away, every parked card slides one
#     slot left and the next one starts playing;
#   - the backlog speeds the current toast up (set_speed) so five merges in a
#     row clear in a few seconds instead of half a minute, then eases back to
#     normal speed as the queue drains; a small "2 / 5" counter shows progress
#     for the cards that are off-screen.
#
# Entries hold their own DATA snapshot (never live units): a queued hero may be
# consumed by a later merge before its card plays.

const SLOT_W := 500.0          # centre-to-centre distance between neighbouring cards
const SLIDE_TIME := 0.24
const ARRIVE_TIME := 0.26      # a new card sliding in from the right edge
const ARRIVE_FROM := 140.0
const BACKLOG_SPEEDUP := 0.45  # +45% toast speed per waiting merge
const MAX_SPEEDUP := 2.6
const COUNTER_Y := 330.0       # below the centre card

# Relic-unlock mode (2026-09-30): a second instance of this queue plays the
# end-of-run relic cards. Unlike merges those must be READ, so: no backlog
# speed-up, it sits above every screen, and a click (or Space/Enter/Esc) skips
# to the next card. While it is busy it swallows clicks so the screen under it
# (the game-over Return button) can't be hit mid-reveal.
var toast_layer := 7
var click_to_skip := false
var backlog_speeds := true

var base_speed := 1.0
var active: Node = null
var pending: Array = []        # [{kind, toast}] — the parked cards, next one first

var _root: Control
var _counter: Label
var _batch_total := 0          # merges in the current burst
var _batch_index := 0          # which of them is playing (1-based)
var _hint: Label

func _ready() -> void:
	layer = toast_layer
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never blocks input
	add_child(_root)
	_counter = Label.new()
	UITheme.apply_font(_counter, UITheme.FONT_VALUE)
	_counter.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	_counter.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_counter.add_theme_constant_override("outline_size", 7)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter.visible = false
	_root.add_child(_counter)
	if click_to_skip:
		_root.gui_input.connect(_on_root_input)
		_hint = Label.new()
		_hint.text = "Click to continue"
		UITheme.apply_read_font(_hint, UITheme.FONT_BODY)
		_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92, 0.85))
		_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_hint.add_theme_constant_override("outline_size", 6)
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hint.visible = false
		_root.add_child(_hint)

func is_busy() -> bool:
	return active != null and is_instance_valid(active)

# ── Enqueue ───────────────────────────────────────────────────────────────────
# `info` = MergeResultScreen.info_of(unit) and `after` = snapshot(unit), both
# taken right after the merge; `before` was taken right before it.
func enqueue_hero(info: Dictionary, before: Dictionary, after: Dictionary) -> void:
	var t := MergeResultScreen.new()
	t.layer = toast_layer
	add_child(t)
	var waiting := is_busy()
	t.prepare_data(info, before, after, waiting)
	_push("hero", t, waiting)

func enqueue_equipment(base: ComponentEquipmentItem, other: ComponentEquipmentItem,
		result: ComponentEquipmentItem) -> void:
	var t := EquipmentMergeScreen.new()
	t.layer = toast_layer
	add_child(t)
	var waiting := is_busy()
	t.prepare(base, other, result, waiting)
	_push("equipment", t, waiting)

func enqueue_relic(relic: Dictionary) -> void:
	var t := RelicUnlockReveal.new()
	t.layer = toast_layer
	add_child(t)
	var waiting := is_busy()
	t.prepare(relic, waiting)
	_push("relic", t, waiting)

# Skip the card that is playing; the next one (if any) slides in. Bound to a click.
func skip_current() -> void:
	if active != null and is_instance_valid(active) and active.has_method("skip"):
		active.skip()

func _on_root_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		skip_current()
		_root.accept_event()

func _input(event: InputEvent) -> void:
	if not is_busy():
		return
	if not click_to_skip:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and active.has_method("contains_click") and active.contains_click(event.position):
			skip_current()
			get_viewport().set_input_as_handled()
		return
	var is_skip_key: bool = event is InputEventKey and event.pressed and not event.echo \
		and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]
	if is_skip_key:
		skip_current()
		get_viewport().set_input_as_handled()

# Busy (playing or waiting) -> swallow clicks; idle -> let everything through.
func _update_input_block() -> void:
	if not click_to_skip:
		return
	var busy := is_busy() or not pending.is_empty()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP if busy else Control.MOUSE_FILTER_IGNORE
	if _hint != null:
		_hint.visible = busy
		var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
		_hint.size = Vector2(300, 26)
		_hint.position = Vector2(vp.x * 0.5 - 150.0, vp.y - 70.0)

func _push(kind: String, toast: Node, waiting: bool) -> void:
	if not waiting:
		_batch_total = 1
		_batch_index = 0
		_activate(kind, toast)
		return
	_batch_total += 1
	pending.append({"kind": kind, "toast": toast})
	# Park it one slot beyond the last waiting card, sliding in from further right.
	var slot: float = SLOT_W * pending.size()
	toast.offset = Vector2(slot + ARRIVE_FROM, 0)
	var tw := toast.create_tween()
	tw.tween_property(toast, "offset:x", slot, ARRIVE_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_apply_speed()   # the backlog grew: speed the current toast up right away
	_update_counter()

# ── Playback ──────────────────────────────────────────────────────────────────
# Makes `toast` the centre card: it is (or slides to) offset 0, then plays.
func _activate(kind: String, toast: Node, slide: bool = false) -> void:
	active = toast
	_batch_index += 1
	_update_input_block()
	toast.done.connect(_on_toast_done.bind(toast))
	_apply_speed()
	_update_counter()
	toast_started.emit(kind)
	if not slide:
		toast.play()
		return
	# Everything parked moves one slot left together; the new centre card plays
	# once it has arrived.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(toast, "offset:x", 0.0, SLIDE_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	for i in range(pending.size()):
		tw.tween_property(pending[i]["toast"], "offset:x", SLOT_W * (i + 1), SLIDE_TIME) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	# A click can free this card before its slide finishes. Capture its ID,
	# since capturing the freed node itself makes the lambda fail before its guard.
	var toast_id: int = toast.get_instance_id()
	tw.chain().tween_callback(func() -> void:
		var sliding_toast = instance_from_id(toast_id)
		if is_instance_valid(sliding_toast) and not sliding_toast.is_queued_for_deletion():
			sliding_toast.play())

func _start_next() -> void:
	if pending.is_empty():
		_batch_total = 0
		_batch_index = 0
		_update_counter()
		_update_input_block()
		drained.emit()
		return
	var entry: Dictionary = pending.pop_front()
	_activate(str(entry["kind"]), entry["toast"], true)

func _on_toast_done(toast: Node) -> void:
	if active == toast:
		active = null
	_start_next()

func _process(_delta: float) -> void:
	if is_busy():
		_apply_speed()

# The backlog drives the speed live, so it eases back down as the queue drains.
func _apply_speed() -> void:
	var s: float = base_speed * (minf(1.0 + BACKLOG_SPEEDUP * pending.size(), MAX_SPEEDUP) if backlog_speeds else 1.0)
	if active != null and active.has_method("set_speed"):
		active.set_speed(s)

func _update_counter() -> void:
	_counter.visible = _batch_total > 1
	if not _counter.visible:
		return
	_counter.text = "%d / %d" % [_batch_index, _batch_total]
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_counter.size = Vector2(160, 30)
	_counter.position = Vector2(vp.x * 0.5 - 80.0, vp.y * 0.5 + COUNTER_Y)
