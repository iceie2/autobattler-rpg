extends Node

# Systemic audit: which enemies carry an ULTIMATE they never declared?
# UnitBase defaults ultimate_charge_max = 300. A mob that declares no
# ultimate_name still charges one from damage dealt/taken, shows an ultimate
# strip, and on full hits _use_ultimate's `_:` fallback -> _use_skill(), i.e. a
# free extra cast of its signature move that ignores its own cooldown.
# The arena probe cannot see this: it reports NO_KIT on an empty ultimate_name.
#
# Run: godot --headless --fixed-fps 30 res://scenes/tools/mob_ultimate_audit.tscn

func _ready() -> void:
	var codes: Array = EnemyFactory.CODE_TO_TYPE.values()
	codes.sort()
	var afflicted: Array = []
	var clean: Array = []
	var seen: Dictionary = {}
	for t in codes:
		if seen.has(t): continue
		seen[t] = true
		var u: VisualUnit = EnemyFactory.create_by_type(t)
		if not u: continue
		add_child(u)
		var has_ult_pool: bool = u.ultimate_charge_max > 0
		var declares: bool = u.ultimate_name != ""
		if has_ult_pool and not declares:
			afflicted.append("%-26s pool=%d  skill=%s" % [t, u.ultimate_charge_max, u.skill_name])
		elif has_ult_pool and declares:
			clean.append("%-26s DECLARES '%s'" % [t, u.ultimate_name])
		u.free()

	print("=== MOBS WITH AN UNDECLARED ULTIMATE (bug) : %d ===" % afflicted.size())
	for a in afflicted: print("  ", a)
	print("=== MOBS THAT LEGITIMATELY DECLARE ONE : %d ===" % clean.size())
	for c in clean: print("  ", c)
	get_tree().quit(0)
