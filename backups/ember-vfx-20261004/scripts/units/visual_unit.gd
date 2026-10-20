extends UnitBase
class_name VisualUnit

@export var shape_size: float = 66.0
@export var outline_width: float = 3.0

# Sprite scale-up — LPC character art sits inside a 64px frame with wide
# transparent margins, so we enlarge it to fill the 80px grid cell properly.
const SPRITE_SCALE_1X := 1.5
const SPRITE_SCALE_2X := 3.0
# AI/plain sprites for 2×2 units (Hill Giant etc.) render this much taller than a
# 1-cell unit so they actually fill their 2×2 block.
const SPRITE_RENDER_H_2X_MULT := 1.9

# ── 3D hero models (2.5D switch, 2026-09-04) ─────────────────────────────────
# Checked BEFORE HERO_SPRITE_PATHS, so a hero listed here renders as a rigged
# 3D character and one that isn't keeps its existing 2D art untouched. That's
# what makes the 2D→2.5D migration incremental: the roster converts one hero at
# a time and everything else on the board is unaffected.
#
# The model itself is a Sprite2D fed by a SubViewport (see Model3DSprite), so
# every procedural layer below — bob, lunge, recoil, flash, squash, the Long
# Fall toss — composites onto it EXACTLY as it does for a flat sprite. Nothing
# in _apply_animation() needed a 3D branch.
const HERO_MODEL_PATHS: Dictionary = {
	# Bouncer v002 (2026-09-24, rework in progress): `attack` is the body half of
	# the rubber punch; the arm itself is drawn by RubberArm. bouncer.glb untouched.
	UnitBase.UnitClass.BOUNCER: "res://assets/3d pipeline/hero/bouncer/bouncer_v002.glb",
	# Bloodhound v002, 2026-09-23. Versioned candidate pending human art review;
	# bloodhound.glb (v001) is untouched. `attack` is one quick claw swipe,
	# `ult` is the Pounce (crouch, leap, land into the two overhead swipes that
	# used to be his auto-attack), the colour map is rebuilt from the raw Meshy
	# texture (v001's gamma lift had turned his brown fur grey-mauve), and the
	# eyes + maw are their own "Glow" material. Build notes:
	# assets/3d pipeline/hero/bloodhound/review/conversion_report_v002.md
	# v003 (same day, owner-approved next step): v002 + a 2 s breathing idle in
	# place of the frozen pose; starts/ends on the old pose so attack/ult entry
	# is unchanged.
	UnitBase.UnitClass.BLOODHOUND: "res://assets/3d pipeline/hero/bloodhound/bloodhound_v003.glb",
	UnitBase.UnitClass.CROSS: "res://assets/3d pipeline/hero/cross/cross_v002.glb",
	UnitBase.UnitClass.STITCH: "res://assets/3d pipeline/hero/stitch/stitch.glb",
	UnitBase.UnitClass.DOC: "res://assets/3d pipeline/hero/doc/doc_v002.glb",
	# Versioned Coal candidate: magma-rock brawler with a complete unarmed clip set.
	UnitBase.UnitClass.COAL: "res://assets/3d pipeline/hero/coal/coal_v001.glb",
	# Versioned prototype candidates pending the grouped in-game art review.
	UnitBase.UnitClass.ZOLT: "res://assets/3d pipeline/hero/zolt/zolt_v001.glb",
	UnitBase.UnitClass.JUNE: "res://assets/3d pipeline/hero/june/june_v002.glb",
	UnitBase.UnitClass.RIFT: "res://assets/3d pipeline/hero/rift/rift_v018.glb",
	# Versioned Static candidate: rigged duck electrician with a flexible live-wire prop.
	# v019 (2026-10-01) = v018 with only the texture swapped: leather/steel pushed
	# darker in Lab (review/recolor_v019.py) so the harness reads against the body.
	# v020 (same day): v019 + brawler idle (review/build_idle_v020.py) — crouch,
	# hunch, left guard up, two-dip bounce; wire fist held where v018 had it.
	UnitBase.UnitClass.STATIC: "res://assets/3d pipeline/hero/static/static_v020.glb",
	# Versioned candidate remains reversible until the human art review promotes it.
	UnitBase.UnitClass.SHEILDOR: "res://assets/3d pipeline/hero/sheildor/sheildor_v043.glb",
	# Riot, rebuilt 2026-09-18 as an anthropomorphic pig riot officer (was a human
	# with a spiked bat). Props are NOT in this mesh — the baton and riot shield
	# are separate and socket to weapon_r / shield_l, so until those land he
	# renders empty-handed.
	UnitBase.UnitClass.RIOT: "res://assets/3d pipeline/hero/riot/riot.glb",
	# Vail, 2026-09-19. Versioned candidate pending human art review. Her 2D
	# portrait ends in a legless tornado, which the fixed 24-bone Meshy biped
	# cannot rig, so the coil became an ankle-length wrap gown wide enough to
	# hold legs. She carries nothing — no sockets, no props.
	# v002: material-only polish; reduced body emission reveals the pale folds.
	UnitBase.UnitClass.VAIL: "res://assets/3d pipeline/hero/vail/vail_v002.glb",
	# Reed, 2026-09-19. Versioned candidate pending human art review. An
	# anthropomorphic frog whose head is ~29% of his height, which put his
	# shoulders 11 points lower than a human's and made every retargeted library
	# action land his hands on top of his head. Corrected in-place with
	# tools/model3d/retarget_arms.py (k=0.4), not by regenerating the body.
	UnitBase.UnitClass.REED: "res://assets/3d pipeline/hero/reed/reed_v001.glb",
	# Lumen, 2026-09-19. Versioned candidate pending human art review. REDESIGNED
	# rather than converted: his 2D portrait is a hooded human mage in a
	# floor-length iridescent robe, which fails this rig three ways at once (no
	# hood bones, no cloth bones, and floating crystal shards cannot be rigged)
	# and is near-white, the exact value that made Vail vanish into the air
	# board. He is now a HOLLOW SUIT of blackened iron animated by the violet
	# arc caged in its chest — near-black mass plus bright emissive seams, so
	# some part of the silhouette separates from a board at any luminance.
	# Knee-length rigid tassets instead of a gown: every clip scores 1.19-1.46x
	# on skirt_stress (Vail's gown hit 3.16x on this same run cycle). He carries
	# nothing — no sockets, no props.
	# v002: native PBR armor and selective violet emission; rig/clips unchanged.
	UnitBase.UnitClass.LUMEN: "res://assets/3d pipeline/hero/lumen/lumen_v002.glb",
	# Lordee, 2026-09-20. Versioned candidate pending human art review. REDESIGNED
	# rather than converted, on the owner's call: his 2D portrait is an ordinary
	# human pirate with a sword, which does not carry a kit whose ult blinks in
	# and permanently STEALS 7% of a target's ATK. He is now a HOLLOW SUIT of
	# pirate clothes — tricorn, crimson coat, boots — worn by nothing, with a
	# violet soul-void inside showing as rim light at the collar and cuffs and
	# two bright points under the hat brim. Deliberately NOT a hooded skeleton
	# with soul flames: that is Necro's silhouette already.
	# He carries a cutlass, bound 100% to weapon_r under RightHand.
	UnitBase.UnitClass.LORDEE: "res://assets/3d pipeline/hero/lordee/lordee_v001.glb",
	# Sear / Spore / Pastor, 2026-10-01. Versioned candidates pending human art
	# review, built as one batch on the last of an expiring credit pot (105 of
	# 112 spent). All three carry SYNTHESIZED idles (freeze_pose.py from the
	# tightest-stance frame of their walk cycle) — the engine adds a procedural
	# bob + breathe over every clip, so a frozen idle is not static on the board.
	# None of them holds anything: no sockets, no props.
	UnitBase.UnitClass.SEAR: "res://assets/3d pipeline/hero/sear/sear_v001.glb",
	# Spore is a REDESIGN: his 2D art is a hooded figure whose robe ends in root
	# tendrils with no feet, which the fixed 24-bone rig cannot represent. He is
	# now a solid bark-and-moss creature standing on two real root legs, with the
	# mushroom cap worn as a helmet. He is also the only one of the three with no
	# cloth — but his layered leg plates still skin to the legs and still tear,
	# which is why his run was dropped for the walk cycle (3.36x -> 2.28x).
	UnitBase.UnitClass.SPORE: "res://assets/3d pipeline/hero/spore/spore_v001.glb",
	# Ember (2026-10-04) is a REDESIGN under the elemental rule: a small fire
	# sprite whose body is solid molten glass, flame crest instead of hair, no
	# cloth at all (her 2D split skirt would have torn on every archery stance).
	# Bow is a make_prop.py primitive bound to LeftHand at full draw.
	UnitBase.UnitClass.EMBER: "res://assets/3d pipeline/hero/ember/ember_v001.glb",
	# Pastor's joke is that he is a DEVIL dressed as an ordinary preacher — black
	# cassock, white dog collar, spectacles — so the horns and cloven hooves are
	# the only things out of place. The first concept came back in a runed cult
	# robe, which killed the gag; runes/sigils/rope belts are banned in his prompt.
	UnitBase.UnitClass.PASTOR: "res://assets/3d pipeline/hero/pastor/pastor_v001.glb",
}
# On-screen pixel heights for 1-cell 3D units. Enemy models retain the older
# board scale; 3D heroes use the reviewed PBR presentation size.
const MODEL_RENDER_H := 115.0
const HERO_MODEL_RENDER_H := 140.0
# Downward camera tilt for every 3D hero, so they visually sit IN the board's
# tabletop-perspective look instead of standing perfectly frontal to it (the
# board itself fakes a downward-looking angle via BoardPerspective's trapezoid
# shape — there's no real shared camera connecting the two, so this is a
# shape). NO LONGER hand-picked: it reads BoardPerspective.PITCH_DEG, the one
# angle the board's taper is also derived from, so the two cannot drift apart.
# User call 2026-09-06: tilt/zoom tabletop feel, no rotation, no panning; 2026-
# 09-08: full roster is going 3D, so the view commits to the tabletop angle
# (28°) even though most of the roster is still frontal 2D art in the meantime.
const MODEL_CAMERA_PITCH_DEG := BoardPerspective.PITCH_DEG
# Heroes whose attack reaches out past their own idle silhouette — widens the
# render viewport (Model3DSprite.stretch_arm) so the reach doesn't clip
# against a frame sized for the idle pose. This does NOT enable the old
# runtime stretch bake (Model3DSprite.runtime_bake_stretch, separate and off
# by default) — Bouncer's actual reach is authored directly into bouncer.glb's
# `attack` clip (tools/model3d/add_stretch_punch.py). He was pulled off this
# list entirely on 2026-09-06 to kill that old bake (it targeted
# RightArm/RightForeArm while his real punching arm is Left, so it was
# stretching his static guard arm on top of the correct left-arm stretch) —
# but that also removed the frame widening, which the baked stretch still
# needs regardless of who computes it. Re-added right after, viewport-only.
const STRETCH_ARM_HEROES: Array = [UnitBase.UnitClass.BOUNCER, UnitBase.UnitClass.STATIC]

# AI-generated hero sprites (static Sprite2D, bypasses LPC system)
const HERO_SPRITE_PATHS: Dictionary = {
	UnitBase.UnitClass.NEMI:       "res://assets/using/nemi.png",
	UnitBase.UnitClass.BLOODHOUND: "res://assets/using/bloodhound.png",
	UnitBase.UnitClass.BOUNCER:    "res://assets/using/bouncer.png",
	UnitBase.UnitClass.HEADHUNTER: "res://assets/using/headhunter.png",
	UnitBase.UnitClass.SHAUNA:     "res://assets/using/shauna.png",
	UnitBase.UnitClass.RUSH:       "res://assets/using/rush.png",
	UnitBase.UnitClass.SABLE:      "res://assets/using/sable.png",
	UnitBase.UnitClass.STITCH:     "res://assets/using/stitch.png",
	UnitBase.UnitClass.EMBER:      "res://assets/using/ember.png",
	UnitBase.UnitClass.RIFT:       "res://assets/using/rift.png",
	UnitBase.UnitClass.ZOLT:       "res://assets/using/zolt.png",
	UnitBase.UnitClass.LUMEN:      "res://assets/using/lumen.png",
	UnitBase.UnitClass.STATIC:     "res://assets/using/static.png",
	UnitBase.UnitClass.SPORE:      "res://assets/using/spore.png",
	UnitBase.UnitClass.CROSS:      "res://assets/using/cross.png",
	UnitBase.UnitClass.SEAR:       "res://assets/using/sear.png",
	UnitBase.UnitClass.DOC:        "res://assets/using/doc.png",
	UnitBase.UnitClass.RIOT:       "res://assets/using/riot.png",
	UnitBase.UnitClass.PASTOR:     "res://assets/using/pastor.png",
	UnitBase.UnitClass.SHEILDOR:   "res://assets/using/sheildor.png",
	UnitBase.UnitClass.LORDEE:     "res://assets/using/lordee.png",
	UnitBase.UnitClass.VAIL:       "res://assets/using/vail.png",
	UnitBase.UnitClass.COAL:       "res://assets/using/coal.png",
	UnitBase.UnitClass.JUNE:       "res://assets/using/june.png",
	UnitBase.UnitClass.REED:       "res://assets/using/reed.png",
	UnitBase.UnitClass.NECRO:      "res://assets/using/necro.png",
}

# 3D models for monsters, keyed by sprite_folder the same way the sprites are.
#
# Enemies cannot use HERO_MODEL_PATHS: a hero is identified by UnitClass, but a
# monster's identity is a sprite_folder STRING set as meta by enemy_factory, and
# several monsters share one UnitClass. So this is a parallel table on the same
# key the sprite lookup already uses.
#
# ONE MESH, MANY UNITS. goblin and goblin_archer are the same goblin carrying
# different gear, so they share a single .glb and differ only in which prop
# nodes are shown (MONSTER_MODEL_PROPS) and which attack clip they play. That is
# the whole economic case for converting enemies: the second variant costs
# nothing beyond its own attack motion.
const MONSTER_MODEL_PATHS: Dictionary = {
	# v010 (2026-09-24): goblin.glb + a re-authored `attack_bow` (v009's Meshy
	# clip aimed 137 deg off target, never drew, held the bow like a stick; kept
	# as `attack_bow_meshy_v009`). Every other clip is unchanged. Both variants
	# MUST point at the same file: each hides the other's props only via this
	# shared path (split paths showed the archer holding the melee knife).
	"goblin":        "res://assets/3d pipeline/enemy/goblin/goblin_v010.glb",
	"goblin_archer": "res://assets/3d pipeline/enemy/goblin/goblin_v010.glb",
	# Elites/bosses, 2026-10-02 overnight batch — candidates pending owner art
	# review. Delete a line to fall back to the 2D sprite.
	"hill_giant":    "res://assets/3d pipeline/enemy/hill_giant/hill_giant_v001.glb",
	# ⚠ skill + hurt tear the flank (arms were generated fused to the body);
	# low-arm replacement clips pending owner OK.
	"tidecaller":    "res://assets/3d pipeline/enemy/tidecaller/tidecaller_v001.glb",
	# Non-bipeds: Meshy body + custom rig/clips (tools/model3d/creature_rig.py).
	"gale_warden":   "res://assets/3d pipeline/enemy/gale_warden/gale_warden_v001.glb",
	"skyrender":     "res://assets/3d pipeline/enemy/skyrender/skyrender_v002.glb",   # v002: spread-wing body, own wing rig (2026-10-04)
	"drowned_maw":   "res://assets/3d pipeline/enemy/drowned_maw/drowned_maw_v003.glb",
	# Khagan (wave 10): phase 1 = the octopus riding its crab (2x2), phase 2 =
	# the octopus alone (1x1, also clings to the possessed hero in phase 3).
	"khagan_phase1": "res://assets/3d pipeline/enemy/khagan_phase1/khagan_phase1_v003.glb",   # v003: new body, rider's arms modelled wrapped round the crab (2026-10-03)
	"khagan_phase2": "res://assets/3d pipeline/enemy/khagan_phase2/khagan_phase2_v001.glb",
	# Batch 2 (2026-10-03): Meshy bipeds with GRAFTED clips (tools/model3d/assemble_biped.py).
	"terracotta_colossus": "res://assets/3d pipeline/enemy/terracotta_colossus/terracotta_colossus_v001.glb",
	"cloven_titan": "res://assets/3d pipeline/enemy/cloven_titan/cloven_titan_v001.glb",
	"cloven_fist": "res://assets/3d pipeline/enemy/cloven_fist/cloven_fist_v001.glb",
	"cloven_heart": "res://assets/3d pipeline/enemy/cloven_heart/cloven_heart_v001.glb",
	"magma_heart": "res://assets/3d pipeline/enemy/magma_heart/magma_heart_v001.glb",
	"emberhollow": "res://assets/3d pipeline/enemy/emberhollow/emberhollow_v001.glb",
	"stat_stealer": "res://assets/3d pipeline/enemy/stat_stealer/stat_stealer_v001.glb",
	"gravekeeper": "res://assets/3d pipeline/enemy/gravekeeper/gravekeeper_v001.glb",
	"the_architect": "res://assets/3d pipeline/enemy/the_architect/the_architect_v001.glb",
	# Batch 2 non-bipeds: Meshy body (ant_hill: procedural, tools/model3d/make_ant_hill.py)
	# + custom rig/clips (creature_rig.py --kind serpent/quad/insect/static).
	"tempest_conduit": "res://assets/3d pipeline/enemy/tempest_conduit/tempest_conduit_v001.glb",
	"arcfang": "res://assets/3d pipeline/enemy/arcfang/arcfang_v001.glb",
	"aspect_devourer": "res://assets/3d pipeline/enemy/aspect_devourer/aspect_devourer_v001.glb",
	"mirrorplate_warden": "res://assets/3d pipeline/enemy/mirrorplate_warden/mirrorplate_warden_v001.glb",
	"ant": "res://assets/3d pipeline/enemy/ant/ant_v001.glb",
	"ant_hill": "res://assets/3d pipeline/enemy/ant_hill/ant_hill_v001.glb",
	"ember_heart": "res://assets/3d pipeline/enemy/ember_heart/ember_heart_v001.glb",
	# Hydra (wave 80, player-chosen element): one body per element, `--kind hydra`.
	"hydra_normal": "res://assets/3d pipeline/enemy/hydra_normal/hydra_normal_v001.glb",
	"hydra_fire": "res://assets/3d pipeline/enemy/hydra_fire/hydra_fire_v001.glb",
	"hydra_water": "res://assets/3d pipeline/enemy/hydra_water/hydra_water_v001.glb",
	"hydra_earth": "res://assets/3d pipeline/enemy/hydra_earth/hydra_earth_v001.glb",
	"hydra_air": "res://assets/3d pipeline/enemy/hydra_air/hydra_air_v001.glb",
	"hydra_lightning": "res://assets/3d pipeline/enemy/hydra_lightning/hydra_lightning_v001.glb",
	# The Triarch (wave 70): one champion shedding layers -- Knight (greatsword),
	# Hunter (bow), Arcane Core (floating crown). Swapped per phase by sprite_folder.
	"triarch_phase1": "res://assets/3d pipeline/enemy/triarch_phase1/triarch_phase1_v001.glb",
	"triarch_phase2": "res://assets/3d pipeline/enemy/triarch_phase2/triarch_phase2_v001.glb",
	"triarch_phase3": "res://assets/3d pipeline/enemy/triarch_phase3/triarch_phase3_v001.glb",
}

# Which socketed props each monster variant shows, and any clip renames it
# needs. `clips` maps the engine's clip name to the one in the .glb, so the
# archer's "attack" resolves to the bow draw while the melee goblin's resolves
# to the knife slash -- both live in the shared file.
const MONSTER_MODEL_PROPS: Dictionary = {
	# Goblins on the hero presentation (graphics audit 2026-10-02): the 128px
	# nearest toon render was the one enemy still stair-stepped next to smooth
	# PBR heroes. Material_1 imports metallic=1.0 (glTF default, no metallic
	# texture), which renders it dark/pale with no diffuse -- matte it.
	"goblin":        {"props": ["Knife_Held"], "clips": {}, "pbr": true,
					  "pbr_overrides": {"Material_1": {"metallic": 0.0, "roughness": 0.85}}},
	"goblin_archer": {"props": ["Bow_Held", "Quiver_Back"],
					  "clips": {"attack": "attack_bow"}, "pbr": true,
					  "pbr_overrides": {"Material_1": {"metallic": 0.0, "roughness": 0.85}}},
	# Charged_Ground_Slam is NAME_MAPped to "ult" (Cross); the giant plays it as
	# his Smash skill.
	"hill_giant":    {"props": ["Club_Held"], "clips": {"skill": "ult"}, "pbr": true},
	"tidecaller":    {"props": [], "clips": {}, "pbr": true},
	"gale_warden":   {"props": [], "clips": {}, "pbr": true},
	# Skyrender's "fly" loop plays while `skyrender_aloft` is set (_update_model3d_animation).
	# v002 spread wings: sized by height, the span left the body tiny on its 2x2
	# -- scaled up, and the frame grown so the wingtips aren't cut off.
	"skyrender":     {"props": [], "clips": {}, "pbr": true, "scale": 1.6, "frame_grow": 1.8},
	"drowned_maw":   {"props": [], "clips": {}, "pbr": true},
	"khagan_phase1": {"props": [], "clips": {}, "pbr": true},
	"khagan_phase2": {"props": [], "clips": {}, "pbr": true},
	"terracotta_colossus": {"props": [], "clips": {"skill": "ult"}, "pbr": true},
	"cloven_titan": {"props": [], "clips": {"skill": "ult"}, "pbr": true},
	"cloven_fist": {"props": [], "clips": {"skill": "ult"}, "pbr": true},
	"cloven_heart": {"props": [], "clips": {}, "pbr": true, "scale": 0.85},
	"magma_heart": {"props": [], "clips": {"skill": "ult"}, "pbr": true},
	"emberhollow": {"props": [], "clips": {"skill": "ult"}, "pbr": true},
	"stat_stealer": {"props": [], "clips": {}, "pbr": true},
	"gravekeeper": {"props": ["Shovel_Held"], "clips": {"skill": "ult"}, "pbr": true},
	"the_architect": {"props": [], "clips": {"skill": "ult"}, "pbr": true},
	"tempest_conduit": {"props": [], "clips": {}, "pbr": true, "scale": 1.5},
	"arcfang": {"props": [], "clips": {}, "pbr": true},
	"aspect_devourer": {"props": [], "clips": {}, "pbr": true, "scale": 0.62},
	"mirrorplate_warden": {"props": [], "clips": {}, "pbr": true, "scale": 0.7},
	"ant": {"props": [], "clips": {}, "pbr": true},
	"ant_hill": {"props": [], "clips": {}, "pbr": true, "scale": 0.36, "frame_grow": 2.4},
	"ember_heart": {"props": [], "clips": {}, "pbr": true},
	"hydra_normal": {"props": [], "clips": {}, "pbr": true},
	"hydra_fire": {"props": [], "clips": {}, "pbr": true},
	"hydra_water": {"props": [], "clips": {}, "pbr": true},
	"hydra_earth": {"props": [], "clips": {}, "pbr": true},
	"hydra_air": {"props": [], "clips": {}, "pbr": true},
	"hydra_lightning": {"props": [], "clips": {}, "pbr": true},
	"triarch_phase1": {"props": ["Sword_Held"], "clips": {"skill": "ult"}, "pbr": true, "scale": 1.4},
	# The volley clip's off-hand pose turned the bow edge-on, so the skill reuses
	# the clean draw-and-loose; Piercing Volley's VFX carries the difference.
	"triarch_phase2": {"props": ["Bow_Held"], "clips": {"attack": "archery_shot_2", "skill": "archery_shot_2"}, "pbr": true, "scale": 1.4},
	"triarch_phase3": {"props": [], "clips": {}, "pbr": true, "scale": 1.4},
}

