extends Object
class_name EventCatalog
# ══════════════════════════════════════════════════════════════════════════════
# EVENT CATALOG (2026-09-19, RUN_MAP_PLAN.md §4)
#
# Replaces the 12 hand-built _create_*() functions in event_generator.gd. Every
# event is DATA: an id, an eligibility block, and a list of choices. A choice
# names a resolver `kind` plus params; resolve_choice() turns (choice, ctx,
# grade) into {effects, outcome}. Nothing here constructs UI or touches the
# scene tree, so `arena --mode=events` can walk every event × every choice ×
# every grade and assert the whole catalog is sane (see arena_main.gd).
#
# WHY DATA AND NOT CALLABLES: the first draft of this file used lambdas per
# choice. Multi-line lambdas inside dictionary literals are a parser minefield
# in GDScript, and a Callable can't be validated without calling it. A `kind`
# string can be checked against a known list, which is what makes the harness
# mode possible at all.
#
# WHY GDSCRIPT AND NOT JSON: payouts are functions of round/gold/run state
# ("3 + round * 1.5"), which JSON can only express with an expression
# mini-language. Same call as ability_formulas.gd, for the same reason.
#
# ── Adding an event ───────────────────────────────────────────────────────────
#   1. Append a def to one of the _pool_* functions below.
#   2. Use only `kind` values listed in KINDS — the harness fails on unknown ones.
#   3. Art is automatic: drop assets/events/<slug>.png (title lowercased,
#      spaces → underscores, apostrophes stripped) and the panel picks it up.
# ══════════════════════════════════════════════════════════════════════════════

# Every resolver kind. The harness asserts no choice names anything outside this.
const KINDS: Array[String] = [
	"nothing", "gold", "gold_cost", "gamble", "team_buff", "team_curse",
	"heal", "item", "perk", "hero_xp", "level_up", "team_size", "damage",
	"destroy_items", "shop_discount", "shop_sales", "debt", "flag", "combo",
	# 2026-09-19, owner rulings: scars (permanent per-hero trade) and wave
	# modifiers (events that reach into the next fight).
	"scar", "next_wave",
]

# Every effect key main_game._apply_event_effects knows how to apply. This list
# is the contract between the catalog (which produces effect dicts) and
# main_game (which consumes them); `arena --mode=events` fails on any key that
# isn't here, so a typo in a new event can't silently do nothing at runtime.
const EFFECT_VERBS: Array[String] = [
	# original verbs
	"gold", "heal_all", "restore_mana", "hero_damage", "team_dmg_mult",
	"team_def_mult", "team_spd_mult", "max_hp_mult", "max_units", "max_level",
	"gold_if_win", "gold_if_lose",
	# added with the catalog (2026-09-19)
	"gold_pct", "heal_pct", "mana_pct", "grant_item", "destroy_items",
	"hero_perk", "hero_xp", "shop_discount", "shop_sales", "debt", "set_flag",
	"hero_scar", "next_wave",
]

# Grade → item rarity for "item" payouts (EquipmentItem.Rarity: 0 COMMON …
# 4 LEGENDARY). generate_item treats this as a CEILING, so an S roll can still
# come back Epic — it just becomes possible to see a Legendary at all.
const GRADE_RARITY := {"F": 0, "D": 0, "C": 1, "B": 2, "A": 3, "S": 4}

# main_game clamps a scrap sale's grade multiplier to this window (a bad roll
# still pays something, a great one can't beat buying). Shared so the preview
# quotes the same gold main_game pays.
const SCRAP_GRADE_MIN := 0.6
const SCRAP_GRADE_MAX := 1.4

# ══════════════════════════════════════════════════════════════════════════════
# ELIGIBILITY
# ══════════════════════════════════════════════════════════════════════════════
# A def's optional "requires" block, all keys AND-ed. ctx is built by
# main_game._event_context() (round, gold, team_size, team_max, items, relics,
# flags, dominant_element).
static func is_eligible(def: Dictionary, ctx: Dictionary) -> bool:
	var req: Dictionary = def.get("requires", {})
	if int(ctx.get("round", 1)) < int(req.get("min_round", 1)):
		return false
	if req.has("max_round") and int(ctx.get("round", 1)) > int(req["max_round"]):
		return false
	if req.has("min_gold") and int(ctx.get("gold", 0)) < int(req["min_gold"]):
		return false
	if req.has("min_items") and int(ctx.get("items", 0)) < int(req["min_items"]):
		return false
	if req.has("min_relics") and int(ctx.get("relics", 0)) < int(req["min_relics"]):
		return false
	if req.has("min_team") and int(ctx.get("team_size", 0)) < int(req["min_team"]):
		return false
	# "team_full": only when the board is at its cap — the event is ABOUT having
	# nowhere to put another hero, so it must not fire when there's room.
	if bool(req.get("team_full", false)) \
			and int(ctx.get("team_size", 0)) < int(ctx.get("team_max", 99)):
		return false
	if req.has("dominant_element") \
			and int(ctx.get("dominant_element", 0)) < int(req["dominant_element"]):
		return false
	var flags: Dictionary = ctx.get("flags", {})
	if req.has("flag") and not _flag_truthy(flags, String(req["flag"])):
		return false
	if req.has("not_flag") and _flag_truthy(flags, String(req["not_flag"])):
		return false
	return true

static func _flag_truthy(flags: Dictionary, key: String) -> bool:
	if not flags.has(key):
		return false
	var v = flags[key]
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) > 0.0
	return true

# ══════════════════════════════════════════════════════════════════════════════
# RESOLUTION
# ══════════════════════════════════════════════════════════════════════════════
# Turn one choice into {effects, outcome} at a rolled grade. Pure: no side
# effects, no randomness except the coin flip inside "gamble" (which main_game
# resolves, not us — we only hand over the two payouts).
static func resolve_choice(choice: Dictionary, ctx: Dictionary, grade: String) -> Dictionary:
	var kind: String = String(choice.get("kind", "nothing"))
	var p: Dictionary = choice.get("params", {})
	var out: Dictionary = _resolve_kind(kind, p, ctx, grade)
	var prefix: String = String(choice.get("outcome_prefix", ""))
	if prefix != "":
		out["outcome"] = "%s %s" % [prefix, out.get("outcome", "")]
	return out

