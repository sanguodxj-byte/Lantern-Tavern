extends GdUnitTestSuite

func test_use_input_routes_pickable_focus_to_pickup_state() -> void:
	var source := _source("res://scenes/characters/player/state/player_state_moving.gd")
	assert_bool(source.contains('Input.is_action_just_pressed("use") and player.can_pickup_object()')) \
		.override_failure_message("移动状态必须用 E/use 检查当前可拾取物").is_true()
	assert_bool(source.contains("transition_state(Player.State.PICKING_UP)")) \
		.override_failure_message("E/use 命中可拾取物时必须进入 PICKING_UP 状态").is_true()


func test_pickup_state_equips_weapon_data_from_pickable_item() -> void:
	var source := _source("res://scenes/characters/player/state/player_state_picking_up.gd")
	assert_bool(source.contains("pickable_object.weapon_data != null")) \
		.override_failure_message("拾取状态必须识别 PickableItem.weapon_data").is_true()
	assert_bool(source.contains("player.equipment.equip_weapon(resolved_data")) \
		.override_failure_message("拾取武器必须调用玩家 EquipmentComponent.equip_weapon（使用解析后的完整数据）").is_true()
	assert_bool(source.contains("resolve_weapon_data")) \
		.override_failure_message("拾取武器前必须通过 WeaponRegistry.resolve_weapon_data 解析旧版 .tres 为完整数据").is_true()
	assert_bool(source.contains("pickable_object.queue_free()")) \
		.override_failure_message("拾取完成后场景物品必须移除").is_true()


func test_pickup_state_checks_equip_weapon_return_value() -> void:
	# 回归测试：装备失败时不应销毁物品，应回退到移动状态
	var source := _source("res://scenes/characters/player/state/player_state_picking_up.gd")
	assert_bool(source.contains("not player.equipment.equip_weapon")) \
		.override_failure_message("拾取状态必须检查 equip_weapon 返回值，失败时不销毁物品").is_true()
	assert_bool(source.contains("transition_state(Player.State.MOVING)")) \
		.override_failure_message("装备失败应回退到移动状态").is_true()


func test_focused_pickable_weapon_can_be_equipped_and_used_by_primary_attack() -> void:
	var player := _make_player_with_equipment()
	var pickable := PickableItem.new()
	pickable.weapon_data = _make_weapon("Pickup Sword", "one_hand_melee", "melee", "one_hand")
	player.current_pickable_focused_item = pickable
	assert_bool(player.can_pickup_object()).is_true()
	player.equipment.equip_weapon(pickable.weapon_data, Transform3D.IDENTITY)
	assert_bool(player.has_active_hand_equipment()).is_true()
	assert_int(player.get_primary_weapon_action_state()).is_equal(Player.State.ATTACK_PREPARING)
	assert_int(player.get_primary_weapon_release_state()).is_equal(Player.State.SLASHING)
	player.free()
	pickable.free()


func test_shield_in_hand_left_attacks_and_right_blocks() -> void:
	var player := _make_player_with_equipment()
	player.equipment.configure_weapon_slot(0, _make_shield("Buckler"), true)
	assert_bool(player.equipment.has_weapon()).is_false()
	assert_bool(player.has_active_hand_equipment()).is_true()
	assert_bool(player.equipment.has_shield()).is_true()
	assert_int(player.get_primary_weapon_action_state()).is_equal(Player.State.ATTACK_PREPARING)
	assert_int(player.get_primary_weapon_release_state()).is_equal(Player.State.SLASHING)
	assert_int(player.get_secondary_weapon_action_state()).is_equal(Player.State.BLOCKING)
	player.free()


func test_two_hand_weapon_left_attacks_and_right_blocks() -> void:
	var player := _make_player_with_equipment()
	player.equipment.configure_weapon_slot(0, _make_weapon("Greatsword", "two_hand", "melee", "two_hand"), true)
	assert_bool(player.is_active_weapon_two_handed()).is_true()
	assert_bool(player.can_block_with_active_equipment()).is_true()
	assert_int(player.get_primary_weapon_action_state()).is_equal(Player.State.ATTACK_PREPARING)
	assert_int(player.get_primary_weapon_release_state()).is_equal(Player.State.SLASHING)
	assert_int(player.get_secondary_weapon_action_state()).is_equal(Player.State.BLOCKING)
	player.free()


