extends GdUnitTestSuite
# has_method 空值守卫测试
# 验证 has_method 调用前有 null 检查，防止 "Attempt to call function 'has_method' in base 'null instance'" 错误

# ==================== player.gd ====================

func test_player_physics_process_guards_null_collider() -> void:
	# 验证 _physics_process 中 collider.has_method("interact") 前有 null 检查 (line 115)
	var script: Resource = load("res://scenes/characters/player/player.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("collider != null and not (collider is PickableItem) and collider.has_method") != -1) \
		.override_failure_message("player.gd _physics_process 缺少 collider null 检查 (line 115)").is_true()

func test_player_check_for_possible_action_guards_null_collider() -> void:
	# 验证 check_for_possible_action 中 collider.has_method("interact") 前有 null 检查 (line 204)
	var script: Resource = load("res://scenes/characters/player/player.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("collider != null and collider.has_method") != -1) \
		.override_failure_message("player.gd check_for_possible_action 缺少 collider null 检查 (line 204)").is_true()

# ==================== combat_bridge.gd ====================

func test_combat_bridge_resolve_player_attack_guards_null_enemy() -> void:
	var script: Resource = load("res://globals/combat/combat_bridge.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("enemy != null and enemy.has_method") != -1) \
		.override_failure_message("combat_bridge.gd resolve_player_attack 缺少 enemy null 检查").is_true()

# ==================== character_panel.gd ====================

func test_character_panel_ready_guards_null_gamestate() -> void:
	var script: Resource = load("res://scenes/ui/character_panel.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("GameState != null and GameState.has_method") != -1) \
		.override_failure_message("character_panel.gd _ready 缺少 GameState null 检查").is_true()

# ==================== player_state_slashing.gd ====================

func test_player_state_slashing_guards_null_collider() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_slashing.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("collider != null and collider.has_method") != -1) \
		.override_failure_message("player_state_slashing.gd 缺少 collider null 检查").is_true()

# ==================== player_state_grabbing.gd ====================

func test_player_state_grabbing_guards_null_state_data() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_grabbing.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("state_data != null and state_data.has_method") != -1) \
		.override_failure_message("player_state_grabbing.gd 缺少 state_data null 检查").is_true()
