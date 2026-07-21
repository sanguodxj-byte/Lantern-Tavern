extends GdUnitTestSuite

func before() -> void:
	load("res://scenes/expedition/dungeon_streaming_controller.gd")


# 性能优化回归测试：覆盖地牢物理合批、navmesh 烘焙、光源预算、
# minimap 敌人缓存、enemy_health_bar 节流、combat_log dirty、player collider 去重。

const DUNGEON_SCRIPT := "res://scenes/expedition/procedural_dungeon.gd"
const MINIMAP_SCRIPT := "res://scenes/ui/minimap.gd"
const HEALTH_BAR_SCRIPT := "res://scenes/ui/enemy_health_bar.gd"
const COMBAT_LOG_SCRIPT := "res://scenes/ui/combat_log.gd"
const PLAYER_SCRIPT := "res://scenes/characters/player/player.gd"
const PROJECTILE_SERVICE_SCRIPT := "res://globals/combat/projectile_service.gd"
const PROJECTILE_ENTITY_SCRIPT := "res://scenes/equipment/projectile_entity.gd"


# ── P0-1: 地牢物理合批 ─────────────────────────────────────

func test_dungeon_merges_collisions_into_few_bodies() -> void:
	var script: GDScript = load(DUNGEON_SCRIPT)
	var source := script.source_code
	# 合并碰撞已迁入 DungeonSceneBuilder
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(not builder_src.contains("_spawn_collision(t.origin, Vector3(tile_size, 0.1, tile_size))")) \
		.override_failure_message("地板不应每格调用 _spawn_collision，必须合并") \
		.is_true()
	assert_bool(builder_src.contains("_build_collisions") or builder_src.contains("_build_merged_collision_group")) \
		.override_failure_message("DungeonSceneBuilder 必须实现合并碰撞") \
		.is_true()
	assert_bool(builder_src.contains("ConcavePolygonShape3D")) \
		.override_failure_message("合并碰撞应使用 ConcavePolygonShape3D 而非每格 BoxShape3D") \
		.is_true()
	assert_bool(builder_src.contains("_append_box_faces")) \
		.override_failure_message("合并碰撞应通过 _append_box_faces 累积面片") \
		.is_true()


func test_dungeon_merged_collision_bodies_are_environment_layered() -> void:
	var dungeon := load("res://scenes/expedition/procedural_dungeon.tscn").instantiate() as ProceduralDungeon
	add_child(dungeon)
	await await_idle_frame()

	var merged_body_count := 0
	for child in dungeon.get_children():
		var body := child as StaticBody3D
		if body == null:
			continue
		# 合并 body 名以 Collisions 结尾
		if String(body.name).contains("Collisions"):
			merged_body_count += 1
			assert_int(body.collision_layer).is_equal(PhysicsSetup.LAYER_ENVIRONMENT)
			assert_int(body.collision_mask).is_equal(PhysicsSetup.MASK_ENVIRONMENT)
			# 应仅有一个 CollisionShape3D 子节点（ConcavePolygonShape3D）
			var col_count := 0
			var concave_count := 0
			for sub in body.get_children():
				if sub is CollisionShape3D:
					col_count += 1
					if (sub as CollisionShape3D).shape is ConcavePolygonShape3D:
						concave_count += 1
			assert_int(col_count).is_equal(1)
			assert_int(concave_count).is_equal(1)

	# 42x42 地牢至少应产出地板+天花板各若干 chunk body
	assert_int(merged_body_count) \
		.override_failure_message("地牢应产出至少 2 个合并碰撞 body（地板+天花板），实际 %d" % merged_body_count) \
		.is_greater_equal(2)

	remove_child(dungeon)
	dungeon.free()


# ── P0-2: 导航网格烘焙 ─────────────────────────────────────

