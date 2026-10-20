extends RefCounted
class_name MirrorWardenKit

const TILE_LIFE := 9.0
const ECHO_SHARE := 0.30
const ECHO_CAP := 0.75
var tiles: Array[Dictionary] = []
var casts: Array[Dictionary] = []
var echoes: Array[Dictionary] = []

static func broken(u: UnitBase) -> bool:
	return bool(u.get_meta("warden_broken", false)) or u.current_hp <= u.max_hp / 2

static func reflect(u: UnitBase) -> float:
	return 0.0 if broken(u) else 0.15

static func echo_damage(source: UnitBase, owner: UnitBase) -> int:
	return maxi(1, int(minf(source.attack_damage * source.outgoing_damage_multiplier() * ECHO_SHARE, owner.attack_damage * ECHO_CAP)))

static func description(u: UnitBase) -> String:
	if u.has_meta("mirror_copy"):
		return "Rooted mirror copy. Echoes its linked hero's basic attacks only; no skills or ultimates. Displayed ATK is its current physical echo damage before defenses, using the linked hero element. Magic basics also produce this physical echo. Destroy it to silence this mirror. Expires with its tile."
	return "Mirrorplate: %s\nMirror Field: marks hero tiles for 9s; occupants create fragile rooted copies. Copies echo basic attacks at 30%% outgoing ATK, capped at 75%% Warden ATK (%d), with no skills or ultimates. Destroy copies or leave the mirrors.\nShatter: 1.1s warning, then marked mirrors and their straight shard lanes hit for %d physical damage; each hero is hit once.\nAt half HP armor permanently breaks: reflection stops, mirrors appear faster, and Rebound Charge warns a route before charging out and back for %d physical damage." % ["broken — reflection inactive" if broken(u) else "reflects 15% of received damage, capped at 0.5% attacker max HP; cannot kill", int(u.attack_damage * ECHO_CAP), int(u.attack_damage * 1.1), int(u.attack_damage * 1.2)]

static func reset(u: UnitBase) -> void:
	u.set_meta("warden_broken", false)
	u.set_meta("warden_busy", false)
	u.set_meta("warden_field_t", 2.0)
	u.set_meta("warden_shatter_t", 5.0)
	u.set_meta("warden_charge_t", 4.0)

func passive(m, u: UnitBase, opponents: Array, dt: float) -> void:
	if broken(u) and not u.get_meta("warden_broken", false):
		u.set_meta("warden_broken", true)
		u.set_meta("warden_charge_t",4.0)
		fx(m, u.footprint_at(u.grid_position), 0.8, false, true)
		m.action_logged.emit("Mirrorplate breaks — Rebound Charge unlocked!", false)
	for key in ["warden_field_t", "warden_shatter_t", "warden_charge_t"]:
		u.set_meta(key, float(u.get_meta(key, 2.0)) - dt)
	if u.stun_time > 0: return
	if u.get_meta("warden_busy",false): return
	if float(u.get_meta("warden_field_t")) <= 0:
		u.set_meta("warden_field_t", 4.5 if broken(u) else 7.5)
		var count := 0
		for hero in opponents:
			if not m._is_alive(hero) or hero.is_summoned: continue
			if tiles.any(func(t): return t.cell == hero.grid_position): continue
			var owned := tiles.filter(func(t): return t.owner == u).size()
			if owned >= (5 if broken(u) else 3): break
			var tile := {"owner":u,"cell":hero.grid_position,"life":TILE_LIFE,"copy":null,"source":null,"callback":Callable(),"used":false}
			tiles.append(tile)
			tile["effect"] = fx(m, [hero.grid_position], TILE_LIFE)
			count += 1
			if count >= (3 if broken(u) else 2): break
	if float(u.get_meta("warden_shatter_t")) <= 0:
		u.set_meta("warden_shatter_t", 5.0 if broken(u) else 8.0)
		var cells: Array = []
		for tile in tiles:
			if tile.owner != u: continue
			for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				for step in 4:
					var c: Vector2i = tile.cell + direction * step
					if m.battle_grid.is_valid_position(c) and not cells.has(c): cells.append(c)
		if not cells.is_empty():
			casts.append({"owner":u,"cells":cells,"time":1.1,"charge":false})
			fx(m,cells,1.1,true)
	if broken(u) and float(u.get_meta("warden_charge_t")) <= 0 and not opponents.is_empty():
		u.set_meta("warden_charge_t", 7.0)
		for hero in opponents:
			if not m._is_alive(hero): continue
			var dest: Vector2i = charge_destination(m,u,hero.grid_position)
			if dest == Vector2i(-1,-1): continue
			var cells: Array = []
			var start := u.grid_position
			var steps := maxi(absi(dest.x-start.x),absi(dest.y-start.y))
			for i in range(steps+1):
				var c := Vector2i(Vector2(start).lerp(Vector2(dest),float(i)/maxi(1,steps)).round())
				for occupied in u.footprint_at(c):
					if not cells.has(occupied): cells.append(occupied)
			u.set_meta("warden_busy",true)
			casts.append({"owner":u,"cells":cells,"time":0.9,"charge":true,"dest":dest,"origin":start})
			fx(m,cells,0.9,true)
			break

