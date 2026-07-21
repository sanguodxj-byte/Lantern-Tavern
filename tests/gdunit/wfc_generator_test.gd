extends GdUnitTestSuite

# Test suite for WFC_RoomGenerator (12 templates)

var _wfc: WFC_RoomGenerator

func before_test() -> void:
	_wfc = load("res://scenes/expedition/wfc_generator.gd").new()


func after_test() -> void:
	if is_instance_valid(_wfc):
		_wfc.free()
	_wfc = null


# ─── Legacy regression tests ──────────────────────────────────────────────────

func test_collapse_room_returns_configured_grid() -> void:
	var map1 = _wfc.collapse_room()
	assert_int(map1.size()).is_equal(10)
	for row in map1:
		assert_int(row.size()).is_equal(10)

	var map2 = _wfc.collapse_room(15, 20)
	assert_int(map2.size()).is_equal(20)
	for row in map2:
		assert_int(row.size()).is_equal(15)


func test_border_tiles_are_wall_or_empty_dynamic() -> void:
	var width := 12
	var height := 16
	var map = _wfc.collapse_room(width, height)
	for y in range(height):
		for x in range(width):
			if x == 0 or x == width - 1 or y == 0 or y == height - 1:
				var val = map[y][x]
				var valid = val == 2 or val == 0
				assert_bool(valid) \
					.override_failure_message("Border tile at (%d, %d) has invalid type: %d" % [x, y, val]) \
					.is_true()


func test_collapse_completes_in_reasonable_time() -> void:
	var start_time = Time.get_ticks_msec()
	_wfc.collapse_room(30, 30)
	var elapsed = Time.get_ticks_msec() - start_time
	assert_int(elapsed).is_less(5000)


func test_floor_never_on_border_dynamic() -> void:
	var width := 14
	var height := 14
	var map = _wfc.collapse_room(width, height)
	for y in range(height):
		for x in range(width):
			if x == 0 or x == width - 1 or y == 0 or y == height - 1:
				assert_int(map[y][x]) \
					.override_failure_message("Floor tile at border (%d, %d)" % [x, y]) \
					.is_not_equal(1)


# ─── Template pin-verification tests ─────────────────────────────────────────

## TreasureCorner: 四角固定物正确出现
func test_treasure_corner_pins() -> void:
	var w := 8; var h := 8
	var t = WFC_RoomGenerator._make_treasure_corner(w, h)
	var map = _wfc.collapse_room(w, h, t)
	assert_int(map[1][1]).is_equal(WFC_RoomGenerator.TileType.LOOT)
	assert_int(map[1][w - 2]).is_equal(WFC_RoomGenerator.TileType.LOOT)
	assert_int(map[h - 2][1]).is_equal(WFC_RoomGenerator.TileType.RESOURCE)
	assert_int(map[h - 2][w - 2]).is_equal(WFC_RoomGenerator.TileType.RESOURCE)


## PillarHall: 四个对称石柱位置正确
func test_pillar_hall_pins() -> void:
	var w := 9; var h := 9
	var t = WFC_RoomGenerator._make_pillar_hall(w, h)
	var map = _wfc.collapse_room(w, h, t)
	var pillar := WFC_RoomGenerator.TileType.PILLAR
	assert_int(map[h / 3][w / 3]).is_equal(pillar)
	assert_int(map[h / 3][2 * w / 3]).is_equal(pillar)
	assert_int(map[2 * h / 3][w / 3]).is_equal(pillar)
	assert_int(map[2 * h / 3][2 * w / 3]).is_equal(pillar)


## AltarRoom: 中央宝箱固定
func test_altar_room_center_loot() -> void:
	var w := 9; var h := 9
	var t = WFC_RoomGenerator._make_altar_room(w, h)
	var map = _wfc.collapse_room(w, h, t)
	assert_int(map[h / 2][w / 2]).is_equal(WFC_RoomGenerator.TileType.LOOT)


## RingHall: 中央宝箱固定
func test_ring_hall_center_loot() -> void:
	var w := 8; var h := 8
	var t = WFC_RoomGenerator._make_ring_hall(w, h)
	var map = _wfc.collapse_room(w, h, t)
	assert_int(map[h / 2][w / 2]).is_equal(WFC_RoomGenerator.TileType.LOOT)


## ResourceDepot: 左下宝箱固定
func test_resource_depot_loot_pin() -> void:
	var w := 8; var h := 8
	var t = WFC_RoomGenerator._make_resource_depot(w, h)
	var map = _wfc.collapse_room(w, h, t)
	assert_int(map[h - 2][1]).is_equal(WFC_RoomGenerator.TileType.LOOT)


## LabyrinthCell: 右上宝箱固定（尺寸足够时）
func test_labyrinth_cell_loot_pin() -> void:
	var w := 8; var h := 8
	var t = WFC_RoomGenerator._make_labyrinth_cell(w, h)
	var map = _wfc.collapse_room(w, h, t)
	assert_int(map[1][w - 2]).is_equal(WFC_RoomGenerator.TileType.LOOT)


