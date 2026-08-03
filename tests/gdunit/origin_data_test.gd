extends GdUnitTestSuite

# 出身系统数据层测试（docs/36-出身系统与涌现式Build.md）
# 覆盖：出身定义完整性、查询 API、apply_origin 属性/熟练度应用、apply_faction_bonus 势力加成。

const OD := preload("res://globals/combat/origin_data.gd")
const ATTR_PANEL_SCRIPT := preload("res://globals/combat/attr_panel.gd")
const TAVERN_SETTLEMENT_SCRIPT := preload("res://globals/tavern/tavern_settlement.gd")

const EXPECTED_ORIGIN_IDS := ["retired_mercenary", "forest_hunter", "half_baked_warlock", "dwarven_disciple"]

# ============================================================================
# 1. 查询 API
# ============================================================================

func test_get_origin_returns_valid_definition() -> void:
	var o := OD.get_origin("retired_mercenary")
	assert_str(String(o.get("id", ""))).is_equal("retired_mercenary")
	assert_str(String(o.get("name", ""))).is_equal("退役佣兵")
	assert_str(String(o.get("name_en", ""))).is_equal("Retired Mercenary")
	assert_bool(o.has("attr_bonus")).is_true()
	assert_bool(o.has("starting_weapon")).is_true()
	assert_bool(o.has("faction_bonus")).is_true()


func test_get_origin_unknown_id_returns_empty() -> void:
	var o := OD.get_origin("nonexistent_origin")
	assert_bool(o.is_empty()).is_true()


func test_get_origin_returns_independent_copy() -> void:
	var o1 := OD.get_origin("retired_mercenary")
	o1["name"] = "MUTATED"
	var o2 := OD.get_origin("retired_mercenary")
	# 修改副本不应影响常量源数据
	assert_str(String(o2["name"])).is_equal("退役佣兵")


func test_get_all_ids_returns_four_origins() -> void:
	var ids := OD.get_all_ids()
	assert_array(ids).has_size(4)
	for oid in EXPECTED_ORIGIN_IDS:
		assert_bool(ids.has(oid)).is_true()


func test_count_returns_four() -> void:
	assert_int(OD.count()).is_equal(4)


# ============================================================================
# 2. 出身定义完整性
# ============================================================================

func test_each_origin_has_required_fields() -> void:
	var required := ["id", "name", "name_en", "lore", "attr_bonus", "starting_weapon",
		"starting_shield", "faction_bonus", "brewing_direction", "target_zone",
		"proficiency_headstart"]
	for oid in OD.get_all_ids():
		var o := OD.get_origin(oid)
		for field in required:
			assert_bool(o.has(field)).is_true()


func test_each_origin_attr_bonus_sums_to_four() -> void:
	# 设计约束：主属性 +3 / 副属性 +1，合计 4
	for oid in OD.get_all_ids():
		var o := OD.get_origin(oid)
		var bonus: Dictionary = o.get("attr_bonus", {})
		var total := 0
		for k in bonus:
			total += int(bonus[k])
		assert_int(total).is_equal(4)


func test_each_origin_has_proficiency_headstart() -> void:
	for oid in OD.get_all_ids():
		var o := OD.get_origin(oid)
		var headstart: Dictionary = o.get("proficiency_headstart", {})
		assert_bool(headstart.size() >= 1).is_true()


func test_each_origin_starting_weapon_matches_headstart() -> void:
	# 起跑武器类型应与初始武器的 proficiency_key 一致
	# weapon ID → proficiency key 映射（weapons.json 中的 proficiency_key 字段）
	const WEAPON_ID_TO_PROF_KEY := {
		"sword": "sword",
		"longbow": "bow",
		"staff": "staff",
		"warhammer": "hammer",
	}
	for oid in OD.get_all_ids():
		var o := OD.get_origin(oid)
		var weapon_id := String(o.get("starting_weapon", ""))
		var headstart: Dictionary = o.get("proficiency_headstart", {})
		var expected_prof_key: String = WEAPON_ID_TO_PROF_KEY.get(weapon_id, "")
		assert_str(expected_prof_key).is_not_empty()
		assert_bool(headstart.has(expected_prof_key)).is_true()


