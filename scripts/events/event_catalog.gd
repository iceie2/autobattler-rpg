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

static func _resolve_kind(kind: String, p: Dictionary, ctx: Dictionary, grade: String) -> Dictionary:
	match kind:
		"nothing":
			return {"effects": {}, "outcome": "Nothing happens."}

		# base (round-1 gold) × the price curve × the grade.
		"gold":
			var amt: int = EventGrade.scale_int(
				float(p.get("base", 5)) * gold_scale(ctx), grade)
			return {"effects": {"gold": amt}, "outcome": "+%dg" % amt}

		# A flat cost, or a percentage of the purse (pct wins if both given).
		# NOT grade-scaled: a price you agreed to shouldn't move after you agree.
		# Flat costs still ride the price curve, or a round-70 "toll" would be
		# pocket change.
		"gold_cost":
			if p.has("pct"):
				var pct: float = float(p["pct"])
				var lost: int = int(round(float(ctx.get("gold", 0)) * pct))
				return {"effects": {"gold": -lost},
					"outcome": "−%dg (%d%% of your purse)" % [lost, int(pct * 100.0)]}
			var flat: int = maxi(1, int(round(float(p.get("gold", 3)) * gold_scale(ctx))))
			return {"effects": {"gold": -flat}, "outcome": "−%dg" % flat}

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
			return {"effects": {"gold_if_win": win, "gold_if_lose": -stake},
				"outcome": "50/50 — win %dg, lose %dg" % [win, stake]}

		# stat: dmg / def / spd / hp. base is the 1.xx multiplier at grade C.
		"team_buff":
			var stat_b: String = String(p.get("stat", "dmg"))
			var m: float = EventGrade.scale_mult(float(p.get("base", 1.15)), grade)
			return {"effects": {_buff_key(stat_b): m},
				"outcome": _stat_line(stat_b, m - 1.0, true)}

		# Same, below 1.0. Grade here means SEVERITY — an S-grade curse is the
		# worst one, not the best. Bands for curses should lean "risky".
		"team_curse":
			var stat_c: String = String(p.get("stat", "def"))
			var mc: float = EventGrade.scale_penalty(float(p.get("base", 0.9)), grade)
			return {"effects": {_buff_key(stat_c): mc},
				"outcome": _stat_line(stat_c, mc - 1.0, false)}

		"heal":
			var e: Dictionary = {}
			var parts: Array[String] = []
			var hp_pct: float = float(p.get("hp", 0.0))
			if hp_pct > 0.0:
				var scaled_hp: float = minf(1.0, hp_pct * EventGrade.mult(grade))
				e["heal_pct"] = scaled_hp
				parts.append("+%d%% HP" % int(round(scaled_hp * 100.0)))
			var mp_pct: float = float(p.get("mana", 0.0))
			if mp_pct > 0.0:
				var scaled_mp: float = minf(1.0, mp_pct * EventGrade.mult(grade))
				e["mana_pct"] = scaled_mp
				parts.append("+%d%% MP" % int(round(scaled_mp * 100.0)))
			return {"effects": e, "outcome": " · ".join(parts) if parts else "Nothing happens."}

		# Item rarity ceiling comes from the grade — this is the payout where the
		# reel matters most, because a Legendary is only reachable at S.
		"item":
			var count: int = int(p.get("count", 1))
			var cap: int = int(GRADE_RARITY.get(grade, 1))
			if p.has("max_rarity"):
				cap = mini(cap, int(p["max_rarity"]))
			return {"effects": {"grant_item": {"count": count, "max_rarity": cap}},
				"outcome": "%d item%s (up to %s)" % [count, "" if count == 1 else "s",
					_rarity_name(cap)]}

		# A graded perk onto one hero. target: random / best / weakest.
		"perk":
			var n: int = int(p.get("count", 1))
			var target: String = String(p.get("target", "random"))
			return {"effects": {"hero_perk": {"count": n, "target": target, "grade": grade}},
				"outcome": "%d %s-grade perk%s to your %s hero" % [
					n, grade, "" if n == 1 else "s", _target_word(target)]}

		"hero_xp":
			var xp: int = EventGrade.scale_int(float(p.get("base", 50)) * xp_scale(ctx), grade)
			return {"effects": {"hero_xp": xp}, "outcome": "+%d XP to every hero" % xp}

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
			return {"effects": {"hero_scar": {
					"target": String(p.get("target", "random")),
					"gain_stat": String(gain.get("stat", "attack_damage")),
					"gain_pct": gpct,
					"cost_stat": String(cost.get("stat", "max_hp")),
					"cost_pct": cpct,
				}},
				"outcome": "%s hero: +%d%% %s, −%d%% %s (permanent)" % [
					_target_word(String(p.get("target", "random"))).capitalize(),
					int(round(gpct * 100.0)), _stat_word(String(gain.get("stat", ""))),
					int(round(cpct * 100.0)), _stat_word(String(cost.get("stat", "")))]}

		# Reach into the NEXT fight. extra_enemies adds bodies to the wave the
		# director builds; reward_tier re-rolls its payout on a higher tier's
		# odds. Both are consumed by that one battle and then cleared.
		"next_wave":
			var mods: Dictionary = {}
			var lines: Array[String] = []
			if p.has("extra_enemies"):
				# Grade decides how many extra bodies show up, so a bad roll on a
				# bounty is a rougher fight for the same promised payout.
				var n_extra: int = maxi(1, int(round(float(p["extra_enemies"])
					* EventGrade.mult(grade))))
				mods["extra_enemies"] = n_extra
				lines.append("next fight has +%d enemies" % n_extra)
			if p.has("reward_tier"):
				mods["reward_tier"] = int(p["reward_tier"])
				lines.append("its reward pays at %s rates"
					% _tier_word(int(p["reward_tier"])))
			return {"effects": {"next_wave": mods}, "outcome": ", ".join(lines)}

		"level_up":
			var lv: int = int(p.get("count", 1))
			return {"effects": {"max_level": lv},
				"outcome": "Every hero gains %d level%s" % [lv, "" if lv == 1 else "s"]}

		"team_size":
			var slots: int = int(p.get("count", 1))
			return {"effects": {"max_units": slots}, "outcome": "+%d board slot" % slots}

		# Team-wide HP loss. Grade = severity (bands should be "risky").
		"damage":
			var dmg: float = minf(0.9, float(p.get("pct", 0.2)) * EventGrade.mult(grade))
			return {"effects": {"hero_damage": -dmg},
				"outcome": "−%d%% team HP" % int(round(dmg * 100.0))}

		# Scrap value is computed by main_game FROM THE ACTUAL ITEMS, not from a
		# flat number here — a flat "gold_per × price curve × grade" hit 84g per
		# item at round 75, more than a Rare costs to BUY at that round, i.e. a
		# buy-two-commons-and-scrap-them arbitrage. main_game pays a fraction of
		# each item's own shop value instead, so scrapping can never beat buying.
		# The grade rides along as a bounded bonus, not as the whole payout.
		"destroy_items":
			var dn: int = int(p.get("count", 1))
			return {"effects": {"destroy_items":
					{"count": dn, "grade_mult": EventGrade.mult(grade)}},
				"outcome": "Scrap %d item%s at %s salvage rates" % [
					dn, "" if dn == 1 else "s", _salvage_word(grade)]}

		"shop_discount":
			var pctd: float = minf(0.75, float(p.get("pct", 0.2)) * EventGrade.mult(grade))
			return {"effects": {"shop_discount": pctd},
				"outcome": "%d%% off the next merchant" % int(round(pctd * 100.0))}

		"shop_sales":
			var sn: int = int(p.get("count", 2))
			return {"effects": {"shop_sales": sn},
				"outcome": "+%d sale slots at the next merchant" % sn}

		# Gold now, a larger sum owed at the next merchant. Not grade-scaled on
		# the debt side — a loan shark doesn't round in your favour.
		"debt":
			var now_g: int = maxi(1, int(round(float(p.get("gold", 20)) * gold_scale(ctx))))
			var owed: int = maxi(1, int(round(float(p.get("owed", 34)) * gold_scale(ctx))))
			return {"effects": {"gold": now_g, "debt": owed},
				"outcome": "+%dg now, %dg owed at the next merchant" % [now_g, owed]}

		"flag":
			var f: Dictionary = {}
			for k in p.keys():
				f[String(k)] = p[k]
			return {"effects": {"set_flag": f}, "outcome": String(p.get("_text", "Noted."))}

		# Several kinds at once — "fight back: gold AND a beating".
		"combo":
			var merged: Dictionary = {}
			var lines: Array[String] = []
			for part in p.get("parts", []):
				var sub: Dictionary = _resolve_kind(
					String(part.get("kind", "nothing")), part.get("params", {}), ctx, grade)
				for k in sub.get("effects", {}).keys():
					merged[k] = sub["effects"][k]
				var line: String = String(sub.get("outcome", ""))
				if line != "" and line != "Nothing happens.":
					lines.append(line)
			return {"effects": merged, "outcome": "  ·  ".join(lines)}

		_:
			push_warning("EventCatalog: unknown choice kind '%s'" % kind)
			return {"effects": {}, "outcome": "Nothing happens."}

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
static func _stat_line(stat: String, delta: float, _is_buff: bool) -> String:
	var pct: int = int(round(absf(delta) * 100.0))
	match stat:
		"dmg": return "Damage %s%d%%" % ["+" if delta > 0.0 else "−", pct]
		"spd": return "Attack speed %s%d%%" % ["+" if delta > 0.0 else "−", pct]
		"hp":  return "Max HP %s%d%%" % ["+" if delta > 0.0 else "−", pct]
		"def":
			# delta > 0 = a defence BUFF = less incoming damage.
			return "Damage taken %s%d%%" % ["−" if delta > 0.0 else "+", pct]
	return "Damage %s%d%%" % ["+" if delta > 0.0 else "−", pct]

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
		"magic_power":   return "magic"
		"max_hp":        return "max HP"
		"resistance":    return "armour"
		"attack_speed":  return "attack speed"
	return stat

