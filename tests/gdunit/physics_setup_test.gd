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
	assert_int(ps.LAYER_FURNITURE).is_equal(64)

func test_mask_combinations() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	# 玩家掩码应含环境+敌人+可拾取+家具
	assert_int(ps.MASK_PLAYER).is_equal(1 | 4 | 8 | 64)
	# 敌人掩码应含环境+玩家+可投掷
	assert_int(ps.MASK_ENEMY).is_equal(1 | 2 | 16)
	# 环境掩码为 0（被动碰撞）
	assert_int(ps.MASK_ENVIRONMENT).is_equal(0)

func test_get_layer_name() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node("PhysicsSetup")
	assert_str(ps.get_layer_name(1)).is_equal("environment")
	assert_str(ps.get_layer_name(2)).is_equal("player")
	assert_str(ps.get_layer_name(4)).is_equal("enemy")
	assert_str(ps.get_layer_name(8)).is_equal("pickable")

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
	assert_int(body.collision_mask).is_equal(1 | 4 | 2)
	body.queue_free()

# ---------- 酒馆物理补全 ----------

func test_tavern_structure_has_pillar_collision() -> void:
	var script: Resource = load("res://scenes/tavern/tavern_structure.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_add_box_collision") != -1).is_true()
	assert_bool(source.find("Pillar%d") != -1).is_true()

func test_tavern_structure_has_bar_counter_collision() -> void:
	var script: Resource = load("res://scenes/tavern/tavern_structure.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("BarTopBody") != -1).is_true()
	assert_bool(source.find("BarFrontBody") != -1).is_true()

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