# ── The button line (2026-09-23) ──────────────────────────────────────────────
# What the player reads BEFORE picking. It used to be a hand-written line per
# choice ("Cold, wet and slower — severity graded"), which told the player the
# mood of a choice and none of its numbers. Now it is COMPUTED from the same
# resolver that pays out: resolve at the band's floor and ceiling grade and
# merge the two outcome sentences, so "…loses 8% of its current health" and
# "…loses 33%…" read as "…loses 8–33%…". It cannot drift from what it does,
# because it IS what the choice does, at both ends of its roll.
static func preview_line(choice: Dictionary, ctx: Dictionary) -> String:
	var pool: Array = EventGrade.reel_pool(String(choice.get("band", EventGrade.DEFAULT_BAND)))
	var lo: String = String(resolve_choice(choice, ctx, String(pool[0])).get("outcome", ""))
	var hi: String = String(resolve_choice(choice, ctx, String(pool[pool.size() - 1])).get("outcome", ""))
	return merge_range(lo, hi)

# Merge two outcome lines that differ only in their numbers/words into one
# ranged line. Token by token: equal tokens pass through; "−8%" vs "−33%" share
# a prefix and suffix around the digits, so they become "−8–33%"; anything else
# ("Common" vs "Legendary") becomes "Common–Legendary". If the two lines don't
# even have the same shape, show both rather than invent a merge.
static func merge_range(lo: String, hi: String) -> String:
	if lo == hi:
		return lo
	var a: PackedStringArray = lo.split(" ")
	var b: PackedStringArray = hi.split(" ")
	if a.size() != b.size():
		return "%s  →  %s" % [lo, hi]
	var num := RegEx.new()
	num.compile("^(\\D*?)(\\d+)(\\D*)$")
	# Words keep their punctuation outside the range: "D)" / "B)" → "D–B)".
	var word := RegEx.new()
	word.compile("^(\\W*)(.*?)(\\W*)$")
	var out: PackedStringArray = []
	for i in range(a.size()):
		if a[i] == b[i]:
			out.append(a[i])
			continue
		var ma: RegExMatch = num.search(a[i])
		var mb: RegExMatch = num.search(b[i])
		if ma and mb and ma.get_string(1) == mb.get_string(1) \
				and ma.get_string(3) == mb.get_string(3):
			var x: int = int(ma.get_string(2))
			var y: int = int(mb.get_string(2))
			out.append("%s%d–%d%s" % [ma.get_string(1), mini(x, y), maxi(x, y),
				ma.get_string(3)])
		else:
			var wa: RegExMatch = word.search(a[i])
			var wb: RegExMatch = word.search(b[i])
			if wa and wb and wa.get_string(1) == wb.get_string(1) \
					and wa.get_string(3) == wb.get_string(3):
				out.append("%s%s–%s%s" % [wa.get_string(1), wa.get_string(2),
					wb.get_string(2), wa.get_string(3)])
			else:
				out.append("%s–%s" % [a[i], b[i]])
	return " ".join(out)

# ── Scaling (MEASURED, not guessed — 2026-09-19) ──────────────────────────────
# The first draft of this catalog scaled payouts as "base + per_round * round",
# on the assumption that income climbs with the round. It does not: `arena
# --mode=goldcurve` reports ~7g per round at round 10 AND at round 100, flat
# across the whole run. What DOES climb is prices (ShopGenerator.round_scale =
# 1 + 0.05 × round, so a round-75 hero costs ~4.75x its base).
#
# So event gold tracks PRICES, not rounds: a payout with base 10 is worth
# roughly one hero purchase whenever it fires, early or late. Bases below are
# therefore quoted in round-1 gold, and the single source of truth for the curve
# is the shop's own constant — retune ROUND_PRICE_SCALE and events follow.
static func gold_scale(ctx: Dictionary) -> float:
	return ShopGenerator.round_scale(int(ctx.get("round", 1)))

# XP is a different curve again: total wave XP only moves 250 → 460 across
# rounds 5 → 75 (`arena --mode=xpcurve`), and a kill's XP is DIVIDED among
# living heroes, so one round is worth ~40-75 XP per hero. A gentle ramp keeps
# an XP event worth about the same number of rounds late as it is early.
static func xp_scale(ctx: Dictionary) -> float:
	return 1.0 + float(ctx.get("round", 1)) * 0.008

# ── How outcomes are worded (2026-09-24) ──────────────────────────────────────
# Every kind says what it does as (subject, clause) pairs — ["your team", "gains
# 12 gold"] — and _sentence() stitches them into plain English the way a person
# would say it: "Your team takes 9% more damage and gains 12 gold." The first
# pass printed stat-sheet fragments ("Team damage taken +9%  ·  +12g"), which
# the owner rejected: an event should read like how humans talk.
#
# Subject "" = the clause is already a whole sentence (flag lines, coin flips).
# Clause wording must not depend on the NUMBER (no "1 enemy" / "2 enemies"),
# because preview_line merges the floor and ceiling sentences word by word.
const TEAM := "your team"

static func _says(effects: Dictionary, said: Array) -> Dictionary:
	return {"effects": effects, "said": said, "outcome": _sentence(said)}

static func _sentence(said: Array) -> String:
	var sentences: PackedStringArray = []
	var i: int = 0
	while i < said.size():
		var subject: String = String(said[i][0])
		if subject == "":
			sentences.append(String(said[i][1]))
			i += 1
			continue
		var clauses: PackedStringArray = []
		while i < said.size() and String(said[i][0]) == subject:
			clauses.append(String(said[i][1]))
			i += 1
		sentences.append("%s %s." % [subject.left(1).to_upper() + subject.substr(1),
			_join_list(clauses)])
	return " ".join(sentences)

