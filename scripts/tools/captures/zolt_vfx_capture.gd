extends AnimPreview

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Deterministic regression frames for Zolt's approved combat presentation.
func _ready() -> void:
	super._ready()
	for i in range(unit_box.item_count):
		if unit_box.get_item_text(i).to_lower() == "zolt":
			unit_box.select(i)
			_spawn_selected()
			break
	panel.visible = false
	await get_tree().process_frame
	await get_tree().process_frame

	caster.attack(dummy_enemy)
	await get_tree().create_timer(0.23).timeout
	await _shot(CapturePaths.out("zolt_vfx_auto.png"))

	_reset_all()
	mgr._chain_lightning(caster, dummy_enemy, mgr.enemy_units, 20.0, 39)
	await get_tree().create_timer(0.16).timeout
	await _shot(CapturePaths.out("zolt_vfx_chain.png"))

	_reset_all()
	_on_ability_pressed()
	await get_tree().create_timer(0.42).timeout
	await _shot(CapturePaths.out("zolt_vfx_storm_charge.png"))
	await get_tree().create_timer(0.22).timeout
	await _shot(CapturePaths.out("zolt_vfx_storm_impact.png"))

	_reset_all()
	_on_ultimate_pressed()
	await get_tree().create_timer(0.16).timeout
	await _shot(CapturePaths.out("zolt_vfx_ultimate.png"))
	await get_tree().create_timer(0.9).timeout
	await _shot(CapturePaths.out("zolt_vfx_stun.png"))
	print("ZOLT_VFX_CAPTURE: ALL PASS")
	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	assert(err == OK, "Zolt VFX capture failed: %s" % path)
