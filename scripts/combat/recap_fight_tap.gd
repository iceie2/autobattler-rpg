class_name RecapFightTap
extends RefCounted
# ══════════════════════════════════════════════════════════════════════════════
# RUN-RECAP FIGHT TAP (2026-10-07) - the two per-fight facts the run recap needs
# that the final-battle recorder (BattleRecorder) does not keep:
#
#   1. CASTER PROTECTION - damage absorbed by shields a hero SUPPLIED.
#   2. ENEMY DEFEATS by type.
#
# It sits beside BattleRecorder rather than inside it so the defeat infographic's
# recorder (and its smoke test) stay untouched. One per AutoBattleManager; begin()
# at battle start, snapshot() at the final whistle, exactly where the recorder is
# begun and frozen. Plain data out, no node references kept after snapshot().
#
# ── PROTECTION ────────────────────────────────────────────────────────────────
# BattleRecorder's `taken_shield` is RECIPIENT-side (what shields on a hero
# soaked) and stays the defeat report's "Shields absorbed". This tap credits the
# SUPPLIER:
#   protect_out   absorbed on ANOTHER ally by a shield this hero supplied
#   protect_self  absorbed on this hero by shields it supplied itself: self-cast
#                 pool shields, relic start shields, Overflow from its own
#                 overheal, plus its item shields and Mana Shield (GearPassives -
#                 always the holder's own items)
#   unattributed  pool absorption whose grant had no known hero source, or came
#                 from an enemy. Reported as its own number; never guessed onto
#                 a caster.
# Credit happens only when a hit is absorbed, so capacity that expires, is wiped
# at the final whistle or is never hit counts for nobody.
#
# A player SUMMON's shields, and shields ON a summon, roll into the owning hero
# exactly once: every unit is resolved to its credit hero (itself, or its
# summon_owner) before anything is added, and a summon never gets its own row.
#
# CONSUMPTION ORDER. UnitBase.current_shield is ONE additive pool; the game has
# no per-source order, so attribution can never change a fight. Every grant is
# noted (note_shield_grant) in a per-holder ledger, and absorption spends the
# ledger OLDEST FIRST (FIFO). Before each absorption the ledger is reconciled
# with the real pool: if something other than a hit cut the pool (battle start /
# end, Khagan possession and phase changes all zero it) the ledger is trimmed
# oldest-first to match; if the pool holds more than the ledger knows of, the
# excess becomes an explicit unattributed grant.
#
# ── DEFEATS ───────────────────────────────────────────────────────────────────
# main_game calls on_enemy_defeat at the exact point it counts a run kill
# (_on_unit_died -> _run_kills += 1), so a fight's tally is the run's "Enemies
# defeated" definition, split by type: every confirmed `died` of an enemy-roster
# unit while this fight is open. A phase change (Triarch, Khagan, rebirth) is not
# a death. An enemy revived and killed again counts once per death. Enemy summons
# count under their own type and ALSO in `summoned`. A kill landing after the
# final whistle (a projectile still in flight when the last hero fell) belongs to
# no fight and is not recorded.
# ══════════════════════════════════════════════════════════════════════════════

const MAX_LEDGER := 64                # grants remembered per holder; overflow merges the oldest two
const MAX_DEFEAT_TYPES := 96          # distinct enemy types per fight; beyond that they pool as OTHER
const OTHER_KEY := "_other"

# Ledger credit codes besides a hero instance id.
const CREDIT_NONE := 0                # a grant with no known hero source
const CREDIT_ENEMY := -1              # a grant from an enemy-side unit

# A battle's identity is (session nonce, serial). The serial counts battles for
# the whole PROCESS, not per manager: quitting to the menu and pressing Continue
# builds a new manager in the same process, and a per-manager count restarted at
# 1 there, so a replayed fight collided with the original's token and was refused
# instead of replacing it (caught by run_recap_integration). The nonce keeps a
# fight from an earlier game session distinct. RunRecap uses the pair to finalise
# each fight exactly once.
static var _session_nonce: int = 0
static var _battle_counter: int = 0

