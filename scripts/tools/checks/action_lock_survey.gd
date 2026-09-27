extends Node
# Survey of the action lane: how long attack / skill / ultimate LOCK each unit
# (VisualUnit.combat_action_duration = max(authored clip, fallback)) against its
# attack interval and skill cooldown. A lock longer than the attack interval
# means the animation, not the stats, sets that unit's damage rate.
# Run: godot --headless res://scenes/tools/action_lock_survey.tscn
func _ready() -> void:
	var mgr := AutoBattleManager.new()
	add_child(mgr)
	var rows: Array = []
	for cname in UnitBase.UnitClass.keys():
		var cls: int = UnitBase.UnitClass[cname]
		var u: VisualUnit = UnitFactory.create_unit(cls, UnitBase.Element.NORMAL, true)
		if u == null:
			continue
		add_child(u)
		await get_tree().process_frame
		var interval := 1.0 / maxf(u.attacks_per_second, 0.01)
		# raw clip -> capped lock actually applied by the lane (VD-15 caps)
		rows.append("%-12s interval=%.2f  atk %.2f->%.2f  skill %.2f->%.2f (cd %d)  ult %.2f->%.2f  %s" % [
			cname, interval,
			u.combat_action_duration("attack"), mgr._combat_action_duration(u, "attack", 0.30),
			u.combat_action_duration("skill"), mgr._combat_action_duration(u, "skill", 0.45), u.skill_cooldown_max,
			u.combat_action_duration("ultimate"), mgr._combat_action_duration(u, "ultimate", 0.70),
			u.skill_name])
		u.queue_free()
	for r in rows:
		print("LOCK ", r)
	get_tree().quit()
