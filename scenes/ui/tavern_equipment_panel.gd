extends Control
class_name TavernEquipmentPanel

const SD := preload("res://globals/combat/skill_data.gd")
const AS := preload("res://globals/combat/action_skills.gd")
const RD := preload("res://globals/combat/rune_data.gd")
const CB := preload("res://globals/combat/combat_bridge.gd")
const CE := preload("res://globals/combat/combat_engine.gd")
const DETAIL_POPUP_SCRIPT := preload("res://scenes/ui/equipment_detail_popup.gd")
const PLAYER_PREVIEW_SCENE := preload("res://scenes/characters/player/player.tscn")
const COMBAT_STATS := preload("res://scenes/ui/equipment_panel_combat_stats.gd")
const PLAYER_FINDER := preload("res://scenes/ui/equipment_panel_player_finder.gd")
const Service := preload("res://globals/core/service.gd")
const SLOT_ICON_SIZE := 92
const RUNE_SLOT_ICON_SIZE := 32
const EQUIPMENT_SLOT_SIZE := Vector2(112, 112)

@onready var return_btn: Button = %ReturnBtn
@onready var slot_head: Button = %SlotHead
@onready var slot_body: Button = %SlotBody
@onready var slot_hands: Button = %SlotHands
@onready var slot_feet: Button = %SlotFeet
@onready var slot_weapon_1: Button = %SlotWeapon1
@onready var slot_weapon_2: Button = %SlotWeapon2
@onready var slot_weapon_3: Button = %SlotWeapon3
@onready var slot_weapon_4: Button = %SlotWeapon4
@onready var eq_viewport: SubViewport = %EqSubViewport
@onready var eq_camera_pivot: Node3D = %EqCameraPivot
@onready var eq_camera: Camera3D = %EqCamera3D
@onready var character_stats_text: Label = %CharacterStatsText
@onready var proficiency_text: Label = %ProficiencyText
@onready var right_tabs: TabContainer = %RightTabs
@onready var gear_list: ItemList = %GearList
@onready var equip_selected_btn: Button = %EquipSelectedBtn
@onready var warehouse_carried_list: ItemList = %WarehouseCarriedList
@onready var warehouse_list: ItemList = %WarehouseList
@onready var skill_slot_0: Button = %SkillSlot0
@onready var skill_slot_1: Button = %SkillSlot1
@onready var skill_slot_2: Button = %SkillSlot2
@onready var skill_slot_3: Button = %SkillSlot3
@onready var skill_slot_4: Button = %SkillSlot4
@onready var skill_slot_5: Button = %SkillSlot5
@onready var skill_slot_6: Button = %SkillSlot6
@onready var rune_warehouse_list: ItemList = %RuneWarehouseList
@onready var available_skills_list: ItemList = %AvailableSkillsList
@onready var skill_details: Label = %SkillDetails
@onready var bind_skill_btn: Button = %BindSkillBtn
@onready var unbind_skill_btn: Button = %UnbindSkillBtn

var selected_skill_id: String = ""
var selected_skill_slot: int = 0
var selected_weapon_slot: int = 0
var selected_armor_slot: String = "body"
var weapon_slot_buttons: Array[Button] = []
var armor_slot_buttons: Dictionary = {}
var skill_slot_buttons: Array[Button] = []
var rune_slot_buttons: Array[Button] = []
var detail_popup
var current_preview_node: Node3D = null
var _slot_icon_cache: Dictionary = {}
var armor_slot_ids := {
	"head": "",
	"body": "",
	"hands": "",
	"feet": "",
}

func _ready() -> void:
	add_to_group("character_panel")
	weapon_slot_buttons = [slot_weapon_1, slot_weapon_2, slot_weapon_3, slot_weapon_4]
	armor_slot_buttons = {
		"head": slot_head,
		"body": slot_body,
		"hands": slot_hands,
		"feet": slot_feet,
	}
	skill_slot_buttons = [skill_slot_0, skill_slot_1, skill_slot_2, skill_slot_3, skill_slot_4, skill_slot_5, skill_slot_6]
	rune_slot_buttons = _collect_rune_slot_buttons()
	detail_popup = DETAIL_POPUP_SCRIPT.new()
	add_child(detail_popup)
	return_btn.pressed.connect(hide_panel)
	for i in range(weapon_slot_buttons.size()):
		weapon_slot_buttons[i].pressed.connect(func(slot_index := i): select_weapon_slot(slot_index))
	slot_head.pressed.connect(func(): select_armor_slot("head"))
	slot_body.pressed.connect(func(): select_armor_slot("body"))
	slot_hands.pressed.connect(func(): select_armor_slot("hands"))
	slot_feet.pressed.connect(func(): select_armor_slot("feet"))
	gear_list.item_activated.connect(_on_gear_item_activated)
	gear_list.item_selected.connect(_on_gear_item_selected)
	equip_selected_btn.pressed.connect(_on_equip_selected_pressed)
	available_skills_list.item_selected.connect(_on_available_skill_selected)
	bind_skill_btn.pressed.connect(_on_bind_skill_pressed)
	unbind_skill_btn.pressed.connect(_on_unbind_skill_pressed)
	_refresh_all()

func show_panel() -> void:
	_refresh_all()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func hide_panel() -> void:
	hide_detail_popup()
	visible = false
	if get_tree() != null and not get_tree().paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		hide_panel()

