extends SceneTree
## 体素道具真 3D 材质渲染捕获（单一资产，--asset=<model_id> 必选）。
## 需要非 headless 渲染器；输出 reports/props_preview/<model_id>_render_{preview,front,side,top}.png，
## 与结构投影 <model_id>_{front,side,top}.png 互不覆盖。
## 只读捕获：不写场景、不烘焙、不生成/改写模型资产。

const OUTPUT_DIR := "res://reports/props_preview"
const IMAGE_SIZE := Vector2i(1024, 1024)
const SETTLE_FRAMES := 30
const VIEW_ORDER := ["preview", "front", "side", "top"]
const VIEW_DIRECTIONS := {
	"preview": Vector3(0.55, 0.42, -1.0),
	"front": Vector3(0.0, 0.0, -1.0),
	"side": Vector3(1.0, 0.0, 0.0),
	"top": Vector3(0.0, 1.0, 0.0),
}
const VIEW_UP_VECTORS := {
	"preview": Vector3.UP,
	"front": Vector3.UP,
	"side": Vector3.UP,
	"top": Vector3.FORWARD,
}

const SCENES := {
	"brew_cauldron": "res://scenes/props/decor/brew_cauldron.tscn",
	"barrel": "res://scenes/props/barrel/barrel.tscn",
	"bucket": "res://scenes/props/decor/bucket.tscn",
	"chest": "res://scenes/props/chest/chest.tscn",
	"table": "res://scenes/props/decor/table.tscn",
	"fireplace": "res://scenes/props/decor/fireplace.tscn",
	"torch": "res://scenes/props/torch/torch.tscn",
	"weapon_rack": "res://scenes/props/decor/weapon_rack.tscn",
	"tankard": "res://scenes/props/decor/tankard.tscn",
	"rock_golem": "res://assets/meshes/characters/voxel_rock_golem_80px.glb",
}

var _viewport: SubViewport

func _initialize() -> void:
	print("PROP_RENDER_CAPTURE_START")
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Prop render capture requires a non-headless renderer.")
		quit(4)
		return
	var selected := ""
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--asset="):
			printerr("Prop render capture requires exactly one --asset=<model_id>.")
			quit(1)
			return
		var candidate := arg.trim_prefix("--asset=").strip_edges()
		if candidate.is_empty() or not selected.is_empty():
			printerr("Prop render capture requires exactly one --asset=<model_id>.")
			quit(1)
			return
		selected = candidate
	if not SCENES.has(selected):
		printerr("Unsupported prop render asset: %s" % selected)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	_viewport = SubViewport.new()
	_viewport.name = "PropRenderViewport"
	_viewport.size = IMAGE_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(_viewport)
	await process_frame

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.05, 0.055, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.38, 0.33, 1.0)
	environment.ambient_light_energy = 0.85
	if _viewport.world_3d != null:
		_viewport.world_3d.environment = environment

	var stage := Node3D.new()
	stage.name = "PropStage"
	_viewport.add_child(stage)

	var model: Node = (load(String(SCENES[selected])) as PackedScene).instantiate()
	# 刚体根节点（如可拾取酒桶）在捕获视口中会因重力掉出取景框：先冻结
	if model is RigidBody3D:
		var body := model as RigidBody3D
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	stage.add_child(model)

	var key_light := DirectionalLight3D.new()
	key_light.name = "WarmKeyLight"
	key_light.light_energy = 2.2
	stage.add_child(key_light)
	key_light.look_at_from_position(Vector3(-4.5, 7.0, -6.0), Vector3(0.0, 0.4, 0.0), Vector3.UP)

	var fill_light := OmniLight3D.new()
	fill_light.name = "LowWarmFill"
	fill_light.position = Vector3(3.5, 2.5, -2.5)
	fill_light.light_color = Color(1.0, 0.72, 0.42, 1.0)
	fill_light.light_energy = 1.0
	fill_light.omni_range = 8.0
	stage.add_child(fill_light)

	var camera := Camera3D.new()
	camera.name = "CaptureCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(camera)
	camera.current = true

	var bounds := _global_bounds(model)
	if bounds.size.length_squared() <= 0.0001:
		printerr("%s has no mesh bounds." % selected)
		quit(1)
		return

	var ok := await _capture_views(camera, bounds, selected)
	quit(0 if ok else 2)

