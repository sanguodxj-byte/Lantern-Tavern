extends Node
# NOTE: No class_name — registered as autoload in project.godot

# ── Signals ──────────────────────────────────────────────────────────────
signal registry_ready()
signal weapon_added(weapon_id: String)

# ── Data ─────────────────────────────────────────────────────────────────
const EQUIPMENT_JSON_PATH := "res://data/weapons/weapons.json"
const WEAPON_DATA_SCRIPT := preload("res://data/weapon_data.gd")

# Internal storage
var _weapons: Dictionary = {}            # id → WeaponData Resource
var _glb_paths: Dictionary = {}          # id → glb path string
var _icons: Dictionary = {}              # id → icon path string
var _categories: Dictionary = {}         # category → [ids]
var _all_ids: Array[String] = []
var _tiers: Dictionary = {}              # id → array of tier dicts
var _equipment_meta: Dictionary = {}     # id → full entry from JSON
var _entry_names: Dictionary = {}        # id → display name (without tier suffix)
var _category_display: Dictionary = {}

# ── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	_category_display = {
		"weapons": tr("Weapons"),
		"shields": tr("Shields"),
		"armor_light": tr("Light Armor"),
		"armor_heavy": tr("Heavy Armor"),
		"accessories": tr("Accessories"),
	}
	_load_equipment_json()


func _load_equipment_json() -> void:
	if not ResourceLoader.exists(EQUIPMENT_JSON_PATH):
		push_error("WeaponRegistry: not found at ", EQUIPMENT_JSON_PATH)
		return

	var file := FileAccess.open(EQUIPMENT_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("WeaponRegistry: cannot open ", EQUIPMENT_JSON_PATH)
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("WeaponRegistry: JSON parse error: ", json.get_error_message())
		return

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("WeaponRegistry: JSON root is not a Dictionary")
		return

	for entry in data.get("weapons", []):
		_register_equipment(entry)
	for entry in data.get("armor", []):
		_register_equipment(entry)

	emit_signal("registry_ready")
	print("[WeaponRegistry] Loaded ", _weapons.size(), " equipment entries")


func _register_equipment(entry: Dictionary) -> void:
	var id: String = entry.get("id", "")
	if id.is_empty():
		return

	var category: String = entry.get("category", "weapons")
	var base_name: String = entry.get("name", id)

	# Store metadata
	_glb_paths[id] = entry.get("glb_path", "")
	_icons[id] = entry.get("icon", "res://assets/textures/icons/icon-weapon.png")
	_entry_names[id] = base_name

	if not _categories.has(category):
		_categories[category] = []
	_categories[category].append(id)
	_all_ids.append(id)
	_equipment_meta[id] = entry
	_tiers[id] = entry.get("tiers", [])

	# Create WeaponData Resource (backward compat with .tres system)
	var weapon_data := WEAPON_DATA_SCRIPT.new()
	var stats: Dictionary = entry.get("stats", {})

	weapon_data.name = base_name
	weapon_data.condition = stats.get("condition", 20)
	weapon_data.max_condition = stats.get("max_condition", 20)
	weapon_data.damage_min = stats.get("damage_min", 1)
	weapon_data.damage_max = stats.get("damage_max", 3)
	weapon_data.reach = stats.get("reach", 3.0)
	weapon_data.throw_rotation_speed = stats.get("throw_rotation_speed", 40.0)
	weapon_data.throw_movement_speed = stats.get("throw_movement_speed", 10.0)

	var impale_trans: Array = stats.get("impale_local_translation", [0, 0, 0.7])
	if typeof(impale_trans) == TYPE_ARRAY and impale_trans.size() >= 3:
		weapon_data.impale_local_translation = Vector3(impale_trans[0], impale_trans[1], impale_trans[2])

	weapon_data.impale_local_rotation = stats.get("impale_local_rotation", 0.0)

	var glb_path: String = _glb_paths[id]
	if not glb_path.is_empty() and ResourceLoader.exists(glb_path):
		weapon_data.glb_mesh = load(glb_path)

	_weapons[id] = weapon_data
	emit_signal("weapon_added", id)


# ── Public API ───────────────────────────────────────────────────────────

## Get WeaponData Resource by ID.
func get_weapon_data(weapon_id: String) -> WeaponData:
	return _weapons.get(weapon_id, null)

## Get the GLB scene path for a weapon ID.
func get_glb_path(weapon_id: String) -> String:
	return _glb_paths.get(weapon_id, "")

## Get the icon path for a weapon ID.
func get_icon_path(weapon_id: String) -> String:
	return _icons.get(weapon_id, "res://assets/textures/icons/icon-weapon.png")

## Get the icon Texture2D for a weapon ID.
func get_icon(weapon_id: String) -> Texture2D:
	var path := get_icon_path(weapon_id)
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Get the display name (localized) for a weapon ID.
func get_display_name(weapon_id: String) -> String:
	var name_str: String = _entry_names.get(weapon_id, weapon_id)
	return tr(name_str)

## Get all equipment IDs.
func get_all_ids() -> Array[String]:
	return _all_ids.duplicate()

## Get IDs grouped by category.
func get_by_category() -> Dictionary:
	return _categories.duplicate(true)

## Get category display name.
func get_category_name(category: String) -> String:
	return _category_display.get(category, category.capitalize())

## Get all categories.
func get_categories() -> Array[String]:
	return _categories.keys()

## Get the tiers for a weapon ID.
func get_tiers(weapon_id: String) -> Array:
	return _tiers.get(weapon_id, [])

## Get the full entry metadata.
func get_entry_meta(weapon_id: String) -> Dictionary:
	return _equipment_meta.get(weapon_id, {})

## Build model viewer entries: { "CategoryName": { "DisplayName": "glb_path" } }
func get_model_viewer_entries() -> Dictionary:
	var result: Dictionary = {}
	for category in _categories.keys():
		var group_name: String = get_category_name(category)
		var group: Dictionary = {}
		for wid in _categories[category]:
			var path: String = _glb_paths[wid]
			if not path.is_empty():
				group[get_display_name(wid)] = path
		result[group_name] = group
	return result

## Build gear list entries: [{ "id", "name", "icon", "tres_path" }]
func get_gear_list_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for wid in _all_ids:
		var path: String = _glb_paths[wid]
		if path.is_empty():
			continue  # only show items with 3D models
		result.append({
			"id": wid,
			"name": get_display_name(wid),
			"icon": get_icon(wid),
			"tres_path": "res://data/weapons/" + wid + ".tres",
		})
	return result

## Get gear list entries filtered by category.
func get_gear_list_entries_by_category(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in get_gear_list_entries():
		var entry_id: String = entry.get("id", "")
		var meta: Dictionary = _equipment_meta.get(entry_id, {})
		if meta.get("category", "") == category:
			result.append(entry)
	return result
