extends GdUnitTestSuite
## skill_released 信号分发测试
## 验证：player.gd 的 _on_skill_released 按技能 id 正确分发到动作/武器技能处理

const AS_DB := preload("res://globals/combat/action_skills.gd")
const SD_DB := preload("res://globals/combat/skill_data.gd")
const CE_LIB := preload("res://globals/combat/combat_engine.gd")

## 动作技能 id 全集可被 AS_DB.get_skill_by_id 命中
func test_action_skill_ids_resolvable() -> void:
	for sid in ["踢击", "冲撞", "抓取投掷", "滑铲", "战术滑步"]:
		var sk: Dictionary = AS_DB.get_skill_by_id(sid)
		assert_bool(sk.is_empty()).is_false()
		assert_str(sk["id"]).is_equal(sid)

## 武器技能 id 全集可被 SD_DB.get_skill_by_id 命中
func test_weapon_skill_ids_resolvable() -> void:
	for sid in ["防御姿态", "顺劈斩", "旋风斩", "震地击", "贯穿刺击"]:
		var sk: Dictionary = SD_DB.get_skill_by_id(sid)
		assert_bool(sk.is_empty()).is_false()

## 动作技能 enum 值唯一且匹配
func test_action_skill_enum_unique() -> void:
	var enums: Array = []
	for sk in AS_DB.SKILLS:
		assert_bool(enums.has(sk["enum"])).is_false()
		enums.append(sk["enum"])
	assert_int(enums.size()).is_equal(5)

## DamageResult 字段可构造（_apply_skill_hit_to_kick_raycast 用）
func test_damage_result_constructible() -> void:
	var r := CE_LIB.DamageResult.new()
	r.hit = true
	r.final_damage = 4
	r.knockback_force = 3.0
	r.knockback_impulse = Vector3(0, 0, -3)
	r.stun_duration = 0.5
	r.physical_impact_enabled = true
	r.physical_impact_damage_mult = 1.25
	assert_bool(r.hit).is_true()
	assert_int(r.final_damage).is_equal(4)
	assert_float(r.knockback_force).is_equal(3.0)
	assert_float(r.stun_duration).is_equal(0.5)
	assert_bool(r.physical_impact_enabled).is_true()
	assert_float(r.physical_impact_damage_mult).is_equal(1.25)

## 冲撞技能字段完整（_dispatch_action_skill 用）
func test_charge_skill_fields() -> void:
	var sk: Dictionary = AS_DB.get_skill_by_id("冲撞")
	assert_float(float(sk["damage_mult"])).is_equal(0.8)
	assert_int(int(sk["range_m"])).is_equal(5)
	assert_float(float(sk["knockback_m"])).is_equal(6.0)
	assert_float(float(sk["stun_sec"])).is_equal(0.5)
	assert_float(float(sk["dash_speed_mps"])).is_greater(0.0)
	assert_bool(bool(sk["breaks_shield"])).is_true()

## 滑铲技能 buff 字段（无敌帧）
func test_slide_skill_iframes() -> void:
	var sk: Dictionary = AS_DB.get_skill_by_id("滑铲")
	assert_str(sk["buff_type"]).is_equal("iframes")
	assert_float(float(sk["buff_value"])).is_equal(0.5)

## 战术滑步 buff 字段（闪避帧）
func test_tactical_step_dodge_frames() -> void:
	var sk: Dictionary = AS_DB.get_skill_by_id("战术滑步")
	assert_str(sk["buff_type"]).is_equal("dodge_frames")
	assert_float(float(sk["buff_value"])).is_equal(0.3)

func test_weapon_skill_dispatch_keeps_non_damage_buffs() -> void:
	var script: Resource = load("res://scenes/characters/player/player_skill_dispatcher.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find('if float(skill.get("damage_mult", 0.0)) <= 0.0:\\n\\t\\treturn') == -1) \
		.override_failure_message("非伤害武器技能不能在套用 buff 前直接 return").is_true()
	assert_bool(source.find("_apply_self_skill_buff(player, skill)") != -1).is_true()
	assert_bool(source.find("_apply_lifesteal(player, result)") != -1).is_true()

## SkillRuntime 信号 skill_released 存在
func test_skill_released_signal_exists() -> void:
	var sr: Node = Engine.get_main_loop().root.get_node_or_null("SkillRuntime")
	assert_object(sr).is_not_null()
	# 信号存在性：连接一个 lambda 验证
	var received: Array = []
	var cb: Callable = func(sid: String): received.append(sid)
	sr.skill_released.connect(cb)
	# 直接 emit 验证链路
	sr.skill_released.emit("测试技能")
	assert_int(received.size()).is_equal(1)
	assert_str(received[0]).is_equal("测试技能")
	sr.skill_released.disconnect(cb)

func test_player_f_input_releases_skill_runtime_f_slot() -> void:
	var script: Resource = load("res://scenes/characters/player/player.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("_is_skill_input_enabled") == -1) \
		.override_failure_message("F/G 技能输入不应按场景禁用，酒馆和地牢都要可用").is_true()
	assert_bool(source.find('Input.is_action_just_pressed("kick")') != -1).is_true()
	assert_bool(source.find("sr.SLOT_F_ACTION") != -1).is_true()
	assert_bool(source.find("sr.start_release(f_skill, main_type, off_type, self, sr.SLOT_F_ACTION)") != -1).is_true()

func test_kick_state_uses_action_skill_hit_result_for_momentum() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_kicking.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("player.apply_kick_hit(enemy)") != -1) \
		.override_failure_message("踢击命中敌人应走动作技能 DamageResult，才能继承滑铲/冲撞动量").is_true()
	assert_bool(source.find("enemy.try_receive_kick(player)") == -1) \
		.override_failure_message("旧固定踢击不会应用动量伤害和击退倍率").is_true()

func test_player_action_skill_hit_consumes_momentum_context() -> void:
	var script: Resource = load("res://scenes/characters/player/player_skill_dispatcher.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("consume_momentum_context") != -1).is_true()
	assert_bool(source.find("build_bonus(skill, forward)") != -1).is_true()

func test_player_action_skill_hit_passes_physical_impact_fields() -> void:
	var script: Resource = load("res://scenes/characters/player/player_skill_dispatcher.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("physical_impact_enabled") != -1).is_true()
	assert_bool(source.find("physical_impact_damage_mult") != -1).is_true()
	assert_bool(source.find("breaks_shield") != -1).is_true()

func test_moving_state_does_not_hardcode_kick_on_f() -> void:
	var script: Resource = load("res://scenes/characters/player/state/player_state_moving.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find('Input.is_action_just_pressed("kick")') == -1) \
		.override_failure_message("移动状态不应固定把 F/kick 转成踢击，F 应释放技能栏动作槽").is_true()
	assert_bool(source.find("Player.State.KICKING") == -1) \
		.override_failure_message("移动状态不应绕过 SkillRuntime 直接进入 KICKING").is_true()
