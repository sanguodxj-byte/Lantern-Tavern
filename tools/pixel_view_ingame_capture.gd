extends SceneTree
## 验证 PixelView（方案2 低分辨率+最近邻）在真实游戏 World 中的效果。
## 实例化 world.tscn -> 强制进 dungeon -> 等玩家相机 -> 截主视口全图。

const OUT_ABS := "D:/123/Lantern Tavern/reports/retro_pixel_preview/ingame_pixel_view.png"

var _had_error := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requires non-headless renderer.")
		quit(4)
		return
	root.size = Vector2i(1920, 1080)
	var tm := root.get_node_or_null("TavernManager")
	if tm != null:
		tm.current_phase = tm.Phase.NIGHT_TAVERN
	var packed := load("res://scenes/world/world.tscn") as PackedScene
	var world := packed.instantiate() as Node3D
	root.add_child(world)
	await process_frame
	world.call("transition_to_dungeon")
	# 等 dungeon 加载 + 玩家相机激活
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		var level := world.get("current_loaded_level") as Node3D
		var cam := root.get_camera_3d()
		if level != null and cam != null and cam.get_parent() != null:
			break
		await process_frame
	# 等渲染稳定
	for i in 60:
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Main viewport image empty.")
		quit(2)
		return
	if image.save_png(OUT_ABS) != OK:
		push_error("Failed to save " + OUT_ABS)
		_had_error = true
	else:
		print("[PixelViewCapture] saved " + OUT_ABS)
	# 校验 PixelView 生效：主视口应已 disable_3d
	var pixel_view := world.get_node_or_null("PixelView")
	if pixel_view == null:
		push_error("PixelView node missing in World.")
		_had_error = true
	elif not root.disable_3d:
		push_error("Main viewport 3D not disabled — PixelView inactive.")
		_had_error = true
	quit(1 if _had_error else 0)
