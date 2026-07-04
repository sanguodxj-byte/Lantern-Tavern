extends GdUnitTestSuite
## ActionSkills 通用动作技能数据测试
## 验证：5 个动作技能定义、无媒介限制、ARPG 字段

const AS := preload("res://globals/action_skills.gd")

func test_action_skills_count_5() -> void:
	assert_int(AS.get_skill_count()).is_equal(5)

func test_all_skill_ids_chinese() -> void:
	var ids: Array = AS.get_all_skill_ids()
	assert_bool(ids.has("踢击")).is_true()
	assert_bool(ids.has("冲撞")).is_true()
	assert_bool(ids.has("抓取投掷")).is_true()
	assert_bool(ids.has("滑铲")).is_true()
	assert_bool(ids.has("战术滑步")).is_true()

func test_get_skill_by_id() -> void:
	var s: Dictionary = AS.get_skill_by_id("踢击")
	assert_bool(not s.is_empty()).is_true()
	assert_str(s["name"]).is_equal("踢击 / Kick")
	assert_float(s["cooldown"]).is_equal(2.0)
	assert_float(s["knockback_m"]).is_equal(1.5)

func test_get_skill_by_id_not_found() -> void:
	assert_bool(AS.get_skill_by_id("不存在").is_empty()).is_true()

func test_get_skill_by_enum() -> void:
	var s: Dictionary = AS.get_skill_by_enum(AS.ActionSkill.CHARGE)
	assert_str(s["id"]).is_equal("冲撞")
	assert_float(s["range_m"]).is_equal(5.0)

func test_all_skills_type_action() -> void:
	for s in AS.SKILLS:
		assert_str(s["type"]).is_equal("action")

func test_all_skills_no_school_field() -> void:
	# 动作技能无流派媒介限制，不应含 school 字段
	for s in AS.SKILLS:
		assert_bool(not s.has("school")).is_true()

func test_kick_low_cooldown() -> void:
	var s: Dictionary = AS.get_skill_by_id("踢击")
	assert_float(s["cooldown"]).is_equal(2.0)

func test_charge_has_stun() -> void:
	var s: Dictionary = AS.get_skill_by_id("冲撞")
	assert_float(s["stun_sec"]).is_equal(0.5)

func test_slide_has_iframes() -> void:
	var s: Dictionary = AS.get_skill_by_id("滑铲")
	assert_str(s["buff_type"]).is_equal("iframes")
	assert_float(s["buff_value"]).is_equal(0.5)

func test_tactical_step_has_dodge_frames() -> void:
	var s: Dictionary = AS.get_skill_by_id("战术滑步")
	assert_str(s["buff_type"]).is_equal("dodge_frames")
	assert_float(s["buff_value"]).is_equal(0.3)

func test_grab_throw_high_knockback() -> void:
	var s: Dictionary = AS.get_skill_by_id("抓取投掷")
	assert_float(s["knockback_m"]).is_equal(3.0)
	assert_float(s["stun_sec"]).is_equal(1.0)

func test_all_cooldowns_positive() -> void:
	for s in AS.SKILLS:
		assert_float(s["cooldown"]).is_greater(0.0)

func test_all_cast_times_non_negative() -> void:
	for s in AS.SKILLS:
		assert_float(s["cast_time"]).is_greater_equal(0.0)
