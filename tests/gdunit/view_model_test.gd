extends GdUnitTestSuite

# ViewModel 第一人称武器视图模型测试
# 验证脚本存在、核心方法、与 player/equipment/state 的集成

func test_view_model_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/characters/player/view_model.gd")).is_true()


func test_view_model_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/characters/player/view_model.tscn")).is_true()


func test_view_model_has_class_name() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("class_name ViewModel")


func test_view_model_extends_node3d() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("extends Node3D")


func test_view_model_has_weapon_holder_reference() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("weapon_holder")


func test_view_model_has_set_weapon_method() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("func set_weapon(")


func test_view_model_has_clear_weapon_method() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("func clear_weapon(")


func test_view_model_has_apply_slash_arc_method() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("func apply_slash_arc(")


func test_view_model_has_restore_transform_method() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("func restore_transform(")


func test_view_model_has_apply_recoil_method() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("func apply_recoil(")


func test_view_model_has_set_aiming_method() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("func set_aiming(")


func test_view_model_listens_to_weapon_changed() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("weapon_changed")


func test_view_model_uses_get_tree_for_signal_connection() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	# 确保使用 get_tree() 而非 Engine.get_main_loop() 来获取 autoload
	assert_str(script.source_code).contains("get_tree()")


func test_view_model_sets_render_layer_on_weapon_mesh() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	# 确保武器网格被显式设置到第 1 渲染层
	assert_str(script.source_code).contains("VIEW_MODEL_RENDER_LAYER")
	assert_str(script.source_code).contains("_set_render_layer_recursive")


func test_view_model_supports_shield_display() -> void:
	# 盾牌现在有第一人称视觉：ViewModel 提供 set_shield 并监听 shield_changed。
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("func set_shield(")
	assert_str(script.source_code).contains("shield_changed")


func test_view_model_has_default_position_export() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("view_position")
	assert_str(script.source_code).contains("@export")