static func _join_list(items: PackedStringArray) -> String:
	if items.size() <= 1:
		return "".join(items)
	return "%s and %s" % [", ".join(items.slice(0, items.size() - 1)), items[items.size() - 1]]

static func _resolve_kind(kind: String, p: Dictionary, ctx: Dictionary, grade: String) -> Dictionary:
	match kind:
		"nothing":
			return _says({}, [["", "Nothing happens."]])

		# base (round-1 gold) × the price curve × the grade.
		"gold":
			var amt: int = EventGrade.scale_int(
				float(p.get("base", 5)) * gold_scale(ctx), grade)
			return _says({"gold": amt}, [[TEAM, "gains %d gold" % amt]])

		# A flat cost, or a percentage of the purse (pct wins if both given).
		# NOT grade-scaled: a price you agreed to shouldn't move after you agree.
		# Flat costs still ride the price curve, or a round-70 "toll" would be
		# pocket change.
		"gold_cost":
			if p.has("pct"):
				var pct: float = float(p["pct"])
				var lost: int = int(round(float(ctx.get("gold", 0)) * pct))
				return _says({"gold": -lost},
					[[TEAM, "pays %d gold (%d%% of your gold)" % [lost, int(pct * 100.0)]]])
			var flat: int = maxi(1, int(round(float(p.get("gold", 3)) * gold_scale(ctx))))
			return _says({"gold": -flat}, [[TEAM, "pays %d gold" % flat]])

		# 50/50, resolved by main_game's existing gold_if_win/gold_if_lose path.
		# stake_pct stakes a share of the purse; otherwise a flat amount. The
		# grade scales the WIN side only — that's what makes a graded gamble
		# different from a coin flip: the reel decides how big the prize is,
		# the flip decides whether you get it.
		"gamble":
			var stake: int = maxi(1, int(round(float(p.get("stake", 5)) * gold_scale(ctx))))
			if p.has("stake_pct"):
				stake = maxi(0, int(round(float(ctx.get("gold", 0)) * float(p["stake_pct"]))))
			# The prize can never be smaller than the stake. Without this floor a
			# low grade on a big wager produced "50/50 — win 30g, lose 60g",
			# which isn't a gamble, it's a mugging with extra steps.
			var win: int = maxi(stake,
				EventGrade.scale_int(float(stake) * float(p.get("payout", 2.0)), grade))
			return _says({"gold_if_win": win, "gold_if_lose": -stake},
				[["", "A coin flip: win %d gold or lose %d gold." % [win, stake]]])

		# stat: dmg / def / spd / hp. base is the 1.xx multiplier at grade C.
		"team_buff":
			var stat_b: String = String(p.get("stat", "dmg"))
			var m: float = EventGrade.scale_mult(float(p.get("base", 1.15)), grade)
			return _says({_buff_key(stat_b): m}, [[TEAM, _stat_clause(stat_b, m - 1.0)]])

		# Same, below 1.0. Grade here means SEVERITY — an S-grade curse is the
		# worst one, not the best. Bands for curses should lean "risky".
		"team_curse":
			var stat_c: String = String(p.get("stat", "def"))
			var mc: float = EventGrade.scale_penalty(float(p.get("base", 0.9)), grade)
			return _says({_buff_key(stat_c): mc}, [[TEAM, _stat_clause(stat_c, mc - 1.0)]])

		"heal":
			var e: Dictionary = {}
			var said: Array = []
			var hp_pct: float = float(p.get("hp", 0.0))
			if hp_pct > 0.0:
				var scaled_hp: float = minf(1.0, hp_pct * EventGrade.mult(grade))
				e["heal_pct"] = scaled_hp
				said.append([TEAM, "heals %d%% of its max health" % int(round(scaled_hp * 100.0))])
			var mp_pct: float = float(p.get("mana", 0.0))
			if mp_pct > 0.0:
				var scaled_mp: float = minf(1.0, mp_pct * EventGrade.mult(grade))
				e["mana_pct"] = scaled_mp
				said.append([TEAM, "restores %d%% of its max mana" % int(round(scaled_mp * 100.0))])
			if said.is_empty():
				said.append(["", "Nothing happens."])
			return _says(e, said)

		# Item rarity ceiling comes from the grade — this is the payout where the
		# reel matters most, because a Legendary is only reachable at S.
		"item":
			var count: int = int(p.get("count", 1))
			var cap: int = int(GRADE_RARITY.get(grade, 1))
			if p.has("max_rarity"):
				cap = mini(cap, int(p["max_rarity"]))
			return _says({"grant_item": {"count": count, "max_rarity": cap}},
				[[TEAM, "gets %s of up to %s rarity" % [
					"a random item" if count == 1 else "%d random items" % count,
					_rarity_name(cap)]]])

		# A graded perk onto one hero. target: random / best / weakest.
		"perk":
			var n: int = int(p.get("count", 1))
			var target: String = String(p.get("target", "random"))
			var who: String = _target_phrase(target, n)
			var verb: String = "each get" if n > 1 else "gets"
			return _says({"hero_perk": {"count": n, "target": target, "grade": grade}},
				[[who, "%s a grade %s perk" % [verb, grade]]])

		"hero_xp":
			var xp: int = EventGrade.scale_int(float(p.get("base", 50)) * xp_scale(ctx), grade)
			return _says({"hero_xp": xp}, [["every hero", "gains %d XP" % xp]])

		# A permanent trade on ONE hero: gain a percentage of one stat, lose a
		# percentage of another, forever. The GRADE SCALES THE UPSIDE ONLY — the
		# price is fixed, so the roll decides how good a deal you got, never
		# whether the deal hurts. Percentages (not flat numbers) keep a scar
		# meaningful at level 2 and at level 20.
		#
		# Numbers are percentages here because the catalog can't see which hero
		# it lands on; main_game reports the real figures once it does.
		"scar":
			var gain: Dictionary = p.get("gain", {})
			var cost: Dictionary = p.get("cost", {})
			var gpct: float = float(gain.get("pct", 0.15)) * EventGrade.mult(grade)
			var cpct: float = float(cost.get("pct", 0.12))
			var target_s: String = String(p.get("target", "random"))
			return _says({"hero_scar": {
					"target": target_s,
					"gain_stat": String(gain.get("stat", "attack_damage")),
					"gain_pct": gpct,
					"cost_stat": String(cost.get("stat", "max_hp")),
					"cost_pct": cpct,
				}},
				[[_target_phrase(target_s, 1), "permanently gains %d%% %s but loses %d%% %s" % [
					int(round(gpct * 100.0)), _stat_word(String(gain.get("stat", ""))),
					int(round(cpct * 100.0)), _stat_word(String(cost.get("stat", "")))]]])

		# Reach into the NEXT fight. extra_enemies adds bodies to the wave the
		# director builds; reward_tier re-rolls its payout on a higher tier's
		# odds. Both are consumed by that one battle and then cleared.
		"next_wave":
			var mods: Dictionary = {}
			var said: Array = []
			if p.has("extra_enemies"):
				# Grade decides how many extra bodies show up, so a bad roll on a
				# bounty is a rougher fight for the same promised payout.
				var n_extra: int = maxi(1, int(round(float(p["extra_enemies"])
					* EventGrade.mult(grade))))
				mods["extra_enemies"] = n_extra
				said.append(["your next fight", "has %d more enemies than usual" % n_extra])
			if p.has("reward_tier"):
				mods["reward_tier"] = int(p["reward_tier"])
				said.append(["your next fight", "pays %s-tier rewards"
					% _tier_word(int(p["reward_tier"]))])
			return _says({"next_wave": mods}, said)

		"level_up":
			var lv: int = int(p.get("count", 1))
			return _says({"max_level": lv},
				[["every hero", "gains %d level%s" % [lv, "" if lv == 1 else "s"]]])

		"team_size":
			var slots: int = int(p.get("count", 1))
			return _says({"max_units": slots},
				[["your board", "permanently gets %d more hero slot%s" % [
					slots, "" if slots == 1 else "s"]]])

		# Team-wide HP loss. Grade = severity (bands should be "risky").
		"damage":
			var dmg: float = minf(0.9, float(p.get("pct", 0.2)) * EventGrade.mult(grade))
			return _says({"hero_damage": -dmg},
				[[TEAM, "loses %d%% of its current health" % int(round(dmg * 100.0))]])

		# Scrap value is computed by main_game FROM THE ACTUAL ITEMS, not from a
		# flat number here — a flat "gold_per × price curve × grade" hit 84g per
		# item at round 75, more than a Rare costs to BUY at that round, i.e. a
		# buy-two-commons-and-scrap-them arbitrage. main_game pays a fraction of
		# each item's own shop value instead, so scrapping can never beat buying.
		# The grade rides along as a bounded bonus, not as the whole payout.
		"destroy_items":
			var dn: int = int(p.get("count", 1))
			var what: String = "its lowest-rarity item" if dn == 1 \
				else "its %d lowest-rarity items" % dn
			var fx: Dictionary = {"destroy_items":
				{"count": dn, "grade_mult": EventGrade.mult(grade)}}
			# ctx.scrap_values (main_game._event_context) is each item's salvage
			# value, lowest rarity first — the same items and the same formula
			# main_game pays out with, so the quoted gold is the real gold.
			if ctx.has("scrap_values"):
				var vals: Array = ctx["scrap_values"]
				var gm: float = clampf(EventGrade.mult(grade), SCRAP_GRADE_MIN, SCRAP_GRADE_MAX)
				var total: int = 0
				for i in range(mini(dn, vals.size())):
					total += maxi(1, int(round(float(vals[i]) * gm)))
				return _says(fx, [[TEAM, "sells %s for %d gold" % [what, total]]])
			return _says(fx, [[TEAM, "sells %s at a %s price" % [what, _salvage_word(grade)]]])

		"shop_discount":
			var pctd: float = minf(0.75, float(p.get("pct", 0.2)) * EventGrade.mult(grade))
			return _says({"shop_discount": pctd},
				[[TEAM, "gets %d%% off at the next merchant" % int(round(pctd * 100.0))]])

		"shop_sales":
			var sn: int = int(p.get("count", 2))
			return _says({"shop_sales": sn},
				[["the next merchant", "puts %d more item%s on sale" % [sn, "" if sn == 1 else "s"]]])

		# Gold now, a larger sum owed at the next merchant. Not grade-scaled on
		# the debt side — a loan shark doesn't round in your favour.
		"debt":
			var now_g: int = maxi(1, int(round(float(p.get("gold", 20)) * gold_scale(ctx))))
			var owed: int = maxi(1, int(round(float(p.get("owed", 34)) * gold_scale(ctx))))
			return _says({"gold": now_g, "debt": owed},
				[[TEAM, "gets %d gold now but owes %d gold at the next merchant" % [now_g, owed]]])

		"flag":
			var f: Dictionary = {}
			for k in p.keys():
				f[String(k)] = p[k]
			return _says({"set_flag": f}, [["", String(p.get("_text", "Noted."))]])

		# Several kinds at once — "fight back: gold AND a beating". Parts' clauses
		# are concatenated so _sentence can share a subject across them: "Your
		# team loses 18% of its current health and gains 26 gold."
		"combo":
			var merged: Dictionary = {}
			var said_all: Array = []
			for part in p.get("parts", []):
				var sub: Dictionary = _resolve_kind(
					String(part.get("kind", "nothing")), part.get("params", {}), ctx, grade)
				for k in sub.get("effects", {}).keys():
					merged[k] = sub["effects"][k]
				for s in sub.get("said", []):
					if String(s[1]) != "Nothing happens.":
						said_all.append(s)
			if said_all.is_empty():
				said_all.append(["", "Nothing happens."])
			return _says(merged, said_all)

		_:
			push_warning("EventCatalog: unknown choice kind '%s'" % kind)
			return _says({}, [["", "Nothing happens."]])

