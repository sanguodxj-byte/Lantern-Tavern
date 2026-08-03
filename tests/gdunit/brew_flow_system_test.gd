extends GdUnitTestSuite
## 3D 酿酒流程状态中枢 (BrewFlowSystem) 测试。
## 覆盖：炼药锅投料/蒸煮状态机/取麦汁、酒桶登记→窖藏→开缸全链路，
## 以及与 FermentationSystem Keg 状态机的对接。

const FS := preload("res://globals/tavern/fermentation_system.gd")
var bfs: Node  # autoload 实例
var fs: Node

func before_test() -> void:
	bfs = Engine.get_main_loop().root.get_node("BrewFlowSystem")
	fs = Engine.get_main_loop().root.get_node("FermentationSystem")
	bfs.reset()
	fs.setup_kegs(1)

# ---------- 炼药锅投料 ----------

func test_add_to_cauldron_accumulates() -> void:
	assert_bool(bfs.add_to_cauldron("blackberry")).is_true()
	assert_bool(bfs.add_to_cauldron("blackberry")).is_true()
	assert_bool(bfs.add_to_cauldron("glowshroom")).is_true()
	assert_int(bfs.cauldron_basket["blackberry"]).is_equal(2)
	assert_int(bfs.cauldron_basket["glowshroom"]).is_equal(1)

func test_add_to_cauldron_rejected_when_ready() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.start_boiling()
	bfs.tick_boil(bfs.BOIL_DURATION_SEC)
	assert_int(bfs.cauldron_state).is_equal(bfs.CauldronState.READY)
	assert_bool(bfs.add_to_cauldron("blackberry")).is_false()
	assert_bool(bfs.can_add_ingredient()).is_false()

func test_add_empty_id_rejected() -> void:
	assert_bool(bfs.add_to_cauldron("")).is_false()

# ---------- 蒸煮状态机 ----------

func test_start_boiling_requires_ingredients() -> void:
	assert_bool(bfs.start_boiling()).is_false()

func test_start_boiling_twice_rejected() -> void:
	bfs.add_to_cauldron("blackberry")
	assert_bool(bfs.start_boiling()).is_true()
	assert_bool(bfs.start_boiling()).is_false()

func test_tick_boil_progresses_to_ready() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.start_boiling()
	bfs.tick_boil(bfs.BOIL_DURATION_SEC * 0.5)
	assert_float(bfs.boil_progress).is_equal_approx(0.5, 0.01)
	assert_int(bfs.cauldron_state).is_equal(bfs.CauldronState.BOILING)
	bfs.tick_boil(bfs.BOIL_DURATION_SEC)
	assert_float(bfs.boil_progress).is_equal(1.0)
	assert_int(bfs.cauldron_state).is_equal(bfs.CauldronState.READY)

func test_tick_boil_noop_when_not_boiling() -> void:
	bfs.tick_boil(1.0)
	assert_float(bfs.boil_progress).is_equal(0.0)

func test_take_wort_fails_when_not_ready() -> void:
	bfs.add_to_cauldron("blackberry")
	assert_bool(bfs.take_wort()).is_false()

func test_take_wort_clears_cauldron() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.start_boiling()
	bfs.tick_boil(bfs.BOIL_DURATION_SEC)
	assert_bool(bfs.take_wort()).is_true()
	assert_bool(bfs.cauldron_basket.is_empty()).is_true()
	assert_int(bfs.cauldron_state).is_equal(bfs.CauldronState.IDLE)
	assert_float(bfs.boil_progress).is_equal(0.0)

# ---------- 酒桶生命周期 ----------

func test_register_filled_keg_returns_token() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	assert_int(token).is_greater_equal(0)
	assert_object(bfs.find_keg(token)).is_not_null()

func test_register_filled_keg_rejects_empty() -> void:
	assert_int(bfs.register_filled_keg({})).is_equal(-1)

func test_place_keg_on_rack_starts_fermentation() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	assert_bool(bfs.place_keg_on_rack(token, 3)).is_true()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.FERMENTING)
	assert_int(fs.kegs[0].brew_day).is_equal(3)
	var keg = bfs.find_keg(token)
	assert_object(keg).is_not_null()
	assert_int(keg.keg_index).is_equal(0)

func test_place_keg_twice_rejected() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	assert_bool(bfs.place_keg_on_rack(token, 1)).is_true()
	assert_bool(bfs.place_keg_on_rack(token, 1)).is_false()

func test_place_keg_fails_when_no_free_keg() -> void:
	bfs.register_filled_keg({"blackberry": 1})
	bfs.place_keg_on_rack(bfs.active_kegs[0].token, 1)
	# 第二桶：无空桶位（Lv1 仅 1 桶）
	var token2: int = bfs.register_filled_keg({"blackberry": 1})
	assert_bool(bfs.place_keg_on_rack(token2, 1)).is_false()

func test_open_rack_keg_returns_flavors_and_removes() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	bfs.place_keg_on_rack(token, 1)
	# 隔夜发酵完成
	fs.advance_day()
	bfs.sync_keg_state(token)
	assert_bool(bfs.can_open_keg(token)).is_true()
	var flavors: Dictionary = bfs.open_rack_keg(token)
	assert_int(flavors.get("果香", 0)).is_equal(6)
	assert_object(bfs.find_keg(token)).is_null()
	# 桶位回归空桶
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)

func test_cannot_open_fermenting_keg() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	bfs.place_keg_on_rack(token, 1)
	assert_bool(bfs.can_open_keg(token)).is_false()
	assert_bool(bfs.open_rack_keg(token).is_empty()).is_true()

func test_open_invalid_token_returns_empty() -> void:
	assert_bool(bfs.open_rack_keg(999).is_empty()).is_true()

# ---------- 存档 ----------

func test_serialize_deserialize_roundtrip() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.start_boiling()
	bfs.tick_boil(bfs.BOIL_DURATION_SEC * 0.25)
	var token: int = bfs.register_filled_keg({"glowshroom": 1, "blackberry": 1})
	bfs.place_keg_on_rack(token, 2)
	var data: Dictionary = bfs.serialize()
	bfs.reset()
	bfs.deserialize(data)
	assert_int(bfs.cauldron_basket.get("blackberry", 0)).is_equal(1)
	assert_float(bfs.boil_progress).is_equal_approx(0.25, 0.01)
	assert_int(bfs.active_kegs.size()).is_equal(1)
	assert_int(bfs.active_kegs[0].keg_index).is_equal(0)
	assert_int(bfs.active_kegs[0].state).is_equal(FS.KegState.FERMENTING)

func test_reset_clears_all() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.start_boiling()
	bfs.register_filled_keg({"blackberry": 1})
	bfs.reset()
	assert_bool(bfs.cauldron_basket.is_empty()).is_true()
	assert_int(bfs.cauldron_state).is_equal(bfs.CauldronState.IDLE)
	assert_int(bfs.active_kegs.size()).is_equal(0)
