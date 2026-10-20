extends Node
# Drowned Maw — Abyssal Breach (owner design 2026-10-02). Drives the dive state
# machine directly and checks every promise the design makes:
#   triggers at 70/40/10% HP and exactly three times; untargetable AND unhittable
#   while under; its cells are vacated; it rises under the top damage dealer;
#   the 2x2 takes damage + is knocked out; the 4x4 (and only it) takes the
#   pulse; the grid agrees with every unit afterwards.
#
#   GODOT --headless --path . --fixed-fps 30 res://scenes/maw_breach_smoke.tscn

var _fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)

func _hero(cls) -> UnitBase:
	return UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)

func _place(grid, u, c: Vector2i) -> void:
	grid.place_unit(u, c)
	u.grid_position = c

func _run_until(mgr, boss, players: Array, state: String, limit: float) -> float:
	var t := 0.0
	while t < limit and boss.get_meta("maw_dive_state", "") != state:
		mgr._maw_dive_tick(boss, players, 0.05)
		t += 0.05
	return t

func _ready() -> void:
	var mgr = load("res://scripts/combat/auto_battle_manager.gd").new()
	var grid = load("res://scripts/combat/battle_grid.gd").new()
	add_child(grid)
	add_child(mgr)
	mgr.battle_grid = grid
	await get_tree().process_frame

	var boss = EnemyFactory.create_drowned_maw(14)
	var carry = _hero(UnitBase.UnitClass.BLOODHOUND)   # top damage -> the hunted one
	var buddy = _hero(UnitBase.UnitClass.BOUNCER)      # shares the 2x2 with the carry
	var ring = _hero(UnitBase.UnitClass.NEMI)          # in the 4x4, outside the 2x2
	var far = _hero(UnitBase.UnitClass.SABLE)          # nowhere near it
	for u in [boss, carry, buddy, ring, far]:
		add_child(u)
	_place(grid, boss, Vector2i(3, 0))
	_place(grid, carry, Vector2i(4, 6))
	_place(grid, buddy, Vector2i(5, 6))
	_place(grid, ring, Vector2i(3, 5))
	_place(grid, far, Vector2i(0, 8))
	var players: Array = [carry, buddy, ring, far]
	mgr.enemy_units = [boss]
	mgr.player_units = players
	carry.damage_dealt = 5000
	buddy.damage_dealt = 100
	ring.damage_dealt = 50
	for h in players:
		h.max_hp = 100000
		h.current_hp = 100000

	# ── no dive above 70% ────────────────────────────────────────────────────
	boss.current_hp = int(boss.max_hp * 0.75)
	mgr._maw_dive_tick(boss, players, 0.05)
	_check(boss.get_meta("maw_dive_state", "") == "", "dived above 70% HP")

	# ── dive 1 ───────────────────────────────────────────────────────────────
	var res0: int = boss.resistance
	var mr0: int = boss.magic_resist
	var atk0: int = boss.attack_damage
	boss.current_hp = int(boss.max_hp * 0.69)
	mgr._maw_dive_tick(boss, players, 0.05)
	_check(boss.get_meta("maw_dive_state", "") == "sink", "no dive at 69% HP")
	# Each dive hardens it: armour and attack up, magic resist NOT (its weakness).
	_check(boss.resistance > res0, "armour didn't rise on the dive (%d -> %d)" % [res0, boss.resistance])
	_check(boss.attack_damage > atk0, "attack didn't rise on the dive (%d -> %d)" % [atk0, boss.attack_damage])
	_check(boss.magic_resist == mr0, "magic resist changed on the dive (%d -> %d) — it must stay the weakness" % [mr0, boss.magic_resist])
	_check(boss.get_meta("maw_dive_target", null) == carry, "hunting the wrong hero — should be top damage dealer")
	_check(boss.untargetable_time > 0.0, "targetable while diving")
	_check(boss.stun_time > 0.0, "can still act while diving")
	var hp_before: int = boss.current_hp
	boss.take_damage(500, UnitBase.Element.NORMAL, carry)
	_check(boss.current_hp == hp_before, "took damage while submerged (%d -> %d)" % [hp_before, boss.current_hp])

	_run_until(mgr, boss, players, "stalk", 3.0)
	_check(boss.get_meta("maw_dive_state", "") == "stalk", "never went under (stalk)")
	_check(not boss.visible, "body still visible while under the board")
	_check(grid.get_unit_at(Vector2i(3, 0)) != boss and grid.get_unit_at(Vector2i(4, 1)) != boss,
			"its old 2x2 is still occupied while it is under the board")
	_check(mgr.find_nearest_enemy(far, [boss]) == null, "a hero can still pick it as a target while under")

	var hp0 := {}
	for h in players:
		hp0[h] = h.current_hp
	_run_until(mgr, boss, players, "breach", 4.0)
	_check(boss.get_meta("maw_dive_state", "") == "breach", "never breached")
	# step to just past impact (hit 1), before the pulse
	var t := 0.0
	while t < mgr.MAW_BREACH_IMPACT + 0.06:
		mgr._maw_dive_tick(boss, players, 0.05); t += 0.05
	_check(bool(boss.get_meta("maw_hit1", false)), "impact never fired")
	var block: Array = [Vector2i(4, 6), Vector2i(5, 6), Vector2i(4, 7), Vector2i(5, 7)]
	_check(block.has(boss.grid_position) and boss.grid_position == Vector2i(4, 6),
			"rose at %s, not on the carry's 2x2 (4,6)" % boss.grid_position)
	for c in block:
		_check(grid.get_unit_at(c) == boss, "2x2 cell %s not held by the Maw after surfacing" % c)
	_check(not boss.has_meta("maw_submerged"), "still flagged submerged after surfacing")
	var dmg1: int = int(boss.attack_damage * mgr.MAW_BREACH_DMG)
	for h in [carry, buddy]:
		_check(hp0[h] - h.current_hp >= dmg1 * 0.5, "%s in the 2x2 took too little impact damage (%d)" % [h.unit_name, hp0[h] - h.current_hp])
		_check(not block.has(h.grid_position), "%s was not knocked out of the 2x2 (at %s)" % [h.unit_name, h.grid_position])
		_check(grid.get_unit_at(h.grid_position) == h, "grid disagrees about where %s landed" % h.unit_name)
	_check(ring.current_hp == hp0[ring], "the 4x4 ring hero was hit by the IMPACT (should be pulse only)")

	while t < mgr.MAW_BREACH_IMPACT + mgr.MAW_PULSE_DELAY + 0.06:
		mgr._maw_dive_tick(boss, players, 0.05); t += 0.05
	_check(bool(boss.get_meta("maw_hit2", false)), "4x4 pulse never fired")
	_check(ring.current_hp < hp0[ring], "ring hero inside the 4x4 took no pulse damage")
	_check(far.current_hp == hp0[far], "hero far outside the 4x4 was hit")
	_run_until(mgr, boss, players, "", 3.0)
	_check(boss.get_meta("maw_dive_state", "") == "", "never returned to fighting")
	_check(boss.visible, "invisible after the sequence")

	# ── dives 2 and 3, and no 4th ────────────────────────────────────────────
	for frac in [0.39, 0.09]:
		boss.current_hp = int(boss.max_hp * frac)
		mgr._maw_dive_tick(boss, players, 0.05)
		_check(boss.get_meta("maw_dive_state", "") == "sink", "no dive at %d%%" % int(frac * 100))
		_run_until(mgr, boss, players, "breach", 6.0)
		_run_until(mgr, boss, players, "", 4.0)
		_check(grid.get_unit_at(boss.grid_position) == boss, "grid lost the Maw after the dive at %d%%" % int(frac * 100))
	boss.current_hp = int(boss.max_hp * 0.02)
	mgr._maw_dive_tick(boss, players, 0.05)
	_check(boss.get_meta("maw_dive_state", "") == "", "a FOURTH dive fired")
	_check(int(boss.get_meta("maw_dive_idx", 0)) == 3, "dive count is %d, expected 3" % int(boss.get_meta("maw_dive_idx", 0)))

	if _fails.is_empty():
		print("MAW_BREACH_SMOKE: ALL PASS")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("MAW_BREACH_SMOKE: FAIL -> %s" % f)
		print("MAW_BREACH_SMOKE: %d FAILURE(S)" % _fails.size())
		get_tree().quit(1)