static func _buff_key(stat: String) -> String:
	match stat:
		"dmg": return "team_dmg_mult"
		"def": return "team_def_mult"
		"spd": return "team_spd_mult"
		"hp":  return "max_hp_mult"
	return "team_dmg_mult"

# One readout for both buffs and curses, and the reason it's shared: DEFENCE IS
# INVERTED. main_game applies team_def_mult as `relic_dmg_taken_mult *= 2 - m`,
# so a 1.33 "def buff" means you TAKE 33% LESS, not "damage taken +33%" — which
# is how the first version of this printed, i.e. a blessing that read like a
# curse. delta is the signed change to the stat's multiplier (m - 1).
static func _stat_clause(stat: String, delta: float) -> String:
	var pct: int = int(round(absf(delta) * 100.0))
	var up: bool = delta > 0.0
	match stat:
		"spd": return "attacks %d%% %s" % [pct, "faster" if up else "slower"]
		"hp":  return "%s %d%% max health" % ["gains" if up else "loses", pct]
		"def":
			# delta > 0 = a defence BUFF = less incoming damage.
			return "takes %d%% %s damage" % [pct, "less" if up else "more"]
	return "deals %d%% %s damage" % [pct, "more" if up else "less"]

# The grade on a scrap sale reads as how good a price she gives you, since the
# actual per-item number depends on what you hand over.
static func _salvage_word(grade: String) -> String:
	match grade:
		"F", "D": return "poor"
		"C":      return "fair"
		"B":      return "good"
	return "excellent"

