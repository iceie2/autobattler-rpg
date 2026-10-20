extends Node

var failures: Array = []
var grid: BattleGrid
var mgr: AutoBattleManager
var boss: VisualUnit

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func unit(cell: Vector2i, player := true) -> VisualUnit:
	var u := EnemyFactory.create_goblin()
	u.is_player_unit = player
	u.max_hp = 100000; u.current_hp = 100000
	u.resistance = 0; u.magic_resist = 0; u.tenacity = 0
	u.battle_manager = mgr
	u.set_meta("anim_preview_lock", true)
	add_child(u)
	check(grid.place_unit(u, cell), "fixture overlap")
	u.grid_position = cell
	u.position = grid.grid_to_world(cell)
	if player: mgr.player_units.append(u)
	else: mgr.enemy_units.append(u)
	return u

func setup(cell := Vector2i(4, 3)) -> void:
	if mgr:
		mgr.triarch_kit.clear()
		for u in mgr.player_units + mgr.enemy_units:
			if is_instance_valid(u): u.queue_free()
		mgr.queue_free(); grid.queue_free()
	grid = BattleGrid.new(); add_child(grid)
	mgr = AutoBattleManager.new(); add_child(mgr); mgr.set_process(false)
	mgr.battle_grid = grid
	boss = EnemyFactory.create_triarch()
	boss.battle_manager = mgr
	boss.set_meta("anim_preview_lock", true)
	add_child(boss)
	check(grid.place_unit(boss, cell), "boss placement")
	boss.grid_position = cell; boss.position = grid.grid_to_world(cell)
	mgr.enemy_units = [boss]; mgr.battle_active = true

