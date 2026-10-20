class_name RunMap
extends RefCounted
# ══════════════════════════════════════════════════════════════════════════════
# RUN MAP — the Slay-the-Spire-style branching path through one biome.
# Design: RUN_MAP_PLAN.md §3 (decisions locked with the owner 2026-09-19).
#
# ── THE ONE RULE THAT MAKES THIS WORK: TWO COUNTERS ───────────────────────────
# A biome is ten fixed PATH STAGES. Stage 5 is the elite and stage 10 is the
# boss. Every combat option on stage N uses wave N's scaler data. Events and the
# merchant REPLACE an option on that stage; they never create extra rows.
#
# What the player chooses is:
# A row is 2–5 choices wide. Combat difficulties never repeat within a row.
# Four-wide rows are Easy / Normal / Hard plus one utility node, five-wide rows
# plus two (VD-14). Narrower rows contain fights only, always including Normal.
# Utility choices are optional: every incoming path retains a combat exit.
#
# Interstitial nodes must never call GameState.start_battle_round(). That single
# fact is the whole model; it's also the thing a later refactor is most likely
# to break, which is why it's stated here and in CONVENTIONS.md.
#
# ── WHY THIS IS A RefCounted WITH NO SCENE ────────────────────────────────────
# Same reason WaveDirector is (see wave_director.gd): the arena harness has to
# be able to generate and walk thousands of maps headlessly. Anything that
# needs the scene tree belongs in the map SCREEN, not here.
# ══════════════════════════════════════════════════════════════════════════════

enum NodeType { RELIC, BATTLE, ELITE, BOSS, EVENT, MERCHANT, CAMP }

const WAVES_PER_BIOME := 10

# Rows are 2 to 5 nodes wide and the width VARIES per row (owner call,
# 2026-09-19). A grid of identical 3-wide rows read as a corridor: every row
# asked the same question, so by the third one the player was clicking, not
# choosing. A 2-wide row is a genuine fork; a 4-wide row is a spread worth
# studying; alternating them is what makes it read as a map.
const MIN_WIDTH := 2
# 5 since VD-14 (2026-09-23, owner: "changing the max row witdth to 5. so we
# can fit more events/rest/shop on our map"). A 5-wide row is the three fight
# tiers plus two side nodes. Its weight is taken from the other widths roughly
# evenly, so the map keeps its mix of forks and spreads.
const MAX_WIDTH := 5
const WIDTH_WEIGHTS := {2: 22, 3: 34, 4: 26, 5: 18}

# Camp is wired into path generation now; its actual interaction is the next
# feature pass. It never appears on wave 1 or on the protected elite/boss rows.
const INCLUDE_CAMP := true

# ── THE THIRTY SLOTS, AND WHY WE DON'T FILL THEM ──────────────────────────────
# Ten waves × three intensities is thirty possible fights per biome. A map that
# offers all thirty is the same map every run. So each wave row offers only a
# SUBSET of its tiers, and a slot that isn't a fight can be an event or a
# merchant instead.
#
# THE CONSEQUENCE, STATED PLAINLY: taking that event means you never fight that
# wave. Paths no longer all fight ten waves — one can fight eight and reach the
# boss poorer for it (kill gold + item drops). NOT lower-level: since 2026-09-29
# (owner: events must not be punished) a utility node pays that stage's Normal-
# clear XP + early crystal floor — main_game._grant_skipped_wave_rewards. The
# trade is gold/loot vs the node's own payoff, and
# it's why a wave row always keeps at least one real fight (so the wave EXISTS
# for anyone who wants it) and why the elite and boss rows are fights only.
# Raised 2026-09-27 (VD-17, owner: "we need more events/merchants"): a route
# met 0.93 events over ten stages at 0.30 / 4.

# VD-17: where the two merchants go, and how hard generation tries to make
# both reachable (see merchant_reach_problems).
const MERCHANT_EARLY := Vector2i(3, 4)
const MERCHANT_LATE := Vector2i(7, 9)
const MERCHANT_REACH_ATTEMPTS := 40

# One start plus ten stages. There are no interstitial rows.
const ROW_PLAN: Array[Dictionary] = [
	{"kind": "relic",        "wave": 0},
	{"kind": "battle",       "wave": 1},
	{"kind": "battle",       "wave": 2},
	{"kind": "battle",       "wave": 3},
	{"kind": "battle",       "wave": 4},
	{"kind": "elite",        "wave": 5},
	{"kind": "battle",       "wave": 6},
	{"kind": "battle",       "wave": 7},
	{"kind": "battle",       "wave": 8},
	{"kind": "battle",       "wave": 9},
	{"kind": "boss",         "wave": 10},
]

