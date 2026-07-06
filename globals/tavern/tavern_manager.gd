extends Node

enum Phase { DAY_EXPEDITION, NIGHT_TAVERN }

const BREWING_DATA := preload("res://globals/tavern/brewing_data.gd")
const WORLD_SCENE_PATH := "res://scenes/world/world.tscn"
const DEFAULT_EXPEDITION_RETURN := {
	"arrival_minutes": 0,
	"deadline_minutes": 18 * 60,
	"missed_tavern": false,
	"voluntary": true,
	"threat_level": 0.0,
	"opened_doors": 0,
	"broken_doors": 0,
}

## 材料数据统一委托给 BrewingData（策划案单一数据源），此处保留只读兼容入口

var current_phase: int = Phase.DAY_EXPEDITION
var day: int = 1
var gold: int = 100
var tutorial_active: bool = false
var tutorial_completed: bool = false
var player_name: String = ""
var save_name: String = ""
var has_confirmed_character_name: bool = false
var last_expedition_return: Dictionary = DEFAULT_EXPEDITION_RETURN.duplicate()
var missed_tavern_income_nights: int = 0
var next_day_expedition_motivation: String = ""

# Inventory of brewing materials collected
var inventory: Dictionary = {}
var runes_inventory: Dictionary = {}

# Alias used by UI scripts
var materials_inventory: Dictionary:
	get:
		return inventory
	set(value):
		inventory = value

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
	inventory[material_id] = int(inventory.get(material_id, 0)) + amount

func _is_known_material(material_id: String) -> bool:
	return BREWING_DATA.MATERIALS_DB.has(material_id)

func start_new_game(with_tutorial: bool = true) -> void:
	day = 1
	gold = 100
	inventory.clear()
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

func remove_from_inventory(material_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var current_amount: int = int(inventory.get(material_id, 0))
	if current_amount >= amount:
		var remaining: int = current_amount - amount
		inventory[material_id] = remaining
		if remaining == 0:
			inventory.erase(material_id)
		return true
	return false

## 酿造逻辑已迁移至 FermentationSystem，此处保留兼容签名
## 调用者应改用 FermentationSystem.start_brewing()

# Extract from dungeon -> go to tavern night phase
func extract_to_tavern(expedition_result: Dictionary = {}):
	print("[TavernManager] Extraction! Day=%d Materials=%d" % [day, inventory.size()])
	record_expedition_return(expedition_result)
	current_phase = Phase.NIGHT_TAVERN
	_go_to_world_space("tavern")

func record_expedition_return(expedition_result: Dictionary) -> void:
	var result := DEFAULT_EXPEDITION_RETURN.duplicate()
	for key in expedition_result.keys():
		result[key] = expedition_result[key]
	last_expedition_return = result
	if bool(result.get("missed_tavern", false)):
		missed_tavern_income_nights += 1
		next_day_expedition_motivation = "这次要控制好时间"
	else:
		next_day_expedition_motivation = ""

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
	var tree := get_tree()
	if tree == null:
		return
	var current := tree.current_scene
	if current != null and current.has_method("load_space"):
		current.call("load_space", space)
		return
	tree.change_scene_to_file(WORLD_SCENE_PATH)
