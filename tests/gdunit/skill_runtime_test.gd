extends GdUnitTestSuite
## SkillRuntime 技能运行时测试（2 主动 + 5 被动槽位结构）
## 验证：F 槽动作技能无媒介限制、G 槽武器技能受媒介限制、被动槽、CD、施法前摇

const SR := preload("res://globals/skill_runtime.gd")
const SD := preload("res://globals/skill_data.gd")
const AS := preload("res://globals/action_skills.gd")

var sr: Node
var ap: Node

func before() -> void:
	sr = Engine.get_main_loop().root.get_node_or_null("SkillRuntime")
	ap = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if sr: sr.reset()
	if ap: ap.reset()

func after() -> void:
	if sr: sr.reset()
	if ap: ap.reset()

func _reset() -> void:
	if sr: sr.reset()
	if ap: ap.reset()

# 辅助：绕过领悟校验直接设槽位
func _set_slot(slot_index: int, skill_id: String) -> void:
	sr.slots[slot_index] = skill_id

# ---------- 槽位结构 ----------

func test_total_slots_7() -> void:
	assert_int(SR.TOTAL_SLOTS).is_equal(7)

func test_slot_indices() -> void:
	assert_int(SR.SLOT_F_ACTION).is_equal(0)
	assert_int(SR.SLOT_G_WEAPON).is_equal(1)
	assert_int(SR.SLOT_PASSIVE_1).is_equal(2)
	assert_int(SR.SLOT_PASSIVE_5).is_equal(6)

func test_initial_slots_all_empty() -> void:
	_reset()
	for i in range(7):
		assert_str(sr.get_slot_skill(i)).is_equal("")

func test_slot_type_f_action() -> void:
	assert_int(sr.get_slot_type(0)).is_equal(SR.SlotType.F_ACTION)

func test_slot_type_g_weapon() -> void:
	assert_int(sr.get_slot_type(1)).is_equal(SR.SlotType.G_WEAPON)

func test_slot_type_passive() -> void:
	assert_int(sr.get_slot_type(2)).is_equal(SR.SlotType.PASSIVE)
	assert_int(sr.get_slot_type(6)).is_equal(SR.SlotType.PASSIVE)

func test_is_active_slot() -> void:
	assert_bool(sr.is_active_slot(0)).is_true()
	assert_bool(sr.is_active_slot(1)).is_true()
	assert_bool(sr.is_active_slot(2)).is_false()

# ---------- F 槽：动作技能绑定（无媒介限制） ----------

func test_bind_f_slot_action_skill_succeeds() -> void:
	_reset()
	assert_bool(sr.bind_skill(0, "踢击")).is_true()
	assert_str(sr.get_slot_skill(0)).is_equal("踢击")

func test_bind_f_slot_weapon_skill_rejected() -> void:
	_reset()
	# F 槽不接受动作技能，不接受武器流派技能
	if ap: ap.unlocked_skills.append("防御姿态")
	assert_bool(sr.bind_skill(0, "防御姿态")).is_false()

func test_bind_f_slot_invalid_skill_rejected() -> void:
	_reset()
	assert_bool(sr.bind_skill(0, "不存在")).is_false()

func test_f_slot_no_medium_restriction() -> void:
	_reset()
	_set_slot(0, "踢击")
	# 任何装备状态下都可释放
	var check: Dictionary = sr.can_release("踢击", "one_hand_melee", "")
	assert_bool(check["ok"]).is_true()
	check = sr.can_release("踢击", "two_hand", "")
	assert_bool(check["ok"]).is_true()
	check = sr.can_release("踢击", "", "")
	assert_bool(check["ok"]).is_true()

func test_is_slot_medium_matched_f_always_true() -> void:
	_reset()
	_set_slot(0, "踢击")
	assert_bool(sr.is_slot_medium_matched(0, "longbow", "")).is_true()
	assert_bool(sr.is_slot_medium_matched(0, "", "")).is_true()

# ---------- G 槽：武器技能绑定（受媒介限制） ----------

func test_bind_g_slot_weapon_skill_succeeds() -> void:
	_reset()
	if ap: ap.unlocked_skills.append("防御姿态")
	assert_bool(sr.bind_skill(1, "防御姿态")).is_true()
	assert_str(sr.get_slot_skill(1)).is_equal("防御姿态")

func test_bind_g_slot_action_skill_rejected() -> void:
	_reset()
	# G 槽不接受动作技能
	assert_bool(sr.bind_skill(1, "踢击")).is_false()

func test_bind_g_slot_not_learned_rejected() -> void:
	_reset()
	# 未解锁防御姿态
	assert_bool(sr.bind_skill(1, "防御姿态")).is_false()

func test_bind_g_slot_passive_rejected() -> void:
	_reset()
	if ap: ap.unlocked_skills.append("招架反击")
	assert_bool(sr.bind_skill(1, "招架反击")).is_false()

func test_g_slot_medium_mismatch_grey() -> void:
	_reset()
	_set_slot(1, "防御姿态")  # 单手剑流派
	var check: Dictionary = sr.can_release("防御姿态", "longbow", "")
	assert_bool(check["ok"]).is_false()
	assert_bool(check.get("grey", false)).is_true()

func test_g_slot_medium_matched_ok() -> void:
	_reset()
	_set_slot(1, "防御姿态")
	var check: Dictionary = sr.can_release("防御姿态", "one_hand_melee", "")
	assert_bool(check["ok"]).is_true()

func test_is_slot_medium_matched_g_slot() -> void:
	_reset()
	_set_slot(1, "防御姿态")
	assert_bool(sr.is_slot_medium_matched(1, "one_hand_melee", "")).is_true()
	assert_bool(sr.is_slot_medium_matched(1, "two_hand", "")).is_false()

