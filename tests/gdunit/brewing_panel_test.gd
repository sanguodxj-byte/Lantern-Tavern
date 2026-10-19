extends GdUnitTestSuite
## 酿酒台/吧台操作面板测试
## 决策 G3（审查 0856 P0-1）：面板写 API 已冻结。三大写操作（下料/开缸/陈酿）
## 不再触碰 FermentationSystem；本套件只保留只读展示能力与冻结契约的测试。
## 酿造写入唯一入口 = BrewFlowSystem（3D 链路），见 brewing_single_write_entry_test.gd。

const BP := preload("res://scenes/tavern/brewing_panel.gd")
const BD := preload("res://globals/tavern/brewing_data.gd")
const FS := preload("res://globals/tavern/fermentation_system.gd")

var panel: Control
var fs: Node
var tm: Node

func before() -> void:
	fs = Engine.get_main_loop().root.get_node_or_null("FermentationSystem")
	tm = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	if fs:
		fs.setup_kegs(2)
	if tm:
		tm.materials_inventory = {"blackberry": 3, "glowshroom": 2, "pixie_dust": 1}
		tm.day = 1
	panel = Control.new()
	panel.set_script(BP)
	add_child(panel)
	panel.selected_keg_index = -1
	panel.brewing_basket.clear()

func after() -> void:
	if panel:
		panel.queue_free()
		panel = null
	if fs:
		fs.setup_kegs(1)
	if tm:
		tm.materials_inventory = {}

func _reset_state() -> void:
	if fs:
		fs.setup_kegs(2)
	if tm:
		tm.materials_inventory = {"blackberry": 3, "glowshroom": 2, "pixie_dust": 1}
		tm.day = 1
	if panel:
		panel.selected_keg_index = -1
		panel.brewing_basket.clear()

# ---------- 初始化 ----------

func test_panel_loads_with_autoloads() -> void:
	assert_object(panel).is_not_null()
	assert_object(fs).is_not_null()
	assert_object(tm).is_not_null()

func test_panel_has_brewing_basket_empty_initially() -> void:
	assert_bool(panel.brewing_basket.is_empty()).is_true()

func test_inventory_loaded_from_tavern_manager() -> void:
	var inv: Dictionary = panel._get_inventory()
	assert_int(int(inv.get("blackberry", 0))).is_equal(3)
	assert_int(int(inv.get("glowshroom", 0))).is_equal(2)
	assert_int(int(inv.get("pixie_dust", 0))).is_equal(1)

func test_current_day_from_tavern_manager() -> void:
	assert_int(panel._get_current_day()).is_equal(1)

# ---------- 冻结契约：写操作不再触碰发酵系统 ----------

func test_brew_pressed_frozen_does_not_start_fermentation() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2, "glowshroom": 1}
	panel._on_brew_pressed()
	# 冻结后不得占用桶位、不得扣减仓库库存
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)
	assert_int(fs.kegs[1].state).is_equal(FS.KegState.EMPTY)
	var inv: Dictionary = panel._get_inventory()
	assert_int(int(inv.get("blackberry", 0))).is_equal(3)

func test_brew_pressed_frozen_does_not_match_recipe() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}
	panel._on_brew_pressed()
	assert_str(fs.kegs[0].recipe_id).is_equal("")

func test_open_keg_frozen_does_not_clear_keg() -> void:
	_reset_state()
	# 手工把桶 0 置为 READY（模拟 3D 链路产物），面板冻结不得清空它
	fs.kegs[0].state = FS.KegState.READY
	fs.kegs[0].final_flavors = {"果香": 6}
	panel.selected_keg_index = 0
	panel._on_open_keg_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.READY)
	assert_int(fs.kegs[0].final_flavors["果香"]).is_equal(6)

func test_seal_aging_frozen_does_not_seal() -> void:
	_reset_state()
	fs.kegs[0].state = FS.KegState.READY
	panel.selected_keg_index = 0
	panel._on_seal_aging_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.READY)
	assert_bool(fs.kegs[0].sealed).is_false()

func test_frozen_handlers_emit_no_write_signals() -> void:
	_reset_state()
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

# ---------- 只读辅助（保留） ----------

func test_deduct_inventory_success() -> void:
	_reset_state()
	var basket: Dictionary = {"blackberry": 2, "glowshroom": 1}
	assert_bool(panel._deduct_inventory(basket)).is_true()
	var inv: Dictionary = panel._get_inventory()
	assert_int(int(inv.get("blackberry", 0))).is_equal(1)
	assert_int(int(inv.get("glowshroom", 0))).is_equal(1)

func test_deduct_inventory_insufficient_fails() -> void:
	_reset_state()
	var basket: Dictionary = {"blackberry": 10}
	assert_bool(panel._deduct_inventory(basket)).is_false()
	var inv: Dictionary = panel._get_inventory()
	assert_int(int(inv.get("blackberry", 0))).is_equal(3)

func test_deduct_inventory_erases_zero_entries() -> void:
	_reset_state()
	var basket: Dictionary = {"pixie_dust": 1}
	assert_bool(panel._deduct_inventory(basket)).is_true()
	var inv: Dictionary = panel._get_inventory()
	assert_bool(not inv.has("pixie_dust"))

func test_find_empty_keg_returns_first_empty() -> void:
	_reset_state()
	fs.kegs[0].state = FS.KegState.FERMENTING
	fs.kegs[1].state = FS.KegState.EMPTY
	assert_int(panel._find_empty_keg(fs)).is_equal(1)

func test_find_empty_keg_none_empty_returns_minus1() -> void:
	_reset_state()
	fs.kegs[0].state = FS.KegState.FERMENTING
	fs.kegs[1].state = FS.KegState.AGING
	assert_int(panel._find_empty_keg(fs)).is_equal(-1)

func test_clear_basket_empties() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2}
	panel.clear_basket()
	assert_bool(panel.brewing_basket.is_empty()).is_true()

func test_on_day_advance_advances_fermentation() -> void:
	_reset_state()
	# 用 3D 门面下料，面板的 on_day_advance 仍可推进时序（只读调度）
	var bfs: Node = Engine.get_main_loop().root.get_node_or_null("BrewFlowSystem")
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	bfs.place_keg_on_rack(token, 1)
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.FERMENTING)
	panel.on_day_advance()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.READY)

# ---------- 中文键数据对齐 ----------

func test_inventory_uses_chinese_material_ids() -> void:
	_reset_state()
	var inv: Dictionary = panel._get_inventory()
	for mat_id in inv:
		var mat_name: String = BD.get_material_name(mat_id)
		assert_bool(mat_name.length() > 0).is_true()
		assert_bool(mat_id != "wild_glowcap").is_true()
		assert_bool(mat_id != "frost_berry").is_true()
		assert_bool(mat_id != "fire_bloom").is_true()