func test_ranged_weapon_left_shoots_and_right_aims() -> void:
	var player := _make_player_with_equipment()
	player.equipment.configure_weapon_slot(0, _make_weapon("Longbow", "longbow", "ranged", "two_hand"), true)
	assert_bool(player.is_active_weapon_ranged()).is_true()
	assert_bool(player.can_block_with_active_equipment()).is_false()
	assert_int(player.get_primary_weapon_action_state()).is_equal(Player.State.ATTACK_PREPARING)
	assert_int(player.get_primary_weapon_release_state()).is_equal(Player.State.SHOOTING)
	assert_int(player.get_secondary_weapon_action_state()).is_equal(Player.State.AIMING)
	player.free()


func test_dual_wield_one_hand_weapon_left_and_right_prepare_attacks() -> void:
	var player := _make_player_with_equipment()
	player.equipment.configure_weapon_slot(0, _make_weapon("Dagger", "one_hand_melee", "melee", "one_hand"), true)
	assert_bool(player.can_dual_wield_attack_with_active_equipment()).is_true()
	assert_int(player.get_primary_weapon_action_state()).is_equal(Player.State.ATTACK_PREPARING)
	assert_int(player.get_secondary_weapon_action_state()).is_equal(Player.State.ATTACK_PREPARING)
	assert_int(player.get_secondary_weapon_release_state()).is_equal(Player.State.SLASHING)
	assert_str(player.make_secondary_weapon_attack_data().weapon_input_action).is_equal("block")
	assert_str(player.make_secondary_weapon_attack_data().weapon_attack_hand).is_equal("secondary")
	player.free()


func test_attack_input_is_hold_then_release_instead_of_click_attack() -> void:
	var moving_source := _source("res://scenes/characters/player/state/player_state_moving.gd")
	var prepare_source := _source("res://scenes/characters/player/state/player_state_attack_preparing.gd")
	assert_bool(moving_source.contains("make_primary_weapon_attack_data()")) \
		.override_failure_message("移动状态按下攻击键时必须进入攻击准备数据流").is_true()
	assert_bool(prepare_source.contains("Input.is_action_pressed(input_action)")) \
		.override_failure_message("攻击准备状态必须在按住时保持，不得点击即攻击").is_true()
	assert_bool(prepare_source.contains("transition_state(release_state, state_data)")) \
		.override_failure_message("攻击准备状态必须在释放后进入真实攻击状态").is_true()


func test_blocking_holds_until_right_button_released() -> void:
	var source := _source("res://scenes/characters/player/state/player_state_blocking.gd")
	assert_bool(source.contains('not Input.is_action_pressed("block")')) \
		.override_failure_message("格挡必须按住保持，松开才退出").is_true()


func test_aiming_changes_camera_fov_and_can_reset() -> void:
	var player := _make_player_with_equipment()
	var camera := Camera3D.new()
	camera.fov = 70.0
	player.camera = camera
	player.default_camera_fov = camera.fov
	player.set_weapon_aiming(true)
	assert_bool(player.is_weapon_aiming).is_true()
	# 望远镜效果：目标 FOV 应大幅缩减（至少 20 度）
	assert_float(player.target_camera_fov).is_less_equal(50.0)
	assert_float(player.target_camera_fov).is_less(70.0)
	player.set_weapon_aiming(false)
	assert_bool(player.is_weapon_aiming).is_false()
	# 关闭瞄准后目标 FOV 恢复默认值
	assert_float(player.target_camera_fov).is_equal(70.0)
	player.free()
	camera.free()


func test_aiming_fov_reduction_is_strong_enough_for_telescope() -> void:
	# 望远镜效果：缩减量必须 >= 20 度（旧值 12 不够）
	assert_float(Player.AIM_FOV_REDUCTION).is_greater_equal(20.0)