static func _stat_word(stat: String) -> String:
	match stat:
		"attack_damage": return "damage"
		"magic_power":   return "magic power"
		"max_hp":        return "max health"
		"resistance":    return "armour"
		"attack_speed":  return "attack speed"
	return stat

static func _tier_word(tier: int) -> String:
	return ["Veteran", "Veteran", "Brutal"][clampi(tier, 0, 2)]

# The subject of a per-hero outcome: "your strongest hero gets…".
static func _target_phrase(target: String, n: int) -> String:
	match target:
		"best":    return "your strongest hero"
		"weakest": return "your weakest hero"
	return "a random hero" if n == 1 else "%d random heroes" % n

static func _rarity_name(r: int) -> String:
	const NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
	return NAMES[clampi(r, 0, 4)]

# ══════════════════════════════════════════════════════════════════════════════
# THE CATALOG
# ══════════════════════════════════════════════════════════════════════════════
# Built by a function rather than held in a const so enum references
# (EventBlessing.EventType.*) resolve at call time — a const dictionary
# referencing another class's enum is a parse-order hazard.
static func all_defs() -> Array:
	var defs: Array = []
	defs.append_array(_pool_blessings())
	defs.append_array(_pool_curses())
	defs.append_array(_pool_crossroads())
	defs.append_array(_pool_economy())
	defs.append_array(_pool_callbacks())
	return defs

static func def_by_id(id: String) -> Dictionary:
	for d in all_defs():
		if String(d.get("id", "")) == id:
			return d
	return {}

# ── Blessings ─────────────────────────────────────────────────────────────────
static func _pool_blessings() -> Array:
	var B: int = EventBlessing.EventType.BLESSING
	return [
	{
		"id": "gold_rush", "title": "Gold Rush", "type": B,
		"desc": "A collapsed cart has spilled a merchant's takings across the road.",
		"weight": 10,
		"choices": [
			{"text": "Pocket the coin", "band": "safe", "kind": "gold",
			 "params": {"base": 10}},
			{"text": "Buy the caravan's training", "band": "none", "kind": "level_up",
			 "params": {"count": 1}},
		],
	},
	{
		"id": "mystical_enhancement", "title": "Mystical Enhancement", "type": B,
		"desc": "An old enchanter offers to lay one blessing on your whole company.",
		"weight": 10,
		"choices": [
			{"text": "Blessing of fury", "band": "wide", "kind": "team_buff",
			 "params": {"stat": "dmg", "base": 1.15}},
			{"text": "Blessing of stone", "band": "wide", "kind": "team_buff",
			 "params": {"stat": "def", "base": 1.15}},
			{"text": "Blessing of haste", "band": "wide", "kind": "team_buff",
			 "params": {"stat": "spd", "base": 1.18}},
		],
	},
	{
		"id": "blacksmiths_offer", "title": "Blacksmith's Offer", "type": B,
		"desc": "A road-side smith will reinforce your gear — or pay you for the scrap you're hauling.",
		"weight": 9,
		"choices": [
			{"text": "Reinforce our armour", "band": "wide", "kind": "team_buff",
			 "params": {"stat": "hp", "base": 1.15}},
			{"text": "Sell him the scrap", "band": "safe", "kind": "gold",
			 "params": {"base": 7}},
		],
	},
	{
		"id": "rest_camp", "title": "Rest Camp", "type": B,
		"desc": "A walled camp with a well and a fire. You can spare an hour, not a night.",
		"weight": 8,
		"choices": [
			{"text": "Sleep", "band": "none", "kind": "heal",
			 "params": {"hp": 1.0}},
			{"text": "Meditate", "band": "none", "kind": "heal",
			 "params": {"mana": 1.0}},
			{"text": "Half of each, and take the camp's tithe", "band": "none", "kind": "combo",
			 "params": {"parts": [
				{"kind": "heal", "params": {"hp": 0.5, "mana": 0.5}},
				{"kind": "gold", "params": {"base": 5}},
			 ]}},
		],
	},
	{
		"id": "reinforcements", "title": "Reinforcements", "type": B,
		"desc": "A free company has been shadowing your march. Their captain wants in.",
		"weight": 7,
		"choices": [
			{"text": "Make room for them", "band": "none", "kind": "team_size",
			 "params": {"count": 1}},
			{"text": "Send them off with a purse", "band": "safe", "kind": "gold",
			 "params": {"base": 8}},
		],
	},
	{
		"id": "the_whetstone", "title": "The Whetstone", "type": B,
		"desc": "A grinding wheel, still warm. Whoever left it sharpened something recently.",
		"weight": 9,
		"choices": [
			{"text": "Sharpen for your strongest", "band": "safe", "kind": "perk",
			 "params": {"count": 1, "target": "best"}},
			{"text": "Let everyone take a turn", "band": "wide", "kind": "perk",
			 "params": {"count": 2, "target": "random"}},
		],
	},
	{
		"id": "traveling_scholar", "title": "Travelling Scholar", "type": B,
		"desc": "She has been writing down everything your company does. She'll read it back for a price.",
		"weight": 8,
		"choices": [
			{"text": "Sit and listen", "band": "wide", "kind": "hero_xp",
			 "params": {"base": 55}},
			{"text": "Buy her notes instead", "band": "safe", "kind": "gold",
			 "params": {"base": 8}},
		],
	},
	{
		"id": "armory_cache", "title": "Armoury Cache", "type": B,
		"desc": "A buried strongbox. The lock is old; the contents are anyone's guess.",
		"weight": 9,
		"choices": [
			{"text": "Force the lock", "band": "wide", "kind": "item",
			 "params": {"count": 1}},
			{"text": "Sell it unopened", "band": "safe", "kind": "gold",
			 "params": {"base": 9}},
		],
	},
	{
		"id": "the_wellspring", "title": "The Wellspring", "type": B,
		"desc": "Water with a faint light in it. Your wounded drink first, or nobody does.",
		"weight": 7,
		"choices": [
			{"text": "Drink deep", "band": "safe", "kind": "heal",
			 "params": {"hp": 0.5, "mana": 0.5}},
			{"text": "Fill the skins and march", "band": "wide", "kind": "team_buff",
			 "params": {"stat": "spd", "base": 1.12}},
		],
	},
	]

