extends Node2D
class_name HydraVFX

# Six different silhouettes and motion patterns, not a recolored shared burst.
var manager = null
var cast: Dictionary
var warning := true
var duration := 1.0
var elapsed := 0.0
var element := 0
var cell := 110.0
var color := Color.WHITE
var title: Label

func setup(m, c: Dictionary, tell: bool, life: float) -> void:
	manager = m; cast = c; warning = tell; duration = life
	element = int(c.element); cell = m.battle_grid.cell_size
	color = SynergyData.element_color(element)
	global_position = c.origin
	z_index = 30 if not tell and element in [UnitBase.Element.EARTH, UnitBase.Element.LIGHTNING] else (8 if not tell else 1)
	title = Label.new()
	title.text = HydraKit.MOVE_NAMES[element] if tell else ""
	UITheme.apply_read_font(title, UITheme.FONT_BODY)
	title.add_theme_color_override("font_color", color.lightened(0.3))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 3)
	title.position = Vector2(-70, -95)
	add_child(title)
	queue_redraw()

func _process(dt: float) -> void:
	if is_instance_valid(manager):
		if manager.paused: return
		dt *= manager.time_scale
	elapsed += dt
	if elapsed >= duration: queue_free(); return
	queue_redraw()

func point(world: Vector2) -> Vector2:
	return world - global_position

func target_point() -> Vector2:
	var target = cast.get("target")
	return point(target.global_position) if is_instance_valid(target) else Vector2.ZERO

func strip() -> PackedVector2Array:
	var direction: Vector2 = cast.direction
	var side := direction.orthogonal() * cell * (0.7 + 0.2 * (int(cast.heads) - 1))
	return PackedVector2Array([-side, direction * cell * 5 - side, direction * cell * 5 + side, side, -side])

func cone() -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	for i in 25:
		points.append(Vector2.from_angle((cast.direction as Vector2).angle() + deg_to_rad(-35 + 70.0 * i / 24)) * cell * (4.0 + 0.5 * (int(cast.heads) - 1)))
	points.append(Vector2.ZERO)
	return points

