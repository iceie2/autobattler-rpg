extends Node2D
class_name Model3DSprite

## A rigged 3D character that behaves like a Sprite2D.
##
## The board, the backgrounds and every bit of UI stay 2D — this renders one
## glTF character into its own SubViewport with an orthogonal camera and shows
## the result through a Sprite2D. That keeps the whole 2.5D change local: from
## the outside this node has a texture, a position, a scale and a flip, exactly
## like the plain_sprite / animated_sprite that VisualUnit already drives.
##
## Anim names follow the merge tool's NAME_MAP (see tools/model3d/glb_merge_anims.py):
##   idle walk run attack attack_alt attack_heavy skill block hurt death victory
##
## Cost note: each instance is a live 3D viewport. Keep RENDER_SIZE modest and
## call set_paused(true) for units that are off-screen or dead — a board of 20
## always-updating viewports is the thing most likely to cost frames.

## Production pixel-art render resolution. The viewport is composited with
## nearest-neighbour filtering at 115px on the board, keeping deliberate pixel
## clusters instead of preserving sub-pixel Meshy surface noise.
const RENDER_SIZE := Vector2i(128, 128)
## Extra viewport WIDTH (multiplier) for characters whose animations reach well
## outside their standing silhouette. A stretched punch is ~2.2x the arm's normal
## reach and clipped straight off the side of a square frame. Widening the
## viewport rather than zooming the camera out keeps the character the same
## on-screen HEIGHT as every other hero — see camera keep_aspect below.
const STRETCH_FRAME_WIDTH := 1.9

var render_size: Vector2i = RENDER_SIZE
## Headroom on every side for a character whose CLIPS reach well past its idle +
## death silhouette. The camera frame is sized from those two alone, so anything
## outside it is cut off: Bloodhound's overhead chop put a claw ~0.45 units over
## the top edge and ~0.4 past the side (measured 2026-09-23 — the v001 auto-attack
## had been clipping the same way on every swing). Grows the camera frame AND the
## viewport by the same factor, so pixels per world unit — his on-screen size and
## pixel-art look — do not change; only the transparent canvas around him grows.
## Viewport pixels scale with the square, so measure before raising it.
var frame_grow: float = 1.0
## Test-only presentation override. The style-comparison scene sets this before
## constructing each VisualUnit, then clears it immediately. Empty in gameplay,
## so the production defaults below remain unchanged.
static var debug_style_override: Dictionary = {}
var texture_filter_nearest: bool = true
var toon_bands: float = 3.0
var color_cluster_levels: float = 0.0
## Camera pitch, in degrees above the character's eye line.
##
## DEFAULT 0 ON PURPOSE. This game's board is dead-flat: the grass/dirt tiles are
## an unforeshortened plane and every 2D hero and monster is drawn square to the
## viewer. Any pitch at all makes the 3D character the ONLY object on screen with
## a perspective, which is what read as "off" when the first model went in.
## Set it per-instance BEFORE setup() if a scene ever wants a tilted look.
var camera_pitch_deg: float = 0.0
## Cel-shade the model and give it a dark outline, instead of smooth PBR.
##
## This is the setting that decides whether a 3D character belongs on a 2D
## painted board. Default PBR gives a smooth gradient across every surface; the
## hand-drawn roster has flat colour areas and hard shadow edges, so an
## unmodified model reads as an object from a different game sitting on top of
## the art rather than a character in it. Banding the light into 2 steps and
## adding a silhouette line is what closes most of that gap.
var toon: bool = true
## Toon palette knobs, mirrored into TOON_SHADER's uniforms at setup().
## Defaults chosen by rendering the board check across a ladder of values and
## measuring mean HSV saturation of Cross's pixels against the 2D roster's:
## 0.274 (raw PBR) -> 0.336 here, with the roster at 0.515 (fire/water heroes,
## an unfair ceiling for a grey lemur). Per-instance, so a character whose
## source texture is already vivid can dial it back without a shader edit.
var toon_saturation: float = 1.55
var toon_brightness: float = 1.14
## Dark half of the 2-step ramp; lower = harder terminator.
var toon_shadow_tone: float = 0.38
## Optional per-source-material tuning. This keeps a character's focal material
## readable without shifting props or the rest of the roster. Keys are exact
## material names from the imported GLB.
var material_saturation_scale: Dictionary = {}
var material_brightness_scale: Dictionary = {}
var material_shadow_tone: Dictionary = {}
var material_rim_amount: Dictionary = {}
## Outline thickness in SCREEN PIXELS.
##
## Done as a 2D pass over the finished viewport texture, not as the usual 3D
## inverted-hull. Two reasons, both decisive here: a model-space hull gives an
## outline whose apparent thickness changes with the character's size on screen,
## while the hand-drawn roster has a constant ~2px contour at every size; and the
## hull version measurably did not read at the 118px a unit actually occupies.
## Because the character is already being composited as a sprite, the 2D route
## is both cheaper and the one that matches the art.
var outline_px: float = 2.5
var outline_color: Color = Color(0.09, 0.07, 0.12, 1.0)
## Widens the render viewport for a character whose attack reaches out past
## its own idle silhouette (a punch/claw/limb stretch). Opt-in per character:
## it is a strong stylistic choice that suits a character whose whole identity
## is reaching out and dragging things in, and would look wrong on a
## swordsman. ALSO REQUIRED even when the reach is baked straight into the
## clip's own keyframes (see 3D_PIPELINE.md / add_stretch_punch.py) rather
## than by _bake_arm_stretch below: _frame_camera() sizes the camera from the
## character's IDLE bone bounds with only 14% padding, computed once at setup
## before any clip has played, so a stretch clip's reach extends past the
## frame and gets clipped rather than just rendered small. Measured the hard
## way on Bouncer (2026-09-06): removing him from STRETCH_ARM_HEROES to kill
## the wrong-arm runtime bake bug below ALSO silently removed this frame
## widening, so the correctly-authored glb stretch was there and playing, just
## clipped down to almost nothing on screen.
var stretch_arm: bool = false
## Separately opt-in: actually run the OLD runtime stretch bake below. Off by
## default because every character converted so far bakes its stretch
## directly into the clip in Blender instead (see add_stretch_punch.py) — a
## real, reviewable keyframe rather than a generic procedural curve applied to
## whichever bones stretch_bones names. Turning this on without checking which
## arm the character's clip actually swings duplicates or fights that baked
## stretch with an unrelated one on the wrong bone (exactly what happened to
## Bouncer: this defaulted to targeting RightArm while his real, baked stretch
## is on LeftArm).
var runtime_bake_stretch: bool = false
## Clips that should stretch, and how far into each the arm is fully extended
## (as a fraction of the clip). The peak wants to land on the clip's own contact
## frame, or the arm reaches after the punch has already landed.
## Clips a character does not have are skipped, so listing extras is harmless.
var stretch_clips: Dictionary = {"attack": 0.45}

