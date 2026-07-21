extends GdUnitTestSuite
## 敌人格挡/伤害判定回归测试
## 动作控制版：验证 EnemyState.can_get_hurt() 状态判定、动作格挡（非概率格挡）

const CE := preload("res://globals/combat/combat_engine.gd")

# ============================================================
# 1. 基类 can_get_hurt 默认值验证
# ============================================================

func test_enemy_state_base_can_get_hurt_returns_true() -> void:
	var script := load("res://scenes/characters/enemies/state/enemy_state.gd") as GDScript
	var source := script.source_code
	# 基类 can_get_hurt 必须返回 true（与 PlayerState 一致）
	var func_start := source.find("func can_get_hurt()")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("return true")) \
		.override_failure_message("EnemyState 基类 can_get_hurt() 必须返回 true（默认可受伤），否则持盾敌人 100%% 格挡所有攻击").is_true()

func test_player_state_base_can_get_hurt_returns_true() -> void:
	var script := load("res://scenes/characters/player/state/player_state.gd") as GDScript
	var source := script.source_code
	var func_start := source.find("func can_get_hurt()")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("return true")).is_true()

# ============================================================
# 2. 各状态 can_get_hurt 覆盖验证
# ============================================================

func test_enemy_state_moving_inherits_can_get_hurt_true() -> void:
	# EnemyStateMoving 不覆盖 can_get_hurt，应继承基类的 true
	var script := load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	var source := script.source_code
	assert_bool(not source.contains("func can_get_hurt")) \
		.override_failure_message("EnemyStateMoving 不应覆盖 can_get_hurt（应继承基类 true）").is_true()

func test_enemy_state_slashing_inherits_can_get_hurt_true() -> void:
	var script := load("res://scenes/characters/enemies/state/enemy_state_slashing.gd") as GDScript
	var source := script.source_code
	assert_bool(not source.contains("func can_get_hurt")) \
		.override_failure_message("EnemyStateSlashing 不应覆盖 can_get_hurt（应继承基类 true）").is_true()

func test_enemy_state_hurt_rejects_reentrant_hits() -> void:
	var script := load("res://scenes/characters/enemies/state/enemy_state_hurt.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func can_get_hurt")).is_true()
	assert_bool(source.contains("return false")).is_true()

func test_enemy_state_hurt_guards_missing_head_bone() -> void:
	# 受击流血特效需要 physical_bone_head.global_transform；
	# 无布娃娃的敌人 physical_bone_head 为 null，缺失时必须回退到 enemy.global_transform，
	# 否则对 null 访问 global_transform 会崩溃。
	var script := load("res://scenes/characters/enemies/state/enemy_state_hurt.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("enemy.physical_bone_head != null")) \
		.override_failure_message("EnemyStateHurt 受击前应先检查 physical_bone_head 非空").is_true()
	assert_bool(source.contains("enemy.global_transform")) \
		.override_failure_message("EnemyStateHurt 缺失头部骨骼时应回退到 enemy.global_transform").is_true()

func test_enemy_state_stunned_can_get_hurt_true() -> void:
	var script := load("res://scenes/characters/enemies/state/enemy_state_stunned.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func can_get_hurt")) \
		.override_failure_message("EnemyStateStunned 应覆盖 can_get_hurt").is_true()
	var func_start := source.find("func can_get_hurt()")
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("return true")).is_true()

func test_enemy_state_dying_can_get_hurt_false() -> void:
	var script := load("res://scenes/characters/enemies/state/enemy_state_dying.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func can_get_hurt")) \
		.override_failure_message("EnemyStateDying 应覆盖 can_get_hurt 为 false").is_true()
	var func_start := source.find("func can_get_hurt()")
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("return false")) \
		.override_failure_message("EnemyStateDying.can_get_hurt() 必须返回 false（已死亡不可再受伤）").is_true()

func test_enemy_state_dead_can_get_hurt_false() -> void:
	var script := load("res://scenes/characters/enemies/state/enemy_state_dead.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func can_get_hurt")) \
		.override_failure_message("EnemyStateDead 应覆盖 can_get_hurt 为 false").is_true()
	var func_start := source.find("func can_get_hurt()")
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("return false")) \
		.override_failure_message("EnemyStateDead.can_get_hurt() 必须返回 false（已死亡不可再受伤）").is_true()

# ============================================================
# 3. enemy.gd 格挡逻辑验证（动作控制版）
# ============================================================

