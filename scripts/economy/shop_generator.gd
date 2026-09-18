extends Object
class_name ShopGenerator
# ══════════════════════════════════════════════════════════════════════════════
# EVENT SHOP — stock rolling + pricing (2026-07-20, user spec)
#
# A Slay-the-Spire-style merchant that appears at a prep-phase modal on the
# MERCHANT_ROUNDS below (later this becomes a map node the player walks to).
# EVERYTHING is pre-rolled and priced up front: the card you see IS what you
# buy — the hero's exact stat rolls, the item's exact stats, the stat-upgrade's
# exact grade. Nothing re-rolls at purchase time.
#
# This file is pure data/logic (no UI, no scene) so the arena harness can roll
# a stock and assert on prices/grades headlessly. The screen (shop_screen.gd)
# only renders the stock this returns and calls the price helper for rerolls.
#
# Pricing philosophy (matches balance.gd's stingy economy — see balance journal):
#   price = category_base × grade_mult × round_scale
# so a late-game S-roll costs a lot more than an early C-roll, and the shop
# stays relevant as income grows. All numbers are arena-tunable.
# ══════════════════════════════════════════════════════════════════════════════

# Which rounds the merchant appears on. Deliberately dodges elite rounds (5/15/25/.../95),
# relic waves (1/11/21/.../91) and boss rounds (10/20/30/.../100) so big moments don't pile up.
const MERCHANT_ROUNDS: Array[int] = [
	4, 8, 12, 16, 22, 26, 32, 36, 42, 46, 52, 56,
	62, 66, 72, 76, 82, 86, 92, 96,
]

# Inventory shape per visit (7 slots total — medium, StS-like).
const N_HEROES := 2
const N_ITEMS  := 2
const N_STATS  := 2
const N_RELICS := 1

# ── Pricing knobs ─────────────────────────────────────────────────────────────
const STAT_BASE  := 4                              # stat-upgrade base price
const HERO_BASE  := 10                             # hero base (prep-shop hero is 10g flat — shop heroes are KNOWN rolls, that's the premium)
const ITEM_BASE_BY_RARITY := [4, 7, 10, 14, 20]    # COMMON..LEGENDARY
# Relic bases ~1.8x'd 2026-08-07 (user: "relics are too cheap") — a relic is a
# PERMANENT run-wide effect (see relic_system_design), and at 8-30g base a
# round-4 C relic (14g) cost less than a single hero (10g) plus a coffee. Item
# and hero bases untouched — those were never called out as underpriced.
const RELIC_BASE_BY_GRADE := {"D": 14, "C": 22, "B": 30, "A": 40, "S": 55}
const RELIC_BASE_DEFAULT  := 22

# Grade → price multiplier (shared by heroes' letter grades and any letter path).
# Mirrors the F–S quality steps used by perks/recruits/relics everywhere else.
const GRADE_PRICE_MULT := {
	"F": 0.6, "D": 0.75, "C": 1.0, "B": 1.3, "A": 1.7, "S": 2.4,
}

# 0.04 -> 0.05 (2026-08-07 user: "price of items should also factor in the
# round" — items/relics/heroes/stats already ALL run through round_scale()
# below via _price(), this just steepens the existing curve a bit rather than
# adding a second mechanism).
const ROUND_PRICE_SCALE := 0.05
const SALE_MULT := 0.55           # the one sale slot: ~45% off
# Reroll: escalates WITHIN a visit (resets next shop). 3, 5, 7, 9 ...
const REROLL_BASE := 3
const REROLL_STEP := 2

static func is_merchant_round(round: int) -> bool:
	return round in MERCHANT_ROUNDS

# Cost of the Nth reroll this visit (n=0 for the first).
static func reroll_cost(n: int) -> int:
	return REROLL_BASE + REROLL_STEP * maxi(0, n)

static func round_scale(round: int) -> float:
	return 1.0 + maxi(0, round) * ROUND_PRICE_SCALE

