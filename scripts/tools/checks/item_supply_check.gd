extends Node
# Item supply with the component system on vs off: reward-type shares per
# difficulty (20k rolls each) and the enemy held-item chance by round.
# Run: godot --headless res://scenes/tools/item_supply_check.tscn
func _ready() -> void:
	for active in [false, true]:
		ComponentEquipmentGateway.active_run = active
		for diff in [WaveScaler.Difficulty.NORMAL, WaveScaler.Difficulty.VETERAN, WaveScaler.Difficulty.BRUTAL]:
			var counts := {}
			for i in range(20000):
				var t: int = int(RoundReward.roll(diff, 10)["type"])
				counts[t] = int(counts.get(t, 0)) + 1
			var parts: Array = []
			for t in [RoundReward.Type.NOTHING, RoundReward.Type.GOLD, RoundReward.Type.ITEM, RoundReward.Type.STAT_BONUS]:
				parts.append("%s %4.1f%%" % [RoundReward.TYPE_NAMES[t], 100.0 * int(counts.get(t, 0)) / 20000.0])
			print("SUPPLY component=%s diff=%d  %s" % [str(active), diff, "  ".join(parts)])
		var held: Array = []
		for r in [1, 10, 20, 30]:
			var c: float = (0.08 + r * 0.008) * ComponentEquipmentGateway.supply_mult()
			held.append("r%d %.1f%%" % [r, c * 100.0])
		print("SUPPLY component=%s held-item chance per enemy (no tree bonus): %s" % [str(active), ", ".join(held)])
	ComponentEquipmentGateway.active_run = false
	get_tree().quit()
