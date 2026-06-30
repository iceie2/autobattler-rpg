extends UnitBase
class_name VisualUnit

@export var shape_size: float = 66.0
@export var outline_width: float = 3.0

# Sprite scale-up — LPC character art sits inside a 64px frame with wide
# transparent margins, so we enlarge it to fill the 80px grid cell properly.
const SPRITE_SCALE_1X := 1.7
const SPRITE_SCALE_2X := 3.4

# AI-generated hero sprites (static Sprite2D, bypasses LPC system)
const HERO_SPRITE_PATHS: Dictionary = {
	UnitBase.UnitClass.NEMI:       "res://assets/using/nemi.png",
	UnitBase.UnitClass.BLOODHOUND: "res://assets/using/bloodhound.png",
	UnitBase.UnitClass.BOUNCER:    "res://assets/using/bouncer.png",
	UnitBase.UnitClass.HEADHUNTER: "res://assets/using/headhunter.png",
	UnitBase.UnitClass.SHAUNA:     "res://assets/using/shauna.png",
	UnitBase.UnitClass.RUSH:       "res://assets/using/rush.png",
	UnitBase.UnitClass.SABLE:      "res://assets/using/sable.png",
	UnitBase.UnitClass.STITCH:     "res://assets/using/stitch.png",
	UnitBase.UnitClass.EMBER:      "res://assets/using/ember.png",
	UnitBase.UnitClass.RIFT:       "res://assets/using/rift.png",
	UnitBase.UnitClass.ZOLT:       "res://assets/using/zolt.png",
	UnitBase.UnitClass.LUMEN:      "res://assets/using/lumen.png",
	UnitBase.UnitClass.STATIC:     "res://assets/using/static.png",
	UnitBase.UnitClass.SPORE:      "res://assets/using/spore.png",
	UnitBase.UnitClass.CROSS:      "res://assets/using/cross.png",
	UnitBase.UnitClass.SEAR:       "res://assets/using/sear.png",
	UnitBase.UnitClass.DOC:        "res://assets/using/doc.png",
	UnitBase.UnitClass.RIOT:       "res://assets/using/riot.png",
	UnitBase.UnitClass.PASTOR:     "res://assets/using/pastor.png",
	UnitBase.UnitClass.SHEILDOR:   "res://assets/using/sheildor.png",
	UnitBase.UnitClass.LORDEE:     "res://assets/using/lordee.png",
	UnitBase.UnitClass.VAIL:       "res://assets/using/vail.png",
}

# AI-generated monster sprites keyed by sprite_folder string
const MONSTER_SPRITE_PATHS: Dictionary = {
	"goblin":        "res://assets/using/goblin.png",
	"goblin_archer": "res://assets/using/goblin_archer.png",
	"goblin_shaman": "res://assets/using/goblin_shaman.png",
	"slime":         "res://assets/using/slime.png",
	"skeleton":      "res://assets/using/skeleton.png",
	"rat":           "res://assets/using/rat.png",
	"orc_brute":     "res://assets/using/orc_brute.png",
	"hill_giant":    "res://assets/using/hill_giant.png",
}
# All hero sprites are normalised to this rendered height (px) regardless of source resolution.
# 166 = what 128px art looked like at the old 1.3× scale — keeps Nemi/Bloodhound unchanged.
const HERO_SPRITE_RENDER_H := 130.0
var sprite_variant: int = -1  # set by factory; -1 = pick randomly in _ready

# Drag and drop
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO       # local coords saved on drag start
var original_global_pos: Vector2 = Vector2.ZERO    # global coords saved on drag start
var can_be_dragged: bool = true
var mouse_down_position: Vector2 = Vector2.ZERO
var drag_threshold: float = 5.0

# Components
var health_bar: HealthBar
var animated_sprite: LPCAnimatedSprite2D
var plain_sprite: Sprite2D   # used for AI-generated hero sprites instead of LPC
var element_glow: Sprite2D

# Animation state
var last_move_direction: Vector2 = Vector2.ZERO
var fill_color: Color = Color(1, 1, 1, 1)

