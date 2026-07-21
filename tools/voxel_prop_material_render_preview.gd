extends SceneTree

const OUTPUT_DIR := "res://reports/props_preview"
const OUTPUT_PATH := "res://reports/props_preview/tavern_decor_material_contact_sheet.png"
const CHARACTER_OUTPUT_DIR := "res://reports/characters_preview"
const CHARACTER_RENDER_OUTPUT_PATTERN := "res://reports/characters_preview/voxel_%s_render_%s.png"
const CHARACTER_COMPATIBILITY_OUTPUT_PATTERN := "res://reports/characters_preview/voxel_%s_godot_material.png"
const IMAGE_SIZE := Vector2i(1600, 1000)
const CHARACTER_VIEW_SETTLE_FRAMES := 35
const CHARACTER_VIEW_ORDER := ["preview", "front", "side", "top"]
# Directions point from the model toward the camera in Godot coordinates.
# Front is viewed from -Z, side from +X, and top from +Y with -Z kept image-up.
const CHARACTER_VIEW_DIRECTIONS := {
	"preview": Vector3(0.55, 0.42, -1.0),
	"front": Vector3(0.0, 0.0, -1.0),
	"side": Vector3(1.0, 0.0, 0.0),
	"top": Vector3(0.0, 1.0, 0.0),
}
const CHARACTER_VIEW_UP_VECTORS := {
	"preview": Vector3.UP,
	"front": Vector3.UP,
	"side": Vector3.UP,
	"top": Vector3.FORWARD,
}
const CHARACTER_SCENES := {
	"goblin": "res://assets/meshes/characters/voxel_goblin_32px.glb",
	"dragon": "res://assets/meshes/characters/voxel_dragon_256px.glb",
	"rock_golem": "res://assets/meshes/characters/voxel_rock_golem_80px.glb",
	"orc_raider": "res://assets/meshes/characters/voxel_orc_raider_48px.glb",
	"skeleton": "res://assets/meshes/characters/voxel_skeleton_48px.glb",
	"troll": "res://assets/meshes/characters/voxel_troll_64x.glb",
	"player": "res://assets/meshes/characters/voxel_player_54px.glb",
	"minotaur": "res://assets/meshes/characters/voxel_minotaur_72px.glb",
	"slime": "res://assets/meshes/characters/voxel_slime_24px.glb",
	"spider": "res://assets/meshes/characters/voxel_spider_30px.glb",
}
const PREVIEW_SCENES := [
	{
		"path": "res://scenes/props/decor/tankard.tscn",
		"position": Vector3(-3.9, 0.0, -1.1),
		"scale": 3.3,
		"rotation_y": 0.0,
	},
	{
		"path": "res://scenes/props/decor/goblet.tscn",
		"position": Vector3(-1.35, 0.0, -1.1),
		"scale": 2.65,
		"rotation_y": 0.0,
	},
	{
		"path": "res://scenes/props/decor/bottle_set.tscn",
		"position": Vector3(1.65, 0.0, -1.1),
		"scale": 2.2,
		"rotation_y": 0.0,
	},
	{
		"path": "res://scenes/props/decor/wall_notice.tscn",
		"position": Vector3(-3.9, 0.0, 1.25),
		"scale": 1.55,
		"rotation_y": 0.0,
	},
	{
		"path": "res://scenes/props/decor/chandelier.tscn",
		"position": Vector3(-0.45, 2.2, 1.35),
		"scale": 1.75,
		"rotation_y": 0.0,
	},
	{
		"path": "res://scenes/props/decor/wall_lantern.tscn",
		"position": Vector3(3.35, 0.0, 1.25),
		"scale": 1.8,
		"rotation_y": 0.0,
	},
]

var _viewport: SubViewport
var _had_error := false


func _initialize() -> void:
	print("VOXEL_PROP_MATERIAL_PREVIEW_START")
	call_deferred("_run")


