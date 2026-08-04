extends Node
# Autoload singleton — persists crystal wallet and upgrade levels across runs.

const SAVE_PATH := "user://progression.json"

var crystals: int = 0

# upgrade_levels maps upgrade key → current level (0 = not bought)
var upgrade_levels: Dictionary = {}

# ── Upgrade catalogue ─────────────────────────────────────────────────────────
# Each entry: { key, name, desc, max_level, effect_per_level }
# effect_per_level is used by the game to query the bonus value.
const UPGRADES: Array = [
	{
		# 2026-07-16 economy pair rework (user spec): converted from "+1 gold
		# once at run start" to "+1 gold after every round" — the cheap half of
		# the gold pair, with Bounty (per-kill) hard-gated behind it. Key stays
		# "starting_gold" for save compatibility.
		"key": "starting_gold", "name": "Head Start",
		"desc": "+1 gold after every round per level.",
		"effect": "Gold / Round +%d", "max_level": 10, "effect_per_level": 1,
	},
	{
		# The expensive half of the gold pair: far more total income (kills per
		# round beat rounds per round), locked until Head Start has a level.
		# Reworked 2026-07-31 (user spec): was a flat +1 gold guaranteed per
		# kill; now each level is an INDEPENDENT 25% chance to drop one extra
		# coin per kill, decoupled from the base gold-per-kill rate. 4 levels
		# so maxed = 100% = the old guaranteed +1. See main_game.gd kill-credit
		# block for the roll. More of these %-chance drop nodes are planned —
		# this is the first of that family, not a one-off.
		"key": "gold_per_kill", "name": "Bounty",
		"desc": "+25% independent chance per level to drop 1 extra gold on kill.",
		"effect": "Bonus Gold Chance +%d%%", "max_level": 4, "effect_per_level": 25,
		"cost_mult": 3.0, "requires": "starting_gold",
	},
	{
		# 2026-07-10 user correction: was +50/level, now +10/level.
		"key": "team_hp", "name": "Fortified",
		"desc": "+10 max HP to all heroes at the start of every run per level.",
		"effect": "Team HP +%d", "max_level": 20, "effect_per_level": 10,
	},
	{
		"key": "hero_slots", "name": "Roster Expansion",
		"desc": "+1 hero you can field per level (stacks with your player level).",
		"effect": "Hero Slots: %d", "max_level": 5, "effect_per_level": 1,
	},
	{
		# Cheap half of the crystal pair (2026-07-16, mirrors Head Start/Bounty).
		"key": "crystal_per_round", "name": "Crystal Tithe",
		"desc": "+1 crystal after every round per level.",
		"effect": "Crystals / Round +%d", "max_level": 10, "effect_per_level": 1,
	},
	{
		# Expensive per-kill half, gated behind Crystal Tithe (2026-07-16).
		# Reworked 2026-07-31 (mirrors Bounty above): each level is an
		# INDEPENDENT 25% chance per kill to drop 1 extra crystal, decoupled
		# from the base per-enemy crystal drop rate. 4 levels so maxed = 100%.
		"key": "crystal_drop", "name": "Crystal Surge",
		"desc": "+25% independent chance per level to drop 1 extra crystal on kill.",
		"effect": "Bonus Crystal Chance +%d%%", "max_level": 4, "effect_per_level": 25,
		"cost_mult": 3.0, "requires": "crystal_per_round",
	},
	{
		# 2026-07-10: the 4 core root-branch upgrades are starting_gold/team_hp/
		# hero_slots/bonus_xp — crystal_drop above stays in the catalogue as a
		# regular (non-core) branch instead of being removed.
		"key": "bonus_xp", "name": "Quick Learner",
		"desc": "+25% XP earned by every hero from kills, per level.",
		"effect": "Bonus XP +%d%%", "max_level": 20, "effect_per_level": 25,
	},
	# ── Stat tree (2026-07-10) — one flat/percent bonus applied to every hero
	# at recruit time, same mechanism as team_hp above (see
	# main_game._apply_progression_bonuses). Numbers are a first pass, freely
	# invented per convention — tune after playtesting.
	{
		"key": "mana_well", "name": "Mana Well",
		"desc": "+10 max mana to all heroes per level.",
		"effect": "Max Mana +%d", "max_level": 20, "effect_per_level": 10,
	},
	{
		"key": "spellpower", "name": "Spellpower",
		"desc": "+2 magic power to all heroes per level.",
		"effect": "Magic Power +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "might", "name": "Might",
		"desc": "+2 attack damage to all heroes per level.",
		"effect": "Attack Damage +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		# 2026-07-16 defense split: Warding is the MAGIC armor node now (the
		# flavor fits); Bulwark below covers physical armor. Key kept for saves.
		"key": "warding", "name": "Warding",
		"desc": "+2 magic armor to all heroes per level.",
		"effect": "Magic Armor +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "bulwark", "name": "Bulwark",
		"desc": "+2 armor to all heroes per level.",
		"effect": "Armor +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "fleetfoot", "name": "Fleetfoot",
		"desc": "+0.02 attack speed to all heroes per level.",
		"effect": "Attack Speed +%.2f", "max_level": 20, "effect_per_level": 0.02, "is_float": true,
	},
	{
		"key": "vitality_flow", "name": "Vitality Flow",
		"desc": "+0.1 HP regen to all heroes per level.",
		"effect": "HP Regen +%.1f", "max_level": 20, "effect_per_level": 0.1, "is_float": true,
	},
	{
		"key": "mana_flow", "name": "Mana Flow",
		"desc": "+0.1 mana regen to all heroes per level.",
		"effect": "Mana Regen +%.1f", "max_level": 20, "effect_per_level": 0.1, "is_float": true,
	},
	{
		"key": "swiftness", "name": "Swiftness",
		"desc": "+1 movement speed to all heroes per level.",
		"effect": "Movement Speed +%d", "max_level": 5, "effect_per_level": 1,
	},
	{
		# Stored as whole percentage points (2 = 2%), divided by 100 wherever it's
		# actually applied to unit.crit_chance — keeps the shop display a plain
		# int like elemental_attunement below instead of a raw 0.02 fraction.
		"key": "lethality", "name": "Lethality",
		"desc": "+2% crit chance to all heroes per level.",
		"effect": "Crit Chance +%d%%", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "killing_blow", "name": "Killing Blow",
		"desc": "+5% crit damage to all heroes per level.",
		"effect": "Crit Damage +%d%%", "max_level": 20, "effect_per_level": 5,
	},
	# ── Hero unlocks (2026-08-01) ──────────────────────────────────────────────
	# One-shot (max_level 1) purchases that unlock a recruitable hero. 6 heroes
	# (one per element, see STARTER_HEROES below) start unlocked for free and
	# have no entry here. effect_per_level is unused (no numeric bonus) — the
	# unlock itself is read via is_hero_unlocked() checking upgrade_levels.
	{
		"key": "hero_unlock_pastor", "name": "Unlock Pastor",
		"desc": "Adds Pastor to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_coal", "name": "Unlock Coal",
		"desc": "Adds Coal to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_sear", "name": "Unlock Sear",
		"desc": "Adds Sear to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_ember", "name": "Unlock Ember",
		"desc": "Adds Ember to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_doc", "name": "Unlock Doc",
		"desc": "Adds Doc to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_reed", "name": "Unlock Reed",
		"desc": "Adds Reed to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_sheildor", "name": "Unlock Sheildor",
		"desc": "Adds Sheildor to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_june", "name": "Unlock June",
		"desc": "Adds June to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_spore", "name": "Unlock Spore",
		"desc": "Adds Spore to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_sable", "name": "Unlock Sable",
		"desc": "Adds Sable to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_lumen", "name": "Unlock Lumen",
		"desc": "Adds Lumen to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_vail", "name": "Unlock Vail",
		"desc": "Adds Vail to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_zolt", "name": "Unlock Zolt",
		"desc": "Adds Zolt to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_rush", "name": "Unlock Rush",
		"desc": "Adds Rush to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_lordee", "name": "Unlock Lordee",
		"desc": "Adds Lordee to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_necro", "name": "Unlock Necro",
		"desc": "Adds Necro to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_riot", "name": "Unlock Riot",
		"desc": "Adds Riot to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_stitch", "name": "Unlock Stitch",
		"desc": "Adds Stitch to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_cross", "name": "Unlock Cross",
		"desc": "Adds Cross to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	{
		"key": "hero_unlock_rift", "name": "Unlock Rift",
		"desc": "Adds Rift to the recruitment pool.",
		"effect": "Unlocked", "max_level": 1, "effect_per_level": 0,
	},
	# ── Run-start gold (2026-08-01 user spec) ──────────────────────────────────
	# Distinct from "starting_gold"/Head Start above (which despite its key
	# actually pays out every ROUND, not at run start — see that entry's
	# comment). This one is a literal flat bonus added once when a run begins
	# (see main_game.start_new_game()), 100 levels so it scales all the way to
	# +100 starting gold at max.
	{
		"key": "starting gold", "name": "Starting Gold",
		"desc": "+1 gold at the start of every run per level.",
		"effect": "Start Gold +%d", "max_level": 100, "effect_per_level": 1,
	},
	# ── Tier-2 stat tree (2026-08-01 user spec) ────────────────────────────────
	# Independent second copies of the original stat branch: each stacks
	# ADDITIONALLY on top of its tier-1 counterpart (both summed in
	# main_game._apply_progression_bonuses), not an extension of the same
	# track. Same numbers as tier 1, same reasoning — see those entries above.
	{
		"key": "team_hp_2", "name": "Fortified II",
		"desc": "+10 max HP to all heroes at the start of every run per level.",
		"effect": "Team HP +%d", "max_level": 20, "effect_per_level": 10,
	},
	{
		"key": "mana_well_2", "name": "Mana Well II",
		"desc": "+10 max mana to all heroes per level.",
		"effect": "Max Mana +%d", "max_level": 20, "effect_per_level": 10,
	},
	{
		"key": "might_2", "name": "Might II",
		"desc": "+2 attack damage to all heroes per level.",
		"effect": "Attack Damage +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "spellpower_2", "name": "Spellpower II",
		"desc": "+2 magic power to all heroes per level.",
		"effect": "Magic Power +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "warding_2", "name": "Warding II",
		"desc": "+2 magic armor to all heroes per level.",
		"effect": "Magic Armor +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "bulwark_2", "name": "Bulwark II",
		"desc": "+2 armor to all heroes per level.",
		"effect": "Armor +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "fleetfoot_2", "name": "Fleetfoot II",
		"desc": "+0.02 attack speed to all heroes per level.",
		"effect": "Attack Speed +%.2f", "max_level": 20, "effect_per_level": 0.02, "is_float": true,
	},
	{
		"key": "vitality_flow_2", "name": "Vitality Flow II",
		"desc": "+0.1 HP regen to all heroes per level.",
		"effect": "HP Regen +%.1f", "max_level": 20, "effect_per_level": 0.1, "is_float": true,
	},
	{
		"key": "mana_flow_2", "name": "Mana Flow II",
		"desc": "+0.1 mana regen to all heroes per level.",
		"effect": "Mana Regen +%.1f", "max_level": 20, "effect_per_level": 0.1, "is_float": true,
	},
	{
		"key": "swiftness_2", "name": "Swiftness II",
		"desc": "+1 movement speed to all heroes per level.",
		"effect": "Movement Speed +%d", "max_level": 5, "effect_per_level": 1,
	},
	{
		"key": "lethality_2", "name": "Lethality II",
		"desc": "+2% crit chance to all heroes per level.",
		"effect": "Crit Chance +%d%%", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "killing_blow_2", "name": "Killing Blow II",
		"desc": "+5% crit damage to all heroes per level.",
		"effect": "Crit Damage +%d%%", "max_level": 20, "effect_per_level": 5,
	},
	# ── Per-hero-level growth-rate upgrades (2026-08-01 user spec) ─────────────
	# Unlike everything above (a flat bonus applied once at recruit time), these
	# raise how much a hero gains EACH TIME THEY LEVEL UP in battle — see
	# UnitBase.stat_growth(), which now adds Progression.get_bonus_float() for
	# the matching key on top of the class's own growth_base/growth_bonus roll.
	# Small numbers are intentional: this compounds over every hero level, and
	# is explicitly meant to reward pushing heroes deep past the level cap
	# (see the max-level-cap family below) rather than being a flat power
	# spike on its own.
	{
		"key": "attack_per_level", "name": "Might Growth",
		"desc": "+0.1 attack growth per hero level-up, per level.",
		"effect": "Attack Growth +%.1f", "max_level": 20, "effect_per_level": 0.1, "is_float": true,
	},
	{
		"key": "spellpower_per_level", "name": "Spellpower Growth",
		"desc": "+0.1 magic power growth per hero level-up, per level.",
		"effect": "Magic Growth +%.1f", "max_level": 20, "effect_per_level": 0.1, "is_float": true,
	},
	{
		"key": "attack_speed_per_level", "name": "Fleetfoot Growth",
		"desc": "+0.002 attack speed growth per hero level-up, per level.",
		"effect": "Attack Speed Growth +%.3f", "max_level": 20, "effect_per_level": 0.002, "is_float": true,
	},
	{
		"key": "hp_regen_per_level", "name": "Vitality Flow Growth",
		"desc": "+0.01 HP regen growth per hero level-up, per level.",
		"effect": "HP Regen Growth +%.2f", "max_level": 20, "effect_per_level": 0.01, "is_float": true,
	},
	{
		"key": "mana regen per level", "name": "Mana Flow Growth",
		"desc": "+0.02 mana regen growth per hero level-up, per level.",
		"effect": "Mana Regen Growth +%.2f", "max_level": 20, "effect_per_level": 0.02, "is_float": true,
	},
	{
		"key": "health_per_level", "name": "Fortified Growth",
		"desc": "+1 max HP growth per hero level-up, per level.",
		"effect": "HP Growth +%.1f", "max_level": 20, "effect_per_level": 1.0, "is_float": true,
	},
	{
		"key": "mana_per_level", "name": "Mana Well Growth",
		"desc": "+1 max mana growth per hero level-up, per level.",
		"effect": "Mana Growth +%.1f", "max_level": 20, "effect_per_level": 1.0, "is_float": true,
	},
	{
		# 2026-08-02: crit chance/damage have NO innate per-class growth (see
		# UnitFactory.CLASS_GROWTH_PER_LEVEL — no "crit"/"critdmg" keys), so
		# this is a genuinely new growth source, not a boost to an existing one.
		"key": "crit_per_level", "name": "Lethality Growth",
		"desc": "+0.1% crit chance growth per hero level-up, per level.",
		"effect": "Crit Growth +%.3f", "max_level": 20, "effect_per_level": 0.001, "is_float": true,
	},
	{
		"key": "crit_dmg_per_lvl", "name": "Killing Blow Growth",
		"desc": "+0.5% crit damage growth per hero level-up, per level.",
		"effect": "Crit Dmg Growth +%.3f", "max_level": 20, "effect_per_level": 0.005, "is_float": true,
	},
	{
		# Physical armor (resistance) only — parented to Bulwark II in the tree,
		# not Warding II. Magic armor rides a separate growth bucket ("res",
		# shared with resistance's base class roll) that this does NOT touch,
		# so it doesn't silently buff magic armor growth too.
		"key": "armor_per_lvl", "name": "Bulwark Growth",
		"desc": "+0.1 armor growth per hero level-up, per level.",
		"effect": "Armor Growth +%.1f", "max_level": 20, "effect_per_level": 0.1, "is_float": true,
	},
	# ── Hero level cap (2026-08-01 user spec) ──────────────────────────────────
	# Base hero level cap is 10 (see HERO_LEVEL_CAP_BASE/hero_level_cap() below
	# and UnitBase.grant_xp()'s cap check) — heroes simply stop leveling once
	# they hit it. Each of these 7 nodes independently raises that cap by
	# +1/level, 5 levels each (35 max total), so a fully-invested run can push
	# the cap to 45. Seven separate purchase points (rather than one deep
	# track) so the cap rises gradually as you branch out across the tree,
	# same shape as the tier-2 stat family above.
	{
		"key": "max_level", "name": "Max Hero Level",
		"desc": "+1 max hero level per level.",
		"effect": "Hero Level Cap +%d", "max_level": 5, "effect_per_level": 1,
	},
	{
		"key": "max_level_2", "name": "Max Hero Level II",
		"desc": "+1 max hero level per level.",
		"effect": "Hero Level Cap +%d", "max_level": 5, "effect_per_level": 1,
	},
	{
		"key": "max_level_2_2", "name": "Max Hero Level III",
		"desc": "+1 max hero level per level.",
		"effect": "Hero Level Cap +%d", "max_level": 5, "effect_per_level": 1,
	},
	{
		"key": "max_level_2_2_2", "name": "Max Hero Level IV",
		"desc": "+1 max hero level per level.",
		"effect": "Hero Level Cap +%d", "max_level": 5, "effect_per_level": 1,
	},
	{
		"key": "max_level_2_3", "name": "Max Hero Level V",
		"desc": "+1 max hero level per level.",
		"effect": "Hero Level Cap +%d", "max_level": 5, "effect_per_level": 1,
	},
	{
		"key": "max_level_2_3_2", "name": "Max Hero Level VI",
		"desc": "+1 max hero level per level.",
		"effect": "Hero Level Cap +%d", "max_level": 5, "effect_per_level": 1,
	},
	{
		"key": "max_level_2_3_2_2", "name": "Max Hero Level VII",
		"desc": "+1 max hero level per level.",
		"effect": "Hero Level Cap +%d", "max_level": 5, "effect_per_level": 1,
	},
]

