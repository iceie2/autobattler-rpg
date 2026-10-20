extends Node
# ══════════════════════════════════════════════════════════════════════════════
# PERF PROBE (2026-07-04) — measures real frame times during a forced big
# battle inside the ACTUAL main_game scene (not the arena, which has no UI —
# the lag hypothesis is UI rebuild thrash, so the UI must be present).
#
# Run:  godot --headless res://scenes/perf_probe.tscn
# Prints PERF_RESULT lines: avg / p95 / max frame ms for two phases:
#   phase A: side panels in their default (collapsed) state
#   phase B: damage meter + event history + team panel all expanded (worst case)
# Headless removes GPU cost, but the suspected cost (Control node churn +
# layout) is CPU/process-side and shows up here.
# ══════════════════════════════════════════════════════════════════════════════

const HERO_CLASSES := [
	"RIOT", "SABLE", "COAL", "LUMEN", "DOC", "NEMI", "JUNE", "PASTOR",
	"RUSH", "EMBER", "CROSS", "SEAR", "RIFT", "ZOLT", "SHEILDOR",
]
const SAMPLE_SECONDS := 6.0

# 2.5D cost check (2026-09-04): pass `-- --roster=BOUNCER` to fill all 15 slots
# with one class. Every hero in HERO_MODEL_PATHS renders through its own 3D
# SubViewport, so a 15-BOUNCER board is the worst case for the 2D→2.5D switch —
# compare it against `--roster=RUSH` (a 2D hero) on the SAME run length.
# Must be run WINDOWED for that comparison: headless has no GPU, which is
# exactly the cost a per-unit 3D viewport adds.
var mg = null

func _roster() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roster="):
			var only := a.substr(9)
			var out := []
			for i in HERO_CLASSES.size():
				out.append(only)
			return out
	return HERO_CLASSES

func _ready() -> void:
	var mg_scene := load("res://scenes/main_game.tscn") as PackedScene
	mg = mg_scene.instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame
	# Optional reproducible starting roster and per-hero AA comparison. Seed
	# after main_game startup so its initial UI/offer generation cannot shift it.
	var probe_msaa := -1
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			seed(int(argument.substr(7)))
		if argument.begins_with("--msaa="):
			probe_msaa = int(argument.substr(7))

	# ── Force a 15-hero roster ──
	# Raise the level-gated team cap BEFORE placing (find_empty_player_slot
	# refuses past max_player_units — first probe run only placed 4/15).
	mg.max_player_units = 30
	var placed := 0
	var keys: PackedStringArray = UnitBase.UnitClass.keys()
	for cname in _roster():
		var cls: int = keys.find(cname)
		if cls < 0:
			continue
		var u: VisualUnit = UnitFactory.create_unit(cls, UnitBase.Element.NORMAL, true)
		UnitFactory.apply_recruit_rolls(u, UnitFactory.generate_recruit_rolls())
		u.set_level(3)
		var pos: Vector2i = mg.find_empty_player_slot()
		if pos == Vector2i(-1, -1):
			u.queue_free()
			continue
		u.grid_position = pos
		u.position = mg.battle_grid.grid_to_world(pos)
		mg.battle_grid_node.add_child(u)
		if u.model3d and probe_msaa >= 0:
			u.model3d._viewport.msaa_3d = ({0: Viewport.MSAA_DISABLED,
				2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}.get(probe_msaa, Viewport.MSAA_DISABLED))
		if mg.battle_grid.place_unit(u, pos):
			u.home_position = pos
			mg.player_units.append(u)
			u.died.connect(mg._on_unit_died.bind(u))
			u.battle_manager = mg.auto_battle_manager
			u.damage_text_container = mg.damage_text_container
			placed += 1
		else:
			u.queue_free()
	# ── Beef up the enemy side to ~14 units ──
	var enemy_types: Array = []
	var enemy_style := {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--enemies="):
			enemy_types = Array(argument.trim_prefix("--enemies=").split(","))
		if argument.begins_with("--enemy-resolution="):
			enemy_style["resolution"] = int(argument.trim_prefix("--enemy-resolution="))
		if argument.begins_with("--enemy-msaa="):
			enemy_style["msaa"] = {0:Viewport.MSAA_DISABLED,2:Viewport.MSAA_2X,4:Viewport.MSAA_4X}.get(int(argument.trim_prefix("--enemy-msaa=")),Viewport.MSAA_4X)
	for i in range(12):
		var e: VisualUnit = EnemyFactory.create_goblin(4) if enemy_types.is_empty() else EnemyFactory.create_by_type(enemy_types[i % enemy_types.size()])
		var previous_style := Model3DSprite.debug_style_override
		Model3DSprite.debug_style_override = enemy_style
		mg._place_enemy(e, false)
		Model3DSprite.debug_style_override = previous_style
	print("PERF_ENEMY_STYLE: ",enemy_style)

	print("PERF_SETUP: players=%d enemies=%d" % [mg.player_units.size(), mg.enemy_units.size()])
	var starting_stats: Array = []
	for u in mg.player_units:
		starting_stats.append([u.unit_class, u.max_hp, u.max_mana, u.attack_damage])
	print("PERF_STARTING_STATS: ", JSON.stringify(starting_stats).sha256_text(),
		" msaa=", probe_msaa)

	# Make goblins spongy so the battle lasts through both sample phases.
	for e in mg.enemy_units:
		if e and is_instance_valid(e):
			e.max_hp = 200000
			e.current_hp = 200000
			e.attack_damage = 1

	mg.close_shop()
	if mg.difficulty_panel:
		mg.difficulty_panel.set_panel_visible(false)
	mg._pending_round_reward = {}
	mg.game_state.player_ready_for_battle()
	for i in range(30):
		await get_tree().process_frame

	# ── Phase A: default (collapsed) panels ──
	var a := await _sample("A_collapsed")

	# ── Phase B: worst case — expand damage meter, event history, team panel ──
	if not mg._dm_expanded: mg._on_dm_toggle()
	if not mg._eh_expanded: mg._on_eh_toggle()
	if not mg._team_panel_expanded: mg._on_team_toggle()
	for i in range(10):
		await get_tree().process_frame
	var b := await _sample("B_expanded")

	print("PERF_DONE battle_still_active=%s" % str(mg.auto_battle_manager.battle_active))
	get_tree().quit(0 if (a and b) else 1)

func _sample(label: String) -> bool:
	var samples: Array[float] = []
	var cpu_ms := 0.0
	var physics_ms := 0.0
	var draw_calls := 0.0
	var primitives := 0.0
	var t_end := Time.get_ticks_usec() + int(SAMPLE_SECONDS * 1e6)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_usec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - last) / 1000.0)
		cpu_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		last = now
	if samples.is_empty():
		return false
	samples.sort()
	var total := 0.0
	for s in samples: total += s
	var avg := total / samples.size()
	var p95: float = samples[int(samples.size() * 0.95)]
	var mx: float = samples[samples.size() - 1]
	print("PERF_RESULT %s: frames=%d avg=%.2fms p95=%.2fms max=%.2fms (fps~%.0f)"
			% [label, samples.size(), avg, p95, mx, 1000.0 / maxf(avg, 0.001)])
	print("PERF_WORK %s: process=%.2fms physics=%.2fms draws=%.0f primitives=%.0f"
		% [label, cpu_ms / samples.size(), physics_ms / samples.size(),
			draw_calls / samples.size(), primitives / samples.size()])
	return true
