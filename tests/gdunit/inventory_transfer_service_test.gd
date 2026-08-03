extends GdUnitTestSuite

## InventoryTransferService 单元测试：
## 覆盖容量常量正确来源、原子移动、容量预检失败整体回滚、空 id 跳过等事务语义。

const ITS := preload("res://globals/core/inventory_transfer_service.gd")
const ExpeditionInventory := preload("res://globals/core/state/expedition_inventory.gd")

func _source(dict: Dictionary) -> Dictionary:
	return dict.duplicate(true)

func test_space_constants_match_expedition_inventory() -> void:
	# 容量常量的语义来源是 ExpeditionInventory，UI 不得再引用不存在的 GameState.* 常量。
	assert_int(ITS.MATERIAL_SPACE_PER_ITEM).is_equal(ExpeditionInventory.MATERIAL_SPACE_PER_ITEM)
	assert_int(ITS.RUNE_SPACE_PER_ITEM).is_equal(ExpeditionInventory.RUNE_SPACE_PER_ITEM)

func test_moves_whole_stack_between_inventories() -> void:
	var src := _source({"iron": 3, "wood": 2})
	var dst := _source({"iron": 1})
	var moved: Dictionary = ITS.move_items_between(src, dst, ["iron", "wood"], false, 1)
	assert_dict(moved).contains_key_value("iron", 3)
	assert_dict(moved).contains_key_value("wood", 2)
	# 源整堆移除
	assert_int(int(src.get("iron", 0))).is_equal(0)
	assert_bool(not src.has("iron")).is_true()
	# 目标叠加
	assert_int(int(dst.get("iron", 0))).is_equal(4)

func test_unknown_or_empty_ids_are_skipped() -> void:
	var src := _source({"iron": 3})
	var dst := _source({})
	var moved: Dictionary = ITS.move_items_between(src, dst, ["iron", "ghost_item", ""], false, 1)
	assert_dict(moved).contains_key_value("iron", 3)
	assert_bool(not moved.has("ghost_item")).is_true()

func test_capacity_precheck_failure_rolls_back_whole_batch() -> void:
	# 容量只够 2 格，但请求 3 格（iron 3 + wood 2 = 5 格 > 2 格）→ 整体回滚，不得部分移动。
	var src := _source({"iron": 3, "wood": 2})
	var dst := _source({})
	var moved: Dictionary = ITS.move_items_between(src, dst, ["iron", "wood"], true, 1,
		func(total_space: int, _per_item: int) -> bool:
			return total_space <= 2)
	assert_dict(moved).is_empty()
	assert_dict(src).contains_key_value("iron", 3)
	assert_dict(src).contains_key_value("wood", 2)
	assert_bool(dst.is_empty())

func test_capacity_ok_commits_full_batch() -> void:
	var src := _source({"iron": 1, "wood": 1})
	var dst := _source({})
	var moved: Dictionary = ITS.move_items_between(src, dst, ["iron", "wood"], true, 1,
		func(total_space: int, _per_item: int) -> bool:
			return total_space <= 2)
	assert_dict(moved).has_size(2)
	assert_int(int(dst.get("iron", 0))).is_equal(1)
	assert_int(int(dst.get("wood", 0))).is_equal(1)

func test_space_per_item_scales_capacity_requirement() -> void:
	var src := _source({"iron": 3})
	var dst := _source({})
	# 每件占 2 格：3 件 = 6 格 > 5 格 → 拒绝
	var moved: Dictionary = ITS.move_items_between(src, dst, ["iron"], true, 2,
		func(total_space: int, _per_item: int) -> bool:
			return total_space <= 5)
	assert_dict(moved).is_empty()
	assert_dict(src).contains_key_value("iron", 3)

func test_non_carried_transfer_skips_capacity_check() -> void:
	# target_is_carried=false：不调用容量回调（仓库间转移不校验随身空间）。
	var src := _source({"iron": 50})
	var dst := _source({})
	var called := [false]
	var moved: Dictionary = ITS.move_items_between(src, dst, ["iron"], false, 1,
		func(total_space: int, _per_item: int) -> bool:
			called[0] = true
			return false)
	assert_dict(moved).contains_key_value("iron", 50)
	assert_bool(called[0]).is_false()