## Bones lengthened by the stretch, shoulder outward. The HAND is deliberately
## excluded — scaling it too inflates the glove into a balloon instead of
## sending it out on a long arm.
var stretch_bones: PackedStringArray = ["RightArm", "RightForeArm"]
## Extra length at full extension, as a multiple of the bone's rest length.
var stretch_amount: float = 1.65
## Vertical headroom above the model inside the frame, as a fraction of height.
const FRAME_MARGIN := 0.12

## Holstering + per-clip weapon variants: a held prop (gun, bow) rigidly bound
## to one hand bone cannot look right in every clip, because the bind is a
## SINGLE fixed offset relative to that bone's rotation, and different Meshy
## clips pose the hand differently (measured on Headhunter: the calibration
## that looked right in `aim` put the gun visibly wrong in `attack`, since the
## arms are drawn in close there instead of extended — recalibrating for
## `attack` then broke `aim` the same way in reverse). The fix is not one
## "best" calibration; it's a SEPARATE weapon node per clip (or group of
## clips) that needs its own, each produced by its own tools/model3d/
## rig_weapon.py pass against that clip's own hand positions, plus one more
## bound to a torso bone for every clip that isn't actively aiming/firing at
## all (holstered "on the back" — user call 2026-09-07).
##
## `weapon_variants` maps a clip to one node name or an Array of node names.
## Multiple names let a character show a matched prop set (Stitch's doll and
## needle) while retaining string compatibility for single-weapon heroes.
## Unlisted clips use `weapon_default_node` with the same String/Array shape.
## Node lookup is by exact object name and cached during setup().
var weapon_variants: Dictionary = {}     # e.g. {"aim":"Weapon_Aim","attack":"Weapon_Attack"}
var weapon_default_node: Variant = ""    # e.g. "Weapon_Back" or ["Doll_Stowed", "Needle_Stowed"]

## Clip name the CALLER asks for -> clip name in this .glb.
##
## Lets several units share one file when they differ only in which version of a
## clip they play: the goblin archer's "attack" is the bow draw, the melee
## goblin's is the knife slash, and both live in goblin.glb. Without this the
## caller would have to know which variant it is at every play() site.
var clip_aliases: Dictionary = {}
## Every prop node in the file this unit is responsible for showing OR HIDING.
##
## Visibility is only ever applied to nodes that got cached at setup(), and only
## names appearing in weapon_variants/weapon_default_node are cached. That is
## fine for a character whose variants between them mention every prop, and
## silently wrong for one sharing a file with another unit: the goblin archer's
## bow and quiver were never registered by the melee goblin, so they were never
## hidden and both variants rendered carrying all three props.
##
## List the file's FULL prop set here and the unshown ones get hidden.
var managed_prop_nodes: Array = []
var _weapon_nodes: Dictionary = {}       # node name -> Node3D, cached at setup()

## Self-illuminating surfaces, keyed by the SOURCE MATERIAL NAME in the .glb.
##
## Doc's syringe is authored as a two-slot mesh (tools/model3d/prop_edit.py
## --band) so the barrel's fluid span is its own material, "Fluid", separable
## from the casing. A material name is the right handle here and a mesh/node
## name is not: the glow has to cover PART of one welded prop object, which
## node visibility cannot express.
##
## `glow_base` is what the fluid reads as at rest — a syringe full of luminous
## serum, on every clip. `glow_by_clip` overrides it per clip (Doc: green while
## `skill` plays, gold on `ult`), so the ability's colour is carried by the prop
## the ability comes out of rather than by a separate VFX sprite.
## Leave `glow_material` empty and this whole path is inert.
var glow_material: String = ""
var glow_base: Color = Color(0, 0, 0)
var glow_by_clip: Dictionary = {}        # clip name -> Color
var glow_energy: float = 1.0
var _glow_mats: Array[ShaderMaterial] = []

## Optional board-scale prop motion layered over an authored attack.
var attack_prop_node: String = ""
var attack_prop_offset: Vector3 = Vector3.ZERO
var attack_prop_rotation_deg: Vector3 = Vector3.ZERO
var _attack_prop: Node3D = null
var _attack_prop_base: Transform3D

signal animation_finished(anim_name: String)

var model_path: String = ""
var render_height: float = 120.0   ## on-screen pixel height of the character
var facing_right: bool = true

var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D             ## Y-rotated for facing; model hangs off it
var _model: Node3D
var _anim: AnimationPlayer
var _sprite: Sprite2D
var _model_height: float = 1.0
var _sprite_scale_compensation: float = 1.0   ## see _frame_camera()
var _current: String = ""
var _queued_after_oneshot: String = ""
var _oneshot_active: bool = false

