class_name RunRecap
extends RefCounted
# ══════════════════════════════════════════════════════════════════════════════
# RUN RECAP RECORD (2026-10-07) - the whole run, one immutable entry per fight.
#
# Written DURING the run by main_game from the two frozen per-fight snapshots
# the combat manager takes at the final whistle (BattleRecorder.snapshot() and
# RecapFightTap.snapshot()). Never rebuilt from log text, current hero stats or a
# replay. The terminal recap screen and every historical per-fight overview read
# only this record.
#
# ── WHAT A FIGHT ENTRY HOLDS (`fights`, append-only; entries are never edited)
#   key       encounter identity: "<map node id>@<round>", or "r<round>" without
#             the run map. A resumed save that replays a fight REPLACES the entry
#             with the same key (the run continued from the replay), so a fight
#             is never counted twice.
#   token     the battle's identity (RecapFightTap.token()). A second finalise of
#             the same battle is refused - exactly once per fight.
#   rows      [[uid, damage, healing, protection], ...] per hero who fought:
#               damage      BattleRecorder `dealt_hp` - HP removed from enemies,
#                           overkill and enemy-shield soak excluded; summons
#                           credited to their owner.
#               healing     heal_out + heal_self - effective HP restored on allies
#                           AND itself (regen, lifesteal, self-heals), overheal
#                           excluded; summons credited to their owner.
#               protection  protect_out + protect_self - damage absorbed by shields
#                           this hero supplied, credited when absorbed (see
#                           RecapFightTap); unused capacity excluded.
#   fallen / revived  uids down at the end / down and back up during this fight
#   roster    every hero on the run's roster at this fight (field, bench, downed)
#   defeats   [[enemy type key, count, of which summoned], ...]
#   report    the frozen per-fight report in compact form; report() rebuilds the
#             exact dictionary shape the existing per-fight overview renders.
#
# Cumulative totals are PREFIX SUMS over these immutable entries (prefix_totals),
# computed once - nothing is accumulated while the recap animates.
#
# ── IDENTITY ─────────────────────────────────────────────────────────────────
# Heroes carry a run-scoped uid in meta "recap_uid" (saved with the hero), so a
# hero keeps its identity across death, revival, bench, save/resume, and after it
# leaves the roster. Enemies are identified by TYPE (sprite folder), not
# instance. Display identity (name, class, element) lives in `heroes`.
#
# ── BOUNDS (measured worst case in run_recap_smoke) ───────────────────────────
# A run is at most Balance.VICTORY_ROUND (100) fights and 10 biome maps of 11
# nodes; 20 heroes field at once. Limits below hold any legal run with room to
# spare. Anything beyond a limit is POOLED with exact totals and DISCLOSED in
# `limits_hit` - never dropped silently:
#   MAX_FIGHTS / MAX_ROUTE   refuse further entries and say so
#   MAX_HEROES               extra heroes pool into one "Other heroes" row
#   MAX_ENEMY_TYPES          extra types pool into "Other enemies"
#   stored report markers    every death/revival kept up to MAX_STORED_DEATHS;
#                            the first MAX_STORED_ULTS ultimates; the largest
#                            MAX_STORED_HEALS big heals - reductions are listed
#                            in the report's notes, and per-hero counts (deaths,
#                            revivals, ultimates) stay exact.
#
# ── PERSISTENCE ──────────────────────────────────────────────────────────────
# In-progress: inside run_save.json (RunSave), key "run_recap", written by every
# save_run - so the record always matches the run state it is saved with, and a
# resume can never hold a fight the run itself never reached. Battle state is
# not saved by this game (resume restarts the round's prep), so an unfinished
# fight has no recorder state to keep: it is recorded when it is fought.
# Terminal: user://last_run_recap.json, written atomically (tmp + rename, the
# Progression.save_data pattern) once the run result is final. Kept until the
# next run finishes and replaces it. No archive.
#
# Older saves without a recap get a record that starts where the resume starts:
# `history_before_unavailable` + `coverage_from_round` -> "Recorded from Wave X".
# Unknown waves are UNAVAILABLE, never zero.
# ══════════════════════════════════════════════════════════════════════════════

const VERSION := 1
const TERMINAL_PATH := "user://last_run_recap.json"

const MAX_FIGHTS := 128
const MAX_ROUTE := 256
const MAX_HEROES := 96
const MAX_ENEMY_TYPES := 192
const MAX_REPORT_HEROES := 32
const MAX_STORED_DEATHS := 96         # deaths + revivals
const MAX_STORED_ULTS := 16
const MAX_STORED_HEALS := 8
const MAX_STORED_SURVIVORS := 40

const OTHER_UID := -1                 # pooled heroes beyond MAX_HEROES
const OTHER_ENEMY := "_other"

# Metric indices inside a fight row / prefix vector.
const M_DAMAGE := 0
const M_HEALING := 1
const M_PROTECTION := 2

