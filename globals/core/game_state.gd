extends Node

var current_keys : Dictionary[Door.KeyColor, bool] = {}
var current_level : Node3D
var current_player : Player

# 角色随身状态：酒馆/地牢共用，不随场景切换清空。
var carried_materials: Dictionary = {}   # material_id → 数量
var carried_runes: Dictionary = {}       # rune_id → 数量
var carried_equipment: Dictionary = {}   # equipment_id → 数量（未装备的背包装备）
var carried_weapons: int = 0             # 探险获得的武器统计
var carried_shields: int = 0             # 探险获得的盾统计
var weapon_slot_ids: Array[String] = ["", "", "", ""]
var armor_slot_ids: Dictionary = {
	"head": "",
	"body": "",
	"hands": "",
	"feet": "",
}
var active_weapon_slot: int = 0

const EXPEDITION_FAILURE_DAMAGE_FRACTION := 1.0
const DEFAULT_CARRIED_SPACE_LIMIT := 30
const MATERIAL_SPACE_PER_ITEM := 1
const RUNE_SPACE_PER_ITEM := 1
const EQUIPMENT_SPACE_PER_ITEM := 1

var carried_space_limit: int = DEFAULT_CARRIED_SPACE_LIMIT

func has_key(color: Door.KeyColor) -> bool:
	return current_keys.get(color, false)

func use_key(color: Door.KeyColor) -> void:
	current_keys[color] = false
	GameEvents.current_keys_changed.emit(color)

func obtain_key(color: Door.KeyColor) -> void:
	current_keys[color] = true
	GameEvents.current_keys_changed.emit(color)

func register_level(level: Node3D) -> void:
	current_level = level
	current_keys = {}

func register_player(player: Player) -> void:
	if player != null and player.has_meta("equipment_preview"):
		return
	current_player = player
	if _has_saved_equipment_loadout():
		apply_equipment_to_player(player)
	else:
		save_equipment_from_player(player)

## 记录拾取材料（地牢内实时调用）
func add_carried_material(material_id: String, amount: int = 1) -> bool:
	if material_id.is_empty() or amount <= 0:
		return false
	if not can_add_carried_space(amount * MATERIAL_SPACE_PER_ITEM):
		return false
	carried_materials[material_id] = int(carried_materials.get(material_id, 0)) + amount
	return true

func add_carried_rune(rune_id: String, amount: int = 1) -> bool:
	if rune_id.is_empty() or amount <= 0:
		return false
	if not can_add_carried_space(amount * RUNE_SPACE_PER_ITEM):
		return false
	carried_runes[rune_id] = int(carried_runes.get(rune_id, 0)) + amount
	return true

## 记录未装备的背包装备
func add_carried_equipment(equipment_id: String, amount: int = 1) -> bool:
	if equipment_id.is_empty() or amount <= 0:
		return false
	if not can_add_carried_space(amount * EQUIPMENT_SPACE_PER_ITEM):
		return false
	carried_equipment[equipment_id] = int(carried_equipment.get(equipment_id, 0)) + amount
	return true

func remove_carried_equipment(equipment_id: String, amount: int = 1) -> bool:
	if equipment_id.is_empty() or amount <= 0:
		return false
	var current := int(carried_equipment.get(equipment_id, 0))
	if current < amount:
		return false
	var remaining := current - amount
	if remaining > 0:
		carried_equipment[equipment_id] = remaining
	else:
		carried_equipment.erase(equipment_id)
	return true

func get_carried_equipment_dict() -> Dictionary:
	return carried_equipment.duplicate()

## 记录拾取武器
func add_carried_weapon(equipment_id: String = "") -> bool:
	if not equipment_id.is_empty():
		if not add_carried_equipment(equipment_id, 1):
			return false
	carried_weapons += 1
	return true

## 记录拾取盾
func add_carried_shield(equipment_id: String = "") -> bool:
	if not equipment_id.is_empty():
		if not add_carried_equipment(equipment_id, 1):
			return false
	carried_shields += 1
	return true

func can_add_carried_space(space: int) -> bool:
	if space <= 0:
		return true
	return get_carried_space_used() + space <= carried_space_limit

func get_carried_space_used() -> int:
	return _sum_inventory(carried_materials) * MATERIAL_SPACE_PER_ITEM \
		+ _sum_inventory(carried_runes) * RUNE_SPACE_PER_ITEM \
		+ _sum_inventory(carried_equipment) * EQUIPMENT_SPACE_PER_ITEM

func get_carried_space_limit() -> int:
	return carried_space_limit

func get_carried_space_free() -> int:
	return maxi(0, carried_space_limit - get_carried_space_used())

## 获取本局携带材料总数
func get_carried_materials() -> int:
	var total: int = 0
	for k in carried_materials.keys():
		total += int(carried_materials[k])
	return total

## 获取本局携带材料字典（material_id → 数量）
func get_carried_materials_dict() -> Dictionary:
	return carried_materials.duplicate()

func get_carried_runes() -> int:
	var total: int = 0
	for k in carried_runes.keys():
		total += int(carried_runes[k])
	return total

func get_carried_runes_dict() -> Dictionary:
	return carried_runes.duplicate()

## 获取本局携带武器数
func get_carried_weapons() -> int:
	return carried_weapons

## 获取本局携带盾数
func get_carried_shields() -> int:
	return carried_shields