func test_dungeon_bakes_navigation_mesh() -> void:
	var script: GDScript = load("res://scenes/expedition/dungeon_scene_builder.gd")
	var source := script.source_code
	assert_bool(source.contains("_build_navigation_mesh")) \
		.override_failure_message("地牢必须实现 _build_navigation_mesh 烘焙导航网格") \
		.is_true()
	assert_bool(source.contains("NavigationRegion3D")) \
		.override_failure_message("地牢必须创建 NavigationRegion3D 供敌人寻路") \
		.is_true()
	# 必须使用 bake_from_source_geometry_data 直接烘焙，而非 parse_source_geometry_data
	# 后者会从 RenderingServer 回传 GPU 几何数据，阻塞渲染管线
	assert_bool(source.contains("NavigationServer3D.bake_from_source_geometry_data")) \
		.override_failure_message("地牢必须用 NavigationServer3D.bake_from_source_geometry_data 直接烘焙 navmesh") \
		.is_true()
	assert_bool(not source.contains("NavigationServer3D.parse_source_geometry_data")) \
		.override_failure_message("不应使用 parse_source_geometry_data，它会触发 GPU → CPU 几何回传") \
		.is_true()
	# 不应创建临时 MeshInstance3D 作为源几何
	assert_bool(not source.contains('_NavSourceGeometry')) \
		.override_failure_message("不应创建临时 _NavSourceGeometry 节点，应直接用 add_faces 注入面片") \
		.is_true()


func test_dungeon_has_navigation_region_after_ready() -> void:
	var dungeon := load("res://scenes/expedition/procedural_dungeon.tscn").instantiate() as ProceduralDungeon
	add_child(dungeon)
	await await_idle_frame()

	var nav_region: NavigationRegion3D = null
	for child in dungeon.get_children():
		if child is NavigationRegion3D:
			nav_region = child as NavigationRegion3D
			break
	assert_object(nav_region) \
		.override_failure_message("地牢 ready 后必须存在 NavigationRegion3D 节点") \
		.is_not_null()
	assert_object(nav_region.navigation_mesh) \
		.override_failure_message("NavigationRegion3D 必须挂载 NavigationMesh") \
		.is_not_null()

	remove_child(dungeon)
	dungeon.free()


# ── P1: 光源预算 ───────────────────────────────────────────

func test_dungeon_light_budget_is_low_for_gl_compat_target() -> void:
	# 28 → 12：低配 gl_compatibility 目标下同时可见局部光源需受控
	assert_int(DungeonStreamingController.DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET) \
		.override_failure_message("GL Compatibility 下局部光源预算应 ≤ 12") \
		.is_less_equal(12)


# ── P1: minimap 敌人缓存 ───────────────────────────────────

func test_minimap_caches_enemies_and_not_scan_per_draw() -> void:
	var script: GDScript = load(MINIMAP_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("_cached_enemies")) \
		.override_failure_message("minimap 必须缓存敌人列表到 _cached_enemies") \
		.is_true()
	assert_bool(source.contains("_refresh_enemy_cache")) \
		.override_failure_message("minimap 必须用 _refresh_enemy_cache 节流刷新敌人缓存") \
		.is_true()
	# _draw_enemies 不应再每帧 get_nodes_in_group
	var draw_section := source.substr(source.find("_draw_enemies"))
	assert_bool(not draw_section.contains("get_nodes_in_group")) \
		.override_failure_message("_draw_enemies 不应每帧调用 get_nodes_in_group，必须读缓存") \
		.is_true()


func test_minimap_refresh_enemy_cache_filters_dead_and_non_enemy() -> void:
	var minimap := CombatMinimap.new()
	add_child(minimap)
	# 清空组内已有敌人，避免历史数据干扰
	for n in get_tree().get_nodes_in_group("enemies"):
		n.remove_from_group("enemies")
	# 非 Enemy 节点入组
	var fake := Node.new()
	fake.add_to_group("enemies")
	add_child(fake)
	# 真实 Enemy 入组
	var enemy := Enemy.new()
	enemy.add_to_group("enemies")
	add_child(enemy)
	minimap._refresh_enemy_cache()
	assert_int(minimap._cached_enemies.size()).is_equal(1)
	assert_object(minimap._cached_enemies[0]).is_equal(enemy)
	fake.queue_free()
	enemy.queue_free()
	minimap.queue_free()


# ── P2: enemy_health_bar 节流 ──────────────────────────────

func test_enemy_health_bar_has_scan_interval_and_dirty_state() -> void:
	var script: GDScript = load(HEALTH_BAR_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("SCAN_INTERVAL")) \
		.override_failure_message("enemy_health_bar 必须定义 SCAN_INTERVAL 节流射线") \
		.is_true()
	assert_bool(source.contains("_scan_timer")) \
		.override_failure_message("enemy_health_bar 必须用 _scan_timer 控制射线频率") \
		.is_true()


