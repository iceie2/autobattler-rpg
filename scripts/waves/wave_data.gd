extends Node
class_name WaveData

# ── Enemy codes ───────────────────────────────────────────────────────────────
#  M  = Goblin (melee)
#  A  = Goblin Archer (ranged)
#  S  = Goblin Shaman, Fire (ranged magic) — GSN/GSW/GSE/GSA/GSL = Normal/Water/Earth/Air/Lightning Goblin Shaman
#  B  = Orc, Earth (heavy melee) — BN/BF/BW/BA/BL = Normal/Fire/Water/Air/Lightning Orc
#  G  = Hill Giant (2×2 boss)
#  SL = Slime, Water — SLN/SLF/SLE/SLA/SLL = Normal/Fire/Earth/Air/Lightning Slime
#  LZN/LZF/LZW/LZE/LZA/LZL = Lizard, Normal/Fire/Water/Earth/Air/Lightning (far-range sniper, barely moves)
#  BRN/BRF/BRW/BRE/BRA/BRL = Bear, Normal/Fire/Water/Earth/Air/Lightning (beefy tank, low damage, bleed on swipe)
#  TLN/TLF/TLW/TLE/TLA/TLL = Troll, Normal/Fire/Water/Earth/Air/Lightning (ranged, buffs ally attack speed)
#  WUN/WUF/WUW/WUE/WUA/WUL = Wind-Up Bot, Normal/Fire/Water/Earth/Air/Lightning (light melee striker, hit + 1s stun)
#  WY = Sky Wyvern (2×2, the Air decade's anchor); TH = Tidepool Horror (2×2, the Water decade's anchor)
#  HRP = Harpy (Air, evasive — foreshadows the round-15 Gale Warden)
#  CH  = Coral Husk (Water, self-shields — foreshadows the round-25 Tidecaller)
#  FG = Fire Giant (2×2, Fire decade); STG = Storm Giant (2×2, Lightning decade)
#  KHA = Khagan (wave-10 boss, mount-swap fight); TRI = The Triarch (relocated to wave 70)
#  HYN/HYF/HYW/HYE/HYA/HYL = Hydra (relocated to wave 80; player picks the element pre-battle)
#  Bosses aren't listed in the waves below — WaveScaler.boss_code_for(round) dispatches them directly.
#  AH = Ant Hill


# To add a new enemy type:
#   1. Add its factory in enemy_factory.gd, register it in CODE_TO_TYPE + create_by_type
#   2. Register its code + role in wave_scaler.gd (CODE_ROLE, UNIT_POWER, FILLER_POOL)
#   3. Use the code in waves below (spawn_enemies() dispatches via EnemyFactory.create_by_code, no per-code case needed)
#
# ── Wave format ───────────────────────────────────────────────────────────────
# Each wave is just {code: count}. WaveScaler auto-places units by role:
#   FRONT role  → rows 3 → 2 (frontline, closest to player)
#   BACK role   → rows 0 → 1 (backline, farthest from player)
#   BOSS role   → rows 1–2 (centered)
# Units are spread evenly across the row. No manual positioning needed.

