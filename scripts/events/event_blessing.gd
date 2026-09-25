extends Resource
class_name EventBlessing

enum EventType { BLESSING, CURSE, NEUTRAL }

class EventChoice:
	var text: String
	var effects: Dictionary
	var description: String
	# ── Graded outcomes (2026-09-19, see event_grade.gd) ──────────────────────
	# A choice is either FIXED (effects filled in up front, band "none" — the
	# original shape, still used by flat trades) or GRADED (band + resolve),
	# where the effects aren't known until the grade is rolled at pick time.
	# Both shapes coexist on purpose: not every decision should be a reel.
	var band: String = "none"
	# Callable(ctx: Dictionary, grade: String) -> {"effects": Dictionary, "outcome": String}
	var resolve: Callable = Callable()
	# What the button shows BEFORE you pick: the exact outcome, as a min–max
	# range over the band (EventCatalog.preview_line), e.g. "+6–26g".
	var preview: String = ""
	# The catalog resolver kind ("gold", "damage", "combo"…). Carried purely so
	# the panel can colour the preview line by what the choice DOES before its
	# effects exist — the band is already spelled out in the preview text, so
	# colour stays on the gain/cost axis it has always meant.
	var kind: String = ""

	func _init(p_text: String, p_effects: Dictionary, p_desc: String = "") -> void:
		text = p_text
		effects = p_effects
		description = p_desc

	func is_graded() -> bool:
		return resolve.is_valid()

	# The line under the button: explicit preview if the author wrote one,
	# otherwise the fixed outcome description.
	func button_line() -> String:
		return preview if preview != "" else description

var id: String
var title: String
var description: String
var event_type: int
var choices: Array = []
# Catalog id (stable across a run, unlike `id` which carries a random suffix so
# two rolls of the same event are distinct objects). Used for the seen-set and
# for once-per-run uniqueness — see EventGenerator.
var def_id: String = ""
# Run context snapshot taken when this event was rolled, handed back to a
# choice's resolve() so payouts can scale off round/gold/team state.
var ctx: Dictionary = {}

func _init(p_title: String = "", p_desc: String = "", p_type: int = EventType.NEUTRAL) -> void:
	id = "%s_%d" % [p_title.to_lower(), randi()]
	title = p_title
	description = p_desc
	event_type = p_type

func add_choice(text: String, effects: Dictionary, desc: String = "") -> void:
	choices.append(EventChoice.new(text, effects, desc))

# Graded sibling of add_choice: no effects up front, a band and a resolver instead.
func add_graded_choice(text: String, band: String, resolve: Callable,
		preview: String = "", kind: String = "") -> void:
	var c := EventChoice.new(text, {}, "")
	c.band = band
	c.resolve = resolve
	c.preview = preview
	c.kind = kind
	choices.append(c)

func get_type_color() -> Color:
	match event_type:
		EventType.BLESSING: return Color(0.3, 1.0, 0.3)
		EventType.CURSE:    return Color(1.0, 0.3, 0.3)
		EventType.NEUTRAL:  return Color(1.0, 1.0, 0.5)
		_: return Color.WHITE
