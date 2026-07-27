extends Node3D

const DUNGEON_SCENE := preload("res://scenes/expedition/procedural_dungeon.tscn")
const OUTPUT_PATH := "res://reports/dungeon_real_overview.png"
const DEFAULT_SEED := 94021
const IMAGE_SIZE := Vector2i(1600, 1000)

var _dungeon: ProceduralDungeon = null
var _camera: Camera3D = null
var _had_error := false
var _capture_room := Rect2i()

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().size = IMAGE_SIZE
	var seed_value := _get_int_arg("--seed=", DEFAULT_SEED)
	_dungeon = DUNGEON_SCENE.instantiate() as ProceduralDungeon
	if _dungeon == null:
		_fail("无法实例化生产地牢")
		_finish(1)
		return
	_dungeon.generation_seed = seed_value
	_dungeon.spawn_population_enabled = true
	add_child(_dungeon)
	await _wait_frames(72)
	if _dungeon.layout == null or _dungeon.build_result == null:
		_fail("生产地牢未完成生成")
		_finish(1)
		return
	_hide_material_items()
	_hide_ceilings()
	_hide_game_hud()
	_configure_capture_lighting()
	_disable_game_cameras()
	var target := _pick_capture_target()
	var room_span := _pick_capture_span()
	if not _activate_capture_room(target):
		_finish(1)
		return
	await _wait_frames(8)
	_hide_ceilings()
	_force_enemy_visuals()
	_camera = Camera3D.new()
	_camera.name = "DungeonCaptureCamera"
	add_child(_camera)
	_camera.current = true
	_camera.cull_mask = 0xFFFFF
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 58.0
	_camera.near = 0.05
	_camera.far = 180.0
	_camera.global_position = target + Vector3(room_span * 0.72, room_span * 0.62, room_span * 0.86)
	_camera.look_at(target + Vector3(0.0, 0.25, 0.0), Vector3.UP)
	await _wait_frames(18)
	_force_enemy_visuals()
	if not _save_viewport(OUTPUT_PATH):
		_finish(1)
		return
	print("[DungeonRealOverviewCapture] saved=%s seed=%d enemies=%d hazards=%d focus=%d" % [
		OUTPUT_PATH,
		seed_value,
		_count_nodes_with_meta("enemy_type"),
		_count_nodes_with_meta("hazard_anchor"),
		_count_nodes_with_meta("room_focus"),
	])
	_finish(0)

func _activate_capture_room(target: Vector3) -> bool:
	var player := GameState.current_player as Node3D
	if player == null or not is_instance_valid(player):
		_fail("生产地牢没有有效的当前玩家，无法激活截图目标 chunk")
		return false
	player.global_position = target + Vector3(0.0, 0.85, 0.0)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	if _dungeon.streaming_controller == null or not is_instance_valid(_dungeon.streaming_controller):
		_fail("生产地牢没有流送控制器，无法激活截图目标 chunk")
		return false
	_dungeon.streaming_controller.set_player(player)
	_dungeon.streaming_controller.update_streaming(true)
	return true

func _disable_game_cameras() -> void:
	for node in _walk(_dungeon):
		if node is Camera3D:
			(node as Camera3D).current = false

func _hide_game_hud() -> void:
	for node in _walk(_dungeon):
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false

func _configure_capture_lighting() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.018, 0.025)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.52, 0.60)
	environment.ambient_light_energy = 0.72
	world_environment.environment = environment
	add_child(world_environment)
	var fill := DirectionalLight3D.new()
	fill.name = "DungeonCaptureFill"
	fill.light_color = Color(0.74, 0.82, 0.98)
	fill.light_energy = 0.85
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-54.0, 28.0, 0.0)
	add_child(fill)

func _hide_material_items() -> void:
	for node in _walk(_dungeon):
		if not node.has_meta("item_tag") or String(node.get_meta("item_tag")) != "material":
			continue
		if node is Node3D:
			(node as Node3D).visible = false

func _force_enemy_visuals() -> void:
	var player := GameState.current_player as Node3D
	if player != null and is_instance_valid(player):
		var player_model := player.get_node_or_null("character") as Node3D
		if player_model != null:
			player_model.visible = false
	for node in _walk(_dungeon):
		if not node.has_meta("enemy_type"):
			continue
		var enemy := node as Node3D
		if enemy == null:
			continue
		enemy.visible = true
		for mesh in enemy.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).visible = true
		var imposter := enemy.get_node_or_null("ImposterSprite") as Sprite3D
		if imposter != null:
			imposter.visible = false

