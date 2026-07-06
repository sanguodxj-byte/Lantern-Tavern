class_name EquipmentDetailPopup
extends PanelContainer

const DEFAULT_WEAPON_ICON := "res://assets/textures/icons/icon-weapon.png"
const DEFAULT_SHIELD_ICON := "res://assets/textures/icons/icon-shield.png"
const RUNE_ICON_DIR := "res://assets/textures/icons/runes"
const RD := preload("res://globals/combat/rune_data.gd")
## 详情悬浮窗相对物体屏幕坐标的偏移：正 X = 物体右侧，负 Y = 垂直居中略偏上。
## 与交互提示 HINT_OFFSET 一致，使弹窗“取代”交互提示在物体右侧的位置。
const POPUP_OFFSET := Vector2(28, -22)

var _title_label: Label
var _category_label: Label
var _body_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if _title_label != null:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 200
	custom_minimum_size = Vector2(260, 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(236, 0)
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 4)
	root.add_child(text_box)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(_title_label)
	_category_label = Label.new()
	_category_label.add_theme_font_size_override("font_size", 15)
	_category_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.35))
	_category_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(_category_label)
	_body_label = Label.new()
	_body_label.custom_minimum_size = Vector2(236, 0)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(_body_label)

func show_detail(detail: Dictionary, screen_position: Vector2 = Vector2.ZERO) -> void:
	if detail.is_empty():
		hide_detail()
		return
	if _title_label == null:
		_build_ui()
	# 详情内容在构建期已本地化（tr），此处仅做显示，不再二次本地化
	_title_label.text = String(detail.get("title", _tr("Item")))
	_category_label.text = String(detail.get("category", ""))
	_body_label.text = _format_body(detail)
	visible = true
	reset_size()
	_position_near(screen_position)

func hide_detail() -> void:
	visible = false

func show_for_equipment_id(equipment_id: String, screen_position: Vector2 = Vector2.ZERO) -> void:
	show_detail(detail_for_equipment_id(equipment_id), screen_position)

func show_for_weapon_data(data, screen_position: Vector2 = Vector2.ZERO) -> void:
	show_detail(detail_for_weapon_data(data), screen_position)

func show_for_material_id(material_id: String, amount: int = 1, screen_position: Vector2 = Vector2.ZERO) -> void:
	show_detail(detail_for_material_id(material_id, amount), screen_position)

func show_for_rune_id(rune_id: String, amount: int = 1, screen_position: Vector2 = Vector2.ZERO) -> void:
	show_detail(detail_for_rune_id(rune_id, amount), screen_position)

static func detail_for_equipment_id(equipment_id: String) -> Dictionary:
	if equipment_id.is_empty() or WeaponRegistry == null:
		return {}
	var data = WeaponRegistry.get_weapon_data(equipment_id)
	if data == null:
		return {}
	var detail := detail_for_weapon_data(data)
	detail["icon_path"] = WeaponRegistry.get_icon_path(equipment_id)
	return detail