# ── State ─────────────────────────────────────────────────────────────────────
var biome: int = 0                  # 0-based decade index
var rows: Array = []                # Array[Array[Dictionary]] — nodes per row
var current_id: String = ""         # node the player is standing on ("" = not started)
var cleared: Dictionary = {}        # {node_id: true}
var generation_seed: int = 0        # persisted so telemetry can reproduce the layout

var _rng := RandomNumberGenerator.new()

# ── Generation ────────────────────────────────────────────────────────────────
# roll_rewards=false skips the RoundReward/EquipmentManager rolls, so the
# harness can generate thousands of maps to check structural invariants without
# minting thousands of throwaway items.
static func generate(biome_index: int, rng_seed: int = 0, roll_rewards: bool = true) -> RunMap:
	var map := RunMap.new()
	map.biome = maxi(0, biome_index)
	map.generation_seed = rng_seed if rng_seed != 0 else randi()
	map._rng.seed = map.generation_seed
	# VD-17: a merchant the player's lane can't reach is a merchant that
	# doesn't exist. Rebuild (the rng carries on, so this stays deterministic
	# per seed) until both merchants are reachable from where they must be.
	for _attempt in range(MERCHANT_REACH_ATTEMPTS):
		map._build(roll_rewards)
		if map.merchant_reach_problems().is_empty():
			break
	return map

func _build(roll_rewards: bool) -> void:
	rows.clear()
	cleared.clear()
	current_id = ""
	# TWO merchants per biome (VD-17, owner 2026-09-27: three runs to biome 3
	# without meeting one). The first comes once the player has had a few
	# fights' gold; the second after the elite, before the boss. Each merchant
	# row is widened to at least four choices to keep all three combat tiers.
	var merchant_waves: Array = [_rng.randi_range(MERCHANT_EARLY.x, MERCHANT_EARLY.y),
		_rng.randi_range(MERCHANT_LATE.x, MERCHANT_LATE.y)]

	for r in range(ROW_PLAN.size()):
		var plan: Dictionary = ROW_PLAN[r]
		match String(plan["kind"]):
			"relic":
				rows.append([_make_node(r, 1, NodeType.RELIC, 0, 0, roll_rewards)])
			"battle":
				var wave: int = int(plan["wave"])
				rows.append(_build_battle_row(r, wave, roll_rewards, wave in merchant_waves))
			"elite":
				rows.append(_build_tiered_row(r, int(plan["wave"]), NodeType.ELITE, roll_rewards))
			"boss":
				rows.append(_build_tiered_row(r, int(plan["wave"]), NodeType.BOSS, roll_rewards))
	_assign_layout()
	_wire_edges()

# Give each generated map its own silhouette. Rows remain ordered and readable,
# but they no longer sit on the same perfectly centred 2/3/4-lane stencil.
# Values are stored on the nodes, so save/load preserves the exact composition.
func _assign_layout() -> void:
	for r in range(rows.size()):
		var row: Array = rows[r]
		var count: int = row.size()
		# Keep the endpoints calmer; the middle of the journey is where the trail
		# is allowed to climb, dip, bunch up, and open out.
		var endpoint_weight: float = 0.35 if r == 0 or r == rows.size() - 1 else 1.0
		var row_shift: float = _rng.randf_range(-0.34, 0.34) * endpoint_weight
		var spacing: float = _rng.randf_range(0.88, 1.10)
		var x_shift: float = 0.0 if r == 0 or r == rows.size() - 1 \
			else _rng.randf_range(-0.13, 0.13)
		for i in range(count):
			var centred: float = float(i) - float(count - 1) * 0.5
			var local_jitter: float = _rng.randf_range(-0.10, 0.10) if count > 1 else 0.0
			row[i]["layout_lane"] = centred * spacing + row_shift + local_jitter
			row[i]["layout_stage"] = x_shift

