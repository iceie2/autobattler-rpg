extends Node
class_name WaveScaler

# Renamed 2026-08-07 (user): tiers were EASY/NORMAL/HARD, but tier 0 IS the
# baseline everyone plays — calling it "easy" implied a concession and made
# "normal" ambiguous between the baseline and the first scaled tier (it caused
# real target-slippage during the team-size retune). Tier 0 is now NORMAL; the
# two scaled-up tiers are VETERAN and BRUTAL.
enum Difficulty { NORMAL, VETERAN, BRUTAL }
enum Role      { FRONT, BACK, BOSS }

# Total-power multiplier relative to the baseline (Normal) wave.
# Normal base power × this mult = total power budget for Veteran/Brutal.
#
# 1.75/3.5 → 1.5/2.0 (owner call, 2026-09-20). Two reasons, one measured and one
# design: 3.5× made the hard lane not worth walking, which defeats the point of a
# map whose lanes are supposed to be real alternatives; and the old numbers were
# never actually delivered anyway — priced in UNIT_POWER they measured anywhere
# from ×1.17 to ×5.37. Now that the budget is priced in the same currency the
# THREAT readout uses (see WaveScaler.fill_to_score), these are honest: a Veteran
# wave really is half again a Normal one.
const DIFFICULTY_MULT: Array[float] = [1.0, 1.5, 2.0]

# ── Role registry ─────────────────────────────────────────────────────────────
# To add a new enemy: register its code here. That's it.
#   FRONT → rows 3 → 2  (melee, chargers)
#   BACK  → rows 0 → 1  (ranged, supports)
#   BOSS  → rows 1–2    (large/boss units, centered)
const CODE_ROLE: Dictionary = {
	"M":  Role.FRONT,  # Goblin
	"A":  Role.BACK,   # Goblin Archer
	"S":  Role.BACK,   # Goblin Shaman (Fire) — was plain "Goblin Shaman"
	"GSN": Role.BACK,  # Goblin Shaman (Normal)
	"GSW": Role.BACK,  # Goblin Shaman (Water)
	"GSE": Role.BACK,  # Goblin Shaman (Earth)
	"GSA": Role.BACK,  # Goblin Shaman (Air)
	"GSL": Role.BACK,  # Goblin Shaman (Lightning)
	"B":  Role.FRONT,  # Orc (Earth) — was "Orc Brute"
	"BN": Role.FRONT,  # Orc (Normal)
	"BF": Role.FRONT,  # Orc (Fire)
	"BW": Role.FRONT,  # Orc (Water)
	"BA": Role.FRONT,  # Orc (Air)
	"BL": Role.FRONT,  # Orc (Lightning)
	"G":  Role.BOSS,   # Hill Giant (2×2) — elite-tier now, still centered like a boss when placed
	"SL": Role.FRONT,  # Slime (Water) — was plain "Slime"
	"SLN": Role.FRONT, # Slime (Normal)
	"SLF": Role.FRONT, # Slime (Fire)
	"SLE": Role.FRONT, # Slime (Earth)
	"SLA": Role.FRONT, # Slime (Air)
	"SLL": Role.FRONT, # Slime (Lightning)
	"LZN": Role.BACK,  # Lizard (Normal) — far-range, barely moves
	"LZF": Role.BACK,  # Lizard (Fire)
	"LZW": Role.BACK,  # Lizard (Water)
	"LZE": Role.BACK,  # Lizard (Earth)
	"LZA": Role.BACK,  # Lizard (Air)
	"LZL": Role.BACK,  # Lizard (Lightning)
	"BRN": Role.FRONT, # Bear (Normal) — beefy tank
	"BRF": Role.FRONT, # Bear (Fire)
	"BRW": Role.FRONT, # Bear (Water)
	"BRE": Role.FRONT, # Bear (Earth)
	"BRA": Role.FRONT, # Bear (Air)
	"BRL": Role.FRONT, # Bear (Lightning)
	"TLN": Role.BACK,  # Troll (Normal) — ranged attack-speed support
	"TLF": Role.BACK,  # Troll (Fire)
	"TLW": Role.BACK,  # Troll (Water)
	"TLE": Role.BACK,  # Troll (Earth)
	"TLA": Role.BACK,  # Troll (Air)
	"TLL": Role.BACK,  # Troll (Lightning)
	"WUN": Role.FRONT, # Wind-Up Bot (Normal) — light melee striker
	"WUF": Role.FRONT, # Wind-Up Bot (Fire)
	"WUW": Role.FRONT, # Wind-Up Bot (Water)
	"WUE": Role.FRONT, # Wind-Up Bot (Earth)
	"WUA": Role.FRONT, # Wind-Up Bot (Air)
	"WUL": Role.FRONT, # Wind-Up Bot (Lightning)
	"SK": Role.FRONT,  # Skeleton
	"R":  Role.FRONT,  # Rat
	"TRI": Role.FRONT, # The Triarch (1×1 — opens in its melee phase)
	"SS": Role.FRONT,  # Stat Stealer (1×1 elite)
	"AH": Role.BOSS,   # Ant Hill (2×2 — stationary spawner)
	"KHA": Role.BOSS,  # Khagan (2×2 while mounted — phase 1)
	"SKR": Role.BOSS,   # Skyrender (2×2 — wave-20 Air boss)
	"DMW": Role.BOSS,   # The Drowned Maw (2×2 — wave-30 Water boss)
	"CLT": Role.BOSS,   # Cloven Titan (2×2 — wave-40 Earth boss)
	"EMB": Role.BOSS,   # Emberhollow (2×2 — wave-50 Fire boss)
	"ARC": Role.BOSS,   # Arcfang (2×2 — wave-60 Lightning boss)
	"GRV": Role.BOSS,   # The Gravekeeper (2×2 — wave-90 mixed boss)
	"ARCH": Role.BOSS,  # The Architect (3×3 — the wave-100 finale)
	"EMH": Role.FRONT,  # Ember Heart — FRONT on purpose: it must stand between the player and Emberhollow so nearest-targeting engages it first
	"HYN": Role.BOSS, "HYF": Role.BOSS, "HYW": Role.BOSS,   # Hydra (all 6 elements, 2×2 final boss)
	"HYE": Role.BOSS, "HYA": Role.BOSS, "HYL": Role.BOSS,
	# Beast tier (2026-07-24) — 1×1 heavies, all melee frontline.
	"OG": Role.FRONT,  # Ogre
	"MT": Role.FRONT,  # Minotaur
	"GY": Role.FRONT,  # Gargoyle
	"SG": Role.FRONT,  # Stone Golem
	# Earth-decade variety (2026-07-24, wave 31-40).
	"CC": Role.FRONT,  # Crystal Crab
	"RW": Role.BACK,   # Root Walker
	# Fire-decade roster (2026-07-24, wave 41-50).
	"FG": Role.BOSS,   # Fire Giant (2×2 — centered like every other large body)
	"HH": Role.FRONT,  # Hellhound
	"EP": Role.BACK,   # Ember Phoenix
	# Lightning-decade roster (2026-07-24, wave 51-60).
	"STG": Role.BOSS,  # Storm Giant (2×2)
	"SC": Role.BACK,   # Storm Crow
	# Air/Water-decade anchors (2026-08-02, wave 11-20 / 21-30).
	"WY": Role.BOSS,   # Sky Wyvern (2×2 — the Air decade's anchor)
	"TH": Role.BOSS,   # Tidepool Horror (2×2 — the Water decade's anchor)
	"HRP": Role.FRONT, # Harpy (fast melee harasser — foreshadows the Gale Warden's evasion)
	"CH": Role.FRONT,  # Coral Husk (slow wall — foreshadows the Tidecaller's shields)
	# Elemental elites (2026-07-27) — one per decade, see ELITE_BY_ROUND.
	"GW": Role.FRONT,  # Gale Warden (1×1 evasive skirmisher)
	"TC": Role.BACK,   # Tidecaller (1×1 support elite — hangs back behind its escort)
	"TCC": Role.BOSS,  # Terracotta Colossus (2×2 — centered like every other large body)
	"MH": Role.BOSS,   # Magma Heart (2×2 stationary vent)
	"TPC": Role.BACK,  # Tempest Conduit (1×1 ranged chain-caster)
	"MW": Role.BOSS,   # Mirrorplate Warden (2×2 reflector)
	"AD": Role.BOSS,   # Aspect Devourer (2×2 element-cycling capstone)
}

