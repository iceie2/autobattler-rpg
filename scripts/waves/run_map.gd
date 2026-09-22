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
# A row is 2–4 choices wide. Combat difficulties never repeat within a row.
# Four-wide rows are Easy / Normal / Hard plus one utility node; narrower rows
# show a distinct subset, possibly with one combat slot replaced by utility.
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

# Rows are 2 to 4 nodes wide and the width VARIES per row (owner call,
# 2026-09-19). A grid of identical 3-wide rows read as a corridor: every row
# asked the same question, so by the third one the player was clicking, not
# choosing. A 2-wide row is a genuine fork; a 4-wide row is a spread worth
# studying; alternating them is what makes it read as a map.
const MIN_WIDTH := 2
const MAX_WIDTH := 4
const WIDTH_WEIGHTS := {2: 30, 3: 42, 4: 28}

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
# boss poorer and lower-level for it. That's the trade the player is making, and
# it's why a wave row always keeps at least one real fight (so the wave EXISTS
# for anyone who wants it) and why the elite and boss rows are fights only.
const UTILITY_CHANCE := 0.30
const MAX_UTILITY_NODES_PER_BIOME := 4

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
# Budget for optional utility replacements on narrower rows. Four-wide rows
# always receive utility even after this budget is spent.
var _utility_budget: int = MAX_UTILITY_NODES_PER_BIOME

# ── Generation ────────────────────────────────────────────────────────────────
# roll_rewards=false skips the RoundReward/EquipmentManager rolls, so the
# harness can generate thousands of maps to check structural invariants without
# minting thousands of throwaway items.
static func generate(biome_index: int, rng_seed: int = 0, roll_rewards: bool = true) -> RunMap:
	var map := RunMap.new()
	map.biome = maxi(0, biome_index)
	map.generation_seed = rng_seed if rng_seed != 0 else randi()
	map._rng.seed = map.generation_seed
	map._build(roll_rewards)
	return map

func _build(roll_rewards: bool) -> void:
	rows.clear()
	cleared.clear()
	current_id = ""
	_utility_budget = MAX_UTILITY_NODES_PER_BIOME
	# Exactly one merchant, late enough that the player has gold and early enough
	# to matter before the boss. Its stage is guaranteed to contain utility even
	# when that row rolls only two choices.
	var merchant_wave: int = _rng.randi_range(6, 9)

	for r in range(ROW_PLAN.size()):
		var plan: Dictionary = ROW_PLAN[r]
		match String(plan["kind"]):
			"relic":
				rows.append([_make_node(r, 1, NodeType.RELIC, 0, 0, roll_rewards)])
			"battle":
				var wave: int = int(plan["wave"])
				rows.append(_build_battle_row(r, wave, roll_rewards, wave == merchant_wave))
			"elite":
				rows.append(_build_tiered_row(r, int(plan["wave"]), NodeType.ELITE, roll_rewards))
			"boss":
				rows.append(_build_tiered_row(r, int(plan["wave"]), NodeType.BOSS, roll_rewards))
	_assign_layout()
	_wire_edges()
	_grant_relief_edges()

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

# A stage row: distinct combat tiers, with at most one utility replacement.
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
	var utility_type: int = -1
	if force_merchant:
		utility_type = NodeType.MERCHANT
	elif width == 4 or (_utility_budget > 0 and _rng.randf() < UTILITY_CHANCE):
		utility_type = _pick_utility_type(wave)
	if utility_type >= 0:
		_utility_budget = maxi(0, _utility_budget - 1)
	var fight_count: int = width - (1 if utility_type >= 0 else 0)
	var tiers: Array = _distinct_tiers(fight_count)
	# Battles stay in ascending difficulty by COLUMN INDEX — col 0 is the mildest.
	# Which direction that points on screen is the map screen's business (it
	# currently draws col 0 as the topmost lane); nothing here should care. The
	# utility slot moves between runs, replacing one conceptual lane rather than
	# changing the order.
	var utility_slot: int = _rng.randi_range(0, width - 1) if utility_type >= 0 else -1
	var out: Array = []
	var tier_i: int = 0
	for c in range(width):
		if c == utility_slot:
			var node := _make_node(r, c, utility_type, 0, 0, roll_rewards)
			node["slot_wave"] = wave
			node["round"] = absolute_round(wave)
			out.append(node)
		else:
			out.append(_make_node(r, c, NodeType.BATTLE, int(tiers[tier_i]), wave, roll_rewards))
			tier_i += 1
	return out

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