# Difficulty intent for the full run (roguelite, 2026-07-12 per user):
#   wave 10  — a good player clears it first try with zero crystal upgrades
#   wave 20  — clearable without upgrades only when the stars align
#   wave 30  — impossible without crystal upgrades
# Three ramps stack to get there: base composition power, enemy level (fixed
# waves 11+ spawn at WaveScaler.enemy_level_for_round — ~3-5 at wave 11 up to
# ~18-20 at wave 29; waves 1-9 stay level 1), and the round-11+ enemy stat
# multiplier (Balance.enemy_late_hp_mult/dmg_mult, applied in WaveDirector).
# Real per-wave difficulty (summed score_unit, level+mult baked in) climbs from
# ~7.7k at wave 11 to ~57k at wave 29 — measure with arena --mode=power, not the
# raw UNIT_POWER budget (which only counts level-1 composition, not the ramps).
# Heavy tier (2026-07-23, per user): the round-5/15/25 elites now double as
# recurring "heavy" anchors in later waves — a big single body that carries a
# lot of power, so a wave hits its difficulty target with far FEWER bodies than
# a swarm of fodder would need. This replaced the old "elites EXCLUSIVE to
# 5/15/25" rule: the retune below was toning down enemy COUNT (board was ~half
# full by wave ~12, way too early for a run headed to wave 100) while holding
# felt difficulty (score_unit power — see arena --mode=power). Unlock is implicit
# in run order: you can't reach wave 11 without having beaten the wave-5 Hill
# Giant, wave 16 without the wave-15 Ant Hill, wave 26 without the wave-25 Stat
# Stealer — so each heavy only appears AFTER you first fought it as an elite.
#   G  (Hill Giant, 2×2) — heavy anchor from wave 11+
#   SS (Stat Stealer, 1×1) — heavy anchor from wave 26+
#   AH (Ant Hill) is deliberately NOT used as a heavy — it SPAWNS ants, which
#      fights the whole point (fewer bodies); it stays elite-only for now.
# When one of these codes appears in a normal wave, WaveDirector demotes it
# (no is_elite flag, no elite coin/crystal bounty, capped XP) — see
# create_enemy_for_entry + WaveScaler.crystals_for_unit.
# Boss rounds (10/20/30) and elite rounds (5/15/25) never reach these tables —
# WaveScaler dispatches them first, which is why those slots return {}.
# ── Wave names (prep-phase dossier) ───────────────────────────────────────────
# Promoted from the trailing comments on each wave below (2026-07-27) so the
# player can read the same one-line characterisation the designer wrote. These
# are FLAVOUR — the mechanically load-bearing part of the dossier is the derived
# threat readout (WaveScaler.threat_profile), which stays accurate even for the
# generated Act 7 waves that have no entry here.
# Format: "Name — what it is". Elite/boss rounds are omitted (the encounter
# names itself); rounds 61-100 are generated and have no fixed identity.
const WAVE_NAMES := {
	1:  "First contact — a lone goblin",
	2:  "The pair — a goblin and an archer",
	3:  "Skirmish line — goblins behind archers",
	4:  "The warband — a shaman joins the line",
	6:  "Clockwork patrol — wind-up bots under covering fire",
	7:  "Beasts and snipers — orcs behind lizard fire",
	8:  "The raid — a mixed goblin force",
	9:  "Arrow storm — six archers behind a thin line",
	11: "The wyvern descends — first heavy anchor, escorted",
	12: "Slime flood — a swarm spike on the wind",
	13: "Firing line — snipers behind the wyvern",
	14: "The first flock — harpies on the wind",
	16: "Bear wall — an HP check behind the wyvern",
	17: "Gale of gears — fast strikers and stuns",
	18: "Sky legion — mono-element Air press",
	19: "The muster — combined arms before Skyrender",
	21: "The undertow — a water orc press",
	22: "Slime flood II — a swarm with a twin-anchor core",
	23: "Sniper nest — a ranged wall behind the twin horrors",
	24: "The horde — fodder swarm, anchored",
	26: "The drowned vanguard — an ogre and twin horrors",
	27: "The tide wall — a deep water-heavy frontline",
	28: "The rusted tide — a waterlogged machine press",
	29: "The last gate — everything short of the Drowned Maw",
	31: "The earthen gate — twin giants, ogre debut",
	32: "Crystal flood — slime swarm behind twin giants",
	33: "Quarry snipers — a ranged wall behind giant and ogre",
	34: "Root and stone — an orc press",
	36: "Granite wall — an HP check",
	37: "Deep roots — a mixed press",
	38: "Petrified grove — twin giants",
	39: "The last stone — everything short of the Fire decade",
	41: "The ember gate — hellhound debut",
	42: "The hunting pack — hellhounds stack attack speed",
	43: "Phoenix roost — a ranged wall behind the giants",
	44: "The bull charge — a minotaur press",
	46: "Magma flood — slime swarm behind the giants",
	47: "The firing line — a mixed ranged press",
	48: "The forge — bear and bot core, minotaur anchor",
	49: "The last forge — everything short of the Lightning decade",
	51: "The first strike — storm giant debut",
	52: "The murder — storm crows stack flock speed",
	53: "The high ground — a layered ranged press",
	54: "Rolling thunder — a bear and bot core",
	56: "The surge — slime swarm behind the giants",
	57: "The storm front — a full ranged wall",
	58: "The anvil — an HP check behind twin giants",
	59: "The eye of the storm — the last wave before the endgame",
}

