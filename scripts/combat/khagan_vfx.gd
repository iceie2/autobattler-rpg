extends Node2D
class_name KhaganVFX

# Self-contained, self-cleaning one-shot VFX node for Khagan's wave-10 boss
# beats (dismount transform, later possession/Shell Slam passes). Everything
# it draws is procedural — no imported particle art — so it stays cheap and
# self-explanatory. Spawn with `.new()`, add to a container, then call
# `setup(...)`; the node frees itself once its longest child effect finishes.
# Mirrors SkillEffect's add-then-setup lifecycle (scripts/combat/skill_effect.gd)
# so it slots into the same skill_effect_container without any new plumbing.

var _elapsed: float = 0.0
var _ring_duration: float = 0.45
var _ring_radius: float = 130.0
var _ring_color: Color = Color(0.8, 0.85, 0.9, 0.9)
var _lifetime: float = 0.6
var _dust: GPUParticles2D

func setup(world_pos: Vector2, ring_radius: float, ring_color: Color, ring_duration: float,
		dust_amount: int, dust_color: Color, dust_duration: float) -> void:
	global_position = world_pos
	_ring_radius = ring_radius
	_ring_color = ring_color
	_ring_duration = ring_duration
	_lifetime = max(ring_duration, dust_duration)
	if dust_amount > 0:
		_dust = _build_dust_burst(dust_amount, dust_color, dust_duration)
		add_child(_dust)
		_dust.emitting = true
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _lifetime:
		queue_free()
		return
	if _elapsed <= _ring_duration:
		queue_redraw()

func _draw() -> void:
	if _elapsed > _ring_duration:
		return
	var t: float = _elapsed / _ring_duration
	var radius: float = lerp(_ring_radius * 0.25, _ring_radius, t)
	var col: Color = _ring_color
	col.a *= (1.0 - t)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, col, 5.0, true)

# A small procedurally generated soft dot — no imported texture — used as the
# single particle sprite for the dust burst.
static func _make_dot_texture() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var center := Vector2(8, 8)
	for y in range(16):
		for x in range(16):
			var dist: float = Vector2(x, y).distance_to(center)
			var a: float = pow(clamp(1.0 - dist / 7.0, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _build_dust_burst(amount: int, color: Color, duration: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = amount
	p.lifetime = duration
	p.one_shot = true
	p.explosiveness = 0.9
	p.texture = _make_dot_texture()
	p.z_index = 5

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, 220, 0)
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 140.0
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	mat.color = color
	var fade := Gradient.new()
	fade.set_color(0, Color(color, color.a))
	fade.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	mat.color_ramp = fade_tex
	p.process_material = mat
	return p
