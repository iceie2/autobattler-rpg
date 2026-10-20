extends Node
# Shared status layer probe (ENEMY_FEEL_AUDIT.md §2.1), driving the REAL
# AutoBattleManager._sync_status_marks and VisualUnit badge update.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/status_layer_probe.tscn

var _fail: Array = []

func _check(c: bool, m: String) -> void:
	if not c: _fail.append(m)

func _ready() -> void:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	var u := EnemyFactory.create_by_type("orc_normal")
	add_child(u); u.battle_manager = mgr
	var src := EnemyFactory.create_by_type("goblin")
	add_child(src)
	mgr.enemy_units = [u]; mgr.player_units = [src]

	# Every generic status raises exactly one mark while its timer runs.
	mgr.apply_slow(u, 0.3, 2.0)
	var slow_peak: float = u.slow_time
	mgr.apply_root(u, 2.0)
	mgr.apply_taunt(u, src, 2.0)
	u.burn_time = 2.0; u.burn_flavor = "fire"
	u.heal_cut_time = 2.0
	u.weakened_time = 2.0; u.weaken_flavor = ""
	mgr._sync_status_marks()
	_check(mgr._status_marks.size() == 6, "expected 6 marks, got %d" % mgr._status_marks.size())

	# Bespoke flavours are NOT painted over.
	u.burn_flavor = "disease"
	u.weaken_flavor = "corrosion"
	mgr._sync_status_marks()
	_check(mgr._status_marks.size() == 4,
		"disease/corrosion still got a generic mark (%d marks)" % mgr._status_marks.size())

	# Badges: one per active status, ring reflects remaining / peak.
	u._update_status_icons()
	for k in ["slow", "root", "taunt", "disease", "heal_cut", "corroded"]:
		var b = u._status_icons.get(k)
		_check(b != null and b.visible, "no visible badge for %s" % k)
	_check(u._status_icons.get("burn") == null or not u._status_icons["burn"].visible,
		"fire-burn badge shown while the burn is disease-flavoured")
	u.slow_time = slow_peak * 0.5   # tenacity shortens the applied slow, so halve what landed
	u._update_status_icons()
	var sb = u._status_icons.get("slow")
	_check(sb and absf(sb.frac - 0.5) < 0.01, "slow ring should be half-drained, is %s" % str(sb.frac if sb else -1))

	# Timers expiring clear both layers.
	u.slow_time = 0.0; u.root_time = 0.0; u.taunt_time = 0.0
	u.burn_time = 0.0; u.heal_cut_time = 0.0; u.weakened_time = 0.0
	mgr._sync_status_marks()
	u._update_status_icons()
	_check(mgr._status_marks.is_empty(), "marks outlived their statuses")
	for k in u._status_icons:
		_check(not u._status_icons[k].visible, "badge %s outlived its status" % k)

	if _fail.is_empty():
		print("STATUS_LAYER_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("STATUS_LAYER_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)
