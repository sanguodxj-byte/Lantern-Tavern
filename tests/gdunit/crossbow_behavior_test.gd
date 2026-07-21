extends GdUnitTestSuite

# 弩行为测试
# 验证弩无需拉弓蓄力动画、无需颤抖、右键瞄准后左键直接射击保持瞄准视角

# ── EquipmentComponent.is_active_weapon_crossbow 测试 ──

func test_equipment_has_crossbow_detection_method() -> void:
	var script := load("res://scenes/characters/component/equipment_component.gd") as GDScript
	assert_str(script.source_code).contains("func is_active_weapon_crossbow()")


func test_player_has_crossbow_detection_method() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	assert_str(script.source_code).contains("func is_active_weapon_crossbow()")


func test_crossbow_detected_by_weapon_class() -> void:
	var eq := _create_equipment()
	var crossbow := _make_crossbow()
	eq.weapon_data = crossbow
	assert_bool(eq.is_active_weapon_crossbow()).is_true()


func test_crossbow_detected_by_tag() -> void:
	var eq := _create_equipment()
	var crossbow := _make_crossbow()
	crossbow.weapon_class = "ranged"
	crossbow.tags = ["weapon", "ranged", "crossbow"]
	eq.weapon_data = crossbow
	assert_bool(eq.is_active_weapon_crossbow()).is_true()


func test_longbow_not_detected_as_crossbow() -> void:
	var eq := _create_equipment()
	var bow := WeaponData.new()
	bow.id = "longbow"
	bow.weapon_class = "longbow"
	bow.tags = ["weapon", "ranged", "bow"]
	bow.attack_type = "ranged"
	eq.weapon_data = bow
	assert_bool(eq.is_active_weapon_crossbow()).is_false()


func test_melee_not_detected_as_crossbow() -> void:
	var eq := _create_equipment()
	var sword := WeaponData.new()
	sword.id = "sword"
	sword.weapon_class = "one_hand_melee"
	sword.tags = ["weapon", "melee"]
	eq.weapon_data = sword
	assert_bool(eq.is_active_weapon_crossbow()).is_false()


func test_null_weapon_not_crossbow() -> void:
	var eq := _create_equipment()
	eq.weapon_data = null
	assert_bool(eq.is_active_weapon_crossbow()).is_false()


# ── AimingState 弩直接射击测试 ──

func test_aiming_state_crossbow_goes_directly_to_shooting() -> void:
	var script := load("res://scenes/characters/player/state/player_state_aiming.gd") as GDScript
	# 弩在瞄准状态下左键应直接进入 SHOOTING，跳过 ATTACK_PREPARING
	assert_str(script.source_code).contains("is_active_weapon_crossbow()")
	assert_str(script.source_code).contains("State.SHOOTING")


func test_aiming_state_bow_still_uses_attack_preparing() -> void:
	var script := load("res://scenes/characters/player/state/player_state_aiming.gd") as GDScript
	# 弓仍需经过 ATTACK_PREPARING 蓄力
	assert_str(script.source_code).contains("get_primary_weapon_action_state()")


# ── AttackPreparingState 弩跳过拉弓动画测试 ──

func test_attack_preparing_skips_bow_pull_for_crossbow() -> void:
	var script := load("res://scenes/characters/player/state/player_state_attack_preparing.gd") as GDScript
	# 弩跳过拉弓：仅非弩远程才 sample_action(vm_bow_draw)，弩被 is_active_weapon_crossbow() 排除
	assert_str(script.source_code).contains("is_active_weapon_crossbow()")
	assert_str(script.source_code).contains("not player.is_active_weapon_crossbow()")
	assert_str(script.source_code).contains("sample_action")


func test_attack_preparing_has_crossbow_min_hold_constant() -> void:
	var script := load("res://scenes/characters/player/state/player_state_attack_preparing.gd") as GDScript
	# 弩的最低蓄力时间应为 0
	assert_str(script.source_code).contains("CROSSBOW_MIN_HOLD_MSEC")
	assert_str(script.source_code).contains("CROSSBOW_MIN_HOLD_MSEC := 0")


