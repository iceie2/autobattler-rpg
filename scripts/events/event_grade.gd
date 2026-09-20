extends Object
class_name EventGrade
# ══════════════════════════════════════════════════════════════════════════════
# EVENT OUTCOME GRADES (2026-09-19, RUN_MAP_PLAN.md §4.1)
#
# Events were the one system in the game with no grade language: recruits, perks,
# relics and shop cards all roll F–S and all say so in the same colors, but an
# event just handed you a fixed number. This is that missing layer.
#
# The rule that keeps it from being a pure slot machine: THE CHOICE PICKS THE
# BAND, THE BAND PICKS THE SPREAD. A cautious choice rolls "safe" (D–B, no
# disasters and no jackpots); a greedy one rolls "wide" or "risky" (the full
# F–S spread, fat tails). So the player's decision still decides the shape of
# the outcome — the reel only decides where inside that shape they land.
#
# Magnitude multipliers are deliberately the SAME numbers as
# LevelUpScreen.PERK_GRADE_TABLE (0.5x at F → 2.2x at S): an S event payout and
# an S perk roll should feel like the same quality of luck, because the player
# reads them with the same letter and the same color.
# ══════════════════════════════════════════════════════════════════════════════

const ORDER: Array[String] = ["F", "D", "C", "B", "A", "S"]

# Grade → payout multiplier. Mirrors PERK_GRADE_TABLE.mult exactly.
const MULT := {"F": 0.5, "D": 0.75, "C": 1.0, "B": 1.3, "A": 1.7, "S": 2.2}

# Bands are weight tables over ORDER. Any grade absent from a band simply can't
# be rolled there — that absence IS the design (a "safe" choice cannot land an F
# and cannot land an S, which is exactly what makes it safe).
const BANDS := {
	# No roll at all: a flat trade is a flat trade. Resolves as C (1.0x) with no
	# reel, so authors can write deterministic choices without special-casing.
	"none":  {"C": 1},
	# Cautious: narrow, no tails. The "take the sure thing" option.
	"safe":  {"D": 25, "C": 45, "B": 30},
	# Standard gacha spread — identical weights to PERK_GRADE_TABLE.
	"wide":  {"F": 8, "D": 18, "C": 32, "B": 24, "A": 13, "S": 5},
	# Fat tails both ends: more F, more S, less middle. For the greedy option on
	# a risk/reward pair — it should genuinely be able to blow up in your face.
	"risky": {"F": 18, "D": 20, "C": 22, "B": 18, "A": 13, "S": 9},
}

const DEFAULT_BAND := "wide"

static func band_table(band: String) -> Dictionary:
	return BANDS.get(band, BANDS[DEFAULT_BAND])

# Roll one grade out of a band's weights.
static func roll(band: String) -> String:
	var table: Dictionary = band_table(band)
	var total: int = 0
	for w in table.values():
		total += int(w)
	if total <= 0:
		return "C"
	var r: int = randi() % total
	var acc: int = 0
	# Walk ORDER (not the dictionary) so the result is stable regardless of how
	# a band literal was typed.
	for g in ORDER:
		if not table.has(g):
			continue
		acc += int(table[g])
		if r < acc:
			return g
	return "C"

static func mult(grade: String) -> float:
	return float(MULT.get(grade, 1.0))

static func color(grade: String) -> Color:
	return UnitFactory.GRADE_COLORS.get(grade, Color(0.86, 0.86, 1.0))

# The candidate letters a band can produce — what the GradeRoll reel flashes
# through while spinning. A reel that can show an S on a "safe" choice would be
# lying about the odds, so the pool is the band, not the full alphabet.
static func reel_pool(band: String) -> Array:
	var pool: Array = []
	for g in ORDER:
		if band_table(band).has(g):
			pool.append(g)
	return pool

# True when a band is worth animating at all ("none" resolves instantly).
static func has_reel(band: String) -> bool:
	return band != "none" and reel_pool(band).size() > 1

# Scale an integer payout by a grade, never rounding a promised reward to 0.
static func scale_int(base: float, grade: String) -> int:
	return maxi(1, int(round(base * mult(grade))))

# Scale a MULTIPLIER-style effect (e.g. a 1.15 damage buff) by a grade. The
# grade scales the BONUS above 1.0, not the whole number — a 2.2x S roll on a
# 1.15 buff means +33%, not +153%.
static func scale_mult(base_mult: float, grade: String) -> float:
	return 1.0 + (base_mult - 1.0) * mult(grade)

# Same idea below 1.0 (a curse: 0.9 defense at S severity is 0.78, not 1.98).
static func scale_penalty(base_mult: float, grade: String) -> float:
	return 1.0 - (1.0 - base_mult) * mult(grade)