# ---------- 被动槽绑定 ----------

func test_bind_passive_slot_passive_skill_succeeds() -> void:
	_reset()
	if ap: ap.unlocked_skills.append("招架反击")
	assert_bool(sr.bind_skill(2, "招架反击")).is_true()
	assert_str(sr.get_slot_skill(2)).is_equal("招架反击")

func test_bind_passive_slot_active_rejected() -> void:
	_reset()
	if ap: ap.unlocked_skills.append("防御姿态")
	assert_bool(sr.bind_skill(2, "防御姿态")).is_false()

func test_bind_passive_slot_action_rejected() -> void:
	_reset()
	assert_bool(sr.bind_skill(2, "踢击")).is_false()

func test_bind_passive_slot_not_learned_rejected() -> void:
	_reset()
	assert_bool(sr.bind_skill(3, "招架反击")).is_false()

# ---------- 解绑 ----------

func test_unbind_slot() -> void:
	_reset()
	_set_slot(0, "踢击")
	sr.unbind_slot(0)
	assert_str(sr.get_slot_skill(0)).is_equal("")

func test_bind_empty_clears_slot() -> void:
	_reset()
	_set_slot(0, "踢击")
	assert_bool(sr.bind_skill(0, "")).is_true()
	assert_str(sr.get_slot_skill(0)).is_equal("")

# ---------- 已绑定技能查询 ----------

func test_get_bound_active_skills() -> void:
	_reset()
	_set_slot(0, "踢击")
	_set_slot(1, "防御姿态")
	var active: Array = sr.get_bound_active_skills()
	assert_int(active.size()).is_equal(2)
	assert_bool(active.has("踢击")).is_true()
	assert_bool(active.has("防御姿态")).is_true()

func test_get_bound_passive_skills() -> void:
	_reset()
	_set_slot(2, "招架反击")
	_set_slot(3, "魔力涌动")
	var passive: Array = sr.get_bound_passive_skills()
	assert_int(passive.size()).is_equal(2)

# ---------- CD 倒计时 ----------

func test_can_release_on_cd_returns_false() -> void:
	_reset()
	_set_slot(0, "踢击")
	sr.cooldowns["踢击"] = 1.0
	var check: Dictionary = sr.can_release("踢击", "", "")
	assert_bool(check["ok"]).is_false()
	assert_str(check["reason"]).is_equal("冷却中")

func test_tick_reduces_cooldown() -> void:
	_reset()
	sr.cooldowns["踢击"] = 2.0
	sr.tick(0.5)
	assert_float(sr.get_cooldown_remain("踢击")).is_equal(1.5)

func test_tick_cooldown_zero_erases() -> void:
	_reset()
	sr.cooldowns["踢击"] = 1.0
	sr.tick(1.5)
	assert_bool(not sr.cooldowns.has("踢击")).is_true()

func test_get_cooldown_progress_full_when_ready() -> void:
	_reset()
	assert_float(sr.get_cooldown_progress("踢击")).is_equal(1.0)

func test_get_cooldown_progress_zero_at_start() -> void:
	_reset()
	sr.cooldowns["踢击"] = 2.0  # 踢击 CD 2.0
	assert_float(sr.get_cooldown_progress("踢击")).is_equal(0.0)

# ---------- 施法前摇 ----------

func test_start_release_with_cast_time() -> void:
	_reset()
	_set_slot(0, "踢击")  # cast_time 0.3
	var emitted: Array = []
	sr.skill_released.connect(func(sid): emitted.append(sid))
	sr.start_release("踢击", "", "")
	assert_str(sr.casting_skill).is_equal("踢击")
	assert_float(sr.get_cast_remain("踢击")).is_equal(0.3)

func test_tick_completes_cast_emits_signal() -> void:
	_reset()
	_set_slot(0, "踢击")
	var emitted: Array = []
	sr.skill_released.connect(func(sid): emitted.append(sid))
	sr.start_release("踢击", "", "")
	sr.tick(0.3)
	assert_str(sr.casting_skill).is_equal("")
	assert_int(emitted.size()).is_greater(0)
	assert_str(emitted[0]).is_equal("踢击")

func test_casting_blocks_other_release() -> void:
	_reset()
	_set_slot(0, "踢击")
	_set_slot(1, "防御姿态")
	sr.start_release("踢击", "", "")
	var check: Dictionary = sr.can_release("防御姿态", "one_hand_melee", "")
	assert_bool(check["ok"]).is_false()
	assert_str(check["reason"]).is_equal("正在施法其他技能")

func test_complete_release_enters_cooldown() -> void:
	_reset()
	_set_slot(0, "踢击")  # CD 2.0
	sr.start_release("踢击", "", "")
	sr.tick(0.3)
	assert_float(sr.get_cooldown_remain("踢击")).is_equal(2.0)

# ---------- 存档/读档 ----------

func test_serialize_deserialize_roundtrip() -> void:
	_reset()
	_set_slot(0, "踢击")
	_set_slot(2, "招架反击")
	sr.cooldowns["踢击"] = 1.0
	var data: Dictionary = sr.serialize()
	sr.reset()
	sr.deserialize(data)
	assert_str(sr.get_slot_skill(0)).is_equal("踢击")
	assert_str(sr.get_slot_skill(2)).is_equal("招架反击")
	assert_float(sr.get_cooldown_remain("踢击")).is_equal(1.0)

func test_reset_clears_all() -> void:
	_reset()
	_set_slot(0, "踢击")
	sr.cooldowns["x"] = 5.0
	sr.casting_skill = "y"
	sr.reset()
	assert_str(sr.get_slot_skill(0)).is_equal("")
	assert_bool(sr.cooldowns.is_empty()).is_true()
	assert_str(sr.casting_skill).is_equal("")