# ── Curses ────────────────────────────────────────────────────────────────────
static func _pool_curses() -> Array:
	var C: int = EventBlessing.EventType.CURSE
	return [
	{
		"id": "bandits_attack", "title": "Bandits Attack", "type": C,
		"desc": "A dozen of them, and they only want the purse. Probably.",
		"weight": 9,
		"choices": [
			{"text": "Pay the toll", "band": "none", "kind": "gold_cost",
			 "params": {"pct": 0.25}},
			{"text": "Fight them for it", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold", "params": {"base": 12}},
				{"kind": "damage", "params": {"pct": 0.18}},
			 ]}},
		],
	},
	{
		"id": "ambush", "title": "Ambush!", "type": C,
		"desc": "Arrows from the treeline before anyone has a weapon drawn.",
		"weight": 9,
		"choices": [
			{"text": "Hold formation and take it", "band": "risky", "kind": "damage",
			 "params": {"pct": 0.2}},
			{"text": "Scatter, and abandon a pack", "band": "none", "kind": "gold_cost",
			 "params": {"gold": 6}},
		],
	},
	{
		"id": "toll_bridge", "title": "Toll Bridge", "type": C,
		"desc": "The only crossing for a day's march, and it is owned.",
		"weight": 8,
		"choices": [
			{"text": "Pay the bridgekeeper", "band": "none", "kind": "gold_cost",
			 "params": {"pct": 0.3}},
			{"text": "Ford the river", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "damage", "params": {"pct": 0.15}},
				{"kind": "team_curse", "params": {"stat": "spd", "base": 0.94}},
			 ]}},
		],
	},
	{
		"id": "plague_wind", "title": "Plague Wind", "type": C,
		"desc": "The village downwind has been empty for a week. Now you know why.",
		"weight": 7, "requires": {"min_round": 6},
		"choices": [
			{"text": "Burn the supplies and quarantine", "band": "none", "kind": "gold_cost",
			 "params": {"pct": 0.2}},
			{"text": "March through it", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "damage", "params": {"pct": 0.16}},
				{"kind": "gold", "params": {"base": 11}},
			 ]}},
		],
	},
	{
		"id": "cave_of_echoes", "title": "Cave of Echoes", "type": C,
		"desc": "Something in here repeats what your heroes say, a half-second late.",
		"weight": 7,
		"choices": [
			{"text": "Push in and loot it", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "team_curse", "params": {"stat": "def", "base": 0.92}},
				{"kind": "gold", "params": {"base": 11}},
			 ]}},
			{"text": "Back out quietly", "band": "none", "kind": "nothing",
			 "params": {}},
		],
	},
	{
		"id": "rust_and_rot", "title": "Rust and Rot", "type": C,
		"desc": "Something in the damp has been eating your baggage train.",
		"weight": 6, "requires": {"min_items": 2},
		"choices": [
			{"text": "Pay a caravan smith to treat the gear", "band": "none", "kind": "gold_cost",
			 "params": {"pct": 0.18}},
			{"text": "Salvage what's left", "band": "wide", "kind": "destroy_items",
			 "params": {"count": 1}},
		],
	},
	{
		"id": "the_hoard", "title": "The Hoard", "type": C,
		"desc": "More gold than your company has ever seen, and something under it still breathing.",
		"weight": 5, "requires": {"min_round": 10},
		"choices": [
			{"text": "Take all of it", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold", "params": {"base": 20}},
				{"kind": "team_curse", "params": {"stat": "hp", "base": 0.88}},
			 ]}},
			{"text": "Take one handful and go", "band": "safe", "kind": "gold",
			 "params": {"base": 8}},
		],
	},
	]

