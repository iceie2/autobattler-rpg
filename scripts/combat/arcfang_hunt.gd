extends Node2D
class_name ArcfangHunt

# One controller per storm wolf. All clocks and drawings advance in combat time.
const INTERVAL := 10.0
const WARNING := 1.5
const PURSUIT := 4.0
const RECOVERY := 2.0
const LAST_RECOVERY := 3.0
const DEFENSE_CUT := 0.4
const SNAP_DELAY := 0.6
const BITE_MULT := 0.95
const SNAP_MULT := 0.5
const GOLD := Color(1.0, 0.83, 0.22)
const BLUE := Color(0.55, 0.86, 1.0)

var unit: UnitBase
var manager: AutoBattleManager
var state := "idle"
var remaining := INTERVAL
var prey: UnitBase
var previous_prey: UnitBase
var baseline: Dictionary = {}
var last_howl_used := false
var bonus_hunt := false
var second_hunt := false
var snap_target: UnitBase
var snap_remaining := 0.0
var trail_from := Vector2.ZERO
var trail_to := Vector2.ZERO
var trail_time := 0.0
var flash_time := 0.0
var bursts: Array = [] # Independent hit positions survive dead/lost targets.
var audio: AudioStreamPlayer
static var thunder: AudioStreamWAV

func setup(owner_unit: UnitBase, mgr: AutoBattleManager, opponents: Array) -> void:
	unit = owner_unit
	manager = mgr
	z_index = 15
	if DisplayServer.get_name() != "headless":
		audio = AudioStreamPlayer.new()
		add_child(audio)
		if thunder == null:
			thunder = _thunder_sound()
		audio.stream = thunder
		audio.volume_db = -15.0
	_snapshot(opponents)
	_sync()

func _process(_dt: float) -> void:
	if audio:
		audio.stream_paused = manager.paused or not manager.battle_active

static func _thunder_sound() -> AudioStreamWAV:
	# Local procedural clap: deterministic noise, no assets or gameplay RNG.
	var rng := RandomNumberGenerator.new()
	rng.seed = 60060
	var sr := 22050
	var data := PackedByteArray()
	data.resize(sr * 2)
	var low := 0.0
	for i in sr:
		var t := float(i) / sr
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.08)
		var envelope := minf(t / 0.003, 1.0) * exp(-t * 6.0)
		var sample := int(clampf((noise * exp(-t * 36.0) * 0.4 + low * 1.8 + sin(TAU * 52.0 * t) * 0.25) * envelope, -1.0, 1.0) * 32767)
		data[i * 2] = sample & 255
		data[i * 2 + 1] = (sample >> 8) & 255
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = sr
	sound.data = data
	return sound

func _eligible(target, opponents: Array) -> bool:
	return manager._is_alive(target) and target in opponents and target.untargetable_time <= 0.0

func _snapshot(opponents: Array) -> void:
	baseline.clear()
	for target in opponents:
		if is_instance_valid(target):
			baseline[target.get_instance_id()] = target.damage_dealt

func pick(opponents: Array, excluded: UnitBase = null) -> UnitBase:
	var best: UnitBase = null
	var score := -1
	for target in opponents:
		if not _eligible(target, opponents) or target == excluded:
			continue
		var recent: int = maxi(0, target.damage_dealt - int(baseline.get(target.get_instance_id(), 0)))
		# Stable roster order breaks ties; attack is only the no-damage tie breaker.
		if best == null or recent > score or (recent == 0 and score == 0 and target.attack_damage > best.attack_damage):
			best = target
			score = recent
	return best

func blocks_actions() -> bool:
	return state in ["warning", "recovery"] or snap_remaining > 0.0

func target(opponents: Array) -> UnitBase:
	return prey if state == "hunt" and _eligible(prey, opponents) else null

