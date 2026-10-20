extends Node2D
class_name Projectile

var start_pos: Vector2
var target_pos: Vector2
var speed: float = 600.0
var damage: int = 0
var element: UnitBase.Element = UnitBase.Element.NORMAL
var is_magic: bool = false   # magic-scaled payloads are mitigated by magic armor
var is_crit: bool = false     # drives gold crit floating text when this lands
var is_basic_auto: bool = false   # a basic attack (component equipment on-hit passives key on this)
var recap_action: int = 0         # caster's skill / ult tag at spawn (run recap breakdown)
var is_seventh_shot: bool = false   # Headhunter passive proc â€” bigger, gold-tinted bullet so it reads as more than a generic crit
var is_true_damage: bool = false   # Shauna Glass Cannon proc â€” bypasses armor/resistance on landing
var is_static_arc: bool = false    # Static auto: jagged live-wire discharge instead of a generic orb
var is_zolt_arc: bool = false      # Zolt auto: compact blue-white storm bolt
var is_tempest_bolt: bool = false # tail-origin magic auto follows combat pause/speed
var is_rift_void: bool = false     # Rift auto: compact violet void pulse
## Lumen auto (2026-10-06): an invisible, near-instant damage carrier. What the
## player sees is LumenVFX's held BEAM, which the manager lights on the swing.
var is_lumen_beam: bool = false
var is_sear_bolt: bool = false     # Sear auto: ember bolt with a trailing wake
var is_lizard_bolt: bool = false    # Lizard Precision Shot: cold piercing bolt
var is_lizard_spit: bool = false    # Basic shot shares the look, not row piercing.
var is_phoenix_lance: bool = false  # Ember Phoenix Cinder Lance: forge-spark bolt
# >= 0 means this bolt PIERCES that board row on arrival instead of damaging a
# single target. The manager owns the row resolution (see resolve_precision_shot)
# so the damage, accounting and VFX live in one place.
var pierce_row: int = -1
var is_ember_arrow: bool = false
var is_goblin_arrow: bool = false
var is_goblin_shaman_orb: bool = false
# Vail is range 4, so her basic attack is a cast, not a swing. Without this
# her auto had only the shared AIR element particles while her abilities got
# bespoke beats, which made her strongest-looking moment her weakest one.
var is_vail_gust: bool = false
var is_crippling_arrow: bool = false
var slow_pct: float = 0.0
var slow_duration: float = 0.0
var focus_stacks: int = 0
var target_unit = null
var target_section: int = 0  # lock the selected snake section; home on its live position
var caster = null          # tracks who fired this for damage_dealt attribution

func live_target_position() -> Vector2:
	if target_unit is UnitBase and is_instance_valid(target_unit):
		return target_unit.section_canvas_position(target_section)
	return target_unit.global_position if target_unit and is_instance_valid(target_unit) else target_pos
var traveled_distance: float = 0.0
var total_distance: float = 0.0

# Muzzle delay: holds the bullet invisible/stationary for this many seconds
# before it actually launches, so it leaves the gun on the animation's fire
# frame instead of at the instant the attack call fires (which used to be
# the instant the attack ANIMATION started too â€” the bullet was already
# halfway to the target before the character finished raising the weapon).
# Set per-hero from PROJECTILE_MUZZLE_DELAY in unit_base.gd; 0.0 (default)
# reproduces the old immediate-launch behavior exactly.
var spawn_delay: float = 0.0
var _launched: bool = false

# Visual
var projectile_size: float = 8.0
var projectile_color: Color = Color.WHITE

# Optional sprite-sheet override (per-hero auto-attack visuals, e.g. Nemi's
# water-slash frames) â€” when sprite_tex is set, _draw() plays a looping frame
# strip instead of the plain colored circle. Unset for every other hero, so
# the default stays exactly what it was.
var sprite_tex: Texture2D = null
var sprite_frame_w: int = 0
var sprite_frame_h: int = 0
var sprite_frame_count: int = 1
var sprite_fps: float = 12.0
var sprite_display_size: Vector2 = Vector2(48, 48)   # max on-screen bounding box, aspect preserved

