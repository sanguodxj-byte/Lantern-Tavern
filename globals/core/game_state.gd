extends Node

const Service := preload("res://globals/core/service.gd")

var current_level : Node3D
var current_player : Player

## 每玩家上下文（联机保险层）。单机下绑定到全局单例；详见 globals/core/player_context.gd。
## 通过 player_context() 惰性获取，避免 autoload 初始化顺序问题。
var _player_context: PlayerContext = null

const DEFAULT_CARRIED_SPACE_LIMIT := 30
const ExpeditionInventoryClass := preload("res://globals/core/state/expedition_inventory.gd")
const EquipmentLoadoutClass := preload("res://globals/core/state/equipment_loadout.gd")

var expedition_inventory := ExpeditionInventoryClass.new()
var equipment_loadout := EquipmentLoadoutClass.new()

var carried_materials: Dictionary:
	get: return expedition_inventory.materials
	set(value): expedition_inventory.materials = value

var carried_runes: Dictionary:
	get: return expedition_inventory.runes
	set(value): expedition_inventory.runes = value

var carried_equipment: Dictionary:
	get: return expedition_inventory.equipment
	set(value): expedition_inventory.equipment = value

var carried_weapons: int = 0             # 探险获得的武器统计
var carried_shields: int = 0             # 探险获得的盾统计

var weapon_slot_ids: Array[String]:
	get: return equipment_loadout.weapon_slots
	set(value): equipment_loadout.weapon_slots = value

var armor_slot_ids: Dictionary:
	get: return equipment_loadout.armor_slots
	set(value): equipment_loadout.armor_slots = value

var active_weapon_slot: int:
	get: return equipment_loadout.active_weapon_slot
	set(value): equipment_loadout.active_weapon_slot = value

const EXPEDITION_FAILURE_DAMAGE_FRACTION := 1.0

var carried_space_limit: int:
	get: return expedition_inventory.space_limit
	set(value): expedition_inventory.space_limit = value

func register_level(level: Node3D) -> void:
	current_level = level
	# 关卡切换时清空投射物对象池，释放上一关残留的投射物
	var ps: Node = Service.projectile_service()
	if ps != null and ps.has_method("clear_pool"):
		ps.clear_pool()

func register_player(player: Player) -> void:
	if player != null and player.has_meta("equipment_preview"):
		return
	current_player = player
	if _player_context != null:
		_player_context.player_node = player
	if _has_saved_equipment_loadout():
		apply_equipment_to_player(player)
	# 不再在 register_player 中调用 save_equipment_from_player。
	# 装备保存应由装备面板 (_apply_equipment_changed) 和拾取逻辑
	# (player_state_picking_up) 显式调用。
	# 否则场景重加载时新 Player 的空装备会覆盖已保存的数据，
	# 导致“开始下一天”后装备丢失。

## 每玩家上下文（联机保险层）。
## 惰性创建并绑定到当前单机全局单例；后续联机改为 per-peer 实例。
func player_context() -> PlayerContext:
	if _player_context == null:
		_player_context = PlayerContext.bind_to_globals(current_player)
	return _player_context

## 记录拾取材料（地牢内实时调用）
func add_carried_material(material_id: String, amount: int = 1) -> bool:
	return expedition_inventory.add_material(material_id, amount)

func add_carried_rune(rune_id: String, amount: int = 1) -> bool:
	return expedition_inventory.add_rune(rune_id, amount)

## 记录未装备的背包装备
func add_carried_equipment(equipment_id: String, amount: int = 1) -> bool:
	return expedition_inventory.add_equipment(equipment_id, amount)

func add_carried_equipment_instance(data: WeaponData) -> bool:
	return expedition_inventory.add_equipment_instance(data)

func get_carried_equipment_instance(equipment_id: String) -> WeaponData:
	return expedition_inventory.get_equipment_instance(equipment_id)

func remove_carried_equipment(equipment_id: String, amount: int = 1) -> bool:
	return expedition_inventory.remove_equipment(equipment_id, amount)

func remove_carried_material(material_id: String, amount: int = 1) -> bool:
	return expedition_inventory.remove_material(material_id, amount)

func remove_carried_rune(rune_id: String, amount: int = 1) -> bool:
	return expedition_inventory.remove_rune(rune_id, amount)

func get_carried_equipment_dict() -> Dictionary:
	return expedition_inventory.equipment.duplicate()

## 记录拾取武器
func add_carried_weapon(equipment_id: String = "") -> bool:
	if not equipment_id.is_empty():
		if not expedition_inventory.add_equipment(equipment_id, 1):
			return false
	carried_weapons += 1
	return true

## 记录拾取盾
func add_carried_shield(equipment_id: String = "") -> bool:
	if not equipment_id.is_empty():
		if not expedition_inventory.add_equipment(equipment_id, 1):
			return false
	carried_shields += 1
	return true

func can_add_carried_space(space: int) -> bool:
	if space <= 0:
		return true
	return expedition_inventory.get_space_used() + space <= expedition_inventory.space_limit

func get_carried_space_used() -> int:
	return expedition_inventory.get_space_used()

func get_carried_space_limit() -> int:
	return expedition_inventory.space_limit

func get_carried_space_free() -> int:
	return expedition_inventory.get_space_free()