# A stage row: distinct combat tiers, with side nodes replacing harder ones.
# Every row keeps at least one fight for players who want the scaler encounter.
func _build_battle_row(r: int, wave: int, roll_rewards: bool,
		force_merchant: bool = false) -> Array:
	var width: int = _pick_width()
	# The biome opens on a SINGLE relic node, and every node above it has to be
	# reachable from that one node — so the first row's width is the width of the
	# opening fan. Four made it sprawl the whole screen; three still offers a
	# real choice of lane without the start looking like a starburst.
	if r == 1:
		width = mini(width, 3)
	# Merchants remain on their scheduled stages, but need a wide column so
	# they are a side choice rather than replacing a fight in a narrow fork.
	if force_merchant:
		width = maxi(width, 4)
	# How many side nodes this row carries. Rows wider than the three fight
	# tiers MUST spend the extra width on side nodes — that is what width is for
	# (VD-14, owner: "so we can fit more events/rest/shop on our map") — and
	# narrower rows contain fights only (owner, 2026-10-07).
	var n_util: int = utilities_for_width(width)
	var util_types: Array = []
	for u in range(n_util):
		if u == 0 and force_merchant:
			util_types.append(NodeType.MERCHANT)
			continue
		var t: int = _pick_utility_type(wave)
		# Two side nodes in one row should be two different offers when the
		# wave allows it, or the pair reads as a duplicate rather than a choice.
		if t in util_types and wave >= 3:
			t = NodeType.EVENT if t == NodeType.CAMP else NodeType.CAMP
		util_types.append(t)
	var tiers: Array = _distinct_tiers(width - n_util)
	# Battles stay in ascending difficulty by COLUMN INDEX — col 0 is the mildest.
	# Which direction that points on screen is the map screen's business (it
	# currently draws col 0 as the topmost lane); nothing here should care. The
	# utility slots move between runs, each replacing one conceptual lane rather
	# than changing the order.
	# Both outside lanes are fights. This permits non-crossing paths to give
	# every parent a fight even when the next column includes side choices.
	var slots: Array = range(1, width - 1)
	var util_slots: Array = []
	for _u in range(n_util):
		util_slots.append(slots.pop_at(_rng.randi_range(0, slots.size() - 1)))
	util_slots.sort()
	var out: Array = []
	var tier_i: int = 0
	var util_i: int = 0
	for c in range(width):
		if c in util_slots:
			var node := _make_node(r, c, int(util_types[util_i]), 0, 0, roll_rewards)
			node["slot_wave"] = wave
			node["round"] = absolute_round(wave)
			out.append(node)
			util_i += 1
		else:
			out.append(_make_node(r, c, NodeType.BATTLE, int(tiers[tier_i]), wave, roll_rewards))
			tier_i += 1
	return out

# Side nodes a row of this width must carry: whatever doesn't fit three fight
# tiers. A 4-wide row is Normal / Veteran / Brutal plus one; a 5-wide row plus
# two (VD-14). Narrower rows contain no utility nodes.
static func utilities_for_width(width: int) -> int:
	return maxi(0, width - 3)

func _pick_width() -> int:
	var total: int = 0
	for w in WIDTH_WEIGHTS.values():
		total += int(w)
	var roll: int = _rng.randi() % total
	var acc: int = 0
	for w in range(MIN_WIDTH, MAX_WIDTH + 1):
		acc += int(WIDTH_WEIGHTS.get(w, 0))
		if roll < acc:
			return w
	return 3

# Which fight tiers a row offers. NORMAL IS ALWAYS ONE OF THEM (VD-12, owner
# 2026-09-23): a fresh account's whole run is Normal, so a row without a Normal
# fight is the map itself killing new accounts. The old version rolled a
# one-fight row's tier at random, and a third of those rows came out Brutal-only
# — the owner's "wave 3 event or hard fight". A side node therefore replaces a
# HARDER tier, never Normal: that is the order the draws below keep.
func _distinct_tiers(count: int) -> Array:
	if count >= 3:
		return [0, 1, 2]
	if count == 2:
		return [0, 1] if _rng.randf() < 0.5 else [0, 2]
	return [0]

# Pick an ordinary utility. The one merchant is assigned separately so random
# utility rolls can never create duplicates.
func _pick_utility_type(wave: int) -> int:
	# The opening column is combat-only; later wide columns can offer camp.
	if INCLUDE_CAMP and wave >= 3 and _rng.randf() < 0.30:
		return NodeType.CAMP
	return NodeType.EVENT

# The elite and the boss are FORCED — every path meets them (owner's call), one
# node per intensity. They use the same easy/climb/hold guarantees as ordinary
# stages, so players can retreat to easy at the elite or boss as well.
func _build_tiered_row(r: int, wave: int, type: int, roll_rewards: bool) -> Array:
	var out: Array = []
	for c in range(3):
		out.append(_make_node(r, c, type, c, wave, roll_rewards))
	return out

