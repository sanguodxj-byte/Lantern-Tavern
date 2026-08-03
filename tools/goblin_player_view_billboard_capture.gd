extends SceneTree

const PLAYER_PATH := "res://scenes/characters/player/player.tscn"
const GOBLIN_PATH := "res://scenes/characters/enemies/goblin.tscn"
const OUTPUT_PATH := "res://reports/characters_preview/goblin_player_view_billboard.png"
const IMAGE_SIZE := Vector2i(1280, 720)

var _viewport: SubViewport
var _failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Player-view billboard capture requires a non-headless renderer.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/characters_preview"))
	_viewport = SubViewport.new()
	_viewport.name = "PlayerViewCaptureViewport"
	_viewport.size = IMAGE_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_add_environment()
	var stage := Node3D.new()
	stage.name = "PlayerViewStage"
	_viewport.add_child(stage)
	_add_floor(stage)
	_add_lights(stage)

	var player_scene := load(PLAYER_PATH) as PackedScene
	var goblin_scene := load(GOBLIN_PATH) as PackedScene
	if player_scene == null or goblin_scene == null:
		_fail("Player or goblin scene failed to load.")
		quit(1)
		return
	var player := player_scene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	stage.add_child(player)
	await process_frame
	var player_body := player.get_node_or_null("character") as Node3D
	if player_body != null:
		player_body.visible = false
	var view_model := player.get_node_or_null("MainCamera/ViewModel") as Node3D
	if view_model != null:
		view_model.visible = false
	var camera := player.get_node_or_null("MainCamera") as Camera3D
	if camera == null:
		_fail("Player scene has no MainCamera.")
		quit(1)
		return
	camera.current = true
	var goblin = goblin_scene.instantiate()
	goblin.process_mode = Node.PROCESS_MODE_DISABLED
	goblin.set_meta("player_ref", player)
	goblin.set_meta("enemy_base_type", "goblin")
	# 放在 LOD 阈值之外，验证远处才切换 authored billboard。
	goblin.position = Vector3(0.0, 0.0, -19.0)
	stage.add_child(goblin)
	await process_frame
	await process_frame
	camera.look_at_from_position(camera.global_position, goblin.global_position + Vector3(0.0, 0.85, 0.0), Vector3.UP)
	for _frame in 12:
		await process_frame

	var imposter := goblin.get_node_or_null("ImposterSprite") as Sprite3D
	if imposter == null or imposter.texture == null or not imposter.visible:
		_fail("Goblin billboard is not visible from the player camera.")
	for mesh in goblin.find_children("*", "MeshInstance3D", true, false):
		if mesh.visible:
			_fail("Goblin source mesh remains visible while billboard is active.")
			break
	var image := _viewport.get_texture().get_image()
	if image == null or _sample_color_count(image) < 32:
		_fail("Player-view capture is blank.")
	elif image.save_png(OUTPUT_PATH) != OK:
		_fail("Failed to save player-view capture.")
	else:
		print("SAVED_PLAYER_VIEW_BILLBOARD: ", OUTPUT_PATH)
	quit(1 if _failed else 0)

func _add_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.03, 0.04, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	environment.ambient_light_energy = 0.8
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

func _add_floor(stage: Node3D) -> void:
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(12.0, 0.04, 12.0)
	floor.mesh = mesh
	floor.position.y = -0.02
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.12, 0.14, 1.0)
	material.roughness = 0.95
	floor.material_override = material
	stage.add_child(floor)

func _add_lights(stage: Node3D) -> void:
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.look_at_from_position(Vector3(-3.0, 5.0, -4.0), Vector3(0.0, 0.7, -2.0), Vector3.UP)
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(1.5, 2.4, -2.0)
	fill.light_color = Color(1.0, 0.72, 0.44)
	fill.light_energy = 1.0
	fill.omni_range = 8.0
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
	_failed = true
	push_error(message)
