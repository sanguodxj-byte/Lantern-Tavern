class_name ExpeditionInventory
extends RefCounted

## 探险携带物（背包）库存模块，负责管理探险中材料、符文以及未装备道具的增加、移除、查询及容量控制。
## 纯数据模型，不依赖任何全局单例、Autoload 或场景树。

const MATERIAL_SPACE_PER_ITEM := 1
const RUNE_SPACE_PER_ITEM := 1
const EQUIPMENT_SPACE_PER_ITEM := 1
const DEFAULT_LIMIT := 30

var materials: Dictionary = {} # material_id -> int
var runes: Dictionary = {}     # rune_id -> int
var equipment: Dictionary = {} # equipment_id -> int
## Per-item runtime data.  `equipment` remains the compact id -> count index used by
## existing transfer code; this sidecar prevents rolled affixes and durability from
## being discarded when an item enters the backpack.
var equipment_instances: Dictionary = {} # equipment_id -> Array[WeaponData]

var space_limit: int = DEFAULT_LIMIT

func add_material(material_id: String, amount: int = 1) -> bool:
	if material_id.is_empty() or amount <= 0:
		return false
	if get_space_used() + (amount * MATERIAL_SPACE_PER_ITEM) > space_limit:
		return false
	materials[material_id] = int(materials.get(material_id, 0)) + amount
	return true

func remove_material(material_id: String, amount: int = 1) -> bool:
	if material_id.is_empty() or amount <= 0:
		return false
	var current := int(materials.get(material_id, 0))
	if current < amount:
		return false
	var remaining := current - amount
	if remaining > 0:
		materials[material_id] = remaining
	else:
		materials.erase(material_id)
	return true

func add_rune(rune_id: String, amount: int = 1) -> bool:
	if rune_id.is_empty() or amount <= 0:
		return false
	if get_space_used() + (amount * RUNE_SPACE_PER_ITEM) > space_limit:
		return false
	runes[rune_id] = int(runes.get(rune_id, 0)) + amount
	return true

func remove_rune(rune_id: String, amount: int = 1) -> bool:
	if rune_id.is_empty() or amount <= 0:
		return false
	var current := int(runes.get(rune_id, 0))
	if current < amount:
		return false
	var remaining := current - amount
	if remaining > 0:
		runes[rune_id] = remaining
	else:
		runes.erase(rune_id)
	return true

func add_equipment(equipment_id: String, amount: int = 1) -> bool:
	if equipment_id.is_empty() or amount <= 0:
		return false
	if get_space_used() + (amount * EQUIPMENT_SPACE_PER_ITEM) > space_limit:
		return false
	equipment[equipment_id] = int(equipment.get(equipment_id, 0)) + amount
	return true

func add_equipment_instance(data: WeaponData) -> bool:
	if data == null or data.id.is_empty():
		return false
	if not add_equipment(data.id, 1):
		return false
	var instances: Array = equipment_instances.get(data.id, [])
	instances.append(data.duplicate())
	equipment_instances[data.id] = instances
	return true

func get_equipment_instance(equipment_id: String) -> WeaponData:
	var instances: Array = equipment_instances.get(equipment_id, [])
	return instances[0] as WeaponData if not instances.is_empty() else null

func remove_equipment(equipment_id: String, amount: int = 1) -> bool:
	if equipment_id.is_empty() or amount <= 0:
		return false
	var current := int(equipment.get(equipment_id, 0))
	if current < amount:
		return false
	var remaining := current - amount
	if remaining > 0:
		equipment[equipment_id] = remaining
	else:
		equipment.erase(equipment_id)
	var instances: Array = equipment_instances.get(equipment_id, [])
	for _i in range(mini(amount, instances.size())):
		instances.pop_front()
	if instances.is_empty():
		equipment_instances.erase(equipment_id)
	else:
		equipment_instances[equipment_id] = instances
	return true

func get_space_used() -> int:
	var total: int = 0
	for amt in materials.values():
		total += int(amt) * MATERIAL_SPACE_PER_ITEM
	for amt in runes.values():
		total += int(amt) * RUNE_SPACE_PER_ITEM
	for amt in equipment.values():
		total += int(amt) * EQUIPMENT_SPACE_PER_ITEM
	return total

func get_space_free() -> int:
	return maxi(0, space_limit - get_space_used())

func clear() -> void:
	materials.clear()
	runes.clear()
	equipment.clear()
	equipment_instances.clear()

func to_dict() -> Dictionary:
	return {
		"materials": materials.duplicate(),
		"runes": runes.duplicate(),
		"equipment": equipment.duplicate(),
		"space_limit": space_limit
	}

func from_dict(data: Dictionary) -> void:
	clear()
	if data.has("materials") and data["materials"] is Dictionary:
		materials = data["materials"].duplicate()
	if data.has("runes") and data["runes"] is Dictionary:
		runes = data["runes"].duplicate()
	if data.has("equipment") and data["equipment"] is Dictionary:
		equipment = data["equipment"].duplicate()
	if data.has("space_limit") and (data["space_limit"] is int or data["space_limit"] is float):
		space_limit = int(data["space_limit"])
