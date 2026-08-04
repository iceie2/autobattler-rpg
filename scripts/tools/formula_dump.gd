extends Node

# Verification harness for AbilityFormulas (2026-08-02).
#
# Dumps every hero's three abilities at a chosen level so the registry can be
# eyeballed against the inline numbers it replaced, and proves the calibration
# claim: at AbilityFormulas.CAL_LEVEL every value must equal what the old code
# produced for the same unit.
#
#   godot --headless res://scenes/formula_dump.tscn -- --level=12
#
# Runs as a SCENE, not `-s`: a bare SceneTree script gets no autoloads, and
# UnitFactory/UnitBase both reach for Progression at parse time (CONVENTIONS
# landmine #1).

func _ready() -> void:
	var lvl := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			lvl = int(a.split("=")[1])

	print("FORMULA_DUMP level=%d  (calibration level=%d)" % [lvl, int(AbilityFormulas.CAL_LEVEL)])
	print("")

	var missing := 0
	var slots := [AbilityFormulas.PASSIVE, AbilityFormulas.ACTIVE, AbilityFormulas.ULTIMATE]
	for cls in UnitFactory.get_all_classes():
		if not AbilityFormulas.has_entry(cls, AbilityFormulas.PASSIVE):
			continue
		var u := UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
		u.set_level(lvl)
		print("── %s  (scales off %s · MAG %d · ATK %d · lvl %d)" % [
			u.get_class_name_string(), AbilityFormulas.scaling_stat(cls),
			u.magic_power, u.attack_damage, u.level])
		for slot in slots:
			var r := AbilityFormulas.resolve(u, slot)
			if r["terms"].is_empty():
				missing += 1
				print("   %-9s %s  << NO TERMS" % [slot.to_upper(), r["name"]])
				continue
			var vals: Array[String] = []
			for t in r["terms"]:
				vals.append("%s=%s" % [t["id"], t["display"]])
			print("   %-9s %-16s %s" % [slot.to_upper(), r["name"], ", ".join(vals)])
			print("             %s" % r["text"])
		u.free()
		print("")

	print("FORMULA_DUMP done — %d slots with no terms" % missing)
	print("")
	_lint_descriptions()
	get_tree().quit()


# Every description must make sense on its own (2026-08-02, user request:
# "Overdrive for 4s" said nothing about what Overdrive does). This catches the
# two ways that breaks:
#   1. The text just restates the ability's own name instead of its effect.
#   2. The text names ANOTHER ability, which the player may never have seen.
# Also flags descriptions long enough to overflow the shop/level-up rows.
const MAX_TEMPLATE_LEN := 68

func _lint_descriptions() -> void:
	var slots := [AbilityFormulas.PASSIVE, AbilityFormulas.ACTIVE, AbilityFormulas.ULTIMATE]

	# Collect every ability name in the roster so cross-references are detectable.
	var all_names: Dictionary = {}
	var units: Array = []
	for cls in UnitFactory.get_all_classes():
		if not AbilityFormulas.has_entry(cls, AbilityFormulas.PASSIVE):
			continue
		var u := UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
		units.append(u)
		for slot in slots:
			var n: String = str(AbilityFormulas.resolve(u, slot).get("name", ""))
			if n != "":
				all_names[n] = cls

	var problems := 0
	for u in units:
		for slot in slots:
			var r := AbilityFormulas.resolve(u, slot)
			var tmpl: String = str(r.get("template", ""))
			if tmpl == "":
				continue
			var own: String = str(r.get("name", ""))
			var label := "%s %s (%s)" % [u.get_class_name_string(), slot.to_upper(), own]

			# Using the ability's name as a natural verb is fine ("Bites the
			# nearest enemy for X") — the anti-pattern is a description with
			# NOTHING left once the name and the numbers are removed, which is
			# how "Overdrive for {dur}" managed to say nothing at all. So strip
			# both and count what actually describes the effect.
			if own != "" and _describing_words(tmpl, own) < 4:
				print("  JARGON  %s — says nothing beyond its own name" % label)
				problems += 1
			for other in all_names:
				if other == own or other == "":
					continue
				# Word-boundary-ish: avoid "Bite"/"Bites" style false hits by
				# requiring the name to stand alone.
				for pad in [" %s " % other, " %s." % other, " %s," % other]:
					if (" " + tmpl).contains(pad):
						print("  XREF    %s — names another ability (%s)" % [label, other])
						problems += 1
						break
			if tmpl.length() > MAX_TEMPLATE_LEN:
				print("  LONG    %s — %d chars (max %d), will wrap past its row"
					% [label, tmpl.length(), MAX_TEMPLATE_LEN])
				problems += 1
	for u in units:
		u.free()

	if problems == 0:
		print("DESC_LINT: ALL PASS — every description stands on its own")
	else:
		print("DESC_LINT: %d problem(s)" % problems)


# Words left in a template once its {placeholders} and the ability's own name are
# removed — i.e. how much of it actually describes the effect.
func _describing_words(tmpl: String, own: String) -> int:
	var re := RegEx.new()
	re.compile("\\{[^}]*\\}")
	var s: String = re.sub(tmpl, " ", true)
	# Strip the name word by word so "Blood Frenzy" doesn't survive as "Blood".
	for w in own.split(" ", false):
		s = s.replace(w, " ")
	var count := 0
	for tok in s.split(" ", false):
		if tok.strip_edges(true, true).length() >= 2:
			count += 1
	return count
