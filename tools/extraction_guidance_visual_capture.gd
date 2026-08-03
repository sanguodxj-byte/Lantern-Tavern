extends Node3D

const OUTPUT_PATH := "res://reports/extraction_guidance_preview.png"
const VIEWPORT_SIZE := Vector2i(1280, 720)
const TERRAIN_CFG := preload("res://scenes/expedition/dungeon_terrain_config.gd")


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport)
	_add_environment(viewport)
	_add_floor(viewport)

	var portal := load("res://scenes/expedition/extraction_portal.tscn").instantiate() as ExtractionPortal
	viewport.add_child(portal)
	portal._set_visual_progress(0.64)

	var camera := Camera3D.new()
	camera.position = Vector3(3.2, 2.25, 4.1)
	camera.fov = 52.0
	camera.near = 0.05
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
	camera.make_current()

	var hud := load("res://scenes/ui/expedition_hud.tscn").instantiate() as ExpeditionHUD
	viewport.add_child(hud)
	hud.begin_extraction(1.5)
	hud.update_extraction_progress(0.64, 0.5)

	for _frame in range(24):
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if image == null or _sampled_color_count(image) < 24:
		push_error("[ExtractionGuidanceCapture] capture is blank or mostly uniform")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("[ExtractionGuidanceCapture] failed to save image: %d" % error)
		get_tree().quit(1)
		return
	print("[ExtractionGuidanceCapture] saved %s colors=%d" % [OUTPUT_PATH, _sampled_color_count(image)])
	get_tree().quit(0)


func _add_environment(viewport: SubViewport) -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.03, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.46, 0.5, 0.58)
	environment.ambient_light_energy = 0.42
	world_environment.environment = environment
	viewport.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(0.72, 0.78, 0.92)
	key_light.light_energy = 0.8
	key_light.light_specular = 0.0
	key_light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	viewport.add_child(key_light)


func _add_floor(viewport: SubViewport) -> void:
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8.0, 0.2, 8.0)
	floor.mesh = mesh
	floor.position.y = -0.1
	floor.material_override = TERRAIN_CFG.make_terrain_mat("BARONY_FLOOR", Vector2.ONE, {
		"world_aligned_uv": true,
		"meters_per_tile": 1.0,
		"albedo_tint": Color(0.88, 0.90, 0.96),
		"roughness": 0.96,
		"voxel_base_fill": 0.10,
	})
	viewport.add_child(floor)


func _sampled_color_count(image: Image) -> int:
	var colors := {}
	var step_x := maxi(image.get_width() / 80, 1)
	var step_y := maxi(image.get_height() / 45, 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var key := Vector3i(roundi(color.r * 63.0), roundi(color.g * 63.0), roundi(color.b * 63.0))
			colors[key] = true
	return colors.size()
