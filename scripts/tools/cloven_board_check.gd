extends "res://scripts/tools/model3d_board_check.gd"

func _spawn_monster(type: String, x: int, y: int) -> VisualUnit:
	var u: VisualUnit = EnemyFactory.create_cloven_titan(40)
	u.set_meta("sprite_folder", type)
	u.unit_name = "Cloven Heart" if type == "cloven_heart" else "Cloven Fist"
	u.cell_size = 1
	u.position = Vector2(x, y)
	u.can_be_dragged = false
	add_child(u)
	return u
