extends Node
# ══════════════════════════════════════════════════════════════════════════════
# GRAPHICS AUDIT — PERFORMANCE BREAKDOWN (2026-10-02). Experiment tool only.
#
# Same forced battle as scripts/arena/perf_probe.gd (15 heroes vs 12 spongy
# goblins inside the real main_game scene, seeded), but it answers a different
# question: WHERE does the frame go, and which change would actually help?
#
# Why not just rerun perf_probe with different settings: the documented runs
# could not separate a setting from battle-to-battle variance (two "identical"
# runs differed by ~10%). Here every A/B toggle happens INSIDE ONE battle, with
# a baseline phase re-sampled between experiments, so drift is visible and
# variance between runs does not enter the comparison.
#
# Per frame it records:
#   frame_ms    wall time between process frames
#   script_ms   time from a first-priority sentinel _process to a last-priority
#               one = every node's _process this frame (battle logic, units,
#               UI, AnimationPlayers). Tweens/physics are outside this window.
#   hero/mon/main CPU+GPU  RenderingServer per-viewport render timers
#
# Production code is not modified. Toggles act on runtime instances only and
# are restored before the next phase.
#
# Run WINDOWED (GPU cost is the point) with an isolated APPDATA:
#   APPDATA=<scratch> Godot --path autobattler-rpg --windowed
#     --resolution 1280x720 --disable-vsync res://scenes/tools/graphics_audit_perf.tscn
#     -- --seed=1234
# ══════════════════════════════════════════════════════════════════════════════

const HERO_CLASSES := [
	"RIOT", "SABLE", "COAL", "LUMEN", "DOC", "NEMI", "JUNE", "PASTOR",
	"RUSH", "EMBER", "CROSS", "SEAR", "RIFT", "ZOLT", "SHEILDOR",
]
const PHASE_SECONDS := 4.0
const SETTLE_FRAMES := 20
var ENEMY_POOL: int = 9500

var mg = null
var _t_first: int = 0
var _script_us: int = 0
var _hero_vps: Array = []      # [SubViewport]
var _mon_vps: Array = []
var _hero_sprites: Array = []  # Model3DSprite (heroes)
var _main_rid: RID
var _stagger_on: bool = false
var _stagger_parity: int = 0
var _t_pre: int = 0
var _render_us: int = 0
var _enemies_pinned: Array = []
var _t_defer: int = 0
var _defer_us: int = 0
func _defer_start() -> void: _t_defer = Time.get_ticks_usec()
func _defer_end() -> void: _defer_us = Time.get_ticks_usec() - _t_defer

class Sentinel extends Node:
	var probe = null
	var is_first: bool = true
	func _process(_d: float) -> void:
		if is_first:
			probe._t_first = Time.get_ticks_usec()
			probe.call_deferred("_defer_start")
		else:
			probe._script_us = Time.get_ticks_usec() - probe._t_first
			probe.call_deferred("_defer_end")