# Player-facing name for a round, or "" when it has none (elite/boss rounds name
# themselves; Act 7 waves are generated). Callers hide the line on "".
static func name_for(round_number: int) -> String:
	return String(WAVE_NAMES.get(round_number, ""))

static func get_wave(round_number: int) -> Dictionary:
	match round_number:
		1:  return {"M": 1}
		2:  return {"M": 1, "A": 1}
		3:  return {"M": 2, "A": 2}
		4:  return {"M": 2, "A": 2, "S": 1}
		5:  return {"AH": 1, "M": 2}
		6:  return {"WUN": 3, "A": 2}
		7:  return {"BN": 2, "LZN": 2}
		8:  return {"M": 4, "A": 2, "BN": 1, "LZN": 1}
		9:  return {"WUN": 2, "BN": 2, "A": 6}
		10: return {}   # boss: Khagan
		# ── Act 2 (11-19): the AIR decade, ramping toward Skyrender ───────────
		# Body counts cut ~30-45% vs the old comps; power held via the 2×2
		# anchor (big score) + the unchanged level/late-mult ramp.
		# RETINTED 2026-08-02. These waves were authored before the decade→element
		# map was locked and were only ever declared "Air" retroactively — the
		# comps were element rainbows (wave 18 was literally a FIRE legion sitting
		# inside the Air decade) anchored on the Hill Giant, an EARTH creature.
		# Now on-element: the "_air" variant families (BA/BRA/TLA/LZA/WUA/SLA/GSA)
		# plus the new Sky Wyvern as the decade's own 2×2 anchor, matching how
		# Earth/Fire/Lightning were built. Almost every swap is WITHIN a mob family
		# (all 6 elemental variants share one stat block), so the power curve is
		# preserved by construction rather than by re-tuning — the only real delta
		# is G→WY, and WY is statted to land in the demoted-Giant slot.
		# A handful of Normal bodies (A, SLN, LZN, BN) are left in deliberately as
		# neutral filler — the built decades aren't 100% pure either (wave 31 has
		# an "A", wave 32 has SLN×2).
		11: return {"WY": 1, "BRA": 1, "A": 3, "TLA": 1}                          # the wyvern descends — first heavy anchor, escorted (6)
		12: return {"SLA": 7, "SLN": 3, "TLA": 1, "GSA": 2}                       # slime flood — swarm spike, capped (13)
		13: return {"WY": 1, "LZA": 3, "LZN": 2, "TLA": 1, "A": 1}                # firing line — snipers behind the wyvern (8)
		14: return {"WY": 1, "BA": 1, "HRP": 1, "GSA": 2}                         # the first flock — HARPY DEBUT, one round before the Gale Warden (5)
		15: return {}   # elite round
		16: return {"WY": 1, "BRA": 2, "HRP": 1, "TLA": 2, "GSA": 1}              # bear wall — HP check behind the wyvern (7)
		17: return {"WY": 1, "WUA": 3, "HRP": 1, "LZA": 2, "GSA": 1}              # gale of gears — fast strikers + stuns (8)
		18: return {"WY": 1, "BA": 2, "HRP": 1, "WUA": 1, "TLA": 2, "GSA": 1}     # sky legion — mono-element Air press (8)
		19: return {"WY": 1, "BA": 2, "HRP": 1, "BRA": 1, "GSA": 2, "TLA": 1, "LZA": 1}  # the muster — combined arms before Skyrender (9)
		20: return {}   # boss: Skyrender (Air) — see WaveScaler.boss_code_for
		# ── Act 3 (21-29): the WATER decade; only upgraded rosters survive ────
		# Retinted 2026-08-02 on the same basis as Act 2 above — the "_water"
		# families (BW/BRW/TLW/LZW/WUW/SL/GSW; note water Slime is plain "SL" and
		# water Orc is "BW") anchored on the new Tidepool Horror. Wave 21's old
		# "one orc of every element" rainbow and wave 28's "bot rainbow" were the
		# two most theme-breaking comps in the game — both are now on-element
		# presses of the same families at the same body counts.
		21: return {"TH": 1, "BW": 4, "B": 1, "CH": 1, "TLW": 2, "LZW": 1}        # the undertow — CORAL HUSK DEBUT, four rounds before the Tidecaller (10)
		22: return {"TH": 2, "SL": 4, "SLN": 2, "WUW": 1, "TLW": 1, "GSW": 1}     # slime flood II — swarm with a twin-anchor core (11)
		23: return {"TH": 2, "LZW": 4, "LZN": 1, "CH": 1, "TLW": 1, "GSW": 1}     # sniper nest — ranged wall behind the twin horrors (10)
		24: return {"TH": 1, "SL": 4, "A": 4, "BW": 2, "WUW": 2, "TLW": 1, "BRW": 1}  # the horde — fodder swarm spike, capped, anchored (15)
			# ^ the one wave whose retint had to leave the mob families: goblins have
			# no Water variant, so the 5 "M" fodder became Slimes (the Water swarm
			# body). Slime scores under Goblin, which measured a real ~6% drop, so
			# one Slime is traded for a second Wind-Up Bot to hold the wave's power.
			# The 4 "A" archers stay — there's no water-variant cheap ranged body,
			# and a fodder-horde wave needs them.
		25: return {}   # elite round
		26: return {"OG": 1, "TH": 2, "BRW": 2, "WUW": 1, "TLW": 1, "GSW": 1, "BW": 1}  # the drowned vanguard — ogre + twin horrors (9)
		27: return {"TH": 2, "BRW": 2, "BW": 2, "CH": 1, "LZW": 1, "TLW": 1, "GSW": 1}  # the tide wall — deep water-heavy frontline (10)
		28: return {"OG": 1, "TH": 1, "WUW": 5, "WUN": 1, "BRW": 1, "TLW": 1, "GSW": 1}  # the rusted tide — waterlogged bot press + ogre (11)
		29: return {"TH": 2, "OG": 1, "BRW": 2, "BW": 2, "CH": 1, "TLW": 1, "GSW": 1}  # the last gate — everything short of the Drowned Maw (10)
		30: return {}   # boss: The Drowned Maw (Water) — see WaveScaler.boss_code_for
		# ── Act 4 (31-40): the Earth decade ────────────────────────────────────
		# First of the elemental decades proper (2026-07-24 structure — see
		# [[wave_structure_1_100]]): 11-20/21-30 retroactively count as Air/Water,
		# so 31-40 is the first NEW decade, themed Earth. Composition mostly earth-
		# element variants of existing families (BRE/GSE/TLE/LZE/WUE/"B"=orc_earth,
		# SLE) plus the new Earth-flavored Ogre/Stone Golem/Crystal Crab/Root
		# Walker (2026-07-24, [[beast_tier_enemies]]) as anchors/variety — no new
		# mechanics, only new bodies.
		# EVERY regular wave keeps TWO Hill Giants (thematically fitting — it's
		# already an Earth creature by element). This isn't just taste, it's the
		# score_unit() math: the ×2.5 2×2-cell multiplier means no amount of 1×1
		# Beast-tier heavies matches even one Giant's power contribution — a
		# single-giant version of this decade measured a hard cliff to ~1/3 of
		# round 29's power. Two giants per wave gives a smooth 45k→84k climb
		# across 31-39 (measured via arena --mode=power), comparable in scale to
		# how 21-29 climbed (~28k→57k) before ITS boss spike. Deliberately NOT
		# tuned to match/exceed round 30's ~90k: the Hydra is a documented
		# deliberate spike ("wave 30 — impossible without crystal upgrades", see
		# this file's header), not a smooth curve midpoint — round 29 sits well
		# under it too, so 31 doing the same is consistent, not a regression.
		# Rounds 35/40 (elite/boss) are handled separately per user direction —
		# return {} here, same as every other decade's elite/boss slots.
		31: return {"G": 2, "OG": 1, "BRE": 1, "GSE": 1, "A": 1}                  # the earthen gate — decade opener, twin giants + ogre debut (5)
		32: return {"G": 2, "SLE": 4, "SLN": 2, "CC": 1}                          # crystal flood — slime swarm behind twin giants (9)
		33: return {"G": 2, "OG": 1, "LZE": 2, "TLE": 1, "CC": 1}                 # quarry snipers — ranged wall behind giant + ogre (7)
		34: return {"G": 2, "B": 1, "BRE": 1, "WUE": 2, "GSE": 1}                 # root and stone — orc press, single-heavy-tier escort (7)
		36: return {"G": 2, "OG": 1, "BRE": 2, "TLE": 1}                         # granite wall — HP check, one beast-tier heavy only (6)
		37: return {"G": 2, "OG": 1, "LZE": 2, "TLE": 1, "WUE": 1}               # deep roots — mixed press, one beast-tier heavy only (7)
		38: return {"G": 2, "BRE": 2, "GSE": 1, "TLE": 1, "LZE": 1}              # petrified grove — twin giants, no sustain stacking (7)
		39: return {"G": 2, "OG": 1, "BRE": 2, "TLE": 1, "GSE": 1, "B": 1}       # the last stone — everything short of the Fire decade (8)
		35: return {}   # elite round (handled separately)
		40: return {}   # boss round (handled separately)
		# ── Act 5 (41-50): the Fire decade ─────────────────────────────────────
		# Second new elemental decade. Same shape as Act 4: fire-element variants
		# of existing families (S=goblin_shaman_fire, BF, BRF, TLF, LZF, WUF, SLF,
		# plus MT/Minotaur which is already Fire by element) alongside the new
		# Fire roster (Fire Giant / Hellhound / Ember Phoenix, 2026-07-24) — no
		# new mechanics, only new bodies.
		# The anchor is the FIRE GIANT, not the Hill Giant: each elemental decade
		# gets its own 2×2 body so the theme holds while the power math still
		# works (score_unit's ×2.5 cell_size multiplier means only a large unit
		# can anchor a wave — see Act 4's notes). FG is built at ~60% of G's
		# statline precisely so it drops into the slot a demoted Hill Giant used
		# to fill; see create_fire_giant.
		# Two hard-won constraints from Act 4, both kept here:
		#   • TWO large anchors per wave (one isn't enough to hold the curve)
		#   • at most ONE non-anchor heavy per wave — stacking several self-shield
		#     /regen bodies causes real combat stalls that score_unit can't see,
		#     so this is verified with live --mode=sim, not just --mode=power.
		41: return {"FG": 2, "HH": 2, "S": 1, "BF": 1}                            # the ember gate — decade opener, hellhound debut (6)
		42: return {"FG": 2, "HH": 3, "S": 1, "BF": 1}                            # the hunting pack — hellhounds stack Hunting Pack aspd (7)
		43: return {"FG": 2, "EP": 2, "LZF": 2, "BF": 1}                          # phoenix roost — ranged wall behind the giants (7)
		44: return {"FG": 2, "MT": 1, "BRF": 1, "WUF": 2, "S": 1}                 # the bull charge — minotaur press (7)
		46: return {"FG": 2, "SLF": 4, "HH": 1, "S": 1}                           # magma flood — slime swarm behind the giants (8)
		47: return {"FG": 2, "EP": 1, "LZF": 2, "TLF": 1, "HH": 1}                # the firing line — mixed ranged press (7)
		48: return {"FG": 2, "MT": 1, "BRF": 2, "WUF": 1, "S": 1}                 # the forge — bear/bot core, minotaur anchor (7)
		49: return {"FG": 2, "MT": 1, "HH": 2, "EP": 1, "BRF": 1, "BF": 1}        # the last forge — everything short of the Lightning decade (8)
		45: return {}   # elite round (handled separately)
		50: return {}   # boss round (handled separately)
		# ── Act 6 (51-60): the Lightning decade ────────────────────────────────
		# Last of the five elemental decades (61-100 is the mixed-element,
		# difficulty-focused endgame — see [[wave_structure_1_100]]). The existing
		# "_lightning" variant families (BL/BRL/TLL/LZL/WUL/SLL/GSL) already cover
		# most of the bodies, so this decade only needed two new units: the Storm
		# Giant (2×2 anchor, same role Fire Giant plays for 41-50) and the Storm
		# Crow (fast ranged flock harasser).
		# Same three constraints as Acts 4-5: TWO large anchors per wave, at most
		# ONE non-anchor heavy, and no monotone comps (a wave of near-identical
		# bodies is what produced the worst stall in the Fire decade).
		51: return {"STG": 2, "WUL": 2, "GSL": 1, "A": 1}                         # the first strike — decade opener, storm giant debut (6)
		52: return {"STG": 2, "SC": 3, "GSL": 1}                                  # the murder — storm crows stack flock aspd (6)
		53: return {"STG": 2, "LZL": 2, "SC": 2, "BL": 1}                         # the high ground — layered ranged press (7)
		54: return {"STG": 2, "BRL": 1, "WUL": 2, "GSL": 1, "BL": 1}              # rolling thunder — bear/bot core (7)
		56: return {"STG": 2, "SLL": 4, "SC": 1, "WUL": 1}                        # the surge — slime swarm behind the giants (8; no healer here on purpose — a shaman's heal on top of splitting slimes maximized the regen density that triggers the known high-round stall, see the blocker note in [[wave_structure_1_100]])
		57: return {"STG": 2, "SC": 2, "LZL": 2, "TLL": 1}                        # the storm front — full ranged wall (7)
		58: return {"STG": 2, "BRL": 2, "WUL": 2, "GSL": 1}                       # the anvil — HP check, twin giants (7)
		59: return {"STG": 2, "BRL": 1, "SC": 2, "WUL": 1, "LZL": 1, "BL": 1, "GSL": 1}  # the eye of the storm — last wave before the mixed endgame (9)
		55: return {}   # elite round (handled separately)
		60: return {}   # boss round (handled separately)
		# ── Act 7 (61-100): the mixed-element difficulty endgame ───────────────
		# GENERATED, not hand-authored — see _mixed_endgame_wave below for why.
		_:
			if round_number >= 61 and round_number <= 100:
				return _mixed_endgame_wave(round_number)
			return {}

