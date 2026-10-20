extends Node
## THROWAWAY: Zolt thunderstorm visual audit on the real board. Delete after use.
var mg = null
var _suppress := false
func _process(_d: float) -> void:
	if not _suppress or mg == null: return
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
	mg._recruit_hero(UnitBase.UnitClass.ZOLT, UnitBase.Element.LIGHTNING, UnitFactory.generate_recruit_rolls())
	await get_tree().process_frame
	mg._recruit_hero(UnitBase.UnitClass.SHEILDOR, UnitBase.Element.NORMAL, UnitFactory.generate_recruit_rolls())
	for i in 7: mg._place_enemy(EnemyFactory.create_goblin(), false)
	if mg._relic_screen and mg._relic_screen.visible: mg._relic_screen.hide()
	mg.close_shop()
	if mg.difficulty_panel: mg.difficulty_panel.set_panel_visible(false)
	mg._pending_round_reward = {}
	for i in 30: await get_tree().process_frame
	_suppress = true
	var abm = mg.auto_battle_manager
	abm.start_battle()
	for e in abm.enemy_units: e.max_hp = 8000; e.current_hp = 8000
	var z = abm.player_units.filter(func(u): return u.unit_class == UnitBase.UnitClass.ZOLT).front()
	for i in 240:
		if i in [20, 70, 120]:
			z.current_mana = z.max_mana; z.skill_cd_time = 0.0
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/f_%03d.png" % [out, i])
	get_tree().quit()
