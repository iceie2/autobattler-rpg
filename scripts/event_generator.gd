extends Node
class_name EventGenerator

static func generate_event(round: int) -> EventBlessing:
	# Pool is freshly built each call, so no duplicate() needed.
	# (Resource.duplicate() re-runs _init() with empty defaults and drops the
	#  choices array of inner-class objects, which blanked the event panel.)
	var events = _get_event_pool(round)
	return events[randi() % events.size()]

static func _get_event_pool(round: int) -> Array:
	var pool = []

	# Blessing events
	pool.append(_create_gold_blessing(round))
	pool.append(_create_extra_hero_blessing(round))
	pool.append(_create_stat_blessing(round))
	pool.append(_create_healing_blessing())

	# Curse events (risk/reward)
	pool.append(_create_gold_curse(round))
	pool.append(_create_damage_curse())

	# Neutral decision events
	pool.append(_create_sacrifice_event())
	pool.append(_create_gamble_event(round))

	# 2026-07-03 content pass: pool was only 8 entries, so the same handful of
	# events repeated constantly — added to add variety/flavor (see balance_journal.md).
	pool.append(_create_duel_event(round))
	pool.append(_create_echo_curse())
	pool.append(_create_blacksmith_blessing(round))
	pool.append(_create_desperate_wager(round))

	return pool

static func _create_gold_blessing(round: int) -> EventBlessing:
	var event = EventBlessing.new("Gold Rush", "Merchants are selling cheap", EventBlessing.EventType.BLESSING)
	var gold_amount = 3 + int(round * 1.5)
	event.add_choice(
		"Take the gold",
		{"gold": gold_amount},
		"You gain %dg" % gold_amount
	)
	event.add_choice(
		"Invest in training (+1 max hero level)",
		{"max_level": 1},
		"Increase hero level cap by 1"
	)
	return event

static func _create_extra_hero_blessing(round: int) -> EventBlessing:
	var event = EventBlessing.new("Reinforcements", "A new hero has arrived to help", EventBlessing.EventType.BLESSING)
	event.add_choice(
		"Recruit them",
		{"max_units": 1},
		"Add 1 to your max unit limit"
	)
	event.add_choice(
		"Turn them down",
		{"gold": 4},
		"Gain 4g instead"
	)
	return event

static func _create_stat_blessing(round: int) -> EventBlessing:
	var event = EventBlessing.new("Mystical Enhancement", "A magical aura surrounds your team")
	var dmg_boost = 10 + round * 5
	event.add_choice(
		"Boost damage",
		{"team_dmg_mult": 1.15},
		"All heroes deal 15% more damage"
	)
	event.add_choice(
		"Boost defense",
		{"team_def_mult": 1.15},
		"All heroes take 15% less damage"
	)
	event.add_choice(
		"Boost speed",
		{"team_spd_mult": 1.20},
		"All heroes act 20% faster"
	)
	return event

static func _create_healing_blessing() -> EventBlessing:
	var event = EventBlessing.new("Rest Camp", "Your team finds a safe place to rest")
	event.add_choice(
		"Full heal",
		{"heal_all": 1.0},
		"Restore all hero HP to maximum"
	)
	event.add_choice(
		"Restore mana",
		{"restore_mana": 1.0},
		"Restore all hero MP to maximum"
	)
	return event

static func _create_gold_curse(round: int) -> EventBlessing:
	var event = EventBlessing.new("Bandits Attack", "Bandits demand tribute", EventBlessing.EventType.CURSE)
	event.add_choice(
		"Pay the toll",
		{"gold": -4},
		"Lose 4g but continue"
	)
	event.add_choice(
		"Fight back",
		{"gold": 7, "hero_damage": -0.2},  # Lose 20% HP across team
		"Gain 7g but lose 20% team HP"
	)
	return event

static func _create_damage_curse() -> EventBlessing:
	var event = EventBlessing.new("Ambush!", "Enemies attack before the battle", EventBlessing.EventType.CURSE)
	event.add_choice(
		"Take the hit",
		{"hero_damage": -0.3},
		"Your team loses 30% HP"
	)
	event.add_choice(
		"Dodge and flee",
		{"gold": -3},
		"Lose 3g but avoid damage"
	)
	return event

static func _create_sacrifice_event() -> EventBlessing:
	var event = EventBlessing.new("Dark Pact", "A mysterious offer of power", EventBlessing.EventType.NEUTRAL)
	event.add_choice(
		"Accept the power",
		{"team_dmg_mult": 1.25, "max_hp_mult": 0.75},
		"Deal 25% more damage but have 25% less HP"
	)
	event.add_choice(
		"Decline",
		{"gold": 0},
		"Nothing happens"
	)
	return event

static func _create_gamble_event(round: int) -> EventBlessing:
	var event = EventBlessing.new("Gambler's Table", "A merchant offers a risky trade", EventBlessing.EventType.NEUTRAL)
	var high_gold = 8 + round * 2
	event.add_choice(
		"Take the big bet (50/50)",
		{"gold_if_win": high_gold, "gold_if_lose": -5},
		"50%% chance for %dg, 50%% chance to lose 5g" % high_gold
	)
	event.add_choice(
		"Skip",
		{"gold": 2},
		"Take 2g and move on"
	)
	return event

static func _create_duel_event(round: int) -> EventBlessing:
	var event = EventBlessing.new("Old Rival's Duel", "A former ally challenges your team to a friendly duel", EventBlessing.EventType.NEUTRAL)
	event.add_choice(
		"Accept (test your mettle)",
		{"team_dmg_mult": 1.1, "team_spd_mult": 1.1},
		"All heroes deal 10% more damage and act 10% faster"
	)
	var decline_gold = 2 + int(round * 0.5)
	event.add_choice(
		"Decline politely",
		{"gold": decline_gold},
		"Gain %dg instead" % decline_gold
	)
	return event

static func _create_echo_curse() -> EventBlessing:
	var event = EventBlessing.new("Cave of Echoes", "Strange echoes sap your team's nerve", EventBlessing.EventType.CURSE)
	event.add_choice(
		"Push forward and loot the cave",
		{"team_def_mult": 0.9, "gold": 4},
		"All heroes take 10% more damage, but gain 4g"
	)
	event.add_choice(
		"Retreat and regroup",
		{"gold": 0},
		"Nothing happens"
	)
	return event

static func _create_blacksmith_blessing(round: int) -> EventBlessing:
	var event = EventBlessing.new("Blacksmith's Offer", "A traveling blacksmith offers to reinforce your gear", EventBlessing.EventType.BLESSING)
	event.add_choice(
		"Reinforce armor",
		{"max_hp_mult": 1.15},
		"All heroes gain 15% max HP"
	)
	var save_gold = 3 + int(round * 0.7)
	event.add_choice(
		"Save your coin",
		{"gold": save_gold},
		"Gain %dg instead" % save_gold
	)
	return event

static func _create_desperate_wager(round: int) -> EventBlessing:
	var event = EventBlessing.new("Desperate Wager", "A stranger offers one final, bigger bet", EventBlessing.EventType.NEUTRAL)
	var high_gold = 12 + round * 3
	event.add_choice(
		"All in (50/50)",
		{"gold_if_win": high_gold, "gold_if_lose": -8},
		"50%% chance for %dg, 50%% chance to lose 8g" % high_gold
	)
	event.add_choice(
		"Play it safe",
		{"gold": 2},
		"Take 2g and move on"
	)
	return event
