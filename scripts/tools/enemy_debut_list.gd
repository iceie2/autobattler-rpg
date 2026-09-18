extends Node

# Lists every enemy's FIRST appearance round across the early game, using the
# real WaveDirector. Read-only — it is a survey, not a test.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/enemy_debut_list.tscn

const LAST_ROUND := 20
const SAMPLES := 6      # wave specs roll, so sample each round a few times

func _ready() -> void:
	var debut: Dictionary = {}
	var counts: Dictionary = {}
	for r in range(1, LAST_ROUND + 1):
		for s in range(SAMPLES):
			var director := WaveDirector.new()
			for entry in director.generate_wave_spec(r, 1, 9):
				var u: VisualUnit = director.create_enemy_for_entry(entry, r)
				if not u:
					continue
				var n: String = u.unit_name
				if not debut.has(n):
					debut[n] = r
				var key := "%d|%s" % [r, n]
				counts[key] = int(counts.get(key, 0)) + 1
				u.free()
	var names: Array = debut.keys()
	names.sort_custom(func(a, b): return int(debut[a]) < int(debut[b]))
	print("ENEMY DEBUTS (rounds 1-%d)" % LAST_ROUND)
	for n in names:
		print("  round %2d   %s" % [int(debut[n]), n])
	get_tree().quit(0)