func _run() -> void:
	print("VOXEL_PROP_MATERIAL_PREVIEW_BUILD")
	var requested_asset := _requested_character_asset(OS.get_cmdline_user_args())
	if _had_error:
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		printerr("Voxel prop material render preview requires a non-headless renderer.")
		quit(4)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CHARACTER_OUTPUT_DIR))

	_viewport = SubViewport.new()
	_viewport.name = "VoxelPropMaterialPreviewViewport"
	_viewport.size = IMAGE_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(_viewport)
	await process_frame

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.052, 0.047, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.31, 0.25, 1.0)
	environment.ambient_light_energy = 0.72
	if _viewport.world_3d != null:
		_viewport.world_3d.environment = environment

	var stage := Node3D.new()
	stage.name = "PreviewStage"
	_viewport.add_child(stage)

	var character_preview: Node3D = null
	if not requested_asset.is_empty():
		character_preview = _add_character_preview(stage, requested_asset)
	else:
		_add_floor(stage)
		for spec in PREVIEW_SCENES:
			_add_preview_prop(stage, spec)

	var key_light := DirectionalLight3D.new()
	key_light.name = "WarmKeyLight"
	key_light.light_energy = 2.0
	stage.add_child(key_light)
	key_light.look_at_from_position(Vector3(-3.8, 6.5, -5.6), Vector3(0.0, 0.8, 0.0), Vector3.UP)

	var fill_light := OmniLight3D.new()
	fill_light.name = "LowWarmFill"
	fill_light.position = Vector3(3.0, 2.5, -2.2)
	fill_light.light_color = Color(1.0, 0.72, 0.42, 1.0)
	fill_light.light_energy = 0.9
	fill_light.omni_range = 7.0
	stage.add_child(fill_light)

	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(camera)
	camera.current = true

	if _had_error:
		quit(1)
		return

	if not requested_asset.is_empty():
		if character_preview == null:
			quit(1)
			return
		var bounds := _global_bounds(character_preview)
		if bounds.size.length_squared() <= 0.0001:
			_fail("Character material preview has no mesh bounds: %s" % requested_asset)
			quit(1)
			return
		var capture_ok := await _capture_character_views(camera, bounds, requested_asset)
		quit(0 if capture_ok else 2)
		return

	camera.size = 5.6
	camera.position = Vector3(0.0, 2.9, -7.2)
	camera.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)
	for _frame in CHARACTER_VIEW_SETTLE_FRAMES:
		await process_frame
	var prop_image := _viewport.get_texture().get_image()
	var prop_colors := _validate_rendered_image(prop_image, "prop contact sheet")
	if prop_colors < 0 or not _save_rendered_image(prop_image, OUTPUT_PATH, "prop contact sheet"):
		quit(2)
		return
	print("VOXEL_PROP_MATERIAL_PREVIEW_SAVED %s colors=%d" % [OUTPUT_PATH, prop_colors])
	quit(0)


func _capture_character_views(camera: Camera3D, bounds: AABB, model_id: String) -> bool:
	# The model is instantiated once; this loop only repositions one camera around it.
	for view_name in CHARACTER_VIEW_ORDER:
		var direction: Vector3 = CHARACTER_VIEW_DIRECTIONS[view_name]
		var up_vector: Vector3 = CHARACTER_VIEW_UP_VECTORS[view_name]
		_frame_character_camera(camera, bounds, direction, up_vector)
		for _frame in CHARACTER_VIEW_SETTLE_FRAMES:
			await process_frame

		var image := _viewport.get_texture().get_image()
		var label := "%s %s" % [model_id, view_name]
		var sampled_colors := _validate_rendered_image(image, label, 12, true)
		if sampled_colors < 0:
			return false

		var output_path := CHARACTER_RENDER_OUTPUT_PATTERN % [model_id, view_name]
		if not _save_rendered_image(image, output_path, label):
			return false
		print("VOXEL_CHARACTER_RENDER_SAVED %s colors=%d" % [output_path, sampled_colors])

		if view_name == "preview":
			var compatibility_path := CHARACTER_COMPATIBILITY_OUTPUT_PATTERN % model_id
			if not _save_rendered_image(image, compatibility_path, "%s compatibility preview" % model_id):
				return false
			print("VOXEL_CHARACTER_RENDER_SAVED %s colors=%d" % [compatibility_path, sampled_colors])
	return true


func _frame_character_camera(
	camera: Camera3D,
	bounds: AABB,
	view_direction: Vector3,
	view_up: Vector3
) -> void:
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
	var framing_margin := 1.18
	camera.size = maxf(vertical_span * framing_margin, horizontal_span * framing_margin / aspect)
	camera.size = maxf(camera.size, 0.75)
	var distance := maxf(bounds.size.length() * 2.4, 4.0)
	camera.near = 0.05
	camera.far = distance + bounds.size.length() * 2.0 + 4.0
	camera.position = center + direction * distance
	camera.look_at(center, up_vector)