func setup(path: String, height: float = 120.0) -> bool:
	model_path = path
	render_height = height
	if not debug_style_override.is_empty():
		var dbg := debug_style_override
		var res := int(dbg.get("render_resolution", RENDER_SIZE.x))
		render_size = Vector2i(res, res)
		render_height = float(dbg.get("render_height", render_height))
		camera_pitch_deg = float(dbg.get("camera_pitch_deg", camera_pitch_deg))
		outline_px = float(dbg.get("outline_px", outline_px))
		toon_bands = float(dbg.get("toon_bands", toon_bands))
		texture_filter_nearest = bool(dbg.get("nearest", texture_filter_nearest))
		color_cluster_levels = float(dbg.get("color_cluster_levels", color_cluster_levels))
	if not ResourceLoader.exists(path):
		push_error("Model3DSprite: no model at %s" % path)
		return false

	if debug_style_override.is_empty():
		render_size = RENDER_SIZE
	if stretch_arm:
		render_size.x = int(round(RENDER_SIZE.x * STRETCH_FRAME_WIDTH))
	if frame_grow > 1.0:
		render_size = Vector2i(int(round(render_size.x * frame_grow)),
				int(round(render_size.y * frame_grow)))

	_viewport = SubViewport.new()
	_viewport.size = render_size
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The board is 2D and unlit; a 3D viewport with no environment renders black,
	# so the character carries its own light rig and ambient fill.
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	add_child(_viewport)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)

	_model = (load(path) as PackedScene).instantiate()
	_pivot.add_child(_model)
	if attack_prop_node != "":
		_attack_prop = _find_by_name(_model, attack_prop_node) as Node3D
		if _attack_prop:
			_attack_prop_base = _attack_prop.transform
		else:
			push_warning("Model3DSprite: attack prop '%s' missing in %s" % [attack_prop_node, path])

	_anim = _find(_model, "AnimationPlayer") as AnimationPlayer
	if _anim:
		_anim.animation_finished.connect(_on_anim_finished)
		_strip_horizontal_root_motion()

	var _weapon_names: Array = []
	for value in weapon_variants.values():
		_weapon_names.append_array(_weapon_name_list(value))
	_weapon_names.append_array(_weapon_name_list(weapon_default_node))
	_weapon_names.append_array(managed_prop_nodes)
	for wn in _weapon_names:
		if not _weapon_nodes.has(wn):
			var found := _find_by_name(_model, wn) as Node3D
			if found:
				_weapon_nodes[wn] = found

	_setup_lighting()
	if toon:
		_apply_toon_shading()
	if runtime_bake_stretch:
		_bake_arm_stretch()
	_frame_camera()

	_sprite = Sprite2D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.texture_filter = (CanvasItem.TEXTURE_FILTER_NEAREST if texture_filter_nearest
			else CanvasItem.TEXTURE_FILTER_LINEAR)
	_sprite.centered = true
	_sprite.z_index = 1
	if toon and outline_px > 0.0:
		_apply_outline_material()
	add_child(_sprite)
	# The viewport renders the character at RENDER_SIZE; scale down to the height
	# the board wants. Frame height maps to model height + margin on both sides.
	# _sprite_scale_compensation cancels out a wider death-clip camera frame
	# (see _frame_camera) so the IDLE pose still lands at exactly render_height
	# on screen — only the transparent canvas around him grows, not his size.
	var s: float = render_height / float(render_size.y) * (1.0 + FRAME_MARGIN * 2.0) \
			* _sprite_scale_compensation
	_sprite.scale = Vector2(s, s)

	play("idle")
	return true

## Bottom-anchor offset for a unit occupying `cell_size` cells, matching the
## convention VisualUnit._setup_plain_sprite() uses for the 2D art.
func bottom_anchor_offset(cell_half_px: float) -> Vector2:
	return Vector2(0.0, cell_half_px - _sprite.scale.y * render_size.y * 0.5)

func _setup_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	key.light_energy = 1.6
	# NO 3D shadows, ever (2026-09-09). Grounding on this board is the 2D black
	# oval VisualUnit._draw_shadow() paints under every unit, 2D and 3D alike.
	# A directional shadow inside the viewport can only fall on the character
	# himself — there is no floor geometry in here to catch one — so all it does
	# is add a soft self-shadow that fights the hard 2-step ramp, and reads as a
	# figurine lit by a different scene than the board it stands on.
	# Explicit rather than relying on the engine default: a default is not a
	# decision, and this one has to survive someone toggling it in the inspector.
	key.shadow_enabled = false
	_viewport.add_child(key)

	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS   # transparent, no sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.78)
	env.ambient_light_energy = 0.85
	# Same reasoning as key.shadow_enabled: every screen-space effect that could
	# darken or blur the silhouette is off by name, not by default.
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	# Screen-space glow stays OFF even for the emissive-syringe hero. Tried and
	# measured 2026-09-10: this SubViewport is transparent-bg, so the glow pass
	# does not see an HDR buffer and glow_hdr_threshold gates nothing -- at 1.0
	# AND at 1.9 the entire character bloomed, scrubs, boots and all. A glow
	# that softens the whole silhouette is exactly what the lines above refuse.
	# The luminous read is produced in the MATERIAL instead (_update_glow),
	# which is also how the 2D roster does it.
	env.glow_enabled = false
	env.fog_enabled = false
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

## Bake the rubber-hose arm stretch into the punch clips themselves.
##
## WHY BAKED, not applied at runtime: a text-to-animation service animates a
## FIXED skeleton — it emits bone rotations, never bone lengths — so no generated
## clip can contain a stretch. Writing bone scale from _process() loses to the
## AnimationPlayer, and a SkeletonModifier3D running after it is one more
## ordering dependency to get wrong; that version measured a x1.00 change in the
## arm's reach, i.e. did nothing, silently.
##
## Writing it into the track keys sidesteps all of it. The stretch is a pure
## function of clip time, so it bakes exactly, stays in perfect sync, costs
## nothing per frame, and can be inspected.
##
## The library is DUPLICATED first: Godot caches the imported .glb, so editing
## the animations in place would leak the stretch into every other instance of
## the same model — including any that deliberately set stretch_arm = false.
func _bake_arm_stretch() -> void:
	var skel := _find(_model, "Skeleton3D") as Skeleton3D
	if not (skel and _anim):
		push_warning("Model3DSprite: stretch_arm needs a Skeleton3D and an AnimationPlayer")
		return

	for ln in _anim.get_animation_library_list():
		var dup: AnimationLibrary = _anim.get_animation_library(ln).duplicate(true)
		_anim.remove_animation_library(ln)
		_anim.add_animation_library(ln, dup)

	for bone_name in stretch_bones:
		var bi: int = skel.find_bone(bone_name)
		if bi < 0:
			push_warning("Model3DSprite: no bone named %s" % bone_name)
			continue
		var axis := _bone_length_axis(skel, bi)
		for clip in stretch_clips:
			if has_animation(clip):
				_bake_track(_anim.get_animation(clip), skel, bi, bone_name,
					axis, float(stretch_clips[clip]))