var run_id: String = ""
var coverage_from_round: int = 1
var history_before_unavailable: bool = false
var route: Array = []                 # see note_node
var fights: Array = []
var heroes: Array = []                # [{uid, name, cls, element, first_round, last_round, first_fight}]
var enemy_types: Dictionary = {}      # key -> {name, portrait, boss, elite}
var next_uid: int = 1
var last_token: String = ""
var limits_hit: Array = []            # human-readable disclosures
var outcome: String = ""              # "" while running, "defeat" / "victory" once final
var final_round: int = 0
var run_kills_counter: int = -1       # main_game's run-kill count at the end (cross-check)
var crystals: int = 0
var ended_at: String = ""

var _hero_index: Dictionary = {}      # uid -> index into heroes (rebuilt on load)

# ── Construction ──────────────────────────────────────────────────────────────

static func create(p_run_id: String, from_round: int = 1) -> RunRecap:
	var r := RunRecap.new()
	r.run_id = p_run_id
	r.coverage_from_round = maxi(1, from_round)
	return r

# A run resumed from a save written before the recorder existed. Everything up to
# `from_round` happened, but was not recorded.
static func from_legacy(p_run_id: String, from_round: int) -> RunRecap:
	var r := create(p_run_id, from_round)
	r.history_before_unavailable = from_round > 1
	return r

func is_final() -> bool:
	return outcome != ""

func is_partial() -> bool:
	return history_before_unavailable or coverage_from_round > 1

# ── Heroes ────────────────────────────────────────────────────────────────────

# The hero's uid, assigning one (and stamping meta) on first sight.
func ensure_uid(u) -> int:
	if not (is_instance_valid(u) and u is UnitBase):
		return 0
	var uid: int = int(u.get_meta("recap_uid", 0))
	if uid == 0:
		if _hero_count_real() >= MAX_HEROES:
			uid = OTHER_UID
			_note_limit("More than %d heroes joined this run; the extras share one \"Other heroes\" row with exact totals." % MAX_HEROES)
		else:
			uid = next_uid
			next_uid += 1
		u.set_meta("recap_uid", uid)
	elif uid > 0 and uid >= next_uid:
		next_uid = uid + 1                # a restored hero from this run's save
	var hr := _touch_hero(uid, String(u.unit_name), int(u.unit_class), int(u.current_element))
	# Ability names, so the damage breakdown can say "Skill: Rapid Fire".
	if uid != OTHER_UID:
		hr["skill"] = String(u.skill_name)
		hr["ult"] = String(u.ultimate_name)
		hr["passive"] = String(u.passive_name)
	return uid

func _hero_count_real() -> int:
	var n := 0
	for h in heroes:
		if int(h["uid"]) > 0:
			n += 1
	return n

func _touch_hero(uid: int, name: String, cls: int, element: int) -> Dictionary:
	_ensure_index()
	if _hero_index.has(uid):
		var h: Dictionary = heroes[_hero_index[uid]]
		if uid != OTHER_UID:
			h["name"] = name
			h["cls"] = cls
			h["element"] = element
		return h
	var rec := {"uid": uid, "name": "Other heroes" if uid == OTHER_UID else name,
		"cls": -1 if uid == OTHER_UID else cls, "element": element,
		"first_round": 0, "last_round": 0, "first_fight": 0}
	heroes.append(rec)
	_hero_index[uid] = heroes.size() - 1
	return rec

func hero(uid: int) -> Dictionary:
	_ensure_index()
	return heroes[_hero_index[uid]] if _hero_index.has(uid) else {}

func _ensure_index() -> void:
	if _hero_index.size() == heroes.size():
		return
	_hero_index.clear()
	for i in range(heroes.size()):
		_hero_index[int(heroes[i]["uid"])] = i

func _note_limit(text: String) -> void:
	if not limits_hit.has(text):
		limits_hit.append(text)

# ── Route ─────────────────────────────────────────────────────────────────────

static func encounter_key(node_id: String, round_no: int) -> String:
	return "%s@%d" % [node_id, round_no] if node_id != "" else "r%d" % round_no

# A visited route node, in visit order. ctx: {node_id, round, biome, type, tier,
# icon}. Fights are noted on entry too, so the route keeps its order even if the
# app closes mid-fight; finalise_fight links to the entry by key.
func note_node(ctx: Dictionary, is_fight: bool) -> void:
	if is_final():
		return
	var key := encounter_key(String(ctx.get("node_id", "")), int(ctx.get("round", 0)))
	if not is_fight:
		key = "node:" + String(ctx.get("node_id", "")) + "@%d" % int(ctx.get("round", 0))
	for e in route:
		if String(e["key"]) == key:
			return
	if route.size() >= MAX_ROUTE:
		_note_limit("The route passed %d stops; later stops were not drawn (fights are still recorded)." % MAX_ROUTE)
		return
	route.append({
		"kind": "fight" if is_fight else "node",
		"key": key,
		"node_id": String(ctx.get("node_id", "")),
		"round": int(ctx.get("round", 0)),
		"biome": int(ctx.get("biome", 0)),
		"type": int(ctx.get("type", RunMap.NodeType.BATTLE)),
		"tier": int(ctx.get("tier", 0)),
		"icon": String(ctx.get("icon", "")),
	})

