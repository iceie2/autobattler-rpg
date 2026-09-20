extends AnimPreview

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Deterministic captures of June's kit. Same shape as rift/sheildor_vfx_capture:
# drive the REAL combat manager, shoot the frame where each effect is doing its
# readable work.
func _ready() -> void:
	super._ready()
	for i in range(unit_box.item_count):
		if unit_box.get_item_text(i).to_lower() == "june":
			unit_box.select(i)
			_spawn_selected()
			break
	panel.visible = false
	await get_tree().process_frame
	await get_tree().process_frame

	# June is range 1, so pin the dummies adjacent in combat data while keeping
	# the preview's readable screen spacing.
	grid.purge_unit(dummy_enemy)
	dummy_enemy.grid_position = Vector2i(5, 4)
	grid.place_unit(dummy_enemy, dummy_enemy.grid_position)
	grid.purge_unit(dummy_ally)
	dummy_ally.grid_position = Vector2i(3, 4)
	grid.place_unit(dummy_ally, dummy_ally.grid_position)

	# Passive: the persistent aura lattice, then a regen pulse to a hurt ally.
	dummy_ally.current_hp = maxi(1, dummy_ally.max_hp / 3)
	mgr._tick_passive(caster, [dummy_enemy], [caster, dummy_ally], 0.02)
	await get_tree().create_timer(0.30).timeout
	await _shot(CapturePaths.out("june_vfx_aura.png"))
	caster.set_meta("aura_tick_t", 0.0)
	mgr._tick_passive(caster, [dummy_enemy], [caster, dummy_ally], 0.02)
	await get_tree().create_timer(0.18).timeout
	await _shot(CapturePaths.out("june_vfx_aura_pulse.png"))

	# Auto attack, resolved on the measured lead-hand contact (23% of the clip).
	_reset_all()
	await _settle()
	var interval: float = 1.0 / caster.attacks_per_second
	caster.attack(dummy_enemy)
	await get_tree().create_timer(interval * 0.23 + 0.06).timeout
	await _shot(CapturePaths.out("june_vfx_auto_impact.png"))

	# Active: Root — the cuffs must persist for the CC's real duration.
	_reset_all()
	await _settle()
	mgr._june_root(caster, [dummy_enemy])
	await get_tree().create_timer(0.30).timeout
	await _shot(CapturePaths.out("june_vfx_root.png"))
	# Still rooted well into the 3s: the tell has to last as long as the CC.
	await get_tree().create_timer(1.6).timeout
	await _shot(CapturePaths.out("june_vfx_root_sustain.png"))

	# Bloom is deliberately NOT captured here. Its field is built from
	# battle_grid.to_global(cell quads), and this harness parents its effect layer
	# under a 2.5x scaled stage while the grid sits outside it — so the field lands
	# in the wrong place for reasons that have nothing to do with the effect.
	# scenes/tools/june_board_check.tscn renders it on a REAL board instead, and
	# asserts the field's cell count, the aura and the cuffs.

	print("JUNE_VFX_CAPTURE: ALL PASS")
	get_tree().quit()

## Let in-flight effects from the previous stage expire so each capture shows
## exactly one ability.
func _settle() -> void:
	await get_tree().create_timer(1.0).timeout

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	assert(err == OK, "June VFX capture failed: %s" % path)
