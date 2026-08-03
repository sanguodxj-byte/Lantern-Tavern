extends GdUnitTestSuite
## 符文机制触发系统（RuneEffectHooks）测试套件。
## 覆盖：被动加成查询/类型伤害倍率/空值安全。

const REH := preload("res://globals/combat/rune_effect_hooks.gd")
const RD := preload("res://globals/combat/rune_data.gd")
const SES := preload("res://globals/combat/status_effect_system.gd")

## 模拟敌人
class MockEnemy:
	extends Node3D
	var combat_debuffs: Dictionary = {}
	var health: MockHealth

class MockHealth:
	extends Node
	var current_life: int = 100
	var max_life: int = 100
	func take_damage(dmg: int) -> void:
		current_life = maxi(0, current_life - dmg)
	func heal(amount: int) -> void:
		current_life = mini(max_life, current_life + amount)

func _make_enemy() -> MockEnemy:
	var e := MockEnemy.new()
	e.health = MockHealth.new()
	e.add_child(e.health)
	return auto_free(e)

# ---------- 被动加成查询 ----------

func test_get_passive_bonuses_returns_default_structure() -> void:
	var bonuses := REH.get_passive_bonuses()
	# 即使没有装备符文，也应返回包含所有键的字典
	assert_bool(bonuses.has("hp_regen_per_sec")).is_true()
	assert_bool(bonuses.has("stamina_regen_per_sec")).is_true()
	assert_bool(bonuses.has("lifesteal_pct")).is_true()
	assert_bool(bonuses.has("dodge_chance")).is_true()
	assert_bool(bonuses.has("cc_immune")).is_true()
	assert_bool(bonuses.has("damage_reduce_pct")).is_true()
	assert_bool(bonuses.has("death_save")).is_true()
	assert_bool(bonuses.has("fear_resist")).is_true()
	assert_bool(bonuses.has("stun_resist")).is_true()
	assert_bool(bonuses.has("dark_dmg_mult")).is_true()
	assert_bool(bonuses.has("holy_dmg_mult")).is_true()
	assert_bool(bonuses.has("undead_dmg_mult")).is_true()
	assert_bool(bonuses.has("righteous_dmg_mult")).is_true()
	assert_bool(bonuses.has("fear_dmg_mult")).is_true()

func test_get_passive_bonuses_default_values() -> void:
	var bonuses := REH.get_passive_bonuses()
	assert_float(float(bonuses["hp_regen_per_sec"])).is_equal_approx(0.0, 0.001)
	assert_float(float(bonuses["lifesteal_pct"])).is_equal_approx(0.0, 0.001)
	assert_bool(bool(bonuses["cc_immune"])).is_false()
	assert_bool(bool(bonuses["death_save"])).is_false()
	assert_float(float(bonuses["dark_dmg_mult"])).is_equal_approx(1.0, 0.001)
	assert_float(float(bonuses["holy_dmg_mult"])).is_equal_approx(1.0, 0.001)

# ---------- 类型伤害倍率 ----------

func test_get_damage_mult_vs_type_no_meta() -> void:
	var e := _make_enemy()
	assert_float(REH.get_damage_mult_vs_type(e, "undead")).is_equal_approx(1.0, 0.001)
	assert_float(REH.get_damage_mult_vs_type(e, "evil")).is_equal_approx(1.0, 0.001)

func test_get_damage_mult_vs_type_null_enemy() -> void:
	assert_float(REH.get_damage_mult_vs_type(null, "undead")).is_equal_approx(1.0, 0.001)

func test_get_damage_mult_vs_type_unknown_key() -> void:
	var e := _make_enemy()
	e.set_meta("unknown_type", true)
	assert_float(REH.get_damage_mult_vs_type(e, "unknown_type")).is_equal_approx(1.0, 0.001)

# ---------- 空值安全 ----------

func test_on_player_hit_enemy_null_player() -> void:
	var e := _make_enemy()
	REH.on_player_hit_enemy(null, e, Vector3.ZERO, 10)
	assert_bool(true).is_true()

func test_on_player_hit_enemy_null_enemy() -> void:
	# 用 Node 作为 mock player（不需要完整 Player）
	var p: Node = auto_free(Node.new())
	REH.on_player_hit_enemy(p, null, Vector3.ZERO, 10)
	assert_bool(true).is_true()

func test_on_player_hit_enemy_both_null() -> void:
	REH.on_player_hit_enemy(null, null, Vector3.ZERO, 10)
	assert_bool(true).is_true()

# ---------- 符文数据完整性验证 ----------

func test_all_runes_have_mechanics_or_are_cosmetic() -> void:
	# 确保每个符文要么有 mechanics 字段，要么是纯被动（无机制）
	var all_runes := RD.get_all_rune_ids()
	var with_mechanics := 0
	var without_mechanics := 0
	for rid in all_runes:
		var rune: Dictionary = RD.get_rune(String(rid))
		var m: Dictionary = rune.get("mechanics", {})
		if m.is_empty():
			without_mechanics += 1
		else:
			with_mechanics += 1
	# 至少有一些符文带机制
	assert_int(with_mechanics).is_greater(0)

func test_rune_mechanics_chance_values_are_valid_percent() -> void:
	# 所有 *_chance 字段的值应在 0-100 范围内
	var all_runes := RD.get_all_rune_ids()
	for rid in all_runes:
		var rune: Dictionary = RD.get_rune(String(rid))
		var m: Dictionary = rune.get("mechanics", {})
		if m.is_empty():
			continue
		for key in m.keys():
			if String(key).ends_with("_chance"):
				var val := int(m[key])
				assert_bool(val >= 0 and val <= 100) \
					.override_failure_message("符文 %s 的 %s 值 %d 不在 0-100 范围内" % [rid, key, val]) \
					.is_true()

func test_rune_mechanics_duration_values_are_positive() -> void:
	# 所有 *_sec 字段的值应为正数
	var all_runes := RD.get_all_rune_ids()
	for rid in all_runes:
		var rune: Dictionary = RD.get_rune(String(rid))
		var m: Dictionary = rune.get("mechanics", {})
		if m.is_empty():
			continue
		for key in m.keys():
			if String(key).ends_with("_sec"):
				var val := float(m[key])
				assert_bool(val > 0.0) \
					.override_failure_message("符文 %s 的 %s 值 %.2f 不是正数" % [rid, key, val]) \
					.is_true()

# ---------- StatusEffectSystem 与 RuneEffectHooks 协作验证 ----------

func test_status_aura_type_mapping_covers_all_dot_statuses() -> void:
	# 确保所有 DoT 状态都有对应的 aura 类型
	for status_type in SES.DOT_TYPES:
		var aura := SES.get_aura_type(String(status_type))
		assert_bool(not aura.is_empty()) \
			.override_failure_message("DoT 状态 %s 缺少 aura 类型映射" % status_type) \
			.is_true()

func test_status_def_covers_all_aura_mapped_statuses() -> void:
	# 确保 aura 映射中的每个状态都有对应的 STATUS_DEFS 条目
	for se_key in SES.AURA_TYPE_MAP.keys():
		assert_bool(SES.STATUS_DEFS.has(se_key)) \
			.override_failure_message("aura 映射的状态 %s 在 STATUS_DEFS 中无定义" % se_key) \
			.is_true()
