extends Node3D
## 酒馆地下层（酒窖 + 酿造间）3D 实机视角捕获工具。
## 只读捕获：实例化 tavern.tscn 后加相机/补光，不修改任何场景/材质。
## 输出：
##   reports/tavern_underground_topdown.png  — 地下层正交俯视（酒窖 + 酿造间）
##   reports/tavern_underground_3d.png       — 地下层 3/4 透视实机视角（酿造间方向）

const TAVERN_SCENE := preload("res://scenes/tavern/tavern.tscn")
const OUTPUT_TOPDOWN := "res://reports/tavern_underground_topdown.png"
const OUTPUT_3D := "res://reports/tavern_underground_3d.png"
const OUTPUT_CAULDRON := "res://reports/tavern_underground_cauldron_closeup.png"

var _camera: Camera3D


func _ready() -> void:
	print("UNDERGROUND_CAPTURE_READY")
	get_window().size = Vector2i(1600, 1100)
	_prepare_tavern_state()
	var tavern := TAVERN_SCENE.instantiate() as Node3D
	add_child(tavern)
	# 等玩家/酿酒协调器延迟装配（炼药锅站、原料架、倒桶台、窖藏位）
	for i in 24:
		await get_tree().process_frame
	_add_underground_lights()
	_camera = Camera3D.new()
	_camera.name = "UndergroundCaptureCamera"
	add_child(_camera)
	await _capture_topdown_pass()
	await _capture_perspective_pass()
	await _capture_cauldron_closeup()
	var final_colors := _sample_color_count(get_viewport().get_texture().get_image())
	print("UNDERGROUND_CAPTURE_DONE passes=3 colors=%d" % final_colors)
	get_tree().quit(0 if final_colors >= 6 else 2)


## 相机必须放在主厅地板（y≈-0.1）之下、地下地板（y=-3.04）之上，才不会被地面层遮挡。
func _capture_topdown_pass() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 13.0
	_camera.position = Vector3(1.0, -0.7, -6.1)
	_camera.look_at(Vector3(1.0, -3.04, -6.1), Vector3(0.0, 0.0, 1.0))
	_camera.make_current()
	for i in 20:
		await get_tree().process_frame
		_camera.make_current()
	_save_viewport(OUTPUT_TOPDOWN)


func _capture_perspective_pass() -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 66.0
	# 相机在酿造间东南角内部，广角朝向酒窖门洞方向：
	# 炼药锅（中）、倒桶台（右下）、原料架（左上）、门洞（左中）
	_camera.position = Vector3(6.8, -0.5, -7.3)
	_camera.look_at(Vector3(3.9, -2.5, -6.1), Vector3(0.0, 1.0, 0.0))
	_camera.make_current()
	for i in 20:
		await get_tree().process_frame
		_camera.make_current()
	_save_viewport(OUTPUT_3D)


func _capture_cauldron_closeup() -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 55.0
	# 炼药锅特写（炼药锅在酿造间 (4.4,-3.0,-6.9)，锅高 1.94m 顶部 y=-1.06）：
	# 相机退到东南角墙前 (7.8,-7.5)，完整露出 三足→圆肚→束颈→宽沿 全轮廓
	_camera.position = Vector3(7.8, -1.4, -7.5)
	_camera.look_at(Vector3(4.4, -2.05, -6.9), Vector3(0.0, 1.0, 0.0))
	_camera.make_current()
	var spot := OmniLight3D.new()
	spot.name = "CauldronCloseupOmni"
	spot.light_energy = 2.2
	spot.omni_range = 5.0
	spot.position = Vector3(5.6, -1.9, -7.2)
	add_child(spot)
	for i in 20:
		await get_tree().process_frame
		_camera.make_current()
	_save_viewport(OUTPUT_CAULDRON)
	spot.queue_free()


func _save_viewport(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		printerr("Capture image is null for %s" % path)
		get_tree().quit(1)
		return
	var err := image.save_png(path)
	if err != OK:
		printerr("Failed to save capture %s: %d" % [path, err])
		get_tree().quit(1)
		return
	print("UNDERGROUND_CAPTURE_SAVED %s" % path)


func _add_underground_lights() -> void:
	var dir := DirectionalLight3D.new()
	dir.name = "UndergroundFillLight"
	dir.light_energy = 1.3
	dir.shadow_enabled = true
	dir.position = Vector3(1.0, -0.7, -6.1)
	add_child(dir)
	dir.look_at(Vector3(1.0, -4.0, -6.1), Vector3(0.0, 0.0, 1.0))

	var omni_brew := OmniLight3D.new()
	omni_brew.name = "BrewRoomOmni"
	omni_brew.light_energy = 1.6
	omni_brew.omni_range = 7.0
	omni_brew.position = Vector3(5.15, -2.1, -5.57)
	add_child(omni_brew)

	var omni_cellar := OmniLight3D.new()
	omni_cellar.name = "CellarOmni"
	omni_cellar.light_energy = 1.3
	omni_cellar.omni_range = 7.0
	omni_cellar.position = Vector3(-1.0, -2.1, -6.1)
	add_child(omni_cellar)


func _prepare_tavern_state() -> void:
	var tavern_manager := get_tree().root.get_node_or_null("TavernManager")
	if tavern_manager != null:
		tavern_manager.set("tutorial_completed", true)
		tavern_manager.set("has_confirmed_character_name", true)


func _sample_color_count(image: Image) -> int:
	if image == null:
		return 0
	var colors := {}
	var step_x := maxi(image.get_width() / 80, 1)
	var step_y := maxi(image.get_height() / 55, 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0)]
			colors[key] = true
	return colors.size()
