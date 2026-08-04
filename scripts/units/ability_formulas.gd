class_name AbilityFormulas
extends RefCounted

# ══════════════════════════════════════════════════════════════════════════════
# Single source of truth for every hero ability number.
# ══════════════════════════════════════════════════════════════════════════════
#
# WHY THIS EXISTS
# ---------------
# Ability numbers used to be inline magic constants scattered across
# auto_battle_manager.gd (~78 call sites) and unit_base.gd. Nothing could ask
# "what does Static's Tripwire hit for?" without re-running the fight, so the
# level-up screen could not show the player what a stat pick would actually do
# to their hero's kit. This file makes every number queryable BEFORE it is
# dealt, and combat reads its numbers from here — so the UI and the fight can
# never disagree.
#
# THE FORMULA
# -----------
#   value = coef' * STAT * [skill/ult multiplier] * [element aspect]
#   coef' = coef * (1 + LVL_COEF * level) / (1 + LVL_COEF * CAL_LEVEL)
#
# `coef` is the LEGACY coefficient — the exact number the old inline code used.
# The level term is normalised at CAL_LEVEL, so a hero at level 12 computes
# EXACTLY what it computed before this refactor, for any stat value. Below 12
# abilities are slightly weaker, above 12 slightly stronger. That is the whole
# behavioural change: balance is preserved at the calibration point and the
# refactor itself is a no-op there.
#
# Keeping `coef` as the legacy value (rather than baking the division in) means
# every number here can still be diffed against the code it replaced.
#
# WHAT SCALES
# -----------
# Damage, healing and shields scale with level and with MAG or ATK.
# Proc chances, stun/root/taunt durations, radii and charge counts DO NOT —
# scaling those produces permanent-lockdown and 100%-proc degenerate states.
# They still appear in the panel, as flat values, so the player sees the whole
# ability rather than only the parts that react to hovering.
#
# MAG OR ATK
# ----------
# Each term names its own stat, so mixed kits stay exact. `scale` on the hero
# entry is the PRIMARY stat — the one the level-up panel calls out. The
# assignment follows CLASS_GROWTH_PER_LEVEL in unit_factory.gd: a hero whose
# per-level magic growth is 0 is an ATK hero. Two heroes contradict their own
# growth table — LORDEE and EMBER both grow magic but their kits read
# attack_damage, so their magic growth is a dead stat. Parity wins here (they
# stay ATK); the growth table is the thing that should be fixed, in the balance
# pass, not this refactor.
#
# ADDING A HERO
# -------------
# Add a SPEC entry with the three slots, then call value_of() from combat
# instead of writing the number inline. If it isn't in here, the level-up panel
# cannot show it.

# The level at which this refactor is exactly power-neutral. Anchored to
# Progression.HERO_LEVEL_CAP_BASE (10): on an uninvested save a hero that has
# hit its cap computes EXACTLY what it computed before this refactor, so the
# baseline the arena harness measures against is unmoved. Crystal-tree Max Hero
# Level nodes push the cap to 45, and those levels are where the new scaling
# actually pays out — which is the point: investing in levels now visibly
# improves the kit, not just the statline.
# Move this and every ability re-anchors together.
const CAL_LEVEL := 10.0

# Per-level growth applied to scaling terms: +2% per level. Deliberately modest
# because MAG/ATK ALREADY grow per level (see CLASS_GROWTH_PER_LEVEL), so this
# compounds on top of existing stat growth rather than being the only source.
const LVL_COEF := 0.02

const PASSIVE := "passive"
const ACTIVE := "active"
const ULTIMATE := "ultimate"

# ══════════════════════════════════════════════════════════════════════════════
# Term schema
# ══════════════════════════════════════════════════════════════════════════════
#   id      String  — key used in the `text` template, e.g. "{dmg}"
#   label   String  — human label for the panel
#   stat    String  — "magic_power" | "attack_damage" | "max_hp" | "resistance"
#                     | "" (flat: the value IS coef, no stat multiply)
#   coef    float   — legacy coefficient
#   mult    String  — "skill" | "ult" | "" — folds in the hero's
#                     skill_damage_multiplier / ultimate_damage_mult, which stay
#                     in unit_factory.gd rather than being duplicated here
#   aspect  bool    — multiply by UnitFactory.natural_aspect (matches old code)
#   lvl     bool    — does the level term apply (false for flat/CC/duration)
#   fmt     String  — "dmg" | "heal" | "shield" | "pct" | "sec" | "x" | "num"
#   curve   String  — "" | "static" — bespoke curve, see _apply_curve

