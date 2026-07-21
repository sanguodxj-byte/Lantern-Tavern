extends GdUnitTestSuite
## 物理统一注册器测试
## 验证：PhysicsSetup autoload 注册 + 层/掩码常量 + 碰撞添加函数

func test_physics_setup_autoload_registered() -> void:
	assert_object(Engine.get_main_loop().root.get_node_or_null("PhysicsSetup")).is_not_null()

func test_layer_constants_correct() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	assert_int(ps.LAYER_ENVIRONMENT).is_equal(1)
	assert_int(ps.LAYER_PLAYER).is_equal(2)
	assert_int(ps.LAYER_ENEMY).is_equal(4)
	assert_int(ps.LAYER_PICKABLE).is_equal(8)
	assert_int(ps.LAYER_THROWABLE).is_equal(16)
	assert_int(ps.LAYER_TRIGGER).is_equal(32)
	assert_int(ps.LAYER_SCENE_OBJECT).is_equal(64)
	assert_int(ps.LAYER_FURNITURE).is_equal(64)

func test_mask_combinations() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	# 玩家掩码应含环境+敌人+可拾取+门/触发层+家具
	assert_int(ps.MASK_PLAYER).is_equal(1 | 4 | 8 | 32 | 64)
	assert_int(ps.MASK_SELECTABLE).is_equal(8 | 64)
	# 敌人掩码应含环境+玩家+敌人+可投掷+门/触发层+家具
	assert_int(ps.MASK_ENEMY).is_equal(1 | 2 | 4 | 16 | 32 | 64)
	# 动态物体应彼此碰撞，避免掉落物/可投掷物互相穿过
	assert_int(ps.MASK_PICKABLE).is_equal(1 | 8 | 16 | 64)
	assert_int(ps.MASK_THROWABLE).is_equal(1 | 2 | 4 | 8 | 16 | 32 | 64)
	# 环境掩码为 0（被动碰撞）
	assert_int(ps.MASK_ENVIRONMENT).is_equal(0)

func test_get_layer_name() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	assert_str(ps.get_layer_name(1)).is_equal("environment")
	assert_str(ps.get_layer_name(2)).is_equal("player")
	assert_str(ps.get_layer_name(4)).is_equal("enemy")
	assert_str(ps.get_layer_name(8)).is_equal("pickable")
	assert_str(ps.get_layer_name(64)).is_equal("scene_object")

func test_add_box_collision_creates_static_body() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	var parent: Node3D = Node3D.new()
	add_child(parent)
	var body: StaticBody3D = ps.add_box_collision(parent, Vector3.ZERO, Vector3(2, 2, 2))
	assert_object(body).is_not_null()
	assert_str(body.get_class()).is_equal("StaticBody3D")
	assert_int(body.collision_layer).is_equal(1)
	assert_int(body.get_child_count()).is_equal(1)
	parent.queue_free()

func test_add_static_collision_from_mesh() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	var parent: Node3D = Node3D.new()
	add_child(parent)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(3, 3, 3)
	mi.mesh = mesh
	parent.add_child(mi)
	var body: StaticBody3D = ps.add_static_collision(parent, mi)
	assert_object(body).is_not_null()
	assert_str(body.get_class()).is_equal("StaticBody3D")
	parent.queue_free()

func test_setup_rigidbody_sets_layer() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	var body: RigidBody3D = RigidBody3D.new()
	add_child(body)
	ps.setup_rigidbody(body, ps.LAYER_THROWABLE)
	assert_int(body.collision_layer).is_equal(16)
	assert_int(body.collision_mask).is_equal(1 | 4 | 2 | 8 | 16 | 32 | 64)
	assert_object(body.get_node("CollisionShape3D").shape).is_instanceof(BoxShape3D)
	body.queue_free()

func test_setup_rigidbody_as_pickable_uses_pickable_mask() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	var body: RigidBody3D = RigidBody3D.new()
	add_child(body)
	ps.setup_rigidbody(body, ps.LAYER_PICKABLE)
	assert_int(body.collision_layer).is_equal(8)
	assert_int(body.collision_mask).is_equal(1 | 8 | 16 | 64)
	assert_object(body.get_node("CollisionShape3D").shape).is_instanceof(BoxShape3D)
	body.queue_free()

