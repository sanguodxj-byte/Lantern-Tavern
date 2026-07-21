extends GdUnitTestSuite

# 主菜单界面截图测试 - 在真实窗口渲染模式下捕获中文和英文渲染，以供视觉和美化效果检查

const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"
var _original_locale: String

func before() -> void:
	_original_locale = TranslationServer.get_locale()
	# 确保 reports 目录存在
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists("reports"):
		dir.make_dir("reports")

func after() -> void:
	TranslationServer.set_locale(_original_locale)

func test_capture_main_menu_screenshots() -> void:
	# 记录原窗口大小并强行设置为 1920x1080，以保证 MenuVBox 不会因为低分辨率而溢出裁剪
	var original_window_size := DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	
	# 给 Godot 几帧时间来应用新的窗口大小
	for i in range(5):
		await get_tree().process_frame

	# 1. 实例化主菜单并加到场景树中，它会自动铺满 1920x1080 的主视口
	var packed := load(MAIN_MENU_PATH) as PackedScene
	assert_bool(packed != null).is_true()
	var menu := packed.instantiate() as Control
	assert_bool(menu != null).is_true()
	add_child(menu)

	# 2. 【核心修复】强行等待 200 帧，消耗掉测试刚启动时所有的 3D 背景载入与 Shader 编译卡顿，确保主视口渲染状态彻底平稳
	for i in range(200):
		await get_tree().process_frame

	# 强行将 SidePanel 及其下的按钮全部设置为完全显现的最终状态，规避任何动画中途挂起的问题
	var side_panel = menu.get_node_or_null("SidePanel")
	if side_panel:
		side_panel.modulate.a = 1.0
	var menu_vbox = menu.get_node_or_null("SidePanel/MenuVBox")
	if menu_vbox:
		for child in menu_vbox.get_children():
			if child is Control:
				child.modulate.a = 1.0
				child.scale = Vector2(1.0, 1.0)

	# 3. 截取中文界面
	TranslationServer.set_locale("zh")
	if menu.has_method("_update_button_texts"):
		menu.call("_update_button_texts")
	
	# 等待 10 帧确保 layout 刷新在物理视口中被重新绘制
	for i in range(10):
		await get_tree().process_frame

	# 抓取整个主视口的纹理并保存
	var tex_zh := get_viewport().get_texture()
	assert_bool(tex_zh != null).is_true()
	var img_zh := tex_zh.get_image()
	var save_path_zh := "res://reports/main_menu_screenshot_zh.png"
	if img_zh != null:
		var err := img_zh.save_png(save_path_zh)
		print("[截图测试] 中文版保存至: %s 结果: %s 尺寸: %s" % [save_path_zh, str(err), str(img_zh.get_size())])
		assert_int(err).is_equal(OK)

	# 4. 接着截取英文界面
	TranslationServer.set_locale("en")
	if menu.has_method("_update_button_texts"):
		menu.call("_update_button_texts")

	# 等待 10 帧确保 layout 刷新在物理视口中被重新绘制
	for i in range(10):
		await get_tree().process_frame

	var tex_en := get_viewport().get_texture()
	assert_bool(tex_en != null).is_true()
	var img_en := tex_en.get_image()
	var save_path_en := "res://reports/main_menu_screenshot_en.png"
	if img_en != null:
		var err := img_en.save_png(save_path_en)
		print("[截图测试] 英文版保存至: %s 结果: %s 尺寸: %s" % [save_path_en, str(err), str(img_en.get_size())])
		assert_int(err).is_equal(OK)

	# 5. 清理并恢复窗口大小
	remove_child(menu)
	menu.queue_free()
	
	# 等待两帧让 queue_free() 在场景树中物理销毁，彻底避免 Orphan 节点泄漏警告
	await get_tree().process_frame
	await get_tree().process_frame
	
	DisplayServer.window_set_size(original_window_size)