# Base hero level cap before any Max Hero Level purchases (2026-08-01 user
# spec: "there is no hero level cap [today]. we will make it 10"). Heroes
# cannot level past hero_level_cap() — see UnitBase.grant_xp()/set_level().
const HERO_LEVEL_CAP_BASE: int = 10

func hero_level_cap() -> int:
	# Every level-cap node (30 on the spokes, 10 in the web) feeds "max_level",
	# so this is one aggregated read rather than a hardcoded key list.
	return HERO_LEVEL_CAP_BASE + get_bonus("max_level")

# Heroes unlocked for free from the very start (no purchase, no tree node) —
# one per element so early runs have element variety. Checked directly in
# is_hero_unlocked() rather than seeded into upgrade_levels, so existing save
# files (with no hero_unlock_* keys at all) don't retroactively lock heroes a
# player has already been using.
const STARTER_HEROES: Array = [
	UnitBase.UnitClass.BLOODHOUND,  # earth
	UnitBase.UnitClass.SHAUNA,      # fire
	UnitBase.UnitClass.NEMI,        # water
	UnitBase.UnitClass.HEADHUNTER,  # air
	UnitBase.UnitClass.STATIC,        # lightning
	UnitBase.UnitClass.BOUNCER,     # normal
]

# UnitClass -> hero_unlock_* upgrade key, for every hero NOT in STARTER_HEROES.
const HERO_UNLOCK_KEYS: Dictionary = {
	UnitBase.UnitClass.PASTOR:   "hero_unlock_pastor",
	UnitBase.UnitClass.COAL:     "hero_unlock_coal",
	UnitBase.UnitClass.SEAR:     "hero_unlock_sear",
	UnitBase.UnitClass.EMBER:    "hero_unlock_ember",
	UnitBase.UnitClass.DOC:      "hero_unlock_doc",
	UnitBase.UnitClass.REED:     "hero_unlock_reed",
	UnitBase.UnitClass.SHEILDOR: "hero_unlock_sheildor",
	UnitBase.UnitClass.JUNE:     "hero_unlock_june",
	UnitBase.UnitClass.SPORE:    "hero_unlock_spore",
	UnitBase.UnitClass.SABLE:    "hero_unlock_sable",
	UnitBase.UnitClass.LUMEN:    "hero_unlock_lumen",
	UnitBase.UnitClass.VAIL:     "hero_unlock_vail",
	UnitBase.UnitClass.ZOLT:     "hero_unlock_zolt",
	UnitBase.UnitClass.RUSH:   "hero_unlock_rush",
	UnitBase.UnitClass.LORDEE:   "hero_unlock_lordee",
	UnitBase.UnitClass.NECRO:    "hero_unlock_necro",
	UnitBase.UnitClass.RIOT:     "hero_unlock_riot",
	UnitBase.UnitClass.STITCH:   "hero_unlock_stitch",
	UnitBase.UnitClass.CROSS:    "hero_unlock_cross",
	UnitBase.UnitClass.RIFT:     "hero_unlock_rift",
}