func test_enemy_health_bar_no_target_skips_frequent_ray() -> void:
	var bar := EnemyHealthBar.new()
	add_child(bar)
	# 无目标时 _scan_timer 未到，应直接 return 不刷新
	bar._scan_timer = EnemyHealthBar.SCAN_INTERVAL  # 还未衰减
	var before_alpha := bar.modulate.a
	bar._process(0.016)
	# alpha 不变证明没进入淡入分支
	assert_float(bar.modulate.a).is_equal(before_alpha)
	bar.queue_free()


# ── P2: combat_log dirty 驱动重绘 ──────────────────────────

func test_combat_log_uses_dirty_flag_not_per_frame_redraw() -> void:
	var script: GDScript = load(COMBAT_LOG_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("_dirty")) \
		.override_failure_message("combat_log 必须用 _dirty 标志驱动重绘，而非每帧 queue_redraw") \
		.is_true()
	# _process 不应直接无条件 queue_redraw
	var proc_section := source.substr(source.find("func _process"), source.find("\n\nfunc", source.find("func _process")))
	assert_bool(not proc_section.contains("queue_redraw()") or proc_section.contains("if _dirty")) \
		.override_failure_message("_process 中的 queue_redraw 必须受 _dirty 条件保护") \
		.is_true()


func test_combat_log_push_entry_sets_dirty() -> void:
	var log := CombatLog.new()
	add_child(log)
	log._dirty = false
	log.push_entry("test entry", Color.WHITE)
	assert_bool(log._dirty) \
		.override_failure_message("push_entry 必须置 _dirty=true 触发重绘") \
		.is_true()
	log.queue_free()


func test_combat_log_clear_sets_dirty() -> void:
	var log := CombatLog.new()
	add_child(log)
	log._dirty = false
	log.clear()
	assert_bool(log._dirty) \
		.override_failure_message("clear 必须置 _dirty=true 触发重绘") \
		.is_true()
	log.queue_free()


# ── P2: player collider 去重 emit ──────────────────────────

func test_player_caches_last_action_collider() -> void:
	var script: GDScript = load(PLAYER_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("_last_possible_action_collider")) \
		.override_failure_message("player 必须缓存上一次交互 collider 以去重 emit") \
		.is_true()
	assert_bool(source.contains("collider_changed")) \
		.override_failure_message("player 必须用 collider_changed 判断是否变化") \
		.is_true()


func test_player_check_for_possible_action_skips_build_when_collider_unchanged() -> void:
	# 验证逻辑结构：collider_changed 为 false 且非宝箱进度时，应提前返回跳过 tr()/拼接
	var script: GDScript = load(PLAYER_SCRIPT)
	var source := script.source_code
	var func_start := source.find("func check_for_possible_action")
	var func_end := source.find("\n\n## ", func_start)
	var body := source.substr(func_start, func_end - func_start)
	# 必须用 collider_changed 判断是否变化
	assert_bool(body.contains("var collider_changed := current_collider != _last_possible_action_collider")) \
		.override_failure_message("必须用 collider_changed 判断是否变化").is_true()
	# collider 未变且非宝箱进度时必须提前返回，跳过 tr()/拼接
	assert_bool(body.contains("not collider_changed and not chest_in_progress")) \
		.override_failure_message("collider 未变且非宝箱进度时必须提前返回，跳过 tr()/拼接/emit").is_true()
	# 宝箱开启动画进度需每帧重建，必须识别 chest_in_progress
	assert_bool(body.contains("var chest_in_progress := current_collider is Chest and Input.is_action_pressed(\"use\")")) \
		.override_failure_message("宝箱开启动画进度需每帧重建，必须识别 chest_in_progress").is_true()


# ── P1-2: 静态装饰并入 MultiMesh 批处理（铁栅栏）──────────────