func _ready() -> void:
	transition()
	moves()
	echo_test()
	if failures.is_empty(): print("TRIARCH_KIT_PROBE: ALL PASS")
	else:
		for f in failures: print("FAIL: ", f)
		print("TRIARCH_KIT_PROBE: %d FAILURE(S)" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func transition() -> void:
	setup()
	var h := unit(Vector2i(4, 6))
	h.target_unit = boss
	var base_atk := boss.attack_damage
	var base_mr := boss.magic_resist
	var deaths := [0]
	boss.died.connect(func(): deaths[0] += 1)
	var projectiles := Node2D.new(); add_child(projectiles); mgr.projectile_container = projectiles
	var incoming := Projectile.new(); incoming.target_unit = boss; projectiles.add_child(incoming)
	var lethal := Projectile.new(); lethal.target_unit = boss; lethal.caster = h; lethal.damage = 999999
	projectiles.add_child(lethal)
	var hp_before := boss.current_hp
	var dealt_before := h.damage_dealt
	lethal.on_reach_target()
	check(h.damage_dealt - dealt_before == hp_before, "lethal projectile did not finish damage accounting")
	check(lethal.is_queued_for_deletion() and lethal.target_unit == boss, "lethal projectile lost its target inside hit()")
	check(incoming.is_queued_for_deletion(), "incoming projectile survived form change")
	check(boss.has_meta("triarch_transition") and boss.untargetable_time > 0, "transition must reject targeting")
	check(boss.current_hp == 0 and mgr._is_alive(boss), "zero HP form must remain in fight")
	check(h.target_unit == null, "heroes must retarget")
	var damage := boss.damage_dealt
	mgr._tick_unit(boss, 0.3)
	check(boss.damage_dealt == damage and not boss.is_moving, "boss acted during transition")
	boss.current_shield = 100
	boss.take_damage(500, UnitBase.Element.NORMAL, h)
	check(boss.current_shield == 100, "shielded hit landed during transition")
	mgr.paused = true
	mgr._process(1)
	check(mgr.triarch_kit.transitions[boss].time == 0.0, "paused transition moved")
	mgr.paused = false
	mgr.triarch_kit.tick(0.81)
	check(grid.get_unit_at(Vector2i(4, 3)) == null, "take-off cell not freed")
	var dest: Vector2i = mgr.triarch_kit.transitions[boss].landing
	check(dest == Vector2i(0, 0), "Hunter farthest open cell must be (0,0), got %s" % dest)
	check(grid.get_unit_at(dest) == boss, "landing cell not reserved")
	mgr.check_battle_end()
	check(mgr.battle_active, "transition falsely ended fight")
	mgr.triarch_kit.tick(1.38)
	check(int(boss.get_meta("triarch_phase")) == 2 and boss.grid_position == dest, "Hunter did not return")
	check(boss.current_hp == boss.max_hp and boss.attack_damage == roundi(base_atk * 0.85), "Hunter stats/refill incorrect")
	check(boss.effective_magic_resist() == roundi(base_mr * 0.85), "live MR not phase-scaled")
	check(not boss.has_meta("triarch_transition") and boss.untargetable_time == 0, "transition state remained")
	check(deaths[0] == 0, "form change emitted death")
	boss.current_hp = 0; boss.die(); mgr.triarch_kit.tick(2.19)
	check(int(boss.get_meta("triarch_phase")) == 3 and boss.grid_position == Vector2i(4, 0), "Core back-centre landing wrong")
	check(boss.skill_description.contains("220% MAG") and boss.skill_cooldown_max == 6, "Core description/cooldown stale")
	setup(); unit(Vector2i(4, 6))
	boss.current_hp = 0; boss.die(); mgr.triarch_kit.tick(1.0)
	mgr._clear_board_effects()
	check(not boss.has_meta("triarch_transition") and boss.untargetable_time == 0 and boss._aloft_offset == Vector2.ZERO, "reset left transition state")
	check(not grid.occupied_cells.values().has(boss), "reset left reserved cell")

func hp(units: Array) -> Array:
	return units.map(func(u): return u.current_hp)

func moves() -> void:
	setup(Vector2i(4, 3))
	var target := unit(Vector2i(4, 4))
	var left := unit(Vector2i(3, 4))
	var right := unit(Vector2i(5, 4))
	var out := unit(Vector2i(4, 5))
	boss.target_unit = target
	var team := [target, left, right, out]
	var before := hp(team)
	mgr._use_skill(boss, team)
	check(hp(team) == before, "cleave hit before contact")
	mgr._tick_channel(boss, 0.36)
	check(target.current_hp < before[0] and left.current_hp < before[1] and right.current_hp < before[2] and out.current_hp == before[3], "cleave footprint incorrect")
	var far := unit(Vector2i(8, 8))
	target.tenacity = 100
	mgr.triarch_kit.challenge(boss)
	check(target.taunt_time == 1.0 and left.taunt_time == 2.0 and out.taunt_time == 2.0 and far.taunt_time == 0, "Challenge range/Tenacity incorrect")
	EnemyFactory.advance_triarch_phase(boss)
	before = hp(team)
	mgr._use_skill(boss, mgr.player_units)
	check(hp(team) == before, "volley hit before telegraph")
	mgr._tick_channel(boss, 0.59)
	check(hp(team) == before, "volley hit early")
	mgr._tick_channel(boss, 0.02)
	check(target.current_hp < before[0] and left.current_hp < before[1] and right.current_hp < before[2] and out.current_hp == before[3], "volley line hits incorrect")
	check(mgr.triarch_kit.disengage(boss), "Disengage failed with open cells")
	check(grid.get_unit_at(boss.grid_position) == boss, "leap destination not reserved")
	check(not mgr.player_units.any(func(h): return h.grid_position == boss.grid_position), "leap overlapped hero")
	mgr.triarch_kit.tick(0.61)
	check(not boss.has_meta("triarch_leaping"), "leap never completed")
	EnemyFactory.advance_triarch_phase(boss)
	var centres := mgr.triarch_kit.meteor_cells()
	check(centres.size() == 3, "Meteor Storm did not choose 3 distinct cells")
	before = hp(mgr.player_units)
	mgr._use_skill(boss, mgr.player_units)
	mgr._tick_channel(boss, 1.49)
	check(hp(mgr.player_units) == before, "meteor hit before impact")
	mgr._tick_channel(boss, 0.02)
	for i in mgr.player_units.size():
		var h = mgr.player_units[i]
		var hits := 0
		for c in centres:
			if maxi(absi(h.grid_position.x - c.x), absi(h.grid_position.y - c.y)) <= 1: hits += 1
		check(before[i] - h.current_hp == hits * int(boss.magic_power * 2.2), "meteor exact-cell damage mismatch")

func echo_test() -> void:
	setup()
	unit(Vector2i(4, 6))
	EnemyFactory.advance_triarch_phase(boss); EnemyFactory.advance_triarch_phase(boss)
	mgr.unit_summoned.connect(func(u): add_child(u))
	boss.current_hp = boss.max_hp / 2 + 1
	mgr.triarch_kit.secondary(boss, 0.01)
	check(mgr.triarch_kit.echoes.is_empty(), "Echoes fired above half HP")
	boss.current_hp -= 1
	mgr.triarch_kit.secondary(boss, 0.01)
	check(mgr.triarch_kit.echoes.size() == 2, "Echoes not spawned at half HP")
	for e in mgr.triarch_kit.echoes:
		check(e.unit.is_summoned and e.unit.gold_reward == 0 and e.unit.xp_reward == 0 and e.unit.crystal_reward == 0, "Echo rewards/identity wrong")
		check(not e.unit.has_meta("triarch_phase") and e.unit.get_meta("kit_moves").size() == 1, "Echo has extra form/move")
		var p: int = int(e.unit.get_meta("triarch_echo"))
		check(e.unit.max_hp == 550 and e.unit.attack_damage == (10 if p == 1 else 8), "Echo not at 25% form HP/ATK")
		check(grid.get_unit_at(e.unit.grid_position) == e.unit and e.unit.grid_position.y < 4, "Echo placement wrong")
	mgr.triarch_kit.secondary(boss, 0.01)
	check(mgr.triarch_kit.echoes.size() == 2, "Echoes spawned twice")
	mgr.triarch_kit.tick(10.01)
	check(mgr.triarch_kit.echoes.is_empty() and mgr.enemy_units.size() == 1, "Echo expiry failed")
	boss.remove_meta("triarch_echoes_used")
	mgr.triarch_kit.spawn_echoes(boss)
	boss.current_hp = 0; boss.die()
	mgr.triarch_kit.tick(0.01)
	check(mgr.triarch_kit.echoes.is_empty(), "Echoes remained after Core death")