# Alternate to sprite_tex: a set of separate per-frame textures (e.g. Shauna's
# auto, exported as 8 individual PNGs rather than one strip). When set,
# _draw_sprite_frame() cycles this array instead of slicing sprite_tex.
var sprite_frames: Array[Texture2D] = []
var _sprite_anim_t: float = 0.0

signal hit_target(target)

func _ready():
	if start_pos and target_pos:
		global_position = start_pos
		total_distance = start_pos.distance_to(target_pos)
	_launched = spawn_delay <= 0.0

func setup(from: Vector2, to: Vector2, dmg: int, elem: UnitBase.Element, target = null):
	start_pos = from
	target_pos = to
	damage = dmg
	element = elem
	target_unit = target
	# Don't set position here - wait until added to tree
	total_distance = from.distance_to(to)
	total_distance = from.distance_to(to)
	
	# Set color based on element
	projectile_color = get_element_color(elem)
	queue_redraw()

func _process(delta: float):
	if (is_ember_arrow or is_tempest_bolt) and is_instance_valid(caster) and caster.battle_manager:
		delta *= 0.0 if caster.battle_manager.paused else caster.battle_manager.time_scale
		if delta <= 0.0: return
	if not start_pos or not target_pos:
		queue_free()
		return

	if not _launched:
		# Held at the muzzle: track the caster (who may still be finishing the
		# aim/lunge) instead of sitting frozen at a stale spawn-time position,
		# and re-check the target's live position too so the eventual launch
		# aims at where it actually is, not a spawn-time snapshot.
		spawn_delay -= delta
		if caster and is_instance_valid(caster):
			global_position = caster.global_position
			start_pos = global_position
		if target_unit and is_instance_valid(target_unit):
			target_pos = live_target_position()
		if spawn_delay > 0.0:
			return
		if is_ember_arrow:
			delta = maxf(0.0, -spawn_delay) # only the remaining battle time belongs to flight
		_launched = true
		total_distance = global_position.distance_to(target_pos)
		traveled_distance = 0.0
		if is_static_arc:
			var muzzle_dir := (target_pos - global_position).normalized()
			_spawn_static_point(StaticVFX.Mode.AUTO_MUZZLE, global_position + muzzle_dir * 24.0, 0.28)
		elif is_zolt_arc:
			var muzzle_dir := (target_pos - global_position).normalized()
			_spawn_zolt_point(ZoltVFX.Mode.AUTO_MUZZLE, global_position + muzzle_dir * 24.0, 0.3)

	# Target died mid-flight (e.g. another hit killed it first) â€” fizzle out
	# instead of visibly flying on to hit a corpse.
	if target_unit and is_instance_valid(target_unit) and "current_hp" in target_unit and target_unit.current_hp <= 0:
		queue_free()
		return

	# Home in on the target's CURRENT position every frame. target_pos used to
	# be a one-time snapshot taken at spawn (setup()'s `to` param), so any
	# projectile fired at a unit that then moved â€” knockback, a push/pull
	# effect, retreating mid-flight, anything â€” flew to the empty spot it used
	# to occupy instead of following it. System-wide fix: every ranged
	# hero/enemy routes through this same Projectile class.
	if target_unit and is_instance_valid(target_unit):
		target_pos = live_target_position()

	# Move towards target using global position
	var direction = (target_pos - global_position).normalized()
	var move_amount = speed * delta
	global_position += direction * move_amount
	traveled_distance += move_amount

	if sprite_tex or not sprite_frames.is_empty() or is_static_arc or is_zolt_arc \
			or is_rift_void or is_sear_bolt or is_goblin_arrow or is_goblin_shaman_orb or is_ember_arrow:
		_sprite_anim_t += delta
		queue_redraw()

	# Reached: proximity-based, not the old traveled_distance>=total_distance
	# check â€” that assumed a fixed target_pos and would fire early/late (or
	# never) once homing lets target_pos move frame to frame. The threshold
	# tracks this frame's step size so a fast bullet can't tunnel past a
	# moving target without ever registering as "close enough". total_distance
	# still caps stray flights (e.g. no target_unit at all) from going forever.
	var reach_threshold: float = max(5.0, move_amount)
	if global_position.distance_to(target_pos) < reach_threshold \
			or (not target_unit and traveled_distance >= total_distance):
		on_reach_target()

