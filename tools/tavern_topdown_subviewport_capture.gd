extends SceneTree

const TAVERN_STRUCTURE_SCRIPT := preload("res://scenes/tavern/tavern_structure.gd")
const OUTPUT_PATH := "res://reports/tavern_topdown_test_current.png"

var _viewport: SubViewport


func _initialize() -> void:
	_capture()


func _capture() -> void:
	print("TAVERN_TOPDOWN_SUBVIEWPORT_CAPTURE_START")
	_viewport = SubViewport.new()
	_viewport.name = "TavernTopDownViewport"
	_viewport.size = Vector2i(1600, 1100)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(_viewport)

	var structure := Node3D.new()
	structure.name = "Structure"
	structure.set_script(TAVERN_STRUCTURE_SCRIPT)
	_viewport.add_child(structure)
	await process_frame

	_hide_underground_for_topdown(structure)
	_apply_capture_materials(structure)

	var camera := Camera3D.new()
	camera.name = "TopDownCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.0
	camera.position = Vector3(3.5, 26.0, -2.7)
	_viewport.add_child(camera)
	camera.look_at(Vector3(3.5, 0.0, -2.7), Vector3(0.0, 0.0, 1.0))
	camera.current = true

	var light := DirectionalLight3D.new()
	light.name = "TopDownLight"
	light.light_energy = 1.4
	light.position = Vector3(3.5, 18.0, -2.7)
	_viewport.add_child(light)
	light.look_at(Vector3(3.5, 0.0, -2.7), Vector3(0.0, 0.0, 1.0))

	for i in 20:
		await process_frame

	var image := _viewport.get_texture().get_image()
	var color_count := _sample_color_count(image)
	if color_count < 4:
		printerr("Topdown capture looks blank; sampled color count: %d" % color_count)
		quit(2)
		return

	var err := image.save_png(OUTPUT_PATH)
	if err != OK:
		printerr("Failed to save topdown capture: %d" % err)
		quit(1)
		return

	print("TAVERN_TOPDOWN_SUBVIEWPORT_CAPTURE_SAVED %s colors=%d" % [OUTPUT_PATH, color_count])
	quit(0)


func _apply_capture_materials(structure: Node3D) -> void:
	var built := structure.get_node_or_null("BuiltStructure")
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


func _hide_underground_for_topdown(structure: Node3D) -> void:
	var built := structure.get_node_or_null("BuiltStructure")
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