# AI-generated monster sprites keyed by sprite_folder string
const MONSTER_SPRITE_PATHS: Dictionary = {
	"goblin":        "res://assets/using/enemies/normal/goblin.png",
	"goblin_archer": "res://assets/using/enemies/normal/goblin_archer.png",
	# Goblin Shaman — 6 elemental variants (2026-07-09).
	"goblin_shaman_normal":     "res://assets/using/enemies/normal/all element mobs/goblin_shaman/goblin_shaman_normal.png",
	"goblin_shaman_fire":       "res://assets/using/enemies/normal/all element mobs/goblin_shaman/goblin_shaman_fire.png",
	"goblin_shaman_water":      "res://assets/using/enemies/normal/all element mobs/goblin_shaman/goblin_shaman_water.png",
	"goblin_shaman_earth":      "res://assets/using/enemies/normal/all element mobs/goblin_shaman/goblin_shaman_earth.png",
	"goblin_shaman_air":        "res://assets/using/enemies/normal/all element mobs/goblin_shaman/goblin_shaman_air.png",
	"goblin_shaman_lightning":  "res://assets/using/enemies/normal/all element mobs/goblin_shaman/goblin_shaman_lightning.png",
	"skeleton":      "res://assets/using/enemies/normal/skeleton.png",
	"rat":           "res://assets/using/enemies/normal/rat.png",
	# ── Elite tier — all elite art lives in assets/using/enemies/elite/ ─────────
	# Consolidated there 2026-07-28 (hill_giant/ant/ant_hill/stat_stealer moved up
	# from the flat using/ dir to join the 7 new elemental elites).
	#
	# ⚠️ These paths MUST stay valid or ANIMATION breaks, not just the still art:
	# _setup_lpc_sprite() gates the animated-sprite loader behind
	# ResourceLoader.exists(mpath) — a dead path here silently falls through to the
	# generic warrior LPC sheet, so a unit with a full frame set (hill_giant has
	# walk x4 + idle + attack in assets/sprites/monsters/hill_giant/) would lose it
	# with no error. The frames themselves are keyed by FOLDER NAME, not by this
	# path, so they never move — but they're only reached if this resolves.
	"hill_giant":    "res://assets/using/enemies/elite/hill_giant.png",
	# Elemental elites (2026-07-27, art landed 2026-07-28).
	"gale_warden":   "res://assets/using/enemies/elite/gale_warden.png",
	"tidecaller":    "res://assets/using/enemies/elite/tidecaller.png",
	"terracotta_colossus": "res://assets/using/enemies/elite/terracotta_colossus.png",
	"magma_heart":   "res://assets/using/enemies/elite/magma_heart.png",
	"tempest_conduit": "res://assets/using/enemies/elite/tempest_conduit.png",
	"mirrorplate_warden": "res://assets/using/enemies/elite/mirrorplate_warden.png",
	"aspect_devourer": "res://assets/using/enemies/elite/aspect_devourer.png",
	# ── Decade bosses (2026-07-28) — art lives in assets/using/enemies/boss/ ────
	# Khagan and the Hydra are NOT here: they were already wired to
	# assets/using/*.png further down this dict and have been rendering fine all
	# along (the copies under enemies/boss/Chubulu/ and pick_element/ are just the
	# kept originals). Only skyrender is coded so far — the other seven are
	# registered ahead of their factories so the art is live the moment each
	# boss's create_* lands and sets the matching sprite_folder meta.
	# Same dead-path caveat as the elite block above: a typo here fails SILENTLY
	# (falls through to the generic warrior LPC), so verify by rendering.
	"skyrender":     "res://assets/using/enemies/boss/skyrender.png",
	"drowned_maw":   "res://assets/using/enemies/boss/drowned_maw.png",
	"cloven_titan":  "res://assets/using/enemies/boss/cloven_titan.png",
	"emberhollow":   "res://assets/using/enemies/boss/emberhollow.png",
	"ember_heart":   "res://assets/using/enemies/boss/ember_heart.png",
	"arcfang":       "res://assets/using/enemies/boss/arcfang.png",
	"gravekeeper":   "res://assets/using/enemies/boss/gravekeeper.png",
	"the_architect": "res://assets/using/enemies/boss/the_architect.png",
	# Orc + Slime — 6 elemental variants each, one sprite per Element enum value.
	"orc_normal":     "res://assets/using/enemies/normal/all element mobs/orc/orc_normal.png",
	"orc_fire":       "res://assets/using/enemies/normal/all element mobs/orc/orc_fire.png",
	"orc_water":      "res://assets/using/enemies/normal/all element mobs/orc/orc_water.png",
	"orc_earth":      "res://assets/using/enemies/normal/all element mobs/orc/orc_earth.png",
	"orc_air":        "res://assets/using/enemies/normal/all element mobs/orc/orc_air.png",
	"orc_lightning":  "res://assets/using/enemies/normal/all element mobs/orc/orc_lightning.png",
	"slime_normal":     "res://assets/using/enemies/normal/all element mobs/slime/slime_normal.png",
	"slime_fire":       "res://assets/using/enemies/normal/all element mobs/slime/slime_fire.png",
	"slime_water":      "res://assets/using/enemies/normal/all element mobs/slime/slime_water.png",
	"slime_earth":      "res://assets/using/enemies/normal/all element mobs/slime/slime_earth.png",
	"slime_air":        "res://assets/using/enemies/normal/all element mobs/slime/slime_air.png",
	"slime_lightning":  "res://assets/using/enemies/normal/all element mobs/slime/slime_lightning.png",
	# Lizard — 6 elemental variants (2026-07-06), far-range sniper mob.
	"lizard_normal":     "res://assets/using/enemies/normal/all element mobs/lizard/lizard_normal.png",
	"lizard_fire":       "res://assets/using/enemies/normal/all element mobs/lizard/lizard_fire.png",
	"lizard_water":      "res://assets/using/enemies/normal/all element mobs/lizard/lizard_water.png",
	"lizard_earth":      "res://assets/using/enemies/normal/all element mobs/lizard/lizard_earth.png",
	"lizard_air":        "res://assets/using/enemies/normal/all element mobs/lizard/lizard_air.png",
	"lizard_lightning":  "res://assets/using/enemies/normal/all element mobs/lizard/lizard_lightning.png",
	# Bear — 6 elemental variants (2026-07-06), beefy melee tank.
	"bear_normal":     "res://assets/using/enemies/normal/all element mobs/bear/bear_normal.png",
	"bear_fire":       "res://assets/using/enemies/normal/all element mobs/bear/bear_fire.png",
	"bear_water":      "res://assets/using/enemies/normal/all element mobs/bear/bear_water.png",
	"bear_earth":      "res://assets/using/enemies/normal/all element mobs/bear/bear_earth.png",
	"bear_air":        "res://assets/using/enemies/normal/all element mobs/bear/bear_air.png",
	"bear_lightning":  "res://assets/using/enemies/normal/all element mobs/bear/bear_lightning.png",
	# Troll — 6 elemental variants (2026-07-06), ranged attack-speed support.
	"troll_normal":     "res://assets/using/enemies/normal/all element mobs/troll/troll_normal.png",
	"troll_fire":       "res://assets/using/enemies/normal/all element mobs/troll/troll_fire.png",
	"troll_water":      "res://assets/using/enemies/normal/all element mobs/troll/troll_water.png",
	"troll_earth":      "res://assets/using/enemies/normal/all element mobs/troll/troll_earth.png",
	"troll_air":        "res://assets/using/enemies/normal/all element mobs/troll/troll_air.png",
	"troll_lightning":  "res://assets/using/enemies/normal/all element mobs/troll/troll_lightning.png",
	# Wind-Up Bot — 6 elemental variants (2026-07-07), light melee striker.
	"windup_bot_normal":     "res://assets/using/enemies/normal/all element mobs/windup_bot/windup_bot_normal.png",
	"windup_bot_fire":       "res://assets/using/enemies/normal/all element mobs/windup_bot/windup_bot_fire.png",
	"windup_bot_water":      "res://assets/using/enemies/normal/all element mobs/windup_bot/windup_bot_water.png",
	"windup_bot_earth":      "res://assets/using/enemies/normal/all element mobs/windup_bot/windup_bot_earth.png",
	"windup_bot_air":        "res://assets/using/enemies/normal/all element mobs/windup_bot/windup_bot_air.png",
	"windup_bot_lightning":  "res://assets/using/enemies/normal/all element mobs/windup_bot/windup_bot_lightning.png",
	"zombie_minion": "res://assets/using/enemies/normal/zombie_minion.png",
	"bat_minion":    "res://assets/using/enemies/normal/bat_minion.png",
	"ant":           "res://assets/using/enemies/elite/ant.png",
	"ant_hill":      "res://assets/using/enemies/elite/ant_hill.png",
	"stat_stealer":  "res://assets/using/enemies/elite/stat_stealer.png",
	# Khagan — boss, 2 body phases (phase 3 is a positioning trick, see below).
	"khagan_phase1": "res://assets/using/enemies/normal/khagan_phase1.png",
	"khagan_phase2": "res://assets/using/enemies/normal/khagan_phase2.png",
	# Hydra — wave-30 final boss, 6 elemental variants (player picks which one fights).
	"hydra_normal":     "res://assets/using/enemies/normal/all element mobs/hydra/hydra_normal.png",
	"hydra_fire":       "res://assets/using/enemies/normal/all element mobs/hydra/hydra_fire.png",
	"hydra_water":      "res://assets/using/enemies/normal/all element mobs/hydra/hydra_water.png",
	"hydra_earth":      "res://assets/using/enemies/normal/all element mobs/hydra/hydra_earth.png",
	"hydra_air":        "res://assets/using/enemies/normal/all element mobs/hydra/hydra_air.png",
	"hydra_lightning":  "res://assets/using/enemies/normal/all element mobs/hydra/hydra_lightning.png",
	# Beast tier (2026-07-24) — art pending, slugs match GEMINI_MONSTER_PROMPTS.md
	# so dropped Gemini art lines up directly. Falls back to the generic warrior
	# LPC sheet until the PNG exists (see ResourceLoader.exists check above).
	"ogre":        "res://assets/using/enemies/normal/ogre.png",
	"minotaur":    "res://assets/using/enemies/normal/minotaur.png",
	"gargoyle":    "res://assets/using/enemies/normal/gargoyle.png",
	"stone_golem": "res://assets/using/enemies/normal/stone_golem.png",
	# Earth-decade variety (2026-07-24, wave 31-40) — art pending, same fallback.
	"crystal_crab": "res://assets/using/enemies/normal/crystal_crab.png",
	"root_walker":  "res://assets/using/enemies/normal/root_walker.png",
	# Fire decade (2026-07-24, wave 41-50) — art pending, same fallback.
	"fire_giant":    "res://assets/using/enemies/normal/fire_giant.png",
	"hellhound":     "res://assets/using/enemies/normal/hellhound.png",
	"ember_phoenix": "res://assets/using/enemies/normal/ember_phoenix.png",
	# Lightning decade (2026-07-24, wave 51-60) — art pending, same fallback.
	"storm_giant": "res://assets/using/enemies/normal/storm_giant.png",
	"storm_crow":  "res://assets/using/enemies/normal/storm_crow.png",
	# Air/Water decade anchors (2026-08-02, wave 11-20 / 21-30) — art pending,
	# same generic-warrior fallback. Prompts already exist on the monster sheet
	# under "wyvern" and "tidepool_horror".
	"sky_wyvern":      "res://assets/using/enemies/normal/sky_wyvern.png",
	"tidepool_horror": "res://assets/using/enemies/normal/tidepool_horror.png",
	"harpy":           "res://assets/using/enemies/normal/harpy.png",
	"coral_husk":      "res://assets/using/enemies/normal/coral_husk.png",
}
# All hero sprites are normalised to this rendered height (px) regardless of source resolution.
# 166 = what 128px art looked like at the old 1.3× scale — keeps Nemi/Bloodhound unchanged.
const HERO_SPRITE_RENDER_H := 115.0
# Per-hero/monster multiplier on top of HERO_SPRITE_RENDER_H, for sprites whose
# source art reads small at the shared height (e.g. Nemi's serpent form has a
# lot of empty canvas above her). Keyed by the same sprite key used to look up
# the sheet (hero_key in _setup_lpc_sprite / folder for monsters).
const SPRITE_SCALE_OVERRIDE := {
	"nemi": 1.35,
	"headhunter": 1.2,
	# Gale Warden flock bird (2026-09-28). Its 256px frames are mostly empty
	# canvas — the idle bird fills only 58% × 53% — so at 1.0 it was ~67px in a
	# 110px cell, and the first 0.72 pass looked lost on the board (owner: "it
	# should at least fill the square"). 1.5 puts the idle body ~100px wide.
	"gale_warden": 1.5,
}
# Health-bar drop (px) for sprites whose frame canvas has empty space above the
# art, so the bar sits on the body instead of floating over it.
const HEALTH_BAR_DROP := {
	"gale_warden": 17.0,
}
var sprite_variant: int = -1  # set by factory; -1 = pick randomly in _ready

# Looping status-effect icons (small sprite sheets shown above the unit's head
# while a status timer is active). "size" is the on-screen display size in
# pixels — set it per-status so a big dramatic effect and a subtle one don't
# have to share the same scale. Add new entries here as sheets arrive, no other
# code changes needed.
# frame_w/h of 0 = single whole image (StatusIcon reads the real size off the
# texture) rather than a sprite sheet.
const STATUS_ICON_SHEETS := {
	"stun": {"path": "res://assets/using/status_icons/stunned.png", "frame_w": 32, "frame_h": 32, "frames": 3, "size": Vector2(60, 60)},
}

# Display order for status icons, so an icon never jumps sideways just because a
# different status expired. Add new keys here AND to STATUS_ICON_SHEETS.
const STATUS_ICON_ORDER := ["stun", "root", "taunt", "slow", "burn", "disease", "venom",
	"bleed", "heal_cut", "weaken", "corroded", "dread", "blind"]
const STATUS_BADGE_SIZE := 26.0
const STATUS_ICON_SPACING := 34.0

var _status_icons: Dictionary = {}   # status_key -> StatusBadge node (lazily created)
var _status_peaks: Dictionary = {}   # status_key -> longest remaining time seen (ring scale)

# Skill-cooldown badge, floated to the left of the health bar (2026-07-06 user
# request — first skill icon art in the game, "Corrosive Goo" on Slime). Lit up
# when the skill is off cooldown, dark while on cooldown, blinks briefly the
# instant it fires. Only created for units whose mob_skill has art registered
# in UnitDetailsController.SKILL_ICONS — silently absent otherwise.
const SKILL_ICON_DISPLAY_SIZE := 26.0
const SKILL_ICON_MARGIN := 8.0
const SKILL_ICON_BLINK_DURATION := 0.35   # seconds
const SKILL_ICON_READY_COLOR    := Color(1.0, 1.0, 1.0, 1.0)
const SKILL_ICON_COOLDOWN_COLOR := Color(0.32, 0.32, 0.32, 1.0)
const SKILL_ICON_BLINK_COLOR    := Color(1.4, 1.4, 1.0, 1.0)
var _skill_icon: Sprite2D = null
var _skill_icon_prev_cd: float = 0.0
var _skill_icon_blink_time: float = 0.0

# Drag and drop
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO       # local coords saved on drag start
var original_global_pos: Vector2 = Vector2.ZERO    # global coords saved on drag start
# Setter-backed so revoking drag permission ALWAYS resolves an in-flight drag
# immediately (battle start, death), instead of leaving the node stranded
# wherever the cursor was until some later input event happens to arrive.
var can_be_dragged: bool = true:
	set(value):
		can_be_dragged = value
		if not value and is_dragging:
			_cancel_drag()
var mouse_down_position: Vector2 = Vector2.ZERO
var drag_threshold: float = 5.0

# Components
var health_bar: HealthBar
var _health_bar_base_pos: Vector2 = Vector2.ZERO   # see _ready(); health_bar's resting local position before per-frame animation offsets
# Runtime bar-side flipping (2026-09-17 user request): a unit whose default bar
# side points straight into an occupied neighbouring cell draws its bar across
# that unit's sprite. _update_bar_placement() flips it to the other side when
# that side is clear. Checked on a throttle, and a candidate has to survive two
# consecutive checks before it's applied, so units shuffling past each other
# mid-combat can't make a bar strobe between sides.
const BAR_FLIP_INTERVAL := 0.2
var _bar_flip_timer: float = 0.0
var _bar_flip_pending: int = -1
var animated_sprite: AnimatedSprite2D   # LPCAnimatedSprite2D for classes, or a plain
										 # AnimatedSprite2D for generated video->sheet anims
var plain_sprite: Sprite2D   # used for AI-generated hero sprites instead of LPC
							 # ALSO points at model3d's inner Sprite2D on the 3D
							 # path, so the procedural layers apply unchanged
var model3d: Model3DSprite   # set for heroes in HERO_MODEL_PATHS; drives clips
var element_glow: Sprite2D
var held_item_badge: Sprite2D   # small weapon icon shown while an enemy wields loot

# Animation state
var fill_color: Color = Color(1, 1, 1, 1)

# ── Procedural animation (additive layers) ───────────────────────────────────
# Each behaviour writes its OWN variable; _apply_animation() composites them all
# onto the sprite every frame, so no animation ever fights another. Everything is
# applied to the sprite child (or the _draw transform) — never the unit root, which
# the battle manager owns for grid movement.
var _anim_time: float = 0.0
var _last_ult_charge_drawn: int = -1
var _anim_phase: float = 0.0                 # per-unit desync so idles don't sync up
var _base_sprite_scale: Vector2 = Vector2.ONE  # the SPRITE_SCALE set at setup
var _sprite_base_offset: Vector2 = Vector2.ZERO  # bottom-anchors plain sprites
## Unscaled half-height of the bottom-anchored sprite, in pixels. Set by the
## three setup paths that bottom-anchor (plain / 3D model / generated sheet) and
## left at 0 by the LPC path, whose frames carry their own feet placement — 0
## means "not foot-pinnable", and _foot_pinned_y() leaves that path alone.
var _sprite_half_h: float = 0.0
## Y (unit-local) the character's FEET should sit at: the near edge of the row
## it stands on. Recomputed with _depth_scale, because a far row is physically
## shorter than a near one and a flat constant would float or sink the unit
## there. Falls back to the old flat half-cell until the grid is known.
var _foot_anchor_y: float = 55.0
# Faked-perspective depth (see BoardPerspective): 1.0 on the front row, smaller
# toward the back. Multiplied into the sprite scale in _apply_animation().
var _depth_scale: float = 1.0
var _shadow: Node2D = null
var soft_contact_shadow: bool = false
static var _soft_shadow_texture: GradientTexture2D
# Per-animation correction so the character reads as the same physical size no
# matter which generated sheet (walk/idle/attack/...) is playing — each is its
# own AI-generated clip on the same 256x256 canvas, but the character isn't
# always drawn at the same scale within that canvas from clip to clip. Keyed
# by anim name, filled in _setup_generated_animated_sprite; empty (no-op) for
# units on the older static-sprite path. Applied in _apply_animation().
var _anim_scale_mult: Dictionary = {}
# sheet dir -> {anim: content height px}. Static: the measurement is a property
# of the art, so every unit sharing a sheet folder reuses the first scan.
static var _ANIM_CONTENT_H_CACHE: Dictionary = {}
# continuous (idle)
var _bob_offset: Vector2 = Vector2.ZERO
var _breathe_scale: Vector2 = Vector2.ONE
# one-shots (tweened)
var _lunge_offset: Vector2 = Vector2.ZERO    # attack
var _recoil_offset: Vector2 = Vector2.ZERO   # hit knockback
var _toss_offset: Vector2 = Vector2.ZERO     # Long Fall (Skyrender) — hurled off-screen and back
var _updraft_offset: Vector2 = Vector2.ZERO  # Vail Updraft — whirled airborne
# Skyrender aloft (2026-10-04): the body rises off the board while its Cyclone
# Ascent window is open, eased in/out in _update_model3d_animation.
const ALOFT_LIFT := 45.0   # the fly clip lifts the body too; more ran the bar off the top row
var _aloft_offset: Vector2 = Vector2.ZERO
var _shove_offset: Vector2 = Vector2.ZERO    # forced displacement: body slides from the old tile
# Rift's Tear (2026-10-01). The victim is teleported by the grid INSTANTLY; these
# two channels let the BODY fall into a portal at the old tile and drop out of one
# at the new tile, without the grid ever disagreeing with itself. Same contract as
# _shove_offset: purely visual, so it cannot desync targeting or movement.
var _portal_offset: Vector2 = Vector2.ZERO
var _portal_scale: Vector2 = Vector2.ONE
# Vail Updraft — horizontal spin, faked via a scale.x cosine wave (a real Z
# rotation would tumble the sprite head-over-heels like a clock hand; this
# reads as spinning around the vertical axis instead — squash to edge-on,
# flip to backward-facing, squash again, flip back). Driven per-frame in
# _process rather than a tween, since tween_method only lerps between two
# fixed values and can't express an oscillating function of elapsed time.
var _updraft_spin_x: float = 1.0
var _updraft_spin_active: bool = false
var _updraft_spin_t0: float = 0.0
var _updraft_spin_dur: float = 0.0
const UPDRAFT_SPIN_TURNS := 2.0
# Turns for the CURRENT airborne spin. Vail's Updraft keeps the 2.0 above (it is
# a swirling gust and wants the extra rotation); the Wind-Up Punch knock-up sets
# 1.0 for exactly one clean 360. Per-cast rather than a second constant so the
# two never have to share a value.
var _updraft_spin_turns: float = UPDRAFT_SPIN_TURNS
var _punch_scale: Vector2 = Vector2.ONE      # attack stretch
var _hit_squash: Vector2 = Vector2.ONE       # hit squash
var _flash: float = 0.0                       # 0..1 white flash on hit
var _death_rotation: float = 0.0             # topple on death
var _death_alpha: float = 1.0                # fade on death
var _is_dying: bool = false
var _death_tween: Tween = null   # kept so revive() can cancel a fade-out in flight

# Khagan-only ambient idle pulse (wave-10 boss body treatment, synced to
# KhaganArenaOverlay's ground pulse) — a SEPARATE layer from _flash, composed
# on top of it in _apply_animation so a hit/dismount/possession flash always
# reads through unchanged; this only tints the quiet moments between them.
var _khagan_pulse_tween: Tween = null
var _khagan_pulse_strength: float = 0.0
var _khagan_pulse_color: Color = Color(0.72, 0.55, 0.22)   # iron/gold, plain 0-1 range

# Particles (assigned per element in _ready; tune the mapping by previewing
# assets/particle/"Free Preview All.gif" and swapping which "Part N" maps to what).
var attack_particle_pack: String = "Part 2"  # burst when this unit attacks / casts
var hit_particle_pack: String = "Part 1"     # impact when this unit is hit
var death_particle_pack: String = "Part 11"  # fade on death

# Element → {attack/cast burst, hit impact}. Gives each aspect its own flavour
# (fire heroes throw embers, lightning heroes crackle, …) on top of the procedural
# SkillEffect that every ability already spawns.
const ELEMENT_PARTICLES := {
	UnitBase.Element.FIRE:      {"atk": "Part 3",  "hit": "Part 4"},
	UnitBase.Element.WATER:     {"atk": "Part 6",  "hit": "Part 7"},
	UnitBase.Element.EARTH:     {"atk": "Part 8",  "hit": "Part 9"},
	UnitBase.Element.AIR:       {"atk": "Part 10", "hit": "Part 12"},
	UnitBase.Element.LIGHTNING: {"atk": "Part 5",  "hit": "Part 13"},
	UnitBase.Element.NORMAL:    {"atk": "Part 2",  "hit": "Part 1"},
}


func get_class_sprite_folder() -> String:
	match unit_class:
		UnitBase.UnitClass.WARRIOR:    return "warrior"
		UnitBase.UnitClass.RANGER:     return "archer"
		UnitBase.UnitClass.MONK:       return "monk"
		UnitBase.UnitClass.THIEF:      return "thief"
		UnitBase.UnitClass.BLACK_MAGE: return "black_mage"
		UnitBase.UnitClass.WHITE_MAGE: return "white_mage"
		UnitBase.UnitClass.RED_MAGE:   return "red_mage"
		UnitBase.UnitClass.BLOODHOUND: return "warrior"
		UnitBase.UnitClass.BOUNCER:    return "monk"
		UnitBase.UnitClass.HEADHUNTER: return "archer"
		UnitBase.UnitClass.SHAUNA:    return "shauna"
		UnitBase.UnitClass.NEMI:      return "nemi"
		# Necro's two summons (2026-07-11) — were drawn as plain triangle/diamond
		# shapes before real art landed; MONSTER_SPRITE_PATHS already had these
		# keys registered ahead of the art.
		UnitBase.UnitClass.ZOMBIE:    return "zombie_minion"
		UnitBase.UnitClass.BAT:       return "bat_minion"
		_: return ""