func tick(dt: float, opponents: Array) -> void:
	if not manager._is_alive(unit):
		clear()
		return
	trail_time = maxf(0.0, trail_time - dt)
	flash_time = maxf(0.0, flash_time - dt)
	for burst in bursts.duplicate():
		burst.t += dt
		if burst.t >= burst.life: bursts.erase(burst)
	# The delayed contact never survives death, recovery, a lost target, or a stun.
	if snap_remaining > 0.0:
		snap_remaining = maxf(0.0, snap_remaining - dt)
		if unit.stun_time > 0.0:
			snap_remaining = 0.0
			snap_target = null
		elif snap_remaining == 0.0:
			if _eligible(snap_target, opponents) and manager._unit_dist(unit, snap_target) <= unit.skill_range:
				_hit(snap_target, SNAP_MULT, true)
			snap_target = null
	if not last_howl_used and unit.current_hp <= unit.max_hp * 0.4:
		last_howl_used = true
		bonus_hunt = true
		_burst("howl", unit.global_position, unit.global_position, 1.4)
		manager.action_logged.emit("Arcfang's Last Howl — the next hunt strikes twice!", unit.is_player_unit)
	# Stun pauses the warning/pursuit, never grants extra actions during recovery.
	if unit.stun_time > 0.0 and state != "recovery":
		_sync()
		queue_redraw()
		return
	remaining = maxf(0.0, remaining - dt)
	if state == "idle" and remaining == 0.0:
		_begin_warning(opponents)
	elif state == "warning":
		if not _eligible(prey, opponents):
			# A replacement always gets a fresh warning, never an unannounced pounce.
			_begin_warning(opponents, previous_prey if second_hunt else null)
		elif remaining == 0.0:
			_pounce(opponents)
	elif state == "hunt" and (remaining == 0.0 or not _eligible(prey, opponents)):
		previous_prey = prey
		if bonus_hunt and not second_hunt:
			second_hunt = true
			_begin_warning(opponents, previous_prey)
		else:
			_recover()
	elif state == "recovery" and remaining == 0.0:
		state = "idle"
		# Next warning starts 10 seconds after the previous primary warning.
		remaining = maxf(0.0, INTERVAL - WARNING - PURSUIT - RECOVERY)
		if second_hunt:
			remaining = INTERVAL
			bonus_hunt = false
		second_hunt = false
		prey = null
		previous_prey = null
	_sync()
	queue_redraw()

func _begin_warning(opponents: Array, excluded: UnitBase = null) -> void:
	prey = pick(opponents, excluded)
	if prey == null:
		_recover()
		return
	_snapshot(opponents)
	state = "warning"
	remaining = WARNING
	_burst("mark", unit.global_position, prey.global_position, WARNING)
	if unit.has_method("begin_arcfang_rest"):
		unit.begin_arcfang_rest()
	unit.is_moving = false
	manager.unit_paths.erase(unit)
	manager.action_logged.emit("Eye of the Storm: Arcfang marks %s%s." % [prey.unit_name, " — Last Howl" if second_hunt else ""], unit.is_player_unit)

func _pounce(opponents: Array) -> void:
	var grid := manager.battle_grid
	if grid == null or not _eligible(prey, opponents):
		_recover()
		return
	var origin := unit.grid_position
	trail_from = unit.global_position
	grid.purge_unit(unit)
	var dest := Pathfinding.find_nearest_free_origin(prey.grid_position, grid, unit)
	if dest == Vector2i(-1, -1) or not grid.place_unit(unit, dest):
		grid.place_unit(unit, origin)
		_recover()
		return
	unit.grid_position = dest
	unit.position = manager._world_pos_for(unit, dest)
	unit.is_moving = false
	manager.unit_paths.erase(unit)
	unit.target_unit = prey
	trail_to = unit.global_position
	trail_time = 0.45
	_burst("pounce", trail_from, trail_to, 0.65)
	if audio:
		audio.play()
	state = "hunt"
	remaining = PURSUIT
	manager.action_logged.emit("Thunder Run! Arcfang hunts %s for 4 seconds." % prey.unit_name, unit.is_player_unit)