## 撤离失败/死亡结算：
## - 本趟背包内材料与临时战利品全部丢失；
## - 已配置/已装备的手持装备或防具随机损坏一件，但不掉落；
## - 属性、技能、熟练度、酒馆资产与关系成长不变。
func handle_expedition_failure(player_node: Node = null) -> Dictionary:
	var lost_materials := get_carried_materials_dict()
	var lost_runes := get_carried_runes_dict()
	var lost_weapons := carried_weapons
	var lost_shields := carried_shields
	var damaged_item := damage_random_equipped_item(player_node)
	carried_materials.clear()
	carried_runes.clear()
	carried_equipment.clear()
	carried_weapons = 0
	carried_shields = 0
	return {
		"lost_materials": lost_materials,
		"lost_runes": lost_runes,
		"lost_weapons": lost_weapons,
		"lost_shields": lost_shields,
		"damaged_item": damaged_item,
	}

func _sum_inventory(inventory: Dictionary) -> int:
	var total := 0
	for key in inventory.keys():
		total += int(inventory[key])
	return total

func save_equipment_from_player(player_node: Node = null) -> void:
	var target_player := player_node if player_node != null else current_player
	if target_player == null or not is_instance_valid(target_player):
		return
	var equipment = target_player.get("equipment") if "equipment" in target_player else null
	if equipment == null:
		return
	if "active_weapon_slot" in equipment:
		active_weapon_slot = clampi(int(equipment.active_weapon_slot), 0, weapon_slot_ids.size() - 1)
	if "weapon_slots" in equipment:
		var slots: Array = equipment.weapon_slots
		for i in range(weapon_slot_ids.size()):
			var data = slots[i] if i < slots.size() else null
			weapon_slot_ids[i] = String(data.id) if data != null and "id" in data else ""
	if "armor_slots" in equipment:
		var slots_dict: Dictionary = equipment.armor_slots
		for slot_name in armor_slot_ids.keys():
			var armor = slots_dict.get(slot_name, null)
			armor_slot_ids[slot_name] = String(armor.id) if armor != null and "id" in armor else ""

func apply_equipment_to_player(player_node: Node = null) -> void:
	var target_player := player_node if player_node != null else current_player
	if target_player == null or not is_instance_valid(target_player):
		return
	var equipment = target_player.get("equipment") if "equipment" in target_player else null
	if equipment == null:
		return
	for i in range(weapon_slot_ids.size()):
		var weapon_id := String(weapon_slot_ids[i])
		var data := WeaponRegistry.get_weapon_data(weapon_id) if not weapon_id.is_empty() else null
		if equipment.has_method("configure_weapon_slot"):
			equipment.configure_weapon_slot(i, data, false)
	if equipment.has_method("activate_weapon_slot"):
		equipment.activate_weapon_slot(clampi(active_weapon_slot, 0, weapon_slot_ids.size() - 1))
	for slot_name in armor_slot_ids.keys():
		var armor_id := String(armor_slot_ids[slot_name])
		var armor := WeaponRegistry.get_weapon_data(armor_id) if not armor_id.is_empty() else null
		if equipment.has_method("configure_armor_slot"):
			equipment.configure_armor_slot(String(slot_name), armor)

func _has_saved_equipment_loadout() -> bool:
	for equipment_id in weapon_slot_ids:
		if not String(equipment_id).is_empty():
			return true
	for equipment_id in armor_slot_ids.values():
		if not String(equipment_id).is_empty():
			return true
	return false

func damage_random_equipped_item(player_node: Node = null) -> Dictionary:
	var target_player := player_node if player_node != null else current_player
	if target_player == null or not is_instance_valid(target_player):
		return {}
	var equipment = target_player.get("equipment") if "equipment" in target_player else null
	if equipment == null:
		return {}
	var candidates: Array = []
	if "weapon_slots" in equipment:
		var weapon_slots: Array = equipment.weapon_slots
		for i in range(weapon_slots.size()):
			var weapon = weapon_slots[i]
			if weapon != null and "condition" in weapon:
				candidates.append({"kind": "hand", "slot": i, "data": weapon})
	if "armor_slots" in equipment:
		var armor_slots: Dictionary = equipment.armor_slots
		for slot_name in armor_slots.keys():
			var armor = armor_slots[slot_name]
			if armor != null and "condition" in armor:
				candidates.append({"kind": "armor", "slot": String(slot_name), "data": armor})
	if equipment.has_method("has_shield") and equipment.has_shield():
		var shield = equipment.get_active_shield_data() if equipment.has_method("get_active_shield_data") else (equipment.get("shield_data") if "shield_data" in equipment else null)
		if shield != null and "condition" in shield:
			var already_listed := false
			for candidate in candidates:
				if candidate.get("data") == shield:
					already_listed = true
					break
			if not already_listed:
				candidates.append({"kind": "shield", "slot": -1, "data": shield})
	if candidates.is_empty():
		return {}
	var picked: Dictionary = candidates[randi() % candidates.size()]
	var data = picked["data"]
	var max_condition := int(data.get("max_condition")) if "max_condition" in data else int(data.get("condition"))
	var damage := maxi(1, int(ceil(max_condition * EXPEDITION_FAILURE_DAMAGE_FRACTION)))
	if data.has_method("decrease_condition"):
		data.decrease_condition(damage)
	else:
		data.set("condition", 0)
	if equipment.get("is_linked_to_ui") if "is_linked_to_ui" in equipment else false:
		if String(picked["kind"]) == "hand" and int(picked["slot"]) == int(equipment.get("active_weapon_slot")):
			GameEvents.weapon_changed.emit(equipment.get("weapon_data"))
			if equipment.has_method("get_active_shield_data"):
				GameEvents.shield_changed.emit(equipment.get_active_shield_data())
		elif String(picked["kind"]) == "shield":
			GameEvents.shield_changed.emit(equipment.get("shield_data"))
	return {
		"kind": picked["kind"],
		"slot": picked["slot"],
		"name": data.get("name") if "name" in data else "",
		"condition": int(data.get("condition")),
	}