## Crypt: 走道两端宝箱固定（尺寸足够时）
func test_crypt_loot_pins() -> void:
	var w := 10; var h := 7
	var t = WFC_RoomGenerator._make_crypt(w, h)
	var map = _wfc.collapse_room(w, h, t)
	assert_int(map[h / 2][1]).is_equal(WFC_RoomGenerator.TileType.LOOT)
	assert_int(map[h / 2][w - 2]).is_equal(WFC_RoomGenerator.TileType.LOOT)


## CheckerHall: 中央宝箱固定（尺寸足够时）
func test_checkerboard_center_loot() -> void:
	var w := 9; var h := 9
	var t = WFC_RoomGenerator._make_checkerboard(w, h)
	var map = _wfc.collapse_room(w, h, t)
	assert_int(map[h / 2][w / 2]).is_equal(WFC_RoomGenerator.TileType.LOOT)


## FortressVault: 中央宝箱固定（尺寸足够时）
func test_fortress_vault_center_loot() -> void:
	var w := 9; var h := 9
	var t = WFC_RoomGenerator._make_fortress_vault(w, h)
	var map = _wfc.collapse_room(w, h, t)
	assert_int(map[h / 2][w / 2]).is_equal(WFC_RoomGenerator.TileType.LOOT)


# ─── Post-processing validator tests ──────────────────────────────────────────

## BFS 连通性：正确区分连通/孤岛情况
func test_connectivity_check() -> void:
	var F = WFC_RoomGenerator.TileType.FLOOR
	var W = WFC_RoomGenerator.TileType.WALL

	# 完全连通的 5×5
	var connected_grid := [
		[W, W, W, W, W],
		[W, F, F, F, W],
		[W, F, F, F, W],
		[W, F, F, F, W],
		[W, W, W, W, W],
	]
	assert_bool(_wfc.check_connectivity(connected_grid)).is_true()

	# 被竖墙一分为二的孤岛
	var disconnected_grid := [
		[W, W, W, W, W, W, W],
		[W, F, F, W, F, F, W],
		[W, F, F, W, F, F, W],
		[W, F, F, W, F, F, W],
		[W, W, W, W, W, W, W],
	]
	assert_bool(_wfc.check_connectivity(disconnected_grid)).is_false()

	# 全墙：无可走格子 → false
	var all_walls := [[W, W, W], [W, W, W], [W, W, W]]
	assert_bool(_wfc.check_connectivity(all_walls)).is_false()


## 密度校验：宝物比例 ≤ 15%
func test_density_check() -> void:
	var F = WFC_RoomGenerator.TileType.FLOOR
	var W = WFC_RoomGenerator.TileType.WALL
	var L = WFC_RoomGenerator.TileType.LOOT
	var R = WFC_RoomGenerator.TileType.RESOURCE

	# 1/9 ≈ 11%，通过
	var ok_grid := [
		[W, W, W, W, W],
		[W, L, F, F, W],
		[W, F, F, F, W],
		[W, F, F, F, W],
		[W, W, W, W, W],
	]
	assert_bool(_wfc.check_density(ok_grid)).is_true()

	# 9/9 = 100%，不通过
	var overflow_grid := [
		[W, W, W, W, W],
		[W, L, L, L, W],
		[W, L, L, L, W],
		[W, L, L, L, W],
		[W, W, W, W, W],
	]
	assert_bool(_wfc.check_density(overflow_grid)).is_false()


## 重试与降级：极端尺寸下不崩溃，最终结果通过验证
func test_wfc_retry_and_fallback() -> void:
	var map = _wfc.collapse_room(3, 3)
	assert_int(map.size()).is_equal(3)
	for row in map:
		assert_int(row.size()).is_equal(3)
	assert_bool(_wfc.validate_grid(map)).is_true()


# ─── Template pool / get_template_for_size ────────────────────────────────────

## 所有12个模板静态工厂函数都能成功构造并包含合法布局
func test_all_template_factories_build_valid_layouts() -> void:
	var w := 10; var h := 10
	var templates: Array = [
		WFC_RoomGenerator._make_empty_chamber(w, h),
		WFC_RoomGenerator._make_pillar_hall(w, h),
		WFC_RoomGenerator._make_treasure_corner(w, h),
		WFC_RoomGenerator._make_divided_arena(w, h),
		WFC_RoomGenerator._make_altar_room(w, h),
		WFC_RoomGenerator._make_resource_depot(w, h),
		WFC_RoomGenerator._make_twin_treasure(w, h),
		WFC_RoomGenerator._make_fortress_vault(w, h),
		WFC_RoomGenerator._make_labyrinth_cell(w, h),
		WFC_RoomGenerator._make_ring_hall(w, h),
		WFC_RoomGenerator._make_checkerboard(w, h),
		WFC_RoomGenerator._make_crypt(w, h),
	]
	assert_int(templates.size()).is_equal(12)
	for t in templates:
		assert_object(t).is_not_null()
		assert_int(t.layout.size()).is_equal(h)
		for row in t.layout:
			assert_int(row.size()).is_equal(w)


## get_template_for_size 在大尺寸下能选出全部12种
func test_get_template_for_size_selects_from_full_pool() -> void:
	var seen_names: Dictionary = {}
	# 多次采样，验证不同模板都会出现
	for _i in range(200):
		var t = _wfc.get_template_for_size(10, 10)
		seen_names[t.name] = true
	# 10×10 尺寸下全部 12 种模板均可被选中
	assert_int(seen_names.size()).is_equal(12)
