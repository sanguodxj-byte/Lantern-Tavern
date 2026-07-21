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
	return {
		"weapon_slots": weapon_slots.duplicate(),
		"armor_slots": armor_slots.duplicate(),
		"active_weapon_slot": active_weapon_slot
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
