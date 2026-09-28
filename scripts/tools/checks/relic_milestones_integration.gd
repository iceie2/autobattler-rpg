extends Node
# Integration writes are allowed ONLY in the explicitly selected disposable profile.
var failures: Array = []
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("VD20_INTEGRATION: " + label)

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/vd20-20260927/isolated-profile/"):
		push_error("Refusing integration test outside the VD-20 disposable profile")
		get_tree().quit(2)
		return
	Progression.relic_milestones = RelicMilestoneState.new()
	RunSave.resume_on_start = false
	var mg = load("res://scenes/main_game.tscn").instantiate()
	add_child(mg)
	await get_tree().process_frame
	mg._record_relic_milestones({"won": true, "elapsed": 5.0})
	check(Progression.relic_milestones.pending.has("opening_1"), "production hook awards")
	var disk = JSON.parse_string(FileAccess.get_file_as_string(Progression.SAVE_PATH))
	check(disk.relic_milestones.pending.has("opening_1"), "pending immediately on disk")
	check(not Progression.is_relic_unlocked("d_opening"), "active run remains locked")
	mg.game_state.battle_round = 1
	mg.save_run()
	var checkpoint := RunSave.read_data()
	check(checkpoint.has("relic_milestone_pool") and not checkpoint.relic_milestone_pool.has("opening_1"), "checkpoint saves frozen pool")
	Progression.load_data()
	check(Progression.relic_milestones.pending.has("opening_1"), "production reload restores pending")
	mg._on_battle_ended(false)
	await get_tree().process_frame
	var screen: RelicMilestoneScreen
	for child in mg.get_children():
		if child is RelicMilestoneScreen: screen = child
	check(screen != null, "defeat opens new collection screen")
	if screen:
		screen._button.pressed.emit()
	await get_tree().process_frame
	check(mg._game_over_screen.visible, "collection continues to existing game-over screen")
	check(Progression.relic_milestones.pending.is_empty(), "collection clears pending")
	check(not Progression.is_relic_unlocked("d_opening"), "collection leaves previous pool frozen")
	disk = JSON.parse_string(FileAccess.get_file_as_string(Progression.SAVE_PATH))
	check(disk.relic_milestones.unlocked.has("opening_1"), "atomic replacement persists collected state")
	mg.start_new_game()
	check(Progression.is_relic_unlocked("d_opening"), "next production run includes earned family")
	mg._game_over_screen.visible = false
	mg.game_state.battle_round = 100
	mg._on_battle_ended(true)
	await get_tree().process_frame
	screen = null
	for child in mg.get_children():
		if child is RelicMilestoneScreen: screen = child
	check(screen != null, "victory opens collection even without new awards")
	if screen: screen._button.pressed.emit()
	await get_tree().process_frame
	check(mg._game_over_screen.visible, "victory continues after collection")
	# Resume uses the checkpoint, not newly collected account state.
	RunSave.write_data(checkpoint)
	mg._resume_run()
	check(not Progression.is_relic_unlocked("d_opening"), "production resume restores old pool")
	mg.queue_free()
	await get_tree().process_frame
	# An abandoned/crashed run's pending awards are presented before a new run.
	Progression.relic_milestones.pending["execute_2"] = true
	var recovered = load("res://scenes/main_game.tscn").instantiate()
	add_child(recovered)
	await get_tree().process_frame
	screen = null
	for child in recovered.get_children():
		if child is RelicMilestoneScreen: screen = child
	check(screen != null, "fresh run recovers uncollected awards")
	if screen: screen._button.pressed.emit()
	await get_tree().process_frame
	check(Progression.is_relic_unlocked("s_execute"), "recovery collects before new run snapshot")
	recovered.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(4.1).timeout
	print("VD20_INTEGRATION: " + ("ALL PASS" if failures.is_empty() else "FAILED"))
	get_tree().quit(0 if failures.is_empty() else 1)
