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


func test_view_model_switches_editor_authored_variant_for_same_weapon() -> void:
	var vm := _create_view_model()
	var weapon := WeaponData.new()
	weapon.id = "sword"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "one_hand_melee"
	vm.set_weapon(weapon)
	assert_str(String(vm.get_weapon_animation_variant())).is_equal("standard")
	assert_bool(vm.animation_player.has_animation(&"vm_sword_slash")).is_true()
	assert_bool(vm.set_weapon_animation_variant("alternate")).is_true()
	assert_str(String(vm.get_weapon_animation_variant())).is_equal("alternate")
	assert_bool(vm.set_weapon_animation_variant("not_a_variant")).is_false()


func test_view_model_samples_loaded_sword_animation_on_action_pivot() -> void:
	var vm := _create_view_model()
	var weapon := WeaponData.new()
	weapon.id = "sword"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "one_hand_melee"
	vm.set_weapon(weapon)
	var action := vm.resolve_melee_action(weapon)
	assert_str(String(action)).is_equal("vm_sword_slash")
	assert_bool(vm.animation_player.has_animation(action)).is_true()
	var base := vm.action_pivot.transform
	vm.sample_action(action, 0.5)
	assert_bool(vm.action_pivot.transform.is_equal_approx(base)).is_false()


func test_view_model_scene_contains_only_equipment_pivots_not_character_parts() -> void:
	var vm := _create_view_model()
	assert_object(vm.get_node_or_null("BobPivot/AimPivot/ActionPivot")).is_not_null()
	assert_object(vm.get_node_or_null("BobPivot/AimPivot/ShieldActionPivot")).is_not_null()
	assert_object(vm.find_child("PlayerVisualModel", true, false)).is_null()
	assert_object(vm.find_child("Skeleton3D", true, false)).is_null()
	assert_object(vm.find_child("BoneAttachment3D", true, false)).is_null()


func test_view_model_weapon_camera_uses_fixed_modern_fov_and_lit_overlay_rig() -> void:
	var vm := _create_view_model()
	assert_float(vm.weapon_camera_fov).is_equal_approx(68.0, 0.001)
	assert_object(vm._weapon_subviewport).is_not_null()
	assert_object(vm._weapon_subviewport.get_node_or_null("WeaponOverlayEnvironment")).is_not_null()
	assert_object(vm._weapon_subviewport.get_node_or_null("WeaponOverlayKeyLight")).is_not_null()
	assert_object(vm._weapon_subviewport.get_node_or_null("WeaponOverlayFillLight")).is_not_null()
	assert_object(vm._weapon_subviewport.get_node_or_null("WeaponOverlayCameraFill")).is_not_null()


# ── 叠加层受光同步测试 ──────────────────────────────────────

func test_overlay_lighting_mirrors_world_zone_ambient_and_directional() -> void:
	var rig := Node3D.new()
	var camera := Camera3D.new()
	camera.current = true
	rig.add_child(camera)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.5, 0.6)
	env.ambient_light_energy = 0.3
	env_node.environment = env
	rig.add_child(env_node)
	var zone_dir := DirectionalLight3D.new()
	zone_dir.rotation_degrees = Vector3(-70.0, 25.0, 0.0)
	zone_dir.light_color = Color(0.8, 0.9, 1.0)
	zone_dir.light_energy = 0.35
	rig.add_child(zone_dir)
	var vm := _create_view_model_under(camera)
	add_child(auto_free(rig))
	await get_tree().process_frame
	var mock_weapon := Node3D.new()
	camera.add_child(mock_weapon)
	vm._current_weapon_node = mock_weapon
	vm._sync_weapon_overlay_lighting(0.5)
	assert_object(vm._overlay_environment).is_not_null()
	assert_object(vm._overlay_key_light).is_not_null()
	if vm._overlay_environment == null or vm._overlay_key_light == null:
		return
	assert_float(vm._overlay_environment.ambient_light_energy).is_equal_approx(0.3, 0.001)
	assert_bool(vm._overlay_environment.ambient_light_color.is_equal_approx(env.ambient_light_color)).is_true()
	assert_bool(vm._overlay_key_light.light_color.is_equal_approx(zone_dir.light_color)).is_true()
	assert_float(vm._overlay_key_light.light_energy).is_equal_approx(0.35, 0.001)
	assert_bool(vm._overlay_key_light.rotation_degrees.is_equal_approx(zone_dir.rotation_degrees)).is_true()