static func _tier_word(tier: int) -> String:
	return ["Veteran", "Veteran", "Brutal"][clampi(tier, 0, 2)]

static func _target_word(target: String) -> String:
	match target:
		"best":    return "strongest"
		"weakest": return "weakest"
	return "random"

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
			 "params": {"base": 10}, "preview": "Gold — a sure thing (D–B)"},
			{"text": "Buy the caravan's training", "band": "none", "kind": "level_up",
			 "params": {"count": 1}, "preview": "Every hero gains a level"},
		],
	},
	{
		"id": "mystical_enhancement", "title": "Mystical Enhancement", "type": B,
		"desc": "An old enchanter offers to lay one blessing on your whole company.",
		"weight": 10,
		"choices": [
			{"text": "Blessing of fury", "band": "wide", "kind": "team_buff",
			 "params": {"stat": "dmg", "base": 1.15}, "preview": "Team damage — graded F–S"},
			{"text": "Blessing of stone", "band": "wide", "kind": "team_buff",
			 "params": {"stat": "def", "base": 1.15}, "preview": "Damage taken — graded F–S"},
			{"text": "Blessing of haste", "band": "wide", "kind": "team_buff",
			 "params": {"stat": "spd", "base": 1.18}, "preview": "Attack speed — graded F–S"},
		],
	},
	{
		"id": "blacksmiths_offer", "title": "Blacksmith's Offer", "type": B,
		"desc": "A road-side smith will reinforce your gear — or pay you for the scrap you're hauling.",
		"weight": 9,
		"choices": [
			{"text": "Reinforce our armour", "band": "wide", "kind": "team_buff",
			 "params": {"stat": "hp", "base": 1.15}, "preview": "Team max HP — graded F–S"},
			{"text": "Sell him the scrap", "band": "safe", "kind": "gold",
			 "params": {"base": 7}, "preview": "Gold — a sure thing (D–B)"},
		],
	},
	{
		"id": "rest_camp", "title": "Rest Camp", "type": B,
		"desc": "A walled camp with a well and a fire. You can spare an hour, not a night.",
		"weight": 8,
		"choices": [
			{"text": "Sleep", "band": "none", "kind": "heal",
			 "params": {"hp": 1.0}, "preview": "Restore all HP"},
			{"text": "Meditate", "band": "none", "kind": "heal",
			 "params": {"mana": 1.0}, "preview": "Restore all MP"},
			{"text": "Half of each, and take the camp's tithe", "band": "none", "kind": "combo",
			 "params": {"parts": [
				{"kind": "heal", "params": {"hp": 0.5, "mana": 0.5}},
				{"kind": "gold", "params": {"base": 5}},
			 ]}, "preview": "Half HP and MP, plus gold"},
		],
	},
	{
		"id": "reinforcements", "title": "Reinforcements", "type": B,
		"desc": "A free company has been shadowing your march. Their captain wants in.",
		"weight": 7,
		"choices": [
			{"text": "Make room for them", "band": "none", "kind": "team_size",
			 "params": {"count": 1}, "preview": "+1 board slot, permanently"},
			{"text": "Send them off with a purse", "band": "safe", "kind": "gold",
			 "params": {"base": 8}, "preview": "Gold — a sure thing (D–B)"},
		],
	},
	{
		"id": "the_whetstone", "title": "The Whetstone", "type": B,
		"desc": "A grinding wheel, still warm. Whoever left it sharpened something recently.",
		"weight": 9,
		"choices": [
			{"text": "Sharpen for your strongest", "band": "safe", "kind": "perk",
			 "params": {"count": 1, "target": "best"}, "preview": "One perk, your best hero (D–B)"},
			{"text": "Let everyone take a turn", "band": "wide", "kind": "perk",
			 "params": {"count": 2, "target": "random"}, "preview": "Two perks, random heroes (F–S)"},
		],
	},
	{
		"id": "traveling_scholar", "title": "Travelling Scholar", "type": B,
		"desc": "She has been writing down everything your company does. She'll read it back for a price.",
		"weight": 8,
		"choices": [
			{"text": "Sit and listen", "band": "wide", "kind": "hero_xp",
			 "params": {"base": 55}, "preview": "XP for every hero — graded F–S"},
			{"text": "Buy her notes instead", "band": "safe", "kind": "gold",
			 "params": {"base": 8}, "preview": "Gold — a sure thing (D–B)"},
		],
	},
	{
		"id": "armory_cache", "title": "Armoury Cache", "type": B,
		"desc": "A buried strongbox. The lock is old; the contents are anyone's guess.",
		"weight": 9,
		"choices": [
			{"text": "Force the lock", "band": "wide", "kind": "item",
			 "params": {"count": 1}, "preview": "One item — rarity set by the roll (F–S)"},
			{"text": "Sell it unopened", "band": "safe", "kind": "gold",
			 "params": {"base": 9}, "preview": "Gold — a sure thing (D–B)"},
		],
	},
	{
		"id": "the_wellspring", "title": "The Wellspring", "type": B,
		"desc": "Water with a faint light in it. Your wounded drink first, or nobody does.",
		"weight": 7,
		"choices": [
			{"text": "Drink deep", "band": "safe", "kind": "heal",
			 "params": {"hp": 0.5, "mana": 0.5}, "preview": "Restore HP and MP — graded (D–B)"},
			{"text": "Fill the skins and march", "band": "wide", "kind": "team_buff",
			 "params": {"stat": "spd", "base": 1.12}, "preview": "Attack speed — graded F–S"},
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
			 "params": {"pct": 0.25}, "preview": "Lose a quarter of your gold"},
			{"text": "Fight them for it", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold", "params": {"base": 12}},
				{"kind": "damage", "params": {"pct": 0.18}},
			 ]}, "preview": "Their purse, and a beating — graded F–S"},
		],
	},
	{
		"id": "ambush", "title": "Ambush!", "type": C,
		"desc": "Arrows from the treeline before anyone has a weapon drawn.",
		"weight": 9,
		"choices": [
			{"text": "Hold formation and take it", "band": "risky", "kind": "damage",
			 "params": {"pct": 0.2}, "preview": "Team HP — severity graded F–S"},
			{"text": "Scatter, and abandon a pack", "band": "none", "kind": "gold_cost",
			 "params": {"gold": 6}, "preview": "Pay them off — no damage taken"},
		],
	},
	{
		"id": "toll_bridge", "title": "Toll Bridge", "type": C,
		"desc": "The only crossing for a day's march, and it is owned.",
		"weight": 8,
		"choices": [
			{"text": "Pay the bridgekeeper", "band": "none", "kind": "gold_cost",
			 "params": {"pct": 0.3}, "preview": "Lose 30% of your gold"},
			{"text": "Ford the river", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "damage", "params": {"pct": 0.15}},
				{"kind": "team_curse", "params": {"stat": "spd", "base": 0.94}},
			 ]}, "preview": "Cold, wet and slower — severity graded"},
		],
	},
	{
		"id": "plague_wind", "title": "Plague Wind", "type": C,
		"desc": "The village downwind has been empty for a week. Now you know why.",
		"weight": 7, "requires": {"min_round": 6},
		"choices": [
			{"text": "Burn the supplies and quarantine", "band": "none", "kind": "gold_cost",
			 "params": {"pct": 0.2}, "preview": "Lose 20% of your gold, stay clean"},
			{"text": "March through it", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "damage", "params": {"pct": 0.16}},
				{"kind": "gold", "params": {"base": 11}},
			 ]}, "preview": "Loot the village, carry the sickness — graded"},
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
			 ]}, "preview": "Gold, and rattled nerves — graded F–S"},
			{"text": "Back out quietly", "band": "none", "kind": "nothing",
			 "params": {}, "preview": "Nothing gained, nothing lost"},
		],
	},
	{
		"id": "rust_and_rot", "title": "Rust and Rot", "type": C,
		"desc": "Something in the damp has been eating your baggage train.",
		"weight": 6, "requires": {"min_items": 2},
		"choices": [
			{"text": "Pay a caravan smith to treat the gear", "band": "none", "kind": "gold_cost",
			 "params": {"pct": 0.18}, "preview": "Lose 18% of your gold, keep everything"},
			{"text": "Salvage what's left", "band": "wide", "kind": "destroy_items",
			 "params": {"count": 1},
			 "preview": "Lose one item, sell the remains — graded F–S"},
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
			 ]}, "preview": "A fortune, and it costs you — graded F–S"},
			{"text": "Take one handful and go", "band": "safe", "kind": "gold",
			 "params": {"base": 8}, "preview": "Gold — a sure thing (D–B)"},
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
			 ]}, "preview": "Damage up, HP down — both graded F–S"},
			{"text": "Refuse", "band": "none", "kind": "nothing",
			 "params": {}, "preview": "Nothing happens"},
		],
	},
	{
		"id": "gamblers_table", "title": "Gambler's Table", "type": N,
		"desc": "Three cups, one stone, and a man who is very pleased to see you.",
		"weight": 8,
		"choices": [
			{"text": "Play a hand", "band": "risky", "kind": "gamble",
			 "params": {"stake": 6, "payout": 2.2}, "preview": "50/50 — the prize is graded F–S"},
			{"text": "Watch someone else lose", "band": "none", "kind": "gold",
			 "params": {"base": 2}, "preview": "Pocket a little and move on"},
		],
	},
	{
		"id": "desperate_wager", "title": "Desperate Wager", "type": N,
		"desc": "The same gambler, later, with a bigger table and no cups at all.",
		"weight": 5, "requires": {"min_gold": 15},
		"choices": [
			{"text": "All in", "band": "wide", "kind": "gamble",
			 "params": {"stake_pct": 1.0, "payout": 1.0},
			 "preview": "50/50 on your whole purse — prize graded F–S"},
			{"text": "Walk away", "band": "none", "kind": "gold",
			 "params": {"base": 2}, "preview": "Pocket a little and move on"},
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
			 ]}, "preview": "Sharper and faster — graded F–S"},
			{"text": "Decline politely", "band": "none", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold", "params": {"base": 6}},
				{"kind": "flag", "params": {"refused_duel": true, "_text": "She remembers this."}},
			 ]}, "preview": "Take the purse and go — she'll remember"},
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
				"cost": {"stat": "max_hp", "pct": 0.12}},
			 "preview": "Permanent: damage up, max HP down — upside graded F–S"},
			{"text": "Send him away", "band": "safe", "kind": "gold",
			 "params": {"base": 6}, "preview": "Gold — a sure thing (D–B)"},
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
				"cost": {"stat": "resistance", "pct": 0.25}},
			 "preview": "Permanent: faster, thinner-skinned — upside graded F–S"},
			{"text": "Offer whoever volunteers", "band": "wide", "kind": "scar",
			 "params": {"target": "random",
				"gain": {"stat": "magic_power", "pct": 0.2},
				"cost": {"stat": "max_hp", "pct": 0.1}},
			 "preview": "Permanent, on a random hero: magic up, HP down"},
			{"text": "Nobody is going under that knife", "band": "none", "kind": "nothing",
			 "params": {}, "preview": "Nothing happens"},
		],
	},
	{
		"id": "bounty_board", "title": "Bounty Board", "type": N,
		"desc": "A contract nailed to a post: clear the road, and the guild pays properly.",
		"weight": 8, "requires": {"min_round": 3},
		"choices": [
			{"text": "Take the contract", "band": "wide", "kind": "next_wave",
			 "params": {"extra_enemies": 2, "reward_tier": 2},
			 "preview": "Harder next fight, but it pays at Brutal rates"},
			{"text": "Read it and walk on", "band": "none", "kind": "nothing",
			 "params": {}, "preview": "Nothing happens"},
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
			 ]}, "preview": "Bloodied going in, a much harder fight, top-tier payout"},
			{"text": "Pay the crossing toll", "band": "none", "kind": "gold_cost",
			 "params": {"pct": 0.25}, "preview": "Lose a quarter of your gold, walk through"},
		],
	},
	{
		"id": "the_crossroads", "title": "The Crossroads", "type": N,
		"desc": "Three roads, three signposts, none of them in a language anyone here reads.",
		"weight": 8,
		"choices": [
			{"text": "The merchant road", "band": "wide", "kind": "gold",
			 "params": {"base": 12}, "preview": "Gold — graded F–S"},
			{"text": "The battlefield road", "band": "wide", "kind": "item",
			 "params": {"count": 1}, "preview": "An item — rarity set by the roll (F–S)"},
			{"text": "The pilgrim road", "band": "wide", "kind": "perk",
			 "params": {"count": 1, "target": "random"}, "preview": "A perk for one hero — graded F–S"},
		],
	},
	{
		"id": "the_understudy", "title": "The Understudy", "type": N,
		"desc": "A squire has been copying your best fighter's footwork for three days.",
		"weight": 6, "requires": {"min_round": 4},
		"choices": [
			{"text": "Train them properly", "band": "safe", "kind": "perk",
			 "params": {"count": 1, "target": "weakest"}, "preview": "A perk for your weakest hero (D–B)"},
			{"text": "Put them to work carrying", "band": "safe", "kind": "gold",
			 "params": {"base": 6}, "preview": "Gold — a sure thing (D–B)"},
		],
	},
	{
		"id": "field_surgeon", "title": "Field Surgeon", "type": N,
		"desc": "He is not a good surgeon. He is, however, the only one.",
		"weight": 6,
		"choices": [
			{"text": "Let him work", "band": "wide", "kind": "heal",
			 "params": {"hp": 0.4}, "preview": "Team HP — graded F–S"},
			{"text": "Pay him to go away", "band": "none", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold_cost", "params": {"gold": 4}},
				{"kind": "team_buff", "params": {"stat": "def", "base": 1.08}},
			 ]}, "preview": "Pay him off — the company sleeps easier"},
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
			 "params": {"pct": 0.2}, "preview": "Discount at the next merchant — graded F–S"},
			{"text": "Take coin instead", "band": "safe", "kind": "gold",
			 "params": {"base": 8}, "preview": "Gold — a sure thing (D–B)"},
		],
	},
	{
		"id": "loyalty_token", "title": "Loyalty Token", "type": N,
		"desc": "A brass chit stamped with a guild mark. Merchants honour these. Mostly.",
		"weight": 6,
		"choices": [
			{"text": "Keep the token", "band": "none", "kind": "shop_sales",
			 "params": {"count": 2}, "preview": "+2 sale slots at the next merchant"},
			{"text": "Melt it down", "band": "safe", "kind": "gold",
			 "params": {"base": 7}, "preview": "Gold — a sure thing (D–B)"},
		],
	},
	{
		"id": "letter_of_credit", "title": "Letter of Credit", "type": N,
		"desc": "Coin now against your company's name. The name is the collateral.",
		"weight": 6, "requires": {"min_round": 5, "not_flag": "debt"},
		"choices": [
			{"text": "Sign it", "band": "none", "kind": "debt",
			 "params": {"gold": 20, "owed": 34},
			 "preview": "Gold now, more owed at the next merchant"},
			{"text": "Don't sign anything", "band": "none", "kind": "nothing",
			 "params": {}, "preview": "Nothing happens"},
		],
	},
	{
		"id": "scrap_merchant", "title": "Scrap Merchant", "type": N,
		"desc": "She buys anything, by weight, and does not ask where it came from.",
		"weight": 7, "requires": {"min_items": 2},
		"choices": [
			{"text": "Sell her two pieces", "band": "wide", "kind": "destroy_items",
			 "params": {"count": 2},
			 "preview": "Two items become gold — graded F–S"},
			{"text": "Sell her one", "band": "safe", "kind": "destroy_items",
			 "params": {"count": 1},
			 "preview": "One item becomes gold (D–B)"},
			{"text": "Keep your kit", "band": "none", "kind": "nothing",
			 "params": {}, "preview": "Nothing happens"},
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
			 ]}, "preview": "Two items, sight unseen — rarity graded F–S"},
			{"text": "Buy two cheap bundles", "band": "safe", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold_cost", "params": {"gold": 10}},
				{"kind": "item", "params": {"count": 2, "max_rarity": 1}},
			 ]}, "preview": "Two low-rarity items at a fixed price"},
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
			 ]}, "preview": "A real bout — graded F–S"},
			{"text": "Buy her a drink and settle it", "band": "none", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold_cost", "params": {"gold": 8}},
				{"kind": "team_buff", "params": {"stat": "def", "base": 1.1}},
			 ]}, "preview": "Buy the round — the company steadies"},
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
			 ]}, "preview": "Half your purse, and the matter ends"},
			{"text": "Tell them to try", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "damage", "params": {"pct": 0.18}},
				{"kind": "flag", "params": {"debt_unpaid": false, "_text": "The matter ends painfully."}},
			 ]}, "preview": "They collect in blood — severity graded"},
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
			 ]}, "preview": "Damage and defence — graded F–S"},
			{"text": "Loot the offerings", "band": "risky", "kind": "combo",
			 "params": {"parts": [
				{"kind": "gold", "params": {"base": 16}},
				{"kind": "team_curse", "params": {"stat": "def", "base": 0.92}},
			 ]}, "preview": "Gold, and the shrine's displeasure — graded"},
		],
	},
	{
		"id": "no_room_in_the_ranks", "title": "No Room in the Ranks", "type": N,
		"desc": "Another good sword, and nowhere on the board to put them.",
		"weight": 10, "requires": {"team_full": true, "min_round": 8},
		"choices": [
			{"text": "Make room", "band": "none", "kind": "team_size",
			 "params": {"count": 1}, "preview": "+1 board slot, permanently"},
			{"text": "Take their signing fee instead", "band": "wide", "kind": "gold",
			 "params": {"base": 12}, "preview": "Gold — graded F–S"},
		],
	},
	{
		"id": "veterans_toast", "title": "Veteran's Toast", "type": B,
		"desc": "Far enough in that the company has stories. They'd like a night to tell them.",
		"weight": 8, "requires": {"min_round": 20},
		"choices": [
			{"text": "Let them drink", "band": "wide", "kind": "hero_xp",
			 "params": {"base": 70}, "preview": "XP for every hero — graded F–S"},
			{"text": "March at dawn regardless", "band": "safe", "kind": "team_buff",
			 "params": {"stat": "spd", "base": 1.1}, "preview": "Attack speed (D–B)"},
		],
	},
	]