func bite(target_unit: UnitBase) -> void:
	if not manager._is_alive(target_unit) or blocks_actions():
		return
	_hit(target_unit, BITE_MULT, false)
	snap_target = target_unit
	snap_remaining = SNAP_DELAY
	unit.is_moving = false
	manager.unit_paths.erase(unit)
	if unit.has_method("play_skill_attack"):
		unit.play_skill_attack(target_unit)
	_sync()

func _hit(victim: UnitBase, mult: float, magic: bool) -> void:
	var prev_action := unit.recap_action
	unit.recap_action = 1
	var before_hp := victim.current_hp
	var before_shield := victim.current_shield + victim.gear_shield
	var dmg := maxi(1, int(unit.attack_damage * mult * unit.outgoing_damage_multiplier()))
	victim.take_damage(dmg, UnitBase.Element.LIGHTNING, unit, false, 0, magic)
	unit.damage_dealt += maxi(0, before_hp - victim.current_hp) + maxi(0, before_shield - victim.current_shield - victim.gear_shield)
	unit.recap_action = prev_action
	flash_time = 0.3
	_burst("snap" if magic else "bite", unit.global_position, victim.global_position, 0.65 if magic else 0.55)
	if magic:
		manager.action_logged.emit("Thunderjaw's lightning snap strikes %s!" % victim.unit_name, unit.is_player_unit)

func _recover() -> void:
	state = "recovery"
	remaining = LAST_RECOVERY if second_hunt else RECOVERY
	_burst("spent", unit.global_position, unit.global_position, remaining)
	if unit.has_method("begin_arcfang_rest"):
		unit.begin_arcfang_rest()
	snap_target = null
	snap_remaining = 0.0
	unit.is_moving = false
	manager.unit_paths.erase(unit)
	manager.action_logged.emit("Spent Storm: Arcfang is exposed for %.0fs (40%% less armor and magic resist)." % remaining, unit.is_player_unit)

func _sync() -> void:
	if str(unit.get_meta("arcfang_state", "")) in ["warning", "recovery"] and state not in ["warning", "recovery"]:
		if unit.has_method("end_arcfang_rest"):
			unit.end_arcfang_rest()
	unit.set_meta("arcfang_state", state)
	unit.set_meta("arcfang_remaining", remaining)
	unit.set_meta("arcfang_prey", prey)
	unit.set_meta("arcfang_last_howl", last_howl_used)
	unit.set_meta("arcfang_bonus_hunt", bonus_hunt)
	unit.set_meta("arcfang_second_hunt", second_hunt)
	unit.set_meta("arcfang_snap_remaining", snap_remaining)
	unit.set_meta("arcfang_recovery_remaining", remaining if state == "recovery" else 0.0)
	if unit.get("health_bar"):
		unit.health_bar.set_channel(1.0 - remaining / WARNING if state == "warning" else -1.0, GOLD)
	if unit.has_method("_update_arcfang_cooldown_bars"):
		unit._update_arcfang_cooldown_bars()

func clear() -> void:
	if is_instance_valid(unit):
		if unit.has_method("end_arcfang_rest"):
			unit.end_arcfang_rest()
		for key in ["arcfang_state", "arcfang_remaining", "arcfang_prey", "arcfang_last_howl", "arcfang_recovery_remaining", "arcfang_bonus_hunt", "arcfang_second_hunt", "arcfang_snap_remaining"]:
			unit.remove_meta(key)
		if unit.get("health_bar"):
			unit.health_bar.set_channel(-1.0)
	bursts.clear()
	snap_target = null
	prey = null
	hide()
	queue_free()

func _burst(kind: String, from: Vector2, to: Vector2, life: float) -> void:
	bursts.append({"kind": kind, "from": from, "to": to, "t": 0.0, "life": life})
	queue_redraw()