func on_reach_target():
	if is_static_arc:
		_spawn_static_point(StaticVFX.Mode.AUTO_IMPACT,
			live_target_position(),
			0.42)
	elif is_zolt_arc:
		_spawn_zolt_point(ZoltVFX.Mode.AUTO_IMPACT,
			live_target_position(),
			0.42)
	elif is_rift_void:
		# The void pulse used to simply blink out of existence on contact â€” the
		# only ranged hero auto with no impact beat at all.
		_spawn_rift_point(RiftVFX.Mode.AUTO_IMPACT,
			live_target_position(),
			0.38)
	elif is_sear_bolt:
		_spawn_sear_point(SearVFX.Mode.AUTO_IMPACT,
			live_target_position(),
			0.40)
	elif is_phoenix_lance:
		var pcontainer := get_parent()
		if pcontainer:
			var pfx := PhoenixVFX.new()
			pcontainer.add_child(pfx)
			pfx.setup_point(PhoenixVFX.Mode.LANCE_IMPACT,
				live_target_position(),
				88.0, 0.42)
	elif is_goblin_shaman_orb:
		_spawn_shaman_impact(live_target_position())
	if pierce_row >= 0:
		# Row-piercing bolt: every opponent in the promised row, resolved by the
		# manager. Deliberately does NOT fall through to the single-target block
		# below, or the named target would be hit twice.
		if caster and is_instance_valid(caster) and caster.battle_manager 				and caster.battle_manager.has_method("resolve_precision_shot"):
			caster.battle_manager.resolve_precision_shot(caster, pierce_row, damage)
		hit_target.emit(target_unit)
		queue_free()
		return
	if target_unit and is_instance_valid(target_unit) and target_unit.has_method("take_damage") and target_unit.current_hp > 0:
		var pre_hp: int = target_unit.current_hp
		var was_alive: bool = pre_hp > 0
		var tag_basic: bool = is_basic_auto and is_instance_valid(caster) and "gear_basic_hit" in caster
		if tag_basic:
			caster.gear_basic_hit = true
		# The shot lands frames after its cast: restore the cast's skill / ult tag
		# for this hit only (read by the run recap's damage breakdown, nothing else).
		var prev_action: int = -1
		if recap_action != 0 and is_instance_valid(caster) and "recap_action" in caster:
			prev_action = caster.recap_action
			caster.recap_action = recap_action
		if target_unit is UnitBase and not target_unit.segment_cells.is_empty():
			target_unit.set_meta("projectile_hit_section", target_section)
		target_unit.take_damage(damage, element, caster, is_true_damage, 0, is_magic, is_crit)
		if is_instance_valid(target_unit): target_unit.remove_meta("projectile_hit_section")
		if tag_basic:
			caster.gear_basic_hit = false
		if prev_action >= 0 and is_instance_valid(caster):
			caster.recap_action = prev_action
		var actual: int = max(0, pre_hp - target_unit.current_hp)
		if is_crippling_arrow and actual > 0 and caster and is_instance_valid(caster) \
				and caster.battle_manager:
			caster.battle_manager.apply_slow(target_unit, slow_pct, slow_duration)
		# Credit the damage back to whoever fired this projectile
		if caster and is_instance_valid(caster) and "damage_dealt" in caster:
			caster.damage_dealt += actual
			# Ultimate charge from damage dealt, at 1/4 the rate of damage taken
			# (mirrors melee in UnitBase.attack). Without this, ranged heroes only
			# charged when hit, which back-row units almost never are.
			if caster.has_method("_charge_ultimate"):
				caster._charge_ultimate(actual / 4)
			# Relic lifesteal / on-kill for ranged attackers (mirrors melee in
			# UnitBase.attack).
			if caster.has_method("apply_relic_on_hit"):
				caster.apply_relic_on_hit(target_unit, actual, was_alive)
		if is_ember_arrow and is_instance_valid(caster) and caster.battle_manager:
			var manager = caster.battle_manager
			manager._spawn_ember_fx(EmberVFX.Mode.IMPACT, target_unit.global_position, 0.38, 32.0)
			manager._apply_on_hit_passives(caster, target_unit, manager.enemy_units if caster.is_player_unit else manager.player_units)
		if is_vail_gust:
			_spawn_vail_gust_impact(live_target_position())
		if is_goblin_arrow:
			_spawn_goblin_arrow_impact(live_target_position(), is_crippling_arrow)
			if not is_crippling_arrow and actual > 0 and caster and is_instance_valid(caster) \
					and caster.battle_manager:
				var opponents: Array = caster.battle_manager.enemy_units if caster.is_player_unit \
					else caster.battle_manager.player_units
				caster.battle_manager._apply_on_hit_passives(caster, target_unit, opponents)

	hit_target.emit(target_unit)
	queue_free()

