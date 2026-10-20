extends Node3D
class_name Model3DCable

## A simulated rope inside a Model3DSprite's viewport, strung between two bones.
##
## Exists for Static (2026-10-01, owner: "hopefully our rubber wire looks more
## like a flexible wire"). His live wire was a rigid mesh bound 100% to
## RightHand, so it swung like a stick. Skinning it between Hips and RightHand
## sheared it instead (see the STATIC block in VisualUnit). A verlet rope has
## neither problem: both ends are pinned to bones, everything between sags under
## gravity, trails the hand when it moves, and keeps its length.
##
## Lives in the model's own space as a child of the glTF root, so it renders in
## the same SubViewport — same toon shading, same 2D outline pass — as the body.
## Coordinates passed in are MODEL space at REST (Blender world (x, y, z) ->
## Godot (x, z, -y)), converted once to bone-local offsets at setup.

var segments: int = 14
var length: float = 0.95
var radius: float = 0.032
var sides: int = 6
var gravity: float = 9.8
var damping: float = 0.94
var iterations: int = 10
## Vertical capsules the rope may not enter, model space:
##   [{"bottom": Vector3, "top": Vector3, "radius": float}]
var colliders: Array = []
var floor_y: float = 0.0

var _skel: Skeleton3D
var _start_bone := -1
var _end_bone := -1
var _start_local: Vector3
var _end_local: Vector3
var _tip_local: Vector3
var _has_tip := false
var _pts: PackedVector3Array = PackedVector3Array()
var _prev: PackedVector3Array = PackedVector3Array()
var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var _mat: Material
var _acc := 0.0
const STEP := 1.0 / 60.0

func setup(skel: Skeleton3D, start_bone: String, start_rest: Vector3,
		end_bone: String, end_rest: Vector3, material: Material) -> bool:
	_skel = skel
	_start_bone = skel.find_bone(start_bone)
	_end_bone = skel.find_bone(end_bone)
	if _start_bone < 0 or _end_bone < 0:
		push_warning("Model3DCable: bone missing (%s / %s)" % [start_bone, end_bone])
		return false
	_mat = material
	_start_local = (_bone_model_xform(_start_bone, true)).affine_inverse() * start_rest
	_end_local = (_bone_model_xform(_end_bone, true)).affine_inverse() * end_rest
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	_seed()
	# Settle before the first frame so the rope never appears as a stiff line.
	for i in 90:
		_step(STEP)
	_rebuild()
	return true

## Bone transform in this node's parent space (the glTF root = model space).
func _bone_model_xform(idx: int, rest: bool) -> Transform3D:
	var to_model: Transform3D = get_parent().global_transform.affine_inverse() * _skel.global_transform
	var pose: Transform3D = _skel.get_bone_global_rest(idx) if rest else _skel.get_bone_global_pose(idx)
	return to_model * pose

func _anchors() -> Array:
	return [_bone_model_xform(_start_bone, false) * _start_local,
		_bone_model_xform(_end_bone, false) * _end_local]

func _seed() -> void:
	var ab: Array = _anchors()
	var a: Vector3 = ab[0]
	var b: Vector3 = ab[1]
	# A V hanging below the chord, so the rope starts close to its rest length.
	var chord := a.distance_to(b)
	var drop := sqrt(maxf(length * length - chord * chord, 0.0)) * 0.5
	_pts.resize(segments + 1)
	_prev.resize(segments + 1)
	for i in segments + 1:
		var f := float(i) / segments
		var p := a.lerp(b, f) + Vector3.DOWN * drop * (1.0 - absf(f * 2.0 - 1.0))
		_pts[i] = p
		_prev[i] = p

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_acc = minf(_acc + delta, STEP * 4.0)
	while _acc >= STEP:
		_step(STEP)
		_acc -= STEP
	_rebuild()

