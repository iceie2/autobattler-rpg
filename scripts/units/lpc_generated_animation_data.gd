class_name LPCGeneratedAnimData extends LPCAnimationDataBase
# Animation data matching the Universal LPC Character Generator's 6-animation output:
# spellcast (rows 0-3), thrust (4-7), walk (8-11), slash (12-15), shoot (16-19), hurt (row 20)
# Also adds a synthetic "idle" mapped to walk row 0 (standing frame).

func _init() -> void:
	resource_name = "LPCGeneratedAnimData"
	base_animation_size = 64

	available_animations = ["spellcast", "thrust", "walk", "slash", "shoot", "hurt", "idle"]

	required_spritesheets = {
		"spellcast": "single",
		"thrust":    "single",
		"walk":      "single",
		"slash":     "single",
		"shoot":     "single",
		"hurt":      "single",
		"idle":      "single",
	}

	available_directions = {
		"spellcast": {"north": 0, "west": 1, "south": 2, "east": 3},
		"thrust":    {"north": 0, "west": 1, "south": 2, "east": 3},
		"walk":      {"north": 0, "west": 1, "south": 2, "east": 3},
		"slash":     {"north": 0, "west": 1, "south": 2, "east": 3},
		"shoot":     {"north": 0, "west": 1, "south": 2, "east": 3},
		"hurt":      {"south": 0},
		"idle":      {"north": 0, "west": 1, "south": 2, "east": 3},
	}

	animation_frame_counts = {
		"spellcast": 7,
		"thrust":    8,
		"walk":      9,
		"slash":     6,
		"shoot":     13,
		"hurt":      6,
		"idle":      2,
	}

	initial_sprite_indices = {
		"spellcast": 0,
		"thrust":    0,
		"walk":      1,
		"slash":     0,
		"shoot":     0,
		"hurt":      0,
		"idle":      0,
	}

	animation_loops = {
		"spellcast": true,
		"thrust":    true,
		"walk":      true,
		"slash":     true,
		"shoot":     true,
		"hurt":      false,
		"idle":      true,
	}

	animation_speeds = {
		"spellcast": 8,
		"thrust":    8,
		"walk":      8,
		"slash":     8,
		"shoot":     8,
		"hurt":      8,
		"idle":      2,
	}

	animation_rows = {
		"spellcast": 0,
		"thrust":    4,
		"walk":      8,
		"slash":     12,
		"shoot":     16,
		"hurt":      20,
		"idle":      8,  # same row as walk — frame 0 is the standing pose
	}

	frame_sizes = {
		"spellcast": 64,
		"thrust":    64,
		"walk":      64,
		"slash":     64,
		"shoot":     64,
		"hurt":      64,
		"idle":      64,
	}

	custom_frames = {
		"walk": [1, 2, 3, 4, 5, 6, 7, 8],  # frame 0 = standing, skip it for walking
		"idle": [0, 0],                       # frame 0 of walk row = standing pose
	}