var serial: int = 0
var _open: bool = false
var _protect: Dictionary = {}         # hero instance id -> [out, self]
var _uids: Dictionary = {}            # hero instance id -> RunRecap uid (meta "recap_uid")
var _unattributed: int = 0
var _ledger: Dictionary = {}          # holder instance id -> Array of [credit, amount]
var _defeats: Dictionary = {}         # type key -> {key, name, portrait, n, summoned, boss, elite}
var _defeat_total: int = 0
var _summoned_total: int = 0
var _headliners: Array = []           # [{name, key, boss, elite}] fielded at battle start
# The order enemies fell in (type keys), so the recap's defeat parade can replay
# each wave's kills in sequence. Bounded; counts in _defeats stay exact beyond it.
const MAX_ORDER := 512
var _order: Array = []

# ── DAMAGE BREAKDOWN (owner, 2026-10-07: "a breakdown of all its damage") ──────
# Every hit that counts toward a hero's Damage (BattleRecorder `dealt_hp`: HP
# removed from an opposing unit, overkill and enemy-shield soak excluded) is
# also filed by SOURCE x TYPE, so the sources always sum to that total:
#   source  AUTO      the attacker's basic attack (UnitBase.gear_basic_hit -
#                     the flag item passives already use; includes on-hit procs
#                     and basic projectiles)
#           SKILL     inside the attacker's active-skill cast, its projectiles
#                     and channels (UnitBase.recap_action set by the manager),
#                     and the manager's delayed-hit queues that belong to that
#                     skill (set_ambient around the queue's tick: Bouncer's
#                     reel, Nemi's tide, Zolt's storm...)
#           ULT       the same for the ultimate
#           DOT       burn / bleed / poison ticks and spore bursts
#           SUMMON    dealt by a summon, credited to its owner
#           PASSIVE   the hero's passive: on-hit passives, its passive tick,
#                     reactive reflects / redirects (in_passive)
#           OTHER     anything not tagged above. Never guessed.
# Precedence follows that list: a hit inside a skill cast that also triggers an
# on-hit passive is the skill's, as the cast window has always meant.
#   type    PHYS (armour-mitigated), MAGIC (magic-resist-mitigated), TRUE
const SRC_AUTO := 0
const SRC_SKILL := 1
const SRC_ULT := 2
const SRC_DOT := 3
const SRC_SUMMON := 4
const SRC_OTHER := 5
const SRC_PASSIVE := 6                # appended: records written with 6 sources still read
const SOURCES := 7
const TYPE_PHYS := 0
const TYPE_MAGIC := 1
const TYPE_TRUE := 2
const TYPES := 3
var in_dot: bool = false              # set by the manager around status-tick damage
var in_passive: bool = false          # set by the manager around passive damage
var _ambient_cls: int = -1            # a delayed-hit queue's hero class...
var _ambient_action: int = 0          # ...and its ability (1 skill, 2 ult)
var _split: Dictionary = {}           # hero instance id -> Array[SOURCES * TYPES]

func is_open() -> bool:
	return _open

func token() -> String:
	return "%d-%d" % [_session_nonce, serial]

func begin(player_units: Array, enemy_units: Array = []) -> void:
	if _session_nonce == 0:
		_session_nonce = randi_range(1, 1 << 30)
	_battle_counter += 1
	serial = _battle_counter
	_open = true
	_protect.clear()
	_uids.clear()
	_unattributed = 0
	_ledger.clear()
	_defeats.clear()
	_defeat_total = 0
	_summoned_total = 0
	_headliners.clear()
	_order.clear()
	_split.clear()
	in_dot = false
	in_passive = false
	clear_ambient()
	for u in player_units:
		var h = _credit_hero(u)
		if h != null:
			_hero(h)
	# The bosses / elites actually standing at the opening whistle, so the recap
	# can name the encounter from the fight itself rather than from a wave table.
	for e in enemy_units:
		if is_instance_valid(e) and e is UnitBase and (e.is_boss or e.is_elite):
			var key: String = enemy_type_key(e)
			var seen := false
			for hl in _headliners:
				seen = seen or hl["key"] == key
			if not seen and _headliners.size() < 8:
				_headliners.append({"name": String(e.unit_name), "key": key,
					"boss": bool(e.is_boss), "elite": bool(e.is_elite)})

# ── Identity ──────────────────────────────────────────────────────────────────

static func _is_hero(u) -> bool:
	return is_instance_valid(u) and u is UnitBase and u.is_player_unit and not u.is_summoned

# The hero a unit's shields are credited to: itself, or its owner for a summon.
static func _credit_hero(u) -> Variant:
	if not (is_instance_valid(u) and u is UnitBase):
		return null
	var o: UnitBase = u
	if u.is_summoned and is_instance_valid(u.summon_owner):
		o = u.summon_owner
	return o if _is_hero(o) else null

