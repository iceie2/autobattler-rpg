extends Node
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
var failures: Array[String] = []
var captures := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func shot(tag: String) -> void:
	if not captures: return
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(CapturePaths.out("camp_" + tag + ".png"))

func _ready() -> void:
	if not "camp-check" in OS.get_environment("APPDATA"):
		push_error("CAMP_CHECK requires an isolated APPDATA folder containing camp-check.")
		get_tree().quit(2)
		return
	captures = "--capture" in OS.get_cmdline_user_args()
	if captures: get_window().size = Vector2i(1920, 1080)
	seed(482)
	var mg = load("res://scenes/main_game.tscn").instantiate()
	add_child(mg)
	for i in range(30): await get_tree().process_frame
	mg._relic_screen.hide()
	mg._hero_shop.hide()
	mg._call_to_arms_pending = false
	mg.game_state.battle_round = 1
	mg._recruit_hero(UnitBase.UnitClass.RIOT, UnitBase.Element.NORMAL, {})
	var hero = mg.player_units[0]
	hero.current_hp = 1
	var gold: int = mg.game_state.gold
	var round_before: int = mg.game_state.battle_round
	var node: Dictionary = mg._run_map.available_next()[0]
	node["type"] = RunMap.NodeType.CAMP
	mg._on_map_node_chosen(node)
	check(mg._camp_screen.visible and mg._run_flags["camp_actions"] == 2, "map opens camp with two actions")
	check(mg.game_state.battle_round == round_before, "camp advances zero rounds")
	check(mg._any_modal_open(), "camp covers board UI")
	await shot("1920_rest")
	mg._on_camp_activity("reforge", EquipmentItem.new("Sword", 0), "")
	check(mg._run_flags["camp_actions"] == 2, "stale item consumes no action")
	mg._on_camp_activity("rest", null, "")
	check(hero.current_hp == mini(hero.max_hp, 1 + maxi(1, roundi(hero.max_hp * 0.5))), "rest heals half maximum HP")
	check(mg._run_flags["camp_actions"] == 1, "rest spends one action")
	var saved := RunSave.read_data()
	check(saved["run_flags"]["camp_actions"] == 1 and saved["run_flags"]["camp_active"], "camp progress saved")
	await shot("1920_one_action")
	mg._resume_run()
	check(mg._camp_screen.visible and mg._run_flags["camp_actions"] == 1, "resume reopens camp without resetting actions")
	hero = mg.player_units[0]
	mg._on_camp_activity("rest", null, "")
	check(hero.current_hp == hero.max_hp, "repeat rest heals fully")
	check(mg._run_flags["camp_actions"] == 0, "two actions exhausted")
	mg._on_camp_activity("supplies", null, "")
	check(not mg._run_flags.has("camp_supplies"), "third action rejected")
	check(mg._camp_screen.activities._confirm.disabled, "exhausted confirm disabled")
	await shot("1920_exhausted")
	if captures: get_window().size = Vector2i(1280, 720)
	await shot("1280_exhausted")
	mg._run_flags["camp_actions"] = 2
	mg._run_flags["camp_history"] = []
	mg._on_camp_activity("supplies", null, "")
	mg._on_camp_activity("supplies", null, "")
	check(mg._run_flags["camp_supplies"] == 2 and mg._run_flags["camp_actions"] == 0, "repeat supplies stacks two packs")
	var atk: int = hero.attack_damage
	var mag: int = hero.magic_power
	mg._apply_team_synergies()
	check(not mg._run_flags.has("camp_supplies"), "supplies consumed at battle start")
	check(hero.attack_damage >= roundi(atk * 1.2), "two packs apply twenty percent attack")
	mg._revert_team_synergies()
	check(hero.attack_damage == atk and hero.magic_power == mag, "supplies bonuses revert after battle")
	mg._run_flags["camp_actions"] = 2
	var item := ComponentEquipmentRules.generate_item(3, 1)
	mg._equipment_inventory.items.append(item)
	mg._on_camp_activity("reforge", item, "")
	check(mg._equipment_inventory.items[-1] == item and mg._run_flags["camp_actions"] == 2, "camp reforge unavailable")
	mg._run_flags["camp_actions"] = 2
	hero.current_xp = 0
	hero.perk_points = 0
	mg._on_camp_activity("training", hero, "")
	check(hero.current_xp > 0 and mg._run_flags["camp_actions"] == 1, "training grants XP for one action")
	mg._camp_screen.activities._kind = "training"
	mg._camp_screen.refresh()
	await shot("1280_training")
	mg._on_camp_activity("training", hero, "")
	await get_tree().process_frame
	check(mg._level_up_screen.visible and not mg._camp_screen.visible, "repeat training opens perk picker above camp")
	mg._level_up_screen._apply_perk({"stat": "attack_damage", "value": 1.0})
	await get_tree().process_frame
	check(mg._camp_screen.visible and mg._run_flags["camp_actions"] == 0, "perk choice returns to exhausted camp")
	mg._run_flags["camp_actions"] = 1
	mg._camp_screen.activities._kind = "supplies"
	mg._camp_screen.refresh()
	await shot("1280_supplies")
	mg._camp_screen.activities._kind = "rest"
	mg._camp_screen.refresh()
	await shot("1280_rest")
	check(mg.game_state.gold == gold, "camp never spends gold")
	mg._camp_screen.activities.hide()
	check(not mg._run_flags.has("camp_active") and mg._run_map_screen.visible, "leave returns to map and closes camp checkpoint")
	check(mg._shop_screen.services._stations.keys() == ["reforge", "enchant"], "merchant service split")
	print("CAMP_CHECK: ", "ALL PASS" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