func route_entry(key: String) -> Dictionary:
	for e in route:
		if String(e["key"]) == key:
			return e
	return {}

# ── Fights ────────────────────────────────────────────────────────────────────

# Freeze one finished fight. Returns true when recorded.
#   ctx          {node_id, round, biome, type, tier, icon, won}
#   report       BattleRecorder.snapshot() (may be {} - then it is UNAVAILABLE)
#   tap          RecapFightTap.snapshot()
#   uid_by_id    hero instance id -> uid for every hero main_game still holds
#   roster_uids  uids of the whole roster at this fight
func finalise_fight(ctx: Dictionary, report: Dictionary, tap: Dictionary,
		uid_by_id: Dictionary, roster_uids: Array, bench_uids: Array = []) -> bool:
	if is_final():
		return false
	var token := String(tap.get("token", ""))
	if token != "" and token == last_token:
		return false                          # this battle is already recorded
	var round_no: int = int(ctx.get("round", 0))
	var key := encounter_key(String(ctx.get("node_id", "")), round_no)
	var replace_at := -1
	for i in range(fights.size()):
		if String(fights[i]["key"]) == key:
			replace_at = i
	if replace_at < 0 and fights.size() >= MAX_FIGHTS:
		_note_limit("More than %d fights; later fights were not recorded." % MAX_FIGHTS)
		return false
	note_node(ctx, true)

	var tap_heroes: Dictionary = tap.get("heroes", {})
	var rows: Array = []
	var fallen: Array = []
	var revived: Array = []
	var available: bool = not report.is_empty() and report.has("heroes")
	var row_of: Dictionary = {}               # uid -> row (pooled OTHER heroes merge)
	if available:
		for h in report["heroes"]:
			var uid := _uid_for(int(h["id"]), h, uid_by_id, tap_heroes)
			var p: Dictionary = tap_heroes.get(int(h["id"]), {})
			var dmg: int = int(h.get("dealt_hp", 0))
			var heal: int = int(h.get("heal_out", 0)) + int(h.get("heal_self", 0))
			var prot: int = int(p.get("protect_out", 0)) + int(p.get("protect_self", 0))
			if row_of.has(uid):
				var r: Array = row_of[uid]
				r[1] += dmg; r[2] += heal; r[3] += prot
			else:
				var r2: Array = [uid, dmg, heal, prot]
				row_of[uid] = r2
				rows.append(r2)
			var died: bool = int(h.get("deaths", 0)) > 0
			if died and not bool(h.get("survived", false)):
				fallen.append(uid)
			elif died:
				revived.append(uid)
			var hr := hero(uid)
			if not hr.is_empty() and int(hr["first_fight"]) == 0:
				hr["first_fight"] = round_no
	for uid in roster_uids:
		var hr2 := hero(int(uid))
		if hr2.is_empty():
			continue
		if int(hr2["first_round"]) == 0:
			hr2["first_round"] = round_no
		hr2["last_round"] = maxi(int(hr2["last_round"]), round_no)

	var defeats: Array = []
	for d in tap.get("defeats", []):
		var k := String(d["key"])
		if not enemy_types.has(k):
			if enemy_types.size() >= MAX_ENEMY_TYPES:
				k = OTHER_ENEMY
				_note_limit("More than %d enemy types; the extras are pooled as \"Other enemies\"." % MAX_ENEMY_TYPES)
			if not enemy_types.has(k):
				enemy_types[k] = {"name": "Other enemies" if k == OTHER_ENEMY else String(d.get("name", k)),
					"portrait": "" if k == OTHER_ENEMY else String(d.get("portrait", "")),
					"boss": bool(d.get("boss", false)), "elite": bool(d.get("elite", false))}
		var merged := false
		for row in defeats:
			if row[0] == k:
				row[1] += int(d["n"]); row[2] += int(d.get("summoned", 0))
				merged = true
		if not merged:
			defeats.append([k, int(d["n"]), int(d.get("summoned", 0))])

	# The order enemies fell, as indices into this fight's `defeats` rows.
	var kill_seq: Array = []
	for k in tap.get("order", []):
		var key2 := String(k)
		if not enemy_types.has(key2):
			key2 = OTHER_ENEMY
		for di in range(defeats.size()):
			if defeats[di][0] == key2:
				kill_seq.append(di)
				break
	var compact: Dictionary = compact_report(report, uid_by_id, tap_heroes) if available else {}
	var entry := {
		"key": key,
		"token": token,
		"round": round_no,
		"biome": int(ctx.get("biome", 0)),
		"type": int(ctx.get("type", RunMap.NodeType.BATTLE)),
		"tier": int(ctx.get("tier", 0)),
		"node_id": String(ctx.get("node_id", "")),
		"won": bool(ctx.get("won", report.get("won", false))),
		"duration": snappedf(float(report.get("duration", 0.0)), 0.01) if available else -1.0,
		"available": available,
		"rows": rows,
		"fallen": fallen,
		"revived": revived,
		"roster": roster_uids.duplicate(),
		"defeats": defeats,
		"defeat_total": int(tap.get("defeat_total", 0)),
		"summoned_total": int(tap.get("summoned_total", 0)),
		"protect_unattributed": int(tap.get("protect_unattributed", 0)),
		"headliners": (tap.get("headliners", []) as Array).duplicate(true),
		"kill_seq": kill_seq,
		"bench": bench_uids.duplicate(),
		"dmg_split": _split_rows(tap, uid_by_id, tap_heroes),
		"report": compact,
	}
	if replace_at >= 0:
		fights[replace_at] = entry
	else:
		fights.append(entry)
	last_token = token
	return true

