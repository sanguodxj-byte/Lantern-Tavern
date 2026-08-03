extends GdUnitTestSuite
## 昼夜发酵时序接线测试：白天探索结束（撤离回酒馆）时，
## TavernManager 驱动 FermentationSystem 的环境共振 + advance_day（策划案 11 隔夜发酵）。

const FS := preload("res://globals/tavern/fermentation_system.gd")

var tm: Node
var fs: Node
var zm: Node
var _phase_before: int
var _zone_before: int

func before_test() -> void:
	tm = Engine.get_main_loop().root.get_node("TavernManager")
	fs = Engine.get_main_loop().root.get_node("FermentationSystem")
	zm = Engine.get_main_loop().root.get_node("ZoneManager")
	_phase_before = tm.current_phase
	_zone_before = int(zm.selected_zone)
	fs.setup_kegs(1)

func after_test() -> void:
	tm.current_phase = _phase_before
	zm.set_zone(_zone_before)

func test_extract_to_tavern_advances_fermentation() -> void:
	# 夜晚下料 → 白天探索 → 撤离回酒馆 → 发酵完成
	var idx: int = fs.start_brewing({"blackberry": 2}, tm.day)
	assert_int(idx).is_equal(0)
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.FERMENTING)
	tm._advance_fermentation_day()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.READY)
	assert_int(fs.kegs[0].final_flavors.get("果香", 0)).is_equal(6)

func test_advance_fermentation_applies_zone_resonance() -> void:
	# 白天探索火山区（VOLCANO=4）→ 撤离时注入 温暖+2 辣口+1
	zm.set_zone(4)
	fs.start_brewing({"blackberry": 2}, tm.day)
	tm._advance_fermentation_day()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.READY)
	assert_int(fs.kegs[0].final_flavors.get("温暖", 0)).is_equal(2)
	assert_int(fs.kegs[0].final_flavors.get("辣口", 0)).is_equal(1)

func test_advance_fermentation_advances_aging() -> void:
	# READY → 封存陈酿 → 下一天撤离 → AGING +1 天
	fs.start_brewing({"blackberry": 2}, tm.day)
	tm._advance_fermentation_day()
	assert_bool(fs.seal_for_aging(0)).is_true()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.AGING)
	tm._advance_fermentation_day()
	assert_int(fs.kegs[0].aging_days).is_equal(1)
	assert_int(fs.kegs[0].final_flavors.get("果香", 0)).is_equal(7)

func test_extract_to_tavern_wires_day_advance() -> void:
	# 契约：extract_to_tavern 主路径必须调用 _advance_fermentation_day
	var source := FileAccess.get_file_as_string("res://globals/tavern/tavern_manager.gd")
	assert_bool(source.contains("_advance_fermentation_day()")).is_true()
	var func_pos := source.find("func extract_to_tavern")
	var advance_pos := source.find("_advance_fermentation_day()")
	assert_int(advance_pos).is_greater(func_pos)
	# _advance_fermentation_day 内部必须驱动 FermentationSystem
	var block_start := source.find("func _advance_fermentation_day")
	var block := source.substr(block_start, 600)
	assert_bool(block.contains("apply_environment_resonance")).is_true()
	assert_bool(block.contains("advance_day")).is_true()

func test_advance_fermentation_noop_without_kegs() -> void:
	fs.reset()
	tm._advance_fermentation_day()
	assert_int(fs.free_keg_count()).is_equal(fs.max_kegs)