# ============================================================================
# 3. apply_origin — 属性偏移与熟练度起跑
# ============================================================================

func test_apply_origin_applies_attr_bonus() -> void:
	var ap = auto_free(ATTR_PANEL_SCRIPT.new())
	var ok := OD.apply_origin(ap, "retired_mercenary")
	assert_bool(ok).is_true()
	# str +3 (base 5 → 8), con +1 (base 5 → 6)
	assert_int(ap.get_attr("str")).is_equal(8)
	assert_int(ap.get_attr("con")).is_equal(6)
	# 其它属性不受影响
	assert_int(ap.get_attr("dex")).is_equal(5)


func test_apply_origin_applies_proficiency_headstart() -> void:
	var ap = auto_free(ATTR_PANEL_SCRIPT.new())
	OD.apply_origin(ap, "retired_mercenary")
	assert_int(ap.get_proficiency("sword")).is_equal(2)


func test_apply_origin_sets_origin_id() -> void:
	var ap = auto_free(ATTR_PANEL_SCRIPT.new())
	OD.apply_origin(ap, "forest_hunter")
	assert_str(ap.origin_id).is_equal("forest_hunter")


func test_apply_origin_unknown_id_returns_false() -> void:
	var ap = auto_free(ATTR_PANEL_SCRIPT.new())
	var ok := OD.apply_origin(ap, "nonexistent")
	assert_bool(ok).is_false()
	# 失败不应修改任何状态
	assert_str(ap.origin_id).is_equal("")
	assert_int(ap.get_attr("str")).is_equal(5)


func test_apply_origin_headstart_does_not_lower_existing() -> void:
	var ap = auto_free(ATTR_PANEL_SCRIPT.new())
	ap.accumulate_proficiency("sword", 10)
	OD.apply_origin(ap, "retired_mercenary")
	# 已有 10 > 起跑 2，应保留 10
	assert_int(ap.get_proficiency("sword")).is_equal(10)


func test_apply_origin_all_four_origins_succeed() -> void:
	for oid in OD.get_all_ids():
		var ap = auto_free(ATTR_PANEL_SCRIPT.new())
		assert_bool(OD.apply_origin(ap, oid)).is_true()
		assert_str(ap.origin_id).is_equal(oid)


# ============================================================================
# 4. apply_faction_bonus — 势力声望加成
# ============================================================================

func test_apply_faction_bonus_adds_reputation() -> void:
	var ts = auto_free(TAVERN_SETTLEMENT_SCRIPT.new())
	ts.reset_state()
	# forest_hunter: goblin +30, elf +30
	OD.apply_faction_bonus(ts, "forest_hunter")
	assert_int(int(ts.faction_reputation["goblin"])).is_equal(30)
	assert_int(int(ts.faction_reputation["elf"])).is_equal(30)
	# 未加成势力保持 0
	assert_int(int(ts.faction_reputation["minotaur"])).is_equal(0)


func test_apply_faction_bonus_human_skipped() -> void:
	# retired_mercenary 的 faction_bonus 含 human:30，但 human 不在 faction_reputation 中
	var ts = auto_free(TAVERN_SETTLEMENT_SCRIPT.new())
	ts.reset_state()
	OD.apply_faction_bonus(ts, "retired_mercenary")
	# 不应报错，且既有势力保持 0
	for faction in ts.faction_reputation:
		assert_int(int(ts.faction_reputation[faction])).is_equal(0)


func test_apply_faction_bonus_unknown_origin_noop() -> void:
	var ts = auto_free(TAVERN_SETTLEMENT_SCRIPT.new())
	ts.reset_state()
	OD.apply_faction_bonus(ts, "nonexistent")
	for faction in ts.faction_reputation:
		assert_int(int(ts.faction_reputation[faction])).is_equal(0)


func test_apply_faction_bonus_dwarven_disciple_minotaur() -> void:
	var ts = auto_free(TAVERN_SETTLEMENT_SCRIPT.new())
	ts.reset_state()
	OD.apply_faction_bonus(ts, "dwarven_disciple")
	assert_int(int(ts.faction_reputation["minotaur"])).is_equal(30)
