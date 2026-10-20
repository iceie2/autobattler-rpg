extends Node
## THROWAWAY (delete after use). Doc audit on the real board:
##   --fight : Doc + Bouncer vs tanky goblins. f150 Bouncer wounded + Inject ready,
##             f230 Bouncer killed, f250 Field Surgery armed. frames -> --out
##   GODOT --path . --fixed-fps 30 res://scenes/tools/_doc_audit.tscn -- --fight --out=DIR
## Windowed: headless gives empty SubViewports.

var mg = null
var _suppress := false

func _process(_d: float) -> void:
	if not _suppress or mg == null:
		return
	if mg._level_up_screen and mg._level_up_screen.visible: mg._level_up_screen.hide()
	if mg._relic_screen and mg._relic_screen.visible: mg._relic_screen.hide()
	if mg._battle_controls: mg._battle_controls.visible = false

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	mg = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in 30: await get_tree().process_frame
	mg.max_player_units = 40
	mg._recruit_hero(UnitBase.UnitClass.DOC, UnitBase.Element.WATER, UnitFactory.generate_recruit_rolls())
	await get_tree().process_frame
	mg._recruit_hero(UnitBase.UnitClass.BOUNCER, UnitBase.Element.NORMAL, UnitFactory.generate_recruit_rolls())
	for i in 5:
		mg._place_enemy(EnemyFactory.create_goblin(), false)
	if mg._relic_screen and mg._relic_screen.visible: mg._relic_screen.hide()
	mg.close_shop()
	if mg.difficulty_panel: mg.difficulty_panel.set_panel_visible(false)
	mg._pending_round_reward = {}
	for i in 30: await get_tree().process_frame
	_suppress = true
	var abm = mg.auto_battle_manager
	abm.start_battle()
	for e in abm.enemy_units:
		e.max_hp = 5000; e.current_hp = 5000
	var doc = abm.player_units.filter(func(u): return u.unit_class == UnitBase.UnitClass.DOC).front()
	var ally = abm.player_units.filter(func(u): return u.unit_class != UnitBase.UnitClass.DOC).front()
	print("units ", abm.player_units.map(func(u): return u.unit_name))
	var log := FileAccess.open(out + "/pos.csv", FileAccess.WRITE)
	for i in 420:
		if i == 150 and ally:
			ally.current_hp = int(ally.max_hp * 0.35)
			doc.current_mana = doc.max_mana
			doc.skill_cd_time = 0.0
		if i == 230 and ally and is_instance_valid(ally):
			ally.take_damage(ally.current_hp + 9999, UnitBase.Element.NORMAL, null, true)
		if i == 250:
			doc.ultimate_ready = true
		await RenderingServer.frame_post_draw
		var ap = ally.global_position if ally and is_instance_valid(ally) else Vector2.ZERO
		log.store_line("%d,%.1f,%.1f,%s,%.1f,%.1f" % [i, doc.global_position.x, doc.global_position.y, doc.model3d._current, ap.x, ap.y])
		get_viewport().get_texture().get_image().save_png("%s/f_%03d.png" % [out, i])
	log.close()
	get_tree().quit()
