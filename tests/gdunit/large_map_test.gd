extends GdUnitTestSuite

# 大地图（M键）单元测试：LargeMap 类、CombatHUD 集成、小地图数据共享接口

# ── LargeMap 基础功能 ────────────────────────────────────

func test_large_map_exists() -> void:
	var lm := LargeMap.new()
	add_child(lm)
	assert_object(lm).is_not_null()
	lm.queue_free()


func test_large_map_starts_hidden() -> void:
	var lm := LargeMap.new()
	add_child(lm)
	await await_idle_frame()
	assert_bool(lm.visible).is_false()
	lm.queue_free()


func test_large_map_mouse_filter_ignore() -> void:
	var lm := LargeMap.new()
	add_child(lm)
	await await_idle_frame()
	# 不应拦截鼠标输入（游戏继续接收鼠标事件）
	assert_int(lm.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	lm.queue_free()


func test_large_map_show_hide() -> void:
	var lm := LargeMap.new()
	add_child(lm)
	lm.show_map()
	assert_bool(lm.visible).is_true()
	lm.hide_map()
	assert_bool(lm.visible).is_false()
	lm.queue_free()


func test_large_map_toggle() -> void:
	var lm := LargeMap.new()
	add_child(lm)
	assert_bool(lm.visible).is_false()
	lm.toggle()
	assert_bool(lm.visible).is_true()
	lm.toggle()
	assert_bool(lm.visible).is_false()
	lm.queue_free()


func test_large_map_set_minimap() -> void:
	var lm := LargeMap.new()
	add_child(lm)
	var minimap := CombatMinimap.new()
	add_child(minimap)
	lm.set_minimap(minimap)
	assert_object(lm._minimap).is_not_null()
	minimap.queue_free()
	lm.queue_free()


func test_large_map_has_color_constants() -> void:
	var script: GDScript = load("res://scenes/ui/large_map.gd") as GDScript
	var source := script.source_code
	# 复用小地图配色
	assert_bool(source.contains("COL_WALL")).is_true()
	assert_bool(source.contains("COL_FLOOR")).is_true()
	assert_bool(source.contains("COL_ENEMY")).is_true()
	assert_bool(source.contains("COL_PLAYER")).is_true()
	assert_bool(source.contains("COL_FOG_FLOOR")).is_true()
	assert_bool(source.contains("COL_FOG_WALL")).is_true()


func test_large_map_has_fog_logic() -> void:
	var script: GDScript = load("res://scenes/ui/large_map.gd") as GDScript
	var source := script.source_code
	# 大地图应读取小地图的已探索格子
	assert_bool(source.contains("get_explored_cells()")) \
		.override_failure_message("大地图应从小地图读取已探索格子").is_true()
	assert_bool(source.contains("get_explored_collision_cells()")) \
		.override_failure_message("大地图应从小地图读取已探索碰撞体格子").is_true()
	# 未探索格子应跳过
	assert_bool(source.contains("未探索")) \
		.override_failure_message("大地图应跳过未探索格子").is_true()


func test_large_map_draws_grid_and_collision() -> void:
	var script: GDScript = load("res://scenes/ui/large_map.gd") as GDScript
	var source := script.source_code
	# 应有网格地图和碰撞体地图两种绘制路径
	assert_bool(source.contains("_draw_grid_large_map")) \
		.override_failure_message("大地图应有网格地图绘制方法").is_true()
	assert_bool(source.contains("_draw_collision_large_map")) \
		.override_failure_message("大地图应有碰撞体地图绘制方法").is_true()


func test_large_map_player_arrow_rotates_by_yaw() -> void:
	var script: GDScript = load("res://scenes/ui/large_map.gd") as GDScript
	var source := script.source_code
	# 玩家箭头应根据 yaw 旋转
	assert_bool(source.contains("_draw_player_arrow")) \
		.override_failure_message("大地图应有玩家箭头绘制方法").is_true()
	assert_bool(source.contains("sin(yaw)")) \
		.override_failure_message("玩家箭头应使用 sin(yaw) 计算朝向").is_true()
	assert_bool(source.contains("cos(yaw)")) \
		.override_failure_message("玩家箭头应使用 cos(yaw) 计算朝向").is_true()


func test_large_map_reads_fog_vision_radius() -> void:
	var script: GDScript = load("res://scenes/ui/large_map.gd") as GDScript
	var source := script.source_code
	# 大地图应从小地图读取 fog_vision_radius 判断当前可见区域
	assert_bool(source.contains("fog_vision_radius")) \
		.override_failure_message("大地图应读取小地图的 fog_vision_radius").is_true()


func test_large_map_enemies_only_in_fog_vision() -> void:
	var script: GDScript = load("res://scenes/ui/large_map.gd") as GDScript
	var source := script.source_code
	# 敌人应在 fog_vision_radius 范围内才显示
	var enemy_section := source.substr(source.find("func _draw_enemies"))
	assert_bool(enemy_section.contains("fog_r_sq")) \
		.override_failure_message("敌人标记应仅在 fog_vision_radius 范围内显示").is_true()


# ── CombatHUD 集成 ───────────────────────────────────────

func test_combat_hud_has_large_map_node() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	assert_object(hud.large_map).is_not_null()
	assert_bool(hud.large_map is LargeMap).is_true()
	# 默认隐藏
	assert_bool(hud.large_map.visible).is_false()
	hud.queue_free()


func test_combat_hud_binds_minimap_to_large_map() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	# _ready() 应将小地图绑定到大地图
	assert_object(hud.large_map._minimap).is_not_null()
	assert_object(hud.large_map._minimap).is_equal(hud.minimap)
	hud.queue_free()


func test_combat_hud_has_m_key_input() -> void:
	var script: GDScript = load("res://scenes/ui/combat_hud.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("KEY_M")) \
		.override_failure_message("CombatHUD 应处理 M 键切换大地图").is_true()
	assert_bool(source.contains("toggle_large_map()")) \
		.override_failure_message("CombatHUD 应有 toggle_large_map 方法").is_true()


func test_combat_hud_has_escape_to_close() -> void:
	var script: GDScript = load("res://scenes/ui/combat_hud.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("KEY_ESCAPE")) \
		.override_failure_message("CombatHUD 应支持 ESC 关闭大地图").is_true()
	assert_bool(source.contains("is_large_map_visible()")) \
		.override_failure_message("ESC 关闭前应检查大地图是否可见").is_true()


func test_combat_hud_is_large_map_visible() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	# 初始不可见
	assert_bool(hud.is_large_map_visible()).is_false()
	# 显示后可见
	hud.large_map.show_map()
	assert_bool(hud.is_large_map_visible()).is_true()
	# 隐藏后不可见
	hud.large_map.hide_map()
	assert_bool(hud.is_large_map_visible()).is_false()
	hud.queue_free()


func test_combat_hud_toggle_large_map() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	# 初始不可见
	assert_bool(hud.is_large_map_visible()).is_false()
	# 切换后可见
	hud.toggle_large_map()
	assert_bool(hud.is_large_map_visible()).is_true()
	# 再次切换后不可见
	hud.toggle_large_map()
	assert_bool(hud.is_large_map_visible()).is_false()
	hud.queue_free()


func test_combat_hud_large_map_mouse_filter_ignore() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	# 大地图不应拦截鼠标输入
	assert_int(hud.large_map.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	hud.queue_free()


func test_combat_hud_closes_large_map_on_tavern_hud() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	# 打开大地图
	hud.large_map.show_map()
	assert_bool(hud.is_large_map_visible()).is_true()
	# 经营 HUD 打开时应关闭大地图
	hud._on_tavern_hud_visibility_changed(true)
	assert_bool(hud.is_large_map_visible()).is_false()
	hud.queue_free()


# ── 小地图数据共享接口 ───────────────────────────────────

func test_minimap_get_grid_data() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)
	var grid := [
		[0, 0, 2, 0],
		[0, 1, 1, 0],
		[2, 1, 1, 2],
		[0, 1, 1, 0],
	]
	minimap.set_grid_data(grid, Vector3(-6, 0, -6), 3.0)
	var data: Dictionary = minimap.get_grid_data()
	assert_bool(data.has("grid")).is_true()
	assert_bool(data.has("offset")).is_true()
	assert_bool(data.has("tile_size")).is_true()
	assert_bool(data.has("has_grid")).is_true()
	assert_bool(data.has("colliders")).is_true()
	assert_bool(data["has_grid"]).is_true()
	assert_int(data["grid"].size()).is_equal(4)
	minimap.queue_free()


func test_minimap_get_grid_data_empty() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)
	minimap.set_grid_data([], Vector3.ZERO, 3.0)
	var data: Dictionary = minimap.get_grid_data()
	assert_bool(data["has_grid"]).is_false()
	minimap.queue_free()


func test_minimap_get_explored_cells() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)
	minimap.mark_cell_explored(1, 2)
	minimap.mark_cell_explored(3, 4)
	var cells: Dictionary = minimap.get_explored_cells()
	assert_int(cells.size()).is_equal(2)
	assert_bool(cells.has(Vector2i(1, 2))).is_true()
	assert_bool(cells.has(Vector2i(3, 4))).is_true()
	minimap.queue_free()


func test_minimap_get_explored_collision_cells() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)
	# 初始应为空
	var cells: Dictionary = minimap.get_explored_collision_cells()
	assert_int(cells.size()).is_equal(0)
	minimap.queue_free()


func test_minimap_get_cached_enemies() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)
	var enemies: Array[Enemy] = minimap.get_cached_enemies()
	# 初始应为空数组
	assert_int(enemies.size()).is_equal(0)
	minimap.queue_free()


func test_minimap_get_player() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)
	var mock_player := Node3D.new()
	add_child(mock_player)
	minimap.set_player(mock_player)
	assert_object(minimap.get_player()).is_not_null()
	assert_object(minimap.get_player()).is_equal(mock_player)
	mock_player.queue_free()
	minimap.queue_free()
