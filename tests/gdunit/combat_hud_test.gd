extends GdUnitTestSuite

# Tests for CombatHUD components: PixelBar, CombatLog, CombatMinimap, EnemyHealthBar

const BuffIconScript := preload("res://scenes/ui/buff_icon.gd")
const ShieldBarScript := preload("res://scenes/ui/shield_bar.gd")

# ── PixelBar ─────────────────────────────────────────────

func test_pixel_bar_set_values() -> void:
	var bar := PixelBar.new()
	bar.show_numeric = false  # 避免 Label 依赖
	add_child(bar)

	bar.set_values(70, 100)
	assert_int(bar._current).is_equal(70)
	assert_int(bar._max).is_equal(100)
	assert_float(bar._display_ratio).is_equal_approx(0.7, 0.001)

	bar.set_values(0, 50)
	assert_int(bar._current).is_equal(0)
	assert_float(bar._display_ratio).is_equal_approx(0.0, 0.001)
	bar.queue_free()


func test_pixel_bar_clamps_negative() -> void:
	var bar := PixelBar.new()
	add_child(bar)

	bar.set_values(-10, 100)
	assert_int(bar._current).is_equal(0)
	assert_int(bar._max).is_equal(100)
	bar.queue_free()


func test_pixel_bar_label_update() -> void:
	var bar := PixelBar.new()
	add_child(bar)

	bar.label_text = "HP"
	bar.set_values(80, 120)
	# Label 存在时应该有文本
	if bar._label:
		assert_str(bar._label.text).contains("80")
		assert_str(bar._label.text).contains("120")
		assert_str(bar._label.text).contains("HP")
	bar.queue_free()


# ── CombatLog ────────────────────────────────────────────

func test_combat_log_push_entry() -> void:
	var log := CombatLog.new()
	add_child(log)

	log.push_entry("测试消息1", Color.RED)
	log.push_entry("测试消息2", Color.GREEN)

	assert_array(log.get_entries()).has_size(2)
	assert_str(log.get_entries()[0]["text"]).is_equal("测试消息1")
	assert_str(log.get_entries()[1]["text"]).is_equal("测试消息2")
	log.queue_free()


func test_combat_log_max_lines_limit() -> void:
	var log := CombatLog.new()
	log.max_lines = 3
	add_child(log)

	for i in range(10):
		log.push_entry("消息 %d" % i)

	assert_array(log.get_entries()).has_size(3)
	assert_str(log.get_entries()[0]["text"]).is_equal("消息 7")
	assert_str(log.get_entries()[2]["text"]).is_equal("消息 9")
	log.queue_free()


func test_combat_log_clear() -> void:
	var log := CombatLog.new()
	add_child(log)

	log.push_entry("消息A")
	log.push_entry("消息B")
	log.clear()

	assert_array(log.get_entries()).has_size(0)
	log.queue_free()


func test_combat_log_empty_text_ignored() -> void:
	var log := CombatLog.new()
	add_child(log)

	log.push_entry("")
	assert_array(log.get_entries()).has_size(0)
	log.queue_free()


# ── CombatMinimap ────────────────────────────────────────

func test_combat_hud_places_time_above_minimap_and_dark_erosion_below() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()

	var minimap := hud.get_node("MinimapContainer/Minimap") as Control
	var time_panel := hud.get_node("MinimapContainer/TimePanel") as Panel
	var erosion_panel := hud.get_node("MinimapContainer/DarkErosionPanel") as Panel

	assert_bool(time_panel.position.y < minimap.position.y) \
		.override_failure_message("时间面板必须位于小地图上方") \
		.is_true()
	assert_bool(erosion_panel.position.y > minimap.position.y) \
		.override_failure_message("暗蚀值面板必须位于小地图下方") \
		.is_true()
	assert_object(hud.time_label.get_theme_font("font")).is_not_null()
	assert_object(hud.dark_erosion_label.get_theme_font("font")).is_not_null()

	hud.queue_free()


