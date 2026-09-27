extends Node

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Renders GearIcons composites for one item of every tier, including a gold
# with three passives (Lifesteal 2, Thorns 1, Spell Echo 1), so installed art in
# assets/using/equipment_icons/ can be judged in its real composite.
# Run: godot --headless --path . res://scenes/tools/gear_icons_check.tscn
func _ready() -> void:
	var R := ComponentEquipmentRules
	var items: Array = [R.create_common("hp"), R.create_common("cdr")]
	for spec in [[EquipmentItem.Rarity.UNCOMMON, {"lifesteal": 1}],
			[EquipmentItem.Rarity.RARE, {"lifesteal": 1, "thorns": 1}],
			[EquipmentItem.Rarity.EPIC, {"lifesteal": 2, "thorns": 1}],
			[EquipmentItem.Rarity.LEGENDARY, {"lifesteal": 2, "thorns": 1, "spell_echo": 1}]]:
		var it := ComponentEquipmentItem.new("x", spec[0])
		it.passive_levels = spec[1]
		items.append(it)
	var sheet := Image.create(items.size() * 136, 136, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.16, 0.17, 0.14))
	for i in range(items.size()):
		var im: Image = GearIcons._compose(items[i])
		im.resize(128, 128, Image.INTERPOLATE_NEAREST)
		sheet.blend_rect(im, Rect2i(0, 0, 128, 128), Vector2i(i * 136 + 4, 4))
	var out: String = ProjectSettings.globalize_path(CapturePaths.out("gear_icons_check.png"))
	print("GEAR_ICONS: ", "saved " + out if sheet.save_png(out) == OK else "SAVE FAILED")
	get_tree().quit()
