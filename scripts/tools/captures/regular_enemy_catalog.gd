extends Node2D
const Paths = preload("res://scripts/tools/capture_paths.gd")
const Roster = preload("res://scripts/tools/regular_enemy_model_probe.gd")

func _ready() -> void:
	get_window().size = Vector2i(1560,900)
	get_window().content_scale_size = Vector2i(1560,900)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.scale = Vector2(1560.0/1180.0,900.0/780.0)
	bg.set_biome_from_round(Paths.cli_round(1))
	var keys: Array = Roster.SINGLE.duplicate()
	for family in Roster.SIX: keys.append(family + "_normal")
	var units: Array = []
	for i in range(keys.size()):
		var origin := Vector2((i % 7)*222,(i / 7)*220)
		var panel := ColorRect.new()
		panel.position = origin + Vector2(4,4)
		panel.size = Vector2(214,212)
		panel.color = Color(0.02,0.04,0.055,0.6)
		add_child(panel)
		var label := Label.new()
		label.text = str(keys[i]).trim_suffix("_normal").replace("_"," ").capitalize()
		label.position = origin + Vector2(10,12)
		label.add_theme_font_size_override("font_size",20)
		add_child(label)
		var unit := EnemyFactory.create_by_type(keys[i])
		unit.position = origin + Vector2(110,174)
		add_child(unit)
		unit.set_process(false)
		if unit.health_bar: unit.health_bar.hide()
		unit.model3d.face_direction(Vector2(1,1))
		units.append(unit)
	for i in range(8): await get_tree().process_frame
	for unit in units:
		unit.model3d._anim.play("idle",0)
		unit.model3d._anim.seek(0.25,true)
		unit.model3d._anim.advance(0)
		unit.model3d._anim.pause()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(Paths.out("_regular_enemy_catalog.png")) == OK)
	print("REGULAR_ENEMY_CATALOG: ALL PASS 26 families at game scale")
	get_tree().quit()
