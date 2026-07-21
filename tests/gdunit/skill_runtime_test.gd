extends GdUnitTestSuite
## SkillRuntime 技能运行时测试（2 主动 + 5 被动槽位结构）
## 验证：F 槽动作技能无媒介限制、G 槽武器技能受媒介限制、被动槽、CD、施法前摇

const SR := preload("res://globals/combat/skill_runtime.gd")
const SD := preload("res://globals/combat/skill_data.gd")
const AS := preload("res://globals/combat/action_skills.gd")
const RD := preload("res://globals/combat/rune_data.gd")

class MockMomentumActor:
	extends Node
	var velocity := Vector3.ZERO
	var pushback_force := Vector3.ZERO

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

func test_bind_f_slot_weapon_skill_succeeds_when_learned() -> void:
	_reset()
	if ap: ap.unlocked_skills.append("防御姿态")
	assert_bool(sr.bind_skill(0, "防御姿态")).is_true()
	assert_str(sr.get_slot_skill(0)).is_equal("防御姿态")

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

func test_bind_g_slot_action_skill_succeeds() -> void:
	_reset()
	assert_bool(sr.bind_skill(1, "踢击")).is_true()
	assert_str(sr.get_slot_skill(1)).is_equal("踢击")

func test_bind_g_slot_not_learned_rejected() -> void:
	_reset()
	# 未解锁防御姿态
	assert_bool(sr.bind_skill(1, "防御姿态")).is_false()

func test_bind_g_slot_passive_rejected() -> void:
	_reset()
	if ap: ap.unlocked_skills.append("招架反击")
	assert_bool(sr.bind_skill(1, "招架反击")).is_false()

func test_g_slot_no_medium_mismatch_grey() -> void:
	_reset()
	_set_slot(1, "防御姿态")  # 单手剑流派
	var check: Dictionary = sr.can_release("防御姿态", "longbow", "")
	assert_bool(check["ok"]).is_true()
	assert_bool(check.get("grey", false)).is_false()

func test_g_slot_medium_matched_ok() -> void:
	_reset()
	_set_slot(1, "防御姿态")
	var check: Dictionary = sr.can_release("防御姿态", "one_hand_melee", "")
	assert_bool(check["ok"]).is_true()

func test_is_slot_medium_matched_g_slot() -> void:
	_reset()
	_set_slot(1, "防御姿态")
	assert_bool(sr.is_slot_medium_matched(1, "one_hand_melee", "")).is_true()
	assert_bool(sr.is_slot_medium_matched(1, "two_hand", "")).is_true()

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

func test_socket_rune_modifies_active_skill_definition() -> void:
	_reset()
	assert_bool(sr.bind_skill(0, "踢击")).is_true()
	assert_bool(sr.socket_rune(0, "ember")).is_true()
	var effective: Dictionary = sr.get_effective_slot_skill(0)
	assert_float(float(effective.get("damage_mult", 0.0))).is_equal_approx(0.6, 0.001)
	assert_bool(effective.get("rune_effects", {}).has("burn_chance")).is_true()

func test_socket_rune_allows_three_duplicate_runes_for_archetype_builds() -> void:
	_reset()
	assert_int(SR.MAX_RUNES_PER_SLOT).is_equal(3)
	assert_bool(sr.bind_skill(0, "冲撞")).is_true()
	assert_bool(sr.socket_rune(0, "surge")).is_true()
	assert_bool(sr.socket_rune(0, "surge")).is_true()
	assert_bool(sr.socket_rune(0, "surge")).is_true()
	assert_bool(sr.socket_rune(0, "surge")).is_false()
	var runes: Array = sr.get_slot_runes(0)
	assert_array(runes).has_size(3)
	assert_str(runes[0]).is_equal("surge")
	assert_str(runes[1]).is_equal("surge")
	assert_str(runes[2]).is_equal("surge")

func test_kick_build_uses_three_launch_runes() -> void:
	_reset()
	assert_bool(sr.bind_skill(1, "踢击")).is_true()
	assert_bool(sr.socket_rune(1, "launch")).is_true()
	assert_bool(sr.socket_rune(1, "launch")).is_true()
	assert_bool(sr.socket_rune(1, "launch")).is_true()
	var effective: Dictionary = sr.get_effective_slot_skill(1)
	assert_float(float(effective.get("knockback_m", 0.0))).is_greater(1.5)
	assert_float(float(effective.get("physical_impact_damage_mult", 0.0))).is_greater(1.0)