func _arg(key: String, fallback: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return fallback

func _roster() -> Array:
	var custom := _arg("--heroes")
	if custom != "":
		return Array(custom.split(","))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roster="):
			var only := a.substr(9)
			var out := []
			for i in HERO_CLASSES.size():
				out.append(only)
			return out
	return HERO_CLASSES

func _ready() -> void:
	var first := Sentinel.new(); first.probe = self; first.is_first = true
	first.process_priority = -1000000
	add_child(first)
	var last := Sentinel.new(); last.probe = self; last.is_first = false
	last.process_priority = 1000000
	add_child(last)

	var mg_scene := load("res://scenes/main_game.tscn") as PackedScene
	mg = mg_scene.instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			seed(int(argument.substr(7)))
		if argument.begins_with("--pool="):
			ENEMY_POOL = int(argument.substr(7))

	mg.max_player_units = 30
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
		if mg.battle_grid.place_unit(u, pos):
			u.home_position = pos
			mg.player_units.append(u)
			u.died.connect(mg._on_unit_died.bind(u))
			u.battle_manager = mg.auto_battle_manager
			u.damage_text_container = mg.damage_text_container
		else:
			u.queue_free()
	for i in range(int(_arg("--enemies", "12"))):
		var e: VisualUnit = EnemyFactory.create_goblin(4)
		mg._place_enemy(e, false)

	var starting_stats: Array = []
	for u in mg.player_units:
		starting_stats.append([u.unit_class, u.max_hp, u.max_mana, u.attack_damage])
	print("AUDIT_SETUP: players=%d enemies=%d stats=%s" % [mg.player_units.size(),
		mg.enemy_units.size(), JSON.stringify(starting_stats).sha256_text().substr(0, 16)])

	# NOT 200,000 HP like perf_probe.gd: health_bar.gd draws one texture tile
	# per HP segment (500 HP above 2,000), so a 200k pool draws ~402 tiles per
	# redraw against ~16 for a real goblin -- the benchmark was inflating its
	# own canvas cost. 9,500 HP draws ~21 tiles and still survives a big hit;
	# _pin_enemies() refills it every frame so the fight never ends.
	for e in mg.enemy_units:
		if e and is_instance_valid(e):
			e.max_hp = ENEMY_POOL
			e.current_hp = ENEMY_POOL
			e.attack_damage = 1

	_collect_viewports()
	_print_inventory()
	# Whole CPU render pass for the frame (every viewport, sync, submission):
	# the per-viewport timers in run 1 accounted for only ~3ms of a 27ms frame.
	RenderingServer.frame_pre_draw.connect(func(): _t_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): _render_us = Time.get_ticks_usec() - _t_pre)
	for e in mg.enemy_units:
		if e and is_instance_valid(e):
			_enemies_pinned.append(e)

	mg.close_shop()
	if mg.difficulty_panel:
		mg.difficulty_panel.set_panel_visible(false)
	mg._pending_round_reward = {}
	mg.game_state.player_ready_for_battle()
	for i in range(40):
		await get_tree().process_frame

	# First seconds of a fight compile pipelines for every VFX/material the
	# first time it appears. Measure that window on its own, then sample steady
	# state, so first-encounter hitches and per-frame cost are not conflated.
	if "--mode=shots" in OS.get_cmdline_user_args():
		var rnd := int(_arg("--round", "1"))
		mg.background_layer.set_biome_from_round(rnd)
		# The wave-1 relic pick opens over the board as the fight starts. Hide
		# it (do not choose) so the capture shows the battle, not a modal.
		if mg.get("_relic_screen") != null:
			mg._relic_screen.visible = false
		for i in 20:
			_pin_enemies()
			await get_tree().process_frame
		var out_dir := _arg("--out")
		var tag := _arg("--tag", "shot")
		var times := Array(_arg("--times", "1.0,2.5,4.0").split(","))
		var t0 := Time.get_ticks_msec()
		# --cast=skill@0.5,ult@2.0 --caster=SPORE : force that hero's moves at
		# those times so a capture sequence can frame them (audit 2026-10-02).
		var casts: Array = []
		if _arg("--cast") != "":
			for c in _arg("--cast").split(","):
				casts.append([c.get_slice("@", 0), float(c.get_slice("@", 1))])
		var caster_name := _arg("--caster", "")
		if _arg("--speed") != "":
			mg.auto_battle_manager.time_scale = float(_arg("--speed"))
		get_viewport().warp_mouse(Vector2(1900, 1060))   # keep hover tooltips off the board
		for t in times:
			while Time.get_ticks_msec() - t0 < int(float(t) * 1000.0):
				_pin_enemies()
				var now_s := float(Time.get_ticks_msec() - t0) / 1000.0
				for c in casts.duplicate():
					if now_s >= float(c[1]):
						casts.erase(c)
						var abm = mg.auto_battle_manager
						for u in mg.player_units:
							if is_instance_valid(u) and UnitBase.UnitClass.find_key(u.unit_class) == caster_name:
								if c[0] == "skill":
									abm._use_skill(u, mg.enemy_units, mg.player_units)
								else:
									abm._use_ultimate(u, mg.enemy_units, mg.player_units)
								print("CAST ", c[0], " at ", now_s)
				await get_tree().process_frame
			# A shot's save can take longer than the gap to the next time, so the
			# loop above may not iterate at all: give pending casts a chance here
			# too, then let them run a few frames before the capture.
			var fired := false
			for c in casts.duplicate():
				if float(Time.get_ticks_msec() - t0) / 1000.0 >= float(c[1]):
					casts.erase(c)
					fired = true
					for u in mg.player_units:
						if is_instance_valid(u) and UnitBase.UnitClass.find_key(u.unit_class) == caster_name:
							if c[0] == "skill":
								mg.auto_battle_manager._use_skill(u, mg.enemy_units, mg.player_units)
							else:
								mg.auto_battle_manager._use_ultimate(u, mg.enemy_units, mg.player_units)
							print("CAST ", c[0], " (late)")
			if fired:
				for i in 2:
					await get_tree().process_frame
			# --drop_channel_at=T: drop the caster's channel without callbacks,
			# exactly as the round-start reset does (Dawnbreaker linger repro).
			var dca := _arg("--drop_channel_at", "")
			if dca != "" and float(Time.get_ticks_msec() - t0) / 1000.0 >= float(dca) 					and not has_meta("dropped"):
				set_meta("dropped", true)
				for u in mg.player_units:
					if is_instance_valid(u) and UnitBase.UnitClass.find_key(u.unit_class) == caster_name:
						u.channel = null
						u.remove_meta("dawn_ray")
						print("DROPPED channel at ", float(Time.get_ticks_msec() - t0) / 1000.0)
				for i in 4:
					await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := "%s/%s_r%d_t%s.png" % [out_dir, tag, rnd, str(t).replace(".", "p")]
			img.save_png(path)
			print("SHOT ", path, " ", img.get_size())
		get_tree().quit(0)
		return
	if "--mode=vfx_census" in OS.get_cmdline_user_args():
		await _phase("warmup_opening")
		for snap in 4:
			_vfx_census("t%d" % snap)
			for i in 45:
				_pin_enemies()
				await get_tree().process_frame
		get_tree().quit(0)
		return
	if "--mode=inspect_ui" in OS.get_cmdline_user_args():
		await _phase("warmup_opening")
		_inspect_ui()
		get_tree().quit(0)
		return
	if "--mode=ab_fx" in OS.get_cmdline_user_args():
		await _phase("warmup_opening")
		await _run_ab_fx()
		print("AUDIT_DONE battle_active=%s" % str(mg.auto_battle_manager.battle_active))
		get_tree().quit(0)
		return
	if "--mode=ab" in OS.get_cmdline_user_args():
		await _phase("warmup_opening")
		await _run_ab()
		print("AUDIT_DONE battle_active=%s" % str(mg.auto_battle_manager.battle_active))
		get_tree().quit(0)
		return
	var ui: CanvasItem = mg.get_node_or_null("UI") as CanvasItem
	var ui_layer = mg.get_node_or_null("UI")
	var fx: CanvasItem = mg.auto_battle_manager.skill_effect_container
	var dmg: CanvasItem = mg.damage_text_container
	await _phase("warmup_opening")
	await _phase("warmup_2")
	await _phase("base_a")
	await _phase("all_3d_frozen",
		func(): _set_update(_hero_vps, false); _set_update(_mon_vps, false),
		func(): _set_update(_hero_vps, true); _set_update(_mon_vps, true))
	await _phase("base_b")
	await _phase("ui_hidden", func(): ui_layer.visible = false, func(): ui_layer.visible = true)
	await _phase("base_c")
	await _phase("vfx_hidden", func(): fx.visible = false, func(): fx.visible = true)
	await _phase("base_d")
	await _phase("dmgtext_hidden", func(): dmg.visible = false, func(): dmg.visible = true)
	await _phase("base_e")
	await _phase("bars_hidden", func(): _set_bars(false), func(): _set_bars(true))
	await _phase("base_f")
	await _phase("battle_paused", func(): mg.auto_battle_manager.set_paused(true),
		func(): mg.auto_battle_manager.set_paused(false))
	await _phase("base_g")
	_node_histogram("end")
	print("AUDIT_DONE battle_active=%s" % str(mg.auto_battle_manager.battle_active))
	get_tree().quit(0)