static func _t(id: String, label: String, stat: String, coef: float,
		fmt: String = "dmg", mult: String = "", aspect: bool = false,
		lvl: bool = true, curve: String = "") -> Dictionary:
	return {
		"id": id, "label": label, "stat": stat, "coef": coef, "mult": mult,
		"aspect": aspect, "lvl": lvl, "fmt": fmt, "curve": curve,
	}

# Flat term: no stat, no level scaling. Durations, chances, counts.
static func _f(id: String, label: String, value: float, fmt: String = "num",
		aspect: bool = false) -> Dictionary:
	return _t(id, label, "", value, fmt, "", aspect, false)


static func _spec() -> Dictionary:
	# Built as a function rather than a const because the entries call helpers.
	# Cached in _SPEC_CACHE on first use — this runs once per session.
	var C = UnitBase.UnitClass
	return {
		# ── Bloodhound — MAG bruiser (2026-08-03, user request) ───────────────
		# His kit reads magic_power; his AUTO-ATTACKS still read attack_damage, so
		# both stats matter. Damage TYPE is unchanged — Bite and Pounce still deal
		# physical damage through take_damage(), MAG only feeds the number.
		# unit_factory gives him magic 20 base / +2 per level, mirroring his atk
		# line, so coef 1.0 reproduces the old ATK-based output at every level.
		C.BLOODHOUND: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [_f("thresh", "HP threshold", 0.45, "pct")],
				"text": "Below {thresh} HP, he hunts whoever hurt him most.",
			},
			ACTIVE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "skill"),
					# Lifesteal rides his max HP: 25% at 1 HP up to 45% at 10000
					# (2026-08-03, user spec). Bulk is the thing that keeps a
					# melee bruiser alive long enough to drain, so stacking HP
					# now feeds the sustain instead of only the health bar.
					_t("drain", "Lifesteal", "", 0.25, "pct", "", false, false,
						"lerp:max_hp:1:10000:0.25:0.45"),
				],
				"text": "Bites the nearest enemy for {dmg}, healing {drain} of it.",
			},
			ULTIMATE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "ult"),
					_f("stun", "Stun", 1.5, "sec"),
				],
				"text": "Leaps at his tormentor for {dmg}, stunning {stun}.",
			},
		},

		# ── Bouncer — MAG brawler, damage scales with the crowd ───────────────
		C.BOUNCER: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [
					_f("per", "Per unit nearby", 0.05, "pct"),
					_f("cap", "Cap", 0.30, "pct"),
				],
				"text": "Each unit within 2 tiles: +{per} damage, up to {cap}.",
			},
			ACTIVE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "skill"),
					_f("stun", "Stun", 1.5, "sec"),
				],
				"text": "Smashes the nearest enemy for {dmg}, stunning {stun}.",
			},
			ULTIMATE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "ult"),
					_f("radius", "Pull radius", 4.0, "num"),
				],
				"text": "Drags enemies within {radius} tiles in, hitting for {dmg}.",
			},
		},

		# ── Headhunter — ATK sniper ───────────────────────────────────────────
		C.HEADHUNTER: {
			"scale": "attack_damage",
			PASSIVE: {
				"terms": [
					_f("every", "Every", 7.0, "num"),
					_f("mult", "Damage", 3.0, "x"),
				],
				"text": "Every {every}th shot he fires deals {mult} damage.",
			},
			ACTIVE: {
				"terms": [
					_f("dur", "Duration", 4.0, "sec"),
					_f("range", "Bonus range", 2.0, "num"),
				],
				"text": "For {dur}: an extra shot at a 2nd target, +{range} range.",
			},
			ULTIMATE: {
				"terms": [_t("dmg", "Damage", "attack_damage", 1.0, "dmg", "ult")],
				"text": "Shoots the farthest enemy for {dmg}; blockers intercept.",
			},
		},

		# ── Shauna — ATK glass cannon ─────────────────────────────────────────
		C.SHAUNA: {
			"scale": "attack_damage",
			PASSIVE: {
				"terms": [_f("every", "Every", 3.0, "num")],
				"text": "Every {every}rd hit ignores enemy armor entirely.",
			},
			ACTIVE: {
				"terms": [_f("boost", "Next attack", 0.50, "pct")],
				"text": "Backs away; her next attack hits {boost} harder.",
			},
			ULTIMATE: {
				"terms": [_f("dur", "Duration", 4.0, "sec")],
				"text": "She attacks twice per swing for {dur}.",
			},
		},

		# ── Nemi — MAG water controller ───────────────────────────────────────
		C.NEMI: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [_f("radius", "Radius", 3.0, "num")],
				"text": "Allies within {radius} move +1; nearest enemy moves -1.",
			},
			ACTIVE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "skill", true),
					_f("bounces", "Bounces", 8.0, "num"),
				],
				"text": "Chains {bounces} times: {dmg} to foes, heals allies hit.",
			},
			ULTIMATE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "ult", true),
					_f("push", "Pushback", 2.0, "num"),
				],
				"text": "Hits a 3-wide column for {dmg}, shoving {push} tiles back.",
			},
		},

		# ── Sheildor — MAG guardian. Shields read MAG; the ally max-HP portion
		#    can't be resolved against the caster, so it stays a flat percentage.
		C.SHEILDOR: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [
					_t("shield", "Shield", "magic_power", 0.35, "shield", "", true),
					_f("every", "Interval", 4.0, "sec"),
				],
				"text": "Every {every}, shields the weakest adjacent ally {shield}.",
			},
			ACTIVE: {
				"terms": [
					_t("shield", "Shield", "magic_power", 8.0, "shield"),
					_f("bonus", "+ ally max HP", 0.06, "pct"),
					_f("heal", "Heal", 0.05, "pct"),
				],
				"text": "Shields an ally {shield} +{bonus} their max HP; heals {heal}.",
			},
			ULTIMATE: {
				"terms": [
					_t("shield", "Shield", "magic_power", 15.0, "shield"),
					_f("bonus", "+ ally max HP", 0.20, "pct"),
					_f("self", "Self shield", 0.50, "pct"),
				],
				"text": "Leaps to an ally: shields {shield} +{bonus} HP, self {self}.",
			},
		},

		# ── Lordee — ATK leech. NOTE: grows magic per level but the kit reads
		#    ATK; flagged for the balance pass, parity kept here.
		C.LORDEE: {
			"scale": "attack_damage",
			PASSIVE: {
				"terms": [
					_t("dmg", "Pulse damage", "attack_damage", 0.12, "dmg"),
					_f("every", "Interval", 0.8, "sec"),
				],
				"text": "Every {every}, hits adjacent enemies for {dmg}.",
			},
			ACTIVE: {
				"terms": [_t("dmg", "Damage", "attack_damage", 1.0, "dmg", "skill")],
				"text": "Slams everything within 2 tiles of the nearest foe: {dmg}.",
			},
			ULTIMATE: {
				"terms": [
					_t("dmg", "Damage", "attack_damage", 1.5, "dmg"),
					_f("steal", "ATK stolen", 0.07, "pct"),
				],
				"text": "Blinks in for {dmg}, permanently stealing {steal} of their ATK.",
			},
		},

		# ── Necro — MAG summoner ──────────────────────────────────────────────
		C.NECRO: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [_f("regen", "HP/s per summon", 0.5, "num")],
				"text": "Regenerates {regen} HP a second per summon still alive.",
			},
			ACTIVE: {
				"terms": [_f("count", "Zombies", 1.0, "num")],
				"text": "Summons {count} zombie to fight for you.",
			},
			ULTIMATE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "ult"),
					_f("bats", "Bats", 3.0, "num"),
				],
				"text": "Hits nearby enemies for {dmg} and summons {bats} bats.",
			},
		},

		# ── Doc — MAG healer. Heal scales with the target's missing HP, so the
		#    panel shows the full band rather than a single misleading number.
		C.DOC: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [
					_t("lo", "Heal (healthy)", "magic_power", 0.35, "heal", "", true),
					_t("hi", "Heal (near death)", "magic_power", 1.45, "heal", "", true),
					_f("every", "Interval", 1.4, "sec"),
				],
				"text": "Every {every}, heals the weakest ally {lo}-{hi}.",
			},
			ACTIVE: {
				"terms": [
					_t("lo", "Heal (healthy)", "magic_power", 1.2, "heal", "", true),
					_t("hi", "Heal (near death)", "magic_power", 3.0, "heal", "", true),
				],
				"text": "Heals the most-wounded ally in range {lo}-{hi}.",
			},
			ULTIMATE: {
				"terms": [
					_f("revive", "Revive HP", 0.30, "pct"),
					_f("fallback", "Team heal", 0.25, "pct"),
				],
				"text": "Revives a fallen ally at {revive} HP, else heals team {fallback}.",
			},
		},

		# ── Riot — ATK control tank (his kit reads attack_damage, not MAG) ────
		C.RIOT: {
			"scale": "attack_damage",
			PASSIVE: {
				"terms": [
					_f("slow", "Slow", 0.30, "pct"),
					_f("dur", "Duration", 1.5, "sec"),
				],
				"text": "Anyone who damages him is slowed {slow} for {dur}.",
			},
			ACTIVE: {
				"terms": [
					_t("dmg", "Damage", "attack_damage", 1.0, "dmg", "skill"),
					_f("stun", "Stun", 1.2, "sec"),
					_f("taunt", "Taunt", 3.0, "sec"),
				],
				"text": "Bashes {dmg}, stuns {stun}, forces them onto him {taunt}.",
			},
			ULTIMATE: {
				"terms": [_f("taunt", "Taunt", 4.0, "sec")],
				"text": "Forces every enemy to attack him for {taunt}.",
			},
		},

		# ── Pastor — MAG buffer. No stat-scaling terms by design: he multiplies
		#    the team's damage rather than adding his own.
		C.PASTOR: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [
					_f("bonus", "Damage bonus", 0.12, "pct", true),
					_f("radius", "Radius", 3.0, "num"),
				],
				"text": "Allies within {radius} tiles deal {bonus} more damage.",
			},
			ACTIVE: {
				"terms": [
					_f("aspd", "Attack speed", 0.40, "pct"),
					_f("dur", "Duration", 5.0, "sec"),
				],
				"text": "Gives the strongest nearby ally {aspd} attack speed, {dur}.",
			},
			ULTIMATE: {
				"terms": [_f("weaken", "Enemy damage", 0.40, "pct")],
				"text": "Every enemy deals {weaken} less damage for the round.",
			},
		},

		# ── Sable — ATK carry. Headshot scales with banked Momentum, so the
		#    panel shows the empty-to-full band.
		C.SABLE: {
			"scale": "attack_damage",
			PASSIVE: {
				"terms": [
					_f("per", "Per hit", 0.12, "pct"),
					_f("cap", "Max stacks", 12.0, "num"),
				],
				"text": "Each hit banks {per} ultimate damage, up to {cap} stacks.",
			},
			ACTIVE: {
				"terms": [_t("dmg", "Damage", "attack_damage", 1.0, "dmg", "skill")],
				"text": "Piercing shot hits her whole column for {dmg}.",
			},
			ULTIMATE: {
				"terms": [
					_t("dmg", "Damage (0 stacks)", "attack_damage", 1.0, "dmg", "ult"),
					_t("dmg_max", "Damage (12 stacks)", "attack_damage", 2.44, "dmg", "ult"),
				],
				"text": "One shot for {dmg}, up to {dmg_max} at full stacks.",
			},
		},

		# ── Rush — ATK skirmisher ─────────────────────────────────────────────
		C.RUSH: {
			"scale": "attack_damage",
			PASSIVE: {
				"terms": [_f("move", "Move speed", 15.0, "num")],
				"text": "Moves at {move} - far faster than any other hero.",
			},
			ACTIVE: {
				"terms": [_t("dmg", "Damage", "attack_damage", 1.0, "dmg", "skill")],
				"text": "Dashes to the nearest enemy, hitting its row for {dmg}.",
			},
			ULTIMATE: {
				"terms": [
					_t("dmg", "Damage", "attack_damage", 1.0, "dmg", "ult"),
					_f("dur", "Duration", 3.0, "sec"),
				],
				"text": "Hits all for {dmg}; everyone else is frozen {dur}.",
			},
		},

		# ── Stitch — MAG disruptor. Pure percentage kit: nothing scales.
		C.STITCH: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [_f("bleed", "Bleed share", 0.08, "pct")],
				"text": "Damage to an enemy bleeds {bleed} onto each of its allies.",
			},
			ACTIVE: {
				"terms": [_f("share", "Shared damage", 0.50, "pct")],
				"text": "Ties two enemies: each takes {share} of the other's damage.",
			},
			ULTIMATE: {
				"terms": [_f("dur", "Duration", 4.0, "sec")],
				"text": "The toughest enemy fights for your side for {dur}.",
			},
		},

		# ── Coal — ATK burner ─────────────────────────────────────────────────
		C.COAL: {
			"scale": "attack_damage",
			PASSIVE: {
				"terms": [
					_t("burn", "Burn/tick", "attack_damage", 0.12, "dmg", "", true),
					_f("dur", "Duration", 3.0, "sec"),
				],
				"text": "Every hit burns for {burn} a tick over {dur}.",
			},
			ACTIVE: {
				"terms": [
					_f("charges", "Charges", 3.0, "num"),
					_f("mult", "Burn", 2.0, "x"),
				],
				"text": "Loads {charges} charges; each makes one hit's burn {mult}.",
			},
			ULTIMATE: {
				"terms": [
					_t("blast", "Explosion", "attack_damage", 0.6, "dmg", "", true),
					_f("dur", "Duration", 5.0, "sec"),
				],
				"text": "For {dur} his hits explode for {blast}; then he tires.",
			},
		},

		# ── June — MAG earth support ──────────────────────────────────────────
		C.JUNE: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [
					_t("regen", "Regen/s", "magic_power", 0.10, "heal", "", true),
					_f("radius", "Radius", 3.0, "num"),
				],
				"text": "Allies within {radius} tiles regenerate {regen} HP a second.",
			},
			ACTIVE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "skill"),
					_f("root", "Root", 3.0, "sec"),
				],
				"text": "Traps the nearest enemy in place {root}; deals {dmg}.",
			},
			ULTIMATE: {
				"terms": [
					_t("thorns", "Thorns damage", "magic_power", 0.5, "dmg", "", true),
					_f("dur", "Duration", 8.0, "sec"),
				],
				"text": "For {dur}, enemies take {thorns} each tile they move.",
			},
		},

		# ── Cross — ATK paladin. Absolution reads max HP and RES rather than a
		#    damage stat; Judgment banks Penance healing and floors at ATK, which
		#    is why he is an ATK hero for panel purposes.
		C.CROSS: {
			"scale": "attack_damage",
			PASSIVE: {
				"terms": [_f("share", "Damage healed", 0.15, "pct")],
				"text": "Heals {share} of damage taken, and banks that much.",
			},
			ACTIVE: {
				"terms": [
					_t("hp", "Heal (max HP)", "max_hp", 0.12, "heal"),
					_t("res", "Heal (RES)", "resistance", 6.0, "heal"),
				],
				"text": "Clears all debuffs from the weakest ally, heals {hp}+{res}.",
			},
			ULTIMATE: {
				"terms": [
					_f("pool", "Banked healing", 0.50, "pct"),
					_t("floor", "Minimum", "attack_damage", 1.0, "dmg"),
				],
				"text": "Spends banked healing: {pool} of it as damage (min {floor}).",
			},
		},

		# ── Sear — MAG fire fighter ───────────────────────────────────────────
		C.SEAR: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [
					_t("trail", "Trail damage", "magic_power", 0.5, "dmg", "", true),
					_f("dur", "Duration", 5.0, "sec"),
				],
				"text": "His tiles burn for {dur}, dealing {trail} to enemies.",
			},
			ACTIVE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "skill"),
					_t("burn", "Burn/tick", "magic_power", 0.25, "dmg", "", true),
					_f("dur", "Burn duration", 5.0, "sec"),
				],
				"text": "Deals {dmg} and burns for {burn} a tick over {dur}.",
			},
			ULTIMATE: {
				"terms": [
					_t("floor", "Minimum burn", "magic_power", 0.2, "dmg", "", true),
					_f("burst", "Instant burst", 2.0, "x"),
				],
				"text": "Spreads the worst burn (min {floor}) to all, bursting {burst}.",
			},
		},

		# ── Ember — ATK fire archer. NOTE: grows magic per level but the kit
		#    reads ATK; same dead-stat flag as Lordee.
		C.EMBER: {
			"scale": "attack_damage",
			PASSIVE: {
				"terms": [
					_t("burn", "Burn/tick", "attack_damage", 0.12, "dmg", "", true),
					_f("dur", "Duration", 3.0, "sec"),
				],
				"text": "Every arrow burns for {burn} a tick over {dur}.",
			},
			ACTIVE: {
				"terms": [_t("dmg", "Damage", "attack_damage", 1.0, "dmg", "skill")],
				"text": "Hits everything within 2 tiles of the nearest foe: {dmg}.",
			},
			ULTIMATE: {
				"terms": [
					_t("blast", "Base blast", "attack_damage", 0.5, "dmg"),
					_f("burn_mult", "Burn bonus", 4.0, "x"),
				],
				"text": "Burning enemies explode for {blast} +{burn_mult} their burn.",
			},
		},

		# ── Rift — MAG void mage ──────────────────────────────────────────────
		C.RIFT: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [_f("redirect", "Redirected", 0.30, "pct")],
				"text": "Redirects {redirect} of damage he takes to a random enemy.",
			},
			ACTIVE: {
				"terms": [_t("dmg", "Damage", "magic_power", 1.0, "dmg", "skill")],
				"text": "Deals {dmg} and teleports the target to the far edge.",
			},
			ULTIMATE: {
				"terms": [_t("dmg", "Damage", "magic_power", 1.0, "dmg", "ult")],
				"text": "Drags every enemy to the centre and deals {dmg}.",
			},
		},

		# ── Zolt — MAG lightning carry ────────────────────────────────────────
		C.ZOLT: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [
					_t("dmg", "Chain damage", "magic_power", 0.6, "dmg", "", true),
					_f("every", "Every", 6.0, "num"),
				],
				"text": "Every {every}th attack arcs to nearby enemies for {dmg}.",
			},
			ACTIVE: {
				"terms": [
					_t("dmg", "Storm damage", "magic_power", 0.5, "dmg", "", true),
					_f("stun", "Stun", 0.5, "sec"),
				],
				"text": "Drops a drifting storm: {dmg} and a {stun} stun.",
			},
			ULTIMATE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "ult", true),
					_f("stun", "Stun", 5.0, "sec"),
				],
				"text": "Hits the toughest enemy for {dmg}, stunning {stun}.",
			},
		},

		# ── Lumen — MAG multi-target mage ─────────────────────────────────────
		C.LUMEN: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [_t("dmg", "Bounce damage", "attack_damage", 0.5, "dmg", "", true)],
				"text": "Every attack also strikes a 2nd enemy for {dmg}.",
			},
			ACTIVE: {
				"terms": [
					_t("dmg", "First hit", "magic_power", 1.0, "dmg", "skill"),
					_f("bounces", "Bounces", 5.0, "num"),
					_f("decay", "Decay per bounce", 0.15, "pct"),
				],
				"text": "Beam hits {bounces} enemies for {dmg}, -{decay} per bounce.",
			},
			ULTIMATE: {
				"terms": [_t("dmg", "Damage", "magic_power", 1.0, "dmg", "ult")],
				"text": "Strikes every enemy on the field for {dmg}.",
			},
		},

		# ── Static — MAG disruptor. The one hero whose passive percentage
		#    genuinely scales; it predates this file and is kept as a bespoke
		#    curve (see _apply_curve) rather than flattened.
		C.STATIC: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [_t("reflect", "Reflected", "", 0.10, "pct", "", false, true, "static:0.10:0.20")],
				"text": "Attackers take {reflect} of the damage they dealt him.",
			},
			ACTIVE: {
				"terms": [
					_t("dmg", "Damage", "magic_power", 1.0, "dmg", "", true, true, "static:0.60:1.00"),
					_f("stun", "Stun", 3.0, "sec"),
				],
				"text": "Stuns the nearest enemy {stun} and deals {dmg}.",
			},
			ULTIMATE: {
				"terms": [
					_t("dmg", "Damage/tick", "magic_power", 1.0, "dmg", "", true, true, "static:0.25:0.50"),
					_f("dur", "Duration", 4.0, "sec"),
					_f("lock", "Lockdown stun", 2.0, "sec"),
				],
				"text": "Shocks all {dmg} a second for {dur}; if uninterrupted, stuns {lock}.",
			},
		},

		# ── Reed — MAG water support ──────────────────────────────────────────
		C.REED: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [
					_t("regen", "Regen/s", "magic_power", 0.12, "heal", "", true),
					_f("cleanse", "Debuffs fade", 0.30, "pct"),
				],
				"text": "Nearby allies regen {regen}/s and shed debuffs {cleanse} faster.",
			},
			ACTIVE: {
				"terms": [_t("heal", "Heal", "magic_power", 1.4, "heal", "", true)],
				"text": "Clears all debuffs from the weakest ally and heals {heal}.",
			},
			ULTIMATE: {
				"terms": [
					_f("heal", "Team heal", 0.18, "pct"),
					_f("per_water", "Per Water ally", 0.40, "pct"),
				],
				"text": "Heals the team {heal} max HP, +{per_water} per Water ally.",
			},
		},

		# ── Vail — MAG air support. Utility only; nothing scales.
		C.VAIL: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [
					_f("aspd", "Attack speed", 0.10, "pct", true),
					_f("radius", "Radius", 3.0, "num"),
				],
				"text": "Allies within {radius} tiles attack {aspd} faster.",
			},
			ACTIVE: {
				"terms": [_f("dur", "Untargetable", 2.0, "sec")],
				"text": "Lifts the weakest ally away {dur} - they cannot be hit.",
			},
			ULTIMATE: {
				"terms": [
					_f("aspd", "Attack speed", 0.50, "pct"),
					_f("dur", "Duration", 6.0, "sec"),
				],
				"text": "The whole team attacks {aspd} faster for {dur}.",
			},
		},

		# ── Spore — MAG earth carry ───────────────────────────────────────────
		C.SPORE: {
			"scale": "magic_power",
			PASSIVE: {
				"terms": [
					_t("burst", "Burst damage", "magic_power", 1.6, "dmg", "", true),
					_f("radius", "Radius", 2.0, "num"),
				],
				"text": "Enemies within {radius} tiles gather spores, bursting {burst}.",
			},
			ACTIVE: {
				"terms": [_t("burst", "Burst damage", "magic_power", 1.6, "dmg", "", true)],
				"text": "Maxes spores on the nearest enemy; bursts for {burst}.",
			},
			ULTIMATE: {
				"terms": [
					_t("lo", "Damage (few stacks)", "magic_power", 1.12, "dmg", "", true),
					_t("hi", "Damage (full stacks)", "magic_power", 2.94, "dmg", "", true),
				],
				"text": "Bursts every spore cloud for {lo}-{hi} by stacks.",
			},
		},
	}


