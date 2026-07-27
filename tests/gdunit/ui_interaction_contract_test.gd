extends GdUnitTestSuite

const PIXEL_THEME_PATH := "res://scenes/ui/lantern_theme.tres"
const PAGE_SCRIPTS := [
	"res://scenes/ui/main_menu.gd",
	"res://scenes/ui/settings_menu.gd",
	"res://scenes/ui/model_viewer.gd",
	"res://scenes/ui/lobby_menu.gd",
	"res://scenes/ui/zone_select.gd",
]
const PIXEL_SCENES := [
	"res://scenes/ui/character_name_prompt.tscn",
	"res://scenes/ui/scripted_dialogue_box.tscn",
	"res://scenes/ui/tutorial_hint_overlay.tscn",
	"res://scenes/ui/expedition_prompt.tscn",
	"res://scenes/ui/zone_select.tscn",
	"res://scenes/ui/stat_indicator.tscn",
]

var _original_mouse_mode := Input.MOUSE_MODE_VISIBLE


func before() -> void:
	_original_mouse_mode = Input.get_mouse_mode()


func after() -> void:
	Input.set_mouse_mode(_original_mouse_mode)


func test_page_ui_has_shared_cancel_and_pixel_mouse_contract() -> void:
	var source := _source("res://scenes/ui/core/ui_screen.gd")
	assert_bool(source.contains("func _input(event: InputEvent)")) \
		.override_failure_message("页面取消键必须在 GUI 子控件之前捕获").is_true()
	assert_bool(source.contains("KEY_ESCAPE")).is_true()
	assert_bool(source.contains("KEY_TAB")).is_true()
	assert_bool(source.contains("MOUSE_MODE_VISIBLE")).is_true()
	assert_bool(source.contains("MOUSE_MODE_CAPTURED")).is_true()
	assert_bool(source.contains("TEXTURE_FILTER_NEAREST")).is_true()
	assert_bool(source.contains(PIXEL_THEME_PATH)).is_true()


func test_all_page_screens_override_cancel_to_return_or_close() -> void:
	for path in PAGE_SCRIPTS:
		var source := _source(path)
		assert_bool(source.contains("func _on_cancel_input()")) \
			.override_failure_message("页面缺少 ESC/TAB 取消动作: %s" % path).is_true()


func test_page_base_closes_on_escape_and_tab_before_child_focus_navigation() -> void:
	var screen := UiScreen.new()
	add_child(screen)
	await await_idle_frame()
	for keycode in [KEY_ESCAPE, KEY_TAB]:
		screen.visible = true
		screen.lifecycle = UiScreen.Lifecycle.OPEN
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = true
		screen._input(event)
		assert_bool(screen.visible).is_false()
		if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
			assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_CAPTURED)
	screen.queue_free()


func test_clickable_overlay_sources_restore_captured_mouse_on_exit() -> void:
	for path in [
		"res://scenes/ui/pause_menu.gd",
		"res://scenes/ui/chest_loot_panel.gd",
		"res://scenes/ui/tavern_equipment_panel.gd",
		"res://scenes/ui/character_panel.gd",
	]:
		var source := _source(path)
		assert_bool(source.contains("KEY_ESCAPE")) \
			.override_failure_message("可交互 UI 缺少 ESC 退出: %s" % path).is_true()
		assert_bool(source.contains("KEY_TAB")) \
			.override_failure_message("可交互 UI 缺少 TAB 退出: %s" % path).is_true()
		assert_bool(source.contains("MOUSE_MODE_CAPTURED")) \
			.override_failure_message("可交互 UI 退出后未恢复鼠标捕获: %s" % path).is_true()


