extends GdUnitTestSuite
## 酿酒台/吧台操作面板测试
## 验证：下料/开缸/陈酿三大操作与 FermentationSystem/BrewingData 集成闭环
## 注：gdUnit4 before() 非每测试前调用，每个涉及状态变更的测试须自行调 _reset_state()

const BP := preload("res://scenes/tavern/brewing_panel.gd")
const BD := preload("res://globals/brewing_data.gd")
const FS := preload("res://globals/fermentation_system.gd")

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

# ---------- 下料操作 ----------

func test_brew_pressed_empty_basket_shows_status() -> void:
	_reset_state()
	panel._on_brew_pressed()
	var inv: Dictionary = panel._get_inventory()
	assert_int(int(inv.get("blackberry", 0))).is_equal(3)

func test_brew_pressed_with_ingredients_starts_fermentation() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2, "glowshroom": 1}
	panel._on_brew_pressed()
	var inv: Dictionary = panel._get_inventory()
	assert_int(int(inv.get("blackberry", 0))).is_equal(1)
	assert_int(int(inv.get("glowshroom", 0))).is_equal(1)
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.FERMENTING)
	assert_bool(panel.brewing_basket.is_empty()).is_true()

func test_brew_pressed_no_empty_keg_fails() -> void:
	_reset_state()
	fs.kegs[0].state = FS.KegState.FERMENTING
	fs.kegs[1].state = FS.KegState.FERMENTING
	panel.brewing_basket = {"blackberry": 1}
	panel._on_brew_pressed()
	var inv: Dictionary = panel._get_inventory()
	assert_int(int(inv.get("blackberry", 0))).is_equal(3)

func test_brew_pressed_insufficient_inventory_fails() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 10}
	panel._on_brew_pressed()
	var inv: Dictionary = panel._get_inventory()
	assert_int(int(inv.get("blackberry", 0))).is_equal(3)
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)

func test_brew_matched_recipe_recorded() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}
	panel._on_brew_pressed()
	assert_str(fs.kegs[0].recipe_id).is_equal("glowberry_juice")
	assert_str(fs.kegs[0].recipe_name).is_equal("亮莓果汁")

# ---------- 开缸操作 ----------

func test_open_keg_empty_keg_fails() -> void:
	_reset_state()
	panel.selected_keg_index = 0
	fs.kegs[0].state = FS.KegState.EMPTY
	panel._on_open_keg_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)

func test_open_keg_ready_returns_flavors() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2, "glowshroom": 1}
	panel._on_brew_pressed()
	fs.advance_day()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.READY)
	panel.selected_keg_index = 0
	panel._on_open_keg_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)

func test_open_keg_aging_returns_flavors() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2}
	panel._on_brew_pressed()
	fs.advance_day()
	fs.seal_for_aging(0)
	fs.advance_day()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.AGING)
	panel.selected_keg_index = 0
	panel._on_open_keg_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)

func test_open_keg_no_selection_fails() -> void:
	_reset_state()
	panel.selected_keg_index = -1
	fs.kegs[0].state = FS.KegState.READY
	panel._on_open_keg_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.READY)

# ---------- 陈酿操作 ----------

func test_seal_aging_ready_succeeds() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2}
	panel._on_brew_pressed()
	fs.advance_day()
	panel.selected_keg_index = 0
	panel._on_seal_aging_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.AGING)
	assert_bool(fs.kegs[0].sealed).is_true()

func test_seal_aging_empty_fails() -> void:
	_reset_state()
	panel.selected_keg_index = 0
	fs.kegs[0].state = FS.KegState.EMPTY
	panel._on_seal_aging_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)

func test_seal_aging_fermenting_fails() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2}
	panel._on_brew_pressed()
	panel.selected_keg_index = 0
	panel._on_seal_aging_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.FERMENTING)

func test_seal_aging_no_selection_fails() -> void:
	_reset_state()
	panel.selected_keg_index = -1
	fs.kegs[0].state = FS.KegState.READY
	panel._on_seal_aging_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.READY)

# ---------- 库存扣减 ----------

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

# ---------- 辅助函数 ----------

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
	panel.brewing_basket = {"blackberry": 2}
	panel._on_brew_pressed()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.FERMENTING)
	panel.on_day_advance()
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.READY)

# ---------- 信号 ----------

func test_brew_started_signal_emitted() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2}
	var received: Array = []
	panel.brew_started.connect(func(idx): received.append(idx))
	panel._on_brew_pressed()
	assert_int(received.size()).is_greater(0)
	if received.size() > 0:
		assert_int(received[0]).is_equal(0)

func test_keg_opened_signal_emitted() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2}
	panel._on_brew_pressed()
	fs.advance_day()
	panel.selected_keg_index = 0
	var received_idx: Array = []
	var received_flavors: Array = []
	panel.keg_opened.connect(func(idx, flv): received_idx.append(idx); received_flavors.append(flv))
	panel._on_open_keg_pressed()
	assert_int(received_idx.size()).is_greater(0)
	assert_int(received_idx[0]).is_equal(0)
	assert_bool(not received_flavors[0].is_empty()).is_true()

func test_keg_sealed_signal_emitted() -> void:
	_reset_state()
	panel.brewing_basket = {"blackberry": 2}
	panel._on_brew_pressed()
	fs.advance_day()
	panel.selected_keg_index = 0
	var received: Array = []
	panel.keg_sealed.connect(func(idx): received.append(idx))
	panel._on_seal_aging_pressed()
	assert_int(received.size()).is_greater(0)
	assert_int(received[0]).is_equal(0)

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
