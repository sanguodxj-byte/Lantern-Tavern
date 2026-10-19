class_name EquipmentLoadout
extends RefCounted

## 装备配置模块，负责管理手持武器槽、护甲槽以及当前激活武器的索引与序列化。
## 纯数据模型，不依赖任何全局单例、Autoload 或场景树。

const WEAPON_SLOT_COUNT := 4
const VALID_ARMOR_SLOTS := ["head", "body", "hands", "feet"]

var weapon_slots: Array[String] = ["", "", "", ""]
var armor_slots: Dictionary = {
	"head": "",
	"body": "",
	"hands": "",
	"feet": "",
}
var active_weapon_slot: int = 0

## 已装备实例数据（与 weapon_slots 同位）。元素为 WeaponData.to_save_dict() 的字典，
## 或空字典表示无实例数据（回退注册表模板）。防止读档后词缀/耐久/阶位丢失。
var weapon_instances: Array = [{}, {}, {}, {}]
## 已装备护甲实例数据（slot_name -> save dict，空字典表示无实例数据）。
var armor_instances: Dictionary = {
	"head": {},
	"body": {},
	"hands": {},
	"feet": {},
}

func set_weapon_slot(slot: int, equipment_id: String) -> bool:
	if slot < 0 or slot >= WEAPON_SLOT_COUNT:
		return false
	weapon_slots[slot] = equipment_id
	return true

func get_weapon_slot(slot: int) -> String:
	if slot < 0 or slot >= WEAPON_SLOT_COUNT:
		return ""
	return weapon_slots[slot]

func set_armor_slot(slot_name: String, equipment_id: String) -> bool:
	if not slot_name in VALID_ARMOR_SLOTS:
		return false
	armor_slots[slot_name] = equipment_id
	return true

func get_armor_slot(slot_name: String) -> String:
	if not slot_name in VALID_ARMOR_SLOTS:
		return ""
	return armor_slots.get(slot_name, "")

func set_active_weapon_slot(slot: int) -> bool:
	if slot < 0 or slot >= WEAPON_SLOT_COUNT:
		return false
	active_weapon_slot = slot
	return true

func to_dict() -> Dictionary:
	var weapons_out: Array = []
	for inst in weapon_instances:
		weapons_out.append(inst.duplicate() if inst is Dictionary else {})
	var armor_out: Dictionary = {}
	for slot_name in VALID_ARMOR_SLOTS:
		armor_out[slot_name] = armor_instances.get(slot_name, {})
	return {
		"weapon_slots": weapon_slots.duplicate(),
		"armor_slots": armor_slots.duplicate(),
		"active_weapon_slot": active_weapon_slot,
		"weapon_instances": weapons_out,
		"armor_instances": armor_out,
	}

func from_dict(data: Dictionary) -> void:
	if data.has("weapon_slots") and data["weapon_slots"] is Array:
		var arr = data["weapon_slots"]
		for i in range(mini(arr.size(), WEAPON_SLOT_COUNT)):
			weapon_slots[i] = String(arr[i])
	if data.has("armor_slots") and data["armor_slots"] is Dictionary:
		var dict = data["armor_slots"]
		for key in VALID_ARMOR_SLOTS:
			if dict.has(key):
				armor_slots[key] = String(dict[key])
	if data.has("active_weapon_slot") and (data["active_weapon_slot"] is int or data["active_weapon_slot"] is float):
		var slot_val = int(data["active_weapon_slot"])
		if slot_val >= 0 and slot_val < WEAPON_SLOT_COUNT:
			active_weapon_slot = slot_val
	# 实例数据可选（兼容旧存档）。
	if data.has("weapon_instances") and data["weapon_instances"] is Array:
		var w_arr = data["weapon_instances"]
		for i in range(mini(w_arr.size(), WEAPON_SLOT_COUNT)):
			weapon_instances[i] = w_arr[i].duplicate() if w_arr[i] is Dictionary else {}
	if data.has("armor_instances") and data["armor_instances"] is Dictionary:
		var a_dict = data["armor_instances"]
		for key in VALID_ARMOR_SLOTS:
			if a_dict.has(key) and a_dict[key] is Dictionary:
				armor_instances[key] = a_dict[key].duplicate()

## 获取指定武器槽的实例数据（无实例返回空字典）。
func get_weapon_instance(slot: int) -> Dictionary:
	if slot < 0 or slot >= WEAPON_SLOT_COUNT:
		return {}
	var inst = weapon_instances[slot]
	return inst.duplicate() if inst is Dictionary else {}

## 获取指定护甲槽的实例数据（无实例返回空字典）。
func get_armor_instance(slot_name: String) -> Dictionary:
	var inst = armor_instances.get(slot_name, {})
	return inst.duplicate() if inst is Dictionary else {}
