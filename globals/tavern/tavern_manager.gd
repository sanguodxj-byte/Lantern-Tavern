extends Node

enum Phase { DAY_EXPEDITION, NIGHT_TAVERN }

const BREWING_DATA := preload("res://globals/tavern/brewing_data.gd")
const Service := preload("res://globals/core/service.gd")
const WORLD_SCENE_PATH := "res://scenes/world/world.tscn"
const DEFAULT_EXPEDITION_RETURN := {
	"arrival_minutes": 0,
	"deadline_minutes": 18 * 60,
	"missed_tavern": false,
	"voluntary": true,
	"threat_level": 0.0,
	"dark_erosion": 0.0,
	"opened_doors": 0,
	"broken_doors": 0,
}

## 材料数据统一委托给 BrewingData（策划案单一数据源），此处保留只读兼容入口

var current_phase: int = Phase.DAY_EXPEDITION
var day: int = 1
const TavernLedgerClass := preload("res://globals/core/state/tavern_ledger.gd")
var tavern_ledger := TavernLedgerClass.new()

var gold: int:
	get: return tavern_ledger.gold
	set(value): tavern_ledger.gold = value

var tutorial_active: bool = false
var tutorial_completed: bool = false
var player_name: String = ""
var save_name: String = ""
var has_confirmed_character_name: bool = false
var last_expedition_return: Dictionary = DEFAULT_EXPEDITION_RETURN.duplicate()
var missed_tavern_income_nights: int = 0
var next_day_expedition_motivation: String = ""

var inventory: Dictionary:
	get: return tavern_ledger.materials
	set(value): tavern_ledger.materials = value

var runes_inventory: Dictionary:
	get: return tavern_ledger.runes
	set(value): tavern_ledger.runes = value

# Alias used by UI scripts
var materials_inventory: Dictionary:
	get: return inventory
	set(value): inventory = value

# Active brews waiting for sale (brewed previous night, available tonight)
var current_brews: Array = []

## 兼容属性：委托给 BrewingData.MATERIALS_DB（策划案单一数据源）
var materials_db: Dictionary:
	get:
		return BREWING_DATA.MATERIALS_DB

## 兼容属性：委托给 BrewingData.RECIPES_DB（策划案单一数据源）
var brewing_recipes: Dictionary:
	get:
		return BREWING_DATA.RECIPES_DB

func add_material(material_id: String, amount: int = 1):
	if amount <= 0:
		return
	if not _is_known_material(material_id):
		return
	tavern_ledger.add_material(material_id, amount)

func _is_known_material(material_id: String) -> bool:
	return BREWING_DATA.MATERIALS_DB.has(material_id)

func start_new_game(with_tutorial: bool = true) -> void:
	day = 1
	tavern_ledger.clear()
	current_brews.clear()
	tutorial_active = with_tutorial
	tutorial_completed = not with_tutorial
	player_name = ""
	save_name = ""
	has_confirmed_character_name = false
	last_expedition_return = DEFAULT_EXPEDITION_RETURN.duplicate()
	missed_tavern_income_nights = 0
	next_day_expedition_motivation = ""
	current_phase = Phase.DAY_EXPEDITION if with_tutorial else Phase.NIGHT_TAVERN
	_go_to_world_space("intro" if with_tutorial else "tavern")

func complete_intro_and_enter_tavern() -> void:
	tutorial_active = false
	tutorial_completed = true
	current_phase = Phase.NIGHT_TAVERN
	_go_to_world_space("tavern")

func confirm_player_name(name_text: String) -> void:
	var trimmed := name_text.strip_edges()
	if trimmed.is_empty():
		return
	player_name = trimmed
	save_name = trimmed
	has_confirmed_character_name = true

func continue_in_tavern() -> void:
	current_phase = Phase.NIGHT_TAVERN
	_go_to_world_space("tavern")

## 记录本局地牢撤离携带物品统计（供 procedural_dungeon._settle_extraction_loot 调用）
func record_expedition_loot(materials_count: int, weapons_count: int, shields_count: int) -> void:
	print("[TavernManager] Expedition loot recorded: %d materials, %d weapons, %d shields" % [materials_count, weapons_count, shields_count])
	var gs := _get_game_state()
	if gs != null:
		# 将随身背包装备、材料、符文归入酒馆仓库，并清空随身背包
		for mat_id in gs.carried_materials.keys():
			tavern_ledger.add_material(mat_id, int(gs.carried_materials[mat_id]))
		for rune_id in gs.carried_runes.keys():
			tavern_ledger.add_rune(rune_id, int(gs.carried_runes[rune_id]))
		gs.clear_carried_state()

