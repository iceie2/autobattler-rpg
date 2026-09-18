extends AnimPreview

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

func _ready() -> void:
	super._ready()
	for i in range(unit_box.item_count):
		if unit_box.get_item_text(i).to_lower() == "sheildor":
			unit_box.select(i)
			_spawn_selected()
			break
	panel.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	# The preview spaces its dummies widely for readability, but its logical
	# grid positions default outside Sheildor's melee/skill range. Keep the
	# readable screen spacing while making both targets adjacent in combat data.
	grid.purge_unit(dummy_ally)
	dummy_ally.grid_position = Vector2i(3, 4)
	grid.place_unit(dummy_ally, dummy_ally.grid_position)
	grid.purge_unit(dummy_enemy)
	dummy_enemy.grid_position = Vector2i(5, 4)
	grid.place_unit(dummy_enemy, dummy_enemy.grid_position)

	# Contact-timed greatshield bash.
	caster.attack(dummy_enemy)
	await get_tree().create_timer((1.0 / caster.attacks_per_second) * 0.48 + 0.06).timeout
	# Re-stage just the visual at the already-proven contact point so this frame
	# evaluates its opening silhouette rather than a later decay frame.
	mgr._spawn_sheildor_point(SheildorVFX.Mode.BASH_IMPACT,
		dummy_enemy.global_position, 0.52, dummy_enemy)
	await get_tree().process_frame
	await _shot(CapturePaths.out("sheildor_vfx_bash.png"))

	_reset_all()
	dummy_ally.current_hp = maxi(1, dummy_ally.max_hp / 3)
	# The combat timer intentionally starts at four seconds. Prime it here so
	# this isolated frame captures the actual proc rather than the quiet wait.
	caster.set_meta("bulwark_t", 0.01)
	mgr._tick_passive(caster, [dummy_enemy], [caster, dummy_ally], 0.02)
	await get_tree().create_timer(0.2).timeout
	await _shot(CapturePaths.out("sheildor_vfx_aura.png"))

	_reset_all()
	dummy_ally.current_hp = maxi(1, dummy_ally.max_hp / 3)
	mgr._sheildor_shield_ally(caster, [caster, dummy_ally])
	await get_tree().create_timer(0.26).timeout
	await _shot(CapturePaths.out("sheildor_vfx_bulwark.png"))

	_reset_all()
	dummy_ally.current_hp = maxi(1, dummy_ally.max_hp / 4)
	mgr._sheildor_guardian_leap(caster, [caster, dummy_ally], [dummy_enemy])
	await get_tree().create_timer(0.12).timeout
	await _shot(CapturePaths.out("sheildor_vfx_leap_tell.png"))
	await get_tree().create_timer(0.33).timeout
	await _shot(CapturePaths.out("sheildor_vfx_leap.png"))
	await get_tree().create_timer(0.32).timeout
	await _shot(CapturePaths.out("sheildor_vfx_leap_land.png"))
	await get_tree().create_timer(0.30).timeout
	await _shot(CapturePaths.out("sheildor_vfx_barriers.png"))
	print("SHEILDOR_VFX_CAPTURE: ALL PASS")
	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	assert(err == OK, "Sheildor VFX capture failed: %s" % path)