func test_combat_hud_updates_time_and_dark_erosion_from_pressure_snapshot() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()

	hud.update_pressure({
		"clock_minutes": 17 * 60 + 35,
		"threat_level": 64.0,
		"pressure_band": "leave_soon",
	})

	assert_str(hud.time_label.text).is_equal("17:35 / 18:00")
	assert_str(hud.dark_erosion_label.text).contains("暗蚀 064%")
	assert_str(hud.dark_erosion_label.text).contains("撤离")

	hud.queue_free()

func test_minimap_set_grid_data() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)

	var grid := [
		[0, 0, 2, 0],
		[0, 1, 1, 0],
		[2, 1, 1, 2],
		[0, 1, 1, 0],
	]
	minimap.set_grid_data(grid, Vector3(-6, 0, -6), 3.0)

	assert_bool(minimap._has_grid).is_true()
	assert_int(minimap._cached_grid.size()).is_equal(4)
	assert_float(minimap._grid_tile_size).is_equal(3.0)
	minimap.queue_free()


func test_minimap_set_grid_data_empty() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)

	minimap.set_grid_data([], Vector3.ZERO, 3.0)
	assert_bool(minimap._has_grid).is_false()
	minimap.queue_free()


func test_minimap_player_reference() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)

	# set_player 应该存储引用
	var mock_player := Node3D.new()
	add_child(mock_player)
	minimap.set_player(mock_player)

	assert_object(minimap._player).is_not_null()
	mock_player.queue_free()
	minimap.queue_free()


# ── CombatMinimap: 旋转多边形绘制（修复网格空隙）──────────

func test_minimap_grid_map_uses_polygon_not_rect() -> void:
	# _draw_grid_map 应使用 draw_colored_polygon 而非 draw_rect 来绘制格子，
	# 消除旋转视角时的网格状空隙
	var script: GDScript = load("res://scenes/ui/minimap.gd") as GDScript
	var source := script.source_code
	# 格子绘制应使用旋转多边形
	assert_bool(source.contains("draw_colored_polygon(screen_pts, color)")) \
		.override_failure_message("网格地图应使用 draw_colored_polygon 绘制旋转多边形，消除旋转空隙").is_true()
	# 不应再使用旧的 draw_rect 绘制网格格子（psz 变量已移除）
	assert_bool(not source.contains("var psz: float = maxf(_grid_tile_size")) \
		.override_failure_message("不应再使用旧的 psz + draw_rect 方式绘制网格格子").is_true()


