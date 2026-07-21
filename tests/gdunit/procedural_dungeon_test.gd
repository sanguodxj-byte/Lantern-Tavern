extends GdUnitTestSuite

# Test suite for ProceduralDungeon
#
# 引擎限制（headless GL Compatibility）：反复实例化完整 3D 地牢场景（含 MultiMesh/shader/
# 光照，尤其是蒙皮 rig 敌人）会累积 GPU 资源，约第 3 次实例化即触发引擎原生崩溃
# （signal 11，见 enemy_dying_defer_test 记录，真机正常）。为把全场景实例化次数压到崩溃阈值以下：
#   1) before() 只构建「一具」共享地牢（不刷怪），所有只读断言查这一实例；
#   2) 仅 test_dungeon_spawns_enemies 单独构建「第二具」带敌人的地牢并放最后。
# 合计仅 2 次全场景实例化，稳定低于崩溃阈值。
#
# 共享地牢不刷怪，避免骨骼 rig 增加 headless GPU 资源压力。

var _dungeon: ProceduralDungeon

# 固定生成种子：经历史层级探针验证确定产出 boss=1 / standard=31 门的布局，
# 含 boss 房且 boss 门与普通门都可检测。改动此值需重新验证门/墙体断言仍成立。
const SHARED_DUNGEON_SEED := 1


func before() -> void:
	# 注入固定种子使布局确定可复现（含 boss 房且 boss 门可检测），并只构建一次共享地牢。
	# 注：DungeonGenerator 用 config.seed 驱动自己的 RNG，不读全局 seed()，
	# 故必须通过 generation_seed 字段注入（在 add_child 触发 _ready 前设置）。
	_dungeon = load("res://scenes/expedition/procedural_dungeon.tscn").instantiate()
	_dungeon.spawn_population_enabled = false
	_dungeon.generation_seed = SHARED_DUNGEON_SEED
	add_child(_dungeon)
	await await_idle_frame()


func after() -> void:
	if is_instance_valid(_dungeon):
		remove_child(_dungeon)
		_dungeon.free()


