extends Resource
class_name EventBlessing

enum EventType { BLESSING, CURSE, NEUTRAL }

class EventChoice:
	var text: String
	var effects: Dictionary
	var description: String

	func _init(p_text: String, p_effects: Dictionary, p_desc: String = "") -> void:
		text = p_text
		effects = p_effects
		description = p_desc

var id: String
var title: String
var description: String
var event_type: int
var choices: Array = []

func _init(p_title: String = "", p_desc: String = "", p_type: int = EventType.NEUTRAL) -> void:
	id = "%s_%d" % [p_title.to_lower(), randi()]
	title = p_title
	description = p_desc
	event_type = p_type

func add_choice(text: String, effects: Dictionary, desc: String = "") -> void:
	choices.append(EventChoice.new(text, effects, desc))

func get_type_color() -> Color:
	match event_type:
		EventType.BLESSING: return Color(0.3, 1.0, 0.3)
		EventType.CURSE:    return Color(1.0, 0.3, 0.3)
		EventType.NEUTRAL:  return Color(1.0, 1.0, 0.5)
		_: return Color.WHITE