func _make_node(r: int, c: int, type: int, difficulty: int, wave: int,
		roll_rewards: bool) -> Dictionary:
	var node: Dictionary = {
		"id": "b%dr%dc%d" % [biome, r, c],
		"row": r, "col": c, "type": type,
		"difficulty": difficulty,
		"wave": wave,                       # 0 = utility; slot_wave still locates it
		"slot_wave": wave,
		"round": absolute_round(wave),
		"children": [],
		"grade": "C",
		"reward": {},
		# The run's pin for this fight's Veteran/Brutal filler. Minted from the
		# MAP's rng, so it is a property of this run: a new run rolls a new cast
		# for the same wave, while within the run the node card and the fight it
		# opens are guaranteed to be the same fight. Rides in the node dict, so
		# to_dict/from_dict carry it through a save with no extra handling.
		# See WaveScaler._filler_rng.
		"wave_seed": _rng.randi_range(1, 1 << 30),
	}
	if roll_rewards and wave > 0:
		# A map node that pays NOTHING is a node nobody weighs — it's dead space
		# on a screen whose whole job is to make you choose. Normal-tier rewards
		# are 40% Nothing (RoundReward.ODDS), which left roughly a third of the
		# map grey and meaningless. Re-roll past it: every node on the map
		# advertises something. (The odds table is untouched — this is the map
		# declining to draw a blank, not a change to what a round pays.)
		node["reward"] = RoundReward.roll(difficulty, node["round"])
		var guard: int = 0
		while int(node["reward"].get("type", RoundReward.Type.NOTHING)) \
				== RoundReward.Type.NOTHING and guard < 12:
			node["reward"] = RoundReward.roll(difficulty, node["round"])
			guard += 1
		node["grade"] = grade_for_reward(node["reward"])
	elif wave == 0:
		node["grade"] = _roll_node_grade(type)
	return node

# Interstitial/relic nodes have no pre-rolled reward to read a grade off, so
# they roll one directly. It advertises how RICH the node is, not whether the
# outcome will be good — an S-grade event can still be an S-grade disaster.
func _roll_node_grade(type: int) -> String:
	var table: Dictionary = {"D": 22, "C": 34, "B": 24, "A": 14, "S": 6}
	if type == NodeType.RELIC:
		table = {"C": 30, "B": 34, "A": 24, "S": 12}   # treasure skews up
	var total: int = 0
	for w in table.values():
		total += int(w)
	var roll: int = _rng.randi() % total
	var acc: int = 0
	for g in ["D", "C", "B", "A", "S"]:
		if not table.has(g):
			continue
		acc += int(table[g])
		if roll < acc:
			return g
	return "C"

# A node's letter comes from the quality of what it PAYS, on each reward type's
# own scale — an Epic item is an A whatever tier dropped it, a perk reports the
# grade it actually rolled. Uses the same letters/colors as recruits, perks,
# relics and shop cards (UnitFactory.GRADE_COLORS).
static func grade_for_reward(reward: Dictionary) -> String:
	match int(reward.get("type", RoundReward.Type.NOTHING)):
		RoundReward.Type.NOTHING:
			return "F"
		RoundReward.Type.GOLD:
			return "D"
		RoundReward.Type.ITEM:
			var item: EquipmentItem = reward.get("item")
			if item == null:
				return "D"
			return ["D", "C", "B", "A", "S"][clampi(item.rarity, 0, 4)]
		RoundReward.Type.STAT_BONUS:
			return String(reward.get("perk", {}).get("grade", "C"))
	return "C"

# ── Edges ─────────────────────────────────────────────────────────────────────
# Difficulty choices take priority over non-crossing geometry (owner, 2026-10-07).
# Draw only required combat links and local utility branches; crossings are
# allowed when they preserve a player's ability to climb or return to easy.
func _wire_edges() -> void:
	for r in range(rows.size() - 1):
		var parents: Array = rows[r]
		var children: Array = rows[r + 1]
		var demands: Array = _row_demands(parents)
		for i in range(parents.size()):
			# The opening relic has no difficulty commitment: offer every tier.
			parents[i]["children"] = _required_combat_ids(children, 1 if r == 0 else int(demands[i]))
		# Keep side branches local. Both merchants must remain available from
		# every lane entering their stage, so they deliberately get wider access.
		for child in children:
			if is_battle_node(child):
				continue
			if int(child["type"]) == NodeType.MERCHANT:
				for parent in parents:
					parent["children"].append(String(child["id"]))
			else:
				var nearest: int = 0
				var distance: float = INF
				for i in range(parents.size()):
					var d: float = absf(float(parents[i].get("layout_lane", i))
							- float(child.get("layout_lane", child["col"])))
					if d < distance:
						distance = d
						nearest = i
				parents[nearest]["children"].append(String(child["id"]))

