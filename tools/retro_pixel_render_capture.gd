extends SceneTree
## One-off capture: retro pixel-art rendering test for a single voxel model.
## Renders the S-tier rock golem in a low-res SubViewport, then compares:
##   1. full-res render (baseline)
##   2. low-res + nearest upscale (pixelated)
##   3. low-res + color quantization + Bayer dither + nearest upscale
## Output: res://reports/retro_pixel_preview/

const MODEL_PATH := "res://assets/meshes/characters/voxel_rock_golem_80px.glb"
const OUTPUT_DIR := "res://reports/retro_pixel_preview"
const FULL_SIZE := Vector2i(960, 960)
const LOW_SIZE := Vector2i(240, 240)  # 1/4 res -> 4x nearest upscale
const COLOR_LEVELS := 8.0

const BAYER_4X4 := [
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0,
]

var _viewport: SubViewport
var _camera: Camera3D
var _had_error := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Retro pixel render capture requires a non-headless renderer.")
		quit(4)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	_viewport = SubViewport.new()
	_viewport.size = FULL_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	root.add_child(_viewport)
	await process_frame

	_add_environment()
	var stage := Node3D.new()
	_viewport.add_child(stage)
	_add_floor(stage)
	_add_lights(stage)

	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("Cannot load model: %s" % MODEL_PATH)
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	stage.add_child(model)
	await process_frame
	await process_frame

	var bounds := _global_bounds(model)
	if bounds.size.length_squared() <= 0.01:
		_fail("Model has no visible mesh bounds.")
		quit(1)
		return

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	_camera.current = true
	var center := bounds.get_center()
	var distance := maxf(bounds.size.length() * 2.2, 4.0)
	_camera.size = maxf(bounds.size.y * 1.45, 2.4)
	_camera.position = center + Vector3(0.65, 0.35, -1.0).normalized() * distance
	_camera.look_at(center, Vector3.UP)

	# --- 1. full-res baseline ---
	var full_image := await _capture()
	_save(full_image, "golem_1_fullres.png")

	# --- 2. low-res render + nearest upscale ---
	_viewport.size = LOW_SIZE
	var low_image := await _capture()
	var pixelated := low_image.duplicate() as Image
	pixelated.resize(FULL_SIZE.x, FULL_SIZE.y, Image.INTERPOLATE_NEAREST)
	_save(pixelated, "golem_2_pixelated.png")

	# --- 3. low-res + palette quantization + Bayer dither + nearest upscale ---
	var dithered := _quantize_dither(low_image)
	dithered.resize(FULL_SIZE.x, FULL_SIZE.y, Image.INTERPOLATE_NEAREST)
	_save(dithered, "golem_3_pixelated_dither.png")

	# --- side-by-side comparison strip ---
	var strip := Image.create(FULL_SIZE.x * 3 + 8, FULL_SIZE.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color.BLACK)
	strip.blit_rect(full_image, Rect2i(Vector2i.ZERO, FULL_SIZE), Vector2i(0, 0))
	strip.blit_rect(pixelated, Rect2i(Vector2i.ZERO, FULL_SIZE), Vector2i(FULL_SIZE.x + 4, 0))
	strip.blit_rect(dithered, Rect2i(Vector2i.ZERO, FULL_SIZE), Vector2i(FULL_SIZE.x * 2 + 8, 0))
	_save(strip, "golem_0_comparison.png")

	quit(1 if _had_error else 0)


func _capture() -> Image:
	for frame in 12:
		await process_frame
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _quantize_dither(source: Image) -> Image:
	var image := source.duplicate() as Image
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var threshold: float = (float(BAYER_4X4[(y % 4) * 4 + (x % 4)]) / 16.0 - 0.5) / COLOR_LEVELS
			image.set_pixel(x, y, Color(
				floorf(clampf(c.r + threshold, 0.0, 1.0) * COLOR_LEVELS) / COLOR_LEVELS,
				floorf(clampf(c.g + threshold, 0.0, 1.0) * COLOR_LEVELS) / COLOR_LEVELS,
				floorf(clampf(c.b + threshold, 0.0, 1.0) * COLOR_LEVELS) / COLOR_LEVELS,
				c.a))
	return image


func _save(image: Image, file_name: String) -> void:
	var output_path := "%s/%s" % [OUTPUT_DIR, file_name]
	if image.save_png(output_path) != OK:
		_fail("Failed to save %s" % output_path)
	elif _sample_color_count(image) <= 8:
		_fail("Render looks blank: %s" % output_path)
	else:
		print("[RetroPixelCapture] saved %s" % output_path)


func _add_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.04, 0.045, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.52, 0.58)
	environment.ambient_light_energy = 0.75
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)


func _add_floor(stage: Node3D) -> void:
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(6.0, 0.04, 6.0)
	floor.mesh = mesh
	floor.position.y = -0.02
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.13, 0.14)
	material.roughness = 0.95
	floor.material_override = material
	stage.add_child(floor)


func _add_lights(stage: Node3D) -> void:
	var key := DirectionalLight3D.new()
	key.light_energy = 0.9
	key.shadow_enabled = true
	key.shadow_blur = 0.0
	stage.add_child(key)
	key.look_at_from_position(Vector3(-3.0, 5.0, -4.0), Vector3(0.0, 0.7, 0.0), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.0, 2.2, -2.0)
	fill.light_color = Color(1.0, 0.72, 0.44)
	fill.light_energy = 0.35
	fill.omni_range = 8.0
	stage.add_child(fill)


func _global_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var initialized := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mesh_bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = mesh_bounds if not initialized else bounds.merge(mesh_bounds)
		initialized = true
	return bounds


func _sample_color_count(image: Image) -> int:
	var colors := {}
	var step_x := maxi(image.get_width() / 100, 1)
	var step_y := maxi(image.get_height() / 100, 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			colors[Color(color.r, color.g, color.b).to_html(false)] = true
	return colors.size()


func _fail(message: String) -> void:
	_had_error = true
	push_error(message)
