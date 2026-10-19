extends SceneTree
## 命中特效视觉验证（真实 3D 渲染捕获）
# 用途：验证 命中火花特效（fx/metal_spark.tscn，像素火花 shader）与
#       可破坏地牢场景物体 击碎碎屑特效（fx/voxel_chip.tscn）的实际渲染质量。
# 场景：石墙 + 火花爆发、木箱击碎（木色碎屑）、石材击碎（石色碎屑）。
# 运行（需要非 headless 渲染器）：
#   "D:/123/Godot_v4.7-stable_mono_win64.exe" --path "D:/123/Lantern Tavern" --script res://tools/fx_impact_visual_capture.gd
# 输出：res://reports/fx_preview/{metal_spark_wall,crate_break,stone_chips}_<frame>.png

const OUT_DIR := "res://reports/fx_preview"
const IMAGE_SIZE := Vector2i(1280, 720)
# 注意：--script 模式下脚本解析期 autoload 尚未注册（如 voxel_prop.gd 引用 GameEvents），
# 因此场景一律在 _run 延迟执行后用 load() 加载，不能在 const 中 preload。
const METAL_SPARK_PATH := "res://fx/metal_spark.tscn"
const VOXEL_CHIP_PATH := "res://fx/voxel_chip.tscn"
const DUNGEON_CRATE_PATH := "res://scenes/props/dungeon/dungeon_crate.tscn"
const WOOD_CHIP_COLOR := Color(0.62, 0.5, 0.36, 1.0)   # 与 dungeon_crate.tscn break_chip_color 一致
const STONE_CHIP_COLOR := Color(0.55, 0.55, 0.58, 1.0) # 与 sarcophagus/stalagmite break_chip_color 一致

var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FX impact visual capture requires a non-headless renderer.")
		quit(4)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _build_viewport()

	var spark_ok := await _capture_spark_on_wall()
	var crate_ok := await _capture_crate_break()
	var stone_ok := await _capture_stone_chips()
	quit(0 if spark_ok and crate_ok and stone_ok else 2)


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "FxImpactPreviewViewport"
	_viewport.size = IMAGE_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(_viewport)
	await process_frame

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.031, 0.039, 0.063, 1.0)  # 暗地牢底色
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.68, 1.0)
	environment.ambient_light_energy = 1.15
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	_viewport.add_child(world_env)

	_stage = Node3D.new()
	_stage.name = "FxPreviewStage"
	_viewport.add_child(_stage)

	var key_light := DirectionalLight3D.new()
	key_light.name = "WarmKeyLight"
	key_light.light_energy = 1.8
	_stage.add_child(key_light)
	key_light.look_at_from_position(Vector3(-3.2, 5.5, -4.6), Vector3(0.0, 0.8, 0.0), Vector3.UP)

	var fill_light := OmniLight3D.new()
	fill_light.name = "LowWarmFill"
	fill_light.position = Vector3(3.0, 2.2, 2.4)
	fill_light.light_color = Color(1.0, 0.72, 0.42, 1.0)
	fill_light.light_energy = 0.8
	fill_light.omni_range = 7.0
	_stage.add_child(fill_light)

	# 正面补光：受光材质（体素碎屑/对照盒）面向相机一侧需要足够照度，
	# 否则在暗地牢背景下暗到无法判定；自发光材质（金属火花）不受影响。
	var front_light := OmniLight3D.new()
	front_light.name = "FrontFill"
	front_light.position = Vector3(0.0, 1.2, 2.2)
	front_light.light_color = Color(0.9, 0.93, 1.0, 1.0)
	front_light.light_energy = 12.0
	front_light.omni_range = 10.0
	_stage.add_child(front_light)

	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = 60.0
	_camera.near = 0.05
	_camera.far = 30.0
	_camera.current = true
	_viewport.add_child(_camera)
	await process_frame