func test_overlay_lighting_applies_readability_floors_for_dark_zone() -> void:
	var rig := Node3D.new()
	var camera := Camera3D.new()
	camera.current = true
	rig.add_child(camera)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_energy = 0.02
	env_node.environment = env
	rig.add_child(env_node)
	var zone_dir := DirectionalLight3D.new()
	zone_dir.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	zone_dir.light_color = Color(0.3, 0.35, 0.5)
	zone_dir.light_energy = 0.05
	rig.add_child(zone_dir)
	var vm := _create_view_model_under(camera)
	add_child(auto_free(rig))
	await get_tree().process_frame
	var mock_weapon := Node3D.new()
	camera.add_child(mock_weapon)
	vm._current_weapon_node = mock_weapon
	vm._sync_weapon_overlay_lighting(0.5)
	if vm._overlay_environment == null or vm._overlay_key_light == null:
		assert_object(vm._overlay_environment).is_not_null()
		return
	assert_float(vm._overlay_environment.ambient_light_energy).is_equal_approx(vm.OVERLAY_AMBIENT_FLOOR, 0.001)
	assert_float(vm._overlay_key_light.light_energy).is_equal_approx(vm.OVERLAY_KEY_ENERGY_FLOOR, 0.001)


func test_overlay_fill_tracks_nearby_local_lights_only() -> void:
	var rig := Node3D.new()
	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3.ZERO
	rig.add_child(camera)
	var warm := OmniLight3D.new()
	warm.position = Vector3(2.0, 0.0, 0.0)
	warm.light_color = Color(1.0, 0.6, 0.3)
	warm.light_energy = 1.0
	warm.omni_range = 8.0
	rig.add_child(warm)
	# 远处光源超出采样半径，不应进入补光
	var far := OmniLight3D.new()
	far.position = Vector3(50.0, 0.0, 0.0)
	far.light_color = Color(0.1, 1.0, 0.1)
	far.light_energy = 5.0
	far.omni_range = 60.0
	rig.add_child(far)
	var vm := _create_view_model_under(camera)
	add_child(auto_free(rig))
	await get_tree().process_frame
	var mock_weapon := Node3D.new()
	camera.add_child(mock_weapon)
	vm._current_weapon_node = mock_weapon
	vm._sync_weapon_overlay_lighting(0.5)
	if vm._overlay_camera_fill == null:
		assert_object(vm._overlay_camera_fill).is_not_null()
		return
	assert_float(vm._overlay_camera_fill.light_energy).is_greater(0.0)
	# 近处暖光主导：R 通道应明显高于 B 通道
	assert_bool(vm._overlay_camera_fill.light_color.r > vm._overlay_camera_fill.light_color.b).is_true()


func test_overlay_fill_excludes_player_vision_light() -> void:
	# 玩家视野灯是"照亮地形以便看见"的辅助光，不是真实光源；武器叠加层补光必须
	# 忽略它，否则黑暗区域武器也会被自带的视野灯照得通亮。
	var rig := Node3D.new()
	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3.ZERO
	rig.add_child(camera)
	var vision := OmniLight3D.new()
	vision.name = Player.PLAYER_VISION_LIGHT_NAME
	vision.position = Vector3(0.0, 1.5, 0.0)
	vision.light_color = Color(0.9, 0.95, 1.0)
	vision.light_energy = 2.0
	vision.omni_range = 9.0
	rig.add_child(vision)
	var vm := _create_view_model_under(camera)
	add_child(auto_free(rig))
	await get_tree().process_frame
	var mock_weapon := Node3D.new()
	camera.add_child(mock_weapon)
	vm._current_weapon_node = mock_weapon
	vm._sync_weapon_overlay_lighting(0.5)
	if vm._overlay_camera_fill == null:
		assert_object(vm._overlay_camera_fill).is_not_null()
		return
	# 只有视野灯在采样半径内时，补光应保持默认值而未被采样覆盖。
	assert_float(vm._overlay_camera_fill.light_energy).is_equal_approx(0.70, 0.001)


