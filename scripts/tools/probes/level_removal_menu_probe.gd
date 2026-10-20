extends Node
# LevelRemovalPanel (the REMOVE N LEVEL merge menu), driven through its real
# buttons. Run: godot --headless res://scenes/tools/level_removal_menu_probe.tscn
# Prints LEVEL_REMOVAL_MENU_PROBE: ALL PASS, or every failed check.

var _fail: Array = []
var _passed := 0
var _confirmed: Array = []
var _cancelled := 0

func _check(c: bool, m: String) -> void:
	if c: _passed += 1
	else: _fail.append(m)

func _fresh(pool: Dictionary, need: int) -> LevelRemovalPanel:
	var p := LevelRemovalPanel.new()
	add_child(p)
	_confirmed.clear()
	_cancelled = 0
	p.confirmed.connect(func(r): _confirmed.append(r))
	p.cancelled.connect(func(): _cancelled += 1)
	p.open(pool, need)
	return p

func _click(p: LevelRemovalPanel, key: String) -> void:
	p.row_button(key).pressed.emit()

func _hint(p: LevelRemovalPanel, key: String) -> String:
	return str(p.row_node(key).get("_hint").text)

func _ready() -> void:
	var pool := {"recovery": 1, "aftercast_ward": 1, "sustained_assault": 1, "equilibrium": 1}
	var p := _fresh(pool, 1)

	# 1. Initial state: 0 / 1, primary action disabled and labelled as such.
	_check(p.is_open(), "menu opens")
	_check(p.count_text() == "0 / 1", "initial count is 0 / 1 (%s)" % p.count_text())
	_check(p.status_text() == "Select 1 passive", "initial status line (%s)" % p.status_text())
	_check(p.merge_button().disabled, "primary action starts disabled")
	_check(p.merge_text() == "SELECT A PASSIVE", "disabled primary reads SELECT A PASSIVE (%s)" % p.merge_text())
	_check(p.row_keys().size() == 4, "one row per pooled passive")
	for k in p.row_keys():
		_check(not p.row_node(k).is_selected(), "no row starts selected (%s)" % k)

	# 5. Merge cannot run with zero selected: not by method, not by pressing the disabled button.
	_check(not p.try_confirm(), "try_confirm() refuses with nothing selected")
	p.merge_button().pressed.emit()
	_check(_confirmed.is_empty() and p.is_open(), "no merge signal and menu stays open with nothing selected")

	# 2 + 3. Click a passive: it is selected, status reads 1 / 1, row shows REMOVING.
	_click(p, "recovery")
	_check(p.is_removing("recovery") and p.total() == 1, "click selects the passive")
	_check(p.count_text() == "1 / 1", "count becomes 1 / 1 (%s)" % p.count_text())
	_check(p.status_text() == "1 passive will be removed", "status line after selection (%s)" % p.status_text())
	_check(p.row_node("recovery").is_selected() and _hint(p, "recovery") == "REMOVING", "selected row is in the removing state (%s)" % _hint(p, "recovery"))
	_check(str(p.row_node("recovery").get("_chip").text) == "Lv 1 → gone", "chip shows the result (%s)" % p.row_node("recovery").get("_chip").text)
	_check(not p.row_node("equilibrium").is_selected(), "other rows stay unselected")
	_check(not p.merge_button().disabled and p.merge_text() == "REMOVE & MERGE", "primary action wakes up (%s)" % p.merge_text())

	# 4. Click it again: unselected, disabled again.
	_click(p, "recovery")
	_check(not p.is_removing("recovery") and p.total() == 0, "second click undoes the pick")
	_check(p.count_text() == "0 / 1" and p.merge_button().disabled and p.merge_text() == "SELECT A PASSIVE", "undo returns to the disabled state")
	_check(_hint(p, "recovery") == "", "undone row shows no REMOVING tag")

	# Changing your mind: another row takes over (one pick is the whole budget).
	_click(p, "recovery")
	_click(p, "equilibrium")
	_check(p.is_removing("equilibrium") and not p.is_removing("recovery") and p.total() == 1, "picking another row swaps the choice")

	# 6. Merge with exactly one selected: signal carries exactly that removal; menu closes.
	_check(p.try_confirm(), "try_confirm() succeeds with exactly one selected")
	_check(_confirmed.size() == 1 and _confirmed[0] == {"equilibrium": 1}, "confirmed carries {equilibrium: 1}: %s" % str(_confirmed))
	_check(not p.is_open() and _cancelled == 0, "merge closes the menu without a cancel")
	# Double activation cannot merge twice.
	_check(not p.try_confirm(), "second confirm is refused")
	p.merge_button().pressed.emit()
	_check(_confirmed.size() == 1, "double press cannot fire a second merge")

	# 7. Cancel: closes, reports cancel, never a merge, nothing selected leaks out.
	p = _fresh(pool, 1)
	_click(p, "aftercast_ward")
	p.cancel_button().pressed.emit()
	_check(_cancelled == 1 and _confirmed.is_empty() and not p.is_open(), "cancel closes with a cancel signal and no merge")
	_check(not p.try_confirm() and _confirmed.is_empty(), "nothing can merge after cancel")

	# Escape = Cancel (game convention), and it consumes the key.
	p = _fresh(pool, 1)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	p._input(esc)
	_check(_cancelled == 1 and _confirmed.is_empty() and not p.is_open(), "Escape cancels")

	# Two levels (purple + purple): must mark two; a single level is not enough.
	p = _fresh({"thorns": 2, "lifesteal": 1, "sunder": 1}, 2)
	_check(p.count_text() == "0 / 2" and p.status_text() == "Select 2 levels" and p.merge_text() == "SELECT 2 LEVELS",
		"two-level menu initial text (%s | %s | %s)" % [p.count_text(), p.status_text(), p.merge_text()])
	_click(p, "thorns")
	_check(p.count_text() == "1 / 2" and p.merge_button().disabled and not p.try_confirm(), "one of two levels is not enough")
	_click(p, "thorns")
	_check(p.can_merge() and p.removals() == {"thorns": 2}, "both levels can come off one passive")
	_check(str(p.row_node("thorns").get("_chip").text) == "Lv 2 → gone" and _hint(p, "thorns") == "REMOVING ×2", "row shows ×2 (%s)" % _hint(p, "thorns"))
	_click(p, "thorns")
	_check(p.removals() == {"thorns": 1}, "clicking a marked row undoes one level")
	_click(p, "lifesteal")
	_check(p.can_merge() and p.removals() == {"thorns": 1, "lifesteal": 1}, "levels can be spread across passives")
	_check(p.try_confirm() and _confirmed[0] == {"thorns": 1, "lifesteal": 1}, "two-level merge reports both removals")

	if _fail.is_empty():
		print("LEVEL_REMOVAL_MENU_PROBE: ALL PASS (%d checks)" % _passed)
	else:
		for f in _fail: print("  FAIL: ", f)
		print("LEVEL_REMOVAL_MENU_PROBE: %d FAILED / %d passed" % [_fail.size(), _passed])
	get_tree().quit()
