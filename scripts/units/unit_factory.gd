extends Node
class_name UnitFactory

# Icon per stat key — shared so any UI (recruit card, level-up perks, unit
# details) can show a consistent icon next to a stat without duplicating paths.
# Only the 10 stats we currently use have icons; more get added as they arrive
# in assets/icons/stat_icons/ (see MEMORY.md / conversation for the full list).
const STAT_ICONS: Dictionary = {
	"hp":        "res://assets/icons/stat_icons/health.png",
	"mana":      "res://assets/icons/stat_icons/mana.png",
	"atk":       "res://assets/icons/stat_icons/attack_power.png",
	"magic":     "res://assets/icons/stat_icons/magic_dmg.png",
	"res":       "res://assets/icons/stat_icons/defense.png",
	"mres":      "res://assets/icons/stat_icons/defense.png",   # shared art until a magic-armor icon lands
	"ten":       "res://assets/icons/stat_icons/defense.png",   # ditto — stand-in until a tenacity icon lands
	"aspd":      "res://assets/icons/stat_icons/attack_speed.png",
	"hpregen":   "res://assets/icons/stat_icons/hp_regen.png",
	"manaregen": "res://assets/icons/stat_icons/mp_regen.png",
	"move":      "res://assets/icons/stat_icons/movement_speed.png",
	"range":     "res://assets/icons/stat_icons/range.png",
	"crit_chance": "res://assets/icons/stat_icons/critical_rate.png",
	"crit_damage": "res://assets/icons/stat_icons/critical_dmg.png",
}

# Display name per stat key — shown as a tooltip on the stat's icon in the
# Unit Details panel (see main_game.gd _ensure_details_icons).
const STAT_NAMES: Dictionary = {
	"hp":        "Max HP",
	"mana":      "Max Mana",
	"atk":       "Attack Damage",
	"magic":     "Magic Power",
	"res":       "Armor",
	"mres":      "Magic Armor",
	"ten":       "Tenacity — shortens stun/root/taunt/slow (100/(100+TEN)); never blocks them outright",
	"aspd":      "Attack Speed",
	"hpregen":   "HP Regen",
	"manaregen": "MP Regen",
	"move":      "Movement Speed",
	"range":     "Attack Range",
	"crit_chance": "Crit Chance",
	"crit_damage": "Crit Damage",
}

# Element glyph per Element enum — hand-made set, backgrounds removed via the
# sprite pipeline (assets/icons/glyphts/clean/). Used by the Unit Details
# affinity matrix + element chip.
const ELEMENT_ICONS: Dictionary = {
	UnitBase.Element.NORMAL:    "res://assets/icons/glyphts/clean/element_normal.png",
	UnitBase.Element.FIRE:      "res://assets/icons/glyphts/clean/element_fire.png",
	UnitBase.Element.WATER:     "res://assets/icons/glyphts/clean/element_water.png",
	UnitBase.Element.EARTH:     "res://assets/icons/glyphts/clean/element_earth.png",
	UnitBase.Element.AIR:       "res://assets/icons/glyphts/clean/element_air.png",
	UnitBase.Element.LIGHTNING: "res://assets/icons/glyphts/clean/element_lightning.png",
}

# Trait class mapping (for synergies)
const TRAIT_CLASS_MAP = {
	UnitBase.UnitClass.BLOODHOUND: UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.BOUNCER:    UnitBase.TraitClass.TANK,
	UnitBase.UnitClass.HEADHUNTER: UnitBase.TraitClass.RANGED,
	UnitBase.UnitClass.SHAUNA:     UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.NEMI:       UnitBase.TraitClass.MAGE,
	UnitBase.UnitClass.SHEILDOR:   UnitBase.TraitClass.TANK,
	UnitBase.UnitClass.LORDEE:     UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.NECRO:      UnitBase.TraitClass.SUMMONER,
	# ── Roster expansion (design role → nearest synergy trait) ──
	UnitBase.UnitClass.DOC:        UnitBase.TraitClass.HEALER,   # Support
	UnitBase.UnitClass.RIOT:       UnitBase.TraitClass.TANK,     # Tank
	UnitBase.UnitClass.PASTOR:     UnitBase.TraitClass.MAGE,     # Support/Disruptor
	UnitBase.UnitClass.SABLE:      UnitBase.TraitClass.RANGED,   # Ranged Carry
	UnitBase.UnitClass.RUSH:       UnitBase.TraitClass.FIGHTER,  # Fighter
	UnitBase.UnitClass.STITCH:     UnitBase.TraitClass.MAGE,     # Disruptor
	UnitBase.UnitClass.COAL:       UnitBase.TraitClass.FIGHTER,  # Fighter
	UnitBase.UnitClass.JUNE:       UnitBase.TraitClass.HEALER,   # Support
	UnitBase.UnitClass.CROSS:      UnitBase.TraitClass.TANK,     # Tank
	UnitBase.UnitClass.SEAR:      UnitBase.TraitClass.MAGE,     # Magic Fighter
	UnitBase.UnitClass.EMBER:      UnitBase.TraitClass.RANGED,   # Ranged Carry
	UnitBase.UnitClass.RIFT:       UnitBase.TraitClass.MAGE,     # Magic Fighter
	UnitBase.UnitClass.ZOLT:       UnitBase.TraitClass.MAGE,     # Magic Carry
	UnitBase.UnitClass.LUMEN:      UnitBase.TraitClass.MAGE,     # Magic Carry
	UnitBase.UnitClass.STATIC:     UnitBase.TraitClass.MAGE,     # Disruptor
	UnitBase.UnitClass.REED:       UnitBase.TraitClass.HEALER,   # Support
	UnitBase.UnitClass.VAIL:       UnitBase.TraitClass.HEALER,   # Support
	UnitBase.UnitClass.SPORE:      UnitBase.TraitClass.MAGE,     # Magic Carry
	UnitBase.UnitClass.ZOMBIE:     UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.BAT:        UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.ANT:        UnitBase.TraitClass.FIGHTER,
}