func test_minimap_grid_map_rotates_four_corners() -> void:
	# 验证旋转逻辑使用四角而非中心点
	var script: GDScript = load("res://scenes/ui/minimap.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("corner_wx")) \
		.override_failure_message("应计算格子四角世界坐标用于旋转多边形绘制").is_true()
	assert_bool(source.contains("for i in range(4):")) \
		.override_failure_message("应遍历四角进行旋转变换").is_true()


# ── CombatMinimap: 迷雾探索 ──────────────────────────────

func test_minimap_has_fog_of_war_properties() -> void:
	var script: GDScript = load("res://scenes/ui/minimap.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("fog_vision_radius")) \
		.override_failure_message("小地图应导出 fog_vision_radius 视野半径").is_true()
	assert_bool(source.contains("_explored_cells")) \
		.override_failure_message("小地图应维护 _explored_cells 已探索格子集合").is_true()
	assert_bool(source.contains("_visible_cells")) \
		.override_failure_message("小地图应维护 _visible_cells 当前可见格子集合").is_true()
	assert_bool(source.contains("COL_FOG_FLOOR")) \
		.override_failure_message("小地图应定义迷雾颜色常量 COL_FOG_FLOOR").is_true()
	assert_bool(source.contains("COL_FOG_WALL")) \
		.override_failure_message("小地图应定义迷雾颜色常量 COL_FOG_WALL").is_true()


func test_minimap_unexplored_cells_not_drawn() -> void:
	# 未探索的格子应被跳过（不绘制）
	var script: GDScript = load("res://scenes/ui/minimap.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("not explored")) \
		.override_failure_message("未探索格子应跳过不绘制").is_true()
	assert_bool(source.contains("continue")) \
		.override_failure_message("未探索格子应 continue 跳过").is_true()


func test_minimap_explored_not_visible_uses_fog_color() -> void:
	# 已探索但当前不可见的格子应使用迷雾色
	var script: GDScript = load("res://scenes/ui/minimap.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("COL_FOG_FLOOR if cell_type != 2 else COL_FOG_WALL")) \
		.override_failure_message("已探索但不可见的格子应使用迷雾色").is_true()


func test_minimap_reset_fog_clears_state() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)
	# 手动标记一些格子
	minimap.mark_cell_explored(1, 2)
	minimap.mark_cell_explored(3, 4)
	assert_int(minimap.get_explored_count()).is_equal(2)
	# 重置后应为空
	minimap.reset_fog()
	assert_int(minimap.get_explored_count()).is_equal(0)
	minimap.queue_free()


func test_minimap_mark_cell_explored() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)
	minimap.mark_cell_explored(5, 6)
	assert_bool(minimap._explored_cells.has(Vector2i(5, 6))) \
		.override_failure_message("mark_cell_explored 应将格子标记到 _explored_cells").is_true()
	minimap.queue_free()


func test_minimap_fog_vision_radius_default() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)
	assert_float(minimap.fog_vision_radius) \
		.override_failure_message("默认迷雾视野半径应为 12m").is_equal(12.0)
	minimap.queue_free()


func test_minimap_enemies_only_visible_in_fog_vision() -> void:
	# 敌人应在 fog_vision_radius 范围内才显示（而非 world_radius）
	var script: GDScript = load("res://scenes/ui/minimap.gd") as GDScript
	var source := script.source_code
	# _draw_enemies 中应使用 fog_vision_radius 而非 world_radius
	var enemy_section := source.substr(source.find("func _draw_enemies"))
	var section_end := enemy_section.find("func _draw_player_arrow")
	enemy_section = enemy_section.substr(0, section_end)
	assert_bool(enemy_section.contains("fog_vision_radius * fog_vision_radius")) \
		.override_failure_message("敌人标记应仅在 fog_vision_radius 范围内显示（迷雾中不显示敌人）").is_true()


func test_minimap_refresh_references_resets_fog_on_level_change() -> void:
	# 关卡切换时应重置迷雾
	var script: GDScript = load("res://scenes/ui/minimap.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("reset_fog()")) \
		.override_failure_message("_refresh_references 应在关卡失效时调用 reset_fog()").is_true()


# ── EnemyHealthBar ───────────────────────────────────────

func test_enemy_health_bar_set_target() -> void:
	var bar := EnemyHealthBar.new()
	add_child(bar)

	# 创建一个 Enemy 但不入树（避免 _ready 需要 %PlayerDetectionArea 等子节点）
	var enemy := Enemy.new()
	bar.set_target(enemy)

	assert_object(bar._target_enemy).is_not_null()
	enemy.free()
	bar.queue_free()


func test_enemy_health_bar_hp_color_high() -> void:
	var bar := EnemyHealthBar.new()
	add_child(bar)

	var color := bar._hp_color(0.8)
	# 高血量应该是绿色调
	assert_float(color.g).is_greater(color.r)
	bar.queue_free()


func test_enemy_health_bar_hp_color_low() -> void:
	var bar := EnemyHealthBar.new()
	add_child(bar)

	var color := bar._hp_color(0.1)
	# 低血量应该是红色调
	assert_float(color.r).is_greater(color.g)
	bar.queue_free()


# ── EnemyHealthBar: 持续追踪 & 视角离开自动隐藏 ──────────

func test_enemy_health_bar_raycast_uses_collision_mask() -> void:
	# 射线检测应设置碰撞掩码，排除材料/投掷物
	var script: GDScript = load("res://scenes/ui/enemy_health_bar.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("query.collision_mask")) \
		.override_failure_message("射线检测应设置 collision_mask").is_true()
	assert_bool(source.contains("LAYER_ENEMY | PhysicsSetup.LAYER_ENVIRONMENT | PhysicsSetup.LAYER_SCENE_OBJECT")) \
		.override_failure_message("碰撞掩码应仅含敌人+环境+场景物体，排除材料/投掷物").is_true()


func test_enemy_health_bar_continuously_tracks_target() -> void:
	# 有目标时仍应定期重新射线检测（不应只检测一次就锁定）
	var script: GDScript = load("res://scenes/ui/enemy_health_bar.gd") as GDScript
	var source := script.source_code
	# "有目标"分支中应包含重新射线检测逻辑
	assert_bool(source.contains("hit_enemy != _target_enemy")) \
		.override_failure_message("有目标时应重新射线检测并验证是否仍注视同一敌人").is_true()
	assert_bool(source.contains("_visible_timer <= 0.0")) \
		.override_failure_message("目标丢失后应通过 timer 超时清除目标").is_true()


func test_enemy_health_bar_enemy_name_uses_metadata() -> void:
	# _enemy_name 应优先使用 enemy_base_type metadata
	var script: GDScript = load("res://scenes/ui/enemy_health_bar.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("enemy_base_type")) \
		.override_failure_message("_enemy_name 应优先使用 enemy_base_type metadata").is_true()
	assert_bool(source.contains('match base_type:')) \
		.override_failure_message("_enemy_name 应使用 match 语句匹配 base_type metadata").is_true()


func test_enemy_health_bar_enemy_name_handles_at_suffix() -> void:
	# 节点名回退应处理 @后缀（如 @Goblin@123）
	var script: GDScript = load("res://scenes/ui/enemy_health_bar.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains('n.find("@")')) \
		.override_failure_message("节点名回退应去除 @后缀").is_true()


func test_enemy_health_bar_enemy_name_has_zombie() -> void:
	# 应包含 zombie 名称映射
	var script: GDScript = load("res://scenes/ui/enemy_health_bar.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains('"zombie"')) \
		.override_failure_message("_enemy_name 应包含 zombie 名称映射").is_true()


func test_enemy_health_bar_name_from_metadata() -> void:
	# 行为验证：通过 metadata 获取正确名称
	var bar := EnemyHealthBar.new()
	add_child(bar)
	var enemy := Enemy.new()
	enemy.set_meta("enemy_base_type", "goblin")
	var name := bar._enemy_name(enemy)
	assert_str(name).is_equal(tr("哥布林"))
	enemy.free()
	bar.queue_free()


func test_enemy_health_bar_name_from_metadata_dragon() -> void:
	var bar := EnemyHealthBar.new()
	add_child(bar)
	var enemy := Enemy.new()
	enemy.set_meta("enemy_base_type", "dragon")
	var name := bar._enemy_name(enemy)
	assert_str(name).is_equal(tr("巨龙"))
	enemy.free()
	bar.queue_free()


func test_enemy_health_bar_name_from_metadata_zombie() -> void:
	var bar := EnemyHealthBar.new()
	add_child(bar)
	var enemy := Enemy.new()
	enemy.set_meta("enemy_base_type", "zombie")
	var name := bar._enemy_name(enemy)
	assert_str(name).is_equal(tr("僵尸"))
	enemy.free()
	bar.queue_free()


func test_enemy_health_bar_name_fallback_node_name() -> void:
	# 无 metadata 时回退到节点名
	var bar := EnemyHealthBar.new()
	add_child(bar)
	var enemy := Enemy.new()
	enemy.name = "Skeleton"
	var name := bar._enemy_name(enemy)
	assert_str(name).is_equal(tr("骷髅兵"))
	enemy.free()
	bar.queue_free()


func test_enemy_health_bar_name_fallback_at_suffix() -> void:
	# 节点名带 @后缀时仍能正确匹配
	var bar := EnemyHealthBar.new()
	add_child(bar)
	var enemy := Enemy.new()
	enemy.name = "@Troll@123"
	var name := bar._enemy_name(enemy)
	assert_str(name).is_equal(tr("巨魔"))
	enemy.free()
	bar.queue_free()


func test_enemy_health_bar_name_unknown_fallback() -> void:
	var bar := EnemyHealthBar.new()
	add_child(bar)
	var enemy := Enemy.new()
	enemy.name = "MysteryCreature"
	var name := bar._enemy_name(enemy)
	assert_str(name).is_equal(tr("未知敌人"))
	enemy.free()
	bar.queue_free()


# ── BuffIcon ─────────────────────────────────────────────

func test_buff_icon_blink_threshold_constant() -> void:
	# BLINK_THRESHOLD 必须为 3.0（用户需求：剩 3 秒开始闪烁）
	assert_float(BuffIconScript.BLINK_THRESHOLD).is_equal(3.0)


func test_buff_icon_is_blinking_when_under_threshold() -> void:
	var icon: Node = BuffIconScript.new()
	add_child(icon)
	icon.setup("def_and_evade_up", 2.0)
	assert_bool(icon.is_blinking()).is_true()
	icon.queue_free()


func test_buff_icon_not_blinking_when_above_threshold() -> void:
	var icon: Node = BuffIconScript.new()
	add_child(icon)
	icon.setup("def_and_evade_up", 5.0)
	assert_bool(icon.is_blinking()).is_false()
	icon.queue_free()


func test_buff_icon_blink_alpha_changes() -> void:
	var icon: Node = BuffIconScript.new()
	add_child(icon)
	icon.setup("def_and_evade_up", 2.0)
	# 初始 alpha 应为 1.0
	assert_float(icon.modulate.a).is_equal(1.0)
	# 模拟一帧 process
	icon._process(0.1)
	# 闪烁后 alpha 应在 (0.25, 1.0) 之间变化
	assert_float(icon.modulate.a).is_greater_equal(0.25)
	assert_float(icon.modulate.a).is_less_equal(1.0)
	icon.queue_free()


func test_buff_icon_not_blinking_keeps_full_alpha() -> void:
	var icon: Node = BuffIconScript.new()
	add_child(icon)
	icon.setup("def_and_evade_up", 5.0)
	icon._process(0.1)
	assert_float(icon.modulate.a).is_equal(1.0)
	icon.queue_free()


# ── CombatHUD Buff Container ─────────────────────────────

func test_combat_hud_has_buff_container() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	assert_object(hud.buff_container).is_not_null()
	assert_bool(hud.buff_container is HBoxContainer).is_true()
	hud.queue_free()


func test_combat_hud_hp_bar_is_enlarged() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	# HP 条宽度应 >= 260（旧值 200）
	assert_float(hud.hp_bar.size.x).is_greater_equal(260.0)
	# HP 条高度应 >= 32（旧值 28）
	assert_float(hud.hp_bar.size.y).is_greater_equal(32.0)
	hud.queue_free()


func test_combat_hud_pixel_bar_uses_readable_type_and_texture() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	var bar := hud.get_node("BottomLeft/HPBar") as PixelBar
	assert_float(bar.custom_minimum_size.x).is_greater_equal(320.0)
	assert_float(bar.custom_minimum_size.y).is_greater_equal(36.0)
	assert_int(bar.get_node("Label").get_theme_font_size("font_size")).is_greater_equal(18)
	hud.queue_free()


func test_combat_hud_mp_bar_is_enlarged() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	assert_float(hud.mp_bar.size.x).is_greater_equal(260.0)
	assert_float(hud.mp_bar.size.y).is_greater_equal(32.0)
	hud.queue_free()


func test_combat_hud_buff_container_is_above_bars() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	# buff 容器应在 HP 条上方
	assert_float(hud.buff_container.position.y).is_less(hud.hp_bar.position.y)
	hud.queue_free()


# ── ShieldBar ────────────────────────────────────────────

func test_shield_bar_set_values_activates() -> void:
	var bar: Node = ShieldBarScript.new()
	add_child(bar)
	bar.shield_type = 0  # MAGIC
	bar.set_values(30, 100)
	assert_bool(bar.is_active()).is_true()
	assert_int(bar._current).is_equal(30)
	assert_int(bar._max).is_equal(100)
	assert_float(bar._display_ratio).is_equal_approx(0.3, 0.001)
	bar.queue_free()


func test_shield_bar_deactivate() -> void:
	var bar: Node = ShieldBarScript.new()
	add_child(bar)
	bar.set_values(50, 100)
	bar.deactivate()
	assert_bool(bar.is_active()).is_false()
	assert_int(bar._current).is_equal(0)
	assert_float(bar._display_ratio).is_equal(0.0)
	bar.queue_free()


func test_shield_bar_zero_current_not_active() -> void:
	var bar: Node = ShieldBarScript.new()
	add_child(bar)
	bar.set_values(0, 100)
	# current == 0 时不应该激活
	assert_bool(bar.is_active()).is_false()
	bar.queue_free()


func test_shield_bar_fade_in_on_activate() -> void:
	var bar: Node = ShieldBarScript.new()
	add_child(bar)
	# 初始 fade 应为 0
	assert_float(bar.get_fade_progress()).is_equal(0.0)
	bar.set_values(50, 100)
	# 模拟几帧 process 来渐入
	bar._process(0.1)
	assert_float(bar.get_fade_progress()).is_greater(0.0)
	bar._process(0.2)
	# 0.3 秒后应完全显示（FADE_DURATION=0.25）
	assert_float(bar.get_fade_progress()).is_equal_approx(1.0, 0.01)
	bar.queue_free()


func test_shield_bar_fade_out_on_deactivate() -> void:
	var bar: Node = ShieldBarScript.new()
	add_child(bar)
	bar.set_values(50, 100)
	bar._process(0.25)  # 完全渐入
	assert_float(bar.get_fade_progress()).is_equal_approx(1.0, 0.01)
	bar.deactivate()
	bar._process(0.25)  # 完全渐出
	assert_float(bar.get_fade_progress()).is_equal_approx(0.0, 0.01)
	bar.queue_free()


func test_shield_bar_magic_color_is_blue() -> void:
	var bar: Node = ShieldBarScript.new()
	add_child(bar)
	bar.shield_type = 0  # MAGIC
	bar._ready()
	# 法术护盾颜色应为蓝色调（b > r）
	assert_float(bar._bar_color.b).is_greater(bar._bar_color.r)
	bar.queue_free()


func test_shield_bar_physical_color_is_gray() -> void:
	var bar: Node = ShieldBarScript.new()
	add_child(bar)
	bar.shield_type = 1  # PHYSICAL
	bar._ready()
	# 物理护盾颜色应为灰白色（r ≈ g ≈ b，且亮度较高）
	var c: Color = bar._bar_color
	assert_float(c.r).is_equal_approx(c.g, 0.05)
	assert_float(c.g).is_equal_approx(c.b, 0.05)
	assert_float(c.r).is_greater(0.5)
	bar.queue_free()


# ── CombatHUD Shield Integration ─────────────────────────

func test_combat_hud_has_magic_shield_bar() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	assert_object(hud.magic_shield_bar).is_not_null()
	hud.queue_free()


func test_combat_hud_has_physical_shield_bar() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	assert_object(hud.physical_shield_bar).is_not_null()
	hud.queue_free()


func test_combat_hud_shield_bars_above_hp_bar() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	# 护盾条应在 HP 条上方
	assert_float(hud.magic_shield_bar.position.y).is_less(hud.hp_bar.position.y)
	assert_float(hud.physical_shield_bar.position.y).is_less(hud.hp_bar.position.y)
	hud.queue_free()


func test_combat_hud_shield_bars_below_buff_container() -> void:
	var hud: CombatHUD = load("res://scenes/ui/combat_hud.tscn").instantiate()
	add_child(hud)
	await await_idle_frame()
	# 护盾条的原始布局位置 _base_y 应在 buff 容器底部之下
	assert_float(hud.magic_shield_bar._base_y).is_greater_equal(hud.buff_container.offset_bottom)
	hud.queue_free()
