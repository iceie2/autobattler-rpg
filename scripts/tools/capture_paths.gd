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

## The board's backdrop changes every decade and cycles through these six
## (BackgroundLayer.BACKDROP_ORDER). An effect checked only on round-1 "normal"
## grass is unverified for an enemy that fights on fire or lightning, so every
## enemy capture takes its round from the CLI and files its output per biome.
const BIOMES := ["normal", "air", "water", "earth", "fire", "lightning"]

static var _biome_dir := ""

## Round to capture on: `--round=N` from the command line, else `default_round`
## (that enemy's real debut, from the enemy_biome_matrix survey). Also selects
## the biome subfolder that out() will write into.
static func cli_round(default_round: int) -> int:
	var r := default_round
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--round="):
			r = int(a.split("=")[1])
	_biome_dir = BIOMES[(r - 1) / 10 % BIOMES.size()]
	return r

static func biome_of(r: int) -> String:
	return BIOMES[(r - 1) / 10 % BIOMES.size()]

## Absolute path to write `name` (e.g. "june_vfx_aura.png") into.
## Creates the captures dir on first use. Safe to pass to save_png() directly,
## and safe to wrap in globalize_path() again (it is already absolute).
static func out(name: String) -> String:
	var abs_dir: String = ProjectSettings.globalize_path(DIR)
	if _biome_dir != "":
		abs_dir = abs_dir.path_join(_biome_dir)
	var full: String = abs_dir.path_join(name).simplify_path()
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	return full