# Natural aspect: the element that best scales each hero's kit, and — since the
# 2026-07-31 rework — the element that hero simply IS. The random recruitment
# roll is gone: shops offer every hero at its natural aspect (see
# element_for_class), so element synergies are drafted toward on purpose rather
# than prayed for. natural_aspect() therefore returns the matched multiplier for
# every player hero; it still discriminates for enemy/summon units, which inherit
# their spawner's element and can legitimately run off-aspect.
# Void-themed heroes have no matching element, so they home to NORMAL.
const NATURAL_ASPECT = {
	UnitBase.UnitClass.BOUNCER:    UnitBase.Element.NORMAL,
	UnitBase.UnitClass.HEADHUNTER: UnitBase.Element.AIR,
	UnitBase.UnitClass.SHAUNA:     UnitBase.Element.FIRE,
	UnitBase.UnitClass.NEMI:       UnitBase.Element.WATER,
	UnitBase.UnitClass.BLOODHOUND: UnitBase.Element.EARTH,
	UnitBase.UnitClass.SHEILDOR:   UnitBase.Element.EARTH,
	UnitBase.UnitClass.LORDEE:     UnitBase.Element.NORMAL,
	UnitBase.UnitClass.NECRO:      UnitBase.Element.NORMAL,
	UnitBase.UnitClass.DOC:        UnitBase.Element.WATER,
	# Riot moved Normal -> Lightning on 2026-09-18 with his pig-officer redesign:
	# the spiked bat became a taser baton. Everything downstream reads
	# current_element, so synergy counts, affinity ratings, element particles and
	# the element icon all follow from this one line. The crystal tree does NOT —
	# his unlock node lives in a spoke's `heroes` list, see gen_crystal_tree.py.
	UnitBase.UnitClass.RIOT:       UnitBase.Element.LIGHTNING,
	UnitBase.UnitClass.PASTOR:     UnitBase.Element.FIRE,
	UnitBase.UnitClass.SABLE:      UnitBase.Element.AIR,
	UnitBase.UnitClass.RUSH:       UnitBase.Element.LIGHTNING,
	UnitBase.UnitClass.STITCH:     UnitBase.Element.NORMAL,
	UnitBase.UnitClass.COAL:       UnitBase.Element.FIRE,
	UnitBase.UnitClass.JUNE:       UnitBase.Element.EARTH,
	UnitBase.UnitClass.CROSS:      UnitBase.Element.NORMAL,
	UnitBase.UnitClass.SEAR:      UnitBase.Element.FIRE,
	UnitBase.UnitClass.EMBER:      UnitBase.Element.FIRE,
	UnitBase.UnitClass.RIFT:       UnitBase.Element.LIGHTNING,
	UnitBase.UnitClass.ZOLT:       UnitBase.Element.LIGHTNING,
	UnitBase.UnitClass.LUMEN:      UnitBase.Element.LIGHTNING,
	UnitBase.UnitClass.STATIC:     UnitBase.Element.LIGHTNING,
	UnitBase.UnitClass.REED:       UnitBase.Element.WATER,
	UnitBase.UnitClass.VAIL:       UnitBase.Element.AIR,
	UnitBase.UnitClass.SPORE:      UnitBase.Element.EARTH,
}

# The element a hero is offered/recruited at. Single source of truth for every
# player-facing hero roll — shops must call this instead of picking at random.
static func element_for_class(cls: UnitBase.UnitClass) -> UnitBase.Element:
	return NATURAL_ASPECT.get(cls, UnitBase.Element.NORMAL)

# 1.0 normally; matched natural aspect grants +15% kit magnitude (no off-aspect penalty).
static func natural_aspect(unit: UnitBase) -> float:
	if NATURAL_ASPECT.get(unit.unit_class, UnitBase.Element.NORMAL) == unit.current_element:
		# Base +15%, plus the Elemental Attunement meta-upgrade (read live, not
		# applied at recruit time, since this is a multiplier recomputed on
		# every call rather than a stored base stat — 2026-07-10).
		return 1.15 + float(Progression.get_bonus("elemental_attunement")) / 100.0
	return 1.0