# Per-hero damage breakdown rows, [uid, cell x 18] (RecapFightTap SOURCES x TYPES).
func _split_rows(tap: Dictionary, uid_by_id: Dictionary, tap_heroes: Dictionary) -> Array:
	var out: Array = []
	var by_uid: Dictionary = {}
	var src: Dictionary = tap.get("split", {})
	for iid in src.keys():
		var uid: int = int(uid_by_id.get(int(iid), 0))
		if uid == 0:
			uid = int((tap_heroes.get(int(iid), {}) as Dictionary).get("uid", 0))
		if uid == 0:
			continue
		var cells: Array = src[iid]
		if not by_uid.has(uid):
			var row: Array = [uid]
			for c in cells:
				row.append(int(c))
			by_uid[uid] = row
			out.append(row)
		else:
			var r: Array = by_uid[uid]
			for i in range(cells.size()):
				r[i + 1] = int(r[i + 1]) + int(cells[i])
	return out

# A hero's damage by source x type, summed over fights[0..upto]. Fights recorded
# before the breakdown existed are NOT guessed: their damage is reported apart
# as `unsplit` (with the waves it covers), never spread over the sources.
func damage_split(uid: int, upto: int) -> Dictionary:
	var n: int = RecapFightTap.SOURCES * RecapFightTap.TYPES
	var cells: Array = []
	cells.resize(n)
	cells.fill(0)
	var unsplit := 0
	var unsplit_rounds: Array = []
	var shields := 0
	for fi in range(mini(upto + 1, fights.size())):
		var f: Dictionary = fights[fi]
		var dealt := 0
		for r in f["rows"]:
			if int(r[0]) == uid:
				dealt += int(r[1])
		var split = f.get("dmg_split")
		if split == null:
			if dealt > 0:
				unsplit += dealt
				unsplit_rounds.append(int(f["round"]))
		else:
			for row in split:
				if int(row[0]) == uid:
					# Rows written before the Passive source was appended are
					# shorter; the sources they have sit at the same indices.
					for i in range(mini(n, (row as Array).size() - 1)):
						cells[i] = int(cells[i]) + int(row[i + 1])
		var rep: Dictionary = f.get("report", {})
		for hr in rep.get("h", []):
			if int(hr[0]) == uid:
				shields += int(hr[3])
	return {"cells": cells, "unsplit": unsplit, "unsplit_rounds": unsplit_rounds, "enemy_shields": shields}

func _uid_for(instance_id: int, h: Dictionary, uid_by_id: Dictionary, tap_heroes: Dictionary) -> int:
	var uid: int = int(uid_by_id.get(instance_id, 0))
	if uid == 0:
		uid = int(h.get("uid", 0))
	if uid == 0:
		uid = int((tap_heroes.get(instance_id, {}) as Dictionary).get("uid", 0))
	if uid == 0:
		# A hero nothing could identify (should not happen: main_game stamps every
		# roster hero before the fight). Give it its own identity, never a guess.
		uid = next_uid if _hero_count_real() < MAX_HEROES else OTHER_UID
		if uid != OTHER_UID:
			next_uid += 1
	if hero(uid).is_empty():
		_touch_hero(uid, String(h.get("name", "?")), int(h.get("cls", -1)), -1)
	return uid

func fight(key: String) -> Dictionary:
	for f in fights:
		if String(f["key"]) == key:
			return f
	return {}

func fight_index(key: String) -> int:
	for i in range(fights.size()):
		if String(fights[i]["key"]) == key:
			return i
	return -1

# ── Terminal ──────────────────────────────────────────────────────────────────

func finalise_run(p_outcome: String, p_final_round: int, kills: int, p_crystals: int) -> void:
	if is_final():
		return
	outcome = p_outcome
	final_round = p_final_round
	run_kills_counter = kills
	crystals = p_crystals
	ended_at = Time.get_datetime_string_from_system(false, true)

# ── Derived views (pure, over the immutable entries) ──────────────────────────

# prefix[i][uid] = [damage, healing, protection] summed over fights[0..i].
func prefix_totals() -> Array:
	var out: Array = []
	var running: Dictionary = {}
	for f in fights:
		for r in f["rows"]:
			var uid: int = int(r[0])
			var v: Array = running.get(uid, [0, 0, 0])
			running[uid] = [int(v[0]) + int(r[1]), int(v[1]) + int(r[2]), int(v[2]) + int(r[3])]
		var snap: Dictionary = {}
		for k in running.keys():
			snap[k] = (running[k] as Array).duplicate()
		out.append(snap)
	return out

