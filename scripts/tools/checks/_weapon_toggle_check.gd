extends SceneTree
## Headless check: does the held/back weapon swap actually work.
## Run: godot --headless --script res://scripts/tools/checks/_weapon_toggle_check.gd

var _m
var _done := false

func _initialize() -> void:
	var Model3DSprite = load("res://scripts/units/model3d_sprite.gd")
	_m = Model3DSprite.new()
	_m.weapon_variants = {"aim": "Weapon_Aim", "attack": "Weapon_Attack", "walk_aim": "Weapon_Aim"}
	_m.weapon_default_node = "Weapon_Back"
	root.add_child(_m)

func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var ok: bool = _m.setup("res://assets/3d pipeline/hero/headhunter/headhunter.glb", 118.0)
	print("setup ok:", ok)
	print("weapon nodes found:", _m._weapon_nodes.keys())
	for clip in ["idle", "walk", "walk_aim", "attack", "hurt", "death", "aim"]:
		_m.play(clip, clip in ["idle","walk","aim"])
		var vis := {}
		for wn in _m._weapon_nodes:
			vis[wn] = _m._weapon_nodes[wn].visible
		print(clip, "->", vis)
	return true
