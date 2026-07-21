extends GdUnitTestSuite
## 动作格挡系统测试
## 验证：根据装备流派区分格挡方式
##   - 单手武器 / 远程武器：无法格挡
##   - 双手武器：仅按下右键后 0.3s 内可格挡（精确格挡窗口）
##   - 持盾：持续格挡，0.3s 完美窗口内不消耗盾牌耐久

const CE := preload("res://globals/combat/combat_engine.gd")

# ============================================================
# 1. can_block_with_active_equipment 验证
# ============================================================

func test_one_hand_weapon_cannot_block() -> void:
	# 单手武器（无盾）无法格挡，但可以双持攻击（副手进入 ATTACK_PREPARING）
	var player := _make_player_with_equipment()
	player.equipment.configure_weapon_slot(0, _make_weapon("Shortsword", "one_hand_melee", "melee", "one_hand"), true)
	assert_bool(player.can_block_with_active_equipment()).is_false()
	# 单手武器副手可双持攻击，进入 ATTACK_PREPARING 而非 BLOCKING
	assert_int(player.get_secondary_weapon_action_state()).is_equal(Player.State.ATTACK_PREPARING)
	player.free()

func test_ranged_weapon_cannot_block() -> void:
	# 远程武器无法格挡
	var player := _make_player_with_equipment()
	player.equipment.configure_weapon_slot(0, _make_weapon("Longbow", "longbow", "ranged", "two_hand"), true)
	assert_bool(player.is_active_weapon_ranged()).is_true()
	assert_bool(player.can_block_with_active_equipment()).is_false()
	player.free()

func test_two_hand_weapon_can_block() -> void:
	# 双手武器可以格挡（0.3s 精确窗口）
	var player := _make_player_with_equipment()
	player.equipment.configure_weapon_slot(0, _make_weapon("Greatsword", "two_hand", "melee", "two_hand"), true)
	assert_bool(player.is_active_weapon_two_handed()).is_true()
	assert_bool(player.can_block_with_active_equipment()).is_true()
	assert_int(player.get_secondary_weapon_action_state()).is_equal(Player.State.BLOCKING)
	player.free()

func test_shield_can_block() -> void:
	# 持盾可以格挡（持续格挡）
	var player := _make_player_with_equipment()
	player.equipment.configure_weapon_slot(0, _make_shield("Buckler"), true)
	assert_bool(player.equipment.has_shield()).is_true()
	assert_bool(player.can_block_with_active_equipment()).is_true()
	assert_int(player.get_secondary_weapon_action_state()).is_equal(Player.State.BLOCKING)
	player.free()

func test_one_hand_with_shield_can_block() -> void:
	# 单手武器 + 盾牌可以格挡（持盾持续格挡）
	var player := _make_player_with_equipment()
	player.equipment.configure_weapon_slot(0, _make_weapon("Sword", "one_hand_melee", "melee", "one_hand"), true)
	player.equipment.equip_shield(_make_shield_data("Buckler"))
	assert_bool(player.can_block_with_active_equipment()).is_true()
	player.free()

# ============================================================
# 2. PlayerStateBlocking 格挡模式验证
# ============================================================

func test_blocking_state_source_has_block_window() -> void:
	# PlayerStateBlocking 必须定义 0.3s 格挡窗口常量
	var source := _source("res://scenes/characters/player/state/player_state_blocking.gd")
	assert_bool(source.contains("BLOCK_WINDOW_SEC")) \
		.override_failure_message("PlayerStateBlocking 必须定义 BLOCK_WINDOW_SEC 常量").is_true()
	assert_bool(source.contains("0.3")) \
		.override_failure_message("BLOCK_WINDOW_SEC 应为 0.3 秒").is_true()

func test_blocking_state_has_block_mode_enum() -> void:
	# PlayerStateBlocking 必须区分盾牌格挡与双手武器格挡
	var source := _source("res://scenes/characters/player/state/player_state_blocking.gd")
	assert_bool(source.contains("BlockMode")) \
		.override_failure_message("PlayerStateBlocking 必须定义 BlockMode 枚举区分格挡方式").is_true()
	assert_bool(source.contains("SHIELD")) \
		.override_failure_message("BlockMode 必须包含 SHIELD 模式").is_true()
	assert_bool(source.contains("TWO_HAND")) \
		.override_failure_message("BlockMode 必须包含 TWO_HAND 模式").is_true()

func test_blocking_state_two_hand_auto_exit() -> void:
	# 双手武器格挡：0.3s 后自动退出
	var source := _source("res://scenes/characters/player/state/player_state_blocking.gd")
	assert_bool(source.contains("BlockMode.TWO_HAND")) \
		.override_failure_message("必须处理 TWO_HAND 模式").is_true()
	assert_bool(source.contains("BLOCK_WINDOW_SEC")) \
		.override_failure_message("双手格挡必须检查 BLOCK_WINDOW_SEC 超时").is_true()
	assert_bool(source.contains("transition_state(Player.State.MOVING)")) \
		.override_failure_message("双手格挡超时后必须退出到 MOVING").is_true()