# Base stats for each class at level 1 (TFT-style independent stats)
const CLASS_BASE_STATS = {
	# magic 10 -> 20 (2026-08-03): his kit now reads magic_power instead of
	# attack_damage (user request), so his MAG line is mirrored onto his ATK line
	# — same base, same per-level growth. That makes the stat swap exactly
	# power-neutral at every level instead of a 50% ability nerf, and it means
	# MAG is finally a live pick for him on the level-up screen. Autos still use
	# ATK, so both stats do real work. See AbilityFormulas C.BLOODHOUND.
	UnitBase.UnitClass.BLOODHOUND: { "hp":1100,"mana":400, "atk":20,"magic":20,"res":20,"aspd":0.74,"hpregen":0.5,"manaregen":2.0, "move":3,"range":1, "off_affinity":135.0,"def_affinity":80.0 },
	UnitBase.UnitClass.BOUNCER: { "hp":1300,"mana":600, "atk":11,"magic":18,"res":22,"aspd":0.62,"hpregen":0.5,"manaregen":4.67, "move":2,"range":0, "off_affinity":130.0,"def_affinity":74.0 },
	# Balance 2026-07-03: HEADHUNTER atk 24→23, SABLE atk 21→20, RUSH atk 24→22,
	# NEMI magic 19→21 — arena sweep + user playtests: the first three top the
	# damage board (their base stats over-fit their kits), Nemi underperforms
	# even for a support. ZOMBIE/BAT summon stats buffed (melted instantly,
	# making Necro's whole kit weak: 183 solo dmg, worst-3 in roster).
	UnitBase.UnitClass.HEADHUNTER: { "hp":600,"mana":350, "atk":23,"magic":16,"res":11,"aspd":0.9,"hpregen":0.47,"manaregen":2.83, "move":3,"range":6, "off_affinity":155.0,"def_affinity":93.0 },
	UnitBase.UnitClass.SHAUNA: { "hp":700,"mana":400, "atk":22,"magic":11,"res":12,"aspd":0.9,"hpregen":0.45,"manaregen":2.33, "move":3,"range":5, "off_affinity":150.0,"def_affinity":93.0 },
	UnitBase.UnitClass.NEMI: { "hp":750,"mana":600, "atk":16,"magic":26,"res":16,"aspd":0.7,"hpregen":0.6,"manaregen":6.0, "move":2,"range":4, "off_affinity":135.0,"def_affinity":83.0 },
	UnitBase.UnitClass.SHEILDOR: { "hp":1400,"mana":700, "atk":14,"magic":17,"res":24,"aspd":0.66,"hpregen":0.6,"manaregen":4.67, "move":2,"range":1, "off_affinity":120.0,"def_affinity":71.0 },
	UnitBase.UnitClass.LORDEE: { "hp":950,"mana":500, "atk":23,"magic":14,"res":16,"aspd":0.78,"hpregen":0.6,"manaregen":3.0, "move":3,"range":1, "off_affinity":145.0,"def_affinity":87.0 },
	UnitBase.UnitClass.NECRO: { "hp":800,"mana":900, "atk":8,"magic":21,"res":14,"aspd":0.64,"hpregen":0.53,"manaregen":6.0, "move":2,"range":4, "off_affinity":130.0,"def_affinity":87.0 },
	UnitBase.UnitClass.DOC: { "hp":850,"mana":750, "atk":10,"magic":17,"res":15,"aspd":0.68,"hpregen":0.6,"manaregen":5.67, "move":3,"range":3, "off_affinity":130.0,"def_affinity":83.0 },
	UnitBase.UnitClass.RIOT: { "hp":1500,"mana":500, "atk":14,"magic":11,"res":26,"aspd":0.64,"hpregen":0.47,"manaregen":2.67, "move":2,"range":1, "off_affinity":120.0,"def_affinity":71.0 },
	UnitBase.UnitClass.PASTOR: { "hp":900,"mana":650, "atk":12,"magic":17,"res":17,"aspd":0.68,"hpregen":0.53,"manaregen":4.67, "move":2,"range":3, "off_affinity":140.0,"def_affinity":83.0 },
	UnitBase.UnitClass.SABLE: { "hp":650,"mana":350, "atk":20,"magic":12,"res":12,"aspd":0.88,"hpregen":0.45,"manaregen":2.5, "move":3,"range":6, "off_affinity":155.0,"def_affinity":93.0 },
	UnitBase.UnitClass.RUSH: { "hp":820,"mana":300, "atk":22,"magic":11,"res":14,"aspd":0.86,"hpregen":0.53,"manaregen":2.17, "move":15,"range":1, "off_affinity":145.0,"def_affinity":91.0 },
	UnitBase.UnitClass.STITCH: { "hp":780,"mana":700, "atk":13,"magic":18,"res":15,"aspd":0.74,"hpregen":0.47,"manaregen":4.67, "move":2,"range":2, "off_affinity":140.0,"def_affinity":87.0 },
	UnitBase.UnitClass.COAL: { "hp":1150,"mana":350, "atk":22,"magic":13,"res":19,"aspd":0.72,"hpregen":0.57,"manaregen":2.33, "move":3,"range":1, "off_affinity":145.0,"def_affinity":83.0 },
	UnitBase.UnitClass.JUNE: { "hp":880,"mana":700, "atk":10,"magic":15,"res":16,"aspd":0.68,"hpregen":0.57,"manaregen":5.17, "move":2,"range":1, "off_affinity":130.0,"def_affinity":82.0 },
	# Balance 2026-07-24: hp 1450->1300, res 24->20 — Cross was sitting at
	# roughly Sheildor/Riot's HP+armor tier (1400/1400 hp, 24/26 res) while
	# ALSO being the only tank with a lifesteal-off-all-damage passive
	# (Penance). Same stat budget as peer tanks + a strictly-better kit made
	# him strictly better than them; now he's the squishiest of the three,
	# paying for Penance/Judgment with lower raw bulk. See auto_battle_manager
	# _cross_judgment/Penance comments for the kit-side half of this fix.
	UnitBase.UnitClass.CROSS: { "hp":1300,"mana":550, "atk":15,"magic":13,"res":20,"aspd":0.64,"hpregen":0.6,"manaregen":3.67, "move":2,"range":1, "off_affinity":125.0,"def_affinity":72.0 },
	UnitBase.UnitClass.SEAR: { "hp":900,"mana":600, "atk":18,"magic":19,"res":16,"aspd":0.7,"hpregen":0.55,"manaregen":4.17, "move":3,"range":2, "off_affinity":150.0,"def_affinity":87.0 },
	UnitBase.UnitClass.EMBER: { "hp":640,"mana":400, "atk":19,"magic":16,"res":12,"aspd":0.86,"hpregen":0.42,"manaregen":3.33, "move":3,"range":5, "off_affinity":155.0,"def_affinity":93.0 },
	UnitBase.UnitClass.RIFT: { "hp":950,"mana":650, "atk":17,"magic":19,"res":18,"aspd":0.7,"hpregen":0.53,"manaregen":4.17, "move":3,"range":2, "off_affinity":145.0,"def_affinity":82.0 },
	UnitBase.UnitClass.ZOLT: { "hp":720,"mana":850, "atk":9,"magic":21,"res":14,"aspd":0.68,"hpregen":0.5,"manaregen":5.83, "move":2,"range":5, "off_affinity":160.0,"def_affinity":89.0 },
	UnitBase.UnitClass.LUMEN: { "hp":700,"mana":800, "atk":10,"magic":20,"res":13,"aspd":0.72,"hpregen":0.45,"manaregen":5.33, "move":2,"range":5, "off_affinity":158.0,"def_affinity":91.0 },
	UnitBase.UnitClass.STATIC: { "hp":820,"mana":700, "atk":12,"magic":18,"res":16,"aspd":0.72,"hpregen":0.47,"manaregen":4.67, "move":2,"range":3, "off_affinity":145.0,"def_affinity":85.0 },
	UnitBase.UnitClass.REED: { "hp":860,"mana":780, "atk":10,"magic":16,"res":17,"aspd":0.66,"hpregen":0.6,"manaregen":5.5, "move":2,"range":4, "off_affinity":130.0,"def_affinity":80.0 },
	UnitBase.UnitClass.VAIL: { "hp":820,"mana":780, "atk":11,"magic":16,"res":15,"aspd":0.7,"hpregen":0.6,"manaregen":5.5, "move":3,"range":4, "off_affinity":130.0,"def_affinity":85.0 },
	UnitBase.UnitClass.SPORE: { "hp":780,"mana":820, "atk":9,"magic":20,"res":15,"aspd":0.68,"hpregen":0.47,"manaregen":5.5, "move":2,"range":2, "off_affinity":150.0,"def_affinity":85.0 },
	UnitBase.UnitClass.ZOMBIE: { "hp":110,"mana":0, "atk":10,"magic":2,"res":5,"aspd":0.58,"hpregen":0.17,"manaregen":0.33, "move":2,"range":1, "off_affinity":120.0,"def_affinity":91.0 },
	UnitBase.UnitClass.BAT: { "hp":70,"mana":0, "atk":9,"magic":2,"res":3,"aspd":0.7,"hpregen":0.12,"manaregen":0.33, "move":4,"range":1, "off_affinity":120.0,"def_affinity":95.0 },
	# Ant (2026-07-15): only the round-15 Ant Hill spawns these (always level 1,
	# no set_level — see _spawn_ant), so this base row IS the round-15 statline.
	UnitBase.UnitClass.ANT: { "hp":400,"mana":0, "atk":50,"magic":0,"res":1,"aspd":0.9,"hpregen":0.0,"manaregen":0.0, "move":6,"range":1, "off_affinity":115.0,"def_affinity":95.0 },
}

