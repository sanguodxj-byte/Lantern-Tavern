extends Node3D

const TAVERN_SCENE := preload("res://scenes/tavern/tavern.tscn")
const OUTPUT_PATH := "res://reports/tavern_topdown_full_scene_current.png"

var _topdown_camera: Camera3D
var _frames_forced := 0

func _ready() -> void:
	print("TOPDOWN_CAPTURE_SCENE_READY")
	get_window().size = Vector2i(1600, 1100)
	_prepare_tavern_state()
	var tavern := TAVERN_SCENE.instantiate() as Node3D
	add_child(tavern)
	await get_tree().process_frame

	_hide_underground_for_topdown(tavern)
	_apply_capture_materials(tavern)

	var camera := Camera3D.new()
	camera.name = "TopDownCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.0
	camera.position = Vector3(3.5, 26.0, -2.7)
	add_child(camera)
	camera.look_at(Vector3(3.5, 0.0, -2.7), Vector3(0.0, 0.0, 1.0))
	_topdown_camera = camera
	_topdown_camera.make_current()

	var light := DirectionalLight3D.new()
	light.name = "TopDownFillLight"
	light.light_energy = 1.2
	light.position = Vector3(3.5, 10.0, -2.7)
	add_child(light)
	light.look_at(Vector3(3.5, 0.0, -2.7), Vector3(0.0, 0.0, 1.0))

	for i in 30:
		await get_tree().process_frame
		if _topdown_camera != null:
			_topdown_camera.make_current()

	var image := get_viewport().get_texture().get_image()
	var color_count := _sample_color_count(image)
	if color_count < 8:
		printerr("Full-scene topdown capture looks blank; sampled color count: %d" % color_count)
		get_tree().quit(2)
		return

	var err := image.save_png(OUTPUT_PATH)
	if err != OK:
		printerr("Failed to save full-scene topdown capture: %d" % err)
		get_tree().quit(1)
		return

	print("TOPDOWN_FULL_SCENE_CAPTURE_SAVED %s colors=%d" % [OUTPUT_PATH, color_count])
	get_tree().quit(0)


func _process(_delta: float) -> void:
	if _topdown_camera != null and _frames_forced < 60:
		_topdown_camera.make_current()
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
	var bar_mat := _capture_mat(Color(0.58, 0.29, 0.10, 1.0))
	var wine_rack_mat := _capture_mat(Color(0.95, 0.82, 0.05, 1.0))
	var warehouse_mat := _capture_mat(Color(0.34, 0.56, 0.34, 1.0))
	var brewery_mat := _capture_mat(Color(0.42, 0.58, 0.76, 1.0))
	var guest_entry_mat := _capture_mat(Color(0.72, 0.56, 0.36, 1.0))
	var back_hall_mat := _capture_mat(Color(0.62, 0.50, 0.34, 1.0))
	var dungeon_entry_mat := _capture_mat(Color(0.48, 0.38, 0.28, 1.0))
	var spare_room_mat := _capture_mat(Color(0.68, 0.62, 0.50, 1.0))
	var pillar_mat := _capture_mat(Color(0.18, 0.18, 0.18, 1.0))
	var corridor_mat := _capture_mat(Color(0.52, 0.44, 0.30, 1.0))

	for child in built.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var node_name := String(mesh_instance.name)
			if node_name.contains("WineRackZone"):
				mesh_instance.material_override = wine_rack_mat
			elif node_name.contains("SpareRoom"):
				mesh_instance.material_override = spare_room_mat
			elif node_name.contains("DungeonEntranceFloor"):
				mesh_instance.material_override = dungeon_entry_mat
			elif node_name.contains("BackHallFloor"):
				mesh_instance.material_override = back_hall_mat
			elif node_name.contains("GuestEntryFloor"):
				mesh_instance.material_override = guest_entry_mat
			elif node_name.contains("BreweryFloor"):
				mesh_instance.material_override = brewery_mat
			elif node_name.contains("WarehouseFloor"):
				mesh_instance.material_override = warehouse_mat
			elif node_name.contains("Floor") or node_name.contains("Branch"):
				mesh_instance.material_override = corridor_mat if node_name.contains("Corridor") or node_name.contains("Branch") else floor_mat
			elif node_name.begins_with("Bar"):
				mesh_instance.material_override = bar_mat
			elif node_name.begins_with("Pillar"):
				mesh_instance.material_override = pillar_mat
			elif node_name.contains("Wall") or node_name.contains("Lintel"):
				mesh_instance.material_override = wall_mat


func _hide_underground_for_topdown(tavern: Node3D) -> void:
	var built := tavern.get_node_or_null("Structure/BuiltStructure")
	if built == null:
		return
	for child in built.get_children():
		if String(child.name).begins_with("Cellar"):
			(child as Node3D).visible = false


func _capture_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _sample_color_count(image: Image) -> int:
	var colors := {}
	var step_x := maxi(image.get_width() / 80, 1)
	var step_y := maxi(image.get_height() / 55, 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0)]
			colors[key] = true
	return colors.size()
