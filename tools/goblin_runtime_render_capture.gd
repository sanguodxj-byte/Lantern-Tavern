extends SceneTree
## Focused real-3D capture of the production goblin scene with hand equipment.

const RUNTIME_PATH := "res://scenes/characters/enemies/goblin.tscn"
const OUTPUT_DIR := "res://reports/characters_preview"
const IMAGE_SIZE := Vector2i(900, 900)
const WINDUP_PROGRESS := 0.4
const STRIKE_PROGRESS := 0.72
const RECOVER_PROGRESS := 1.0

var _viewport: SubViewport
var _had_error := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Goblin runtime render capture requires a non-headless renderer.")
		quit(4)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	_viewport = SubViewport.new()
	_viewport.size = IMAGE_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	await process_frame

	_add_environment()
	var stage := Node3D.new()
	_viewport.add_child(stage)
	_add_floor(stage)
	_add_lights(stage)

	var packed := load(RUNTIME_PATH) as PackedScene
	if packed == null:
		_fail("Cannot load runtime goblin scene.")
		quit(1)
		return
	var runtime := packed.instantiate() as CharacterBody3D
	runtime.set_script(null)
	runtime.process_mode = Node.PROCESS_MODE_DISABLED
	stage.add_child(runtime)
	await process_frame
	await process_frame

	var equipment := runtime.get_node_or_null("EquipmentComponent")
	var weapon_placeholder := equipment.get("weapon_placeholder") as Node3D if equipment != null else null
	var shield_placeholder := equipment.get("shield_placeholder") as Node3D if equipment != null else null
	if weapon_placeholder == null or shield_placeholder == null:
		_fail("Runtime equipment placeholders did not resolve.")
		quit(1)
		return
	if weapon_placeholder.get_child_count() == 0:
		_fail("Runtime weapon did not mount to Hand.R.")
	if shield_placeholder.get_child_count() == 0:
		_fail("Runtime shield did not mount to Hand.L.")
	if _had_error:
		quit(1)
		return
	var animation_player := runtime.get_node("character/AnimationPlayer") as AnimationPlayer
	var attack := animation_player.get_animation("slash_one_hand")
	var phases := [
		{"name": "windup", "progress": WINDUP_PROGRESS},
		{"name": "strike", "progress": STRIKE_PROGRESS},
		{"name": "recover", "progress": RECOVER_PROGRESS},
	]
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(camera)
	camera.current = true
	var views := [
		{"name": "preview", "direction": Vector3(0.65, 0.35, -1.0).normalized(), "up": Vector3.UP},
		{"name": "front", "direction": Vector3.FORWARD, "up": Vector3.UP},
		{"name": "side", "direction": Vector3.RIGHT, "up": Vector3.UP},
		{"name": "top", "direction": Vector3.UP, "up": Vector3.FORWARD},
	]
	animation_player.play("slash_one_hand")
	for phase in phases:
		animation_player.seek(attack.length * phase["progress"], true)
		animation_player.advance(0.0)
		await process_frame
		var bounds := _global_bounds(runtime)
		if bounds.size.length_squared() <= 0.01:
			_fail("Runtime goblin has no visible mesh bounds at %s." % phase["name"])
			continue
		camera.size = maxf(bounds.size.y * 1.55, 2.4)
		var center := bounds.get_center()
		var distance := maxf(bounds.size.length() * 2.2, 4.0)
		for view in views:
			camera.position = center + view["direction"] * distance
			camera.look_at(center, view["up"])
			for frame in 12:
				await process_frame
			var image := _viewport.get_texture().get_image()
			var output_path := "%s/voxel_goblin_runtime_slash_%s_%s.png" % [OUTPUT_DIR, phase["name"], view["name"]]
			if image.save_png(output_path) != OK:
				_fail("Failed to save %s." % output_path)
			elif _sample_color_count(image) <= 24:
				_fail("Runtime render looks blank: %s." % output_path)
			else:
				print("[GoblinRuntimeCapture] saved %s" % output_path)

	quit(1 if _had_error else 0)


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


func _add_floor(stage: Node3D) -> void:
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4.0, 0.04, 4.0)
	floor.mesh = mesh
	floor.position.y = -0.02
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.13, 0.14)
	material.roughness = 0.95
	floor.material_override = material
	stage.add_child(floor)


func _add_lights(stage: Node3D) -> void:
	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	stage.add_child(key)
	key.look_at_from_position(Vector3(-3.0, 5.0, -4.0), Vector3(0.0, 0.7, 0.0), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.0, 2.2, -2.0)
	fill.light_color = Color(1.0, 0.72, 0.44)
	fill.light_energy = 1.0
	fill.omni_range = 6.0
	stage.add_child(fill)


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
