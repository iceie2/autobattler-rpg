extends Node
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _ready() -> void:
	var original: bool = Balance.BOSS_ELITE_STUN_IMMUNITY_TEST
	var mgr := AutoBattleManager.new(); add_child(mgr)
	Balance.BOSS_ELITE_STUN_IMMUNITY_TEST = true
	var bosses := 0
	var elites := 0
	var normals := 0
	var seen: Array = []
	for type in EnemyFactory.CODE_TO_TYPE.values():
		if type in seen: continue
		seen.append(type)
		var u: VisualUnit = EnemyFactory.create_by_type(type)
		if not u: continue
		var tenacity: int = u.tenacity
		mgr.apply_stun(u,2.0)
		if u.is_boss or u.is_elite:
			if u.is_boss: bosses += 1
			else: elites += 1
			check(u.is_stun_immune() and u.stun_time == 0,"Boss/elite accepted stun: "+str(type))
		else:
			normals += 1
			check(not u.is_stun_immune() and is_equal_approx(u.stun_time,u.tenacity_scaled(2.0)),"Normal unit lost tenacity-scaled stun: "+str(type))
		mgr.apply_root(u,2.0)
		check(is_equal_approx(u.root_time,u.tenacity_scaled(2.0)),"Root no longer uses tenacity: "+str(type))
		mgr.apply_taunt(u,null,2.0)
		check(is_equal_approx(u.taunt_time,u.tenacity_scaled(2.0)),"Taunt no longer uses tenacity: "+str(type))
		mgr.apply_slow(u,0.3,2.0)
		check(is_equal_approx(u.slow_time,u.tenacity_scaled(2.0)),"Slow no longer uses tenacity: "+str(type))
		check(u.tenacity == tenacity,"Test changed tenacity stat: "+str(type))
		u.stun_time = 0
		Balance.BOSS_ELITE_STUN_IMMUNITY_TEST = false
		mgr.apply_stun(u,2.0)
		check(not u.is_stun_immune() and is_equal_approx(u.stun_time,u.tenacity_scaled(2.0)),"Toggle-off did not restore scaled stun: "+str(type))
		Balance.BOSS_ELITE_STUN_IMMUNITY_TEST = true
		u.free()
	check(bosses > 0 and elites > 0 and normals > 0,"Probe must cover every enemy tier")
	# Incoming stun cannot interrupt a boss channel while this test is enabled.
	var titan := EnemyFactory.create_cloven_titan(); add_child(titan)
	var fired := [false]
	mgr.start_channel(titan,"immunity probe",0.5,func(): fired[0] = true)
	mgr.apply_stun(titan,2.0)
	mgr._tick_channel(titan,0.6)
	check(fired[0],"Immune boss channel was interrupted")
	# Authored holds still work and are not erased by a rejected incoming stun.
	titan.stun_time = 1.25
	mgr.apply_stun(titan,3.0)
	check(is_equal_approx(titan.stun_time,1.25),"Incoming gate erased an authored action hold")
	Balance.BOSS_ELITE_STUN_IMMUNITY_TEST = original
	for failure in failures: print("FAIL: ",failure)
	print("BOSS_STUN_IMMUNITY: ALL PASS (%d bosses, %d elites, %d normal types)" % [bosses,elites,normals] if failures.is_empty() else "BOSS_STUN_IMMUNITY: FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)
