class_name RelicMilestones
extends RefCounted
# VD-20: canonical, tutorial-ready wording and predicates. Evaluation is pure.
const FAMILIES := ["opening", "momentum", "row", "execute", "firststrike", "ultrefund", "underdog", "goldscale"]
const TABLE: Array = [
  {
    "id": "opening_1",
    "name": "Opening I",
    "condition": "Win a fight in under 6 seconds.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "elapsed",
        "lt",
        6
      ]
    ]
  },
  {
    "id": "opening_2",
    "name": "Opening II",
    "condition": "Beat an elite in under 10 seconds.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "elite",
        "eq",
        true
      ],
      [
        "elapsed",
        "lt",
        10
      ]
    ]
  },
  {
    "id": "momentum_1",
    "name": "Momentum I",
    "condition": "Win a fight lasting at least 40 seconds.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "elapsed",
        "ge",
        40
      ]
    ]
  },
  {
    "id": "momentum_2",
    "name": "Momentum II",
    "condition": "Beat a decade boss in a fight lasting at least 60 seconds.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "boss",
        "eq",
        true
      ],
      [
        "elapsed",
        "ge",
        60
      ]
    ]
  },
  {
    "id": "row_1",
    "name": "Row I",
    "condition": "Win with at least 4 heroes in the front row.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "front",
        "ge",
        4
      ]
    ]
  },
  {
    "id": "row_2",
    "name": "Row II",
    "condition": "Beat a decade boss with at least 4 heroes in the front row.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "boss",
        "eq",
        true
      ],
      [
        "front",
        "ge",
        4
      ]
    ]
  },
  {
    "id": "execute_1",
    "name": "Execute I",
    "condition": "Beat the first decade boss (wave 10).",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "boss",
        "eq",
        true
      ],
      [
        "round",
        "eq",
        10
      ]
    ]
  },
  {
    "id": "execute_2",
    "name": "Execute II",
    "condition": "Beat a decade boss on Brutal.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "boss",
        "eq",
        true
      ],
      [
        "brutal",
        "eq",
        true
      ]
    ]
  },
  {
    "id": "firststrike_1",
    "name": "First Strike I",
    "condition": "Kill an enemy in the first 2 seconds of a fight.",
    "requirements": [
      [
        "first_kill",
        "le",
        2
      ]
    ]
  },
  {
    "id": "firststrike_2",
    "name": "First Strike II",
    "condition": "Kill an elite in the first 5 seconds of a fight.",
    "requirements": [
      [
        "first_elite_kill",
        "le",
        5
      ]
    ]
  },
  {
    "id": "ultrefund_1",
    "name": "Ult Refund I",
    "condition": "Cast 4 ultimates in one fight.",
    "requirements": [
      [
        "ults",
        "ge",
        4
      ]
    ]
  },
  {
    "id": "ultrefund_2",
    "name": "Ult Refund II",
    "condition": "Cast 10 ultimates in one fight.",
    "requirements": [
      [
        "ults",
        "ge",
        10
      ]
    ]
  },
  {
    "id": "underdog_2",
    "name": "Underdog",
    "condition": "Win a fight after losing half your team.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "lost_half",
        "eq",
        true
      ]
    ]
  },
  {
    "id": "goldscale_2",
    "name": "Gold Scale",
    "condition": "Start a fight holding at least 150 gold.",
    "requirements": [
      [
        "start_gold",
        "ge",
        150
      ]
    ]
  },
  {
    "id": "ladder_armor_dual",
    "name": "Armor",
    "condition": "Win with at least 3 Tanks.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "tanks",
        "ge",
        3
      ]
    ]
  },
  {
    "id": "ladder_max_hp",
    "name": "HP",
    "condition": "A hero reaches 3,000 max HP.",
    "requirements": [
      [
        "max_hp",
        "ge",
        3000
      ]
    ]
  },
  {
    "id": "ladder_magic_power",
    "name": "Magic",
    "condition": "Win with at least 3 Mages.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "mages",
        "ge",
        3
      ]
    ]
  },
  {
    "id": "ladder_atk_dmg",
    "name": "Attack",
    "condition": "Win with at least 3 Fighters.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "fighters",
        "ge",
        3
      ]
    ]
  },
  {
    "id": "ladder_attack_speed",
    "name": "Attack Speed",
    "condition": "Win with at least 3 Ranged heroes.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "ranged",
        "ge",
        3
      ]
    ]
  },
  {
    "id": "ladder_lifesteal",
    "name": "Lifesteal",
    "condition": "Win with at least 2 Healers.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "healers",
        "ge",
        2
      ]
    ]
  },
  {
    "id": "ladder_crit_chance",
    "name": "Crit Chance",
    "condition": "A hero reaches 40% crit chance.",
    "requirements": [
      [
        "crit_chance",
        "ge",
        0.4
      ]
    ]
  },
  {
    "id": "ladder_crit_damage",
    "name": "Crit Damage",
    "condition": "A hero reaches 3x crit damage.",
    "requirements": [
      [
        "crit_damage",
        "ge",
        3
      ]
    ]
  },
  {
    "id": "ladder_gold_econ",
    "name": "Gold",
    "condition": "Finish a fight holding at least 200 gold.",
    "requirements": [
      [
        "finished",
        "eq",
        true
      ],
      [
        "gold",
        "ge",
        200
      ]
    ]
  },
  {
    "id": "ladder_vs_boss",
    "name": "Boss Damage",
    "condition": "Beat 3 decade bosses across any runs.",
    "requirements": [
      [
        "boss_wins",
        "ge",
        3
      ]
    ]
  },
  {
    "id": "ladder_double_atk",
    "name": "Double Attack",
    "condition": "Trigger 15 double attacks in one fight.",
    "requirements": [
      [
        "doubles",
        "ge",
        15
      ]
    ]
  },
  {
    "id": "ladder_on_kill_atk",
    "name": "On-Kill",
    "condition": "One hero gets 8 kills in one fight.",
    "requirements": [
      [
        "max_kills",
        "ge",
        8
      ]
    ]
  },
  {
    "id": "ladder_start_shield",
    "name": "Start Shield",
    "condition": "Win a fight where shields absorb 1,000 damage.",
    "requirements": [
      [
        "won",
        "eq",
        true
      ],
      [
        "shield",
        "ge",
        1000
      ]
    ]
  },
  {
    "id": "ladder_ult_charge",
    "name": "Ult Charge",
    "condition": "One hero casts 3 ultimates in one fight.",
    "requirements": [
      [
        "max_ults",
        "ge",
        3
      ]
    ]
  }
]

