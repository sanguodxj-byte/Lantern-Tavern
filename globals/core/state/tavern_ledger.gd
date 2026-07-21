# TavernLedger - 酒馆账目与仓库数据模块
# 职责：独立管理酒馆金币、材料与符文的物理存储，不依赖 SceneTree，方便独立测试。
class_name TavernLedger
extends RefCounted

var gold: int = 100
var materials: Dictionary = {}
var runes: Dictionary = {}

func clear() -> void:
	gold = 100
	materials.clear()
	runes.clear()

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount

func remove_gold(amount: int) -> bool:
	if amount <= 0:
		return false
	if gold < amount:
		return false
	gold -= amount
	return true

func add_material(material_id: String, amount: int = 1) -> bool:
	if material_id.is_empty() or amount <= 0:
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

func to_dict() -> Dictionary:
	return {
		"gold": gold,
		"materials": materials.duplicate(),
		"runes": runes.duplicate()
	}

func from_dict(data: Dictionary) -> void:
	clear()
	if data.has("gold"):
		gold = maxi(0, int(data["gold"]))
	if data.has("materials") and data["materials"] is Dictionary:
		materials = data["materials"].duplicate()
	if data.has("runes") and data["runes"] is Dictionary:
		runes = data["runes"].duplicate()
