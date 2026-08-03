extends RefCounted
## 装备面板的库存访问与搬运逻辑（从 tavern_equipment_panel.gd 拆出）。
## 统一封装「随身 (GameState) / 酒馆仓库 (TavernManager)」两套库存的读取与转移，
## 不持有任何 UI 节点；刷新由面板自身负责。

const Service := preload("res://globals/core/service.gd")
const InventoryTransferService := preload("res://globals/core/inventory_transfer_service.gd")

# ── 库存字典访问 ─────────────────────────────────────

static func carried_materials() -> Dictionary:
	var gs: Node = Service.game_state()
	if gs != null and "carried_materials" in gs:
		return gs.carried_materials
	return {}

static func carried_runes() -> Dictionary:
	var gs: Node = Service.game_state()
	if gs != null and "carried_runes" in gs:
		return gs.carried_runes
	return {}

static func carried_equipment() -> Dictionary:
	var gs: Node = Service.game_state()
	if gs != null and "carried_equipment" in gs:
		return gs.carried_equipment
	return {}

static func warehouse_materials() -> Dictionary:
	var tm: Node = Service.tavern_manager()
	if tm != null and "materials_inventory" in tm:
		return tm.materials_inventory
	return {}

static func warehouse_runes() -> Dictionary:
	var tm: Node = Service.tavern_manager()
	if tm != null and "runes_inventory" in tm:
		return tm.runes_inventory
	return {}

static func materials_for_source(source: String) -> Dictionary:
	match source:
		"items":
			return carried_materials()
		"warehouse":
			return warehouse_materials()
	return {}

static func runes_for_source(source: String) -> Dictionary:
	match source:
		"items":
			return carried_runes()
		"warehouse":
			return warehouse_runes()
	return {}

# ── 搬运 ─────────────────────────────────────────────

## 在两个库存字典间按 id 列表整堆转移（委托 InventoryTransferService 原子事务）。
## 随身容量判定经 GameState.can_add_carried_space 回调注入（无 GameState 时跳过容量校验）。
## 返回 {item_id: moved_amount}；容量预检失败时整体回滚，返回空字典。
static func move_items_between(source_inv: Dictionary, target_inv: Dictionary, item_ids: Array, target_is_carried: bool = false, space_per_item: int = 1) -> Dictionary:
	var capacity: Callable = Callable()
	var gs: Node = Service.game_state()
	if gs != null and gs.has_method("can_add_carried_space"):
		capacity = func(total_space: int, _per_item: int) -> bool:
			return gs.can_add_carried_space(total_space)
	return InventoryTransferService.move_items_between(source_inv, target_inv, item_ids, target_is_carried, space_per_item, capacity)

# ── 随身装备/符文操作 ─────────────────────────────────

static func consume_rune(rune_id: String) -> bool:
	for inventory in [carried_runes(), warehouse_runes()]:
		var amount := int(inventory.get(rune_id, 0))
		if amount <= 0:
			continue
		if amount > 1:
			inventory[rune_id] = amount - 1
		else:
			inventory.erase(rune_id)
		return true
	return false

static func consume_carried_equipment(equipment_id: String) -> bool:
	var gs: Node = Service.game_state()
	if gs == null or not gs.has_method("remove_carried_equipment"):
		return false
	return gs.remove_carried_equipment(equipment_id, 1)

static func take_carried_equipment_instance(equipment_id: String) -> WeaponData:
	if equipment_id.is_empty():
		return null
	var gs: Node = Service.game_state()
	if gs == null:
		return null
	var data: WeaponData = null
	if gs.has_method("remove_carried_equipment_instance"):
		data = gs.remove_carried_equipment_instance(equipment_id)
	if data != null:
		return data
	if not gs.has_method("remove_carried_equipment") or not gs.remove_carried_equipment(equipment_id, 1):
		return null
	var registry: Node = Service.weapon_registry()
	return registry.get_weapon_data(equipment_id) if registry != null and registry.has_method("get_weapon_data") else null

static func return_carried_equipment_instance(data: WeaponData) -> bool:
	if data == null:
		return false
	var gs: Node = Service.game_state()
	return gs != null and gs.has_method("add_carried_equipment_instance") and gs.add_carried_equipment_instance(data)

static func return_carried_equipment(equipment_id: String) -> void:
	if equipment_id.is_empty():
		return
	var gs: Node = Service.game_state()
	if gs != null and gs.has_method("add_carried_equipment"):
		gs.add_carried_equipment(equipment_id, 1)

static func can_add_carried_stack(amount: int, space_per_item: int) -> bool:
	var gs: Node = Service.game_state()
	if gs == null or not gs.has_method("can_add_carried_space"):
		return false
	return gs.can_add_carried_space(amount * space_per_item)