func test_batched_decor_includes_iron_bar_grate() -> void:
	var script: GDScript = load(DUNGEON_SCRIPT)
	var source := script.source_code
	# iron_bar_grate 必须纳入批处理集合，10 根铁栏合并为每批 1 个 draw call
	assert_bool(source.contains("\"res://scenes/props/decor/iron_bar_grate.tscn\": true")) \
		.override_failure_message("iron_bar_grate 应并入 BATCHED_DECOR_SCENES 批量渲染").is_true()
	# 批处理只收集 MeshInstance3D，会剥离 Light/Particle/脚本——该场景必须不含这些动态组件
	var grate := load("res://scenes/props/decor/iron_bar_grate.tscn") as PackedScene
	assert_object(grate).is_not_null()
	var grate_inst := grate.instantiate() as Node3D
	add_child(grate_inst)
	var has_light := false
	var has_particle := false
	for c in grate_inst.find_children("*", "Node", true, false):
		if c is Light3D:
			has_light = true
		if c is GPUParticles3D:
			has_particle = true
	assert_bool(has_light).is_false() \
		.override_failure_message("iron_bar_grate 不得含 Light3D，否则批处理会丢失光源").is_false()
	assert_bool(has_particle).is_false() \
		.override_failure_message("iron_bar_grate 不得含 GPUParticles3D，否则批处理会丢失粒子").is_false()
	grate_inst.queue_free()


# ── P1-3: 散落装饰/材料距离剔除（visibility_range）────────────

func test_distance_culling_helper_sets_visibility_range() -> void:
	var script: GDScript = load(DUNGEON_SCRIPT)
	var source := script.source_code
	# 必须提供距离剔除辅助函数与阈值常量
	assert_bool(source.contains("func _apply_distance_culling")) \
		.override_failure_message("地牢必须提供 _apply_distance_culling 距离剔除辅助函数").is_true()
	assert_bool(source.contains("const DECOR_VISIBILITY_RANGE_END")) \
		.override_failure_message("必须定义 DECOR_VISIBILITY_RANGE_END 距离剔除阈值").is_true()
	# 应基于 SELF 淡出模式设置每个 GeometryInstance3D 的 visibility_range_end
	assert_bool(source.contains("visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF")) \
		.override_failure_message("_apply_distance_culling 应使用 SELF 淡出模式").is_true()
	# 单体装饰分支与材料分支都必须调用距离剔除
	assert_bool(source.contains("_apply_distance_culling(instance)")) \
		.override_failure_message("_spawn_random_decor 的单体装饰分支必须应用距离剔除").is_true()
	assert_bool(source.contains("_apply_distance_culling(item)")) \
		.override_failure_message("_spawn_random_material 必须应用距离剔除").is_true()


# ── P0-3: 导航网格直接面片烘焙（无 GPU 回传）────────────────

func test_dungeon_navmesh_uses_add_faces_not_rendering_server() -> void:
	var script: GDScript = load("res://scenes/expedition/dungeon_scene_builder.gd")
	var source := script.source_code
	# 必须使用 add_faces 直接注入面片
	assert_bool(source.contains("add_faces")) \
		.override_failure_message("navmesh 必须用 add_faces 直接注入地板面片，绕过 RenderingServer") \
		.is_true()
	# 必须有 _append_floor_top_face 辅助函数
	assert_bool(source.contains("_append_floor_top_face")) \
		.override_failure_message("必须有 _append_floor_top_face 辅助函数构建可行走面片") \
		.is_true()
	# 必须有障碍面片（墙体）——使用 has_method 兼容检查
	assert_bool(source.contains("add_obstruction_faces")) \
		.override_failure_message("navmesh 必须用 add_obstruction_faces 添加墙体障碍几何（通过 has_method 兼容检查）") \
		.is_true()
	assert_bool(source.contains('has_method("add_obstruction_faces")')) \
		.override_failure_message("add_obstruction_faces 调用前必须有 has_method 兼容检查，因为该方法在部分 Godot 4.x 版本不存在") \
		.is_true()


# ── P1-1: 投射物对象池 ──────────────────────────────────────

func test_projectile_service_has_object_pool() -> void:
	var script: GDScript = load(PROJECTILE_SERVICE_SCRIPT)
	var source := script.source_code
	assert_bool(source.contains("_projectile_pool")) \
		.override_failure_message("ProjectileService 必须有 _projectile_pool 对象池") \
		.is_true()
	assert_bool(source.contains("POOL_MAX_SIZE")) \
		.override_failure_message("ProjectileService 必须定义 POOL_MAX_SIZE 限制池大小") \
		.is_true()
	assert_bool(source.contains("_acquire_projectile")) \
		.override_failure_message("ProjectileService 必须有 _acquire_projectile 从池获取投射物") \
		.is_true()
	assert_bool(source.contains("return_projectile_to_pool")) \
		.override_failure_message("ProjectileService 必须有 return_projectile_to_pool 归还接口") \
		.is_true()
	assert_bool(source.contains("clear_pool")) \
		.override_failure_message("ProjectileService 必须有 clear_pool 清空池（关卡切换时调用）") \
		.is_true()


