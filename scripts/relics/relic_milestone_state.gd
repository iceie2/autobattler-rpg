class_name RelicMilestoneState
extends RefCounted
# No IO: tests exercise exactly the state serialized by Progression.
var unlocked: Dictionary = {}
var pending: Dictionary = {}
var boss_wins: Dictionary = {}
var pool: Dictionary = {}

func begin_run() -> void:
	pool = unlocked.duplicate()

func resume_pool(snapshot: Dictionary) -> void:
	pool = snapshot.duplicate()

func record(facts: Dictionary, boss_token: String = "") -> Array:
	if facts.get("won", false) and facts.get("boss", false) and boss_token != "" and boss_wins.size() < 3:
		boss_wins[boss_token] = true
	var checked := facts.duplicate()
	checked["boss_wins"] = boss_wins.size()
	var awards: Array = []
	for id: String in RelicMilestones.earned(checked):
		if not unlocked.has(id) and not pending.has(id):
			pending[id] = true
			awards.append(id)
	return awards

func collect() -> void:
	unlocked.merge(pending, true)
	pending.clear()
	# Deliberately leave the active pool alone, even after collection.

func to_dict() -> Dictionary:
	return {"unlocked": unlocked.duplicate(), "pending": pending.duplicate(), "boss_wins": boss_wins.duplicate()}

func restore(data: Dictionary) -> void:
	unlocked = _known(data.get("unlocked", {}))
	pending = _known(data.get("pending", {}))
	for id in unlocked: pending.erase(id)
	var bosses = data.get("boss_wins", {})
	boss_wins = bosses.duplicate() if bosses is Dictionary else {}
	begin_run()

static func _known(value) -> Dictionary:
	var out: Dictionary = {}
	if value is Dictionary:
		for id in value:
			if not RelicMilestones.by_id(str(id)).is_empty() and value[id]: out[id] = true
	return out
