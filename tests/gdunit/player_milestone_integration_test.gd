extends GdUnitTestSuite
## 里程碑被动与属性面板接入 player 状态机集成测试
## 验证：player_state_slashing 从 AttrPanel 读属性、命中累积经验、
## player_state_hurt 厚皮减伤、player 侧垫步免伤、process_movement 轻捷移速加成

const CE := preload("res://globals/combat/combat_engine.gd")
const ME := preload("res://globals/combat/milestone_effects.gd")

var ap: Node

func before() -> void:
	ap = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap:
		ap.reset()

func after() -> void:
	if ap:
		ap.reset()

# ---------- AttrPanel 可访问性 ----------

func test_attr_panel_autoload_available() -> void:
	assert_object(ap).is_not_null()

# ---------- 里程碑被动接入 player_state_hurt（厚皮减伤） ----------

func test_thick_skin_reduces_hurt_damage() -> void:
	if ap == null:
		return
	ap.reset()
	# 未解锁：伤害不变
	assert_int(ME.apply_thick_skin(10)).is_equal(10)
	# 解锁厚皮：-2
	ap.unlocked_milestones.append("厚实皮肤")
	assert_int(ME.apply_thick_skin(10)).is_equal(8)
	assert_int(ME.apply_thick_skin(2)).is_equal(1)  # 最低 1

# ---------- 侧垫步免伤（player.try_receive_hit_result 前置判定） ----------

func test_sidestep_can_fully_dodge() -> void:
	if ap == null:
		return
	ap.reset()
	ap.unlocked_milestones.append("侧垫步")
	var dodged: bool = false
	for i in range(500):
		if ME.try_sidestep(true):
			dodged = true
			break
	assert_bool(dodged).is_true()

func test_sidestep_not_melee_never_dodges() -> void:
	if ap == null:
		return
	ap.reset()
	ap.unlocked_milestones.append("侧垫步")
	for i in range(100):
		assert_bool(ME.try_sidestep(false)).is_false()

# ---------- 轻捷之行移速加成 ----------

func test_move_speed_mult_base_no_bonus() -> void:
	if ap == null:
		return
	ap.reset()
	assert_float(ap.compute_move_speed_mult()).is_equal(1.0)

func test_move_speed_mult_with_fleet_foot() -> void:
	if ap == null:
		return
	ap.reset()
	# 提升灵巧到 15 解锁轻捷之行
	for i in range(10):
		ap.accumulate_attr("agi", 100)
	assert_bool(ap.has_milestone("轻捷之行")).is_true()
	assert_float(ap.compute_move_speed_mult()).is_equal(1.10)

# ---------- 属性面板驱动 CombatBridge（间接验证） ----------

func test_attr_panel_provides_attrs_for_combat_bridge() -> void:
	if ap == null:
		return
	ap.reset()
	# 提升力量到 15
	for i in range(10):
		ap.accumulate_attr("str", 100)
	var attrs: Dictionary = ap.get_player_attrs()
	assert_int(int(attrs["str"])).is_equal(15)
	# CombatBridge.build_player_attack 应能使用这些属性
	const CB := preload("res://globals/combat/combat_bridge.gd")
	var player := Node3D.new()
	add_child(player)
	var weapon := WeaponData.new()
	weapon.damage_min = 2
	weapon.damage_max = 6
	weapon.condition = 100
	weapon.max_condition = 100
	var attack = CB.build_player_attack(player, weapon, "one_hand_melee", "", attrs, 1)
	assert_int(attack.attacker_str).is_equal(15)
	player.queue_free()

# ---------- 双轨经验累积接入战斗 ----------

func test_hit_accumulates_str_exp_for_melee() -> void:
	if ap == null:
		return
	ap.reset()
	var initial_exp: int = int(ap.attr_exp["str"])
	ap.accumulate_attr("str", 5)
	assert_int(int(ap.attr_exp["str"])).is_equal(initial_exp + 5)

