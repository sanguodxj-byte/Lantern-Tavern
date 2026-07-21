extends GdUnitTestSuite
## 发酵时序系统 (FermentationSystem) 测试。
## 验证策划案《11-酿造时间时序与发酵博弈设计》：
## Keg 状态机、隔夜发酵、环境共振、陈酿桶位博弈。

const FS := preload("res://globals/tavern/fermentation_system.gd")
var fs: Node  # autoload 实例

func before_test() -> void:
	fs = Engine.get_main_loop().root.get_node("FermentationSystem")
	fs.setup_kegs(1)  # 默认 1 桶（酒馆 Lv1）

# ---------- 桶位初始化 ----------

func test_setup_kegs_creates_empty_kegs() -> void:
	fs.setup_kegs(3)
	assert_int(fs.kegs.size()).is_equal(3)
	for keg in fs.kegs:
		assert_int(keg.state).is_equal(FS.KegState.EMPTY)

func test_free_keg_count_initial() -> void:
	fs.setup_kegs(2)
	assert_int(fs.free_keg_count()).is_equal(2)

func test_expand_kegs_adds_capacity() -> void:
	fs.setup_kegs(1)
	fs.expand_kegs(2)
	assert_int(fs.max_kegs).is_equal(3)
	assert_int(fs.kegs.size()).is_equal(3)
	assert_int(fs.free_keg_count()).is_equal(3)

# ---------- 下料 ----------

func test_start_brewing_occupies_empty_keg() -> void:
	fs.setup_kegs(1)
	var ings := {"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}
	var idx: int = fs.start_brewing(ings, 1)
	assert_int(idx).is_equal(0)
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.FERMENTING)
	assert_int(fs.kegs[0].brew_day).is_equal(1)

func test_start_brewing_returns_minus_one_when_no_free_keg() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 1}, 1)
	# 第二次下料应失败（无空桶）
	var idx: int = fs.start_brewing({"blackberry": 1}, 1)
	assert_int(idx).is_equal(-1)

func test_start_brewing_computes_base_flavors() -> void:
	fs.setup_kegs(1)
	var ings := {"blackberry": 2}  # 果香3 甜美2 × 2 = 果香6 甜美4
	fs.start_brewing(ings, 1)
	assert_int(fs.kegs[0].base_flavors["果香"]).is_equal(6)
	assert_int(fs.kegs[0].base_flavors["甜美"]).is_equal(4)

func test_start_brewing_matches_recipe() -> void:
	fs.setup_kegs(1)
	# 亮莓果汁：2 黑莓 + 1 蓝光菇 + 1 妖精粉尘
	var ings := {"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}
	fs.start_brewing(ings, 1)
	assert_str(fs.kegs[0].recipe_id).is_equal("glowberry_juice")
	assert_str(fs.kegs[0].recipe_name).is_equal("亮莓果汁")

func test_start_brewing_no_recipe_for_custom_combo() -> void:
	fs.setup_kegs(1)
	var ings := {"blackberry": 1}  # 不匹配任何经典配方
	fs.start_brewing(ings, 1)
	assert_str(fs.kegs[0].recipe_id).is_equal("")

# ---------- 环境共振 (策划案 11 §点子1) ----------

func test_volcano_resonance_adds_warmth_spicy() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 1}, 1)
	fs.apply_environment_resonance(BrewingData.Zone.VOLCANO)
	# 火山区共振：温暖+2, 辣口+1
	assert_int(fs.kegs[0].resonance_flavors["温暖"]).is_equal(2)
	assert_int(fs.kegs[0].resonance_flavors["辣口"]).is_equal(1)

func test_graveyard_resonance_adds_decayed() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 1}, 1)
	fs.apply_environment_resonance(BrewingData.Zone.GRAVEYARD)
	assert_int(fs.kegs[0].resonance_flavors["死寂"]).is_equal(2)

func test_forest_resonance_no_effect() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 1}, 1)
	fs.apply_environment_resonance(BrewingData.Zone.FOREST)
	assert_bool(fs.kegs[0].resonance_flavors.is_empty()).is_true()

func test_resonance_only_affects_fermenting_kegs() -> void:
	fs.setup_kegs(1)
	# 空桶不应受共振影响
	fs.apply_environment_resonance(BrewingData.Zone.VOLCANO)
	assert_bool(fs.kegs[0].resonance_flavors.is_empty()).is_true()