func test_nested_save_panel_has_own_escape_and_tab_close_path() -> void:
	var source := _source("res://scenes/ui/save_load_panel.gd")
	assert_bool(source.contains("func _input(event: InputEvent)")) \
		.override_failure_message("存档子面板必须独立处理取消输入").is_true()
	assert_bool(source.contains("KEY_ESCAPE")).is_true()
	assert_bool(source.contains("KEY_TAB")).is_true()
	assert_bool(source.contains("back_pressed.emit()")) \
		.override_failure_message("存档子面板取消后必须返回暂停菜单").is_true()


func test_tavern_hud_closes_without_opening_pause_menu() -> void:
	var hud_source := _source("res://scenes/ui/tavern_hud.gd")
	var manager_source := _source("res://scenes/tavern/tavern_manager_node.gd")
	assert_bool(hud_source.contains("close_tavern_hud")).is_true()
	assert_bool(not hud_source.contains("_toggle_pause_menu()")) \
		.override_failure_message("经营 HUD 退出不应误打开暂停菜单").is_true()
	assert_bool(manager_source.contains("func close_tavern_hud()")) \
		.override_failure_message("酒馆管理器必须提供经营 HUD 的关闭入口").is_true()
	assert_bool(manager_source.contains("MOUSE_MODE_CAPTURED")).is_true()


func test_overlay_close_restores_gameplay_mouse_capture() -> void:
	var source := _source("res://scenes/world/world.gd")
	var close_start := source.find("func close_overlay()")
	var close_end := source.find("\nfunc ", close_start + 1)
	var close_body := source.substr(close_start, close_end - close_start)
	assert_bool(close_body.contains("_clear_overlay()")).is_true()
	assert_bool(close_body.contains("MOUSE_MODE_CAPTURED")) \
		.override_failure_message("区域选择覆盖层关闭后必须恢复鼠标捕获").is_true()


func test_detail_popup_is_pixel_styled_and_cleanup_is_centralized() -> void:
	var popup_source := _source("res://scenes/ui/equipment_detail_popup.gd")
	assert_bool(popup_source.contains("PIXEL_THEME")).is_true()
	assert_bool(popup_source.contains("TEXTURE_FILTER_NEAREST")).is_true()
	assert_bool(popup_source.contains("MOUSE_FILTER_IGNORE")).is_true()
	var ui_source := _source("res://scenes/ui/ui.gd")
	assert_bool(ui_source.contains("item_detail_popup.hide_detail()")) \
		.override_failure_message("共享 UI 清理提示时必须同步隐藏详情悬浮窗").is_true()


func test_hover_sources_hide_detail_popup_on_mouse_exit() -> void:
	var inventory_source := _source("res://scenes/ui/inventory_drag_list.gd")
	var slot_source := _source("res://scenes/ui/equipment_slot_drop_button.gd")
	assert_bool(inventory_source.contains("func _on_mouse_exited()")) \
		.override_failure_message("背包物品离开后必须隐藏详情悬浮窗").is_true()
	assert_bool(inventory_source.contains("panel.hide_detail_popup()")) \
		.override_failure_message("背包离开事件必须调用详情清理").is_true()
	assert_bool(slot_source.contains("func _on_mouse_exited()")) \
		.override_failure_message("装备槽离开后必须隐藏详情悬浮窗").is_true()
	assert_bool(slot_source.contains("panel.hide_detail_popup()")) \
		.override_failure_message("装备槽离开事件必须调用详情清理").is_true()


func test_interaction_hint_uses_square_nearest_pixel_style() -> void:
	var source := _source("res://scenes/ui/interaction_hint_base.gd")
	assert_bool(source.contains("TEXTURE_FILTER_NEAREST")).is_true()
	assert_bool(source.contains("anti_aliasing = false")).is_true()
	assert_bool(source.contains("corner_detail = 1")).is_true()
	assert_bool(not source.contains("corner_radius_top_left = 6")).is_true()