static func by_id(id: String) -> Dictionary:
	for row: Dictionary in TABLE:
		if row.id == id:
			return row
	return {}

static func matches(row: Dictionary, facts: Dictionary) -> bool:
	for rule: Array in row.requirements:
		if not facts.has(rule[0]):
			return false
		var value = facts[rule[0]]
		match rule[1]:
			"eq":
				if value != rule[2]: return false
			"ge":
				if value < rule[2]: return false
			"le":
				if value > rule[2]: return false
			"lt":
				if value >= rule[2]: return false
	return true

static func earned(facts: Dictionary) -> Array:
	var out: Array = []
	for row: Dictionary in TABLE:
		if matches(row, facts): out.append(row.id)
	return out

static func relic_gate(id: String) -> String:
	var parts := id.split("_", true, 1)
	if parts.size() != 2 or parts[1] not in FAMILIES:
		return ""
	var high := parts[0] in ["a", "s"]
	if parts[1] in ["underdog", "goldscale"] and not high:
		return ""
	return parts[1] + ("_2" if high else "_1")

static func members(id: String) -> Array:
	var out: Array = []
	for relic: Dictionary in Relic.POOL:
		var gate := "ladder_" + String(relic.get("ladder", "")) if relic.get("ladder_gated", false) else relic_gate(relic.id)
		if gate == id: out.append(relic)
	out.sort_custom(func(a, b): return Relic.GRADE_ORDER.find(a.grade) < Relic.GRADE_ORDER.find(b.grade))
	return out