func get_enemy_sprite_override() -> String:
	# Enemy units can override the class-based folder via metadata
	if has_meta("sprite_folder"):
		return str(get_meta("sprite_folder"))
	return ""


func _ready():
	super._ready()

	if sprite_variant == -1:
		sprite_variant = randi() % 3

	element_glow = Sprite2D.new()
	element_glow.texture = _create_glow_texture()
	element_glow.scale = Vector2(1.5, 1.5)
	add_child(element_glow)

	_setup_lpc_sprite()
	_assign_element_particles()

	fill_color = get_element_color()
	if element_glow:
		element_glow.modulate = fill_color
		element_glow.modulate.a = 0.4

	health_bar = HealthBar.new()
	health_bar.placement = HealthBar.BarPlacement.BOTTOM if is_player_unit else HealthBar.BarPlacement.TOP
	health_bar.mp_is_skill_cooldown = not is_player_unit
	# Scale the bar with the unit's footprint so a 2×2 boss gets a bar wide enough
	# to span its block, floated higher to clear the taller sprite. (1×1 keeps the
	# defaults, so normal units are unchanged.)
	health_bar.bar_width = 70.0 + (cell_size - 1) * 120.0   # 70 / 190 / …
	health_bar.offset_y  = 60.0 + (cell_size - 1) * 35.0    # 60 / 95 / …
	# A SHRUNK sprite (SPRITE_SCALE_OVERRIDE < 1, e.g. the Gale Warden flock
	# birds) keeps its feet pinned, so its top drops — drop the bar with it or
	# it floats a whole head above the body. Enlarged sprites (Nemi, Headhunter)
	# are left exactly as tuned.
	var ov_key: String = get_enemy_sprite_override()   # enemies: their own folder, not the stats-host class
	if ov_key == "":
		ov_key = get_class_sprite_folder()
	var ov: float = SPRITE_SCALE_OVERRIDE.get(ov_key, 1.0)
	if ov < 1.0:
		health_bar.offset_y -= (1.0 - ov) * HERO_SPRITE_RENDER_H
	health_bar.offset_y -= float(HEALTH_BAR_DROP.get(ov_key, 0.0))
	add_child(health_bar)
	# health_bar's own _ready() (triggered by add_child above, since this unit
	# is already inside the tree) sets its resting position.y for TOP/BOTTOM
	# placement. Bank that as the base _apply_animation() offsets from every
	# frame — otherwise the bar sits fixed on the unit's ROOT while attack
	# lunges / hurt recoils / death tosses only move the sprite child, and the
	# bar visibly detaches and lands on whichever cell the unit lunged past.
	_health_bar_base_pos = health_bar.position
	_setup_skill_icon()
	_setup_role_badge()
	health_bar.update_hp(current_hp, max_hp)
	if is_player_unit:
		health_bar.update_mp(current_mana, max_mana)
	else:
		health_bar.update_mp(0.0, float(skill_cooldown_max) if skill_name != "" else 0.0)
	# Pass the REAL max — 0 means "this unit has no ultimate" and the bar hides
	# the strip entirely instead of drawing a forever-empty track.
	health_bar.update_ult(ultimate_charge, ultimate_charge_max)

	health_changed.connect(_on_health_changed)
	mana_changed.connect(_on_mana_changed)
	attacked.connect(_on_attacked)
	took_damage.connect(_on_took_damage)
	shield_changed.connect(_on_shield_changed)
	ward_changed.connect(_on_ward_changed)
	_anim_phase = randf() * TAU   # so units don't all bob in lockstep
	update_visuals()


func _sprite_variant_count(folder: String) -> int:
	if folder == "hill_giant": return 1
	return 3