# Codes that occupy a 2×2 cell block
const CODE_IS_LARGE: Dictionary = {
	"G": true,
	"FG": true,   # Fire Giant — the Fire decade's 2×2 anchor (2026-07-24)
	"STG": true,  # Storm Giant — the Lightning decade's 2×2 anchor (2026-07-24)
	"WY": true,   # Sky Wyvern — the Air decade's 2×2 anchor (2026-08-02)
	"TH": true,   # Tidepool Horror — the Water decade's 2×2 anchor (2026-08-02)
	"AH": true,
	"TCC": true,  # Terracotta Colossus — the Earth decade's elite wall (2026-07-27)
	"MH": true,   # Magma Heart — the Fire decade's elite vent (2026-07-27)
	"MW": true,   # Mirrorplate Warden — round-85 elite (2026-07-27)
	"AD": true,   # Aspect Devourer — round-95 capstone elite (2026-07-27)
	"KHA": true,
	"SKR": true,   # Skyrender — wave-20 Air boss (2026-07-27)
	"DMW": true,   # The Drowned Maw — wave-30 Water boss (2026-07-28)
	"CLT": true,   # Cloven Titan — wave-40 Earth boss (2026-07-28)
	"EMB": true,   # Emberhollow — wave-50 Fire boss (2026-07-28)
	"ARC": true,   # Arcfang — wave-60 Lightning boss (2026-07-29)
	"GRV": true,   # The Gravekeeper — wave-90 mixed boss (2026-07-29)
	"ARCH": true,  # The Architect — wave-100 finale; 3×3, see cell_size_for_code
	"HYN": true, "HYF": true, "HYW": true, "HYE": true, "HYA": true, "HYL": true,
}

# ── Power costs (rough unit strength used for budget system) ──────────────────
# Normal (baseline) wave power is the reference. Veteran/Brutal spend their leftover budget on
# random filler units pulled from FILLER_POOL (ordered strongest → weakest).
const UNIT_POWER: Dictionary = {
	"R":  15,   # Rat         — very cheap swarm
	"SL": 25, "SLN": 25, "SLF": 25, "SLE": 25, "SLA": 25, "SLL": 25,  # Slime (all 6 elements) — tanky but slow
	"SK": 25,   # Skeleton    — glass cannon
	"M":  30,   # Goblin      — basic melee
	"A":  30,   # Goblin Archer
	"S":  55, "GSN": 55, "GSW": 55, "GSE": 55, "GSA": 55, "GSL": 55,  # Goblin Shaman (all 6 elements)
	"LZN": 40, "LZF": 40, "LZW": 40, "LZE": 40, "LZA": 40, "LZL": 40,  # Lizard (all 6 elements) — far range + burst snipe, but barely moves and dies fast if rushed
	"TLN": 70, "TLF": 70, "TLW": 70, "TLE": 70, "TLA": 70, "TLL": 70,  # Troll (all 6 elements) — no direct damage, but a real attack-speed threat multiplier for the whole side
	"B":  95, "BN": 95, "BF": 95, "BW": 95, "BA": 95, "BL": 95,  # Orc (all 6 elements)
	"BRN": 100, "BRF": 100, "BRW": 100, "BRE": 100, "BRA": 100, "BRL": 100,  # Bear (all 6 elements) — beefiest 1×1 HP pool, but low damage output
	"WUN": 90, "WUF": 90, "WUW": 90, "WUE": 90, "WUA": 90, "WUL": 90,  # Wind-Up Bot (all 6 elements) — light melee striker, hit + stun
	# Beast tier (2026-07-24) — 1×1 heavies, one notch above Bear/Wind-Up Bot
	# (90-100), below the elite-heavy tier (Hill Giant 300 / Stat Stealer 150).
	"OG": 150,  # Ogre         — bruiser, Bloodrage below 50% hp
	"MT": 145,  # Minotaur     — faster bruiser, Savage Charge aspd ramp
	"GY": 140,  # Gargoyle     — tanky bleed-applier, self-regen
	"SG": 170,  # Stone Golem  — pure wall, self-shield, no passive
	"CC": 105,  # Crystal Crab — basic-mob band, self-shield + aspd ramp
	"RW": 75,   # Root Walker  — basic-mob band, slow + ally regen aura
	# Fire decade (2026-07-24). FG is priced at ~60% of Hill Giant's 300 because
	# its statline is built at 60% of G's (G gets demoted by HEAVY_STAT_MULT in
	# normal waves; FG isn't an elite so it spawns full — same effective slot).
	"FG": 180,  # Fire Giant   — the Fire decade's 2×2 anchor
	"HH": 95,   # Hellhound    — fast pack melee, burn bite
	"EP": 110,  # Ember Phoenix — ranged burst + self-regen
	# Lightning decade (2026-07-24) — STG priced like FG, same anchor slot.
	"STG": 180, # Storm Giant  — the Lightning decade's 2×2 anchor
	"SC": 90,   # Storm Crow   — fast ranged harasser, flock aspd
	# Air/Water decades (2026-08-02) — priced like FG/STG, same anchor slot.
	"WY": 180,  # Sky Wyvern      — the Air decade's 2×2 anchor
	"TH": 180,  # Tidepool Horror — the Water decade's 2×2 anchor
	"HRP": 90,  # Harpy      — basic-mob band (Storm Crow's slot); evasion is
				# effective-HP score_unit can't see, but 12% is small enough to ignore
	"CH": 105,  # Coral Husk — basic-mob band (Crystal Crab's slot), self-shield wall
	"G":  300,  # Hill Giant  — elite-tier
	"TRI": 350, # The Triarch — 3-phase final boss
	"SS": 150,  # Stat Stealer — elite-tier
	"AH": 250,  # Ant Hill — elite-tier (tanky spawner; the ants are the real threat, uncounted here)
	# Elemental elites (2026-07-27). Priced in the Stat Stealer's 1×1 elite band;
	# GW's evasion is effective-HP the score can't see, so it sits a notch above.
	"GW": 45,   # Gale Warden — ONE BIRD of the flock (2026-09-28): a quarter of the old 170 lone elite
	"TC": 190,  # Tidecaller — elite-tier (support; its regen/shield output is
				# force-multiplier power score_unit can't see, hence the premium)
	"TCC": 320, # Terracotta Colossus — elite-tier 2×2, priced just above Hill Giant
	"MH": 340,  # Magma Heart — elite-tier 2×2 (zero attack, but its team-wide
				# escalating burn is threat score_unit reads as nearly nothing)
	"TPC": 260, # Tempest Conduit — elite-tier 1×1; its real output depends on the
				# player's own formation, so treat this as a mid-clump estimate
	"MW": 480,  # Mirrorplate Warden — round-85 elite 2×2
	"AD": 560,  # Aspect Devourer — round-95 capstone elite 2×2, the strongest
				# non-boss body in the game (it stands one wave before the finale)
	"KHA": 300, # Khagan — wave-10 boss (mount-swap fight)
	"SKR": 380,  # Skyrender — wave-20 Air boss (aloft windows add effective bulk)
	"DMW": 420,  # The Drowned Maw — wave-30 Water boss (attrition; the heal-cut aura is uncounted here)
	"CLT": 460,  # Cloven Titan — wave-40 Earth boss (the two halves it leaves behind are uncounted here)
	"EMB": 480,  # Emberhollow — wave-50 Fire boss (its one revival is uncounted here)
	"EMH": 45,   # Ember Heart — barely fights; its value is gating the revive
	"ARC": 500,  # Arcfang — wave-60 Lightning boss (glass cannon; the blink is uncounted here)
	"GRV": 520,  # The Gravekeeper — wave-90 mixed boss (the shades it raises are uncounted here)
	"ARCH": 900, # The Architect — the finale; 3×3 body, three reprised mechanics
	"HYN": 400, "HYF": 400, "HYW": 400, "HYE": 400, "HYA": 400, "HYL": 400,  # Hydra — wave-30 final boss (all 6 elements)
}

# Ordered strong → weak. _fill_budget() prefers the top of this list.
const FILLER_POOL: Array[String] = [
	"G", "FG", "STG", "WY", "TH", "SG", "OG", "MT", "GY", "EP", "CC", "BRN", "BRF", "BRW", "BRE", "BRA", "BRL",
	"B", "BN", "BF", "BW", "BA", "BL",
	"S", "GSN", "GSW", "GSE", "GSA", "GSL", "TLN", "TLF", "TLW", "TLE", "TLA", "TLL", "HH", "SC", "RW", "HRP", "CH",
	"WUN", "WUF", "WUW", "WUE", "WUA", "WUL",
	"LZN", "LZF", "LZW", "LZE", "LZA", "LZL", "A", "M", "SK",
	"SL", "SLN", "SLF", "SLE", "SLA", "SLL",
	"R",
]