# ── Crossroads (neutral decisions) ────────────────────────────────────────────
static func _pool_crossroads() -> Array:
	var N: int = EventBlessing.EventType.NEUTRAL
	var C: int = EventBlessing.EventType.CURSE
	return [
	{
		"id": "dark_pact", "title": "Dark Pact", "type": N,
		"desc": "It offers strength, and it is very clear about the price.",
		"weight": 8,
		"choices": [
			{"text": "Accept the pact", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "team_buff", "params": {"stat": "dmg", "base": 1.25}},
				{"kind": "team_curse", "params": {"stat": "hp", "base": 0.85}},
			 ]}},
			{"text": "Refuse", "band": "none", "kind": "nothing",
			 "params": {}},
		],
	},
	{
		"id": "gamblers_table", "title": "Gambler's Table", "type": N,
		"desc": "Three cups, one stone, and a man who is very pleased to see you.",
		"weight": 8,
		"choices": [
			{"text": "Play a hand", "band": "risky", "kind": "gamble",
			 "params": {"stake": 6, "payout": 2.2}},
			{"text": "Watch someone else lose", "band": "none", "kind": "gold",
			 "params": {"base": 2}},
		],
	},
	{
		"id": "desperate_wager", "title": "Desperate Wager", "type": N,
		"desc": "The same gambler, later, with a bigger table and no cups at all.",
		"weight": 5, "requires": {"min_gold": 15},
		"choices": [
			{"text": "All in", "band": "wide", "kind": "gamble",
			 "params": {"stake_pct": 1.0, "payout": 1.0}},
			{"text": "Walk away", "band": "none", "kind": "gold",
			 "params": {"base": 2}},
		],
	},
	{
		"id": "old_rivals_duel", "title": "Old Rival's Duel", "type": N,
		"desc": "A captain you once served with wants a friendly bout. Nothing is ever friendly with her.",
		"weight": 7,
		"choices": [
			{"text": "Accept the challenge", "band": "wide", "kind": "combo",
			 "params": {"parts": [
				{"kind": "team_buff", "params": {"stat": "dmg", "base": 1.1}},
				{"kind": "team_buff", "params": {"stat": "spd", "base": 1.1}},
			 ]}},
			{"text": "Decline politely", "band": "none", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold", "params": {"base": 6}},
				{"kind": "flag", "params": {"refused_duel": true, "_text": "She remembers this."}},
			 ]}},
		],
	},
	{
		"id": "veterans_scar", "title": "Veteran's Scar", "type": N,
		"desc": "The old field surgeon can cut deeper than the wound. Some of what he takes doesn't come back.",
		"weight": 7, "requires": {"min_round": 4},
		"choices": [
			{"text": "Let him work on your best", "band": "wide", "kind": "scar",
			 "params": {"target": "best",
				"gain": {"stat": "attack_damage", "pct": 0.18},
				"cost": {"stat": "max_hp", "pct": 0.12}}},
			{"text": "Send him away", "band": "safe", "kind": "gold",
			 "params": {"base": 6}},
		],
	},
	{
		"id": "the_bloodletting", "title": "The Bloodletting", "type": C,
		"desc": "A ritual that trades weight for speed. It has never once been reversed.",
		"weight": 6, "requires": {"min_round": 8},
		"choices": [
			{"text": "Offer your strongest", "band": "risky", "kind": "scar",
			 "params": {"target": "best",
				"gain": {"stat": "attack_speed", "pct": 0.16},
				"cost": {"stat": "resistance", "pct": 0.25}}},
			{"text": "Offer whoever volunteers", "band": "wide", "kind": "scar",
			 "params": {"target": "random",
				"gain": {"stat": "magic_power", "pct": 0.2},
				"cost": {"stat": "max_hp", "pct": 0.1}}},
			{"text": "Nobody is going under that knife", "band": "none", "kind": "nothing",
			 "params": {}},
		],
	},
	{
		"id": "bounty_board", "title": "Bounty Board", "type": N,
		"desc": "A contract nailed to a post: clear the road, and the guild pays properly.",
		"weight": 8, "requires": {"min_round": 3},
		"choices": [
			{"text": "Take the contract", "band": "wide", "kind": "next_wave",
			 "params": {"extra_enemies": 2, "reward_tier": 2}},
			{"text": "Read it and walk on", "band": "none", "kind": "nothing",
			 "params": {}},
		],
	},
	{
		"id": "the_gauntlet", "title": "The Gauntlet", "type": N,
		"desc": "They'll let your company through the pass — if it earns the crossing.",
		"weight": 7, "requires": {"min_round": 6},
		"choices": [
			{"text": "Run it", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "next_wave", "params": {"extra_enemies": 3, "reward_tier": 2}},
				{"kind": "damage", "params": {"pct": 0.1}},
			 ]}},
			{"text": "Pay the crossing toll", "band": "none", "kind": "gold_cost",
			 "params": {"pct": 0.25}},
		],
	},
	{
		"id": "the_crossroads", "title": "The Crossroads", "type": N,
		"desc": "Three roads, three signposts, none of them in a language anyone here reads.",
		"weight": 8,
		"choices": [
			{"text": "The merchant road", "band": "wide", "kind": "gold",
			 "params": {"base": 12}},
			{"text": "The battlefield road", "band": "wide", "kind": "item",
			 "params": {"count": 1}},
			{"text": "The pilgrim road", "band": "wide", "kind": "perk",
			 "params": {"count": 1, "target": "random"}},
		],
	},
	{
		"id": "the_understudy", "title": "The Understudy", "type": N,
		"desc": "A squire has been copying your best fighter's footwork for three days.",
		"weight": 6, "requires": {"min_round": 4},
		"choices": [
			{"text": "Train them properly", "band": "safe", "kind": "perk",
			 "params": {"count": 1, "target": "weakest"}},
			{"text": "Put them to work carrying", "band": "safe", "kind": "gold",
			 "params": {"base": 6}},
		],
	},
	{
		"id": "field_surgeon", "title": "Field Surgeon", "type": N,
		"desc": "He is not a good surgeon. He is, however, the only one.",
		"weight": 6,
		"choices": [
			{"text": "Let him work", "band": "wide", "kind": "heal",
			 "params": {"hp": 0.4}},
			{"text": "Pay him to go away", "band": "none", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold_cost", "params": {"gold": 4}},
				{"kind": "team_buff", "params": {"stat": "def", "base": 1.08}},
			 ]}},
		],
	},
	]

