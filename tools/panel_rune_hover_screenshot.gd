extends SceneTree
## 技能/符文配置界面截图工具。
## 实例化整个 TavernEquipmentPanel 场景，镶嵌符文，模拟悬浮状态，截图整个面板。
## 用法（不要用 --headless，需要渲染）：
##   & "D:/123/Godot_v4.7-stable_mono_win64.exe" --path "D:/123/Lantern Tavern" --script res://tools/panel_rune_hover_screenshot.gd
## 输出：reports/rune_tooltip_preview/panel_rune_hover_<rune_id>.png

const PANEL_SCENE := preload("res://scenes/ui/tavern_equipment_panel.tscn")

func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	await process_frame

	var sr := root.get_node_or_null("SkillRuntime")
	if sr == null:
		push_error("SkillRuntime autoload 未找到")
		quit(1)
		return

	# 设置捕获模式标记，跳过 PLAYER_FINDER 等运行时依赖
	root.set_meta("equipment_capture_mode", true)

	# 重置并镶嵌符文：
	# 槽 0 (F 动作槽): thunder_run 配方 (surge + force + quick) — 3个符文
	# 槽 1 (G 武器槽): aegis 配方 (guardian + guardian + force) — 3个符文
	sr.reset()
	sr.slots[0] = "踢击"
	sr.socket_rune(0, "surge")
	sr.socket_rune(0, "force")
	sr.socket_rune(0, "quick")
	sr.slots[1] = "冲撞"
	sr.socket_rune(1, "guardian")
	sr.socket_rune(1, "guardian")
	sr.socket_rune(1, "force")

	print("Active rune words: %s" % str(sr.get_active_rune_words()))

	# 创建输出目录
	var dir := DirAccess.open("res://")
	if dir == null:
		push_error("无法打开项目目录")
		quit(1)
		return
	if not dir.dir_exists("reports/rune_tooltip_preview"):
		dir.make_dir_recursive("reports/rune_tooltip_preview")

	# 实例化面板
	var panel: Control = PANEL_SCENE.instantiate()
	root.add_child(panel)

	# 设置面板大小并显示
	panel.size = Vector2i(1600, 1000)
	panel.visible = true

	# 等待布局完成
	await process_frame
	await process_frame
	await process_frame

	# 切换到技能 Tab（索引 1）
	var right_tabs: TabContainer = panel.find_child("RightTabs", true, false) as TabContainer
	if right_tabs != null:
		right_tabs.current_tab = 1

	await process_frame
	await process_frame

	# 刷新面板数据
	if panel.has_method("_refresh_all"):
		panel._refresh_all()
	if panel.has_method("show_panel"):
		panel.show_panel()

	await process_frame
	await process_frame
	await process_frame

	# 确保信息面板已创建并挂载到场景树
	var pyramid_check: Node = panel.find_child("SkillPyramid", true, false)
	print("SkillPyramid 查找结果: %s" % (pyramid_check.name if pyramid_check != null else "null"))

	var existing_panel: Control = panel.get("rune_word_info_panel") as Control
	if existing_panel != null and existing_panel.get_parent() != null:
		print("rune_word_info_panel 已存在且已挂载, parent=%s" % existing_panel.get_parent().name)
	else:
		print("rune_word_info_panel 状态: panel=%s, parent=%s" % [existing_panel != null, existing_panel.get_parent() if existing_panel != null else "null"])

	# 创建 SubViewport 渲染整个面板
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 1000)
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false

	# 把面板移到 SubViewport 下
	var old_parent := panel.get_parent()
	old_parent.remove_child(panel)
	vp.add_child(panel)
	root.add_child(vp)

	await process_frame
	await process_frame
	await process_frame

	# 截图 1：无悬浮状态
	_save_screenshot(vp, "panel_rune_no_hover.png")

	# 查找符文槽位按钮，模拟悬浮不同的符文
	var rune_buttons: Array = []
	for child in panel.find_children("RuneSlot*", "Button", true, false):
		if "rune_id" in child:
			rune_buttons.append(child)

	print("找到 %d 个符文槽位按钮" % rune_buttons.size())

	# 对每个有符文的槽位模拟悬浮
	var captured: Dictionary = {}
	for button in rune_buttons:
		var rune_id := String(button.get("rune_id"))
		if rune_id.is_empty() or captured.has(rune_id):
			continue
		captured[rune_id] = true

		# 模拟 mouse_entered
		if panel.has_method("_on_rune_slot_hovered"):
			panel._on_rune_slot_hovered(button)

		# 等待更多帧确保布局和渲染完成
		await process_frame
		await process_frame
		await process_frame
		await process_frame
		await process_frame

		# 验证面板可见性
		var info_panel: Control = panel.get("rune_word_info_panel") as Control
		if info_panel != null:
			print("  悬浮 %s: info_panel.visible=%s, parent=%s, name=%s" % [rune_id, info_panel.visible, info_panel.get_parent() if info_panel.get_parent() != null else "null", info_panel.name])
		else:
			print("  悬浮 %s: rune_word_info_panel 属性为 null" % rune_id)

		_save_screenshot(vp, "panel_rune_hover_%s.png" % rune_id)

		# 模拟 mouse_exited
		if panel.has_method("_on_rune_slot_unhovered"):
			panel._on_rune_slot_unhovered()

		await process_frame

	print("=== 面板截图已保存到 reports/rune_tooltip_preview/ ===")
	quit(0)

func _save_screenshot(vp: SubViewport, filename: String) -> void:
	var img := vp.get_texture().get_image()
	var path := "res://reports/rune_tooltip_preview/%s" % filename
	var err := img.save_png(path)
	if err == OK:
		print("已保存: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	else:
		push_error("保存失败: %s (错误 %d)" % [path, err])
