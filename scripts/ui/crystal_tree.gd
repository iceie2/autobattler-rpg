extends RefCounted
class_name CrystalTree

# Data model for the crystal shop's upgrade tree (2026-07-31 extraction).
#
# The layout used to be a hand-authored const dict in crystal_shop.gd with
# literal angles — adding one node meant re-computing the arc spacing of its
# siblings by hand, which does not survive a 5-10x bigger tree. Layout now
# lives in data/crystal_tree.json as plain absolute canvas coordinates, which
# is exactly what a drag-to-place editor produces (see crystal_tree_editor.gd).
#
# This class ONLY owns layout/presentation (where a node sits, how big, which
# icon, who its parent is). The upgrade's actual content — name, desc, cost
# curve, max level, effect — still lives in Progression.UPGRADES, keyed by the
# same "key" string. A node whose key has no Progression entry is an orphan and
# is reported by validate().

const DATA_PATH := "res://data/crystal_tree.json"
const ICON_DIR := "res://assets/icons/crystalshop/"
const DEFAULT_ICON := "head_start.png"
const DEFAULT_SIZE := 96.0

# One placed node. Position is absolute in canvas space (same space as center).
class TreeNode extends RefCounted:
	var key: String = ""
	# Empty array = attaches to the Call to Arms hub. One or more entries =
	# keys of other nodes this one hangs off of (multi-parent support,
	# 2026-08-01). A node with several parents draws one connector line per
	# parent (see CrystalShop._build_tree/_refresh) — this is purely a visual
	# layout relationship, NOT a hard gameplay prerequisite gate (that's a
	# separate mechanism: Progression.UPGRADES[i].requires).
	var parents: Array[String] = []
	var pos: Vector2 = Vector2.ZERO
	var size: float = DEFAULT_SIZE
	var icon: String = DEFAULT_ICON   # filename inside ICON_DIR
	# 0 = inherit whatever Progression.UPGRADES says for this key. Any other
	# value overrides it, so node depth can be tuned in the editor without
	# editing the upgrade catalogue. See Progression.max_level().
	var max_level: int = 0
	# "" = inherit the catalogue's name/desc. Non-empty overrides it, so
	# content wording can be iterated from the F9 editor without a script
	# edit. See Progression.display_name()/display_desc().
	var name_override: String = ""
	var desc_override: String = ""

	func icon_path() -> String:
		return ICON_DIR + icon

	func to_dict() -> Dictionary:
		var d := {
			"key": key, "parents": parents.duplicate(),
			"x": snappedf(pos.x, 0.1), "y": snappedf(pos.y, 0.1),
			"size": size, "icon": icon,
		}
		# Each override omitted entirely when inheriting, so the file only
		# records values someone actually deviated from the catalogue.
		if max_level > 0:
			d["max_level"] = max_level
		if name_override != "":
			d["name"] = name_override
		if desc_override != "":
			d["desc"] = desc_override
		return d

var center: Vector2 = Vector2(750, 480)
var center_size: float = 140.0
var nodes: Array[TreeNode] = []

# ── Load / save ───────────────────────────────────────────────────────────────

static func load_from_disk(path: String = DATA_PATH) -> CrystalTree:
	var tree := CrystalTree.new()
	if not FileAccess.file_exists(path):
		push_error("CrystalTree: missing data file %s — shop will render empty." % path)
		return tree
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CrystalTree: %s is not valid JSON — shop will render empty." % path)
		return tree
	tree.apply_doc(parsed)
	return tree

# ── Whole-tree snapshots ──────────────────────────────────────────────────────
# The editor's undo/redo is snapshot-based rather than per-operation inverse
# ops: the whole tree is a few KB of plain data, and one code path that always
# restores exactly what was there beats a dozen hand-written undo handlers that
# each have to remember to restore re-parented children, icons, sizes, etc.