static func detail_for_weapon_data(data) -> Dictionary:
	if data == null:
		return {}
	var title := _read_string(data, "name_zh", "")
	if title.is_empty():
		title = _read_string(data, "name", "Equipment")
	var item_tag := _read_string(data, "item_tag", "")
	var category := _read_string(data, "equipment_category", "")
	if category.is_empty():
		category = item_tag
	var lines: Array[String] = []
	var damage_min := _read_int(data, "damage_min", 0)
	var damage_max := _read_int(data, "damage_max", 0)
	if damage_max > 0:
		lines.append(_tr("Damage %d-%d") % [damage_min, damage_max])
	var reach := _read_float(data, "reach", 0.0)
	if reach > 0.0:
		lines.append(_tr("Reach %.1fm") % reach)
	var armor_def := _read_int(data, "armor_phys_def", 0)
	if armor_def != 0:
		lines.append(_tr("Phys Def %+d") % armor_def)
	var armor_evade := _read_float(data, "armor_evade_percent", 0.0)
	if armor_evade != 0.0:
		lines.append(_tr("Evade %+0.1f%%") % armor_evade)
	var armor_move_speed := _read_float(data, "armor_move_speed_mult", 1.0)
	if armor_move_speed != 1.0:
		lines.append(_tr("Move Spd %+.0f%%") % ((armor_move_speed - 1.0) * 100.0))
	var shield_def := _read_int(data, "shield_phys_def", 0)
	var block_value := _read_int(data, "shield_block_value", 0)
	var block_chance := _read_float(data, "shield_block_chance_percent", 0.0)
	if shield_def != 0:
		lines.append(_tr("Shield Def %+d") % shield_def)
	if block_value != 0 or block_chance != 0.0:
		lines.append(_tr("Block %d / %.1f%%") % [block_value, block_chance])
	var condition := _read_int(data, "condition", 0)
	var max_condition := _read_int(data, "max_condition", 0)
	if max_condition > 0:
		lines.append(_tr("Durability %d/%d") % [condition, max_condition])
	return {
		"kind": "equipment",
		"title": _tr(title),
		"category": _tr(_display_category(category)),
		"lines": lines,
		"description": _equipment_description(data),
		"icon_path": _icon_for_data(data),
	}

static func detail_for_material_id(material_id: String, amount: int = 1) -> Dictionary:
	if material_id.is_empty():
		return {}
	var display_name := material_id.replace("_", " ").capitalize()
	var lines: Array[String] = [_tr("Qty x%d") % amount]
	var desc := _tr("Brewing material recovered from the dungeon.")
	var tm: Node = Service.tavern_manager()
	if tm != null and tm.materials_db.has(material_id):
		var meta: Dictionary = tm.materials_db[material_id]
		display_name = String(meta.get("name", display_name))
		var flavors: Dictionary = meta.get("flavors", {})
		if not flavors.is_empty():
			var flavor_parts: Array[String] = []
			for key in flavors.keys():
				flavor_parts.append("%s %s" % [String(key), str(flavors[key])])
			lines.append(_tr("Flavor: %s") % ", ".join(flavor_parts))
	return {
		"kind": "material",
		"title": _tr(display_name),
		"category": _tr("Material"),
		"lines": lines,
		"description": desc,
		"icon_path": DEFAULT_WEAPON_ICON,
	}

static func detail_for_rune_id(rune_id: String, amount: int = 1) -> Dictionary:
	var rune := RD.get_rune(rune_id)
	if rune.is_empty():
		return {}
	return {
		"kind": "rune",
		"title": _tr(RD.get_rune_name(rune_id)),
		"category": _tr("Rune"),
		"lines": [_tr("Qty x%d") % amount, _tr("Rarity %s") % String(rune.get("rarity", "common"))],
		"description": _tr(String(rune.get("desc", ""))),
		"icon_path": rune_icon_path(rune_id),
	}

static func detail_for_pickable_item(item: PickableItem) -> Dictionary:
	if item == null:
		return {}
	if item.weapon_data != null:
		return detail_for_weapon_data(item.weapon_data)
	if item.shield_data != null:
		return {
			"kind": "shield",
			"title": _tr(item.shield_data.name),
			"category": _tr("Shield"),
			"lines": [_tr("Durability %d/%d") % [item.shield_data.condition, item.shield_data.max_condition]],
			"description": _tr("Defensive gear equippable in the off-hand slot."),
			"icon_path": DEFAULT_SHIELD_ICON,
		}
	if item.material_id != "":
		return detail_for_material_id(item.material_id, 1)
	if item.rune_id != "":
		return detail_for_rune_id(item.rune_id, 1)
	if item.furniture_data != null:
		return {
			"kind": "furniture",
			"title": _tr(item.furniture_data.name),
			"category": _tr("Movable Object"),
			"lines": [],
			"description": _tr("A scene object you can lift, throw, or use in impromptu combat."),
			"icon_path": DEFAULT_WEAPON_ICON,
		}
	return {}

