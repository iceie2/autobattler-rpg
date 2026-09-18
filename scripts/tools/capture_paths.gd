# NOTE: intentionally no class_name — global class registration needs an editor
# import pass, which headless capture runs do not do. Call sites preload it.
extends RefCounted

## Shared output path for throwaway debug renders (VFX strips, board checks,
## A/B comparisons).
##
## These live OUTSIDE res:// on purpose: anything under res:// gets imported by
## Godot, so every one-off capture used to leave a permanent entry in .godot/
## and a stray _name.png in the project root. Capture scripts must route every
## save_png() through here — never hardcode a "res://_*.png" path.
const DIR := "res://../captures/renders/"

## Absolute path to write `name` (e.g. "june_vfx_aura.png") into.
## Creates the captures dir on first use. Safe to pass to save_png() directly,
## and safe to wrap in globalize_path() again (it is already absolute).
static func out(name: String) -> String:
	var abs_dir: String = ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	return abs_dir.path_join(name).simplify_path()