func _bake_track(a: Animation, skel: Skeleton3D, bone_idx: int, bone_name: String,
		axis: Vector3, peak: float) -> void:
	# Find this bone's tracks. In practice there is NO scale track to reuse:
	# Meshy's glTF carries all-ones scale channels and Godot's importer discards
	# them, so every clip arrives with position + rotation only. The path has to
	# be copied off one of those rather than rebuilt — it is relative to the
	# AnimationPlayer's root ("Armature/Skeleton3D:RightArm"), and a hand-made
	# "Skeleton3D:RightArm" silently resolves to nothing and animates no bone.
	var track := -1
	var bone_path := ""
	for t in a.get_track_count():
		if not str(a.track_get_path(t)).ends_with(":" + bone_name):
			continue
		bone_path = str(a.track_get_path(t))
		if a.track_get_type(t) == Animation.TYPE_SCALE_3D:
			track = t
			break
	if bone_path == "":
		push_warning("Model3DSprite: '%s' has no tracks for %s" % [a.resource_name, bone_name])
		return
	if track < 0:
		track = a.add_track(Animation.TYPE_SCALE_3D)
		a.track_set_path(track, bone_path)
		var rest: Vector3 = skel.get_bone_rest(bone_idx).basis.get_scale()
		# Sampled densely: the stretch curve is the fastest-moving thing in the
		# clip, and a coarse bake turns its snap-back into a slow drift.
		for i in 49:
			a.scale_track_insert_key(track, a.length * float(i) / 48.0, rest)

	for k in a.track_get_key_count(track):
		var f: float = a.track_get_key_time(track, k) / maxf(a.length, 0.001)
		var s: float = 1.0 + stretch_amount * _stretch_curve(f, peak)
		var base: Vector3 = a.track_get_key_value(track, k)
		# Scale ALONG the bone only — a uniform scale fattens the arm as it
		# reaches, which reads as inflating rather than stretching.
		a.track_set_key_value(track, k, base * (Vector3.ONE + axis.abs() * (s - 1.0)))

## Out fast, hold an instant at full reach, snap back. The asymmetry IS the
## punch — a symmetric curve reads as the arm breathing rather than striking.
static func _stretch_curve(f: float, peak: float) -> float:
	if f <= 0.0 or f >= 1.0:
		return 0.0
	if f <= peak:
		return ease(f / peak, 0.30)                    # fast out
	var back: float = (f - peak) / maxf(1.0 - peak, 0.001)
	return clampf(1.0 - ease(minf(back / 0.75, 1.0), 2.2), 0.0, 1.0)   # hold, snap in

## Unit vector along a bone's own length, in its local space. Taken from where
## its first child sits at rest — no rig convention guarantees bones run down +Y.
static func _bone_length_axis(skel: Skeleton3D, idx: int) -> Vector3:
	for c in skel.get_bone_children(idx):
		var off: Vector3 = skel.get_bone_rest(c).origin
		if off.length() > 0.0001:
			return off.normalized()
	return Vector3.UP



## Screen-space outline over the composited character.
##
## Samples the viewport texture's alpha in a ring around each pixel; anywhere the
## character is transparent but a neighbour within `outline_px` is solid becomes
## contour. `region_rect`-free and resolution-independent, so the contour stays
## the same weight whether the unit is a 1-cell hero or a 3x3 boss.
const OUTLINE_SHADER = """
shader_type canvas_item;

uniform float thickness = 2.0;
uniform vec4 line_color : source_color = vec4(0.09, 0.07, 0.12, 1.0);
uniform float color_levels = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a > 0.5) {
		if (color_levels > 1.0) {
			c.rgb = floor(c.rgb * color_levels + 0.5) / color_levels;
		}
		COLOR = c;
	} else {
		float a = 0.0;
		vec2 px = TEXTURE_PIXEL_SIZE * thickness;
		// 8-tap ring: enough for a clean contour at these sizes, and a quarter
		// the samples of a full box blur.
		a = max(a, texture(TEXTURE, UV + vec2( px.x, 0.0)).a);
		a = max(a, texture(TEXTURE, UV + vec2(-px.x, 0.0)).a);
		a = max(a, texture(TEXTURE, UV + vec2(0.0,  px.y)).a);
		a = max(a, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);
		a = max(a, texture(TEXTURE, UV + px * 0.707).a);
		a = max(a, texture(TEXTURE, UV - px * 0.707).a);
		a = max(a, texture(TEXTURE, UV + vec2(px.x, -px.y) * 0.707).a);
		a = max(a, texture(TEXTURE, UV + vec2(-px.x, px.y) * 0.707).a);
		COLOR = vec4(line_color.rgb, line_color.a * step(0.5, a));
	}
}
"""

func _apply_outline_material() -> void:
	var sh := Shader.new()
	sh.code = OUTLINE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	# The viewport renders at RENDER_SIZE and is scaled down to render_height, so
	# convert the wanted SCREEN pixels back into viewport pixels. Must match
	# the ACTUAL final _sprite.scale (setup(), including
	# _sprite_scale_compensation) or the outline comes out the wrong physical
	# thickness whenever the death-clip camera frame is wider than idle.
	var down: float = render_height / float(render_size.y) * (1.0 + FRAME_MARGIN * 2.0) \
			* _sprite_scale_compensation
	mat.set_shader_parameter("thickness", outline_px / maxf(down, 0.001))
	mat.set_shader_parameter("line_color", outline_color)
	mat.set_shader_parameter("color_levels", color_cluster_levels)
	_sprite.material = mat

