extends SceneTree

const OUTPUT_PATH := "res://reports/dungeon_hazards_preview/dungeon_hazards_real3d.png"
const HAZARD_SPECS := [
	{"name": "尖刺", "path": "res://scenes/traps/spikes_trap.tscn", "type": "spikes"},
	{"name": "酸液", "path": "res://scenes/traps/acid_trap.tscn", "type": "acid"},
	{"name": "火焰喷口", "path": "res://scenes/traps/flame_vent_trap.tscn", "type": "flame_vent"},
]

var _viewport: SubViewport

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Dungeon hazard visual capture requires a real renderer")
		quit(2)
		return
	_viewport = SubViewport.new()
	_viewport.name = "DungeonHazardPreviewViewport"
	_viewport.size = Vector2i(960, 540)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(_viewport)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.03, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.42, 1.0)
	env.ambient_light_energy = 0.65
	environment.environment = env
	_viewport.add_child(environment)

	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(10.0, 0.12, 4.2)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.16, 0.18, 0.21, 1.0)
	floor_material.roughness = 0.9
	floor.material_override = floor_material
	floor.position = Vector3(0, -0.08, 0)
	_viewport.add_child(floor)

	for index in range(HAZARD_SPECS.size()):
		var spec: Dictionary = HAZARD_SPECS[index]
		var instance := load(String(spec["path"])).instantiate() as Node3D
		instance.position = Vector3((index - 1) * 3.0, 0.0, 0.0)
		if String(spec["type"]) == "spikes":
			instance.rotation_degrees.x = 90.0
		elif String(spec["type"]) == "acid":
			instance.rotation = Vector3.ZERO
		_viewport.add_child(instance)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 5.4, 9.2)
	camera.fov = 42.0
	_viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.25, 0), Vector3.UP)
	camera.current = true

	var light := DirectionalLight3D.new()
	light.light_energy = 1.8
	light.light_color = Color(1.0, 0.9, 0.78, 1.0)
	_viewport.add_child(light)
	light.look_at(Vector3(0, 0, 0), Vector3.UP)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 2.5, 3.0)
	fill.light_color = Color(0.45, 0.58, 1.0, 1.0)
	fill.light_energy = 2.0
	fill.omni_range = 12.0
	_viewport.add_child(fill)

	var labels := CanvasLayer.new()
	_viewport.add_child(labels)
	for index in range(HAZARD_SPECS.size()):
		var label := Label.new()
		label.text = String(HAZARD_SPECS[index]["name"])
		label.position = Vector2(245 + index * 235, 475)
		label.add_theme_font_override("font", load("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf"))
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75, 1.0))
		labels.add_child(label)

	for _i in range(24):
		await process_frame
	var image := _viewport.get_texture().get_image()
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("reports/dungeon_hazards_preview")
	var err := image.save_png(OUTPUT_PATH)
	if err != OK:
		printerr("Failed to save dungeon hazard capture: ", err)
		quit(1)
		return
	print("DUNGEON_HAZARD_VISUAL_CAPTURE_SAVED ", OUTPUT_PATH)
	quit(0)