# ── BIOME CONTAINMENT: the earliest round a filler body may appear ────────────
# Added 2026-09-21 (VD-06). _fill_budget/fill_to_score used to draw from the
# WHOLE pool at every round, and both prefer the strongest affordable body — so
# a Veteran/Brutal node in the first ten waves happily bought the 2×2 decade
# anchors. Measured on biome 1 before this gate: round 6 Brutal led with WY
# (Sky Wyvern, the AIR anchor) and round 7 Brutal led with FG (Fire Giant, the
# FIRE anchor). Those were the two hardest non-boss waves in the biome, and both
# were hard because of a creature the biome had not taught. Harder is supposed
# to mean more of what you have been shown, not a preview of decade five.
#
# The numbers are NOT hand-authored difficulty knobs. Every entry below is the
# first round that code appears in WaveData.get_wave() — the authored table IS
# the debut schedule, so this is derived from it and stays honest as long as the
# two agree (arena `--mode=debut` re-derives and diffs them; see arena_main).
#
# Eight pool codes never appear in an authored wave and are assigned by family:
#   R/SK/BRN/GSN/TLN  → 1   normal-element basics, the biome-1 family whose
#                           siblings M/A/S/WUN/BN/LZN all debut in rounds 1-7.
#   SG/RW/GY          → 31  beast tier. WaveData's Act-4 header names Ogre/
#                           Stone Golem/Crystal Crab/Root Walker as the EARTH
#                           decade's new bodies; Gargoyle is the same stone band.
# These eight are marked with a trailing comment so a future reader can see at a
# glance which rows are derived and which are assigned.
const DEBUT_ROUND: Dictionary = {
	# Biome 1 — Normal (rounds 1-10)
	"M": 1, "A": 2, "S": 4, "WUN": 6, "BN": 7, "LZN": 7,
	"R": 1, "SK": 1, "BRN": 1, "GSN": 1, "TLN": 1,          # assigned: normal basics
	# Biome 2 — Air (11-20)
	"WY": 11, "BRA": 11, "TLA": 11, "GSA": 12, "SLA": 12, "SLN": 12,
	"LZA": 13, "BA": 14, "HRP": 14, "WUA": 17,
	# Biome 3 — Water (21-30)
	"TH": 21, "B": 21, "BW": 21, "CH": 21, "LZW": 21, "TLW": 21,
	"GSW": 22, "SL": 22, "WUW": 22, "BRW": 24, "OG": 26,
	# Biome 4 — Earth (31-40)
	"G": 31, "BRE": 31, "GSE": 31, "CC": 32, "SLE": 32, "LZE": 33,
	"TLE": 33, "WUE": 34,
	"SG": 31, "RW": 31, "GY": 31,                           # assigned: beast tier
	# Biome 5 — Fire (41-50)
	"FG": 41, "BF": 41, "HH": 41, "EP": 43, "LZF": 43, "BRF": 44,
	"MT": 44, "WUF": 44, "SLF": 46, "TLF": 47,
	# Biome 6 — Lightning (51-60)
	"STG": 51, "GSL": 51, "WUL": 51, "SC": 52, "BL": 53, "LZL": 53,
	"BRL": 54, "SLL": 56, "TLL": 57,
}

# ── BIOME ELEMENT IDENTITY (VD-11) ───────────────────────────────────────────
# DEBUT_ROUND above is a one-way ratchet: it stops an early wave receiving a
# later creature, but places no constraint the other way, so a Fire-decade wave
# could legally field the whole Normal/Air/Water/Earth roster. Measured
# 2026-09-22 before this pass, off-element body share on Brutal: Air 29%, Water
# 46%, Earth 48%, Fire 44%, Lightning 38%. The AUTHORED waves were fine (0-14%
# on Normal tier — the 2026-08-02 retint did its job); it was the difficulty
# FILLER that dissolved the theme, and filler is most of what a hard tier is.
# So the harder you played, the less the biome meant. `LZA` (the Air lizard)
# appeared in every Fire wave 41-49.
#
# This is power-neutral by construction and that is the whole reason it is safe:
# every family's six element variants SHARE ONE STAT BLOCK. That is why the
# 2026-08-02 authored retint preserved the power curve without re-tuning, and it
# is why swapping a filler body for its on-element sibling changes theme and
# nothing else. Verify it stayed that way with --mode=power before and after.
#
# Rounds 61-100 are deliberately excluded: WaveData Act 7 is the mixed-element
# endgame ("mixed elements, about being difficult"), so purity there would fight
# the design. Matches the owner's VD-06 call — biomes 1-5 read pure, deliberate
# mixing starts later.
const DECADE_ELEMENTS: Array[String] = ["N", "A", "W", "E", "F", "L"]

# family -> element -> code. Written out rather than derived by prefix, because
# the codes are NOT regular: the Water slime is "SL" (not SLW), the Fire shaman
# is "S", the Earth orc is "B", and a "B" prefix would also swallow the Bear
# family. Prefix matching here would silently mis-tint three families.
const ELEMENT_VARIANTS: Dictionary = {
	"slime":  {"N": "SLN", "F": "SLF", "W": "SL",  "E": "SLE", "A": "SLA", "L": "SLL"},
	"shaman": {"N": "GSN", "F": "S",   "W": "GSW", "E": "GSE", "A": "GSA", "L": "GSL"},
	"lizard": {"N": "LZN", "F": "LZF", "W": "LZW", "E": "LZE", "A": "LZA", "L": "LZL"},
	"troll":  {"N": "TLN", "F": "TLF", "W": "TLW", "E": "TLE", "A": "TLA", "L": "TLL"},
	"bear":   {"N": "BRN", "F": "BRF", "W": "BRW", "E": "BRE", "A": "BRA", "L": "BRL"},
	"windup": {"N": "WUN", "F": "WUF", "W": "WUW", "E": "WUE", "A": "WUA", "L": "WUL"},
	"orc":    {"N": "BN",  "F": "BF",  "W": "BW",  "E": "B",   "A": "BA",  "L": "BL"},
}
# Reverse lookup, flat and explicit for the same collision reason.
const CODE_FAMILY: Dictionary = {
	"SLN": "slime", "SLF": "slime", "SL": "slime", "SLE": "slime", "SLA": "slime", "SLL": "slime",
	"GSN": "shaman", "S": "shaman", "GSW": "shaman", "GSE": "shaman", "GSA": "shaman", "GSL": "shaman",
	"LZN": "lizard", "LZF": "lizard", "LZW": "lizard", "LZE": "lizard", "LZA": "lizard", "LZL": "lizard",
	"TLN": "troll", "TLF": "troll", "TLW": "troll", "TLE": "troll", "TLA": "troll", "TLL": "troll",
	"BRN": "bear", "BRF": "bear", "BRW": "bear", "BRE": "bear", "BRA": "bear", "BRL": "bear",
	"WUN": "windup", "WUF": "windup", "WUW": "windup", "WUE": "windup", "WUA": "windup", "WUL": "windup",
	"BN": "orc", "BF": "orc", "BW": "orc", "B": "orc", "BA": "orc", "BL": "orc",
}

# The element a round's decade is built on, or "" where no constraint applies
# (rounds 61+, the mixed endgame).
static func decade_element(round: int) -> String:
	if round < 1 or round > 60:
		return ""
	return DECADE_ELEMENTS[(round - 1) / 10]

# Swap every variant-family body in `counts` for its on-element sibling.
# Bodies outside the seven variant families are returned untouched: goblins
# (M/A) have no variants at all — WaveData's wave-24 note already documents that
# hole — and anchors, elites, bosses and the beast tier each own their element.
static func retint_counts(counts: Dictionary, round: int) -> Dictionary:
	var elem: String = decade_element(round)
	if elem == "":
		return counts.duplicate()
	var out: Dictionary = {}
	for code: String in counts:
		var swapped: String = code
		var family: String = String(CODE_FAMILY.get(code, ""))
		if family != "":
			swapped = String(ELEMENT_VARIANTS[family].get(elem, code))
		# Two codes can collapse onto one (LZA and LZN both become LZF in the
		# Fire decade), so accumulate rather than assign.
		out[swapped] = int(out.get(swapped, 0)) + int(counts[code])
	return out

# Filler codes legal at `round`: everything whose authored debut has passed.
# A code missing from DEBUT_ROUND is treated as round-1 legal rather than being
# silently dropped, because dropping it would shrink the budget pool without
# anyone noticing. `--mode=debut` fails loudly on a missing entry instead.
static func legal_filler(round: int) -> Array[String]:
	var out: Array[String] = []
	for code: String in FILLER_POOL:
		if int(DEBUT_ROUND.get(code, 1)) <= round:
			out.append(code)
	return out