# Easy: easy + the next higher tier offered. Medium: all combat tiers.
# Hard: easy + hard (or the hardest tier present in a narrow column).
# Utility nodes inherit their neighbouring combat lane's demand.
static func _required_combat_ids(children: Array, demand: int) -> Array:
	var fights: Array = []
	for child in children:
		if is_battle_node(child):
			fights.append(child)
	fights.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["difficulty"]) < int(b["difficulty"]))
	var ids: Array = []
	if fights.is_empty():
		return ids
	ids.append(String(fights[0]["id"]))
	if demand == 1:
		for fight in fights:
			if not String(fight["id"]) in ids:
				ids.append(String(fight["id"]))
	elif fights.size() > 1:
		var target: Dictionary = fights[1] if demand == 0 else fights.back()
		ids.append(String(target["id"]))
	return ids
static func _every_parent_has_combat(parents: Array, children: Array) -> bool:
	var combat_ids: Dictionary = {}
	for child in children:
		if is_battle_node(child):
			combat_ids[String(child["id"])] = true
	for parent in parents:
		var has_combat := false
		for cid in parent["children"]:
			if combat_ids.has(String(cid)):
				has_combat = true
		if not has_combat:
			return false
	return true

# Which columns of the next row a node currently points at, in order.
func _child_cols(parent: Dictionary, kid_index: Dictionary) -> Array:
	var cols: Array = []
	for cid in parent["children"]:
		if kid_index.has(String(cid)):
			cols.append(int(kid_index[String(cid)]))
	cols.sort()
	return cols

# How much difficulty a player standing on each node of a row has already taken
# on. A fight reports its own tier. A side node reports the lane it sits in —
# the tier of the fight to its left — because stepping onto an event doesn't
# move you out of the brutal lane, it just doesn't fight you there. Columns run
# easy to hard, so this remains non-decreasing across a row.
static func _row_demands(row: Array) -> Array:
	var out: Array = []
	var last: int = 0
	for n in row:
		if is_battle_node(n):
			last = int(n["difficulty"])
		out.append(last)
	return out

# VD-12 (owner, 2026-09-23): "we want the player to always have ways to go
# easier in difficulty." A way DOWN is a side node or a fight strictly easier
# than the lane you're in; the Normal lane can't go lower, so for it a Normal
# fight counts. Strict on purpose — an equal-tier child is a way to hold, not a
# way down, which is exactly the "normal -> normal" the owner flagged.
static func _is_way_down(child: Dictionary, demand: int) -> bool:
	return not is_battle_node(child) or int(child["difficulty"]) < maxi(demand, 1)

# Nodes whose every child is a fight at least as hard as their own lane.
func no_way_down_nodes() -> int:
	return _count_nodes_where(func(kids: Array, demand: int) -> bool:
		for k in kids:
			if _is_way_down(k, demand):
				return false
		return true)

# Nodes with at least one strictly HARDER fight ahead — the climbing VD-12's
# downhill rule trades away, kept as a number so the trade stays visible.
func can_climb_nodes() -> int:
	return _count_nodes_where(func(kids: Array, demand: int) -> bool:
		for k in kids:
			if is_battle_node(k) and int(k["difficulty"]) > demand:
				return true
		return false)

# Battle rows with no Normal fight in them — the owner's wave-3 screenshot.
func rows_without_normal() -> int:
	var count: int = 0
	for r in range(rows.size()):
		if String(ROW_PLAN[r]["kind"]) != "battle":
			continue
		var has_normal: bool = false
		for n in rows[r]:
			if is_battle_node(n) and int(n["difficulty"]) == 0:
				has_normal = true
		if not has_normal:
			count += 1
	return count