func test_projectile_service_spawn_uses_pool() -> void:
	var script: GDScript = load(PROJECTILE_SERVICE_SCRIPT)
	var source := script.source_code
	# spawn 函数应调用 _acquire_projectile 而非直接 instantiate
	var spawn_section := source.substr(source.find("func spawn("))
	assert_bool(spawn_section.contains("_acquire_projectile")) \
		.override_failure_message("spawn 必须通过 _acquire_projectile 从对象池获取") \
		.is_true()
	# 不应直接在 spawn 中调用 PROJECTILE_PREFAB.instantiate()
	var spawn_body_end := spawn_section.find("\n\n##")
	var spawn_body := spawn_section.substr(0, spawn_body_end if spawn_body_end > 0 else 500)
	assert_bool(not spawn_body.contains("PROJECTILE_PREFAB.instantiate()")) \
		.override_failure_message("spawn 不应直接调用 PROJECTILE_PREFAB.instantiate()，应由 _acquire_projectile 处理") \
		.is_true()


func test_projectile_entity_returns_to_pool_instead_of_queue_free() -> void:
	var script: GDScript = load(PROJECTILE_ENTITY_SCRIPT)
	var source := script.source_code
	# _destroy_with_impact 应调用 _return_to_pool
	var destroy_section := source.substr(source.find("func _destroy_with_impact"))
	var destroy_end := destroy_section.find("\n\n##")
	var destroy_body := destroy_section.substr(0, destroy_end if destroy_end > 0 else 600)
	assert_bool(destroy_body.contains("_return_to_pool")) \
		.override_failure_message("_destroy_with_impact 应调用 _return_to_pool 而非 queue_free") \
		.is_true()
	assert_bool(not destroy_body.contains("queue_free()")) \
		.override_failure_message("_destroy_with_impact 不应直接调用 queue_free") \
		.is_true()
	# _on_lifetime_expired 也应调用 _return_to_pool
	var lifetime_section := source.substr(source.find("func _on_lifetime_expired"))
	var lifetime_end := lifetime_section.find("\n\n##")
	var lifetime_body := lifetime_section.substr(0, lifetime_end if lifetime_end > 0 else 300)
	assert_bool(lifetime_body.contains("_return_to_pool")) \
		.override_failure_message("_on_lifetime_expired 应调用 _return_to_pool 而非 queue_free") \
		.is_true()


func test_projectile_entity_ready_clears_visual_for_reuse() -> void:
	var script: GDScript = load(PROJECTILE_ENTITY_SCRIPT)
	var source := script.source_code
	# _ready 必须重置状态（对象池复用）
	var ready_section := source.substr(source.find("func _ready"), 800)
	assert_bool(ready_section.contains("_is_destroyed = false")) \
		.override_failure_message("_ready 必须重置 _is_destroyed（对象池复用）") \
		.is_true()
	assert_bool(ready_section.contains("_hit_targets.clear()")) \
		.override_failure_message("_ready 必须清空 _hit_targets（对象池复用）") \
		.is_true()
	assert_bool(ready_section.contains("_clear_visual")) \
		.override_failure_message("_ready 必须调用 _clear_visual 清理旧视觉（对象池复用）") \
		.is_true()
	# 信号连接必须有 is_connected 检查
	assert_bool(ready_section.contains("is_connected")) \
		.override_failure_message("_ready 连接 body_entered 前必须检查 is_connected（对象池复用）") \
		.is_true()


func test_projectile_service_clear_pool_on_level_change() -> void:
	# GameState.register_level 应调用 ProjectileService.clear_pool
	var gs_script: GDScript = load("res://globals/core/game_state.gd")
	var gs_source := gs_script.source_code
	var register_section := gs_source.substr(gs_source.find("func register_level"))
	var register_end := register_section.find("\n\n##")
	var register_body := register_section.substr(0, register_end if register_end > 0 else 300)
	assert_bool(register_body.contains("clear_pool")) \
		.override_failure_message("register_level 必须调用 ProjectileService.clear_pool 清空投射物池") \
		.is_true()