func final_totals() -> Dictionary:
	var p := prefix_totals()
	return p[p.size() - 1] if not p.is_empty() else {}

# Heroes that fought in at least one recorded fight, in stable roster order
# (first recorded fight, then join order).
func fighting_heroes() -> Array:
	var seen: Dictionary = {}
	for f in fights:
		for r in f["rows"]:
			seen[int(r[0])] = true
	var out: Array = []
	for h in heroes:
		if seen.has(int(h["uid"])):
			out.append(h)
	out.sort_custom(func(a, b):
		var fa: int = int(a["first_fight"]) if int(a["first_fight"]) > 0 else 1 << 20
		var fb: int = int(b["first_fight"]) if int(b["first_fight"]) > 0 else 1 << 20
		if fa != fb:
			return fa < fb
		if int(a["uid"]) == OTHER_UID or int(b["uid"]) == OTHER_UID:
			return int(b["uid"]) == OTHER_UID
		return int(a["uid"]) < int(b["uid"]))
	return out

func bench_only_count() -> int:
	var fought: Dictionary = {}
	for h in fighting_heroes():
		fought[int(h["uid"])] = true
	var n := 0
	for h in heroes:
		if not fought.has(int(h["uid"])) and int(h["first_round"]) > 0:
			n += 1
	return n

# Whole-run defeat tally: [{key, name, portrait, n, summoned, boss, elite}],
# bosses first, then by count.
func defeat_tally() -> Array:
	var agg: Dictionary = {}
	for f in fights:
		for d in f["defeats"]:
			var k := String(d[0])
			if not agg.has(k):
				var t: Dictionary = enemy_types.get(k, {})
				agg[k] = {"key": k, "name": String(t.get("name", k)), "portrait": String(t.get("portrait", "")),
					"n": 0, "summoned": 0, "boss": bool(t.get("boss", false)), "elite": bool(t.get("elite", false))}
			agg[k]["n"] += int(d[1])
			agg[k]["summoned"] += int(d[2])
	var out: Array = agg.values()
	out.sort_custom(func(a, b):
		var ra: int = 0 if bool(a["boss"]) else (1 if bool(a["elite"]) else 2)
		var rb: int = 0 if bool(b["boss"]) else (1 if bool(b["elite"]) else 2)
		if ra != rb:
			return ra < rb
		if int(a["n"]) != int(b["n"]):
			return int(a["n"]) > int(b["n"])
		return String(a["key"]) < String(b["key"]))
	return out

# One fight's defeats as type keys, in the order they fell. Fights recorded before
# the order was kept (or past the per-fight cap) fill in by type, count-exact.
func kill_order(fi: int) -> Array:
	if fi < 0 or fi >= fights.size():
		return []
	var f: Dictionary = fights[fi]
	var defs: Array = f["defeats"]
	var out: Array = []
	var left: Array = []
	for d in defs:
		left.append(int(d[1]))
	for di in f.get("kill_seq", []):
		var i := int(di)
		if i >= 0 and i < defs.size() and int(left[i]) > 0:
			out.append(String(defs[i][0]))
			left[i] = int(left[i]) - 1
	for i in range(defs.size()):
		for _n in range(int(left[i])):
			out.append(String(defs[i][0]))
	return out

func defeat_total() -> int:
	var n := 0
	for f in fights:
		n += int(f.get("defeat_total", 0))
	return n

func unattributed_protection() -> int:
	var n := 0
	for f in fights:
		n += int(f.get("protect_unattributed", 0))
	return n

# Route positions that are fights with a recorded entry, in route order.
func fight_route_order() -> Array:
	var out: Array = []
	for e in route:
		if String(e["kind"]) == "fight" and fight_index(String(e["key"])) >= 0:
			out.append(String(e["key"]))
	return out

# ── Compact per-fight report ──────────────────────────────────────────────────
# Stored form of BattleRecorder.snapshot(). report_for() rebuilds the exact shape
# the per-fight overview (DefeatReportView / BattleTimeline) reads, with hero
# "id" = uid so lanes and markers still line up.

const EV_CODES := {"death": "d", "revive": "r", "ultimate": "u", "heal": "h"}
const EV_KINDS := {"d": "death", "r": "revive", "u": "ultimate", "h": "heal"}

