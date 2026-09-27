extends Node
# Drives the REAL main_game bag: tooltip passive text for component items, the
# drag-hover combine preview, and drop-to-combine (lossless merge and the
# remove-levels menu). Restores user://run_save.json on exit.
# Run: godot --headless res://scenes/tools/bag_combine_check.tscn
var _save_existed := false
var _save_backup := ""
var _fail: Array = []

func _exit_tree() -> void:
	if _save_existed:
		var f := FileAccess.open(RunSave.PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
	else:
		RunSave.clear()

func _check(c: bool, m: String) -> void:
	if not c: _fail.append(m)

func _green(x: String, y: String) -> ComponentEquipmentItem:
	return ComponentEquipmentRules.combine(ComponentEquipmentRules.create_common(x, {x: 5}),
		ComponentEquipmentRules.create_common(y, {y: 5}))

func _ready() -> void:
	_save_existed = FileAccess.file_exists(RunSave.PATH)
	if _save_existed:
		var sf := FileAccess.open(RunSave.PATH, FileAccess.READ)
		if sf: _save_backup = sf.get_as_text()
	var mg = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(10): await get_tree().process_frame
	var inv = mg._equipment_inventory
	_check(inv is ComponentEquipmentInventory, "new run uses the component inventory")
	if not (inv is ComponentEquipmentInventory):
		_finish(); return
	inv.items.clear()
	var g := _green("hp", "hpregen")
	inv.add_item(g)
	mg._show_item_tooltip(g, Vector2(200, 200))
	_check(mg._item_tip_passive_desc.visible and "Regeneration" in mg._item_tip_passive_desc.text,
		"green tooltip shows its passive: '%s'" % mg._item_tip_passive_desc.text)
	# Lossless: green + green previews the blue, drop makes it.
	var g2 := _green("res", "res")
	inv.add_item(g2)
	mg._dragged_item = g2
	mg._show_combine_preview(g2, g, Vector2(200, 200))
	_check("Release to combine" in mg._item_tip_hint_lbl.text, "preview hint for a lossless merge")
	_check("Thorns" in mg._item_tip_passive_desc.text and "Regeneration" in mg._item_tip_passive_desc.text,
		"preview lists both passives")
	mg._dragged_item = null
	mg._drop_combine(g2, g)
	_check(inv.items.size() == 1 and inv.items[0].rarity == EquipmentItem.Rarity.RARE, "drop combined into a blue")
	# Menu case: blue + blue opens the remove-levels menu instead of merging.
	var b2 := ComponentEquipmentRules.combine(_green("atk", "hp"), _green("crit", "crit"))
	inv.add_item(b2)
	var n_before: int = inv.items.size()
	mg._drop_combine(b2, inv.items[0])
	_check(inv.items.size() == n_before, "menu merge waits for the player")
	_check(mg._equipment_panel._rm_active and mg._equipment_panel._pick_panel.visible, "remove-levels menu opened")
	_finish()

func _finish() -> void:
	if _fail.is_empty():
		print("BAG_COMBINE_CHECK: ALL PASS")
	else:
		for f in _fail: print("  FAIL: ", f)
		print("BAG_COMBINE_CHECK: %d FAILED" % _fail.size())
	get_tree().quit()
