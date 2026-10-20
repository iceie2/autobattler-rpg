# Arcfang — The Storm That Hunts (wave 60)

Implemented 2026-10-08. Preserves the existing storm-wolf model and base stats.
Backups of changed production scripts are in `../backups/arcfang-hunt-20261008`
relative to the Godot project. No external AI service or generated asset used.

## Fight

- Opening mark at 10 combat seconds. Select the living, targetable opposing
  hero with the most recorded damage since the previous mark. Before any
  damage, higher ATK breaks ties; otherwise roster order breaks ties.
- Eye of the Storm holds Arcfang for 1.5 seconds with a fang emblem above
  the prey, charging ring, channel bar, crouch, and brightened body.
- Thunder Run flashes to the nearest legal 2x2 footprint beside the prey,
  clears stale paths and commits to pursuing that prey for 4 seconds.
  Taunt takes priority. The lightning streak shows origin and destination;
  a locally synthesized thunderclap plays on arrival.
- Thunderjaw replaces Sunder Bite: 95% live ATK physical damage immediately,
  then 50% live ATK magic damage after 0.6 seconds if the same target remains
  alive, targetable and within melee reach. Both hits use Lightning affinity,
  outgoing modifiers, ordinary armor/magic resist and shields. Arcfang holds
  still between contacts. Stun cancels the pending snap. Three-second CD.
- Spent Storm follows each pursuit: no attacks, skills or movement for 2s;
  both defenses are reduced by 40%, rounded through the shared effective
  defense accessor. Body dims and a labeled broken ring marks the opening.
  This stacks multiplicatively with other defense reductions without changing
  base stats. Unit Details and its tooltips display the live defense values.
- Last Howl activates once at/below 40% HP. The current or next primary hunt
  adds a second fully warned pursuit of a DIFFERENT living hero. If no other
  prey exists, recover immediately. Recovery after this sequence lasts 3s.
  Afterward, wait 10s before starting the next ordinary hunt.
- The ordinary cycle is 1.5s warning + 4s pursuit + 2s recovery + 2.5s wait.
  Lost prey restarts a full warning, so replacements cannot be ambushed.
  Stun pauses warning/pursuit; the existing boss stun-immunity setting remains.
  Occupied destinations restore the original footprint on placement failure.

All gameplay and VFX clocks use the manager's combat delta. Pause freezes
them; combat speed scales them. Death and battle end/start clear prey marks,
pending contacts, sound, temporary stats and Last Howl state. The Architect
keeps its original simple blink reprise, with none of the new wolf mechanics.

## Verification

Run `res://scenes/tools/arcfang_hunt_probe.tscn` headless with fixed FPS 30.
The probe verifies 97 checks including the real Unit Details defense cells,
physical/magic shield contacts, recent-damage targeting, warning replacement,
taunt, full footprint placement, expiry/reset, Last Howl, crowded board,
pause/speed and three complete seven-hero wave-60 fights.

Isolated simulation cap is explicitly set and actual hero levels are asserted.
Without equipment or crystal bonuses, the fixed roster won at levels 36, 40,
and 44 against level-47 Arcfang in 25.9s, 22.8s, and 19.1s; survivors were
6, 6, and 7. This exercises the behavior, not final difficulty tuning. Veteran
and Brutal retain their existing escorts and budget logic.

Godot import, main-game boot, boss signature, UI smoke, phantom-cell and Doc
revival checks pass without script errors. General arena ability probe still
reports the existing two silent results: Drowned Maw's on-being-hit reaction
and Magma Heart's passive. Arcfang's skill passes; its opening passive exceeds
the generic 3-second window and is covered by the targeted probe.

Windowed `res://scenes/tools/arcfang_hunt_capture.tscn` renders warning, pounce,
Thunderjaw, recovery and Last Howl on the actual lightning board, writing to
`../captures/renders/lightning/arcfang_*.png`. Warning and recovery captures
were visually inspected. Existing certificate-store and retained-resource
shutdown diagnostics also appear in the isolated test environment.

## Move effects and timer bars (2026-10-08 follow-up)

Each of the five moves has its own color-coded strip on the real
HealthBar. Eye of the Storm counts to the next mark; Thunder Run shows the
pounce charge and pursuit duration; Thunderjaw follows the real skill cooldown
and announces its delayed snap; Spent Storm shows time until recovery and its
remaining active duration. Last Howl displays progress toward the 40% HP gate,
then ARMED / SECOND HUNT / RECOVERING / USED. It has no timed cooldown.
Normal waiting time, extended double-hunt recovery, pause, and combat speed
come from actual controller state. The bars use the exact same width, height,
spacing, opacity and ready brightening as other elite/boss timer strips;
only their colors differ. The wide labeled rows have been removed. Controller
status strings remain available for inspection, but are not drawn on the bars.

Move effects now include gathering sparks and a prey ground rune, departure
and landing shock rings, serrated jaws clamping on physical contact, branching
lightning with an impact ring on the delayed snap, electricity draining into
extinguished sparks during recovery, and violet howl shockwaves on the HP
trigger. Effects retain snapshot hit positions after targets die or references
are cleared. They all use the controller's combat clock and clear with it.

The additional probe checks cover all five rows, real cooldown fraction,
HP-gated one-use status, phase labels, paused rows, independent bite/snap
effects, all move-effect triggers, and cleanup. UI smoke, main-game boot,
import, and Tidecaller's shared-bar regression pass. General arena probe keeps
the same two pre-existing silent results. Updated warning and snap captures
were visually inspected; `arcfang_lightning_snap.png` is also captured now.