static var _SPEC_CACHE: Dictionary = {}

static func spec() -> Dictionary:
	if _SPEC_CACHE.is_empty():
		_SPEC_CACHE = _spec()
	return _SPEC_CACHE


# ══════════════════════════════════════════════════════════════════════════════
# Resolution
# ══════════════════════════════════════════════════════════════════════════════

static func has_entry(unit_class: int, slot: String) -> bool:
	var s := spec()
	return s.has(unit_class) and s[unit_class].has(slot)


# Primary scaling stat for a hero — the one the level-up panel calls out.
static func scaling_stat(unit_class: int) -> String:
	var s := spec()
	if not s.has(unit_class):
		return "attack_damage"
	return str(s[unit_class].get("scale", "attack_damage"))


# THE combat entry point. Returns a single term's value for `unit`, with the
# level term and every multiplier already folded in.
#
#   var dmg := int(AbilityFormulas.value_of(caster, AbilityFormulas.ACTIVE, "dmg"))
#
# Returns 0.0 for an unknown hero/slot/term so a missing entry degrades to a
# no-op rather than crashing mid-battle.
static func value_of(unit: UnitBase, slot: String, term_id: String,
		overrides: Dictionary = {}) -> float:
	if not (unit and is_instance_valid(unit)):
		return 0.0
	var s := spec()
	if not s.has(unit.unit_class):
		return 0.0
	var entry: Dictionary = s[unit.unit_class]
	if not entry.has(slot):
		return 0.0
	for term in entry[slot]["terms"]:
		if term["id"] == term_id:
			return _eval(unit, term, overrides)
	return 0.0