func tick(m, dt: float) -> void:
	for tile in tiles.duplicate():
		tile.life -= dt
		if not m._is_alive(tile.owner) or tile.life <= 0:
			remove_tile(m,tile)
			continue
		if not tile.used:
			var source = m.battle_grid.get_unit_at(tile.cell)
			if m._is_alive(source) and source.is_player_unit and not source.is_summoned: spawn_copy(m,tile,source)
		if m._is_alive(tile.copy) and m._is_alive(tile.source): tile.copy.attack_damage = echo_damage(tile.source,tile.owner)
	for echo in echoes.duplicate():
		echo.time -= dt
		if echo.time > 0: continue
		echoes.erase(echo)
		var tile: Dictionary = echo.tile
		if not tiles.has(tile) or not m._is_alive(tile.copy) or not m._is_alive(tile.source) or tile.copy.stun_time > 0: continue
		var target = m.find_nearest_enemy(tile.copy,m.player_units)
		if not m._is_alive(target): continue
		var copy: UnitBase = tile.copy
		copy.attack_damage = echo_damage(tile.source,tile.owner)
		copy.recap_action = 0
		if copy is VisualUnit: copy.play_attack(target.global_position-copy.global_position)
		hit(copy,target,copy.attack_damage)
	for cast in casts.duplicate():
		cast.time -= dt
		if cast.time > 0: continue
		casts.erase(cast)
		var u: UnitBase = cast.owner
		if not m._is_alive(u): continue
		if cast.get("return",false):
			move(m,u,cast.origin)
			u.set_meta("warden_busy",false)
			continue
		for hero in m.player_units:
			if not m._is_alive(hero): continue
			if hero.footprint_at(hero.grid_position).any(func(c): return cast.cells.has(c)):
				hit(u,hero,int(u.attack_damage*(1.2 if cast.charge else 1.1)*u.outgoing_damage_multiplier()))
		fx(m,cast.cells,0.6,false,true)
		if cast.charge:
			# Reserve the complete footprint before visual travel; rebound to a
			# legal origin so neither leg can strand occupied grid cells.
			move(m,u,cast.dest)
			u.set_meta("warden_busy",true)
			casts.append({"owner":u,"time":0.4,"return":true,"origin":cast.origin})
		else:
			for tile in tiles.duplicate():
				if tile.owner == u: remove_tile(m,tile)

func charge_destination(m, u: UnitBase, center: Vector2i) -> Vector2i:
	for radius in range(1,4):
		for x in range(-radius,radius+1):
			for y in range(-radius,radius+1):
				var dest := center + Vector2i(x,y)
				if u.footprint_at(dest).all(func(c): return m.battle_grid.is_valid_position(c) and (not m.battle_grid.is_cell_occupied(c) or m.battle_grid.get_unit_at(c)==u)): return dest
	return Vector2i(-1,-1)