func _distinct_tiers(count: int) -> Array:
	if count >= 3:
		return [0, 1, 2]
	if count == 2:
		var pairs: Array = [[0, 1], [1, 2], [0, 2]]
		return pairs[_rng.randi() % pairs.size()]
	return [_rng.randi_range(0, 2)]

# Pick an ordinary utility. The one merchant is assigned separately so random
# utility rolls can never create duplicates.
func _pick_utility_type(wave: int) -> int:
	# Wave 1 may surprise the player with an event, but never asks them to shop
	# or rest before they have resources worth managing.
	if INCLUDE_CAMP and wave >= 3 and _rng.randf() < 0.30:
		return NodeType.CAMP
	return NodeType.EVENT

# The elite and the boss are FORCED — every path meets them (owner's call), one
# node per intensity. They are reached by the same proportional slices as every
# other row, NOT by a fan from everything to everything: the lane you are in
# does narrow which elite tiers you can reach, and that is the point — drifting
# toward the easy lane before the wall is a decision you make three rows early.
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
# StS rules: no two edges may cross, and every node must have at least one
# parent (an unreachable node is a lie drawn on the map).
#
# HOW, AND WHY NOT THE OBVIOUS WAY: the first version picked random children
# then repaired the result — adopt orphans, then delete crossing edges. The
# harness (--mode=map) failed it immediately on two counts: deleting a crossing
# edge can strip a child's LAST parent, re-orphaning it after the adoption pass
# had already run, and the repair order made that unfixable without looping.
#
# This version can't produce either fault, because it assigns MONOTONE ranges:
# parents are walked left to right and each takes a contiguous block of
# children that never starts before the previous parent's block did. Monotone
# ranges cannot cross — that's the whole trick — the blocks are contiguous from
# the first child to the last, so nothing is orphaned, and every parent is
# handed at least one child so nothing dead-ends. No repair pass at all.
func _wire_edges() -> void:
	for r in range(rows.size() - 1):
		var parents: Array = rows[r]
		var children: Array = rows[r + 1]
		var m: int = parents.size()
		var n: int = children.size()
		for i in range(m):
			parents[i]["children"] = []

		# A monotone walk through the parent×child grid is a complete wiring:
		# every visited cell is an edge, every parent and child is visited, and
		# indices never move backwards so edges cannot cross. Random step choices
		# create funnels, lane holds, and diagonal shifts instead of repeating one
		# proportional fan on every map.
		var pi := 0
		var ci := 0
		parents[pi]["children"].append(String(children[ci]["id"]))
		while pi < m - 1 or ci < n - 1:
			var can_parent: bool = pi < m - 1
			var can_child: bool = ci < n - 1
			var candidates: Array[Vector2i] = []
			if can_parent:
				candidates.append(Vector2i(1, 0))
			if can_child and (m == 1 or parents[pi]["children"].size() < 2):
				candidates.append(Vector2i(0, 1))
			if can_parent and can_child:
				candidates.append(Vector2i(1, 1))
			var moves: Array[Vector2i] = []
			for candidate in candidates:
				if m == 1:
					moves.append(candidate)
					continue
				var next_pi: int = pi + candidate.x
				var next_ci: int = ci + candidate.y
				var next_degree: int = 1 if candidate.x > 0 \
					else parents[pi]["children"].size() + candidate.y
				# Do not strand too many child lanes behind the final parents.
				# Every parent may fan to at most two children, so reserve enough
				# capacity before accepting a tempting early lane change.
				var remaining_capacity: int = (2 - next_degree) \
					+ 2 * (m - 1 - next_pi)
				if n - 1 - next_ci <= remaining_capacity:
					moves.append(candidate)
			if moves.is_empty():
				# Defensive fallback; the feasibility rule above should always leave
				# at least one monotone step for widths 1–4.
				moves = candidates
			var move: Vector2i = moves[_rng.randi() % moves.size()]
			pi += move.x
			ci += move.y
			var cid := String(children[ci]["id"])
			if not cid in parents[pi]["children"]:
				parents[pi]["children"].append(cid)