func _setup_plain_sprite(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var s := Sprite2D.new()
	s.texture = load(path)
	s.centered = true
	s.z_index = 1
	s.flip_h = not is_player_unit
	# Scale so every unit renders at a consistent height regardless of source
	# resolution; larger footprints (2×2 bosses) render proportionally bigger.
	var render_h: float = HERO_SPRITE_RENDER_H * (SPRITE_RENDER_H_2X_MULT if cell_size >= 2 else 1.0)
	var scale_val: float = render_h / float(s.texture.get_height())
	s.scale = Vector2(scale_val, scale_val)
	# Bottom-anchor within the unit's footprint (the node sits at the footprint
	# centre — a 2×2 unit is centred on its block, so its half-height is 2 cells).
	var anchor_half: float = 55.0 * cell_size
	var tex_half: float  = render_h * 0.5
	_sprite_half_h = tex_half
	_sprite_base_offset = Vector2(0.0, anchor_half - tex_half)
	s.position = _sprite_base_offset
	add_child(s)
	plain_sprite = s
	_base_sprite_scale = s.scale
	if cell_size >= 2:
		shape_size = 100.0   # bigger click/hover + held-item-badge radius for big units

# 3D counterpart of _setup_plain_sprite: same bottom-anchoring contract, same
# _base_sprite_scale / _sprite_base_offset outputs, so everything downstream
# (the procedural layers, the drag hit radius, the health bar) is unchanged.
#
# The deliberate trick is the last two lines: plain_sprite is aimed at the
# Sprite2D INSIDE the Model3DSprite. That sprite is what carries the viewport's
# texture, so _apply_animation()'s existing plain_sprite branch drives the 3D
# character's offset/scale/rotation/flash with no 3D-specific code at all.
func _setup_model3d(path: String, prop_nodes: Variant = null,
		clip_aliases: Dictionary = {}, managed_props: Array = []) -> bool:
	if not ResourceLoader.exists(path):
		push_warning("VisualUnit: 3D model missing at %s — falling back to 2D art" % path)
		return false
	var m := Model3DSprite.new()
	# Approved 3D hero presentation: native GLB materials at smooth 256px,
	# with a thin screen-space silhouette. Enemy models keep their own settings.
	# A monster opts into the same presentation with "pbr": true in
	# MONSTER_MODEL_PROPS (2026-10-02 batch, pending owner review — the toon
	# path's 1.55x saturation lift blew Tidecaller's already-vivid texture out).
	var monster_pbr: bool = bool(MONSTER_MODEL_PROPS.get(
			get_meta("sprite_folder", "") if has_meta("sprite_folder") else "", {}).get("pbr", false))
	if HERO_MODEL_PATHS.get(unit_class, "") == path or monster_pbr:
		soft_contact_shadow = true
		m.render_size = Vector2i(256, 256)
		m.texture_filter_nearest = false
		m.toon = false
		m.outline_with_pbr = true
		m.outline_px = 1.5
		m.outline_soft_edges = true
		m.msaa_3d = Viewport.MSAA_4X
		if unit_class == UnitBase.UnitClass.LUMEN:
			# The v002 GLB contains a grayscale seam mask. Apply its violet tint
			# explicitly using native PBR multiply mode after Godot import.
			m.pbr_material_overrides = {"Material_1": {
				"emission_color": Color(0.60, 0.30, 1.0), "emission_energy": 2.0}}
		# Meshy bodies import Material_1 at metallic=1.0 with no metallic texture
		# (the glTF default). With no environment to reflect, a full metal gets
		# no diffuse light and shows its texture only through the key's
		# highlight, so dark costumes went to flat silhouettes. Matte ONLY the
		# heroes that measured darker AND kept their contrast when matted
		# (graphics audit 2026-10-02, variants/set3): Rift 0.22->0.32,
		# Lordee 0.20->0.31, Zolt 0.42->0.55 figure luma. Bright bodies (Vail,
		# Bouncer, Static, June, Doc) washed out when matted -- left alone.
		# Riot keeps a little metal for his armour.
		if unit_class in [UnitBase.UnitClass.RIFT, UnitBase.UnitClass.LORDEE,
				UnitBase.UnitClass.ZOLT]:
			m.pbr_material_overrides = {"Material_1": {"metallic": 0.0, "roughness": 0.75}}
		elif unit_class == UnitBase.UnitClass.RIOT:
			m.pbr_material_overrides = {"Material_1": {"metallic": 0.3, "roughness": 0.6}}
		elif unit_class == UnitBase.UnitClass.EMBER:
			# Inner glow from her OWN texture as the emission map (multiply), so
			# the bright glass glows and the dark cooled seams stay dark -- a flat
			# emission colour would wash the seams out. The bow's primitive
			# "Wood" is tinted ember-gold with a faint glow of its own.
			m.pbr_material_overrides = {
				"Material_0": {"emission_color": Color(1.0, 0.62, 0.30),
					"emission_energy": 0.55,
					"emission_texture": load("res://assets/3d pipeline/hero/ember/ember_v001_Image_0.png")},
				"Wood": {"albedo_tint": Color(2.5, 2.1, 1.3),
					"emission_color": Color(1.0, 0.45, 0.12), "emission_energy": 0.35}}
		if monster_pbr:
			m.pbr_material_overrides = MONSTER_MODEL_PROPS.get(
				str(get_meta("sprite_folder", "")), {}).get("pbr_overrides", {})
		# These five had the largest unblended action-to-idle pose gaps in the
		# quality audit. Blend only returns/travel; action entries stay immediate.
		if unit_class in [UnitBase.UnitClass.PASTOR, UnitBase.UnitClass.LORDEE,
				UnitBase.UnitClass.REED, UnitBase.UnitClass.SPORE, UnitBase.UnitClass.RIOT]:
			m.clip_blend_by_clip = {"idle": 0.10, "walk": 0.06}
	# Monsters pass their prop set straight in; heroes leave these null and are
	# configured by the per-class blocks below.
	if prop_nodes != null:
		m.weapon_default_node = prop_nodes
	if not clip_aliases.is_empty():
		m.clip_aliases = clip_aliases
	if not managed_props.is_empty():
		m.managed_prop_nodes = managed_props
	# A monster wider than its square render frame (the dirt mound) gets its
	# sides clipped; "frame_grow" widens the frame without changing density.
	if has_meta("sprite_folder"):
		var fg: float = float(MONSTER_MODEL_PROPS.get(get_meta("sprite_folder"), {}).get("frame_grow", 0.0))
		if fg > 0.0:
			m.frame_grow = fg
	# Bouncer's whole kit is reaching out and dragging the board to himself
	# (Presence / Slam / Gravity Drop), so his punches stretch. Opt-in per hero
	# rather than global — it would look wrong on a swordsman.
	m.stretch_arm = unit_class in STRETCH_ARM_HEROES
	m.camera_pitch_deg = MODEL_CAMERA_PITCH_DEG
	# Headhunter's rifle: a SEPARATE rigid bind per clip group, not one gun
	# shown/hidden — a single bind looked wrong in either aim or attack (see
	# Model3DSprite.weapon_variants). Holstered to his back for every other
	# clip (user call 2026-09-07).
	# Doc's syringe glows because it is FULL of the thing his abilities do. The
	# fluid span of the barrel is its own material slot in the .glb ("Fluid"),
	# so the colour can change without touching the casing. Green while he is
	# using Triage/Inject, gold on the ult (user call 2026-09-10); a dim green
	# simmer the rest of the time so it reads as luminous serum, not as a lamp
	# that switches on only during abilities.
	# Alpha is intensity — see Model3DSprite._update_glow().
	if unit_class == UnitBase.UnitClass.DOC:
		# v002 (2026-09-26): scrubs toned down in the texture AND here — the toon
		# shader's 1.55x saturation still pumped them to neon cyan and the tan apron
		# to orange without this. His fur is raccoon grey now, so damping Material_1
		# no longer greys out a brown body; the syringe's Body/Fluid slots keep their
		# own colour and ability glow.
		m.material_saturation_scale = {"Material_1": 0.60}
		m.material_brightness_scale = {"Material_1": 0.92}
		m.glow_material = "Fluid"
		m.glow_base = Color(0.35, 0.95, 0.45, 0.35)
		m.glow_by_clip = {
			"skill": Color(0.30, 1.00, 0.40, 1.60),
			"ult": Color(1.00, 0.78, 0.20, 2.20),
		}
	if unit_class == UnitBase.UnitClass.BOUNCER:
		# Gravity Drop "Big Inhale": the `belly` morph balloons on the inhale and
		# snaps back (with a small overshoot) on the exhale. Clip seconds of the
		# v002 `ult` — impact is f15.8 = 0.66 s, matching GD_IMPACT.
		m.morph_curves = {"ult": {"belly": [
			[0.0, 0.0], [0.125, 0.0], [0.62, 1.0], [0.66, 1.05],
			[0.72, -0.12], [0.80, 0.06], [0.90, 0.0], [1.083, 0.0]]}}
	if unit_class == UnitBase.UnitClass.CROSS:
		# v002 (2026-09-25, "just a happy lemur knight healing people"): the halo
		# and the chest cross share one "Glow" material. Warm gold at rest; it
		# brightens on Absolution and blazes on Judgment.
		m.glow_material = "Glow"
		m.glow_base = Color(1.00, 0.78, 0.30, 0.60)
		m.glow_by_clip = {"skill": Color(1.00, 0.86, 0.45, 1.40),
			"ult": Color(1.00, 0.84, 0.35, 2.00)}
	if unit_class == UnitBase.UnitClass.BLOODHOUND:
		# v002: eyes + maw are one "Glow" material (faces picked by raycasting
		# the head close-up, teeth excluded by colour). One ember colour for
		# both reads as a single fire inside him; it flares on the Pounce.
		m.glow_material = "Glow"
		m.glow_base = Color(1.00, 0.45, 0.12, 1.00)
		m.glow_by_clip = {"ult": Color(1.00, 0.32, 0.06, 2.00)}
		# The Pounce's overhead chop reaches 1.47x past the idle+death frame
		# (top) and 1.44x (side), measured on bone heads + claw length; 1.55
		# clears both. Same on-screen size and pixel density, bigger canvas.
		m.frame_grow = 1.55
	if unit_class == UnitBase.UnitClass.HEADHUNTER:
		# idle (2026-09-07): user supplied a REAL Meshy idle clip ("Idle_9"),
		# replacing the earlier hand-frozen-from-attack workaround — see
		# tools/model3d/replace_clip.py, a plain glTF node-copy (matches
		# bones by name) for dropping one new animation into an
		# already-merged character without rebuilding the whole file.
		# It's a clean, neutral, upright A-pose-derived stance (measured:
		# its own hip orientation is only 8° off from `walk`'s, vs. 40-70°
		# for the bladed aim/attack poses), so it needs neither a dedicated
		# weapon bind nor a yaw correction of its own — Weapon_Back (already
		# calibrated for the holster) happens to look right on it too, since
		# a relaxed idle stance realistically has the rifle slung, not held.
		m.weapon_variants = {
			"aim": "Weapon_Aim",
			"attack": "Weapon_Attack",
			# walk_aim is the walk cycle with the aim pose grafted on from the
			# spine up (tools/model3d/graft_upper_body.py), so it holds the gun
			# in the same hands the aim bind was calibrated against.
			"walk_aim": "Weapon_Aim",
		}
		m.weapon_default_node = "Weapon_Back"
		# MEASURED, not guessed (2026-09-09). The earlier values here were a
		# first guess derived from the Hips bone's orientation, and they were
		# wrong for a reason worth recording: in an aiming pose the body is
		# BLADED — hips deliberately point away from the target — so hip
		# forward is not aim forward. Picking the number by eye is worse
		# still: a bias chosen because the pose "looks good" leaves the barrel
		# at a fixed offset from the target on EVERY shot, so he fires
		# visibly sideways while the projectile flies true.
		#
		# So it's derived from where the rifle's barrel actually points, and
		# verified by rendering the gun alone across 8 target yaws and fitting
		# its projected length: a barrel broadside to the camera projects
		# long, end-on projects short. At the right bias that curve peaks at
		# due east/west and bottoms at north/south. Measured residual after
		# calibration: +1.0° (was +51°). idle needs no entry — its hip
		# orientation is within 8° of walk's, so 0 is fine.
		#
		# NOTE the aim clip must stay a STATIC hold for this to mean anything;
		# see the freeze in the pipeline. The raw Meshy clip swept ~60° of
		# barrel yaw across its "settled" tail, so no single bias could be
		# right and he visibly panned off-target while holding.
		# One number for all three weapon-up clips, because attack and walk_aim
		# are both built from the aim pose and inherit its barrel orientation
		# exactly (add_recoil.py rotates only the spine; graft_upper_body.py
		# pins the torso's WORLD rotation to aim's over an untouched walk).
		# Verified together: each measured -1.0 to -1.2 deg of residual error.
		#
		# CALIBRATE LAST. An earlier pass measured -13.0 here and verified it
		# cleanly, then rebuilding the glb shifted the model's orientation
		# ~51 deg and silently invalidated it while the Blender-side numbers
		# stayed put. Any change that re-exports the .glb can move this, so it
		# has to be the final step, after the clips are done.
		m.clip_yaw_bias_deg = {"aim": 38.4, "attack": 38.4, "walk_aim": 38.4}
	if unit_class == UnitBase.UnitClass.SHEILDOR:
		# HelmetContrast is a head-weighted material region in the versioned GLB.
		# A harder shadow band and stronger rim separate the helmet ornaments from
		# the dark shoulder armor without introducing smooth PBR specular noise.
		m.material_shadow_tone = {"HelmetContrast": 0.24}
		m.material_brightness_scale = {"HelmetContrast": 1.08}
		m.material_rim_amount = {"HelmetContrast": 0.58}
		m.weapon_variants = {"attack": "Greatshield_Attack"}
		m.weapon_default_node = "Greatshield"
		# The greatshield is rigidly bound to Hips while both arm poses are baked
		# into every clip. This rebuilt walk is authored model-forward, so Godot's
		# movement yaw needs no additional clip correction.
	if unit_class == UnitBase.UnitClass.STITCH:
		# The needle is deliberately thicker at native scale, and a small lift in
		# brightness keeps its shaft distinct from Stitch's brown/orange costume.
		m.material_brightness_scale = {"Material_0.001": 1.35}
		# Doll left / needle right for voodoo actions; both stowed for travel,
		# hit reactions and death. Each mesh is rigidly bound to one bone.
		m.weapon_variants = {
			"idle": ["Doll_Held", "Needle_Held"],
			"attack": ["Doll_Held", "Needle_Held"],
			"skill": ["Doll_Held", "Needle_Held"],
			"ult": ["Doll_Held", "Needle_Held"],
		}
		m.weapon_default_node = ["Doll_Stowed", "Needle_Stowed"]
		# Measured after the final GLB export. A shared authored ready pose is
		# 4.09° off model-forward; raw movement/death clips have their own root
		# orientations. Hurt's Meshy clip is the large outlier at -53.45°.
		m.clip_yaw_bias_deg = {
			"idle": -4.086, "attack": -4.086,
			"skill": -4.086, "ult": -4.086,
			"walk": -0.395, "walk_slow": 6.344,
			"hurt": 53.446, "death": -3.769,
		}
	if unit_class == UnitBase.UnitClass.STATIC:
		# Static deliberately grips the live end in every gameplay stance. The
		# cable and visible voltage forks are rigidly hand-bound so idle/walk never
		# shear between Hips and RightHand. Keep the old flexible mesh reachable
		# only for the non-gameplay rest reference.
		m.weapon_variants = {"rest_reference": "LiveWire_Flexible"}
		m.weapon_default_node = ["LiveWire_Cast", "LiveWire_Sparks"]
		# Audit 2026-10-01: the body texture is already vivid (median sat 0.77), so
		# the global 1.55x toon lift clipped him to sat 1.00 on every board vs ~0.3
		# for the rest of the roster — goggles/harness/beak merged into one blob.
		# Same fix as Doc; the wire's cyan materials keep the full lift.
		# Tried darkening Static_Cable_Rubber too (2026-10-01): read on air but the
		# cable vanished on water/fire, so the teal stays.
		m.material_saturation_scale = {"Material_1": 0.60}
		m.material_brightness_scale = {"Material_1": 0.92}
		# Flexible live wire (2026-10-01): the rigid cable surface is hidden and a
		# simulated rope runs plug -> belt, sagging and trailing the fist. Points
		# are model REST space measured on v019 (plug bottom at the fist; belt front
		# at the right hip, so the slack loop hangs in FRONT of the leg instead of
		# hiding behind the forearm — the first cut anchored at the hip side and
		# only a sliver showed). The capsule is the belly band (y 0.45-0.85, r ~0.33).
		m.cable_config = {
			"start_bone": "RightHand", "start": Vector3(-0.67, 0.55, 0.10),
			"end_bone": "Hips", "end": Vector3(-0.22, 0.50, 0.24),
			"material": "Static_Cable_Rubber", "hide_material": "Static_Cable_Rubber",
			"length": 1.30, "radius": 0.042,
			# Top of the cyan voltage forks above the plug (v019 rest).
			"tip": Vector3(-0.67, 0.76, 0.12),
			"colliders": [{"bottom": Vector3(0.0, 0.45, -0.03),
				"top": Vector3(0.0, 0.85, -0.03), "radius": 0.33}],
		}
		# The voltage forks were authored as Static_Electric_Cyan but never lit.
		# Only ~3 px at 115 px tall, so this alone does not sell "electric" —
		# a real spark VFX is the open follow-up.
		m.glow_material = "Static_Electric_Cyan"
		m.glow_base = Color(0.45, 0.95, 1.00, 0.60)
		m.glow_by_clip = {
			"attack": Color(0.70, 1.00, 1.00, 1.40),
			"skill": Color(0.70, 1.00, 1.00, 1.60),
			"ult": Color(0.85, 1.00, 1.00, 2.20),
		}
		# Head-front measurements against idle put the attack/skill cast centers
		# about 14 degrees counter-clockwise. Center those clips on model-forward;
		# the ultimate keeps its authored turn but starts and resolves on-axis.
		m.clip_yaw_bias_deg = {"attack": 14.0, "skill": 14.0, "ult": 14.0}
		# The v020 guard idle no longer matches the first frame of the casts.
		m.clip_blend_sec = 0.12
	if unit_class == UnitBase.UnitClass.RIFT:
		# Staff remains in the left hand; the free right hand performs basic casts.
		m.weapon_default_node = "Staff_Held"
		m.clip_yaw_bias_deg = {"attack": 32.0}
	add_child(m)
	var base_render_h: float = (HERO_MODEL_RENDER_H
			if HERO_MODEL_PATHS.get(unit_class, "") == path else MODEL_RENDER_H)
	var render_h: float = base_render_h * (SPRITE_RENDER_H_2X_MULT if cell_size >= 2 else 1.0)
	# June's plant body is intentionally broad and imposing in the 2D design.
	# Give that silhouette more of the occupied cell after the v002 width pass.
	if unit_class == UnitBase.UnitClass.JUNE:
		render_h *= 1.10
	if not m.setup(path, render_h):
		m.queue_free()
		return false
	model3d = m
	if unit_class == UnitBase.UnitClass.CROSS:
		var halo := CrossHaloGlow.new()
		add_child(halo)
		halo.setup(self)
	if unit_class == UnitBase.UnitClass.STATIC and m.has_cable():
		var sparks := StaticWireSparks.new()
		add_child(sparks)
		sparks.setup(self)
	# Players hold the bottom of the board and face up-screen, enemies the top —
	# same convention the flip_h on the 2D sprites encodes.
	m.set_facing_right(is_player_unit)

	var inner := m.get_sprite()
	# Monsters: Model3DSprite pins IDLE HEIGHT to render_h, so a body much wider
	# than tall (a beetle, a tortoise, a dirt mound) comes out far wider than its
	# cell. Per-variant "scale" in MONSTER_MODEL_PROPS (tuned on the board render,
	# 2026-10-03). An automatic aspect cap was tried and dropped: bone bounds do
	# not see a shell's width, so it never triggered on the cases that needed it.
	if has_meta("sprite_folder") and MONSTER_MODEL_PATHS.get(get_meta("sprite_folder"), "") == path:
		var k: float = float(MONSTER_MODEL_PROPS.get(get_meta("sprite_folder"), {}).get("scale", 1.0))
		if not is_equal_approx(k, 1.0):
			inner.scale *= k
			render_h *= k
	var anchor_half: float = 55.0 * cell_size
	_sprite_half_h = render_h * 0.5
	_sprite_base_offset = Vector2(0.0, anchor_half - render_h * 0.5)
	inner.position = _sprite_base_offset
	plain_sprite = inner
	_base_sprite_scale = inner.scale
	if cell_size >= 2:
		shape_size = 100.0
	return true


# Every anim name video_to_sheet.py can produce for a unit — loaded if present,
# skipped if not (a unit can have just legacy "walk" or a full directional set).
const _GENERATED_ANIM_NAMES := [
	"walk_south", "walk_north", "walk_east", "walk_west",
	"idle_south", "idle_north",
]
# One-shot actions (single direction, non-looping). Played over the walk/idle
# base by _play_oneshot() when the unit swings / gets hit / dies.
const _ONESHOT_ANIM_NAMES := ["attack", "hurt", "death"]

# Loads video_to_sheet.py-generated animations (assets/sprites/<category>/<key>/<anim>.png
# + <anim>.json) as a real AnimatedSprite2D. Picks up whichever of walk_south/
# north/east/west + idle_south/north exist for this unit — _update_animation()
# already knows how to pick between them by last_move_direction, falling back
# to walk_south for any direction that isn't generated yet. Also loads the
# legacy single "walk" sheet (pre-4-direction hill_giant test) as walk_south
# so older units keep working untouched.
# Returns false (leaving nothing built) if no sheet at all has been generated
# for this unit yet, so callers fall back to the static plain_sprite art.
func _setup_generated_animated_sprite(key: String, category: String) -> bool:
	var dir := "res://assets/sprites/%s/%s" % [category, key]
	var sf := SpriteFrames.new()
	# A fresh SpriteFrames is born holding an EMPTY animation called "default".
	# Left in, it sorts ahead of every real name in get_animation_names(), so the
	# frame-height fallback below grabbed frame 0 of an animation with no frames
	# and died on `null.get_height()`. That took out every hero with no
	# walk_south sheet — bouncer, cross, pastor, rush, static — which lost their
	# animations and fell back to static art. Drop the phantom up front so no
	# loop over the animation names can ever see it.
	if sf.has_animation("default"):
		sf.remove_animation("default")
	var frame_h_ref: int = 0

	var found_loop := false
	for anim in _GENERATED_ANIM_NAMES:
		found_loop = _load_anim_into(sf, dir, anim, anim) or found_loop
	# True walk_east/west already encode team-relative facing, so only the
	# legacy single-sheet fallback (one side-view sheet reused for everyone)
	# still needs a flip to make enemy-side units face the other way.
	var is_legacy_single_sheet := not found_loop
	if not found_loop:
		# Legacy single-direction sheet: "walk.png" stands in for walk_south.
		found_loop = _load_anim_into(sf, dir, "walk", "walk_south")

	# One-shot actions load non-looping (loop=false) so _update_animation() holds
	# them to their last frame. Loaded even when NO walk/idle exists: a unit can
	# legitimately have only an attack sheet (goblin, 2026-07-25) and still needs
	# it to play — bailing out before this point sent those units back to the
	# static sprite and the attack never appeared.
	var found_oneshot := false
	for anim in _ONESHOT_ANIM_NAMES:
		found_oneshot = _load_anim_into(sf, dir, anim, anim, false) or found_oneshot

	if not (found_loop or found_oneshot):
		return false

	# Whatever actually has frames tells us the frame height for scaling. Prefer
	# walk_south when it exists, but never assume it does (only 21 of the 26
	# heroes have one) and never assume an animation has a frame 0.
	for anim in ["walk_south"] + Array(sf.get_animation_names()):
		if not sf.has_animation(anim) or sf.get_frame_count(anim) == 0:
			continue
		var t := sf.get_frame_texture(anim, 0)
		if t:
			frame_h_ref = t.get_height()
			break

	# Attack-only unit: synthesise a 1-frame resting pose so the walk/idle
	# picker in _update_animation() always has something valid to play. Frame 0
	# of a one-shot is the neutral stance (the prompts require these clips to
	# start and end there), so it reads correctly as a standing pose.
	if not found_loop:
		var rest_src := ""
		for anim in _ONESHOT_ANIM_NAMES:
			if sf.has_animation(anim):
				rest_src = anim
				break
		if rest_src != "":
			sf.add_animation("idle_south")
			sf.set_animation_loop("idle_south", true)
			sf.set_animation_speed("idle_south", 1.0)
			sf.add_frame("idle_south", sf.get_frame_texture(rest_src, 0))

	# Measure each animation's actual character height (not the raw 256px canvas —
	# how tall he is drawn WITHIN it) off frame 0, and derive a correction factor
	# relative to the idle/walk reference so every clip renders at the same
	# apparent size. See _anim_scale_mult / _measure_frame_content_height.
	# Measured once per SHEET, not once per unit: the result depends only on the
	# art, and wave 6 alone spawns three units off the same folder.
	var content_h: Dictionary = _ANIM_CONTENT_H_CACHE.get(dir, {})
	if content_h.is_empty():
		for anim in sf.get_animation_names():
			var h: int = _measure_anim_content_height(sf, anim)
			content_h[anim] = h if h > 0 else frame_h_ref
		_ANIM_CONTENT_H_CACHE[dir] = content_h
	var ref_anim := ""
	if sf.has_animation("idle_south"): ref_anim = "idle_south"
	elif sf.has_animation("walk_south"): ref_anim = "walk_south"
	elif sf.get_animation_names().size() > 0: ref_anim = sf.get_animation_names()[0]
	var ref_h: int = int(content_h.get(ref_anim, frame_h_ref))
	_anim_scale_mult.clear()
	for anim in content_h.keys():
		# Clamp is a safety net against a bad measurement (stray fringe pixel
		# skewing the scan), not a real cap — some clips (e.g. Shauna's attack
		# pose, drawn at ~58% of her idle height) genuinely need close to 1.7x.
		_anim_scale_mult[anim] = clampf(float(ref_h) / float(max(int(content_h[anim]), 1)), 0.6, 2.0)

	var node := AnimatedSprite2D.new()
	node.sprite_frames = sf
	node.z_index = 1
	node.flip_h = is_legacy_single_sheet and not is_player_unit
	# Same bottom-anchor + consistent-render-height convention as _setup_plain_sprite —
	# the generated canvas is a fixed square (feet locked near the bottom), so it
	# scales/anchors identically to the static AI sprites it replaces.
	var render_h: float = HERO_SPRITE_RENDER_H * (SPRITE_RENDER_H_2X_MULT if cell_size >= 2 else 1.0) * SPRITE_SCALE_OVERRIDE.get(key, 1.0)
	var scale_val: float = render_h / float(max(frame_h_ref, 1))
	node.scale = Vector2(scale_val, scale_val)
	var anchor_half: float = 55.0 * cell_size
	var tex_half: float = render_h * 0.5
	_sprite_half_h = tex_half
	_sprite_base_offset = Vector2(0.0, anchor_half - tex_half)
	node.position = _sprite_base_offset
	add_child(node)
	var start_anim := "idle_south" if is_player_unit else "idle_north"
	if not sf.has_animation(start_anim):
		start_anim = "walk_south" if sf.has_animation("walk_south") else sf.get_animation_names()[0]
	node.play(start_anim)
	animated_sprite = node
	_base_sprite_scale = node.scale
	if cell_size >= 2:
		shape_size = 100.0
	return true

# Reads "<dir>/<file_name>.png" + ".json" (if present) into `sf` as animation
# `anim_key`. `loop` is false for one-shot actions (attack/hurt/death) — that's
# what makes _update_animation() hold them to their last frame instead of
# cutting back to walk/idle mid-swing. Returns whether it found a sheet.
func _load_anim_into(sf: SpriteFrames, dir: String, file_name: String, anim_key: String, loop: bool = true) -> bool:
	var png_path := "%s/%s.png" % [dir, file_name]
	var json_path := "%s/%s.json" % [dir, file_name]
	if not (ResourceLoader.exists(png_path) and FileAccess.file_exists(json_path)):
		return false

	var f := FileAccess.open(json_path, FileAccess.READ)
	var meta = JSON.parse_string(f.get_as_text())
	f.close()
	if not (meta is Dictionary and meta.has("frame_w") and meta.has("count")):
		push_warning("Malformed sprite sheet metadata: %s" % json_path)
		return false

	var texture: Texture2D = load(png_path)
	var frame_w: int = int(meta["frame_w"])
	var frame_h: int = int(meta.get("frame_h", frame_w))
	var count: int = int(meta["count"])
	var fps: float = float(meta.get("fps", 12.0))

	sf.add_animation(anim_key)
	sf.set_animation_loop(anim_key, loop)
	sf.set_animation_speed(anim_key, fps)
	for i in range(count):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
		sf.add_frame(anim_key, atlas)
	return true

# Content height of a whole CLIP for _anim_scale_mult: the tallest the character
# is drawn across every frame of the animation, as an exact bounding box.
#
# Both halves of that sentence are load-bearing, and the previous version got
# both wrong (2026-09-17 user report: the Hill Giant "grows in size on certain
# frames then snaps back"):
#
#  • It measured FRAME 0 ONLY and applied that to the entire clip. The Hill
#    Giant's attack opens on a wind-up crouch, so frame 0 measured 120px against
#    a 201px idle reference and the whole swing rendered at 1.675x — then snapped
#    back to 1.0 the moment idle resumed. His walk did the same at 1.182x. All
#    three of his clips are in fact drawn at the same height (209px), so every
#    one of those corrections was inventing a size change out of nothing.
#
#  • It sampled 3 COLUMNS, which is not a reliable estimator of a character's
#    height. On attack frame 2 the three columns fell between the giant's leaning
#    body and his club and reported 124px where the true height is 203px.
#
# Measuring the clip's MAXIMUM is what makes the result stable: it describes how
# tall the character actually is in that animation rather than which pose happens
# to sit at index 0, so a crouch, a lunge or a raised club can no longer change
# the scale. Corrections that are real survive untouched — Shauna's attack pose
# is genuinely drawn at ~59% of her idle and still resolves to ~1.69x.
#
# Uses Image.get_region + get_used_rect (both native) rather than a GDScript
# pixel loop, so scanning every frame is cheaper than the old 3-column scan was.
func _measure_anim_content_height(sf: SpriteFrames, anim: String) -> int:
	var count: int = sf.get_frame_count(anim)
	if count <= 0:
		return 0
	var first = sf.get_frame_texture(anim, 0)
	if not (first is AtlasTexture and first.atlas):
		return 0
	var img: Image = first.atlas.get_image()
	if not img:
		return 0
	var tallest := 0
	var region_h := 0
	for i in range(count):
		var tex = sf.get_frame_texture(anim, i)
		if not (tex is AtlasTexture):
			continue
		var r := Rect2i(tex.region)
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		region_h = maxi(region_h, r.size.y)
		# Clamp to the source image: a malformed sheet whose declared frame count
		# runs past the PNG would otherwise throw on every frame past the end.
		r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		var used := img.get_region(r).get_used_rect()
		tallest = maxi(tallest, used.size.y)
	# All-transparent clip: fall back to the region height, as before.
	return tallest if tallest > 0 else region_h

# Tear down and rebuild whichever sprite node is active, re-reading unit_class /
# the "sprite_folder" meta. Used by the Triple-Threat boss so its silhouette
# actually changes when it transforms phase (unit_class drives the class→folder
# lookup in _setup_lpc_sprite/get_class_sprite_folder).
func rebuild_sprite() -> void:
	if animated_sprite and is_instance_valid(animated_sprite):
		remove_child(animated_sprite)
		animated_sprite.free()
		animated_sprite = null
	# On the 3D path plain_sprite is OWNED by model3d, not by the unit — freeing
	# the whole Model3DSprite takes the inner sprite (and its viewport) with it,
	# so clear the alias first rather than double-freeing it below.
	if model3d and is_instance_valid(model3d):
		plain_sprite = null
		remove_child(model3d)
		model3d.free()
		model3d = null
	if plain_sprite and is_instance_valid(plain_sprite):
		remove_child(plain_sprite)
		plain_sprite.free()
		plain_sprite = null
	_setup_lpc_sprite()
	_rebuild_skill_icon()

# Phase-transform bosses (Triarch/Khagan) swap skill_name mid-fight, so the
# cooldown badge has to be torn down and re-resolved the same way the sprite
# does in rebuild_sprite() — otherwise it'd keep showing (or hiding) art for
# whatever skill the unit had when it first spawned.
func _rebuild_skill_icon() -> void:
	if _skill_icon and is_instance_valid(_skill_icon):
		_skill_icon.get_parent().remove_child(_skill_icon)
		_skill_icon.free()
		_skill_icon = null
	_skill_icon_prev_cd = 0.0
	_skill_icon_blink_time = 0.0
	if health_bar:
		_setup_skill_icon()

## Monster variant: same Model3DSprite path the heroes take, keyed by
## sprite_folder and carrying that variant's prop set and clip aliases. It
## DELEGATES rather than building its own — _setup_model3d's tail wires the
## inner sprite up as plain_sprite and computes the bottom anchor, and a
## monster that skipped it rendered detached from its cell.
func _setup_monster_model3d(folder: String) -> bool:
	var cfg: Dictionary = MONSTER_MODEL_PROPS.get(folder, {})
	# The unit must also be told about the props belonging to the OTHER variants
	# sharing this .glb, or it cannot hide them — see
	# Model3DSprite.managed_prop_nodes. Union every variant that points at the
	# same file, so adding a third goblin needs no change here.
	var path: String = MONSTER_MODEL_PATHS[folder]
	var all_props: Array = []
	for f in MONSTER_MODEL_PATHS:
		if MONSTER_MODEL_PATHS[f] != path:
			continue
		for n in MONSTER_MODEL_PROPS.get(f, {}).get("props", []):
			if not all_props.has(n):
				all_props.append(n)
	return _setup_model3d(path, cfg.get("props", []), cfg.get("clips", {}),
			all_props)


func _setup_lpc_sprite() -> void:
	if unit_class in HERO_MODEL_PATHS and _setup_model3d(HERO_MODEL_PATHS[unit_class]):
		return

	if unit_class in HERO_SPRITE_PATHS:
		var hero_path: String = HERO_SPRITE_PATHS[unit_class]
		var hero_key: String = hero_path.get_file().get_basename()
		if _setup_generated_animated_sprite(hero_key, "heroes"):
			return
		_setup_plain_sprite(hero_path)
		return

	var folder: String = get_meta("sprite_folder") if has_meta("sprite_folder") else get_class_sprite_folder()
	if folder == "":
		return

	# 3D model first, exactly as heroes do above — falls through to the sprite
	# path if the .glb is missing, so a half-converted monster still renders.
	if MONSTER_MODEL_PATHS.has(folder) and _setup_monster_model3d(folder):
		return

	# Use AI monster sprite if available for this folder
	if MONSTER_SPRITE_PATHS.has(folder):
		var mpath: String = MONSTER_SPRITE_PATHS[folder]
		if ResourceLoader.exists(mpath):
			if _setup_generated_animated_sprite(folder, "monsters"):
				return
			_setup_plain_sprite(mpath)
			return
		# Registered but the art hasn't been dropped in yet (e.g. a boss whose
		# kit shipped ahead of its dedicated art, like Khagan originally) —
		# "folder" is a monster name, not a real LPC sheet path, so falling
		# through to the LPC loader below with it would just error. Placeholder
		# on the generic warrior LPC sheet instead until the real art lands.
		folder = "warrior"
	var v: int = sprite_variant % _sprite_variant_count(folder)
	var sprite_path: String = "res://assets/sprites/generated/%s/%d" % [folder, v]

	var lpc = LPCAnimatedSprite2D.new()
	lpc.sprite_frames = SpriteFrames.new()
	lpc.z_index = 1
	lpc.spritesheets_path = sprite_path
	lpc.animation_data = LPCGeneratedAnimData.new()
	add_child(lpc)

	# walk_south is always present in the generated 6-animation sheets
	if lpc.sprite_frames and lpc.sprite_frames.has_animation("walk_south"):
		animated_sprite = lpc
		var idle := "idle_south" if is_player_unit else "idle_north"
		lpc.play(idle)
		# LPC frames have large transparent margins, so the character only fills
		# part of the 64px frame. Scale up so units read at a good size on the grid.
		# Scale with the footprint rather than branching on 2 — a 3×3 body has to
		# read as bigger than a 2×2 or the finale looks like just another giant.
		if cell_size > 1:
			var s: float = SPRITE_SCALE_2X * (cell_size - 1)
			lpc.scale = Vector2(s, s)
		else:
			lpc.scale = Vector2(SPRITE_SCALE_1X, SPRITE_SCALE_1X)
		_base_sprite_scale = lpc.scale   # animations multiply on top of this
	else:
		lpc.queue_free()
		if cell_size > 1:
			shape_size = 80.0 * (cell_size - 1)   # click/hit radius tracks the block


# Small weapon icon shown above an enemy that spawned wielding a dropped item —
# a visible tell of what you'll loot if you kill it.
func show_held_item_icon(tex: Texture2D, rarity_color: Color) -> void:
	if not held_item_badge:
		held_item_badge = Sprite2D.new()
		held_item_badge.z_index = 6
		held_item_badge.position = Vector2(shape_size * 0.55, -shape_size * 0.75)
		held_item_badge.scale = Vector2(0.4, 0.4)
		add_child(held_item_badge)

		var ring := Sprite2D.new()
		ring.texture = _create_glow_texture()
		ring.modulate = rarity_color
		ring.modulate.a = 0.8
		ring.scale = Vector2(0.55, 0.55)
		ring.z_index = 5
		held_item_badge.add_child(ring)
	held_item_badge.texture = tex
	held_item_badge.visible = true

# Khagan's possession overlay — his phase-2 "dismounted" sprite pinned above
# whichever ally he's currently puppeting, so the player can see who's
# possessed at a glance (2026-07-08 user spec: "attach it to the top of the
# hero he takes control of" — phase 3 has no dedicated art of its own, it's
# just this icon placed on the possessed unit). Mirrors show_held_item_icon's
# lazy-create-then-reuse shape; call hide_possession_icon() when control ends.
# Scale is computed from the TEXTURE'S OWN pixel size, not a flat multiplier —
# khagan_phase2.png is a full ~550x550 boss sprite, not a pre-shrunk icon, so a
# flat 0.5 scale rendered it at ~275px (nearly boss-sized) instead of an icon
# (2026-07-10 user report: "too big, should be on the unit's head").
const POSSESSION_ICON_TARGET_PX := 56.0
var possession_icon: Sprite2D
# 3D phase 3 (2026-10-02, owner: "he jumps on one of your heroes and takes
# control of them"): Khagan's phase-2 octopus model, small, CLINGING to the
# possessed hero's head and playing its `cling` loop -- the creature is
# literally riding the hero. Falls back to the flat icon if the model is missing.
const POSSESSION_MODEL_PX := 52.0
var possession_model: Model3DSprite
func show_possession_icon(tex: Texture2D) -> void:
	var path: String = MONSTER_MODEL_PATHS.get("khagan_phase2", "")
	if path != "" and ResourceLoader.exists(path):
		if not possession_model:
			possession_model = Model3DSprite.new()
			possession_model.z_index = 7
			add_child(possession_model)
			if not possession_model.setup(path, POSSESSION_MODEL_PX):
				possession_model.queue_free()
				possession_model = null
		if possession_model:
			possession_model.visible = true
			possession_model.set_facing_right(is_player_unit)
			possession_model.play("cling")
			# sit ON the head, below the health bar (the clinger frame has headroom above its body, so its sprite centre sits lower than the crown)
			var top: float = _sprite_base_offset.y - _sprite_half_h if _sprite_half_h > 0.0 					else -shape_size * 1.0
			possession_model.get_sprite().position = Vector2(0, top + POSSESSION_MODEL_PX * 0.30)
			if possession_icon:
				possession_icon.visible = false
			return
	if not possession_icon:
		possession_icon = Sprite2D.new()
		possession_icon.z_index = 7
		possession_icon.position = Vector2(0, -shape_size * 1.15)
		add_child(possession_icon)
	var largest_dim: float = max(tex.get_width(), tex.get_height())
	if largest_dim > 0.0:
		possession_icon.scale = Vector2.ONE * (POSSESSION_ICON_TARGET_PX / largest_dim)
	possession_icon.texture = tex
	possession_icon.visible = true

func hide_possession_icon() -> void:
	if possession_icon and is_instance_valid(possession_icon):
		possession_icon.visible = false
	if possession_model and is_instance_valid(possession_model):
		possession_model.queue_free()
		possession_model = null

func _on_health_changed(current: int, maximum: int) -> void:
	if health_bar:
		health_bar.update_hp(current, maximum)

func _on_mana_changed(current: int, maximum: int) -> void:
	if health_bar and is_player_unit:
		health_bar.update_mp(current, maximum)

func _on_shield_changed(current: int) -> void:
	if health_bar:
		health_bar.update_shield(float(current), float(max_hp))

func _on_ward_changed(hits: int, maximum: int) -> void:
	if health_bar:
		health_bar.update_ward(hits, maximum)

# ── Attack: anticipation → snappy lunge → ease back, with a stretch punch ─────
func _on_attacked(target) -> void:
	if _is_dying:
		return
	if not (target and is_instance_valid(target)):
		return
	if str(get_meta("sprite_folder", "")) == "goblin" and battle_manager \
			and battle_manager.has_method("spawn_goblin_auto_impact"):
		battle_manager.spawn_goblin_auto_impact(target.global_position)
	var dir_world: Vector2 = target.global_position - global_position
	if dir_world.length() > 0.01:
		_engaged_dir = dir_world
		_engaged_until_ms = Time.get_ticks_msec() + ENGAGED_HOLD_MS
	if unit_class == UnitBase.UnitClass.BOUNCER and model3d and model3d.has_animation("attack"):
		throw_rubber_arm(target, "attack")
		return
	if attack_range > 1:
		# Ranged units: play their attack-pose sheet if they have one (e.g.
		# Headhunter's aim/fire frames) alongside the projectile; otherwise
		# stay silent here — never lunge toward a target that's far away.
		var played := false
		if unit_class in [UnitBase.UnitClass.ZOLT, UnitBase.UnitClass.RIFT] \
				and model3d and model3d.has_animation("attack"):
			# One complete authored cast per live attack interval. This follows every
			# haste/slow source through attacks_per_second and shares its release
			# fraction with UnitBase.spawn_projectile.
			played = model3d.play_oneshot_timed("attack", 1.0 / attacks_per_second, "idle")
		elif _is_goblin_archer() and model3d and model3d.has_animation("attack"):
			played = play_goblin_bow_shot(target)
		else:
			played = _play_oneshot("attack")
		_face_target_3d(dir_world)   # AFTER play(): needs "attack"'s own yaw bias, not idle's
		# Sear has no model and no sprite sheet, so `played` is ALWAYS false for
		# him and the whole feedback block below was skipped — his auto fired with
		# no muzzle, no particle and no recoil of any kind. Until his art lands he
		# gets an explicit cast beat instead of inheriting one from an animation
		# that does not exist.
		if unit_class == UnitBase.UnitClass.SEAR:
			var sdir: Vector2 = dir_world.normalized() if dir_world.length() > 0.01 else Vector2.UP
			_sear_cast_beat(sdir)
			return
		if played:
			var dir: Vector2 = dir_world.normalized() if dir_world.length() > 0.01 else Vector2.UP
			# Zolt's custom muzzle particle is emitted by Projectile on the authored
			# hands-out frame; an immediate generic burst would double/lead that cue.
			# The goblin archer's arrow waits for the string release the same way.
			if unit_class != UnitBase.UnitClass.ZOLT and not _is_goblin_archer():
				_spawn_particle(attack_particle_pack, 0.22, global_position + dir * 24.0)
			if unit_class == UnitBase.UnitClass.STATIC:
				_static_discharge_recoil(dir)
			elif unit_class == UnitBase.UnitClass.RIFT:
				_rift_void_push(dir)
		return
	# If this unit has a real attack sheet, play the swing and keep just the
	# impact particles — skip the procedural lunge so the two don't fight.
	var played2 := false
	# June's authored attack clip is SIX SECONDS long against a 1.47s attack
	# interval, so the untimed path restarted it from frame 0 every swing and the
	# player only ever saw the first ~24% — the strike itself never played.
	if unit_class in [UnitBase.UnitClass.SHEILDOR, UnitBase.UnitClass.JUNE,
			UnitBase.UnitClass.RIOT] \
			and model3d and model3d.has_animation("attack"):
		played2 = model3d.play_oneshot_timed("attack", 1.0 / attacks_per_second, "idle")
	else:
		played2 = _play_oneshot("attack")
	_face_target_3d(dir_world)
	if played2:
		var dir2: Vector2 = dir_world.normalized() if dir_world.length() > 0.01 else Vector2.UP
		# Sheildor's dedicated impact is emitted on shield contact by the manager.
		if unit_class != UnitBase.UnitClass.SHEILDOR:
			_spawn_particle(attack_particle_pack, 0.22, global_position + dir2 * 24.0)
		return
	play_attack(dir_world)

## Sear's auto cast, for a hero who is still a single static PNG: a short body
## brace and release, plus flame gathering at the casting side on the same beat
## the bolt leaves (SEAR_MUZZLE_FRAC, shared with UnitBase.spawn_projectile so
## haste and slow can never pull the two apart).
func _sear_cast_beat(dir: Vector2) -> void:
	var interval: float = 1.0 / maxf(attacks_per_second, 0.05)
	var t := create_tween()
	t.tween_method(_set_recoil, Vector2.ZERO, -dir * 5.0, interval * 0.18) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_recoil, -dir * 5.0, dir * 9.0, interval * 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_recoil, dir * 9.0, Vector2.ZERO, interval * 0.30) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var at: float = interval * UnitBase.SEAR_MUZZLE_FRAC
	get_tree().create_timer(at).timeout.connect(func():
		if not is_instance_valid(self) or _is_dying:
			return
		var fx := SearVFX.new()
		get_parent().add_child(fx)
		fx.setup_point(SearVFX.Mode.AUTO_MUZZLE,
			global_position + Vector2(0, -20.0) + dir * 20.0, 0.26))