func _collect_viewports() -> void:
	_main_rid = get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_main_rid, true)
	for u in mg.player_units + mg.enemy_units:
		if not (u and is_instance_valid(u)) or u.model3d == null:
			continue
		var vp = u.model3d.get("_viewport")
		if vp == null:
			continue
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		if u in mg.player_units:
			_hero_vps.append(vp)
			_hero_sprites.append(u.model3d)
		else:
			_mon_vps.append(vp)

func _print_inventory() -> void:
	print("AUDIT_INVENTORY: hero_3d_viewports=%d monster_3d_viewports=%d 2d_units=%d" % [
		_hero_vps.size(), _mon_vps.size(),
		(mg.player_units.size() + mg.enemy_units.size()) - _hero_vps.size() - _mon_vps.size()])
	for u in mg.player_units + mg.enemy_units:
		if not (u and is_instance_valid(u)):
			continue
		var name_s: String = UnitBase.UnitClass.find_key(u.unit_class) if u in mg.player_units \
			else str(u.get_meta("sprite_folder", "enemy"))
		if u.model3d == null:
			print("  %-14s 2D" % name_s)
			continue
		var m = u.model3d
		var vp = m.get("_viewport")
		print("  %-14s 3D vp=%s msaa=%s toon=%s outline_pbr=%s outline_px=%.1f soft=%s nearest=%s render_h=%.0f" % [
			name_s, str(vp.size), str(vp.msaa_3d), str(m.toon), str(m.outline_with_pbr),
			m.outline_px, str(m.get("outline_soft_edges")), str(m.texture_filter_nearest),
			m.render_height])

