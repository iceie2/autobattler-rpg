extends Node
var failures: Array[String] = []
var _save_existed := false
var _save_backup := ""

func _exit_tree() -> void:
	if _save_existed:
		var file := FileAccess.open(RunSave.PATH, FileAccess.WRITE)
		if file: file.store_string(_save_backup)
	else:
		RunSave.clear()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_save_existed = FileAccess.file_exists(RunSave.PATH)
	if _save_existed:
		var file := FileAccess.open(RunSave.PATH, FileAccess.READ)
		if file: _save_backup = file.get_as_text()
	seed(8172)
	# Pure rules: both equipment modes, all rarities, legal save round trips.
	for rarity in range(5):
		for n in range(12):
			var item := ComponentEquipmentRules.generate_item(12, rarity)
			var result := MerchantServices.exchange(item, 12)
			check(result.rarity == rarity and result != item, "component exchange rarity")
			check(ComponentEquipmentRules.from_dict(ComponentEquipmentRules.to_dict(result)) != null, "exchange save validity")
			var reforged := MerchantServices.reforge(item, 12) as ComponentEquipmentItem
			check(reforged != item and reforged.id == item.id and reforged.name == item.name, "component reforge identity")
			check(reforged.rarity == rarity and reforged.composition == item.composition and reforged.passive_levels == item.passive_levels and reforged.counters == item.counters, "component reforge preservation")
			check(ComponentEquipmentRules.from_dict(ComponentEquipmentRules.to_dict(reforged)) != null, "reforge save validity")
			if rarity > 0:
				var key: String = str(item.passive_levels.keys()[0])
				var before := item.passive_levels.duplicate()
				var enchanted := MerchantServices.enchant(item, key) as ComponentEquipmentItem
				check(enchanted != null and enchanted.passive_level_count() == rarity, "enchant budget")
				check(enchanted.stat_bonus == item.stat_bonus and item.passive_levels == before, "enchant preserves stats and source")
				check(int(enchanted.passive_levels.get(key, 0)) == int(before[key]) - 1, "selected modifier replaced")
				check(ComponentEquipmentRules.from_dict(ComponentEquipmentRules.to_dict(enchanted)) != null, "enchant save validity")
			else:
				check(MerchantServices.enchant(item, "") == null, "common enchant rejected")
			var legacy := EquipmentItem.new("Sword", rarity)
			var swapped := MerchantServices.exchange(legacy, 12)
			check(swapped.rarity == rarity and not swapped is ComponentEquipmentItem, "legacy exchange rarity")
			var legacy_reforged := MerchantServices.reforge(legacy, 12)
			check(legacy_reforged.rarity == rarity and legacy_reforged.name == legacy.name and legacy_reforged.id == legacy.id, "legacy reforge preservation")
			if EquipmentManager.passive_cap(rarity) > 0:
				var enchanted := MerchantServices.enchant(legacy, "")
				check(enchanted != null and enchanted.passives.size() == 1, "legacy adds passive")
				var replaced := MerchantServices.enchant(enchanted, enchanted.passives[0]["name"])
				check(replaced.passives[0]["name"] != enchanted.passives[0]["name"], "legacy replaces passive")
	var mg = load("res://scenes/main_game.tscn").instantiate()
	add_child(mg)
	for i in range(12): await get_tree().process_frame
	mg.game_state.battle_round = 12
	mg.game_state.gold = 1000
	mg._shop_stock = ShopGenerator.roll_stock(12)
	mg._shop_screen.open(12, 1000, mg._shop_stock)
	mg._equipment_inventory.items.clear()
	var source := ComponentEquipmentRules.generate_item(12, 2)
	mg._equipment_inventory.items.append(source)
	var gold: int = mg.game_state.gold
	mg._on_merchant_service("reforge", source, "")
	check(mg.game_state.gold == gold - MerchantServices.cost("reforge", 12, 2), "reforge exact charge")
	check(mg._equipment_inventory.items.size() == 1 and mg._equipment_inventory.items[0] != source, "reforge atomically replaces")
	gold = mg.game_state.gold
	mg._on_merchant_service("exchange", source, "")
	check(mg.game_state.gold == gold, "moved exchange no charge")
	source = mg._equipment_inventory.items[0]
	var old_stats: Dictionary = source.stat_bonus.duplicate(true)
	gold = mg.game_state.gold
	mg._on_merchant_service("reforge", source, "")
	check(mg.game_state.gold == gold - MerchantServices.cost("reforge", 12, 2), "repeat reforge charges")
	check(mg._equipment_inventory.items[0] != source and source.stat_bonus == old_stats, "repeat reforge replaces only target")
	source = mg._equipment_inventory.items[0]
	mg.game_state.gold = 0
	mg._on_merchant_service("enchant", source, str(source.passive_levels.keys()[0]))
	check(mg._equipment_inventory.items[0] == source and mg.game_state.gold == 0, "unaffordable enchant untouched")
	mg.game_state.gold = 1000
	mg._on_merchant_service("enchant", source, "invalid")
	check(mg.game_state.gold == 1000 and mg._equipment_inventory.items[0] == source, "invalid modifier no charge")
	mg._on_merchant_service("enchant", source, str(source.passive_levels.keys()[0]))
	check(mg.game_state.gold == 1000 - MerchantServices.cost("enchant", 12, 2), "enchant exact charge")
	while mg._equipment_inventory.items.size() < EquipmentInventory.MAX_ITEMS:
		mg._equipment_inventory.items.append(ComponentEquipmentRules.generate_item(12, 0))
	gold = mg.game_state.gold
	mg._on_shop_buy_item(4, mg._shop_stock[4]["item"])
	check(mg.game_state.gold == gold and not mg._shop_stock[4].get("sold", false), "full bag purchase refunded")
	source = mg._equipment_inventory.items[0]
	mg._on_merchant_service("exchange", source, "")
	check(mg._equipment_inventory.items.size() == EquipmentInventory.MAX_ITEMS, "full bag exchange succeeds")
	# Empty roster stat purchase must remain available and free of charge.
	gold = mg.game_state.gold
	mg._on_shop_buy_stat(2, mg._shop_stock[2]["perk"])
	check(mg.game_state.gold == gold and not mg._shop_stock[2].get("sold", false), "stat rejected without hero")
	var unit := UnitFactory.create_unit(UnitBase.UnitClass.RIOT, UnitBase.Element.LIGHTNING, true)
	mg.battle_grid_node.add_child(unit)
	mg.player_units.append(unit)
	unit.current_xp = 0
	var xp := MerchantServices.training_xp(unit)
	gold = mg.game_state.gold
	mg._on_merchant_service("training", unit, "")
	check(unit.current_xp == 0 and mg.game_state.gold == gold, "merchant rejects moved training")
	mg._on_merchant_service("training", unit, "")
	check(unit.level == 1 and unit.perk_points == 0, "repeated merchant training does nothing")
	# Force a full roster without changing the player's actual save.
	var original_cap: int = mg.max_player_units
	mg.max_player_units = 0
	for i in range(mg.max_bench_slots()): mg.bench_units.append(unit)
	gold = mg.game_state.gold
	mg._on_shop_buy_hero(0, mg._shop_stock[0]["class"], mg._shop_stock[0]["element"], mg._shop_stock[0]["rolls"])
	check(mg.game_state.gold == gold and not mg._shop_stock[0].get("sold", false), "full roster hero refunded")
	mg.bench_units.clear()
	mg.max_player_units = original_cap
	unit.level = Progression.hero_level_cap()
	gold = mg.game_state.gold
	mg._on_merchant_service("training", unit, "")
	check(mg.game_state.gold == gold, "capped training no charge")
	unit.level = 1
	mg._apply_team_synergies()
	var normal_atk: int = unit.attack_damage
	var normal_mag: int = unit.magic_power
	mg._revert_team_synergies()
	var base_atk: int = unit.attack_damage
	var base_mag: int = unit.magic_power
	mg._on_merchant_service("supplies", null, "")
	check(not mg._run_flags.get("merchant_supplies", false), "merchant rejects moved supplies")
	# Old saves containing a paid merchant pack still receive their bonus.
	mg._run_flags["merchant_supplies"] = true
	mg.save_run()
	check(RunSave.read_data()["run_flags"].get("merchant_supplies", false), "legacy supplies persisted")
	gold = mg.game_state.gold
	mg._on_merchant_service("supplies", null, "")
	check(mg.game_state.gold == gold, "duplicate supplies no charge")
	mg._apply_team_synergies()
	check(unit.attack_damage == maxi(1, roundi(normal_atk * 1.1)), "supply attack bonus")
	check(unit.magic_power == maxi(0, roundi(normal_mag * 1.1)), "supply magic bonus")
	check(not mg._run_flags.get("merchant_supplies", false), "supplies consumed once")
	mg.player_units.erase(unit)
	mg._downed_heroes.append(unit)
	mg._revert_team_synergies()
	check(unit.attack_damage == base_atk and unit.magic_power == base_mag, "supply reverted for fallen hero")
	mg._downed_heroes.erase(unit)
	mg.player_units.append(unit)
	mg._apply_team_synergies()
	check(unit.attack_damage == normal_atk, "supplies do not repeat next battle")
	mg._revert_team_synergies()
	mg.game_state.gold = 100
	mg._shop_screen.open(12, 100, mg._shop_stock)
	for i in range(3): mg._on_shop_screen_reroll()
	check(mg.game_state.gold == 85 and mg._shop_screen.current_reroll_cost() == 9, "actual refresh charges 3 5 7")
	mg._shop_screen._on_leave()
	gold = mg.game_state.gold
	mg._on_merchant_service("supplies", null, "")
	check(mg.game_state.gold == gold, "closed shop rejects services")
	print("MERCHANT_SERVICES: ", "ALL PASS" if failures.is_empty() else str(failures))
	mg.queue_free()
	for i in range(3): await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