# Deterministic per-level growth, same for every unit of a class (the "base
# growth" every hero/enemy of that class always gets on level-up, on top of
# their personalized growth_bonus rolled at recruit — see apply_recruit_rolls).
const CLASS_GROWTH_PER_LEVEL = {
	# magic 0 -> 2, matching atk (2026-08-03): his abilities scale off MAG now, so
	# without magic growth they would flatline the moment he leveled. See the
	# CLASS_BASE_STATS comment above.
	UnitBase.UnitClass.BLOODHOUND: {"hp":44,"mana":0,"atk":2,"magic":2,"res":5,"aspd":0.02,"hpregen":0.1,"manaregen":0.333},
	UnitBase.UnitClass.BOUNCER: {"hp":56,"mana":0,"atk":1,"magic":2,"res":5,"aspd":0.02,"hpregen":0.05,"manaregen":0.667},
	UnitBase.UnitClass.HEADHUNTER: {"hp":20,"mana":0,"atk":2,"magic":0,"res":4,"aspd":0.02,"hpregen":0.05,"manaregen":0.167},
	UnitBase.UnitClass.SHAUNA: {"hp":24,"mana":0,"atk":2,"magic":0,"res":4,"aspd":0.02,"hpregen":0.075,"manaregen":0.333},
	UnitBase.UnitClass.NEMI: {"hp":28,"mana":20,"atk":1,"magic":3,"res":4,"aspd":0.02,"hpregen":0.075,"manaregen":1.0},
	UnitBase.UnitClass.SHEILDOR: {"hp":36,"mana":15,"atk":1,"magic":2,"res":5,"aspd":0.02,"hpregen":0.075,"manaregen":0.833},
	UnitBase.UnitClass.LORDEE: {"hp":44,"mana":12,"atk":1,"magic":3,"res":5,"aspd":0.02,"hpregen":0.025,"manaregen":0.667},
	UnitBase.UnitClass.NECRO: {"hp":20,"mana":25,"atk":1,"magic":4,"res":4,"aspd":0.02,"hpregen":0.075,"manaregen":1.167},
	UnitBase.UnitClass.DOC: {"hp":28,"mana":20,"atk":1,"magic":3,"res":4,"aspd":0.02,"hpregen":0.1,"manaregen":1.167},
	UnitBase.UnitClass.RIOT: {"hp":40,"mana":0,"atk":2,"magic":0,"res":6,"aspd":0.02,"hpregen":0.075,"manaregen":0.167},
	UnitBase.UnitClass.PASTOR: {"hp":28,"mana":18,"atk":1,"magic":3,"res":4,"aspd":0.02,"hpregen":0.075,"manaregen":1.0},
	UnitBase.UnitClass.SABLE: {"hp":22,"mana":0,"atk":3,"magic":0,"res":4,"aspd":0.02,"hpregen":0.075,"manaregen":0.167},
	UnitBase.UnitClass.RUSH: {"hp":28,"mana":0,"atk":3,"magic":0,"res":4,"aspd":0.02,"hpregen":0.075,"manaregen":0.167},
	UnitBase.UnitClass.STITCH: {"hp":26,"mana":18,"atk":1,"magic":3,"res":4,"aspd":0.02,"hpregen":0.025,"manaregen":0.667},
	UnitBase.UnitClass.COAL: {"hp":44,"mana":0,"atk":3,"magic":0,"res":4,"aspd":0.02,"hpregen":0.1,"manaregen":0.167},
	UnitBase.UnitClass.JUNE: {"hp":32,"mana":18,"atk":1,"magic":2,"res":4,"aspd":0.02,"hpregen":0.1,"manaregen":1.0},
	# Balance 2026-07-24: growth trimmed to match RIOT (his closest stat-twin —
	# identical hp/res/atk/aspd growth) instead of exceeding it: hpregen
	# 0.1->0.075, manaregen 0.333->0.167, res growth 6->5. Cross's hp_regen
	# and mana_regen growth used to OUTPACE Riot's despite Cross alone having
	# Penance (heals off all damage taken) — a tank shouldn't out-sustain the
	# roster's dedicated CC tank on raw regen AND have a unique heal passive.
	UnitBase.UnitClass.CROSS: {"hp":60,"mana":0,"atk":2,"magic":0,"res":5,"aspd":0.02,"hpregen":0.075,"manaregen":0.167},
	UnitBase.UnitClass.SEAR: {"hp":32,"mana":16,"atk":2,"magic":3,"res":4,"aspd":0.02,"hpregen":0.075,"manaregen":0.667},
	UnitBase.UnitClass.EMBER: {"hp":22,"mana":0,"atk":1,"magic":2,"res":4,"aspd":0.02,"hpregen":0.025,"manaregen":0.5},
	UnitBase.UnitClass.RIFT: {"hp":34,"mana":16,"atk":1,"magic":3,"res":4,"aspd":0.02,"hpregen":0.025,"manaregen":0.667},
	UnitBase.UnitClass.ZOLT: {"hp":20,"mana":24,"atk":1,"magic":4,"res":4,"aspd":0.02,"hpregen":0.075,"manaregen":1.167},
	UnitBase.UnitClass.LUMEN: {"hp":20,"mana":22,"atk":1,"magic":4,"res":4,"aspd":0.02,"hpregen":0.025,"manaregen":0.833},
	UnitBase.UnitClass.STATIC: {"hp":26,"mana":18,"atk":1,"magic":3,"res":4,"aspd":0.02,"hpregen":0.025,"manaregen":0.667},
	UnitBase.UnitClass.REED: {"hp":30,"mana":20,"atk":1,"magic":2,"res":4,"aspd":0.02,"hpregen":0.1,"manaregen":1.0},
	UnitBase.UnitClass.VAIL: {"hp":28,"mana":20,"atk":1,"magic":2,"res":4,"aspd":0.02,"hpregen":0.1,"manaregen":1.0},
	UnitBase.UnitClass.SPORE: {"hp":24,"mana":22,"atk":1,"magic":4,"res":4,"aspd":0.02,"hpregen":0.05,"manaregen":1.0},	# Summons don'''t level, but give them a small fallback so set_level() never crashes.
	UnitBase.UnitClass.ZOMBIE: {"hp":10,"mana":0,"atk":1,"magic":0,"res":1,"aspd":0.0,"hpregen":0.0,"manaregen":0.0},
	UnitBase.UnitClass.BAT:    {"hp":6,"mana":0,"atk":1,"magic":0,"res":1,"aspd":0.0,"hpregen":0.0,"manaregen":0.0},
	UnitBase.UnitClass.ANT:    {"hp":4,"mana":0,"atk":1,"magic":0,"res":1,"aspd":0.0,"hpregen":0.0,"manaregen":0.0},
}