func remove_from_inventory(material_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	return tavern_ledger.remove_material(material_id, amount)

## 酿造逻辑已迁移至 FermentationSystem，此处保留兼容签名
## 调用者应改用 FermentationSystem.start_brewing()

# Extract from dungeon -> go to tavern night phase
func extract_to_tavern(expedition_result: Dictionary = {}):
	var gs := _get_game_state()
	var mat_count: int = gs.get_carried_materials() if gs != null and gs.has_method("get_carried_materials") else 0
	print("[TavernManager] Extraction! Day=%d Materials=%d" % [day, mat_count])
	record_expedition_return(expedition_result)
	current_phase = Phase.NIGHT_TAVERN
	_go_to_world_space("tavern")

func record_expedition_return(expedition_result: Dictionary) -> void:
	var result := DEFAULT_EXPEDITION_RETURN.duplicate()
	for key in expedition_result.keys():
		result[key] = expedition_result[key]
	if bool(result.get("missed_tavern", false)):
		missed_tavern_income_nights += 1
		next_day_expedition_motivation = "这次要控制好时间"
	else:
		next_day_expedition_motivation = ""
	_clear_return_dark_erosion(result)
	last_expedition_return = result

func _clear_return_dark_erosion(result: Dictionary) -> void:
	result["threat_level"] = 0.0
	result["dark_erosion"] = 0.0

func _get_game_state() -> Node:
	return Service.game_state()

func did_miss_last_tavern_income() -> bool:
	return bool(last_expedition_return.get("missed_tavern", false))

# Next day: switch to day phase, stay in tavern for departure preparation
func start_next_day():
	day += 1
	current_phase = Phase.DAY_EXPEDITION
	# Clear tonight's brews (they were sold)
	current_brews.clear()
	# 保持在酒馆场景，切换到白天探险阶段；玩家通过出发键(T)触发区域选择→地牢
	_go_to_world_space("tavern")

func start_expedition() -> void:
	current_phase = Phase.DAY_EXPEDITION
	_go_to_world_space("dungeon")

func _go_to_world_space(space: String) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var current := tree.current_scene
	if current != null and current.has_method("load_space"):
		current.call("load_space", space)
		return
	tree.change_scene_to_file(WORLD_SCENE_PATH)

# ============================================================================
# 存档/读档
# ============================================================================

## 序列化为字典（供 SaveManager 存档）
## inventory / runes_inventory 已委托给 GameState，不再在此序列化（避免重复）。
func serialize() -> Dictionary:
	return {
		"day": day,
		"tavern_ledger": tavern_ledger.to_dict(),
		"current_phase": current_phase,
		"tutorial_active": tutorial_active,
		"tutorial_completed": tutorial_completed,
		"player_name": player_name,
		"save_name": save_name,
		"has_confirmed_character_name": has_confirmed_character_name,
		"current_brews": current_brews.duplicate(true),
		"last_expedition_return": last_expedition_return.duplicate(true),
		"missed_tavern_income_nights": missed_tavern_income_nights,
		"next_day_expedition_motivation": next_day_expedition_motivation,
	}

## 从字典恢复
func deserialize(data: Dictionary) -> void:
	if data.has("day"):
		day = int(data["day"])
	if data.has("current_phase"):
		current_phase = int(data["current_phase"])
	if data.has("tutorial_active"):
		tutorial_active = bool(data["tutorial_active"])
	if data.has("tutorial_completed"):
		tutorial_completed = bool(data["tutorial_completed"])
	if data.has("player_name"):
		player_name = String(data["player_name"])
	if data.has("save_name"):
		save_name = String(data["save_name"])
	if data.has("has_confirmed_character_name"):
		has_confirmed_character_name = bool(data["has_confirmed_character_name"])
	
	if data.has("tavern_ledger") and data["tavern_ledger"] is Dictionary:
		tavern_ledger.from_dict(data["tavern_ledger"])
	else:
		# 兼容老版直接存档字段
		if data.has("gold"):
			gold = int(data["gold"])
		if data.has("inventory") and data["inventory"] is Dictionary:
			var old_inv: Dictionary = data["inventory"]
			for mat_id in old_inv.keys():
				tavern_ledger.add_material(mat_id, int(old_inv[mat_id]))
		if data.has("runes_inventory") and data["runes_inventory"] is Dictionary:
			var old_runes: Dictionary = data["runes_inventory"]
			for rune_id in old_runes.keys():
				tavern_ledger.add_rune(rune_id, int(old_runes[rune_id]))
			
	if data.has("current_brews"):
		current_brews = (data["current_brews"] as Array).duplicate(true)
	if data.has("last_expedition_return"):
		last_expedition_return = (data["last_expedition_return"] as Dictionary).duplicate(true)
	if data.has("missed_tavern_income_nights"):
		missed_tavern_income_nights = int(data["missed_tavern_income_nights"])
	if data.has("next_day_expedition_motivation"):
		next_day_expedition_motivation = String(data["next_day_expedition_motivation"])

## 重置为初始状态（不含场景切换）
func reset_state() -> void:
	day = 1
	tavern_ledger.clear()
	current_phase = Phase.DAY_EXPEDITION
	tutorial_active = false
	tutorial_completed = false
	player_name = ""
	save_name = ""
	has_confirmed_character_name = false
	current_brews.clear()
	last_expedition_return = DEFAULT_EXPEDITION_RETURN.duplicate()
	missed_tavern_income_nights = 0
	next_day_expedition_motivation = ""
