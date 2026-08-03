extends SceneTree
## 验证 PixelView（方案2 低分辨率+最近邻）在真实游戏 World 中的效果。
## 实例化 world.tscn -> 等目标空间与玩家相机就绪 -> 截主视口全图。

const DUNGEON_FILTERED_OUT_ABS := "D:/123/Lantern Tavern/reports/retro_pixel_preview/ingame_pixel_view.png"
const DUNGEON_UNFILTERED_OUT_ABS := "D:/123/Lantern Tavern/reports/dungeon_ingame_unfiltered.png"
const TAVERN_FILTERED_OUT_ABS := "D:/123/Lantern Tavern/reports/retro_pixel_preview/tavern_ingame_pixel_view.png"
const TAVERN_UNFILTERED_OUT_ABS := "D:/123/Lantern Tavern/reports/tavern_ingame_unfiltered.png"
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")

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
	# PixelView 后处理与材质 Toon 着色是独立功能；本工具只切换前者。
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	var world := packed.instantiate() as Node3D
	var capture_tavern := _has_user_arg("--tavern")
	var capture_filter_enabled := _has_user_arg("--pixel-filter")
	var pixel_view := world.get_node_or_null("PixelView") as PixelView
	if pixel_view != null:
		pixel_view.filter_enabled = capture_filter_enabled
	root.add_child(world)
	# World._ready() 会先异步预热 shader，再加载初始空间；必须等它完成，
	# 否则提前切入地牢后，初始空间加载会再次把画面覆盖回酒馆。
	var initialization_deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < initialization_deadline:
		if world.get("current_loaded_level") != null:
			break
		await process_frame
	var target_space := "tavern" if capture_tavern else "dungeon"
	if not capture_tavern:
		world.call("transition_to_dungeon")
	# 等目标空间加载 + 玩家相机激活
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		var level := world.get("current_loaded_level") as Node3D
		var cam := root.get_camera_3d()
		if String(world.get("current_space")) == target_space \
				and level != null and cam != null and cam.get_parent() != null:
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
	var output_path := _capture_output_path(capture_tavern, capture_filter_enabled)
	if image.save_png(output_path) != OK:
		push_error("Failed to save " + output_path)
		_had_error = true
	else:
		print("[PixelViewCapture] saved " + output_path)
	pixel_view = world.get_node_or_null("PixelView") as PixelView
	if pixel_view == null:
		push_error("PixelView node missing in World.")
		_had_error = true
	elif root.disable_3d != capture_filter_enabled:
		push_error("Main viewport 3D state does not match requested PixelView mode.")
		_had_error = true
	quit(1 if _had_error else 0)


func _has_user_arg(expected: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if String(arg) == expected:
			return true
	return false


func _capture_output_path(capture_tavern: bool, capture_filter_enabled: bool) -> String:
	if capture_tavern:
		return TAVERN_FILTERED_OUT_ABS if capture_filter_enabled else TAVERN_UNFILTERED_OUT_ABS
	return DUNGEON_FILTERED_OUT_ABS if capture_filter_enabled else DUNGEON_UNFILTERED_OUT_ABS