func test_resonance_does_not_affect_ready_kegs() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 1}, 1)
	fs.advance_day()  # FERMENTING → READY
	# READY 状态不应再受共振
	fs.apply_environment_resonance(BrewingData.Zone.VOLCANO)
	assert_bool(fs.kegs[0].resonance_flavors.is_empty()).is_true()

func test_multiple_resonance_calls_accumulate() -> void:
	# 同一天多次探索火山区应累积（虽然策划案未明确，但实现合理）
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 1}, 1)
	fs.apply_environment_resonance(BrewingData.Zone.VOLCANO)
	fs.apply_environment_resonance(BrewingData.Zone.VOLCANO)
	assert_int(fs.kegs[0].resonance_flavors["温暖"]).is_equal(4)

# ---------- 时序推进 (advance_day) ----------

func test_advance_day_fermenting_to_ready() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)  # 果香6 甜美4
	fs.advance_day()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.READY)

func test_advance_day_finalizes_flavors_with_resonance() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)  # base: 果香6 甜美4
	fs.apply_environment_resonance(BrewingData.Zone.VOLCANO)  # +温暖2 辣口1
	fs.advance_day()
	# final = base + resonance
	assert_int(fs.kegs[0].final_flavors["果香"]).is_equal(6)
	assert_int(fs.kegs[0].final_flavors["甜美"]).is_equal(4)
	assert_int(fs.kegs[0].final_flavors["温暖"]).is_equal(2)
	assert_int(fs.kegs[0].final_flavors["辣口"]).is_equal(1)

func test_advance_day_aging_increments_flavors() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)  # 果香6 甜美4
	fs.advance_day()  # FERMENTING → READY
	fs.seal_for_aging(0)  # READY → AGING
	fs.advance_day()  # AGING +1天：果香7 甜美5
	assert_int(fs.kegs[0].final_flavors["果香"]).is_equal(7)
	assert_int(fs.kegs[0].final_flavors["甜美"]).is_equal(5)
	assert_int(fs.kegs[0].aging_days).is_equal(1)

func test_advance_day_aging_caps_at_3_days() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)
	fs.advance_day()
	fs.seal_for_aging(0)
	fs.advance_day()  # +1
	fs.advance_day()  # +2
	fs.advance_day()  # +3 → AGED 封顶
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.AGED)
	assert_int(fs.kegs[0].aging_days).is_equal(3)

func test_aged_keg_does_not_increase_on_advance() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)
	fs.advance_day()
	fs.seal_for_aging(0)
	fs.advance_day()
	fs.advance_day()
	fs.advance_day()  # AGED
	var before: int = fs.kegs[0].final_flavors["果香"]
	fs.advance_day()  # 不应再增长
	assert_int(fs.kegs[0].final_flavors["果香"]).is_equal(before)
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.AGED)

# ---------- 开缸取酒 ----------

func test_open_keg_returns_final_flavors() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)
	fs.advance_day()  # READY
	var flavors: Dictionary = fs.open_keg(0)
	assert_int(flavors["果香"]).is_equal(6)
	assert_int(flavors["甜美"]).is_equal(4)

func test_open_keg_clears_keg_to_empty() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)
	fs.advance_day()
	fs.open_keg(0)
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)
	assert_bool(fs.kegs[0].ingredients.is_empty()).is_true()
	assert_bool(fs.kegs[0].final_flavors.is_empty()).is_true()

func test_open_keg_returns_empty_for_fermenting() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)
	# 未发酵完成，不可开缸
	var flavors: Dictionary = fs.open_keg(0)
	assert_bool(flavors.is_empty()).is_true()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.FERMENTING)

func test_open_keg_returns_empty_for_empty_keg() -> void:
	fs.setup_kegs(1)
	var flavors: Dictionary = fs.open_keg(0)
	assert_bool(flavors.is_empty()).is_true()

func test_open_keg_includes_recipe_id_if_matched() -> void:
	fs.setup_kegs(1)
	var ings := {"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}
	fs.start_brewing(ings, 1)
	fs.advance_day()
	var flavors: Dictionary = fs.open_keg(0)
	assert_str(flavors["__recipe_id__"]).is_equal("glowberry_juice")

func test_open_aging_keg_returns_current_flavors() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)  # 果香6 甜美4
	fs.advance_day()
	fs.seal_for_aging(0)
	fs.advance_day()  # +1: 果香7 甜美5
	var flavors: Dictionary = fs.open_keg(0)
	assert_int(flavors["果香"]).is_equal(7)
	assert_int(flavors["甜美"]).is_equal(5)

