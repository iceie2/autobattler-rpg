extends RefCounted
class_name SynergyTracker

# Reads the current player roster and works out which element/trait synergies are
# active and what tier each is at. Used both to render the SET BONUSES panel and
# to compute the combat stat bonuses applied at battle start.

# Each active entry: { type:"element"/"trait", key:int, name:String, count:int,
#   tier:1/2, stat:String, val:float, desc:String, color:Color }
var active: Array = []
var element_counts: Dictionary = {}
var trait_counts: Dictionary = {}

func update_from_team(units: Array) -> void:
	element_counts.clear()
	trait_counts.clear()
	for u in units:
		if u and is_instance_valid(u):
			element_counts[u.current_element] = element_counts.get(u.current_element, 0) + 1
			trait_counts[u.trait_class] = trait_counts.get(u.trait_class, 0) + 1

	active.clear()
	for e in SynergyData.ELEMENT_SYN:
		_consider("element", e, element_counts.get(e, 0), SynergyData.ELEMENT_SYN[e], SynergyData.element_color(e))
	for t in SynergyData.TRAIT_SYN:
		_consider("trait", t, trait_counts.get(t, 0), SynergyData.TRAIT_SYN[t], SynergyData.trait_color(t))

func _consider(type: String, key: int, count: int, data: Dictionary, col: Color) -> void:
	var need: Array = data["need"]
	var tier := 0
	if count >= int(need[1]):
		tier = 2
	elif count >= int(need[0]):
		tier = 1
	if tier == 0:
		return
	var val: float = float(data["t2"]) if tier == 2 else float(data["t1"])
	active.append({
		"type": type, "key": key, "name": data["name"], "count": count,
		"tier": tier, "stat": data["stat"], "val": val,
		"desc": SynergyData.bonus_desc(data["stat"], val), "color": col,
	})

# Accumulated team stat bonuses from all active synergies. Multipliers combine
# multiplicatively; range_add sums.
func team_bonuses() -> Dictionary:
	var b := {
		"attack_damage": 1.0, "magic_power": 1.0, "resistance": 1.0,
		"max_hp": 1.0, "attack_speed": 1.0, "range_add": 0,
	}
	for s in active:
		var stat: String = s["stat"]
		if stat == "range_add":
			b["range_add"] += int(s["val"])
		elif b.has(stat):
			b[stat] *= float(s["val"])
	return b