func test_attack_preparing_uses_dynamic_min_hold() -> void:
	var script := load("res://scenes/characters/player/state/player_state_attack_preparing.gd") as GDScript
	# 应根据武器类型选择不同的 min_hold
	assert_str(script.source_code).contains("var min_hold :=")
	assert_str(script.source_code).contains("is_active_weapon_crossbow()")


# ── ShootingState 保持瞄准视角测试 ──

func test_shooting_state_does_not_disable_aiming_on_enter() -> void:
	var script := load("res://scenes/characters/player/state/player_state_shooting.gd") as GDScript
	# 射击状态进入时不应关闭瞄准（保持瞄准视角）
	var enter_block := _extract_function(script.source_code, "_enter_tree")
	assert_bool(enter_block.contains("set_weapon_aiming(false)")).is_false()


func test_shooting_state_returns_to_aiming_if_right_click_held() -> void:
	var script := load("res://scenes/characters/player/state/player_state_shooting.gd") as GDScript
	# 射击完成后若右键仍按住，应回到瞄准状态
	assert_str(script.source_code).contains("Input.is_action_pressed(\"block\")")
	assert_str(script.source_code).contains("State.AIMING")


func test_shooting_state_plays_view_model_fire_action() -> void:
	var script := load("res://scenes/characters/player/state/player_state_shooting.gd") as GDScript
	# 射击时经 ViewModel.play_action 播放开火视觉（弓/弩），并从 MuzzlePoint 生成投射物
	assert_str(script.source_code).contains("play_action")
	assert_str(script.source_code).contains("get_muzzle_global_transform")


# ── ViewModel apply_bow_pull 仅为弓设计测试 ──

func test_view_model_apply_bow_pull_has_trembling() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	# 拉弓动作经由 vm_bow_draw 动画表现（含颤抖/回缩效果），仅弓调用
	assert_str(script.source_code).contains("vm_bow_draw")


func test_attack_preparing_crossbow_no_pull_no_shake() -> void:
	var script := load("res://scenes/characters/player/state/player_state_attack_preparing.gd") as GDScript
	# 验证弩的代码路径不经过 sample_action(vm_bow_draw)
	var source := script.source_code
	var pull_block := _extract_function(source, "_process")
	# 仅非弩远程才 sample_action(vm_bow_draw)
	assert_str(pull_block).contains("is_active_weapon_crossbow()")
	assert_str(pull_block).contains("not player.is_active_weapon_crossbow()")
	assert_str(pull_block).contains("sample_action")


# ── 辅助方法 ──────────────────────────────────────────────

func _create_equipment() -> EquipmentComponent:
	var eq: EquipmentComponent = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	eq.weapon_placeholder = Node3D.new()
	eq.weapon_reach_raycast = RayCast3D.new()
	eq.weapon_spawn_position = Node3D.new()
	eq.add_child(eq.weapon_placeholder)
	eq.add_child(eq.weapon_reach_raycast)
	eq.add_child(eq.weapon_spawn_position)
	return eq


func _make_crossbow() -> WeaponData:
	var data := WeaponData.new()
	data.id = "crossbow"
	data.name = "Crossbow"
	data.name_zh = "轻弩"
	data.item_tag = "weapon"
	data.weapon_class = "crossbow"
	data.attack_type = "ranged"
	data.tags = ["weapon", "ranged", "two_hand", "crossbow", "light_crossbow"]
	data.condition = 100
	data.max_condition = 100
	data.damage_min = 4
	data.damage_max = 10
	data.reach = 5.0
	return data


func _extract_function(source: String, func_name: String) -> String:
	var start_idx := source.find("\nfunc " + func_name + "(")
	if start_idx == -1:
		return ""
	var end_idx := source.find("\nfunc ", start_idx + 1)
	if end_idx == -1:
		end_idx = source.length()
	return source.substr(start_idx, end_idx - start_idx)