func move(m, u: UnitBase, dest: Vector2i) -> void:
	var valid := u.footprint_at(dest).all(func(c): return m.battle_grid.is_valid_position(c) and (not m.battle_grid.is_cell_occupied(c) or m.battle_grid.get_unit_at(c)==u))
	if not valid: return
	var old := u.grid_position
	m.battle_grid.purge_unit(u)
	if not m.battle_grid.place_unit(u,dest): m.battle_grid.place_unit(u,old); return
	u.grid_position = dest
	var tween := u.create_tween()
	tween.tween_property(u,"position",m._world_pos_for(u,dest),0.3)

func spawn_copy(m, tile: Dictionary, source: UnitBase) -> void:
	if not UnitFactory.CLASS_BASE_STATS.has(source.unit_class): return
	var cell: Vector2i = m._nearest_open_adjacent(tile.owner.grid_position)
	if cell == Vector2i(-1,-1): return
	var copy := UnitFactory.create_unit(source.unit_class,source.current_element,false)
	copy.unit_name = "Mirror of " + source.unit_name
	copy.is_summoned = true
	copy.set_meta("mirror_copy",true)
	copy.set_meta("passive_name","Mirror Echo")
	copy.max_hp = maxi(1,int(tile.owner.max_hp*0.06)); copy.current_hp = copy.max_hp
	copy.attack_damage = echo_damage(source,tile.owner)
	copy.magic_power = 0; copy.resistance = 0; copy.magic_resist = 0
	copy.movement_speed = 0; copy.hp_regen = 0; copy.mana_regen = 0
	copy.gold_reward = 0; copy.crystal_reward = 0; copy.xp_reward = 0
	copy.skill_name = ""; copy.ultimate_name = ""; copy.ultimate_charge_max = 0
	if not m.battle_grid.place_unit(copy,cell): copy.free(); return
	copy.grid_position = cell
	m.enemy_units.append(copy)
	m.unit_summoned.emit(copy)
	if not copy.is_inside_tree(): tile.owner.get_parent().add_child(copy)
	copy.battle_manager = m
	copy.position = m._world_pos_for(copy,cell)
	copy.modulate = Color(0.5,0.85,1,0.65)
	tile.copy = copy; tile.source = source; tile.used = true
	var callback := func(_target): echoes.append({"tile":tile,"time":0.35})
	tile.callback = callback
	source.attacked.connect(callback)

func hit(u: UnitBase, target: UnitBase, amount: int) -> void:
	var before := target.current_hp
	u.recap_action = 0 if u.has_meta("mirror_copy") else 1
	target.take_damage(amount,u.current_element,u)
	u.damage_dealt += maxi(0,before-target.current_hp)

func remove_tile(m, tile: Dictionary) -> void:
	if is_instance_valid(tile.get("effect")): tile.effect.queue_free()
	if is_instance_valid(tile.source) and tile.callback.is_valid() and tile.source.attacked.is_connected(tile.callback): tile.source.attacked.disconnect(tile.callback)
	if is_instance_valid(tile.copy):
		m.battle_grid.purge_unit(tile.copy)
		m.enemy_units.erase(tile.copy)
		if tile.copy.current_hp > 0: tile.copy.current_hp = 0; tile.copy.die()
	tiles.erase(tile)

func clear(m = null) -> void:
	if m != null:
		for tile in tiles.duplicate(): remove_tile(m,tile)
	tiles.clear(); casts.clear(); echoes.clear()

func fx(m, cells: Array, life: float, warning := false, burst := false):
	if not is_instance_valid(m.skill_effect_container): return null
	var effect := WardenVFX.new()
	effect.grid = m.battle_grid; effect.manager = m; effect.cells = cells.duplicate()
	effect.life = life; effect.warning = warning; effect.burst = burst
	m.skill_effect_container.add_child(effect)
	return effect