# Class-level constant lookup for terms that outlive their caster. Stitch's Link
# and Loose Threads both pay out through victims that may still be on the field
# after the Stitch has died, so there is no unit to resolve against — but the
# number still belongs in the registry rather than inline in the damage hook.
# Only valid for flat terms (no stat, no level scaling); returns 0.0 otherwise.
static func flat(unit_class: int, slot: String, term_id: String) -> float:
	var s := spec()
	if not s.has(unit_class) or not s[unit_class].has(slot):
		return 0.0
	for term in s[unit_class][slot]["terms"]:
		if term["id"] == term_id:
			if str(term["stat"]) != "" or bool(term["lvl"]):
				push_warning("AbilityFormulas.flat() called on a scaling term: %s" % term_id)
				return 0.0
			return float(term["coef"])
	return 0.0


# Full resolution of one ability, for the UI. `overrides` lets the level-up
# screen ask "what would this be if magic_power were 13 higher, at level 5?" —
# pass {"magic_power": 60.0, "level": 5.0} with ABSOLUTE values, not deltas.
#
# Returns:
#   { "name": String, "text": String, "template": String,
#     "terms": [ {id,label,value,display,fmt}, ... ] }
#
# `text` has the numbers already substituted, for anywhere that just wants a
# string. `template` keeps the raw "{id}" placeholders so a caller that needs to
# style individual numbers — the level-up panel colouring the ones a perk would
# change — can do its own substitution.
static func resolve(unit: UnitBase, slot: String,
		overrides: Dictionary = {}) -> Dictionary:
	var out := {"name": _slot_name(unit, slot), "text": "", "template": "", "terms": []}
	if not (unit and is_instance_valid(unit)):
		return out
	var s := spec()
	if not s.has(unit.unit_class) or not s[unit.unit_class].has(slot):
		return out
	var ability: Dictionary = s[unit.unit_class][slot]
	var text: String = str(ability.get("text", ""))
	out["template"] = text
	for term in ability["terms"]:
		var v := _eval(unit, term, overrides)
		var disp := format_value(v, str(term["fmt"]))
		out["terms"].append({
			"id": term["id"], "label": term["label"],
			"value": v, "display": disp, "fmt": term["fmt"],
		})
		text = text.replace("{%s}" % term["id"], disp)
	out["text"] = text
	return out


