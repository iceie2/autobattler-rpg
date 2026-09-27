extends Node
# Shared channel system probe (VD-15): the generic rules on bare units, then the
# two migrated abilities (Headhunter Snipe, Static Grid) through their REAL code.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/channel_probe.tscn
# Prints CHANNEL_PROBE: ALL PASS, or every failed check.

var _fail: Array = []
var _passed := 0

func _check(c: bool, m: String) -> void:
	if c: _passed += 1
	else: _fail.append(m)

func _fresh() -> Dictionary:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	return {"grid": grid, "mgr": mgr}

func _mk(mgr, grid, u, cell: Vector2i, player: bool):
	add_child(u); u.battle_manager = mgr; u.is_player_unit = player
	grid.place_unit(u, cell); u.grid_position = cell
	return u

func _run(mgr, u, seconds: float, dt: float = 1.0 / 30.0) -> bool:
	var blocked := false
	var t := 0.0
	while t < seconds and u.channel:
		blocked = mgr._tick_channel(u, dt) or blocked
		t += dt
	return blocked

func _ready() -> void:
	_generic()
	_headhunter()
	_static()
	if _fail.is_empty():
		print("CHANNEL_PROBE: ALL PASS (%d checks)" % _passed)
	else:
		for f in _fail: print("  FAIL: ", f)
		print("CHANNEL_PROBE: %d FAILED / %d passed" % [_fail.size(), _passed])
	get_tree().quit()

func _generic() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var a: UnitBase = _mk(mgr, s["grid"], UnitBase.new(), Vector2i(1, 5), true)
	var done := [0]
	var broke := [""]
	mgr.start_channel(a, "t", 1.0, func(): done[0] += 1,
		{"blocks": true, "on_interrupt": func(r): broke[0] = r})
	_check(mgr._tick_channel(a, 0.5), "blocking channel owns the turn")
	_check(done[0] == 0 and a.channel != null, "not done at 0.5 s")
	mgr._tick_channel(a, 0.6)
	_check(done[0] == 1 and a.channel == null, "completes once after its duration")
	# PAUSE: a stun holds the timer.
	mgr.start_channel(a, "p", 1.0, func(): done[0] += 1, {"on_stun": Channel.OnStun.PAUSE})
	a.stun_time = 2.0
	mgr._tick_channel(a, 0.9)
	_check(a.channel != null and is_equal_approx(a.channel.remaining, 1.0), "PAUSE holds while stunned")
	a.stun_time = 0.0
	mgr._tick_channel(a, 1.1)
	_check(done[0] == 2, "PAUSE resumes and completes after the stun")
	# INTERRUPT: a stun breaks it, no payoff, on_interrupt told why.
	mgr.start_channel(a, "i", 1.0, func(): done[0] += 1,
		{"on_stun": Channel.OnStun.INTERRUPT, "on_interrupt": func(r): broke[0] = r})
	a.stun_time = 1.0
	_check(not mgr._tick_channel(a, 0.1), "broken channel releases the turn to the stun gate")
	_check(a.channel == null and done[0] == 2 and broke[0] == "stunned", "INTERRUPT: no payoff, reason 'stunned'")
	a.stun_time = 0.0
	# Non-blocking channel lets the unit act.
	mgr.start_channel(a, "nb", 1.0, func(): pass, {"blocks": false})
	_check(not mgr._tick_channel(a, 0.1), "non-blocking channel does not own the turn")
	# Starting a new channel replaces (interrupts) the old one.
	broke[0] = ""
	mgr.start_channel(a, "x", 1.0, func(): pass, {"on_interrupt": func(r): broke[0] = r})
	mgr.start_channel(a, "y", 1.0, func(): pass)
	_check(a.channel.id == "y" and broke[0] == "replaced", "new channel replaces the old")
	# Two units channel at once, independently (Static's globals could not).
	var b: UnitBase = _mk(mgr, s["grid"], UnitBase.new(), Vector2i(2, 5), true)
	var both := [0]
	mgr.start_channel(a, "g", 0.5, func(): both[0] += 1)
	mgr.start_channel(b, "g", 0.5, func(): both[0] += 1)
	mgr._tick_channel(a, 0.6); mgr._tick_channel(b, 0.6)
	_check(both[0] == 2, "two channels at once both complete")

func _headhunter() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var hh: UnitBase = _mk(mgr, s["grid"], UnitFactory.create_unit(UnitBase.UnitClass.HEADHUNTER, UnitBase.Element.NORMAL, true), Vector2i(3, 7), true)
	var foe: UnitBase = _mk(mgr, s["grid"], UnitFactory.create_unit(UnitBase.UnitClass.RIOT, UnitBase.Element.NORMAL, false), Vector2i(3, 1), false)
	mgr.player_units = [hh]; mgr.enemy_units = [foe]
	var hp0: int = foe.current_hp
	mgr._use_ultimate(hh, [foe], [hh])
	_check(hh.channel != null and hh.channel.id == "snipe" and hh.channel.blocks_actions, "Snipe starts a blocking channel")
	_check(foe.current_hp == hp0, "no damage before the aim completes")
	hh.stun_time = 1.0
	mgr._tick_channel(hh, 1.0)
	_check(hh.channel != null and is_equal_approx(hh.channel.remaining, AutoBattleManager.HEADHUNTER_AIM_DURATION), "a stun pauses the aim")
	hh.stun_time = 0.0
	_run(mgr, hh, AutoBattleManager.HEADHUNTER_AIM_DURATION + 0.2)
	_check(hh.channel == null and foe.current_hp < hp0, "Snipe fires after %.1f s of aim" % AutoBattleManager.HEADHUNTER_AIM_DURATION)

func _static() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var st: UnitBase = _mk(mgr, s["grid"], UnitFactory.create_unit(UnitBase.UnitClass.STATIC, UnitBase.Element.NORMAL, true), Vector2i(3, 7), true)
	var foe: UnitBase = _mk(mgr, s["grid"], UnitFactory.create_unit(UnitBase.UnitClass.RIOT, UnitBase.Element.NORMAL, false), Vector2i(3, 1), false)
	mgr.player_units = [st]; mgr.enemy_units = [foe]
	mgr._static_grid(st)
	_check(st.channel != null and st.channel.id == "grid" and not st.channel.blocks_actions, "Grid starts a NON-blocking channel")
	_run(mgr, st, 30.0)
	_check(st.channel == null and foe.stun_time > 0.0, "Grid completes and stuns the foes")
	# Interrupted by a stun: no lockdown.
	foe.stun_time = 0.0
	mgr._static_grid(st)
	st.stun_time = 0.5
	mgr._tick_channel(st, 0.1)
	st.stun_time = 0.0
	_run(mgr, st, 30.0)
	_check(st.channel == null and foe.stun_time <= 0.0, "a stunned Static gets no lockdown")
