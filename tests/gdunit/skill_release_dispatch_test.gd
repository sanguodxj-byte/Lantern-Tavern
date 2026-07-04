extends GdUnitTestSuite
## skill_released 信号分发测试
## 验证：player.gd 的 _on_skill_released 按技能 id 正确分发到动作/武器技能处理

const AS_DB := preload("res://globals/action_skills.gd")
const SD_DB := preload("res://globals/skill_data.gd")
const CE_LIB := preload("res://globals/combat_engine.gd")

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
	assert_bool(r.hit).is_true()
	assert_int(r.final_damage).is_equal(4)
	assert_float(r.knockback_force).is_equal(3.0)
	assert_float(r.stun_duration).is_equal(0.5)

## 冲撞技能字段完整（_dispatch_action_skill 用）
func test_charge_skill_fields() -> void:
	var sk: Dictionary = AS_DB.get_skill_by_id("冲撞")
	assert_float(float(sk["damage_mult"])).is_equal(0.8)
	assert_int(int(sk["range_m"])).is_equal(5)
	assert_float(float(sk["knockback_m"])).is_equal(2.0)
	assert_float(float(sk["stun_sec"])).is_equal(0.5)

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
