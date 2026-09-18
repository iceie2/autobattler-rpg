extends Node
# ══════════════════════════════════════════════════════════════════════════════
# Scaling probe (2026-08-07) — "do enemies reflect how much the player scales?"
#
# The first tester run showed a bimodal outcome curve (waves 5-28, then a clean
# 100) and the user's read is that heroes out-scale the enemy curve badly. This
# measures BOTH curves on the same axis instead of arguing about it:
#
#   HERO side  — every player class built at levels 1/10/20/30/40/50, scored
#                with WaveScaler.score_unit (the game's own power metric).
#   ENEMY side — the ACTUAL wave the live game generates for a round, via the
#                same WaveDirector main_game uses, summed with the same score.
#
# Deliberately no battle simulation: this is the raw stat curve, so a divergence
# here is a design fact, not a formation/AI artifact. Battle sims are the
# follow-up (arena --mode=sim), and they should agree with whatever this shows.
#
# NOTE ON THE LEVEL CAP: UnitBase.set_level() clamps player units to
# Progression.hero_level_cap(). This probe runs with a fresh Progression (no
# crystal nodes), so the cap it reports is the FLOOR of what a real account can
# reach — heroes at high levels here are the pessimistic case, not the optimistic
# one. The cap is printed so the numbers can be read honestly.
# ══════════════════════════════════════════════════════════════════════════════

const HERO_LEVELS: Array[int] = [1, 10, 20, 30, 40, 50]
const ROUNDS: Array[int] = [1, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100]
const GRID_WIDTH := 9

# One representative per archetype rather than all 26 — the growth tables are
# per-class, so a carry/tank/caster triple brackets the whole roster's spread.
# SABLE has the highest atk growth (3), CROSS the highest hp growth (60),
# ZOLT/LUMEN the highest magic growth (4). If the spread between them is small,
# the roster scales as one and a single fix applies to all of it.
const SAMPLE_CLASSES: Array[String] = [
	"SABLE", "HEADHUNTER", "SHAUNA", "CROSS", "RIOT", "ZOLT", "LUMEN", "DOC", "SPORE",
]

func _ready() -> void:
	print("SCALING_PROBE_BEGIN")
	print("hero_level_cap (fresh account) = %d" % Progression.hero_level_cap())
	_hero_curve()
	_enemy_curve()
	_ratio_table()
	print("SCALING_PROBE_END")
	get_tree().quit()

# ── Hero side ─────────────────────────────────────────────────────────────────

# score_unit for one class at one level. Builds, levels, scores, frees.
func _hero_score(class_name_str: String, lvl: int) -> Dictionary:
	var uc: int = UnitBase.UnitClass.get(class_name_str, -1)
	if uc < 0:
		return {}
	var u: VisualUnit = UnitFactory.create_unit(uc, UnitBase.Element.NORMAL, true)
	if u == null:
		return {}
	add_child(u)
	# Level via the real level_up() path (not a stat poke) so growth carry,
	# progression growth bonuses and the cap all behave exactly as in a run.
	u.set_level(lvl)
	var out := {
		"level": u.level,
		"score": snappedf(WaveScaler.score_unit(u), 0.1),
		"hp": u.max_hp, "atk": u.attack_damage, "mag": u.magic_power,
		"res": u.resistance, "aspd": snappedf(u.attack_speed, 0.01),
	}
	remove_child(u)
	u.queue_free()
	return out

func _hero_curve() -> void:
	print("\n── HERO POWER BY LEVEL (score_unit) ──")
	print("class        " + "".join(HERO_LEVELS.map(func(l): return "  lvl%-9d" % l)))
	for cn: String in SAMPLE_CLASSES:
		var row := "%-12s" % cn
		for lvl: int in HERO_LEVELS:
			var d := _hero_score(cn, lvl)
			row += "  %-12s" % ("%.0f" % float(d.get("score", 0.0)))
		print(row)

	# Same table again as a multiple of the class's own level-1 score — this is
	# the number that answers "how much do we scale", independent of base stats.
	print("\n── HERO POWER AS A MULTIPLE OF ITS OWN LEVEL 1 ──")
	print("class        " + "".join(HERO_LEVELS.map(func(l): return "  lvl%-9d" % l)))
	for cn: String in SAMPLE_CLASSES:
		var base: float = float(_hero_score(cn, 1).get("score", 1.0))
		if base <= 0.0:
			base = 1.0
		var row := "%-12s" % cn
		for lvl: int in HERO_LEVELS:
			var s: float = float(_hero_score(cn, lvl).get("score", 0.0))
			row += "  %-12s" % ("%.2fx" % (s / base))
		print(row)

	# Raw statlines at the sampled levels for one carry — so the growth is
	# legible as numbers a designer can reason about, not just an index.
	print("\n── STATLINE DETAIL: SABLE (highest atk growth in the roster) ──")
	print("%-6s %-8s %-7s %-7s %-6s %-7s %s" % ["lvl", "hp", "atk", "mag", "res", "aspd", "score"])
	for lvl: int in HERO_LEVELS:
		var d := _hero_score("SABLE", lvl)
		print("%-6d %-8d %-7d %-7d %-6d %-7.2f %.0f" % [
			int(d.get("level", 0)), int(d.get("hp", 0)), int(d.get("atk", 0)),
			int(d.get("mag", 0)), int(d.get("res", 0)),
			float(d.get("aspd", 0.0)), float(d.get("score", 0.0))])

