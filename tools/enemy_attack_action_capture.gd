extends SceneTree
## 敌人攻击动作捕获（单一资产，--asset=<id> 必选；非 headless 渲染器）。
## 按 enemy_attack_profile.gd 的招式档案播放攻击动画，在 起手/命中/收势 三阶段截图。
## 输出 reports/characters_preview/voxel_<id>_attack_{windup,hit,recover}_{front,side}.png。
## 只读捕获：不写场景、不生成/改写模型资产。

const OUTPUT_DIR := "res://reports/characters_preview"
const IMAGE_SIZE := Vector2i(900, 900)
const PROFILE := preload("res://globals/combat/enemy_attack_profile.gd")

const ASSETS := {
	"slime": {"scene": "res://scenes/characters/enemies/slime.tscn", "body": true},
	"spider": {"scene": "res://scenes/characters/enemies/spider.tscn", "body": true},
	"dragon": {"scene": "res://scenes/characters/enemies/dragon.tscn", "body": true},
	"rock_golem": {"scene": "res://scenes/characters/enemies/rock_golem.tscn", "body": true},
	"goblin": {"scene": "res://scenes/characters/enemies/goblin.tscn", "body": false},
}

var _viewport: SubViewport

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Enemy attack capture requires a non-headless renderer.")
		quit(4)
		return
	var selected := ""
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--asset="):
			printerr("Requires exactly one --asset=<id>.")
			quit(1)
			return
		var candidate := arg.trim_prefix("--asset=").strip_edges()
		if candidate.is_empty() or not selected.is_empty():
			printerr("Requires exactly one --asset=<id>.")
			quit(1)
			return
		selected = candidate
	if not ASSETS.has(selected):
		printerr("Unsupported asset: %s" % selected)
		quit(1)
		return
	var spec: Dictionary = ASSETS[selected]
	var enemy_type := String(selected)
	var profile: Dictionary = PROFILE.profile_for_enemy(enemy_type, null, bool(spec.get("body", true)))
	var anim_name := String(profile.get("animation", "claw_swipe"))

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

	var packed := load(String(spec["scene"])) as PackedScene
	if packed == null:
		printerr("Cannot load %s scene." % enemy_type)
		quit(1)
		return
	var creature := packed.instantiate() as CharacterBody3D
	creature.set_script(null)
	creature.process_mode = Node.PROCESS_MODE_DISABLED
	stage.add_child(creature)
	await process_frame
	await process_frame

	var ap := creature.get_node_or_null("character/AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(anim_name):
		printerr("%s rig has no animation %s." % [enemy_type, anim_name])
		quit(1)
		return
	var anim := ap.get_animation(anim_name)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(camera)
	camera.current = true

	ap.play(anim_name)
	var phases := [
		{"name": "windup", "progress": 0.25},
		{"name": "hit", "progress": 0.55},
		{"name": "recover", "progress": 0.88},
	]
	var views := [
		{"name": "front", "direction": Vector3.FORWARD, "up": Vector3.UP},
		{"name": "side", "direction": Vector3.RIGHT, "up": Vector3.UP},
	]
	for phase in phases:
		ap.seek(anim.length * float(phase["progress"]), true)
		ap.advance(0.0)
		await process_frame
		var bounds := _global_bounds(creature)
		if bounds.size.length_squared() <= 0.01:
			printerr("%s no visible bounds at %s." % [enemy_type, phase["name"]])
			continue
		var center := bounds.get_center()
		camera.size = maxf(maxf(bounds.size.x, bounds.size.z) * 1.5, bounds.size.y * 1.4)
		var distance := maxf(bounds.size.length() * 2.4, 4.0)
		for view in views:
			camera.position = center + view["direction"] * distance
			camera.look_at(center, view["up"])
			for _frame in 10:
				await process_frame
			var image := _viewport.get_texture().get_image()
			var output_path := "%s/voxel_%s_attack_%s_%s.png" % [OUTPUT_DIR, enemy_type, phase["name"], view["name"]]
			if image.save_png(output_path) != OK:
				printerr("Failed to save %s." % output_path)
			elif _sample_color_count(image) <= 24:
				printerr("Attack render looks blank: %s." % output_path)
			else:
				print("[EnemyAttackCapture] saved %s" % output_path)
	quit(1 if _had_error else 0)

var _had_error := false

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

func _add_floor(stage: Node3D) -> void:
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "PreviewFloor"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(7.0, 0.04, 5.0)
	floor_mesh.mesh = mesh
	floor_mesh.position = Vector3(0.0, -0.03, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.15, 0.14, 1.0)
	mat.roughness = 0.95
	floor_mesh.material_override = mat
	stage.add_child(floor_mesh)

func _add_lights(stage: Node3D) -> void:
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	stage.add_child(key)
	key.look_at_from_position(Vector3(-4.0, 5.5, -5.0), Vector3(0.0, 0.8, 0.0), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(3.0, 2.5, -2.0)
	fill.light_energy = 0.7
	fill.omni_range = 6.0
	stage.add_child(fill)

func _global_bounds(root_node: Node) -> AABB:
	var initialized := false
	var min_point := Vector3.ZERO
	var max_point := Vector3.ZERO
	for mesh_instance in _collect_meshes(root_node):
		if mesh_instance.mesh == null:
			continue
		var local_bounds := mesh_instance.get_aabb()
		for corner in range(8):
			var local_point := local_bounds.position + Vector3(
				local_bounds.size.x if (corner & 1) != 0 else 0.0,
				local_bounds.size.y if (corner & 2) != 0 else 0.0,
				local_bounds.size.z if (corner & 4) != 0 else 0.0
			)
			var world_point := mesh_instance.global_transform * local_point
			if not initialized:
				min_point = world_point
				max_point = world_point
				initialized = true
			else:
				min_point = Vector3(minf(min_point.x, world_point.x), minf(min_point.y, world_point.y), minf(min_point.z, world_point.z))
				max_point = Vector3(maxf(max_point.x, world_point.x), maxf(max_point.y, world_point.y), maxf(max_point.z, world_point.z))
	if not initialized:
		return AABB()
	return AABB(min_point, max_point - min_point)

func _collect_meshes(root_node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root_node is MeshInstance3D:
		meshes.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		meshes.append_array(_collect_meshes(child))
	return meshes

func _sample_color_count(image: Image) -> int:
	var colors := {}
	var step_x := maxi(image.get_width() / 120, 1)
	var step_y := maxi(image.get_height() / 80, 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0)]
			colors[key] = true
	return colors.size()
