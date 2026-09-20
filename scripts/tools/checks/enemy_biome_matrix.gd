extends Node

# Which BIOMES does each enemy actually fight on?
#
# The board's backdrop changes every decade and cycles through six biomes
# (BackgroundLayer.BACKDROP_ORDER), so a capture taken on round 1 "normal"
# grass verifies nothing for an enemy that debuts on round 41 fire. This
# surveys the real WaveDirector across the whole 1-100 ladder and reports,
# per enemy, every biome it can appear on plus its debut round.
#
# Read-only survey, not a test.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/enemy_biome_matrix.tscn

const LAST_ROUND := 100
const SAMPLES := 4
const BIOMES := ["normal", "air", "water", "earth", "fire", "lightning"]

func _ready() -> void:
	var biomes_for: Dictionary = {}
	var debut: Dictionary = {}
	for r in range(1, LAST_ROUND + 1):
		var biome: int = (r - 1) / 10 % BIOMES.size()
		for s in range(SAMPLES):
			var director := WaveDirector.new()
			for entry in director.generate_wave_spec(r, 1, 9):
				var u: VisualUnit = director.create_enemy_for_entry(entry, r)
				if not u:
					continue
				var n: String = u.unit_name
				if not debut.has(n):
					debut[n] = r
				if not biomes_for.has(n):
					biomes_for[n] = {}
				biomes_for[n][biome] = int(biomes_for[n].get(biome, 0)) + 1
				u.free()
	var names: Array = biomes_for.keys()
	names.sort_custom(func(a, b): return int(debut[a]) < int(debut[b]))
	print("BIOME_MATRIX_BEGIN")
	for n in names:
		var bs: Array = biomes_for[n].keys()
		bs.sort()
		var labels: Array[String] = []
		for b in bs:
			labels.append(BIOMES[b])
		print("%-34s debut=%-4d biomes=%s" % [n, int(debut[n]), ",".join(labels)])
	print("BIOME_MATRIX_END")
	get_tree().quit(0)