func _count_nodes_where(test: Callable) -> int:
	var count: int = 0
	for r in range(rows.size() - 1):
		var demands: Array = _row_demands(rows[r])
		var kid_index: Dictionary = {}
		for c in range(rows[r + 1].size()):
			kid_index[String(rows[r + 1][c]["id"])] = c
		for i in range(rows[r].size()):
			var kids: Array = []
			for ci in _child_cols(rows[r][i], kid_index):
				kids.append(rows[r + 1][ci])
			if bool(test.call(kids, int(demands[i]))):
				count += 1
	return count

# Required difficulty choices absent from the graph (arena telemetry).
func missing_paths() -> int:
	var total: int = 0
	for r in range(rows.size() - 1):
		var demands: Array = _row_demands(rows[r])
		for i in range(rows[r].size()):
			for cid in _required_combat_ids(rows[r + 1], 1 if r == 0 else int(demands[i])):
				if not cid in rows[r][i]["children"]:
					total += 1
	return total
func edge_count() -> int:
	var total: int = 0
	for r in range(rows.size() - 1):
		for n in rows[r]:
			total += (n["children"] as Array).size()
	return total

# ── Walking the map ───────────────────────────────────────────────────────────
func node_by_id(id: String) -> Dictionary:
	for row in rows:
		for n in row:
			if String(n["id"]) == id:
				return n
	return {}

func nodes_in_row(r: int) -> Array:
	return rows[r] if r >= 0 and r < rows.size() else []

# What the player may walk to next: the first row when the biome hasn't started,
# otherwise the current node's children.
func available_next() -> Array:
	if current_id == "":
		return rows[0].duplicate()
	var cur: Dictionary = node_by_id(current_id)
	if cur.is_empty():
		return []
	var out: Array = []
	for id in cur["children"]:
		var n: Dictionary = node_by_id(String(id))
		if not n.is_empty():
			out.append(n)
	return out

func can_enter(id: String) -> bool:
	for n in available_next():
		if String(n["id"]) == id:
			return true
	return false

# Step onto a node. Returns it (empty dict if the move isn't legal from here —
# the screen should never offer an illegal one, but a save restored mid-biome
# shouldn't be able to corrupt the walk either).
func advance_to(id: String) -> Dictionary:
	if not can_enter(id):
		return {}
	if current_id != "":
		cleared[current_id] = true
	current_id = id
	return node_by_id(id)

func current_node() -> Dictionary:
	return node_by_id(current_id) if current_id != "" else {}

# How many of the biome's ten fixed stages are behind you. Utility choices carry
# slot_wave even though they do not start combat, so row position and scaler
# position can never drift apart.
func waves_cleared() -> int:
	var cur: Dictionary = current_node()
	return int(cur.get("slot_wave", cur.get("wave", 0))) if not cur.is_empty() else 0

func is_finished() -> bool:
	var cur: Dictionary = current_node()
	return not cur.is_empty() and int(cur["type"]) == NodeType.BOSS and cleared.has(current_id)

# Does stepping onto this node start a fight (and therefore advance the wave
# counter)? The single question every caller in main_game needs to ask.
static func is_battle_node(node: Dictionary) -> bool:
	var t: int = int(node.get("type", NodeType.EVENT))
	return t == NodeType.BATTLE or t == NodeType.ELITE or t == NodeType.BOSS

# Absolute round number for a wave inside this biome (wave 0 = not a battle).
func absolute_round(wave: int) -> int:
	return 0 if wave <= 0 else biome * WAVES_PER_BIOME + wave

static func type_name(type: int) -> String:
	match type:
		NodeType.RELIC:    return "Relic"
		NodeType.BATTLE:   return "Battle"
		NodeType.ELITE:    return "Elite"
		NodeType.BOSS:     return "Boss"
		NodeType.EVENT:    return "Event"
		NodeType.MERCHANT: return "Merchant"
		NodeType.CAMP:     return "Camp"
	return "?"

# ── Serialization (the map has to survive a save/quit mid-biome) ──────────────
func to_dict() -> Dictionary:
	# A reward holds an EquipmentItem, which var_to_str can't round-trip. Rather
	# than drop the reward and re-roll it (which would let a node promise an Epic
	# on the map and pay a Common after a save/quit — the map's whole appeal is
	# that what you see IS what you get), each one is reduced to a STUB: type,
	# gold amount, perk dict, item rarity. from_dict rebuilds an equivalent
	# reward from that, so the promise survives even though the exact item
	# instance doesn't.
	var plain: Array = []
	for row in rows:
		var r: Array = []
		for n in row:
			var c: Dictionary = n.duplicate(true)
			c.erase("reward")
			if n.has("reward") and not n["reward"].is_empty():
				c["reward_stub"] = _reward_stub(n["reward"])
			r.append(c)
		plain.append(r)
	return {
		"biome": biome, "seed": generation_seed, "rows": plain,
		"current": current_id, "cleared": cleared.duplicate(),
	}