func _spawn_static_point(kind: StaticVFX.Mode, world_pos: Vector2, life: float) -> void:
	var container := get_parent()
	if not container:
		return
	var fx := StaticVFX.new()
	container.add_child(fx)
	fx.setup_point(kind, world_pos, life)

func _spawn_zolt_point(kind: ZoltVFX.Mode, world_pos: Vector2, life: float) -> void:
	var container := get_parent()
	if not container:
		return
	var fx := ZoltVFX.new()
	container.add_child(fx)
	fx.setup_point(kind, world_pos, life)

# Sear's auto was the plain element-tinted circle every unspecialised unit uses.
# An ember bolt: dark smoke core so it reads against the bright grass, hot body,
# white seed, and a tapering wake that points the way it is travelling.
func _draw_sear_bolt() -> void:
	var travel := (target_pos - global_position).normalized()
	if travel == Vector2.ZERO:
		travel = Vector2.UP
	var side := travel.orthogonal()
	var flick: float = sin(_sprite_anim_t * 26.0)
	var tail := -travel * 34.0
	# Smoke wake first, widest at the tail.
	var wake := PackedVector2Array([
		tail + side * (1.0 + flick * 0.6), Vector2.ZERO + side * 6.0,
		Vector2.ZERO - side * 6.0, tail - side * (1.0 + flick * 0.6)])
	draw_colored_polygon(wake, Color(SearVFX.CHAR.r, SearVFX.CHAR.g, SearVFX.CHAR.b, 0.45))
	draw_line(tail * 0.7, Vector2.ZERO,
		Color(SearVFX.EMBER.r, SearVFX.EMBER.g, SearVFX.EMBER.b, 0.85), 7.0)
	draw_circle(Vector2.ZERO, 8.0 + flick * 1.0,
		Color(SearVFX.EMBER.r, SearVFX.EMBER.g, SearVFX.EMBER.b, 0.95))
	draw_circle(Vector2.ZERO, 5.0,
		Color(SearVFX.FLAME.r, SearVFX.FLAME.g, SearVFX.FLAME.b, 1.0))
	draw_circle(Vector2.ZERO, 2.4, SearVFX.HOT)

func _spawn_sear_point(kind: SearVFX.Mode, world_pos: Vector2, life: float) -> void:
	var container := get_parent()
	if not container:
		return
	var fx := SearVFX.new()
	container.add_child(fx)
	fx.setup_point(kind, world_pos, life)

