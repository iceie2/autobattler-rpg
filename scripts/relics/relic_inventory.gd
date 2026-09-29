extends RefCounted
class_name RelicInventory

# Holds the relics picked this run and applies their run-wide effects. Stat
# effects are applied per-unit exactly once â€” guarded by a per-unit applied-set
# of unique acquisition ids â€” so heroes bought at different waves each receive
# every owned relic exactly once, and a relic is never double-stacked on a unit.

signal relics_changed()

# Stats treated as floats (never int-rounded). Everything else multiplies as int.
const FLOAT_STATS: Array[String] = ["attack_speed", "hp_regen", "mana_regen", "crit_chance", "crit_damage"]

var owned: Array = []          # Array of relic dicts, each tagged with "_acq"
var _next_acq: int = 0

# Record a freshly-picked relic. Returns the stored copy (tagged with a unique
# "_acq" id) so the caller can immediately apply it to existing units.
func add_relic(relic: Dictionary) -> Dictionary:
	var r: Dictionary = relic.duplicate(true)
	r["_acq"] = _next_acq
	_next_acq += 1
	owned.append(r)
	relics_changed.emit()
	return r

func owned_ids() -> Array:
	var ids: Array = []
	for r in owned:
		ids.append(r.get("id", ""))
	return ids

func is_empty() -> bool:
	return owned.is_empty()

# All sub-effects of a relic (supports the `effects` array, with a single-`effect`
# fallback for safety).
func _effects_of(relic: Dictionary) -> Array:
	if relic.has("effects"):
		return relic.get("effects", [])
	if relic.has("effect"):
		return [relic.get("effect", {})]
	return []

# Total +gold granted per round from all economy relics.
func gold_per_round() -> int:
	var g := 0
	for r in owned:
		for e in _effects_of(r):
			if e.get("type", "") == "gold_round":
				g += int(e.get("value", 0))
	return g

# Total extra hero cards the shop should show from all owned relics.
func shop_slot_bonus() -> int:
	var n := 0
	for r in owned:
		for e in _effects_of(r):
			if e.get("type", "") == "shop_slots":
				n += int(e.get("value", 0))
	return n

# Verbs of every SEED relic owned (VD-16). The hero shop leans toward heroes
# with these verbs, so a seed is a plan the player can act on.
func seed_verbs() -> Array:
	var out: Array = []
	for r in owned:
		if r.get("seed", false):
			var v := String(r.get("verb", ""))
			if v != "" and not v in out:
				out.append(v)
	return out

# Apply every owned relic's stat effect to one unit (each at most once).
func apply_all_to_unit(unit) -> void:
	for r in owned:
		_apply_one(unit, r)

# Apply one already-owned (tagged) relic to a list of units â€” used when a relic
# is freshly acquired so heroes already on the team get it retroactively.
func apply_relic_to_units(relic: Dictionary, units: Array) -> void:
	for u in units:
		_apply_one(u, relic)

# â”€â”€ Internals â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
func _apply_one(unit, relic: Dictionary) -> void:
	if not (unit and is_instance_valid(unit)):
		return
	var acq: int = int(relic.get("_acq", -1))
	var applied: Array = unit.get_meta("relics_applied", [])
	if acq in applied:
		return
	applied.append(acq)
	unit.set_meta("relics_applied", applied)

	for e in _effects_of(relic):
		_apply_effect(unit, e)

