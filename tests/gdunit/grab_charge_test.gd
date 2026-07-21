extends GdUnitTestSuite
## 抓取/冲撞技能测试
## 验证：State 枚举扩展 + state_map 注册 + 分发逻辑 + 前置条件 + 状态脚本存在

func test_player_has_grabbing_state() -> void:
	var script: Resource = load("res://scenes/characters/player/player.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("GRABBING") != -1).is_true()

func test_player_has_charging_state() -> void:
	var script: Resource = load("res://scenes/characters/player/player.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("CHARGING") != -1).is_true()

func test_state_map_registers_grabbing() -> void:
	var script: Resource = load("res://scenes/characters/player/player.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("State.GRABBING: PlayerStateGrabbing") != -1).is_true()

func test_state_map_registers_charging() -> void:
	var script: Resource = load("res://scenes/characters/player/player.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("State.CHARGING: PlayerStateCharging") != -1).is_true()

func test_grabbing_state_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/characters/player/state/player_state_grabbing.gd")).is_true()

func test_charging_state_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/characters/player/state/player_state_charging.gd")).is_true()

func test_grabbing_state_has_class_name() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_grabbing.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("class_name PlayerStateGrabbing") != -1).is_true()

func test_charging_state_has_class_name() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_charging.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("class_name PlayerStateCharging") != -1).is_true()

func test_charge_requires_run_input() -> void:
	# 冲撞分发逻辑必须检查 Input.is_action_pressed("run")
	var script: Resource = load("res://scenes/characters/player/player.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find('Input.is_action_pressed("run")') != -1) \
		.override_failure_message("冲撞未检查 Shift 跑步前置条件").is_true()

func test_grab_uses_kick_raycast_enemy() -> void:
	# 抓取分发逻辑必须用 kick_raycast 命中 Enemy
	var script: Resource = load("res://scenes/characters/player/player_skill_dispatcher.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("kick_raycast.get_collider() as Enemy") != -1) \
		.override_failure_message("抓取未用 kick_raycast 探测敌人").is_true()

func test_grab_has_fallback_shape_query() -> void:
	# 抓取必须有球形查询后备，解决敌人贴近时 raycast 无法命中的问题
	var script: Resource = load("res://scenes/characters/player/player_skill_dispatcher.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_find_grab_target") != -1) \
		.override_failure_message("抓取必须有 _find_grab_target 方法").is_true()
	assert_bool(source.find("intersect_shape") != -1) \
		.override_failure_message("抓取后备探测必须使用 intersect_shape 球形查询").is_true()

func test_grabbing_throws_on_action_input() -> void:
	# GRABBING 状态左键投掷
	var script: Resource = load("res://scenes/characters/player/state/player_state_grabbing.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find('Input.is_action_just_pressed("action")') != -1).is_true()
	assert_bool(source.find("_perform_throw") != -1).is_true()

func test_grabbing_cancels_on_use_input() -> void:
	# GRABBING 状态右键/E 取消抓取
	var script: Resource = load("res://scenes/characters/player/state/player_state_grabbing.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find('Input.is_action_just_pressed("use")') != -1).is_true()
	assert_bool(source.find("_cancel_grab") != -1).is_true()

func test_charging_locks_direction() -> void:
	# 冲撞锁定进入时朝向
	var script: Resource = load("res://scenes/characters/player/state/player_state_charging.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("charge_direction") != -1).is_true()
	assert_bool(source.find("basis.z.normalized") != -1).is_true()

func test_charging_has_time_limit() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_charging.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("CHARGE_MAX_DURATION") != -1).is_true()
	assert_bool(source.find("charge_max_duration") != -1).is_true()
	assert_bool(source.find("elapsed >= charge_max_duration") != -1).is_true()

func test_charging_deals_damage_on_collision() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_charging.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_check_charge_collision") != -1).is_true()
	assert_bool(source.find("_apply_charge_damage") != -1).is_true()
	assert_bool(source.find("apply_action_skill_hit_to_enemy") != -1).is_true()

func test_charging_uses_effective_charge_skill_for_runes() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_charging.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find('get_effective_skill_definition("冲撞")') != -1).is_true()
	assert_bool(source.find("dash_speed_mps") != -1).is_true()

func test_charging_has_superarmor() -> void:
	# 冲撞期间霸体免伤
	var script: Resource = load("res://scenes/characters/player/state/player_state_charging.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("can_get_hurt") != -1).is_true()
	assert_bool(source.find("return false") != -1).is_true()

func test_player_state_data_has_grabbed_enemy() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_data.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("grabbed_enemy") != -1).is_true()
	assert_bool(source.find("set_grabbed_enemy") != -1).is_true()
	assert_bool(source.find("get_grabbed_enemy") != -1).is_true()