# ── THE MERCY EDGE: the hard lane is a decision, not a one-way door ───────────
# The monotone walk above produces a LEGAL graph, and a legal graph can still
# hand a node exactly one child that is a HARDER fight than the node itself.
# That is the failure the owner hit (2026-09-21): drift into the brutal lane on
# wave 2, discover on wave 4 that the team can't carry it, and there is no move
# left on the board — the run is decided several rows before it ends.
#
# So after wiring, every node that CAN be given a way out is given one. An "out"
# is any child that is not a harder fight than where the player is standing:
# an equal tier, an easier tier, or a side node, which is no fight at all.
# Choosing hard still costs you — you get the Brutal reward table and the easy
# lane's rewards are gone — but it never removes the steering wheel.
#
# The no-crossing rule still wins every argument. An out is only added when the
# geometry allows it, and when it doesn't, the node keeps its hard-only children
# and the map is simply pointed there. `validate()` re-derives this on the
# finished graph, so the harness catches it if the two ever disagree.
func _grant_relief_edges() -> void:
	for r in range(rows.size() - 1):
		# Each fix strictly moves one parent's block leftward, so the pass can
		# only run as many times as there are lanes to give away; the guard is
		# belt-and-braces against a future edit breaking that.
		var guard: int = 0
		while guard < 32:
			guard += 1
			var plan: Array = _relief_fixes(r)
			if plan.is_empty():
				break
			_apply_relief_fix(r, plan[0])

# Every parent in row r that has no out AND could legally be handed one.
# Shared by the repair pass and by validate() so they can never drift apart.
func _relief_fixes(r: int) -> Array:
	var parents: Array = rows[r]
	var children: Array = rows[r + 1]
	var demands: Array = _row_demands(parents)
	var kid_index: Dictionary = {}
	for c in range(children.size()):
		kid_index[String(children[c]["id"])] = c

	var fixes: Array = []
	for i in range(parents.size()):
		var block: Array = _child_cols(parents[i], kid_index)
		if block.is_empty():
			continue
		var demand: int = int(demands[i])
		var has_out: bool = false
		for ci in block:
			if _is_relief(children[ci], demand):
				has_out = true
				break
		if has_out:
			continue
		# Everything inside the block is harder, so the nearest out is left of
		# it. Take the CLOSEST one: it adds the fewest lines to the screen.
		var target: int = -1
		for c in range(int(block[0]) - 1, -1, -1):
			if _is_relief(children[c], demand):
				target = c
				break
		if target < 0:
			continue                      # no easier node exists on that row at all
		if i > 0:
			# Reaching left means the neighbour releases the lanes above `target`.
			# It may not release its own first child — a parent with no children
			# is a dead end, which is the one thing worse than a hard-only fork.
			var left: Array = _child_cols(parents[i - 1], kid_index)
			if left.is_empty() or int(left[0]) > target:
				continue
		fixes.append({"parent": i, "target": target})
	return fixes

# Hand parent `fix.parent` every lane from `fix.target` up to the hardest child
# it already had, and pull the neighbour to its left back to `target`.
#
# Nothing is orphaned: every child the neighbour gives up sits inside the block
# the parent just took. Nothing crosses: blocks stay contiguous and stay in
# column order. And the neighbour keeps its OWN out, because parents are ordered
# easy-to-hard across a row, so anything that was an out for the neighbour is
# also an out for this parent — and would therefore have been picked as
# `target` or better.
func _apply_relief_fix(r: int, fix: Dictionary) -> void:
	var parents: Array = rows[r]
	var children: Array = rows[r + 1]
	var kid_index: Dictionary = {}
	for c in range(children.size()):
		kid_index[String(children[c]["id"])] = c
	var i: int = int(fix["parent"])
	var target: int = int(fix["target"])
	var block: Array = _child_cols(parents[i], kid_index)
	if i > 0:
		var left: Array = _child_cols(parents[i - 1], kid_index)
		_set_child_block(parents[i - 1], children, int(left[0]),
				mini(int(left[left.size() - 1]), target))
	_set_child_block(parents[i], children, target, int(block[block.size() - 1]))