func _static_discharge_recoil(dir: Vector2) -> void:
	# Static's projectile launches 0.22s into the authored attack clip. A short,
	# sharp body kick on that exact beat sells the live-wire discharge without
	# replacing or fighting the model animation.
	var t := create_tween()
	t.tween_interval(0.20)
	t.tween_method(_set_recoil, Vector2.ZERO, -dir * 7.0, 0.045).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_recoil, -dir * 7.0, Vector2.ZERO, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _rift_void_push(dir: Vector2) -> void:
	# The robe hides much of the arm at 115px. A short body brace and release on
	# the same beat as the hand/projectile makes the push readable in combat.
	var interval: float = 1.0 / maxf(attacks_per_second, 0.05)
	var t := create_tween()
	t.tween_method(_set_recoil, Vector2.ZERO, -dir * 4.0, interval * 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_recoil, -dir * 4.0, dir * 10.0, interval * 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_recoil, dir * 10.0, Vector2.ZERO, interval * 0.30) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# A hand-anchored charge makes the free-hand travel legible through the robe.
	var charge := Sprite2D.new()
	charge.texture = _create_glow_texture()
	charge.modulate = Color(0.72, 0.18, 1.0, 0.95)
	charge.z_index = 8
	var hand_side: float = 16.0 if is_player_unit else -16.0
	var hand_start := Vector2(hand_side, -20.0)
	charge.position = hand_start
	charge.scale = Vector2(0.10, 0.10)
	add_child(charge)
	var flare := create_tween()
	flare.set_parallel(true)
	flare.tween_property(charge, "position", hand_start + dir * 24.0, interval * 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flare.tween_property(charge, "scale", Vector2(0.32, 0.32), interval * 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flare.chain().tween_property(charge, "modulate:a", 0.0, interval * 0.10)
	flare.chain().tween_callback(charge.queue_free)
	# Muzzle discharge on the SAME release fraction the projectile uses
	# (UnitBase.spawn_projectile, 0.34 of the live interval), so the bolt never
	# leaves the hand before or after the hand crackles.
	var muzzle_at: float = interval * 0.34
	get_tree().create_timer(muzzle_at).timeout.connect(func():
		if not is_instance_valid(self) or _is_dying:
			return
		var fx := RiftVFX.new()
		get_parent().add_child(fx)
		# Anchored to the casting HAND (same offset the charge sprite uses), not
		# the body centre — otherwise the discharge reads as a hit on Rift.
		fx.setup_point(RiftVFX.Mode.AUTO_MUZZLE,
			global_position + hand_start + dir * 14.0, 0.26))

# 3D model: actually turn to face the target. Must run AFTER _play_oneshot()
# switches the clip, not before — face_direction() applies the CURRENTLY
# playing clip's yaw bias (Model3DSprite._yaw_bias_deg, refreshed by play()),
# and a bladed stance like Headhunter's aim/attack needs its OWN bias, not
# whatever the previous clip (idle) left behind. The 2D sprite roster already
# turns via its own directional-sheet picker in _update_animation(); this is
# the 3D equivalent (user report 2026-09-06: he always faced the same way
# no matter which direction he attacked; 2026-09-07: bladed-stance skew).
func _face_target_3d(dir_world: Vector2) -> void:
	if unit_class == UnitBase.UnitClass.STITCH and model3d:
		_face_stitch_cast_3d()
		return
	if model3d and dir_world.length() > 0.01:
		model3d.face_direction(dir_world)

## Stitch works on the doll, so his combat silhouette faces the viewer.
## Use the same angle between casts; target changes must not spin him around.
func _face_stitch_cast_3d() -> void:
	if unit_class == UnitBase.UnitClass.STITCH and model3d:
		model3d.face_direction(Vector2(0.174, 0.985)) # 10 degrees off camera

## How long after a shot the character keeps the weapon up. A ranged unit
## re-attacks on a cooldown, so without a hold it would holster the rifle to
## its back between every shot and whip it out again — the gun would flicker.
## Long enough to bridge a normal attack cadence, short enough that a unit
## which genuinely disengages drops back to walk/idle.
const ENGAGED_HOLD_MS := 2500
var _engaged_until_ms: int = 0
var _engaged_dir: Vector2 = Vector2.ZERO

## "Mid-fight", inferred from having attacked recently rather than plumbed
## through from the combat layer — _on_attacked() is already the one place the
## visual layer is told about a target, and this keeps the animation choice a
## purely presentational concern.
func _is_engaged() -> bool:
	return Time.get_ticks_msec() < _engaged_until_ms and _engaged_dir.length() > 0.01

# Pick element-themed particle packs (called from _ready once element is set).
func _assign_element_particles() -> void:
	var packs = ELEMENT_PARTICLES.get(current_element, ELEMENT_PARTICLES[UnitBase.Element.NORMAL])
	attack_particle_pack = packs["atk"]
	hit_particle_pack = packs["hit"]

# A particle burst at this unit — used when it fires a skill or ultimate so every
# move reads as an action even before the procedural SkillEffect lands.
func cast_particles() -> void:
	if _is_dying:
		return
	var dir: Vector2 = Vector2.UP if is_player_unit else Vector2.DOWN
	_spawn_particle(attack_particle_pack, 0.35, global_position + dir * 18.0)

# Play the 3D model's "ult" clip as a one-shot. The 2D VFX (ring/particle
# sprite sheet) for an ultimate is spawned separately by the ability itself in
# auto_battle_manager.gd and is untouched by this — this is ONLY the body
# animation. No-ops for any character with no model3d or no authored "ult"
# clip, so it's safe to call unconditionally from every ultimate.
#
# Missing entirely until 2026-09-06: Bouncer's Gravity Drop ult had a real
# "ult" clip with a bulk-morph body expansion (built and verified playing
# correctly in isolation — Godot's own AnimationPlayer drives the blend shape
# fine), but nothing ever told the model to switch TO that clip when the
# ability fired. He just kept playing whatever he was already doing (idle or
# mid-attack) underneath the VFX, so the body never visibly changed.
##
## `speed` plays the clip in step with the battle clock (pass the manager's
## time_scale). Clips otherwise run in real time while combat runs at
## time_scale — 0.8 on the "1×" button — which matters for an ult whose travel
## and hit are timed against its own frames (Bloodhound's Pounce).
func play_ult_oneshot(speed: float = 1.0) -> void:
	if not model3d or not model3d.has_animation("ult"):
		return
	if is_equal_approx(speed, 1.0):
		model3d.play_oneshot("ult", "idle")
	else:
		model3d.play_oneshot_timed("ult", model3d.animation_length("ult") / maxf(speed, 0.05), "idle")
	_face_stitch_cast_3d()

## Bouncer's rubber punch (2026-09-24). The 3D clip does the wind-up and lunge
## and tucks the real lead arm away; RubberArm draws the arm that actually
## reaches the target, at any distance. Both run on battle time — the clip via
## play_oneshot_timed, the arm via its own clock — and UnitBase lands the damage
## at BOUNCER_PUNCH_CONTACT on that same clock, so glove, number and clip agree.
const RubberArmScript := preload("res://scripts/combat/rubber_arm.gd")
##
## `out`/`hold`/`back` < 0 keep the punch defaults. A longer throw (the grab)
## slows the whole body clip so its tuck window still covers the drawn arm:
## the clip launches at CLIP_LAUNCH_FRAC and regrows the 3D arm at
## CLIP_RETURN_FRAC of its length (bouncer_v002 `attack`: f4.5 and f12.5 of 18).
const CLIP_LAUNCH_FRAC := 4.5 / 18.0
const CLIP_RETURN_FRAC := 12.5 / 18.0
func throw_rubber_arm(target, clip: String = "attack", out: float = -1.0,
		hold: float = -1.0, back: float = -1.0) -> RubberArm:
	if _is_dying or not (target and is_instance_valid(target)) or not model3d:
		return null
	var ts: float = 1.0
	if battle_manager and battle_manager.get("time_scale") != null:
		ts = maxf(float(battle_manager.time_scale), 0.05)
	var arm: RubberArm = RubberArmScript.new()
	if out > 0.0: arm.out_time = out
	if hold > 0.0: arm.hold_time = hold
	if back > 0.0: arm.back_time = back
	var clip_len: float = model3d.animation_length(clip)
	var active: float = arm.out_time + arm.hold_time + arm.back_time
	# battle seconds the clip should take so launch..regrow spans the arm
	var dur: float = maxf(clip_len, active / (CLIP_RETURN_FRAC - CLIP_LAUNCH_FRAC) + 0.02)
	arm.launch_delay = dur * CLIP_LAUNCH_FRAC if dur > clip_len else arm.launch_delay
	model3d.play_oneshot_timed(clip, dur / ts, _resume_clip())
	_face_target_3d(target.global_position - global_position)
	var host: Node = battle_manager.skill_effect_container \
		if battle_manager and battle_manager.get("skill_effect_container") else get_parent()
	host.add_child(arm)
	arm.setup(self, target)
	return arm

func _is_goblin_archer() -> bool:
	return str(get_meta("sprite_folder", "")) == "goblin_archer"

## Goblin Archer bow shot, for his auto AND Crippling Arrow (which used to fire
## with no body motion). One authored shot per attack interval, in real seconds;
## UnitBase holds the arrow for GOBLIN_ARROW_RELEASE_FRAC of the same number, so
## the arrow leaves on the string-release frame at any haste / battle speed.
func play_goblin_bow_shot(target) -> bool:
	if _is_dying or not (target and is_instance_valid(target)):
		return false
	var played := false
	if model3d and model3d.has_animation("attack"):
		played = model3d.play_oneshot_timed("attack", goblin_shot_seconds(), _resume_clip())
	else:
		played = _play_oneshot("attack")
	_face_target_3d(target.global_position - global_position)
	return played

## Turn to face an on-screen direction outside an auto-attack — Bloodhound's
## Pounce faces its victim from the crouch, before any swing has set a facing.
func face_toward(dir_world: Vector2) -> void:
	_face_target_3d(dir_world)

## Height of Bloodhound's Pounce arc, in px, driven from the battle tick so it
## stays locked to the travel at any battle speed. Rides _toss_offset (the Long
## Fall / knock-up layer): the sprite, health bar and glow lift while the contact
## shadow stays on the ground, and clear_long_fall() resets it at battle start.
func set_pounce_height(px: float) -> void:
	_toss_offset = Vector2(0.0, -px)

func play_skill_oneshot() -> void:
	if model3d and model3d.has_animation("skill"):
		model3d.play_oneshot("skill", "idle")
		_face_stitch_cast_3d()

## Start a generic skill clip only when the ability itself has not already
## started an authored action (for example a lunge or wind-up).
func play_generic_skill_action() -> void:
	if model3d and model3d.has_animation("skill") and not model3d.is_oneshot_playing():
		play_skill_oneshot()

## As above for ultimates. Ability-specific timing may start its own ultimate
## clip later, so do not restart an action that has already begun.
func play_generic_ult_action(speed: float = 1.0) -> void:
	if model3d and model3d.has_animation("ult") and not model3d.is_oneshot_playing():
		play_ult_oneshot(speed)

# Basic monsters can reuse their authored attack strip for a melee signature
# without emitting the gameplay `attacked` signal (which would deal another hit).
func play_skill_attack(target) -> void:
	if _is_dying or not (target and is_instance_valid(target)):
		return
	var dir_world: Vector2 = target.global_position - global_position
	var played := _play_oneshot("attack")
	_face_target_3d(dir_world)
	if not played:
		play_attack(dir_world)

func play_stitch_rupture_stab(duration: float) -> void:
	if model3d and model3d.has_animation("attack"):
		model3d.play_oneshot_timed("attack", duration, "idle")
		_face_stitch_cast_3d()

func play_attack(dir_world: Vector2) -> void:
	var dir: Vector2 = dir_world.normalized() if dir_world.length() > 0.01 else Vector2.UP
	var peak: Vector2 = dir * 15.0
	# Attack-impact particles at the strike point.
	_spawn_particle(attack_particle_pack, 0.22, global_position + dir * 24.0)

	var t := create_tween()
	# tiny wind-up the other way (anticipation), then lunge, then settle
	t.tween_method(_set_lunge, Vector2.ZERO, -dir * 5.0, 0.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_lunge, -dir * 5.0, peak, 0.07) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_lunge, peak, Vector2.ZERO, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var t2 := create_tween()
	t2.tween_method(_set_punch, Vector2.ONE, Vector2(1.12, 0.9), 0.1)
	t2.tween_method(_set_punch, Vector2(1.12, 0.9), Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Hit: white flash + knockback recoil + squash + particles ────────────────
func _on_took_damage(_amount: int, attacker) -> void:
	if _is_dying:
		return
	# DEFERRED, not decided here. Every stunning ability in auto_battle_manager
	# calls take_damage() THEN apply_stun() (Pounce, Riot Shield Bash, Crushing
	# Blow, the lightning ult — checked every call site 2026-09-06, only one
	# outlier applies stun first). took_damage fires synchronously from inside
	# take_damage(), which is BEFORE that same ability's apply_stun() line has
	# run — so stun_time read right here would still be last frame's value, not
	# the stun this very hit is about to apply. Deferring to end-of-frame lets
	# the ability finish its own synchronous apply_stun() call first.
	call_deferred("_resolve_hit_reaction", attacker)

func _resolve_hit_reaction(attacker) -> void:
	if _is_dying:
		return
	var dir := Vector2.UP
	if attacker and is_instance_valid(attacker):
		var d: Vector2 = global_position - attacker.global_position
		if d.length() > 0.01:
			dir = d.normalized()
	# The full hurt clip is a flinch/stagger — it should read as "this hit
	# rocked him", not fire on every routine auto-attack. Gated to stunned
	# hits only (user call, 2026-09-06: it was playing on every hit and
	# drowning out attack/idle). An un-stunned hit still gets full impact
	# feedback, just via the lighter procedural recoil every 2D-only hero
	# already uses.
	if stun_time > 0.0 and _play_oneshot("hurt"):
		create_tween().tween_method(_set_flash, 1.0, 0.0, 0.18)
	else:
		play_hit(dir)
	_spawn_particle(hit_particle_pack, 0.05, global_position)

func play_hit(dir: Vector2) -> void:
	var kb: Vector2 = dir * 7.0
	var t := create_tween()
	t.tween_method(_set_recoil, Vector2.ZERO, kb, 0.05).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_recoil, kb, Vector2.ZERO, 0.20) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	var t2 := create_tween()
	t2.tween_method(_set_squash, Vector2.ONE, Vector2(1.15, 0.85), 0.05)
	t2.tween_method(_set_squash, Vector2(1.15, 0.85), Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	create_tween().tween_method(_set_flash, 1.0, 0.0, 0.18)

# ── Death: topple + shrink + fade + particle fade ──────────────────────────
func die() -> void:
	if _is_dying:
		return
	# Khagan's mind-controlled puppet (a player's own hero, temporarily fighting
	# for the enemy side): a lethal hit clamps to 1 HP and STAYS there — no
	# partial-heal floor (2026-07-08 user spec) — breaking the possession
	# instead of really dying: bursting the puppet to 0 HP frees it EARLY (the
	# other break path is the survival timer in _tick_khagan_possession). Checked
	# FIRST since a single big hit can overshoot straight past 1 to a negative
	# number, so this can't be a polling threshold check — it must intercept
	# every death path the same way Phoenix Pact/Triarch do below.
	# end_khagan_possession restores loaned stats; the between-round row heal tops
	# it up afterward like any survivor, since home_position was never touched.
	if has_meta("khagan_puppet") and current_hp <= 0:
		current_hp = 1   # setter emits health_changed
		current_shield = 0
		if battle_manager and battle_manager.has_method("end_khagan_possession"):
			battle_manager.end_khagan_possession(self)
		return
	# Triple-Threat boss: transform into its next attack-type phase instead of
	# dying, until the final phase is actually defeated (see EnemyFactory).
	if has_meta("triarch_phase") and current_hp <= 0 \
			and EnemyFactory.advance_triarch_phase(self):
		return
	# Khagan (mount-swap boss): phase 1→2 transforms in place (same mechanism as
	# Triarch above); phase 2's "death" instead channels into a captured hero
	# (see EnemyFactory.advance_khagan_phase) and then Khagan's own body really
	# does die — the puppet now carries the fight.
	if has_meta("khagan_phase") and current_hp <= 0 \
			and EnemyFactory.advance_khagan_phase(self):
		return
	# Phoenix Pact relic: cheat death once per battle instead of dying. Mirrors
	# UnitBase.die() (that base version is shadowed by this override, so the
	# revive check must live here too).
	if relic_revive_pct > 0.0 and not relic_revive_used and current_hp <= 0:
		relic_revive_used = true
		current_hp = maxi(1, int(round(max_hp * relic_revive_pct)))   # setter emits health_changed
		current_shield = 0
		return
	# Skeleton "Undying": the first time it would die, it reassembles once at 35% HP
	# instead of dying (same cheat-death mechanism as Phoenix Pact above).
	if has_meta("mob_passive") and str(get_meta("mob_passive")) == "skeleton_undying" \
			and not has_meta("undying_used") and current_hp <= 0:
		set_meta("undying_used", true)
		current_hp = maxi(1, int(round(max_hp * 0.35)))   # setter emits health_changed
		current_shield = 0
		# Announce it. Reassembling was previously silent, so a Skeleton standing
		# back up looked identical to one that simply had not died yet.
		if battle_manager and battle_manager.has_method("spawn_skeleton_reassemble"):
			battle_manager.spawn_skeleton_reassemble(self)
		return
	# Phoenix "Rebirth": the first death starts a short rebuild instead — immune
	# and unable to act while HP climbs back to PHOENIX_REBIRTH_HP (ticked in
	# AutoBattleManager._tick_mob_passive). Once per fight.
	if has_meta("mob_passive") and str(get_meta("mob_passive")) == "phoenix_rebirth" \
			and not has_meta("rebirth_used") and current_hp <= 0:
		set_meta("rebirth_used", true)
		current_hp = 1   # setter emits health_changed
		current_shield = 0
		rebirth_time = AutoBattleManager.PHOENIX_REBIRTH_TIME
		stun_time = maxf(stun_time, rebirth_time)
		if battle_manager and battle_manager.has_method("spawn_phoenix_rebirth"):
			battle_manager.spawn_phoenix_rebirth(self)
		return
	# Slime "Split": a real death spawns two smaller slimes (handled by the battle
	# manager, which owns the grid + unit arrays). Guarded there against splitting
	# the children again, so it stays one generation.
	if has_meta("mob_passive") and str(get_meta("mob_passive")) == "slime_split" and current_hp <= 0 \
			and battle_manager and battle_manager.has_method("spawn_slime_split"):
		battle_manager.spawn_slime_split(self)
	# Emberhollow (wave-50 boss): while either Ember Heart still burns, a lethal
	# hit only banks the kill — it returns at EMBERHOLLOW_REVIVE_HP. Sits with the
	# other cheat-death paths above, and like them restores HP to >= 1 before
	# returning, so every "is it dead" check in the game stays consistent.
	if has_meta("emberhollow_revive") and not has_meta("emberhollow_revived") \
			and current_hp <= 0 and battle_manager \
			and battle_manager.has_method("emberhollow_hearts_alive") \
			and battle_manager.emberhollow_hearts_alive(self):
		set_meta("emberhollow_revived", true)
		current_hp = maxi(1, int(round(max_hp * AutoBattleManager.EMBERHOLLOW_REVIVE_HP)))
		current_shield = 0
		if battle_manager.has_signal("action_logged"):
			battle_manager.action_logged.emit(
				"%s reignites — the Hearts still burn!" % unit_name, false)
		return
	# Cloven Titan (wave-40 boss): the crack down its middle finally gives and it
	# comes apart into two 1×1 halves. Same shape as the slime split above — the
	# boss's own death is REAL (loot/xp fire normally), the halves are what's left
	# to finish. Separate function because a 2×2 parent needs a wider spawn ring
	# than the slime's immediate neighbours.
	if has_meta("cloven_split") and current_hp <= 0 \
			and battle_manager and battle_manager.has_method("spawn_cloven_halves"):
		battle_manager.spawn_cloven_halves(self)
	# Gravekeeper (wave-90 boss): anything that falls while it still stands gets
	# back up on ITS side. Runs after every cheat-death path above, so a hero that
	# survives via Phoenix Pact / Undying is never raised — only a real death.
	if current_hp <= 0 and not has_meta("grave_shade") \
			and battle_manager and battle_manager.has_method("gravekeeper_active") \
			and battle_manager.gravekeeper_active(is_player_unit):
		battle_manager.gravekeeper_raise_shade(self)
	# Khagan's own body really dying now (phase 1/2 both funnel through the
	# advance_khagan_phase returns above before ever reaching here) — stop the
	# ambient body pulse immediately rather than let it tween through the
	# death-fade.
	if has_meta("khagan_phase"):
		stop_khagan_body_pulse()
	_is_dying = true
	can_be_dragged = false
	# Terracotta Colossus: a REAL death crumbles into falling masonry.
	if has_meta("mob_passive") and str(get_meta("mob_passive")) == "terracotta_harden" \
			and battle_manager and battle_manager.has_method("spawn_terracotta_rubble"):
		battle_manager.spawn_terracotta_rubble(self)
	# Stat Stealer: return any stats it's currently holding stolen — only on a
	# REAL death (this point), not the phase-transform / relic-revive returns above.
	if battle_manager and battle_manager.has_method("restore_stat_theft"):
		battle_manager.restore_stat_theft(self)
	died.emit()                       # main_game removes us from arrays + grid now
	if health_bar:
		health_bar.visible = false

	_spawn_particle(death_particle_pack, 0.35, global_position)  # start fading death particles

	# Real death sheet: let it play out (it ends on a collapsed pose and is
	# pinned there by the _is_dying guard in _update_animation), then fade + free
	# once the clip has finished. No procedural topple — the frames own the fall.
	if _play_oneshot("death"):
		var dur: float = _oneshot_duration("death")
		_death_tween = create_tween()
		_death_tween.tween_interval(dur)
		_death_tween.tween_method(_set_death_alpha, 1.0, 0.0, 0.25).set_ease(Tween.EASE_IN)
		_death_tween.tween_callback(_after_death_anim)
		return

	var topple: float = 0.5 if randf() > 0.5 else -0.5   # ~28°, random side
	_death_tween = create_tween()
	_death_tween.set_parallel(true)
	_death_tween.tween_method(_set_death_rot, 0.0, topple, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_death_tween.tween_method(_set_death_alpha, 1.0, 0.0, 0.35).set_ease(Tween.EASE_IN)
	_death_tween.tween_method(_set_punch, _punch_scale, Vector2(0.7, 0.7), 0.35)
	_death_tween.set_parallel(false)
	_death_tween.tween_callback(_after_death_anim)

# Death animation finished. A player HERO is no longer freed here (2026-07-24
# design change: heroes are never permanently lost — they come back at 10% HP
# at the end of the round, see main_game._revive_downed_heroes). Its node is
# simply parked invisible, keeping level/XP/equipment/recruit-rolls intact
# because it stays the very same object. Enemies, summons and Doc's revivals
# still free normally.
func _after_death_anim() -> void:
	if is_player_unit and not is_summoned:
		visible = false
		# A parked hero keeps its node (and, on the 3D path, a live SubViewport)
		# for the rest of the run — stop rendering it, or every hero that ever
		# died goes on costing a 3D render pass per frame while invisible.
		if model3d:
			model3d.set_paused(true)
		return
	queue_free()

# Bring a parked (or mid-battle downed) hero back to life at `hp_pct` of max.
# Undoes everything die() did visually AND clears the status effects that
# killed them, so a revived hero can't be instantly re-killed by a leftover
# burn/bleed tick. Used by both the end-of-round revival and Doc's Field
# Surgery ultimate.
func revive(hp_pct: float) -> void:
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null
	_is_dying = false
	visible = true
	if model3d:
		model3d.set_paused(false)   # undo the park in _after_death_anim
		# A revive can land while the death clip is still running; its one-shot
		# guard would keep _update_model3d_animation away and leave the body lying
		# in the death pose (health bar back) until the hero's next action.
		model3d.cancel_oneshot()
		model3d.play("idle")
	_death_alpha = 1.0
	_death_rotation = 0.0
	# Thrown off the board by Skyrender's (fatal) Long Fall: the body was left
	# parked off-screen -- bring it back with the hero (2026-10-04, revived heroes
	# were invisible all through the next prep phase).
	_toss_offset = Vector2.ZERO
	_punch_scale = Vector2.ONE
	_hit_squash = Vector2.ONE
	_flash = 0.0
	current_hp = maxi(1, int(round(float(max_hp) * hp_pct)))   # setter emits health_changed
	current_shield = 0
	# Wipe the damage-over-time / control statuses that were on them when they
	# fell — reviving into an active burn would just kill them again.
	burn_time = 0.0; bleed_time = 0.0
	stun_time = 0.0; root_time = 0.0; slow_time = 0.0
	taunt_time = 0.0; taunt_source = null
	spore_stacks = 0.0
	is_moving = false
	move_progress = 0.0
	if health_bar:
		health_bar.visible = true
	_apply_animation()
	_update_animation()
	update_visuals()

# ── The Long Fall (Skyrender, wave 20) ────────────────────────────────────────
# REDESIGNED 2026-08-04: the boss now visibly CARRIES the victim toward the
# board edge before throwing (see the manager's _skyrender_long_fall for why —
# user feedback on the first cut was "sudden with no logic"; the carry IS the
# logic). Sequence: GRAB (hoist) → CARRY (footstep-bounce trek toward the edge,
# in step with the boss's own play_aerial_snatch below) → a held beat at the edge
# → THROW (launches off-screen) → GONE (real absence) → RE-ENTRY (falls from
# the opposite edge) → lands, impact squash. `carry_dir` is +1 toward the
# bottom of the screen, -1 toward the top — the exit and re-entry edges always
# mirror each other, so a +1 carry exits bottom and re-enters top.
const LONG_FALL_OFFSCREEN := 1400.0        # px of travel — must clear the tallest viewport
const LONG_FALL_CARRY_DISTANCE := 260.0    # px hauled toward the edge before the throw

## `lead_t` holds the hero in place first (the aerial snatch: the boss is still
## swooping in). `glide` carries them in one smooth line -- they're flown, not
## hauled on foot -- instead of the footstep bounce.
## `carry_px` (> 0): how far to carry, in this unit's local px -- the measured
## distance to the board edge (owner 2026-10-04: "should go to the edge", the
## fixed 260 dropped front-liners mid-board). 0 keeps the old fixed distance.
func play_long_fall(grab_t: float, carry_t: float, edge_pause_t: float, throw_t: float,
		gone_t: float, reentry_t: float, carry_dir: float = 1.0, lead_t: float = 0.0,
		glide: bool = false, carry_px: float = 0.0, fatal: bool = false) -> void:
	if _is_dying:
		return
	# The bar would otherwise hang in mid-air over an empty square, which reads
	# as a rendering bug rather than "that hero is gone".
	if health_bar:
		health_bar.visible = false

	var carry_y: float = (carry_px if carry_px > 0.0 else LONG_FALL_CARRY_DISTANCE) * carry_dir
	var t := create_tween()
	if lead_t > 0.0:
		t.tween_interval(lead_t)
	# GRAB — snatched upward first, anticipation that sells being GRABBED.
	t.tween_method(_set_toss, Vector2.ZERO, Vector2(0, -50), grab_t) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# CARRY — three footstep-bounce steps toward the edge rather than one smooth
	# glide, or the hero reads as floating instead of being hauled along. (In the
	# aerial snatch it IS flown, so it glides.)
	var steps := 1 if glide else 3
	var step_t: float = carry_t / float(steps)
	var prev: Vector2 = Vector2(0, -50)
	for i in range(steps):
		var frac: float = float(i + 1) / float(steps)
		var base_y: float = lerp(-50.0, carry_y, frac)
		if i < steps - 1:
			var wobble := Vector2(8.0 if i % 2 == 0 else -8.0, base_y - 10.0)
			t.tween_method(_set_toss, prev, wobble, step_t * 0.5) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			t.tween_method(_set_toss, wobble, Vector2(0, base_y), step_t * 0.5) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			prev = Vector2(0, base_y)
		else:
			t.tween_method(_set_toss, prev, Vector2(0, carry_y), step_t) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			prev = Vector2(0, carry_y)

	# EDGE PAUSE — held at the edge, the "about to throw" reveal beat.
	t.tween_interval(edge_pause_t)

	# THROW — launches off-screen from the carry position, accelerating.
	t.tween_method(_set_toss, Vector2(0, carry_y),
			Vector2(90 * carry_dir, LONG_FALL_OFFSCREEN * carry_dir), throw_t) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# `fatal` (Skyrender, owner 2026-10-04): thrown off the board for good -- no
	# re-entry; the manager kills the unit as it leaves.
	if fatal:
		return
	# GONE — real absence. Parked far off-screen so nothing peeks in at any
	# resolution.
	t.tween_interval(gone_t)

	# RE-ENTRY — falls from the OPPOSITE edge and slams into its landing cell.
	t.tween_callback(func(): _set_toss(Vector2(0, -LONG_FALL_OFFSCREEN * carry_dir)))
	t.tween_method(_set_toss, Vector2(0, -LONG_FALL_OFFSCREEN * carry_dir), Vector2.ZERO, reentry_t) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_on_long_fall_land)

# The aerial snatch (owner 2026-10-04: the Long Fall happens from the sky now
# that Skyrender has real wings). The BOSS body swoops from its own square to
# hover just above the victim, rides along over them through the carry, lets go
# at the edge and climbs, then flies home. `to_victim` is the victim's feet in
# this unit's local space. Purely visual -- grid_position never moves; drawn on
# top of everything for the duration so its talons sit OVER the hero.
const SNATCH_HOVER := 40.0   # px the boss's feet ride above the victim's

func play_aerial_snatch(to_victim: Vector2, swoop_t: float, grab_t: float, carry_t: float,
		edge_pause_t: float, throw_t: float, return_t: float, carry_dir: float = 1.0,
		to_edge: Vector2 = Vector2.INF) -> void:
	if _is_dying:
		return
	# `to_edge`: the board-edge point under the victim's column, in THIS unit's
	# local space (the boss and the hero sit at different row scales, so a shared
	# px distance would part them mid-carry). INF = old fixed distance.
	var carry_y: float = LONG_FALL_CARRY_DISTANCE * carry_dir
	if to_edge != Vector2.INF:
		carry_y = to_edge.y - to_victim.y
	var over := func(victim_toss_y: float) -> Vector2:
		return to_victim + Vector2(0, victim_toss_y - SNATCH_HOVER)
	var old_z: int = z_index
	z_index = 40
	var t := create_tween()
	# SWOOP -- in over the victim, still standing on its square.
	t.tween_method(_set_toss, Vector2.ZERO, over.call(0.0), swoop_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# GRAB -- talons close as the hero is hoisted.
	t.tween_method(_set_toss, over.call(0.0), over.call(-50.0), grab_t) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# CARRY -- flown toward the edge with the hero underneath.
	t.tween_method(_set_toss, over.call(-50.0), over.call(carry_y), carry_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_interval(edge_pause_t)
	# DROP -- lets go and climbs away as the hero is flung off.
	t.tween_method(_set_toss, over.call(carry_y), over.call(carry_y) + Vector2(0, -70), throw_t) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# HOME -- back to its own square.
	t.tween_method(_set_toss, over.call(carry_y) + Vector2(0, -70), Vector2.ZERO, return_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func(): z_index = old_z)

func _on_long_fall_land() -> void:
	_set_toss(Vector2.ZERO)
	if health_bar and not _is_dying:
		health_bar.visible = true
	if _is_dying:
		return
	# Impact: hard squash + flash, reusing the existing hit-feel layers.
	var t := create_tween()
	t.tween_method(_set_squash, Vector2(1.45, 0.55), Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	create_tween().tween_method(_set_flash, 1.0, 0.0, 0.22)

# Vail Updraft: whirls the target up off the ground and spins them for the
# untargetable window, then sets them back down. `duration` is the ability's
# untargetable_time (short — ~1s) so the whole rise/spin/fall reads as one
# quick gust rather than a slow float. Purely visual; grid_position never moves.
const UPDRAFT_LIFT_HEIGHT := 46.0
func play_updraft_lift(duration: float) -> void:
	if _is_dying:
		return
	var rise_t: float = clampf(duration * 0.3, 0.08, 0.35)
	var fall_t: float = clampf(duration * 0.3, 0.08, 0.35)
	var hold_t: float = maxf(duration - rise_t - fall_t, 0.0)

	var t := create_tween()
	t.tween_method(_set_updraft, Vector2.ZERO, Vector2(0, -UPDRAFT_LIFT_HEIGHT), rise_t) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var last_y: float = -UPDRAFT_LIFT_HEIGHT
	if hold_t > 0.0:
		# Small bob while airborne so it reads as caught in a swirling gust,
		# not just parked in the air.
		var bob_steps: int = maxi(1, int(hold_t / 0.18))
		var step_t: float = hold_t / bob_steps
		for i in range(bob_steps):
			var y: float = -UPDRAFT_LIFT_HEIGHT + (4.0 if i % 2 == 0 else -4.0)
			t.tween_method(_set_updraft, Vector2(0, last_y), Vector2(0, y), step_t) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			last_y = y
	t.tween_method(_set_updraft, Vector2(0, last_y), Vector2.ZERO, fall_t) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	# Horizontal spin for the whole airborne window — driven per-frame in
	# _process (see _updraft_spin_x), not a tween, since the spin is a
	# cosine oscillation rather than a lerp between two fixed values.
	_updraft_spin_active = true
	_updraft_spin_turns = UPDRAFT_SPIN_TURNS
	_updraft_spin_t0 = _anim_time
	_updraft_spin_dur = duration

# Hard reset — used at battle start. A unit whose Long Fall was interrupted by
# the round ending has a dead tween and would stay parked off-screen forever.
func clear_long_fall() -> void:
	_toss_offset = Vector2.ZERO
	if health_bar and not _is_dying:
		health_bar.visible = true

# ── Wind-Up Punch knock-up (Wind-Up Bot) ─────────────────────────────────────
# A Blitzcrank-style punt: the target is launched straight up on the fist's
# contact frame, tumbles helplessly through the stun, and slams back down into
# ITS OWN SQUARE as the stun expires. Purely visual — grid_position never
# changes, so this cannot strand a cell the way a real displacement would
# (see CONVENTIONS §1 phantom-cell test for why that matters).
#
# `duration` is the stun ACTUALLY applied after tenacity, not the nominal 1.5s,
# so the landing and the recovery are the same beat. A victim with high
# tenacity gets a correspondingly shorter, lower hop — the height reads the
# real duration instead of lying about it.
#
# Deliberately built on _toss_offset rather than Vail's _updraft_offset: this
# is a hard ballistic punt, not a swirling gust, and _toss_offset is the layer
# with the battle-start hard reset above (an interrupted knock-up cannot leave
# a hero parked in mid-air next round).
const KNOCKUP_PEAK_HEIGHT := 129.0
## Terracotta Colossus slam (2026-09-30): the body rears UP through the windup
## (taller, narrower), then crashes DOWN (squashed wide) and settles. Still art
## has no slam clip, so this is done on the same punch-scale layer as attacks.
func play_slam_wind(duration: float) -> void:
	var t := create_tween()
	t.tween_method(_set_punch, Vector2.ONE, Vector2(0.93, 1.10), duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func play_slam_hit() -> void:
	var t := create_tween()
	t.tween_method(_set_punch, Vector2(1.14, 0.84), Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Forced displacement (Cyclone Shove etc.): the unit has ALREADY been placed
## on its new tile; this only makes the body visibly slide there from
## `from_world` instead of snapping. Purely visual — grid position, targeting
## and movement are untouched, so it can't desync the board.
func play_shove_slide(from_world: Vector2, duration: float = 0.22) -> void:
	var start: Vector2 = to_local(from_world)   # local: units carry a per-row perspective scale
	var t := create_tween()
	t.tween_method(_set_shove, start, Vector2.ZERO, duration) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Rift's Tear: the victim FALLS INTO a portal where it stood and DROPS OUT of
## one at the destination (owner 2026-10-01). Like play_shove_slide, the unit has
## ALREADY been placed on its new tile by the grid — this only decides where the
## BODY is while it gets there, so targeting, pathing and the grid never disagree.
##
## Three beats, and the shrink is what sells it: a 2D sprite has no depth, so
## "goes down a hole" has to be read as sinking AND getting smaller, the same
## trick the toss uses in reverse. The body is squashed to a sliver at the bottom
## of the sink so it vanishes into the portal's mouth rather than clipping through
## the ground plane.
##   SINK  stand on the OLD tile, drop into the portal, squash to a sliver
##   HANG  gone — nothing drawn where either portal is
##   DROP  reappear high over the NEW tile and accelerate down, landing squash
##
## SPEED: the tween runs on Godot's REAL clock, but battle pace is a manual
## `time_scale` the simulation applies to its own deltas (it is NOT
## Engine.time_scale), so an unscaled tween ignores the pace control entirely --
## at 0.25x the board crawled while this still played full speed. set_speed_scale
## binds it to the battle clock. A pace change MID-DROP is not re-applied; the
## whole move is ~1s, so it would have to be changed inside that window.
const PORTAL_SINK_PX := 34.0    # how far the body drops into the mouth
const PORTAL_RISE_PX := 88.0    # how high above the destination it re-enters
func play_portal_drop(from_world: Vector2, sink: float = 0.34,
		hang: float = 0.12, drop: float = 0.38) -> void:
	if _is_dying:
		return
	var start: Vector2 = to_local(from_world)   # local: units carry a per-row perspective scale
	var gone := Vector2(0.62, 0.04)
	_set_portal_off(start)
	_set_portal_scl(Vector2.ONE)
	var t := create_tween()
	var pace: float = 1.0
	if battle_manager and is_instance_valid(battle_manager):
		var ts = battle_manager.get("time_scale")
		if ts != null:
			pace = maxf(0.05, float(ts))
	t.set_speed_scale(pace)
	t.tween_method(_set_portal_off, start, start + Vector2(0.0, PORTAL_SINK_PX), sink) 		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.parallel().tween_method(_set_portal_scl, Vector2.ONE, gone, sink) 		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# Park it at the destination's entry point while it is invisible, so the
	# drop does not start by sliding across the board in full view.
	t.tween_callback(func() -> void: _set_portal_off(Vector2(0.0, -PORTAL_RISE_PX)))
	t.tween_interval(hang)
	t.tween_method(_set_portal_off, Vector2(0.0, -PORTAL_RISE_PX), Vector2.ZERO, drop) 		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.parallel().tween_method(_set_portal_scl, gone, Vector2.ONE, drop * 0.7) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Land. Reset both channels to identity so nothing leaks into the next clip.
	t.tween_method(_set_portal_scl, Vector2(1.18, 0.80), Vector2.ONE, 0.16) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		_set_portal_off(Vector2.ZERO)
		_set_portal_scl(Vector2.ONE))


func play_knockup(duration: float) -> void:
	if _is_dying:
		return
	var dur: float = maxf(duration, 0.2)
	# Ballistic, not symmetric: a fast punt, a brief hang at apex, then an
	# accelerating fall. Apex sits ~40% in so the rise reads as violent.
	var rise_t: float = dur * 0.34
	var hang_t: float = dur * 0.22
	var fall_t: float = dur - rise_t - hang_t
	var peak: float = KNOCKUP_PEAK_HEIGHT * clampf(dur / 1.5, 0.55, 1.0)

	var t := create_tween()
	t.tween_method(_set_toss, Vector2.ZERO, Vector2(0, -peak), rise_t) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Hang: drifts up a few more px and stalls, the classic top-of-arc beat.
	t.tween_method(_set_toss, Vector2(0, -peak), Vector2(0, -peak - 5.0), hang_t) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_toss, Vector2(0, -peak - 5.0), Vector2.ZERO, fall_t) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_on_knockup_land)

	# ONE full 360 across the airborne window, reusing the Updraft spin layer (a
	# horizontal scale oscillation: 1 -> -1 -> 1 is front, edge, back, edge,
	# front). Exactly one turn reads as a single deliberate flip; Vail's two
	# turns read as tumbling, which is right for a gust and wrong for a punch.
	# Scale rather than rotation on purpose — a real rotation would fight the
	# foot-pinned sprite offset.
	_updraft_spin_active = true
	_updraft_spin_turns = 1.0     # exactly one clean 360 across the airborne window
	_updraft_spin_t0 = _anim_time
	_updraft_spin_dur = dur

func _on_knockup_land() -> void:
	_set_toss(Vector2.ZERO)
	if _is_dying:
		return
	# Hard landing — same squash+flash hit-feel layers the Long Fall lands on,
	# so "hit the ground" is consistent wherever it happens.
	var t := create_tween()
	t.tween_method(_set_squash, Vector2(1.35, 0.62), Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	create_tween().tween_method(_set_flash, 0.7, 0.0, 0.20)

# ── Khagan Dismount Beat (wave-10 boss, phase 1→2) ────────────────────────────
# Presentation-only accompaniment to enemy_factory.advance_khagan_phase(); no
# stat, grid, or skill logic lives here — that function still does all of that
# itself, unchanged, and only calls into this for the visuals. Sequence:
# anticipation squash → flash rises → `on_swap` fires at the flash peak (this
# is where advance_khagan_phase actually calls rebuild_sprite(), so the
# same-frame texture change happens while the unit is whited out instead of
# visibly popping) → shockwave ring + dust burst spawn → flash/squash settle.
# Reuses the existing _set_squash/_set_flash tween-target layers (same ones
# play_long_fall's landing squash and every hit-flash already drive) rather
# than adding new per-frame state.
const KHAGAN_DISMOUNT_ANTICIPATION_TIME := 0.14   # squash-in telegraphing the transform
const KHAGAN_DISMOUNT_FLASH_RISE := 0.07          # flash ramp to peak (obscures the swap)
const KHAGAN_DISMOUNT_FLASH_HOLD := 0.05          # peak hold — on_swap fires here
const KHAGAN_DISMOUNT_FLASH_FALL := 0.18          # flash/squash settle back to normal
const KHAGAN_DISMOUNT_RING_RADIUS := 130.0
const KHAGAN_DISMOUNT_RING_DURATION := 0.45
const KHAGAN_DISMOUNT_RING_COLOR := Color(0.8, 0.85, 0.9, 0.9)
const KHAGAN_DISMOUNT_DUST_AMOUNT := 22
const KHAGAN_DISMOUNT_DUST_DURATION := 0.55
const KHAGAN_DISMOUNT_DUST_COLOR := Color(0.62, 0.55, 0.42, 0.85)

func play_dismount_transform(on_swap: Callable) -> void:
	if _is_dying:
		on_swap.call()
		return
	var t := create_tween()
	t.tween_method(_set_squash, Vector2(1.12, 0.88), Vector2(0.9, 1.1), KHAGAN_DISMOUNT_ANTICIPATION_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_method(_set_flash, 0.0, 1.0, KHAGAN_DISMOUNT_FLASH_RISE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Flash rise (0.07s) + hold (0.05s) = 0.12s at/near full whiteout — the swap
	# happens inside that window, under the 0.15s "obscured" cap.
	t.tween_callback(on_swap)
	t.tween_interval(KHAGAN_DISMOUNT_FLASH_HOLD)
	t.tween_callback(_spawn_dismount_burst)
	t.tween_method(_set_flash, 1.0, 0.0, KHAGAN_DISMOUNT_FLASH_FALL) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_method(_set_squash, Vector2(0.9, 1.1), Vector2.ONE, KHAGAN_DISMOUNT_FLASH_FALL) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _spawn_dismount_burst() -> void:
	if not battle_manager or not battle_manager.skill_effect_container:
		return
	var fx := KhaganVFX.new()
	battle_manager.skill_effect_container.add_child(fx)
	fx.setup(global_position, KHAGAN_DISMOUNT_RING_RADIUS, KHAGAN_DISMOUNT_RING_COLOR,
		KHAGAN_DISMOUNT_RING_DURATION, KHAGAN_DISMOUNT_DUST_AMOUNT, KHAGAN_DISMOUNT_DUST_COLOR,
		KHAGAN_DISMOUNT_DUST_DURATION)

# ── Khagan Possession Arrival Flash (wave-10 boss, phase 2→3) ────────────────
# The target-hero half of KhaganPossessionVFX's arrival beat (scripts/combat/
# khagan_possession_vfx.gd) — a brief hostile-tint flash on the possessed
# hero's own sprite, separate from that world-space effect since it drives
# this unit's existing _flash/_hit_squash layers directly (the same ones item
# 1's dismount beat and ordinary hit-flashes already use). Deliberately its
# own function, not a reuse of play_dismount_transform, so the two beats can
# be tuned independently.
const KHAGAN_POSSESS_FLASH_DURATION := 0.10   # <= 0.12s obscured, per spec
func play_possession_arrival_flash() -> void:
	if _is_dying:
		return
	var t := create_tween()
	t.tween_method(_set_flash, 0.0, 1.0, KHAGAN_POSSESS_FLASH_DURATION * 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_flash, 1.0, 0.0, KHAGAN_POSSESS_FLASH_DURATION * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_method(_set_squash, Vector2(0.92, 1.1), Vector2.ONE, KHAGAN_POSSESS_FLASH_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Khagan Body Pulse (wave-10 boss, ambient idle treatment) ────────────────
# Khagan-only — gated by the caller (AutoBattleManager checks khagan_phase
# meta before calling any of these). Kept as a plain 0-1 Color throughout, no
# HDR overbright channel values (this project doesn't use HDR bloom/glow
# anywhere; _flash above uses a >1.0 channel deliberately for a hit-white
# blowout, which is a different, unrelated technique this does NOT reuse).
# Strength is capped low (KHAGAN_PULSE_MAX_STRENGTH) so it's always visually
# subordinate to a hit/dismount/possession flash riding on top of it.
const KHAGAN_PULSE_MAX_STRENGTH := 0.12

func start_khagan_body_pulse(period: float, color: Color = Color(0.72, 0.55, 0.22)) -> void:
	if _is_dying or has_meta("khagan_pulse_active"):
		return   # guard: never double-start a second competing loop
	set_meta("khagan_pulse_active", true)
	_khagan_pulse_color = color
	_run_khagan_pulse_tween(period)

# Called on Phase 2 escalation / Phase 3 shift — replaces the running loop
# with a new period/color instead of stacking a second one.
func retune_khagan_body_pulse(period: float, color: Color) -> void:
	if _is_dying or not has_meta("khagan_pulse_active"):
		return
	_khagan_pulse_color = color
	_run_khagan_pulse_tween(period)

func _run_khagan_pulse_tween(period: float) -> void:
	if _khagan_pulse_tween and _khagan_pulse_tween.is_valid():
		_khagan_pulse_tween.kill()
	# create_tween() on THIS node — Godot binds the tween's lifetime to this
	# node and kills it automatically if the node is freed, so a looping
	# tween here can never outlive the unit (death, queue_free, battle reset).
	_khagan_pulse_tween = create_tween()
	_khagan_pulse_tween.set_loops()
	_khagan_pulse_tween.tween_method(_set_khagan_pulse, 0.0, KHAGAN_PULSE_MAX_STRENGTH, period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_khagan_pulse_tween.tween_method(_set_khagan_pulse, KHAGAN_PULSE_MAX_STRENGTH, 0.0, period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func stop_khagan_body_pulse() -> void:
	if _khagan_pulse_tween and _khagan_pulse_tween.is_valid():
		_khagan_pulse_tween.kill()
	_khagan_pulse_tween = null
	_khagan_pulse_strength = 0.0
	remove_meta("khagan_pulse_active")

func _set_khagan_pulse(v: float) -> void: _khagan_pulse_strength = v

# Tween target setters (named so tween_method can't mis-parse an inline lambda).
# _apply_animation() runs every frame in _process, so these only write state.
func _set_toss(v: Vector2) -> void:        _toss_offset = v
func _set_updraft(v: Vector2) -> void:     _updraft_offset = v
func _set_shove(v: Vector2) -> void:       _shove_offset = v
func _set_portal_off(v: Vector2) -> void:  _portal_offset = v
func _set_portal_scl(v: Vector2) -> void:  _portal_scale = v
func _set_lunge(v: Vector2) -> void:       _lunge_offset = v
func _set_recoil(v: Vector2) -> void:      _recoil_offset = v
func _set_punch(v: Vector2) -> void:       _punch_scale = v
func _set_squash(v: Vector2) -> void:      _hit_squash = v
func _set_flash(v: float) -> void:         _flash = v
func _set_death_rot(v: float) -> void:     _death_rotation = v
func _set_death_alpha(v: float) -> void:   _death_alpha = v
# ── Composite all layers and apply to the sprite (or trigger _draw) ──────────
## Depth scale for the row this unit stands on — 1.0 at the front of the board,
## BoardPerspective.FAR_SCALE at the back. Multiplied into the sprite scale so a
## back-line unit reads as further away, and folded into z_index so a nearer unit
## always draws over a further one (the thing that sells a tilted board).
func _update_depth() -> void:
	var bg = battle_manager.battle_grid if battle_manager else null
	if not bg:
		return
	var row: int = grid_position.y
	_depth_scale = BoardPerspective.row_scale(float(row), bg.grid_height)
	_foot_anchor_y = BoardPerspective.foot_offset(
		row, bg.grid_height, float(bg.cell_size), cell_size)
	# Nearer rows on top. Health bars and status icons are children, so they
	# inherit this and never punch through a unit standing in front.
	z_index = 2 + row

func _update_shadow() -> void:
	if not _shadow:
		_shadow = Node2D.new()
		_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_shadow.z_index = -1
		_shadow.draw.connect(_draw_shadow)
		add_child(_shadow)
		move_child(_shadow, 0)
	_shadow.queue_redraw()

## An ellipse on the ground under the unit. This is the single cheapest thing
## that stops a character reading as pasted onto the board — without it a 3D
## model and a 2D sprite both float, and the eye has nothing tying them to a cell.
## Where this unit's feet meet the board, in its OWN space — the same line the
## contact shadow is drawn on.
##
## A unit's origin is NOT at its feet. Any effect that belongs on the ground
## beneath a unit (root cuffs, scorch marks, ground burns) has to anchor here or
## it floats up the body: June's root cuffs, drawn at the origin, rendered around
## the target's waist (measured on the board check, 2026-09-17).
func ground_offset() -> float:
	return _foot_anchor_y

func _draw_shadow() -> void:
	if _is_dying and _death_alpha < 0.05:
		return
	var w: float = 34.0 * cell_size * _depth_scale
	var h: float = w * 0.34
	# The SAME foot line the sprite is pinned to. Previously a flat 46px, which
	# sat ~9px above where the sprite's feet actually were — a contact shadow
	# that isn't at the contact point is the thing that makes a unit read as
	# hovering, so these two must be driven from one number.
	var y: float = _foot_anchor_y
	var a: float = 0.32 * _death_alpha
	# Two stacked ellipses: a soft wide one and a tighter core, which reads as a
	# contact shadow rather than a flat blob.
	_shadow.draw_set_transform(Vector2(0, y), 0.0, Vector2(1.0, h / w))
	if soft_contact_shadow and model3d:
		if _soft_shadow_texture == null:
			var gradient := Gradient.new()
			gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
			gradient.colors = PackedColorArray([Color(0, 0, 0, 1),
				Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.30), Color(0, 0, 0, 0)])
			_soft_shadow_texture = GradientTexture2D.new()
			_soft_shadow_texture.gradient = gradient
			_soft_shadow_texture.width = 64
			_soft_shadow_texture.height = 64
			_soft_shadow_texture.fill = GradientTexture2D.FILL_RADIAL
			_soft_shadow_texture.fill_from = Vector2(0.5, 0.5)
			_soft_shadow_texture.fill_to = Vector2(1.0, 0.5)
		_shadow.draw_texture_rect(_soft_shadow_texture,
			Rect2(Vector2(-w, -w), Vector2(w * 2, w * 2)), false, Color(1, 1, 1, a))
		# Graphics audit 2026-10-02: at board size the soft falloff alone barely
		# registered, worst on the dark Earth/Volcano boards, and units read as
		# floating. A tighter core at the feet (0.7w) brings the centre to ~0.5
		# opacity while the outer falloff stays soft.
		var core: float = w * 0.7
		_shadow.draw_texture_rect(_soft_shadow_texture,
			Rect2(Vector2(-core, -core), Vector2(core * 2, core * 2)), false, Color(1, 1, 1, a * 0.95))
	else:
		_shadow.draw_circle(Vector2.ZERO, w, Color(0, 0, 0, a * 0.45))
		_shadow.draw_circle(Vector2.ZERO, w * 0.62, Color(0, 0, 0, a))
	# Rift's locomotion is magical levitation. At native board scale the imported
	# leg and robe motion is largely hidden inside one silhouette, so a violet
	# pulse at the fixed ground plane makes the air gap and motion readable.
	if unit_class == UnitBase.UnitClass.RIFT and not _is_dying \
			and is_moving and move_target_pos != move_start_pos:
		var pulse: float = 0.5 + 0.5 * sin(_anim_time * 4.0 + _anim_phase)
		_shadow.draw_circle(Vector2.ZERO, w * (0.82 + pulse * 0.10),
				Color(0.42, 0.08, 0.95, (0.12 + pulse * 0.10) * _death_alpha))
		_shadow.draw_circle(Vector2.ZERO, w * (0.42 + pulse * 0.08),
				Color(0.78, 0.30, 1.0, (0.18 + pulse * 0.14) * _death_alpha))
	_shadow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Where a bottom-anchored sprite's CENTRE has to sit so its feet land on
## _foot_anchor_y at the current scale.
##
## The sprite is `centered`, so scaling it shrinks it about its middle and lifts
## the feet off the ground by half the size it lost — depth scaling on a far row
## and a hit-squash both did that. Placing the centre from the foot line instead
## of a fixed offset pins the feet through every scale the animation stack
## applies, which is what makes a squash read as compressing INTO the board
## rather than the character bouncing above it.
##
## Returns the untouched base offset for the LPC path (_sprite_half_h == 0),
## whose frames carry their own feet placement.
func _foot_pinned_offset(scl: Vector2) -> Vector2:
	if _sprite_half_h <= 0.0:
		return _sprite_base_offset
	return Vector2(_sprite_base_offset.x, _foot_anchor_y - _sprite_half_h * scl.y)


## Where the body is drawn relative to the unit's origin right now (lift +
## swoop/toss) -- for effects that ride the body, like Skyrender's wind.
func body_visual_offset() -> Vector2:
	return _toss_offset + _aloft_offset

func _apply_animation() -> void:
	var off: Vector2 = _bob_offset + _lunge_offset + _recoil_offset + _toss_offset + _updraft_offset + _shove_offset + _portal_offset + _aloft_offset
	# `shadow_follows_toss` (Skyrender's aerial snatch): the ground shadow tracks
	# the body across the board instead of staying on the home square -- on the
	# ground under it, so the swoop's hover height is taken back out.
	if _shadow and has_meta("shadow_follows_toss"):
		var hover: float = SNATCH_HOVER * clampf(_toss_offset.length() / SNATCH_HOVER, 0.0, 1.0)
		_shadow.position = _toss_offset + Vector2(0, hover)
	# The bar is a sibling of the sprite, parked on the unit ROOT, which the
	# battle manager owns for grid movement — it never moves during an attack
	# lunge/hurt recoil/death toss. Carry it along with the same offset the
	# sprite gets so it never separates from the unit mid-animation.
	if health_bar and is_instance_valid(health_bar):
		health_bar.position = _health_bar_base_pos + off
	# Per-animation size correction (see _anim_scale_mult) — keeps the character
	# the same apparent height whether he's idling, walking, or mid-attack.
	var anim_mult: float = 1.0
	if animated_sprite and _anim_scale_mult.has(animated_sprite.animation):
		anim_mult = _anim_scale_mult[animated_sprite.animation]
	var scl: Vector2 = _breathe_scale * _punch_scale * _hit_squash * Vector2(_updraft_spin_x, 1.0) * anim_mult * _depth_scale * _portal_scale
	# element_glow is a sibling of the sprite (added straight to the unit, not
	# inside it), so it never inherited any of the above offsets. Unnoticeable
	# for bob/lunge/recoil (a couple px), but the Long Fall's _toss_offset can
	# be 1400px — without this the glow stays pinned at the launch point as a
	# visible ghost for the entire "gone" window (caught 2026-08-04 rendering
	# the toss to a filmstrip; see BOSS_SPECTACLE_PLAN.md §2e).
	if element_glow:
		element_glow.position = off
	if animated_sprite:
		# _sprite_base_offset is zero for the LPC path (its frames are already
		# feet-centred) and set for generated video->sheet anims, which are
		# bottom-anchored on a fixed canvas exactly like _setup_plain_sprite.
		animated_sprite.position = _foot_pinned_offset(scl) + off
		animated_sprite.scale = _base_sprite_scale * scl
		animated_sprite.rotation = _death_rotation
		var m: Color = Color(1, 1, 1, 1).lerp(Color(2.2, 2.2, 2.2, 1), _flash)
		if _khagan_pulse_strength > 0.0:
			m = m.lerp(_khagan_pulse_color, _khagan_pulse_strength)
		m.a = _death_alpha
		animated_sprite.modulate = m
	elif plain_sprite:
		plain_sprite.position = _foot_pinned_offset(scl) + off
		plain_sprite.scale = _base_sprite_scale * scl
		plain_sprite.rotation = _death_rotation
		var m: Color = Color(1, 1, 1, 1).lerp(Color(2.2, 2.2, 2.2, 1), _flash)
		if _khagan_pulse_strength > 0.0:
			m = m.lerp(_khagan_pulse_color, _khagan_pulse_strength)
		m.a = _death_alpha
		plain_sprite.modulate = m
	else:
		queue_redraw()   # shape-drawn units read these layers in _draw()


func _create_glow_texture() -> Texture2D:
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var center = Vector2(32, 32)
	var radius = 28.0
	for y in range(64):
		for x in range(64):
			var dist = Vector2(x, y).distance_to(center)
			var alpha = pow(clamp(1.0 - dist / radius, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_anim_time += delta
	# Idle layer: a gentle vertical bob + breathing squash. Phase-shifted per unit
	# so a row of units doesn't pulse in unison (that reads as robotic).
	if not _is_dying:
		var t: float = _anim_time * 3.0 + _anim_phase
		if unit_class == UnitBase.UnitClass.RIFT and is_moving and move_target_pos != move_start_pos:
			# A constant gap plus a larger slow oscillation sells deliberate hovering.
			# Moving adds another lift so travel cannot read as a static sliding pawn.
			var travel_lift: float = 3.0 if is_moving and move_target_pos != move_start_pos else 0.0
			_bob_offset = Vector2(0.0, -8.0 - travel_lift + sin(t * 0.72) * 4.0)
			_breathe_scale = Vector2(1.0 + sin(t * 0.72) * 0.012,
					1.0 + sin(t * 0.72 + 1.0) * 0.018)
		elif unit_class == UnitBase.UnitClass.RIFT:
			_bob_offset = Vector2.ZERO
			_breathe_scale = Vector2(1.0, 1.0 + sin(t + 1.0) * 0.012)
		else:
			_bob_offset = Vector2(0.0, sin(t) * 2.0)
			_breathe_scale = Vector2(1.0, 1.0 + sin(t + 1.0) * 0.015)
	if _updraft_spin_active:
		var el: float = _anim_time - _updraft_spin_t0
		if el >= _updraft_spin_dur or _updraft_spin_dur <= 0.0:
			_updraft_spin_active = false
			_updraft_spin_x = 1.0
		else:
			var ang: float = (el / _updraft_spin_dur) * _updraft_spin_turns * TAU
			_updraft_spin_x = cos(ang)
	_update_depth()
	_apply_animation()
	_update_animation()
	_update_shadow()
	_update_status_icons()
	_update_skill_icon(delta)
	_update_bar_placement(delta)
	if health_bar and not is_player_unit:
		var cd_max := float(skill_cooldown_max) if skill_name != "" else 0.0
		health_bar.update_mp(maxf(cd_max - maxf(skill_cd_time, 0.0), 0.0), cd_max)
	if health_bar and ultimate_charge_max > 0 and ultimate_charge != _last_ult_charge_drawn:
		_last_ult_charge_drawn = ultimate_charge
		health_bar.update_ult(ultimate_charge, ultimate_charge_max)


## Flips the health bar to the free side when its default side is blocked.
##
## Default sides are BOTTOM for heroes and TOP for enemies, which keeps each
## team's bars on the outside of the board — right up until two units stand in
## adjacent rows, when the lower one's TOP bar lands squarely on the upper
## one's sprite (2026-09-17 user report). If the default side's neighbouring
## cells are occupied and the opposite side's are all free, the bar moves
## there; otherwise it stays on the default side, so nothing changes on an open
## board.
func _update_bar_placement(delta: float) -> void:
	if not (health_bar and is_instance_valid(health_bar)):
		return
	_bar_flip_timer -= delta
	if _bar_flip_timer > 0.0:
		return
	_bar_flip_timer = BAR_FLIP_INTERVAL
	var bg = battle_manager.battle_grid if battle_manager else null
	if not bg:
		return
	var want: int = HealthBar.BarPlacement.BOTTOM if is_player_unit else HealthBar.BarPlacement.TOP
	var default_dir: int = 1 if want == HealthBar.BarPlacement.BOTTOM else -1
	if _bar_row_blocked(bg, default_dir) and not _bar_row_blocked(bg, -default_dir):
		want = HealthBar.BarPlacement.TOP if want == HealthBar.BarPlacement.BOTTOM else HealthBar.BarPlacement.BOTTOM
	if want == health_bar.placement:
		_bar_flip_pending = -1
		return
	# Require the same answer twice running before committing to the move.
	if _bar_flip_pending != want:
		_bar_flip_pending = want
		return
	_bar_flip_pending = -1
	if health_bar.set_placement(want):
		_health_bar_base_pos = health_bar.position

## True if any cell in the row immediately above (dir = -1) or below (dir = +1)
## this unit's footprint holds another live unit. Off-board rows count as free:
## a bar hanging past the edge of the board overlaps nothing.
func _bar_row_blocked(bg, dir: int) -> bool:
	var row: int = grid_position.y + (cell_size if dir > 0 else -1)
	for dx in range(cell_size):
		var cell := Vector2i(grid_position.x + dx, row)
		if not bg.is_valid_position(cell):
			continue
		var other = bg.get_unit_at(cell)
		if other and is_instance_valid(other) and other != self:
			return true
	return false

# Shows/hides every status badge from its matching UnitBase timer, and feeds
# each badge's drain ring (remaining / longest seen since it was applied).
# 2026-09-26 status layer: every status now has a badge, not just stun.
func _update_status_icons() -> void:
	var dot_key := "burn"
	if burn_flavor == "disease" or burn_flavor == "venom":
		dot_key = burn_flavor
	var weak_key := "weaken"
	if weaken_flavor == "corrosion": weak_key = "corroded"
	elif weaken_flavor == "dread": weak_key = "dread"   # Khagan's Dread Gaze
	var timers := {
		"stun": stun_time,
		"burn": burn_time if dot_key == "burn" else 0.0,
		"disease": burn_time if dot_key == "disease" else 0.0,
		"venom": burn_time if dot_key == "venom" else 0.0,
		"bleed": bleed_time,
		"slow": slow_time if slow_pct > 0.0 else 0.0,
		"root": root_time,
		"taunt": taunt_time,
		"heal_cut": heal_cut_time,
		"weaken": weakened_time if weak_key == "weaken" else 0.0,
		"corroded": weakened_time if weak_key == "corroded" else 0.0,
		"dread": weakened_time if weak_key == "dread" else 0.0,
		"blind": blind_time,
	}
	for key in timers:
		var left: float = float(timers[key])
		if left > 0.0:
			var peak: float = maxf(float(_status_peaks.get(key, 0.0)), left)
			_status_peaks[key] = peak
			_set_status_icon_active(key, true)
			var badge: StatusBadge = _status_icons.get(key)
			if badge:
				badge.frac = left / peak
		else:
			_status_peaks.erase(key)
			_set_status_icon_active(key, false)
	_layout_status_icons()

# Lays the visible status icons out in a centred row BELOW the unit, in
# STATUS_ICON_ORDER. Two things this fixes (2026-08-02, user report):
#   • Icons used to sit above the head, where they landed directly on the enemy
#     health bar with the damage numbers rising through the same space — three
#     overlapping things in one strip, all illegible.
#   • Every icon was pinned to the same hardcoded point, so a second status
#     would have rendered exactly on top of the first.
# Below the sprite is otherwise-empty board space for enemies. Player units carry
# their bar down there instead (BarPlacement.BOTTOM), so the row clears the bar's
# full height rather than assuming a fixed offset.
func _layout_status_icons() -> void:
	var shown: Array = []
	for key in STATUS_ICON_ORDER:
		var icon: StatusBadge = _status_icons.get(key)
		if icon and icon.visible:
			shown.append(icon)
	if shown.is_empty():
		return
	var y: float = shape_size * 0.72 + 16.0
	if health_bar and is_instance_valid(health_bar) \
			and health_bar.placement == HealthBar.BarPlacement.BOTTOM:
		y = health_bar.position.y + health_bar.total_height() + 16.0
	var start_x: float = -(float(shown.size()) - 1.0) * STATUS_ICON_SPACING * 0.5
	for i in range(shown.size()):
		shown[i].position = Vector2(start_x + float(i) * STATUS_ICON_SPACING, y)

func _set_status_icon_active(key: String, active: bool) -> void:
	if not active:
		if _status_icons.has(key):
			_status_icons[key].visible = false
		return

	var icon: StatusBadge = _status_icons.get(key)
	if not icon:
		icon = StatusBadge.new()
		add_child(icon)
		# A registered sheet (real art) replaces the drawn glyph; the ring stays.
		icon.setup(key, STATUS_BADGE_SIZE, STATUS_ICON_SHEETS.get(key, {}))
		_status_icons[key] = icon
		# Position is owned by _layout_status_icons(), not set here — a hardcoded
		# spot per icon is exactly what made them pile up on each other.
	icon.visible = true


# Creates the skill-cooldown badge on health_bar (so it inherits the bar's
# TOP/BOTTOM placement offset for free) if this unit's active skill has icon
# art registered in UnitDetailsController.SKILL_ICONS (keyed by skill_name —
# same field skill_cd_time governs, so it works identically for heroes and
# enemies alike; heroes are getting a full icon set soon, per user 2026-07-06).
# ── Role badge (2026-07-27) ───────────────────────────────────────────────────
# A small shape mirroring the skill icon, on the OPPOSITE end of the health bar.
# Enemies only: placement is the player's strongest lever (it swings win rate
# from 0% to ~85% — see the placement-sensitivity measurement) and the right
# formation depends on whether the wave's damage is melee or ranged, but a board
# of unfamiliar monster sprites gave no way to tell them apart. Heroes don't get
# one — the player picked those and already knows what they are.
#
# Shapes, not letters: readable at 14px, language-neutral, and no new art or
# font glyphs needed (Polygon2D is built in, so this adds no class_name and
# needs no Godot rescan).
#   melee   → red square      ranged → blue diamond      support → green cross
# Purely cosmetic — nothing here touches combat state.
const ROLE_BADGE_SIZE := 14.0
const ROLE_BADGE_MARGIN := 8.0
const ROLE_BADGE_COLORS := {
	"melee":   Color(0.86, 0.33, 0.28, 0.95),
	"ranged":  Color(0.36, 0.62, 0.88, 0.95),
	"support": Color(0.42, 0.78, 0.45, 0.95),
}

var _role_badge: Polygon2D = null

# Unit-space points for each role's glyph, sized to ROLE_BADGE_SIZE.
static func _role_badge_points(tag: String, s: float) -> PackedVector2Array:
	var h: float = s * 0.5
	match tag:
		"ranged":   # diamond
			return PackedVector2Array([Vector2(0, -h), Vector2(h, 0), Vector2(0, h), Vector2(-h, 0)])
		"support":  # cross / plus
			var t: float = s * 0.17
			return PackedVector2Array([
				Vector2(-t, -h), Vector2(t, -h), Vector2(t, -t), Vector2(h, -t),
				Vector2(h, t), Vector2(t, t), Vector2(t, h), Vector2(-t, h),
				Vector2(-t, t), Vector2(-h, t), Vector2(-h, -t), Vector2(-t, -t)])
		_:          # melee — square
			return PackedVector2Array([
				Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])

func _setup_role_badge() -> void:
	# Tag is stamped by WaveDirector.create_enemy_for_entry from the wave code.
	# Absent for heroes, summons and arena-spawned units — all correctly badgeless.
	if is_player_unit or not has_meta("role_tag"):
		return
	# Bosses are exempt: the Triarch and Khagan CHANGE combat role mid-fight
	# (melee → ranged → magic), and the tag is derived from the wave code once at
	# spawn, so a badge on them would go stale and lie. They're single, unique,
	# 2×2 silhouettes the player studies anyway — the badge exists to parse a
	# crowd of similar fodder, which is not a problem bosses have.
	if is_boss:
		return
	var tag: String = String(get_meta("role_tag"))
	if not ROLE_BADGE_COLORS.has(tag):
		return
	_role_badge = Polygon2D.new()
	_role_badge.polygon = _role_badge_points(tag, ROLE_BADGE_SIZE)
	_role_badge.color = ROLE_BADGE_COLORS[tag]
	_role_badge.z_index = 5
	var hp_h: float = health_bar.bar_height * HealthBar.HP_HEIGHT_SCALE
	_role_badge.position = Vector2(
		health_bar.bar_width / 2.0 + ROLE_BADGE_MARGIN + ROLE_BADGE_SIZE / 2.0,
		hp_h / 2.0)
	health_bar.add_child(_role_badge)

func _setup_skill_icon() -> void:
	var icon_path: String = UnitDetailsController.SKILL_ICONS.get(skill_name, "")
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		return
	_skill_icon = Sprite2D.new()
	_skill_icon.texture = load(icon_path)
	_skill_icon.z_index = 5
	var tex_size: Vector2 = _skill_icon.texture.get_size()
	_skill_icon.scale = Vector2(SKILL_ICON_DISPLAY_SIZE, SKILL_ICON_DISPLAY_SIZE) / tex_size
	var hp_h: float = health_bar.bar_height * HealthBar.HP_HEIGHT_SCALE
	_skill_icon.position = Vector2(
		-(health_bar.bar_width / 2.0 + SKILL_ICON_MARGIN + SKILL_ICON_DISPLAY_SIZE / 2.0),
		hp_h / 2.0)
	_skill_icon.modulate = SKILL_ICON_COOLDOWN_COLOR
	health_bar.add_child(_skill_icon)
	_skill_icon_prev_cd = skill_cd_time

# Lit when the skill is off cooldown and ready to fire, dark while on
# cooldown, and blinks for SKILL_ICON_BLINK_DURATION the instant AutoBattleManager
# resets skill_cd_time back to skill_cooldown_max (i.e. the moment it fires) —
# detected here by watching for cd jumping up from ~0, since nothing else
# refills it.
func _update_skill_icon(delta: float) -> void:
	if not _skill_icon:
		return
	if skill_cd_time > _skill_icon_prev_cd + 0.001 and _skill_icon_prev_cd <= 0.05:
		_skill_icon_blink_time = SKILL_ICON_BLINK_DURATION
	_skill_icon_prev_cd = skill_cd_time

	if _skill_icon_blink_time > 0.0:
		_skill_icon_blink_time -= delta
		var flash_on: bool = int(_skill_icon_blink_time * 12.0) % 2 == 0
		_skill_icon.modulate = SKILL_ICON_BLINK_COLOR if flash_on else SKILL_ICON_COOLDOWN_COLOR
	elif skill_cd_time <= 0.0:
		_skill_icon.modulate = SKILL_ICON_READY_COLOR
	else:
		_skill_icon.modulate = SKILL_ICON_COOLDOWN_COLOR

# Headhunter's ultimate: hold a mid-swing "attack" sheet frame (his aiming-down-
# the-sights pose) instead of playing it through, for as long as he's channeling
# Snipe. pause() is required — _update_animation()'s non-loop hold only skips
# re-triggering play(), it doesn't stop the sprite's own frame-advance clock.
# release_aim_pose() (a plain _play_oneshot("attack") replay) is what actually
# fires the shot's swing/recoil once the channel ends.
func play_aim_pose(frame_index: int) -> bool:
	if not animated_sprite:
		return false
	var frames = animated_sprite.sprite_frames
	if not (frames and frames.has_animation("attack")):
		return false
	animated_sprite.play("attack")
	var count: int = frames.get_frame_count("attack")
	animated_sprite.frame = clampi(frame_index, 0, maxi(count - 1, 0))
	animated_sprite.pause()
	return true

func release_aim_pose() -> void:
	_play_oneshot("attack")

# Plays a non-looping one-shot action sheet (attack/hurt/death) if this unit has
# it. Returns true if it played. _update_animation()'s non-loop guard holds the
# clip to its final frame, then resumes walk/idle (death stays pinned).
## Where a one-shot settles when it ends. NOT unconditionally "idle": a unit
## that is still mid-fight belongs back in its weapon-up pose. Resuming to idle
## even for the ONE frame before _update_model3d_animation() next runs is
## visible, because idle holsters the rifle — it flashed the stowed weapon
## across his shoulder between every shot and the next aim tick (user report
## 2026-09-09, "weird thing pops up over his shoulder for a split second").
func _resume_clip() -> String:
	if model3d and _is_engaged() and model3d.has_animation("aim"):
		if is_moving and move_target_pos != move_start_pos \
				and model3d.has_animation("walk_aim"):
			return "walk_aim"
		return "aim"
	return "idle"

func _play_oneshot(name: String) -> bool:
	if model3d:
		# "death" holds its final collapsed pose; everything else settles back
		# to whatever state the unit is actually in when the clip ends.
		return model3d.play_oneshot(name, "" if name == "death" else _resume_clip())
	if not animated_sprite:
		return false
	var frames = animated_sprite.sprite_frames
	if not (frames and frames.has_animation(name)):
		return false
	animated_sprite.play(name)
	animated_sprite.frame = 0   # force a restart even if this anim was mid-play
	return true

# How long the one-shot `name` runs, so die() can time its fade to the clip.
# Frame-count/fps on the 2D path, real seconds on the 3D one.
func _oneshot_duration(name: String) -> float:
	if model3d:
		return model3d.animation_length(name)
	if not animated_sprite:
		return 0.0
	var frames = animated_sprite.sprite_frames
	if not (frames and frames.has_animation(name)):
		return 0.0
	return float(frames.get_frame_count(name)) / maxf(1.0, frames.get_animation_speed(name))

## Duration of the visual action beat used by AutoBattleManager to keep a unit
## from starting another action before its current attack/cast has finished.
## Procedural and VFX-only skills still get a short readable beat when no clip
## exists for them.
func combat_action_duration(action_type: String) -> float:
	var clip := ""
	var fallback := 0.0
	match action_type:
		"attack":
			clip = "attack"
			fallback = 0.30  # VisualUnit.play_attack procedural lunge is 0.29s
		"skill":
			clip = "skill" if model3d and model3d.has_animation("skill") else "attack"
			fallback = 0.45
		"ultimate":
			clip = "ult"
			fallback = 0.70
	var duration := _oneshot_duration(clip) if clip != "" else 0.0
	return maxf(duration, fallback)

func _update_animation() -> void:
	# Opt-in escape hatch for scripts/tools/anim_preview.gd: that tool calls
	# animated_sprite.play() directly to show a specific animation on demand,
	# but this function runs every frame from _process() and would otherwise
	# immediately override it back to idle/walk based on real movement state
	# (which a preview dummy never has) — never set by real gameplay code.
	if has_meta("anim_preview_lock"):
		return

	if model3d:
		_update_model3d_animation()
		return

	if not animated_sprite:
		return
	var frames = animated_sprite.sprite_frames
	if not frames:
		return

	# A dying unit with a real death sheet stays on it (non-looping, ends
	# collapsed) — don't let the walk/idle picker below revive it after the
	# last frame. Units without a death sheet keep their old procedural death.
	if _is_dying and frames.has_animation("death"):
		return

	var curr = animated_sprite.animation

	if curr != "" and not frames.get_animation_loop(curr):
		if animated_sprite.frame < frames.get_frame_count(curr) - 1:
			return

	var dir_suffix = "south"
	if last_move_direction.length() > 0:
		if abs(last_move_direction.x) > abs(last_move_direction.y):
			dir_suffix = "east" if last_move_direction.x > 0 else "west"
		else:
			dir_suffix = "south" if last_move_direction.y > 0 else "north"

	if is_moving and move_target_pos != move_start_pos:
		var want = "walk_" + dir_suffix
		if not frames.has_animation(want):
			want = "walk_south"
		# Attack-only units have no walk sheet at all — hold the resting pose
		# rather than calling play() on a missing animation (which errors).
		if not frames.has_animation(want):
			want = "idle_south"
		if not frames.has_animation(want):
			return
		if want != curr:
			animated_sprite.play(want)
		return

	# Enemies prefer a back-view idle, players a front-view one — but most units
	# only have the front (idle_south), matching the front-facing static art, so
	# fall back to idle_south before dropping all the way to walk_south.
	var idle = "idle_south" if is_player_unit else "idle_north"
	if not frames.has_animation(idle):
		idle = "idle_south"
	if not frames.has_animation(idle):
		idle = "walk_south"
	if not frames.has_animation(idle):
		return
	if idle != curr:
		animated_sprite.play(idle)


# 3D equivalent of the walk/idle picker below. Much shorter, because a rigged
# model has no per-direction sheets to fall back through — the character TURNS
# instead, so direction is a yaw and not an animation name.
const SCUTTLE_ANIM_SPEED := 2.2   # walk-clip speed while scuttling down a charge lane
var _scuttle_speed_on := false

func _update_model3d_animation() -> void:
	if _is_dying:
		_aloft_offset = Vector2.ZERO
		return   # the death clip holds its final pose
	# Aloft (Skyrender's Cyclone Ascent): ease the body up off the board, and
	# down again on landing -- the lift holds through attacks too.
	var aloft: bool = bool(get_meta("skyrender_aloft", false)) and model3d.has_animation("fly")
	var lift_k: float = 1.0 - exp(-5.0 * get_process_delta_time())
	_aloft_offset.y = lerpf(_aloft_offset.y, -ALOFT_LIFT if aloft else 0.0, lift_k)
	if model3d.is_oneshot_playing():
		return   # attack/hurt still running — don't stomp it back to idle
	if aloft:
		model3d.play("fly")
		if is_moving and last_move_direction.length() > 0.0:
			model3d.face_direction(last_move_direction)
		else:
			model3d.set_facing_right(is_player_unit)
		return
	# Scuttle (Khagan's Sidestep Charge, 2026-10-03): the body is slid along
	# the lane while the grid says "not moving", so without this the legs froze
	# in idle. Plays the walk fast, still facing forward -- a crab strafes.
	if has_meta("scuttle"):
		model3d.play("walk")
		model3d.set_speed_scale(SCUTTLE_ANIM_SPEED)
		_scuttle_speed_on = true
		model3d.set_facing_right(is_player_unit)
		return
	if _scuttle_speed_on:
		model3d.set_speed_scale(1.0)
		_scuttle_speed_on = false
	var moving: bool = is_moving and move_target_pos != move_start_pos
	# Weapon-up states, for a character that has them. Mid-fight the rifle
	# stays on the target whether or not he happens to be walking — standing
	# aim when stopped, walking aim when closing (user call 2026-09-08). Both
	# face the TARGET rather than the direction of travel, because that is what
	# aiming means; `walk_aim`'s legs come from the walk cycle either way.
	# has_animation() keeps this a no-op for every other 3D hero.
	if _is_engaged() and model3d.has_animation("aim"):
		var clip: String = "aim"
		if moving and model3d.has_animation("walk_aim"):
			clip = "walk_aim"
		model3d.play(clip)
		model3d.face_direction(_engaged_dir)   # AFTER play(): per-clip yaw bias
		return
	if moving:
		model3d.play("walk")
		# `strafe_walk`: walks without turning to face the way it goes (crabs).
		if has_meta("strafe_walk"):
			model3d.set_facing_right(is_player_unit)
		elif last_move_direction.length() > 0.0:
			model3d.face_direction(last_move_direction)
		return
	model3d.play("idle")
	if unit_class == UnitBase.UnitClass.STITCH:
		_face_stitch_cast_3d()
	else:
		model3d.set_facing_right(is_player_unit)


func _draw():
	if animated_sprite or plain_sprite:
		return
	# Shape-drawn units read the same animation layers as the sprite path.
	var off: Vector2 = _bob_offset + _lunge_offset + _recoil_offset + _toss_offset + _updraft_offset + _shove_offset + _portal_offset + _aloft_offset
	var scl: Vector2 = _breathe_scale * _punch_scale * _hit_squash * Vector2(_updraft_spin_x, 1.0) * _portal_scale
	draw_set_transform(off, _death_rotation, scl)
	var color: Color = (fill_color if fill_color else get_element_color()).lerp(Color.WHITE, _flash)
	color.a = _death_alpha
	var outline = Color(1, 1, 1, _death_alpha)
	match unit_class:
		UnitBase.UnitClass.RANGER:     _draw_triangle(color, outline)
		UnitBase.UnitClass.MONK:       _draw_circle(color, outline)
		UnitBase.UnitClass.THIEF:      _draw_diamond(color, outline)
		UnitBase.UnitClass.BLACK_MAGE: _draw_polygon(5, color, outline)
		UnitBase.UnitClass.WHITE_MAGE: _draw_polygon(6, color, outline)
		UnitBase.UnitClass.RED_MAGE:      _draw_star(color, outline)
		UnitBase.UnitClass.BLOODHOUND:    _draw_triangle(color, outline)
		UnitBase.UnitClass.BOUNCER:       _draw_circle(color, outline)
		UnitBase.UnitClass.HEADHUNTER:    _draw_diamond(color, outline)
		UnitBase.UnitClass.SHAUNA:        _draw_triangle(color, outline)
		UnitBase.UnitClass.NEMI:          _draw_polygon(6, color, outline)
		UnitBase.UnitClass.SHEILDOR:      _draw_polygon(5, color, outline)
		UnitBase.UnitClass.LORDEE:        _draw_circle(color, outline)
		UnitBase.UnitClass.NECRO:         _draw_star(color, outline)
		UnitBase.UnitClass.ZOMBIE:        _draw_triangle(color, outline)
		UnitBase.UnitClass.BAT:           _draw_diamond(color, outline)
		# ── Roster expansion (shape-drawn until sprites are dropped in) ──
		UnitBase.UnitClass.DOC:           _draw_polygon(6, color, outline)
		UnitBase.UnitClass.RIOT:          _draw_square(color, outline)
		UnitBase.UnitClass.PASTOR:        _draw_polygon(5, color, outline)
		UnitBase.UnitClass.SABLE:         _draw_diamond(color, outline)
		UnitBase.UnitClass.RUSH:          _draw_triangle(color, outline)
		UnitBase.UnitClass.STITCH:        _draw_star(color, outline)
		UnitBase.UnitClass.COAL:          _draw_circle(color, outline)
		UnitBase.UnitClass.JUNE:          _draw_polygon(6, color, outline)
		UnitBase.UnitClass.CROSS:         _draw_square(color, outline)
		UnitBase.UnitClass.SEAR:         _draw_polygon(5, color, outline)
		UnitBase.UnitClass.EMBER:         _draw_diamond(color, outline)
		UnitBase.UnitClass.RIFT:          _draw_star(color, outline)
		UnitBase.UnitClass.ZOLT:          _draw_star(color, outline)
		UnitBase.UnitClass.LUMEN:         _draw_polygon(5, color, outline)
		UnitBase.UnitClass.STATIC:        _draw_star(color, outline)
		UnitBase.UnitClass.REED:          _draw_polygon(6, color, outline)
		UnitBase.UnitClass.VAIL:          _draw_polygon(6, color, outline)
		UnitBase.UnitClass.SPORE:         _draw_circle(color, outline)
		# ── Elites (enemy-only, placeholder shape until dedicated art lands) ──
		UnitBase.UnitClass.STAT_STEALER:  _draw_star(color, outline)
		_:                                _draw_square(color, outline)


func _draw_square(color: Color, outline: Color) -> void:
	var h = shape_size / 2
	var pts = PackedVector2Array([Vector2(-h,-h), Vector2(h,-h), Vector2(h,h), Vector2(-h,h)])
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_triangle(color: Color, outline: Color) -> void:
	var h = shape_size
	var hb = shape_size * 0.866
	var pts = PackedVector2Array([Vector2(0, -h*0.577), Vector2(hb, h*0.433), Vector2(-hb, h*0.433)])
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_circle(color: Color, outline: Color) -> void:
	var r = shape_size / 2
	draw_circle(Vector2.ZERO, r, color)
	draw_arc(Vector2.ZERO, r, 0, TAU, 32, outline, outline_width)

func _draw_diamond(color: Color, outline: Color) -> void:
	var h = shape_size / 2
	var pts = PackedVector2Array([Vector2(0,-h), Vector2(h,0), Vector2(0,h), Vector2(-h,0)])
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_polygon(sides: int, color: Color, outline: Color) -> void:
	var pts = PackedVector2Array()
	for i in sides:
		var a = -PI/2 + i * TAU / sides
		pts.append(Vector2(cos(a), sin(a)) * (shape_size / 2))
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)

func _draw_star(color: Color, outline: Color) -> void:
	var outer = shape_size / 2
	var inner = outer * 0.4
	var pts = PackedVector2Array()
	for i in 5:
		var ao = -PI/2 + i * TAU / 5
		pts.append(Vector2(cos(ao), sin(ao)) * outer)
		var ai = ao + TAU / 10
		pts.append(Vector2(cos(ai), sin(ai)) * inner)
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i+1) % pts.size()], outline, outline_width)


func update_visuals() -> void:
	fill_color = get_element_color()
	if element_glow:
		element_glow.modulate = fill_color
		element_glow.modulate.a = 0.4
		element_glow.scale = Vector2(1.5, 1.5)
	queue_redraw()

# Headhunter's Rapid Fire buff: pulses element_glow gold instead of spawning a
# separate particle effect, so "he's buffed" reads on the character himself.
# Generic enough to reuse for any future self-buff that wants the same look.
var _buff_glow_tween: Tween = null

func start_buff_glow(color: Color = Color(1.0, 0.84, 0.0)) -> void:
	if not element_glow:
		return
	if _buff_glow_tween and is_instance_valid(_buff_glow_tween):
		_buff_glow_tween.kill()
	element_glow.modulate = Color(color.r, color.g, color.b, 0.55)
	element_glow.scale = Vector2(1.7, 1.7)
	_buff_glow_tween = create_tween().set_loops()
	_buff_glow_tween.tween_property(element_glow, "modulate:a", 0.95, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_buff_glow_tween.parallel().tween_property(element_glow, "scale", Vector2(2.2, 2.2), 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_buff_glow_tween.tween_property(element_glow, "modulate:a", 0.55, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_buff_glow_tween.parallel().tween_property(element_glow, "scale", Vector2(1.7, 1.7), 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func stop_buff_glow() -> void:
	if _buff_glow_tween and is_instance_valid(_buff_glow_tween):
		_buff_glow_tween.kill()
		_buff_glow_tween = null
	update_visuals()

# Speeds up (or resets) the sprite-sheet playback rate — e.g. Shauna's
# Overdrive visibly quickening her attack/walk/idle animation to sell "she's
# hasted" the way most games do, on top of the actual attacks-per-second math
# (which is unaffected by this — purely cosmetic playback speed). No-op for
# units drawn procedurally (no animated_sprite).
func set_anim_speed_scale(mult: float) -> void:
	if animated_sprite:
		animated_sprite.speed_scale = mult
	if model3d:
		model3d.set_speed_scale(mult)

func change_element(new_element: Element) -> void:
	super.change_element(new_element)
	update_visuals()


# ── Drag & drop ────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not can_be_dragged:
		# A drag can be revoked WHILE it's in flight — can_be_dragged flips off
		# at battle start (main_game.enable_unit_dragging) and in die(). This
		# used to plain `return`, which meant the button-release that would have
		# placed-or-reverted the unit was never processed: the node just stayed
		# wherever the cursor left it, permanently off-grid and often entirely
		# off-screen, while the grid still thought it was on its old cell
		# (2026-07-24 user report). Always resolve an in-flight drag first.
		if is_dragging:
			_cancel_drag()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mouse_pos = get_global_mouse_position()
			if global_position.distance_to(mouse_pos) <= shape_size:
				mouse_down_position = mouse_pos
				drag_offset = global_position - mouse_pos
				original_position = position
				original_global_pos = global_position
		else:
			if is_dragging:
				is_dragging = false
				# Resolve the drop FIRST: _set_placement_zone_visible(false)
				# hides the sell zone, and the drop test reads its visibility —
				# hiding first would make every sell-drop silently miss.
				_try_place_at_mouse()
				_set_placement_zone_visible(false)
				get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if not is_dragging and mouse_down_position != Vector2.ZERO:
			if mouse_down_position.distance_to(get_global_mouse_position()) > drag_threshold:
				is_dragging = true
				_set_placement_zone_visible(true)
				get_viewport().set_input_as_handled()
		if is_dragging:
			global_position = get_global_mouse_position() + drag_offset
			get_viewport().set_input_as_handled()
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			mouse_down_position = Vector2.ZERO


# ── Drag-to-sell drop zone ────────────────────────────────────────────────────
# main_game owns the actual Control and the sell logic; it registers both here
# once at setup. Static because it's one shared drop target for every hero on
# the board — wiring a signal per unit would mean touching all six places that
# connect `died`, and every future spawn path would silently miss it.
static var sell_zone: Control = null
static var sell_handler: Callable = Callable()
# Same pattern for merging two copies of a hero: (dragged, target) -> void.
static var merge_handler: Callable = Callable()

static func _sell_zone_ready() -> bool:
	return sell_zone != null and is_instance_valid(sell_zone)

# True while the cursor is inside the drop zone. Hit-tested in the zone's OWN
# space: it lives under a CanvasLayer, so its Control coords and this Node2D's
# world coords are different spaces and comparing them directly would be wrong.
static func _mouse_over_sell_zone() -> bool:
	if not _sell_zone_ready() or not sell_zone.visible:
		return false
	return Rect2(Vector2.ZERO, sell_zone.size).has_point(sell_zone.get_local_mouse_position())

# Show the player placement zone while an allied hero is being dragged.
func _set_placement_zone_visible(v: bool) -> void:
	if not is_player_unit:
		return
	if battle_manager and battle_manager.background_layer:
		battle_manager.background_layer.set_player_zone_visible(v)
	# The sell target only exists while you're actually holding a hero.
	if _sell_zone_ready():
		sell_zone.visible = v and not is_summoned


# Abort an in-flight drag and put the node back where the GRID says it lives.
func _cancel_drag() -> void:
	is_dragging = false
	mouse_down_position = Vector2.ZERO
	_set_placement_zone_visible(false)
	_snap_to_grid_cell()

# Authoritative visual reset. battle_grid is the source of truth for where a
# unit actually IS, so revert paths re-derive the node's position from
# grid_position instead of trusting original_global_pos — a captured global
# that's silently wrong if the board was re-centred (window resize) or if a
# previous interrupted drag already left the node somewhere bogus.
func _snap_to_grid_cell() -> void:
	var bg = battle_manager.battle_grid if battle_manager else null
	if not bg:
		global_position = original_global_pos   # nothing better to go on
		return
	var w: Vector2 = bg.grid_to_world(grid_position)
	if cell_size > 1:
		# Multi-cell units are centred on their block — mirrors main_game._place_at
		# and AutoBattleManager._world_pos_for. N×N formula, same result at size 2.
		var off: float = bg.cell_size * (cell_size - 1) * 0.5
		w += Vector2(off, off)
	position = w

func _try_place_at_mouse() -> void:
	# Dropped on the sell zone → hand off to main_game and stop; it decides
	# whether the sale is legal (prep phase only, can't sell your last hero)
	# and snaps us back itself if it refuses.
	if is_player_unit and not is_summoned and _mouse_over_sell_zone() and sell_handler.is_valid():
		sell_handler.call(self)
		return
	if not battle_manager:
		_snap_to_grid_cell()
		return
	var bg = battle_manager.battle_grid
	if not bg:
		_snap_to_grid_cell()
		return
	var new_pos = bg.world_to_grid(get_global_mouse_position())
	if not _is_valid_placement(new_pos, bg):
		_snap_to_grid_cell()
		return
	# Dropped onto another copy of this same hero → merge (2026-09-28). main_game
	# owns the rules and snaps us back itself if it refuses.
	var occupant = bg.get_unit_at(new_pos)
	if is_player_unit and not is_summoned and occupant != null and occupant != self \
			and is_instance_valid(occupant) and occupant is UnitBase \
			and occupant.unit_class == unit_class and merge_handler.is_valid():
		merge_handler.call(self, occupant)
		return
	bg.purge_unit(self)
	if bg.place_unit(self, new_pos):
		grid_position = new_pos
		_snap_to_grid_cell()
	else:
		bg.place_unit(self, grid_position)
		_snap_to_grid_cell()


func _is_valid_placement(pos: Vector2i, bg) -> bool:
	if not bg.is_valid_position(pos):
		return false
	# Player zone = bottom 4 rows; enemy zone = top 4 rows
	var gh: int = bg.grid_height if bg else 14
	return (pos.y >= gh - 4 and pos.y < gh) if is_player_unit else (pos.y >= 0 and pos.y < 4)


# ── Particle effects ──────────────────────────────────────────────────────────
# Each particle PNG is an 832×576 sprite sheet: 13 cols × 9 rows of 64×64 frames.
# We pick a random variant sheet from the pack, then step through its first row.
const _PART_FRAME_SIZE := 64
const _PART_HFRAMES   := 13   # 832 / 64
const _PART_VFRAMES   := 9    # 576 / 64

# Each "Part N" folder numbers its variant sheets differently (Part 1 → 03.png,
# Part 2 → 62.png, …), so we list the folder's real PNGs rather than guessing
# fixed frame numbers. Cached per pack so we only hit the disk once each.
static var _PACK_CACHE: Dictionary = {}

static func _pack_sheets(pack_name: String) -> Array:
	if _PACK_CACHE.has(pack_name):
		return _PACK_CACHE[pack_name]
	var dir := "res://assets/particle/%s" % pack_name
	var sheets: Array = []
	var da := DirAccess.open(dir)
	if da:
		for f in da.get_files():
			# In-editor the folder also holds .import sidecars — keep only real PNGs.
			if f.to_lower().ends_with(".png"):
				sheets.append("%s/%s" % [dir, f])
	sheets.sort()
	_PACK_CACHE[pack_name] = sheets
	return sheets

func _spawn_particle(pack_name: String, duration: float, pos: Vector2) -> void:
	if pack_name.is_empty():
		return
	var png_files: Array = _pack_sheets(pack_name)
	if png_files.is_empty():
		return

	var tex: Texture2D = load(png_files[randi() % png_files.size()])
	if tex == null:
		return
	var fw := _PART_FRAME_SIZE
	var fh := _PART_FRAME_SIZE

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, fw, fh)
	sprite.centered = true
	sprite.global_position = pos
	sprite.scale = Vector2(2.0, 2.0)
	add_child(sprite)

	# Step through first row of frames over the effect duration, then fade out
	var frame_duration := duration / float(_PART_HFRAMES)
	var t := create_tween()
	for f in _PART_HFRAMES:
		var col := f
		t.tween_callback(func(): sprite.region_rect = Rect2(col * fw, 0, fw, fh))
		t.tween_interval(frame_duration)
	t.tween_method(func(v: float): sprite.modulate.a = v, 1.0, 0.0, 0.15)
	t.tween_callback(sprite.queue_free)
