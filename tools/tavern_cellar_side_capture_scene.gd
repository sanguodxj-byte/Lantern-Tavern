extends Node3D

const TAVERN_SCENE := preload("res://scenes/tavern/tavern.tscn")
const OUTPUT_PATH := "res://reports/tavern_cellar_side_section_current.png"

var _camera: Camera3D
var _frames_forced := 0

func _ready() -> void:
	print("CELLAR_SIDE_CAPTURE_SCENE_READY")
	get_window().size = Vector2i(1600, 1000)
	_prepare_tavern_state()
	var tavern := TAVERN_SCENE.instantiate() as Node3D
	add_child(tavern)
	await get_tree().process_frame

	_apply_capture_materials(tavern)

	var camera := Camera3D.new()
	camera.name = "CellarSideCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.0
	camera.position = Vector3(10.0, -1.2, -12.0)
	add_child(camera)
	camera.look_at(Vector3(-1.0, -1.2, -6.0), Vector3(0.0, 1.0, 0.0))
	_camera = camera
	_camera.make_current()

	var light := DirectionalLight3D.new()
	light.name = "CellarSideFillLight"
	light.light_energy = 1.4
	light.position = Vector3(6.0, 8.0, -10.0)
	add_child(light)
	light.look_at(Vector3(-1.0, -1.5, -6.0), Vector3(0.0, 1.0, 0.0))

	for i in 30:
		await get_tree().process_frame
		if _camera != null:
			_camera.make_current()

	var image := get_viewport().get_texture().get_image()
	var color_count := _sample_color_count(image)
	if color_count < 8:
		printerr("Cellar side capture looks blank; sampled color count: %d" % color_count)
		get_tree().quit(2)
		return

	var err := image.save_png(OUTPUT_PATH)
	if err != OK:
		printerr("Failed to save cellar side capture: %d" % err)
		get_tree().quit(1)
		return

	print("CELLAR_SIDE_CAPTURE_SAVED %s colors=%d" % [OUTPUT_PATH, color_count])
	get_tree().quit(0)


func _process(_delta: float) -> void:
	if _camera != null and _frames_forced < 60:
		_camera.make_current()
		_frames_forced += 1


func _prepare_tavern_state() -> void:
	var tavern_manager := get_tree().root.get_node_or_null("TavernManager")
	if tavern_manager != null:
		tavern_manager.set("tutorial_completed", true)
		tavern_manager.set("has_confirmed_character_name", true)


func _apply_capture_materials(tavern: Node3D) -> void:
	var built := tavern.get_node_or_null("Structure/BuiltStructure")
	if built == null:
		return

	var floor_mat := _capture_mat(Color(0.82, 0.72, 0.50, 1.0))
	var wall_mat := _capture_mat(Color(0.16, 0.12, 0.09, 1.0))
	var cellar_mat := _capture_mat(Color(0.34, 0.25, 0.18, 1.0))
	var stair_mat := _capture_mat(Color(0.72, 0.45, 0.24, 1.0))
	var warehouse_mat := _capture_mat(Color(0.34, 0.56, 0.34, 1.0))
	var brewery_mat := _capture_mat(Color(0.42, 0.58, 0.76, 1.0))
	var guest_entry_mat := _capture_mat(Color(0.72, 0.56, 0.36, 1.0))

	for child in built.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_instance := child as MeshInstance3D
		var node_name := String(mesh_instance.name)
		if node_name == "CellarSouthWall":
			mesh_instance.visible = false
			continue
		if node_name.begins_with("CellarStairStep"):
			mesh_instance.material_override = stair_mat
		elif node_name.begins_with("Cellar"):
			mesh_instance.material_override = cellar_mat
		elif node_name.contains("GuestEntryFloor"):
			mesh_instance.material_override = guest_entry_mat
		elif node_name.contains("BreweryFloor"):
			mesh_instance.material_override = brewery_mat
		elif node_name.contains("WarehouseFloor"):
			mesh_instance.material_override = warehouse_mat
		elif node_name.contains("Wall") or node_name.contains("Lintel"):
			mesh_instance.material_override = wall_mat
		elif node_name.contains("Floor"):
			mesh_instance.material_override = floor_mat


func _capture_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _sample_color_count(image: Image) -> int:
	var colors := {}
	var step_x := maxi(image.get_width() / 80, 1)
	var step_y := maxi(image.get_height() / 50, 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0)]
			colors[key] = true
	return colors.size()