func test_dynamic_object_masks_collide_with_each_other() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	assert_bool((ps.MASK_PICKABLE & ps.LAYER_PICKABLE) != 0) \
		.override_failure_message("可拾取物之间必须能互相碰撞，避免同层物体穿模") \
		.is_true()
	assert_bool((ps.MASK_PICKABLE & ps.LAYER_THROWABLE) != 0) \
		.override_failure_message("可拾取物必须能被可投掷物推开/挡住") \
		.is_true()
	assert_bool((ps.MASK_THROWABLE & ps.LAYER_PICKABLE) != 0) \
		.override_failure_message("可投掷物必须能撞到地面掉落物") \
		.is_true()
	assert_bool((ps.MASK_THROWABLE & ps.LAYER_THROWABLE) != 0) \
		.override_failure_message("可投掷物之间必须能互相碰撞") \
		.is_true()

func test_setup_character_body_adds_capsule_collision() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	var body: CharacterBody3D = CharacterBody3D.new()
	add_child(body)
	ps.setup_player(body)
	assert_int(body.collision_layer).is_equal(2)
	assert_int(body.collision_mask).is_equal(1 | 4 | 8 | 32 | 64)
	assert_object(body.get_node("CollisionShape3D").shape).is_instanceof(CapsuleShape3D)
	var capsule := body.get_node("CollisionShape3D").shape as CapsuleShape3D
	assert_float(capsule.height).is_equal_approx(1.7, 0.001)
	assert_float(capsule.radius).is_equal_approx(0.25, 0.001)
	body.queue_free()

func test_humanoid_collision_standard_fits_one_meter_door() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	assert_float(ps.HUMANOID_COLLISION_HEIGHT).is_equal_approx(1.7, 0.001)
	assert_float(ps.HUMANOID_COLLISION_WIDTH).is_equal_approx(0.5, 0.001)
	assert_float(ps.HUMANOID_COLLISION_WIDTH).is_less(1.0)

func test_body_size_collision_uses_standard_multipliers() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	assert_float(ps.get_character_capsule_height("small")).is_equal_approx(0.85, 0.001)
	assert_float(ps.get_character_capsule_radius("small")).is_equal_approx(0.125, 0.001)
	assert_float(ps.get_character_capsule_height("medium")).is_equal_approx(1.7, 0.001)
	assert_float(ps.get_character_capsule_radius("medium")).is_equal_approx(0.25, 0.001)
	assert_float(ps.get_character_capsule_height("large")).is_equal_approx(2.21, 0.001)
	assert_float(ps.get_character_capsule_radius("large")).is_equal_approx(0.325, 0.001)
	assert_float(ps.get_character_capsule_height("huge")).is_equal_approx(2.975, 0.001)
	assert_float(ps.get_character_capsule_radius("huge")).is_equal_approx(0.4375, 0.001)

func test_setup_enemy_applies_body_size_multiplier() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	var body: CharacterBody3D = CharacterBody3D.new()
	body.set_meta("body_size", "huge")
	add_child(body)
	ps.setup_enemy(body)
	var shape := body.get_node("CollisionShape3D").shape as CapsuleShape3D
	assert_float(shape.height).is_equal_approx(ps.get_character_capsule_height("huge"), 0.001)
	assert_float(shape.radius).is_equal_approx(ps.get_character_capsule_radius("huge"), 0.001)
	assert_float(body.get_node("CollisionShape3D").position.y).is_equal_approx(shape.height * 0.5, 0.001)
	body.queue_free()

func test_setup_pickable_adds_box_collision() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	var body: RigidBody3D = RigidBody3D.new()
	add_child(body)
	ps.setup_pickable(body)
	assert_int(body.collision_layer).is_equal(8)
	assert_int(body.collision_mask).is_equal(1 | 8 | 16 | 64)
	assert_object(body.get_node("CollisionShape3D").shape).is_instanceof(BoxShape3D)
	body.queue_free()