# True if this class can appear in hero recruitment: a starter hero, or an
# hero_unlock_* upgrade has been bought (level >= 1).
func is_hero_unlocked(unit_class) -> bool:
	if unit_class in STARTER_HEROES:
		return true
	var key: String = HERO_UNLOCK_KEYS.get(unit_class, "")
	return key != "" and get_level(key) >= 1

# Per-node overrides from data/crystal_tree.json (2026-07-31: max_level;
# 2026-08-01: name/desc), so node depth AND wording are tunable from the F9
# tree editor instead of requiring a script edit. Empty = every upgrade uses
# its catalogue value above.
var _max_level_overrides: Dictionary = {}
var _name_overrides: Dictionary = {}
var _desc_overrides: Dictionary = {}

# ── Generated catalogue (2026-08-03) ──────────────────────────────────────────
# The crystal tree grew from ~70 upgrades to ~600, because multi-level upgrades
# were split into one-level picks (see tools/crystal_tree/). Hand-authoring that
# many const entries is not viable, so the generated half lives in a data file
# and is merged in at boot; a generated entry wins over a hand-authored one with
# the same key, which is how the split versions replace their originals.
#
# Splitting broke the read path: the game asks get_bonus("might"), which used to
# be one upgrade and is now fourteen nodes. Each generated entry therefore
# carries "feeds": the base key it contributes to. get_bonus() sums the base
# key's own level plus every feeder's, so no call site had to change.
const GENERATED_PATH := "res://data/crystal_upgrades.json"