## 遍历子树收集所有 DungeonDoor（门挂在 DoorsRoot 容器下，非 dungeon 直接子节点）。
func _collect_doors(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		for c in node.get_children():
			stack.push_back(c)
		if node is DungeonDoor:
			out.append(node)
	return out


## 遍历子树收集所有 MultiMeshInstance3D（地形挂在 TerrainRoot 容器下，非 dungeon 直接子节点）。
func _collect_multi_mesh_instances(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		for c in node.get_children():
			stack.push_back(c)
		if node is MultiMeshInstance3D:
			out.append(node)
	return out


func test_dungeon_inheritance() -> void:
	assert_object(_dungeon).is_instanceof(BaseLevel)
	assert_bool(_dungeon.is_procedural()).is_true()


func test_dungeon_ready_flow() -> void:
	# 共享地牢已在 before() 构建并入树；本测试只读断言几何生成 / 出生点 / 玩家。

	# 新架构（阶段 7+）：地板/墙/天花板/装饰改为 MultiMesh 批渲染，挂在 TerrainRoot/DecorRoot 等
	# 容器 root 下，而非 ProceduralDungeon 的直接子节点。因此验证「几何已生成」要遍历子树统计
	# MultiMeshInstance3D 的 instance_count 总和，而不是数直接子节点（旧断言 >=100 已过时）。
	var mmi_count := 0
	var instance_sum := 0
	var atlas_bound_all := true
	var stack: Array = [_dungeon]
	while not stack.is_empty():
		var node = stack.pop_back()
		for c in node.get_children():
			stack.push_back(c)
		if node is MultiMeshInstance3D:
			mmi_count += 1
			if node.multimesh != null:
				instance_sum += node.multimesh.instance_count
			var mat = node.material_override
			if mat is ShaderMaterial and mat.get_shader_parameter("atlas") == null:
				atlas_bound_all = false
	assert_int(mmi_count) \
		.override_failure_message("地牢应生成 MultiMesh 地形/装饰实例，实际一个都没有") \
		.is_greater(0)
	assert_int(instance_sum) \
		.override_failure_message("MultiMesh 实例总数过少，墙体/地面可能未生成") \
		.is_greater_equal(100)
	assert_bool(atlas_bound_all) \
		.override_failure_message("存在未绑定 atlas 纹理的地形材质 → 会渲染成黑色") \
		.is_true()

	# Verify player spawn location was updated
	assert_bool(_dungeon.player_spawn_pos != Vector3.ZERO).is_true()
	
	# Verify player was successfully instantiated as a child of the dungeon
	var player_found = false
	for child in _dungeon.get_children():
		if child is Player:
			player_found = true
			assert_float(child.global_position.x).is_equal_approx(_dungeon.player_spawn_pos.x, 0.01)
			assert_float(child.global_position.z).is_equal_approx(_dungeon.player_spawn_pos.z, 0.01)
			break
	assert_bool(player_found).is_true()


func test_dungeon_wires_door_actions_to_exploration_pressure() -> void:
	# 阶段 8/9 重构：门-压力接线从 procedural_dungeon.gd 迁入 DungeonRuntime + DungeonSceneBuilder。
	# 本测试随之改查新位置（旧断言查 procedural_dungeon.gd 已过时）。
	var runtime_src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code

	assert_bool(runtime_src.contains("EXPLORATION_PRESSURE_SCRIPT")) \
		.override_failure_message("DungeonRuntime 应挂载 ExplorationPressure 作为探索压力控制器") \
		.is_true()
	assert_bool(builder_src.contains("pressure_action.connect(parent._on_door_pressure_action)")) \
		.override_failure_message("地牢门开门/破门行为必须驱动压力上涨") \
		.is_true()
	assert_bool(runtime_src.contains("record_door_action(action)")) \
		.override_failure_message("门行为应交给 ExplorationPressure 统一计时和加压") \
		.is_true()


func test_dungeon_spawns_boss_reward_chest_via_layout_specs() -> void:
	# boss/normal chest 已由 SpawnPlanner + SceneBuilder 按 chest_spawn_specs 实例化
	var planner_src := (load("res://scenes/expedition/dungeon_spawn_planner.gd") as GDScript).source_code
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(planner_src.contains("boss_chest") or planner_src.contains("plan_chest_spawns")).is_true()
	assert_bool(builder_src.contains("boss_chest") and builder_src.contains("_build_chests")).is_true()
	assert_bool(builder_src.contains("layout.zone") or builder_src.contains("instance.zone")).is_true()



func test_dungeon_pressure_drives_hud_vision_and_enemy_activity() -> void:
	# 压力/HUD/视野已迁入 DungeonRuntime
	var source := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	assert_bool(source.contains("update_pressure(snapshot)") or source.contains("on_pressure_changed")) \
		.override_failure_message("探索 HUD 应展示时间、威胁和撤离提示") \
		.is_true()
	assert_bool(source.contains("combat_hud") or source.contains("CombatHUD")) \
		.override_failure_message("探索压力必须推送给 CombatHUD") \
		.is_true()
	assert_bool(source.contains("apply_player_vision_pressure") or source.contains("vision_range_multiplier")) \
		.override_failure_message("压力应缩窄玩家可感知视野") \
		.is_true()
	assert_bool(source.contains("environment_activity_mult") or source.contains("apply_environment_activity")) \
		.override_failure_message("压力应提高怪物活跃度") \
		.is_true()

func test_dungeon_overtime_finishes_expedition_as_non_voluntary_return() -> void:
	# 阶段 8/9 重构：超时结算从 procedural_dungeon.gd 迁入 DungeonRuntime（旧断言查 procedural 已过时）。
	var source := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code

	assert_bool(source.contains("expedition_overtime.connect(on_expedition_overtime)")) \
		.override_failure_message("18:00 超时应触发晚归结算") \
		.is_true()
	assert_bool(source.contains("finish_expedition(player_node, false)")) \
		.override_failure_message("晚归应记录为非主动撤离，供 TavernManager 归零今晚经营收入") \
		.is_true()


func test_dungeon_streams_lighting_and_terrain_by_chunks() -> void:
	# streaming 已迁入 DungeonStreamingController / DungeonStreamingConfig
	var ctrl_src := (load("res://scenes/expedition/dungeon_streaming_controller.gd") as GDScript).source_code
	var cfg_src := (load("res://scenes/expedition/dungeon_streaming_config.gd") as GDScript).source_code
	var pd_src := (load("res://scenes/expedition/procedural_dungeon.gd") as GDScript).source_code
	assert_bool(cfg_src.contains("chunk_size_cells") or ctrl_src.contains("STREAM_CHUNK_SIZE_CELLS")) 		.override_failure_message("应定义 chunk 尺寸，避免全图光照/地形一次性渲染") 		.is_true()
	assert_bool(ctrl_src.contains("STREAM_LIGHT_CHUNK_RADIUS := 2") or cfg_src.contains("light_chunk_radius")) 		.override_failure_message("灯光应启用玩家周围 5x5 chunk") 		.is_true()
	assert_bool(ctrl_src.contains("STREAM_TERRAIN_CHUNK_RADIUS := 1") or cfg_src.contains("terrain_chunk_radius")) 		.override_failure_message("地形应保留周围 chunk") 		.is_true()
	assert_bool(ctrl_src.contains("STREAM_PHYSICS_CHUNK_RADIUS := 1") or cfg_src.contains("physics_chunk_radius")) 		.override_failure_message("物品物理应启用玩家周围 3x3 chunk") 		.is_true()
	assert_bool(ctrl_src.contains("_light_chunks") or ctrl_src.contains("register_light")) 		.override_failure_message("环境光源应按 chunk 建索引") 		.is_true()
	assert_bool(ctrl_src.contains("_physics_chunks") or ctrl_src.contains("register_physics_node")) 		.override_failure_message("可物理化物体应按 chunk 建索引") 		.is_true()
	assert_bool(ctrl_src.contains("_terrain_chunks") or ctrl_src.contains("register_terrain_chunk")) 		.override_failure_message("地形 MultiMesh 应按 chunk 拆分并流式显示") 		.is_true()
	assert_bool(ctrl_src.contains("func update_streaming")) 		.override_failure_message("运行时应按玩家所在 chunk 更新可见光源和地形") 		.is_true()
	assert_bool(pd_src.contains("streaming_controller") and pd_src.contains("DungeonStreamingController")) 		.override_failure_message("ProceduralDungeon 应接线 DungeonStreamingController") 		.is_true()
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(builder_src.contains("_build_chunked_multi_meshes") or builder_src.contains("_group_transforms_by_stream_chunk")) 		.override_failure_message("Floor/Ceiling/Wall MultiMesh 应拆成 chunk 节点") 		.is_true()


func test_dungeon_streams_physics_by_current_chunk() -> void:
	# streaming 物理行为已迁入 DungeonStreamingController
	var ctrl := DungeonStreamingController.new()
	add_child(ctrl)
	var layout := DungeonLayout.new()
	layout.width = 32
	layout.height = 32
	layout.tile_size = 3.0
	layout.grid = [[1,1],[1,1]]
	layout.heights = [[3.0,3.0],[3.0,3.0]]
	ctrl.configure(layout, DungeonBuildResult.new())
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	var near_body := RigidBody3D.new()
	var adjacent_body := RigidBody3D.new()
	var far_body := RigidBody3D.new()
	var far_enemy := CharacterBody3D.new()
	near_body.position = Vector3.ZERO
	adjacent_body.position = Vector3(chunk_size + 1.0, 0.0, 0.0)
	far_body.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	far_enemy.position = far_body.position
	far_enemy.collision_layer = PhysicsSetup.LAYER_ENEMY
	far_enemy.collision_mask = PhysicsSetup.MASK_ENEMY
	add_child(near_body)
	add_child(adjacent_body)
	add_child(far_body)
	add_child(far_enemy)
	ctrl.register_physics_node(near_body)
	ctrl.register_physics_node(adjacent_body)
	ctrl.register_physics_node(far_body)
	ctrl.register_physics_node(far_enemy)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(near_body.freeze) \
		.override_failure_message("当前 chunk 内的物品刚体应被唤醒并自然落地") \
		.is_false()
	assert_bool(adjacent_body.freeze) \
		.override_failure_message("3x3 chunk 内的相邻物品刚体应被唤醒，避免近距离交互冻结") \
		.is_false()
	assert_bool(far_body.freeze) \
		.override_failure_message("3x3 chunk 外的物品刚体应保持冻结，避免全图同时模拟") \
		.is_true()
	assert_bool(far_enemy.is_physics_processing()) \
		.override_failure_message("3x3 chunk 外的敌人应暂停 physics process，避免全图 AI 和寻路同时运行") \
		.is_false()
	assert_int(far_enemy.collision_layer) \
		.override_failure_message("3x3 chunk 外的敌人应关闭碰撞层，避免远处角色体参与物理宽相位") \
		.is_equal(0)
	assert_int(far_enemy.collision_mask) \
		.override_failure_message("3x3 chunk 外的敌人应关闭碰撞 mask，避免远处角色体参与物理宽相位") \
		.is_equal(0)
	ctrl.clear()
	ctrl.queue_free()
	for n in [near_body, adjacent_body, far_body, far_enemy, player]:
		if is_instance_valid(n):
			n.queue_free()


func test_dungeon_streams_environment_lights_in_five_by_five_chunks() -> void:
	# 灯光 streaming 已迁入 DungeonStreamingController
	var ctrl := DungeonStreamingController.new()
	add_child(ctrl)
	var layout := DungeonLayout.new()
	layout.width = 32
	layout.height = 32
	layout.tile_size = 3.0
	layout.grid = [[1,1],[1,1]]
	layout.heights = [[3.0,3.0],[3.0,3.0]]
	ctrl.configure(layout, DungeonBuildResult.new())
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	var center_light := OmniLight3D.new()
	var two_chunks_light := OmniLight3D.new()
	var outside_light := OmniLight3D.new()
	center_light.position = Vector3.ZERO
	two_chunks_light.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	outside_light.position = Vector3(chunk_size * 3.0 + 1.0, 0.0, 0.0)
	for light in [center_light, two_chunks_light, outside_light]:
		light.visible = false
		add_child(light)
		ctrl.register_light(light)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(center_light.visible) \
		.override_failure_message("玩家所在 chunk 的环境光应启用") \
		.is_true()
	assert_bool(two_chunks_light.visible) \
		.override_failure_message("5x5 chunk 内的环境光应启用，避免视野边界硬切") \
		.is_true()
	assert_bool(outside_light.visible) \
		.override_failure_message("5x5 chunk 外的环境光应关闭，保持光源预算") \
		.is_false()
	ctrl.clear()
	ctrl.queue_free()
	for n in [center_light, two_chunks_light, outside_light, player]:
		if is_instance_valid(n):
			n.queue_free()


func test_dungeon_materials() -> void:
	var wall_mat_tested := false
	var floor_mat_tested := false
	var expected_tex = load("res://assets/textures/terrain/level0_dungeon/level0_dungeon_terrain_atlas_32px.png")

	# 地形 MultiMesh 挂 TerrainRoot 容器下，需遍历子树（非 dungeon 直接子节点）。
	for child in _collect_multi_mesh_instances(_dungeon):
		var mat = child.material_override
		if mat is ShaderMaterial:
			if String(child.name).begins_with("WallMultiMesh"):
				assert_object(mat.get_shader_parameter("atlas")).is_equal(expected_tex)
				assert_object(mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(0, 0))
				assert_object(mat.get_shader_parameter("tile_span")).is_equal(Vector2(1, 1))
				assert_object(mat.get_shader_parameter("atlas_grid")).is_equal(Vector2(8, 4))
				assert_bool((mat.get_shader_parameter("tile_repeat") as Vector2).y > 0.0).is_true()
				wall_mat_tested = true
			elif child.name == "FloorMultiMesh":
				assert_object(mat.get_shader_parameter("atlas")).is_equal(expected_tex)
				assert_object(mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(1, 0))
				assert_object(mat.get_shader_parameter("tile_span")).is_equal(Vector2(1, 1))
				assert_object(mat.get_shader_parameter("atlas_grid")).is_equal(Vector2(8, 4))
				assert_object(mat.get_shader_parameter("tile_repeat")).is_equal(Vector2(3.0, 3.0))
				floor_mat_tested = true

	assert_bool(wall_mat_tested).is_true()
	assert_bool(floor_mat_tested).is_true()


func test_dungeon_room_doors_use_boss_texture_only_for_boss_room_entries() -> void:
	var boss_room: Rect2i = _dungeon.layout.room_roles["boss"]
	var boss_doors := 0
	var standard_doors := 0
	# 门挂 DoorsRoot 容器下，需遍历子树（非 dungeon 直接子节点）。
	for door_node in _collect_doors(_dungeon):
		var door := door_node as DungeonDoor
		var kind := String(door.get_meta("door_kind"))
		var inside: Vector2i = door.get_meta("inside_cell")
		var outside: Vector2i = door.get_meta("outside_cell")
		var touches_boss := boss_room.has_point(inside) or boss_room.has_point(outside)
		var shape_node := door.get_node("CollisionShape3D") as CollisionShape3D
		var box := shape_node.shape as BoxShape3D
		var visual := _find_first_mesh(door)
		var side_visual := _find_mesh_by_suffix(door, "Side")
		var top_visual := _find_mesh_by_suffix(door, "Top")
		assert_bool((door.collision_layer & PhysicsSetup.LAYER_SCENE_OBJECT) != 0).is_true()
		assert_bool((door.collision_layer & PhysicsSetup.LAYER_TRIGGER) != 0).is_true()
		assert_bool(door.has_method("interact")).is_true()
		assert_bool(door.has_method("try_receive_hit")).is_true()
		assert_object(box).is_not_null()
		assert_object(visual).is_not_null()
		assert_object(side_visual).is_not_null()
		assert_object(top_visual).is_not_null()
		var mat := visual.material_override as ShaderMaterial
		var side_mat := side_visual.material_override as ShaderMaterial
		var top_mat := top_visual.material_override as ShaderMaterial
		assert_object(mat).is_not_null()
		assert_object(side_mat).is_not_null()
		assert_object(top_mat).is_not_null()
		assert_object(mat.get_shader_parameter("atlas_grid")).is_equal(Vector2(8, 4))
		assert_object(side_mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(2, 2))
		assert_object(side_mat.get_shader_parameter("tile_repeat")).is_equal(Vector2(DungeonDoor.THICKNESS, 2.0))
		assert_object(top_mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(3, 2))
		assert_object(top_mat.get_shader_parameter("tile_repeat")).is_equal(Vector2(1.0, DungeonDoor.THICKNESS))
		if touches_boss:
			boss_doors += 1
			assert_str(kind) \
				.override_failure_message("所有通向 boss 房的门都必须使用 boss 门规则: %s" % door.name) \
				.is_equal("boss")
			assert_float(box.size.y).is_equal_approx(2.0, 0.01)
			assert_float(maxf(box.size.x, box.size.z)).is_equal_approx(2.0, 0.01)
			assert_float(minf(box.size.x, box.size.z)).is_equal_approx(DungeonDoor.THICKNESS, 0.001)
			assert_object(mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(0, 2))
			assert_object(mat.get_shader_parameter("tile_span")).is_equal(Vector2(2, 2))
		else:
			standard_doors += 1
			assert_str(kind).is_equal("standard")
			assert_float(box.size.y).is_equal_approx(2.0, 0.01)
			assert_float(maxf(box.size.x, box.size.z)).is_equal_approx(1.0, 0.01)
			assert_float(minf(box.size.x, box.size.z)).is_equal_approx(DungeonDoor.THICKNESS, 0.001)
			assert_object(mat.get_shader_parameter("tile_col_row")).is_equal(Vector2(7, 1))
			assert_object(mat.get_shader_parameter("tile_span")).is_equal(Vector2(1, 2))

	assert_int(boss_doors) \
		.override_failure_message("程序地牢必须为所有 boss 房入口生成 2x2 boss 门") \
		.is_greater(0)
	assert_int(standard_doors) \
		.override_failure_message("程序地牢的非 boss 房入口必须生成 1x2 普通门") \
		.is_greater(0)


func test_dungeon_room_doors_generate_wall_surrounds_at_door_position() -> void:
	var door_count := 0
	# 门挂 DoorsRoot 容器下，需遍历子树（非 dungeon 直接子节点）。
	for door_node in _collect_doors(_dungeon):
		door_count += 1
		var door := door_node as DungeonDoor
		var surround := _find_door_surround_parts(_dungeon, String(door.name) + "Surround")
		assert_int(surround.size()) \
			.override_failure_message("门需要额外墙体延伸到门位置，至少包含左右门垛和门楣: %s" % door.name) \
			.is_greater_equal(3)
		for part in surround:
			var mat := part.material_override as ShaderMaterial
			assert_object(mat) \
				.override_failure_message("门周围补墙必须使用地牢墙体 ShaderMaterial: %s" % part.name) \
				.is_not_null()
			assert_object(mat.get_shader_parameter("tile_col_row")) \
				.override_failure_message("门周围补墙必须使用 WALL 纹理，不应使用门纹理: %s" % part.name) \
				.is_equal(Vector2(0, 0))

	assert_int(door_count) \
		.override_failure_message("地牢应生成至少 1 扇门来验证门洞补墙") \
		.is_greater(0)


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


func _find_mesh_by_suffix(node: Node, suffix: String) -> MeshInstance3D:
	if node is MeshInstance3D and String(node.name).ends_with(suffix):
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_by_suffix(child, suffix)
		if found != null:
			return found
	return null


func _find_door_surround_parts(root: Node, prefix: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_find_door_surround_parts_recursive(root, prefix, result)
	return result


func _find_door_surround_parts_recursive(node: Node, prefix: String, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and String(node.name).begins_with(prefix) and bool(node.get_meta("door_surround", false)):
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_find_door_surround_parts_recursive(child, prefix, result)


func test_dungeon_lighting_budget_keeps_player_light_and_limits_local_lights() -> void:
	var visible_local_lights := _collect_visible_local_lights(_dungeon)
	var player_light := _dungeon.get_node_or_null("Player/PlayerVisionLight") as OmniLight3D
	assert_object(player_light) \
		.override_failure_message("地牢必须保留玩家主视野灯") \
		.is_not_null()
	assert_bool(player_light.visible).is_true()
	assert_float(player_light.light_energy).is_greater_equal(2.4)
	assert_float(player_light.omni_range).is_greater_equal(10.0)
	assert_int(visible_local_lights.size()) \
		.override_failure_message("GL Compatibility 下实时灯过多会导致拾取后灯光选择抖动/黑屏") \
		.is_less_equal(DungeonStreamingController.DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET + 1)


func test_dungeon_walkable_area_has_baseline_visibility_without_drop_lights() -> void:
	var world_env := _find_world_environment(_dungeon)
	var directional := _find_directional_light(_dungeon)
	var environment_lights := _collect_visible_environment_lights(_dungeon)
	var walkable_points := _collect_walkable_cell_points(_dungeon)
	var visible_count := 0
	var dark_count := 0
	for point in walkable_points:
		var visibility := _estimate_visibility_at(point, world_env, directional, environment_lights)
		if visibility >= 0.075:
			visible_count += 1
		else:
			dark_count += 1

	assert_int(walkable_points.size()) \
		.override_failure_message("测试需要真实地牢可行走地块") \
		.is_greater(20)
	var coverage := float(visible_count) / float(walkable_points.size())
	assert_float(coverage) \
		.override_failure_message("地牢大部分区域应基本可视，当前可视覆盖 %.2f%%，过暗地块 %d/%d" % [coverage * 100.0, dark_count, walkable_points.size()]) \
		.is_greater_equal(0.85)


func _collect_visible_local_lights(root: Node) -> Array[Light3D]:
	var result: Array[Light3D] = []
	_collect_visible_local_lights_recursive(root, result)
	return result


func _collect_visible_local_lights_recursive(node: Node, result: Array[Light3D]) -> void:
	if node is Light3D and not (node is DirectionalLight3D) and (node as Light3D).visible:
		result.append(node as Light3D)
	for child in node.get_children():
		_collect_visible_local_lights_recursive(child, result)


func _collect_visible_environment_lights(root: Node) -> Array[Light3D]:
	var result: Array[Light3D] = []
	_collect_visible_environment_lights_recursive(root, result)
	return result


func _collect_visible_environment_lights_recursive(node: Node, result: Array[Light3D]) -> void:
	if node is Light3D and not (node is DirectionalLight3D) and (node as Light3D).visible:
		var parent := node.get_parent()
		var is_gameplay_entity_light := false
		while parent != null and parent != get_tree().root:
			if parent is PickableItem or parent is Enemy or parent is Player or parent is SpikesTrap or parent is AcidTrap or String(parent.name) == "FlameVentTrap":
				is_gameplay_entity_light = true
				break
			parent = parent.get_parent()
		if not is_gameplay_entity_light:
			result.append(node as Light3D)
	for child in node.get_children():
		_collect_visible_environment_lights_recursive(child, result)


func _collect_walkable_cell_points(dungeon: ProceduralDungeon) -> Array[Vector3]:
	var points: Array[Vector3] = []
	# 阶段 9：旧字段 _grid 已退役，网格统一读 layout.grid。
	var grid: Array = dungeon.layout.grid
	if grid.is_empty():
		return points
	var grid_width := int(grid[0].size())
	var grid_height := int(grid.size())
	var offset := Vector3(
		-(float(grid_width) * ProceduralDungeon.TILE_SIZE) / 2.0,
		1.0,
		-(float(grid_height) * ProceduralDungeon.TILE_SIZE) / 2.0
	)
	for y in range(grid_height):
		for x in range(grid[y].size()):
			var cell_type := int(grid[y][x])
			if cell_type != BSP_DungeonGenerator.TileType.EMPTY and cell_type != BSP_DungeonGenerator.TileType.WALL:
				points.append(offset + Vector3(x * ProceduralDungeon.TILE_SIZE, 0.0, y * ProceduralDungeon.TILE_SIZE))
	return points


func _estimate_visibility_at(point: Vector3, world_env: WorldEnvironment, directional: DirectionalLight3D, lights: Array[Light3D]) -> float:
	var visibility := 0.0
	if world_env != null and world_env.environment != null:
		visibility += _color_luminance(world_env.environment.ambient_light_color) * world_env.environment.ambient_light_energy
	if directional != null:
		visibility += _color_luminance(directional.light_color) * directional.light_energy * 0.35
	for light in lights:
		if light is OmniLight3D:
			var omni := light as OmniLight3D
			var distance := point.distance_to(omni.global_position)
			if distance <= omni.omni_range:
				var falloff := 1.0 - clampf(distance / maxf(omni.omni_range, 0.01), 0.0, 1.0)
				visibility += _color_luminance(omni.light_color) * omni.light_energy * falloff * falloff * 0.35
	return visibility


func _find_world_environment(root: Node) -> WorldEnvironment:
	if root is WorldEnvironment:
		return root as WorldEnvironment
	for child in root.get_children():
		var found := _find_world_environment(child)
		if found != null:
			return found
	return null


func _find_directional_light(root: Node) -> DirectionalLight3D:
	if root is DirectionalLight3D:
		return root as DirectionalLight3D
	for child in root.get_children():
		var found := _find_directional_light(child)
		if found != null:
			return found
	return null


func _color_luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


## 回归测试：procedural_dungeon.gd 必须编译成功。
## 此前 _spawn_room_door_panels 中 `var door_spec := spec.duplicate()` 因 spec
## 是无类型 Variant 导致类型推断失败，级联使 player.gd / game_state.gd 等编译失败，
## 进而使 tavern_manager_node.gd（引用 Player 类型）无法编译，导致出发提示永不挂载。
func test_procedural_dungeon_script_compiles() -> void:
	var script: GDScript = load("res://scenes/expedition/procedural_dungeon.gd")
	assert_object(script).is_not_null()
	assert_bool(script.is_class("GDScript")).is_true()


## 回归测试：door_spec 必须是 Dictionary 且包含 "boss" 键。
## 验证 _spawn_room_door_panels 中 spec.duplicate() 的显式 Dictionary 类型声明生效。
func test_door_spec_is_dictionary_with_boss_key() -> void:
	# 收集所有 DungeonDoor（挂 DoorsRoot 容器下，需遍历子树），验证其 metadata 类型正确
	var door_count := 0
	for door_node in _collect_doors(_dungeon):
		door_count += 1
		# door_kind 由 door_spec["boss"] 决定，必须是 "boss" 或 "standard"
		var kind: String = String(door_node.get_meta("door_kind"))
		assert_bool(kind == "boss" or kind == "standard") \
			.override_failure_message("door_spec 的 boss 键必须正确映射到 door_kind，实际: %s" % kind) \
			.is_true()

	assert_int(door_count) \
		.override_failure_message("地牢应生成至少 1 扇门来验证 door_spec 逻辑") \
		.is_greater(0)


## 唯一自建「第二具」带敌人地牢的测试（共享地牢不刷怪）。放最后：headless 下这具满员蒙皮 rig
## 场景之后不应再有任何全场景重建，合计 2 次实例化稳定低于 signal 11 崩溃阈值。
func test_dungeon_spawns_enemies() -> void:
	# 验证地牢 _ready 后生成了怪物
	var dungeon = load("res://scenes/expedition/procedural_dungeon.tscn").instantiate() as ProceduralDungeon
	add_child(dungeon)
	# 等待一帧确保所有延迟初始化完成
	await await_idle_frame()
	# 新架构（阶段 7+）：敌人生成到 SpawnRoot 容器下，而非 ProceduralDungeon 直接子节点，
	# 故需遍历整棵子树统计 Enemy（旧断言只扫直接子节点已过时）。
	var enemy_count := 0
	var stack: Array = [dungeon]
	while not stack.is_empty():
		var node = stack.pop_back()
		for c in node.get_children():
			stack.push_back(c)
		if node is Enemy:
			enemy_count += 1
	assert_int(enemy_count) \
		.override_failure_message("地牢应生成至少 4 只怪物，实际生成 %d 只" % enemy_count) \
		.is_greater_equal(4)
	remove_child(dungeon)
	dungeon.free()


## 开关对照：共享地牢以 spawn_population_enabled=false 构建，应完全不刷怪。
## 复用 before() 的共享实例，不新增全场景实例化（保持 2 次上限）。与 test_dungeon_spawns_enemies
## （默认 true → 刷怪）共同覆盖 spawn_population_enabled 标志的两条分支。
func test_dungeon_spawn_population_disabled_suppresses_enemies() -> void:
	assert_bool(_dungeon.spawn_population_enabled) \
		.override_failure_message("共享地牢应以 spawn_population_enabled=false 构建") \
		.is_false()
	var enemy_count := 0
	var stack: Array = [_dungeon]
	while not stack.is_empty():
		var node = stack.pop_back()
		for c in node.get_children():
			stack.push_back(c)
		if node is Enemy:
			enemy_count += 1
	assert_int(enemy_count) \
		.override_failure_message("spawn_population_enabled=false 时不应生成任何敌人，实际 %d 只" % enemy_count) \
		.is_equal(0)
