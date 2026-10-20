extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Elite VFX captures (ENEMY_FEEL_AUDIT.md elite/boss list). Runs WINDOWED.
# Run: godot --path . res://scenes/tools/elite_vfx_capture.tscn [-- --round=N]
# Default round 55 = the Tempest Conduit's lightning board.
const ZOOM := 1.6

# Run everything:   godot --path . res://scenes/tools/elite_vfx_capture.tscn
# Run just one:     ... -- --only=tc_plates      (names below; comma-separate for several)
# Each entry is [name, biome round, method] — biomes are per-scene, so a filtered
# run renders ONLY the scenes asked for instead of the whole roster.
const SCENES := [
	["tempest", 55, "_tempest_chain"], ["mirror", 85, "_mirror"], ["magma", 45, "_magma"],
	["gale", 15, "_gale"], ["flock", 15, "_flock"], ["tide", 25, "_tide"],
	["terracotta", 35, "_terracotta"], ["tc_moves", 35, "_tc_moves"], ["tc_plates", 35, "_tc_plates"],
	["aspect", 95, "_aspect"], ["steal", 25, "_steal"], ["anthill", 5, "_anthill"],
]

func _ready() -> void:
	get_window().size = Vector2i(1280, 640)
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.split("=")[1].split(",")
	var bg := BackgroundLayer.new()
	add_child(bg)
	CapturePaths.cli_round(55)
	scale = Vector2(ZOOM, ZOOM)
	for sc in SCENES:
		if not only.is_empty() and not (sc[0] in only):
			continue
		bg.set_biome_from_round(sc[1])
		await call(sc[2])
	print("ELITE_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, code: String):
	var u = EnemyFactory.create_by_type(code)
	u.position = pos; add_child(u)
	u.z_index = 2   # real battles give units z 2+row (_update_depth); no manager here
	return u

func _clear() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

# Conduit top-left, four "heroes" in a loose line — two frames: the serpent
# racing out mid-chain, then every link lit.
func _tempest_chain() -> void:
	for when in [0.10, 0.26]:
		_clear()
		var c = _u(Vector2(110, 110), "tempest_conduit")
		var vs: Array = []
		for p in [Vector2(260, 230), Vector2(380, 250), Vector2(500, 215), Vector2(620, 250)]:
			vs.append(_u(p, "goblin"))
		await get_tree().process_frame
		var pts: Array = [c.global_position]
		for v in vs: pts.append(v.global_position)
		var fx := TempestVFX.new(); add_child(fx)
		fx.setup_chain(pts)
		fx._t = when; fx.set_process(false); fx.queue_redraw()
		await _save("_tempest_chain_%d.png" % int(when * 100))

func _frozen(fx: Node2D, t: float) -> void:
	fx._t = t; fx.set_process(false); fx.queue_redraw()

# Warden centre, three attackers: left = idle sheen, then a glint + shards
# mid-flight to two attackers.
func _mirror() -> void:
	_clear()
	var w = _u(Vector2(330, 170), "mirrorplate_warden")
	var a1 = _u(Vector2(140, 290), "goblin")
	var a2 = _u(Vector2(560, 280), "goblin")
	await get_tree().process_frame
	var sheen := MirrorVFX.new(); add_child(sheen)
	sheen.setup_on(MirrorVFX.Mode.SHEEN, w, INF); sheen.host = null
	_frozen(sheen, 0.45)
	var g := MirrorVFX.new(); add_child(g)
	g.setup_on(MirrorVFX.Mode.GLINT, w, 0.28); g.host = null
	_frozen(g, 0.06)
	for a in [a1, a2]:
		var s := MirrorVFX.new(); add_child(s)
		s.setup_shard(w, a)
		_frozen(s, 0.09)
	await _save("_mirrorplate_reflect.png")

# Left: heart in its final second (white-hot, contracting rings, 3 pips lit).
# Right: the eruption, globs mid-arc toward four heroes.
func _magma() -> void:
	_clear()
	var m1 = _u(Vector2(180, 170), "magma_heart")
	var m2 = _u(Vector2(520, 150), "magma_heart")
	var hs: Array = []
	for p in [Vector2(420, 300), Vector2(520, 320), Vector2(620, 300), Vector2(700, 250)]:
		hs.append(_u(p, "goblin"))
	await get_tree().process_frame
	var h := MagmaVFX.new(); add_child(h)
	h.setup_heart(m1); h.host = null
	h.set_state(0.95, 3)
	_frozen(h, 0.3)
	var pts: Array = []
	for u in hs: pts.append(u.global_position)
	var e := MagmaVFX.new(); add_child(e)
	e.setup_erupt(m2, pts)
	_frozen(e, 0.25)
	await _save("_magma_heart.png")

# Left pair: the gust mid-flight into its target. Right pair: a victim just
# shoved one tile right — body mid-slide, wind trail along the path.
func _gale() -> void:
	_clear()
	var w1 = _u(Vector2(120, 200), "gale_warden")
	var t1 = _u(Vector2(300, 220), "goblin")
	var w2 = _u(Vector2(430, 200), "gale_warden")
	var t2 = _u(Vector2(680, 220), "goblin")
	await get_tree().process_frame
	var g := GaleVFX.new(); add_child(g)
	g.setup(GaleVFX.Mode.GUST, w1.global_position, t1.global_position)
	_frozen(g, 0.16)
	var from_world: Vector2 = t2.global_position + Vector2(-110, 0) * ZOOM
	t2._shove_offset = t2.to_local(from_world) * 0.35   # ~65% through the slide
	var tr := GaleVFX.new(); add_child(tr)
	tr.setup(GaleVFX.Mode.SLIDE, from_world, t2.global_position)
	_frozen(tr, 0.14)
	await _save("_gale_warden_shove.png")

# Tidecaller with three allies: ripple mid-roll, droplets on the two wounded
# allies, and a Tidal Ward stream closing into its dome on the right one.
func _tide() -> void:
	_clear()
	var tc = _u(Vector2(200, 200), "tidecaller")
	var a1 = _u(Vector2(360, 170), "orc_water")
	var a2 = _u(Vector2(330, 300), "slime_water")
	var a3 = _u(Vector2(560, 230), "bear_water")
	await get_tree().process_frame
	var font := TideVFX.new(); add_child(font)
	font.setup_font(tc, 4.0 * 110.0 / ZOOM * 0.5)
	font.host = null
	font.set_recipients([a1.global_position, a2.global_position])
	_frozen(font, 1.0)
	var w := TideVFX.new(); add_child(w)
	w.setup_ward(tc, a3); w._target = null
	_frozen(w, 0.5)
	await _save("_tidecaller.png")

# Left: 40% fortified with the newest slab still landing (dust). Right: full wall.
func _terracotta() -> void:
	_clear()
	var c1 = _u(Vector2(200, 190), "terracotta_colossus")
	var c2 = _u(Vector2(540, 190), "terracotta_colossus")
	await get_tree().process_frame
	var a := TerracottaVFX.new(); add_child(a)
	a.setup_on(c1); a.host = null
	a._t = 1.0; a.set_armor_frac(0.3); a._t = 1.5; a.set_armor_frac(0.4); a._t = 1.62
	a.set_process(false); a.queue_redraw()
	var b := TerracottaVFX.new(); add_child(b)
	b.setup_on(c2); b.host = null
	b.set_armor_frac(1.0); b._t = 3.0
	b.set_process(false); b.queue_redraw()
	await _save("_terracotta_wall.png")

# Three Devourers: Fire mid-cycle, Water about to swap, and a swap burst into Lightning.
func _aspect() -> void:
	_clear()
	var us: Array = []
	for p in [Vector2(150, 200), Vector2(390, 200), Vector2(630, 200)]:
		us.append(_u(p, "aspect_devourer"))
	await get_tree().process_frame
	var specs := [[UnitBase.Element.FIRE, 0.4], [UnitBase.Element.WATER, 0.92]]
	for i in 2:
		var a := AspectVFX.new(); add_child(a)
		a.setup_aura(us[i]); a.host = null
		a.set_state(specs[i][0], specs[i][1])
		_frozen(a, 0.5)
	var sw := AspectVFX.new(); add_child(sw)
	sw.setup_swap(us[2], UnitBase.Element.WATER, UnitBase.Element.LIGHTNING)
	_frozen(sw, 0.42)
	await _save("_aspect_devourer.png")

# Stealer mid-drain on one goblin (sand stream + "ATK" label), holding two
# stolen stats (orbiting runes), and a second Stealer mid Siphon Ward.
func _steal() -> void:
	_clear()
	var s1 = _u(Vector2(200, 180), "stat_stealer")
	var v = _u(Vector2(420, 280), "goblin")
	var s2 = _u(Vector2(620, 180), "stat_stealer")
	await get_tree().process_frame
	var sip := StealVFX.new(); add_child(sip)
	sip.setup(StealVFX.Mode.SIPHON, v, s1, "attack_damage"); sip.host = null
	_frozen(sip, 0.4)
	var held := StealVFX.new(); add_child(held)
	held.setup(StealVFX.Mode.HELD, s1); held.host = null; held.held = 2
	_frozen(held, 0.6)
	var w := StealVFX.new(); add_child(w)
	w.setup(StealVFX.Mode.WARD, s2); w.host = null
	_frozen(w, 0.2)
	await _save("_stat_stealer.png")

# Hill at 23 swarm-rage, and an ant bursting out of the ground beside it.
func _anthill() -> void:
	_clear()
	var h = _u(Vector2(260, 190), "ant_hill")
	await get_tree().process_frame
	var rg := AnthillVFX.new(); add_child(rg)
	rg.setup_rage(h); rg.host = null; rg.stacks = 23
	_frozen(rg, 0.3)
	var b := AnthillVFX.new(); add_child(b)
	b.setup_burrow(h.global_position + Vector2(260, 60) * ZOOM)
	_frozen(b, 0.15)
	await _save("_ant_hill.png")

# The flock (2026-09-28): six birds spread over six heroes, two of them mid
# Scatter (feathers) because a flockmate just fell.
func _flock() -> void:
	_clear()
	var birds: Array = []
	for i in 6:
		birds.append(_u(Vector2(90 + i * 115, 150 + (i % 2) * 40), "gale_warden"))
	for i in 6:
		_u(Vector2(90 + i * 115, 320), "goblin")
	await get_tree().process_frame
	for i in [1, 4]:
		var sc := GaleVFX.new(); add_child(sc)
		sc.setup_scatter(birds[i]); sc._host = null
		_frozen(sc, 0.5)
	await _save("_gale_flock.png")

# Colossus moves (2026-09-30). Frame A: windup (left), slam impact on a goblin at
# full hardening (middle), hardened sparks + wet erosion hits (right). Frame B:
# soft-clay chip hit, the milestone clang, and the death rubble.
func _tc_moves() -> void:
	_clear()
	var cs: Array = []
	for x in [150, 420, 690]:
		cs.append(_u(Vector2(x, 160), "terracotta_colossus"))
	var gob = _u(Vector2(450, 330), "goblin")
	await get_tree().process_frame
	var w := TerracottaStrikeVFX.new(); add_child(w)
	w.setup_windup(cs[0], 0.5, 0.6); w.host = null; _frozen(w, 0.38)
	# Middle: the boulder mid-flight at full hardening; right-hand goblin: a landing.
	var bo := TerracottaStrikeVFX.new(); add_child(bo)
	bo.setup_boulder(cs[1], gob, 0.7, 1.0); _frozen(bo, 0.40)
	var gob2 = _u(Vector2(690, 330), "goblin")
	await get_tree().process_frame
	var im := TerracottaStrikeVFX.new(); add_child(im)
	im.setup_impact(cs[2], gob2.global_position, 1.0, false); _frozen(im, 0.22)
	var h1 := TerracottaStrikeVFX.new(); add_child(h1)
	h1.setup_hit(cs[2], 0.9, false); h1.host = null; _frozen(h1, 0.10)
	var h2 := TerracottaStrikeVFX.new(); add_child(h2)
	h2.setup_hit(cs[2], 0.9, true); h2.host = null; _frozen(h2, 0.16)
	await _save("_tc_moves_a.png")
	_clear()
	var d: Array = []
	for x in [150, 420, 690]:
		d.append(_u(Vector2(x, 160), "terracotta_colossus"))
	await get_tree().process_frame
	var h3 := TerracottaStrikeVFX.new(); add_child(h3)
	h3.setup_hit(d[0], 0.15, false); h3.host = null; _frozen(h3, 0.10)
	var wall := TerracottaVFX.new(); add_child(wall)
	wall.setup_on(d[1]); wall.host = null
	wall.set_armor_frac(0.7); wall._t = 2.0; wall.set_armor_frac(0.76); wall._flash = 0.7; wall._t = 3.0
	wall.set_process(false); wall.queue_redraw()
	var ru := TerracottaStrikeVFX.new(); add_child(ru)
	ru.setup_rubble(d[2]); _frozen(ru, 0.55)
	await _save("_tc_moves_b.png")

# Orbiting plates at three hardening levels: 30% (4 plates), 70% (11), 100% (16).
func _tc_plates() -> void:
	_clear()
	var cs: Array = []
	for x in [170, 480, 790]:
		cs.append(_u(Vector2(x, 160), "terracotta_colossus"))
	await get_tree().process_frame
	var fracs := [0.3, 0.7, 1.0]
	for i in 3:
		var w := TerracottaVFX.new(); add_child(w)
		w.setup_on(cs[i]); w.host = null
		w._t = 0.0; w.set_armor_frac(fracs[i])
		w._t = 2.3 + float(i) * 0.4; w._flash = 0.0
		w.set_process(false); w.queue_redraw()
	await _save("_tc_plates.png")
