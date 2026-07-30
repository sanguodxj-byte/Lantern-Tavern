extends GdUnitTestSuite

# 小地图单元测试：验证“探索进度同步”（与大地图一致）的视图变换行为。
# 关键不变量：已探索但远离玩家的格子也应落在绘制窗口内（旧实现因
# 仅取 world_radius 局部窗口而将其排除）。

const MinimapScript := preload("res://scenes/ui/minimap.gd")


func _make_minimap() -> Node:
	var mm = MinimapScript.new()
	# 构造 60x60 网格（全部地面=1），并让网格中心(grid 30,30)≈世界原点
	var grid: Array = []
	for y in range(60):
		var row: Array = []
		for x in range(60):
			row.append(1)
		grid.append(row)
	mm._cached_grid = grid
	mm._grid_offset = Vector3(-90.0, 0, -90.0)   # -(60*3)/2
	mm._grid_tile_size = 3.0
	mm._has_grid = true
	mm._scale = (mm.map_size / 2.0) / mm.world_radius
	return mm


func _make_player() -> Node:
	var p := Node3D.new()
	p.position = Vector3(0, 0, 0)
	p.rotation = Vector3(0, 0, 0)
	return p


func test_minimap_reveals_far_explored_cells() -> void:
	var mm: Node = _make_minimap()
	var player: Node = _make_player()
	mm._player = player

	# 在远离玩家的位置(网格 20..50)标记一整片已探索区域（模拟已走过的走廊）
	for gy in range(20, 51):
		for gx in range(20, 51):
			mm._explored_cells[Vector2i(gx, gy)] = true

	mm._update_view(player.global_position)

	# 旧实现（仅 world_radius 局部窗口）只会覆盖网格 ~20..40；
	# 新实现以已探索区域包围盒为基准，应把远端的 (50,50) 纳入绘制窗口。
	assert_bool(mm._cell_in_draw_window(50, 50)).is_true()
	# 已探索区域中心也应可见
	assert_bool(mm._cell_in_draw_window(35, 35)).is_true()
	# 窗口退化时玩家本身仍在窗口内
	assert_bool(mm._cell_in_draw_window(30, 30)).is_true()
	# 未探索的格子即使落在窗口范围内也不应被绘制
	assert_bool(mm._cell_in_draw_window(18, 18)).is_false()

	mm.free()
	player.free()


func test_minimap_local_fallback_when_nothing_explored() -> void:
	var mm: Node = _make_minimap()
	var player: Node = _make_player()
	mm._player = player
	# 没有任何已探索格子 → 应退化为玩家中心局部视图，且不报错
	mm._update_view(player.global_position)
	assert_float(mm._view_scale).is_equal_approx(mm._scale, 0.001)
	# 遍历窗口应以玩家所在格(网格 30,30)为中心，半径为 ceil(world_radius/3)+1 = 10
	assert_int(mm._view_cgx).is_equal(30)
	assert_int(mm._view_cgy).is_equal(30)
	assert_int(mm._view_cell_r).is_equal(10)

	mm.free()
	player.free()
