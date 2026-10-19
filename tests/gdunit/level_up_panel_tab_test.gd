extends GdUnitTestSuite
## 升级弹窗行为回归测试：
## 1) 升级（获得待处理属性/符文选择）时不再自动弹出，可累计；
## 2) 地牢场景按 TAB 才唤出升级奖励面板（open_if_pending），非地牢不拦截 TAB；
## 3) ESC 可暂缓关闭面板；队列逐个结算，全部结算完自动隐藏。

const LEVEL_UP_PANEL_SCENE := "res://scenes/ui/level_up_panel.tscn"
const ATTR_PANEL_SCRIPT := "res://globals/combat/attr_panel.gd"
const DUNGEON_SCRIPT := "res://scenes/expedition/procedural_dungeon.gd"
const Service := preload("res://globals/core/service.gd")

var _gs: Node = null
var _saved_current_level: Node = null
var _panel: Node = null
var _ap: Node = null
var _fake_dungeon: Node = null

func before_test() -> void:
	_gs = Service.game_state()
	if _gs != null:
		_saved_current_level = _gs.get("current_level")

func after_test() -> void:
	if _gs != null:
		_gs.set("current_level", _saved_current_level)
	if _panel != null:
		_panel.free()
		_panel = null
	if _ap != null:
		_ap.free()
		_ap = null
	if _fake_dungeon != null:
		_fake_dungeon.free()
		_fake_dungeon = null


func _new_attr_panel() -> Node:
	return (load(ATTR_PANEL_SCRIPT) as GDScript).new()


func _make_panel(attr_panel: Node) -> Node:
	var panel := (load(LEVEL_UP_PANEL_SCENE) as PackedScene).instantiate()
	_panel = panel
	_ap = attr_panel
	add_child(panel)
	if attr_panel.get_parent() == null:
		add_child(attr_panel)
	panel.configure(attr_panel, _gs)
	return panel


func _send_tab(panel: Node) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.pressed = true
	panel._input(ev)


func _send_escape(panel: Node) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	panel._input(ev)


func test_level_up_does_not_auto_show_panel() -> void:
	var ap := _new_attr_panel()
	var panel := _make_panel(ap)
	await await_idle_frame()
	# 升级获得待处理选择（150 经验 → 1 级待处理）
	ap.accumulate_level_exp(150)
	await await_idle_frame()
	assert_bool(panel.visible) \
		.override_failure_message("升级获得属性/符文选择时不得自动弹出升级弹窗（应累计等待 TAB）") \
		.is_false()
	assert_int(ap.get_pending_level_choices()).is_equal(1)


func test_pending_choices_accumulate_across_levels() -> void:
	var ap := _new_attr_panel()
	var panel := _make_panel(ap)
	await await_idle_frame()
	ap.accumulate_level_exp(350)
	await await_idle_frame()
	assert_int(ap.get_pending_level_choices()).is_equal(2)
	assert_bool(panel.visible).is_false()
	# 打开后面板显示累计次数，逐个结算
	assert_bool(panel.open_if_pending()).is_true()
	assert_bool(panel.visible).is_true()
	assert_bool(String(panel.pending_label.text).contains("2")).is_true()
	assert_bool(ap.choose_level_up_attribute("con")).is_true()
	await await_idle_frame()
	assert_bool(panel.visible).is_true()
	assert_bool(String(panel.pending_label.text).contains("1")).is_true()
	assert_bool(ap.choose_level_up_attribute("str")).is_true()
	await await_idle_frame()
	assert_bool(panel.visible) \
		.override_failure_message("全部待处理升级结算完后弹窗应自动隐藏") \
		.is_false()


func test_open_if_pending_false_when_no_choices() -> void:
	var ap := _new_attr_panel()
	var panel := _make_panel(ap)
	await await_idle_frame()
	assert_bool(panel.open_if_pending()).is_false()
	assert_bool(panel.visible).is_false()


func test_tab_opens_panel_only_in_dungeon() -> void:
	var ap := _new_attr_panel()
	ap.accumulate_level_exp(150)
	var panel := _make_panel(ap)
	await await_idle_frame()
	# 非地牢（current_level 为空）：TAB 不弹出、不拦截
	_send_tab(panel)
	assert_bool(panel.visible).is_false()
	# 地牢上下文：注册一个带地牢脚本的关卡节点（不放入场景树，避免跑地牢逻辑）
	var fake_dungeon := Node3D.new()
	fake_dungeon.name = "FakeDungeon"
	fake_dungeon.set_script(load(DUNGEON_SCRIPT))
	_fake_dungeon = fake_dungeon
	_gs.set("current_level", fake_dungeon)
	_send_tab(panel)
	assert_bool(panel.visible) \
		.override_failure_message("地牢场景存在待处理升级时按 TAB 应弹出升级奖励面板") \
		.is_true()
	# TAB 打开后面板已可见，再次 TAB 不再重复处理
	_send_tab(panel)
	# 孤儿检查发生在 after_test 之前：未入树的 fake 节点必须在测试体内释放
	fake_dungeon.free()
	_fake_dungeon = null


func test_escape_postpones_panel_and_unlocks() -> void:
	var ap := _new_attr_panel()
	ap.accumulate_level_exp(150)
	var panel := _make_panel(ap)
	await await_idle_frame()
	assert_bool(panel.open_if_pending()).is_true()
	_send_escape(panel)
	assert_bool(panel.visible) \
		.override_failure_message("ESC 应可暂缓关闭升级奖励面板（待处理选择保留）") \
		.is_false()
	# 待处理次数保留，可再次打开
	assert_int(ap.get_pending_level_choices()).is_equal(1)
	assert_bool(panel.open_if_pending()).is_true()

## 经验 HUD 上方的"待处理升级"角标：存在待处理升级时显示"按 TAB 处理升级 ×N"，否则隐藏。
func test_pending_level_up_label_shows_and_hides() -> void:
	var hud := (load("res://scenes/ui/combat_hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	# 禁用 _process，避免测试环境对 current_player 的 shields/buffs 查询产生噪音
	hud.process_mode = Node.PROCESS_MODE_DISABLED
	await await_idle_frame()
	assert_object(hud.pending_level_up_label).is_not_null()
	assert_bool(hud.pending_level_up_label.visible).is_false()
	hud._update_pending_level_up_label(2)
	assert_bool(hud.pending_level_up_label.visible).is_true()
	assert_bool(String(hud.pending_level_up_label.text).contains("2")).is_true()
	hud._update_pending_level_up_label(0)
	assert_bool(hud.pending_level_up_label.visible).is_false()
	hud.queue_free()
	await await_idle_frame()
