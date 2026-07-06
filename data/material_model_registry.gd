class_name MaterialModelRegistry
extends RefCounted

const MANIFEST_PATH := "res://data/material_model_manifest.json"

static var _entries_by_id: Dictionary = {}
static var _loaded := false

static func get_entry(material_id: String) -> Dictionary:
	_ensure_loaded()
	return _entries_by_id.get(material_id, {})

static func get_model_path(material_id: String) -> String:
	return String(get_entry(material_id).get("glb_path", ""))

static func get_display_name(material_id: String) -> String:
	return String(get_entry(material_id).get("name_zh", material_id.capitalize().replace("_", " ")))

static func get_placement(material_id: String) -> Dictionary:
	return get_entry(material_id).get("placement", {})

static func get_visual_offset(material_id: String) -> Vector3:
	var placement := get_placement(material_id)
	return _array_to_vector3(placement.get("visual_offset", [0.0, 0.0, 0.0]))

static func get_visual_rotation_degrees(material_id: String) -> Vector3:
	var placement := get_placement(material_id)
	return _array_to_vector3(placement.get("visual_rotation_degrees", [0.0, 0.0, 0.0]))

static func get_spawn_offset(material_id: String) -> Vector3:
	var placement := get_placement(material_id)
	return _array_to_vector3(placement.get("spawn_offset", [0.0, 0.0, 0.0]))

static func get_location_preference(material_id: String) -> String:
	var placement := get_placement(material_id)
	return String(placement.get("location_preference", "scatter"))

static func get_surface(material_id: String) -> String:
	var placement := get_placement(material_id)
	return String(placement.get("surface", "floor"))

static func should_align_to_wall(material_id: String) -> bool:
	var placement := get_placement(material_id)
	return bool(placement.get("align_to_wall", false))

static func should_random_yaw(material_id: String) -> bool:
	var placement := get_placement(material_id)
	return bool(placement.get("random_yaw", true))

static func all_material_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for id in _entries_by_id.keys():
		ids.append(String(id))
	return ids

static func reload() -> void:
	_loaded = false
	_entries_by_id.clear()
	_ensure_loaded()

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_entries_by_id.clear()
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for entry in parsed.get("materials", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id := String(entry.get("id", ""))
		if id.is_empty():
			continue
		_entries_by_id[id] = entry

static func _array_to_vector3(value: Variant) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() < 3:
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