func _spawn_rift_point(kind: RiftVFX.Mode, world_pos: Vector2, life: float) -> void:
	var container := get_parent()
	if not container:
		return
	var fx := RiftVFX.new()
	container.add_child(fx)
	fx.setup_point(kind, world_pos, life)

func _spawn_goblin_arrow_impact(world_pos: Vector2, crippling: bool) -> void:
	var container := get_parent()
	if not container: return
	var fx := GoblinArcherVFX.new()
	container.add_child(fx)
	fx.setup(world_pos, crippling)

func _spawn_vail_gust_impact(world_pos: Vector2) -> void:
	var container := get_parent()
	if not container: return
	var fx := VailVFX.new()
	container.add_child(fx)
	fx.setup_point(VailVFX.Mode.GUST_IMPACT, world_pos, 0.34)

func _spawn_shaman_impact(world_pos: Vector2) -> void:
	var container := get_parent()
	if not container: return
	var fx := GoblinShamanVFX.new()
	container.add_child(fx)
	fx.setup_impact(world_pos, element)

func _draw():
	if not _launched or is_lumen_beam:
		return
	if not sprite_frames.is_empty():
		_draw_sprite_frames_array()
		return
	if sprite_tex:
		_draw_sprite_frame()
		return
	if is_static_arc:
		_draw_static_arc()
		return
	if is_zolt_arc:
		_draw_zolt_arc()
		return
	if is_rift_void:
		_draw_rift_void()
		return
	if is_sear_bolt:
		_draw_sear_bolt()
		return
	if is_ember_arrow:
		EmberVFX.draw_arrow(self, (target_pos - global_position).normalized())
		return
	if is_goblin_arrow:
		_draw_goblin_arrow()
		return
	if is_goblin_shaman_orb:
		_draw_shaman_orb()
		return
	if is_lizard_bolt or is_lizard_spit:
		var colors := LizardVFX.effect_colors(element)
		var travel := (target_pos - global_position).normalized()
		var tail := -travel * 55.0
		draw_line(tail, Vector2.ZERO, Color(colors[0].r, colors[0].g, colors[0].b, 0.25), 10.0, true)
		draw_line(tail, Vector2.ZERO, colors[0], 4.5, true)
		draw_line(tail, Vector2.ZERO, colors[1], 1.8, true)
		LizardVFX.draw_accent(self, element, tail * 0.5 + travel.orthogonal() * 7.0, 5.0, _sprite_anim_t, 0.85)
		return
	# Draw a simple circle projectile
	draw_circle(Vector2.ZERO, projectile_size, projectile_color)
	# Outline
	draw_arc(Vector2.ZERO, projectile_size, 0, TAU, 16, Color.WHITE, 1.5)

# Purple lightning, built on the same three-pass polyline as _draw_zolt_arc so
# the two read as the same PHENOMENON in different hands â€” Zolt's celestial
# blue-white storm vs Rift's violet void discharge. Was a soft round orb, which
# looked like a generic magic missile and shared no language with his kit.
func _draw_rift_void() -> void:
	var travel := (target_pos - global_position).normalized()
	if travel == Vector2.ZERO:
		travel = Vector2.UP
	var side := travel.orthogonal()
	var pts := PackedVector2Array()
	for i in range(9):
		var t := float(i) / 8.0
		var jitter := sin(_sprite_anim_t * 41.0 + float(i) * 5.7) * 5.5 * sin(t * PI)
		pts.append((-travel * 40.0).lerp(Vector2.ZERO, t) + side * jitter)
	draw_polyline(pts, Color(RiftVFX.VOID.r, RiftVFX.VOID.g, RiftVFX.VOID.b, 0.5), 12.0)
	draw_polyline(pts, Color(RiftVFX.ARC.r, RiftVFX.ARC.g, RiftVFX.ARC.b, 0.95), 6.0)
	draw_polyline(pts, RiftVFX.CORE, 2.5)
	# A short counter-fork keeps the head from reading as a plain streak tip.
	var fork := PackedVector2Array([Vector2.ZERO,
		-travel * 13.0 + side * 9.0, -travel * 21.0 + side * 5.0])
	draw_polyline(fork, Color(RiftVFX.ARC.r, RiftVFX.ARC.g, RiftVFX.ARC.b, 0.8), 2.0)
	draw_circle(Vector2.ZERO, 4.5, RiftVFX.CORE)