func _refresh_all() -> void:
	_sync_warehouse_tab_visibility()
	_refresh_equipment_slots()
	_refresh_character_summary()
	_refresh_preview()
	_refresh_items()
	_refresh_warehouse()
	_refresh_skill_rune_warehouse()
	_refresh_skill_slots()
	_refresh_available_skills()

func _refresh_equipment_slots() -> void:
	_prepare_equipment_slot_buttons()
	_refresh_armor_slot_button("head", "头部")
	_refresh_armor_slot_button("body", "身体")
	_refresh_armor_slot_button("hands", "手部")
	_refresh_armor_slot_button("feet", "脚部")
	var eq := _get_player_equipment()
	for i in range(weapon_slot_buttons.size()):
		var active_marker := ""
		var icon: Texture2D = null
		var item_label := "空"
		if eq != null:
			active_marker = " *" if i == eq.active_weapon_slot else ""
			var slot_data := eq.get_weapon_slot_data(i)
			if slot_data != null:
				icon = _slot_icon_for_weapon_data(slot_data)
				item_label = _equipment_display_name(slot_data)
		weapon_slot_buttons[i].text = "手持 %d%s\n[%s]" % [i + 1, active_marker, item_label]
		weapon_slot_buttons[i].icon = icon

func _refresh_items() -> void:
	gear_list.clear()
	_append_materials_to_list(gear_list, _get_carried_inventory(), "items")
	_append_runes_to_list(gear_list, _get_carried_rune_inventory(), "items")
	_append_equipment_to_list(gear_list)
	if gear_list.item_count == 0:
		gear_list.add_item("随身物品为空")
		gear_list.set_item_disabled(0, true)

func _append_equipment_to_list(list: ItemList) -> void:
	var equipment_inventory := _get_carried_equipment_inventory()
	for raw_id in equipment_inventory.keys():
		var equipment_id := String(raw_id)
		var amount := int(equipment_inventory.get(equipment_id, 0))
		if amount <= 0:
			continue
		var meta := WeaponRegistry.get_entry_meta(equipment_id)
		if meta.is_empty():
			continue
		var category := String(meta.get("category", ""))
		var item_type := "armor" if _is_armor_category(category) else "weapon"
		var idx: int = list.add_item("", _icon_for_equipment_id(equipment_id))
		list.set_item_metadata(idx, {
			"type": item_type,
			"id": equipment_id,
			"category": category,
			"amount": amount,
		})
		list.set_item_tooltip(idx, "%s x%d" % [WeaponRegistry.get_display_name(equipment_id), amount])

func _refresh_warehouse() -> void:
	warehouse_carried_list.clear()
	warehouse_list.clear()
	_append_materials_to_list(warehouse_carried_list, _get_carried_inventory(), "items")
	_append_runes_to_list(warehouse_carried_list, _get_carried_rune_inventory(), "items")
	_append_materials_to_list(warehouse_list, _get_warehouse_inventory(), "warehouse")
	_append_runes_to_list(warehouse_list, _get_warehouse_rune_inventory(), "warehouse")
	if warehouse_carried_list.item_count == 0:
		warehouse_carried_list.add_item("随身物品为空")
		warehouse_carried_list.set_item_disabled(0, true)
	if warehouse_list.item_count == 0:
		warehouse_list.add_item("仓库为空")
		warehouse_list.set_item_disabled(0, true)

func _refresh_skill_rune_warehouse() -> void:
	if rune_warehouse_list == null:
		return
	rune_warehouse_list.clear()
	_append_runes_to_list(rune_warehouse_list, _combined_owned_rune_inventory(), "rune_warehouse")
	if rune_warehouse_list.item_count == 0:
		rune_warehouse_list.add_item("符文为空")
		rune_warehouse_list.set_item_disabled(0, true)

func _append_materials_to_list(list: ItemList, inventory: Dictionary, source: String) -> void:
	for item_id in inventory.keys():
		var amount: int = int(inventory[item_id])
		if amount <= 0:
			continue
		var idx: int = list.add_item("x%d" % amount, DETAIL_POPUP_SCRIPT.icon_for_material(item_id))
		list.set_item_metadata(idx, {"type": "material", "id": item_id, "source": source, "amount": amount})
		list.set_item_tooltip(idx, "%s x%d" % [_get_material_name(item_id), amount])

func _append_runes_to_list(list: ItemList, inventory: Dictionary, source: String) -> void:
	for rune_id in inventory.keys():
		var amount: int = int(inventory[rune_id])
		if amount <= 0:
			continue
		var id := String(rune_id)
		var idx: int = list.add_item("x%d" % amount, DETAIL_POPUP_SCRIPT.icon_for_rune(id))
		list.set_item_metadata(idx, {"type": "rune", "id": id, "source": source, "amount": amount})
		list.set_item_tooltip(idx, "%s x%d" % [RD.get_rune_name(id), amount])

func _combined_owned_rune_inventory() -> Dictionary:
	var combined: Dictionary = {}
	for inventory in [_get_carried_rune_inventory(), _get_warehouse_rune_inventory()]:
		for raw_id in inventory.keys():
			var rune_id := String(raw_id)
			combined[rune_id] = int(combined.get(rune_id, 0)) + int(inventory[raw_id])
	return combined

func select_weapon_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= 4:
		return false
	selected_weapon_slot = slot_index
	_refresh_equipment_slots()
	return true

func select_armor_slot(slot_name: String) -> bool:
	if not armor_slot_ids.has(slot_name):
		return false
	selected_armor_slot = slot_name
	_refresh_equipment_slots()
	return true

