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
var _entry_names_zh: Dictionary = {}     # id → Chinese display name from JSON
var _item_tags: Dictionary = {}          # id → primary ItemTags value
var _tags: Dictionary = {}               # id → fine-grained tag array
var _weapon_classes: Dictionary = {}     # id → CombatEngine/SkillData medium id
var _attack_types: Dictionary = {}       # id → melee/ranged/spell/shield
var _skill_schools: Dictionary = {}      # id → SkillData school key
var _combat_styles: Dictionary = {}      # id → compatible CombatEngine style keys
var _proficiency_keys: Dictionary = {}   # id → AttrPanel proficiency key
var _category_display: Dictionary = {}

# ── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	_category_display = {
		"weapons": "Weapons",
		"shields": "Shields",
		"armor_light": "Light Armor",
		"armor_heavy": "Heavy Armor",
		"accessories": "Accessories",
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
	var zh_name: String = entry.get("name_zh", "")
	var default_item_tag := "shield" if category == "shields" else ("weapon" if category == "weapons" else category)

	# Store metadata
	_glb_paths[id] = entry.get("glb_path", "")
	_icons[id] = entry.get("icon", "res://assets/textures/icons/icon-weapon.png")
	_entry_names[id] = base_name
	_entry_names_zh[id] = zh_name
	_item_tags[id] = entry.get("item_tag", default_item_tag)
	_tags[id] = entry.get("tags", [_item_tags[id]])
	_weapon_classes[id] = entry.get("weapon_class", "")
	_attack_types[id] = entry.get("attack_type", "")
	_skill_schools[id] = entry.get("skill_school", "")
	_combat_styles[id] = entry.get("combat_styles", [])
	_proficiency_keys[id] = entry.get("proficiency_key", _weapon_classes[id])

	if not _categories.has(category):
		_categories[category] = []
	_categories[category].append(id)
	_all_ids.append(id)
	_equipment_meta[id] = entry
	_tiers[id] = entry.get("tiers", [])

	# Create WeaponData Resource (backward compat with .tres system)
	var weapon_data := WEAPON_DATA_SCRIPT.new()
	var stats: Dictionary = entry.get("stats", {})
	var tiers: Array = entry.get("tiers", [])
	var tier: Dictionary = {}
	if not tiers.is_empty() and tiers[0] is Dictionary:
		tier = tiers[0]
	var dice: Dictionary = _parse_damage_dice(String(tier.get("damage_dice", "")))

	weapon_data.id = id
	weapon_data.name = base_name
	weapon_data.name_zh = zh_name
	weapon_data.equipment_category = category
	weapon_data.item_tag = _item_tags[id]
	weapon_data.tags = get_tags(id)
	weapon_data.weapon_class = _weapon_classes[id]
	weapon_data.attack_type = _attack_types[id]
	weapon_data.skill_school = _skill_schools[id]
	weapon_data.combat_styles = get_combat_styles(id)
	weapon_data.proficiency_key = _proficiency_keys[id]
	weapon_data.hands = entry.get("hands", "")
	weapon_data.tier_index = 0
	weapon_data.tier_name = tier.get("name", "")
	weapon_data.damage_dice_count = int(dice.get("count", 0))
	weapon_data.damage_dice_sides = int(dice.get("sides", 0))
	weapon_data.damage_flat = int(dice.get("flat", 0))
	weapon_data.condition = int(tier.get("condition", stats.get("condition", 20)))
	weapon_data.max_condition = int(tier.get("condition", stats.get("max_condition", weapon_data.condition)))
	weapon_data.damage_min = _compute_damage_min(weapon_data.damage_dice_count, weapon_data.damage_dice_sides, weapon_data.damage_flat, stats.get("damage_min", 1))
	weapon_data.damage_max = _compute_damage_max(weapon_data.damage_dice_count, weapon_data.damage_dice_sides, weapon_data.damage_flat, stats.get("damage_max", 3))
	weapon_data.reach = tier.get("reach", stats.get("reach", 3.0))
	weapon_data.hit_bonus_percent = _ratio_to_percent(float(tier.get("hit_bonus", 0.0)))
	weapon_data.crit_bonus_percent = _ratio_to_percent(float(tier.get("crit_bonus", 0.0)))
	weapon_data.crit_damage_bonus = float(tier.get("crit_dmg_bonus", 0.0))
	weapon_data.armor_pierce_percent = _ratio_to_percent(float(tier.get("armor_pierce", 0.0)))
	weapon_data.knockback_m = float(tier.get("knockback", 0.0)) * 1.5
	weapon_data.stun_sec = float(tier.get("stun", 0.0))
	weapon_data.shield_phys_def = int(tier.get("phys_def", 0))
	weapon_data.shield_block_value = int(tier.get("block_value", 0))
	weapon_data.shield_block_chance_percent = _ratio_to_percent(float(tier.get("block_rate", 0.0)))
	weapon_data.armor_slot = String(entry.get("armor_slot", "body" if category.begins_with("armor") else ""))
	weapon_data.armor_phys_def = int(tier.get("phys_def", 0)) if category.begins_with("armor") else 0
	var evade_value := float(tier.get("evade_bonus", tier.get("evade_penalty", 0.0)))
	weapon_data.armor_evade_percent = _ratio_to_percent(evade_value) if category.begins_with("armor") else 0.0
	weapon_data.armor_move_speed_mult = float(tier.get("move_speed_mult", 1.0)) if category.begins_with("armor") else 1.0
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


