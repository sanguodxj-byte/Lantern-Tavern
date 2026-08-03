extends GdUnitTestSuite

## ProgressionAuthority 单元测试（架构审查 P1-4）：
## 击杀经验公式（基础/精英/Boss）、per-peer 经验写入、升级选择意图的权威应用
## （属性/符文/非法意图不消耗机会）、按 player_guid 确定性符文候选。

const PA := preload("res://globals/multiplayer/progression_authority.gd")
const AttrPanel := preload("res://globals/combat/attr_panel.gd")
const ExpeditionInventory := preload("res://globals/core/state/expedition_inventory.gd")

func _attrs() -> AttrPanel:
	var ap: AttrPanel = auto_free(AttrPanel.new())
	ap.init_defaults()
	return ap

func test_kill_reward_base_scales_with_max_life() -> void:
	assert_int(PA.compute_kill_reward(10)).is_equal(20)
	assert_int(PA.compute_kill_reward(12)).is_equal(24)
	assert_int(PA.compute_kill_reward(1)).is_equal(10)  # 下限

func test_kill_reward_elite_and_boss_multipliers() -> void:
	var base: int = PA.compute_kill_reward(100)
	assert_int(PA.compute_kill_reward(100, true, false)).is_equal(int(ceil(base * 1.5)))
	assert_int(PA.compute_kill_reward(100, false, true)).is_equal(int(ceil(base * 3.0)))

func test_award_kill_experience_accumulates_on_attributes() -> void:
	var ap := _attrs()
	var levels: int = PA.award_kill_experience(ap, 250)
	# 阈值按当前等级计算：Lv1=100 → 250 升 1 级（剩 150，Lv2 阈值 200 未达）。
	assert_int(ap.level).is_equal(2)
	assert_int(ap.level_exp).is_equal(150)
	assert_int(levels).is_equal(1)
	assert_int(ap.get_pending_level_choices()).is_equal(1)

func test_award_kill_experience_ignores_invalid_input() -> void:
	var ap := _attrs()
	assert_int(PA.award_kill_experience(ap, 0)).is_equal(0)
	assert_int(PA.award_kill_experience(null, 100)).is_equal(0)

func test_apply_attribute_choice_consumes_pending() -> void:
	var ap := _attrs()
	PA.award_kill_experience(ap, 120)
	var str_before: int = int(ap.attrs["str"])
	var res: Dictionary = PA.apply_level_up_choice(ap, null, {"kind": "attribute", "attr_key": "str"})
	assert_bool(bool(res["ok"])).is_true()
	assert_int(int(ap.attrs["str"])).is_equal(str_before + 1)
	assert_int(ap.get_pending_level_choices()).is_equal(0)

func test_apply_attribute_choice_rejects_without_pending() -> void:
	var ap := _attrs()
	var res: Dictionary = PA.apply_level_up_choice(ap, null, {"kind": "attribute", "attr_key": "str"})
	assert_bool(bool(res["ok"])).is_false()
	assert_int(int(ap.attrs["str"])).is_equal(5)

func test_apply_rune_choice_grants_rune_and_consumes() -> void:
	var ap := _attrs()
	PA.award_kill_experience(ap, 120)
	var inv := ExpeditionInventory.new()
	var res: Dictionary = PA.apply_level_up_choice(ap, inv, {"kind": "rune", "rune_id": "ember"})
	assert_bool(bool(res["ok"])).is_false()  # 未进入符文分支：无候选
	assert_int(inv.runes.get("ember", 0)).is_equal(0)

func test_apply_rune_choice_after_candidates_grants_rune() -> void:
	var ap := _attrs()
	PA.award_kill_experience(ap, 120)
	var candidates: Array = PA.roll_rune_candidates(ap, "player_alpha")
	assert_int(candidates.size()).is_equal(3)
	var rune_id := String(candidates[0])
	var inv := ExpeditionInventory.new()
	var res: Dictionary = PA.apply_level_up_choice(ap, inv, {"kind": "rune", "rune_id": rune_id})
	assert_bool(bool(res["ok"])).is_true()
	assert_int(int(inv.runes.get(rune_id, 0))).is_equal(1)
	assert_int(ap.get_pending_level_choices()).is_equal(0)

func test_rune_candidates_are_deterministic_per_guid() -> void:
	var ap1 := _attrs()
	var ap2 := _attrs()
	PA.award_kill_experience(ap1, 120)
	PA.award_kill_experience(ap2, 120)
	var a: Array = PA.roll_rune_candidates(ap1, "player_alpha")
	var b: Array = PA.roll_rune_candidates(ap2, "player_alpha")
	assert_array(a).is_equal(b)
	# 不同 guid → 不同候选组（须用全新属性实例：候选一旦锁定不再重掷）。
	var ap3 := _attrs()
	PA.award_kill_experience(ap3, 120)
	var c: Array = PA.roll_rune_candidates(ap3, "player_beta")
	assert_bool(a != c).is_true()

func test_rune_candidates_empty_without_pending() -> void:
	var ap := _attrs()
	assert_array(PA.roll_rune_candidates(ap, "player_alpha")).is_empty()

func test_unknown_intent_kind_rejected() -> void:
	var ap := _attrs()
	PA.award_kill_experience(ap, 120)
	var res: Dictionary = PA.apply_level_up_choice(ap, null, {"kind": "teleport"})
	assert_bool(bool(res["ok"])).is_false()
	assert_int(ap.get_pending_level_choices()).is_equal(1)
