extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Item-passive cues in a REAL fight on the REAL board (grass BackgroundLayer).
# Three heroes wear gold-level component gear through ComponentEquipmentInventory
# (the real equip path) and fight a Riot squad under the real AutoBattleManager
# loop. Captures six frames into one 3x2 sheet for the user's cue review, and
# prints how many of each cue kind fired.
#
# Runs WINDOWED (--headless renders empty PNGs).
# Run: godot --path . res://scenes/tools/gear_cues_board_check.tscn
var OUT: String = CapturePaths.out("gear_cues_board.png")

const LOADOUTS := [
	# Melee bruiser: shields, sustain, stacks, reflect.
	[UnitBase.UnitClass.BLOODHOUND, ["lifesteal", "iron_rhythm", "thorns", "bulwark", "cadence", "critical_focus"]],
	# Caster: cast-triggered passives.
	[UnitBase.UnitClass.NEMI, ["aftercast_ward", "spell_tempo", "clockwork", "spell_echo", "battle_charge", "arcane_conduit"]],
	# Ranged crit build: debuffs, kills, tempo.
	[UnitBase.UnitClass.SHAUNA, ["keen_rhythm", "deep_wound", "sunder", "overkill", "precision_reset", "battle_haste"]],
]

func _ready() -> void:
	get_window().size = Vector2i(1500, 950)
	RenderingServer.set_default_clear_color(Color(0.12, 0.13, 0.10))
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(1)
	var grid := BattleGrid.new()
	add_child(grid)
	var mgr := AutoBattleManager.new()
	add_child(mgr)
	mgr.battle_grid = grid
	var fx := Node2D.new()
	add_child(fx)
	mgr.skill_effect_container = fx
	mgr.projectile_container = Node2D.new()
	add_child(mgr.projectile_container)
	await get_tree().process_frame

	var inv := ComponentEquipmentInventory.new()
	add_child(inv)
	var heroes: Array = []
	var cells := [Vector2i(2, 6), Vector2i(3, 7), Vector2i(4, 7)]
	for i in range(LOADOUTS.size()):
		var h: VisualUnit = UnitFactory.create_unit(LOADOUTS[i][0], UnitBase.Element.NORMAL, true)
		add_child(h)
		h.grid_position = cells[i]
		grid.place_unit(h, cells[i])
		h.position = grid.to_global(grid.grid_to_world(cells[i]))
		h.battle_manager = mgr
		var uid: String = h.unit_name + "_" + str(h.get_instance_id())
		inv.hero_equipment[uid] = []
		for key in LOADOUTS[i][1]:
			var item := ComponentEquipmentItem.new("x", EquipmentItem.Rarity.LEGENDARY)
			item.passive_levels[key] = 4
			ComponentEquipmentRules.refresh(item)
			inv.hero_equipment[uid].append(item)
			inv._apply_equipment_bonuses(h, item)   # real stat + gear_levels path
		heroes.append(h)
	var foes: Array = []
	for cell: Vector2i in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 3), Vector2i(3, 3), Vector2i(5, 2)]:
		var e: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.RIOT, UnitBase.Element.NORMAL, false)
		add_child(e)
		e.grid_position = cell
		grid.place_unit(e, cell)
		e.position = grid.to_global(grid.grid_to_world(cell))
		e.battle_manager = mgr
		foes.append(e)
	mgr.player_units = heroes
	mgr.enemy_units = foes
	for h in heroes:
		print("GEAR_CUES: %s levels=%s" % [h.unit_name, str(h.gear_levels)])
	mgr.start_battle()

	var frames: Array[Image] = []
	for i in range(6):
		await get_tree().create_timer(1.4).timeout
		await RenderingServer.frame_post_draw
		frames.append(get_viewport().get_texture().get_image())
	var w: int = frames[0].get_width() / 2
	var h: int = frames[0].get_height() / 2
	var sheet := Image.create(w * 3, h * 2, false, frames[0].get_format())
	for i in range(frames.size()):
		var f := frames[i]
		f.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(f, Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	var err := sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("GEAR_CUES: cue counts %s" % str(GearFX.spawn_counts))
	for hh in heroes:
		if is_instance_valid(hh):
			print("GEAR_CUES: %s hp=%d/%d gear_shield=%d state=%s" % [hh.unit_name, hh.current_hp,
				hh.max_hp, hh.gear_shield, str(hh.gear.keys())])
	print("GEAR_CUES: %s -> %s" % ["saved" if err == OK else "SAVE FAILED", OUT])
	get_tree().quit(0)