static func _parse_damage_dice(value: String) -> Dictionary:
	var text := value.strip_edges().to_lower()
	if text.is_empty() or text == "0":
		return {"count": 0, "sides": 0, "flat": 0}
	var regex := RegEx.new()
	regex.compile("^(\\d+)d(\\d+)([+-]\\d+)?$")
	var match := regex.search(text)
	if match == null:
		return {"count": 1, "sides": 1, "flat": 0}
	var flat_text := match.get_string(3)
	return {
		"count": int(match.get_string(1)),
		"sides": int(match.get_string(2)),
		"flat": int(flat_text) if not flat_text.is_empty() else 0,
	}


static func _compute_damage_min(count: int, sides: int, flat: int, fallback: int) -> int:
	if count <= 0 or sides <= 0:
		return max(flat, 0)
	return max(count + flat, 0)


static func _compute_damage_max(count: int, sides: int, flat: int, fallback: int) -> int:
	if count <= 0 or sides <= 0:
		return max(flat, fallback)
	return max(count * sides + flat, fallback)


static func _ratio_to_percent(value: float) -> float:
	if absf(value) <= 1.0:
		return value * 100.0
	return value


# ── Public API ───────────────────────────────────────────────────────────

## Get WeaponData Resource by ID.
func get_weapon_data(weapon_id: String) -> WeaponData:
	return _weapons.get(weapon_id, null)