# Which columns of the next row a node currently points at, in order.
func _child_cols(parent: Dictionary, kid_index: Dictionary) -> Array:
	var cols: Array = []
	for cid in parent["children"]:
		if kid_index.has(String(cid)):
			cols.append(int(kid_index[String(cid)]))
	cols.sort()
	return cols

func _set_child_block(parent: Dictionary, children: Array, lo: int, hi: int) -> void:
	var ids: Array = []
	for c in range(lo, hi + 1):
		ids.append(String(children[c]["id"]))
	parent["children"] = ids

# How much difficulty a player standing on each node of a row has already taken
# on. A fight reports its own tier. A side node reports the lane it sits in —
# the tier of the fight to its left — because stepping onto an event doesn't
# move you out of the brutal lane, it just doesn't fight you there. Columns run
# easy to hard, so this is non-decreasing across a row, which is what makes the
# neighbour-keeps-its-own-out argument above hold.
static func _row_demands(row: Array) -> Array:
	var out: Array = []
	var last: int = 0
	for n in row:
		if is_battle_node(n):
			last = int(n["difficulty"])
		out.append(last)
	return out

# Is this child a way out for someone carrying `demand` worth of difficulty?
static func _is_relief(child: Dictionary, demand: int) -> bool:
	return not is_battle_node(child) or int(child["difficulty"]) <= demand

# How many nodes STILL have nothing but harder fights ahead of them after the
# relief pass — the ones where the geometry genuinely had no answer. validate()
# proves none of these were fixable; this reports how pointed the map is anyway,
# so the number can be watched in the harness instead of guessed at.
func hard_only_nodes() -> int:
	var count: int = 0
	for r in range(rows.size() - 1):
		var demands: Array = _row_demands(rows[r])
		var kid_index: Dictionary = {}
		for c in range(rows[r + 1].size()):
			kid_index[String(rows[r + 1][c]["id"])] = c
		for i in range(rows[r].size()):
			var stranded: bool = true
			for ci in _child_cols(rows[r][i], kid_index):
				if _is_relief(rows[r + 1][ci], int(demands[i])):
					stranded = false
					break
			if stranded:
				count += 1
	return count

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
				item = EquipmentManager.generate_item(round_no, want)
				if item and int(item.rarity) == want:
					break
			out["item"] = item
	return out

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
			if row.size() == 4 and utilities != 1:
				bad.append("four-wide wave row %d has %d utility nodes, expected 1" % [r, utilities])
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
	# Exactly one merchant per biome.
	var merchants: int = 0
	for row in rows:
		for n in row:
			if int(n["type"]) == NodeType.MERCHANT:
				merchants += 1
	if merchants != 1:
		bad.append("%d merchants in one biome, expected exactly 1" % merchants)

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

	# No crossing edges, ANYWHERE. The elite and boss rows used to be exempt
	# because every node above them fanned out to all three intensities; they
	# now take proportional slices like every other row (owner call — a screen
	# full of crossed lines was the single most off-putting thing about the
	# map), so the invariant applies to the whole graph with no exceptions.
	for r in range(rows.size() - 1):
		var col_of: Dictionary = {}
		for c in rows[r + 1]:
			col_of[String(c["id"])] = int(c["col"])
		for i in range(rows[r].size()):
			for j in range(i + 1, rows[r].size()):
				var a: Dictionary = rows[r][i]
				var b: Dictionary = rows[r][j]
				if int(a["col"]) >= int(b["col"]):
					continue
				for ea in a["children"]:
					for eb in b["children"]:
						if int(col_of[String(ea)]) > int(col_of[String(eb)]):
							bad.append("edges cross between rows %d and %d (%s→%s vs %s→%s)"
								% [r, r + 1, a["id"], ea, b["id"], eb])

	# THE MERCY EDGE (see _grant_relief_edges). A node whose every child is a
	# harder fight is a one-way door into the brutal lane; it is allowed only
	# when no-crossing geometry leaves no alternative, never by accident. This
	# re-derives the repair on the FINISHED graph, so a map that still has a fix
	# available is a map the pass failed to converge on.
	for r in range(rows.size() - 1):
		for fix in _relief_fixes(r):
			var stranded: Dictionary = rows[r][int(fix["parent"])]
			var reachable: Dictionary = rows[r + 1][int(fix["target"])]
			bad.append("%s has only harder children though %s was reachable"
				% [stranded["id"], reachable["id"]])
	return bad