func configure_selected_weapon_slot(weapon_id: String) -> bool:
	var eq := _get_player_equipment()
	if eq == null:
		return false
	var weapon := WeaponRegistry.get_weapon_data(weapon_id)
	if weapon == null:
		return false
	var previous := eq.get_weapon_slot_data(selected_weapon_slot)
	var previous_id := String(previous.id) if previous != null and "id" in previous else ""
	if previous_id == weapon_id:
		var activated := eq.activate_weapon_slot(selected_weapon_slot) if eq.has_method("activate_weapon_slot") else true
		if activated:
			_apply_equipment_changed(eq)
		return activated
	if not _consume_carried_equipment(weapon_id):
		return false
	var ok: bool = eq.configure_weapon_slot(selected_weapon_slot, weapon, true)
	if ok:
		_return_carried_equipment(previous_id)
		_apply_equipment_changed(eq)
	else:
		_return_carried_equipment(weapon_id)
	return ok

func configure_armor_slot(slot_name: String, armor_id: String) -> bool:
	if not armor_slot_ids.has(slot_name):
		return false
	var meta: Dictionary = WeaponRegistry.get_entry_meta(armor_id)
	var category: String = meta.get("category", "")
	if not _is_armor_category(category):
		return false
	var armor := WeaponRegistry.get_weapon_data(armor_id)
	var eq := _get_player_equipment()
	if eq == null:
		return false
	var previous := eq.get_armor_slot_data(slot_name)
	var previous_id := String(previous.id) if previous != null and "id" in previous else ""
	if previous_id == armor_id:
		return true
	if not _consume_carried_equipment(armor_id):
		return false
	if not eq.configure_armor_slot(slot_name, armor):
		_return_carried_equipment(armor_id)
		return false
	_return_carried_equipment(previous_id)
	armor_slot_ids[slot_name] = armor_id
	_apply_equipment_changed(eq)
	return true

func _apply_equipment_changed(eq: EquipmentComponent) -> void:
	if eq != null:
		var gs := Service.game_state()
		if gs != null and gs.has_method("save_equipment_from_player"):
			gs.save_equipment_from_player(_get_current_player())
		if eq.has_method("show_weapon"):
			eq.show_weapon()
		if eq.has_method("show_shield"):
			eq.show_shield()
		if "weapon_data" in eq:
			GameEvents.weapon_changed.emit(eq.weapon_data)
		if eq.has_method("get_active_shield_data"):
			GameEvents.shield_changed.emit(eq.get_active_shield_data())
	_refresh_equipment_slots()
	_refresh_character_summary()
	_refresh_items()
	_refresh_warehouse()
	call_deferred("_refresh_preview")
	_ensure_mouse_visible()

func _on_gear_item_activated(index: int) -> void:
	var meta = gear_list.get_item_metadata(index)
	_equip_gear_metadata(meta)

func _on_gear_item_selected(index: int) -> void:
	var meta = gear_list.get_item_metadata(index)
	if typeof(meta) == TYPE_DICTIONARY and (meta.get("type", "") == "weapon" or meta.get("type", "") == "armor"):
		_refresh_preview(String(meta.get("id", "")))
	else:
		_refresh_preview()

func _on_equip_selected_pressed() -> void:
	var selected := gear_list.get_selected_items()
	if selected.is_empty():
		return
	var meta = gear_list.get_item_metadata(selected[0])
	_equip_gear_metadata(meta)

func _equip_gear_metadata(meta: Variant) -> void:
	if typeof(meta) != TYPE_DICTIONARY:
		return
	match meta.get("type", ""):
		"weapon":
			configure_selected_weapon_slot(String(meta.get("id", "")))
		"armor":
			var armor_data := WeaponRegistry.get_weapon_data(String(meta.get("id", "")))
			var target_slot := armor_data.armor_slot if armor_data != null and not armor_data.armor_slot.is_empty() else selected_armor_slot
			configure_armor_slot(target_slot, String(meta.get("id", "")))

func _refresh_skill_slots() -> void:
	var sr: Node = _get_skill_runtime()
	for i in range(7):
		var bound: String = sr.get_slot_skill(i) if sr != null else ""
		var label: String = _slot_label(i)
		var selected_marker := " *" if i == selected_skill_slot else ""
		var skill_name := bound if bound != "" else "空"
		if i >= 0 and i < skill_slot_buttons.size():
			skill_slot_buttons[i].text = "%s%s\n%s" % [label, selected_marker, skill_name]
	_refresh_rune_slots()

func _refresh_rune_slots() -> void:
	var sr: Node = _get_skill_runtime()
	for button in rune_slot_buttons:
		var skill_index: int = int(button.get("skill_slot_index"))
		var socket_index: int = int(button.get("rune_socket_index"))
		var capacity := _rune_slot_capacity(skill_index)
		button.visible = socket_index < capacity
		button.disabled = not button.visible
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if not button.visible:
			continue
		var runes: Array = sr.get_slot_runes(skill_index) if sr != null and sr.has_method("get_slot_runes") else []
		if socket_index < runes.size():
			var rune_id := String(runes[socket_index])
			button.text = ""
			button.icon = _scaled_rune_slot_icon(DETAIL_POPUP_SCRIPT.icon_for_rune(rune_id))
			button.tooltip_text = RD.get_rune_name(rune_id)
		else:
			button.text = "-"
			button.icon = null
			button.tooltip_text = ""

