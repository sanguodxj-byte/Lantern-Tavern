class_name InventoryTransferService
extends RefCounted

## 库存转移服务（InventoryTransferService）—— 跨库存整堆转移的纯逻辑事务层。
##
## 背景（架构审查 P0-6）：容量常量（MATERIAL_SPACE_PER_ITEM / RUNE_SPACE_PER_ITEM）
## 属于 ExpeditionInventory，但 UI 曾直接引用不存在的 GameState.* 常量，运行时可能
## 触发无效成员访问；容量与回滚规则也散落在 UI 脚本中。
##
## 本服务把「容量校验 + 原子移动 + 失败回滚」收口为单一纯逻辑实现：
## UI 只提交来源、目标和物品列表；不感知容量常量与回滚细节。
## 纯 RefCounted，无场景树依赖，可单测。

## 容量常量（与 ExpeditionInventory 语义一致，单一来源在 ExpeditionInventory，
## 此处仅提供转移事务使用的常量别名，避免 UI 直接引用库存内部常量）。
const MATERIAL_SPACE_PER_ITEM := 1
const RUNE_SPACE_PER_ITEM := 1

## 在两个库存字典间按 id 列表整堆转移（原子事务）。
##
## 语义（相比旧逐条移动的改进）：
##   * 先对全部请求做容量预检；任一物品超出目标容量时【整体回滚】，不产生部分移动，
##     避免 UI 出现「部分成功但无法向用户解释」的中间态。
##   * target_is_carried 为 true 时校验随身容量（经 can_add_carried_stack 回调），
##     否则不校验（仓库/无容量目标直接接受）。
##   * 返回 {item_id: moved_amount}；失败时为空字典，且源/目标字典均未被修改。
##
## 参数：
##   source_inv / target_inv：inventory 字典（Dictionary，直接按引用修改）。
##   item_ids：要整堆转移的物品 id 列表。
##   can_add_carried_stack：可选回调 Callable(amount:int, space_per_item:int) -> bool，
##     用于随身容量判定；为 null 时跳过随身容量校验（纯仓库转移或测试注入）。
static func move_items_between(source_inv: Dictionary, target_inv: Dictionary, item_ids: Array, target_is_carried: bool = false, space_per_item: int = 1, can_add_carried_stack: Callable = Callable()) -> Dictionary:
	var requests: Array[Dictionary] = []
	var total_space := 0
	for raw_id in item_ids:
		var item_id: String = String(raw_id)
		if item_id.is_empty():
			continue
		var amount: int = int(source_inv.get(item_id, 0))
		if amount <= 0:
			continue
		requests.append({"id": item_id, "amount": amount})
		total_space += amount * maxi(space_per_item, 1)
	# 容量预检：任一物品超容量 → 整体失败（无部分移动）。
	if target_is_carried and can_add_carried_stack.is_valid() and not can_add_carried_stack.call(total_space, maxi(space_per_item, 1)):
		return {}
	if requests.is_empty():
		return {}
	# 应用移动（预检通过后不会失败，直接提交）。
	var moved: Dictionary = {}
	for req in requests:
		var item_id := String(req["id"])
		var amount := int(req["amount"])
		target_inv[item_id] = int(target_inv.get(item_id, 0)) + amount
		source_inv.erase(item_id)
		moved[item_id] = amount
	return moved

## 便捷重载：target_is_carried 时按 GameState.can_add_carried_space 判定容量。
## 返回 {item_id: moved_amount}；失败（整体回滚）时为空字典。
static func move_items_between_carried(source_inv: Dictionary, target_inv: Dictionary, item_ids: Array, space_per_item: int = 1, game_state: Node = null) -> Dictionary:
	var capacity: Callable = Callable()
	if game_state != null and game_state.has_method("can_add_carried_space"):
		capacity = func(total_space: int, _per_item: int) -> bool:
			return game_state.can_add_carried_space(total_space)
	return move_items_between(source_inv, target_inv, item_ids, true, space_per_item, capacity)