func _hide_ceilings() -> void:
	for node in _walk(_dungeon):
		if not node is MultiMeshInstance3D:
			continue
		var node_name := String(node.name).to_lower()
		if node_name.contains("ceiling") or node_name.contains("lintel"):
			(node as Node3D).visible = false

func _pick_capture_target() -> Vector3:
	var best_room := Rect2i()
	var best_score := -1.0
	for room_index in range(_dungeon.layout.rooms.size()):
		var room: Rect2i = _dungeon.layout.rooms[room_index]
		if _dungeon.layout.room_roles.has("start") and room == _dungeon.layout.room_roles["start"]:
			continue
		var enemy_count := _count_specs_in_room(_dungeon.layout.enemy_spawn_specs, room_index)
		var hazard_count := _count_specs_in_room(_dungeon.layout.hazard_anchors, room_index)
		var focus_count := _count_specs_in_room(_dungeon.layout.room_focus_specs, room_index)
		var door_count := _count_door_specs_in_room(room)
		var score := float(enemy_count * 12 + hazard_count * 5 + focus_count * 8 + door_count * 2)
		if enemy_count > 0:
			score += 20.0
		score += minf(float(room.size.x * room.size.y), 100.0) * 0.04
		if score > best_score:
			best_score = score
			best_room = room
	_capture_room = best_room
	if best_score < 0.0:
		return Vector3.ZERO
	var cell := best_room.position + Vector2i(best_room.size.x / 2, best_room.size.y / 2)
	return _cell_to_world(cell)

func _pick_capture_span() -> float:
	var room_area := maxi(1, _capture_room.size.x * _capture_room.size.y)
	return clampf(sqrt(float(room_area)) * _dungeon.layout.tile_size, 10.0, 22.0)

func _count_specs_in_room(specs: Array, room_index: int) -> int:
	var count := 0
	for spec in specs:
		if int(spec.get("room_index", -1)) == room_index:
			count += 1
	return count

func _count_door_specs_in_room(room: Rect2i) -> int:
	var count := 0
	for spec in _dungeon.layout.door_specs:
		var inside: Vector2i = spec.get("inside", Vector2i(-1, -1))
		if room.has_point(inside):
			count += 1
	return count

func _cell_to_world(cell: Vector2i) -> Vector3:
	var offset_x := -float(_dungeon.layout.width * _dungeon.layout.tile_size) / 2.0
	var offset_z := -float(_dungeon.layout.height * _dungeon.layout.tile_size) / 2.0
	return Vector3(offset_x + cell.x * _dungeon.layout.tile_size, 0.0, offset_z + cell.y * _dungeon.layout.tile_size)

func _count_nodes_with_meta(meta_name: String) -> int:
	var count := 0
	for node in _walk(_dungeon):
		if node.has_meta(meta_name):
			count += 1
	return count

func _save_viewport(path: String) -> bool:
	var texture := get_viewport().get_texture()
	if texture == null:
		_fail("viewport texture 为空")
		return false
	var image := texture.get_image()
	if image == null:
		_fail("viewport image 为空")
		return false
	var lit_pixels := 0
	var step_x := maxi(1, image.get_width() / 40)
	var step_y := maxi(1, image.get_height() / 40)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			if color.a > 0.05 and color.r + color.g + color.b > 0.08:
				lit_pixels += 1
	if lit_pixels < 50:
		_fail("截图过暗或为空: lit_pixels=%d" % lit_pixels)
		return false
	return image.save_png(path) == OK

func _walk(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	var index := 0
	while index < nodes.size():
		for child in nodes[index].get_children():
			nodes.append(child)
		index += 1
	return nodes

func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame

func _finish(exit_code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(exit_code)

func _fail(message: String) -> void:
	_had_error = true
	push_error("[DungeonRealOverviewCapture] " + message)

func _get_int_arg(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		var value := String(arg)
		if value.begins_with(prefix) and value.substr(prefix.length()).is_valid_int():
			return int(value.substr(prefix.length()))
	return fallback
