extends GdUnitTestSuite

# PickableItem 材料采集与 TavernManager 入库集成测试

func test_pickable_item_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/equipment/pickable_item.gd")).is_true()


func test_pickable_item_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/equipment/pickable_item.tscn")).is_true()


func test_pickable_item_drops_do_not_emit_light_or_glow() -> void:
	var item: PickableItem = load("res://scenes/equipment/pickable_item.tscn").instantiate()
	add_child(item)
	await await_idle_frame()

	for light in _collect_lights(item):
		assert_bool(light.visible) \
			.override_failure_message("掉落物不应启用自身光源: %s" % light.get_path()) \
			.is_false()
	assert_bool(_source("res://scenes/equipment/pickable_item.gd").contains("GLOW_MATERIAL")) \
		.override_failure_message("掉落物不应再套用自发光材质") \
		.is_false()
	var highlight := load("res://materials/highlight_material.tres") as StandardMaterial3D
	assert_bool(highlight.emission_enabled) \
		.override_failure_message("掉落物高亮材质也不应自发光") \
		.is_false()

	item.free()


func test_pickable_material_models_disable_embedded_emission() -> void:
	var item: PickableItem = load("res://scenes/equipment/pickable_item.tscn").instantiate()
	item.material_id = "glowshroom"
	add_child(item)
	await await_idle_frame()

	var materials := _collect_standard_materials(item)
	assert_int(materials.size()) \
		.override_failure_message("测试需要至少收集到一个掉落物网格材质") \
		.is_greater(0)
	for mat in materials:
		assert_bool(mat.emission_enabled) \
			.override_failure_message("掉落物网格材质不应自发光") \
			.is_false()

	item.free()


func test_pickable_item_has_material_id_property() -> void:
	var script = load("res://scenes/equipment/pickable_item.gd") as GDScript
	assert_object(script).is_not_null()
	var source = script.source_code
	assert_bool(source.contains("material_id")) \
		.override_failure_message("PickableItem 缺少 material_id 属性").is_true()
	assert_bool(source.contains("rune_id")) \
		.override_failure_message("PickableItem 缺少 rune_id 属性").is_true()

func test_pickup_state_routes_runes_to_game_state() -> void:
	var script = load("res://scenes/characters/player/state/player_state_picking_up.gd") as GDScript
	assert_object(script).is_not_null()
	var source: String = script.source_code
	assert_bool(source.contains("pickable_object.rune_id")) \
		.override_failure_message("拾取状态必须识别 PickableItem.rune_id").is_true()
	assert_bool(source.contains("GameState.add_carried_rune")) \
		.override_failure_message("拾取符文必须写入 GameState.add_carried_rune").is_true()


func test_check_for_possible_action_null_collider_safe() -> void:
	# 回归测试：捡起物品 queue_free() 后，射线仍报告碰撞但 get_collider() 返回 null，
	# check_for_possible_action() 的 else 分支不得在 null 上调用 has_method。
	var script = load("res://scenes/characters/player/player.gd") as GDScript
	assert_object(script).is_not_null()
	var source: String = script.source_code
	# 旧代码在 else 分支直接 collider.has_method("get_item_name") 无空检查，
	# 修复后应改为 elif collider != null and collider.has_method("get_item_name")
	assert_bool(source.contains('elif collider != null and collider.has_method("get_item_name")')) \
		.override_failure_message("check_for_possible_action 必须在调用 has_method 前检查 collider != null").is_true()
	# 确保旧的裸 else 分支已移除
	assert_bool(source.contains('else:\n\t\t\tvar item_name := ""\n\t\t\tif collider.has_method("get_item_name")')) \
		.override_failure_message("check_for_possible_action 仍存在未检查 null 的 else 分支").is_false()


func test_pickup_state_clears_focused_item_after_free() -> void:
	# 回归测试：捡起物品后必须清理 current_pickable_focused_item，避免悬空引用。
	var script = load("res://scenes/characters/player/state/player_state_picking_up.gd") as GDScript
	assert_object(script).is_not_null()
	var source: String = script.source_code
	assert_bool(source.contains("player.current_pickable_focused_item = null")) \
		.override_failure_message("捡起物品后必须清理 current_pickable_focused_item").is_true()
	# 确保每条 queue_free 路径都紧跟清理语句
	var free_count := source.count("pickable_object.queue_free()")
	var clear_count := source.count("player.current_pickable_focused_item = null")
	assert_int(clear_count).is_equal(free_count) \
		.override_failure_message("每处 queue_free() 必须配对 current_pickable_focused_item = null")


func test_check_for_selection_uses_is_instance_valid() -> void:
	# 回归测试：check_for_selection 对 current_pickable_focused_item 调用 unhighlight 前需检查 is_instance_valid。
	var script = load("res://scenes/characters/player/player.gd") as GDScript
	assert_object(script).is_not_null()
	var source: String = script.source_code
	assert_bool(source.contains("if current_pickable_focused_item and is_instance_valid(current_pickable_focused_item):")) \
		.override_failure_message("check_for_selection 必须在 unhighlight 前检查 is_instance_valid").is_true()