func test_standalone_overlay_scenes_reference_pixel_theme_and_nearest_filter() -> void:
	for path in PIXEL_SCENES:
		var source := FileAccess.get_file_as_string(path)
		assert_str(source).contains(PIXEL_THEME_PATH) \
			.override_failure_message("UI 场景缺少像素主题: %s" % path)
		assert_str(source).contains("texture_filter = 1") \
			.override_failure_message("UI 场景未固定最近邻采样: %s" % path)


func test_character_name_prompt_can_cancel_with_escape_or_tab() -> void:
	var source := _source("res://scenes/ui/character_name_prompt.gd")
	assert_bool(source.contains("func _input(event: InputEvent)")) \
		.override_failure_message("姓名输入弹窗必须在 LineEdit 消费按键前捕获取消输入").is_true()
	assert_bool(source.contains("signal cancelled")).is_true()
	assert_bool(source.contains("KEY_ESCAPE")).is_true()
	assert_bool(source.contains("KEY_TAB")).is_true()
	assert_bool(source.contains("cancelled.emit()")) \
		.override_failure_message("姓名输入弹窗取消后必须通知教程流程并退出").is_true()


func test_equipment_hover_exit_hides_detail_popup_at_runtime() -> void:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var panel := load("res://scenes/ui/tavern_equipment_panel.tscn").instantiate() as TavernEquipmentPanel
	host.add_child(panel)
	panel.visible = true
	await await_idle_frame()

	var popup := panel.get_node("EquipmentDetailPopup") as Control
	var inventory := panel.get_node("%GearList")
	var equipment_slot := panel.get_node("%SlotHead")
	popup.show_for_material_id("wild_glowcap", 1, Vector2(20, 20))
	assert_bool(popup.visible).is_true()
	inventory.call("_on_mouse_exited")
	assert_bool(popup.visible).is_false()

	popup.show_for_material_id("wild_glowcap", 1, Vector2(20, 20))
	assert_bool(popup.visible).is_true()
	equipment_slot.call("_on_mouse_exited")
	assert_bool(popup.visible).is_false()
	host.queue_free()


func test_equipment_escape_and_tab_close_and_recapture_mouse() -> void:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var panel := load("res://scenes/ui/tavern_equipment_panel.tscn").instantiate() as TavernEquipmentPanel
	host.add_child(panel)
	await await_idle_frame()

	for keycode in [KEY_ESCAPE, KEY_TAB]:
		panel.show_panel()
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = true
		panel._input(event)
		assert_bool(panel.visible).is_false()
		if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
			assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_CAPTURED)
	host.queue_free()


func test_check_for_selection_hides_popup_when_character_panel_visible() -> void:
	var source := _source("res://scenes/characters/player/player.gd")
	var sel_start := source.find("func check_for_selection()")
	assert_bool(sel_start >= 0).override_failure_message("缺少 check_for_selection").is_true()
	var sel_end := source.find("\nfunc ", sel_start + 1)
	var sel_body := source.substr(sel_start, sel_end - sel_start)
	assert_bool(sel_body.contains("is_character_panel_visible()")) \
		.override_failure_message("check_for_selection 必须在角色面板可见时抑制物品检视，避免悬浮窗卡在面板上").is_true()
	assert_bool(sel_body.contains("item_detail_changed.emit({}, Vector2.ZERO)")) \
		.override_failure_message("面板可见时必须发射空详情以隐藏世界悬浮窗").is_true()


func test_check_for_possible_action_suppresses_hints_when_character_panel_visible() -> void:
	var source := _source("res://scenes/characters/player/player.gd")
	var pa_start := source.find("func check_for_possible_action()")
	assert_bool(pa_start >= 0).override_failure_message("缺少 check_for_possible_action").is_true()
	var pa_end := source.find("\nfunc ", pa_start + 1)
	var pa_body := source.substr(pa_start, pa_end - pa_start)
	assert_bool(pa_body.contains("is_character_panel_visible()")) \
		.override_failure_message("check_for_possible_action 必须在角色面板可见时统一抑制交互提示").is_true()


func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code
