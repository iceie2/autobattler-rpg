extends AnimPreview

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Deterministic visual regression capture for Static's complete combat kit.
# Runs the same real-manager preview path as the interactive tool and writes
# project-root PNGs so they can be inspected without timing manual screenshots.

func _ready() -> void:
	super._ready()
	for i in range(unit_box.item_count):
		if unit_box.get_item_text(i).to_lower() == "static":
			unit_box.select(i)
			_spawn_selected()
			break
	panel.visible = false
	await get_tree().process_frame
	await get_tree().process_frame

	# Auto: launch/muzzle, traveling bolt, impact.
	caster.attack(dummy_enemy)
	await get_tree().create_timer(0.27).timeout
	await _shot(CapturePaths.out("static_vfx_auto_launch.png"))
	await get_tree().create_timer(0.58).timeout
	await _shot(CapturePaths.out("static_vfx_auto_impact.png"))

	_reset_all()
	_on_ability_pressed()
	await get_tree().create_timer(0.20).timeout
	await _shot(CapturePaths.out("static_vfx_tripwire.png"))
	await get_tree().create_timer(0.72).timeout
	await _shot(CapturePaths.out("static_vfx_stun_residue.png"))

	_reset_all()
	# The interactive preview intentionally clusters units around stage origin;
	# for Grid, switch to true grid coordinates so the capture verifies the
	# board overlay against the same geometry used by production combat.
	stage.scale = Vector2(0.82, 0.82)
	stage.position = Vector2(565, 105)
	caster.position = grid.grid_to_world(caster.grid_position)
	dummy_ally.position = grid.grid_to_world(dummy_ally.grid_position)
	dummy_enemy.position = grid.grid_to_world(dummy_enemy.grid_position)
	_on_ultimate_pressed()
	await get_tree().create_timer(0.35).timeout
	await _shot(CapturePaths.out("static_vfx_grid_channel.png"))
	await get_tree().create_timer(1.72).timeout
	await _shot(CapturePaths.out("static_vfx_grid_lockdown.png"))
	await get_tree().create_timer(1.0).timeout
	await _shot(CapturePaths.out("static_vfx_grid_sustain.png"))
	print("STATIC_VFX_CAPTURE: ALL PASS")
	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	assert(err == OK, "Static VFX capture failed: %s" % path)
