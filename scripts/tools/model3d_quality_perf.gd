extends Node
## Applies an isolated MSAA experiment to the existing real-battle probe.
const Probe = preload("res://scripts/arena/perf_probe.gd")
var probe: Node
var configured := false

func _ready() -> void:
	probe = Probe.new()
	add_child(probe)

func _process(_delta: float) -> void:
	if configured or probe.mg == null or probe.mg.player_units.size() < 15:
		return
	for u in probe.mg.player_units:
		if u.model3d:
			u.model3d._viewport.msaa_3d = Viewport.MSAA_4X
	configured = true
	print("QUALITY_PERF applied 4x MSAA to hero viewports")