func test_blocking_state_shield_continuous() -> void:
	# 持盾格挡：按住右键保持，松开退出
	var source := _source("res://scenes/characters/player/state/player_state_blocking.gd")
	assert_bool(source.contains('Input.is_action_pressed("block")')) \
		.override_failure_message("持盾格挡必须检查 block 按键状态").is_true()

func test_blocking_state_has_grace_window_method() -> void:
	# PlayerStateBlocking 必须暴露 is_in_grace_window() 供 Player 查询
	var source := _source("res://scenes/characters/player/state/player_state_blocking.gd")
	assert_bool(source.contains("func is_in_grace_window()")) \
		.override_failure_message("PlayerStateBlocking 必须暴露 is_in_grace_window() 方法").is_true()

func test_blocking_state_can_get_hurt_false() -> void:
	# 格挡状态下 can_get_hurt 必须返回 false
	var source := _source("res://scenes/characters/player/state/player_state_blocking.gd")
	var func_start := source.find("func can_get_hurt()")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("return false")) \
		.override_failure_message("PlayerStateBlocking.can_get_hurt() 必须返回 false").is_true()

# ============================================================
# 3. Player 格挡辅助方法验证
# ============================================================

func test_player_has_block_helper_methods() -> void:
	# Player 必须暴露格挡查询方法
	var source := _source("res://scenes/characters/player/player.gd")
	assert_bool(source.contains("func is_currently_blocking()")) \
		.override_failure_message("Player 必须暴露 is_currently_blocking()").is_true()
	assert_bool(source.contains("func _is_shield_block()")) \
		.override_failure_message("Player 必须暴露 _is_shield_block()").is_true()
	assert_bool(source.contains("func _is_in_block_grace_window()")) \
		.override_failure_message("Player 必须暴露 _is_in_block_grace_window()").is_true()

func test_player_try_receive_hit_result_checks_ignores_block() -> void:
	# try_receive_hit_result 必须检查 result.ignores_block 穿透格挡
	var source := _source("res://scenes/characters/player/player.gd")
	var func_start := source.find("func try_receive_hit_result")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("ignores_block")) \
		.override_failure_message("try_receive_hit_result 必须检查 result.ignores_block").is_true()

func test_player_blocking_branch_checks_grace_window() -> void:
	# BLOCKING 分支必须检查完美格挡窗口
	var source := _source("res://scenes/characters/player/player.gd")
	assert_bool(source.contains("_is_in_block_grace_window()")) \
		.override_failure_message("Player 的 BLOCKING 分支必须检查 _is_in_block_grace_window()").is_true()
	assert_bool(source.contains("_is_shield_block()")) \
		.override_failure_message("Player 的 BLOCKING 分支必须检查 _is_shield_block()").is_true()

# ============================================================
# 4. CombatEngine 动作控制验证
# ============================================================

func test_combat_engine_hit_always_true() -> void:
	# 动作控制：hit 恒为 true（hitbox 接触即命中，无概率闪避）
	var a := CE.AttackInput.new()
	a.attacker_str = 10
	a.weapon_damage_dice = {"count": 1, "sides": 6}
	var d := CE.Defender.new()
	d.con = 10
	d.agi = 100  # 极高灵巧不再影响命中率
	for i in range(50):
		var r = CE.resolve_attack(a, d)
		assert_bool(r.hit).is_true()

func test_combat_engine_defender_no_evade_fields() -> void:
	# Defender 不应含闪避/格挡概率字段
	var d := CE.Defender.new()
	assert_bool(not "armor_evade" in d) \
		.override_failure_message("Defender 不应含 armor_evade（已移除）").is_true()
	assert_bool(not "shield_block_chance" in d) \
		.override_failure_message("Defender 不应含 shield_block_chance（已移除）").is_true()
	assert_bool(not "shield_block_value" in d) \
		.override_failure_message("Defender 不应含 shield_block_value（已移除）").is_true()

func test_combat_engine_damage_result_has_ignores_block() -> void:
	# DamageResult 必须含 ignores_block 字段
	var r = CE.DamageResult.new()
	assert_bool("ignores_block" in r) \
		.override_failure_message("DamageResult 必须含 ignores_block 字段").is_true()

# ============================================================
# 辅助
# ============================================================

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
	eq.shield_placeholder = Node3D.new()
	eq.add_child(eq.weapon_placeholder)
	eq.add_child(eq.weapon_reach_raycast)
	eq.add_child(eq.weapon_spawn_position)
	eq.add_child(eq.shield_placeholder)


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
	# 盾无概率格挡：仅保留物理防御
	data.shield_phys_def = 1
	data.reach = 1.0
	return data


func _make_shield_data(label: String) -> ShieldData:
	var data := ShieldData.new()
	data.name = label
	data.condition = 10
	data.max_condition = 10
	return data


static func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code