func test_socket_rune_modifies_passive_skill_definition() -> void:
	_reset()
	if ap: ap.unlocked_skills.append("招架反击")
	assert_bool(sr.bind_skill(2, "招架反击")).is_true()
	assert_bool(sr.socket_rune(2, "guardian")).is_true()
	var effective: Dictionary = sr.get_effective_slot_skill(2)
	assert_float(float(effective.get("damage_mult", 0.0))).is_equal_approx(0.8, 0.001)
	assert_bool(effective.get("rune_effects", {}).has("passive_guard")).is_true()

func test_passive_slots_accept_only_two_runes() -> void:
	_reset()
	if ap: ap.unlocked_skills.append("招架反击")
	assert_int(sr.get_rune_capacity(0)).is_equal(3)
	assert_int(sr.get_rune_capacity(2)).is_equal(2)
	assert_bool(sr.bind_skill(2, "招架反击")).is_true()
	assert_bool(sr.socket_rune(2, "guardian")).is_true()
	assert_bool(sr.socket_rune(2, "guardian")).is_true()
	assert_bool(sr.socket_rune(2, "guardian")).is_false()
	assert_array(sr.get_slot_runes(2)).has_size(2)

func test_start_release_uses_slot_specific_rune_context() -> void:
	_reset()
	assert_bool(sr.bind_skill(0, "踢击")).is_true()
	assert_bool(sr.bind_skill(1, "踢击")).is_true()
	assert_bool(sr.socket_rune(1, "quick")).is_true()
	assert_bool(sr.start_release("踢击", "", "", null, 1)).is_true()
	assert_float(sr.get_cooldown_remain("踢击")).is_equal_approx(1.6, 0.001)

# ---------- 施法前摇 ----------

func test_start_release_with_cast_time() -> void:
	_reset()
	_set_slot(0, "抓取投掷")  # cast_time 0.4
	var emitted: Array = []
	sr.skill_released.connect(func(sid): emitted.append(sid))
	sr.start_release("抓取投掷", "", "")
	assert_str(sr.casting_skill).is_equal("抓取投掷")
	assert_float(sr.get_cast_remain("抓取投掷")).is_equal(0.4)

func test_tick_completes_cast_emits_signal() -> void:
	_reset()
	_set_slot(0, "抓取投掷")
	var emitted: Array = []
	sr.skill_released.connect(func(sid): emitted.append(sid))
	sr.start_release("抓取投掷", "", "")
	sr.tick(0.4)
	assert_str(sr.casting_skill).is_equal("")
	assert_int(emitted.size()).is_greater(0)
	assert_str(emitted[0]).is_equal("抓取投掷")

func test_casting_blocks_other_release() -> void:
	_reset()
	_set_slot(0, "抓取投掷")
	_set_slot(1, "防御姿态")
	sr.start_release("抓取投掷", "", "")
	var check: Dictionary = sr.can_release("防御姿态", "one_hand_melee", "")
	assert_bool(check["ok"]).is_false()
	assert_str(check["reason"]).is_equal("正在施法其他技能")

func test_complete_release_enters_cooldown() -> void:
	_reset()
	_set_slot(0, "踢击")  # CD 2.0
	sr.start_release("踢击", "", "")
	assert_float(sr.get_cooldown_remain("踢击")).is_equal(2.0)

func test_cancel_denied_before_cancel_window() -> void:
	_reset()
	assert_bool(sr.can_cancel("滑铲", "踢击", 0.1)).is_false()

func test_cancel_allowed_inside_cancel_window() -> void:
	_reset()
	assert_bool(sr.can_cancel("滑铲", "踢击", 0.2)).is_true()

func test_weapon_active_skill_has_default_cancel_window() -> void:
	_reset()
	assert_bool(sr.can_cancel("防御姿态", "踢击", 0.4)).is_true()
	assert_bool(sr.can_cancel("防御姿态", "踢击", 0.1)).is_false()