static func create_unit(unit_class: UnitBase.UnitClass, element: UnitBase.Element = UnitBase.Element.NORMAL, is_player: bool = true) -> VisualUnit:
	var unit = VisualUnit.new()

	unit.unit_class = unit_class
	unit.trait_class = TRAIT_CLASS_MAP.get(unit_class, UnitBase.TraitClass.FIGHTER)
	unit.current_element = element
	unit.is_player_unit = is_player

	var stats = CLASS_BASE_STATS[unit_class]
	unit.max_hp = stats["hp"]
	unit.current_hp = stats["hp"]
	unit.max_mana = stats["mana"]
	unit.current_mana = stats["mana"]
	unit.attack_damage = stats["atk"]
	unit.magic_power = stats["magic"]
	unit.resistance = stats["res"]
	unit.magic_resist = stats["res"]   # defense split 2026-07-16: start equal, tune later
	unit.attack_speed = stats["aspd"]
	unit.hp_regen = stats["hpregen"]
	unit.mana_regen = stats["manaregen"]
	unit.movement_speed = stats["move"]
	unit.attack_range = stats["range"]

	# 2026-07-03: allied heroes' move speed flattened to 1 across the board —
	# minions (summon fodder: Zombie/Bat/Ant) keep their own swarm-appropriate
	# speed, and Rush keeps its 15 (its whole kit identity is being the fast one).
	# Enemy-side units are untouched — this only applies to the player's own roster.
	const FLATTENED_MOVE_EXCEPTIONS := [
		UnitBase.UnitClass.ZOMBIE, UnitBase.UnitClass.BAT, UnitBase.UnitClass.ANT,
		UnitBase.UnitClass.RUSH,
	]
	if is_player and unit_class not in FLATTENED_MOVE_EXCEPTIONS:
		unit.movement_speed = 1

	# Deterministic per-class growth — every unit of this class gets at least
	# this much per level, regardless of recruit rolls (enemies included).
	unit.growth_base = CLASS_GROWTH_PER_LEVEL.get(unit_class, {}).duplicate()

	# Affinity ratings (2026-07-16 rework): class base everywhere, then the
	# unit's own element gets +50 off / +25 def and all others −15 def.
	unit.set_affinity_profile(stats["off_affinity"], stats["def_affinity"])

	unit.unit_name = unit.get_element_name_string() + " " + unit.get_class_name_string()

	# Random sprite variant (0–2) so same class looks different each spawn
	unit.sprite_variant = randi() % 3

	# Assign class skill
	match unit_class:
		UnitBase.UnitClass.BLOODHOUND:
			unit.passive_name = "Blood Frenzy"
			unit.skill_name = "Bite"
			unit.skill_damage_multiplier = 1.3
			unit.skill_range = 1
			unit.skill_cooldown_max = 3
			unit.skill_mana_cost = 50
			unit.skill_description = "Deal 130% ATK to nearest enemy and heal self for 30% of damage dealt. · 50 MP · 3s CD"
			unit.ultimate_name = "Pounce"
			unit.ultimate_damage_mult = 2.5
			unit.ultimate_range = 8
			unit.ultimate_charge_max = 300
		UnitBase.UnitClass.BOUNCER:
			unit.passive_name = "Presence"
			unit.skill_name = "Slam"
			unit.skill_damage_multiplier = 1.0
			unit.skill_range = 2
			unit.skill_cooldown_max = 4
			unit.skill_mana_cost = 80
			unit.skill_description = "Deal 100% MAG to nearest enemy and stun them for 1.5s. Damage scales with nearby enemies. · 80 MP · 4s CD"
			unit.ultimate_name = "Gravity Drop"
			unit.ultimate_damage_mult = 1.5
			unit.ultimate_range = 4
			unit.ultimate_charge_max = 350
		UnitBase.UnitClass.HEADHUNTER:
			unit.passive_name = "Seventh Shot"
			unit.skill_name = "Rapid Fire"
			unit.skill_damage_multiplier = 1.0
			unit.skill_range = 8
			unit.skill_cooldown_max = 5
			unit.skill_mana_cost = 60
			unit.skill_description = "Fire an extra shot at a second target and gain +2 attack range for 4s. · 60 MP · 5s CD"
			unit.ultimate_name = "Snipe"
			# Balance 2026-07-03: 4.0 → 3.5 — Headhunter sits top-3 on the arena
			# damage board and user playtests flag him overtuned.
			unit.ultimate_damage_mult = 3.5
			unit.ultimate_range = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.SHAUNA:
			unit.passive_name        = "Glass Cannon"
			unit.skill_name          = "Kite"
			unit.skill_damage_multiplier = 1.5
			unit.skill_range         = 1
			unit.skill_cooldown_max  = 2.5
			unit.skill_mana_cost     = 60
			unit.skill_description   = "Step away from nearest attacker and empower next auto-attack (+50%). Only fires when being targeted. · 60 MP · 2.5s CD"
			unit.ultimate_name       = "Overdrive"
			unit.ultimate_damage_mult = 0.0   # utility ult
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.NEMI:
			unit.passive_name        = "Resonance"
			unit.skill_name          = "Tide"
			unit.skill_damage_multiplier = 0.8
			unit.skill_range         = 6   # matches TIDE_BOUNCE_RANGE (auto_battle_manager.gd)
			unit.skill_cooldown_max  = 3
			unit.skill_mana_cost     = 80
			unit.skill_description   = "Chain bolt bouncing up to 8 times, dealing 80% MAG to enemies and healing allies each hit. · 80 MP · 3s CD"
			unit.ultimate_name       = "Tidal Wave"
			unit.ultimate_damage_mult = 1.5
			unit.ultimate_charge_max = 450
		UnitBase.UnitClass.SHEILDOR:
			unit.passive_name        = "Guardian Aura"
			unit.skill_name          = "Iron Bulwark"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 2
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 80
			unit.skill_description   = "Grant a shield to the most-wounded ally in range and heal them for 5% max HP. · 80 MP · 4s CD"
			unit.ultimate_name       = "Guardian Leap"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 8
			unit.ultimate_charge_max = 350
		UnitBase.UnitClass.LORDEE:
			unit.passive_name        = "Feeding Frenzy"
			unit.skill_name          = "Ground Slam"
			unit.skill_damage_multiplier = 1.2
			unit.skill_range         = 2
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 70
			unit.skill_description   = "AoE slam hitting all enemies within 2 tiles of nearest foe for 120% ATK. · 70 MP · 4s CD"
			unit.ultimate_name       = "Parasite Lunge"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 6
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.NECRO:
			unit.passive_name        = "Soul Harvest"
			unit.skill_name          = "Raise Zombie"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 3
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 120
			unit.skill_description   = "Summon a zombie minion in front to fight by your side. · 120 MP · 5s CD"
			unit.ultimate_name       = "Bat Swarm"
			unit.ultimate_damage_mult = 0.6
			unit.ultimate_range      = 5
			unit.ultimate_charge_max = 500
		# ── Roster expansion ───────────────────────────────────────────────────
		UnitBase.UnitClass.DOC:
			unit.passive_name        = "Triage"
			unit.skill_name          = "Inject"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 70
			unit.skill_description   = "Heal the most-wounded ally in range. Healing greatly scales with their missing HP. · 70 MP · 4s CD"
			unit.ultimate_name       = "Field Surgery"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 450
		UnitBase.UnitClass.RIOT:
			unit.passive_name        = "Crowd Control"
			unit.skill_name          = "Shield Bash"
			unit.skill_damage_multiplier = 1.1
			unit.skill_range         = 1
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.skill_description   = "Bash nearest enemy for 110% ATK, stun them for 1.2s, and force them to attack Riot for 3s. · 60 MP · 4s CD"
			unit.ultimate_name       = "Kettle"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 350
		UnitBase.UnitClass.PASTOR:
			unit.passive_name        = "Righteous Fury"
			unit.skill_name          = "Sermon"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 70
			unit.skill_description   = "Grant the strongest nearby ally +40% attack speed for 5s. · 70 MP · 5s CD"
			unit.ultimate_name       = "Damnation"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.SABLE:
			unit.passive_name        = "Momentum"
			unit.skill_name          = "Bolt"
			unit.skill_damage_multiplier = 1.6
			unit.skill_range         = 7
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 50
			unit.skill_description   = "Piercing shot hits every enemy in your column for 160% ATK. Falls back to nearest if column is clear. · 50 MP · 4s CD"
			unit.ultimate_name       = "Headshot"
			unit.ultimate_damage_mult = 4.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.RUSH:
			unit.passive_name        = "Fleetfoot"
			unit.skill_name          = "Blitz"
			unit.skill_damage_multiplier = 1.1
			unit.skill_range         = 6
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.skill_description   = "Dash to nearest enemy, deal 110% ATK to the entire row, then reposition adjacent to the target. · 60 MP · 4s CD"
			unit.ultimate_name       = "Afterimage"
			unit.ultimate_damage_mult = 1.2
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.STITCH:
			unit.passive_name        = "Threadguard"
			unit.skill_name          = "Link"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 6
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 70
			unit.skill_description   = "Link 3-6 nearby enemies based on MAG. Each shares 15-30% of hits with every other linked enemy. · 70 MP · 5s CD"
			unit.ultimate_name       = "Unravel"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 6
			unit.ultimate_charge_max = 450
		UnitBase.UnitClass.COAL:
			unit.passive_name        = "Smolder"
			unit.skill_name          = "Stoke"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 1
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 50
			unit.skill_description   = "Load 3 charges — the next 3 auto-attacks each trigger a bonus fire burst. · 50 MP · 5s CD"
			unit.ultimate_name       = "Meltdown"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 1
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.JUNE:
			unit.passive_name        = "Verdant Aura"
			unit.skill_name          = "Root"
			unit.skill_damage_multiplier = 0.4
			unit.skill_range         = 3
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.skill_description   = "Root the nearest enemy in place for 3s and deal 40% MAG. · 60 MP · 4s CD"
			unit.ultimate_name       = "Bloom"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.CROSS:
			unit.passive_name        = "Penance"
			unit.skill_name          = "Absolution"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.skill_description   = "Cleanse all debuffs from the most-wounded ally in range and restore their HP. · 60 MP · 4s CD"
			unit.ultimate_name       = "Judgment"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.SEAR:
			unit.passive_name        = "Scorched Path"
			unit.skill_name          = "Ignite"
			unit.skill_damage_multiplier = 1.2
			unit.skill_range         = 3
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.skill_description   = "Deal 120% MAG to target and set them ablaze (25% MAG burn per tick for 5s). · 60 MP · 4s CD"
			unit.ultimate_name       = "Conflagration"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 420
		UnitBase.UnitClass.EMBER:
			unit.passive_name        = "Burning Arrows"
			unit.skill_name          = "Cinder Shot"
			unit.skill_damage_multiplier = 1.2
			unit.skill_range         = 5
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 50
			unit.skill_description   = "Deal 120% ATK to all enemies within 2 tiles of nearest foe; each hit applies a brief burn. · 50 MP · 4s CD"
			unit.ultimate_name       = "Wildfire"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 420
		UnitBase.UnitClass.RIFT:
			unit.passive_name        = "Backlash"
			unit.skill_name          = "Tear"
			unit.skill_damage_multiplier = 1.4
			unit.skill_range         = 5
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			# The percentage here was stale: combat reads AbilityFormulas (1.0×MAG,
			# calibrated), never skill_damage_multiplier, so the shop promised a
			# number the fight never dealt. Describe the EFFECT instead.
			unit.skill_description   = "Deal magic damage and banish the target to a random edge of the battlefield. · 60 MP · 4s CD"
			unit.ultimate_name       = "Collapse"
			unit.ultimate_damage_mult = 2.2
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 450
		UnitBase.UnitClass.ZOLT:
			unit.passive_name        = "Chain Lightning"
			unit.skill_name          = "Thunderstorm"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 6
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 90
			unit.skill_description   = "Summon a drifting storm: its own tile takes 50% MAG lightning damage and a 0.5s stun, the 8 tiles around it take half that damage. Moves every second. · 90 MP · 4s CD"
			unit.ultimate_name       = "Thunderhammer"
			unit.ultimate_damage_mult = 4.5
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 480
		UnitBase.UnitClass.LUMEN:
			unit.passive_name        = "Refraction"
			unit.skill_name          = "Refract"
			unit.skill_damage_multiplier = 0.9
			unit.skill_range         = 5
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.skill_description   = "Chain beam hitting up to 5 enemies for 90% MAG, decaying 15% per bounce. · 60 MP · 4s CD"
			unit.ultimate_name       = "Prism"
			unit.ultimate_damage_mult = 1.4
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 460
		UnitBase.UnitClass.STATIC:
			unit.passive_name        = "Live Wire"
			unit.skill_name          = "Tripwire"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 60
			unit.skill_description   = "Stun the nearest enemy for 3s and deal 60-100% MAG as lightning damage, scaling with level. · 60 MP · 5s CD"
			unit.ultimate_name       = "Grid"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 420
		UnitBase.UnitClass.REED:
			unit.passive_name        = "Wellspring"
			unit.skill_name          = "Cleanse"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.skill_description   = "Remove all debuffs from the most-wounded ally in range and heal them for 140% MAG. · 60 MP · 4s CD"
			unit.ultimate_name       = "Confluence"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 430
		UnitBase.UnitClass.VAIL:
			unit.passive_name        = "Far Winds"
			unit.skill_name          = "Updraft"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 99
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 60
			unit.skill_description   = "Whirls the most-wounded ally into a tornado, untargetable for 1s, then regenerating HP for 8s. · 60 MP · 5s CD"
			unit.ultimate_name       = "Downburst"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 420
		UnitBase.UnitClass.SPORE:
			unit.passive_name        = "Spore Cloud"
			unit.skill_name          = "Bloom"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 50
			unit.skill_description   = "Instantly max spore stacks on the nearest enemy, triggering a toxic burst next tick. · 50 MP · 4s CD"
			unit.ultimate_name       = "Release"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 440
		UnitBase.UnitClass.ZOMBIE:
			unit.skill_name          = "Claw"
			unit.skill_damage_multiplier = 1.0
			unit.skill_range         = 1
			unit.skill_cooldown_max  = 3
			unit.skill_mana_cost     = 0
		UnitBase.UnitClass.BAT:
			unit.skill_name          = "Bite"
			unit.skill_damage_multiplier = 0.8
			unit.skill_range         = 1
			unit.skill_cooldown_max  = 2
			unit.skill_mana_cost     = 0
	# skill_cd_time is initialized by the battle manager (start on cooldown).

	return unit