# ---------- 陈酿封存 ----------

func test_seal_for_aging_only_from_ready() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)
	# FERMENTING 状态不能直接陈酿
	assert_bool(fs.seal_for_aging(0)).is_false()
	fs.advance_day()  # READY
	assert_bool(fs.seal_for_aging(0)).is_true()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.AGING)
	assert_bool(fs.kegs[0].sealed).is_true()

func test_seal_for_aging_resets_aging_days() -> void:
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)
	fs.advance_day()
	fs.seal_for_aging(0)
	assert_int(fs.kegs[0].aging_days).is_equal(0)

# ---------- 查询 ----------

func test_get_keg_status_text() -> void:
	fs.setup_kegs(1)
	assert_str(fs.get_keg_status_text(0)).is_equal("空桶")
	fs.start_brewing({"blackberry": 1}, 1)
	assert_str(fs.get_keg_status_text(0)).is_equal("发酵中")
	fs.advance_day()
	assert_str(fs.get_keg_status_text(0)).is_equal("已熟成")
	fs.seal_for_aging(0)
	fs.advance_day()
	assert_bool(fs.get_keg_status_text(0).begins_with("陈酿中")).is_true()

func test_get_openable_kegs() -> void:
	fs.setup_kegs(3)
	fs.start_brewing({"blackberry": 1}, 1)  # 桶0 FERMENTING
	# 桶1, 桶2 仍为 EMPTY，不可开缸
	assert_bool(fs.get_openable_kegs().is_empty()).is_true()
	fs.advance_day()  # 桶0 → READY
	var openable: Array = fs.get_openable_kegs()
	assert_int(openable.size()).is_equal(1)
	assert_int(openable[0]).is_equal(0)

func test_get_fermenting_kegs() -> void:
	fs.setup_kegs(3)
	fs.start_brewing({"blackberry": 1}, 1)  # 桶0
	fs.start_brewing({"blackberry": 1}, 1)  # 桶1
	var fermenting: Array = fs.get_fermenting_kegs()
	assert_int(fermenting.size()).is_equal(2)
	fs.advance_day()
	# 都转入 READY，无发酵中
	assert_int(fs.get_fermenting_kegs().size()).is_equal(0)

# ---------- 完整日循环集成 ----------

func test_full_day_cycle_brew_ferment_resonance_open() -> void:
	fs.setup_kegs(1)
	# Day 1 夜晚：下料亮莓果汁
	var ings := {"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}
	var idx: int = fs.start_brewing(ings, 1)
	assert_int(idx).is_equal(0)
	# Day 2 白天：探索火山区
	fs.apply_environment_resonance(BrewingData.Zone.VOLCANO)
	# Day 2 白天结束：推进时序
	fs.advance_day()
	# Day 2 夜晚：开缸取酒
	var flavors: Dictionary = fs.open_keg(0)
	# 亮莓果汁 base: 甜美8 果香8 寒凉3 清澈2 香醇3 酸爽1 温暖1
	# + 火山共振: 温暖+2 辣口+1
	assert_int(flavors["果香"]).is_equal(8)
	assert_int(flavors["甜美"]).is_equal(8)
	assert_int(flavors["温暖"]).is_equal(3)  # 1 + 2
	assert_int(flavors["辣口"]).is_equal(1)
	assert_str(flavors["__recipe_id__"]).is_equal("glowberry_juice")
	# 桶已清空，可再次下料
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)

func test_aging_vs_turnover_tradeoff() -> void:
	# 陈酿线 vs 周转线的取舍验证
	fs.setup_kegs(1)
	fs.start_brewing({"blackberry": 2}, 1)  # 果香6 甜美4
	fs.advance_day()  # READY
	# 选择陈酿而非开缸
	fs.seal_for_aging(0)
	fs.advance_day()  # +1: 果香7 甜美5
	fs.advance_day()  # +2: 果香8 甜美6
	fs.advance_day()  # +3: 果香9 甜美7 → AGED
	# 此时桶被占用，无法下新料
	assert_int(fs.free_keg_count()).is_equal(0)
	# 开缸后桶释放
	fs.open_keg(0)
	assert_int(fs.free_keg_count()).is_equal(1)