# Row fill priority per role (row 0 = farthest back, row 3 = frontline)
const ROLE_ROWS: Dictionary = {
	Role.FRONT: [3, 2, 1, 0],
	Role.BACK:  [0, 1, 2, 3],
}

# ── Wave threat profile (prep-phase dossier) ──────────────────────────────────
# Added 2026-07-27. Arena measurement showed placement swings win rate from 0%
# to ~85% on an identical team, and that the BEST formation flips depending on
# whether the wave's damage is melee or ranged — but the player was never shown
# which they were facing. This turns a spec into the handful of counts that
# decision actually needs, without instantiating a single unit.
#
# Support = anything whose job isn't raw damage (heals, regen, attack-speed
# auras). Kept separate from "ranged" because it reads differently to a player:
# a shaman behind the line is a reason the fight drags, not a reason to spread.
const SUSTAIN_CODES: Array[String] = [
	"S", "GSN", "GSW", "GSE", "GSA", "GSL",        # goblin shamans — heal + aura
	"TLN", "TLF", "TLW", "TLE", "TLA", "TLL",      # trolls — regen + attack-speed buff
	"EP", "RW",                                     # ember phoenix, root walker
	"TC",                                           # Tidecaller elite — heals its own wave
]

# "melee" | "ranged" | "support" for one wave code. Single source of truth for
# BOTH the dossier counts and the per-unit role badges on the battlefield, so a
# badge can never disagree with the line the player read in the panel.
static func role_tag_for_code(code: String) -> String:
	if code in SUSTAIN_CODES:
		return "support"
	if CODE_ROLE.get(code, Role.FRONT) == Role.BACK:
		return "ranged"
	# Role.FRONT and Role.BOSS both fight in melee; BOSS only means "placed
	# centrally" (the 2×2 bodies), not "attacks at range".
	return "melee"

# {melee, ranged, support, large, total} for a generated wave spec.
static func threat_profile(spec: Array) -> Dictionary:
	var out: Dictionary = {"melee": 0, "ranged": 0, "support": 0, "large": 0, "total": 0}
	for entry: Dictionary in spec:
		var code: String = String(entry.get("code", ""))
		out["total"] += 1
		if CODE_IS_LARGE.get(code, false):
			out["large"] += 1
		out[role_tag_for_code(code)] += 1
	return out

# ── Live unit scoring (for reward calculation and power display) ───────────────
# ── EFFECTIVE POWER (VD-03 Finding G, 2026-09-22) ────────────────────────────
# This was a weighted SUM:
#   max_hp*0.15 + attack_damage*10 + attack_speed*60 + magic_power*8 + resistance*5
# Two structural faults, both measured:
#
#   1. It ADDED attack damage and attack speed. The game MULTIPLIES them, so a
#      fast/weak body and a slow/strong body priced alike while dealing very
#      different damage.
#   2. HP was weighted 0.15 against damage's 10 — one point of attack damage was
#      worth ~67 points of HP. In a fight, HP buys the uptime that decides how
#      much of that damage ever lands.
#
# Together they overpriced glass cannons. The Rat priced 387 against the
# Goblin's 367 despite half the HP and a measured 3.7s life to the Goblin's 8.7s
# — so the cheapest body at round 1 was the Goblin at 367, which IS the entire
# round-1 wave. With no body cheaper than the wave itself, no tier step below
# +100% was expressible, and Veteran wave 1 overshot onto Brutal's exact roster.
#
# Now: sqrt(throughput * effective_hp), the standard effective-power shape.
#   throughput   = (attack_damage + magic_power) * attack_speed
#                  magic_power is IN on purpose. A pure attack-DPS form prices
#                  the Goblin Shaman (dps 5.9, magic 19) as the cheapest body on
#                  the board and the budget would buy nothing but healers.
#   effective_hp = max_hp * (100 + resistance)/100
#                  matches take_damage's own League-style curve exactly:
#                  damage * (100 / (100 + armor)).
#
# sqrt keeps the result LINEAR in level (both factors scale with level, so the
# product is quadratic and the root brings it back), which is what the old sum
# did — so wave totals across 100 rounds stay in the same magnitude and the
# elite-vs-fodder price relationship inside a round is preserved.
#
# Validation: the new ordering of the round-1 bodies is
#   R < M < SK < GSN < BRN < TLN
# against the hand-authored UNIT_POWER tags' R < SK < M < GSN < TLN < BRN —
# near-identical, differing only where those tags are themselves stale. The old
# formula matched neither. K is a pure normalisation constant, fitted so a
# level-1 Goblin still scores ~367 and every recorded measurement in
# VERTICAL_DEPTH_BASELINE.md stays comparable.
const EFFECTIVE_POWER_K := 6.55

static func score_unit(unit: UnitBase) -> float:
	var throughput: float = (float(unit.attack_damage) + float(unit.magic_power)) \
			* unit.attack_speed
	var effective_hp: float = float(unit.max_hp) \
			* (100.0 + float(unit.resistance)) / 100.0
	# Floors keep a stat-less or not-yet-initialised unit from pricing at zero,
	# which would make it free to the budget rather than merely cheap.
	var s: float = sqrt(maxf(throughput, 0.1) * maxf(effective_hp, 1.0)) \
			* EFFECTIVE_POWER_K
	if unit.attack_range > 1:
		s *= 1.25
	# Large bodies carry disproportionate power (they soak a whole block and can't
	# be surrounded as easily). Generalised from a flat ×2.5 at size 2 to an N×N
	# ramp — identical at size 2, ×4.0 for the 3×3 Architect.
	if unit.cell_size > 1:
		s *= 1.0 + (unit.cell_size - 1) * 1.5
	return s

# LEGACY (pre coin-drop economy) — kept only for anything still displaying a
# "gold value" for a unit. Kill gold now flows through gold_drops_for_unit.
static func gold_for_unit(unit: UnitBase) -> int:
	return maxi(2, int(score_unit(unit) * 0.018))

# Economy v3 (2026-07-03, per user): kills drop PHYSICAL coins on the field
# (collected by the round-end vacuum), max 1 gold per basic kill, and not
# guaranteed — the chance rises with the wave. Elites/bosses drop a fixed
# handful. Summons never drop (Ant Hill would be a gold printer otherwise).
static func gold_drops_for_unit(unit: UnitBase, round: int) -> int:
	if unit.is_summoned:
		return 0
	if unit.is_boss:
		return Balance.BOSS_COIN_DROP
	if unit.is_elite:
		return Balance.ELITE_COIN_DROP \
				+ (1 if round >= Balance.ELITE_COIN_LATE_BONUS_ROUND else 0)
	# FIXED chance, same at wave 1 and wave 100 (2026-08-07 user spec: "coin and
	# crystal drops should both be fixed"; the old round-scaled ramp is the
	# mechanism a prior pass identified as the "so much gold" cause — see
	# Balance.COIN_CHANCE_BASE). The only way to raise this is the Bounty
	# crystal-tree node, itself a flat per-level chance (main_game.gd's
	# gold_per_kill roll) — not round-scaled either. `round` is now unused but
	# kept as a param for call-site compatibility.
	return 1 if randf() < Balance.COIN_CHANCE_BASE else 0

static func crystals_for_unit(unit: UnitBase) -> int:
	# Heavy-tier demotion (2026-07-23): elite mobs (G/AH/SS) recurring as normal
	# heavy units in later waves must NOT pay their elite crystal bounty — crystals
	# are score-based, and a leveled 2×2 Giant scores >800 every time, so without
	# this gate a wave with a couple of Giants becomes a crystal printer. The
	# wave_heavy meta is stamped in WaveDirector.create_enemy_for_entry.
	if unit.has_meta("wave_heavy"):
		return 0
	var s := score_unit(unit)
	var by_score: int = 2 if s >= 800.0 else (1 if s >= 400.0 else 0)
	# Elites/bosses (2026-09-29): the score tiers cap at 2, so a wave-5 Hill
	# Giant paid the same as one Wind-Up Bot. They now pay their hand-authored
	# per-unit crystal_reward (enemy_factory.gd) — never less than the score
	# tier. Not score-scaled: boss scores run to millions late on.
	if unit.is_elite or unit.is_boss:
		return maxi(by_score, unit.crystal_reward)
	return by_score