# ── Act 7 generator (61-100) ──────────────────────────────────────────────────
# The five elemental decades (1-60) are hand-authored because each wave has a
# specific identity to express. Act 7 doesn't: per the locked 1-100 structure
# it's "mixed elements, about being difficult" — 32 regular waves (61-64, 66-69,
# 71-74, …, 96-99; the 5s and 10s are elite/boss rounds dispatched before this
# is ever reached) with no per-wave theme to hand-craft. Writing 32 literal
# dicts would mean repeating the composition rules 32 times and re-tuning them
# 32 times; generating instead encodes those rules ONCE.
#
# Fully DETERMINISTIC (pure arithmetic on the round number, no randi()). That's
# required, not a nicety: the wave spec is generated more than once per round —
# the round-start formation preview and again on Ready — and any RNG here would
# let the previewed board differ from the one that actually spawns. Same reason
# ELITE_BY_ROUND exists in WaveScaler.
#
# Encodes the four composition rules learned building Acts 4-6, all of which
# were paid for with real stalls or power cliffs:
#   1. exactly TWO large (2×2) anchors — only a large body holds the power curve
#      (score_unit's ×2.5 cell_size multiplier); one anchor measured a cliff to
#      ~1/3 power. The anchor giant rotates so the act doesn't look monotone.
#   2. exactly ONE non-anchor heavy — stacking self-shield/regen heavies causes
#      combat stalls score_unit cannot see.
#   3. exactly ONE sustain unit (healer/regen) — a healer piled onto a regen-heavy
#      wave was the single worst stall found (wave 56, Lightning decade). The
#      FRONT/BACK fill pools below deliberately contain NO sustain units, so this
#      count can never drift above one.
#   4. no monotone comps — the fill alternates front/back and strides the pools
#      with round-varying offsets so consecutive waves don't repeat.
# Body count grows 7 → 10 across the act; every wave stays well under the
# 36-cell enemy zone (the original "board is half full by wave 12" complaint).
const _ENDGAME_ANCHORS: Array[String] = ["G", "FG", "STG"]          # Hill/Fire/Storm Giant
const _ENDGAME_HEAVIES: Array[String] = ["OG", "MT", "GY", "SG", "CC", "SS"]
# Sustain = anything that heals or regenerates. Exactly one per wave (rule 3).
const _ENDGAME_SUSTAIN: Array[String] = [
	"GSN", "S", "GSW", "GSE", "GSA", "GSL",      # shamans — heal + regen aura
	"TLN", "TLF", "TLW", "TLE", "TLA", "TLL",    # trolls — self-regen
	"EP", "RW",                                   # phoenix regen, root walker aura
]
# Fill pools — NO sustain units in either, so rule 3 holds by construction.
const _ENDGAME_FRONT: Array[String] = [
	"BN", "BF", "BW", "BA", "BL", "B",                     # orcs, all elements
	"BRN", "BRF", "BRW", "BRE", "BRA", "BRL",              # bears, all elements
	"WUN", "WUF", "WUW", "WUE", "WUA", "WUL",              # wind-up bots
	"HH",                                                   # hellhound
]
const _ENDGAME_BACK: Array[String] = [
	"LZN", "LZF", "LZW", "LZE", "LZA", "LZL",              # lizards, all elements
	"SC", "A",                                              # storm crow, goblin archer
]