static func compact_report(rep: Dictionary, uid_by_id: Dictionary, tap_heroes: Dictionary) -> Dictionary:
	var notes: Array = []
	var uid_of := func(iid) -> int:
		var u: int = int(uid_by_id.get(int(iid), 0))
		if u == 0:
			for h in rep.get("heroes", []):
				if int(h["id"]) == int(iid):
					u = int(h.get("uid", 0))
		if u == 0:
			u = int((tap_heroes.get(int(iid), {}) as Dictionary).get("uid", 0))
		return u
	var hs: Array = []
	var deaths_total := 0
	var revives_total := 0
	var ults_total := 0
	var list: Array = rep.get("heroes", [])
	if list.size() > MAX_REPORT_HEROES:
		notes.append("Only the first %d of %d heroes are listed." % [MAX_REPORT_HEROES, list.size()])
	for i in range(mini(list.size(), MAX_REPORT_HEROES)):
		var h: Dictionary = list[i]
		var iv: Array = []
		for pair in h.get("intervals", []):
			iv.append(snappedf(float(pair[0]), 0.01))
			iv.append(snappedf(float(pair[1]), 0.01))
		hs.append([uid_of.call(h["id"]), int(h.get("level", 0)),
			int(h.get("dealt_hp", 0)), int(h.get("dealt_shield", 0)), int(h.get("dealt_by_summons", 0)),
			int(h.get("taken_hp", 0)), int(h.get("taken_shield", 0)),
			int(h.get("heal_out", 0)), int(h.get("heal_self", 0)), int(h.get("overheal", 0)),
			int(h.get("deaths", 0)), int(h.get("revives", 0)), int(h.get("ults", 0)),
			int(h.get("hp_end", 0)), int(h.get("max_hp_end", 0)), 1 if bool(h.get("survived", false)) else 0,
			snappedf(float(h.get("alive_time", 0.0)), 0.01), iv,
			String(h.get("name", "?")), int(h.get("cls", -1))])
		deaths_total += int(h.get("deaths", 0))
		revives_total += int(h.get("revives", 0))
		ults_total += int(h.get("ults", 0))

	# Events: every death / revival first (they ARE the timeline), then ultimates
	# in time order, then the biggest heals. Reductions are written into notes.
	var dr: Array = []
	var ul: Array = []
	var he: Array = []
	for ev in rep.get("events", []):
		var kind := String(ev.get("kind", ""))
		if not EV_CODES.has(kind):
			continue
		var text := ""
		var amt := 0
		match kind:
			"death": text = String(ev.get("by", ""))
			"ultimate": text = String(ev.get("ability", ""))
			"heal":
				text = String(ev.get("target", ""))
				amt = int(ev.get("amount", 0))
		var row: Array = [snappedf(float(ev["t"]), 0.01), EV_CODES[kind], uid_of.call(ev.get("hero", 0)), text, amt]
		match kind:
			"death", "revive": dr.append(row)
			"ultimate": ul.append(row)
			"heal": he.append(row)
	var dr_seen: int = dr.size()
	if deaths_total + revives_total > dr_seen:
		notes.append("The live recorder kept %d of %d deaths/revivals (its own limit)." % [dr_seen, deaths_total + revives_total])
	if dr.size() > MAX_STORED_DEATHS:
		notes.append("Timeline markers: the first %d of %d deaths/revivals are shown." % [MAX_STORED_DEATHS, dr.size()])
		dr = dr.slice(0, MAX_STORED_DEATHS)
	if ul.size() < ults_total or ul.size() > MAX_STORED_ULTS:
		notes.append("Timeline markers: %d of %d ultimates are shown (per-hero counts are exact)." % [mini(ul.size(), MAX_STORED_ULTS), ults_total])
		ul = ul.slice(0, MAX_STORED_ULTS)
	if he.size() > MAX_STORED_HEALS or he.size() >= BattleRecorder.MAX_MAJOR_HEALS:
		he.sort_custom(func(a, b): return int(a[4]) > int(b[4]))
		notes.append("Timeline markers: only the %d largest heals are shown." % mini(he.size(), MAX_STORED_HEALS))
		he = he.slice(0, MAX_STORED_HEALS)
	var evs: Array = dr + ul + he
	evs.sort_custom(func(a, b): return float(a[0]) < float(b[0]))

	var en: Dictionary = rep.get("enemies", {})
	var surv: Array = []
	var all_surv: Array = en.get("survivors", [])
	for i in range(mini(all_surv.size(), MAX_STORED_SURVIVORS)):
		var s: Dictionary = all_surv[i]
		surv.append([String(s.get("name", "?")), String(s.get("portrait", "")), int(s.get("hp", 0)),
			int(s.get("max_hp", 0)), int(s.get("start_max_hp", s.get("max_hp", 0))), 1 if bool(s.get("summoned", false)) else 0])
	if all_surv.size() > MAX_STORED_SURVIVORS:
		notes.append("%d of %d surviving enemies are pictured; the HP totals cover all of them." % [MAX_STORED_SURVIVORS, all_surv.size()])
	var team: Dictionary = {}
	for k in (rep.get("team", {}) as Dictionary).keys():
		team[k] = int(rep["team"][k])
	return {
		"won": bool(rep.get("won", false)),
		"dur": snappedf(float(rep.get("duration", 0.0)), 0.01),
		"h": hs,
		"ev": evs,
		"en": [int(en.get("seen", 0)), int(en.get("remaining", 0)), int(en.get("hp", 0)), int(en.get("max_hp", 0)), surv],
		"team": team,
		"unattr": int(rep.get("unattributed_taken", 0)),
		"notes": notes,
	}