# ── Procedural animation (additive layers) ───────────────────────────────────
# Each behaviour writes its OWN variable; _apply_animation() composites them all
# onto the sprite every frame, so no animation ever fights another. Everything is
# applied to the sprite child (or the _draw transform) — never the unit root, which
# the battle manager owns for grid movement.
var _anim_time: float = 0.0
var _anim_phase: float = 0.0                 # per-unit desync so idles don't sync up
var _base_sprite_scale: Vector2 = Vector2.ONE  # the SPRITE_SCALE set at setup
var _sprite_base_offset: Vector2 = Vector2.ZERO  # bottom-anchors plain sprites
# continuous (idle)
var _bob_offset: Vector2 = Vector2.ZERO
var _breathe_scale: Vector2 = Vector2.ONE
# one-shots (tweened)
var _lunge_offset: Vector2 = Vector2.ZERO    # attack
var _recoil_offset: Vector2 = Vector2.ZERO   # hit knockback
var _punch_scale: Vector2 = Vector2.ONE      # attack stretch
var _hit_squash: Vector2 = Vector2.ONE       # hit squash
var _flash: float = 0.0                       # 0..1 white flash on hit
var _death_rotation: float = 0.0             # topple on death
var _death_alpha: float = 1.0                # fade on death
var _is_dying: bool = false

# Particles (assigned per element in _ready; tune the mapping by previewing
# assets/particle/"Free Preview All.gif" and swapping which "Part N" maps to what).
var attack_particle_pack: String = "Part 2"  # burst when this unit attacks / casts
var hit_particle_pack: String = "Part 1"     # impact when this unit is hit
var death_particle_pack: String = "Part 11"  # fade on death

# Element → {attack/cast burst, hit impact}. Gives each aspect its own flavour
# (fire heroes throw embers, lightning heroes crackle, …) on top of the procedural
# SkillEffect that every ability already spawns.
const ELEMENT_PARTICLES := {
	UnitBase.Element.FIRE:      {"atk": "Part 3",  "hit": "Part 4"},
	UnitBase.Element.WATER:     {"atk": "Part 6",  "hit": "Part 7"},
	UnitBase.Element.EARTH:     {"atk": "Part 8",  "hit": "Part 9"},
	UnitBase.Element.AIR:       {"atk": "Part 10", "hit": "Part 12"},
	UnitBase.Element.LIGHTNING: {"atk": "Part 5",  "hit": "Part 13"},
	UnitBase.Element.NORMAL:    {"atk": "Part 2",  "hit": "Part 1"},
}


func get_class_sprite_folder() -> String:
	match unit_class:
		UnitBase.UnitClass.WARRIOR:    return "warrior"
		UnitBase.UnitClass.RANGER:     return "archer"
		UnitBase.UnitClass.MONK:       return "monk"
		UnitBase.UnitClass.THIEF:      return "thief"
		UnitBase.UnitClass.BLACK_MAGE: return "black_mage"
		UnitBase.UnitClass.WHITE_MAGE: return "white_mage"
		UnitBase.UnitClass.RED_MAGE:   return "red_mage"
		UnitBase.UnitClass.BLOODHOUND: return "warrior"
		UnitBase.UnitClass.BOUNCER:    return "monk"
		UnitBase.UnitClass.HEADHUNTER: return "archer"
		UnitBase.UnitClass.SHAUNA:    return "shauna"
		UnitBase.UnitClass.NEMI:      return "nemi"
		_: return ""

func get_enemy_sprite_override() -> String:
	# Enemy units can override the class-based folder via metadata
	if has_meta("sprite_folder"):
		return str(get_meta("sprite_folder"))
	return ""


func _ready():
	super._ready()

	if sprite_variant == -1:
		sprite_variant = randi() % 3

	element_glow = Sprite2D.new()
	element_glow.texture = _create_glow_texture()
	element_glow.scale = Vector2(1.5, 1.5)
	add_child(element_glow)

	_setup_lpc_sprite()
	_assign_element_particles()

	fill_color = get_element_color()
	if element_glow:
		element_glow.modulate = fill_color
		element_glow.modulate.a = 0.4

	health_bar = HealthBar.new()
	health_bar.placement = HealthBar.BarPlacement.BOTTOM if is_player_unit else HealthBar.BarPlacement.TOP
	add_child(health_bar)
	health_bar.update_hp(current_hp, max_hp)
	health_bar.update_mp(current_mana, max_mana)
	health_bar.update_ult(ultimate_charge, max(ultimate_charge_max, 1))

	health_changed.connect(_on_health_changed)
	mana_changed.connect(_on_mana_changed)
	attacked.connect(_on_attacked)
	took_damage.connect(_on_took_damage)
	shield_changed.connect(_on_shield_changed)
	_anim_phase = randf() * TAU   # so units don't all bob in lockstep
	update_visuals()


