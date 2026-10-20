extends Node

func _ready() -> void:
	var errors: Array[String] = []
	var director := WaveDirector.new()
	for boundary in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
		if WaveScaler.past_elite_pool(boundary).size() != boundary / 10 - 1:
			errors.append("premature unlock at %d" % boundary)
		if WaveScaler.past_elite_pool(boundary + 1).size() != boundary / 10:
			errors.append("missing unlock after %d" % boundary)
	var seen: Dictionary = {1: {}, 2: {}}
	var price := func(code: String, _round: int) -> float:
		return 200.0 if code == "test_reference" else (80.0 if code.begins_with("past:") else 40.0)
	for tier in [1, 2]:
		for seed in range(1, 201):
			var picks := WaveScaler.fill_to_score({"test_reference": 1}, tier, 61, seed, price)
			var count := 0
			for code: String in picks:
				if code.begins_with("past:"): count += int(picks[code])
			seen[tier][count] = true
			if count > tier: errors.append("elite cap exceeded")
		for n in range(tier + 1):
			if not seen[tier].has(n): errors.append("tier %d never produced %d elites" % [tier, n])
	for round in [11, 21, 31, 41, 51, 61, 71, 81, 91]:
		for code: String in WaveScaler.past_elite_pool(round):
			var entry := {"code": code, "type": EnemyFactory.CODE_TO_TYPE[WaveScaler.original_code(code)]}
			director._resolve_past_elites([entry], round)
			var unit := director.create_enemy_for_entry(entry, round)
			if not unit.is_elite or unit.level != WaveScaler.past_elite_level(code, round):
				errors.append("elite identity/level mismatch %s/%d" % [code, round])
			if not is_equal_approx(WaveScaler.score_unit(unit), director.score_code(code, round)):
				errors.append("price mismatch %s/%d" % [code, round])
			unit.free()
	for tier in [0, 1, 2]:
		for round in [11, 25, 31, 40, 61, 70, 81, 90]:
			for seed in range(1, 13):
				var spec := director.generate_wave_spec(round, tier, 9, -1, seed)
				var count := 0
				for entry: Dictionary in spec:
					if entry.get("past_elite", false): count += 1
					if str(entry.code).begins_with("past:"): errors.append("internal code leaked")
				if count > tier: errors.append("spawn cap exceeded")
	print("PAST_ELITES_CHECK: ", "ALL PASS" if errors.is_empty() else str(errors), " distributions=", seen)
	get_tree().quit(0 if errors.is_empty() else 1)
