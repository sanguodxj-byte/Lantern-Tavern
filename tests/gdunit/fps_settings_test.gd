extends GdUnitTestSuite

## FPS 显示设置 + 右上角叠层 回归测试。
## Settings 为 autoload（globals/settings.gd）；FPS 叠层常驻 World（scenes/ui/fps_overlay.tscn）。

const FPS_OVERLAY_SCENE := preload("res://scenes/ui/fps_overlay.tscn")
const SETTINGS_MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const SETTINGS_GD_PATH := "res://scenes/ui/settings_menu.gd"
const SETTINGS_MENU_TSCN_PATH := "res://scenes/ui/settings_menu.tscn"

func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func test_settings_autoload_registered() -> void:
	# Settings autoload 必须存在，并提供 show_fps 开关与 settings_changed 信号
	assert_object(Settings).is_not_null()
	assert_bool(Settings.show_fps is bool).is_true()
	assert_bool(Settings.has_signal("settings_changed")).is_true()

func test_settings_show_fps_toggle() -> void:
	# set_show_fps 在值变化时更新属性并通过信号广播（不依赖文件落盘是否成功）
	var received := [false]
	Settings.settings_changed.connect(func(): received[0] = true)
	var before := Settings.show_fps
	Settings.set_show_fps(not before)
	assert_bool(Settings.show_fps).is_equal(not before)
	assert_bool(received[0]).is_true()
	Settings.set_show_fps(before)  # 还原，避免影响后续运行持久态

func test_fps_overlay_hidden_until_enabled() -> void:
	Settings.set_show_fps(false)
	var overlay := FPS_OVERLAY_SCENE.instantiate()
	add_child(overlay)
	# 默认（关闭）叠层隐藏
	assert_bool(overlay.visible).is_false()
	# 打开设置开关 → 信号驱动叠层可见
	Settings.set_show_fps(true)
	assert_bool(overlay.visible).is_true()
	# 刷新后文本含 FPS 字样（headless 下帧率为 0，但格式为 "FPS: 0"）
	overlay._refresh()
	assert_str(overlay.get_node("Label").text).contains("FPS")
	Settings.set_show_fps(false)
	overlay.queue_free()

func test_settings_menu_has_fps_toggle() -> void:
	# 设置菜单场景含 ShowFpsCheck 节点，且 settings_menu.gd 把开关接到 Settings.set_show_fps
	var src := _read_source(SETTINGS_GD_PATH)
	assert_bool(src.contains("ShowFpsCheck")).is_true()
	assert_bool(src.contains("set_show_fps(enabled)")).is_true()
	var tscn := _read_source(SETTINGS_MENU_TSCN_PATH)
	assert_bool(tscn.contains("[node name=\"ShowFpsCheck\"")) \
		.override_failure_message("settings_menu.tscn 缺少 ShowFpsCheck 节点") \
		.is_true()

func test_settings_menu_scene_compiles_and_instantiates() -> void:
	# 编译校验：SETTINGS_MENU_SCENE 预加载会编译 settings_menu.gd（含本次新增的 FPS 开关接线）
	assert_object(SETTINGS_MENU_SCENE).is_not_null()
	var menu := SETTINGS_MENU_SCENE.instantiate()
	assert_object(menu).is_not_null()
	menu.queue_free()
