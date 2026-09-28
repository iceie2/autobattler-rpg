class_name RelicMilestoneBattle
extends RefCounted
# Battle facts retain the starting roster, even when main_game parks its dead.
var heroes: Array = []
var fallen: Dictionary = {}
var facts: Dictionary = {}
var active := false

func begin(roster: Array, gold: int, round_number: int, brutal: bool) -> void:
	heroes.clear()
	fallen.clear()
	facts = {"start_gold": gold, "round": round_number, "brutal": brutal,
		"boss": WaveScaler.is_boss_round(round_number), "elite": WaveScaler.is_elite_round(round_number),
		"front": 0, "tanks": 0, "mages": 0, "fighters": 0, "ranged": 0, "healers": 0}
	var roles := {UnitBase.TraitClass.TANK: "tanks", UnitBase.TraitClass.MAGE: "mages",
		UnitBase.TraitClass.FIGHTER: "fighters", UnitBase.TraitClass.RANGED: "ranged", UnitBase.TraitClass.HEALER: "healers"}
	for u in roster:
		if not is_instance_valid(u) or u.is_summoned: continue
		heroes.append(u)
		if u.home_position.y == 5: facts.front += 1
		if roles.has(u.trait_class): facts[roles[u.trait_class]] += 1
	active = true
	sample()

func death(unit: UnitBase, enemy: bool, elapsed: float) -> void:
	if not active: return
	if enemy:
		facts["first_kill"] = minf(float(facts.get("first_kill", INF)), elapsed)
		if unit.is_elite:
			facts["first_elite_kill"] = minf(float(facts.get("first_elite_kill", INF)), elapsed)
	elif unit in heroes:
		fallen[unit.get_instance_id()] = true

func sample() -> Dictionary:
	var ults := 0
	var doubles := 0
	var shield := 0
	for u in heroes:
		if not is_instance_valid(u): continue
		ults += u.milestone_ult_casts
		doubles += u.milestone_double_attacks
		shield += u.milestone_shield_absorbed
		facts["max_ults"] = maxi(int(facts.get("max_ults", 0)), u.milestone_ult_casts)
		facts["max_kills"] = maxi(int(facts.get("max_kills", 0)), u.kill_count)
		for stat: String in ["max_hp", "crit_chance", "crit_damage"]:
			facts[stat] = maxf(float(facts.get(stat, 0.0)), float(u.get(stat)))
	facts["ults"] = ults
	facts["doubles"] = doubles
	facts["shield"] = shield
	facts["lost_half"] = not heroes.is_empty() and fallen.size() * 2 >= heroes.size()
	return facts

func finish(won: bool, elapsed: float, gold: int) -> Dictionary:
	sample()
	facts.merge({"finished": true, "won": won, "elapsed": elapsed, "gold": gold}, true)
	active = false
	return facts