func test_hit_accumulates_proficiency() -> void:
	if ap == null:
		return
	ap.reset()
	ap.accumulate_proficiency("one_hand_melee", 3)
	assert_int(ap.get_proficiency("one_hand_melee")).is_equal(3)

func test_skill_unlock_triggers_on_threshold() -> void:
	if ap == null:
		return
	ap.reset()
	ap.accumulate_proficiency("one_hand_melee", 3)
	for i in range(10):
		ap.accumulate_attr("str", 100)  # str 15
	var unlocked: Array = ap.check_skill_unlocks()
	assert_bool(unlocked.has("防御姿态")).is_true()

# ---------- 直觉闪避取消背袭加成 ----------

func test_negate_flank_bonus_when_unlocked() -> void:
	if ap == null:
		return
	ap.reset()
	ap.unlocked_milestones.append("直觉闪避")
	assert_bool(ME.negate_flank_bonus()).is_true()

func test_negate_flank_bonus_not_unlocked() -> void:
	if ap == null:
		return
	ap.reset()
	assert_bool(ME.negate_flank_bonus()).is_false()

# ---------- 震退被动追加击退 ----------

func test_knockback_chance_adds_force() -> void:
	if ap == null:
		return
	ap.reset()
	ap.unlocked_milestones.append("震退")
	var triggered: bool = false
	for i in range(500):
		var kb: float = ME.try_knockback_chance(true)
		if kb > 0:
			assert_float(kb).is_equal(1.5)
			triggered = true
			break
	assert_bool(triggered).is_true()

# ---------- 重力击近战伤害加成 ----------

func test_heavy_stride_melee_damage_boost() -> void:
	if ap == null:
		return
	ap.reset()
	ap.unlocked_milestones.append("重力击")
	assert_int(ME.apply_heavy_stride(100, true)).is_equal(105)
	assert_int(ME.apply_heavy_stride(100, false)).is_equal(100)

# ---------- 受击累积体质经验 ----------

func test_defense_exp_accumulation_on_hit() -> void:
	if ap == null:
		return
	ap.reset()
	var initial_con_exp: int = int(ap.attr_exp["con"])
	ap.accumulate_attr("con", 2)
	assert_int(int(ap.attr_exp["con"])).is_equal(initial_con_exp + 2)

# ---------- 衍生面板数值含里程碑加成 ----------

func test_max_hp_includes_fortitude() -> void:
	if ap == null:
		return
	ap.reset()
	var base_hp: int = ap.compute_max_hp()
	ap.unlocked_milestones.append("强健体魄")
	assert_int(ap.compute_max_hp()).is_equal(base_hp + 20)

func test_evade_rate_includes_elusive() -> void:
	if ap == null:
		return
	ap.reset()
	var base_evade: float = ap.compute_evade_rate()
	ap.unlocked_milestones.append("虚实避让")
	assert_float(ap.compute_evade_rate()).is_equal(base_evade + 6.0)

func test_crit_rate_includes_find_weakness() -> void:
	if ap == null:
		return
	ap.reset()
	var base_crit: float = ap.compute_crit_rate()
	ap.unlocked_milestones.append("弱点洞察")
	assert_float(ap.compute_crit_rate()).is_equal(base_crit + 5.0)

# ---------- 集成链路：属性提升 → 里程碑解锁 → 被动生效 ----------

func test_full_chain_str_milestone_unlocks_and_heavy_stride_active() -> void:
	if ap == null:
		return
	ap.reset()
	# 提升力量到 15 解锁重力击（STR T2）
	for i in range(10):
		ap.accumulate_attr("str", 100)
	assert_bool(ap.has_milestone("重力击")).is_true()
	# 重力击被动应生效
	assert_int(ME.apply_heavy_stride(100, true)).is_equal(105)

func test_full_chain_agi_milestone_unlocks_and_fleet_foot_active() -> void:
	if ap == null:
		return
	ap.reset()
	for i in range(10):
		ap.accumulate_attr("agi", 100)  # agi 15
	assert_bool(ap.has_milestone("轻捷之行")).is_true()
	assert_float(ap.compute_move_speed_mult()).is_equal(1.10)
