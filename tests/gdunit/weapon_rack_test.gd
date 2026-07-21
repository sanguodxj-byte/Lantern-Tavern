extends GdUnitTestSuite

const WEAPON_RACK_SCENE := "res://scenes/props/decor/weapon_rack.tscn"

func test_weapon_rack_instantiation() -> void:
	var scene := load(WEAPON_RACK_SCENE) as PackedScene
	assert_object(scene).is_not_null()
	
	var inst = scene.instantiate()
	assert_object(inst).is_not_null()
	assert_str(inst.prop_kind).is_equal("weapon_rack")
	
	var weapon_child_count := 0
	for child in inst.get_children():
		if child.name.begins_with("WeaponInstance_"):
			weapon_child_count += 1
	assert_int(weapon_child_count).is_equal(0)
	
	inst.free()


func test_spawn_weapons_on_rack_generates_weapons() -> void:
	var scene := load(WEAPON_RACK_SCENE) as PackedScene
	var inst = scene.instantiate()
	
	# Add child to active scene tree to allow absolute/relative node lookup
	get_tree().root.add_child(inst)
	
	assert_bool(inst.has_method("_spawn_weapons_on_rack")).is_true()
	inst._spawn_weapons_on_rack()
	
	var weapons_spawned: Array[String] = []
	for child in inst.get_children():
		if child.name.begins_with("WeaponInstance_"):
			weapons_spawned.append(child.name.replace("WeaponInstance_", ""))
			
	assert_int(weapons_spawned.size()).is_equal(10)
	assert_array(weapons_spawned).contains(["shortsword", "greatsword", "axe", "warhammer", "spear", "dagger", "longbow", "crossbow", "staff", "sword"])
	
	# Clean up
	get_tree().root.remove_child(inst)
	inst.free()
	await get_tree().process_frame


func test_weapon_rack_chest_polymorphism_and_model_updates() -> void:
	var scene := load(WEAPON_RACK_SCENE) as PackedScene
	var inst = scene.instantiate()
	get_tree().root.add_child(inst)
	
	# 1. 验证宝箱属性与伪装接口
	assert_bool("loot_data" in inst).is_true()
	assert_bool(inst.has_method("interact")).is_true()
	assert_bool(inst.has_method("close_loot_panel")).is_true()
	
	# 2. 初始渲染 10 种武器
	inst._spawn_weapons_on_rack()
	assert_int(inst.loot_data.get("weapons", []).size()).is_equal(10)
	
	var initial_children := 0
	for child in inst.get_children():
		if child.name.begins_with("WeaponInstance_"):
			initial_children += 1
	assert_int(initial_children).is_equal(10)
	
	# 3. 模拟玩家存取行为：取走除 shortsword 外的所有武器，只保留一把
	var wdata_to_keep = inst.loot_data["weapons"][0] # shortsword
	inst.loot_data["weapons"] = [wdata_to_keep]
	
	# 4. 面板关闭触发模型重新刷新渲染
	inst.close_loot_panel()
	
	var updated_children := 0
	var child_names: Array[String] = []
	for child in inst.get_children():
		if child.name.begins_with("WeaponInstance_"):
			updated_children += 1
			child_names.append(child.name)
	
	# 验证模型数量成功自适应变为了 1 且只保留了 shortsword
	assert_int(updated_children).is_equal(1)
	assert_str(child_names[0]).contains("shortsword")
	
	get_tree().root.remove_child(inst)
	inst.free()
	await get_tree().process_frame

