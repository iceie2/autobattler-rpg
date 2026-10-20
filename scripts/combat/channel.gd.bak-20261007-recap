extends RefCounted
class_name Channel

# One channelled ability in progress (VD-15, owner decision 2026-09-26: channels
# are ONE shared system, not per-hero timers). Started with
# AutoBattleManager.start_channel(), ticked per unit by _tick_channel(), shown
# as a channel bar under the caster's HP bar. A unit holds at most one channel;
# starting another interrupts the first.
#
#   blocks_actions  true  = the caster can't move, attack, cast or retarget
#                           until it resolves (Headhunter's Snipe aim)
#                   false = the caster keeps fighting (Static's Grid)
#   on_stun         INTERRUPT = a stun breaks it, no payoff (Static's Grid)
#                   PAUSE     = the timer holds while stunned, then resumes
#                               (Headhunter's Snipe)
# Death always ends it without a payoff: a dead unit is never ticked again.

enum OnStun { INTERRUPT, PAUSE }

const BAR_COLOR := Color(0.95, 0.85, 0.45)   # element-neutral cast-bar gold

var caster: UnitBase
var id: String = ""
var duration: float = 1.0
var remaining: float = 1.0
var blocks_actions: bool = true
var on_stun: int = OnStun.INTERRUPT
var on_complete: Callable
var on_interrupt: Callable        # optional
var on_tick: Callable             # optional, called with (dt) every live frame

func progress() -> float:
	return clampf(1.0 - remaining / maxf(duration, 0.001), 0.0, 1.0)
