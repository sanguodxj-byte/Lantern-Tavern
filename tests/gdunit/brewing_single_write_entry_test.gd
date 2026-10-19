extends GdUnitTestSuite
## 决策 G3 单写入口契约测试（P0-1 / P0-2）。
## 验证：
## 1. D1 源守则：brewing_panel.gd 不再含直接调用 FermentationSystem 写方法的代码
##    （fs.start_brewing( / fs.open_keg( / fs.seal_for_aging( 禁止模式）；
##    冻结面板的写处理器不再改动发酵桶位。
## 2. D2 Keg 不变量：每个非空 FermentationSystem 桶位必须恰好对应一个已窖藏
##    ActiveKeg；每个已窖藏 token 的 keg_index 必须有效且状态一致。
##    生产写入口唯一：经由 BrewFlowSystem 的 place/open 操作保持不变量，
##    绕过门面的直接写（旧面板模式）破坏不变量。

const BP_SCRIPT_PATH := "res://scenes/tavern/brewing_panel.gd"
const FS := preload("res://globals/tavern/fermentation_system.gd")

var bfs: Node
var fs: Node

func before_test() -> void:
	bfs = Engine.get_main_loop().root.get_node("BrewFlowSystem")
	fs = Engine.get_main_loop().root.get_node("FermentationSystem")
	bfs.reset()
	fs.setup_kegs(2)

# ---------- D1：源守则 + 冻结写处理器 ----------

func test_brewing_panel_source_no_direct_fs_write_calls() -> void:
	var script: GDScript = load(BP_SCRIPT_PATH)
	var source: String = script.source_code
	assert_bool(source.find("fs.start_brewing(") == -1) \
		.override_failure_message("brewing_panel.gd 仍含 fs.start_brewing( 直接调用（禁止模式）") \
		.is_true()
	assert_bool(source.find("fs.open_keg(") == -1) \
		.override_failure_message("brewing_panel.gd 仍含 fs.open_keg( 直接调用（禁止模式）") \
		.is_true()
	assert_bool(source.find("fs.seal_for_aging(") == -1) \
		.override_failure_message("brewing_panel.gd 仍含 fs.seal_for_aging( 直接调用（禁止模式）") \
		.is_true()

func test_brewing_panel_write_handlers_frozen_no_write() -> void:
	var BP := preload(BP_SCRIPT_PATH)
	var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	var old_inv: Dictionary = {}
	if tm and "materials_inventory" in tm:
		old_inv = tm.materials_inventory.duplicate()
		tm.materials_inventory = {"blackberry": 5}
		tm.day = 1
	var panel: Control = Control.new()
	panel.set_script(BP)
	add_child(panel)
	fs.setup_kegs(1)
	panel.brewing_basket = {"blackberry": 2}
	panel.selected_keg_index = 0
	panel._on_brew_pressed()
	panel._on_open_keg_pressed()
	panel._on_seal_aging_pressed()
	# 冻结后任何写操作都不得改动桶位状态
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)
	assert_bool(fs.kegs[0].ingredients.is_empty()).is_true()
	panel.queue_free()
	if tm:
		tm.materials_inventory = old_inv

func test_brewing_panel_frozen_handlers_do_not_emit_signals() -> void:
	var BP := preload(BP_SCRIPT_PATH)
	var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	var old_inv: Dictionary = {}
	if tm and "materials_inventory" in tm:
		old_inv = tm.materials_inventory.duplicate()
		tm.materials_inventory = {"blackberry": 5}
		tm.day = 1
	var panel: Control = Control.new()
	panel.set_script(BP)
	add_child(panel)
	var emitted: Array = []
	panel.brew_started.connect(func(_i): emitted.append("brew"))
	panel.keg_opened.connect(func(_i, _f): emitted.append("open"))
	panel.keg_sealed.connect(func(_i): emitted.append("seal"))
	panel.brewing_basket = {"blackberry": 2}
	panel.selected_keg_index = 0
	panel._on_brew_pressed()
	panel._on_open_keg_pressed()
	panel._on_seal_aging_pressed()
	assert_bool(emitted.is_empty()).is_true()
	panel.queue_free()
	if tm:
		tm.materials_inventory = old_inv

# ---------- D2：Keg 不变量 ----------

func test_invariant_holds_after_place_via_flow() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	assert_int(token).is_greater_equal(0)
	assert_bool(bfs.place_keg_on_rack(token, 1)).is_true()
	assert_bool(fs.validate_keg_invariant()) \
		.override_failure_message("合法 3D 窖藏后不变量应成立") \
		.is_true()

func test_invariant_fails_when_slot_filled_without_active_keg() -> void:
	# 模拟旧面板直接写：桶位被占用但无对应 ActiveKeg（P0-2 可复现分叉 #1）
	fs.start_brewing({"blackberry": 2}, 1)
	assert_bool(fs.validate_keg_invariant()).is_false()

func test_invariant_fails_when_active_keg_points_to_emptied_slot() -> void:
	# 模拟旧面板直接开缸：槽位被清空但 token 仍在 active_kegs（P0-2 可复现分叉 #2）
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	bfs.place_keg_on_rack(token, 1)
	fs.advance_day()  # FERMENTING → READY（可开缸）
	fs.open_keg(0)    # 绕过门面直接开缸：桶位清空但 ActiveKeg 未移除
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)
	assert_bool(fs.validate_keg_invariant()).is_false()

func test_invariant_kept_across_place_advance_seal_open_sequence() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	bfs.place_keg_on_rack(token, 1)
	assert_bool(fs.validate_keg_invariant()).is_true()
	# 隔夜发酵（状态迁移，不改变槽位占用）
	fs.advance_day()
	bfs.sync_keg_state(token)
	assert_bool(fs.validate_keg_invariant()).is_true()
	# 封存陈酿（状态迁移）
	assert_bool(fs.seal_for_aging(0)).is_true()
	assert_bool(fs.validate_keg_invariant()).is_true()
	# 开缸取酒（经 3D 门面，token 移除）
	var flavors: Dictionary = bfs.open_rack_keg(token)
	assert_bool(not flavors.is_empty()).is_true()
	assert_bool(fs.validate_keg_invariant()).is_true()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)

func test_invariant_violated_by_direct_fs_write_then_flow_open_fails() -> void:
	# 门面一致性：用旧路径占桶后，BrewFlowSystem 无法找到对应 token，
	# open_rack_keg 返回空（物理桶与逻辑桶分叉的后续表现）
	fs.start_brewing({"blackberry": 2}, 1)
	assert_bool(fs.validate_keg_invariant()).is_false()
	var flavors: Dictionary = bfs.open_rack_keg(999)
	assert_bool(flavors.is_empty()).is_true()