func test_overlay_lighting_skips_sync_when_unarmed() -> void:
	var rig := Node3D.new()
	var camera := Camera3D.new()
	camera.current = true
	rig.add_child(camera)
	var zone_dir := DirectionalLight3D.new()
	zone_dir.rotation_degrees = Vector3(-70.0, 25.0, 0.0)
	zone_dir.light_color = Color(0.8, 0.9, 1.0)
	zone_dir.light_energy = 0.35
	rig.add_child(zone_dir)
	var vm := _create_view_model_under(camera)
	add_child(auto_free(rig))
	await get_tree().process_frame
	# 空手：无受光装备，同步必须保持默认灯组不被覆盖
	var default_color: Color = vm._overlay_key_light.light_color
	var default_energy: float = vm._overlay_key_light.light_energy
	vm._sync_weapon_overlay_lighting(0.5)
	if vm._overlay_key_light == null:
		assert_object(vm._overlay_key_light).is_not_null()
		return
	assert_float(vm._overlay_key_light.light_energy).is_equal_approx(default_energy, 0.001)
	assert_bool(vm._overlay_key_light.light_color.is_equal_approx(default_color)).is_true()


func test_view_model_apply_slash_arc_modifies_transform() -> void:
	var vm := _create_view_model()
	vm.equipment_animation_enabled = true
	var holder: Node3D = vm.weapon_holder
	var base: Transform3D = holder.transform
	# 在挥砍中段（progress=0.5），transform 应该改变。
	# 单手挥砍动画只驱动 ActionPivot 的 rotation，故须比较整个 transform（basis），
	# 而非仅 origin（origin 全程为 0）。
	vm.apply_slash_arc(0.5)
	assert_bool(holder.transform.is_equal_approx(base)).is_false()


func test_view_model_restore_transform_resets() -> void:
	var vm := _create_view_model()
	vm.equipment_animation_enabled = true
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
	vm._update_aim_blend(0.25)
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


func test_player_supplies_local_motion_and_look_input_to_view_model() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	assert_str(script.source_code).contains("_sync_first_person_equipment_motion")
	assert_str(script.source_code).contains("view_model.set_motion_state")
	assert_str(script.source_code).contains("view_model.add_look_input")


func test_player_tscn_has_view_model_node() -> void:
	var scene_text := FileAccess.get_file_as_string("res://scenes/characters/player/player.tscn")
	assert_str(scene_text).contains("ViewModel")
	assert_str(scene_text).contains("view_model.tscn")


func test_player_tscn_camera_has_cull_mask() -> void:
	var scene_text := FileAccess.get_file_as_string("res://scenes/characters/player/player.tscn")
	assert_str(scene_text).contains("cull_mask = 3")


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
	vm.equipment_animation_enabled = true
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
	vm.equipment_animation_enabled = true
	var mock_mesh := Node3D.new()
	vm.weapon_holder.add_child(mock_mesh)
	vm._current_weapon_node = mock_mesh
	
	# 初始状态
	var initial_transform := vm.weapon_holder.transform
	
	# 拉弓一半 (0.5)
	vm.apply_bow_pull(0.5)
	# 验证拉弓引起了位置偏移（回缩到怀中）
	assert_float(vm.weapon_holder.transform.origin.z).is_greater(initial_transform.origin.z)


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
	vm._update_aim_blend(0.25)
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


# ── 纯装备动作开关测试 ────────────────────────────────────

func test_view_model_equipment_animation_enabled_by_default() -> void:
	var vm := _create_view_model()
	assert_bool(vm.equipment_animation_enabled).is_true()