# ── Formation builder ─────────────────────────────────────────────────────────
# Returns Array of {"code": String, "pos": Vector2i} ready for spawn_enemies().
# Returns [] for procedural rounds (round 11+).
#
# Normal:         fixed wave from WaveData — no changes.
# Veteran/Brutal: normal base guaranteed + random filler units up to the power budget.
#               Filler prefers 1 strong unit over several weak ones (70/30 bias).
# wave_seed pins the Veteran/Brutal FILLER so the same node produces the same
# fight every time it is looked at. See _filler_rng for why that matters and for
# what 0 means.
static func build_formation(round: int, difficulty: int, grid_width: int = 9,
		wave_seed: int = 0, score_fn: Callable = Callable()) -> Array:
	var base_counts: Dictionary = WaveData.get_wave(round)
	if base_counts.is_empty():
		return []
	if difficulty == Difficulty.NORMAL:
		return _auto_place(base_counts, grid_width)
	return _auto_place(
		_topped_up(base_counts, difficulty, round, wave_seed, score_fn), grid_width)

# base counts + whatever the difficulty budget buys, as one counts dictionary.
# Prefers the SCORED fill; falls back to the old UNIT_POWER budget when no pricer
# was supplied, which is every tool script and harness that calls build_formation
# without one. Those keep their old behaviour rather than silently getting a
# different wave.
static func _topped_up(base_counts: Dictionary, difficulty: int, round: int,
		wave_seed: int, score_fn: Callable, preplaced: Dictionary = {},
		extra_codes: Array = []) -> Dictionary:
	var counts: Dictionary = base_counts.duplicate()
	# VD-11: the boss honour guard is retinted to the decade's element. It was
	# hardcoded Normal (M/B/BRN/TLN/GSN/LZN) at every tier in every decade, so
	# wave 50 — the FIRE boss — fought behind seven goblins and a skeleton.
	var guard: Dictionary = retint_counts(preplaced, round)
	for code: String in guard:
		counts[code] = counts.get(code, 0) + int(guard[code])
	var filler: Dictionary
	if score_fn.is_valid():
		filler = fill_to_score(base_counts, difficulty, round, wave_seed, score_fn, preplaced,
			extra_codes)
	else:
		var base_power: int = _count_power(base_counts)
		var remaining: int = int(float(base_power) * DIFFICULTY_MULT[difficulty]) - base_power
		filler = _fill_budget(remaining, round, _filler_rng(round, difficulty, wave_seed))
	# VD-11: retint the FILLER only. base_counts is the authored wave and is left
	# exactly as written — those comps already went through the 2026-08-02 retint
	# and their remaining off-element bodies are deliberate (wave 12 keeps SLN×3
	# and wave 24 keeps four "A" archers as neutral filler, both documented in
	# WaveData). Retinting them here would silently overrule the author.
	filler = retint_counts(filler, round)
	for code: String in filler:
		counts[code] = counts.get(code, 0) + int(filler[code])
	return counts

# ── SCORED FILL ───────────────────────────────────────────────────────────────
# Top `base_counts` up to `mult` times its own SCORED power and return just the
# added bodies. score_fn is WaveDirector.score_code — see the long note there for
# why the budget cannot be priced in UNIT_POWER.
#
# Tolerance is what the owner asked for: hit the target within a hair rather than
# "somewhere in the neighbourhood". Whole units can't land exactly, so the fill
# runs greedily and then TRIMS — repeatedly swapping one chosen body for a
# differently-priced one whenever that lands closer to the target. Fine tuning is
# possible because the pool is dense: two Brutal wave-8 rolls measured 45 points
# apart on 2026-09-19, so there is nearly always a swap that shaves the error.
const FILL_TOLERANCE_FRAC := 0.004   # ±0.4% of target — the owner asked for ~±50 on 12k
const FILL_TRIM_PASSES := 10

# ── CROWD CAPS (2026-09-28, owner call) ──────────────────────────────────────
# Brutal used to buy its extra power as BODIES: 2x2 slots top out around three,
# so everything past that became cheap filler and rounds 24/30/32/36 Brutal
# covered ~31 of the enemy half's cells (round 32: 9 bodies Normal, 22 Brutal).
# Owner: "the way we handle it needs to change" — harder should mean fewer,
# heavier threats, not a wall. So a tier may add at most EXTRA_BODY_CAP bodies
# to the authored wave, and the whole wave may use at most WAVE_CELL_CAP cells
# (2/3 of the 4×9 enemy half). Inside those limits each pick aims at
# remaining ÷ slots-left, so the budget PROMOTES (beast tier, decade giants)
# instead of multiplying. If even the heaviest legal body can't reach the target
# within the caps, the wave lands under target on purpose — a crowded board is
# the thing being removed.
const EXTRA_BODY_CAP: Array[int] = [0, 2, 3]   # Normal / Veteran / Brutal
const GALE_FLOCK_SIZE: Array[int] = [4, 6, 8]  # Gale Warden birds per tier (owner, 2026-09-28)
const WAVE_CELL_CAP := 24

static func _cells_of(counts: Dictionary) -> int:
	var n := 0
	for code: String in counts:
		var s: int = cell_size_for_code(code)
		n += s * s * int(counts[code])
	return n

# reference_counts sets the TARGET (it is the Normal-tier wave, so ×1.5 means
# one-and-a-half times what Normal fields). preplaced is anything already on the
# board that is not part of that reference — the boss's hand-designed honour
# guard — and it is charged AGAINST the budget rather than added on top of it.
# Without that split a boss's Veteran target would be 1.5× (boss + guard) instead
# of 1.5× the Normal fight, which is not what the tier is supposed to promise.
static func fill_to_score(reference_counts: Dictionary, difficulty: int, round: int,
		wave_seed: int, score_fn: Callable, preplaced: Dictionary = {},
		extra_codes: Array = []) -> Dictionary:
	if difficulty == Difficulty.NORMAL or not score_fn.is_valid():
		return {}
	var base_score: float = 0.0
	for code: String in reference_counts:
		base_score += float(score_fn.call(code, round)) * float(int(reference_counts[code]))
	if base_score <= 0.0:
		return {}
	var spent: float = base_score
	for code: String in preplaced:
		spent += float(score_fn.call(code, round)) * float(int(preplaced[code]))

	var target: float = base_score * DIFFICULTY_MULT[difficulty]
	var tol: float = target * FILL_TOLERANCE_FRAC
	var remaining: float = target - spent

	# Price every candidate once. A code with no sprite/type prices at 0 and is
	# dropped rather than being treated as free.
	var cost: Dictionary = {}
	var candidates: Array = legal_filler(round)
	for code in extra_codes:
		if not (code in candidates):
			candidates.append(code)
	for code: String in candidates:
		var s: float = float(score_fn.call(code, round))
		if s > 0.0:
			cost[code] = s

	var rng := _filler_rng(round, difficulty, wave_seed)
	var picks: Dictionary = {}
	var body_cap: int = EXTRA_BODY_CAP[difficulty]
	var fixed_cells: int = _cells_of(reference_counts) + _cells_of(preplaced)
	# Room left under both crowd caps once `picks` is on the board.
	var fits := func(code: String, cur: Dictionary) -> bool:
		var bodies := 0
		for c: String in cur: bodies += int(cur[c])
		if bodies + 1 > body_cap:
			return false
		var s: int = cell_size_for_code(code)
		return fixed_cells + _cells_of(cur) + s * s <= WAVE_CELL_CAP
	var safety: int = 0
	while remaining > tol and safety < 60:
		safety += 1
		var affordable: Array = []
		for code: String in cost:
			if float(cost[code]) <= remaining + tol and fits.call(code, picks):
				affordable.append(code)
		if affordable.is_empty():
			break
		affordable.sort_custom(func(a, b): return float(cost[a]) > float(cost[b]))
		# Aim each pick at the average the remaining slots must carry, so a
		# capped tier promotes into heavier bodies instead of stopping short.
		# Any body at or above that average is a fair pick and is chosen
		# UNIFORMLY — with only 2-3 slots, always taking the cheapest qualifier
		# collapsed every run onto the same cast (map_smoke's per-run-variety
		# check caught it). When nothing reaches the average, take one of the
		# three strongest that fit, again at random.
		var used := 0
		for c: String in picks: used += int(picks[c])
		var need: float = remaining / float(maxi(1, body_cap - used))
		var heavy: Array = affordable.filter(func(c): return float(cost[c]) >= need)
		var pick: String
		if heavy.is_empty():
			pick = String(affordable[rng.randi() % mini(3, affordable.size())])
		else:
			pick = String(heavy[rng.randi() % heavy.size()])
		picks[pick] = int(picks.get(pick, 0)) + 1
		remaining -= float(cost[pick])

	# Nothing fit at all. That happens at the very bottom of the curve: wave 1 is
	# ONE goblin, so Veteran's half-a-goblin of headroom buys nothing and the tier
	# would field the identical wave while paying Veteran's much richer reward
	# table — the same free-tier problem the elite rounds had. Take the cheapest
	# body available and overshoot rather than sell a difficulty tier for nothing.
	if picks.is_empty() and remaining > tol and not cost.is_empty():
		var cheapest: String = ""
		for code: String in cost:
			if (cheapest == "" or float(cost[code]) < float(cost[cheapest])) \
					and fits.call(code, picks):
				cheapest = code
		if cheapest != "":
			picks[cheapest] = 1
			remaining -= float(cost[cheapest])

	# Trim toward the target. Three moves are considered each pass — SWAP one
	# chosen body for a differently-priced one, ADD a body, or REMOVE one — and
	# the single best is taken. Swap alone was not enough: the greedy loop often
	# stops holding a deficit smaller than the cheapest body, which no swap can
	# close but an add-then-swap can.
	for _pass in range(FILL_TRIM_PASSES):
		if absf(remaining) <= tol:
			break
		var best_err: float = absf(remaining)
		var move_out: String = ""
		var move_in: String = ""
		for to_code: String in cost:                       # ADD
			if not fits.call(to_code, picks):
				continue
			var e_add: float = absf(remaining - float(cost[to_code]))
			if e_add < best_err - 0.5:
				best_err = e_add
				move_out = ""
				move_in = to_code
		for from_code: String in picks:
			var e_rem: float = absf(remaining + float(cost[from_code]))   # REMOVE
			if e_rem < best_err - 0.5:
				best_err = e_rem
				move_out = from_code
				move_in = ""
			for to_code2: String in cost:                  # SWAP
				if to_code2 == from_code:
					continue
				# A swap frees one body and its cells before placing the new one.
				var after: Dictionary = picks.duplicate()
				after[from_code] = int(after[from_code]) - 1
				if not fits.call(to_code2, after):
					continue
				var err: float = absf(remaining + float(cost[from_code])
						- float(cost[to_code2]))
				if err < best_err - 0.5:
					best_err = err
					move_out = from_code
					move_in = to_code2
		if move_out == "" and move_in == "":
			break
		if move_out != "":
			remaining += float(cost[move_out])
			picks[move_out] = int(picks[move_out]) - 1
			if int(picks[move_out]) <= 0:
				picks.erase(move_out)
		if move_in != "":
			remaining -= float(cost[move_in])
			picks[move_in] = int(picks.get(move_in, 0)) + 1
	return picks

