# Cloven Titan — wave 40

Implemented 2026-10-04: the fused stone guardians split on death into two distinct roles. Original Titan assets are preserved; script backups are in `backups/cloven-2026-10-04`.

- Cloven Fist: broad stone silhouette, melee damage at 105% of the parent's attack, retains Fault Line.
- Cloven Heart: narrower shell, exposed amber core, casting animation, weak ranged attack at 20% of the parent's attack. Moves away from nearby opponents while staying within six cells of its sibling.
- Both fragments retain 45% of the parent's maximum HP, grant no extra rewards, cannot split again, and have no passive HP regeneration.
- The Heart repairs only its own Fist, using 2.5% of the parent's maximum HP per cast and a four-second cooldown while available to act. Its total reserve is 20% of the parent's maximum HP. Actual healing consumes the reserve; overhealing does not. Once the Fist dies it can spend the remaining reserve on itself.
- Amber repair tether and a rubble burst make the split/repair visible.
- Intact Titan landed basic attacks and Fault Line each stack a flat five armor/MR loss on their victim for the remaining fight. Effective defenses have a zero floor. The fragments cannot add stacks; existing stacks still increase their damage. Permanent hero stats are preserved and battle start clears the loss.

Validation: import and boot complete without script errors; dedicated Cloven split test, phantom-cell test, and revive-roster test pass. Both fragment models were rendered on the earth board across idle/walk/attack/hurt/death states; corrected the exposed core's attachment and scale from those renders.

The general arena ability probe reports one silent reaction for Drowned Maw, outside this change. Cloven Titan's probe entries respond. Boot/revive checks report resource-in-use messages at shutdown. A single seven-hero wave-40 simulation reached its time limit; this is not a balance certification. Playtest kill priority and time-to-clear before tuning values.

Rebuild with Blender using `tools/model3d/build_cloven_fragments.py`, copy the exported Heart GLB to `tools/model3d/cloven-heart-stage/00_base.glb`, then run `tools/model3d/merge_cloven_heart.py` to restore its casting clip. Import in Godot afterward. No generation service is needed.