func _set_update(vps: Array, on: bool) -> void:
	for vp in vps:
		if is_instance_valid(vp):
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

func _set_msaa(vps: Array, mode: int) -> void:
	for vp in vps:
		if is_instance_valid(vp):
			vp.msaa_3d = mode

var _saved_mats: Dictionary = {}
func _set_outline(on: bool) -> void:
	for m in _hero_sprites:
		if not is_instance_valid(m):
			continue
		var spr = m.get("_sprite")
		if spr == null:
			continue
		if not on:
			_saved_mats[m] = spr.material
			spr.material = null
		elif _saved_mats.has(m):
			spr.material = _saved_mats[m]

func _apply_stagger() -> void:
	# Each 3D viewport renders on alternate frames: half the board per frame.
	# UPDATE_ONCE renders exactly one frame and then idles until set again.
	_stagger_parity = 1 - _stagger_parity
	var all := _hero_vps + _mon_vps
	for i in all.size():
		var vp = all[i]
		if not is_instance_valid(vp):
			continue
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE if (i % 2) == _stagger_parity \
			else SubViewport.UPDATE_DISABLED

func _vp_times(vps: Array) -> Vector2:
	var cpu := 0.0
	var gpu := 0.0
	for vp in vps:
		if not is_instance_valid(vp):
			continue
		if vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			continue
		var rid: RID = vp.get_viewport_rid()
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return Vector2(cpu, gpu)

