extends GdUnitTestSuite

# 熟练度阶梯系统测试（docs/36-出身系统与涌现式Build.md §3）
# 覆盖：熟练度累积与封顶、阶梯阈值解锁（20/40/60/80/100）、加成计算、存档/读档、出身起跑集成。

const ATTR_PANEL_SCRIPT := preload("res://globals/combat/attr_panel.gd")
const OD := preload("res://globals/combat/origin_data.gd")

const EPS := 0.001

var _ap

func before_test() -> void:
	_ap = auto_free(ATTR_PANEL_SCRIPT.new())


# ============================================================================
# 1. 熟练度累积与封顶
# ============================================================================

func test_accumulate_proficiency_adds_value() -> void:
	_ap.accumulate_proficiency("sword", 15)
	assert_int(_ap.get_proficiency("sword")).is_equal(15)


func test_accumulate_proficiency_caps_at_100() -> void:
	_ap.accumulate_proficiency("sword", 150)
	assert_int(_ap.get_proficiency("sword")).is_equal(100)


func test_accumulate_proficiency_incremental() -> void:
	_ap.accumulate_proficiency("bow", 10)
	_ap.accumulate_proficiency("bow", 15)
	assert_int(_ap.get_proficiency("bow")).is_equal(25)


func test_get_proficiency_unknown_returns_zero() -> void:
	assert_int(_ap.get_proficiency("nonexistent")).is_equal(0)


# ============================================================================
# 2. 阶梯阈值解锁
# ============================================================================

func test_milestone_unlocked_at_20() -> void:
	_ap.accumulate_proficiency("sword", 20)
	var unlocked: Array = _ap.proficiency_milestones.get("sword", [])
	assert_bool(unlocked.has(20)).is_true()
	# 40 尚未解锁
	assert_bool(unlocked.has(40)).is_false()


func test_all_milestones_unlocked_at_100() -> void:
	_ap.accumulate_proficiency("bow", 100)
	var unlocked: Array = _ap.proficiency_milestones.get("bow", [])
	for threshold in [20, 40, 60, 80, 100]:
		assert_bool(unlocked.has(threshold)).is_true()


func test_milestone_not_unlocked_below_threshold() -> void:
	_ap.accumulate_proficiency("sword", 19)
	var unlocked: Array = _ap.proficiency_milestones.get("sword", [])
	assert_bool(unlocked.has(20)).is_false()


func test_milestones_independent_per_weapon_type() -> void:
	_ap.accumulate_proficiency("sword", 60)
	_ap.accumulate_proficiency("bow", 20)
	var sword_unlocked: Array = _ap.proficiency_milestones.get("sword", [])
	var bow_unlocked: Array = _ap.proficiency_milestones.get("bow", [])
	assert_bool(sword_unlocked.has(60)).is_true()
	assert_bool(bow_unlocked.has(60)).is_false()
	assert_bool(bow_unlocked.has(20)).is_true()


# ============================================================================
# 3. 加成计算
# ============================================================================

func test_get_proficiency_bonus_no_milestones() -> void:
	var bonus: Dictionary = _ap.get_proficiency_bonus("sword")
	assert_float(float(bonus["damage_mult"])).is_equal_approx(1.0, EPS)
	assert_float(float(bonus["attack_speed_mult"])).is_equal_approx(1.0, EPS)
	assert_float(float(bonus["crit_bonus"])).is_equal_approx(0.0, EPS)
	assert_bool(bool(bonus["master_passive"])).is_false()


func test_get_proficiency_bonus_damage_mult_at_20() -> void:
	_ap.accumulate_proficiency("sword", 20)
	var bonus: Dictionary = _ap.get_proficiency_bonus("sword")
	# 20: +5% damage
	assert_float(float(bonus["damage_mult"])).is_equal_approx(1.05, EPS)


func test_get_proficiency_bonus_attack_speed_at_40() -> void:
	_ap.accumulate_proficiency("sword", 40)
	var bonus: Dictionary = _ap.get_proficiency_bonus("sword")
	# 40: +5% attack speed
	assert_float(float(bonus["attack_speed_mult"])).is_equal_approx(1.05, EPS)


func test_get_proficiency_bonus_crit_at_60() -> void:
	_ap.accumulate_proficiency("sword", 60)
	var bonus: Dictionary = _ap.get_proficiency_bonus("sword")
	# 60: +3% crit
	assert_float(float(bonus["crit_bonus"])).is_equal_approx(3.0, EPS)