func _hero(h: UnitBase) -> Array:
	var id: int = h.get_instance_id()
	if not _protect.has(id):
		_protect[id] = [0, 0]
		_uids[id] = int(h.get_meta("recap_uid", 0))
	return _protect[id]

static func _credit_code(source) -> int:
	if not (is_instance_valid(source) and source is UnitBase):
		return CREDIT_NONE
	var h = _credit_hero(source)
	if h != null:
		return h.get_instance_id()
	return CREDIT_ENEMY if not source.is_player_unit else CREDIT_NONE

# ── Shields ───────────────────────────────────────────────────────────────────

# Called right after `amount` was ADDED to holder.current_shield. `source` is the
# unit that supplied it (null when unknown). Only player-side holders matter.
func note_shield_grant(holder, source, amount: int) -> void:
	if not _open or amount <= 0 or not (is_instance_valid(holder) and holder is UnitBase):
		return
	if not holder.is_player_unit:
		return
	var id: int = holder.get_instance_id()
	var led: Array = _ledger.get(id, [])
	# Reconcile against the pool as it stood BEFORE this grant.
	_reconcile(led, int(holder.current_shield) - amount)
	led.append([_credit_code(source), amount])
	while led.size() > MAX_LEDGER:
		# Merge the two oldest. Same credit -> still exact. Different credits
		# cannot share one entry without guessing, so the merged amount becomes
		# unattributed (only reachable after 64 live grants on one holder).
		var a: Array = led[0]
		var b: Array = led[1]
		var merged: Array = [a[0] if a[0] == b[0] else CREDIT_NONE, int(a[1]) + int(b[1])]
		led.remove_at(0)
		led[0] = merged
	_ledger[id] = led

# One resolved hit on a player-side unit. `shield_absorbed` = all shield layers
# that soaked this hit; `pool_absorbed` = the part the ordinary pool took (the
# rest were the holder's own item shields / Mana Shield). Called after the pool
# was already reduced, so the pool before the hit is current_shield + pool.
func on_shield_hit(holder, shield_absorbed: int, pool_absorbed: int) -> void:
	if not _open or shield_absorbed <= 0 or not (is_instance_valid(holder) and holder is UnitBase):
		return
	if not holder.is_player_unit:
		return
	var pool: int = clampi(pool_absorbed, 0, shield_absorbed)
	var own_items: int = shield_absorbed - pool
	var holder_hero = _credit_hero(holder)
	if own_items > 0:
		if holder_hero != null:
			_hero(holder_hero)[1] += own_items
		else:
			_unattributed += own_items
	if pool <= 0:
		return
	var id: int = holder.get_instance_id()
	var led: Array = _ledger.get(id, [])
	_reconcile(led, int(holder.current_shield) + pool)
	var left := pool
	while left > 0 and not led.is_empty():
		var entry: Array = led[0]
		var take: int = mini(left, int(entry[1]))
		_credit(int(entry[0]), holder_hero, take)
		left -= take
		entry[1] = int(entry[1]) - take
		if int(entry[1]) <= 0:
			led.remove_at(0)
	if left > 0:
		_unattributed += left   # cannot happen after _reconcile; kept as a guard
	_ledger[id] = led

func _credit(code: int, holder_hero, amount: int) -> void:
	if amount <= 0:
		return
	if code == CREDIT_NONE or code == CREDIT_ENEMY:
		_unattributed += amount
		return
	var supplier = instance_from_id(code)
	if not _is_hero(supplier):
		_unattributed += amount
		return
	var slot: Array = _hero(supplier)
	if holder_hero != null and supplier == holder_hero:
		slot[1] += amount
	else:
		slot[0] += amount

# Make the ledger total equal `pool` (oldest-first trim, or an unattributed top-up).
static func _reconcile(led: Array, pool: int) -> void:
	pool = maxi(0, pool)
	var total := 0
	for e in led:
		total += int(e[1])
	if total > pool:
		var cut := total - pool
		while cut > 0 and not led.is_empty():
			var take: int = mini(cut, int(led[0][1]))
			led[0][1] = int(led[0][1]) - take
			cut -= take
			if int(led[0][1]) <= 0:
				led.remove_at(0)
	elif total < pool:
		led.append([CREDIT_NONE, pool - total])

