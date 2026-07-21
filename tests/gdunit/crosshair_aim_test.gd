extends GdUnitTestSuite
## 准心与瞄准系统测试。
## 验证：
##   1. Crosshair 脚本基本功能（创建、绘制、状态切换）
##   2. 投射物差异化抛物线重力值（弩最小/弓中等/投掷最大）
##   3. Player 准心瞄准方法（源码断言）
##   4. PlayerStateShooting 准心瞄准逻辑（源码断言）
##   5. PlayerStateThrowing 准心瞄准逻辑（源码断言）
##   6. EquipmentComponent.throw_weapon 接受瞄准点参数（源码断言）
##   7. 技能派发器准心瞄准验证

const PD := preload("res://data/projectile_data.gd")
const Service := preload("res://globals/core/service.gd")
const CrosshairScript := preload("res://scenes/ui/crosshair.gd")

## 辅助：加载脚本源码
static func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code

# ============================================================================
# 1. Crosshair 脚本测试
# ============================================================================

func test_crosshair_creates_and_has_draw_method() -> void:
	var ch := CrosshairScript.new()
	assert_object(ch).is_not_null()
	assert_bool(ch.has_method("_draw")).is_true()
	assert_bool(ch.has_method("_process")).is_true()
	ch.free()

func test_crosshair_set_player() -> void:
	var ch := CrosshairScript.new()
	var dummy := Node.new()
	ch.set_player(dummy)
	assert_bool(ch._player == dummy).is_true()
	dummy.free()
	ch.free()

func test_crosshair_has_color_constants() -> void:
	assert_bool(CrosshairScript.COL_DEFAULT != null).is_true()
	assert_bool(CrosshairScript.COL_TARGETING != null).is_true()
	assert_bool(CrosshairScript.COL_AIMING != null).is_true()


func test_crosshair_hit_flash_reuses_targeting_red() -> void:
	# 命中反馈复用已有 COL_TARGETING 变红，不另起 Hitmarker 绘制系统
	var source := _source("res://scenes/ui/crosshair.gd")
	assert_bool(source.contains("COL_TARGETING")) \
		.override_failure_message("命中反馈应复用 COL_TARGETING").is_true()
	assert_bool(source.contains("_draw_hitmarker_x")) \
		.override_failure_message("不应再绘制独立对角 X Hitmarker").is_false()
	assert_bool(source.contains("COL_HIT")) \
		.override_failure_message("不应新增 COL_HIT 颜色体系").is_false()


func test_crosshair_play_hit_flash_activates() -> void:
	var ch := CrosshairScript.new()
	add_child(ch)
	assert_bool(ch.is_hit_flash_active()).is_false()
	ch.play_hit_flash(false)
	assert_bool(ch.is_hit_flash_active()).is_true()
	assert_bool(ch._hit_is_crit).is_false()
	assert_float(ch._hit_timer).is_greater(0.0)
	assert_float(ch._hit_duration).is_equal_approx(CrosshairScript.HIT_FLASH_DURATION, 0.001)
	ch.queue_free()


func test_crosshair_play_hit_flash_crit_longer() -> void:
	var ch := CrosshairScript.new()
	add_child(ch)
	ch.play_hit_flash(true)
	assert_bool(ch.is_hit_flash_active()).is_true()
	assert_bool(ch._hit_is_crit).is_true()
	assert_float(ch._hit_duration).is_equal_approx(CrosshairScript.HIT_FLASH_CRIT_DURATION, 0.001)
	assert_float(ch._hit_duration).is_greater(CrosshairScript.HIT_FLASH_DURATION)
	ch.queue_free()


func test_crosshair_hit_flash_expires() -> void:
	var ch := CrosshairScript.new()
	add_child(ch)
	ch.play_hit_flash(false)
	ch._process(ch._hit_duration + 0.05)
	assert_bool(ch.is_hit_flash_active()).is_false()
	assert_float(ch._hit_timer).is_equal_approx(0.0, 0.001)
	ch.queue_free()


func test_crosshair_listens_to_player_hit_enemy_signal() -> void:
	var source := _source("res://scenes/ui/crosshair.gd")
	assert_bool(source.contains("player_hit_enemy.connect")) \
		.override_failure_message("Crosshair 必须连接 player_hit_enemy 信号").is_true()
	assert_bool(source.contains("play_hit_flash") or source.contains("_on_player_hit_enemy")) \
		.override_failure_message("Crosshair 必须处理命中信号并触发变红").is_true()


func test_crosshair_receives_game_events_hit_signal() -> void:
	var ch := CrosshairScript.new()
	add_child(ch)
	await get_tree().process_frame
	assert_bool(GameEvents.player_hit_enemy.is_connected(ch._on_player_hit_enemy)).is_true()
	GameEvents.player_hit_enemy.emit({"damage": 12, "is_crit": true})
	assert_bool(ch.is_hit_flash_active()).is_true()
	assert_bool(ch._hit_is_crit).is_true()
	ch.queue_free()

# ============================================================================
# 2. 抛物线差异化重力值测试
# ============================================================================