static func _mixed_endgame_wave(r: int) -> Dictionary:
	var counts: Dictionary = {}
	# Rule 1 — two large anchors, rotating which giant leads the wave.
	counts[_ENDGAME_ANCHORS[r % _ENDGAME_ANCHORS.size()]] = 2
	# Rule 2 — exactly one non-anchor heavy.
	var heavy: String = _ENDGAME_HEAVIES[(r / 2) % _ENDGAME_HEAVIES.size()]
	counts[heavy] = counts.get(heavy, 0) + 1
	# Rule 3 — exactly one sustain unit.
	var sustain: String = _ENDGAME_SUSTAIN[(r / 3) % _ENDGAME_SUSTAIN.size()]
	counts[sustain] = counts.get(sustain, 0) + 1
	# Rule 4 — fill the rest, alternating melee/ranged, striding both pools by a
	# round-varying offset so neighbouring rounds don't draw the same bodies.
	var extra: int = 3 + int(float(r - 61) / 13.0)   # 3 at r=61 → 6 by r=100
	for i in range(extra):
		var pool: Array = _ENDGAME_FRONT if i % 2 == 0 else _ENDGAME_BACK
		var pick: String = pool[(r * 7 + i * 5) % pool.size()]
		counts[pick] = counts.get(pick, 0) + 1
	return counts