# All three slots at once — what the level-up panel actually calls.
static func resolve_all(unit: UnitBase, overrides: Dictionary = {}) -> Array:
	return [
		resolve(unit, PASSIVE, overrides),
		resolve(unit, ACTIVE, overrides),
		resolve(unit, ULTIMATE, overrides),
	]


# ══════════════════════════════════════════════════════════════════════════════
# Internals
# ══════════════════════════════════════════════════════════════════════════════

static func _eval(unit: UnitBase, term: Dictionary, overrides: Dictionary) -> float:
	var coef: float = float(term["coef"])
	var curve: String = str(term.get("curve", ""))
	if curve != "":
		coef = _apply_curve(unit, curve, overrides)

	if bool(term["lvl"]):
		var lvl: float = _stat(unit, "level", overrides)
		coef *= (1.0 + LVL_COEF * lvl) / (1.0 + LVL_COEF * CAL_LEVEL)

	var v := coef
	var stat: String = str(term["stat"])
	if stat != "":
		v *= _stat(unit, stat, overrides)

	match str(term["mult"]):
		"skill": v *= unit.skill_damage_multiplier
		"ult":   v *= unit.ultimate_damage_mult

	if bool(term["aspect"]):
		v *= UnitFactory.natural_aspect(unit)
	return v