func _step(dt: float) -> void:
	var ab: Array = _anchors()
	var g := Vector3.DOWN * gravity * dt * dt
	for i in range(1, segments):
		var p := _pts[i]
		var v := (p - _prev[i]) * damping
		_prev[i] = p
		_pts[i] = p + v + g
	var seg := length / segments
	for _it in iterations:
		_pts[0] = ab[0]
		_pts[segments] = ab[1]
		for i in segments:
			var d := _pts[i + 1] - _pts[i]
			var l := d.length()
			if l < 0.00001:
				continue
			var corr := d * ((l - seg) / l) * 0.5
			if i == 0:
				_pts[i + 1] -= corr * 2.0
			elif i + 1 == segments:
				_pts[i] += corr * 2.0
			else:
				_pts[i] += corr
				_pts[i + 1] -= corr
		for i in range(1, segments):
			_pts[i] = _collide(_pts[i])
	_pts[0] = ab[0]
	_pts[segments] = ab[1]

func _collide(p: Vector3) -> Vector3:
	for c in colliders:
		var bot: Vector3 = c["bottom"]
		var top: Vector3 = c["top"]
		var r: float = float(c["radius"]) + radius
		var axis := top - bot
		var t := clampf((p - bot).dot(axis) / maxf(axis.length_squared(), 0.00001), 0.0, 1.0)
		var closest := bot + axis * t
		var off := p - closest
		var dist := off.length()
		if dist < r:
			p = closest + (off / dist if dist > 0.00001 else Vector3.BACK) * r
	p.y = maxf(p.y, floor_y + radius)
	return p

func _rebuild() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	var rings: Array = []
	var ref := Vector3.ZERO
	for i in segments + 1:
		var t: Vector3
		if i == 0:
			t = _pts[1] - _pts[0]
		elif i == segments:
			t = _pts[i] - _pts[i - 1]
		else:
			t = _pts[i + 1] - _pts[i - 1]
		t = t.normalized() if t.length() > 0.00001 else Vector3.DOWN
		# Parallel transport: carry the previous ring's reference axis onto this
		# ring's plane. Rebuilding it from a fixed "up" (or from n2) rotates the
		# cross-section ring to ring and the hexagon faces zig-zag.
		if ref == Vector3.ZERO:
			ref = Vector3.RIGHT if absf(t.dot(Vector3.UP)) > 0.95 else Vector3.UP
		var n1 := (ref - t * ref.dot(t))
		if n1.length() < 0.0001:
			n1 = t.cross(Vector3.FORWARD)
		n1 = n1.normalized()
		var n2 := t.cross(n1).normalized()
		ref = n1
		var ring: Array = []
		for s in sides:
			var ang := TAU * s / sides
			ring.append(n1 * cos(ang) + n2 * sin(ang))
		rings.append(ring)
	for i in segments:
		for s in sides:
			var s2 := (s + 1) % sides
			var na: Vector3 = rings[i][s]
			var nb: Vector3 = rings[i][s2]
			var nc: Vector3 = rings[i + 1][s]
			var nd: Vector3 = rings[i + 1][s2]
			var pa := _pts[i] + na * radius
			var pb := _pts[i] + nb * radius
			var pc := _pts[i + 1] + nc * radius
			var pd := _pts[i + 1] + nd * radius
			for v in [[na, pa], [nc, pc], [nb, pb], [nb, pb], [nc, pc], [nd, pd]]:
				_mesh.surface_set_normal(v[0])
				_mesh.surface_add_vertex(v[1])
	_mesh.surface_end()

## An extra point carried rigidly by the START bone (e.g. the live fork tips
## above the plug), so 2D effects can sit on geometry that is not a bone.
func set_tip(rest: Vector3) -> void:
	_tip_local = (_bone_model_xform(_start_bone, true)).affine_inverse() * rest
	_has_tip = true

func tip_point() -> Vector3:
	if not _has_tip:
		return _pts[0] if _pts.size() > 0 else Vector3.ZERO
	return _bone_model_xform(_start_bone, false) * _tip_local

## Rope points in model space, plug end first — for effects that crawl along it.
func points() -> PackedVector3Array:
	return _pts
