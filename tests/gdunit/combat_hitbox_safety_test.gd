extends GdUnitTestSuite
## 攻击 hitbox 生命周期安全测试
## 验证：hitbox 被释放后不会导致 set_attack_hitbox_active 崩溃

func test_player_slashing_guards_hitbox_validity() -> void:
	var script: GDScript = load("res://scenes/characters/player/state/player_state_slashing.gd") as GDScript
	var source := script.source_code
	# _physics_process 中必须在调用前检查 is_instance_valid
	assert_bool(source.contains("is_instance_valid(hitbox)")) \
		.override_failure_message("player_state_slashing._physics_process 必须在 set_attack_hitbox_active 前检查 hitbox 有效性") \
		.is_true()
	# on_animation_finished 中也必须检查
	assert_bool(source.contains("is_instance_valid(hitbox)")) \
		.override_failure_message("player_state_slashing.on_animation_finished 必须在 set_attack_hitbox_active 前检查 hitbox 有效性") \
		.is_true()
	# _exit_tree 清理
	assert_bool(source.contains("func _exit_tree")) \
		.override_failure_message("player_state_slashing 应有 _exit_tree 清理 hitbox") \
		.is_true()

func test_enemy_slashing_guards_hitbox_validity() -> void:
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_slashing.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("is_instance_valid(hitbox)")) \
		.override_failure_message("enemy_state_slashing 必须在 set_attack_hitbox_active 前检查 hitbox 有效性") \
		.is_true()
	assert_bool(source.contains("func _exit_tree")) \
		.override_failure_message("enemy_state_slashing 应有 _exit_tree 清理 hitbox") \
		.is_true()

func test_hitbox_builder_set_active_already_guards() -> void:
	# 确保 CombatHitboxBuilder.set_active 自身也有 is_instance_valid 防护
	var script: GDScript = load("res://globals/combat/combat_hitbox_builder.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("is_instance_valid(hitbox)")) \
		.override_failure_message("CombatHitboxBuilder.set_active 应检查 is_instance_valid") \
		.is_true()
