class_name RelicUnlockReveal
extends CanvasLayer

# One "relic unlocked" card. Same toast interface as the merge cards
# (prepare / play / set_speed / done) so MergeToastQueue can carousel them:
# the playing card sits centre, the rest are parked to its right.
#
# 2026-09-30 (owner): unlocks stack on the right like merges do, and a click
# skips to the next one. skip() is what the queue calls on that click.

signal done

const FADE_IN := 0.22
const HOLD := 2.4
const FADE_OUT := 0.32
const SKIP_FADE := 0.14
const WAIT_ALPHA := 0.78   # opacity while parked in the queue

var speed := 1.0

var _panel: PanelContainer
var _tween: Tween
var _skip_requested := false
var _finished := false

func set_speed(s: float) -> void:
	speed = maxf(0.1, s)

# waiting=true: built now but parked (dimmed) until it becomes the centre card.
func prepare(relic: Dictionary, waiting: bool = false) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(420, 390)
	_panel.position = (get_viewport().get_visible_rect().size - _panel.custom_minimum_size) * 0.5
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UITheme.menu_surface_box()
	box.border_color = Relic.grade_color(str(relic.get("grade", "D")))
	box.set_border_width_all(3)
	_panel.add_theme_stylebox_override("panel", box)
	root.add_child(_panel)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(content)
	content.add_child(_label("RELIC UNLOCKED", UITheme.FONT_HEADER))
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(140, 140)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := Relic.icon_path(relic)
	if path != "":
		icon.texture = load(path) as Texture2D
	content.add_child(icon)
	content.add_child(_label(str(relic.get("name", "")), UITheme.FONT_DISPLAY))
	content.add_child(_label("%s GRADE" % relic.get("grade", "D"), UITheme.FONT_HEADER))
	var description := _label(str(relic.get("desc", "")), UITheme.FONT_VALUE)
	UITheme.apply_read_font(description, UITheme.FONT_VALUE)   # prose -> Inter
	description.custom_minimum_size = Vector2(360, 110)
	content.add_child(description)
	_panel.pivot_offset = _panel.custom_minimum_size * 0.5
	_panel.modulate.a = WAIT_ALPHA if waiting else 0.0
	_panel.scale = Vector2.ONE if waiting else Vector2(0.82, 0.82)

func play() -> void:
	if _skip_requested:
		_fade_out_now()
		return
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, FADE_IN / speed)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.32 / speed) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(HOLD / speed)
	_tween.chain().tween_property(_panel, "modulate:a", 0.0, FADE_OUT / speed)
	_tween.chain().tween_callback(_finish)

# A click: stop holding and go straight to the fade-out (then the next card).
# Safe to call before play() — the card then leaves the moment it would start.
func skip() -> void:
	if _finished:
		return
	_skip_requested = true
	if _tween != null and _tween.is_valid():
		_fade_out_now()

func _fade_out_now() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 0.0, SKIP_FADE)
	_tween.tween_callback(_finish)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	done.emit()
	queue_free()

func _label(value: String, size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_font(label, size)
	label.add_theme_color_override("font_color", UITheme.menu_title_color())
	return label