static func from_dict(d: Dictionary) -> RunMap:
	var map := RunMap.new()
	map.biome = int(d.get("biome", 0))
	map.generation_seed = int(d.get("seed", 0))
	map.rows = d.get("rows", [])
	map.current_id = String(d.get("current", ""))
	map.cleared = d.get("cleared", {})
	for row in map.rows:
		for n in row:
			if n.has("reward_stub"):
				n["reward"] = _reward_from_stub(n["reward_stub"], int(n.get("round", 1)))
				n.erase("reward_stub")
			elif int(n.get("wave", 0)) > 0 and not n.has("reward"):
				# Pre-stub save, or a node that never had one: roll fresh.
				n["reward"] = RoundReward.roll(int(n.get("difficulty", 0)),
						int(n.get("round", 1)))
	return map

static func _reward_stub(reward: Dictionary) -> Dictionary:
	var stub: Dictionary = {"type": int(reward.get("type", RoundReward.Type.NOTHING))}
	# VD-19: a pick-1-of-3 reward promises only its kind — save the kind, the
	# tier and the round, and let the candidates be rolled when it pays out.
	if reward.get("choice", false):
		stub["choice"] = true
		stub["difficulty"] = int(reward.get("difficulty", 0))
		stub["round"] = int(reward.get("round", 1))
		return stub
	match int(stub["type"]):
		RoundReward.Type.GOLD:
			stub["gold"] = int(reward.get("gold", 0))
		RoundReward.Type.STAT_BONUS:
			stub["perk"] = reward.get("perk", {})   # plain dict, round-trips fine
		RoundReward.Type.ITEM:
			var item: EquipmentItem = reward.get("item")
			stub["rarity"] = int(item.rarity) if item else 0
	return stub

static func _reward_from_stub(stub: Dictionary, round_no: int) -> Dictionary:
	var out: Dictionary = {"type": int(stub.get("type", RoundReward.Type.NOTHING))}
	if stub.get("choice", false):
		out["choice"] = true
		out["difficulty"] = int(stub.get("difficulty", 0))
		out["round"] = int(stub.get("round", round_no))
		return out
	match int(out["type"]):
		RoundReward.Type.GOLD:
			out["gold"] = int(stub.get("gold", 0))
		RoundReward.Type.STAT_BONUS:
			out["perk"] = stub.get("perk", {})
		RoundReward.Type.ITEM:
			# generate_item treats rarity as a CEILING, so a single call can come
			# back lower than promised. Retry a few times to land the rarity the
			# map advertised, then accept whatever the last roll gave rather than
			# looping forever on an unlucky table.
			var want: int = int(stub.get("rarity", 0))
			var item: EquipmentItem = null
			for _i in range(12):
				item = ComponentEquipmentGateway.generate_item(round_no, want)   # new system when active
				if item and int(item.rarity) == want:
					break
			out["item"] = item
	return out

# VD-17: a merchant only counts if the player's lane can reach it. Every
# wave-1 node must reach the early merchant, and every elite node (wave 5) the
# late one — so whichever lane a player takes, both are still on the table.
func merchant_reach_problems() -> Array:
	var bad: Array = []
	var early: Array = []
	var late: Array = []
	for row in rows:
		for n in row:
			if int(n["type"]) != NodeType.MERCHANT:
				continue
			if int(n.get("slot_wave", 0)) <= 5:
				early.append(String(n["id"]))
			else:
				late.append(String(n["id"]))
	if early.size() != 1 or late.size() != 1:
		bad.append("%d early / %d late merchants, expected 1 / 1" % [early.size(), late.size()])
		return bad
	for n in rows[1]:
		if not _can_reach(n, early[0]):
			bad.append("%s cannot reach the early merchant %s" % [n["id"], early[0]])
	for n in rows[5]:
		if not _can_reach(n, late[0]):
			bad.append("%s cannot reach the late merchant %s" % [n["id"], late[0]])
	return bad

func _can_reach(start: Dictionary, target_id: String) -> bool:
	var stack: Array = [start]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var n: Dictionary = stack.pop_back()
		if String(n["id"]) == target_id:
			return true
		for cid in n["children"]:
			if not seen.has(cid):
				seen[cid] = true
				stack.append(node_by_id(String(cid)))
	return false