## 获取本局携带材料总数
func get_carried_materials() -> int:
	var total: int = 0
	for amt in expedition_inventory.materials.values():
		total += int(amt)
	return total

## 获取本局携带材料字典（material_id → 数量）
func get_carried_materials_dict() -> Dictionary:
	return expedition_inventory.materials.duplicate()

func get_carried_runes() -> int:
	var total: int = 0
	for amt in expedition_inventory.runes.values():
		total += int(amt)
	return total

func clear_carried_state() -> void:
	expedition_inventory.clear()
	carried_weapons = 0
	carried_shields = 0


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
			weapon_slot_ids[i] = _resolve_equipment_id(data)
	if "armor_slots" in equipment:
		var slots_dict: Dictionary = equipment.armor_slots
		for slot_name in armor_slot_ids.keys():
			var armor = slots_dict.get(slot_name, null)
			armor_slot_ids[slot_name] = _resolve_equipment_id(armor)

## 解析装备数据可持久化的 id。
## 优先使用 data.id；对于无 id 的旧版 .tres WeaponData（如酒馆内手放的
## shortsword.tres / axe.tres），按 glb_mesh 资源路径反查 WeaponRegistry，
## 使其也能在场景重载（下一天 / 出发返回）后正确恢复，避免装备丢失。
func _resolve_equipment_id(data) -> String:
	if data == null:
		return ""
	if "id" in data and not String(data.id).is_empty():
		return String(data.id)
	if "glb_mesh" in data and data.glb_mesh != null:
		var resolved := WeaponRegistry.find_id_by_glb(data.glb_mesh)
		if not resolved.is_empty():
			return resolved
	return ""

## 玩家是否已拥有指定 id 的装备（已装备于武器槽或在随身背包中）。
## 供酒馆场景抑制已被拾取的固定摆件（如 PickableShortSword）在场景重载后重复刷新。
func is_weapon_owned(weapon_id: String) -> bool:
	if weapon_id.is_empty():
		return false
	for slot_id in weapon_slot_ids:
		if String(slot_id) == weapon_id:
			return true
	return int(carried_equipment.get(weapon_id, 0)) > 0

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

# ============================================================================
# 存档/读档
# ============================================================================

## 序列化为字典（供 SaveManager 存档）。
func serialize() -> Dictionary:
	return {
		"expedition_inventory": expedition_inventory.to_dict(),
		"equipment_loadout": equipment_loadout.to_dict(),
		"carried_weapons": carried_weapons,
		"carried_shields": carried_shields,
	}

## 从字典恢复
func deserialize(data: Dictionary) -> void:
	if data.has("expedition_inventory") and data["expedition_inventory"] is Dictionary:
		expedition_inventory.from_dict(data["expedition_inventory"])
	else:
		# 兼容老版直接存档字段
		if data.has("carried_materials") and data["carried_materials"] is Dictionary:
			expedition_inventory.materials = (data["carried_materials"] as Dictionary).duplicate()
		if data.has("carried_runes") and data["carried_runes"] is Dictionary:
			expedition_inventory.runes = (data["carried_runes"] as Dictionary).duplicate()
		if data.has("carried_equipment") and data["carried_equipment"] is Dictionary:
			expedition_inventory.equipment = (data["carried_equipment"] as Dictionary).duplicate()
		if data.has("carried_space_limit"):
			expedition_inventory.space_limit = int(data["carried_space_limit"])

	if data.has("equipment_loadout") and data["equipment_loadout"] is Dictionary:
		equipment_loadout.from_dict(data["equipment_loadout"])
	else:
		# 兼容老版直接存档字段
		if data.has("weapon_slot_ids") and data["weapon_slot_ids"] is Array:
			var loaded_slots: Array = data["weapon_slot_ids"]
			var arr: Array[String] = ["", "", "", ""]
			for i in range(mini(loaded_slots.size(), 4)):
				arr[i] = String(loaded_slots[i])
			equipment_loadout.weapon_slots = arr
		if data.has("armor_slot_ids") and data["armor_slot_ids"] is Dictionary:
			var loaded_armor: Dictionary = data["armor_slot_ids"]
			equipment_loadout.armor_slots["head"] = String(loaded_armor.get("head", ""))
			equipment_loadout.armor_slots["body"] = String(loaded_armor.get("body", ""))
			equipment_loadout.armor_slots["hands"] = String(loaded_armor.get("hands", ""))
			equipment_loadout.armor_slots["feet"] = String(loaded_armor.get("feet", ""))
		if data.has("active_weapon_slot"):
			equipment_loadout.active_weapon_slot = clampi(int(data["active_weapon_slot"]), 0, 3)

	if data.has("carried_weapons"):
		carried_weapons = int(data["carried_weapons"])
	if data.has("carried_shields"):
		carried_shields = int(data["carried_shields"])

## 重置为初始状态
func reset_state() -> void:
	expedition_inventory.clear()
	expedition_inventory.space_limit = DEFAULT_CARRIED_SPACE_LIMIT
	carried_weapons = 0
	carried_shields = 0
	equipment_loadout.weapon_slots = ["", "", "", ""]
	equipment_loadout.armor_slots = {"head": "", "body": "", "hands": "", "feet": ""}
	equipment_loadout.active_weapon_slot = 0