func test_get_proficiency_bonus_master_at_80() -> void:
	_ap.accumulate_proficiency("sword", 80)
	var bonus: Dictionary = _ap.get_proficiency_bonus("sword")
	assert_bool(bool(bonus["master_passive"])).is_true()


func test_get_proficiency_bonus_full_at_100() -> void:
	_ap.accumulate_proficiency("sword", 100)
	var bonus: Dictionary = _ap.get_proficiency_bonus("sword")
	# 20 + 100: +5% + 10% = +15% damage
	assert_float(float(bonus["damage_mult"])).is_equal_approx(1.15, EPS)
	# 40 + 100: +5% + 5% = +10% attack speed
	assert_float(float(bonus["attack_speed_mult"])).is_equal_approx(1.10, EPS)
	assert_float(float(bonus["crit_bonus"])).is_equal_approx(3.0, EPS)
	assert_bool(bool(bonus["master_passive"])).is_true()


# ============================================================================
# 4. 大师级被动查询
# ============================================================================

func test_has_master_proficiency_false_initially() -> void:
	assert_bool(_ap.has_master_proficiency("sword")).is_false()


func test_has_master_proficiency_true_at_80() -> void:
	_ap.accumulate_proficiency("sword", 80)
	assert_bool(_ap.has_master_proficiency("sword")).is_true()


func test_has_master_proficiency_false_below_80() -> void:
	_ap.accumulate_proficiency("sword", 79)
	assert_bool(_ap.has_master_proficiency("sword")).is_false()


# ============================================================================
# 5. 存档/读档
# ============================================================================

func test_proficiency_milestones_serialize_deserialize() -> void:
	_ap.accumulate_proficiency("sword", 60)
	var data: Dictionary = _ap.serialize()
	var ap2 = auto_free(ATTR_PANEL_SCRIPT.new())
	ap2.deserialize(data)
	var unlocked: Array = ap2.proficiency_milestones.get("sword", [])
	assert_bool(unlocked.has(20)).is_true()
	assert_bool(unlocked.has(40)).is_true()
	assert_bool(unlocked.has(60)).is_true()
	assert_int(ap2.get_proficiency("sword")).is_equal(60)


func test_origin_id_serialize_deserialize() -> void:
	_ap.origin_id = "half_baked_warlock"
	var data: Dictionary = _ap.serialize()
	var ap2 = auto_free(ATTR_PANEL_SCRIPT.new())
	ap2.deserialize(data)
	assert_str(ap2.origin_id).is_equal("half_baked_warlock")


func test_old_save_without_origin_fields_compat() -> void:
	# 旧存档不含 origin_id / proficiency_milestones，应兼容默认值
	var old_data := {"attrs": {"str": 7}, "level": 3}
	var ap2 = auto_free(ATTR_PANEL_SCRIPT.new())
	ap2.deserialize(old_data)
	assert_str(ap2.origin_id).is_equal("")
	assert_bool(ap2.proficiency_milestones.is_empty()).is_true()


# ============================================================================
# 6. 出身起跑集成
# ============================================================================

func test_origin_headstart_sets_proficiency() -> void:
	OD.apply_origin(_ap, "retired_mercenary")
	assert_int(_ap.get_proficiency("sword")).is_equal(2)


func test_origin_headstart_below_milestone_no_unlock() -> void:
	OD.apply_origin(_ap, "retired_mercenary")
	# 起跑值 2 < 20，不应解锁阶梯
	var unlocked: Array = _ap.proficiency_milestones.get("sword", [])
	assert_bool(unlocked.is_empty()).is_true()


func test_skill_unlock_uses_shared_weapon_category_key() -> void:
	_ap.attrs["str"] = 15
	_ap.accumulate_proficiency("sword", 3)
	var unlocked: Array = _ap.check_skill_unlocks()
	assert_array(unlocked).contains("防御姿态")
	assert_bool(_ap.has_skill("防御姿态")).is_true()


func test_reset_clears_proficiency_and_origin() -> void:
	_ap.accumulate_proficiency("sword", 60)
	_ap.origin_id = "forest_hunter"
	_ap.reset()
	assert_bool(_ap.proficiency_milestones.is_empty()).is_true()
	assert_int(_ap.get_proficiency("sword")).is_equal(0)
	assert_str(_ap.origin_id).is_equal("")