func test_can_pickup_object_checks_is_instance_valid() -> void:
	# 回归测试：can_pickup_object 必须检查 is_instance_valid，防止已释放的物体仍被判定为可拾取。
	var script = load("res://scenes/characters/player/player.gd") as GDScript
	assert_object(script).is_not_null()
	var source: String = script.source_code
	assert_bool(source.contains("is_instance_valid(current_pickable_focused_item)")) \
		.override_failure_message("can_pickup_object 必须检查 is_instance_valid(current_pickable_focused_item)").is_true()


func test_pickup_state_enter_tree_checks_is_instance_valid() -> void:
	# 回归测试：player_state_picking_up _enter_tree 必须在访问 pickable_object 属性前检查 is_instance_valid。
	var script = load("res://scenes/characters/player/state/player_state_picking_up.gd") as GDScript
	assert_object(script).is_not_null()
	var source: String = script.source_code
	assert_bool(source.contains("not pickable_object or not is_instance_valid(pickable_object)")) \
		.override_failure_message("_enter_tree 必须在访问 pickable_object 属性前检查 is_instance_valid").is_true()


func test_check_for_selection_clears_stale_reference() -> void:
	# 回归测试：check_for_selection 必须在比较前清理已失效的 current_pickable_focused_item。
	var script = load("res://scenes/characters/player/player.gd") as GDScript
	assert_object(script).is_not_null()
	var source: String = script.source_code
	assert_bool(source.contains("not is_instance_valid(current_pickable_focused_item)")) \
		.override_failure_message("check_for_selection 必须清理已失效的 current_pickable_focused_item 引用").is_true()


# ── 拾取后悬浮窗不消失 Bug 回归测试 ──────────────────────

func test_check_for_selection_filters_freed_collider() -> void:
	# 回归测试：拾取后 queue_free 的物体可能仍被射线报告一帧，
	# check_for_selection 必须用 is_instance_valid 过滤已释放的 collider，
	# 否则会重新瞄准已释放物体并持续发射 detail 信号，导致悬浮窗不消失。
	var script = load("res://scenes/characters/player/player.gd") as GDScript
	var source: String = script.source_code
	# check_for_selection 中应在 collider is PickableItem 前检查 is_instance_valid
	assert_bool(source.contains("is_instance_valid(collider) and collider is PickableItem")) \
		.override_failure_message("check_for_selection 必须在 collider is PickableItem 前检查 is_instance_valid(collider)").is_true()


func test_check_for_selection_validates_focused_item_before_emit() -> void:
	# 回归测试：发射 detail 信号前必须验证 current_pickable_focused_item 仍然有效，
	# 防止对已释放物体调用 highlight() 和 detail_for_pickable_item()。
	var script = load("res://scenes/characters/player/player.gd") as GDScript
	var source: String = script.source_code
	assert_bool(source.contains("current_pickable_focused_item is PickableItem and is_instance_valid(current_pickable_focused_item)")) \
		.override_failure_message("check_for_selection 必须在发射 detail 信号前验证 is_instance_valid(current_pickable_focused_item)").is_true()


func test_check_for_possible_action_filters_freed_collider_first_pass() -> void:
	# 回归测试：check_for_possible_action 首次扫描必须过滤已释放的 collider，
	# 否则 freed_obj == _last_possible_action_collider 导致 collider_changed=false，
	# 提前返回不发射空 hint 信号，拾取提示悬浮窗不消失。
	var script = load("res://scenes/characters/player/player.gd") as GDScript
	var source: String = script.source_code
	# 首次扫描应使用 is_instance_valid 过滤
	var fn_start := source.find("func check_for_possible_action")
	var fn_body := source.substr(fn_start, 1200)
	assert_bool(fn_body.contains("is_instance_valid(sel_collider)")) \
		.override_failure_message("check_for_possible_action 首次扫描必须用 is_instance_valid 过滤 select_raycast collider").is_true()


func test_check_for_possible_action_filters_freed_collider_second_pass() -> void:
	# 回归测试：check_for_possible_action 第二次扫描（构建 hint 字符串时）也必须过滤已释放的 collider，
	# 否则会对已释放物体调用 get_item_name() 等方法。
	var script = load("res://scenes/characters/player/player.gd") as GDScript
	var source: String = script.source_code
	var fn_start := source.find("func check_for_possible_action")
	var fn_body := source.substr(fn_start, 2000)
	# 第二次扫描应在 get_collider 后检查 is_instance_valid
	assert_bool(fn_body.contains("not is_instance_valid(current_collider)")) \
		.override_failure_message("check_for_possible_action 第二次扫描必须过滤已释放的 current_collider").is_true()