# ── Economy (events that reach forward into the merchant) ─────────────────────
static func _pool_economy() -> Array:
	var N: int = EventBlessing.EventType.NEUTRAL
	return [
	{
		"id": "merchants_apprentice", "title": "Merchant's Apprentice", "type": N,
		"desc": "He'll mark your company as a favoured buyer — his master need never know.",
		"weight": 7,
		"choices": [
			{"text": "Take the favour", "band": "wide", "kind": "shop_discount",
			 "params": {"pct": 0.2}},
			{"text": "Take coin instead", "band": "safe", "kind": "gold",
			 "params": {"base": 8}},
		],
	},
	{
		"id": "loyalty_token", "title": "Loyalty Token", "type": N,
		"desc": "A brass chit stamped with a guild mark. Merchants honour these. Mostly.",
		"weight": 6,
		"choices": [
			{"text": "Keep the token", "band": "none", "kind": "shop_sales",
			 "params": {"count": 2}},
			{"text": "Melt it down", "band": "safe", "kind": "gold",
			 "params": {"base": 7}},
		],
	},
	{
		"id": "letter_of_credit", "title": "Letter of Credit", "type": N,
		"desc": "Coin now against your company's name. The name is the collateral.",
		"weight": 6, "requires": {"min_round": 5, "not_flag": "debt"},
		"choices": [
			{"text": "Sign it", "band": "none", "kind": "debt",
			 "params": {"gold": 20, "owed": 34}},
			{"text": "Don't sign anything", "band": "none", "kind": "nothing",
			 "params": {}},
		],
	},
	{
		"id": "scrap_merchant", "title": "Scrap Merchant", "type": N,
		"desc": "She buys anything, by weight, and does not ask where it came from.",
		"weight": 7, "requires": {"min_items": 2},
		"choices": [
			{"text": "Sell her two pieces", "band": "wide", "kind": "destroy_items",
			 "params": {"count": 2}},
			{"text": "Sell her one", "band": "safe", "kind": "destroy_items",
			 "params": {"count": 1}},
			{"text": "Keep your kit", "band": "none", "kind": "nothing",
			 "params": {}},
		],
	},
	{
		"id": "quartermasters_offer", "title": "Quartermaster's Offer", "type": N,
		"desc": "An army quartermaster with a wagon of surplus and no paperwork.",
		"weight": 6, "requires": {"min_gold": 12},
		"choices": [
			# The crate is TWO items, not one. As one it was strictly the worse
			# bet — more gold for less expected value than the safe bundle — so
			# the "greedy" option lost on both the floor and the average, which
			# is the one shape a risk/reward pair must never have.
			{"text": "Buy the crate unseen", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold_cost", "params": {"gold": 12}},
				{"kind": "item", "params": {"count": 2}},
			 ]}},
			{"text": "Buy two cheap bundles", "band": "safe", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold_cost", "params": {"gold": 10}},
				{"kind": "item", "params": {"count": 2, "max_rarity": 1}},
			 ]}},
		],
	},
	]

# ── Callbacks (only fire because of something you already did) ────────────────
static func _pool_callbacks() -> Array:
	var N: int = EventBlessing.EventType.NEUTRAL
	var C: int = EventBlessing.EventType.CURSE
	var B: int = EventBlessing.EventType.BLESSING
	return [
	{
		"id": "the_rival_returns", "title": "The Rival Returns", "type": N,
		"desc": "She has not forgotten that you walked away from her challenge.",
		"weight": 14, "unique": true, "requires": {"flag": "refused_duel", "min_round": 6},
		"choices": [
			{"text": "Fight her properly this time", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "team_buff", "params": {"stat": "dmg", "base": 1.2}},
				{"kind": "damage", "params": {"pct": 0.12}},
			 ]}},
			{"text": "Buy her a drink and settle it", "band": "none", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold_cost", "params": {"gold": 8}},
				{"kind": "team_buff", "params": {"stat": "def", "base": 1.1}},
			 ]}},
		],
	},
	{
		"id": "debt_collector", "title": "Debt Collector", "type": C,
		"desc": "The letter you signed has found its way into less patient hands.",
		"weight": 16, "unique": true, "requires": {"flag": "debt_unpaid"},
		"choices": [
			{"text": "Settle what you can", "band": "none", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold_cost", "params": {"pct": 0.5}},
				{"kind": "flag", "params": {"debt_unpaid": false, "_text": "The ledger closes."}},
			 ]}},
			{"text": "Tell them to try", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "damage", "params": {"pct": 0.18}},
				{"kind": "flag", "params": {"debt_unpaid": false, "_text": "The matter ends painfully."}},
			 ]}},
		],
	},
	{
		"id": "shrine_of_convergence", "title": "Shrine of Convergence", "type": B,
		"desc": "The shrine answers to companies that share one nature. Yours does.",
		"weight": 12, "requires": {"dominant_element": 3, "min_round": 5},
		"choices": [
			{"text": "Kneel", "band": "wide", "kind": "combo",
			 "params": {"parts": [
				{"kind": "team_buff", "params": {"stat": "dmg", "base": 1.18}},
				{"kind": "team_buff", "params": {"stat": "def", "base": 1.1}},
			 ]}},
			{"text": "Loot the offerings", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold", "params": {"base": 16}},
				{"kind": "team_curse", "params": {"stat": "def", "base": 0.92}},
			 ]}},
		],
	},
	{
		"id": "no_room_in_the_ranks", "title": "No Room in the Ranks", "type": N,
		"desc": "Another good sword, and nowhere on the board to put them.",
		"weight": 10, "requires": {"team_full": true, "min_round": 8},
		"choices": [
			{"text": "Make room", "band": "none", "kind": "team_size",
			 "params": {"count": 1}},
			{"text": "Take their signing fee instead", "band": "wide", "kind": "gold",
			 "params": {"base": 12}},
		],
	},
	{
		"id": "veterans_toast", "title": "Veteran's Toast", "type": B,
		"desc": "Far enough in that the company has stories. They'd like a night to tell them.",
		"weight": 8, "requires": {"min_round": 20},
		"choices": [
			{"text": "Let them drink", "band": "wide", "kind": "hero_xp",
			 "params": {"base": 70}},
			{"text": "March at dawn regardless", "band": "safe", "kind": "team_buff",
			 "params": {"stat": "spd", "base": 1.1}},
		],
	},
	]