# ── Gacha roll system ────────────────────────────────────────────────────────

# Shared F–S tier colors used everywhere a roll's quality is shown (recruit stat
# rows, level-up perk cards, etc.) so the color language stays consistent — same
# grey/dark-green/blue/purple/gold progression as item rarity. F and D share the
# grey "common" tier at two shades so the bottom of the scale still reads as a
# clear step down from C.
const GRADE_COLORS := {
	"F": Color(0.45, 0.45, 0.48),
	"D": Color(0.65, 0.65, 0.68),
	"C": Color(0.20, 0.62, 0.28),
	"B": Color(0.30, 0.55, 0.95),
	"A": Color(0.68, 0.35, 0.95),
	"S": Color(1.0,  0.85, 0.0),
}

# Per-stat growth ROLL MULTIPLIER ranges 0.3 to 1.7 (see generate_recruit_rolls
# below) — it scales this unit's growth_base into its personalized growth_bonus,
# NOT a percentage of the stat itself. 1.0 = average roll. Grades this the same
# way the card's overall grade is graded, so a bad roll reads as a clear "C or D".
static func grade_letter_for_growth(growth: float) -> String:
	if   growth >= 1.5: return "S"
	elif growth >= 1.2: return "A"
	elif growth >= 0.9: return "B"
	elif growth >= 0.6: return "C"
	elif growth >= 0.4: return "D"
	else:               return "F"

