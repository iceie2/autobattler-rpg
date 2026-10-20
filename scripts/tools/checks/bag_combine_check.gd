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
	var menu: LevelRemovalPanel = mg._equipment_panel._removal_panel
	_check(menu.is_open() and menu.need() == 1, "remove-levels menu opened for 1 level")
	_check(menu.count_text() == "0 / 1" and menu.merge_button().disabled, "menu starts at 0 / 1 with merge disabled")
	# Cancel: nothing changes, both items are still in the bag.
	var blue_a: EquipmentItem = inv.items[0]
	var levels_before: Dictionary = (blue_a as ComponentEquipmentItem).passive_levels.duplicate()
	menu.cancel_button().pressed.emit()
	_check(not menu.is_open() and inv.items.size() == n_before and inv.items.has(blue_a) and inv.items.has(b2),
		"cancel closes the menu and leaves both items")
	_check((blue_a as ComponentEquipmentItem).passive_levels == levels_before, "cancel leaves passives untouched")
	# Reopen, sacrifice one passive, merge: exactly one purple with the right levels.
	mg._drop_combine(b2, inv.items[0])
	var key: String = str(menu.row_keys()[0])
	menu.row_button(key).pressed.emit()
	_check(menu.count_text() == "1 / 1" and not menu.merge_button().disabled, "one pick enables merge")
	menu.merge_button().pressed.emit()
	_check(inv.items.size() == 1 and inv.items[0].rarity == EquipmentItem.Rarity.EPIC,
		"merge made one purple item (%d items)" % inv.items.size())
	if inv.items.size() == 1:
		var purple := inv.items[0] as ComponentEquipmentItem
		_check(purple.passive_level_count() == 3 and not purple.passive_levels.has(key),
			"the sacrificed passive is gone: %s" % str(purple.passive_levels))
	# Escape closes the menu (through the game's own key path), not the panel under it.
	inv.items.clear()
	var b3 := ComponentEquipmentRules.combine(_green("atk", "hp"), _green("crit", "crit"))
	var b4 := ComponentEquipmentRules.combine(_green("magic", "magic"), _green("cdr", "cdr"))
	inv.add_item(b3)
	inv.add_item(b4)
	mg._equipment_panel.visible = false
	mg._drop_combine(b3, b4)
	_check(menu.is_open() and mg._equipment_panel.visible, "the menu opens (hosted by the equipment panel)")
	mg._close_top_menu()
	# 2026-09-30: the drag opened the panel only to host the menu, so backing out
	# returns the player to the bag instead of stranding them in the Equipment menu.
	_check(not menu.is_open() and not mg._equipment_panel.visible and inv.items.size() == 2,
		"Esc cancels the menu AND closes the panel the drag opened")
	# A player who was already inside the Equipment panel stays there.
	mg._equipment_panel.open(inv, mg.player_units)
	mg._drop_combine(b3, b4)
	mg._close_top_menu()
	_check(not menu.is_open() and mg._equipment_panel.visible and inv.items.size() == 2,
		"Esc cancels the menu only when the player was already in the equipment panel")
	await _check_save_persistence(mg)
	_finish()

func _check_save_persistence(mg) -> void:
	var inv: ComponentEquipmentInventory = mg._equipment_inventory
	inv.items.clear()
	mg.game_state.battle_round = 40
	mg.game_state.current_state = GameState.State.PLAYER_TURN
	mg.max_player_units = 10
	_check(mg._recruit_hero(UnitBase.UnitClass.SHEILDOR, UnitBase.Element.NORMAL,
		UnitFactory.generate_recruit_rolls()), "recruit equipment persistence hero")
	var hero: UnitBase = mg.player_units.back()
	var a := _green("hp", "hpregen")
	var b := _green("res", "res")
	inv.add_item(a)
	inv.add_item(b)
	mg.save_run()
	var sources: Array[EquipmentItem] = [a, b]
	var merged := inv.combine_components(sources)
	_check(merged != null, "round 40 merge succeeds")
	await get_tree().process_frame
	await get_tree().process_frame
	var saved := RunSave.read_data()
	_check(saved.get("bag", []).size() == 1 and saved["bag"][0]["id"] == merged.id,
		"completed merge saves the result instead of its consumed inputs")
	_check(inv.apply_to_hero(merged, hero), "equip merged item")
	await get_tree().process_frame
	await get_tree().process_frame
	saved = RunSave.read_data()
	var equipped := false
	for h in saved.get("heroes", []):
		for it in h.get("equipment", []):
			if it["id"] == merged.id: equipped = true
	_check(equipped and saved.get("bag", []).is_empty(), "equipped merge saves on its hero")
	# Next-round checkpoint, then a final prep change immediately before READY.
	mg.game_state.battle_round = 41
	mg.save_run()
	var extra := ComponentEquipmentRules.create_common("atk", {"atk": 5})
	inv.add_item(extra)
	mg.game_state.gold = 0
	mg._on_ready_pressed()
	saved = RunSave.read_data()
	_check(int(saved["round"]) == 41 and saved["bag"].size() == 1
		and saved["bag"][0]["id"] == extra.id, "READY saves final prep before deferred equipment save")
	mg.game_state.current_state = GameState.State.AUTO_BATTLE
	mg._save_if_in_prep()
	_check(RunSave.read_data() == saved, "mid-wave quit preserves round 41 checkpoint")
	var merged_id: String = merged.id
	mg.queue_free()
	await get_tree().process_frame
	RunSave.resume_on_start = true
	var resumed = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(resumed)
	for i in range(12): await get_tree().process_frame
	_check(resumed.game_state.battle_round == 41, "resume stays on round 41")
	var restored := false
	for u in resumed.player_units + resumed.bench_units:
		for it in resumed._equipment_inventory.get_hero_equipment(u):
			if it.id == merged_id:
				restored = it is ComponentEquipmentItem and it.rarity == EquipmentItem.Rarity.RARE
	_check(restored, "resume preserves merged rarity and equipped placement")
	resumed.queue_free()
	await get_tree().process_frame

func _finish() -> void:
	if _fail.is_empty():
		print("BAG_COMBINE_CHECK: ALL PASS")
	else:
		for f in _fail: print("  FAIL: ", f)
		print("BAG_COMBINE_CHECK: %d FAILED" % _fail.size())
	get_tree().quit()