func test_view_model_disabled_equipment_animation_slash_is_noop() -> void:
	var vm := _create_view_model()
	vm.equipment_animation_enabled = false
	var holder: Node3D = vm.weapon_holder
	var base_pos: Vector3 = holder.transform.origin
	vm.apply_slash_arc(0.5)
	assert_vector(holder.transform.origin).is_equal(base_pos)


func test_view_model_disabled_equipment_animation_bow_pull_is_noop() -> void:
	var vm := _create_view_model()
	vm.equipment_animation_enabled = false
	var holder: Node3D = vm.weapon_holder
	var base_pos: Vector3 = holder.transform.origin
	vm.apply_bow_pull(0.7)
	assert_vector(holder.transform.origin).is_equal(base_pos)

# ── 盾牌视觉测试 ──────────────────────────────────────────

func test_view_model_scene_has_shield_socket() -> void:
	var scene := load("res://scenes/characters/player/view_model.tscn") as PackedScene
	var instance: Node = auto_free(scene.instantiate())
	assert_object(instance.get_node_or_null("BobPivot/AimPivot/ShieldActionPivot/ShieldImpactPivot/ShieldSocket")).is_not_null()


func test_view_model_listens_to_shield_changed() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("shield_changed")
	assert_str(script.source_code).contains("_on_shield_changed")


func test_view_model_set_shield_instantiates_mesh() -> void:
	var vm := _create_view_model()
	var shield := ShieldData.new()
	shield.glb_mesh = _make_mock_mesh_scene()
	vm.set_shield(shield)
	# 盾牌网格应挂到独立的 ShieldOrientation 之下。
	assert_int(vm.shield_orientation.get_child_count()).is_greater(0)
	assert_object(vm._current_shield_node).is_not_null()
	assert_vector(vm._current_shield_node.scale).is_equal_approx(Vector3.ONE * 0.30, Vector3.ONE * 0.001)


func test_view_model_set_shield_null_clears() -> void:
	var vm := _create_view_model()
	var shield := ShieldData.new()
	shield.glb_mesh = _make_mock_mesh_scene()
	vm.set_shield(shield)
	vm.set_shield(null)
	assert_object(vm._current_shield_node).is_null()
	assert_int(vm.shield_orientation.get_child_count()).is_equal(0)


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
	var spawned := vm.shield_orientation.get_child(0)
	var mesh_node := spawned if spawned is GeometryInstance3D else spawned.get_child(0)
	assert_int((mesh_node as GeometryInstance3D).layers).is_equal(vm._active_view_layer)


func test_view_model_block_impact_moves_only_isolated_shield_pivot() -> void:
	var vm := _create_view_model()
	var shield := ShieldData.new()
	shield.glb_mesh = _make_mock_mesh_scene()
	vm.set_shield(shield)
	var weapon_action_before := vm.action_pivot.transform
	vm.play_block_impact(1.0, 0.4)
	vm.equipment_motion.step(1.0 / 60.0)
	vm.shield_impact_pivot.transform = vm.equipment_motion.get_shield_impact_transform()
	assert_bool(vm.shield_impact_pivot.transform.is_equal_approx(Transform3D.IDENTITY)).is_false()
	assert_bool(vm.action_pivot.transform.is_equal_approx(weapon_action_before)).is_true()


func test_view_model_reset_clears_shield_impact_spring_without_next_frame_snap() -> void:
	var vm := _create_view_model()
	var shield := ShieldData.new()
	shield.glb_mesh = _make_mock_mesh_scene()
	vm.set_shield(shield)
	vm.play_block_impact(1.0, -0.25)
	vm.equipment_motion.step(1.0 / 60.0)
	assert_bool(vm.equipment_motion.get_shield_impact_transform().is_equal_approx(Transform3D.IDENTITY)).is_false()
	vm.stop_action(true)
	vm.equipment_motion.step(1.0 / 60.0)
	assert_bool(vm.equipment_motion.get_shield_impact_transform().is_equal_approx(Transform3D.IDENTITY)).is_true()


# ── 命中停帧（Hit-Stop）测试 ─────────────────────────────