func _draw_goblin_arrow() -> void:
	var dir := (target_pos - global_position).normalized()
	if dir == Vector2.ZERO: dir = Vector2.RIGHT
	var side := dir.orthogonal()
	# Crippling Arrow is exactly 2Ã— the complete normal-arrow silhouetteâ€”not
	# merely a slightly longer shaftâ€”so players can identify the signature shot
	# immediately in a crowded volley.
	if is_crippling_arrow:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0, 2.0))
	var length := 32.0
	var tail := -dir * length * 0.55
	var tip := dir * length * 0.45
	draw_line(tail - dir * 18.0, tip, Color(0.76, 0.48, 0.12, 0.16), 8.0)
	draw_line(tail, tip, Color(0.30, 0.17, 0.07, 1.0), 4.0)
	draw_line(tail, tip, Color(0.84, 0.58, 0.22, 0.75), 1.5)
	var head := PackedVector2Array([tip + dir * 8.0, tip - dir * 5.0 + side * 6.0,
		tip - dir * 5.0 - side * 6.0])
	draw_colored_polygon(head, Color(0.92, 0.92, 0.72) if not is_crippling_arrow else Color(0.76, 1.0, 0.28))
	draw_line(tail, tail - dir * 8.0 + side * 6.0, Color(0.72, 0.16, 0.08), 3.0)
	draw_line(tail, tail - dir * 8.0 - side * 6.0, Color(0.72, 0.16, 0.08), 3.0)
	for i in range(focus_stacks):
		var mark := tail - dir * (12.0 + i * 5.0)
		draw_line(mark - side * 4.0, mark + side * 4.0, Color(1.0, 0.72, 0.18, 0.85), 2.0)
	if is_crippling_arrow:
		draw_circle(tip, 9.0, Color(0.48, 0.85, 0.14, 0.18))
		draw_circle(tip, 3.0, Color(0.86, 1.0, 0.48, 0.9))

func _draw_shaman_orb() -> void:
	var travel := (target_pos - global_position).normalized()
	if travel == Vector2.ZERO: travel = Vector2.UP
	var side := travel.orthogonal()
	var tail := -travel * 34.0
	var flicker := sin(_sprite_anim_t * 24.0)
	# Smoky broad glow, saturated spirit-flame body, white-hot seed.
	draw_circle(Vector2.ZERO, 13.0 + flicker * 1.5, Color(projectile_color.r, projectile_color.g, projectile_color.b, 0.18))
	var flame := PackedVector2Array([
		tail + side * 8.0, -travel * 10.0 + side * 10.0,
		travel * 10.0, -travel * 9.0 - side * 10.0, tail - side * 5.0])
	draw_colored_polygon(flame, Color(projectile_color.r, projectile_color.g, projectile_color.b, 0.88))
	draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.82, 0.28, 0.92))
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 1.0, 0.88, 1.0))

func _draw_static_arc() -> void:
	var travel := (target_pos - global_position).normalized()
	if travel == Vector2.ZERO:
		travel = Vector2.UP
	var side := Vector2(-travel.y, travel.x)
	var tail := -travel * 54.0
	var pts := PackedVector2Array()
	for i in range(7):
		var t := float(i) / 6.0
		var jitter := sin(_sprite_anim_t * 42.0 + float(i) * 4.7) * 5.0
		if i == 0 or i == 6:
			jitter = 0.0
		pts.append(tail.lerp(Vector2.ZERO, t) + side * jitter)
	# Broad translucent glow, bright cyan body, and a white-hot core keep the
	# bolt readable against both grass and dark units at the 115 px roster scale.
	draw_polyline(pts, Color(0.58, 0.22, 1.0, 0.30), 11.0, false)
	draw_polyline(pts, Color(0.12, 0.88, 1.0, 0.92), 6.0, false)
	draw_polyline(pts, Color(1.0, 0.92, 0.18, 1.0), 2.5, false)
	draw_circle(Vector2.ZERO, 8.0, Color(0.12, 0.88, 1.0, 0.40))
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 0.82, 1.0))