static func grade_color_for_growth(growth: float) -> Color:
	return GRADE_COLORS.get(grade_letter_for_growth(growth), Color(0.86, 0.86, 1.0))

# Roll per-stat bonuses for a recruit offer.
# "flat" scales the STARTING stat (class base → this recruit's current stat).
# "growth" is a MULTIPLIER (0.3–1.7, 1.0 = average) applied to the class's fixed
# growth_base to produce this recruit's personalized growth_bonus — additive,
# not a percentage of the stat. See UnitBase.stat_growth()/apply_stat_growth().
# `bias` shifts both roll windows upward (used by enemy spawns in late rounds —
# see WaveScaler.enemy_roll_bias — so a round-30 enemy hero rolls meaningfully
# better than a round-11 one instead of both landing in the same flat range).
# Returns {"stats": {key: {flat, growth}}, "grade": "A", "avg_pct": 1.1}
static func generate_recruit_rolls(bias: float = 0.0) -> Dictionary:
	const PCT_STATS := ["hp", "mana", "atk", "magic", "res", "aspd", "hpregen", "manaregen"]
	var stat_rolls: Dictionary = {}
	var total_flat := 0.0
	var total_growth := 0.0
	for key in PCT_STATS:
		var flat   := randf_range(-0.25, 0.30) + bias * 0.4
		var growth := clampf(randf_range(0.3, 1.7) + bias, 0.1, 2.2)
		stat_rolls[key] = {"flat": flat, "growth": growth}
		total_flat += flat
		total_growth += growth
	# SPD and RNG are integer rolls (small deltas feel big)
	stat_rolls["move"]  = {"flat": float(randi_range(-1, 1)),  "growth": 0.0, "is_int": true}
	stat_rolls["range"] = {"flat": float(randi_range(-1, 2)),  "growth": 0.0, "is_int": true}

	# Grade reflects the average growth-roll multiplier — the same number that
	# scales every stat row's "bonus" — so the badge matches what's on the card.
	var avg := total_growth / float(PCT_STATS.size())
	var grade := grade_letter_for_growth(avg)
	if grade == "F":
		grade = "D"   # the card's overall badge only ever shows S/A/B/C/D
	return {"stats": stat_rolls, "grade": grade, "avg_pct": avg}


