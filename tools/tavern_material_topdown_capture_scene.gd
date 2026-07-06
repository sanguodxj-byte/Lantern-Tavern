extends Node3D

const TAVERN_SCENE := preload("res://scenes/tavern/tavern.tscn")
const OUTPUT_PATH := "res://reports/tavern_materials_topdown_current.png"

var _camera: Camera3D
var _frames_forced := 0


func _ready() -> void:
	get_window().size = Vector2i(1600, 1100)
	var tavern := TAVERN_SCENE.instantiate() as Node3D
	add_child(tavern)
	await get_tree().process_frame
	_hide_underground_for_topdown(tavern)

	var camera := Camera3D.new()
	camera.name = "MaterialTopDownCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.0
	camera.position = Vector3(3.5, 26.0, -2.7)
	add_child(camera)
	camera.look_at(Vector3(3.5, 0.0, -2.7), Vector3(0.0, 0.0, 1.0))
	_camera = camera
	_camera.make_current()

	var light := DirectionalLight3D.new()
	light.name = "MaterialTopDownFillLight"
	light.light_energy = 1.4
	light.position = Vector3(3.5, 10.0, -2.7)
	add_child(light)
	light.look_at(Vector3(3.5, 0.0, -2.7), Vector3(0.0, 0.0, 1.0))

	for i in 30:
		await get_tree().process_frame
		if _camera != null:
			_camera.make_current()

	var image := get_viewport().get_texture().get_image()
	if _sample_color_count(image) < 24:
		printerr("Material topdown capture looks blank or flat")
		get_tree().quit(2)
		return

	var err := image.save_png(OUTPUT_PATH)
	if err != OK:
		printerr("Failed to save material topdown capture: %d" % err)
		get_tree().quit(1)
		return

	print("TAVERN_MATERIAL_TOPDOWN_CAPTURE_SAVED %s" % OUTPUT_PATH)
	get_tree().quit(0)


func _process(_delta: float) -> void:
	if _camera != null and _frames_forced < 60:
		_camera.make_current()
		_frames_forced += 1


func _hide_underground_for_topdown(tavern: Node3D) -> void:
	var built := tavern.get_node_or_null("Structure/BuiltStructure")
	if built == null:
		return
	for child in built.get_children():
		if String(child.name).begins_with("Cellar"):
			(child as Node3D).visible = false


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