var _catalogue: Array = []          # UPGRADES + generated, merged
var _by_key: Dictionary = {}        # key -> upgrade dict (replaces a linear scan)
var _feeders: Dictionary = {}       # base key -> Array of upgrade dicts

func _ready() -> void:
	_build_catalogue()
	load_data()
	reload_tree_overrides()

func _build_catalogue() -> void:
	_catalogue = []
	_index = {}
	_by_key = {}
	_feeders = {}
	for u in UPGRADES:
		_add_to_catalogue(u)
	if FileAccess.file_exists(GENERATED_PATH):
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(GENERATED_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			for raw: Variant in (parsed as Dictionary).get("upgrades", []):
				if typeof(raw) == TYPE_DICTIONARY:
					_add_to_catalogue(raw)
		else:
			push_error("Progression: %s is not valid JSON — generated upgrades skipped."
				% GENERATED_PATH)
	# Feeder index is built last so it can't be stale after a key replacement.
	for u in _catalogue:
		var feeds := String(u.get("feeds", ""))
		if feeds != "":
			if not _feeders.has(feeds):
				_feeders[feeds] = []
			(_feeders[feeds] as Array).append(u)

var _index: Dictionary = {}         # key -> position in _catalogue

func _add_to_catalogue(u: Dictionary) -> void:
	var key := String(u.get("key", ""))
	if key == "":
		return
	if _index.has(key):
		# Same key from both halves: the generated one replaces the authored one
		# IN PLACE, so ordering (and therefore shop layout) is preserved. The
		# position is tracked explicitly rather than searched for — Array.find()
		# on dictionaries compares by reference and a miss would return -1,
		# which would silently overwrite the last entry instead.
		_catalogue[int(_index[key])] = u
	else:
		_index[key] = _catalogue.size()
		_catalogue.append(u)
	_by_key[key] = u

# Re-read overrides from the tree data file. Called at boot, and again by the
# tree editor after it changes a value so the shop updates without a restart.
func reload_tree_overrides() -> void:
	apply_tree_overrides(CrystalTree.load_from_disk())

func apply_tree_overrides(tree: CrystalTree) -> void:
	var o := tree.overrides()
	_max_level_overrides = o["max_level"]
	_name_overrides = o["name"]
	_desc_overrides = o["desc"]

# ── Public API ────────────────────────────────────────────────────────────────

func get_level(key: String) -> int:
	return upgrade_levels.get(key, 0)

# How many crystal-tree LEVELS the player currently owns (2026-08-03, balance
# baseline instrumentation — see BALANCE_PLAN.md). Nearly every node in the
# generated tree is max_level 1, so this is effectively "nodes owned", but it
# sums levels rather than counting keys so the handful of multi-level
# hand-authored nodes still count honestly. This is the x-axis of the whole
# balance pass: death wave is fitted against THIS number.
func nodes_owned() -> int:
	var total := 0
	for lvl: Variant in upgrade_levels.values():
		total += int(lvl)
	return total

# Every upgrade the game knows about: the hand-authored UPGRADES above plus the
# generated entries loaded from GENERATED_PATH. Iterate this, not UPGRADES.
func catalogue() -> Array:
	return _catalogue

func upgrade_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for u in _catalogue:
		out.append(String(u["key"]))
	return out

# Effective max level: the tree's override if it has one, else the catalogue's.
# Read this instead of upgrade["max_level"] anywhere it affects play.
func max_level(key: String) -> int:
	if _max_level_overrides.has(key):
		return int(_max_level_overrides[key])
	var upgrade := _find(key)
	return int(upgrade["max_level"]) if upgrade.has("max_level") else 0

# Effective display name/desc: the tree's override if it has one, else the
# catalogue's. Read these instead of upgrade["name"]/["desc"] anywhere the
# player sees them (shop detail bar, tooltips) so an editor edit shows up
# without a script change.
func display_name(key: String) -> String:
	if _name_overrides.has(key):
		return String(_name_overrides[key])
	var upgrade := _find(key)
	return String(upgrade.get("name", key))

func display_desc(key: String) -> String:
	if _desc_overrides.has(key):
		return String(_desc_overrides[key])
	var upgrade := _find(key)
	return String(upgrade.get("desc", ""))

# Cost to purchase the next level of an upgrade (returns -1 if already maxed)
func next_cost(key: String) -> int:
	var lvl := get_level(key)
	var upgrade := _find(key)
	if upgrade.is_empty() or lvl >= max_level(key):
		return -1
	# Exponential curve: base 10, multiplier 1.255, caps near 750 at level 19
	# Lv0→1: 10c  |  Lv4→5: 25c  |  Lv9→10: 77c  |  Lv14→15: 240c  |  Lv19→20: 749c
	# cost_mult scales the whole curve for premium nodes (per-kill economy pair).
	return roundi(10.0 * pow(1.255, lvl) * float(upgrade.get("cost_mult", 1.0)))

# Hard prerequisite gate (2026-07-16): an upgrade with a "requires" key can't
# be bought until that prerequisite has at least 1 level.
func is_locked(key: String) -> bool:
	var req: String = _find(key).get("requires", "")
	return req != "" and get_level(req) == 0

func can_afford(key: String) -> bool:
	if is_locked(key):
		return false
	var cost := next_cost(key)
	return cost > 0 and crystals >= cost

func buy(key: String) -> bool:
	if not can_afford(key):
		return false
	crystals -= next_cost(key)
	upgrade_levels[key] = get_level(key) + 1
	save_data()
	return true

# Total crystals ever spent on current upgrade levels — replays the exact
# cost curve (incl. per-node cost_mult) so a reset refunds to the crystal.
func total_spent() -> int:
	var spent := 0
	for u in _catalogue:
		var mult: float = float(u.get("cost_mult", 1.0))
		for lvl in range(get_level(u["key"])):
			spent += roundi(10.0 * pow(1.255, lvl) * mult)
	return spent

# Full respec (2026-07-17 user request): wipe every upgrade level and refund
# every crystal spent. Returns the refund amount for UI feedback.
func reset_all() -> int:
	var refund := total_spent()
	upgrade_levels.clear()
	crystals += refund
	save_data()
	return refund

func add_crystals(amount: int) -> void:
	if amount <= 0:
		return
	crystals += amount
	save_data()

# Returns the total bonus value for an upgrade (level × per_level), as an int.
# Only use this for int-typed stats — for anything marked "is_float": true in
# the catalogue (attack_speed/regen/crit/etc.), use get_bonus_float() instead,
# since this truncates to int.
func get_bonus(key: String) -> int:
	return int(get_bonus_float(key))

# Float-precision version for small per-level increments (attack_speed,
# hp_regen/mana_regen, crit_chance/crit_damage) where int() truncation would
# zero out a sub-1.0 effect_per_level.
func get_bonus_float(key: String) -> float:
	var total := 0.0
	# The base key contributes only if it isn't itself a feeder for someone
	# else — otherwise a node that both exists and feeds would count twice.
	var upgrade := _find(key)
	if not upgrade.is_empty() and String(upgrade.get("feeds", "")) == "":
		total += float(get_level(key)) * float(upgrade["effect_per_level"])
	for u in (_feeders.get(key, []) as Array):
		total += float(get_level(String(u["key"]))) * float(u["effect_per_level"])
	return total

# ── Persistence ───────────────────────────────────────────────────────────────

func save_data() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify({
		"crystals":        crystals,
		"upgrade_levels":  upgrade_levels,
	}))

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	crystals        = int(parsed.get("crystals", 0))
	upgrade_levels  = parsed.get("upgrade_levels", {})

func _find(key: String) -> Dictionary:
	return _by_key.get(key, {})