func test_release_on_start_keeps_skill_active_for_cancel_window() -> void:
	_reset()
	var emitted: Array = []
	sr.skill_released.connect(func(sid): emitted.append(sid))
	assert_bool(sr.start_release("滑铲", "", "")).is_true()
	assert_int(emitted.size()).is_equal(1)
	assert_str(emitted[0]).is_equal("滑铲")
	assert_str(sr.casting_skill).is_equal("滑铲")
	assert_float(sr.get_cast_remain("滑铲")).is_equal(0.5)

func test_start_release_cancels_and_stores_momentum_context() -> void:
	_reset()
	var actor := MockMomentumActor.new()
	actor.velocity = Vector3(0, 0, -6)
	actor.pushback_force = Vector3(0, 0, -4)
	assert_bool(sr.start_release("滑铲", "", "", actor)).is_true()
	sr.tick(0.2)
	assert_bool(sr.start_release("踢击", "", "", actor)).is_true()
	assert_str(sr.casting_skill).is_equal("")
	var ctx = sr.consume_momentum_context()
	assert_object(ctx).is_not_null()
	assert_str(ctx.source_skill_id).is_equal("滑铲")
	assert_float(ctx.compute_strength(Vector3(0, 0, -1))).is_greater(6.0)
	actor.free()

# ---------- 存档/读档 ----------

func test_serialize_deserialize_roundtrip() -> void:
	_reset()
	_set_slot(0, "踢击")
	_set_slot(2, "招架反击")
	assert_bool(sr.socket_rune(0, "quick")).is_true()
	sr.cooldowns["踢击"] = 1.0
	var data: Dictionary = sr.serialize()
	sr.reset()
	sr.deserialize(data)
	assert_str(sr.get_slot_skill(0)).is_equal("踢击")
	assert_str(sr.get_slot_skill(2)).is_equal("招架反击")
	assert_array(sr.get_slot_runes(0)).contains("quick")
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

# ---------- 默认绑定回归测试 ----------

func test_default_f_slot_skill_constant_exists() -> void:
	assert_str(SR.DEFAULT_F_SLOT_SKILL).is_equal("踢击")

func test_ready_binds_default_kick_to_empty_f_slot() -> void:
	_reset()
	assert_str(sr.get_slot_skill(SR.SLOT_F_ACTION)).is_equal("")
	# 模拟 _ready 的行为：空槽时绑定默认踢击
	sr.bind_skill(SR.SLOT_F_ACTION, SR.DEFAULT_F_SLOT_SKILL)
	assert_str(sr.get_slot_skill(SR.SLOT_F_ACTION)).is_equal("踢击")

func test_ready_does_not_overwrite_existing_f_slot() -> void:
	_reset()
	_set_slot(0, "冲撞")
	# 模拟 _ready 的行为：已有技能时不覆盖
	if sr.get_slot_skill(SR.SLOT_F_ACTION) == "":
		sr.bind_skill(SR.SLOT_F_ACTION, SR.DEFAULT_F_SLOT_SKILL)
	assert_str(sr.get_slot_skill(SR.SLOT_F_ACTION)).is_equal("冲撞")

func test_player_handle_skill_input_has_fallback_for_empty_f_slot() -> void:
	# 验证 player.gd 的 _handle_skill_input 在 F 槽为空时回退到默认踢击
	var source := FileAccess.get_file_as_string("res://scenes/characters/player/player.gd")
	assert_bool(source.contains('if f_skill == "":')).is_true() \
		.override_failure_message("_handle_skill_input 必须在 F 槽为空时回退到默认技能")
	assert_bool(source.contains('f_skill = sr.DEFAULT_F_SLOT_SKILL')).is_true() \
		.override_failure_message("_handle_skill_input 必须引用 DEFAULT_F_SLOT_SKILL 作为回退")

func test_player_handle_skill_input_checks_equipment_null() -> void:
	# 验证 player.gd 的 _handle_skill_input 对 equipment 做了 null 检查
	var source := FileAccess.get_file_as_string("res://scenes/characters/player/player.gd")
	assert_bool(source.contains('equipment != null and equipment.has_weapon()')).is_true() \
		.override_failure_message("_handle_skill_input 必须在调用 has_weapon 前检查 equipment != null")
