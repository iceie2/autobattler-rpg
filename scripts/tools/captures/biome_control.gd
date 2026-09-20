extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Bare backdrop for a given round, no units and no VFX — the control plate the
# enemy captures are measured against.
#
# Without it, "contrast" measured on a finished capture just reports how busy
# that biome's backdrop is, which made every enemy look ~50% worse on fire than
# on air regardless of its effect. Differencing a capture against this plate
# isolates the unit+VFX pixels and asks the only question that matters: how far
# does the effect sit from the backdrop DIRECTLY BEHIND IT.
#
# Run: godot --path . res://scenes/tools/biome_control.tscn -- --round=N
const DEBUT_ROUND := 1

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(CapturePaths.out("_control.png"))
	assert(err == OK, "control capture failed")
	print("BIOME_CONTROL: ALL PASS")
	get_tree().quit(0)
