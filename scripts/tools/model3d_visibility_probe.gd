extends Node2D

func _ready() -> void:
	var unit := EnemyFactory.create_by_type("orc_fire")
	unit.position = Vector2(250,200)
	add_child(unit)
	unit.set_process(false)
	unit.model3d._anim.play("attack",0)
	unit.model3d._anim.seek(0.0,true)
	unit.model3d._anim.advance(0)
	unit.model3d._anim.pause()
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var visible_draws := unit.model3d._viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	assert(visible_draws > 0,"Visible body was not rendered")
	var initial := unit.model3d._viewport.get_texture().get_image().get_data().hex_encode().sha256_text()
	unit.hide()
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var hidden_initial := unit.model3d._viewport.get_texture().get_image().get_data().hex_encode().sha256_text()
	unit.model3d._anim.seek(0.3,true)
	unit.model3d._anim.advance(0)
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var hidden := unit.model3d._viewport.get_texture().get_image().get_data().hex_encode().sha256_text()
	assert(hidden == hidden_initial,"Hidden viewport rendered the changed pose")
	unit.show()
	unit.model3d.set_paused(true)
	unit.model3d.set_paused(false)
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var resumed_draws := unit.model3d._viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	assert(resumed_draws > 0,"Shown/resumed body did not render")
	var resumed := unit.model3d._viewport.get_texture().get_image().get_data().hex_encode().sha256_text()
	assert(resumed != initial,"Shown viewport did not render the changed pose")
	print("MODEL3D_VISIBILITY_PROBE: ALL PASS hidden texture frozen, shown texture refreshed")
	get_tree().quit()
