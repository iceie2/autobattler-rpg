extends Node
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
var shop: ShopScreen
var failures: Array[String] = []
var purchases: Array = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func shot(tag: String) -> void:
	await get_tree().create_timer(0.45).timeout
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out("merchant_v2_" + tag + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1920, 1080)
	seed(27491)
	ComponentEquipmentGateway.active_run = true
	shop = ShopScreen.new()
	add_child(shop)
	shop.buy_hero.connect(func(idx, cls, element, rolls): purchases.append([idx, cls, element, rolls]))
	shop.buy_item.connect(func(idx, item): purchases.append([idx, item]))
	shop.buy_stat.connect(func(idx, perk): purchases.append([idx, perk]))
	shop.buy_relic.connect(func(idx, relic): purchases.append([idx, relic]))
	var stock := ShopGenerator.roll_stock(12)
	shop.open(12, 85, stock)
	await shot("1920_stock")
	check(shop._card_nodes.size() == 7, "seven offers")
	check(shop._card_nodes[4].global_position.y == shop._card_nodes[0].global_position.y, "equipment in upper row")
	check(shop._card_nodes[2].global_position.y > shop._card_nodes[0].global_position.y, "stats in lower row")
	check(shop._card_nodes[6].size.x > shop._card_nodes[0].size.x * 1.8, "wide relic")
	for card in shop._card_nodes:
		check(card.get_global_rect().end.y < 956, "card within content")
	var rolls: Dictionary = stock[0]["rolls"].duplicate(true)
	shop._on_card_pressed(0)
	check(purchases.size() == 1 and purchases[0][3] == rolls, "exact pre-rolled hero signal")
	check(not stock[0].get("sold", false), "rejected purchase stays unsold")
	shop.purchase_rejected("No room — field and bench are full!")
	await shot("1920_rejected")
	var before: Vector2 = shop._card_nodes[0].position
	shop.mark_sold(0)
	shop.refresh(0)
	shop._on_card_pressed(0)
	shop._on_card_pressed(1)
	check(purchases.size() == 1, "sold and insufficient gold cannot purchase")
	check(shop._card_nodes[0].position == before, "sold slot stays fixed")
	check(shop._reroll_btn.disabled, "refresh unaffordable")
	await shot("1920_sold_poor")
	get_window().size = Vector2i(1280, 720)
	await shot("1280_sold_poor")
	shop.refresh(1000)
	shop._on_card_pressed(2)
	shop._on_card_pressed(4)
	shop._on_card_pressed(6)
	check(is_same(purchases[-3][1], stock[2]["perk"]), "exact stat reward signal")
	check(purchases[-2][1] == stock[4]["item"], "exact equipment resource signal")
	check(is_same(purchases[-1][1], stock[6]["relic"]), "exact relic reward signal")
	stock[4]["item"].name = "Wayfarer's Ancient Brassbound Blade of the Evening Caravan"
	stock[6]["relic"]["name"] = "The Lantern of a Thousand Forgotten Journeys"
	ShopGenerator.apply_discount(stock, 0.25)
	shop.open(12, 85, stock)
	await shot("1280_long_names")
	get_window().size = Vector2i(1920, 1080)
	await shot("1920_long_names")
	shop._card_nodes[4].grab_focus()
	await shot("1920_details")
	get_window().size = Vector2i(1280, 720)
	shop._card_nodes[4].grab_focus()
	await shot("1280_details")
	check(shop._tooltip.visible, "keyboard focus details")
	var tip_rect := shop._tooltip.get_global_rect()
	for card in shop._card_nodes:
		check(not tip_rect.intersects(card.get_global_rect()), "details do not cover purchase controls")
	shop._card_nodes[4].release_focus()
	shop._hide_tooltip()
	for n in range(4):
		check(shop.current_reroll_cost() == 3 + n * 2, "escalating refresh cost")
		shop.set_stock(85, ShopGenerator.roll_stock(12))
		await get_tree().process_frame
	check(shop.current_reroll_cost() == 11, "four refreshes")
	await shot("1280_refreshed")
	get_window().size = Vector2i(1920, 1080)
	await shot("1920_refreshed")
	get_window().size = Vector2i(1280, 720)
	shop.purchase_rejected("No room — field and bench are full!")
	await shot("1280_rejected")
	shop.open(12, 85, ShopGenerator.roll_stock(12))
	check(shop.current_reroll_cost() == 3, "new visit resets refresh")
	await shot("1280_stock")
	var service_item := ComponentEquipmentRules.generate_item(12, 2)
	var service_hero := UnitFactory.create_unit(UnitBase.UnitClass.RIOT, UnitBase.Element.LIGHTNING, true)
	var bag_items: Array = [service_item]
	for n in range(7):
		bag_items.append(ComponentEquipmentRules.generate_item(12, n % 4))
	shop.services.provider = func(): return {"items": bag_items, "heroes": [service_hero], "gold": 85, "round": 12}
	shop._service_overlay.show()
	shop.services.open()
	check(shop.services._tray.get_child_count() == bag_items.size(), "bag tray displays available items")
	# 2026-10-02: only the small slot takes drops, not the whole station.
	check(shop.services._slots["enchant"]._can_drop_data(Vector2.ZERO, service_item), "slot accepts item drag")
	check(not shop.services._stations["enchant"].has_method("_can_drop_data"), "station backdrop no longer takes drops")
	check(shop.services._slots["enchant"].size.x < 130.0, "slot is only a little bigger than an item")
	shop.services._slots["enchant"]._drop_data(Vector2.ZERO, service_item)
	check(shop.services._slots["enchant"].item == service_item, "dropped item shows in the slot")
	check(shop.services._slots["reforge"].item == null, "other station's slot stays empty")
	check(shop.services._kind == "enchant" and shop.services._item == service_item, "drop selects service and item")
	await shot("1280_services")
	shop.services._kind = "reforge"
	shop.services.reload()
	await shot("1280_reforge")
	shop.services._kind = "enchant"
	shop.services.reload()
	await shot("1280_enchant")
	# Slots wake up while an item is being dragged (state forced: the harness has no mouse).
	for key in shop.services._slots:
		shop.services._slots[key]._dragging = true
	shop.services._slots["reforge"]._hover = true
	await shot("1280_dragging")
	for key in shop.services._slots:
		shop.services._slots[key]._dragging = false
		shop.services._slots[key]._hover = false
	get_window().size = Vector2i(1920, 1080)
	await shot("1920_services")
	get_window().size = Vector2i(1280, 720)
	check(shop.services._stations.keys() == ["reforge", "enchant"], "merchant has reforge and enchant stations")
	shop.services.hide()
	service_hero.free()
	print("MERCHANT_CHECK: ", "ALL PASS" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