# Bespoke curves, for terms whose VALUE is itself a function of a stat rather
# than a flat coefficient. Both forms resolve through _stat(), so they react to
# the level-up screen's hover preview like any other term.
#
#   "static:LO:HI"
#     Static's original shared power ratio — 0 at level 1 with little magic
#     power, 1.0 at level 50 with 100+. Already exactly the level+MAG scaling
#     this file standardises, so it was kept rather than flattened.
#
#   "lerp:<stat>:<from>:<to>:<lo>:<hi>"
#     Linear ramp: <lo> when <stat> is <from>, <hi> when it is <to>, clamped
#     outside. Used for percentages that should reward stacking a stat —
#     e.g. Bloodhound's lifesteal riding his max HP.
static func _apply_curve(unit: UnitBase, curve: String, overrides: Dictionary) -> float:
	var parts := curve.split(":")
	if parts.size() == 3 and parts[0] == "static":
		var lvl_ratio: float = clampf(_stat(unit, "level", overrides) / 50.0, 0.0, 1.0)
		var mp_ratio: float = clampf(_stat(unit, "magic_power", overrides) / 100.0, 0.0, 1.0)
		return lerpf(float(parts[1]), float(parts[2]), lvl_ratio * mp_ratio)
	if parts.size() == 6 and parts[0] == "lerp":
		var v: float = _stat(unit, parts[1], overrides)
		var t: float = clampf(inverse_lerp(float(parts[2]), float(parts[3]), v), 0.0, 1.0)
		return lerpf(float(parts[4]), float(parts[5]), t)
	push_warning("AbilityFormulas: unknown curve '%s'" % curve)
	return 0.0


static func _stat(unit: UnitBase, name: String, overrides: Dictionary) -> float:
	if overrides.has(name):
		return float(overrides[name])
	var v = unit.get(name)
	return float(v) if v != null else 0.0


static func _slot_name(unit: UnitBase, slot: String) -> String:
	if not (unit and is_instance_valid(unit)):
		return ""
	match slot:
		PASSIVE:  return unit.passive_name
		ACTIVE:   return unit.skill_name
		ULTIMATE: return unit.ultimate_name
	return ""


static func format_value(v: float, fmt: String) -> String:
	match fmt:
		"pct": return "%d%%" % int(round(v * 100.0))
		"sec": return _trim(v) + "s"
		"x":   return _trim(v) + "x"
		"num": return _trim(v)
		# dmg / heal / shield — truncate, not round: combat wraps these in int(),
		# so rounding here would show 144 for a hit that lands for 143.
		_:     return str(int(v))


# "%.3g" is not supported by GDScript's format operator — drop trailing zeros by
# hand so 1.50 reads as "1.5" and 3.00 as "3".
static func _trim(v: float) -> String:
	if absf(v - round(v)) < 0.005:
		return str(int(round(v)))
	return String.num(v, 2).rstrip("0").rstrip(".")