func test_aiming_reduces_mouse_sensitivity() -> void:
	# 瞄准时鼠标灵敏度应降低（望远镜效果）
	assert_float(Player.AIM_SENSITIVITY_MULT).is_less(1.0)
	assert_float(Player.AIM_SENSITIVITY_MULT).is_greater(0.0)


func test_shooting_returns_to_aiming_if_block_still_held() -> void:
	# 回归测试：射击完成后若右键仍按住，应回到瞄准状态而非移动
	var source := _source("res://scenes/characters/player/state/player_state_shooting.gd")
	assert_bool(source.contains('is_action_pressed("block")')) \
		.override_failure_message("射击完成后必须检查右键是否仍按住").is_true()
	assert_bool(source.contains("Player.State.AIMING")) \
		.override_failure_message("右键仍按住时应回到 AIMING 状态").is_true()


func test_shooting_does_not_disable_aiming_on_enter() -> void:
	# 回归测试：射击状态进入时不应关闭瞄准缩放（保持望远镜效果）
	var source := _source("res://scenes/characters/player/state/player_state_shooting.gd")
	var enter_idx := source.find("func _enter_tree")
	var next_func_idx := source.find("\nfunc ", enter_idx + 1)
	if next_func_idx == -1:
		next_func_idx = source.length()
	var enter_body := source.substr(enter_idx, next_func_idx - enter_idx)
	assert_bool(not enter_body.contains("set_weapon_aiming(false)")) \
		.override_failure_message("射击状态进入时不应关闭瞄准缩放（保持望远镜效果）").is_true()


func test_aiming_does_not_disable_aiming_on_exit_to_attack_preparing() -> void:
	# 回归测试：瞄准状态退出时不应关闭瞄准（避免 AIMING→ATTACK_PREPARING 时的闪烁）
	var source := _source("res://scenes/characters/player/state/player_state_aiming.gd")
	# _exit_tree 中不应调用 set_weapon_aiming(false)
	assert_bool(not source.contains("_exit_tree")) \
		.override_failure_message("瞄准状态不应在 _exit_tree 中关闭瞄准（会导致状态切换时 FOV 闪烁）").is_true()


func test_attack_preparing_does_not_disable_aiming_on_exit_to_shooting() -> void:
	# 回归测试：攻击准备状态退出到射击时不应关闭瞄准缩放
	var source := _source("res://scenes/characters/player/state/player_state_attack_preparing.gd")
	assert_bool(not source.contains("_exit_tree")) \
		.override_failure_message("攻击准备状态不应在 _exit_tree 中关闭瞄准（会导致射击时 FOV 闪烁）").is_true()


func _make_player_with_equipment() -> Player:
	var player := Player.new()
	var eq := EquipmentComponent.new()
	player.add_child(eq)
	player.equipment = eq
	_prepare_weapon_equipment(eq)
	return player


func _prepare_weapon_equipment(eq: EquipmentComponent) -> void:
	eq.weapon_placeholder = Node3D.new()
	eq.weapon_reach_raycast = RayCast3D.new()
	eq.weapon_spawn_position = Node3D.new()
	eq.add_child(eq.weapon_placeholder)
	eq.add_child(eq.weapon_reach_raycast)
	eq.add_child(eq.weapon_spawn_position)


func _make_weapon(label: String, weapon_class: String, attack_type: String, hands: String) -> WeaponData:
	var data := WeaponData.new()
	data.id = label.to_lower().replace(" ", "_")
	data.name = label
	data.item_tag = "weapon"
	data.equipment_category = "weapons"
	data.weapon_class = weapon_class
	data.attack_type = attack_type
	data.hands = hands
	data.condition = 10
	data.max_condition = 10
	data.damage_min = 1
	data.damage_max = 3
	data.damage_dice_count = 1
	data.damage_dice_sides = 4
	data.reach = 2.0
	return data


func _make_shield(label: String) -> WeaponData:
	var data := _make_weapon(label, "shield", "shield", "off_hand")
	data.item_tag = "shield"
	data.equipment_category = "shields"
	data.shield_phys_def = 1
	data.reach = 1.0
	return data


static func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code
