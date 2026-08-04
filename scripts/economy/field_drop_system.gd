class_name FieldDropSystem
extends Node2D
# ══════════════════════════════════════════════════════════════════════════════
# Generic spawner/vacuum/hover-collect manager for FieldDrop pickups (2026-07-21).
# Crystals and items use this; gold keeps its own GoldCoinSystem (existing,
# untouched to avoid regressing the working coin flow) — but the model is
# identical: drops toss out, idle on the field, then either the player hovers
# one to grab it early or the round-end vacuum sweeps up everything left.
# ══════════════════════════════════════════════════════════════════════════════

signal item_collected(payload)

# Screen-space hover radius (canvas-transformed, same technique main_game
# already uses for the held-item badge tooltip) — generous enough that a
# small ~19px icon is easy to hover without pixel-perfect aim.
const HOVER_RADIUS := 24.0

func spawn(world_pos: Vector2, payload, texture: Texture2D,
		display_scale: float = 0.3, tint: Color = Color(1, 1, 1, 1)) -> void:
	var d := FieldDrop.new()
	d.payload = payload
	d.position = world_pos + Vector2(randf_range(-16.0, 16.0), randf_range(-10.0, 8.0))
	d.setup(texture, display_scale, tint)
	d.collected.connect(func(p): item_collected.emit(p))
	add_child(d)

# THE vacuum: every drop on the field spirals into `target` (a GLOBAL screen
# position), staggered so it reads as a wave. Mirrors GoldCoinSystem.vacuum_all.
func vacuum_all(target: Vector2) -> void:
	var local_target := to_local(target)
	var i := 0
	for c in get_children():
		if c is FieldDrop:
			c.start_vacuum(local_target, float(i) * 0.05)
			i += 1

# Hand-collect: any IDLE drop under the mouse starts vacuuming toward `target`
# immediately, individually, with no stagger delay. Call every frame with the
# current mouse position — repeated calls while still hovering are harmless
# (start_vacuum no-ops once a drop is already vacuuming).
func check_hover(mouse_screen: Vector2, target: Vector2) -> void:
	var local_target := to_local(target)
	for c in get_children():
		if c is FieldDrop and c.state == FieldDrop.State.IDLE:
			var screen_pos: Vector2 = c.get_global_transform_with_canvas().origin
			if screen_pos.distance_to(mouse_screen) <= HOVER_RADIUS:
				c.start_vacuum(local_target, 0.0)
