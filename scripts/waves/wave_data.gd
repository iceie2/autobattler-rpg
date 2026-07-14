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
#  KHA = Khagan (wave-10 boss, mount-swap fight); TRI = The Triarch (wave-20 boss, 3-phase fight)
#  HYN/HYF/HYW/HYE/HYA/HYL = Hydra (wave-30 final boss, player picks the element pre-battle; time-based head-regrowth)
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
# Three ramps stack to get there: base composition power (~540 at wave 11 up
# to ~1300 at wave 29, per WaveScaler.UNIT_POWER costs), enemy level (fixed
# waves 11+ spawn at WaveScaler.enemy_level_for_round — ~3-5 at wave 11 up to
# ~18-20 at wave 29; waves 1-9 stay level 1), and the round-11+ enemy stat
# multiplier (Balance.enemy_late_hp_mult/dmg_mult, applied in WaveDirector).
# Elite mini-bosses (G/SS/AH) are EXCLUSIVE to rounds 5/15/25 — never place
# them in these compositions (user rule). Boss rounds (10/20/30) and elite
# rounds (5/15/25) never reach these tables — WaveScaler dispatches them first,
# which is why those slots return {}.
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
		# ── Act 2 (11-19): the ramp toward the Triarch ────────────────────────
		11: return {"BRN": 2, "WUN": 2, "A": 3, "TLN": 1}                          # shield wall — first bear frontline
		12: return {"SLN": 4, "SLF": 4, "SLA": 4, "GSW": 2, "TLW": 2}              # slime flood — 16 bodies, quantity wave
		13: return {"LZF": 3, "LZL": 3, "BN": 2, "TLF": 1, "A": 2, "M": 2}         # firing line — ranged-heavy, punish slow teams
		14: return {"BF": 2, "BL": 2, "B": 1, "GSA": 2, "S": 1}                    # orc warband — heavy melee press
		15: return {}   # elite round
		16: return {"BRF": 2, "BRW": 2, "BRE": 1, "TLW": 2, "GSL": 1, "A": 1}      # bear wall — HP check
		17: return {"WUL": 3, "WUA": 2, "LZL": 2, "GSL": 2, "TLL": 2}              # lightning storm — fast strikers + stuns
		18: return {"BF": 3, "WUF": 2, "S": 2, "TLF": 2, "LZF": 2}                 # fire legion — mono-element burn
		19: return {"BN": 2, "BW": 2, "BRN": 1, "GSN": 2, "TLN": 2, "LZN": 2, "A": 2}  # the muster — combined arms before the Triarch
		20: return {}   # boss: The Triarch
		# ── Act 3 (21-29): only upgraded rosters should survive this ──────────
		21: return {"BN": 1, "BF": 1, "BW": 1, "BA": 1, "BL": 1, "B": 1, "GSE": 2, "TLE": 2, "LZE": 2, "WUE": 1}  # world tour — one orc of every element
		22: return {"SLL": 4, "SLE": 4, "WUN": 3, "WUW": 2, "TLW": 2, "GSW": 2, "BRW": 1}  # slime flood II — swarm with real support
		23: return {"LZN": 2, "LZF": 2, "LZW": 2, "LZA": 2, "BRN": 2, "BRE": 1, "TLA": 2, "GSA": 2, "WUA": 2}    # sniper nest — 8 ranged behind a bear line
		24: return {"M": 6, "A": 6, "BN": 2, "S": 2, "WUN": 2, "TLN": 2, "BRN": 1}  # the horde — wave-1 mobs, 21 strong, at act-3 levels
		25: return {}   # elite round
		26: return {"BRF": 2, "BRL": 2, "WUF": 2, "WUL": 2, "TLF": 2, "GSL": 2, "LZF": 2, "BF": 1}  # scorched vanguard — bear/bot core with full support
		27: return {"BRW": 2, "BRN": 1, "BW": 2, "BN": 2, "LZW": 2, "GSW": 2, "TLW": 2, "SLN": 4, "WUW": 1}  # the tide wall — deep water-heavy frontline
		28: return {"WUN": 1, "WUF": 1, "WUW": 1, "WUE": 1, "WUA": 1, "WUL": 1, "BRA": 2, "TLL": 2, "GSL": 2, "GSA": 2, "LZL": 2, "BA": 1}  # elemental storm — every bot element at once
		29: return {"BRN": 2, "BRE": 2, "BL": 2, "BN": 2, "TLN": 2, "GSN": 2, "WUN": 2, "LZN": 2}   # the last gate — everything short of the Hydra
		30: return {}   # boss: the Hydra
		_:  return {}   # round 31+: procedural escalation (endless overflow)
