extends Node
# Equipment merge toast (2026-09-29). Run in a DISPOSABLE PROFILE (it boots
# main_game): APPDATA=<scratch>/merge_profile godot --headless --path . res://scenes/equipment_merge_check.tscn
var failures: Array[String] = []
var _integration_done := false   # a GDScript runtime error aborts a function silently

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	if not OS.get_user_data_dir().contains("merge_profile"):
		print("EQUIP_MERGE: refusing to run outside a merge_profile APPDATA sandbox")
		get_tree().quit(2)
		return
	seed(9317)
	_check_rows()
	_check_inventory_signal()
	await _check_toast()
	await _check_integration()
	if not _integration_done:
		check(false, "integration section did not finish (script error?)")
	print("EQUIP_MERGE: ", "ALL PASS" if failures.is_empty() else str(failures))
	for i in range(3): await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

# A legal pair of same-tier items and their manual-merge result.
func _pair(rarity: int) -> Array:
	for i in range(200):
		var a := ComponentEquipmentRules.generate_item(12, rarity)
		var b := ComponentEquipmentRules.generate_item(12, rarity)
		if ComponentEquipmentRules.can_combine(a, b):
			var r := ComponentEquipmentRules.combine(a, b, ComponentEquipmentInventory.STAT_KEEP,
				ComponentEquipmentRules.random_removals(a, b))
			if r != null:
				return [a, b, r]
	return []

func _check_rows() -> void:
	check(MergeStatRows.format("int", 2047.0) == "2047", "int format")
	check(MergeStatRows.format("f2", 1.0) == "1.00", "f2 format")
	check(MergeStatRows.format("int", 5.0, "Lv ", "") == "Lv 5", "prefix")
	check(MergeStatRows.format("int", 6.0, "", "%") == "6%", "suffix")
	check(MergeStatRows.total_for("int", 2047.0, 2059.0) == 12.0, "int total")
	check(MergeStatRows.gain_text("int", 12.0) == "+12" and MergeStatRows.gain_text("int", 0.0) == "", "gain text")
	check(MergeStatRows.gain_text("int", -2.0).length() == 2 and MergeStatRows.gain_text("int", -2.0).ends_with("2"),
		"negative gain text")
	var box := VBoxContainer.new()
	add_child(box)
	var row := MergeStatRows.make_row(box, null, 2047.0, 2059.0, "int")
	check(row["main"].text == "2047" and row["gain"].text == "+12", "row starts old value + full gain")
	var last := 2047
	var sum_ok := true
	for i in range(0, 101):
		MergeStatRows.step(i / 100.0, row)
		var v := int(row["main"].text)
		var g: String = row["gain"].text
		sum_ok = sum_ok and v >= last and v + (int(g.substr(1)) if g != "" else 0) == 2059
		last = v
	check(sum_ok, "int row: monotonic and main + gain always 2059")
	check(row["main"].text == "2059" and row["gain"].text == "", "int row ends at 2059, gain gone")
	var frow := MergeStatRows.make_row(box, null, 0.30, 0.42, "f2")
	var clean := true
	for i in range(0, 101):
		MergeStatRows.step(i / 100.0, frow)
		clean = clean and frow["main"].text.split(".")[1].length() == 2
	check(clean and frow["main"].text == "0.42", "f2 row stays two-decimal and ends at 0.42")
	# A removed level counts DOWN (negative total).
	var nrow := MergeStatRows.make_row(box, null, 3.0, 2.0, "int", "Lv ")
	check(nrow["main"].text == "Lv 3" and nrow["gain"].text.ends_with("1") and not nrow["gain"].text.begins_with("+"),
		"negative row starts 'Lv 3' with a minus gain")
	MergeStatRows.step(1.0, nrow)
	check(nrow["main"].text == "Lv 2", "negative row ends at Lv 2")
	box.queue_free()

