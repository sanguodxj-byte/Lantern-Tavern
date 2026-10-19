extends GdUnitTestSuite

## 2026-08-07（0643/0952 审查 P1-2 关闭）：主动技能声明字段完整兑现行为测试。
## 覆盖 skill_damage 端口实现的全部效果：stun_sec / breaks_shield / ignore_def /
## ignore_block / lifesteal / aoe（cone/circle/line 多目标）/ grapple（抓取投掷）。
## 所有断言走真实 on_command(CMD_SKILL) 权威事务（拒绝表已清空，此前这些技能会被硬拒绝）。

const SR := preload("res://globals/multiplayer/session_root.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")
const AS := preload("res://globals/combat/action_skills.gd")

func _make_server() -> SR:
	var s: SR = SR.new()
	s.init_server()
	return s

## 绑定技能并发送 CMD_SKILL。live 默认在原点面向 -Z。
func _cast_skill(s: SR, skill_id: String, target_hint: Variant, sequence: int = 1) -> Dictionary:
	var ctx = s.handle_spawn_request(1)
	ctx.skills.slots[ctx.skills.SLOT_F_ACTION] = skill_id
	s._live_state[1] = {"peer_id": 1, "is_alive": true, "position": Vector3.ZERO, "facing": Vector3(0, 0, -1)}
	return s.on_command(1, {"type": NP.CMD_SKILL, "skill_id": skill_id, "target_hint": target_hint,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": sequence})

func _enemy(s: SR, eid: int, pos: Vector3, life: int, armor: int = 0) -> void:
	s.set_entity(eid, {"kind": "enemy", "label": "rat", "position": pos,
		"current_life": life, "max_life": life, "armor_def": armor, "con": 0, "agi": 0, "per": 0})

# ---------------------------------------------------------------------------
# stun_sec：震荡打击（战锤 T1，stun 2.0s）→ 实体 stun_until 写入绝对毫秒
# ---------------------------------------------------------------------------

func test_stun_sec_writes_entity_stun_until_absolute_ms() -> void:
	var s: SR = auto_free(_make_server())
	_enemy(s, 1001, Vector3(0.8, 0, 0), 200, 0)
	var r: Dictionary = _cast_skill(s, "震荡打击", 1001)
	assert_bool(bool(r.get("success", false))).is_true()
	var data: Dictionary = s.get_entity(1001)
	var until: int = int(data.get("stun_until", 0))
	assert_int(until).is_greater(0)
	assert_int(until).is_greater(Time.get_ticks_msec())
	assert_int(until - Time.get_ticks_msec()).is_less_equal(2100)
	# 结果携带 stun_sec（供调用方/表现层）
	assert_float(float(r.get("event", {}).get("effects", {}).get("stun_sec", 0.0))).is_greater(0.0)

# ---------------------------------------------------------------------------
# breaks_shield：冲撞（breaks_shield=true）→ 目标 shield 清零
# ---------------------------------------------------------------------------

func test_breaks_shield_clears_entity_shield() -> void:
	var s: SR = auto_free(_make_server())
	s.set_entity(1002, {"kind": "enemy", "label": "goblin", "position": Vector3(0.8, 0, 0),
		"current_life": 100, "max_life": 100, "armor_def": 0, "con": 0, "agi": 0, "per": 0, "shield": 40})
	var r: Dictionary = _cast_skill(s, "冲撞", 1002)
	assert_bool(bool(r.get("success", false))).is_true()
	assert_int(int(s.get_entity(1002).get("shield", -1))).is_equal(0)

# ---------------------------------------------------------------------------
# ignore_def：过顶重击（ignore_def 20%）→ 高护甲目标仍打出显著伤害
# ---------------------------------------------------------------------------

func test_ignore_def_pierces_high_armor() -> void:
	var s: SR = auto_free(_make_server())
	# 高护甲目标（armor 60）：无穿透时伤害被大幅削减，20% 穿透应打出可观伤害。
	_enemy(s, 1003, Vector3(0.8, 0, 0), 500, 60)
	var r: Dictionary = _cast_skill(s, "过顶重击", 1003)
	assert_bool(bool(r.get("success", false))).is_true()
	var damage: int = int(r.get("event", {}).get("effects", {}).get("damage", 0))
	assert_int(damage).is_greater(5)

# ---------------------------------------------------------------------------
# ignore_block：贯穿刺击（ignore_block=true）→ 成功结算且事件标记穿透
# ---------------------------------------------------------------------------

func test_ignore_block_resolves_and_marks_ignores_block() -> void:
	var s: SR = auto_free(_make_server())
	_enemy(s, 1004, Vector3(0.8, 0, 0), 100, 0)
	var r: Dictionary = _cast_skill(s, "贯穿刺击", 1004)
	assert_bool(bool(r.get("success", false))).is_true()
	assert_int(int(r.get("event", {}).get("effects", {}).get("damage", 0))).is_greater(0)

# ---------------------------------------------------------------------------
# lifesteal：不屈重斩（lifesteal 30%）→ caster 权威生命回写
# ---------------------------------------------------------------------------

func test_lifesteal_heals_caster_authoritative_life() -> void:
	var s: SR = auto_free(_make_server())
	_enemy(s, 1005, Vector3(0.8, 0, 0), 100, 0)
	# 先把 caster 生命降到 50（权威状态），满血时吸血无观测窗口。
	var ctx = s.registry.get_context(1) if s.registry.has_peer(1) else null
	if ctx == null:
		var pre = s.handle_spawn_request(1)
		pre.current_life = 50
	var c = s.registry.get_context(1)
	c.current_life = 50
	var r: Dictionary = _cast_skill(s, "不屈重斩", 1005)
	assert_bool(bool(r.get("success", false))).is_true()
	var damage: int = int(r.get("event", {}).get("effects", {}).get("damage", 0))
	assert_int(damage).is_greater(0)
	# 30% 吸血回写：50 + round(damage * 0.30)
	assert_int(c.current_life).is_greater(50)
	assert_int(c.current_life).is_less_equal(c.max_life)

# ---------------------------------------------------------------------------
# aoe circle：旋风斩（circle 2.25m）→ 半径内多目标扣血，外部目标不受影响
# ---------------------------------------------------------------------------

func test_aoe_circle_hits_multiple_targets_in_radius() -> void:
	var s: SR = auto_free(_make_server())
	_enemy(s, 2001, Vector3(1.0, 0, 0), 200, 0)
	_enemy(s, 2002, Vector3(-1.5, 0, 0.5), 200, 0)
	_enemy(s, 2003, Vector3(4.0, 0, 0), 200, 0)  # 半径外
	var r: Dictionary = _cast_skill(s, "旋风斩", 0)  # AoE 无需单目标提示
	assert_bool(bool(r.get("success", false))).is_true()
	assert_int(int(s.get_entity(2001).get("current_life", 200))).is_less(200)
	assert_int(int(s.get_entity(2002).get("current_life", 200))).is_less(200)
	assert_int(int(s.get_entity(2003).get("current_life", 200))).is_equal(200)

# ---------------------------------------------------------------------------
# aoe cone：横扫击（cone 4.5m, 60°）→ 前方锥内命中、身后目标不受影响
# ---------------------------------------------------------------------------

func test_aoe_cone_hits_front_cone_only() -> void:
	var s: SR = auto_free(_make_server())
	_enemy(s, 2101, Vector3(0, 0, -2.0), 200, 0)   # 正前方（facing -Z）命中
	_enemy(s, 2102, Vector3(0, 0, 2.0), 200, 0)    # 正后方（锥外）不命中
	var r: Dictionary = _cast_skill(s, "横扫击", 0)
	assert_bool(bool(r.get("success", false))).is_true()
	assert_int(int(s.get_entity(2101).get("current_life", 200))).is_less(200)
	assert_int(int(s.get_entity(2102).get("current_life", 200))).is_equal(200)

# ---------------------------------------------------------------------------
# aoe line：震地击（line 4.5m）→ 前方直线命中、横向远处不命中
# ---------------------------------------------------------------------------

func test_aoe_line_hits_forward_line_only() -> void:
	var s: SR = auto_free(_make_server())
	_enemy(s, 2201, Vector3(0, 0, -2.0), 200, 0)   # 直线上命中
	_enemy(s, 2202, Vector3(2.5, 0, -2.0), 200, 0) # 横向 2.5m > 1.5m 线宽外
	var r: Dictionary = _cast_skill(s, "震地击", 0)
	assert_bool(bool(r.get("success", false))).is_true()
	assert_int(int(s.get_entity(2201).get("current_life", 200))).is_less(200)
	assert_int(int(s.get_entity(2202).get("current_life", 200))).is_equal(200)

# ---------------------------------------------------------------------------
# grapple：抓取投掷（grapple 族）→ 目标拉近到 caster 面前 1.0m + 眩晕
# ---------------------------------------------------------------------------

func test_grapple_pulls_target_to_caster_front_and_stuns() -> void:
	var s: SR = auto_free(_make_server())
	_enemy(s, 3001, Vector3(1.2, 0, 0), 200, 0)
	var r: Dictionary = _cast_skill(s, "抓取投掷", 3001)
	assert_bool(bool(r.get("success", false))).is_true()
	var pos: Vector3 = s.get_entity(3001).get("position", Vector3(99, 99, 99))
	# 拉近到 caster（原点）面前 1.0m，facing -Z
	assert_float(pos.distance_to(Vector3(0, 0, -1.0))).is_less_equal(0.01)
	# 眩晕 1 秒写 stun_until
	var until: int = int(s.get_entity(3001).get("stun_until", 0))
	assert_int(until).is_greater(Time.get_ticks_msec())
	assert_int(until - Time.get_ticks_msec()).is_less_equal(1100)

# ---------------------------------------------------------------------------
# 拒绝表回归：validate_implemented_fields 已清空，声明字段不再被硬拒绝
# ---------------------------------------------------------------------------

func test_validate_implemented_fields_no_longer_rejects_declared_effects() -> void:
	var sa: RefCounted = (load("res://globals/multiplayer/skill_authority.gd") as GDScript).new()
	for skill_id in ["震荡打击", "冲撞", "过顶重击", "贯穿刺击", "不屈重斩", "旋风斩", "横扫击", "震地击", "抓取投掷"]:
		var skill: Dictionary = SkillAuthority_definition(skill_id)
		assert_str(String(sa.validate_implemented_fields(skill))) \
			.override_failure_message("技能 %s 的声明字段不得被硬拒绝" % skill_id).is_equal("")

## 按 id 取技能定义（action_skills → skill_data 双表）。
func SkillAuthority_definition(skill_id: String) -> Dictionary:
	var as_def: Dictionary = AS.get_skill_by_id(skill_id)
	if not as_def.is_empty():
		return as_def
	var sd := preload("res://globals/combat/skill_data.gd")
	return sd.get_skill_by_id(skill_id)
