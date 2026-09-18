extends Node

# Can Infestation ever actually fire? It needs 2+ OTHER rats within 2 tiles, so
# it requires a wave to field 3+ rats AND for them to be placed close together.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/rat_swarm_survey.tscn

const SAMPLES := 8

func _ready() -> void:
	var best_count := 0
	var best_round := 0
	var ever_clustered := 0
	var rounds_with_rats := 0
	var would_fire_at_1 := 0
	var waves_with_2 := 0
	for r in range(1, 31):
		var seen_rat := false
		for s in range(SAMPLES):
			var director := WaveDirector.new()
			var cells: Array = []
			for entry in director.generate_wave_spec(r, 1, 9):
				var u: VisualUnit = director.create_enemy_for_entry(entry, r)
				if not u: continue
				if u.unit_name == "Rat":
					cells.append(entry.get("pos", Vector2i.ZERO))
				u.free()
			if cells.size() > 0: seen_rat = true
			if cells.size() >= 2: waves_with_2 += 1
			if cells.size() > best_count:
				best_count = cells.size(); best_round = r
			# How many rats have 2+ other rats within 2 tiles (the real condition)?
			for a in cells:
				var near := 0
				for b in cells:
					if a != b and Vector2(a).distance_to(Vector2(b)) <= 2.0:
						near += 1
				if near >= 2:
					ever_clustered += 1
				if near >= 1:
					would_fire_at_1 += 1
		if seen_rat: rounds_with_rats += 1
	print("rounds 1-30 containing any Rat : %d" % rounds_with_rats)
	print("max Rats ever in one wave      : %d (round %d)" % [best_count, best_round])
	print("rat-instances meeting the SHIPPED condition (2+ others w/in 2): %d" % ever_clustered)
	print("rat-instances that WOULD fire at a 1+-other threshold        : %d" % would_fire_at_1)
	print("waves containing 2 Rats at all                               : %d" % waves_with_2)
	get_tree().quit(0)
