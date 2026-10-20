extends Node
# ══════════════════════════════════════════════════════════════════════════════
# DOC REVIVE TEST — regression for "heroes vanish off the roster for good"
# (2026-09-19 tester report: units permanently lost, "they moved toward the
# center and unclickable", seemingly at random).
#
# Mechanism: there are TWO player rosters — main_game.player_units (the run's
# real team) and AutoBattleManager.player_units (rebuilt from the grid every
# fight by collect_units). A hero that dies is erased from BOTH and parked in
# main_game._downed_heroes. Doc's Field Surgery then revives it mid-fight and
# puts it back in the MANAGER's roster only; main_game is never told, and there
# was no signal for it. At round start _revive_downed_heroes saw current_hp > 0,
# `continue`d past the player_units.append(), and then cleared _downed_heroes —
# so the hero ended up in NEITHER array while its node was still alive on the
# board. From there:
#   • reset_player_positions iterates player_units → never snapped home, so it
#     stands wherever Doc revived it: mid-board ("moved toward the center")
#   • enable_unit_dragging iterates player_units → can_be_dragged stays false
#     from battle start ("unclickable")
#   • save_run writes player_units + bench_units + _downed_heroes → the hero is
#     not in the save at all, so a quit/resume loses it for good
#   • _clear_middle_row queue_free()s any grid stray in neither list → the node
#     is destroyed outright
# Doc also wrote home_position to the cell it revived into, chosen by
# _nearest_open_adjacent with NO team-zone constraint — permanently relocating
# a hero to the divider row or the enemy half.
#
#   godot --headless --fixed-fps 30 res://scenes/doc_revive_test.tscn
# Exit code 0 = pass, 1 = fail.
#
# SAFETY: this drives the real main_game, which writes user://run_save.json.
# The player's actual mid-run save is backed up on entry and restored on exit.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []
var _save_backup: String = ""
var _save_existed: bool = false