# The per-fight overview's report for one recorded fight, or {} when that fight
# has no stored report (it then must not open a fabricated overview).
func report_for(key: String) -> Dictionary:
	var f := fight(key)
	if f.is_empty() or not bool(f.get("available", false)):
		return {}
	return rebuild_report(f["report"], self)

static func rebuild_report(c: Dictionary, recap: RunRecap = null) -> Dictionary:
	if c.is_empty():
		return {}
	var names: Dictionary = {}
	var heroes_out: Array = []
	for row in c.get("h", []):
		var uid: int = int(row[0])
		var name: String = String(row[18]) if row.size() > 18 else "?"
		var cls: int = int(row[19]) if row.size() > 19 else -1
		if recap != null:
			var hr := recap.hero(uid)
			if not hr.is_empty():
				name = String(hr["name"]) if name == "?" else name
				cls = int(hr["cls"]) if cls < 0 else cls
		names[uid] = name
		var iv: Array = []
		var flat: Array = row[17]
		var i := 0
		while i + 1 < flat.size():
			iv.append([float(flat[i]), float(flat[i + 1])])
			i += 2
		heroes_out.append({
			"id": uid, "uid": uid, "name": name, "cls": cls,
			"level": int(row[1]),
			"dealt_hp": int(row[2]), "dealt_shield": int(row[3]), "dealt_by_summons": int(row[4]),
			"taken_hp": int(row[5]), "taken_shield": int(row[6]),
			"heal_out": int(row[7]), "heal_self": int(row[8]), "overheal": int(row[9]),
			"healed_in": 0,
			"deaths": int(row[10]), "revives": int(row[11]), "ults": int(row[12]),
			"hp_end": int(row[13]), "max_hp_end": int(row[14]), "survived": int(row[15]) == 1,
			"alive_time": float(row[16]), "intervals": iv,
			"portrait": String(VisualUnit.HERO_SPRITE_PATHS.get(cls, "")) if cls >= 0 else "",
		})
	var events: Array = []
	for e in c.get("ev", []):
		var kind: String = String(EV_KINDS.get(String(e[1]), ""))
		var uid2: int = int(e[2])
		var ev := {"t": float(e[0]), "kind": kind, "hero": uid2, "name": String(names.get(uid2, "?"))}
		match kind:
			"death": ev["by"] = String(e[3])
			"ultimate": ev["ability"] = String(e[3])
			"heal":
				ev["target"] = String(e[3])
				ev["amount"] = int(e[4])
		events.append(ev)
	var en: Array = c.get("en", [0, 0, 0, 0, []])
	var survivors: Array = []
	for s in en[4]:
		survivors.append({"name": String(s[0]), "portrait": String(s[1]), "hp": int(s[2]),
			"max_hp": int(s[3]), "start_max_hp": int(s[4]), "summoned": int(s[5]) == 1})
	var team: Dictionary = {}
	for k in (c.get("team", {}) as Dictionary).keys():
		team[k] = int(c["team"][k])
	var notes: Array = [
		"Damage and healing are effective amounts: overkill, overheal and expired shields are excluded.",
		"Shields are credited to the hero they protected, not to whoever cast them.",
	]
	notes.append_array(c.get("notes", []))
	var out := {
		"version": 1,
		"won": bool(c.get("won", false)),
		"duration": float(c.get("dur", 0.0)),
		"heroes": heroes_out,
		"events": events,
		"enemies": {"seen": int(en[0]), "remaining": int(en[1]), "hp": int(en[2]), "max_hp": int(en[3]),
			"survivors": survivors},
		"team": team,
		"unattributed_taken": int(c.get("unattr", 0)),
		"notes": notes,
		"reduced_detail": (c.get("notes", []) as Array).duplicate(),
	}
	out["takeaway"] = BattleRecorder.build_takeaway(out)
	return out

# ── Serialization ─────────────────────────────────────────────────────────────
# Plain data only (String keys, ints, floats, strings, arrays), so the same dict
# round-trips through var_to_str (run save) and JSON (terminal file). JSON turns
# every number into a float, so every reader above casts.

func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"run_id": run_id,
		"coverage_from_round": coverage_from_round,
		"history_before_unavailable": history_before_unavailable,
		"route": route.duplicate(true),
		"fights": fights.duplicate(true),
		"heroes": heroes.duplicate(true),
		"enemy_types": enemy_types.duplicate(true),
		"next_uid": next_uid,
		"last_token": last_token,
		"limits_hit": limits_hit.duplicate(),
		"outcome": outcome,
		"final_round": final_round,
		"run_kills_counter": run_kills_counter,
		"crystals": crystals,
		"ended_at": ended_at,
	}

