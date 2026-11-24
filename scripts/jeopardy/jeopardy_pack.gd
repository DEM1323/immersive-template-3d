extends RefCounted
class_name JeopardyPack

## Loads and validates external JSON Jeopardy question packs from res://data/packs/.

const PACKS_DIR := "res://data/packs"
const BUILTIN_PACK_FILES := [
	"ephemeral_wonders.json",
	"atlas_of_ideas.json",
	"signals_and_circuits.json",
]

var id: String = ""
var title: String = ""
var subtitle: String = ""
var accent_color: Color = Color(0.36, 0.88, 0.90, 1.0)
var timer_seconds: float = 25.0
var categories: Array[Dictionary] = []
var final_jeopardy: Dictionary = {}
var source_path: String = ""


static func discover_pack_paths() -> Array[String]:
	var found: Array[String] = []
	var seen: Dictionary = {}

	# Include built-in packs first in deterministic order (safe on WebGL exports too)
	for filename in BUILTIN_PACK_FILES:
		var full_path := "%s/%s" % [PACKS_DIR, filename]
		if FileAccess.file_exists(full_path):
			found.append(full_path)
			seen[full_path] = true

	# Also discover any custom user-added JSON packs dropped into data/packs/
	var dir := DirAccess.open(PACKS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		var extras: Array[String] = []
		while entry != "":
			if not dir.current_is_dir() and entry.ends_with(".json"):
				var full_path := "%s/%s" % [PACKS_DIR, entry]
				if not seen.has(full_path):
					extras.append(full_path)
					seen[full_path] = true
			entry = dir.get_next()
		dir.list_dir_end()
		extras.sort()
		found.append_array(extras)

	return found


static func load_all_packs() -> Array[JeopardyPack]:
	var packs: Array[JeopardyPack] = []
	for path in discover_pack_paths():
		var pack := load_from_file(path)
		if pack != null:
			packs.append(pack)
	return packs


static func load_from_file(path: String) -> JeopardyPack:
	if not FileAccess.file_exists(path):
		push_error("JeopardyPack: file not found: %s" % path)
		return null
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("JeopardyPack: invalid JSON root in %s" % path)
		return null
	return from_dictionary(parsed as Dictionary, path)


static func from_dictionary(data: Dictionary, p_source_path: String = "") -> JeopardyPack:
	var errors := validate_dictionary(data)
	if not errors.is_empty():
		push_error("JeopardyPack validation failed (%s): %s" % [p_source_path, "; ".join(errors)])
		return null

	var pack := JeopardyPack.new()
	pack.source_path = p_source_path
	pack.id = str(data.get("id", "custom"))
	pack.title = str(data.get("title", "Ephemeral Jeopardy"))
	pack.subtitle = str(data.get("subtitle", ""))
	pack.accent_color = Color.from_string(str(data.get("accent_color", "#5ce1e6")), Color(0.36, 0.88, 0.90))
	pack.timer_seconds = clampf(float(data.get("timer_seconds", 25.0)), 8.0, 90.0)

	pack.categories = []
	for cat_raw in data.get("categories", []):
		pack.categories.append(cat_raw as Dictionary)
	pack.final_jeopardy = (data.get("final_jeopardy", {}) as Dictionary).duplicate(true)
	return pack


static func validate_dictionary(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if str(data.get("title", "")).strip_edges().is_empty():
		errors.append("Missing title")

	var cats_variant: Variant = data.get("categories", null)
	if not (cats_variant is Array):
		errors.append("Missing categories array")
		return errors

	var cats := cats_variant as Array
	if cats.size() < 3 or cats.size() > 6:
		errors.append("Expected 3..6 categories, got %d" % cats.size())

	for c_idx in range(cats.size()):
		if not (cats[c_idx] is Dictionary):
			errors.append("Category %d is not a dictionary" % c_idx)
			continue
		var cat := cats[c_idx] as Dictionary
		if str(cat.get("name", "")).strip_edges().is_empty():
			errors.append("Category %d missing name" % c_idx)
		var clues_variant: Variant = cat.get("clues", null)
		if not (clues_variant is Array) or (clues_variant as Array).is_empty():
			errors.append("Category %d missing clues" % c_idx)
			continue
		var clues := clues_variant as Array
		for r_idx in range(clues.size()):
			var clue_errs := _validate_clue(clues[r_idx], "cat[%d].clue[%d]" % [c_idx, r_idx], true)
			errors.append_array(clue_errs)

	var final_variant: Variant = data.get("final_jeopardy", null)
	if not (final_variant is Dictionary):
		errors.append("Missing final_jeopardy object")
	else:
		var final_errs := _validate_clue(final_variant, "final_jeopardy", false)
		errors.append_array(final_errs)

	return errors


static func _validate_clue(raw: Variant, label: String, require_value: bool) -> Array[String]:
	var errors: Array[String] = []
	if not (raw is Dictionary):
		errors.append("%s is not a dictionary" % label)
		return errors
	var d := raw as Dictionary
	if require_value and int(d.get("value", 0)) <= 0:
		errors.append("%s must have positive integer value" % label)
	if str(d.get("clue", "")).strip_edges().is_empty():
		errors.append("%s missing clue text" % label)
	if str(d.get("answer", "")).strip_edges().is_empty():
		errors.append("%s missing answer text" % label)
	var choices_var: Variant = d.get("choices", null)
	if not (choices_var is Array) or (choices_var as Array).size() != 4:
		errors.append("%s must have exactly 4 choices" % label)
	else:
		var correct_idx := int(d.get("correct_index", -1))
		if correct_idx < 0 or correct_idx >= 4:
			errors.append("%s correct_index out of range: %d" % [label, correct_idx])
	return errors


func get_category_count() -> int:
	return categories.size()


func get_row_count() -> int:
	if categories.is_empty():
		return 0
	return (categories[0].get("clues", []) as Array).size()


func get_clue(cat_idx: int, row_idx: int) -> Dictionary:
	if cat_idx < 0 or cat_idx >= categories.size():
		return {}
	var clues: Array = categories[cat_idx].get("clues", [])
	if row_idx < 0 or row_idx >= clues.size():
		return {}
	return clues[row_idx] as Dictionary


func get_max_clue_value() -> int:
	var best := 1000
	for cat in categories:
		for clue in cat.get("clues", []):
			best = max(best, int((clue as Dictionary).get("value", 0)))
	return best
