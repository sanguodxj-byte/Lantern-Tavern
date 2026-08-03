extends Node3D

const OUTPUT_PATH := "res://reports/dungeon_decor_material_preview.png"
const VIEWPORT_SIZE := Vector2i(1280, 720)
const TERRAIN_CFG := preload("res://scenes/expedition/dungeon_terrain_config.gd")
const DECOR_SPECS := [
	{"path": "res://scenes/props/dungeon/decor/floor_candelabrum.tscn", "position": Vector3(-3.0, 0.0, -0.9)},
	{"path": "res://scenes/props/dungeon/decor/wall_candelabrum.tscn", "position": Vector3(-1.0, 0.0, -0.9)},
	{"path": "res://scenes/props/dungeon/decor/iron_bar_grate.tscn", "position": Vector3(1.0, 0.0, -0.9)},
	{"path": "res://scenes/props/dungeon/decor/stalagmite_cluster.tscn", "position": Vector3(3.0, 0.0, -0.9)},
	{"path": "res://scenes/props/dungeon/decor/sarcophagus.tscn", "position": Vector3(-2.5, 0.0, 1.1)},
	{"path": "res://scenes/props/dungeon/decor/wall_chain.tscn", "position": Vector3(0.0, 0.0, 1.1)},
	{"path": "res://scenes/props/dungeon/decor/fungus_patch.tscn", "position": Vector3(2.5, 0.0, 1.1)},
]


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
	for spec in DECOR_SPECS:
		var decor := load(String(spec["path"])) as PackedScene
		if decor == null:
			push_error("[DungeonDecorMaterialCapture] missing decor scene: %s" % spec["path"])
			get_tree().quit(1)
			return
		var instance := decor.instantiate() as Node3D
		viewport.add_child(instance)
		instance.position = spec["position"] as Vector3
	var camera := Camera3D.new()
	camera.position = Vector3(6.4, 4.3, 8.2)
	camera.fov = 46.0
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, 0.2), Vector3.UP)
	camera.make_current()
	for _frame in range(24):
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if image == null or _sampled_color_count(image) < 24:
		push_error("[DungeonDecorMaterialCapture] capture is blank or mostly uniform")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	if image.save_png(OUTPUT_PATH) != OK:
		push_error("[DungeonDecorMaterialCapture] failed to save %s" % OUTPUT_PATH)
		get_tree().quit(1)
		return
	print("[DungeonDecorMaterialCapture] saved %s colors=%d" % [OUTPUT_PATH, _sampled_color_count(image)])
	get_tree().quit(0)


func _add_environment(viewport: SubViewport) -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.03, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.46, 0.50, 0.58)
	environment.ambient_light_energy = 0.45
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
	mesh.size = Vector3(10.0, 0.2, 6.0)
	floor.mesh = mesh
	floor.position.y = -0.1
	floor.material_override = TERRAIN_CFG.make_terrain_mat("BARONY_FLOOR", Vector2.ONE, {
		"world_aligned_uv": true,
		"meters_per_tile": 1.0,
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
			colors[Vector3i(roundi(color.r * 63.0), roundi(color.g * 63.0), roundi(color.b * 63.0))] = true
	return colors.size()
