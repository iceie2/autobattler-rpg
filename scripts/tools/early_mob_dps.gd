extends Node

# Raw offensive comparison of the mobs a player meets in rounds 1-8.
# auto DPS = attack_damage * attacks_per_second (the real accessor, so any
# speed modifiers are included). Read-only survey.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/early_mob_dps.tscn

const CODES := ["rat", "goblin", "goblin_archer", "lizard_normal", "slime_normal",
	"goblin_shaman_normal", "crystal_crab", "ember_phoenix", "hill_giant",
	"windup_bot_normal", "orc_normal", "bear_normal", "minotaur", "fire_giant"]

func _ready() -> void:
	var rows: Array = []
	for c in CODES:
		var u: VisualUnit = EnemyFactory.create_by_type(c)
		if not u: continue
		add_child(u)
		var dps: float = float(u.attack_damage) * u.attacks_per_second
		rows.append({"n": u.unit_name, "dps": dps, "hp": u.max_hp,
			"rng": u.attack_range, "sr": u.skill_range, "mv": u.movement_speed,
			"aps": u.attacks_per_second, "atk": u.attack_damage})
		u.free()
	rows.sort_custom(func(a, b): return a["dps"] > b["dps"])
	print("%-22s %7s %6s %5s %5s %6s %5s %5s" % ["mob", "autoDPS", "HP", "ATK", "APS", "range", "skRng", "move"])
	for r in rows:
		var flag := ""
		if int(r["rng"]) > int(r["sr"]):
			flag = "  <-- outranges its OWN skill by %d" % (int(r["rng"]) - int(r["sr"]))
		print("%-22s %7.1f %6d %5d %5.2f %6d %5d %5d%s" % [r["n"], r["dps"], r["hp"],
			r["atk"], r["aps"], r["rng"], r["sr"], r["mv"], flag])
	get_tree().quit(0)