## 构建一个独立的 WeaponData 副本，并应用指定阶位 (tier_index) 的属性。
## 这是装备生成的正确入口：每次调用返回独立实例，不会串改注册表共享数据。
## tier_index 越界时自动 clamp 到有效范围。
func build_weapon_data_with_tier(weapon_id: String, tier_index: int) -> WeaponData:
	var base: WeaponData = _weapons.get(weapon_id, null)
	if base == null:
		return null
	var data: WeaponData = base.duplicate()
	data.affixes = []
	data.damage_mult = 1.0
	data.carry_weight_mult = 1.0
	data.is_broken = false
	var tiers: Array = _tiers.get(weapon_id, [])
	if tiers.is_empty():
		data.tier_index = 0
		return data
	var idx: int = clampi(tier_index, 0, tiers.size() - 1)
	data.tier_index = idx
	var tier: Dictionary = tiers[idx] if tiers[idx] is Dictionary else {}
	# 应用阶位属性
	var dice: Dictionary = _parse_damage_dice(String(tier.get("damage_dice", "")))
	if not dice.is_empty():
		data.damage_dice_count = int(dice.get("count", data.damage_dice_count))
		data.damage_dice_sides = int(dice.get("sides", data.damage_dice_sides))
		data.damage_flat = int(dice.get("flat", data.damage_flat))
	data.tier_name = String(tier.get("name", base.tier_name))
	data.condition = int(tier.get("condition", base.condition))
	data.max_condition = int(tier.get("condition", base.max_condition))
	data.damage_min = _compute_damage_min(data.damage_dice_count, data.damage_dice_sides, data.damage_flat, data.damage_min)
	data.damage_max = _compute_damage_max(data.damage_dice_count, data.damage_dice_sides, data.damage_flat, data.damage_max)
	data.reach = float(tier.get("reach", base.reach))
	data.hit_bonus_percent = _ratio_to_percent(float(tier.get("hit_bonus", 0.0)))
	data.crit_bonus_percent = _ratio_to_percent(float(tier.get("crit_bonus", 0.0)))
	data.crit_damage_bonus = float(tier.get("crit_dmg_bonus", 0.0))
	data.armor_pierce_percent = _ratio_to_percent(float(tier.get("armor_pierce", 0.0)))
	data.knockback_m = float(tier.get("knockback", 0.0)) * 1.5
	data.stun_sec = float(tier.get("stun", 0.0))
	data.shield_phys_def = int(tier.get("phys_def", 0))
	data.shield_block_value = int(tier.get("block_value", 0))
	data.shield_block_chance_percent = _ratio_to_percent(float(tier.get("block_rate", 0.0)))
	var category: String = base.equipment_category
	if category.begins_with("armor"):
		data.armor_phys_def = int(tier.get("phys_def", 0))
		var evade_value := float(tier.get("evade_bonus", tier.get("evade_penalty", 0.0)))
		data.armor_evade_percent = _ratio_to_percent(evade_value)
		data.armor_move_speed_mult = float(tier.get("move_speed_mult", 1.0))
	# 饰品负重加成
	if category == "accessories":
		data.carry_weight_bonus = int(tier.get("carry_bonus", 0))
	return data

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
	if TranslationServer.get_locale().begins_with("zh"):
		var zh_name: String = _entry_names_zh.get(weapon_id, "")
		if not zh_name.is_empty():
			return zh_name
	return tr(name_str)

## Get all equipment IDs.
func get_all_ids() -> Array[String]:
	return _all_ids.duplicate()

## Get IDs grouped by category.
func get_by_category() -> Dictionary:
	return _categories.duplicate(true)

## Get category display name.
func get_category_name(category: String) -> String:
	var display_key: String = _category_display.get(category, category.capitalize())
	return tr(display_key)

## Get all categories.
func get_categories() -> Array[String]:
	return _categories.keys()

## Get the tiers for a weapon ID.
func get_tiers(weapon_id: String) -> Array:
	return _tiers.get(weapon_id, [])

## Get the full entry metadata.
func get_entry_meta(weapon_id: String) -> Dictionary:
	return _equipment_meta.get(weapon_id, {})

## Get the primary item tag used by placement/inventory systems.
func get_item_tag(weapon_id: String) -> String:
	return _item_tags.get(weapon_id, "")

## Get fine-grained tags for filtering weapons by style, range, or material role.
func get_tags(weapon_id: String) -> Array[String]:
	var result: Array[String] = []
	for tag in _tags.get(weapon_id, []):
		result.append(String(tag))
	return result

## Get the combat medium/class string used by CombatEngine and SkillData.
func get_weapon_class(weapon_id: String) -> String:
	return _weapon_classes.get(weapon_id, "")

## Get damage channel: melee, ranged, spell, or shield.
func get_attack_type(weapon_id: String) -> String:
	return _attack_types.get(weapon_id, "")

## Get the skill school key from docs/15-技能与领悟系统.md.
func get_skill_school(weapon_id: String) -> String:
	return _skill_schools.get(weapon_id, "")

## Get compatible combat style keys from docs/05-战斗系统.md.
func get_combat_styles(weapon_id: String) -> Array[String]:
	var result: Array[String] = []
	for style in _combat_styles.get(weapon_id, []):
		result.append(String(style))
	return result

## Get the proficiency key used by AttrPanel.
func get_proficiency_key(weapon_id: String) -> String:
	return _proficiency_keys.get(weapon_id, "")

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
			"item_tag": get_item_tag(wid),
			"tags": get_tags(wid),
			"weapon_class": get_weapon_class(wid),
			"attack_type": get_attack_type(wid),
			"skill_school": get_skill_school(wid),
			"combat_styles": get_combat_styles(wid),
			"proficiency_key": get_proficiency_key(wid),
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