## 场景一：石墙 + 命中火花。火花直接实例化 metal_spark.tscn（其 _ready 即发射），
## 与 FxHelper.create_metal_spark 的资产路径完全一致，渲染于本 SubViewport 世界。
func _capture_spark_on_wall() -> bool:
	_clear_stage()
	_add_wall()
	_camera.position = Vector3(0.0, 1.15, 3.4)
	_camera.look_at(Vector3(0.0, 1.0, -0.1), Vector3.UP)

	var spark_scene := load(METAL_SPARK_PATH) as PackedScene
	if spark_scene == null:
		printerr("Failed to load metal spark scene")
		return false
	var spark := spark_scene.instantiate() as Node3D
	spark.position = Vector3(0.0, 1.05, 0.02)  # 墙面前方的命中接触点
	_stage.add_child(spark)
	await _settle(1)
	if spark is GPUParticles3D:
		var gp := spark as GPUParticles3D
		print("FX_IMPACT_SPARK emitting=%s amount=%d lifetime=%.2f one_shot=%s active=%s" % [
			gp.emitting, gp.amount, gp.lifetime, gp.one_shot, not gp.is_queued_for_deletion()
		])

	var ok := true
	var peak_bright := 0
	var decay_bright := 0
	for frame in [2, 6, 12, 24, 40]:
		await _settle(maxi(frame - 1, 0))
		ok = await _capture("metal_spark_wall_%02d.png" % frame, "metal spark frame %d" % frame) and ok
		var bright := _capture_bright_now()
		if frame < 40:
			peak_bright = maxi(peak_bright, bright)
		else:
			decay_bright = maxi(decay_bright, bright)
	print("FX_IMPACT_SPARK peak_bright=%d decay_bright=%d" % [peak_bright, decay_bright])
	if peak_bright < decay_bright + 100:
		printerr("Metal spark burst not visible (peak=%d decay=%d)" % [peak_bright, decay_bright])
		ok = false
	return ok


## 场景二：木箱被击碎 → 木色体素碎屑爆发。
## 碎屑按 FxHelper.create_voxel_chip 相同路径实例化（setup 先行着色再入树）。
## 木箱本体模拟 destroy() 后的状态（隐藏 + 关闭碰撞），碎屑在箱体位置 +0.4m 生成。
func _capture_crate_break() -> bool:
	_clear_stage()
	_add_floor()
	_camera.position = Vector3(0.0, 1.15, 3.4)
	_camera.look_at(Vector3(0.0, 0.45, 0.0), Vector3.UP)

	var crate_scene := load(DUNGEON_CRATE_PATH) as PackedScene
	if crate_scene == null:
		printerr("Failed to load dungeon crate scene")
		return false
	var crate := crate_scene.instantiate() as Node3D
	crate.position = Vector3(0.0, 0.0, 0.0)
	_stage.add_child(crate)
	await _settle(8)  # 等待 VoxelProp rebuild / 烘焙资产加载
	var intact_ok := await _capture("crate_intact.png", "crate intact") and true

	# 模拟 destroy()：隐藏本体并关闭碰撞（真实 destroy 由战斗路径触发，特效走 FxHelper 挂到主世界，
	# 本工具在独立 SubViewport 世界中按同一资产路径直接生成，保证渲染可见）。
	crate.visible = false
	crate.collision_layer = 0
	crate.collision_mask = 0
	_spawn_chip_burst(Vector3(0.0, 0.4, 0.0), WOOD_CHIP_COLOR)

	var ok := intact_ok
	var peak_bright := 0
	var decay_bright := 0
	for frame in [3, 8, 16, 28]:
		await _settle(frame)
		ok = await _capture("crate_break_%02d.png" % frame, "crate break frame %d" % frame) and ok
		var bright := _capture_bright_now()
		if frame <= 8:
			peak_bright = maxi(peak_bright, bright)
		else:
			decay_bright = maxi(decay_bright, bright)
	print("FX_IMPACT_CHIP_COUNT wood_peak_bright=%d decay_bright=%d" % [peak_bright, decay_bright])
	if peak_bright < decay_bright + 60:
		printerr("Wood chip debris not visible in crate break frames (peak=%d decay=%d)" % [peak_bright, decay_bright])
		ok = false
	return ok


## 场景三：石材道具（石棺/石笋）击碎 → 石灰色碎屑，验证 break_chip_color 覆写。
func _capture_stone_chips() -> bool:
	_clear_stage()
	_add_floor()
	_camera.position = Vector3(0.0, 1.15, 3.4)
	_camera.look_at(Vector3(0.0, 0.45, 0.0), Vector3.UP)

	_spawn_chip_burst(Vector3(0.0, 0.4, 0.0), STONE_CHIP_COLOR)
	var ok := true
	var peak_bright := 0
	var decay_bright := 0
	for frame in [3, 8, 16, 28]:
		await _settle(frame)
		ok = await _capture("stone_chips_%02d.png" % frame, "stone chips frame %d" % frame) and ok
		var bright := _capture_bright_now()
		if frame <= 8:
			peak_bright = maxi(peak_bright, bright)
		else:
			decay_bright = maxi(decay_bright, bright)
	print("FX_IMPACT_CHIP_COUNT stone_peak_bright=%d decay_bright=%d" % [peak_bright, decay_bright])
	# 石灰色碎屑与暗背景色差小，改用“爆发期亮像素显著高于衰减后基线”判定可见性。
	if peak_bright < decay_bright + 60:
		printerr("Stone chip debris not visible in stone chip frames (peak=%d decay=%d)" % [peak_bright, decay_bright])
		ok = false
	return ok