static func icon_for_equipment_id(equipment_id: String) -> Texture2D:
	var path := ""
	if not equipment_id.is_empty() and WeaponRegistry != null:
		path = WeaponRegistry.get_icon_path(equipment_id)
	return _load_icon_static(path, "")

static func icon_for_material(_material_id: String) -> Texture2D:
	return _load_icon_static(DEFAULT_WEAPON_ICON, "")

static func icon_for_rune(rune_id: String) -> Texture2D:
	return _load_icon_static(rune_icon_path(rune_id), "")

static func rune_icon_path(rune_id: String) -> String:
	if rune_id.is_empty():
		return ""
	return "%s/%s.png" % [RUNE_ICON_DIR, rune_id]

func _format_body(detail: Dictionary) -> String:
	var parts: Array[String] = []
	for raw_line in detail.get("lines", []):
		var line := String(raw_line)
		if not line.is_empty():
			parts.append(line)
	var desc := String(detail.get("description", ""))
	if not desc.is_empty():
		parts.append(desc)
	return "\n".join(parts)

func _position_near(screen_position: Vector2) -> void:
	var target := screen_position + POPUP_OFFSET
	if screen_position == Vector2.ZERO:
		target = get_viewport_rect().size * Vector2(0.5, 0.62)
	var viewport_size := get_viewport_rect().size
	var popup_size := size
	target.x = clampf(target.x, 12.0, maxf(12.0, viewport_size.x - popup_size.x - 12.0))
	target.y = clampf(target.y, 12.0, maxf(12.0, viewport_size.y - popup_size.y - 12.0))
	global_position = target

func _load_icon(path: String, category: String) -> Texture2D:
	return _load_icon_static(path, category)

static func _load_icon_static(path: String, category: String) -> Texture2D:
	var selected := path
	var tex := _load_png_texture_static(selected)
	if tex != null:
		return tex
	if selected.is_empty() or not ResourceLoader.exists(selected):
		selected = DEFAULT_SHIELD_ICON if category.to_lower().contains("盾") or category == "shields" else DEFAULT_WEAPON_ICON
		tex = _load_png_texture_static(selected)
		if tex != null:
			return tex
	if ResourceLoader.exists(selected):
		return load(selected)
	return null

static func _load_png_texture_static(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var absolute_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

static func _icon_for_data(data) -> String:
	var id := _read_string(data, "id", "")
	if not id.is_empty() and WeaponRegistry != null:
		return WeaponRegistry.get_icon_path(id)
	var item_tag := _read_string(data, "item_tag", "")
	return DEFAULT_SHIELD_ICON if item_tag == "shield" else DEFAULT_WEAPON_ICON

static func _equipment_description(data) -> String:
	var item_tag := _read_string(data, "item_tag", "")
	var category := _read_string(data, "equipment_category", "")
	if item_tag == "shield" or category == "shields":
		return _tr("A shield shares the off-hand slot with weapons; switch via scroll wheel.")
	if category.begins_with("armor"):
		return _tr("Armor participates in hit defense and may be damaged on extraction failure.")
	return _tr("A handheld weapon, configurable to any hand slot.")

static func _display_category(category: String) -> String:
	match category:
		"weapons":
			return "Weapon"
		"shields":
			return "Shield"
		"armor_light":
			return "Light Armor"
		"armor_heavy":
			return "Heavy Armor"
		"accessories":
			return "Accessory"
	return category

static func _read_string(source, field: String, fallback: String = "") -> String:
	if source != null and field in source:
		return String(source.get(field))
	return fallback

static func _read_int(source, field: String, fallback: int = 0) -> int:
	if source != null and field in source:
		return int(source.get(field))
	return fallback

static func _read_float(source, field: String, fallback: float = 0.0) -> float:
	if source != null and field in source:
		return float(source.get(field))
	return fallback

static func _tr(message: String) -> String:
	return TranslationServer.translate(message)