func _check_inventory_signal() -> void:
	var pair := _pair(1)
	check(not pair.is_empty(), "found a combinable green pair")
	if pair.is_empty():
		return
	var inv := ComponentEquipmentInventory.new()
	inv.items.append(pair[0])
	inv.items.append(pair[1])
	var got: Array = []
	inv.components_merged.connect(func(a, b, r) -> void: got.append([a, b, r]))
	var sources: Array[EquipmentItem] = [pair[0], pair[1]]
	var res := inv.combine_components(sources, ComponentEquipmentRules.random_removals(pair[0], pair[1]))
	check(res != null and got.size() == 1, "manual combine emits components_merged once")
	if got.size() == 1:
		check(got[0][0] == pair[0] and got[0][1] == pair[1] and got[0][2] == res, "signal carries base, other, result")
	# Silent auto-combine sweep: two identical greys merge with NO signal.
	var inv2 := ComponentEquipmentInventory.new()
	var silent: Array = []
	inv2.components_merged.connect(func(_a, _b, _r) -> void: silent.append(1))
	inv2.auto_combine = true
	inv2.add_item(ComponentEquipmentRules.create_common("hp", {"hp": 30}))
	inv2.add_item(ComponentEquipmentRules.create_common("hp", {"hp": 30}))
	check(inv2.items.size() == 1 and inv2.items[0].rarity == EquipmentItem.Rarity.UNCOMMON,
		"auto-combine merged two identical greys")
	check(silent.is_empty(), "auto-combine sweeps do not toast")
	inv.free()
	inv2.free()