func to_doc() -> Dictionary:
	var doc := {
		"version": 1,
		"center": {"x": center.x, "y": center.y},
		"center_size": center_size,
		"nodes": [],
	}
	for n in nodes:
		doc["nodes"].append(n.to_dict())
	return doc

# Rebuilds this tree's contents in place, so every reference held by the shop
# and the editor stays valid across an undo.
func apply_doc(doc: Dictionary) -> void:
	var c: Dictionary = doc.get("center", {})
	center = Vector2(float(c.get("x", 750.0)), float(c.get("y", 480.0)))
	center_size = float(doc.get("center_size", 140.0))
	nodes.clear()
	for raw: Variant in doc.get("nodes", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = raw
		var n := TreeNode.new()
		n.key = String(d.get("key", ""))
		# New format: "parents" array. Old format (pre-2026-08-01): single
		# "parent" string, "" meaning the hub — migrated in place so old
		# save-adjacent files don't hard-crash (the primary data file is
		# already migrated to the array form).
		if d.has("parents"):
			n.parents = []
			for p: Variant in d.get("parents", []):
				n.parents.append(String(p))
		else:
			var legacy := String(d.get("parent", ""))
			n.parents = []
			if legacy != "":
				n.parents.append(legacy)
		n.pos = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		n.size = float(d.get("size", DEFAULT_SIZE))
		n.icon = String(d.get("icon", DEFAULT_ICON))
		n.max_level = int(d.get("max_level", 0))
		n.name_override = String(d.get("name", ""))
		n.desc_override = String(d.get("desc", ""))
		if n.key != "":
			nodes.append(n)

# Writes back to the source data file. Only meaningful when running from
# source (editor / `--path .` runs) — res:// is read-only in an exported
# build, so the editor mode that calls this is dev-only by design.
func save_to_disk(path: String = DATA_PATH) -> bool:
	var doc := to_doc()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("CrystalTree: cannot write %s (err %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	return true

# ── Queries ───────────────────────────────────────────────────────────────────

func find(key: String) -> TreeNode:
	for n in nodes:
		if n.key == key:
			return n
	return null

func has(key: String) -> bool:
	return find(key) != null

func position_of(key: String) -> Vector2:
	# "" resolves to the hub, so connector math needs no special case.
	if key == "":
		return center
	var n := find(key)
	return n.pos if n != null else center

# Canvas-space rect enclosing the hub and every node (including icon extents).
# Drives pan clamping and frame-all, so both scale with the tree instead of
# assuming it stays roughly hub-sized.
func bounds() -> Rect2:
	var r := Rect2(center - Vector2.ONE * center_size / 2.0, Vector2.ONE * center_size)
	for n in nodes:
		r = r.merge(Rect2(n.pos - Vector2.ONE * n.size / 2.0, Vector2.ONE * n.size))
	return r

func children_of(key: String) -> Array[TreeNode]:
	var out: Array[TreeNode] = []
	for n in nodes:
		if n.parents.has(key):
			out.append(n)
	return out

# ── Mutation (used by the editor) ─────────────────────────────────────────────

func add_node(key: String, pos: Vector2, parent: String = "") -> TreeNode:
	if has(key):
		return find(key)
	var n := TreeNode.new()
	n.key = key
	n.pos = pos
	n.parents = []
	if parent != "":
		n.parents.append(parent)
	nodes.append(n)
	return n

# Adds one more parent link to a node (a no-op if it's already there, or if
# it would create a cycle — callers should check can_parent() first for a
# friendlier message, this is the last-resort guard).
func add_parent(key: String, new_parent: String) -> bool:
	if new_parent == "" or not can_parent(key, new_parent):
		return false
	var n := find(key)
	if n == null:
		return false
	if not n.parents.has(new_parent):
		n.parents.append(new_parent)
	return true

# Removes one specific parent link, leaving any others intact. If this was
# the node's only parent, it falls back to the hub (empty parents array).
func remove_parent(key: String, parent_to_remove: String) -> bool:
	var n := find(key)
	if n == null:
		return false
	var idx := n.parents.find(parent_to_remove)
	if idx < 0:
		return false
	n.parents.remove_at(idx)
	return true

# "might" -> "might_2" -> "might_3"… for the editor's Duplicate button.
func unique_key(base: String) -> String:
	if not has(base):
		return base
	var i := 2
	while has("%s_%d" % [base, i]):
		i += 1
	return "%s_%d" % [base, i]

# Removing a node splices its children onto the removed node's OWN parent
# list (in place of the removed key) so the tree never fragments into
# unreachable islands. A child that already has one of those replacement
# parents (e.g. it and the removed node shared a grandparent) doesn't get a
# duplicate link.
func remove_node(key: String) -> void:
	var n := find(key)
	if n == null:
		return
	for child in children_of(key):
		var idx := child.parents.find(key)
		if idx < 0:
			continue
		child.parents.remove_at(idx)
		for p in n.parents:
			if not child.parents.has(p):
				child.parents.append(p)
	nodes.erase(n)

# Guards against a reparent that would make a node its own ancestor (which
# would loop _ancestors forever and orphan the subtree from the hub). Walks
# every ancestor chain reachable from new_parent (a node can now have several
# parents, so this is a multi-source BFS rather than a single walk).
func can_parent(key: String, new_parent: String) -> bool:
	if key == new_parent:
		return false
	var frontier: Array[String] = [new_parent]
	var seen := {}
	var guard := 0
	while not frontier.is_empty() and guard < 4096:
		var walker: String = frontier.pop_back()
		guard += 1
		if walker == "" or seen.has(walker):
			continue
		seen[walker] = true
		if walker == key:
			return false
		var pn := find(walker)
		if pn != null:
			for p in pn.parents:
				frontier.append(p)
	return true

# ── Validation ────────────────────────────────────────────────────────────────

# Returns human-readable problems: keys with no Progression entry, upgrades
# with no placed node, dangling parents, duplicates, missing icon files.
# The shop logs these on load; the editor shows them in its status line.
func validate(upgrade_keys: PackedStringArray) -> PackedStringArray:
	var problems := PackedStringArray()
	var seen := {}
	for n in nodes:
		if seen.has(n.key):
			problems.append("duplicate node '%s'" % n.key)
		seen[n.key] = true
		if not upgrade_keys.has(n.key):
			problems.append("node '%s' has no Progression.UPGRADES entry" % n.key)
		for p in n.parents:
			if p != "" and not has(p):
				problems.append("node '%s' has missing parent '%s'" % [n.key, p])
		if not ResourceLoader.exists(n.icon_path()):
			problems.append("node '%s' icon not found: %s" % [n.key, n.icon])
	for k in upgrade_keys:
		if not seen.has(k):
			problems.append("upgrade '%s' has no tree slot" % k)
	return problems

# { "max_level": {key: int}, "name": {key: String}, "desc": {key: String} } —
# only the keys that actually override something appear in each sub-dict.
# Handed to Progression.apply_tree_overrides() so the rest of the game (cost
# curve, MAXED state, buy gate, detail-bar text) honours the tree's edits
# without any of it having to know the tree/editor exist.
func overrides() -> Dictionary:
	var max_lv := {}
	var names := {}
	var descs := {}
	for n in nodes:
		if n.max_level > 0:
			max_lv[n.key] = n.max_level
		if n.name_override != "":
			names[n.key] = n.name_override
		if n.desc_override != "":
			descs[n.key] = n.desc_override
	return {"max_level": max_lv, "name": names, "desc": descs}

# Every icon file available to the editor's icon picker.
static func available_icons() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(ICON_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		# Godot's exported/imported filesystem serves .png.import alongside the
		# source; strip the suffix so both source and exported runs agree.
		if f.ends_with(".png.import"):
			f = f.trim_suffix(".import")
		elif not f.ends_with(".png"):
			continue
		if not out.has(f):
			out.append(f)
	out.sort()
	return out