static func timer_rows(owner_unit: UnitBase) -> Array:
	var mode := str(owner_unit.get_meta("arcfang_state", "idle"))
	var left := float(owner_unit.get_meta("arcfang_remaining", INTERVAL))
	var second := bool(owner_unit.get_meta("arcfang_second_hunt", false))
	var bonus := bool(owner_unit.get_meta("arcfang_bonus_hunt", false))
	var next_mark := left
	var next_recovery := left + WARNING + PURSUIT
	var eye_status := "%.1fs" % left
	var run_status := "%.1fs" % (left + WARNING)
	var run_progress := 1.0 - (left + WARNING) / (INTERVAL + WARNING)
	var spent_status := "IN %.1fs" % next_recovery
	var spent_progress := 1.0 - next_recovery / (INTERVAL + WARNING + PURSUIT)
	if mode == "warning":
		next_mark = 0.0; eye_status = "MARKED"
		run_status = "CHARGE %.1fs" % left; run_progress = 1.0 - left / WARNING
		next_recovery = left + PURSUIT + (WARNING + PURSUIT if bonus and not second else 0.0)
	elif mode == "hunt":
		next_mark = left if bonus and not second else left + (LAST_RECOVERY + INTERVAL if second else RECOVERY + 2.5)
		eye_status = "%s%.1fs" % ["SECOND " if bonus and not second else "", next_mark]
		run_status = "HUNT %.1fs" % left; run_progress = left / PURSUIT
		next_recovery = left + (WARNING + PURSUIT if bonus and not second else 0.0)
	elif mode == "recovery":
		next_mark = left + (INTERVAL if second else 2.5); eye_status = "%.1fs" % next_mark
		run_status = "%.1fs" % (next_mark + WARNING); run_progress = 1.0 - (next_mark + WARNING) / (INTERVAL + WARNING)
		spent_status = "ACTIVE %.1fs" % left
		spent_progress = left / (LAST_RECOVERY if second else RECOVERY)
	if mode in ["warning", "hunt"]:
		spent_status = "IN %.1fs" % next_recovery
		spent_progress = 1.0 - next_recovery / (INTERVAL + WARNING + PURSUIT)
	var snap := float(owner_unit.get_meta("arcfang_snap_remaining", 0.0))
	var bite_cd := maxf(owner_unit.skill_cd_time, 0.0)
	var bite_status := "SNAP %.1fs" % snap if snap > 0.0 else ("%.1fs" % bite_cd if bite_cd > 0.0 else "READY")
	if mode in ["warning", "recovery"] and snap <= 0.0 and bite_cd <= 0.0: bite_status = "HELD"
	var howl_status := "AT 40% HP"
	var howl_progress := clampf((1.0 - float(owner_unit.current_hp) / maxf(owner_unit.max_hp, 1)) / 0.6, 0.0, 1.0)
	if owner_unit.get_meta("arcfang_last_howl", false):
		howl_status = "RECOVERING" if second and mode == "recovery" else ("SECOND HUNT" if second else ("ARMED" if bonus else "USED"))
		howl_progress = 1.0 if bonus else 0.0
	return [
		[clampf(1.0 - next_mark / INTERVAL, 0, 1), GOLD, "Eye of the Storm  " + eye_status],
		[clampf(run_progress, 0, 1), BLUE, "Thunder Run  " + run_status],
		[clampf(1.0 - bite_cd / maxf(GearPassives.skill_cooldown(owner_unit), 0.001), 0, 1), Color(1, 0.55, 0.22), "Thunderjaw  " + bite_status],
		[clampf(spent_progress, 0, 1), Color(0.50, 0.73, 0.80), "Spent Storm  " + spent_status],
		[howl_progress, Color(0.76, 0.52, 1.0), "Last Howl  " + howl_status]]