func _draw_zolt_arc() -> void:
	var travel := (target_pos - global_position).normalized()
	if travel == Vector2.ZERO:
		travel = Vector2.UP
	var side := travel.orthogonal()
	var pts := PackedVector2Array()
	for i in range(8):
		var t := float(i) / 7.0
		var jitter := sin(_sprite_anim_t * 36.0 + float(i) * 6.1) * 4.5 * sin(t * PI)
		pts.append((-travel * 44.0).lerp(Vector2.ZERO, t) + side * jitter)
	draw_polyline(pts, Color(0.08, 0.16, 0.52, 0.5), 12.0)
	draw_polyline(pts, Color(0.16, 0.48, 1.0, 0.95), 6.0)
	draw_polyline(pts, Color(0.92, 0.98, 1.0), 2.5)
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.76, 0.22))

# Loops sprite_tex's frame strip while the projectile is in flight â€” same
# "max bounding box, aspect preserved" sizing convention as
# AutoBattleManager._spawn_sprite_sheet_effect, so this reads consistently
# with every other sprite-sheet VFX in the game.
func _draw_sprite_frame() -> void:
	var frame: int = int(_sprite_anim_t * sprite_fps) % sprite_frame_count
	var src := Rect2(frame * sprite_frame_w, 0, sprite_frame_w, sprite_frame_h)
	var aspect: float = float(sprite_frame_w) / float(sprite_frame_h)
	var size: Vector2 = sprite_display_size
	var tint := Color.WHITE
	if is_seventh_shot:
		size *= 2.4
		tint = Color(1.0, 0.84, 0.0)   # matches DamageText.CRIT_COLOR
	var h: float = size.y
	var w: float = h * aspect
	if w > size.x:
		w = size.x
		h = w / aspect
	var dst := Rect2(-w / 2.0, -h / 2.0, w, h)
	draw_texture_rect_region(sprite_tex, dst, src, tint)

func _draw_sprite_frames_array() -> void:
	var frame: int = int(_sprite_anim_t * sprite_fps) % sprite_frames.size()
	var tex := sprite_frames[frame]
	if not tex:
		return
	var aspect: float = float(tex.get_width()) / float(tex.get_height())
	var size: Vector2 = sprite_display_size
	var tint := Color.WHITE
	if is_seventh_shot:
		size *= 2.4
		tint = Color(1.0, 0.84, 0.0)
	var h: float = size.y
	var w: float = h * aspect
	if w > size.x:
		w = size.x
		h = w / aspect
	var dst := Rect2(-w / 2.0, -h / 2.0, w, h)
	draw_texture_rect(tex, dst, false, tint)

func get_element_color(elem: UnitBase.Element) -> Color:
	match elem:
		UnitBase.Element.FIRE:
			return Color(1.0, 0.3, 0.0)  # Orange-red
		UnitBase.Element.WATER:
			return Color(0.2, 0.5, 1.0)  # Blue
		UnitBase.Element.EARTH:
			return Color(0.6, 0.4, 0.2)  # Brown
		UnitBase.Element.AIR:
			return Color(0.8, 1.0, 1.0)  # Light cyan
		UnitBase.Element.LIGHTNING:
			return Color(1.0, 1.0, 0.3)  # Bright yellow
		UnitBase.Element.NORMAL:
			return Color(0.7, 0.7, 0.7)  # Grey
		_:
			return Color.WHITE