func _ready() -> void:
	_backup_run_save()

	var mg := (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for _i in range(30):
		await get_tree().process_frame

	# Doc + a victim, both fielded. The level-1 field cap can be 1.
	mg.max_player_units = maxi(mg.max_player_units, 3)
	mg._recruit_hero(UnitBase.UnitClass.DOC,
			UnitFactory.element_for_class(UnitBase.UnitClass.DOC), {})
	mg._recruit_hero(UnitBase.UnitClass.BOUNCER,
			UnitFactory.element_for_class(UnitBase.UnitClass.BOUNCER), {})
	await get_tree().process_frame

	var zone_y: int = mg.battle_grid.grid_height - 4   # first row of the player zone

	var doc = null
	var victim = null
	for u in mg.player_units:
		if u and is_instance_valid(u):
			if u.unit_class == UnitBase.UnitClass.DOC:
				doc = u
			else:
				victim = u
	if doc == null or victim == null:
		print("DOC_REVIVE_TEST: FAILED -> could not field a Doc + a victim")
		_restore_run_save()
		get_tree().quit(1)
		return

	var home_before: Vector2i = victim.home_position
	var victim_name: String = victim.unit_name

	# ── The fight: ABM builds its own roster off the grid, the victim falls ──
	mg.auto_battle_manager.collect_units()
	victim.current_hp = 0
	victim.die()                       # emits died → main_game._on_unit_died parks it
	await get_tree().process_frame

	_check(victim in mg._downed_heroes, "victim parked in _downed_heroes")
	_check(not (victim in mg.player_units), "victim erased from player_units on death")

	# ── Box the Doc in the way a real fight does ────────────────────────────
	# _nearest_open_adjacent scans (1,0),(-1,0),(0,1),(0,-1),… so a Doc holding
	# the front player row with its flanks and its back covered has the DIVIDER
	# as its first free neighbour. That is the everyday case, not a corner one:
	# a support standing behind the frontline is boxed in by its own team.
	var doc_cell := Vector2i(4, zone_y)            # front row of the player zone
	mg.battle_grid.purge_unit(doc)
	if not mg.battle_grid.place_unit(doc, doc_cell):
		print("DOC_REVIVE_TEST: FAILED -> could not stage the Doc at %s" % doc_cell)
		_restore_run_save()
		get_tree().quit(1)
		return
	doc.grid_position = doc_cell
	var blockers: Array = []
	for b in [Vector2i(5, zone_y), Vector2i(3, zone_y), Vector2i(4, zone_y + 1)]:
		var filler: VisualUnit = EnemyFactory.create_by_type("orc_earth")
		mg.battle_grid_node.add_child(filler)
		filler.grid_position = b
		mg.battle_grid.place_unit(filler, b)
		blockers.append(filler)

	# ── Doc's Field Surgery, through the real ultimate ──────────────────────
	mg.auto_battle_manager.fallen_allies = [victim]
	doc.revive_used = false
	mg.auto_battle_manager._doc_field_surgery(doc, mg.auto_battle_manager.player_units)
	# The v002 heartbeat effect deliberately lands after the cast begins. A
	# committed Surgery must hold battle cleanup open until that delayed revive
	# resolves; otherwise end_battle() clears _doc_pending and eats the ultimate.
	mg.auto_battle_manager.battle_active = true
	mg.auto_battle_manager.enemy_units.clear()
	mg.auto_battle_manager.check_battle_end()
	_check(mg.auto_battle_manager.battle_active,
			"committed Field Surgery prevents battle-end cleanup")
	mg.auto_battle_manager._tick_doc_pending(
			mg.auto_battle_manager.DOC_SURGERY_IMPACT +
			mg.auto_battle_manager.DOC_SURGERY_TRAVEL + 0.01)
	mg.auto_battle_manager.battle_active = false
	await get_tree().process_frame

	if victim.current_hp <= 0:
		print("DOC_REVIVE_TEST: FAILED -> Field Surgery did not revive (no repro)")
		_restore_run_save()
		get_tree().quit(1)
		return
	_check(victim.is_player_unit, "revived hero is still on the player side")
	_check(victim.grid_position.y >= zone_y,
			"Field Surgery revived into the PLAYER zone, not the divider/enemy half (at %s)"
				% victim.grid_position)
	_check(victim.home_position.y >= zone_y,
			"home_position stayed inside the player zone (was %s, now %s)"
				% [home_before, victim.home_position])

	# ── A save taken in the between-rounds window (shop/events all call it) ──
	# save_run() no-ops while battle_round < 1, and with MAP_MODE a run now opens
	# on the map at round 0 — so without this the read below just returns whatever
	# stale file the last test left on disk and the check passes on someone else's
	# heroes. The bug under test is about saves taken mid-run, which are round >= 1
	# by definition.
	mg.game_state.battle_round = maxi(1, mg.game_state.battle_round)
	mg.save_run()
	var saved: Dictionary = RunSave.read_data()
	var saved_names: Array = []
	for h in saved.get("heroes", []):
		saved_names.append(str(h.get("name", "")))
	_check(victim_name in saved_names,
			"Doc-revived hero is in the run save (saved: %s)" % str(saved_names))

	# Blockers were staging only — clear the board before the round rolls over.
	for b in blockers:
		if is_instance_valid(b):
			mg.battle_grid.purge_unit(b)
			b.queue_free()
	await get_tree().process_frame

	# ── Round end → next round's ceremony ───────────────────────────────────
	mg._snapshot_between_round_bonuses()
	mg.reset_player_positions()
	await mg._play_round_start_ceremony()

	_check(is_instance_valid(victim), "victim node survived the round transition")
	if not is_instance_valid(victim):
		_finish()
		return

	_check(victim in mg.player_units, "Doc-revived hero rejoined player_units")
	_check(mg._downed_heroes.is_empty(), "downed list drained")
	_check(victim.visible, "revived hero is visible")
	_check(victim.current_hp > 0, "revived hero is alive (%d HP)" % victim.current_hp)

	# Draggable once prep opens — this is the "unclickable" symptom.
	mg.enable_unit_dragging(true)
	_check(victim.can_be_dragged, "revived hero is draggable in prep")

	# Back in formation, not stranded mid-board — the "moved toward the center".
	_check(victim.grid_position.y >= zone_y,
			"revived hero stands in the player zone (at %s)" % victim.grid_position)
	_check(victim.grid_position == victim.home_position,
			"revived hero is on its home cell (%s vs home %s)"
				% [victim.grid_position, victim.home_position])
	_check(mg.battle_grid.get_unit_at(victim.grid_position) == victim,
			"revived hero is registered on the grid cell it stands on")

	# ── The wave-spawn middle-row sweep must never delete a hero ────────────
	# Force the worst case: park the hero on the divider and sweep.
	mg.battle_grid.purge_unit(victim)
	var mid := Vector2i(victim.grid_position.x, mg.battle_grid.grid_height / 2)
	victim.grid_position = mid
	mg.battle_grid.place_unit(victim, mid)
	mg._clear_middle_row()
	await get_tree().process_frame
	_check(is_instance_valid(victim),
			"_clear_middle_row relocated the hero instead of freeing it")
	if is_instance_valid(victim):
		_check(victim.grid_position.y >= zone_y,
				"swept hero was put back in the player zone (at %s)" % victim.grid_position)

	_finish()

func _finish() -> void:
	_restore_run_save()
	if _fails.is_empty():
		print("DOC_REVIVE_TEST: ALL PASS")
		get_tree().quit(0)
	else:
		print("DOC_REVIVE_TEST: FAILED -> %d check(s)" % _fails.size())
		for f in _fails:
			print("    %s" % f)
		get_tree().quit(1)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  — %s" % label)
	else:
		_fails.append(label)
		print("  FAIL — %s" % label)

# ── Keep the player's real mid-run save out of the blast radius ─────────────
func _backup_run_save() -> void:
	_save_existed = FileAccess.file_exists(RunSave.PATH)
	if _save_existed:
		var f := FileAccess.open(RunSave.PATH, FileAccess.READ)
		if f:
			_save_backup = f.get_as_text()
	# Start from NO save. Other smoke tests write their own heroes here, and a
	# leftover file made the save assertion below pass on somebody else's roster
	# — an order-dependent false pass rather than a real check.
	RunSave.clear()

func _restore_run_save() -> void:
	if _save_existed:
		var f := FileAccess.open(RunSave.PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
	else:
		RunSave.clear()