# ── Invariants (asserted by arena --mode=map) ─────────────────────────────────
# Returns a list of human-readable violations; empty means the map is sound.
func validate() -> Array:
	var bad: Array = []
	if rows.size() != ROW_PLAN.size():
		bad.append("row count %d != plan %d" % [rows.size(), ROW_PLAN.size()])
		return bad

	var waves: Array[int] = []
	for r in range(rows.size()):
		var row: Array = rows[r]
		if row.is_empty():
			bad.append("row %d is empty" % r)
			continue
		for n in row:
			if int(n["wave"]) > 0:
				if not int(n["wave"]) in waves:
					waves.append(int(n["wave"]))
			# Every node except the last row needs somewhere to go.
			if r < rows.size() - 1 and n["children"].is_empty():
				bad.append("%s is a dead end" % n["id"])
		# Row width is allowed to vary, but never below two — a one-node row is
		# a corridor pretending to be a choice.
		if row.size() < MIN_WIDTH and String(ROW_PLAN[r]["kind"]) != "relic":
			bad.append("row %d is only %d wide" % [r, row.size()])
		if row.size() > MAX_WIDTH:
			bad.append("row %d is %d wide, over the cap" % [r, row.size()])
		# A wave row must keep at least one real fight (so the wave EXISTS for
		# anyone who wants it) and must offer at least two distinct options —
		# either two intensities, or a fight and a side node.
		if String(ROW_PLAN[r]["kind"]) == "battle":
			var fights: int = 0
			var tiers_seen: Dictionary = {}
			var utilities: int = 0
			for n in row:
				if is_battle_node(n):
					fights += 1
					var tier: int = int(n["difficulty"])
					if tiers_seen.has(tier):
						bad.append("wave row %d repeats difficulty %d" % [r, tier])
					tiers_seen[tier] = true
				else:
					utilities += 1
					if int(n.get("slot_wave", 0)) != int(ROW_PLAN[r]["wave"]):
						bad.append("utility %s lost its stage number" % n["id"])
			if fights == 0:
				bad.append("wave row %d has no fight in it at all" % r)
			# VD-12: a fresh account's whole run is Normal, so every wave row
			# must offer one — a side node replaces a harder tier, never Normal.
			if not tiers_seen.has(0):
				bad.append("wave row %d offers no Normal fight" % r)
			var owed: int = utilities_for_width(row.size())
			if utilities != owed:
				bad.append("%d-wide wave row %d has %d utility nodes, expected %d"
					% [row.size(), r, utilities, owed])
			if int(ROW_PLAN[r]["wave"]) == 1:
				for n in row:
					if int(n["type"]) == NodeType.MERCHANT or int(n["type"]) == NodeType.CAMP:
						bad.append("wave 1 contains a shop or camp")

	# Every wave must still be REACHABLE somewhere on the map, even though an
	# individual path may skip some of them.
	waves.sort()
	if waves.size() != WAVES_PER_BIOME:
		bad.append("map only offers %d of the %d waves (%s)"
			% [waves.size(), WAVES_PER_BIOME, str(waves)])
	# Two merchants per biome, each reachable from where it must be (VD-17).
	bad.append_array(merchant_reach_problems())
	for r in range(rows.size() - 1):
		if not _every_parent_has_combat(rows[r], rows[r + 1]):
			bad.append("stage %d forces a utility-only exit" % r)

	# Reachability: walk forward from row 0 and make sure every node is hit.
	var reached: Dictionary = {}
	for n in rows[0]:
		reached[String(n["id"])] = true
	for r in range(rows.size() - 1):
		for n in rows[r]:
			if not reached.has(String(n["id"])):
				continue
			for cid in n["children"]:
				reached[String(cid)] = true
	for row in rows:
		for n in row:
			if not reached.has(String(n["id"])):
				bad.append("%s is unreachable" % n["id"])

	# Difficulty freedom is mandatory, even where its paths cross.
	for r in range(rows.size() - 1):
		var demands: Array = _row_demands(rows[r])
		for i in range(rows[r].size()):
			var parent: Dictionary = rows[r][i]
			for cid in _required_combat_ids(rows[r + 1], 1 if r == 0 else int(demands[i])):
				if not cid in parent["children"]:
					bad.append("%s cannot take required combat choice %s" % [parent["id"], cid])
	return bad