func _refresh_available_skills() -> void:
	available_skills_list.clear()
	for skill in AS.SKILLS:
		_add_available_skill(skill)
	var ap: Node = _get_attr_panel()
	for skill in SD.SKILLS:
		if ap != null and ap.has_skill(skill["id"]):
			_add_available_skill(skill)
	if available_skills_list.item_count > 0:
		available_skills_list.select(0)
		_on_available_skill_selected(0)

func _add_available_skill(skill: Dictionary) -> void:
	var idx: int = available_skills_list.add_item("%s  [%s]" % [skill["name"], skill["type"]])
	available_skills_list.set_item_metadata(idx, skill)

func _on_available_skill_selected(index: int) -> void:
	var skill: Dictionary = available_skills_list.get_item_metadata(index)
	selected_skill_id = skill.get("id", "")
	skill_details.text = "%s\nCD: %.1fs\n%s" % [
		skill.get("name", selected_skill_id),
		float(skill.get("cooldown", 0.0)),
		skill.get("desc", "")
	]

func select_skill_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= 7:
		return false
	selected_skill_slot = slot_index
	var sr: Node = _get_skill_runtime()
	var bound: String = sr.get_slot_skill(slot_index) if sr != null else ""
	if bound != "":
		selected_skill_id = bound
		var skill: Dictionary = AS.get_skill_by_id(bound)
		if skill.is_empty():
			skill = SD.get_skill_by_id(bound)
		skill_details.text = "%s\n%s" % [skill.get("name", bound), skill.get("desc", "")]
	else:
		skill_details.text = "%s\n空" % _slot_label(slot_index)
	_refresh_skill_slots()
	return true

func _on_bind_skill_pressed() -> void:
	if selected_skill_id == "":
		return
	if not configure_skill_slot(selected_skill_slot, selected_skill_id):
		skill_details.text = "无法绑定到该槽位"

func _on_unbind_skill_pressed() -> void:
	configure_skill_slot(selected_skill_slot, "")

func configure_skill_slot(slot_index: int, skill_id: String) -> bool:
	var sr: Node = _get_skill_runtime()
	if sr == null:
		return false
	var ok: bool = sr.bind_skill(slot_index, skill_id)
	if ok:
		_refresh_skill_slots()
		select_skill_slot(slot_index)
	return ok

func configure_skill_slot_rune(slot_index: int, rune_id: String) -> bool:
	var sr: Node = _get_skill_runtime()
	if sr == null or not sr.has_method("socket_rune"):
		return false
	var ok: bool = sr.socket_rune(slot_index, rune_id)
	if ok:
		_consume_rune_from_inventory(rune_id)
		_refresh_items()
		_refresh_warehouse()
		_refresh_skill_rune_warehouse()
		_refresh_skill_slots()
		select_skill_slot(slot_index)
	return ok

func collect_drag_payload(source: String) -> Dictionary:
	var list: ItemList = _list_for_source(source)
	if list == null:
		return {}
	for index in list.get_selected_items():
		var meta = list.get_item_metadata(index)
		if typeof(meta) == TYPE_DICTIONARY and (meta.get("type", "") == "weapon" or meta.get("type", "") == "armor"):
			return {
				"kind": "equipment",
				"id": String(meta.get("id", "")),
				"category": String(meta.get("category", "")),
				"count": int(meta.get("amount", 1)),
			}
	var ids: Array[String] = []
	var rune_ids: Array[String] = []
	for index in list.get_selected_items():
		var meta = list.get_item_metadata(index)
		if typeof(meta) == TYPE_DICTIONARY and meta.get("type", "") == "material":
			ids.append(String(meta["id"]))
		elif typeof(meta) == TYPE_DICTIONARY and meta.get("type", "") == "rune":
			rune_ids.append(String(meta["id"]))
	if ids.is_empty() and rune_ids.is_empty():
		return {}
	if not ids.is_empty() and rune_ids.is_empty():
		return {"kind": "inventory_materials", "source": source, "ids": ids, "count": ids.size()}
	if ids.is_empty() and not rune_ids.is_empty():
		return {"kind": "inventory_runes", "source": source, "rune_ids": rune_ids, "count": rune_ids.size()}
	return {"kind": "inventory_stacks", "source": source, "ids": ids, "rune_ids": rune_ids, "count": ids.size() + rune_ids.size()}

func can_drop_inventory_data(target: String, data: Variant) -> bool:
	var kind := String(data.get("kind", "")) if typeof(data) == TYPE_DICTIONARY else ""
	return typeof(data) == TYPE_DICTIONARY \
		and (kind == "inventory_materials" or kind == "inventory_runes" or kind == "inventory_stacks") \
		and data.get("source", "") != target \
		and (target == "items" or target == "warehouse") \
		and (not _uses_warehouse(String(data.get("source", "")), target) or _is_warehouse_available())

func drop_inventory_data(target: String, data: Variant) -> void:
	if not can_drop_inventory_data(target, data):
		return
	transfer_inventory_items(String(data["source"]), target, data.get("ids", []), data.get("rune_ids", []))

