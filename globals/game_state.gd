extends Node

var current_keys : Dictionary[Door.KeyColor, bool] = {}
var current_level : Node3D
var current_player : Player

# 本局地牢携带物品统计（进入地牢时重置，撤离时结算）
var carried_materials: Dictionary = {}  # material_id → 数量
var carried_weapons: int = 0             # 本局获得的武器数
var carried_shields: int = 0             # 本局获得的盾数

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
	# 进入新关卡时重置携带统计
	carried_materials.clear()
	carried_weapons = 0
	carried_shields = 0

func register_player(player: Player) -> void:
	current_player = player

## 记录拾取材料（地牢内实时调用）
func add_carried_material(material_id: String, amount: int = 1) -> void:
	carried_materials[material_id] = int(carried_materials.get(material_id, 0)) + amount

## 记录拾取武器
func add_carried_weapon() -> void:
	carried_weapons += 1

## 记录拾取盾
func add_carried_shield() -> void:
	carried_shields += 1

## 获取本局携带材料总数
func get_carried_materials() -> int:
	var total: int = 0
	for k in carried_materials.keys():
		total += int(carried_materials[k])
	return total

## 获取本局携带材料字典（material_id → 数量）
func get_carried_materials_dict() -> Dictionary:
	return carried_materials.duplicate()

## 获取本局携带武器数
func get_carried_weapons() -> int:
	return carried_weapons

## 获取本局携带盾数
func get_carried_shields() -> int:
	return carried_shields
