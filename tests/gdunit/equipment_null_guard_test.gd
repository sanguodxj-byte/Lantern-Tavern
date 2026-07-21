extends GdUnitTestSuite
# 设备对象空安全保护测试
# 验证所有 glb_mesh / cast 空访问路径已被正确守卫

func _track_node(node: Node) -> Node:
	return auto_free(node)


# ========== pickable_item.gd ==========

func test_pickable_item_ready_safe_with_null_glb_mesh() -> void:
	# WeaponData 有数据但无 glb_mesh 时应安全跳过
	var data := WeaponData.new()
	data.name = "NullMeshWeapon"
	data.condition = 10
	data.max_condition = 10
	assert_object(data.glb_mesh).is_null()  # 确认未设置 glb_mesh

	var scene := load("res://scenes/equipment/pickable_item.tscn")
	assert_object(scene).is_not_null()
	var item = _track_node(scene.instantiate())
	assert_object(item).is_not_null()
	item.weapon_data = data
	# 如果 glb_mesh 为空，_ready 应安全跳过（不会崩溃）
	# 因为我们手动调用 _ready，需确保无异常
	item._ready()
	# 到达此处即表示通过（未因空 glb_mesh 抛出异常）


func test_pickable_item_ready_safe_with_null_shield_glb_mesh() -> void:
	var data := ShieldData.new()
	data.name = "NullMeshShield"
	assert_object(data.glb_mesh).is_null()

	var scene := load("res://scenes/equipment/pickable_item.tscn")
	assert_object(scene).is_not_null()
	var item = _track_node(scene.instantiate())
	assert_object(item).is_not_null()
	item.shield_data = data
	item._ready()
	# 通过即表示安全


func test_pickable_item_ready_guards_glb_mesh_in_source() -> void:
	var script: Resource = load("res://scenes/equipment/pickable_item.gd")
	var source: String = (script as GDScript).source_code
	# 验证代码中包含 glb_mesh 空守卫
	assert_bool(source.find("weapon_data and weapon_data.glb_mesh") != -1) \
		.override_failure_message("pickable_item.gd 缺少 weapon_data.glb_mesh 空守卫").is_true()
	assert_bool(source.find("shield_data and shield_data.glb_mesh") != -1) \
		.override_failure_message("pickable_item.gd 缺少 shield_data.glb_mesh 空守卫").is_true()


# ========== equiped_item.gd ==========

func test_equiped_item_ready_safe_with_null_glb_mesh() -> void:
	var data := WeaponData.new()
	data.name = "NullMeshWeapon"
	assert_object(data.glb_mesh).is_null()

	var scene := load("res://scenes/equipment/equiped_item.tscn")
	assert_object(scene).is_not_null()
	var item = _track_node(scene.instantiate())
	assert_object(item).is_not_null()
	item.weapon_data = data
	item._ready()
	# 通过即表示安全


func test_equiped_item_ready_guards_glb_mesh_in_source() -> void:
	var script: Resource = load("res://scenes/equipment/equiped_item.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("weapon_data and weapon_data.glb_mesh") != -1) \
		.override_failure_message("equiped_item.gd 缺少 weapon_data.glb_mesh 空守卫").is_true()
	assert_bool(source.find("shield_data and shield_data.glb_mesh") != -1) \
		.override_failure_message("equiped_item.gd 缺少 shield_data.glb_mesh 空守卫").is_true()
	assert_bool(source.find("furniture_data and furniture_data.glb_mesh") != -1) \
		.override_failure_message("equiped_item.gd 缺少 furniture_data.glb_mesh 空守卫").is_true()


# ========== thrown_item.gd ==========

func test_thrown_item_ready_safe_with_null_glb_mesh() -> void:
	var data := WeaponData.new()
	data.name = "NullMeshWeapon"
	assert_object(data.glb_mesh).is_null()

	var scene := load("res://scenes/equipment/thrown_item.tscn")
	assert_object(scene).is_not_null()
	var item = _track_node(scene.instantiate())
	assert_object(item).is_not_null()
	item.weapon_data = data
	item._ready()
	# 通过即表示安全


func test_thrown_item_ready_guards_glb_mesh_in_source() -> void:
	var script: Resource = load("res://scenes/equipment/thrown_item.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("weapon_data != null and weapon_data.glb_mesh") != -1) \
		.override_failure_message("thrown_item.gd 缺少 weapon_data.glb_mesh 空守卫").is_true()
	assert_bool(source.find("shield_data != null and shield_data.glb_mesh") != -1) \
		.override_failure_message("thrown_item.gd 缺少 shield_data.glb_mesh 空守卫").is_true()
	assert_bool(source.find("furniture_data != null and furniture_data.glb_mesh") != -1) \
		.override_failure_message("thrown_item.gd 缺少 furniture_data.glb_mesh 空守卫").is_true()


# ========== equipment_component.gd ==========

func test_equipment_component_guards_null_equiped_item_cast() -> void:
	var script: Resource = load("res://scenes/characters/component/equipment_component.gd")
	var source: String = (script as GDScript).source_code
	# 验证 equip_weapon 中包含 null 检查
	assert_bool(source.find("if weapon == null") != -1) \
		.override_failure_message("equipment_component.gd equip_weapon 缺少 weapon null 检查").is_true()
	assert_bool(source.find("if shield == null") != -1) \
		.override_failure_message("equipment_component.gd equip_shield 缺少 shield null 检查").is_true()
	assert_bool(source.find("if furniture == null") != -1) \
		.override_failure_message("equipment_component.gd equip_furniture 缺少 furniture null 检查").is_true()


func test_equipment_component_drop_uses_placeholder_fallback_transform() -> void:
	var script: Resource = load("res://scenes/characters/component/equipment_component.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.contains("func _fallback_drop_transform")) \
		.override_failure_message("装备掉落应提供缺失挂点时的 transform 兜底").is_true()
	assert_bool(source.contains("_fallback_drop_transform(weapon_placeholder)")) \
		.override_failure_message("武器掉落不应直接访问 weapon_placeholder.global_transform").is_true()
	assert_bool(source.contains("_fallback_drop_transform(shield_placeholder)")) \
		.override_failure_message("盾牌掉落不应直接访问 shield_placeholder.global_transform").is_true()


# ========== enemy_state_impaling.gd ==========

func test_enemy_state_impaling_guards_null_thrown_item() -> void:
	var script: Resource = load("res://scenes/characters/enemies/state/enemy_state_impaling.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("state_data.thrown_item == null") != -1) \
		.override_failure_message("enemy_state_impaling.gd 缺少 thrown_item null 检查").is_true()


func test_enemy_state_impaling_guards_null_impaled_item() -> void:
	var script: Resource = load("res://scenes/characters/enemies/state/enemy_state_impaling.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("impaled_item == null") != -1) \
		.override_failure_message("enemy_state_impaling.gd 缺少 impaled_item null 检查").is_true()
