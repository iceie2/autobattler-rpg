extends Node
class_name EventGenerator
# ══════════════════════════════════════════════════════════════════════════════
# EVENT SELECTION (rewritten 2026-09-19 — see RUN_MAP_PLAN.md §4)
#
# Was: twelve hard-coded _create_*() builders, one flat pool, uniform odds, no
# memory. Now: a weighted draw over EventCatalog, filtered by the run's actual
# state (gold, items, team, flags) and by what this run has already seen.
#
# Three rules that make a pool of 32 feel bigger than a pool of 12 did:
#   1. ELIGIBILITY — an event can require run state (2+ items, a full board, a
#      flag set by an earlier choice). Callback events only exist because of
#      something the player already did.
#   2. SEEN-SET — the pool drains before it repeats. Previously a 12-event pool
#      rolled uniformly for 100 rounds, so you saw everything twice over and
#      recognised every one by round 30.
#   3. UNIQUE — `unique: true` events fire at most once per run, full stop
#      (the debt collector shouldn't come twice for the same loan).
#
# Everything is static and scene-free so `arena --mode=events` can exercise the
# whole thing headlessly.
# ══════════════════════════════════════════════════════════════════════════════

# ── Entry points ──────────────────────────────────────────────────────────────
# ctx  — run state from main_game._event_context()
# seen — {def_id: true} for this run; caller owns it (it lives in the run save)
static func generate(ctx: Dictionary, seen: Dictionary = {}) -> EventBlessing:
	var def: Dictionary = pick_def(ctx, seen)
	if def.is_empty():
		return null
	return build_event(def, ctx)

# Back-compat shim for the old call site (main_game passed round + gold only).
# Anything that can't build a full context still gets a working event.
static func generate_event(round: int, gold: int = 0) -> EventBlessing:
	return generate({"round": round, "gold": gold}, {})

# ── Selection ─────────────────────────────────────────────────────────────────
static func eligible_defs(ctx: Dictionary, seen: Dictionary = {}) -> Array:
	var out: Array = []
	for def in EventCatalog.all_defs():
		if not EventCatalog.is_eligible(def, ctx):
			continue
		var id: String = String(def.get("id", ""))
		# A unique event that already fired is gone for the rest of the run,
		# even after the seen-set is exhausted and recycled below.
		if bool(def.get("unique", false)) and seen.has(id):
			continue
		out.append(def)
	return out

static func pick_def(ctx: Dictionary, seen: Dictionary = {}) -> Dictionary:
	var pool: Array = eligible_defs(ctx, seen)
	if pool.is_empty():
		return {}
	# Prefer unseen. Only when the eligible pool is fully drained do repeats come
	# back — so a long run cycles rather than hammering one favourite.
	var fresh: Array = []
	for def in pool:
		if not seen.has(String(def.get("id", ""))):
			fresh.append(def)
	if not fresh.is_empty():
		pool = fresh
	return _weighted_pick(pool)

static func _weighted_pick(pool: Array) -> Dictionary:
	var total: int = 0
	for def in pool:
		total += maxi(1, int(def.get("weight", 10)))
	if total <= 0:
		return pool[0]
	var r: int = randi() % total
	var acc: int = 0
	for def in pool:
		acc += maxi(1, int(def.get("weight", 10)))
		if r < acc:
			return def
	return pool[pool.size() - 1]

# ── Construction ──────────────────────────────────────────────────────────────
# Turn a catalog def into the EventBlessing the panel renders. Choices are built
# GRADED: the effects aren't computed here, they're computed when the player
# picks and the grade lands (see EventBlessing.EventChoice / event_grade.gd).
static func build_event(def: Dictionary, ctx: Dictionary) -> EventBlessing:
	var event := EventBlessing.new(
		String(def.get("title", "?")),
		String(def.get("desc", "")),
		int(def.get("type", EventBlessing.EventType.NEUTRAL)))
	event.def_id = String(def.get("id", ""))
	event.ctx = ctx.duplicate(true)
	for choice_def in def.get("choices", []):
		var cd: Dictionary = choice_def   # captured by the lambda below
		var resolver := func(c: Dictionary, g: String) -> Dictionary:
			return EventCatalog.resolve_choice(cd, c, g)
		event.add_graded_choice(
			String(cd.get("text", "…")),
			String(cd.get("band", EventGrade.DEFAULT_BAND)),
			resolver,
			String(cd.get("preview", "")),
			String(cd.get("kind", "")))
	return event

# Build a specific event by catalog id — used by the harness and by debug keys.
static func build_by_id(id: String, ctx: Dictionary) -> EventBlessing:
	var def: Dictionary = EventCatalog.def_by_id(id)
	if def.is_empty():
		return null
	return build_event(def, ctx)
