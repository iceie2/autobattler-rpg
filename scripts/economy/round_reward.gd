extends Node
class_name RoundReward

# Gacha-style round-clear reward. All 3 difficulties are rolled ONCE when the
# round starts (see main_game.gd's _on_battle_round_started) and shown in full —
# the player sees exactly what they'd win at each tier and can weigh "is this
# item/stat bonus worth fighting the harder wave for?" before committing. The
# roll does NOT change if you flip between difficulties or reselect one you've
# already viewed — what you see is locked in for the round.

enum Type { NOTHING, GOLD, ITEM, STAT_BONUS }

# Odds per difficulty (weights, need not sum to 100). Higher difficulty skews
# away from "nothing" and toward the rarer item/stat-bonus rewards.
# Balance 2026-07-24 (user request): fighting the harder wave for NORMAL/HARD
# must always pay off — NOTHING only exists on EASY now. Its old NORMAL/HARD
# weight (20 / 5) folded proportionally into GOLD/ITEM/STAT_BONUS so those
# tables still sum the same as before, just with the whiff removed.
const ODDS := {
	WaveScaler.Difficulty.EASY:   {Type.NOTHING: 40, Type.GOLD: 40, Type.ITEM: 15, Type.STAT_BONUS: 5},
	WaveScaler.Difficulty.NORMAL: {Type.GOLD: 44, Type.ITEM: 38, Type.STAT_BONUS: 18},
	WaveScaler.Difficulty.HARD:   {Type.GOLD: 26, Type.ITEM: 42, Type.STAT_BONUS: 32},
}

const TYPE_NAMES := {
	Type.NOTHING:     "Nothing",
	Type.GOLD:        "Gold",
	Type.ITEM:        "Item",
	Type.STAT_BONUS:  "Stat Bonus",
}

# Compact, concrete description of an already-rolled reward — shown directly
# in the difficulty panel so the player can see exactly what they'd win.
static func describe(reward: Dictionary) -> String:
	match reward.get("type", Type.NOTHING):
		Type.NOTHING:
			return "Nothing"
		Type.GOLD:
			return "+%d Gold" % int(reward.get("gold", 0))
		Type.ITEM:
			var item: EquipmentItem = reward.get("item")
			return "%s (%s)" % [item.name, item.get_rarity_name()] if item else "Item"
		Type.STAT_BONUS:
			var p: Dictionary = reward.get("perk", {})
			if p.is_empty():
				return "Stat Bonus"
			var _v: float = p.get("rolled_value", p.get("value", 0))
			var val_str: String = LevelUpScreen.format_perk_value(p)
			return "%s %s (%s)" % [p.get("label", "?"), val_str, p.get("grade", "?")]
		_:
			return ""

static func roll(difficulty: int, round: int) -> Dictionary:
	var odds: Dictionary = ODDS.get(difficulty, ODDS[WaveScaler.Difficulty.EASY])
	var total := 0
	for w in odds.values():
		total += int(w)
	var r := randi() % total
	var acc := 0
	var chosen_type: int = Type.NOTHING
	for t in odds:
		acc += int(odds[t])
		if r < acc:
			chosen_type = t
			break

	var result := {"type": chosen_type}
	match chosen_type:
		Type.GOLD:
			# Economy v3 (2026-07-03): rescaled to the coin-drop economy (10g
			# heroes, ~1g kills). These now rain onto the field as physical
			# coins at victory and get vacuumed with the rest.
			var base: float = 2.0 + round * 0.4
			var mult: float = 1.0 + difficulty * 0.5   # EASY 1.0x, NORMAL 1.5x, HARD 2.0x
			result["gold"] = maxi(1, int(base * mult))
		Type.ITEM:
			var max_rarity: int = EquipmentItem.Rarity.EPIC if difficulty == WaveScaler.Difficulty.HARD else EquipmentItem.Rarity.RARE
			result["item"] = EquipmentManager.generate_item(round, max_rarity)
		Type.STAT_BONUS:
			# ONE gacha-graded perk, rolled once and shown in full on the
			# difficulty panel — the only choice left after winning is which
			# unit on the team receives it (no separate "pick 1 of 3" step,
			# since that would let the shown preview lie about what you get).
			var base_perk: Dictionary = LevelUpScreen.PERKS[randi() % LevelUpScreen.PERKS.size()]
			result["perk"] = LevelUpScreen.roll_perk_offer(base_perk)
	return result