# ── THE FILLER RNG, AND WHY THE SEED COMES FROM THE MAP ───────────────────────
# The filler used to roll bare randf()/randi(), so EVERY call rebuilt the wave
# from scratch. Two things fell out of that, both live bugs:
#
#   1. The map's node card promised a fight the actual round then didn't
#      deliver — the card generated one spec, the fight generated another. The
#      map's whole premise is that what you see is what you get.
#   2. Difficulty could invert. Measured 2026-09-19: round 2 Brutal came out at
#      1608 power against round 2 Veteran's 1969 — the hard option was easier,
#      and which way it fell changed per roll.
#
# The fix is NOT a fixed seed per (round, difficulty): that would hand every
# playthrough the same wave 8 forever, which kills the variety this system
# exists to provide (owner call, 2026-09-20). The seed is PER RUN — RunMap mints
# one per node from the run's own RNG and stores it on the node, so:
#   new run          → different cast
#   same node twice  → identical, card and fight agree
#   save and quit    → survives, because the seed rides in the node dict
# Same trick the node's reward already uses (see RunMap.to_dict's reward stub).
#
# Round and difficulty are mixed IN rather than trusted to differ on their own:
# main_game generates all three difficulties from the SAME node to fill the
# difficulty panel, so a bare node seed would hand Veteran and Brutal identical
# filler rolls.
#
# wave_seed 0 means "nobody pinned this" — the arena harness, the tool scripts
# and any pre-map save. Those randomize, which is exactly the old behaviour, so
# no existing caller changes meaning.
static func _filler_rng(round: int, difficulty: int, wave_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	if wave_seed == 0:
		rng.randomize()
	else:
		rng.seed = hash("%d:%d:%d" % [wave_seed, round, difficulty])
	return rng

# Sum the power cost of a counts dictionary.
static func _count_power(counts: Dictionary) -> int:
	var total := 0
	for code: String in counts:
		total += UNIT_POWER.get(code, 30) * int(counts[code])
	return total

# Spend `budget` on random filler units.
# 70% chance: pick the strongest affordable unit from FILLER_POOL.
# 30% chance: pick any affordable unit at random.
# Returns a counts dictionary.
static func _fill_budget(budget: int, round: int, rng: RandomNumberGenerator) -> Dictionary:
	var result: Dictionary = {}
	var pool: Array[String] = legal_filler(round)   # VD-06 biome containment
	var safety := 0
	while budget > 0 and safety < 50:
		safety += 1
		# Build list of affordable units
		var affordable: Array[String] = []
		for code: String in pool:
			if UNIT_POWER.get(code, 9999) <= budget:
				affordable.append(code)
		if affordable.is_empty():
			break

		var pick: String
		if rng.randf() < 0.7:
			pick = affordable[0]  # strongest affordable (FILLER_POOL is sorted strong→weak)
		else:
			pick = affordable[rng.randi() % affordable.size()]

		result[pick] = result.get(pick, 0) + 1
		budget -= UNIT_POWER.get(pick, 30)

	return result

# ── Auto-placer ───────────────────────────────────────────────────────────────
# Places units by role: bosses centered first, then FRONT/BACK by row priority.
# All units in a row are spread evenly across free columns.
static func _auto_place(counts: Dictionary, grid_width: int) -> Array:
	var result: Array = []
	var occupied: Dictionary = {}   # Vector2i → true
	counts = counts.duplicate()
	# Emberhollow's body occupies the forward centre block; its two Hearts
	# flank it. Keep the rear return tiles free of difficulty escorts as well.
	if counts.get("EMB", 0) == 1 and counts.get("EMH", 0) >= 2:
		var body := Vector2i(mini(int(grid_width / 2), grid_width - 2), 2)
		result.append({"code": "EMB", "pos": body})
		for dy in 2:
			for dx in 2:
				occupied[body + Vector2i(dx, dy)] = true
		for side in 2:
			var cell := emberhollow_heart_cell(side, grid_width)
			result.append({"code": "EMH", "pos": cell})
			occupied[cell] = true
			occupied[emberhollow_heart_cell(side, grid_width, true)] = true
		counts.erase("EMB")
		counts["EMH"] -= 2

	# --- 1. Collect and place 2×2 boss units first (centered) ---
	var boss_codes: Array = []
	for code: String in counts:
		if CODE_IS_LARGE.get(code, false):
			for _i in range(int(counts[code])):
				boss_codes.append(code)
	if not boss_codes.is_empty():
		result.append_array(_place_bosses(boss_codes, occupied, grid_width))

	# --- 2. Group regular units by role ---
	var by_role: Dictionary = {}
	for code: String in counts:
		if CODE_IS_LARGE.get(code, false):
			continue
		var role: int = CODE_ROLE.get(code, Role.FRONT)
		if not by_role.has(role):
			by_role[role] = []
		for _i in range(int(counts[code])):
			by_role[role].append(code)

	# --- 3. Fill rows in role-priority order ---
	for role: int in [Role.FRONT, Role.BACK]:
		if not by_role.has(role):
			continue
		var rows: Array = ROLE_ROWS.get(role, [3, 2, 1, 0])
		result.append_array(_fill_rows(by_role[role], rows, occupied, grid_width))

	return result

static func emberhollow_heart_cell(side: int, grid_width: int = 9, rear: bool = false) -> Vector2i:
	return Vector2i(1 if side == 0 else grid_width - 2, 1 if rear else 3)

# Place N large (2×2) units, evenly spaced across boss rows (1–2).
static func _place_bosses(codes: Array, occupied: Dictionary, grid_width: int) -> Array:
	var result: Array = []
	var n := codes.size()
	# Widest body in this batch decides the anchor range — generalised from a
	# hardcoded 2-wide block 2026-07-29 so the 3×3 Architect can be placed.
	var max_w := 2
	for c in codes:
		max_w = maxi(max_w, cell_size_for_code(c))
	var valid_x: Array = []
	for x in range(maxi(grid_width - max_w + 1, 1)):
		valid_x.append(x)
	var chosen_x: Array = _even_pick(valid_x, n)

	for i in range(codes.size()):
		var size: int = cell_size_for_code(codes[i])
		# _even_pick returns at most valid_x.size() anchors, which can be fewer
		# than the number of bodies — wrap so wide/crowded batches still place.
		if chosen_x.is_empty():
			break
		var x: int = mini(int(chosen_x[i % chosen_x.size()]), maxi(grid_width - size, 0))
		# Candidate top rows, preferring a centred band and falling back outward.
		# A size-N body needs rows r0 .. r0+N-1 to all sit inside the 4 enemy rows.
		var row_starts: Array = []
		for r0 in [1, 0, 2, 3]:
			if r0 + size <= 4:
				row_starts.append(r0)
		for r0: int in row_starts:
			var cells: Array = []
			for dy in range(size):
				for dx in range(size):
					cells.append(Vector2i(x + dx, r0 + dy))
			var clear := true
			for c: Vector2i in cells:
				if occupied.has(c):
					clear = false
					break
			if clear:
				for c: Vector2i in cells:
					occupied[c] = true
				result.append({"code": codes[i], "pos": Vector2i(x, r0)})
				break

	return result

# Footprint width of a wave code. 3 only for the 3×3 finale; everything flagged
# in CODE_IS_LARGE is 2×2; everything else is a single cell. Keep this in sync
# with the cell_size each factory sets.
static func cell_size_for_code(code: String) -> int:
	if code == "ARCH":
		return 3
	return 2 if CODE_IS_LARGE.get(code, false) else 1

# Fill a list of units across rows in priority order, evenly spacing per row.
static func _fill_rows(codes: Array, row_priority: Array, occupied: Dictionary, grid_width: int) -> Array:
	var result: Array = []
	var idx := 0

	for row: int in row_priority:
		if idx >= codes.size():
			break
		# Collect free columns in this row
		var free_cols: Array = []
		for x in range(grid_width):
			if not occupied.has(Vector2i(x, row)):
				free_cols.append(x)
		if free_cols.is_empty():
			continue
		# Take as many units as fit
		var take := mini(codes.size() - idx, free_cols.size())
		var row_codes: Array = codes.slice(idx, idx + take)
		idx += take
		# Spread them evenly across the free columns
		var chosen: Array = _even_pick(free_cols, row_codes.size())
		for i in range(row_codes.size()):
			var pos := Vector2i(chosen[i], row)
			result.append({"code": row_codes[i], "pos": pos})
			occupied[pos] = true

	return result

# Pick n evenly-spaced items from a list (with margins — no edge-hugging).
# e.g. _even_pick([0..8], 3) → [2, 4, 6]
static func _even_pick(items: Array, n: int) -> Array:
	if n <= 0:
		return []
	if n >= items.size():
		return items.duplicate()
	var picked: Array = []
	for i in range(n):
		var t: float = float(i + 1) / float(n + 1)
		var idx := clampi(int(t * items.size()), 0, items.size() - 1)
		picked.append(items[idx])
	return picked

# ── Procedural round scaling (round 11+) ──────────────────────────────────────
static func procedural_count(base_count: int, difficulty: int) -> int:
	var mult: float = DIFFICULTY_MULT[difficulty]
	return mini(int(float(base_count) * mult), 32)

# ── Boss waves (rounds 10 / 20 / 30) ──────────────────────────────────────────
# A centered 2×2 Hill Giant boss plus escalating adds. Difficulty adds more
# muscle. Returns the same [{code, pos}] format as build_formation.
static func is_boss_round(round: int) -> bool:
	return round > 0 and round % Balance.BOSS_ROUND_INTERVAL == 0 \
			and round <= Balance.VICTORY_ROUND

# Boss tier: 1 at round 10, 2 at 20, 3 at 30.
static func boss_tier(round: int) -> int:
	return int(round / Balance.BOSS_ROUND_INTERVAL)

# Level the boss unit is set to — scales hard between the three encounters.
# Re-anchored 2026-07-12 to the run targets: Khagan (3) stays first-try
# beatable with no crystal upgrades; the Triarch (10) needs a stars-align
# no-upgrade run; the Hydra (18) is meant to be unbeatable without them.
# (Old 3/6/9 curve: arena sims had a frozen level-5 team killing the Hydra.)
# Tiers 1-3 keep their hand-tuned anchors. Tier 4+ (rounds 40-100, added
# 2026-07-24 when the run was extended past 30) continues the curve instead of
# flat-lining at 22 — it tracks enemy_level_for_round so a boss always outranks
# the fodder of its own round by a clear margin.
static func boss_level(round: int) -> int:
	match boss_tier(round):
		1:  return 3
		2:  return 14
		3:  return 22
		_:  return 22 + int(float(round - 30) * 0.85)

# Which boss code fights at a given round. Hill Giant was reclassified to an
# elite (2026-07-02, now spawns in rounds 5/15/25 instead — see is_elite_round).
#
# BOSS/DECADE ALIGNMENT (2026-07-27): each decade's boss now matches that
# decade's element, the same principle the elemental elites follow (see
# ELITE_BY_ROUND). The Triarch and Hydra are archetype/element-agnostic fights
# with no decade identity, so they move OUT to the mixed endgame (61-100) where
# "no fixed element" is thematically correct, and get re-tuned for their new
# rounds by the boss_level curve.
#
#   10  Normal     Khagan             mount-swap → timed possession
#   20  Air        Skyrender   aloft windows ......... reach check
#   30  Water      The Drowned Maw    heal-cut aura ......... sustain check
#   40  Earth      Cloven Titan       splits on death ....... finish-the-job
#   50  Fire       Emberhollow        revives unless Hearts die . kill order
#   60  Lightning  Arcfang            blinks to your carry .. backline check
#   70  mixed      The Triarch        relocated from 20, re-tuned by boss_level
#   80  mixed      (TODO)             — Hydra moves here with its element picker
#   90  mixed      The Gravekeeper    fallen rise as shades . attrition capstone
#   100 mixed      The Architect      3×3; reprises 3 trials . the finale
#
# Un-built slots deliberately fall through to the Hydra rather than to nothing,
# so every boss round stays a real encounter while the rest are built.
# chosen_element takes a UnitBase.Element value and only matters for the Hydra.
static func boss_code_for(round: int, chosen_element: int = -1) -> String:
	match boss_tier(round):
		1: return "KHA"
		2: return "SKR"
		3: return "DMW"
		4: return "CLT"
		5: return "EMB"
		6: return "ARC"
		9: return "GRV"
		10: return "ARCH"
		7: return "TRI"
		_:
			match chosen_element:
				UnitBase.Element.FIRE:      return "HYF"
				UnitBase.Element.WATER:     return "HYW"
				UnitBase.Element.EARTH:     return "HYE"
				UnitBase.Element.AIR:       return "HYA"
				UnitBase.Element.LIGHTNING: return "HYL"
				_: return "HYN"   # NORMAL or unset

static func build_boss_formation(round: int, difficulty: int, grid_width: int = 9,
		chosen_element: int = -1, wave_seed: int = 0, score_fn: Callable = Callable()) -> Array:
	var tier: int = boss_tier(round)
	var counts: Dictionary = {boss_code_for(round, chosen_element): 1}      # the boss
	# Hearts belong to Emberhollow's kit on every difficulty, including Normal.
	if boss_code_for(round, chosen_element) == "EMB":
		counts["EMH"] = 2
	# Normal has the boss's complete kit, without difficulty escorts.
	if difficulty == Difficulty.NORMAL:
		return _auto_place(counts, grid_width)
	# ── The honour guard is a KIT, not filler ────────────────────────────────
	# 2026-07-12: a lone boss just gets focus-fired down by a full late-game
	# roster — arena sims had 10 heroes killing the Hydra in ~20s through its old
	# 5-goblin escort. Trolls buff the boss's attack speed, shamans heal it. That
	# is a designed answer to a specific failure, so it is kept verbatim and NOT
	# replaced by budget filler, which would happily buy five bears instead.
	#
	# What changed 2026-09-20: it no longer scales with `difficulty` itself. The
	# guard is now fixed per tier, and the TIER's extra power is bought by the
	# scored budget below — so Veteran and Brutal mean 1.5× and 2.0× of the
	# Normal fight instead of "the same kit plus a couple of goblins" (measured
	# ×1.30 / ×1.38 at round 10 before this).
	# 2026-09-28 (owner call): cut to its DESIGNED CORE — the two trolls that
	# speed the boss up and the two shamans that heal it. The goblin fodder
	# (2 + tier) and the bear/orc/lizard packs are gone: they were sized in July
	# for bosses that, it turned out, were barely fighting (inherited ult spam —
	# see BOSS_SIGNATURES in AutoBattleManager), and at tier 3+ they were 15-19
	# bodies the crowd caps could not touch. The freed budget now buys heavies
	# inside those caps instead.
	var guard: Dictionary = {"TLN": 2, "GSN": 2}            # buffers + healers
	# counts holds the complete Normal-tier fight (including Ember Hearts), so it
	# is the reference the 1.5×/2.0× target is measured against. The guard is
	# charged against that budget, and whatever is left buys ordinary filler.
	return _auto_place(
		_topped_up(counts, difficulty, round, wave_seed, score_fn, guard), grid_width)

# ── Elite waves (every round ending in 5 — the gaps between boss rounds) ─────
# A mini-boss plus light fodder support. Weaker than a full boss encounter, but
# a real step up from normal fodder.
const ELITE_ROUNDS: Array[int] = Balance.ELITE_ROUNDS   # tune in balance.gd
const ELITE_POOL: Array[String] = ["G", "SS", "AH", "GW", "TC", "TCC", "MH", "TPC", "MW", "AD"]
# Fixed assignment (2026-07-15 user decision, replaces the random pool pick):
# each elite owns ONE round so its stats can be balanced against that round's
# team power instead of having to work at three different power levels.
#
# 2026-07-27 elemental-elite pass: each decade's elite now MATCHES that decade's
# element, so the round-5/15/25/… encounters teach the element the next ten waves
# are built on. Ant Hill and Stat Stealer moved out to the mixed endgame rounds
# (65/75) where they get re-tuned; Hill Giant stays at 5 because "G" is the
# structural 2×2 anchor of nearly every built wave from 11 to 39 and can't move.
#
# All ten slots are now real bespoke encounters — the elite_code_for() fallback
# that used to re-cycle the three original elites through rounds 35-95 is gone.
#   5  Normal    Hill Giant           big dumb body — the tutorial elite
#   15 Air       Gale Warden          evasion + shove ....... formation check
#   25 Water     Tidecaller           heals its own wave .... target-priority check
#   35 Earth     Terracotta Colossus  armor ramps ........... burst check
#   45 Fire      Magma Heart          escalating team burn .. race check
#   55 Lightning Tempest Conduit      chains between heroes . spacing check
#   65 mixed     Ant Hill             ant swarm ............. DPS check
#   75 mixed     Stat Stealer         steals a stat ......... attrition check
#   85 mixed     Mirrorplate Warden   reflects damage ....... overkill check
#   95 mixed     Aspect Devourer      cycles element ........ damage-type capstone
const ELITE_BY_ROUND := {
	5: "G", 15: "GW", 25: "TC", 35: "TCC", 45: "MH",
	55: "TPC", 65: "AH", 75: "SS", 85: "MW", 95: "AD",
}

static func is_elite_round(round: int) -> bool:
	return round in ELITE_ROUNDS

# Level for a non-boss/non-elite enemy in a given round. Extracted from
# main_game.gd (which now delegates here) so the arena harness shares the exact
# live-game curve. is_elite_slot = the legacy "last unit of a procedural wave
# gets elite-ish level" flag, NOT the round-5/15/25 elite tier.
static func enemy_level_for_round(round: int, is_elite_slot: bool) -> int:
	if is_elite_slot and round % 5 == 0:
		return mini(round / 5 + 2, 8)
	if is_elite_slot and round >= 4:
		return mini(round / 2, 5)
	if round <= 2: return 1
	if round <= 10:
		return 1 + randi() % mini(round / 2, 3)
	# Round 11+: level keeps climbing. Steepened 2026-07-12 (was (round-10)/2,
	# topping out ~13-15 by round 30) after arena sims showed a frozen 5-hero
	# level-5 team clearing wave 29 at 88% — nowhere near the run targets
	# (wave 20 = stars-align without crystal upgrades, wave 30 = impossible
	# without them). Now ~4-6 at round 11 up to ~19-21 by round 30.
	var floor_lvl: int = 3 + int(float(round - 10) * 0.8)
	return floor_lvl + randi() % 3

# How much to bias a procedural enemy hero's stat rolls (see
# UnitFactory.generate_recruit_rolls) toward higher grades as the run goes on.
# 0 through round 10 (matches the old flat behaviour); climbs to 0.5 by round
# 30 — pushes the average roll from a "B" up toward "A"/"S" by the late game,
# instead of every round-11+ enemy hero landing in the same grade band forever.
# Capped at 0.5 (not higher) so round 30 still has real variance — a bias that
# guarantees S every time removes the "did I get a scary roll" tension entirely.
static func enemy_roll_bias(round: int) -> float:
	return clampf(float(round - 10) / 20.0, 0.0, 1.0) * 0.5

# Elite level: a step above the regular mobs of its round (which follow
# enemy_level_for_round), a step below the next boss. Re-anchored 2026-07-12
# alongside the steeper round-11+ level curve — the old 2/4/6 would have made
# the wave-15/25 elites WEAKER than their own escort fodder.
# Rounds 5/15/25 keep their hand-tuned anchors. Round 35+ (added 2026-07-24 with
# the run extension) continues the curve rather than flat-lining at 16, which
# would have left every late elite WEAKER than its own escort fodder — the exact
# bug the 2026-07-12 re-anchor above fixed for rounds 15/25.
static func elite_level(round: int) -> int:
	match round:
		5:  return 1    # fodder is lvl 1-2
		15: return 9    # fodder is lvl 7-9
		25: return 16   # fodder is lvl 15-17
		_:  return 16 + int(float(round - 25) * 0.8)

# The elite for a round is fixed by ELITE_BY_ROUND, so regenerating the spec
# (formation preview, then again on Ready) always yields the same pick — the
# old random pool needed a per-round lock cache in wave_director for that.
#
# The 2026-07-24 PLACEHOLDER (undefined rounds deterministically re-cycling the
# three original elites) is GONE as of 2026-07-27 — all ten elite rounds now name
# a real bespoke encounter. The ELITE_POOL fallback is kept only as a defensive
# default for a round somehow outside the table; it should never be reached.
static func elite_code_for(round: int) -> String:
	if ELITE_BY_ROUND.has(round):
		return ELITE_BY_ROUND[round]
	push_warning("elite_code_for: round %d has no ELITE_BY_ROUND entry" % round)
	return ELITE_POOL[int(round / 10) % ELITE_POOL.size()]

# ── ELITE ROUNDS ──────────────────────────────────────────────────────────────
# REBUILT 2026-09-20. The escort used to be `counts["M"] = 1 + difficulty +
# round/15` — a hardcoded pile of goblins that ignored the power budget entirely.
# Two things were wrong with it, both measured:
#
#   * It barely scaled. Round 5 came out ×1.00 / ×1.07 / ×1.15 across the three
#     tiers while ordinary waves swung ×1.0 / ×1.87 / ×2.76. Since Brutal pays a
#     strictly better reward table (RoundReward.ODDS: 0% Nothing vs 40%), Brutal
#     on an elite round was +15% difficulty for a full tier of loot — a dominant
#     strategy with no decision in it.
#   * The escort was always goblins, at round 5 and at round 95 alike.
#
# It now runs the same scored budget as every other wave, so 1.5× and 2.0× mean
# what they say and the escort is drawn from the pool.
#
# NORMAL IS THE ELITE ALONE (owner call, 2026-09-20) — matching what bosses
# already did. Extra bodies only appear on Veteran and Brutal. The elite stays
# the centrepiece; on Brutal it is no longer the whole fight.
static func build_elite_formation(round: int, difficulty: int, grid_width: int = 9,
		wave_seed: int = 0, score_fn: Callable = Callable()) -> Array:
	var base: Dictionary = {elite_code_for(round): 1}
	# The Gale Warden is a FLOCK (2026-09-28, owner design): the tier IS the
	# flock size, 4 / 6 / 8 birds. Each bird is a quarter of the old lone elite,
	# so 6 and 8 land on the 1.5× / 2.0× targets by construction — no filler.
	if elite_code_for(round) == "GW":
		return _auto_place({"GW": GALE_FLOCK_SIZE[difficulty]}, grid_width)
	if difficulty == Difficulty.NORMAL:
		return _auto_place(base, grid_width)
	# 2026-09-28 (owner call, crowd caps): the round's own elite may be bought
	# again as a SECOND ANCHOR — "1 or 2 of this other thing" instead of a pile of
	# filler. Priced at full elite level by WaveDirector.score_code on an elite
	# round, which is also how a second copy spawns. On Brutal the leftover
	# budget is exactly one more elite; Veteran's half-elite never affords it.
	# NOT the Ant Hill: its 20-ant cap is per hill, so two hills would field 40
	# ants — the exact board flood the crowd caps exist to remove.
	var second: Array = [] if elite_code_for(round) == "AH" else [elite_code_for(round)]
	return _auto_place(
		_topped_up(base, difficulty, round, wave_seed, score_fn, {}, second), grid_width)