func test_check_for_possible_action_kick_door_filters_freed() -> void:
	# 回归测试：kick_raycast 路径也必须过滤已释放的 collider
	var script = load("res://scenes/characters/player/player.gd") as GDScript
	var source: String = script.source_code
	var fn_start := source.find("func check_for_possible_action")
	var fn_body := source.substr(fn_start, 2500)
	assert_bool(fn_body.contains("is_instance_valid(kick_door)")) \
		.override_failure_message("check_for_possible_action kick_raycast 路径必须用 is_instance_valid 过滤 kick_door").is_true()
	assert_bool(fn_body.contains("is_instance_valid(kick_collider)")) \
		.override_failure_message("check_for_possible_action 首次扫描 kick_raycast 路径必须用 is_instance_valid 过滤 kick_collider").is_true()


func test_check_for_possible_action_no_raw_get_collider_is_door() -> void:
	# 回归测试：不应再在 elif 条件中直接调用 kick_raycast.get_collider() is Door（未过滤已释放物体）
	var script = load("res://scenes/characters/player/player.gd") as GDScript
	var source: String = script.source_code
	assert_bool(not source.contains("kick_raycast.get_collider() is Door")) \
		.override_failure_message("不应在 elif 条件中直接调用 kick_raycast.get_collider() is Door（需先过滤已释放物体）").is_true()


func test_pickable_item_material_no_old_fictional_ids() -> void:
	# 验证 PickableItem 不再引用旧虚构材料 OBJ 路径
	var script = load("res://scenes/equipment/pickable_item.gd") as GDScript
	var source = script.source_code
	# Should not have any OBJ model references at all
	assert_bool(not source.contains(".obj")) \
		.override_failure_message("PickableItem 仍引用 OBJ 模型").is_true()
	assert_bool(not source.contains("_instantiate_legacy_obj_material")) \
		.override_failure_message("PickableItem 仍有旧版 OBJ 回退函数").is_true()


func test_pickable_item_material_colors_match_brew_data() -> void:
	# 验证 PickableItem 中的材料颜色映射至少覆盖 BrewingData 的部分核心材料
	var script = load("res://scenes/equipment/pickable_item.gd") as GDScript
	var source = script.source_code
	# 核心材料应有对应的颜色分支
	assert_bool(source.contains("glowcap")) \
		.override_failure_message("缺少 glowcap 视觉分支").is_true()
	assert_bool(source.contains("bloom")) \
		.override_failure_message("缺少 bloom 视觉分支").is_true()
	assert_bool(source.contains("honeycomb")) \
		.override_failure_message("缺少 honeycomb 视觉分支").is_true()


# ---------- TavernManager 采集入库 ----------

func test_tavern_manager_add_material_works() -> void:
	var tm_script = load("res://globals/tavern/tavern_manager.gd") as GDScript
	var tm = tm_script.new()
	tm.add_material("rat_tail", 1)
	assert_int(tm.inventory.get("rat_tail", 0)).is_equal(1)
	tm.free()


func test_expedition_hud_add_material_routes_to_game_state_backpack() -> void:
	# 探险中材料先进入随身背包，不能直接进入酒馆仓库。
	var script = load("res://scenes/ui/expedition_hud.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("GameState.add_carried_material")) \
		.override_failure_message("ExpeditionHUD 应调用 GameState.add_carried_material()").is_true()
	assert_bool(source.contains("TavernManager.add_material")) \
		.override_failure_message("ExpeditionHUD 不应直接写入 TavernManager 仓库").is_false()


func test_procedural_dungeon_spawns_pickable_items() -> void:
	var dg_script = load("res://scenes/expedition/procedural_dungeon.gd") as GDScript
	var source = dg_script.source_code
	assert_bool(source.contains("PICKABLE_ITEM_PREFAB")) \
		.override_failure_message("地牢未引用 PickableItem 预制体").is_true()
	assert_bool(source.contains("_spawn_random_material")) \
		.override_failure_message("地牢缺少 _spawn_random_material()").is_true()


func _collect_lights(root: Node) -> Array[Light3D]:
	var result: Array[Light3D] = []
	_collect_lights_recursive(root, result)
	return result


func _collect_lights_recursive(node: Node, result: Array[Light3D]) -> void:
	if node is Light3D:
		result.append(node as Light3D)
	for child in node.get_children():
		_collect_lights_recursive(child, result)


func _source(path: String) -> String:
	var script = load(path) as GDScript
	return script.source_code


func _collect_standard_materials(root: Node) -> Array[StandardMaterial3D]:
	var result: Array[StandardMaterial3D] = []
	_collect_standard_materials_recursive(root, result)
	return result


func _collect_standard_materials_recursive(node: Node, result: Array[StandardMaterial3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		_append_standard_material(mesh_instance.material_override, result)
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var mat := mesh_instance.get_surface_override_material(surface_index)
				if mat == null:
					mat = mesh_instance.mesh.surface_get_material(surface_index)
				_append_standard_material(mat, result)
	for child in node.get_children():
		_collect_standard_materials_recursive(child, result)


func _append_standard_material(mat: Material, result: Array[StandardMaterial3D]) -> void:
	if mat is StandardMaterial3D:
		result.append(mat as StandardMaterial3D)