# ── P1-2: 物理串流增量更新 ─────────────────────────────────

func test_dungeon_physics_streaming_uses_incremental_update() -> void:
	var script: GDScript = load(DUNGEON_SCRIPT)
	var source := script.source_code
	# 必须有 _last_active_physics_chunks 增量对比
	assert_bool(source.contains("_last_active_physics_chunks")) \
		.override_failure_message("地牢物理串流必须用 _last_active_physics_chunks 做增量对比") \
		.is_true()
	# streaming 物理更新已迁入 DungeonStreamingController，不应再全量遍历旧 registry
	var ctrl_src := (load("res://scenes/expedition/dungeon_streaming_controller.gd") as GDScript).source_code
	assert_bool(ctrl_src.contains("func update_streaming") or ctrl_src.contains("_physics_chunks")) \
		.override_failure_message("streaming controller 应按 chunk 管理物理体") \
		.is_true()
	assert_bool(not ctrl_src.contains("for body in _streamed_physics_bodies")) \
		.override_failure_message("controller 不应遍历旧 _streamed_physics_bodies 全量列表") \
		.is_true()



# ── P0-4: LightingController 缓存闪烁光源（避免每帧 get_nodes_in_group）──

const LIGHTING_CONTROLLER_SCRIPT := "res://globals/lighting/lighting_controller.gd"

func test_lighting_controller_caches_flicker_lights() -> void:
	var script: GDScript = load(LIGHTING_CONTROLLER_SCRIPT)
	var source := script.source_code
	# 必须有缓存成员变量
	assert_bool(source.contains("_cached_flicker_lights")) \
		.override_failure_message("LightingController 必须缓存闪烁光源到 _cached_flicker_lights") \
		.is_true()
	assert_bool(source.contains("_flicker_cache_dirty")) \
		.override_failure_message("LightingController 必须有 _flicker_cache_dirty 脏标记") \
		.is_true()
	# _process 不应每帧调用 get_nodes_in_group
	var proc_section := source.substr(source.find("func _process"), source.find("\n\n##", source.find("func _process")))
	assert_bool(not proc_section.contains("get_nodes_in_group")) \
		.override_failure_message("_process 不应每帧调用 get_nodes_in_group，应使用缓存") \
		.is_true()
	# 必须有刷新缓存的函数
	assert_bool(source.contains("_refresh_flicker_cache")) \
		.override_failure_message("LightingController 必须有 _refresh_flicker_cache 函数刷新缓存") \
		.is_true()


func test_lighting_controller_invalidate_marks_dirty() -> void:
	var script: GDScript = load(LIGHTING_CONTROLLER_SCRIPT)
	var source := script.source_code
	# 必须有 invalidate_flicker_cache 公共方法
	assert_bool(source.contains("func invalidate_flicker_cache")) \
		.override_failure_message("LightingController 必须有 invalidate_flicker_cache 公共方法") \
		.is_true()


func test_lighting_controller_apply_tavern_profile_marks_dirty() -> void:
	var script: GDScript = load(LIGHTING_CONTROLLER_SCRIPT)
	var source := script.source_code
	# apply_tavern_profile 添加光源后应标记缓存脏
	var profile_section := source.substr(source.find("func apply_tavern_profile"))
	var profile_end := profile_section.find("\n\n##")
	var profile_body := profile_section.substr(0, profile_end if profile_end > 0 else 600)
	assert_bool(profile_body.contains("_flicker_cache_dirty = true")) \
		.override_failure_message("apply_tavern_profile 添加光源后必须标记 _flicker_cache_dirty = true") \
		.is_true()


# ── P0-5: CombatHUD 脏标记驱动刷新 ──────────────────────────

const COMBAT_HUD_SCRIPT := "res://scenes/ui/combat_hud.gd"