# The manager's delayed-hit queues run outside any cast. Each belongs to one
# hero ability, so the manager names it around the queue's tick; hits by heroes
# of that class while it is set are filed under that ability.
func set_ambient(cls: int, action: int) -> void:
	_ambient_cls = cls
	_ambient_action = action

func clear_ambient() -> void:
	_ambient_cls = -1
	_ambient_action = 0

# One HP-removing hit, filed for the damage breakdown. Same crediting rule as
# BattleRecorder.on_hit's dealt_hp, so a hero's breakdown sums to its Damage.
func on_dealt(victim, attacker, hp_lost: int, is_magic: bool, true_damage: bool) -> void:
	if not _open or hp_lost <= 0 or not (is_instance_valid(victim) and victim is UnitBase):
		return
	var hero = _credit_hero(attacker)
	if hero == null or victim.is_player_unit == hero.is_player_unit:
		return
	var src := SRC_OTHER
	if attacker != hero:
		src = SRC_SUMMON
	elif in_dot:
		src = SRC_DOT
	elif attacker.gear_basic_hit:
		src = SRC_AUTO
	elif int(attacker.recap_action) == 1:
		src = SRC_SKILL
	elif int(attacker.recap_action) == 2:
		src = SRC_ULT
	elif _ambient_action > 0 and int(hero.unit_class) == _ambient_cls:
		src = SRC_SKILL if _ambient_action == 1 else SRC_ULT
	elif in_passive:
		src = SRC_PASSIVE
	var typ := TYPE_TRUE if true_damage else (TYPE_MAGIC if is_magic else TYPE_PHYS)
	_hero(hero)
	var id: int = hero.get_instance_id()
	var row: Array = _split.get(id, [])
	if row.is_empty():
		row.resize(SOURCES * TYPES)
		row.fill(0)
	row[src * TYPES + typ] = int(row[src * TYPES + typ]) + hp_lost
	_split[id] = row

# ── Defeats ───────────────────────────────────────────────────────────────────

static func enemy_type_key(u) -> String:
	if not is_instance_valid(u):
		return "?"
	if u.has_meta("sprite_folder"):
		return str(u.get_meta("sprite_folder"))
	return String(u.unit_name)

func on_enemy_defeat(u) -> void:
	if not _open or not (is_instance_valid(u) and u is UnitBase):
		return
	var key: String = enemy_type_key(u)
	if not _defeats.has(key) and _defeats.size() >= MAX_DEFEAT_TYPES:
		key = OTHER_KEY
	if not _defeats.has(key):
		_defeats[key] = {
			"key": key,
			"name": "Other enemies" if key == OTHER_KEY else String(u.unit_name),
			"portrait": "" if key == OTHER_KEY else BattleRecorder.portrait_path(u),
			"n": 0, "summoned": 0,
			"boss": bool(u.is_boss), "elite": bool(u.is_elite),
		}
	var d: Dictionary = _defeats[key]
	d["n"] = int(d["n"]) + 1
	_defeat_total += 1
	if u.is_summoned:
		d["summoned"] = int(d["summoned"]) + 1
		_summoned_total += 1
	if _order.size() < MAX_ORDER:
		_order.append(key)

# ── Snapshot ──────────────────────────────────────────────────────────────────

# Plain data, frozen at the final whistle. Further calls are ignored until the
# next begin(), so nothing can drift into a finished fight.
func snapshot() -> Dictionary:
	var heroes: Dictionary = {}
	for id in _protect.keys():
		var p: Array = _protect[id]
		var uid: int = int(_uids.get(id, 0))
		var u = instance_from_id(id)
		if uid == 0 and is_instance_valid(u):
			uid = int(u.get_meta("recap_uid", 0))
		heroes[id] = {"uid": uid, "protect_out": int(p[0]), "protect_self": int(p[1])}
	var defeats: Array = []
	for k in _defeats.keys():
		defeats.append((_defeats[k] as Dictionary).duplicate())
	defeats.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]) \
		or (int(a["n"]) == int(b["n"]) and String(a["key"]) < String(b["key"])))
	_open = false
	_ledger.clear()
	return {
		"token": token(),
		"heroes": heroes,
		"protect_unattributed": _unattributed,
		"defeats": defeats,
		"defeat_total": _defeat_total,
		"summoned_total": _summoned_total,
		"headliners": _headliners.duplicate(true),
		"order": _order.duplicate(),
		"split": _split.duplicate(true),
	}
