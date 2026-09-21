extends CanvasLayer
class_name RunHistoryScreen
# Main-menu RUN HISTORY / STATS screen (2026-07-17). Aggregate header + a
# scrollable list of past runs, newest first. Reads RunHistory.

signal closed()

var _panel: Panel
var _stats_lbl: Label
var _list: VBoxContainer
var _export_lbl: Label

func _ready() -> void:
	_build_ui()

func open() -> void:
	_refresh()
	visible = true

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close())
	add_child(overlay)

	_panel = Panel.new()
	# 620 → 660 (2026-08-04) to fit the export button row + its status line
	# without the label overhanging the panel's bottom edge.
	_panel.size = Vector2(760, 660)
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	overlay.add_child(_panel)
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

	_lbl(_panel, "RUN HISTORY", 24, Color(0.95, 0.82, 0.5), Vector2(0, 18), Vector2(760, 36), true)
	_stats_lbl = _lbl(_panel, "", 15, Color(0.72, 0.78, 0.92), Vector2(24, 60), Vector2(712, 26), true)
	var sep := HSeparator.new(); sep.position = Vector2(24, 92); sep.size = Vector2(712, 4)
	_panel.add_child(sep)

	# Column header
	_lbl(_panel, "Result", 12, Color(0.6, 0.6, 0.72), Vector2(40, 100), Vector2(120, 20))
	_lbl(_panel, "Wave", 12, Color(0.6, 0.6, 0.72), Vector2(210, 100), Vector2(80, 20))
	_lbl(_panel, "Kills", 12, Color(0.6, 0.6, 0.72), Vector2(320, 100), Vector2(80, 20))
	_lbl(_panel, "Damage", 12, Color(0.6, 0.6, 0.72), Vector2(430, 100), Vector2(110, 20))
	_lbl(_panel, "When", 12, Color(0.6, 0.6, 0.72), Vector2(570, 100), Vector2(160, 20))

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 128)
	scroll.size = Vector2(712, 428)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(700, 0)
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)

	# Export (2026-08-04): external testers can't be asked to dig a JSON out of
	# %APPDATA%, so this drops a dated copy on their Desktop and opens the folder.
	var export_btn := Button.new()
	export_btn.text = "⇩  Export Run Data"; export_btn.position = Vector2(150, 566); export_btn.size = Vector2(220, 40)
	UITheme.apply_font(export_btn, UITheme.FONT_HEADER)
	export_btn.tooltip_text = "Save run summaries and detailed decision telemetry to your Desktop."
	UITheme.style_button(export_btn)
	export_btn.pressed.connect(_on_export)
	_panel.add_child(export_btn)

	_export_lbl = _lbl(_panel, "", 12, Color(0.6, 0.85, 0.65), Vector2(24, 616), Vector2(712, 22), true)

	var close_btn := Button.new()
	close_btn.text = "✕  Close"; close_btn.position = Vector2(390, 566); close_btn.size = Vector2(220, 40)
	UITheme.apply_font(close_btn, UITheme.FONT_HEADER)
	UITheme.style_button(close_btn)
	close_btn.pressed.connect(_close)
	_panel.add_child(close_btn)

	visible = false

func _on_export() -> void:
	# Meta state is passed in rather than read inside RunHistory so that stays a
	# pure static (CONVENTIONS landmine 9). Nodes owned is the x-axis of the whole
	# balance pass, so an export without it is far less useful.
	var path := RunHistory.export_to_desktop({
		"nodes_owned": Progression.nodes_owned(),
		"crystals": Progression.crystals,
		"crystals_spent": Progression.total_spent(),
	})
	var telemetry_path := RunTelemetry.export_to_desktop()
	if path == "":
		_export_lbl.add_theme_color_override("font_color", Color(0.95, 0.5, 0.5))
		_export_lbl.text = "Export failed — couldn't write the file."
		return
	_export_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 0.65))
	_export_lbl.text = "Saved %s%s" % [path.get_file(),
		(" + " + telemetry_path.get_file()) if telemetry_path != "" else ""]
	OS.shell_show_in_file_manager(path)

func _refresh() -> void:
	var s := RunHistory.stats()
	_stats_lbl.text = "%d runs  ·  %d wins  ·  %d%% win rate  ·  best wave %d  ·  %d total kills" % [
		int(s["runs"]), int(s["wins"]), int(round(float(s["win_rate"]) * 100.0)),
		int(s["best_wave"]), int(s["total_kills"])]
	for c in _list.get_children():
		c.queue_free()
	var entries := RunHistory.entries()
	if entries.is_empty():
		_lbl(_list, "No runs yet — finish a run and it'll show up here.", 14,
			Color(0.6, 0.6, 0.7), Vector2.ZERO, Vector2(700, 40), true)
		return
	for e in entries:
		_list.add_child(_row(e))

func _row(e: Dictionary) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(700, 26)
	var won: bool = bool(e.get("won", false))
	var res := _lbl(row, "✔ Victory" if won else "✕ Defeat", 13,
		Color(0.5, 0.95, 0.55) if won else Color(0.95, 0.5, 0.5), Vector2(16, 0), Vector2(150, 26))
	res.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl(row, "%d" % int(e.get("wave", 0)), 13, Color(0.9, 0.9, 0.95), Vector2(186, 0), Vector2(80, 26))
	_lbl(row, "%d" % int(e.get("kills", 0)), 13, Color(0.9, 0.9, 0.95), Vector2(296, 0), Vector2(80, 26))
	_lbl(row, "%d" % int(e.get("damage", 0)), 13, Color(0.9, 0.9, 0.95), Vector2(406, 0), Vector2(110, 26))
	_lbl(row, str(e.get("when", "")), 12, Color(0.6, 0.6, 0.72), Vector2(546, 0), Vector2(160, 26))
	return row

func _close() -> void:
	visible = false
	closed.emit()

func _lbl(parent: Node, text: String, sz: int, col: Color, pos: Vector2, size: Vector2, center := false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	UITheme.apply_font(l, UITheme.body_font(sz))
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l