static func description(owner_unit: UnitBase) -> String:
	var text := String(owner_unit.get_meta("passive_desc", ""))
	var mode := str(owner_unit.get_meta("arcfang_state", "idle"))
	var time := float(owner_unit.get_meta("arcfang_remaining", INTERVAL))
	var mark = owner_unit.get_meta("arcfang_prey") if owner_unit.has_meta("arcfang_prey") else null
	if mode in ["warning", "hunt"] and is_instance_valid(mark):
		text += "\n\n%s: %s (%.1fs)." % ["Marked prey" if mode == "warning" else "Hunting", mark.unit_name, time]
	elif mode == "recovery":
		text += "\n\nSpent Storm: %.1fs left; armor %d, magic resist %d." % [time, owner_unit.effective_armor(), owner_unit.effective_magic_resist()]
	else:
		text += "\n\nNext mark in %.1fs." % time
	text += "\nLast Howl: %s." % ("triggered" if owner_unit.get_meta("arcfang_last_howl", false) else "ready below 40% HP")
	return text

func _draw() -> void:
	if not is_instance_valid(unit):
		return
	var wolf := to_local(unit.global_position)
	for burst in bursts:
		_draw_burst(burst)
	if state == "warning" and is_instance_valid(prey):
		var p := to_local(prey.global_position) + Vector2(0, -90)
		var pulse := 1.0 + 0.1 * sin(remaining * 18.0)
		draw_arc(p, 23.0 * pulse, 0, TAU, 32, GOLD, 3.0)
		# Two unmistakable downward fangs above the chosen hero.
		for side in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([p + Vector2(side * 5, -10), p + Vector2(side * 17, -10), p + Vector2(side * 9, 17)]), GOLD)
		draw_arc(wolf, 55.0, -PI, -PI + TAU * (1.0 - remaining / WARNING), 48, BLUE, 4.0)
		_tag(wolf + Vector2(0, -70), "LAST HOWL" if second_hunt else "EYE OF THE STORM", GOLD)
	elif state == "hunt" and is_instance_valid(prey):
		draw_arc(to_local(prey.global_position), 35.0, 0, TAU, 32, GOLD, 2.0)
	elif state == "recovery":
		_tag(wolf + Vector2(0, -70), "SPENT STORM", BLUE)
		draw_arc(wolf, 50.0, 0.2, PI - 0.2, 20, Color(0.45, 0.55, 0.62), 3.0)
		draw_arc(wolf, 50.0, PI + 0.2, TAU - 0.2, 20, Color(0.45, 0.55, 0.62), 3.0)
	if trail_time > 0.0:
		var a := to_local(trail_from)
		var b := to_local(trail_to)
		var points := PackedVector2Array()
		for i in 9:
			points.append(a.lerp(b, i / 8.0) + Vector2(0, 0 if i in [0, 8] else (12 if i % 2 else -12)))
		draw_polyline(points, Color(BLUE, trail_time / 0.45), 9.0)
		draw_polyline(points, Color(1, 1, 1, trail_time / 0.45), 3.0)
	if flash_time > 0.0 and is_instance_valid(snap_target):
		var jaw := to_local(snap_target.global_position) + Vector2(0, -24)
		var gap := 30.0 * flash_time / 0.3
		draw_line(jaw + Vector2(-22, -gap), jaw + Vector2(22, -gap), GOLD, 5.0)
		draw_line(jaw + Vector2(-22, gap), jaw + Vector2(22, gap), BLUE, 5.0)