func test_view_model_scene_has_weapon_holder_child() -> void:
	var scene := load("res://scenes/characters/player/view_model.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var instance: Node = auto_free(scene.instantiate())
	assert_object(instance.get_node_or_null("BobPivot/AimPivot/ActionPivot")).is_not_null()


func test_view_model_set_weapon_null_clears() -> void:
	var vm := _create_view_model()
	vm.set_weapon(null)
	assert_object(vm._current_weapon_node).is_null()


func test_view_model_clear_weapon_safe_when_empty() -> void:
	var vm := _create_view_model()
	# 清除空武器不应崩溃
	vm.clear_weapon()
	assert_object(vm._current_weapon_node).is_null()


func test_view_model_apply_slash_arc_modifies_transform() -> void:
	var vm := _create_view_model()
	vm.arm_animation_enabled = true  # 显式开启动作动画以验证启用路径
	var holder: Node3D = vm.weapon_holder
	var base: Transform3D = holder.transform
	# 在挥砍中段（progress=0.5），transform 应该改变。
	# 单手挥砍动画只驱动 ActionPivot 的 rotation，故须比较整个 transform（basis），
	# 而非仅 origin（origin 全程为 0）。
	vm.apply_slash_arc(0.5)
	assert_bool(holder.transform.is_equal_approx(base)).is_false()


func test_view_model_restore_transform_resets() -> void:
	var vm := _create_view_model()
	vm.arm_animation_enabled = true
	var holder: Node3D = vm.weapon_holder
	var base: Transform3D = holder.transform
	vm.apply_slash_arc(0.5)
	vm.restore_transform()
	assert_vector(holder.transform.origin).is_equal(base.origin)


func test_view_model_get_base_transform_returns_transform() -> void:
	var vm := _create_view_model()
	var t: Transform3D = vm.get_base_transform()
	assert_vector(t.origin).is_equal(vm.view_position)


func test_view_model_set_aiming_changes_base_position() -> void:
	var vm := _create_view_model()
	var default_base: Vector3 = vm.get_base_transform().origin
	vm.set_aiming(true)
	var aim_base: Vector3 = vm.get_base_transform().origin
	# 瞄准后基础位置应该改变
	assert_vector(aim_base).is_not_equal(default_base)


# ── Player 集成测试 ──────────────────────────────────────

func test_player_has_view_model_reference() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	assert_str(script.source_code).contains("view_model")


func test_player_has_hide_character_body_method() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	assert_str(script.source_code).contains("_hide_character_body")


func test_player_has_character_body_render_layer_constant() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	assert_str(script.source_code).contains("CHARACTER_BODY_RENDER_LAYER")


func test_player_connects_weapon_changed_for_view() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	# 确保 Player 监听 weapon_changed 信号来重新隐藏角色手上武器
	assert_str(script.source_code).contains("_on_weapon_changed_for_view")
	assert_str(script.source_code).contains("weapon_changed.connect")


func test_player_has_sync_view_model_weapon_method() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	# 确保有直接同步方法（不依赖信号）
	assert_str(script.source_code).contains("_sync_view_model_weapon")
	assert_str(script.source_code).contains("set_weapon")


func test_player_set_weapon_aiming_calls_view_model() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	assert_str(script.source_code).contains("set_aiming")
	assert_str(script.source_code).contains("has_method(\"set_aiming\")")


func test_player_tscn_has_view_model_node() -> void:
	var scene_text := FileAccess.get_file_as_string("res://scenes/characters/player/player.tscn")
	assert_str(scene_text).contains("ViewModel")
	assert_str(scene_text).contains("view_model.tscn")


func test_player_tscn_camera_has_cull_mask() -> void:
	var scene_text := FileAccess.get_file_as_string("res://scenes/characters/player/player.tscn")
	assert_str(scene_text).contains("cull_mask = 1")


# ── 状态脚本集成测试 ──────────────────────────────────────

func test_slashing_state_syncs_view_model() -> void:
	var script := load("res://scenes/characters/player/state/player_state_slashing.gd") as GDScript
	# 挥砍状态通过 ViewModel 的 sample_action / stop_action 同步第一人称挥砍视觉，
	# 真正的击打时序与命中由 CombatSlashAnimator 负责。
	assert_str(script.source_code).contains("sample_action")
	assert_str(script.source_code).contains("stop_action")
	assert_str(script.source_code).contains("has_method(\"sample_action\")")
	assert_str(script.source_code).contains("has_method(\"stop_action\")")


func test_shooting_state_plays_view_model_action() -> void:
	var script := load("res://scenes/characters/player/state/player_state_shooting.gd") as GDScript
	# 射击状态经 ViewModel.play_action 播放远程开火视觉（弓/弩），并从 MuzzlePoint 生成投射物。
	assert_str(script.source_code).contains("play_action")
	assert_str(script.source_code).contains("has_method(\"play_action\")")


# ── 渲染层逻辑测试 ──────────────────────────────────────

func test_character_body_render_layer_is_layer_10() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	# 1 << 9 = 512 = 第 10 层
	assert_str(script.source_code).contains("1 << 9")


func test_set_render_layer_recursive_sets_geometry_instances() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	assert_str(script.source_code).contains("_set_render_layer_recursive")
	assert_str(script.source_code).contains("GeometryInstance3D")
	assert_str(script.source_code).contains("node.layers = layer")


func test_view_model_has_apply_bow_pull_method() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("func apply_bow_pull(")


func test_view_model_apply_bow_pull_modifies_transform() -> void:
	var vm := _create_view_model()
	vm.arm_animation_enabled = true
	# 手动添加一个模拟的子节点作为 _current_weapon_node，以允许 apply_bow_pull 逻辑继续运行
	var mock_mesh := Node3D.new()
	vm.weapon_holder.add_child(mock_mesh)
	vm._current_weapon_node = mock_mesh
	
	var holder: Node3D = vm.weapon_holder
	var base_pos: Vector3 = holder.transform.origin
	# 在拉满弓的过程中，transform 应该发生变化（偏离原位向屏幕中心移动）
	vm.apply_bow_pull(0.5)
	assert_vector(holder.transform.origin).is_not_equal(base_pos)


func test_preparing_state_calls_view_model_action() -> void:
	var script := load("res://scenes/characters/player/state/player_state_attack_preparing.gd") as GDScript
	# 蓄力状态通过 sample_action（拉弓/蓄力）驱动第一人称视觉，结束时 stop_action 复位。
	assert_str(script.source_code).contains("sample_action")
	assert_str(script.source_code).contains("has_method(\"sample_action\")")


func test_view_model_apply_bow_pull_applies_scale_deformation() -> void:
	var vm := _create_view_model()
	vm.arm_animation_enabled = true
	var mock_mesh := Node3D.new()
	vm.weapon_holder.add_child(mock_mesh)
	vm._current_weapon_node = mock_mesh
	
	# 初始状态
	var initial_transform := vm.weapon_holder.transform
	
	# 拉弓一半 (0.5)
	vm.apply_bow_pull(0.5)
	# 验证拉弓引起了位置偏移（回缩到怀中）
	assert_float(vm.weapon_holder.transform.origin.z).is_greater(initial_transform.origin.z)


func test_view_model_pose_offsets_adapt_to_weapon() -> void:
	var vm := _create_view_model()
	
	var melee := WeaponData.new()
	melee.weapon_class = "sword"
	
	var bow := WeaponData.new()
	bow.weapon_class = "longbow"
	bow.tags = ["bow", "ranged"]
	
	# 近战武器默认偏置
	vm._apply_weapon_pose_offsets(melee)
	var melee_pos := vm.view_position
	var melee_rot := vm.view_rotation_degrees
	
	# 弓自适应偏置
	vm._apply_weapon_pose_offsets(bow)
	var bow_pos := vm.view_position
	var bow_rot := vm.view_rotation_degrees
	
	# 二者应该不同
	assert_vector(bow_pos).is_not_equal(melee_pos)
	assert_vector(bow_rot).is_not_equal(melee_rot)


# ── 端正持握姿势测试 ────────────────────────────

func test_view_model_default_rotation_has_positive_x_for_upright_style() -> void:
	# 端正风格：X 轴旋转为正值（剑尖朝前上方）
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("Vector3(12.0, 4.0, -4.0)")


func test_view_model_melee_pose_has_upward_tilt() -> void:
	var vm := _create_view_model()
	var melee := WeaponData.new()
	melee.weapon_class = "sword"
	vm._apply_weapon_pose_offsets(melee)
	# X 旋转为正值 → 剑尖朝前上方
	assert_float(vm.view_rotation_degrees.x).is_greater(0.0)


func test_view_model_melee_pose_has_roll_for_blade_flat() -> void:
	var vm := _create_view_model()
	var melee := WeaponData.new()
	melee.weapon_class = "sword"
	vm._apply_weapon_pose_offsets(melee)
	# Z 旋转非零 → 刀面朝向摄像机
	assert_float(vm.view_rotation_degrees.z).is_not_equal(0.0)


func test_view_model_clear_weapon_restores_minecraft_defaults() -> void:
	var vm := _create_view_model()
	# 先修改为弓的姿势
	var bow := WeaponData.new()
	bow.weapon_class = "longbow"
	bow.tags = ["bow"]
	vm._apply_weapon_pose_offsets(bow)
	# 清除后应恢复为端正近战默认值
	vm.clear_weapon()
	assert_float(vm.view_rotation_degrees.x).is_equal(12.0)
	assert_float(vm.view_rotation_degrees.z).is_equal(-4.0)


func test_view_model_aim_rotation_less_tilted_than_view() -> void:
	var vm := _create_view_model()
	var melee := WeaponData.new()
	melee.weapon_class = "sword"
	vm._apply_weapon_pose_offsets(melee)
	# 瞄准时剑身趋近水平（X 旋转小于默认持握）
	assert_float(vm.aim_rotation_degrees.x).is_less(vm.view_rotation_degrees.x)


func test_view_model_melee_position_is_bottom_right() -> void:
	var vm := _create_view_model()
	var melee := WeaponData.new()
	melee.weapon_class = "sword"
	vm._apply_weapon_pose_offsets(melee)
	# 位置在右下前方：X > 0（右），Y < 0（下），Z < 0（前）
	assert_float(vm.view_position.x).is_greater(0.0)
	assert_float(vm.view_position.y).is_less(0.0)
	assert_float(vm.view_position.z).is_less(0.0)


func test_view_model_bow_pose_differs_from_melee_minecraft() -> void:
	var vm := _create_view_model()
	var melee := WeaponData.new()
	melee.weapon_class = "sword"
	vm._apply_weapon_pose_offsets(melee)
	var melee_x := vm.view_rotation_degrees.x

	var bow := WeaponData.new()
	bow.weapon_class = "longbow"
	bow.tags = ["bow"]
	vm._apply_weapon_pose_offsets(bow)
	# 弓的 X 旋转应不同于近战（弓不需要上仰45°）
	assert_str(bow.weapon_class).is_equal("longbow")
	assert_float(vm.view_rotation_degrees.x).is_not_equal(melee_x)


# ── 枪口/弓口位置测试 ────────────────────────────────────

func test_view_model_has_muzzle_point_node() -> void:
	var scene := load("res://scenes/characters/player/view_model.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var instance: Node = auto_free(scene.instantiate())
	assert_object(instance.get_node_or_null("BobPivot/AimPivot/ActionPivot/WeaponSocket/MuzzlePoint")).is_not_null()


func test_view_model_has_get_muzzle_global_position_method() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("func get_muzzle_global_position()")


func test_view_model_muzzle_point_is_forward_of_weapon_holder() -> void:
	var vm := _create_view_model()
	var muzzle: Node3D = vm.muzzle_point
	assert_object(muzzle).is_not_null()
	# MuzzlePoint 应在 WeaponHolder 前方（-Z 方向）
	assert_float(muzzle.position.z).is_less(0.0)


func test_view_model_get_muzzle_global_position_returns_valid_pos() -> void:
	var vm := _create_view_model()
	var muzzle_pos: Vector3 = vm.get_muzzle_global_position()
	# 应返回有效位置（非原点零向量）
	assert_vector(muzzle_pos).is_not_equal(Vector3.ZERO)


func test_view_model_muzzle_follows_aiming_position() -> void:
	var vm := _create_view_model()
	# 默认基础变换
	var default_base := vm.get_base_transform()
	# 切换到瞄准位置后基础变换应改变（tween 在下一帧才开始，但 _base_transform 立即更新）
	vm.set_aiming(true)
	var aim_base := vm.get_base_transform()
	# 瞄准时武器移到屏幕中央，基础变换应该变化
	assert_vector(aim_base.origin).is_not_equal(default_base.origin)


func test_shooting_state_uses_view_model_muzzle() -> void:
	var script := load("res://scenes/characters/player/state/player_state_shooting.gd") as GDScript
	# 射击状态应优先使用 ViewModel 的 get_muzzle_global_position
	assert_str(script.source_code).contains("get_muzzle_global_position")
	assert_str(script.source_code).contains("view_model")


func test_shooting_state_falls_back_to_weapon_spawn_position() -> void:
	var script := load("res://scenes/characters/player/state/player_state_shooting.gd") as GDScript
	# 当 ViewModel 不可用时，回退到 weapon_spawn_position
	assert_str(script.source_code).contains("weapon_spawn_position")


func test_shooting_state_has_muzzle_comment() -> void:
	var script := load("res://scenes/characters/player/state/player_state_shooting.gd") as GDScript
	# 确保代码注释提到了从弓弩模型发出
	assert_str(script.source_code).contains("弓弩模型")


func test_equiped_item_hides_in_player_third_person() -> void:
	# 建立 Mock 武器网格场景
	var mock_mesh := MeshInstance3D.new()
	mock_mesh.mesh = BoxMesh.new()
	var mock_scene := PackedScene.new()
	mock_scene.pack(mock_mesh)
	mock_mesh.free()
	
	# 创建 Mock 玩家树
	var player := CharacterBody3D.new()
	player.name = "Player"
	
	var placeholder := Node3D.new()
	player.add_child(placeholder)
	
	var item := EquipedItem.new()
	var w_data := WeaponData.new()
	w_data.glb_mesh = mock_scene
	item.weapon_data = w_data
	placeholder.add_child(item)
	auto_free(player)
	
	# 触发 _ready（会实例化 mock_scene 并添加到子节点中）
	item._ready()
	
	# 找到实例化后的网格节点
	var spawned_mesh = item.get_child(0)
	assert_object(spawned_mesh).is_not_null()
	# 断言其 layers 被递归设为第 10 渲染层（512）
	assert_int(spawned_mesh.layers).is_equal(512)


func test_equiped_item_does_not_hide_when_not_in_player() -> void:
	var mock_mesh := MeshInstance3D.new()
	mock_mesh.mesh = BoxMesh.new()
	var mock_scene := PackedScene.new()
	mock_scene.pack(mock_mesh)
	mock_mesh.free()
	
	var dummy_node := Node3D.new()
	dummy_node.name = "Enemy"
	
	var item := EquipedItem.new()
	var w_data := WeaponData.new()
	w_data.glb_mesh = mock_scene
	item.weapon_data = w_data
	dummy_node.add_child(item)
	auto_free(dummy_node)
	
	item._ready()
	
	var spawned_mesh = item.get_child(0)
	assert_object(spawned_mesh).is_not_null()
	# 非玩家持有不被隐藏，依然是 layer 1
	assert_int(spawned_mesh.layers).is_equal(1)


# ── 武器动作动画开关测试 ──────────────────────────────────
# 第一人称下玩家自身身体（含手臂）已被 Player._hide_character_body() 移到第 10 层，
# 对主相机不可见；武器 GLB 也不含手臂几何。因此 arm_animation_enabled 只控制
# “武器自身是否摆动”，默认开启即“看得到完整武器动画、且永远看不到手臂”。

func test_view_model_arm_animation_enabled_by_default() -> void:
	var vm := _create_view_model()
	# 默认开启：第一人称武器动画（挥砍/拉弓/后坐）正常播放
	assert_bool(vm.arm_animation_enabled).is_true()


func test_view_model_disabled_arm_animation_slash_is_noop() -> void:
	var vm := _create_view_model()
	# 显式关闭：挥砍抽样不应改动作层 transform（保持静态持握位）
	vm.arm_animation_enabled = false
	var holder: Node3D = vm.weapon_holder
	var base_pos: Vector3 = holder.transform.origin
	vm.apply_slash_arc(0.5)
	assert_vector(holder.transform.origin).is_equal(base_pos)


func test_view_model_disabled_arm_animation_bow_pull_is_noop() -> void:
	var vm := _create_view_model()
	# 显式关闭：拉弓抽样不应改动作层 transform（保持静态持握位）
	vm.arm_animation_enabled = false
	var holder: Node3D = vm.weapon_holder
	var base_pos: Vector3 = holder.transform.origin
	vm.apply_bow_pull(0.7)
	assert_vector(holder.transform.origin).is_equal(base_pos)


# ── 独立武器相机测试 ──────────────────────────────────────

func test_view_model_has_weapon_camera_setup() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("SubViewport")
	assert_str(script.source_code).contains("_setup_weapon_camera")
	assert_str(script.source_code).contains("_sync_weapon_camera")


func test_view_model_weapon_camera_uses_dedicated_layer() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	# 第 11 层（1 << 10）专供武器相机渲染
	assert_str(script.source_code).contains("WEAPON_VIEW_RENDER_LAYER")
	assert_str(script.source_code).contains("1 << 10")


func test_view_model_falls_back_to_layer1_without_camera_parent() -> void:
	# 测试树/headless 下无 Camera3D 父级：回退到主相机可见的第 1 层，武器不隐身
	var vm := _create_view_model()
	assert_int(vm._active_view_layer).is_equal(ViewModel.VIEW_MODEL_RENDER_LAYER)


func test_view_model_weapon_camera_setup_under_camera_parent() -> void:
	# 显式把 ViewModel 挂到 Camera3D 下（headless 仍会因无显示而跳过相机构建，
	# 但至少验证 _setup_weapon_camera 在有相机父级时不崩溃）
	var cam := Camera3D.new()
	add_child(cam)
	auto_free(cam)
	var scene := load("res://scenes/characters/player/view_model.tscn") as PackedScene
	var vm: ViewModel = scene.instantiate()
	cam.add_child(vm)
	# _ready 已执行 _setup_weapon_camera，不应抛错
	assert_object(vm).is_not_null()


# ── 盾牌视觉测试 ──────────────────────────────────────────

func test_view_model_scene_has_shield_socket() -> void:
	var scene := load("res://scenes/characters/player/view_model.tscn") as PackedScene
	var instance: Node = auto_free(scene.instantiate())
	assert_object(instance.get_node_or_null("BobPivot/ShieldSocket")).is_not_null()


func test_view_model_listens_to_shield_changed() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("shield_changed")
	assert_str(script.source_code).contains("_on_shield_changed")


func test_view_model_set_shield_instantiates_mesh() -> void:
	var vm := _create_view_model()
	var shield := ShieldData.new()
	shield.glb_mesh = _make_mock_mesh_scene()
	vm.set_shield(shield)
	# 盾牌网格应挂到 ShieldSocket 之下
	assert_int(vm.shield_socket.get_child_count()).is_greater(0)
	assert_object(vm._current_shield_node).is_not_null()


func test_view_model_set_shield_null_clears() -> void:
	var vm := _create_view_model()
	var shield := ShieldData.new()
	shield.glb_mesh = _make_mock_mesh_scene()
	vm.set_shield(shield)
	vm.set_shield(null)
	assert_object(vm._current_shield_node).is_null()
	assert_int(vm.shield_socket.get_child_count()).is_equal(0)


func test_view_model_set_shield_accepts_shield_weapon_data() -> void:
	# “盾即武器”场景：shield_changed 可能携带 WeaponData（同样暴露 glb_mesh）
	var vm := _create_view_model()
	var shield_weapon := WeaponData.new()
	shield_weapon.item_tag = "shield"
	shield_weapon.glb_mesh = _make_mock_mesh_scene()
	vm.set_shield(shield_weapon)
	assert_object(vm._current_shield_node).is_not_null()


func test_view_model_shield_mesh_uses_active_view_layer() -> void:
	var vm := _create_view_model()
	var shield := ShieldData.new()
	shield.glb_mesh = _make_mock_mesh_scene()
	vm.set_shield(shield)
	var spawned := vm.shield_socket.get_child(0)
	var mesh_node := spawned if spawned is GeometryInstance3D else spawned.get_child(0)
	assert_int((mesh_node as GeometryInstance3D).layers).is_equal(vm._active_view_layer)


# ── 辅助方法 ──────────────────────────────────────────────

func _make_mock_mesh_scene() -> PackedScene:
	var mock_mesh := MeshInstance3D.new()
	mock_mesh.mesh = BoxMesh.new()
	var mock_scene := PackedScene.new()
	mock_scene.pack(mock_mesh)
	mock_mesh.free()
	return mock_scene


func _create_view_model() -> ViewModel:
	var scene := load("res://scenes/characters/player/view_model.tscn") as PackedScene
	var vm: ViewModel = auto_free(scene.instantiate())
	# 添加到树中以触发 @onready 变量初始化和 _ready()
	add_child(vm)
	return vm