# null for anything that is not a recap this version understands.
static func from_dict(d) -> RunRecap:
	if not (d is Dictionary) or int(d.get("version", -1)) != VERSION:
		return null
	var r := RunRecap.new()
	r.run_id = String(d.get("run_id", ""))
	r.coverage_from_round = int(d.get("coverage_from_round", 1))
	r.history_before_unavailable = bool(d.get("history_before_unavailable", false))
	r.route = _normalise_route(d.get("route", []))
	r.fights = _normalise_fights(d.get("fights", []))
	r.heroes = []
	for h in d.get("heroes", []):
		var hd := {"uid": int(h["uid"]), "name": String(h.get("name", "?")), "cls": int(h.get("cls", -1)),
			"element": int(h.get("element", 0)), "first_round": int(h.get("first_round", 0)),
			"last_round": int(h.get("last_round", 0)), "first_fight": int(h.get("first_fight", 0))}
		if h.has("skill"):
			hd["skill"] = String(h["skill"])
			hd["ult"] = String(h.get("ult", ""))
			hd["passive"] = String(h.get("passive", ""))
		r.heroes.append(hd)
	r.enemy_types = {}
	var et: Dictionary = d.get("enemy_types", {})
	for k in et.keys():
		r.enemy_types[String(k)] = {"name": String(et[k].get("name", k)), "portrait": String(et[k].get("portrait", "")),
			"boss": bool(et[k].get("boss", false)), "elite": bool(et[k].get("elite", false))}
	r.next_uid = int(d.get("next_uid", 1))
	r.last_token = String(d.get("last_token", ""))
	r.limits_hit = (d.get("limits_hit", []) as Array).duplicate()
	r.outcome = String(d.get("outcome", ""))
	r.final_round = int(d.get("final_round", 0))
	r.run_kills_counter = int(d.get("run_kills_counter", -1))
	r.crystals = int(d.get("crystals", 0))
	r.ended_at = String(d.get("ended_at", ""))
	r._hero_index.clear()
	return r

static func _normalise_route(src: Array) -> Array:
	var out: Array = []
	for e in src:
		out.append({"kind": String(e.get("kind", "fight")), "key": String(e.get("key", "")),
			"node_id": String(e.get("node_id", "")), "round": int(e.get("round", 0)),
			"biome": int(e.get("biome", 0)), "type": int(e.get("type", RunMap.NodeType.BATTLE)),
			"tier": int(e.get("tier", 0)), "icon": String(e.get("icon", ""))})
	return out

static func _int_rows(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var row: Array = []
		for v in r:
			row.append(int(v) if (v is float or v is int) else v)
		out.append(row)
	return out

static func _ints(src: Array) -> Array:
	var out: Array = []
	for v in src:
		out.append(int(v))
	return out

static func _normalise_fights(src: Array) -> Array:
	var out: Array = []
	for f in src:
		var ints: Array = []
		for u in f.get("fallen", []): ints.append(int(u))
		var rev: Array = []
		for u in f.get("revived", []): rev.append(int(u))
		var ros: Array = []
		for u in f.get("roster", []): ros.append(int(u))
		var defs: Array = []
		for d in f.get("defeats", []):
			defs.append([String(d[0]), int(d[1]), int(d[2])])
		out.append({
			"key": String(f.get("key", "")), "token": String(f.get("token", "")),
			"round": int(f.get("round", 0)), "biome": int(f.get("biome", 0)),
			"type": int(f.get("type", RunMap.NodeType.BATTLE)), "tier": int(f.get("tier", 0)),
			"node_id": String(f.get("node_id", "")), "won": bool(f.get("won", false)),
			"duration": float(f.get("duration", -1.0)), "available": bool(f.get("available", false)),
			"rows": _int_rows(f.get("rows", [])), "fallen": ints, "revived": rev, "roster": ros,
			"defeats": defs, "defeat_total": int(f.get("defeat_total", 0)),
			"summoned_total": int(f.get("summoned_total", 0)),
			"protect_unattributed": int(f.get("protect_unattributed", 0)),
			"headliners": (f.get("headliners", []) as Array).duplicate(true),
			"kill_seq": _ints(f.get("kill_seq", [])),
			"bench": _ints(f.get("bench", [])),
			# null = recorded before the breakdown existed (kept null across saves)
			"dmg_split": _int_rows(f["dmg_split"]) if f.get("dmg_split") is Array else null,
			"report": (f.get("report", {}) as Dictionary).duplicate(true),
		})
	return out

# ── Terminal file (atomic) ────────────────────────────────────────────────────

static func save_terminal(recap: RunRecap, path: String = TERMINAL_PATH) -> bool:
	if recap == null:
		return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(recap.to_dict()))
	file.flush()
	file.close()
	# Replace only once the whole file is on disk (Progression.save_data pattern):
	# a crash mid-write leaves the previous recap intact, never a truncated one.
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Could not persist the run recap: %s" % error_string(err))
		return false
	return true

static func load_terminal(path: String = TERMINAL_PATH) -> RunRecap:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return null
	return from_dict(JSON.parse_string(f.get_as_text()))

static func terminal_exists(path: String = TERMINAL_PATH) -> bool:
	return FileAccess.file_exists(path)

static func clear_terminal(path: String = TERMINAL_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