func _apply_effect(unit, e: Dictionary) -> void:
	match e.get("type", ""):
		"stat_mult":
			_mult_stat(unit, e.get("stat", ""), float(e.get("value", 1.0)))
		"stat_mult_multi":
			for s in e.get("stats", []):
				_mult_stat(unit, s, float(e.get("value", 1.0)))
		"stat_add":
			_add_stat(unit, e.get("stat", ""), float(e.get("value", 0.0)))
		"element_mult":
			# Everyone gets `base`; units of the named element get `matched` instead.
			var matched: bool = int(unit.current_element) == int(e.get("element", -1))
			var m: float = float(e.get("matched", 1.0)) if matched else float(e.get("base", 1.0))
			_mult_stat(unit, e.get("stat", ""), m)
		# â”€â”€ Per-unit combat modifier fields (read by UnitBase / battle manager) â”€â”€
		"lifesteal":
			unit.relic_lifesteal += float(e.get("value", 0.0))
		"outgoing":
			unit.relic_outgoing_mult *= float(e.get("value", 1.0))
		"dmg_taken":
			unit.relic_dmg_taken_mult *= float(e.get("value", 1.0))
		"vs_boss":
			unit.relic_vs_boss_mult *= float(e.get("value", 1.0))
		"ult_charge":
			unit.relic_ult_charge_mult *= float(e.get("value", 1.0))
		"double_atk":
			unit.relic_double_atk_chance = minf(1.0, unit.relic_double_atk_chance + float(e.get("value", 0.0)))
		"start_shield":
			unit.relic_start_shield_pct += float(e.get("value", 0.0))
		"regen_pct":
			unit.relic_regen_pct += float(e.get("value", 0.0))
		"free_ult":
			unit.relic_free_first_ult = true
		"revive":
			unit.relic_revive_pct = maxf(unit.relic_revive_pct, float(e.get("value", 0.0)))
		"on_kill_atk":
			unit.relic_on_kill_atk += float(e.get("value", 0.0))
		"execute_pct":
			unit.relic_execute_threshold = maxf(unit.relic_execute_threshold, float(e.get("hp_threshold_pct", 0.0)))
			unit.relic_execute_bonus += float(e.get("dmg_bonus_pct", 0.0))
		"row_stat_mult":
			unit.relic_row_front_mult *= float(e.get("front_mult", 1.0))
			unit.relic_row_back_mult *= float(e.get("back_mult", 1.0))
		"battle_start_dmg_window":
			unit.relic_opening_burst_pct += float(e.get("dmg_bonus_pct", 0.0))
			unit.relic_opening_burst_window = maxf(unit.relic_opening_burst_window, float(e.get("seconds", 0.0)))
		"ult_refund_kill":
			unit.relic_ult_refund_kill += float(e.get("value", 0.0))
		"gold_scaling_dmg":
			unit.relic_gold_scaling_dmg += float(e.get("value", 0.0))
		"momentum":
			unit.relic_momentum_pct_per_sec += float(e.get("pct_per_sec", 0.0))
		"underdog":
			unit.relic_underdog_dmg_per_dead += float(e.get("dmg_per_dead", 0.0))
			unit.relic_underdog_res_per_dead += float(e.get("res_per_dead", 0.0))
		# ── Burn archetype pieces (VD-16). The battle manager reads these as
		# team-wide values at battle start; see AutoBattleManager._setup_burn_pieces.
		"burn_per_burner":
			unit.relic_burn_per_burner += float(e.get("value", 0.0))
		"burn_stack_share":
			unit.relic_burn_stack_share = maxf(unit.relic_burn_stack_share, float(e.get("value", 0.0)))
		"burn_leap":
			unit.relic_burn_leap = maxf(unit.relic_burn_leap, float(e.get("value", 0.0)))
		"burn_ult_haste":
			unit.relic_burn_ult_haste += float(e.get("value", 0.0))
		# ── Element pieces (VD-22): one dict, read at battle start by ElementPieces.
		"earth_shred_pct", "earth_rubble", "earth_landslide", "earth_aftershock", "earth_tectonic", \
		"light_stun_ext", "light_conductive", "light_arc", "light_ult_haste", "light_thunder", \
		"water_soak", "water_saturate", "water_riptide", "water_tidecall", "water_deluge", \
		"air_extra_chance", "air_chain", "air_slip", "air_updraft", "air_tempest":
			var k: String = e.get("type", "")
			unit.relic_arch[k] = maxf(float(unit.relic_arch.get(k, 0.0)), float(e.get("value", 0.0)))
		"burn_flare":
			unit.relic_burn_flare_secs = maxf(unit.relic_burn_flare_secs, float(e.get("value", 0.0)))
		# gold_round / shop_slots are run-economy effects (see gold_per_round /
		# shop_slot_bonus) â€” no per-unit mutation.

func _mult_stat(unit, stat: String, m: float) -> void:
	if stat == "":
		return
	if stat == "max_hp":
		unit.max_hp = maxi(1, int(round(unit.max_hp * m)))
		unit.current_hp = clampi(int(round(unit.current_hp * m)), 1, unit.max_hp)
	elif stat == "max_mana":
		unit.max_mana = maxi(0, int(round(unit.max_mana * m)))
		unit.current_mana = mini(unit.current_mana, unit.max_mana)
	elif stat in FLOAT_STATS:
		unit.set(stat, float(unit.get(stat)) * m)
	else:
		unit.set(stat, maxi(0, int(round(float(unit.get(stat)) * m))))

func _add_stat(unit, stat: String, v: float) -> void:
	if stat == "":
		return
	if stat == "max_hp":
		var add := int(v)
		unit.max_hp = maxi(1, unit.max_hp + add)
		unit.current_hp = mini(unit.current_hp + add, unit.max_hp)
	elif stat in FLOAT_STATS:
		unit.set(stat, float(unit.get(stat)) + v)
	else:
		unit.set(stat, int(unit.get(stat)) + int(v))