func _validate_rendered_image(
	image: Image,
	label: String,
	minimum_colors: int = 48,
	require_foreground: bool = false
) -> int:
	if image == null or image.is_empty():
		printerr("Material preview is empty: %s" % label)
		return -1
	if image.get_width() != IMAGE_SIZE.x or image.get_height() != IMAGE_SIZE.y:
		printerr(
			"Material preview has wrong dimensions for %s: %dx%d" % [
				label, image.get_width(), image.get_height()
			]
		)
		return -1
	var sampled_colors := _sample_color_count(image)
	if sampled_colors < minimum_colors:
		printerr(
			"Material preview looks blank or flat for %s; sampled color count: %d" % [
				label, sampled_colors
			]
		)
		return -1
	if require_foreground:
		var foreground_samples := _sample_foreground_count(image)
		if foreground_samples < 80:
			printerr(
				"Material preview has too little visible model area for %s; samples: %d" % [
					label, foreground_samples
				]
			)
			return -1
	return sampled_colors


func _save_rendered_image(image: Image, output_path: String, label: String) -> bool:
	var err := image.save_png(output_path)
	if err != OK:
		printerr("Failed to save material preview for %s: %d" % [label, err])
		return false
	return true


func _add_preview_prop(stage: Node3D, spec: Dictionary) -> void:
	var packed := load(String(spec["path"])) as PackedScene
	if packed == null:
		_fail("Missing preview scene: %s" % spec["path"])
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		_fail("Preview scene root is not Node3D: %s" % spec["path"])
		return
	inst.name = String(spec["path"]).get_file().get_basename()
	inst.position = spec["position"]
	var uniform_scale := float(spec["scale"])
	inst.scale = Vector3(uniform_scale, uniform_scale, uniform_scale)
	inst.rotation.y = float(spec["rotation_y"])
	stage.add_child(inst)


func _requested_character_asset(user_args: PackedStringArray) -> String:
	var selected := ""
	for arg in user_args:
		if not arg.begins_with("--asset="):
			_fail("Material character preview requires exactly one --asset=<model_id>")
			return ""
		var candidate := arg.trim_prefix("--asset=").strip_edges()
		if candidate.is_empty() or not selected.is_empty():
			_fail("Material character preview requires exactly one --asset=<model_id>")
			return ""
		selected = candidate
	if not selected.is_empty() and not CHARACTER_SCENES.has(selected):
		_fail("Unsupported character material preview asset: %s" % selected)
		return ""
	return selected


func _add_character_preview(stage: Node3D, model_id: String) -> Node3D:
	var scene_path := String(CHARACTER_SCENES.get(model_id, ""))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("Missing character material preview asset: %s" % scene_path)
		return null
	var character := packed.instantiate() as Node3D
	if character == null:
		_fail("Character material preview root is not Node3D: %s" % model_id)
		return null
	character.name = "GodotMaterialPreview_%s" % model_id
	stage.add_child(character)
	return character


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
				min_point = Vector3(
					minf(min_point.x, world_point.x),
					minf(min_point.y, world_point.y),
					minf(min_point.z, world_point.z)
				)
				max_point = Vector3(
					maxf(max_point.x, world_point.x),
					maxf(max_point.y, world_point.y),
					maxf(max_point.z, world_point.z)
				)
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


func _add_floor(stage: Node3D) -> void:
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "PreviewFloor"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(9.5, 0.04, 4.8)
	floor_mesh.mesh = mesh
	floor_mesh.position = Vector3(0.0, -0.025, 0.1)
	floor_mesh.material_override = _flat_material(Color(0.19, 0.15, 0.11, 1.0))
	stage.add_child(floor_mesh)


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.96
	return material


func _sample_color_count(image: Image) -> int:
	var colors := {}
	var step_x := maxi(image.get_width() / 120, 1)
	var step_y := maxi(image.get_height() / 80, 1)
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


func _sample_foreground_count(image: Image) -> int:
	var background := image.get_pixel(0, 0)
	var count := 0
	var step_x := maxi(image.get_width() / 120, 1)
	var step_y := maxi(image.get_height() / 80, 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var difference := (
				absf(color.r - background.r)
				+ absf(color.g - background.g)
				+ absf(color.b - background.b)
			)
			if difference > 0.06:
				count += 1
	return count


func _fail(message: String) -> void:
	_had_error = true
	push_error(message)