# ── Enemy side ────────────────────────────────────────────────────────────────

# Total + per-unit score of the wave the LIVE game generates for `round`.
# Uses a fresh WaveDirector per call, matching arena_main._spawn_wave.
func _wave_score(round: int, difficulty: int) -> Dictionary:
	# WaveDirector is a RefCounted, not a Node — it is never parented.
	var director := WaveDirector.new()
	var total := 0.0
	var best := 0.0
	var count := 0
	var lvl_sum := 0
	# Track the single biggest body's real statline — the score proxy proved
	# untrustworthy (2026-08-07), so the raw HP/atk is what gets compared
	# against what the live game actually shows on screen.
	var big_hp := 0
	var big_atk := 0
	var big_lvl := 0
	var big_name := ""
	for entry: Dictionary in director.generate_wave_spec(round, difficulty, GRID_WIDTH):
		var u: VisualUnit = director.create_enemy_for_entry(entry, round)
		if u == null:
			continue
		add_child(u)
		var s: float = WaveScaler.score_unit(u)
		total += s
		if s > best:
			big_hp = u.max_hp
			big_atk = u.attack_damage
			big_lvl = u.level
			big_name = u.unit_name
		best = maxf(best, s)
		lvl_sum += u.level
		count += 1
		remove_child(u)
		u.queue_free()
	return {
		"total": total, "count": count, "biggest": best,
		"avg_level": (float(lvl_sum) / float(count)) if count > 0 else 0.0,
		"big_hp": big_hp, "big_atk": big_atk, "big_lvl": big_lvl, "big_name": big_name,
	}

func _enemy_curve() -> void:
	print("\n── ENEMY WAVE POWER BY ROUND (sum of score_unit, NORMAL) ──")
	print("%-7s %-7s %-8s %-22s %-6s %-10s %s" % [
		"round", "units", "avg_lv", "biggest body", "lv", "its HP", "its ATK"])
	for r: int in ROUNDS:
		var d := _wave_score(r, 0)
		print("%-7d %-7d %-8.1f %-22s %-6d %-10d %d" % [
			r, int(d["count"]), float(d["avg_level"]),
			String(d["big_name"]), int(d["big_lvl"]),
			int(d["big_hp"]), int(d["big_atk"])])

# ── The comparison that matters ───────────────────────────────────────────────

# A full 10-hero team at the level the game actually hands out by that round,
# against that round's wave. team_level_for_round mirrors the XP pacing well
# enough for a ratio: the tester's winning run fielded levels 14-17 at wave 100,
# so this uses the OBSERVED pacing rather than a theoretical curve.
#
# Observed anchors from the 2026-08-06 tester export:
#   wave 21 → ~lvl 8    wave 28 → ~lvl 10    wave 100 → lvl 14-17
# Linear between them, which is deliberately GENEROUS to the enemy side.
func _team_level_for_round(r: int) -> int:
	if r <= 1: return 1
	if r <= 30: return clampi(1 + int(float(r) * 0.33), 1, 10)
	return clampi(10 + int(float(r - 30) * 0.09), 10, 17)

func _ratio_table() -> void:
	print("\n── TEAM vs WAVE (10 heroes at observed run pacing, NORMAL) ──")
	print("If the ratio climbs, the player is out-scaling the content.")
	print("%-7s %-8s %-14s %-14s %s" % ["round", "team_lv", "team_power", "wave_power", "team/wave"])
	for r: int in ROUNDS:
		var lvl: int = _team_level_for_round(r)
		# Average the sample classes so the team isn't a single-class outlier.
		var per_hero := 0.0
		for cn: String in SAMPLE_CLASSES:
			per_hero += float(_hero_score(cn, lvl).get("score", 0.0))
		per_hero /= float(SAMPLE_CLASSES.size())
		var team_power: float = per_hero * 10.0
		var wave: float = maxf(float(_wave_score(r, 0)["total"]), 1.0)
		print("%-7d %-8d %-14.0f %-14.0f %.2fx" % [
			r, lvl, team_power, wave, team_power / wave])