func test_combat_hud_uses_dirty_flags() -> void:
	var script: GDScript = load(COMBAT_HUD_SCRIPT)
	var source := script.source_code
	# 必须有脏标记变量
	assert_bool(source.contains("_bars_dirty")) \
		.override_failure_message("CombatHUD 必须有 _bars_dirty 脏标记") \
		.is_true()
	assert_bool(source.contains("_shields_dirty")) \
		.override_failure_message("CombatHUD 必须有 _shields_dirty 脏标记") \
		.is_true()
	assert_bool(source.contains("_buffs_dirty")) \
		.override_failure_message("CombatHUD 必须有 _buffs_dirty 脏标记") \
		.is_true()


func test_combat_hud_process_checks_dirty_before_update() -> void:
	var script: GDScript = load(COMBAT_HUD_SCRIPT)
	var source := script.source_code
	# _process 必须先检测变化，再按脏标记调用更新
	var proc_section := source.substr(source.find("func _process"), source.find("\n\n##", source.find("func _process")))
	assert_bool(proc_section.contains("_check_bars_changed")) \
		.override_failure_message("_process 必须调用 _check_bars_changed 检测血量变化") \
		.is_true()
	assert_bool(proc_section.contains("_check_shields_changed")) \
		.override_failure_message("_process 必须调用 _check_shields_changed 检测护盾变化") \
		.is_true()
	assert_bool(proc_section.contains("_check_buffs_changed")) \
		.override_failure_message("_process 必须调用 _check_buffs_changed 检测 buff 变化") \
		.is_true()
	# 更新函数必须受 if _xxx_dirty 保护
	assert_bool(proc_section.contains("if _bars_dirty")) \
		.override_failure_message("_update_bars 必须受 if _bars_dirty 保护") \
		.is_true()
	assert_bool(proc_section.contains("if _shields_dirty")) \
		.override_failure_message("_update_shields 必须受 if _shields_dirty 保护") \
		.is_true()
	assert_bool(proc_section.contains("if _buffs_dirty")) \
		.override_failure_message("_update_buffs 必须受 if _buffs_dirty 保护") \
		.is_true()


func test_combat_hud_caches_last_hp_values() -> void:
	var script: GDScript = load(COMBAT_HUD_SCRIPT)
	var source := script.source_code
	# 必须缓存上次的 HP/MP 值做对比
	assert_bool(source.contains("_last_hp_current")) \
		.override_failure_message("CombatHUD 必须缓存 _last_hp_current 用于检测血量变化") \
		.is_true()
	assert_bool(source.contains("_last_mp_current")) \
		.override_failure_message("CombatHUD 必须缓存 _last_mp_current 用于检测蓝量变化") \
		.is_true()


# ── P1-3: PixelBar 值未变时跳过重绘 ──────────────────────────

func test_pixel_bar_skips_redundant_set_values() -> void:
	var bar := PixelBar.new()
	bar.show_numeric = false
	add_child(bar)
	# 首次设置
	bar.set_values(70, 100)
	assert_int(bar._current).is_equal(70)
	assert_int(bar._max).is_equal(100)
	# 再次设置相同值——_current/_max 不变（内部提前返回）
	# 验证源码包含值比较
	var script: GDScript = load("res://scenes/ui/pixel_bar.gd")
	var source := script.source_code
	var set_section := source.substr(source.find("func set_values"))
	var set_end := set_section.find("\n\nfunc")
	var set_body := set_section.substr(0, set_end if set_end > 0 else 400)
	assert_bool(set_body.contains("if current == _current and maximum == _max")) \
		.override_failure_message("set_values 必须在值未变时提前返回，跳过格式化与重绘") \
		.is_true()
	bar.queue_free()


# ── P1-4: Crosshair 仅状态变化时重绘 ─────────────────────────

const CROSSHAIR_SCRIPT := "res://scenes/ui/crosshair.gd"

func test_crosshair_redraws_only_on_state_change() -> void:
	var script: GDScript = load(CROSSHAIR_SCRIPT)
	var source := script.source_code
	# 必须有上次绘制状态快照
	assert_bool(source.contains("_last_drawn_targeting")) \
		.override_failure_message("Crosshair 必须缓存 _last_drawn_targeting 用于检测状态变化") \
		.is_true()
	assert_bool(source.contains("_last_drawn_aiming")) \
		.override_failure_message("Crosshair 必须缓存 _last_drawn_aiming 用于检测状态变化") \
		.is_true()
	# _process 中的 queue_redraw 必须受条件保护
	var proc_section := source.substr(source.find("func _process"), source.find("\n\nfunc", source.find("func _process")))
	assert_bool(not proc_section.strip_edges().ends_with("queue_redraw()")) \
		.override_failure_message("_process 不应无条件调用 queue_redraw()") \
		.is_true()
	assert_bool(proc_section.contains("_is_targeting != _last_drawn_targeting")) \
		.override_failure_message("_process 必须比较状态变化后才 queue_redraw") \
		.is_true()