## 统计当前帧亮像素（luma > 0.25）。
func _capture_bright_now() -> int:
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return 0
	return _count_bright_pixels(image)


func _spawn_chip_burst(world_pos: Vector3, color: Color) -> void:
	var chip_scene := load(VOXEL_CHIP_PATH) as PackedScene
	if chip_scene == null:
		printerr("Failed to load voxel chip scene")
		return
	var chip := chip_scene.instantiate() as Node3D
	# 与 FxHelper.create_voxel_chip 一致：入树前 setup 着色（入树前不定位），
	# 入树后再按世界坐标校正位置，否则碎屑会生成在世界原点。
	chip.call("setup", world_pos, color)
	_stage.add_child(chip)
	chip.global_position = world_pos
	await _settle(2)
	var chips_node := chip.get_node_or_null("Chips") as GPUParticles3D
	if chips_node != null:
		print("FX_IMPACT_CHIP emitting=%s amount=%d lifetime=%.2f one_shot=%s color=%s" % [
			chips_node.emitting,
			chips_node.amount,
			chips_node.lifetime,
			chips_node.one_shot,
			str(chips_node.process_material.color if chips_node.process_material != null else Color.BLACK),
		])


func _add_wall() -> void:
	var wall := MeshInstance3D.new()
	wall.name = "StoneWall"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.2, 2.6, 0.24)
	wall.mesh = mesh
	wall.position = Vector3(0.0, 1.3, -0.45)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.33, 0.29, 1.0)
	mat.roughness = 0.95
	wall.material_override = mat
	_stage.add_child(wall)


func _add_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "PreviewFloor"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4.0, 0.06, 4.0)
	floor_mesh.mesh = mesh
	floor_mesh.position = Vector3(0.0, -0.03, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.19, 0.15, 0.11, 1.0)
	mat.roughness = 0.96
	floor_mesh.material_override = mat
	_stage.add_child(floor_mesh)


func _clear_stage() -> void:
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()
	await _settle(1)


func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame


func _capture(file_name: String, label: String) -> bool:
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("FX capture is empty: %s" % label)
		return false
	var sampled_colors := _sample_color_count(image)
	var bright_pixels := _count_bright_pixels(image)
	var fg_box := _foreground_box(image)
	print("FX_IMPACT_STATS %s colors=%d bright=%d fg_box=%s" % [label, sampled_colors, bright_pixels, str(fg_box)])
	var output_path := "%s/%s" % [OUT_DIR, file_name]
	var err := image.save_png(output_path)
	if err != OK:
		printerr("Failed to save FX capture %s: %d" % [output_path, err])
		return false
	print("FX_IMPACT_CAPTURE_SAVED %s colors=%d bright=%d" % [output_path, sampled_colors, bright_pixels])
	# 特效应答只要求非空与可保存；可见性由各场景的亮像素峰值对比判定。
	return true


## 统计亮像素（luma > 0.25）数量：金属火花为自发光（很亮），体素碎屑为受光材质（中等亮度）。
func _count_bright_pixels(image: Image) -> int:
	var count := 0
	var step := 2
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var color := image.get_pixel(x, y)
			var luma := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
			if luma > 0.25:
				count += 1
	return count


## 前景（非背景）像素的包围盒，用于判断特效是否出现在画面预期位置。
func _foreground_box(image: Image) -> Rect2i:
	var bg := image.get_pixel(0, 0)
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	var step := 2
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var color := image.get_pixel(x, y)
			var difference := (
				absf(color.r - bg.r) + absf(color.g - bg.g) + absf(color.b - bg.b)
			)
			if difference > 0.08:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)


func _sample_color_count(image: Image) -> int:
	var colors := {}
	var step_x := maxi(image.get_width() / 160, 1)
	var step_y := maxi(image.get_height() / 90, 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [
				roundi(color.r * 255.0),
				roundi(color.g * 255.0),
				roundi(color.b * 255.0),
			]
			colors[key] = true
	return colors.size()
