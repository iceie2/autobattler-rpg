extends Node
## Full-resolution screenshot of the REAL board — biome backdrop, rails, tiles,
## UI — with 3D and 2D heroes standing side by side on it.
##
##   GODOT --path . res://scenes/board_look.tscn
##   → user://_board_look.png
##
## The board-check tool renders units against a flat grey void, which is exactly
## where a perspective mismatch is invisible. This is the one that answers "does
## the 3D character look like it's STANDING in this scene".
##
## Windowed (needs a GPU for the 3D SubViewports).

const OUT := "user://_board_look.png"
# Alternating 3D and 2D heroes so the eye can compare them in the same lighting
# and against the same ground.
const MIX := ["BOUNCER", "NEMI", "BOUNCER", "SABLE", "BOUNCER", "RUSH"]

var mg = null

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	mg = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame

	mg.max_player_units = 40
	var keys: PackedStringArray = UnitBase.UnitClass.keys()
	for cname in MIX:
		var cls: int = keys.find(cname)
		if cls < 0:
			continue
		mg._recruit_hero(cls, UnitBase.Element.NORMAL, UnitFactory.generate_recruit_rolls())
		await get_tree().process_frame

	for i in range(6):
		var e: VisualUnit = EnemyFactory.create_goblin(3)
		mg._place_enemy(e, false)

	# The wave-1 relic pick covers the whole board — take the first offer so the
	# screenshot shows the board and not a modal.
	if mg._relic_screen and mg._relic_screen.visible:
		mg._relic_screen.hide()
	mg.close_shop()
	if mg.difficulty_panel:
		mg.difficulty_panel.set_panel_visible(false)
	mg._pending_round_reward = {}
	for i in range(60):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote %s (%dx%d)" % [OUT, img.get_width(), img.get_height()])
	get_tree().quit(0)
