class_name RecapPacing
extends RefCounted
# ══════════════════════════════════════════════════════════════════════════════
# How long the run-recap journey spends on each fight (2026-10-07). Pure maths so
# the timings can be checked without a screen.
#
# Total length INCLUDING the ending, by recorded fight count (owner targets):
#     1 -> ~4.2 s     5 -> 8 s     30 -> 15 s     100 -> 24 s
# piecewise-linear between those anchors, +0.12 s per fight past 100.
#
# The ending (final pause on the last encounter + trophy reveal / zoom-out) is
# reserved first. The rest is the FIGHT BUDGET: the first fight gets ~1.2 s and
# each next fight a constant fraction r of the one before, floored at MIN_FIGHT
# (0.12 s), with r solved so the steps fill the budget exactly. Bosses get a
# modest BOSS_BONUS carved out of the same budget. When even an unhurried
# 1.2 s per fight comes in under budget (a short run) nothing is padded - the
# journey is simply shorter.
# ══════════════════════════════════════════════════════════════════════════════

const ANCHORS := [[1, 4.2], [5, 8.0], [30, 15.0], [100, 24.0]]
const PER_FIGHT_PAST_LAST := 0.12
const FIRST_FIGHT := 1.2
const MIN_FIGHT := 0.12
const BOSS_BONUS := 0.25
const ELITE_BONUS := 0.10
const FINAL_PAUSE := 1.2           # the last encounter, outcome stamped
const REVEAL := 1.8                # trophies in, painting fades, camera frames the route

static func target_total(n: int) -> float:
	if n <= 0:
		return 0.0
	if n <= int(ANCHORS[0][0]):
		return float(ANCHORS[0][1])
	for i in range(ANCHORS.size() - 1):
		var a: Array = ANCHORS[i]
		var b: Array = ANCHORS[i + 1]
		if n <= int(b[0]):
			var k: float = float(n - int(a[0])) / float(int(b[0]) - int(a[0]))
			return lerpf(float(a[1]), float(b[1]), k)
	var last: Array = ANCHORS[ANCHORS.size() - 1]
	return float(last[1]) + PER_FIGHT_PAST_LAST * float(n - int(last[0]))

# kinds: one entry per fight in journey order - "boss", "elite" or "".
# -> {durations, starts, fights_end, final_pause, reveal, total}
static func plan(kinds: Array) -> Dictionary:
	var n: int = kinds.size()
	if n == 0:
		return {"durations": [], "starts": [], "fights_end": 0.0, "final_pause": 0.0,
			"reveal": 0.0, "total": 0.0}
	var budget: float = maxf(0.0, target_total(n) - FINAL_PAUSE - REVEAL)
	var bonus: Array = []
	var bonus_total := 0.0
	for k in kinds:
		var b: float = BOSS_BONUS if k == "boss" else (ELITE_BONUS if k == "elite" else 0.0)
		bonus.append(b)
		bonus_total += b
	# Bonuses never squeeze ordinary fights under the floor.
	var room: float = budget - float(n) * MIN_FIGHT
	if bonus_total > maxf(0.0, room) * 0.5 and bonus_total > 0.0:
		var scale: float = maxf(0.0, room) * 0.5 / bonus_total
		for i in range(n):
			bonus[i] = float(bonus[i]) * scale
		bonus_total *= scale
	var base_budget: float = budget - bonus_total
	var r: float = _solve_ratio(n, base_budget)
	var durations: Array = []
	var starts: Array = []
	var t := 0.0
	for i in range(n):
		var d: float = maxf(MIN_FIGHT, FIRST_FIGHT * pow(r, float(i))) + float(bonus[i])
		starts.append(t)
		durations.append(d)
		t += d
	return {"durations": durations, "starts": starts, "fights_end": t,
		"final_pause": FINAL_PAUSE, "reveal": REVEAL, "total": t + FINAL_PAUSE + REVEAL}

static func _sum(n: int, r: float) -> float:
	var s := 0.0
	for i in range(n):
		s += maxf(MIN_FIGHT, FIRST_FIGHT * pow(r, float(i)))
	return s

# Largest r in (0, 1] whose steps fit `budget`; 1.0 (no acceleration, no padding)
# when an unhurried pace already fits.
static func _solve_ratio(n: int, budget: float) -> float:
	if _sum(n, 1.0) <= budget:
		return 1.0
	var lo := 0.0
	var hi := 1.0
	for _i in range(48):
		var mid: float = (lo + hi) * 0.5
		if _sum(n, mid) > budget:
			hi = mid
		else:
			lo = mid
	return lo