func _check_toast() -> void:
	var pair := _pair(1)
	if pair.is_empty():
		check(false, "no pair for toast test")
		return
	var a: ComponentEquipmentItem = pair[0]
	var b: ComponentEquipmentItem = pair[1]
	var r: ComponentEquipmentItem = pair[2]
	var t := EquipmentMergeScreen.new()
	add_child(t)
	t.present(a, b, r)
	# Starts as the TWO source items, each in its own icon / colour / name, and
	# the result card not yet revealed.
	check(t._card_a.get_meta("icon").texture == GearIcons.icon_for(a), "left card shows item A's icon")
	check(t._card_b.get_meta("icon").texture == GearIcons.icon_for(b), "right card shows item B's icon")
	check(t._card_a.get_meta("name").text == a.name and t._card_b.get_meta("name").text == b.name, "both names shown")
	check(t._card_a.visible and t._card_b.visible and t._card_a.modulate.a == 1.0 and t._card_b.modulate.a == 1.0,
		"both source cards are showing")
	check(t._card_r != t._card_a and t._card_r != t._card_b and t._card_r.modulate.a == 0.0,
		"the result is its own card, hidden until the flash")
	check(not t._rows.is_empty(), "there are stat rows to animate")
	var start_ok := true
	for row in t._rows:
		start_ok = start_ok and float(row["a"]) == 0.0 \
			and row["main"].text == MergeStatRows.format(row["fmt"], 0.0, row["prefix"], row["suffix"])
		start_ok = start_ok and row["gain"].text != ""
	check(start_ok, "result rows start at 0 with the whole merged value as the gain")
	# The merged item's passives pop up: one entry per passive, hidden at first.
	check(not r.passive_levels.is_empty(), "test item has passives to show")
	check(t._passive_entries.size() == r.passive_levels.size(), "one pop-up entry per passive on the result")
	var hidden_ok := true
	for pe in t._passive_entries:
		hidden_ok = hidden_ok and pe["node"].modulate.a == 0.0
	check(hidden_ok, "passive entries start hidden")
	var mid_x: float = (EquipmentMergeScreen.PANEL_W - EquipmentMergeScreen.CARD_W) * 0.5
	check(t._root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay never blocks input")
	check(t.find_children("*", "BaseButton", true, false).is_empty(), "overlay has no buttons")
	var state := {"finished": false, "sum_ok": true, "icon_changed_early": false}
	t.done.connect(func() -> void:
		state["finished"] = true
		state["icon"] = t._card_r.get_meta("icon").texture
		state["name"] = t._card_r.get_meta("name").text
		state["chip"] = t._card_r.get_meta("chip").text
		state["sources_hidden"] = not t._card_a.visible and not t._card_b.visible
		state["a_icon_kept"] = t._card_a.get_meta("icon").texture == GearIcons.icon_for(a)
		state["b_icon_kept"] = t._card_b.get_meta("icon").texture == GearIcons.icon_for(b)
		state["r_shown"] = t._card_r.modulate.a == 1.0
		var pop_ok := true
		for pe in t._passive_entries:
			var key: String = pe["key"]
			var lvl: int = int(r.passive_levels[key])
			pop_ok = pop_ok and pe["node"].modulate.a == 1.0 \
				and pe["name"].text.begins_with(GearCatalog.display_name(key)) and pe["name"].text.ends_with("Lv %d" % lvl) \
				and pe["desc"].text == GearCatalog.describe(key, lvl) and pe["desc"].text != ""
		state["passives_ok"] = pop_ok
		state["border"] = (t._card_r.get_theme_stylebox("panel") as StyleBoxFlat).border_color
		var ok := true
		for row in t._rows:
			ok = ok and row["main"].text == MergeStatRows.format(row["fmt"], row["b"], row["prefix"], row["suffix"]) \
				and row["gain"].text == ""
		state["rows_ok"] = ok)
	var seen_result_icon := false
	var waited := 0.0
	while not state["finished"] and waited < 25.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if state["finished"] or not is_instance_valid(t):
			break
		if t._card_r.modulate.a > 0.5 and t._card_r.get_meta("icon").texture == GearIcons.icon_for(r):
			seen_result_icon = true
		# Neither item is "the base": while both are on screen they mirror each
		# other exactly (positions about the middle, scale, fade).
		if t._card_a.visible and t._card_b.visible:
			if absf((t._card_a.position.x + t._card_b.position.x) - 2.0 * mid_x) > 0.01 \
					or not t._card_a.scale.is_equal_approx(t._card_b.scale) \
					or not is_equal_approx(t._card_a.modulate.a, t._card_b.modulate.a):
				state["asymmetric"] = true
			if t._card_a.position.x > 24.5:
				state["a_moved"] = true
			if t._card_b.position.x < EquipmentMergeScreen.PANEL_W - 24.0 - EquipmentMergeScreen.CARD_W - 0.5:
				state["b_moved"] = true
		for row in t._rows:
			if row["fmt"] == "int":
				var g: String = row["gain"].text
				var signed_g: int = 0
				if g != "":
					signed_g = int(g.substr(1)) * (1 if g.begins_with("+") else -1)
				if int(round(row["a"])) != int(round(row["b"])) \
						and int(row["main"].text.trim_prefix("Lv ").trim_suffix("%")) + signed_g != int(round(row["b"])):
					state["sum_ok"] = false
	check(state["finished"], "toast dismisses itself with no input")
	check(state["icon"] == GearIcons.icon_for(r), "toast ends on the RESULT icon")
	check(seen_result_icon and GearIcons.icon_for(r) != GearIcons.icon_for(a) and GearIcons.icon_for(r) != GearIcons.icon_for(b),
		"the result card appears with a new icon, unlike either source")
	check(state["r_shown"], "result card is shown at the end")
	check(state.get("passives_ok", false), "every passive popped in with its name, level and what it does")
	check(state["name"] == r.name and state["chip"] == r.get_rarity_name().to_upper(), "toast ends on the result name and rarity")
	check(state["border"] == UITheme.card_box(r.icon_color).border_color, "result card has the result's rarity colour")
	check(state["border"] != UITheme.card_box(a.icon_color).border_color, "result colour differs from the sources'")
	check(state["sources_hidden"], "both source cards are gone at the end")
	check(state["a_icon_kept"] and state["b_icon_kept"], "neither source card turned into the result")
	check(state.get("a_moved", false) and state.get("b_moved", false), "BOTH cards slide toward the middle")
	check(not state.get("asymmetric", false), "the two cards mirror each other every frame (equal weight)")
	check(state["sum_ok"], "main + remaining gain always equals the final value")
	check(state.get("rows_ok", false), "every row ends on the merged value with the gain gone")
	await get_tree().process_frame
	check(not is_instance_valid(t), "toast frees itself")

func _check_integration() -> void:
	var mg = load("res://scenes/main_game.tscn").instantiate()
	add_child(mg)
	for i in range(12): await get_tree().process_frame
	check(mg._equipment_inventory is ComponentEquipmentInventory, "component equipment mode is ON in the real run")
	if not (mg._equipment_inventory is ComponentEquipmentInventory):
		mg.queue_free()
		return
	var pair := _pair(1)
	var inv: ComponentEquipmentInventory = mg._equipment_inventory
	inv.items.clear()
	inv.auto_combine = false
	inv.items.append(pair[0])
	inv.items.append(pair[1])
	var sources: Array[EquipmentItem] = [pair[0], pair[1]]
	mg._merge_toasts.base_speed = 8.0   # keep the test quick
	var res := inv.combine_components(sources, ComponentEquipmentRules.random_removals(pair[0], pair[1]))
	check(res != null, "manual merge through the real inventory")
	check(mg._merge_toasts.is_busy() and mg._merge_toasts.active is EquipmentMergeScreen, "toast plays on a manual merge")
	check(mg._merge_toasts._root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the queue never blocks input")
	# A second merge straight away joins the list instead of interrupting.
	var pair2 := _pair(1)
	inv.items.append(pair2[0])
	inv.items.append(pair2[1])
	var sources2: Array[EquipmentItem] = [pair2[0], pair2[1]]
	var first_toast: Node = mg._merge_toasts.active
	inv.combine_components(sources2, ComponentEquipmentRules.random_removals(pair2[0], pair2[1]))
	check(mg._merge_toasts.active == first_toast and mg._merge_toasts.pending.size() == 1,
		"a quick second merge waits in the list, the first keeps playing")
	var waited := 0.0
	while mg._merge_toasts.is_busy() and waited < 40.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(not mg._merge_toasts.is_busy() and mg._merge_toasts.pending.is_empty(), "both toasts played out by themselves")
	# ── Level-removal merges (blue and above) must not strand the player in the
	# Equipment menu (bug 2026-09-30) ──
	var panel: EquipmentPanel = mg._equipment_panel
	inv.items.clear()
	for scenario in ["confirm", "cancel", "already_open"]:
		var need_pair: Array = []
		for i in range(300):
			var a := ComponentEquipmentRules.generate_item(12, 2)
			var b := ComponentEquipmentRules.generate_item(12, 2)
			if ComponentEquipmentRules.can_combine(a, b) and ComponentEquipmentRules.levels_to_remove(a, b) > 0:
				need_pair = [a, b]
				break
		check(not need_pair.is_empty(), "found a blue pair that needs level removal (%s)" % scenario)
		if need_pair.is_empty():
			continue
		inv.items.append(need_pair[0])
		inv.items.append(need_pair[1])
		panel.visible = scenario == "already_open"
		mg._drop_combine(need_pair[1], need_pair[0])   # the bag's drag-to-combine
		check(panel.visible and panel.removal_menu_open(), "the removal menu opens (%s)" % scenario)
		if scenario == "cancel":
			panel.cancel_removal_menu()
			check(not panel.visible, "cancelling closes the panel the drag opened")
			check(need_pair[0] in inv.items and need_pair[1] in inv.items, "cancel leaves both items in the bag")
		else:
			var removals := ComponentEquipmentRules.random_removals(need_pair[0], need_pair[1])
			var before_n: int = inv.items.size()
			panel._on_removal_confirmed(removals)
			check(inv.items.size() == before_n - 1, "the merge happened (%s)" % scenario)
			if scenario == "already_open":
				check(panel.visible, "a player already in the Equipment menu STAYS in it")
			else:
				check(not panel.visible, "confirming closes the panel the drag opened")
		panel.visible = false
		inv.items.clear()
	_integration_done = true
	mg.queue_free()
	for i in range(3): await get_tree().process_frame