func test_setup_trigger_targets_player_layer() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	var area: Area3D = Area3D.new()
	add_child(area)
	ps.setup_trigger(area)
	assert_int(area.collision_layer).is_equal(32)
	assert_int(area.collision_mask).is_equal(2)
	assert_object(area.get_node("CollisionShape3D").shape).is_instanceof(SphereShape3D)
	area.queue_free()

# ---------- 酒馆物理补全 ----------

func test_tavern_structure_has_pillar_collision() -> void:
	var script: Resource = load("res://scenes/tavern/tavern_structure.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_add_box_collision") == -1) \
		.override_failure_message("酒馆结构脚本不应再批量生成碰撞，碰撞应保存在手工场景节点中") \
		.is_true()
	var scene_text := FileAccess.get_file_as_string("res://scenes/tavern/tavern.tscn")
	assert_bool(scene_text.find("Pillar1Body") != -1).is_true()

func test_tavern_structure_has_bar_counter_collision() -> void:
	var scene_text := FileAccess.get_file_as_string("res://scenes/tavern/tavern.tscn")
	assert_bool(scene_text.find("BarTopBody") != -1).is_true()
	assert_bool(scene_text.find("BarFrontBody") != -1).is_true()

# ---------- 地牢物理补全 ----------

func test_procedural_dungeon_ensures_collision_on_decor() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_ensure_collision_on_instance") != -1).is_true()
	assert_bool(source.find("_has_physics_body") != -1).is_true()

func test_procedural_dungeon_spawn_prefab_ensures_collision() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	# _spawn_prefab 应调用 _ensure_collision_on_instance
	assert_bool(source.find("_ensure_collision_on_instance") != -1) \
		.override_failure_message("_spawn_prefab 未调用 _ensure_collision_on_instance").is_true()

func test_procedural_dungeon_configures_prefabs_as_scene_objects() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_configure_scene_object(instance)") != -1) \
		.override_failure_message("地牢 prefab 未标记为场景物体层").is_true()
	assert_bool(source.find("SCENE_OBJECT_SCRIPT") != -1) \
		.override_failure_message("普通场景物体未挂接通用互动脚本").is_true()

func test_tavern_interior_configures_props_as_scene_objects() -> void:
	var script: Resource = load("res://scenes/tavern/tavern_manager_node.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_configure_scene_objects()") != -1) \
		.override_failure_message("酒馆场景未配置场景物体互动层").is_true()
	assert_bool(source.find("SCENE_OBJECT_SCRIPT") != -1) \
		.override_failure_message("酒馆普通场景物体未挂接通用互动脚本").is_true()

func test_procedural_dungeon_scene_object_collision_uses_child_mesh_transform() -> void:
	var dungeon: Node = load("res://scenes/expedition/procedural_dungeon.gd").new()
	_assert_scene_object_collision_uses_child_mesh_transform(dungeon)
	dungeon.free()

func test_tavern_interior_scene_object_collision_uses_child_mesh_transform() -> void:
	var tavern: Node = load("res://scenes/tavern/tavern_manager_node.gd").new()
	_assert_scene_object_collision_uses_child_mesh_transform(tavern)
	tavern.free()

func _assert_scene_object_collision_uses_child_mesh_transform(target: Node) -> void:
	var prop := Node3D.new()
	prop.name = "TransformProbe"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	mesh.mesh = box
	mesh.position = Vector3(0.0, 1.25, 0.0)
	prop.add_child(mesh)

	target.call("_ensure_collision_on_instance", prop)

	var body := prop.get_node_or_null("TransformProbeBody") as StaticBody3D
	assert_object(body).is_not_null()
	if body == null:
		prop.free()
		return
	var col := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_object(col).is_not_null()
	if col == null:
		prop.free()
		return
	assert_float(col.position.y) \
		.override_failure_message("场景物体补碰撞必须把子 Mesh transform 合并进 AABB") \
		.is_equal_approx(1.25, 0.001)
	assert_float((col.shape as BoxShape3D).size.y).is_equal_approx(1.0, 0.001)
	prop.free()