func _sprite_variant_count(folder: String) -> int:
	if folder == "hill_giant": return 1
	return 3

func _setup_plain_sprite(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var s := Sprite2D.new()
	s.texture = load(path)
	s.centered = true
	s.z_index = 1
	s.flip_h = not is_player_unit
	# Scale so every hero renders at the same height regardless of source resolution.
	var scale_val: float = HERO_SPRITE_RENDER_H / float(s.texture.get_height())
	s.scale = Vector2(scale_val, scale_val)
	var cell_half: float = 55.0
	var tex_half: float  = HERO_SPRITE_RENDER_H * 0.5
	_sprite_base_offset = Vector2(0.0, cell_half - tex_half)
	s.position = _sprite_base_offset
	add_child(s)
	plain_sprite = s
	_base_sprite_scale = s.scale

func _setup_lpc_sprite() -> void:
	if unit_class in HERO_SPRITE_PATHS:
		_setup_plain_sprite(HERO_SPRITE_PATHS[unit_class])
		return

	var folder: String = get_meta("sprite_folder") if has_meta("sprite_folder") else get_class_sprite_folder()
	if folder == "":
		return

	# Use AI monster sprite if available for this folder
	if MONSTER_SPRITE_PATHS.has(folder):
		var mpath: String = MONSTER_SPRITE_PATHS[folder]
		if ResourceLoader.exists(mpath):
			_setup_plain_sprite(mpath)
			return
	var v: int = sprite_variant % _sprite_variant_count(folder)
	var sprite_path: String = "res://assets/sprites/generated/%s/%d" % [folder, v]

	var lpc = LPCAnimatedSprite2D.new()
	lpc.sprite_frames = SpriteFrames.new()
	lpc.z_index = 1
	lpc.spritesheets_path = sprite_path
	lpc.animation_data = LPCGeneratedAnimData.new()
	add_child(lpc)

	# walk_south is always present in the generated 6-animation sheets
	if lpc.sprite_frames and lpc.sprite_frames.has_animation("walk_south"):
		animated_sprite = lpc
		var idle := "idle_south" if is_player_unit else "idle_north"
		lpc.play(idle)
		# LPC frames have large transparent margins, so the character only fills
		# part of the 64px frame. Scale up so units read at a good size on the grid.
		if cell_size == 2:
			lpc.scale = Vector2(SPRITE_SCALE_2X, SPRITE_SCALE_2X)
		else:
			lpc.scale = Vector2(SPRITE_SCALE_1X, SPRITE_SCALE_1X)
		_base_sprite_scale = lpc.scale   # animations multiply on top of this
	else:
		lpc.queue_free()
		if cell_size == 2:
			shape_size = 80.0


func _on_health_changed(current: int, maximum: int) -> void:
	if health_bar:
		health_bar.update_hp(current, maximum)

func _on_mana_changed(current: int, maximum: int) -> void:
	if health_bar:
		health_bar.update_mp(current, maximum)

func _on_shield_changed(current: int) -> void:
	if health_bar:
		health_bar.update_shield(float(current), float(max_hp))

# ── Attack: anticipation → snappy lunge → ease back, with a stretch punch ─────
func _on_attacked(target) -> void:
	# Melee units lunge toward the target; ranged units fire projectiles instead.
	if attack_range > 1 or _is_dying:
		return
	if not (target and is_instance_valid(target)):
		return
	play_attack(target.global_position - global_position)

# Pick element-themed particle packs (called from _ready once element is set).
func _assign_element_particles() -> void:
	var packs = ELEMENT_PARTICLES.get(current_element, ELEMENT_PARTICLES[UnitBase.Element.NORMAL])
	attack_particle_pack = packs["atk"]
	hit_particle_pack = packs["hit"]

# A particle burst at this unit — used when it fires a skill or ultimate so every
# move reads as an action even before the procedural SkillEffect lands.
func cast_particles() -> void:
	if _is_dying:
		return
	var dir: Vector2 = Vector2.UP if is_player_unit else Vector2.DOWN
	_spawn_particle(attack_particle_pack, 0.35, global_position + dir * 18.0)

func play_attack(dir_world: Vector2) -> void:
	var dir: Vector2 = dir_world.normalized() if dir_world.length() > 0.01 else Vector2.UP
	var peak: Vector2 = dir * 15.0
	# Attack-impact particles at the strike point.
	_spawn_particle(attack_particle_pack, 0.22, global_position + dir * 24.0)

	var t := create_tween()
	# tiny wind-up the other way (anticipation), then lunge, then settle
	t.tween_method(_set_lunge, Vector2.ZERO, -dir * 5.0, 0.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_lunge, -dir * 5.0, peak, 0.07) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_lunge, peak, Vector2.ZERO, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var t2 := create_tween()
	t2.tween_method(_set_punch, Vector2.ONE, Vector2(1.12, 0.9), 0.1)
	t2.tween_method(_set_punch, Vector2(1.12, 0.9), Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Hit: white flash + knockback recoil + squash + particles ────────────────
func _on_took_damage(_amount: int, attacker) -> void:
	if _is_dying:
		return
	var dir := Vector2.UP
	if attacker and is_instance_valid(attacker):
		var d: Vector2 = global_position - attacker.global_position
		if d.length() > 0.01:
			dir = d.normalized()
	play_hit(dir)
	_spawn_particle(hit_particle_pack, 0.05, global_position)

func play_hit(dir: Vector2) -> void:
	var kb: Vector2 = dir * 7.0
	var t := create_tween()
	t.tween_method(_set_recoil, Vector2.ZERO, kb, 0.05).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_recoil, kb, Vector2.ZERO, 0.20) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	var t2 := create_tween()
	t2.tween_method(_set_squash, Vector2.ONE, Vector2(1.15, 0.85), 0.05)
	t2.tween_method(_set_squash, Vector2(1.15, 0.85), Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	create_tween().tween_method(_set_flash, 1.0, 0.0, 0.18)

# ── Death: topple + shrink + fade + particle fade ──────────────────────────
func die() -> void:
	if _is_dying:
		return
	_is_dying = true
	can_be_dragged = false
	died.emit()                       # main_game removes us from arrays + grid now
	if health_bar:
		health_bar.visible = false

	_spawn_particle(death_particle_pack, 0.35, global_position)  # start fading death particles

	var topple: float = 0.5 if randf() > 0.5 else -0.5   # ~28°, random side
	var t := create_tween()
	t.set_parallel(true)
	t.tween_method(_set_death_rot, 0.0, topple, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_method(_set_death_alpha, 1.0, 0.0, 0.35).set_ease(Tween.EASE_IN)
	t.tween_method(_set_punch, _punch_scale, Vector2(0.7, 0.7), 0.35)
	t.set_parallel(false)
	t.tween_callback(queue_free)

# Tween target setters (named so tween_method can't mis-parse an inline lambda).
func _set_lunge(v: Vector2) -> void:       _lunge_offset = v
func _set_recoil(v: Vector2) -> void:      _recoil_offset = v
func _set_punch(v: Vector2) -> void:       _punch_scale = v
func _set_squash(v: Vector2) -> void:      _hit_squash = v
func _set_flash(v: float) -> void:         _flash = v
func _set_death_rot(v: float) -> void:     _death_rotation = v
func _set_death_alpha(v: float) -> void:   _death_alpha = v
# ── Composite all layers and apply to the sprite (or trigger _draw) ──────────
func _apply_animation() -> void:
	var off: Vector2 = _bob_offset + _lunge_offset + _recoil_offset
	var scl: Vector2 = _breathe_scale * _punch_scale * _hit_squash
	if animated_sprite:
		animated_sprite.position = off
		animated_sprite.scale = _base_sprite_scale * scl
		animated_sprite.rotation = _death_rotation
		var m: Color = Color(1, 1, 1, 1).lerp(Color(2.2, 2.2, 2.2, 1), _flash)
		m.a = _death_alpha
		animated_sprite.modulate = m
	elif plain_sprite:
		plain_sprite.position = _sprite_base_offset + off
		plain_sprite.scale = _base_sprite_scale * scl
		plain_sprite.rotation = _death_rotation
		var m: Color = Color(1, 1, 1, 1).lerp(Color(2.2, 2.2, 2.2, 1), _flash)
		m.a = _death_alpha
		plain_sprite.modulate = m
	else:
		queue_redraw()   # shape-drawn units read these layers in _draw()


func _create_glow_texture() -> Texture2D:
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center = Vector2(32, 32)
	var radius = 28.0
	for y in range(64):
		for x in range(64):
			var dist = Vector2(x, y).distance_to(center)
			var alpha = pow(clamp(1.0 - dist / radius, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_anim_time += delta
	# Idle layer: a gentle vertical bob + breathing squash. Phase-shifted per unit
	# so a row of units doesn't pulse in unison (that reads as robotic).
	if not _is_dying:
		var t: float = _anim_time * 3.0 + _anim_phase
		_bob_offset = Vector2(0.0, sin(t) * 2.0)
		_breathe_scale = Vector2(1.0, 1.0 + sin(t + 1.0) * 0.015)
	_apply_animation()
	_update_animation()
	if health_bar and ultimate_charge_max > 0:
		health_bar.update_ult(ultimate_charge, ultimate_charge_max)


func _update_animation() -> void:
	if not animated_sprite:
		return
	var frames = animated_sprite.sprite_frames
	if not frames:
		return

	var curr = animated_sprite.animation

	if curr != "" and not frames.get_animation_loop(curr):
		if animated_sprite.frame < frames.get_frame_count(curr) - 1:
			return

	var dir_suffix = "south"
	if last_move_direction.length() > 0:
		if abs(last_move_direction.x) > abs(last_move_direction.y):
			dir_suffix = "east" if last_move_direction.x > 0 else "west"
		else:
			dir_suffix = "south" if last_move_direction.y > 0 else "north"

	if is_moving and move_target_pos != move_start_pos:
		var want = "walk_" + dir_suffix
		if not frames.has_animation(want):
			want = "walk_south"
		if want != curr:
			animated_sprite.play(want)
		return

	var idle = "idle_south" if is_player_unit else "idle_north"
	if not frames.has_animation(idle):
		idle = "walk_south"
	if idle != curr:
		animated_sprite.play(idle)


func _draw():
	if animated_sprite or plain_sprite:
		return
	# Shape-drawn units read the same animation layers as the sprite path.
	var off: Vector2 = _bob_offset + _lunge_offset + _recoil_offset
	var scl: Vector2 = _breathe_scale * _punch_scale * _hit_squash
	draw_set_transform(off, _death_rotation, scl)
	var color: Color = (fill_color if fill_color else get_element_color()).lerp(Color.WHITE, _flash)
	color.a = _death_alpha
	var outline = Color(1, 1, 1, _death_alpha)
	match unit_class:
		UnitBase.UnitClass.RANGER:     _draw_triangle(color, outline)
		UnitBase.UnitClass.MONK:       _draw_circle(color, outline)
		UnitBase.UnitClass.THIEF:      _draw_diamond(color, outline)
		UnitBase.UnitClass.BLACK_MAGE: _draw_polygon(5, color, outline)
		UnitBase.UnitClass.WHITE_MAGE: _draw_polygon(6, color, outline)
		UnitBase.UnitClass.RED_MAGE:      _draw_star(color, outline)
		UnitBase.UnitClass.BLOODHOUND:    _draw_triangle(color, outline)
		UnitBase.UnitClass.BOUNCER:       _draw_circle(color, outline)
		UnitBase.UnitClass.HEADHUNTER:    _draw_diamond(color, outline)
		UnitBase.UnitClass.SHAUNA:        _draw_triangle(color, outline)
		UnitBase.UnitClass.NEMI:          _draw_polygon(6, color, outline)
		UnitBase.UnitClass.SHEILDOR:      _draw_polygon(5, color, outline)
		UnitBase.UnitClass.LORDEE:        _draw_circle(color, outline)
		UnitBase.UnitClass.NECRO:         _draw_star(color, outline)
		UnitBase.UnitClass.ZOMBIE:        _draw_triangle(color, outline)
		UnitBase.UnitClass.BAT:           _draw_diamond(color, outline)
		# ── Roster expansion (shape-drawn until sprites are dropped in) ──
		UnitBase.UnitClass.DOC:           _draw_polygon(6, color, outline)
		UnitBase.UnitClass.RIOT:          _draw_square(color, outline)
		UnitBase.UnitClass.PASTOR:        _draw_polygon(5, color, outline)
		UnitBase.UnitClass.SABLE:         _draw_diamond(color, outline)
		UnitBase.UnitClass.RUSH:          _draw_triangle(color, outline)
		UnitBase.UnitClass.STITCH:        _draw_star(color, outline)
		UnitBase.UnitClass.COAL:          _draw_circle(color, outline)
		UnitBase.UnitClass.JUNE:          _draw_polygon(6, color, outline)
		UnitBase.UnitClass.CROSS:         _draw_square(color, outline)
		UnitBase.UnitClass.SEAR:         _draw_polygon(5, color, outline)
		UnitBase.UnitClass.EMBER:         _draw_diamond(color, outline)
		UnitBase.UnitClass.RIFT:          _draw_star(color, outline)
		UnitBase.UnitClass.ZOLT:          _draw_star(color, outline)
		UnitBase.UnitClass.LUMEN:         _draw_polygon(5, color, outline)
		UnitBase.UnitClass.STATIC:        _draw_star(color, outline)
		UnitBase.UnitClass.REED:          _draw_polygon(6, color, outline)
		UnitBase.UnitClass.VAIL:          _draw_polygon(6, color, outline)
		UnitBase.UnitClass.SPORE:         _draw_circle(color, outline)
		_:                                _draw_square(color, outline)


func _draw_square(color: Color, outline: Color) -> void:
	var h = shape_size / 2
	var pts = PackedVector2Array([Vector2(-h,-h), Vector2(h,-h), Vector2(h,h), Vector2(-h,h)])
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_triangle(color: Color, outline: Color) -> void:
	var h = shape_size
	var hb = shape_size * 0.866
	var pts = PackedVector2Array([Vector2(0, -h*0.577), Vector2(hb, h*0.433), Vector2(-hb, h*0.433)])
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_circle(color: Color, outline: Color) -> void:
	var r = shape_size / 2
	draw_circle(Vector2.ZERO, r, color)
	draw_arc(Vector2.ZERO, r, 0, TAU, 32, outline, outline_width)

func _draw_diamond(color: Color, outline: Color) -> void:
	var h = shape_size / 2
	var pts = PackedVector2Array([Vector2(0,-h), Vector2(h,0), Vector2(0,h), Vector2(-h,0)])
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_polygon(sides: int, color: Color, outline: Color) -> void:
	var pts = PackedVector2Array()
	for i in sides:
		var a = -PI/2 + i * TAU / sides
		pts.append(Vector2(cos(a), sin(a)) * (shape_size / 2))
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_star(color: Color, outline: Color) -> void:
	var outer = shape_size / 2
	var inner = outer * 0.4
	var pts = PackedVector2Array()
	for i in 5:
		var ao = -PI/2 + i * TAU / 5
		pts.append(Vector2(cos(ao), sin(ao)) * outer)
		var ai = ao + TAU / 10
		pts.append(Vector2(cos(ai), sin(ai)) * inner)
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)


func update_visuals() -> void:
	fill_color = get_element_color()
	if element_glow:
		element_glow.modulate = fill_color
		element_glow.modulate.a = 0.4
	queue_redraw()

func change_element(new_element: Element) -> void:
	super.change_element(new_element)
	update_visuals()


# ── Drag & drop ────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not can_be_dragged:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mouse_pos = get_global_mouse_position()
			if global_position.distance_to(mouse_pos) <= shape_size:
				mouse_down_position = mouse_pos
				drag_offset = global_position - mouse_pos
				original_position = position
				original_global_pos = global_position
		else:
			if is_dragging:
				is_dragging = false
				_set_placement_zone_visible(false)
				_try_place_at_mouse()
				get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if not is_dragging and mouse_down_position != Vector2.ZERO:
			if mouse_down_position.distance_to(get_global_mouse_position()) > drag_threshold:
				is_dragging = true
				_set_placement_zone_visible(true)
				get_viewport().set_input_as_handled()
		if is_dragging:
			global_position = get_global_mouse_position() + drag_offset
			get_viewport().set_input_as_handled()
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			mouse_down_position = Vector2.ZERO


# Show the player placement zone while an allied hero is being dragged.
func _set_placement_zone_visible(v: bool) -> void:
	if not is_player_unit:
		return
	if battle_manager and battle_manager.background_layer:
		battle_manager.background_layer.set_player_zone_visible(v)


func _try_place_at_mouse() -> void:
	if not battle_manager:
		global_position = original_global_pos
		return
	var bg = battle_manager.battle_grid
	if not bg:
		global_position = original_global_pos
		return
	var new_pos = bg.world_to_grid(get_global_mouse_position())
	if not _is_valid_placement(new_pos, bg):
		global_position = original_global_pos
		return
	bg.remove_unit(grid_position)
	if bg.place_unit(self, new_pos):
		grid_position = new_pos
		position = bg.grid_to_world(new_pos)
	else:
		bg.place_unit(self, grid_position)
		global_position = original_global_pos


func _is_valid_placement(pos: Vector2i, bg) -> bool:
	if not bg.is_valid_position(pos):
		return false
	# Player zone = bottom 4 rows; enemy zone = top 4 rows
	var gh: int = bg.grid_height if bg else 14
	return (pos.y >= gh - 4 and pos.y < gh) if is_player_unit else (pos.y >= 0 and pos.y < 4)


# ── Particle effects ──────────────────────────────────────────────────────────
# Each particle PNG is an 832×576 sprite sheet: 13 cols × 9 rows of 64×64 frames.
# We pick a random variant sheet from the pack, then step through its first row.
const _PART_FRAME_SIZE := 64
const _PART_HFRAMES   := 13   # 832 / 64
const _PART_VFRAMES   := 9    # 576 / 64

# Each "Part N" folder numbers its variant sheets differently (Part 1 → 03.png,
# Part 2 → 62.png, …), so we list the folder's real PNGs rather than guessing
# fixed frame numbers. Cached per pack so we only hit the disk once each.
static var _PACK_CACHE: Dictionary = {}

static func _pack_sheets(pack_name: String) -> Array:
	if _PACK_CACHE.has(pack_name):
		return _PACK_CACHE[pack_name]
	var dir := "res://assets/particle/%s" % pack_name
	var sheets: Array = []
	var da := DirAccess.open(dir)
	if da:
		for f in da.get_files():
			# In-editor the folder also holds .import sidecars — keep only real PNGs.
			if f.to_lower().ends_with(".png"):
				sheets.append("%s/%s" % [dir, f])
	sheets.sort()
	_PACK_CACHE[pack_name] = sheets
	return sheets

func _spawn_particle(pack_name: String, duration: float, pos: Vector2) -> void:
	if pack_name.is_empty():
		return
	var png_files: Array = _pack_sheets(pack_name)
	if png_files.is_empty():
		return

	var tex: Texture2D = load(png_files[randi() % png_files.size()])
	if tex == null:
		return
	var fw := _PART_FRAME_SIZE
	var fh := _PART_FRAME_SIZE

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, fw, fh)
	sprite.centered = true
	sprite.global_position = pos
	sprite.scale = Vector2(2.0, 2.0)
	add_child(sprite)

	# Step through first row of frames over the effect duration, then fade out
	var frame_duration := duration / float(_PART_HFRAMES)
	var t := create_tween()
	for f in _PART_HFRAMES:
		var col := f
		t.tween_callback(func(): sprite.region_rect = Rect2(col * fw, 0, fw, fh))
		t.tween_interval(frame_duration)
	t.tween_method(func(v: float): sprite.modulate.a = v, 1.0, 0.0, 0.15)
	t.tween_callback(sprite.queue_free)