func _draw() -> void:
	var k := clampf(elapsed / duration, 0, 1)
	var fade := 1.0 if warning else 1.0 - k * 0.7
	var ink := Color(color, fade)
	match element:
		UnitBase.Element.NORMAL:
			var p := target_point()
			var gap := 48.0 * (1.0 - k) if not warning else 48.0 + sin(k * PI) * 15.0
			if warning:
				draw_arc(p, 52, 0, TAU, 36, Color(1, 0.8, 0.45), 3)
			# Opposed jaws converge, with individual triangular teeth.
			for side in [-1, 1]:
				var y: float = p.y + gap * side
				draw_line(Vector2(p.x - 42, y), Vector2(p.x + 42, y), Color(0.65, 0.43, 0.25, fade), 9)
				for tooth in 6:
					var x := p.x - 38 + tooth * 14.0
					draw_colored_polygon(PackedVector2Array([Vector2(x-5, y), Vector2(x+5, y), Vector2(x, y - side*18)]), Color(1, 0.94, 0.76, fade))
			if not warning:
				for i in 8:
					var d := Vector2.from_angle(TAU*i/8.0)
					draw_line(p+d*18, p+d*(35+25*k), Color(1,0.85,0.5,fade), 3)
		UnitBase.Element.FIRE:
			var poly := strip()
			draw_colored_polygon(poly, Color(1, 0.18, 0.01, 0.14 if warning else 0.3))
			draw_polyline(poly, Color(1, 0.4, 0.06, fade), 3)
			if warning:
				for i in 8:
					var p: Vector2 = cast.direction * cell * (0.4 + i * 0.6)
					draw_line(p - (cast.direction as Vector2).orthogonal()*15, p + cast.direction*15, Color(1, 0.5, 0.1), 3)
			else:
				for i in 24:
					var d: Vector2 = cast.direction
					var p := d*cell*(0.2+fmod(i*0.73,4.7)) + d.orthogonal()*sin(i*7.1)*cell*.55
					var h := 22 + 17*sin(elapsed*12+i*1.7)
					draw_colored_polygon(PackedVector2Array([p+Vector2(-10,0),p+Vector2(-5,-h*.55),p+Vector2(3,-h),p+Vector2(12,-h*.3),p+Vector2(10,0)]), Color(1, .25, .015, fade))
					draw_line(p, p+Vector2(2,-h*.6), Color(1,.8,.1,fade), 4)
		UnitBase.Element.WATER:
			var radius := cell * (2.0 if cast.state == "water_blast" or not warning else 3.0 + .25*(int(cast.heads)-1))
			draw_circle(Vector2.ZERO, radius, Color(0,.45,1,.1))
			draw_arc(Vector2.ZERO,radius,0,TAU,64,ink,3)
			for ring in 4:
				var t := fmod(k + ring*.25,1.0)
				var r := radius * (1.0-t if warning else t)
				draw_arc(Vector2.ZERO,r,0,TAU,48,Color(.35,.85,1,fade*(.3+.5*t)), 3 if warning else 6)
			for i in 14:
				var d := Vector2.from_angle(TAU*i/14.0+elapsed)
				var p := d*radius*(1.0-fmod(k+i*.07,1.0))
				draw_line(p,p+d*16,Color(.6,.95,1,fade),4)
		UnitBase.Element.EARTH:
			for mark in cast.marks:
				var p := point(manager.battle_grid.to_global(manager.battle_grid.grid_to_world(mark)))
				if warning:
					draw_circle(p, cell*.4, Color(.8,.42,.1,.18))
					for i in 6:
						var d := Vector2.from_angle(TAU*i/6.0)
						draw_line(p+d*15,p+d*(35+8*sin(k*PI)),Color(1,.65,.2),3)
				else:
					for i in 5:
						var base := p+Vector2((i-2)*15.0,abs(i-2)*4.0)
						var h: float = (72-abs(i-2)*9)*sin(PI*minf(1,k*1.2))
						draw_colored_polygon(PackedVector2Array([base+Vector2(-9,3),base+Vector2(-4,-h),base+Vector2(4,-h*.8),base+Vector2(10,3)]),Color(.48,.30,.13,fade))
						draw_line(base+Vector2(-4,-h),base+Vector2(4,-h*.8),Color(1,.74,.35,fade),3)
		UnitBase.Element.AIR:
			var poly := cone()
			draw_colored_polygon(poly,Color(.65,1,1,.10 if warning else .2))
			draw_polyline(poly,ink,2)
			for band in 8:
				var reach := cell*(4+.5*(int(cast.heads)-1))*fmod(k+band*.125,1.0)
				var angle: float = (cast.direction as Vector2).angle()
				draw_arc(Vector2.ZERO,reach,angle-deg_to_rad(32),angle+deg_to_rad(32),24,Color(.75,1,1,fade),2 if warning else 5)
		UnitBase.Element.LIGHTNING:
			if warning:
				var p := target_point()
				draw_arc(p,38,0,TAU,32,Color(1,.85,.05),3)
				for i in 5:
					var d := Vector2.from_angle(TAU*i/5.0 + elapsed*4)
					draw_line(p+d*45,p+d*60,Color(1,1,.3),3)
				bolt(Vector2.ZERO,p,Color(1,.8,.05,.4),elapsed)
			else:
				var points: PackedVector2Array = cast.get("lightning",PackedVector2Array())
				for i in range(1,points.size()):
					bolt(point(points[i-1]),point(points[i]),Color(1,.95,.2,fade),elapsed+i)
					var p := point(points[i])
					for fork in 3:
						bolt(p,p+Vector2.from_angle(fork*TAU/3+elapsed)*45,Color(1,.85,.1,fade*.65),elapsed+fork)

func bolt(a: Vector2, b: Vector2, c: Color, seed_value: float) -> void:
	var points := PackedVector2Array([a])
	var side := (b-a).normalized().orthogonal()
	for i in range(1,9):
		points.append(a.lerp(b,i/9.0)+side*sin(i*12.7+seed_value*30)*13)
	points.append(b)
	draw_polyline(points,c,5)
	draw_polyline(points,Color(1,1,1,c.a),2)