func _capture_views(camera: Camera3D, bounds: AABB, model_id: String) -> bool:
	for view_name in VIEW_ORDER:
		_frame_camera(camera, bounds, VIEW_DIRECTIONS[view_name], VIEW_UP_VECTORS[view_name])
		for _frame in SETTLE_FRAMES:
			await process_frame
		var image := _viewport.get_texture().get_image()
		var label := "%s %s" % [model_id, view_name]
		if not _validate(image, label):
			return false
		var output_path := "%s/%s_render_%s.png" % [OUTPUT_DIR, model_id, view_name]
		var err := image.save_png(output_path)
		if err != OK:
			printerr("Failed to save %s: %d" % [output_path, err])
			return false
		print("PROP_RENDER_SAVED %s" % output_path)
	return true

func _frame_camera(camera: Camera3D, bounds: AABB, view_direction: Vector3, view_up: Vector3) -> void:
	var direction := view_direction.normalized()
	var up_vector := view_up.normalized()
	var right_vector := up_vector.cross(direction).normalized()
	var screen_up_vector := direction.cross(right_vector).normalized()
	var center := bounds.get_center()
	var horizontal_span := 0.0
	var vertical_span := 0.0
	for corner_index in range(8):
		var corner := bounds.position + Vector3(
			bounds.size.x if (corner_index & 1) != 0 else 0.0,
			bounds.size.y if (corner_index & 2) != 0 else 0.0,
			bounds.size.z if (corner_index & 4) != 0 else 0.0
		)
		var offset := corner - center
		horizontal_span = maxf(horizontal_span, absf(offset.dot(right_vector)) * 2.0)
		vertical_span = maxf(vertical_span, absf(offset.dot(screen_up_vector)) * 2.0)
	var aspect := float(IMAGE_SIZE.x) / float(IMAGE_SIZE.y)
	var framing_margin := 1.15
	camera.size = maxf(vertical_span * framing_margin, horizontal_span * framing_margin / aspect)
	camera.size = maxf(camera.size, 1.0)
	var distance := maxf(bounds.size.length() * 2.4, 4.0)
	camera.near = 0.05
	camera.far = distance + bounds.size.length() * 2.0 + 4.0
	camera.position = center + direction * distance
	camera.look_at(center, up_vector)

func _validate(image: Image, label: String) -> bool:
	if image == null or image.is_empty():
		printerr("Empty render for %s" % label)
		return false
	var colors := {}
	var foreground := 0
	var background := image.get_pixel(0, 0)
	var step_x := maxi(image.get_width() / 120, 1)
	var step_y := maxi(image.get_height() / 80, 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0)]
			colors[key] = true
			var difference := absf(color.r - background.r) + absf(color.g - background.g) + absf(color.b - background.b)
			if difference > 0.06:
				foreground += 1
	if colors.size() < 30:
		printerr("Render looks blank or flat for %s; colors: %d" % [label, colors.size()])
		return false
	if foreground < 80:
		printerr("Too little visible model area for %s; samples: %d" % [label, foreground])
		return false
	return true

func _global_bounds(root_node: Node) -> AABB:
	var initialized := false
	var min_point := Vector3.ZERO
	var max_point := Vector3.ZERO
	for mesh_instance in _collect_meshes(root_node):
		if mesh_instance.mesh == null:
			continue
		var local_bounds := mesh_instance.get_aabb()
		for corner in range(8):
			var local_point := local_bounds.position + Vector3(
				local_bounds.size.x if (corner & 1) != 0 else 0.0,
				local_bounds.size.y if (corner & 2) != 0 else 0.0,
				local_bounds.size.z if (corner & 4) != 0 else 0.0
			)
			var world_point := mesh_instance.global_transform * local_point
			if not initialized:
				min_point = world_point
				max_point = world_point
				initialized = true
			else:
				min_point = Vector3(minf(min_point.x, world_point.x), minf(min_point.y, world_point.y), minf(min_point.z, world_point.z))
				max_point = Vector3(maxf(max_point.x, world_point.x), maxf(max_point.y, world_point.y), maxf(max_point.z, world_point.z))
	if not initialized:
		return AABB()
	return AABB(min_point, max_point - min_point)

func _collect_meshes(root_node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root_node is MeshInstance3D:
		meshes.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		meshes.append_array(_collect_meshes(child))
	return meshes