# ── Price helpers (one per category) ──────────────────────────────────────────
static func _price(base: float, mult: float, round: int) -> int:
	return maxi(1, int(round(base * mult * round_scale(round))))

static func hero_price(rolls: Dictionary, round: int) -> int:
	var mult: float = GRADE_PRICE_MULT.get(rolls.get("grade", "C"), 1.0)
	return _price(HERO_BASE, mult, round)

static func stat_price(perk: Dictionary, round: int) -> int:
	return _price(STAT_BASE, float(perk.get("grade_mult", 1.0)), round)

static func item_price(item: EquipmentItem, round: int) -> int:
	var base: int = ITEM_BASE_BY_RARITY[clampi(item.rarity, 0, ITEM_BASE_BY_RARITY.size() - 1)]
	return _price(base, 1.0, round)

static func relic_price(relic: Dictionary, round: int) -> int:
	var base: int = RELIC_BASE_BY_GRADE.get(relic.get("grade", "C"), RELIC_BASE_DEFAULT)
	return _price(base, 1.0, round)

# ── Stock generation ──────────────────────────────────────────────────────────
# Returns an Array of slot dicts, each: {kind, price, on_sale, ...payload}. One
# random slot is flagged on_sale with a discounted price.
#   hero  -> {class, element, rolls}
#   stat  -> {perk}                    (a fully-rolled LevelUpScreen perk offer)
#   item  -> {item: EquipmentItem}
#   relic -> {relic: Dictionary}
static func roll_stock(round: int, owned_relic_ids: Array = []) -> Array:
	var stock: Array = []

	# Heroes — unique classes, each at its fixed natural aspect (2026-07-31: the
	# random element roll is gone) and with its own recruit rolls.
	var classes  := UnitFactory.get_all_classes()
	var used_heroes: Array = []
	var guard := 0
	while _count_kind(stock, "hero") < N_HEROES and guard < 200:
		guard += 1
		var cls: UnitBase.UnitClass = classes[randi() % classes.size()]
		if cls in used_heroes:
			continue
		used_heroes.append(cls)
		var elem := UnitFactory.element_for_class(cls)
		var rolls := UnitFactory.generate_recruit_rolls()
		stock.append({
			"kind": "hero", "class": cls, "element": elem, "rolls": rolls,
			"price": hero_price(rolls, round), "on_sale": false,
		})

	# Stat upgrades — pick distinct perks, each independently grade-rolled.
	var perk_pool: Array = LevelUpScreen.PERKS.duplicate()
	perk_pool.shuffle()
	for i in range(mini(N_STATS, perk_pool.size())):
		var perk: Dictionary = LevelUpScreen.roll_perk_offer(perk_pool[i])
		stock.append({
			"kind": "stat", "perk": perk,
			"price": stat_price(perk, round), "on_sale": false,
		})

	# Items — the shop can exceed the 100%-Common drop cap (uncommon/rare here).
	for _i in range(N_ITEMS):
		var item := EquipmentManager.generate_item(round, EquipmentItem.Rarity.RARE)
		stock.append({
			"kind": "item", "item": item,
			"price": item_price(item, round), "on_sale": false,
		})

	# Relic — one, excluding already-owned where possible.
	var offers := Relic.roll_offers(round, owned_relic_ids, N_RELICS)
	for relic in offers:
		stock.append({
			"kind": "relic", "relic": relic,
			"price": relic_price(relic, round), "on_sale": false,
		})

	_apply_sale(stock)
	return stock

# Flag one random slot as on-sale and discount its price.
static func _apply_sale(stock: Array) -> void:
	if stock.is_empty():
		return
	var idx := randi() % stock.size()
	stock[idx]["on_sale"] = true
	stock[idx]["original_price"] = stock[idx]["price"]
	stock[idx]["price"] = maxi(1, int(round(float(stock[idx]["price"]) * SALE_MULT)))

static func _count_kind(stock: Array, kind: String) -> int:
	var n := 0
	for s in stock:
		if s.get("kind", "") == kind:
			n += 1
	return n