func _phase(label: String, enter: Callable = Callable(), leave: Callable = Callable()) -> void:
	if enter.is_valid():
		enter.call()
	for i in SETTLE_FRAMES:
		if _stagger_on: _apply_stagger()
		_pin_enemies()
		await get_tree().process_frame
	var rows: Array = []   # [frame, script, hero_cpu, hero_gpu, mon_cpu, mon_gpu, main_cpu, main_gpu, proc, draws]
	var t_end := Time.get_ticks_usec() + int(PHASE_SECONDS * 1e6)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_usec() < t_end:
		if _stagger_on: _apply_stagger()
		_pin_enemies()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var h := _vp_times(_hero_vps)
		var mo := _vp_times(_mon_vps)
		rows.append([float(now - last) / 1000.0, float(_script_us) / 1000.0,
			h.x, h.y, mo.x, mo.y,
			RenderingServer.viewport_get_measured_render_time_cpu(_main_rid),
			RenderingServer.viewport_get_measured_render_time_gpu(_main_rid),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			float(_render_us) / 1000.0,
			float(_defer_us) / 1000.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		last = now
	if leave.is_valid():
		leave.call()
	_report(label, rows)

# Interleaved A/B: short alternating windows cancel the slow drift in battle
# activity that made single 4-second phases disagree by +/-4ms between runs.
const AB_CYCLES := 6
const AB_WINDOW := 1.5
func _run_ab() -> void:
	var ui_layer = mg.get_node("UI")
	var fx: CanvasItem = mg.auto_battle_manager.skill_effect_container
	var right: CanvasItem = null
	for c in ui_layer.get_children():
		if c is Control and c.visible and (c as Control).get_global_rect().position.x > 1500.0:
			right = c
	var toggles: Array = [
		["all_3d_frozen", func(on): _set_update(_hero_vps, not on); _set_update(_mon_vps, not on)],
		["vfx_hidden", func(on): fx.visible = not on],
		["right_panel_hidden", func(on): right.visible = not on],
		["bars_hidden", func(on): _set_bars(not on)],
	]
	for t in toggles:
		var off_rows: Array = []
		var on_rows: Array = []
		for cyc in AB_CYCLES:
			t[1].call(false)
			off_rows.append_array(await _window())
			t[1].call(true)
			on_rows.append_array(await _window())
		t[1].call(false)
		_ab_report(t[0], off_rows, on_rows)

# Per-frame VFX filter for --mode=ab_fx: [script file, mode or -1]. Newly
# spawned matches are hidden every frame while the filter is set.
var _hide_fx: Array = []
func _apply_fx_filter(show_all: bool = false) -> void:
	var stack: Array = mg.auto_battle_manager.skill_effect_container.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var sc = n.get_script()
		if n is CanvasItem and sc and sc.resource_path != "":
			for f in _hide_fx:
				if sc.resource_path.get_file() == f[0] and (f[1] < 0 or n.get("mode") == f[1]):
					(n as CanvasItem).visible = show_all
		for c in n.get_children(): stack.append(c)

func _run_ab_fx() -> void:
	var toggles: Array = [
		["vail_aura_pulse_hidden", [["vail_vfx.gd", 0]]],
		["goblin_pack_aura_hidden", [["goblin_vfx.gd", 0]]],
	]
	for t in toggles:
		var off_rows: Array = []
		var on_rows: Array = []
		for cyc in AB_CYCLES:
			_hide_fx = t[1]; _apply_fx_filter(true); _hide_fx = []
			off_rows.append_array(await _window())
			_hide_fx = t[1]
			on_rows.append_array(await _window())
		_apply_fx_filter(true)
		_hide_fx = []
		_ab_report(t[0], off_rows, on_rows)
		print("AUDIT_STATE after %s battle_active=%s" % [t[0], str(mg.auto_battle_manager.battle_active)])

func _window() -> Array:
	for i in 6:
		_pin_enemies()
		if not _hide_fx.is_empty(): _apply_fx_filter()
		await get_tree().process_frame
	var rows: Array = []
	var t_end := Time.get_ticks_usec() + int(AB_WINDOW * 1e6)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_usec() < t_end:
		_pin_enemies()
		if not _hide_fx.is_empty(): _apply_fx_filter()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		rows.append([float(now - last) / 1000.0, float(_script_us) / 1000.0,
			float(_defer_us) / 1000.0, float(_render_us) / 1000.0])
		last = now
	return rows

func _ab_report(label: String, off_rows: Array, on_rows: Array) -> void:
	var parts: Array = []
	for pair in [["base", off_rows], ["test", on_rows]]:
		var rows: Array = pair[1]
		var f: Array = []
		for r in rows: f.append(r[0])
		f.sort()
		var n := f.size()
		var over := 0
		for x in f:
			if x > 33.34: over += 1
		parts.append("%s n=%d avg=%6.2f p50=%6.2f p95=%6.2f >33=%4.1f%% [scr %4.1f def %4.1f rnd %4.1f]" % [
			pair[0], n, _mean(rows, 0), f[n / 2], f[int(n * 0.95)], 100.0 * over / maxf(n, 1),
			_mean(rows, 1), _mean(rows, 2), _mean(rows, 3)])
	var d := _mean(on_rows, 0) - _mean(off_rows, 0)
	print("AUDIT_AB %-26s %+6.2fms (%+5.1f%%) | %s" % [label, d, 100.0 * d / maxf(_mean(off_rows, 0), 0.001),
		" | ".join(parts)])

func _vfx_census(tag: String) -> void:
	# Everything under the battle's effect container, grouped by script, with
	# how many are long-lived (lifetime >= 60s: persistent auras that redraw
	# every frame for the whole fight) and the current mode where present.
	var fx: Node = mg.auto_battle_manager.skill_effect_container
	var counts := {}
	var persistent := {}
	var stack: Array = fx.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var key: String = n.get_class()
		var sc = n.get_script()
		if sc and sc.resource_path != "":
			key = sc.resource_path.get_file()
		if n.get("mode") != null and sc != null:
			key += "/" + str(n.get("mode"))
		counts[key] = int(counts.get(key, 0)) + 1
		var life = n.get("lifetime")
		if life != null and float(life) >= 60.0:
			persistent[key] = int(persistent.get(key, 0)) + 1
		for c in n.get_children(): stack.append(c)
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	var parts: Array = []
	for k in keys.slice(0, 14):
		parts.append("%s=%d%s" % [k, counts[k], (" (persist %d)" % persistent[k]) if persistent.has(k) else ""])
	print("VFX_CENSUS %s total=%d : %s" % [tag, stack.size() + _sum(counts), ", ".join(parts)])

func _sum(d: Dictionary) -> int:
	var t := 0
	for k in d: t += int(d[k])
	return t

func _inspect_ui() -> void:
	for c in mg.get_node("UI").get_children():
		if not (c is CanvasItem and c.visible):
			continue
		var counts := {}
		var scripts := {}
		var total := 0
		var stack: Array = [c]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			total += 1
			counts[n.get_class()] = int(counts.get(n.get_class(), 0)) + 1
			var sc = n.get_script()
			if sc and sc.resource_path != "":
				scripts[sc.resource_path.get_file()] = true
			for ch in n.get_children(): stack.append(ch)
		var top: Array = []
		for ch in c.get_children(): top.append(str(ch.name))
		var texts: Array = []
		var st2: Array = [c]
		while not st2.is_empty() and texts.size() < 14:
			var n2: Node = st2.pop_back()
			if n2 is Label and (n2 as Label).text.strip_edges() != "":
				texts.append((n2 as Label).text.strip_edges().left(18))
			for ch in n2.get_children(): st2.append(ch)
		print("UI_PANEL %s rect=%s nodes=%d labels=%d progress=%d scripts=%s" % [c.name,
			str((c as Control).get_global_rect()) if c is Control else "-", total,
			int(counts.get("Label", 0)), int(counts.get("ProgressBar", 0)), str(scripts.keys())])
		print("   children: %s" % ", ".join(top.slice(0, 12)))
		print("   label text sample: %s" % " | ".join(texts))

func _set_bars(on: bool) -> void:
	for u in mg.player_units + mg.enemy_units:
		if u and is_instance_valid(u) and u.health_bar:
			u.health_bar.visible = on

func _node_histogram(tag: String) -> void:
	var counts := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var key: String = n.get_class()
		var sc = n.get_script()
		if sc and sc.resource_path != "":
			key = sc.resource_path.get_file()
		counts[key] = int(counts.get(key, 0)) + 1
		for c in n.get_children():
			stack.append(c)
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	var parts: Array = []
	for i in mini(18, keys.size()):
		parts.append("%s=%d" % [keys[i], counts[keys[i]]])
	print("AUDIT_NODES %s total=%d top: %s" % [tag, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), ", ".join(parts)])

func _pin_enemies() -> void:
	for e in _enemies_pinned:
		if e and is_instance_valid(e):
			e.max_hp = ENEMY_POOL
			e.current_hp = ENEMY_POOL
	# Heroes too: run 4 lost its battle ~70s in when goblin abilities wore the
	# player side down, and every later A/B measured an empty board.
	for u in mg.player_units:
		if u and is_instance_valid(u) and u.current_hp > 0:
			u.current_hp = u.max_hp

func _report(label: String, rows: Array) -> void:
	if rows.is_empty():
		print("AUDIT_PHASE %s: no frames" % label)
		return
	var alive := 0
	for e in mg.enemy_units:
		if e and is_instance_valid(e) and e.current_hp > 0: alive += 1
	print("AUDIT_STATE %-16s battle_active=%s enemies_alive=%d" % [label,
		str(mg.auto_battle_manager.battle_active), alive])
	var rp := _mean(rows, 10)
	var sc := _mean(rows, 1)
	var df := _mean(rows, 11)
	print("AUDIT_FRAME %-16s frame=%6.2f = script %5.2f + deferred %5.2f + render_pass %5.2f + rest %5.2f | nodes=%.0f" % [
		label, _mean(rows, 0), sc, df, rp, _mean(rows, 0) - sc - df - rp, _mean(rows, 12)])
	_draw_breakdown(label)
	var frames: Array = []
	for r in rows: frames.append(r[0])
	frames.sort()
	var n := frames.size()
	var avg := _mean(rows, 0)
	var over33 := 0
	var over50 := 0
	for f in frames:
		if f > 33.34: over33 += 1
		if f > 50.0: over50 += 1
	print("AUDIT_PHASE %-16s frames=%3d avg=%6.2f p50=%6.2f p95=%6.2f p99=%6.2f max=%6.2f >33ms=%4.1f%% >50ms=%4.1f%% fps~%.0f" % [
		label, n, avg, frames[n / 2], frames[int(n * 0.95)], frames[mini(n - 1, int(n * 0.99))],
		frames[n - 1], 100.0 * over33 / n, 100.0 * over50 / n, 1000.0 / maxf(avg, 0.001)])
	print("AUDIT_SPLIT %-16s script=%5.2f process_mon=%5.2f | hero cpu=%5.2f gpu=%5.2f | monster cpu=%5.2f gpu=%5.2f | main cpu=%5.2f gpu=%5.2f | draws=%.0f" % [
		label, _mean(rows, 1), _mean(rows, 8), _mean(rows, 2), _mean(rows, 3),
		_mean(rows, 4), _mean(rows, 5), _mean(rows, 6), _mean(rows, 7), _mean(rows, 9)])
	# What do the worst frames have in common? Average the split over the
	# slowest 5% so spikes can be attributed rather than just counted.
	var sorted_rows := rows.duplicate()
	sorted_rows.sort_custom(func(a, b): return a[0] > b[0])
	var k: int = maxi(1, int(n * 0.05))
	var worst := sorted_rows.slice(0, k)
	print("AUDIT_SPIKE %-16s worst%d avg_frame=%6.2f script=%5.2f deferred=%5.2f render_pass=%5.2f rest=%5.2f" % [
		label, k, _mean(worst, 0), _mean(worst, 1), _mean(worst, 11), _mean(worst, 10),
		_mean(worst, 0) - _mean(worst, 1) - _mean(worst, 11) - _mean(worst, 10)])

func _draw_breakdown(label: String) -> void:
	var VIS := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var SHD := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	var CNV := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS
	var DC := RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
	var OB := RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME
	var groups := {"hero": _hero_vps, "monster": _mon_vps}
	var parts: Array = []
	for g in groups:
		var v := 0; var sh := 0; var cv := 0; var ob := 0
		for vp in groups[g]:
			if not is_instance_valid(vp): continue
			var rid: RID = vp.get_viewport_rid()
			v += RenderingServer.viewport_get_render_info(rid, VIS, DC)
			sh += RenderingServer.viewport_get_render_info(rid, SHD, DC)
			cv += RenderingServer.viewport_get_render_info(rid, CNV, DC)
			ob += RenderingServer.viewport_get_render_info(rid, VIS, OB)
		parts.append("%s vis=%d shadow=%d canvas=%d objs=%d" % [g, v, sh, cv, ob])
	var mv := RenderingServer.viewport_get_render_info(_main_rid, VIS, DC)
	var mc := RenderingServer.viewport_get_render_info(_main_rid, CNV, DC)
	parts.append("main vis=%d canvas=%d" % [mv, mc])
	print("AUDIT_DRAWS %-16s %s" % [label, " | ".join(parts)])

func _mean(rows: Array, col: int) -> float:
	var t := 0.0
	for r in rows: t += float(r[col])
	return t / maxf(rows.size(), 1)
