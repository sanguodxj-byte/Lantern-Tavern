class_name SpellLoadout
extends RefCounted

const RecipeData := preload("res://globals/combat/spell_recipe_data.gd")
const RuneData := preload("res://globals/combat/rune_data.gd")

signal slot_changed(slot_index: int, spell: Dictionary)

var slot_runes: Array[Array] = []
var rune_inventory: Dictionary = {}
var _inventory_bound: bool = false


func _init() -> void:
	for _slot_index in range(RecipeData.SPELL_SLOT_COUNT):
		slot_runes.append(["", "", ""])


## 注入当前可供法术界面装配的符文库存快照（rune_id -> count）。
## 装配不消耗底层库存，但同一枚实体符文不能同时占用多个符文槽位。
func set_rune_inventory(inventory: Dictionary) -> void:
	_inventory_bound = true
	rune_inventory.clear()
	for raw_id in inventory.keys():
		var rune_id := String(raw_id)
		var count := maxi(0, int(inventory[raw_id]))
		if count > 0 and RuneData.has_rune(rune_id):
			rune_inventory[rune_id] = count
	_reconcile_with_inventory()


func get_remaining_count(rune_id: String) -> int:
	return maxi(0, int(rune_inventory.get(rune_id, 0)) - _equipped_count(rune_id))


func get_available_rune_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id in rune_inventory.keys():
		var rune_id := String(raw_id)
		if int(rune_inventory[raw_id]) > 0:
			result.append(rune_id)
	result.sort()
	return result


func set_rune(slot_index: int, rune_index: int, rune_id: String) -> bool:
	if not _is_valid_slot(slot_index) or rune_index < 0 or rune_index >= RecipeData.RUNES_PER_SPELL:
		return false
	if not rune_id.is_empty() and not RuneData.has_rune(rune_id):
		return false
	# 配方必须从上到下连续，不能在空位之后悬空装配。
	if not rune_id.is_empty() and rune_index > 0 and String(slot_runes[slot_index][rune_index - 1]).is_empty():
		return false
	var previous_id := String(slot_runes[slot_index][rune_index])
	if not rune_id.is_empty() and rune_id != previous_id and _inventory_bound and get_remaining_count(rune_id) <= 0:
		return false
	slot_runes[slot_index][rune_index] = rune_id
	if rune_id.is_empty():
		for clear_index in range(rune_index + 1, RecipeData.RUNES_PER_SPELL):
			slot_runes[slot_index][clear_index] = ""
	slot_changed.emit(slot_index, get_spell(slot_index))
	return true


func clear_slot(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		return false
	slot_runes[slot_index] = ["", "", ""]
	slot_changed.emit(slot_index, {})
	return true


func get_runes(slot_index: int) -> Array[String]:
	if not _is_valid_slot(slot_index):
		return []
	var result: Array[String] = []
	for raw_id in slot_runes[slot_index]:
		result.append(String(raw_id))
	return result


func get_spell(slot_index: int) -> Dictionary:
	if not _is_valid_slot(slot_index):
		return {}
	return RecipeData.resolve(slot_runes[slot_index])


func serialize() -> Dictionary:
	return {"slot_runes": slot_runes.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	var incoming: Array = data.get("slot_runes", [])
	for slot_index in range(mini(incoming.size(), RecipeData.SPELL_SLOT_COUNT)):
		clear_slot(slot_index)
		var rune_ids: Array = incoming[slot_index]
		for rune_index in range(mini(rune_ids.size(), RecipeData.RUNES_PER_SPELL)):
			var rune_id := String(rune_ids[rune_index])
			if rune_id.is_empty():
				break
			if not set_rune(slot_index, rune_index, rune_id):
				break


func _equipped_count(rune_id: String) -> int:
	var count := 0
	for rune_ids in slot_runes:
		for raw_id in rune_ids:
			if String(raw_id) == rune_id:
				count += 1
	return count


func _reconcile_with_inventory() -> void:
	var used: Dictionary = {}
	for slot_index in range(RecipeData.SPELL_SLOT_COUNT):
		for rune_index in range(RecipeData.RUNES_PER_SPELL):
			var rune_id := String(slot_runes[slot_index][rune_index])
			if rune_id.is_empty():
				continue
			var next_count := int(used.get(rune_id, 0)) + 1
			if next_count > int(rune_inventory.get(rune_id, 0)):
				set_rune(slot_index, rune_index, "")
				break
			used[rune_id] = next_count


func _is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < RecipeData.SPELL_SLOT_COUNT
