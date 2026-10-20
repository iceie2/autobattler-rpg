# Wave 85 — Mirrorplate Warden

First-cut kit tuning lives in `scripts/combat/mirror_warden_kit.gd`.
Existing Warden base stats and source model remain intact.

- Polished armor reflects 15% of hits, capped at 0.5% attacker max HP and nonlethal.
- Mirror Field first appears at 2s: two tiles every 7.5s, maximum three active.
  At half health: three every 4.5s, maximum five. Tiles last 9s.
- Standing on a tile creates one rooted, targetable copy of that hero near the
  Warden. It has 6% Warden max HP, zero defenses, no regeneration or rewards.
  Copies repeat only basic attack signals after 0.35s, at 30% of source outgoing
  physical ATK capped at 75% Warden ATK. Their live ATK uses the same calculation.
  These deliberately simplified echoes are physical attacks using the source
  element; they do not reproduce magic basics, skills, passives or equipment.
  Killing a copy silences that tile until it disappears; it cannot respawn there.
- Shatter first fires at 5s, then every 8s (5s after armor breaks). Its fixed
  1.1s warning covers mirror tiles and four cardinal shard lanes, three cells
  long. Hits each hero at most once for 110% Warden outgoing ATK. All current
  mirrors and copies dissolve after the cast.
- Half HP permanently breaks armor and disables reflection immediately.
  Rebound Charge warns a fixed route for 0.9s, hits its footprint corridor for
  120% outgoing ATK, travels to a legal full-footprint destination, then returns.
  It starts after 4s in the broken phase and repeats every 7s. Blocked destinations
  do not overwrite other units or leave phantom cells.
- Cyan glass panels show mirror ground; pulsing red panels warn damaging cells;
  expanding cracks show impacts. Copies are translucent cyan hero models.

Focused verification: `res://scenes/tools/mirror_warden_check.tscn`.
Pass `-- --capture` without headless mode to render the combined warning.
Backups of modified existing scripts: `backups/mirror-warden-20261009/`.