# Apply rolls from generate_recruit_rolls() to a newly created unit.
static func apply_recruit_rolls(unit: UnitBase, rolls: Dictionary) -> void:
	var stats: Dictionary = rolls.get("stats", {})

	unit.max_hp         = maxi(1, int(unit.max_hp         * (1.0 + stats.get("hp",        {}).get("flat", 0.0))))
	unit.current_hp     = unit.max_hp
	unit.max_mana       = maxi(1, int(unit.max_mana       * (1.0 + stats.get("mana",      {}).get("flat", 0.0))))
	unit.current_mana   = unit.max_mana
	unit.attack_damage  = maxi(1, int(unit.attack_damage  * (1.0 + stats.get("atk",       {}).get("flat", 0.0))))
	unit.magic_power    = maxi(1, int(unit.magic_power    * (1.0 + stats.get("magic",     {}).get("flat", 0.0))))
	unit.resistance     = maxi(1, int(unit.resistance     * (1.0 + stats.get("res",       {}).get("flat", 0.0))))
	unit.attack_speed   = maxf(0.05, unit.attack_speed    * (1.0 + stats.get("aspd",      {}).get("flat", 0.0)))
	unit.hp_regen       = maxf(0.0,  unit.hp_regen        * (1.0 + stats.get("hpregen",   {}).get("flat", 0.0)))
	unit.mana_regen     = maxf(0.0,  unit.mana_regen      * (1.0 + stats.get("manaregen", {}).get("flat", 0.0)))

	# Personalize this unit's per-level growth bonus — two recruits of the same
	# class never level up identically. bonus = class's fixed growth_base * this
	# stat's personal roll multiplier (rounded to each stat's natural precision).
	unit.growth_bonus = {}
	for key in ["hp", "mana", "atk", "magic", "res", "aspd", "hpregen", "manaregen"]:
		var base_growth: float = unit.growth_base.get(key, 0.0)
		var mult: float = stats.get(key, {}).get("growth", 1.0)
		if key in ["aspd", "hpregen", "manaregen"]:
			unit.growth_bonus[key] = snappedf(base_growth * mult, 0.01)
		else:
			unit.growth_bonus[key] = float(round(base_growth * mult))

	unit.recruit_rolls = rolls
	unit.recruit_grade = rolls.get("grade", "B")

	# Level 1 already counts as "having" its level — apply one growth tick now,
	# same as every subsequent level-up, so the recruit's live stats match the
	# card's "→ next (+delta)" column immediately, not one level behind.
	unit.apply_stat_growth()
	unit.current_hp = unit.max_hp
	unit.current_mana = unit.max_mana


static func create_random_unit(unit_class: UnitBase.UnitClass, element: UnitBase.Element = UnitBase.Element.NORMAL, is_player: bool = true) -> VisualUnit:
	return create_unit(unit_class, element, is_player)

static func create_random_class_unit(is_player: bool = true) -> VisualUnit:
	var classes = get_all_classes()
	var elements = get_all_elements()
	var random_class = classes[randi() % classes.size()] as UnitBase.UnitClass
	var random_element = elements[randi() % elements.size()] as UnitBase.Element
	return create_unit(random_class, random_element, is_player)

# Recruitable hero pool. The 7 legacy RPG classes (Warrior/Ranger/Monk/Thief/
# Black/White/Red Mage) were retired from recruitment — they live on only as the
# stat/skill templates EnemyFactory reuses, so their enum + implementations stay.
static func get_all_classes() -> Array:
	return [
		# Original 8 custom heroes
		UnitBase.UnitClass.BLOODHOUND,
		UnitBase.UnitClass.BOUNCER,
		UnitBase.UnitClass.HEADHUNTER,
		UnitBase.UnitClass.SHAUNA,
		UnitBase.UnitClass.NEMI,
		UnitBase.UnitClass.SHEILDOR,
		UnitBase.UnitClass.LORDEE,
		UnitBase.UnitClass.NECRO,
		# Roster expansion (18)
		UnitBase.UnitClass.DOC,
		UnitBase.UnitClass.RIOT,
		UnitBase.UnitClass.PASTOR,
		UnitBase.UnitClass.SABLE,
		UnitBase.UnitClass.RUSH,
		UnitBase.UnitClass.STITCH,
		UnitBase.UnitClass.COAL,
		UnitBase.UnitClass.JUNE,
		UnitBase.UnitClass.CROSS,
		UnitBase.UnitClass.SEAR,
		UnitBase.UnitClass.EMBER,
		UnitBase.UnitClass.RIFT,
		UnitBase.UnitClass.ZOLT,
		UnitBase.UnitClass.LUMEN,
		UnitBase.UnitClass.STATIC,
		UnitBase.UnitClass.REED,
		UnitBase.UnitClass.VAIL,
		UnitBase.UnitClass.SPORE,
	]

static func get_all_elements() -> Array:
	return [
		UnitBase.Element.NORMAL,
		UnitBase.Element.FIRE,
		UnitBase.Element.WATER,
		UnitBase.Element.EARTH,
		UnitBase.Element.AIR,
		UnitBase.Element.LIGHTNING
	]
