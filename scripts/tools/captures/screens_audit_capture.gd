extends Node

# Capture harness for the screens no per-screen harness covers (2026-09-27
# screen audit): merchant, crystal shop, game over, class browser, roster,
# run history, hydra element pick, main menu.
#
#   godot --path . res://scenes/_screens_audit_capture.tscn -- --screen=merchant [--ui-style=light]
#
# Writes user://_audit_<screen>[_light].png — a build artifact, move it out
# after looking. Needs a real window (no --headless). Only calls each screen's
# own open/present entry point; nothing here saves progression or a run.

func _ready() -> void:
	var which := "merchant"
	var light := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="): which = a.split("=")[1]
		if a == "--ui-style=light": light = true
	get_window().size = Vector2i(1920, 1080)

	# (Not for the main menu: its own background sits at z -20 and this
	# stand-in would paint over it — the 09-27 audit's "no background" was that.)
	if which != "mainmenu":
		var bg := ColorRect.new()
		bg.color = Color(0.16, 0.24, 0.14)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)

	var wait_frames := 90
	match which:
		"merchant":
			var s := ShopScreen.new()
			add_child(s)
			await get_tree().process_frame
			s.open(8, 42, ShopGenerator.roll_stock(8, []))
			wait_frames = 240
		"crystal":
			var s: Node = (load("res://scenes/crystal_shop.tscn") as PackedScene).instantiate()
			add_child(s)
			await get_tree().process_frame
			s.open()
		"gameover":
			var s: Node = (load("res://scenes/game_over_screen.tscn") as PackedScene).instantiate()
			add_child(s)
			await get_tree().process_frame
			s.show_defeat(37, 14, 48210, 212, "")
		"victory":
			var s: Node = (load("res://scenes/game_over_screen.tscn") as PackedScene).instantiate()
			add_child(s)
			await get_tree().process_frame
			s.show_victory(120, 30, 210400, 890, "")
		"classes":
			var s: Node = (load("res://scenes/class_browser.tscn") as PackedScene).instantiate()
			add_child(s)
			await get_tree().process_frame
			s.open(0)
		"roster":
			var units: Array = []
			var classes: Array = UnitFactory.get_all_classes().filter(
				func(c): return VisualUnit.HERO_SPRITE_PATHS.has(c))
			for i in range(4):
				var c: int = classes[(i * 5) % classes.size()]
				var u := UnitFactory.create_unit(c, UnitFactory.element_for_class(c), true)
				add_child(u)
				u.visible = false
				units.append(u)
			var enemies: Array = []
			for e in [EnemyFactory.create_goblin(3), EnemyFactory.create_goblin_archer(3)]:
				add_child(e)
				e.visible = false
				enemies.append(e)
			var s: Node = (load("res://scenes/character_menu.tscn") as PackedScene).instantiate()
			add_child(s)
			await get_tree().process_frame
			# --side=enemies opens on the enemy tab; --page=N pages forward.
			var on_players := not ("--side=enemies" in OS.get_cmdline_user_args())
			s.open(units, enemies, on_players)
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--page="):
					for p in range(int(a.split("=")[1])):
						s._next()
			which = "roster" if on_players else "roster_enemies"
		"history":
			var s := RunHistoryScreen.new()
			add_child(s)
			await get_tree().process_frame
			s.open()
		"hydra":
			var s := HydraElementScreen.new()
			add_child(s)
			await get_tree().process_frame
			s.present()
		"tooltip":
			# Item tooltip (custom panel) + a Godot built-in hover tooltip, to
			# check both draw prose in Inter (2026-09-29).
			var mg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
			add_child(mg)
			for i in range(30):
				await get_tree().process_frame
			for n in mg.find_children("*", "CanvasLayer", true, false):
				if n is RelicScreen or n is RelicMilestoneScreen:
					(n as CanvasLayer).visible = false
			var it := ComponentEquipmentItem.new("Critical Focus", EquipmentItem.Rarity.UNCOMMON)
			it.passive_levels = {"critical_focus": 1}
			mg._show_item_tooltip(it, Vector2(700, 300), "Release to combine", true)
			var tip := Label.new()
			tip.text = "Tenacity 20 — stuns, roots, taunts and slows on this hero last 83% as long."
			tip.theme_type_variation = "TooltipLabel"
			tip.position = Vector2(700, 700)
			var tl := CanvasLayer.new()
			tl.layer = 40
			add_child(tl)
			tl.add_child(tip)
		"synergy":
			# Left sidebar with a mixed team; --open expands SET BONUSES.
			var smg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
			add_child(smg)
			for i in range(30):
				await get_tree().process_frame
			for n in smg.find_children("*", "CanvasLayer", true, false):
				if n is RelicScreen or n is RelicMilestoneScreen:
					(n as CanvasLayer).visible = false
			var sclasses: Array = UnitFactory.get_all_classes().filter(
				func(c): return VisualUnit.HERO_SPRITE_PATHS.has(c))
			for i in range(5):
				var c: int = sclasses[(i * 4) % sclasses.size()]
				var su := UnitFactory.create_unit(c, UnitFactory.element_for_class(c), true)
				smg.add_child(su)
				smg.player_units.append(su)
			smg._rebuild_synergy_display()
			if "--open" in OS.get_cmdline_user_args() and smg._synergy_btn:
				smg._synergy_btn.pressed.emit()
			wait_frames = 30
		"hovertip":
			# The unit/row hover popup, driven directly (not via the mouse).
			var hmg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
			add_child(hmg)
			for i in range(30):
				await get_tree().process_frame
			for n in hmg.find_children("*", "CanvasLayer", true, false):
				if n is RelicScreen or n is RelicMilestoneScreen:
					(n as CanvasLayer).visible = false
			if "--row" in OS.get_cmdline_user_args():
				hmg._row_tip_title.text = "Row 1  —  Front Line"
				hmg._row_tip_heal.text = "Heal  10%  next round"
				hmg._row_tip_xp.text = "XP  +40%  bonus"
				hmg._layout_row_tip(false)
			else:
				hmg._row_tip_title.text = "Lightning Static"
				hmg._row_tip_heal.text = "Level 12"
				hmg._row_tip_xp.text = ""
				hmg._layout_row_tip(true)
			hmg.set_process(false)   # _process hides the popup when the mouse is off the board
			hmg._row_tip.visible = true
			hmg._row_tip.position = Vector2(700, 500)
			wait_frames = 20
		"endrun":
			# Defeat screen first, THEN the relic unlock cards over it (2026-09-30).
			var emg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
			add_child(emg)
			for i in range(30):
				await get_tree().process_frame
			for n in emg.find_children("*", "CanvasLayer", true, false):
				if n is RelicScreen or n is RelicMilestoneScreen:
					(n as CanvasLayer).visible = false
			Progression.relic_milestones.pending["opening_1"] = true
			Progression.relic_milestones.pending["opening_2"] = true
			emg._game_over_screen.show_defeat(37, 14, 48210, 212, "")
			emg._collect_relic_milestones()   # not awaited: it plays over the screen
			wait_frames = 40
		"dmeter":
			# Damage meter with fake numbers; --enemy shows the Enemies tab.
			var dmg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
			add_child(dmg)
			for i in range(30):
				await get_tree().process_frame
			for n in dmg.find_children("*", "CanvasLayer", true, false):
				if n is RelicScreen or n is RelicMilestoneScreen:
					(n as CanvasLayer).visible = false
			var dcl: Array = UnitFactory.get_all_classes().filter(
				func(c): return VisualUnit.HERO_SPRITE_PATHS.has(c))
			for i in range(4):
				var c: int = dcl[(i * 5) % dcl.size()]
				var du := UnitFactory.create_unit(c, UnitFactory.element_for_class(c), true)
				dmg.add_child(du)
				dmg.player_units.append(du)
				du.damage_dealt = 4000 - i * 900
			dmg._dm_defeated_enemies.append({"unit_name": "Goblin", "damage_dealt": 640})
			dmg._dm_defeated_enemies.append({"unit_name": "Goblin Archer", "damage_dealt": 1210})
			dmg._dm_defeated_enemies.append({"unit_name": "Ogre", "damage_dealt": 2300})
			for n in dmg.find_children("*", "Button", true, false):
				if str(n.text).begins_with("DAMAGE METER"):
					n.pressed.emit()
			if "--enemy" in OS.get_cmdline_user_args():
				dmg._dm_tab = 1
			dmg._rebuild_damage_meter()
			wait_frames = 20
		"board":
			# Units on the REAL grid through main_game's own placement, to judge
			# whether they read as standing on it (2026-10-06 "floating" report).
			var bmg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
			add_child(bmg)
			for i in range(30):
				await get_tree().process_frame
			for n in bmg.find_children("*", "CanvasLayer", true, false):
				if n is RelicScreen or n is RelicMilestoneScreen:
					(n as CanvasLayer).visible = false
			var bcl: Array = UnitFactory.get_all_classes().filter(
				func(c): return VisualUnit.HERO_SPRITE_PATHS.has(c))
			var spots := [Vector2i(1, 6), Vector2i(4, 6), Vector2i(7, 6), Vector2i(2, 7)]
			for i in range(spots.size()):
				var c: int = bcl[(i * 5) % bcl.size()]
				var bu := UnitFactory.create_unit(c, UnitFactory.element_for_class(c), true)
				bmg._place_at(bu, spots[i])
				bmg.player_units.append(bu)
			var crab := EnemyFactory.create_by_type("crystal_crab")
			bmg._place_at(crab, Vector2i(4, 1))
			bmg.enemy_units.append(crab)
			for bu2 in bmg.player_units + bmg.enemy_units:
				var m3: Model3DSprite = (bu2 as VisualUnit).model3d
				if m3 != null:
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
					var vimg: Image = m3._viewport.get_texture().get_image()
					var ur := vimg.get_used_rect()
					var spr: Sprite2D = m3.get_sprite()
					print("FOOTPIX ", bu2.unit_name, " frame=", vimg.get_size(), " used=", ur, " pad_px_screen=", "%.1f" % ((vimg.get_height() - ur.end.y) * spr.scale.y),)
					var feet_g: Vector2 = spr.to_global(Vector2(0.0, float(ur.end.y) - float(vimg.get_height()) * 0.5))
					var line_g: Vector2 = bu2.to_global(Vector2(0.0, bu2.ground_offset()))
					print("   GAP ", bu2.unit_name, " feet_above_line_px=", "%.1f" % (line_g.y - feet_g.y), "  (sprite scale ", spr.global_scale, ")")
			wait_frames = 40
		"mainmenu":
			var s: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
			add_child(s)
			wait_frames = 150
		_:
			push_error("unknown --screen=%s" % which)
			get_tree().quit()
			return

	for i in range(wait_frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := "user://_audit_%s%s.png" % [which, "_light" if light else ""]
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(out))
	print("CAPTURED %s" % out)
	get_tree().quit()