## Cel shading, applied over whatever material the glTF
## shipped with (so the model keeps its own albedo texture).
##
## Two parts. The shader bands the diffuse term into flat steps and adds a rim
## light, which turns smooth gradients into the hard-edged shapes the 2D art
## uses. The next_pass is the classic inverted-hull outline: the same mesh grown
## along its normals, front faces culled, drawn unshaded — that's the dark
## contour every sprite on this board already has drawn into it.
const TOON_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 tint : source_color = vec4(1.0);
uniform float bands = 2.0;
uniform float rim_amount = 0.35;
// Palette match with the 2D roster (2026-09-09). The goblins and board tiles are
// high-chroma flat colour; an unmodified glTF albedo next to them reads muddy
// and desaturated even once the LIGHTING is banded, because the problem is the
// base colour, not the shading. These lift the texture itself before any light
// touches it, so the character sits in the same palette range as the art.
uniform float saturation = 1.55;
uniform float brightness = 1.14;
// The dark half of the 2-step ramp. Lower = higher contrast between lit and
// shadow tone. 0.55 was near-flat; the drawn art's terminator is much harder.
uniform float shadow_tone = 0.38;
// Per-surface self-illumination, driven at runtime by _update_glow(). Zero
// energy on every surface unless a hero opts in (Doc's syringe fluid), so this
// costs nothing for the rest of the roster.
uniform vec4 emission_color : source_color = vec4(0.0);
uniform float emission_energy = 0.0;