func can_drop_equipment_slot_data(slot_kind: String, slot_index: int, armor_slot: String, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("kind", "") != "equipment":
		return false
	var category: String = data.get("category", "")
	match slot_kind:
		"weapon":
			return slot_index >= 0 and slot_index < 4 and _is_hand_category(category)
		"armor":
			return armor_slot_ids.has(armor_slot) and _is_armor_category(category)
	return false

func drop_equipment_slot_data(slot_kind: String, slot_index: int, armor_slot: String, data: Variant) -> void:
	if not can_drop_equipment_slot_data(slot_kind, slot_index, armor_slot, data):
		_ensure_mouse_visible()
		return
	var equipment_id: String = data.get("id", "")
	match slot_kind:
		"weapon":
			select_weapon_slot(slot_index)
			configure_selected_weapon_slot(equipment_id)
		"armor":
			configure_armor_slot(armor_slot, equipment_id)
	_ensure_mouse_visible()

func _ensure_mouse_visible() -> void:
	if visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func collect_skill_drag_payload(source: String) -> Dictionary:
	match source:
		"available_skills":
			if available_skills_list.get_selected_items().is_empty():
				return {}
			var skill: Dictionary = available_skills_list.get_item_metadata(available_skills_list.get_selected_items()[0])
			return {"kind": "skill", "id": String(skill.get("id", "")), "count": 1}
		"skill_slots":
			return collect_skill_slot_drag_payload(selected_skill_slot)
	return {}

func collect_skill_slot_drag_payload(slot_index: int) -> Dictionary:
	var sr: Node = _get_skill_runtime()
	var bound: String = sr.get_slot_skill(slot_index) if sr != null else ""
	if bound == "":
		return {}
	return {"kind": "skill", "id": bound, "source_slot": slot_index, "count": 1}

func can_drop_skill_slot_data(slot_index: int, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var kind := String(data.get("kind", ""))
	if kind == "skill":
		return _can_bind_skill_to_slot(slot_index, String(data.get("id", "")))
	if kind == "rune" or kind == "inventory_runes":
		var rune_id := String(data.get("id", ""))
		if rune_id.is_empty():
			var ids: Array = data.get("rune_ids", [])
			rune_id = String(ids[0]) if not ids.is_empty() else ""
		return _can_socket_rune_to_slot(slot_index, rune_id)
	return false

func drop_skill_slot_data(slot_index: int, data: Variant) -> void:
	if not can_drop_skill_slot_data(slot_index, data):
		return
	var kind := String(data.get("kind", ""))
	if kind == "skill":
		configure_skill_slot(slot_index, String(data.get("id", "")))
	elif kind == "rune":
		configure_skill_slot_rune(slot_index, String(data.get("id", "")))
	elif kind == "inventory_runes":
		for raw_id in data.get("rune_ids", []):
			if not configure_skill_slot_rune(slot_index, String(raw_id)):
				break

func can_drop_rune_socket_data(slot_index: int, rune_socket_index: int, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if rune_socket_index < 0 or rune_socket_index >= _rune_slot_capacity(slot_index):
		return false
	var sr: Node = _get_skill_runtime()
	var runes: Array = sr.get_slot_runes(slot_index) if sr != null and sr.has_method("get_slot_runes") else []
	if rune_socket_index < runes.size():
		return false
	return can_drop_skill_slot_data(slot_index, data)

func drop_rune_socket_data(slot_index: int, rune_socket_index: int, data: Variant) -> void:
	if can_drop_rune_socket_data(slot_index, rune_socket_index, data):
		drop_skill_slot_data(slot_index, data)

func show_inventory_item_detail(source: String, item_index: int, screen_position: Vector2) -> void:
	var list := _list_for_source(source)
	if list == null or item_index < 0 or item_index >= list.item_count:
		hide_detail_popup()
		return
	var meta = list.get_item_metadata(item_index)
	if typeof(meta) != TYPE_DICTIONARY:
		hide_detail_popup()
		return
	match String(meta.get("type", "")):
		"weapon", "armor":
			detail_popup.show_for_equipment_id(String(meta.get("id", "")), screen_position)
		"material":
			detail_popup.show_for_material_id(String(meta.get("id", "")), int(meta.get("amount", 1)), screen_position)
		"rune":
			detail_popup.show_for_rune_id(String(meta.get("id", "")), int(meta.get("amount", 1)), screen_position)
		_:
			hide_detail_popup()

func show_equipment_slot_detail(slot_kind: String, slot_index: int, armor_slot: String, screen_position: Vector2) -> void:
	var eq := _get_player_equipment()
	if eq == null:
		hide_detail_popup()
		return
	match slot_kind:
		"weapon":
			detail_popup.show_for_weapon_data(eq.get_weapon_slot_data(slot_index), screen_position)
		"armor":
			detail_popup.show_for_weapon_data(eq.get_armor_slot_data(armor_slot), screen_position)
		_:
			hide_detail_popup()

func hide_detail_popup() -> void:
	if detail_popup != null:
		detail_popup.hide_detail()

func transfer_materials(source: String, target: String, item_ids: Array) -> Dictionary:
	var source_inv: Dictionary = _inventory_for_source(source)
	var target_inv: Dictionary = _inventory_for_source(target)
	var moved: Dictionary = move_items_between(source_inv, target_inv, item_ids, target == "items", GameState.MATERIAL_SPACE_PER_ITEM)
	_refresh_items()
	_refresh_warehouse()
	_refresh_skill_rune_warehouse()
	return moved

func transfer_inventory_items(source: String, target: String, material_ids: Array, rune_ids: Array) -> Dictionary:
	var moved := {
		"materials": move_items_between(_inventory_for_source(source), _inventory_for_source(target), material_ids, target == "items", GameState.MATERIAL_SPACE_PER_ITEM),
		"runes": move_items_between(_rune_inventory_for_source(source), _rune_inventory_for_source(target), rune_ids, target == "items", GameState.RUNE_SPACE_PER_ITEM),
	}
	_refresh_items()
	_refresh_warehouse()
	_refresh_skill_rune_warehouse()
	return moved

func move_items_between(source_inv: Dictionary, target_inv: Dictionary, item_ids: Array, target_is_carried: bool = false, space_per_item: int = 1) -> Dictionary:
	var moved: Dictionary = {}
	for raw_id in item_ids:
		var item_id: String = String(raw_id)
		var amount: int = int(source_inv.get(item_id, 0))
		if amount <= 0:
			continue
		if target_is_carried and not _can_add_carried_stack(amount, space_per_item):
			continue
		target_inv[item_id] = int(target_inv.get(item_id, 0)) + amount
		source_inv.erase(item_id)
		moved[item_id] = amount
	return moved

func _refresh_armor_slot_button(slot_name: String, display_name: String) -> void:
	var button: Button = armor_slot_buttons.get(slot_name, null)
	if button == null:
		return
	var marker := " *" if selected_armor_slot == slot_name else ""
	var item_label := "空"
	button.icon = null
	var eq := _get_player_equipment()
	var slot_data = eq.get_armor_slot_data(slot_name) if eq != null else null
	if slot_data != null:
		armor_slot_ids[slot_name] = slot_data.id
		button.icon = _slot_icon_for_weapon_data(slot_data)
		item_label = _equipment_display_name(slot_data)
	else:
		armor_slot_ids[slot_name] = ""
		var equipment_id: String = armor_slot_ids.get(slot_name, "")
		if not equipment_id.is_empty():
			button.icon = _slot_icon_for_equipment_id(equipment_id)
			item_label = WeaponRegistry.get_display_name(equipment_id)
	button.text = "%s%s\n[%s]" % [display_name, marker, item_label]

func _refresh_character_summary() -> void:
	if character_stats_text == null or proficiency_text == null:
		return
	var player := _get_current_player()
	var eq := _get_player_equipment()
	var ap := _get_attr_panel()
	var stats_lines: Array[String] = []
	if player != null and "health" in player and player.health != null:
		stats_lines.append("生命 %d/%d" % [player.health.current_life, player.health.max_life])
	if ap != null and ap.has_method("get_level"):
		stats_lines.append("等级 %d" % int(ap.get_level()))
	if ap != null and ap.has_method("get_player_attrs"):
		var attrs: Dictionary = ap.get_player_attrs()
		var attr_parts: Array[String] = []
		for key in ["str", "dex", "mag", "con", "agi", "per"]:
			attr_parts.append("%s %d" % [key.to_upper(), int(attrs.get(key, 0))])
		stats_lines.append("属性 " + "  ".join(attr_parts))
	if eq != null:
		var weapon := eq.weapon_data if "weapon_data" in eq else null
		if weapon != null:
			stats_lines.append("当前手持 %s" % _equipment_display_name(weapon))
			stats_lines.append("基础伤害 %d-%d  距离 %.1fm" % [weapon.damage_min, weapon.damage_max, weapon.reach])
		else:
			stats_lines.append("当前手持 空")
		stats_lines.append_array(_build_combat_stat_lines(player, eq, ap))
	if stats_lines.is_empty():
		stats_lines.append("未找到实机角色")
	character_stats_text.text = "\n".join(stats_lines)

	var prof_lines: Array[String] = []
	var prof_names := {
		"one_hand_melee": "单手",
		"two_hand": "双手",
		"longbow": "长弓",
		"crossbow": "轻弩",
		"wand": "法杖",
		"grimoire": "魔导书",
		"shield": "持盾",
		"unarmed": "徒手",
	}
	if ap != null and "weapon_proficiency" in ap:
		var prof: Dictionary = ap.weapon_proficiency
		for key in ["one_hand_melee", "two_hand", "longbow", "crossbow", "wand", "grimoire", "shield", "unarmed"]:
			prof_lines.append("%s %d" % [prof_names.get(key, key), int(prof.get(key, 0))])
	if prof_lines.is_empty():
		prof_lines.append("暂无熟练度记录")
	proficiency_text.text = "\n".join(prof_lines)

func _refresh_preview(preview_equipment_id: String = "") -> void:
	if eq_viewport == null:
		return
	var preview_hand_data: WeaponData = null
	var eq := _get_player_equipment()
	if eq != null:
		preview_hand_data = eq.weapon_data if "weapon_data" in eq else null
	if not preview_equipment_id.is_empty():
		var data := WeaponRegistry.get_weapon_data(preview_equipment_id)
		if data != null and _is_hand_category(data.equipment_category):
			preview_hand_data = data
	_spawn_preview_character(preview_hand_data)

func _clear_preview() -> void:
	if current_preview_node != null and is_instance_valid(current_preview_node):
		current_preview_node.queue_free()
	current_preview_node = null

func _spawn_preview_character(hand_data: WeaponData = null) -> void:
	_clear_preview()
	var preview_player := PLAYER_PREVIEW_SCENE.instantiate() as Player
	if preview_player == null:
		return
	preview_player.set_meta("equipment_preview", true)
	eq_viewport.add_child(preview_player)
	current_preview_node = preview_player
	preview_player.position = Vector3(0, -0.85, 0)
	preview_player.rotation = Vector3(0, deg_to_rad(35), 0)
	preview_player.set_process(false)
	preview_player.set_physics_process(false)
	preview_player.set_process_input(false)
	preview_player.set_process_unhandled_input(false)
	preview_player.movement_input_enabled = false
	preview_player.interaction_input_enabled = false
	preview_player.combat_input_enabled = false
	if preview_player.equipment != null:
		preview_player.equipment.is_linked_to_ui = false
		if hand_data != null:
			preview_player.equipment.configure_weapon_slot(0, hand_data, true)
	if preview_player.camera != null:
		preview_player.camera.queue_free()
	for path in ["%SelectRaycast", "%KickRaycast", "%WeaponReachRaycast"]:
		var ray_node := preview_player.get_node_or_null(NodePath(path))
		if ray_node != null:
			ray_node.queue_free()
	var collision := preview_player.get_node_or_null("CollisionShape3D")
	if collision != null:
		collision.queue_free()
	if preview_player.animation_player != null and preview_player.animation_player.has_animation("idle"):
		preview_player.animation_player.play("idle")

func _prepare_equipment_slot_buttons() -> void:
	for button in armor_slot_buttons.values():
		_prepare_icon_button(button)
	for button in weapon_slot_buttons:
		_prepare_icon_button(button)

func _prepare_icon_button(button: Button) -> void:
	if button == null:
		return
	button.custom_minimum_size = EQUIPMENT_SLOT_SIZE
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_combat_stat_lines(player: Player, eq: EquipmentComponent, ap: Node) -> Array[String]:
	return COMBAT_STATS.build_stat_lines(player, eq, ap)

func _equipment_display_name(data) -> String:
	if data == null:
		return "空"
	if "name_zh" in data and not String(data.name_zh).is_empty():
		return String(data.name_zh)
	if "name" in data:
		return String(data.name)
	return "装备"

func _is_armor_category(category: String) -> bool:
	return category.begins_with("armor")

func _is_hand_category(category: String) -> bool:
	return category == "weapons" or category == "shields"

func _can_bind_skill_to_slot(slot_index: int, skill_id: String) -> bool:
	var sr: Node = _get_skill_runtime()
	if sr == null or slot_index < 0 or slot_index >= 7 or skill_id == "":
		return false
	var slot_type: int = sr.get_slot_type(slot_index)
	match slot_type:
		SkillRuntime.SlotType.F_ACTION, SkillRuntime.SlotType.G_WEAPON:
			if not AS.get_skill_by_id(skill_id).is_empty():
				return true
			var active_skill: Dictionary = SD.get_skill_by_id(skill_id)
			return not active_skill.is_empty() and active_skill.get("type", "") == "active" and _attr_panel_has_skill(skill_id)
		SkillRuntime.SlotType.PASSIVE:
			var passive_skill: Dictionary = SD.get_skill_by_id(skill_id)
			return not passive_skill.is_empty() and passive_skill.get("type", "") == "passive" and _attr_panel_has_skill(skill_id)
	return false

func _can_socket_rune_to_slot(slot_index: int, rune_id: String) -> bool:
	var sr: Node = _get_skill_runtime()
	if sr == null or not sr.has_method("get_slot_runes"):
		return false
	if slot_index < 0 or slot_index >= 7 or rune_id.is_empty() or not RD.has_rune(rune_id):
		return false
	if sr.get_slot_skill(slot_index) == "":
		return false
	var runes: Array = sr.get_slot_runes(slot_index)
	return runes.size() < _rune_slot_capacity(slot_index)

func _attr_panel_has_skill(skill_id: String) -> bool:
	var ap: Node = _get_attr_panel()
	return ap != null and ap.has_method("has_skill") and ap.has_skill(skill_id)

func _list_for_source(source: String) -> ItemList:
	match source:
		"items":
			if right_tabs.current_tab == 2:
				return warehouse_carried_list
			return gear_list
		"warehouse":
			return warehouse_list
		"rune_warehouse":
			return rune_warehouse_list
	return null

func _inventory_for_source(source: String) -> Dictionary:
	match source:
		"items":
			return _get_carried_inventory()
		"warehouse":
			return _get_warehouse_inventory()
	return {}

func _rune_inventory_for_source(source: String) -> Dictionary:
	match source:
		"items":
			return _get_carried_rune_inventory()
		"warehouse":
			return _get_warehouse_rune_inventory()
	return {}

func _get_carried_inventory() -> Dictionary:
	var gs: Node = Service.game_state()
	if gs != null and "carried_materials" in gs:
		return gs.carried_materials
	return {}

func _get_carried_rune_inventory() -> Dictionary:
	var gs: Node = Service.game_state()
	if gs != null and "carried_runes" in gs:
		return gs.carried_runes
	return {}

func _get_carried_equipment_inventory() -> Dictionary:
	var gs: Node = Service.game_state()
	if gs != null and "carried_equipment" in gs:
		return gs.carried_equipment
	return {}

func _get_warehouse_inventory() -> Dictionary:
	var tm: Node = Service.tavern_manager()
	if tm != null and "materials_inventory" in tm:
		return tm.materials_inventory
	return {}

func _get_warehouse_rune_inventory() -> Dictionary:
	var tm: Node = Service.tavern_manager()
	if tm != null and "runes_inventory" in tm:
		return tm.runes_inventory
	return {}

func _consume_rune_from_inventory(rune_id: String) -> bool:
	for inventory in [_get_carried_rune_inventory(), _get_warehouse_rune_inventory()]:
		var amount := int(inventory.get(rune_id, 0))
		if amount <= 0:
			continue
		if amount > 1:
			inventory[rune_id] = amount - 1
		else:
			inventory.erase(rune_id)
		return true
	return false

func _consume_carried_equipment(equipment_id: String) -> bool:
	var gs: Node = Service.game_state()
	if gs == null or not gs.has_method("remove_carried_equipment"):
		return false
	return gs.remove_carried_equipment(equipment_id, 1)

func _return_carried_equipment(equipment_id: String) -> void:
	if equipment_id.is_empty():
		return
	var gs: Node = Service.game_state()
	if gs != null and gs.has_method("add_carried_equipment"):
		gs.add_carried_equipment(equipment_id, 1)

func _can_add_carried_stack(amount: int, space_per_item: int) -> bool:
	var gs: Node = Service.game_state()
	if gs == null or not gs.has_method("can_add_carried_space"):
		return false
	return gs.can_add_carried_space(amount * space_per_item)

func _uses_warehouse(source: String, target: String) -> bool:
	return source == "warehouse" or target == "warehouse"

func _sync_warehouse_tab_visibility() -> void:
	if right_tabs == null or right_tabs.get_tab_count() <= 2:
		return
	var available := _is_warehouse_available()
	right_tabs.set_tab_hidden(2, not available)
	right_tabs.set_tab_disabled(2, not available)
	if not available and right_tabs.current_tab == 2:
		right_tabs.current_tab = 0

func _is_warehouse_available() -> bool:
	var node: Node = self
	while node != null:
		if "current_space" in node:
			return String(node.get("current_space")) == "tavern"
		node = node.get_parent()
	var gs := Service.game_state()
	if gs != null and "current_level" in gs:
		var level = gs.current_level
		if level != null and is_instance_valid(level):
			if level is TavernInterior or String(level.name).to_lower().contains("tavern"):
				return true
	var tm := Service.tavern_manager()
	if tm != null and "current_phase" in tm:
		return int(tm.current_phase) == 1
	return false

func _get_material_name(item_id: String) -> String:
	var tm: Node = Service.tavern_manager()
	if tm != null and tm.materials_db.has(item_id):
		return String(tm.materials_db[item_id].get("name", item_id))
	return item_id.replace("_", " ").capitalize()

func _icon_for_equipment_id(equipment_id: String) -> Texture2D:
	return DETAIL_POPUP_SCRIPT.icon_for_equipment_id(equipment_id)

func _icon_for_weapon_data(data: WeaponData) -> Texture2D:
	if data == null:
		return null
	return DETAIL_POPUP_SCRIPT.icon_for_equipment_id(data.id)

func _slot_icon_for_equipment_id(equipment_id: String) -> Texture2D:
	return _scaled_slot_icon(_icon_for_equipment_id(equipment_id))

func _slot_icon_for_weapon_data(data: WeaponData) -> Texture2D:
	return _scaled_slot_icon(_icon_for_weapon_data(data))

func _scaled_slot_icon(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var cache_key := texture.get_rid().get_id()
	if _slot_icon_cache.has(cache_key):
		return _slot_icon_cache[cache_key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image.resize(SLOT_ICON_SIZE, SLOT_ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	var scaled := ImageTexture.create_from_image(image)
	_slot_icon_cache[cache_key] = scaled
	return scaled

func _scaled_rune_slot_icon(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var cache_key := "rune_%s" % texture.get_rid().get_id()
	if _slot_icon_cache.has(cache_key):
		return _slot_icon_cache[cache_key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image.resize(RUNE_SLOT_ICON_SIZE, RUNE_SLOT_ICON_SIZE, Image.INTERPOLATE_NEAREST)
	var scaled := ImageTexture.create_from_image(image)
	_slot_icon_cache[cache_key] = scaled
	return scaled

func _collect_rune_slot_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for node in find_children("RuneSlot*", "Button", true, false):
		if "skill_slot_index" in node and "rune_socket_index" in node:
			buttons.append(node as Button)
	buttons.sort_custom(func(a: Button, b: Button) -> bool:
		var a_slot: int = int(a.get("skill_slot_index"))
		var b_slot: int = int(b.get("skill_slot_index"))
		if a_slot == b_slot:
			return int(a.get("rune_socket_index")) < int(b.get("rune_socket_index"))
		return a_slot < b_slot
	)
	return buttons

func _rune_slot_capacity(slot_index: int) -> int:
	var sr: Node = _get_skill_runtime()
	if sr != null and sr.has_method("get_rune_capacity"):
		return int(sr.get_rune_capacity(slot_index))
	return 2 if slot_index >= 2 else SkillRuntime.MAX_RUNES_PER_SLOT

func _get_player_equipment() -> EquipmentComponent:
	var player := _get_current_player()
	if player != null and "equipment" in player and player.equipment != null:
		return player.equipment
	return null

func _get_current_player() -> Player:
	return PLAYER_FINDER.get_current_player()

func _slot_label(slot_index: int) -> String:
	match slot_index:
		0:
			return "F 主动槽"
		1:
			return "G 主动槽"
		_:
			return "被动槽 %d" % (slot_index - 1)

func _format_slot_runes(runes: Array) -> String:
	if runes.is_empty():
		return ""
	var names: Array[String] = []
	for raw_id in runes:
		names.append(RD.get_rune_name(String(raw_id)))
	return "\n符文: %s" % " / ".join(names)

func _get_skill_runtime() -> Node:
	return Service.skill_runtime()

func _get_attr_panel() -> Node:
	return Service.attr_panel()
