extends AnimPreview

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Deterministic captures of Rift's purple-lightning kit. Mirrors
# sheildor_vfx_capture.gd: drive the REAL combat manager, then shoot the frame
# where each effect is doing its readable work rather than a decay frame.
func _ready() -> void:
	super._ready()
	for i in range(unit_box.item_count):
		if unit_box.get_item_text(i).to_lower() == "rift":
			unit_box.select(i)
			_spawn_selected()
			break
	panel.visible = false
	await get_tree().process_frame
	await get_tree().process_frame

	# Auto attack: Rift is range 2, so the preview's wide screen spacing already
	# works, but pin the logical cells so targeting is deterministic.
	grid.purge_unit(dummy_enemy)
	dummy_enemy.grid_position = Vector2i(5, 4)
	grid.place_unit(dummy_enemy, dummy_enemy.grid_position)

	var interval: float = 1.0 / caster.attacks_per_second
	caster.attack(dummy_enemy)
	# The release frame: muzzle discharge + bolt leaving the hand (0.34).
	await get_tree().create_timer(interval * 0.34 + 0.04).timeout
	await _shot(CapturePaths.out("rift_vfx_auto_launch.png"))
	# Re-stage the impact at the proven contact point so the frame evaluates its
	# opening silhouette, not whatever the in-flight bolt happened to reach.
	mgr._spawn_rift_point(RiftVFX.Mode.AUTO_IMPACT, dummy_enemy.global_position, 0.38)
	await get_tree().create_timer(0.08).timeout
	await _shot(CapturePaths.out("rift_vfx_auto_impact.png"))

	# Passive: the persistent aura, then a redirect proc arcing to the enemy.
	_reset_all()
	await _settle()
	mgr._tick_passive(caster, [dummy_enemy], [caster, dummy_ally], 0.02)
	await get_tree().create_timer(0.25).timeout
	await _shot(CapturePaths.out("rift_vfx_backlash_aura.png"))
	mgr._spawn_rift_pair(RiftVFX.Mode.BACKLASH_ARC, caster, dummy_enemy, 0.34)
	var aura = mgr._rift_auras.get(caster.get_instance_id())
	if aura and is_instance_valid(aura):
		aura.pulse()
	await get_tree().create_timer(0.11).timeout
	await _shot(CapturePaths.out("rift_vfx_backlash_arc.png"))

	# Active: Tear — damage, seam at the origin, seam at the random edge landing.
	# _reset_all() resets UNITS, not in-flight VFX; without the settle the still-
	# living Backlash arc from the previous stage re-aimed at the banished target
	# and streaked across this frame.
	_reset_all()
	await _settle()
	# The board is GRASS, and these captures used to run on AnimPreview's flat
	# dark colour, where violet-on-black flatters everything. Rift's own body is
	# violet too, so the only honest question is whether his effects separate
	# from HIM on the real ground. Sampled from the live board capture
	# (captures/renders/normal/_model3d_board_rift.png): RGB 89,109,52.
	# NOTE this is still a flat colour, not the textured BackgroundLayer — see
	# the capture-harness note in the report. Closer, not correct.
	bg_rect.color = Color(0.349, 0.427, 0.204)
	mgr._rift_tear(caster, [dummy_enemy])
	await get_tree().create_timer(0.14).timeout
	await _shot(CapturePaths.out("rift_vfx_tear.png"))

	# Tear, as the PORTAL DROP (owner 2026-10-01). Three frames along the one
	# sequence, because a single still cannot show a fall: the mouth opening
	# under the victim, the body sunk into it, and the body dropping out of the
	# second mouth at the destination. Times track play_portal_drop's
	# sink 0.34 / hang 0.12 / drop 0.38.
	# Pin the victim to a cell that is actually ON SCREEN first. The banish
	# destination is a RANDOM open edge cell, so without this the victim (and
	# both of its mouths) can land outside the preview's view and the capture
	# silently shows an empty board -- which is exactly what it did first time.
	_reset_all()
	await _settle()
	grid.purge_unit(dummy_enemy)
	dummy_enemy.grid_position = Vector2i(5, 4)
	grid.place_unit(dummy_enemy, dummy_enemy.grid_position)
	dummy_enemy.position = mgr._world_pos_for(dummy_enemy, dummy_enemy.grid_position)
	await get_tree().process_frame
	mgr._rift_tear(caster, [dummy_enemy])
	await get_tree().create_timer(0.12).timeout
	await _shot(CapturePaths.out("rift_vfx_portal_open.png"))
	await get_tree().create_timer(0.20).timeout
	await _shot(CapturePaths.out("rift_vfx_portal_sunk.png"))
	await get_tree().create_timer(0.34).timeout
	await _shot(CapturePaths.out("rift_vfx_portal_drop.png"))

	# Ultimate: Collapse — telegraph, convergence, implosion.
	_reset_all()
	await _settle()
	grid.purge_unit(dummy_enemy)
	dummy_enemy.grid_position = Vector2i(6, 1)
	grid.place_unit(dummy_enemy, dummy_enemy.grid_position)
	dummy_enemy.position = mgr._world_pos_for(dummy_enemy, dummy_enemy.grid_position)
	mgr._rift_collapse(caster, [dummy_enemy])
	await get_tree().create_timer(0.18).timeout
	await _shot(CapturePaths.out("rift_vfx_collapse_telegraph.png"))
	await get_tree().create_timer(0.44).timeout
	await _shot(CapturePaths.out("rift_vfx_collapse_implosion.png"))

	print("RIFT_VFX_CAPTURE: ALL PASS")
	get_tree().quit()

## Let every in-flight effect from the previous stage expire so each capture
## shows exactly one ability.
func _settle() -> void:
	await get_tree().create_timer(1.0).timeout

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	assert(err == OK, "Rift VFX capture failed: %s" % path)
