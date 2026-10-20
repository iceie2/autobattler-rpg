extends Node

# Read-only survey of every enemy type's kit, for the combat-feel audit
# (ENEMY_FEEL_AUDIT.md). Builds each unit through create_by_type (so it is the
# unit waves actually spawn) and prints one tab-separated row per type.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/enemy_kit_survey.tscn

const TYPES := ["goblin", "goblin_archer", "goblin_shaman_normal", "goblin_shaman_fire",
	"goblin_shaman_water", "goblin_shaman_earth", "goblin_shaman_air", "goblin_shaman_lightning",
	"orc_normal", "orc_fire", "orc_water", "orc_earth", "orc_air", "orc_lightning", "hill_giant",
	"gale_warden", "tidecaller", "terracotta_colossus", "magma_heart", "tempest_conduit",
	"mirrorplate_warden", "aspect_devourer", "slime_normal", "slime_fire", "slime_water",
	"slime_earth", "slime_air", "slime_lightning", "lizard_normal", "lizard_fire", "lizard_water",
	"lizard_earth", "lizard_air", "lizard_lightning", "bear_normal", "bear_fire", "bear_water",
	"bear_earth", "bear_air", "bear_lightning", "troll_normal", "troll_fire", "troll_water",
	"troll_earth", "troll_air", "troll_lightning", "windup_bot_normal", "windup_bot_fire",
	"windup_bot_water", "windup_bot_earth", "windup_bot_air", "windup_bot_lightning",
	"hydra_normal", "skeleton", "rat", "triarch", "stat_stealer", "ant_hill", "khagan",
	"skyrender", "drowned_maw", "cloven_titan", "emberhollow", "ember_heart", "arcfang",
	"gravekeeper", "the_architect", "ogre", "minotaur", "gargoyle", "stone_golem",
	"crystal_crab", "root_walker", "fire_giant", "hellhound", "ember_phoenix", "storm_giant",
	"storm_crow", "sky_wyvern", "tidepool_horror", "harpy", "coral_husk"]

const SKIP_META := ["sprite_folder", "mob_skill", "mob_passive", "passive_name", "passive_desc"]

func _ready() -> void:
	print("SURVEY_BEGIN")
	print("\t".join(["type", "name", "element", "range", "skill", "skill_key", "skill_desc",
		"passive", "passive_key", "passive_desc", "art", "markers"]))
	for t in TYPES:
		var u: VisualUnit = EnemyFactory.create_by_type(t)
		if not u:
			print("%s\t<create failed>" % t); continue
		var folder: String = str(u.get_meta("sprite_folder", ""))
		var art := "none"
		if VisualUnit.MONSTER_MODEL_PATHS.has(folder):
			art = "3d"
		elif DirAccess.dir_exists_absolute("res://assets/sprites/monsters/%s" % folder):
			art = "frames"
		elif VisualUnit.MONSTER_SPRITE_PATHS.has(folder) \
				and ResourceLoader.exists(VisualUnit.MONSTER_SPRITE_PATHS[folder]):
			art = "still"
		var markers: Array = []
		for m in u.get_meta_list():
			if not (str(m) in SKIP_META):
				markers.append("%s=%s" % [m, str(u.get_meta(m))])
		print("\t".join([t, u.unit_name, str(UnitBase.Element.keys()[u.current_element]),
			str(u.attack_range), u.skill_name, str(u.get_meta("mob_skill", "")),
			u.skill_description, str(u.get_meta("passive_name", "")),
			str(u.get_meta("mob_passive", "")), str(u.get_meta("passive_desc", "")),
			art, ",".join(markers)]))
		u.free()
	print("SURVEY_END")
	get_tree().quit(0)