func _draw_burst(burst: Dictionary) -> void:
	var k: float = clampf(float(burst.t) / float(burst.life), 0, 1)
	var alpha := 1.0 - k
	var origin := to_local(burst.from)
	var hit := to_local(burst.to)
	match str(burst.kind):
		"bite":
			# Two serrated jaw arcs visibly clamp onto the contact point.
			hit += Vector2(0, -25)
			var gap := lerpf(28.0, 3.0, minf(k * 3.0, 1.0))
			for side in [-1.0, 1.0]:
				var pts := PackedVector2Array([hit + Vector2(-38, side * gap), hit + Vector2(0, side * (gap + 13)), hit + Vector2(38, side * gap)])
				draw_polyline(pts, Color(GOLD, alpha), 7.0)
				for x in [-24.0, -8.0, 8.0, 24.0]:
					draw_colored_polygon(PackedVector2Array([hit + Vector2(x - 5, side * gap), hit + Vector2(x + 5, side * gap), hit + Vector2(x, side * (gap - 14))]), Color(1, 0.95, 0.7, alpha))
			draw_arc(hit, 25 + k * 35, 0, TAU, 40, Color(GOLD, alpha * 0.5), 3)
		"snap":
			# Independent snapshot positions: even a lethal snap finishes its effect.
			origin += Vector2(0, -25); hit += Vector2(0, -20)
			_bolt(origin, hit, alpha, 7.0, float(burst.t) * 22)
			for i in 6:
				var dir := Vector2.from_angle(TAU * i / 6.0)
				_bolt(hit + dir * 10, hit + dir * (35 + 55 * k), alpha, 3.0, float(i))
			draw_arc(hit, 15 + k * 80, 0, TAU, 40, Color(BLUE, alpha), 4)
		"pounce":
			for at in [origin, hit]:
				draw_set_transform(at, 0, Vector2(1, 0.45))
				draw_arc(Vector2.ZERO, 25 + k * 95, 0, TAU, 48, Color(BLUE, alpha), 6)
				draw_set_transform(Vector2.ZERO)
			for i in 8:
				var dir := Vector2.from_angle(TAU * i / 8.0)
				_bolt(hit + dir * 18, hit + dir * (50 + 65 * k), alpha, 4, float(i))
		"mark":
			# Lightning gathers around the wolf and etches the target's ground rune.
			for i in 7:
				var dir := Vector2.from_angle(TAU * i / 7.0 + k * 2)
				_bolt(origin + dir * 35, origin + dir * (60 + sin(k * 16 + i) * 12), 0.7, 2, float(i) + k * 10)
			draw_set_transform(hit, 0, Vector2(1, 0.5))
			draw_arc(Vector2.ZERO, 42, 0, TAU, 40, Color(GOLD, 0.75), 3)
			draw_arc(Vector2.ZERO, 52, k * TAU, k * TAU + PI, 24, BLUE, 2)
			draw_set_transform(Vector2.ZERO)
		"spent":
			# Electricity spills out and fades to scattered, extinguished sparks.
			for i in 8:
				var angle := TAU * i / 8.0
				var dir := Vector2.from_angle(angle)
				draw_arc(origin, 55 + k * 65, angle, angle + 0.35, 6, Color(BLUE, alpha * 0.7), 3)
				draw_line(origin + dir * (65 + k * 55), origin + dir * (72 + k * 70), Color(0.5, 0.6, 0.7, alpha), 3)
		"howl":
			for i in 3:
				var wave := fmod(k + float(i) * 0.23, 1.0)
				draw_arc(origin, 25 + wave * 160, 0, TAU, 64, Color(0.76, 0.52, 1, (1.0 - wave) * alpha), 5)
			_tag(origin + Vector2(0, -62), "LAST HOWL", Color(0.85, 0.65, 1))

func _bolt(from: Vector2, to: Vector2, alpha: float, width: float, phase: float) -> void:
	var points := PackedVector2Array()
	var normal := (to - from).normalized().orthogonal()
	for i in 7:
		points.append(from.lerp(to, i / 6.0) + normal * (0 if i in [0, 6] else sin(i * 2.4 + phase) * 12))
	draw_polyline(points, Color(BLUE, alpha), width)
	draw_polyline(points, Color(1, 1, 1, alpha), maxf(1, width * 0.35))

func _tag(at: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_style_box(_tag_box(), Rect2(at + Vector2(-width / 2 - 6, -18), Vector2(width + 12, 25)))
	draw_string(font, at + Vector2(-width / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)

func _tag_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.025, 0.035, 0.07, 0.9)
	box.corner_radius_top_left = 4; box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4; box.corner_radius_bottom_right = 4
	return box