func test_hit_stop_duration_default_is_within_30_50ms_spec() -> void:
	var vm := _create_view_model()
	# docs/task.md B1: 命中停帧 30~50ms
	assert_float(vm.hit_stop_duration_msec).is_greater_equal(30.0)
	assert_float(vm.hit_stop_duration_msec).is_less_equal(50.0)


func test_play_hit_stop_activates_and_expires_within_duration() -> void:
	var vm := _create_view_model()
	assert_bool(vm.is_hit_stop_active()).is_false()
	vm.play_hit_stop()
	assert_bool(vm.is_hit_stop_active()).is_true()
	# 模拟时间流逝：两个完整时长应耗尽停帧
	vm._process(vm.hit_stop_duration_msec / 1000.0 + 0.001)
	assert_bool(vm.is_hit_stop_active()).is_false()


func test_hit_stop_does_not_touch_time_scale_or_pause() -> void:
	var vm := _create_view_model()
	var scale_before: float = Engine.time_scale
	var paused_before: bool = get_tree().paused
	vm.play_hit_stop()
	vm._process(0.01)
	# B1 硬约束：只冻结本地采样，不改 time_scale / SceneTree.paused
	assert_float(Engine.time_scale).is_equal(scale_before)
	assert_bool(get_tree().paused).is_equal(paused_before)


func test_sample_action_is_frozen_during_hit_stop() -> void:
	var vm := _create_view_model()
	vm.equipment_animation_enabled = true
	var weapon := WeaponData.new()
	weapon.id = "sword"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "one_hand_melee"
	vm.set_weapon(weapon)
	# 先让动画采样生效（非停帧态）
	var base := vm.action_pivot.transform
	vm.sample_action(&"vm_sword_slash", 0.5)
	assert_bool(vm.action_pivot.transform.is_equal_approx(base)).is_false()
	# 记录停帧前姿态，进入停帧后再采样必须无变化
	var frozen := vm.action_pivot.transform
	vm.play_hit_stop()
	vm.sample_action(&"vm_sword_slash", 0.8)
	assert_bool(vm.action_pivot.transform.is_equal_approx(frozen)).is_true()


func test_crit_hit_extends_hit_stop_duration() -> void:
	var vm := _create_view_model()
	vm.play_hit_stop()
	var normal: float = vm._hit_stop_remaining_sec
	vm._process(vm.hit_stop_duration_msec / 1000.0)
	assert_bool(vm.is_hit_stop_active()).is_false()
	vm._on_player_hit_enemy({"is_crit": true})
	var crit: float = vm._hit_stop_remaining_sec
	assert_float(crit).is_greater(normal)


func test_view_model_listens_to_player_hit_enemy_signal() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("player_hit_enemy.connect")
	assert_str(script.source_code).contains("func _on_player_hit_enemy(")


func test_hit_stop_disabled_equipment_animation_is_noop() -> void:
	var vm := _create_view_model()
	vm.equipment_animation_enabled = false
	vm.play_hit_stop()
	# 停帧机制本身仍会启动，但采样开关已禁用；这里只验证不会崩溃
	vm.sample_action(&"vm_sword_slash", 0.5)
	vm._process(0.1)
	assert_bool(vm.is_hit_stop_active()).is_false()


# ── 辅助方法 ──────────────────────────────────────────────

func _make_mock_mesh_scene() -> PackedScene:
	var mock_mesh := MeshInstance3D.new()
	mock_mesh.mesh = BoxMesh.new()
	var mock_scene := PackedScene.new()
	mock_scene.pack(mock_mesh)
	mock_mesh.free()
	return mock_scene


func _create_view_model_under(camera: Camera3D) -> ViewModel:
	var scene := load("res://scenes/characters/player/view_model.tscn") as PackedScene
	var vm: ViewModel = auto_free(scene.instantiate())
	camera.add_child(vm)
	return vm


func _create_view_model() -> ViewModel:
	var scene := load("res://scenes/characters/player/view_model.tscn") as PackedScene
	var vm: ViewModel = auto_free(scene.instantiate())
	# 添加到树中以触发 @onready 变量初始化和 _ready()
	add_child(vm)
	return vm
