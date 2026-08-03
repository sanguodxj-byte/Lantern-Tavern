extends SceneTree
## Real 3D multi-view capture for one exact humanoid and one exact action.

const OUTPUT_DIR := "res://reports/characters_preview"
const IMAGE_SIZE := Vector2i(900, 900)
const RIG_SCENES := {
	"goblin": "res://assets/meshes/characters/voxel_goblin_32px_rig.glb",
	"orc_raider": "res://assets/meshes/characters/voxel_orc_raider_48px_rig.glb",
	"skeleton": "res://assets/meshes/characters/voxel_skeleton_48px_rig.glb",
	"troll": "res://assets/meshes/characters/voxel_troll_64x_rig.glb",
	"minotaur": "res://assets/meshes/characters/voxel_minotaur_72px_rig.glb",
	"drow_blade": "res://assets/meshes/characters/voxel_drow_blade_48px_rig.glb",
}
const ALLOWED_ACTIONS := [
	"idle", "run", "slash", "block", "hurt", "stunned", "death", "kick",
	"lift", "pickup", "throw_weapon", "throw_furniture", "hold_weapon",
	"slash_one_hand", "slash_heavy", "slash_dagger", "thrust_spear",
	"bash_shield", "claw_swipe",
]

var _viewport: SubViewport
var _had_error := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Humanoid animation capture requires a non-headless renderer.")
		await _finish(4)
		return
	var selection := _parse_selection(OS.get_cmdline_user_args())
	var asset_id := String(selection.get("asset", ""))
	var action_name := String(selection.get("action", ""))
	if not RIG_SCENES.has(asset_id) or not ALLOWED_ACTIONS.has(action_name):
		_fail("Use one exact --asset=<humanoid_id> and --action=<action_name>.")
		await _finish(2)
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

	# Capture the authored rig directly. Runtime enemy scenes add physics bones,
	# equipment and gameplay services that are unrelated to animation review.
	var packed := load(String(RIG_SCENES[asset_id])) as PackedScene
	if packed == null:
		_fail("Cannot load rig scene for %s." % asset_id)
		await _finish(1)
		return
	var runtime := packed.instantiate() as Node3D
	if runtime == null:
		_fail("Rig scene root is not Node3D: %s." % asset_id)
		await _finish(1)
		return
	runtime.process_mode = Node.PROCESS_MODE_DISABLED
	stage.add_child(runtime)
	await process_frame
	await process_frame

	var animation_player := runtime.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null or not animation_player.has_animation(action_name):
		_fail("%s missing animation %s." % [asset_id, action_name])
		await _finish(1)
		return
	var animation := animation_player.get_animation(action_name)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(camera)
	camera.current = true
	var views := [
		{"name": "front", "direction": Vector3.FORWARD, "up": Vector3.UP},
		{"name": "side", "direction": Vector3.RIGHT, "up": Vector3.UP},
		{"name": "top", "direction": Vector3.UP, "up": Vector3.FORWARD},
	]
	animation_player.play(action_name)
	for phase in _phases_for(action_name):
		animation_player.seek(animation.length * float(phase["progress"]), true)
		animation_player.advance(0.0)
		await process_frame
		var bounds := _global_bounds(runtime)
		if bounds.size.length_squared() <= 0.01:
			_fail("%s %s has no visible bounds." % [asset_id, phase["name"]])
			continue
		camera.size = maxf(bounds.size.y * 1.55, 2.4)
		var center := bounds.get_center()
		var distance := maxf(bounds.size.length() * 2.2, 4.0)
		for view in views:
			camera.position = center + view["direction"] * distance
			camera.look_at(center, view["up"])
			for frame in 10:
				await process_frame
			var image := _viewport.get_texture().get_image()
			var output_path := "%s/voxel_%s_motion_%s_%s_%s.png" % [
				OUTPUT_DIR, asset_id, action_name, phase["name"], view["name"],
			]
			if image.save_png(output_path) != OK:
				_fail("Failed to save %s." % output_path)
			elif _sample_color_count(image) <= 24:
				_fail("Capture looks blank: %s." % output_path)
			else:
				print("[HumanoidMotionCapture] saved %s" % output_path)
	await _finish(1 if _had_error else 0)


func _finish(exit_code: int) -> void:
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _viewport.get_parent() != null:
			_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
		_viewport = null
	# Let RenderingServer retire viewport RIDs before the SceneTree exits.
	await process_frame
	await process_frame
	quit(exit_code)


func _parse_selection(args: PackedStringArray) -> Dictionary:
	var result := {"asset": "", "action": ""}
	for argument in args:
		if argument.begins_with("--asset="):
			result["asset"] = argument.trim_prefix("--asset=")
		elif argument.begins_with("--action="):
			result["action"] = argument.trim_prefix("--action=")
	for value in result.values():
		var text := String(value)
		if text.contains(",") or text.contains("*") or text == "all":
			return {"asset": "", "action": ""}
	return result


func _phases_for(action_name: String) -> Array[Dictionary]:
	if action_name == "idle":
		return [{"name": "still", "progress": 0.0}]
	if action_name == "run":
		return [
			{"name": "contact_r", "progress": 0.0},
			{"name": "passing_r", "progress": 0.25},
			{"name": "contact_l", "progress": 0.50},
			{"name": "passing_l", "progress": 0.75},
		]
	return [
		{"name": "windup", "progress": 0.32},
		{"name": "action", "progress": 0.62},
		{"name": "recover", "progress": 1.0},
	]


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
		if not mesh_instance.is_inside_tree() or mesh_instance.mesh == null:
			continue
		var mesh_bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = mesh_bounds if not initialized else bounds.merge(mesh_bounds)
		initialized = true
	return bounds


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
	key.light_energy = 1.7
	stage.add_child(key)
	key.look_at_from_position(Vector3(-3.0, 5.0, -4.0), Vector3(0.0, 0.9, 0.0), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.0, 2.5, -2.0)
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
