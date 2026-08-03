extends SceneTree
## Read-only, exact-asset real-3D capture for accepted creature locomotion.
## Invoke once per model: -- --asset=slime OR -- --asset=spider.

const OUTPUT_DIR := "res://reports/characters_preview"
const IMAGE_SIZE := Vector2i(900, 900)

var _viewport: SubViewport
var _had_error := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var asset := _exact_asset_argument()
	if asset.is_empty():
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		_fail("Creature animation capture requires a non-headless renderer.")
		quit(4)
		return
	var config := _config_for(asset)
	if config.is_empty():
		_fail("Unsupported exact creature asset: %s" % asset)
		quit(2)
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

	var packed := load(config["scene_path"]) as PackedScene
	if packed == null:
		_fail("Cannot load production creature scene: %s" % config["scene_path"])
		quit(1)
		return
	var creature := packed.instantiate() as CharacterBody3D
	creature.set_script(null)
	creature.process_mode = Node.PROCESS_MODE_DISABLED
	stage.add_child(creature)
	await process_frame
	await process_frame

	var player := creature.get_node_or_null("character/AnimationPlayer") as AnimationPlayer
	if player == null or not player.has_animation("run"):
		_fail("%s production rig has no run animation." % asset)
		quit(1)
		return
	var run := player.get_animation("run")
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(camera)
	camera.current = true
	var views := [
		{"name": "front", "direction": Vector3.FORWARD, "up": Vector3.UP},
		{"name": "top", "direction": Vector3.UP, "up": Vector3.FORWARD},
	]

	player.play("run")
	for phase in config["phases"]:
		player.seek(run.length * float(phase["progress"]), true)
		player.advance(0.0)
		await process_frame
		var bounds := _global_bounds(creature)
		if bounds.size.length_squared() <= 0.01:
			_fail("%s has no visible bounds at phase %s." % [asset, phase["name"]])
			continue
		var center := bounds.get_center()
		camera.size = maxf(maxf(bounds.size.x, bounds.size.z) * 1.45, bounds.size.y * 1.35)
		var distance := maxf(bounds.size.length() * 2.4, 4.0)
		for view in views:
			camera.position = center + view["direction"] * distance
			camera.look_at(center, view["up"])
			for _frame in 12:
				await process_frame
			var image := _viewport.get_texture().get_image()
			var output_path := "%s/voxel_%s_motion_%s_%s.png" % [
				OUTPUT_DIR, asset, phase["name"], view["name"],
			]
			if image.save_png(output_path) != OK:
				_fail("Failed to save %s." % output_path)
			elif _sample_color_count(image) <= 24:
				_fail("Creature motion render looks blank: %s." % output_path)
			else:
				print("[CreatureAnimationCapture] saved %s" % output_path)

	quit(1 if _had_error else 0)


func _exact_asset_argument() -> String:
	var matches: Array[String] = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--asset="):
			matches.append(argument.trim_prefix("--asset=").strip_edges())
	if matches.size() != 1:
		_fail("Exactly one --asset=<slime|spider> selector is required.")
		return ""
	var asset := matches[0]
	if asset.contains(",") or asset.contains("*") or asset == "all":
		_fail("Multiple, wildcard, and all asset selectors are forbidden.")
		return ""
	return asset


func _config_for(asset: String) -> Dictionary:
	if asset == "slime":
		return {
			"scene_path": "res://scenes/characters/enemies/slime.tscn",
			"phases": [
				{"name": "takeoff", "progress": 0.13},
				{"name": "apex", "progress": 0.30},
				{"name": "landing", "progress": 0.64},
			],
		}
	if asset == "spider":
		return {
			"scene_path": "res://scenes/characters/enemies/spider.tscn",
			"phases": [
				{"name": "group_a", "progress": 0.02},
				{"name": "contact", "progress": 0.27},
				{"name": "group_b", "progress": 0.52},
			],
		}
	return {}


func _add_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.030, 0.038, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.46, 0.52, 0.60)
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
	mesh.size = Vector3(5.0, 0.04, 5.0)
	floor.mesh = mesh
	floor.position.y = -0.02
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.105, 0.115, 0.13)
	material.roughness = 0.96
	floor.material_override = material
	stage.add_child(floor)


func _add_lights(stage: Node3D) -> void:
	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	stage.add_child(key)
	key.look_at_from_position(Vector3(-3.0, 5.0, -4.0), Vector3(0.0, 0.7, 0.0), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.3, 2.4, -2.0)
	fill.light_color = Color(1.0, 0.72, 0.44)
	fill.light_energy = 1.0
	fill.omni_range = 7.0
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
