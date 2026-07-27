extends SceneTree
## 单独 instantiate chest_loot_panel.tscn,进入可见状态,截图。
## 用来验证 LootFrame theme 是否正确加载。

const PANEL := preload("res://scenes/ui/chest_loot_panel.tscn")

func _initialize() -> void:
	var root := Window.new()
	root.size = Vector2i(1920, 1080)
	get_root().add_child(root)
	# 1) 把 theme 资源打印出来,确认 LootFrame 定义存在
	var theme: Theme = load("res://scenes/ui/lantern_theme.tres")
	if theme == null:
		push_error("[Probe] theme is null")
		quit(1)
		return
	print("[Probe] theme item 'LootFrame' exists: %s" % str(theme.has_stylebox("panel", "LootFrame")))
	if theme.has_stylebox("panel", "LootFrame"):
		var sb: StyleBox = theme.get_stylebox("panel", "LootFrame")
		print("[Probe] LootFrame panel style = %s" % str(sb))
		if sb is StyleBoxFlat:
			print("[Probe] LootFrame bg = %s" % str(sb.bg_color))
	# 2) 实例化 panel
	var panel_inst = PANEL.instantiate()
	get_root().add_child(panel_inst)
	if panel_inst is CanvasLayer:
		print("[Probe] panel layer = %d" % panel_inst.layer)
	# 3) 让 panel 显形
	panel_inst.visible = true
	# 4) 等几帧
	await create_timer(0.2).timeout
	for i in range(5):
		await process_frame
	# 5) 打印 panel 内部 LootFrame 节点的 theme 状态
	var lf = panel_inst.get_node_or_null("Root/LootFrame")
	if lf == null:
		push_error("[Probe] LootFrame not found")
		quit(2)
		return
	print("[Probe] LootFrame class = %s" % lf.get_class())
	print("[Probe] LootFrame theme_type_variation = %s" % str(lf.theme_type_variation))
	var sb: StyleBox = lf.get_theme_stylebox("panel")
	print("[Probe] LootFrame runtime panel style = %s" % str(sb))
	if sb is StyleBoxFlat:
		print("[Probe] LootFrame runtime bg = %s" % str(sb.bg_color))
	# 5.5) 检查 4 个 Corner Panel 节点的实际 size
	for cn in ["CornerTL", "CornerTR", "CornerBL", "CornerBR"]:
		var n: Node = panel_inst.get_node_or_null("Root/" + cn)
		if n == null:
			print("[Probe] %s not found" % cn)
			continue
		print("[Probe] %s class=%s size=%s pos=%s anchor=(%s,%s,%s,%s)" % [
			cn, n.get_class(), str(n.size), str(n.position),
			str(n.anchor_left), str(n.anchor_top), str(n.anchor_right), str(n.anchor_bottom)
		])
	# 6) 截主 viewport(在 root Window 上)
	for i in range(8):
		RenderingServer.force_sync()
		RenderingServer.force_draw()
		await process_frame
	var win := get_root()
	var img: Image = null
	if win != null:
		var wvp := win.get_viewport()
		if wvp != null and wvp.get_texture() != null:
			img = wvp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png("res://reports/ui_runtime/probe_main_viewport.png")
		var c := img.get_pixel(960, 540)
		print("[Probe] main_viewport center color = %s  size=%dx%d" % [str(c), img.get_width(), img.get_height()])
	else:
		print("[Probe] main viewport image empty, trying SubViewport fallback")
		# 6b) 兜底: SubViewport(在 dummy renderer 上可能失败)
		var sv := SubViewport.new()
		sv.size = Vector2i(1920, 1080)
		sv.transparent_bg = false
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		get_root().add_child(sv)
		panel_inst.get_parent().remove_child(panel_inst)
		sv.add_child(panel_inst)
		for i in range(8):
			RenderingServer.force_sync()
			RenderingServer.force_draw()
			await process_frame
		img = sv.get_texture().get_image()
		if img != null and not img.is_empty():
			img.save_png("res://reports/ui_runtime/probe_lootframe_only.png")
			var c2 := img.get_pixel(960, 540)
			print("[Probe] probe_lootframe_only center color = %s" % str(c2))
	quit(0)
