extends Node
# ══════════════════════════════════════════════════════════════════════════════
# UI SMOKE TEST (2026-07-04) — the plain boot smoke never exercises the details
# panel / tooltips, so UI refactors could pass import+boot and still be broken
# at first click. This scene instantiates the REAL main_game, explicitly deals
# a preview wave (map mode correctly spawns none at boot), then drives the
# details panel + refresh paths and reports PASS/FAIL.
#
# Run:  godot --headless res://scenes/ui_smoke.tscn
# Exit code 0 = pass, 1 = fail. Add checks here whenever a UI subsystem moves.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []

func _ready() -> void:
	var mg_scene := load("res://scenes/main_game.tscn") as PackedScene
	var mg := mg_scene.instantiate()
	add_child(mg)
	# Let _ready and the opening map/modal flow settle. UI smoke owns its fixture:
	# map smoke covers the real node-selection -> round-start contract separately.
	for i in range(30):
		await get_tree().process_frame
	mg.spawn_enemies(WaveScaler.Difficulty.NORMAL)
	for i in range(3):
		await get_tree().process_frame

	_check(mg.enemy_units.size() > 0, "UI fixture spawned enemies")
	if mg.enemy_units.size() > 0:
		var enemy = mg.enemy_units[0]
		mg.show_unit_details(enemy)
		await get_tree().process_frame
		_check(mg.unit_details_panel.visible, "details panel opens")
		# Refresh again (exercises combat grid / affinity / growth / bag paths)
		mg._update_details_panel()
		await get_tree().process_frame
		# A populated name label proves _refresh_details actually ran.
		_check(str(mg.details_unit_name.text) != "", "details panel populated (%s)" % mg.details_unit_name.text)
		# The bag must NOT be rebuilt every refresh: refresh_live() runs each frame,
		# and freeing the slot button under the cursor killed its hover tooltip
		# (2026-08-02). Same items across refreshes → same button instances.
		var bag: GridContainer = mg.unit_details_panel.get_node(
			"Margin/ScrollContainer/Root/Header/HeaderInfo/ChipRow/ItemBag")
		var before: Array = []
		for c in bag.get_children():
			before.append(c.get_instance_id())
		for i in range(3):
			mg._update_details_panel()
			await get_tree().process_frame
		var after: Array = []
		for c in bag.get_children():
			after.append(c.get_instance_id())
		_check(before.size() > 0 and before == after, "bag slots survive live refresh")

		mg._on_details_close_pressed()
		await get_tree().process_frame
		_check(not mg.unit_details_panel.visible, "details panel closes")

	# Item tooltip show/hide round-trip with a generated item.
	var item := EquipmentManager.generate_item(3, EquipmentItem.Rarity.RARE)
	mg._show_item_tooltip(item, Vector2(400, 300))
	await get_tree().process_frame
	_check(mg._item_tip != null and mg._item_tip.visible, "item tooltip shows")
	mg._hide_item_tooltip()
	await get_tree().process_frame
	_check(mg._item_tip == null or not mg._item_tip.visible, "item tooltip hides")

	# Sidebar rebuild paths that UI refactors are most likely to break.
	mg._rebuild_synergy_display()
	mg._rebuild_inventory_grid()
	mg.update_team_health_bars()
	await get_tree().process_frame
	_check(true, "sidebar rebuild paths ran without crashing")

	if _fails.is_empty():
		print("UI_SMOKE: ALL PASS")
		get_tree().quit(0)
	else:
		print("UI_SMOKE: FAILED -> %s" % str(_fails))
		get_tree().quit(1)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		print("  FAIL: %s" % label)
		_fails.append(label)