func test_try_receive_hit_result_no_longer_checks_shield_for_blocking() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	# try_receive_hit_result 不应再使用 "not equipment.has_shield()" 作为完全格挡条件
	var func_start := source.find("func try_receive_hit_result")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	# 不应包含旧的完全格挡条件
	assert_bool(not func_body.contains("not equipment.has_shield() or state_node.can_get_hurt()")) \
		.override_failure_message("try_receive_hit_result 不应再用 has_shield + can_get_hurt 做完全格挡判定").is_true()
	# 应直接用 can_get_hurt 判定是否受伤
	assert_bool(func_body.contains("can_get_hurt()")) \
		.override_failure_message("try_receive_hit_result 应直接用 can_get_hurt() 判定受伤").is_true()

func test_try_receive_hit_result_uses_ignores_block() -> void:
	# 动作控制版：try_receive_hit_result 应检查 result.ignores_block 穿透格挡
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	var func_start := source.find("func try_receive_hit_result")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("ignores_block")) \
		.override_failure_message("try_receive_hit_result 应检查 result.ignores_block 穿透格挡").is_true()

func test_try_receive_hit_result_no_probability_block_feedback() -> void:
	# 动作控制版：不再有概率格挡反馈（result.blocked 检查已移除）
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	var func_start := source.find("func try_receive_hit_result")
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	# 不应包含 result.blocked 概率格挡反馈
	assert_bool(not func_body.contains("result.blocked and equipment.has_shield()")) \
		.override_failure_message("try_receive_hit_result 不应再用 result.blocked 做概率格挡反馈").is_true()

func test_try_receive_hit_uses_can_get_hurt_only() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	var func_start := source.find("func try_receive_hit(")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = source.length()
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(not func_body.contains("not equipment.has_shield() or state_node.can_get_hurt()")) \
		.override_failure_message("try_receive_hit 不应再用 has_shield 做完全格挡判定").is_true()
	assert_bool(func_body.contains("if state_node.can_get_hurt():")) \
		.override_failure_message("try_receive_hit 应直接用 can_get_hurt() 判定受伤").is_true()

# ============================================================
# 4. CombatEngine 动作控制版验证（无概率格挡投骰）
# ============================================================

func test_combat_engine_no_probability_block_roll() -> void:
	var script := load("res://globals/combat/combat_engine.gd") as GDScript
	var source := script.source_code
	# 不应含概率格挡投骰
	assert_bool(not source.contains("block_roll = randi_range")) \
		.override_failure_message("CombatEngine 不应再做概率格挡投骰").is_true()
	assert_bool(not source.contains("shield_block_chance")) \
		.override_failure_message("CombatEngine 不应再含 shield_block_chance 字段").is_true()

func test_combat_engine_hit_always_true() -> void:
	# 动作控制版：hit 恒为 true（hitbox 接触即命中）
	# 使用类级别 const CE（已在文件顶部声明），避免函数内重复声明导致类型推断失败
	var attack := CE.AttackInput.new()
	attack.attacker_str = 20
	attack.weapon_damage_dice = {"count": 2, "sides": 6}
	attack.weapon_damage_flat = 5.0
	var defender := CE.Defender.new()
	defender.con = 5
	defender.agi = 5
	defender.per = 5
	defender.armor_def = 2
	for i in range(20):
		var result = CE.resolve_attack(attack, defender)
		assert_bool(result.hit).is_true()
		assert_int(result.final_damage).is_greater(0)

# ============================================================
# 5. 端到端验证：持盾敌人在 MOVING 状态下可受到伤害
# ============================================================

func test_moving_enemy_with_shield_can_be_hurt() -> void:
	# 验证：持盾敌人在 MOVING 状态下 can_get_hurt 返回 true
	# 由于无法在测试中实例化完整 Enemy（需要场景节点），用源码验证代替
	var moving_script := load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	var base_script := load("res://scenes/characters/enemies/state/enemy_state.gd") as GDScript
	# EnemyStateMoving 不覆盖 can_get_hurt
	assert_bool(not moving_script.source_code.contains("func can_get_hurt")).is_true()
	# EnemyState 基类返回 true
	var base_source := base_script.source_code
	var func_start := base_source.find("func can_get_hurt()")
	var func_end := base_source.find("\nfunc ", func_start + 1)
	if func_end == -1:
		func_end = base_source.length()
	var func_body := base_source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("return true")) \
		.override_failure_message("基类 can_get_hurt 返回 true → 持盾敌人在 MOVING 状态可受伤").is_true()

func test_enemy_gd_no_hardcoded_full_block_for_shield() -> void:
	# 确保 enemy.gd 中不再有 "has_shield" 作为完全格挡的条件
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	# try_receive_hit_result 和 try_receive_hit 中不应有 "not equipment.has_shield() or state_node.can_get_hurt()"
	var old_pattern := "not equipment.has_shield() or state_node.can_get_hurt()"
	var count := source.count(old_pattern)
	assert_int(count).is_equal(0) \
		.override_failure_message("enemy.gd 不应再使用 'not equipment.has_shield() or can_get_hurt()' 做完全格挡判定（共 %d 处）" % count)