void fragment() {
	vec4 c = texture(albedo_tex, UV) * tint;
	vec3 rgb = c.rgb * brightness;
	// Rec.709 luma keeps the saturation lift from shifting perceived value.
	float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	rgb = clamp(mix(vec3(luma), rgb, saturation), vec3(0.0), vec3(1.0));
	ALBEDO = rgb;
	ALPHA = c.a;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	// Added, not mixed: the liquid keeps its own colour and gets brighter,
	// rather than being replaced by the glow tint.
	EMISSION = emission_color.rgb * emission_energy;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	// Band the diffuse into flat steps: hard terminator, like painted shading.
	float lit = clamp(ndl, 0.0, 1.0);
	lit = floor(lit * bands + 0.5) / bands;
	lit = mix(shadow_tone, 1.0, lit);
	// Rim light along the silhouette so the character separates from the
	// backdrop the way a drawn highlight would.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	// MUST modulate by ALBEDO. Adding the light term on its own blows every
	// surface out to the light's colour and the character loses all its own
	// colour — the first cut of this shader turned an orange robot bone white.
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * ALBEDO * (lit + rim * rim_amount);
}
"""

func _apply_toon_shading() -> void:
	var shader := Shader.new()
	shader.code = TOON_SHADER

	for n in _walk(_model):
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		for s in mi.get_surface_override_material_count():
			var src := mi.mesh.surface_get_material(s)
			var mat := ShaderMaterial.new()
			mat.shader = shader
			# `tint` must be applied whether or not there is a TEXTURE. It used to
			# sit inside the albedo_texture guard, which meant any surface
			# without one kept the shader's defaults — hint_default_white times
			# a white tint — and rendered as flat PURE WHITE.
			# That is exactly what happened to Cross's maul and shield
			# (2026-09-09): generated weapon props are untextured and carry no
			# UVs at all (POSITION/NORMAL only), so both came out white, and a
			# thin white maul against a pale lemur read as no weapon at all.
			# Headhunter's rifle has the same problem and only got away with it
			# by being a big shape against a dark character.
			if src is BaseMaterial3D:
				if src.albedo_texture:
					mat.set_shader_parameter("albedo_tex", src.albedo_texture)
				mat.set_shader_parameter("tint", src.albedo_color)
			var material_name := src.resource_name if src != null else ""
			mat.set_shader_parameter("saturation", toon_saturation
					* float(material_saturation_scale.get(material_name, 1.0)))
			mat.set_shader_parameter("brightness", toon_brightness
					* float(material_brightness_scale.get(material_name, 1.0)))
			mat.set_shader_parameter("shadow_tone",
					float(material_shadow_tone.get(material_name, toon_shadow_tone)))
			mat.set_shader_parameter("rim_amount",
					float(material_rim_amount.get(material_name, 0.35)))
			mat.set_shader_parameter("bands", toon_bands)
			if glow_material != "" and src != null and src.resource_name == glow_material:
				_glow_mats.append(mat)
			mi.set_surface_override_material(s, mat)
	if glow_material != "" and _glow_mats.is_empty():
		# Silence here would ship a hero whose ability colour never appears and
		# look like an art problem. Name the materials that DO exist.
		var have: Array[String] = []
		for n in _walk(_model):
			if n is MeshInstance3D:
				for s2 in (n as MeshInstance3D).mesh.get_surface_count():
					var m2 := (n as MeshInstance3D).mesh.surface_get_material(s2)
					if m2 != null:
						have.append(m2.resource_name)
		push_warning("Model3DSprite: glow_material '%s' matched no surface in %s (found: %s)"
			% [glow_material, model_path, ", ".join(have)])
	_update_glow(_current)

## Pin the root bone's HORIZONTAL travel while leaving its vertical travel alone.
##
## These clips are authored with root motion — walk strides forward, and the
## knockdown slides the body a long way across the floor. On a grid board the
## unit's CELL is its position, so that travel just walks the character out of
## its own square (caught in the board check: the death pose ended up two cells
## to the left with its health bar left behind). Y is kept, so the body still
## drops when it falls and bobs when it strides.
##
## Freezing to the FIRST key's value makes this idempotent, which matters because
## Godot caches the imported animations and every unit of this class shares them
## — the meta guard skips the rework, and re-running it would be harmless anyway.
func _strip_horizontal_root_motion() -> void:
	for name in _anim.get_animation_list():
		var a := _anim.get_animation(name)
		if a.has_meta("root_motion_stripped"):
			continue
		a.set_meta("root_motion_stripped", true)
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
				continue
			# Only the root bone drives the body across the floor; every other
			# bone's position track is local to its parent and must be left alone.
			if not str(a.track_get_path(t)).ends_with(":Hips"):
				continue
			var n := a.track_get_key_count(t)
			if n == 0:
				continue
			var anchor: Vector3 = a.track_get_key_value(t, 0)
			for k in n:
				var v: Vector3 = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, Vector3(anchor.x, v.y, anchor.z))

## Orthogonal framing so the character never distorts as it moves around the
## board, and so its on-screen size is exactly predictable from render_height.
func _frame_camera() -> void:
	var idle_aabb := character_bounds(_model)
	_model_height = maxf(idle_aabb.size.y, 0.001)

	# Also account for the death clip specifically, not just idle, for the
	# CAMERA's field of view — a knockdown can launch or sprawl the body past
	# the idle silhouette, clipping at the frame edge instead of just
	# rendering smaller (user report 2026-09-06, "half of him clipped off
	# screen" on landing). Measured on Bouncer: the knockdown apex reaches
	# ~1.5x idle height and the final sprawled pose's X extent is nearly 2x
	# idle's width, both from limbs swinging out via rotation (not root
	# translation, so _strip_horizontal_root_motion doesn't touch this).
	# Scoped to death only — it's the one oneshot guaranteed to play for every
	# character and never return to a smaller pose afterward, unlike
	# attack/hurt where a wider permanent frame would needlessly affect the
	# character's everyday on-board look for the sake of one swing.
	var idle_centre := idle_aabb.position + idle_aabb.size * 0.5

	var frame_aabb := idle_aabb
	if _anim and _anim.has_animation("death"):
		frame_aabb = frame_aabb.merge(_clip_bounds("death"))

	# The camera must keep AIMING at idle_centre, not the merged AABB's own
	# centre — measured 2026-09-06 (user report: units sitting low in their
	# cell): merging death's bounds pulls the centre up by ~0.12 world units
	# (death's launch apex is much higher above idle than its lying-down pose
	# is below it), and re-aiming the camera at that new, higher point pushes
	# the IDLE character down within the rendered frame even though his own
	# position never moved. So `centre` stays pinned to idle_centre always;
	# only the FRAME SIZE grows, as the largest radius from that fixed point
	# to any edge of the merged bounds — symmetric around idle_centre, so
	# idle/walk/attack framing (and therefore on-screen position) is
	# byte-for-byte what it was before death was ever factored in.
	var half_h: float = maxf(idle_centre.y - frame_aabb.position.y,
			(frame_aabb.position.y + frame_aabb.size.y) - idle_centre.y)
	# frame_grow widens the frame symmetrically about idle_centre, and setup()
	# grew the viewport by the same factor, so density and idle placement hold.
	var frame_height: float = maxf(half_h * 2.0, 0.001) * maxf(frame_grow, 1.0)
	var half_w: float = maxf(idle_centre.x - frame_aabb.position.x,
			(frame_aabb.position.x + frame_aabb.size.x) - idle_centre.x)
	var half_d: float = maxf(idle_centre.z - frame_aabb.position.z,
			(frame_aabb.position.z + frame_aabb.size.z) - idle_centre.z)

	# _sprite_scale_compensation undoes the side effect a bigger camera.size
	# would otherwise have: the viewport's world-to-pixel density is set by
	# camera.size ALONE (render_height/render_size.y cancels out of that
	# ratio — see setup()'s sprite-scale comment), so widening the frame to
	# fit death would, uncompensated, make Bouncer render measurably SMALLER
	# during ordinary idle/walk/attack too. Scaling render_height up by
	# exactly (frame_height/idle_height) when computing _sprite.scale cancels
	# that out: the on-screen density stays pinned to the IDLE height, and
	# the extra death headroom just makes the transparent canvas bigger
	# around him rather than shrinking him.
	_sprite_scale_compensation = frame_height / _model_height

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# KEEP_HEIGHT so `size` always means the VERTICAL extent. A wider viewport
	# then simply shows more to the sides at the same vertical scale, instead of
	# shrinking the character to fit.
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.size = frame_height * (1.0 + FRAME_MARGIN * 2.0)
	_camera.near = 0.01
	_camera.far = 100.0
	var dist: float = maxf(Vector3(half_w, half_h, half_d).length() * 2.0, 1.0) * 3.0
	var pitch := deg_to_rad(camera_pitch_deg)
	_camera.position = idle_centre + Vector3(0.0, sin(pitch) * dist, cos(pitch) * dist)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
	_viewport.add_child(_camera)
	_camera.make_current()

# ── animation ────────────────────────────────────────────────────────────────

## Resolve a caller-facing clip name to the one actually in the file.
## Blend-shape weights driven by a curve on a clip's OWN playback position:
## {"ult": {"belly": [[t, w], ...]}} with t in clip seconds. Used where a shape
## should follow a clip exactly without exporting per-clip shape-key actions
## (Bouncer's belly inflating on the Gravity Drop inhale). Timing rides the clip,
## so it follows play_oneshot_timed's speed change for free. Weights are zeroed
## as soon as the clip is not the one playing.
var morph_curves: Dictionary = {}
var _morph_meshes: Array = []          # [MeshInstance3D, shape_idx, shape_name]
var _morph_active := false

func _update_morphs() -> void:
	if morph_curves.is_empty() or _anim == null:
		return
	if _morph_meshes.is_empty():
		var names := {}
		for clip in morph_curves:
			for n in morph_curves[clip]:
				names[n] = true
		for node in _walk(_model):
			if node is MeshInstance3D:
				for n in names:
					var idx: int = (node as MeshInstance3D).find_blend_shape_by_name(n)
					if idx >= 0:
						_morph_meshes.append([node, idx, n])
	var curves: Dictionary = morph_curves.get(_current, {})
	var playing := not curves.is_empty() and _anim.is_playing()
	if not playing and not _morph_active:
		return
	_morph_active = playing
	var t: float = _anim.current_animation_position if playing else 0.0
	for entry in _morph_meshes:
		var w := 0.0
		if playing and curves.has(entry[2]):
			var pts: Array = curves[entry[2]]
			w = float(pts[-1][1])
			for i in pts.size() - 1:
				if t <= float(pts[i + 1][0]):
					var u := (t - float(pts[i][0])) / maxf(float(pts[i + 1][0]) - float(pts[i][0]), 0.0001)
					w = lerpf(float(pts[i][1]), float(pts[i + 1][1]), smoothstep(0.0, 1.0, clampf(u, 0.0, 1.0)))
					break
		(entry[0] as MeshInstance3D).set_blend_shape_value(entry[1], w)

func _process(_delta: float) -> void:
	_update_morphs()
	if not _attack_prop:
		return
	_attack_prop.transform = _attack_prop_base
	if _current != "attack" or not _anim or not _anim.is_playing():
		return
	var length: float = maxf(_anim.current_animation_length, 0.001)
	var phase: float = clampf(_anim.current_animation_position / length, 0.0, 1.0)
	# Brace until 18%, snap to full extension at 38%, and recover by 68%.
	var amount: float = 0.0
	if phase < 0.18:
		amount = -0.18 * smoothstep(0.0, 0.18, phase)
	elif phase < 0.38:
		amount = lerpf(-0.18, 1.0, smoothstep(0.18, 0.38, phase))
	elif phase < 0.68:
		amount = 1.0 - smoothstep(0.38, 0.68, phase)
	var attack_transform := _attack_prop_base
	attack_transform.origin += attack_prop_offset * amount
	var euler := attack_prop_rotation_deg * (PI / 180.0) * amount
	attack_transform.basis = attack_transform.basis * Basis.from_euler(euler)
	_attack_prop.transform = attack_transform


func _clip(name: String) -> String:
	return clip_aliases.get(name, name)


func has_animation(name: String) -> bool:
	return _anim != null and _anim.has_animation(_clip(name))

func play(name: String, loop: bool = true) -> bool:
	if not has_animation(name):
		return false
	# Alias resolution happens ONCE, here. _current and every per-clip lookup
	# below (weapon visibility, glow, yaw bias) stay in the caller's vocabulary,
	# so a config keyed on "attack" works whichever file variant is loaded.
	name = _clip(name)
	if _current == name and _anim.is_playing():
		return true
	var a := _anim.get_animation(name)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_anim.play(name)
	_current = name
	if loop:
		_oneshot_active = false
	_update_weapon_visibility(name)
	_update_glow(name)
	_yaw_bias_deg = clip_yaw_bias_deg.get(name, 0.0)
	return true

## Recolour the glowing surfaces for the clip about to play. Called from play(),
## alongside the weapon-visibility swap, so the glow changes on exactly the same
## frame the ability's animation starts.
func _update_glow(clip: String) -> void:
	if _glow_mats.is_empty():
		return
	var c: Color = glow_by_clip.get(clip, glow_base)
	# Alpha carries INTENSITY: a base fluid can sit at a low simmer and an ult
	# can blow out, without needing a second parallel dictionary.
	var e: float = glow_energy * c.a
	for m in _glow_mats:
		# Drive the ALBEDO, not just EMISSION. With no bloom pass available
		# (see _setup_lighting) emission alone only lightens the fluid a shade
		# and is invisible at the 138 px the character actually ships at. The
		# tint is the ability's colour outright and `brightness` lifts it clear
		# of the surrounding casing, so the liquid reads as lit from inside.
		m.set_shader_parameter("tint", c)
		m.set_shader_parameter("brightness", toon_brightness * (1.0 + e))
		# Kept as well: it costs nothing, survives a future bloom pass, and
		# flattens the fluid's own shading so it does not band like cloth.
		m.set_shader_parameter("emission_color", c)
		m.set_shader_parameter("emission_energy", e)


func _update_weapon_visibility(clip: String) -> void:
	if _weapon_nodes.is_empty():
		return   # this character has no weapon-variant nodes — no-op
	var show_names := _weapon_name_list(weapon_variants.get(clip, weapon_default_node))
	for wn in _weapon_nodes:
		_weapon_nodes[wn].visible = wn in show_names

func _weapon_name_list(value: Variant) -> Array:
	if value is Array:
		return value
	if value is String and value != "":
		return [value]
	return []

## Play a non-looping action, then fall back to `resume`. Pass resume="" to HOLD
## the final pose instead (death: the clip ends collapsed and stays there).
func play_oneshot(name: String, resume: String = "idle") -> bool:
	if not play(name, false):
		return false
	_queued_after_oneshot = resume
	_oneshot_active = true
	return true

func play_oneshot_timed(name: String, duration: float, resume: String = "idle") -> bool:
	if not play_oneshot(name, resume):
		return false
	_anim.speed_scale = animation_length(name) / maxf(duration, 0.05)
	return true

## True while a one-shot is still running. VisualUnit._update_animation() runs
## every frame and would otherwise stomp an attack/hurt clip back to idle on the
## very next frame — same guard the 2D sprite path gets from its non-loop check.
func is_oneshot_playing() -> bool:
	return _oneshot_active

## Length of a clip in seconds, for callers that need to time a tween to it.
func animation_length(name: String) -> float:
	return _anim.get_animation(_clip(name)).length if has_animation(name) else 0.0

func _on_anim_finished(name: String) -> void:
	_oneshot_active = false
	_anim.speed_scale = 1.0
	animation_finished.emit(name)
	if _queued_after_oneshot != "":
		var next := _queued_after_oneshot
		_queued_after_oneshot = ""
		play(next)

func set_speed_scale(v: float) -> void:
	if _anim:
		_anim.speed_scale = v

## Turn the character to face left or right. Rotating the model beats flipping
## the sprite: a flip would mirror the lighting and read as a different pose.
##
## Yaw off dead-on-camera. Mirrored for facing, never a full 180° (that would
## show the model's back) and never a sprite flip (that mirrors the lighting).
##
## DEFAULT 0, for the same reason as camera_pitch_deg: the 2D roster all faces
## the viewer square-on, so a 3/4-turned character reads as belonging to a
## different game. Raise it only if the whole roster turns with it.
var base_yaw_deg: float = 0.0

func set_facing_right(v: bool) -> void:
	facing_right = v
	_pivot.rotation.y = deg_to_rad(base_yaw_deg if v else -base_yaw_deg)

## Turn the character to actually face an arbitrary on-screen direction —
## movement, or the target of an attack — instead of the left/right mirror
## set_facing_right does. This is the real version of the "he TURNS instead of
## switching sprite sheets" idea the 2D-vs-3D animation picker was already
## commented as assuming; until this existed base_yaw_deg's default of 0 meant
## the model never actually turned at all; it just stood square to the camera
## always (user report 2026-09-06: "he runs north for everything").
##
## `_frame_camera` puts the camera at local +Z looking toward -Z, so yaw 0
## (the model's own rest orientation) already faces the camera — i.e. screen
## SOUTH (dir.y > 0, toward the viewer, matching the 2D roster's own
## north/south/east/west convention in VisualUnit). Given a target forward
## direction (dx, dz) in that same world XZ-plane, Rodrigues' rotation formula
## for a yaw of θ around +Y sends the rest-forward (0,0,1) to (sinθ, 0, cosθ) —
## so θ = atan2(dx, dz) is the yaw that makes the model face (dx, 0, dz).
## Screen dx maps straight to world +X (east) and screen dy maps straight to
## world +Z (south) with no extra sign flip, because the camera's own local
## +X/+Z were never rotated away from world +X/+Z (only pitched around X).
## Correction for a clip whose AUTHORED pose doesn't stand square to camera —
## degrees added on top of the calculated yaw. face_direction() assumes every
## clip's body is neutral/square at yaw 0 (true for walk/idle on every
## character converted so far), but a bladed stance (a sniper aiming, say)
## has the shoulders/hips rotated relative to the actual aim line even in its
## OWN rest state — measured on Headhunter: the hip bone's own orientation
## differs between `walk` and `aim`/`attack` by a real, clip-specific amount,
## not just whatever face_direction() calculates. Keyed by clip name; a clip
## not listed gets 0 (no correction). Set per-character in VisualUnit.
var clip_yaw_bias_deg: Dictionary = {}
var _yaw_bias_deg: float = 0.0   ## refreshed by play() from clip_yaw_bias_deg

func face_direction(dir: Vector2) -> void:
	if dir.length() < 0.01:
		return
	facing_right = dir.x >= 0.0
	var d := dir.normalized()
	_pivot.rotation.y = atan2(d.x, d.y) + deg_to_rad(_yaw_bias_deg)

## Stop rendering (dead / off-screen units) — the sprite keeps its last frame.
func set_paused(v: bool) -> void:
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_DISABLED if v else SubViewport.UPDATE_ALWAYS)
	if _anim:
		_anim.speed_scale = 0.0 if v else 1.0

func modulate_sprite(c: Color) -> void:
	if _sprite:
		_sprite.modulate = c

## Where a bone of the 3D character is on the 2D canvas, in GLOBAL canvas
## coordinates. For effects that must attach to the body exactly — Bouncer's
## drawn rubber arm leaves from his real shoulder, wherever the clip has put it.
## Follows the sprite's offsets/scale (bob, lunge, toss) because it goes
## through the Sprite2D's own transform.
var _skel_cache: Skeleton3D = null
func bone_canvas_position(bone_name: String) -> Vector2:
	if _skel_cache == null:
		_skel_cache = _find(_model, "Skeleton3D") as Skeleton3D
	if _skel_cache == null or _camera == null or _sprite == null:
		return global_position
	var idx := _skel_cache.find_bone(bone_name)
	if idx < 0:
		return global_position
	var world: Vector3 = (_skel_cache.global_transform * _skel_cache.get_bone_global_pose(idx)).origin
	var px: Vector2 = _camera.unproject_position(world)
	return _sprite.to_global(px - Vector2(render_size) * 0.5)

func get_sprite() -> Sprite2D:
	return _sprite

func get_animation_list() -> PackedStringArray:
	return _anim.get_animation_list() if _anim else PackedStringArray()

# ── helpers ──────────────────────────────────────────────────────────────────

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

func _find_by_name(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var r := _find_by_name(c, name)
		if r:
			return r
	return null

## Real world-space bounds of a rigged character.
##
## MeshInstance3D.get_aabb() on a SKINNED mesh returns the bind-pose bounds in
## the mesh's own space and ignores everything the skeleton does to it — for the
## Meshy exports that reads as a 0.017-unit-tall character while the rig renders
## it at ~1.7, which framed the camera inside the model's shoulder. Bone global
## poses are the only thing that reflects the actual rig, so measure those and
## pad for the mesh that hangs off them (head crown, feet, gloves).
static func character_bounds(root: Node, pad: float = 0.14) -> AABB:
	var skel: Skeleton3D = null
	for n in _walk(root):
		if n is Skeleton3D:
			skel = n
			break
	if skel and skel.get_bone_count() > 0:
		var acc := AABB()
		for i in skel.get_bone_count():
			var p: Vector3 = (skel.global_transform * skel.get_bone_global_pose(i)).origin
			acc = AABB(p, Vector3.ZERO) if i == 0 else acc.expand(p)
		var grow: float = maxf(acc.size.y, 0.001) * pad
		return acc.grow(grow)
	# Unrigged prop — the plain mesh AABB is correct for those.
	var mb := AABB()
	var first := true
	for m in _walk(root):
		if m is MeshInstance3D:
			var b: AABB = m.global_transform * m.get_aabb()
			mb = b if first else mb.merge(b)
			first = false
	return mb

## Union of bone bounds across an entire clip, sampled at several times — for
## a camera-framing decision that needs the WORST case a clip ever reaches,
## not just its rest/first frame. Leaves the AnimationPlayer sitting at
## whatever frame it lands on last; callers that care about the player's
## state afterward (nothing here currently does — this only runs during
## _frame_camera(), before setup() calls play("idle")) should reset it.
func _clip_bounds(clip: String, samples: int = 12) -> AABB:
	var skel := _find(_model, "Skeleton3D") as Skeleton3D
	if not (skel and _anim and _anim.has_animation(clip)):
		return AABB()
	var length: float = _anim.get_animation(clip).length
	_anim.current_animation = clip   # seek() operates on current_animation
	var acc := AABB()
	var first := true
	for i in samples + 1:
		_anim.seek(length * float(i) / float(samples), true)
		for b in skel.get_bone_count():
			var p: Vector3 = (skel.global_transform * skel.get_bone_global_pose(b)).origin
			if first:
				acc = AABB(p, Vector3.ZERO)
				first = false
			else:
				acc = acc.expand(p)
	return acc

static func _walk(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