func test_crosshair_no_redraw_when_state_unchanged() -> void:
	var crosshair := Crosshair.new()
	add_child(crosshair)
	# 状态未变化时，_process 不应触发重绘
	# 先跑一次让状态稳定
	crosshair._is_targeting = false
	crosshair._is_aiming = false
	crosshair._last_drawn_targeting = false
	crosshair._last_drawn_aiming = false
	# 手动调用 _process——状态未变，不应改变快照
	crosshair._process(0.016)
	assert_bool(crosshair._last_drawn_targeting).is_false()
	assert_bool(crosshair._last_drawn_aiming).is_false()
	crosshair.queue_free()


# ── P1-5: ProjectileEntity 共享材质缓存 ─────────────────────

func test_projectile_entity_caches_shared_materials() -> void:
	var script: GDScript = load(PROJECTILE_ENTITY_SCRIPT)
	var source := script.source_code
	# 必须有共享材质缓存
	assert_bool(source.contains("_shared_spell_materials")) \
		.override_failure_message("ProjectileEntity 必须有 _shared_spell_materials 共享法术弹材质缓存") \
		.is_true()
	assert_bool(source.contains("_shared_arrow_shaft_materials")) \
		.override_failure_message("ProjectileEntity 必须有 _shared_arrow_shaft_materials 共享箭杆材质缓存") \
		.is_true()
	# 必须有获取共享材质的函数
	assert_bool(source.contains("_get_shared_spell_material")) \
		.override_failure_message("ProjectileEntity 必须有 _get_shared_spell_material 获取共享材质") \
		.is_true()
	assert_bool(source.contains("_get_shared_arrow_shaft_material")) \
		.override_failure_message("ProjectileEntity 必须有 _get_shared_arrow_shaft_material 获取共享材质") \
		.is_true()


func test_projectile_entity_spell_visual_uses_shared_material() -> void:
	var script: GDScript = load(PROJECTILE_ENTITY_SCRIPT)
	var source := script.source_code
	# _build_default_spell_visual 不应每次创建新 StandardMaterial3D
	var spell_section := source.substr(source.find("func _build_default_spell_visual"))
	var spell_end := spell_section.find("\n\n##")
	var spell_body := spell_section.substr(0, spell_end if spell_end > 0 else 600)
	assert_bool(not spell_body.contains("StandardMaterial3D.new()")) \
		.override_failure_message("_build_default_spell_visual 不应每次创建新 StandardMaterial3D，应使用共享材质") \
		.is_true()
	assert_bool(spell_body.contains("_get_shared_spell_material")) \
		.override_failure_message("_build_default_spell_visual 必须使用 _get_shared_spell_material 获取共享材质") \
		.is_true()


func test_projectile_entity_arrow_visual_uses_shared_material() -> void:
	var script: GDScript = load(PROJECTILE_ENTITY_SCRIPT)
	var source := script.source_code
	# _build_default_arrow_visual 不应每次创建新 StandardMaterial3D
	var arrow_section := source.substr(source.find("func _build_default_arrow_visual"))
	var arrow_end := arrow_section.find("\n\n##")
	var arrow_body := arrow_section.substr(0, arrow_end if arrow_end > 0 else 800)
	assert_bool(not arrow_body.contains("StandardMaterial3D.new()")) \
		.override_failure_message("_build_default_arrow_visual 不应每次创建新 StandardMaterial3D，应使用共享材质") \
		.is_true()
	assert_bool(arrow_body.contains("_get_shared_arrow_shaft_material")) \
		.override_failure_message("_build_default_arrow_visual 必须使用 _get_shared_arrow_shaft_material 获取共享材质") \
		.is_true()
	assert_bool(arrow_body.contains("_get_shared_arrow_head_material")) \
		.override_failure_message("_build_default_arrow_visual 必须使用 _get_shared_arrow_head_material 获取共享材质") \
		.is_true()