func test_bolt_gravity_is_minimal() -> void:
	var ps: Node = Service.projectile_service()
	var bolt: Resource = ps.get_data("bolt")
	assert_object(bolt).is_not_null()
	assert_float(bolt.gravity_scale).is_equal(0.04)

func test_arrow_gravity_is_medium() -> void:
	var ps: Node = Service.projectile_service()
	var arrow: Resource = ps.get_data("arrow")
	assert_object(arrow).is_not_null()
	assert_float(arrow.gravity_scale).is_equal(0.20)

func test_thrown_weapon_gravity_is_maximum() -> void:
	# 投掷武器的重力在 thrown_item.gd 中硬编码
	var source := _source("res://scenes/equipment/thrown_item.gd")
	# 验证投掷武器 gravity = 0.55
	assert_bool(source.contains("gravity = 0.55")).is_true()
	# 验证不再是 gravity = 0（零重力）
	var has_zero_gravity_for_weapon := source.contains("gravity = 0\n")
	assert_bool(has_zero_gravity_for_weapon).is_false()

func test_gravity_hierarchy_bolt_less_than_arrow_less_than_thrown() -> void:
	var bolt_gravity: float = 0.04
	var arrow_gravity: float = 0.20
	var thrown_gravity: float = 0.55
	# 弩 < 弓 < 投掷
	assert_float(bolt_gravity).is_less(arrow_gravity)
	assert_float(arrow_gravity).is_less(thrown_gravity)

# ============================================================================
# 3. Player 准心瞄准方法源码验证
# ============================================================================

func test_player_has_get_aim_point_method() -> void:
	var source := _source("res://scenes/characters/player/player.gd")
	assert_bool(source.contains("func get_aim_point")).is_true()

func test_player_has_get_aim_transform_method() -> void:
	var source := _source("res://scenes/characters/player/player.gd")
	assert_bool(source.contains("func get_aim_transform")).is_true()

func test_player_get_aim_point_source_uses_camera_ray() -> void:
	# 实现已提取到 PlayerAimHelper，验证 helper 源码使用摄像机射线检测
	var source := _source("res://scenes/characters/player/player_aim_helper.gd")
	assert_bool(source.contains("func get_aim_point")).is_true()
	assert_bool(source.contains("intersect_ray")).is_true()
	assert_bool(source.contains("camera.global_position")).is_true()
	# player.gd 中应保留薄代理调用
	var player_source := _source("res://scenes/characters/player/player.gd")
	assert_bool(player_source.contains("AIM_HELPER.get_aim_point")).is_true()

func test_player_get_aim_transform_uses_looking_at() -> void:
	# 实现已提取到 PlayerAimHelper，验证 helper 源码使用 looking_at
	var source := _source("res://scenes/characters/player/player_aim_helper.gd")
	assert_bool(source.contains("func get_aim_transform")).is_true()
	assert_bool(source.contains("looking_at")).is_true()
	# player.gd 中应保留薄代理调用
	var player_source := _source("res://scenes/characters/player/player.gd")
	assert_bool(player_source.contains("AIM_HELPER.get_aim_transform")).is_true()

# ============================================================================
# 4. PlayerStateShooting 准心瞄准源码验证
# ============================================================================

func test_shooting_state_uses_aim_transform() -> void:
	var source := _source("res://scenes/characters/player/state/player_state_shooting.gd")
	# 验证射击状态使用 get_aim_transform 而非直接使用 weapon_spawn_position.global_transform
	assert_bool(source.contains("get_aim_transform")).is_true()
	# 不应再直接返回 weapon_spawn_position.global_transform
	var old_pattern := "return eq.weapon_spawn_position.global_transform"
	assert_bool(source.contains(old_pattern)).is_false()

# ============================================================================
# 5. PlayerStateThrowing 准心瞄准源码验证
# ============================================================================

func test_throwing_state_passes_aim_point() -> void:
	var source := _source("res://scenes/characters/player/state/player_state_throwing.gd")
	# 验证投掷状态调用 get_aim_point 并传递给 throw_weapon
	assert_bool(source.contains("get_aim_point")).is_true()
	assert_bool(source.contains("throw_weapon(false, aim_point)")).is_true()

# ============================================================================
# 6. EquipmentComponent.throw_weapon 瞄准参数验证
# ============================================================================

func test_throw_weapon_accepts_aim_point_parameter() -> void:
	var source := _source("res://scenes/characters/component/equipment_component.gd")
	# 验证 throw_weapon 签名包含 aim_point 参数
	assert_bool(source.contains("aim_point: Vector3")).is_true()
	# 验证使用 looking_at 朝准心方向
	assert_bool(source.contains("looking_at(aim_point")).is_true()

# ============================================================================
# 7. 技能派发器准心瞄准验证
# ============================================================================

func test_skill_dispatcher_uses_aim_transform() -> void:
	var source := _source("res://scenes/characters/player/player_skill_dispatcher.gd")
	# 验证技能投射物也朝准心发射
	assert_bool(source.contains("get_aim_transform")).is_true()
