extends Node

## Real-renderer dungeon stress probe.
##
## Run one scenario per process to keep GPU/resource lifetime isolated:
##   --scenario=dense_monsters
##   --scenario=multi_room_population
##   --scenario=cross_room_traversal
##
## This is a performance gate, not a visual approximation. It instantiates the
## production ProceduralDungeon scene, real Player, real enemy scenes, and real
## ItemSpawner objects before sampling a non-headless renderer.

const DUNGEON_SCENE := preload("res://scenes/expedition/procedural_dungeon.tscn")
const ITEM_TAGS := preload("res://data/item_tags.gd")
const P95_FRAME_MS := 33.3
const MAX_FRAME_MS := 50.0
const MAX_AVG_FRAME_MS := 16.7
const DEFAULT_SEED := 94021
const DEFAULT_SAMPLE_FRAMES := 90
const DEFAULT_WARMUP_FRAMES := 90
const DEFAULT_EXTRA_ENEMIES := 48
const DEFAULT_EXTRA_ITEMS_PER_ROOM := 4
const SCENARIOS := ["dense_monsters", "multi_room_population", "cross_room_traversal"]

var _scenario := "dense_monsters"
var _seed_value := DEFAULT_SEED
var _sample_frames := DEFAULT_SAMPLE_FRAMES
var _warmup_frames := DEFAULT_WARMUP_FRAMES
var _extra_enemies := DEFAULT_EXTRA_ENEMIES
var _extra_items_per_room := DEFAULT_EXTRA_ITEMS_PER_ROOM
var _output_path := ""
var _output_lines: Array[String] = []
var _dungeon: ProceduralDungeon = null
var _player: Node3D = null


func _ready() -> void:
	await _run()


func _run() -> void:
	_parse_args()
	# 压力测量必须绕过显示器 VSync，否则 GPU/CPU 超预算会被 60 Hz 帧间隔掩盖。
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().size = Vector2i(1280, 720)
	if _scenario == "all":
		for scenario in SCENARIOS:
			_scenario = scenario
			if not await _run_isolated_scenario():
				_finish(2)
				return
		_finish(0)
		return
	if not SCENARIOS.has(_scenario):
		push_error("DUNGEON_STRESS unknown scenario: %s" % _scenario)
		_finish(2)
		return
	var ok := await _run_isolated_scenario()
	_finish(0 if ok else 2)


func _run_isolated_scenario() -> bool:
	_output_lines.clear()
	if _output_path.is_empty():
		_output_path = "res://reports/dungeon_stress_%s.txt" % _scenario
	seed(_seed_value)
	var boot_started := Time.get_ticks_usec()
	_dungeon = DUNGEON_SCENE.instantiate() as ProceduralDungeon
	if _dungeon == null:
		push_error("DUNGEON_STRESS could not instantiate production dungeon")
		return false
	_dungeon.generation_seed = _seed_value
	_dungeon.spawn_population_enabled = true
	add_child(_dungeon)
	await _wait_frames(_warmup_frames)
	if _dungeon.layout == null or _dungeon.build_result == null:
		push_error("DUNGEON_STRESS production dungeon did not finish building")
		return false
	_player = GameState.current_player as Node3D
	if _player == null or not is_instance_valid(_player):
		push_error("DUNGEON_STRESS production Player was not spawned")
		return false
	var boot_ms := float(Time.get_ticks_usec() - boot_started) / 1000.0
	_emit("DUNGEON_STRESS scenario=%s seed=%d boot_ms=%.3f rooms=%d base_enemies=%d base_items=%d" % [
		_scenario,
		_seed_value,
		boot_ms,
		_dungeon.layout.rooms.size(),
		_count_enemies(),
		_count_items(),
	])

	var gate_ok := true
	match _scenario:
		"dense_monsters":
			gate_ok = await _run_dense_monsters()
		"multi_room_population":
			gate_ok = await _run_multi_room_population(false)
		"cross_room_traversal":
			gate_ok = await _run_multi_room_population(true)
	_cleanup_dungeon()
	_flush_output()
	return gate_ok


func _run_dense_monsters() -> bool:
	var room := _nearest_room(_player.global_position)
	var positions := _room_floor_positions(room, _extra_enemies)
	if positions.size() < _extra_enemies:
		positions = _ring_positions(_player.global_position, _extra_enemies, 3.0, 11.0)
	var spawned_enemies := _spawn_extra_enemies(positions)
	var item_positions := _ring_positions(_player.global_position, 24, 2.5, 9.0)
	var spawned_items := _spawn_extra_items(item_positions)
	await _wait_frames(_warmup_frames)
	_emit("DUNGEON_STRESS setup=dense_monsters extra_enemies=%d extra_items=%d" % [spawned_enemies, spawned_items])
	return await _sample_phase("dense_monsters", "dense_arena")


func _run_multi_room_population(traverse: bool) -> bool:
	var rooms := _selected_rooms(10)
	var enemy_positions: Array[Vector3] = []
	var item_positions: Array[Vector3] = []
	for room in rooms:
		var floor_positions := _room_floor_positions(room, 8)
		if floor_positions.is_empty():
			floor_positions.append(_room_center_position(room))
		for i in range(2):
			enemy_positions.append(floor_positions[i % floor_positions.size()])
		for i in range(_extra_items_per_room):
			item_positions.append(floor_positions[(i + 2) % floor_positions.size()])
	var spawned_enemies := _spawn_extra_enemies(enemy_positions)
	var spawned_items := _spawn_extra_items(item_positions)
	await _wait_frames(_warmup_frames)
	_emit("DUNGEON_STRESS setup=%s extra_enemies=%d extra_items=%d populated_rooms=%d" % [
		"cross_room_traversal" if traverse else "multi_room_population",
		spawned_enemies,
		spawned_items,
		rooms.size(),
	])
	if not traverse:
		return await _sample_phase("multi_room_population", "all_rooms_static")
	var gate_ok := true
	var room_index := 0
	for room in rooms:
		_player.global_position = _room_center_position(room)
		_player.velocity = Vector3.ZERO
		if _dungeon.streaming_controller != null:
			_dungeon.streaming_controller.update_streaming(true)
		await _wait_frames(20)
		var phase_ok := await _sample_phase("cross_room_traversal", "room_%02d" % room_index)
		gate_ok = gate_ok and phase_ok
		room_index += 1
	return gate_ok


func _spawn_extra_enemies(positions: Array[Vector3]) -> int:
	var spawner := Service.dungeon_spawner()
	if spawner == null or _dungeon.build_result.spawn_root == null:
		return 0
	var plan: Array = spawner.build_enemy_spawn_plan(_dungeon.layout, _player)
	var valid_plan: Array[Dictionary] = []
	for raw_desc in plan:
		var desc: Dictionary = raw_desc
		var base_type := String(desc.get("enemy_type", "")).trim_prefix("elite_")
		if not base_type.is_empty() and ResourceLoader.exists("res://scenes/characters/enemies/%s.tscn" % base_type):
			valid_plan.append(desc)
	if valid_plan.is_empty():
		return 0
	var spawned := 0
	for i in range(positions.size()):
		var desc := valid_plan[i % valid_plan.size()].duplicate(true)
		desc["pos"] = positions[i]
		var enemy: Node = spawner.instantiate_enemy_descriptor(
			desc, _dungeon.build_result.spawn_root, _player, _dungeon.layout
		)
		if enemy != null:
			enemy.set("player", _player)
			spawned += 1
	return spawned


func _spawn_extra_items(positions: Array[Vector3]) -> int:
	var spawner := Service.item_spawner()
	if spawner == null or _dungeon.build_result.spawn_root == null:
		return 0
	var spawned := 0
	for position in positions:
		var item: Node = spawner.spawn_item_by_tag(
			ITEM_TAGS.MATERIAL, position, _dungeon.build_result.spawn_root, _dungeon.dungeon_zone
		)
		if item != null:
			spawned += 1
	return spawned


func _sample_phase(scenario: String, phase: String) -> bool:
	var frame_times: Array[float] = []
	var total_render_objects := 0.0
	var total_primitives := 0.0
	var total_physics_ms := 0.0
	var total_process_ms := 0.0
	var worst_ms := 0.0
	var frame_started_usec := Time.get_ticks_usec()
	for _i in range(maxi(_sample_frames, 1)):
		await get_tree().process_frame
		var frame_ms := float(Time.get_ticks_usec() - frame_started_usec) / 1000.0
		frame_started_usec = Time.get_ticks_usec()
		frame_times.append(frame_ms)
		worst_ms = maxf(worst_ms, frame_ms)
		total_render_objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		total_primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		total_physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		total_process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var p95_ms := _percentile(frame_times, 0.95)
	var average_ms := _average(frame_times)
	var sample_count := float(maxi(_sample_frames, 1))
	var gate_ok := average_ms <= MAX_AVG_FRAME_MS and p95_ms <= P95_FRAME_MS and worst_ms <= MAX_FRAME_MS
	_emit("DUNGEON_STRESS scenario=%s phase=%s gate=%s avg_ms=%.3f p95_ms=%.3f worst_ms=%.3f physics_ms=%.3f process_ms=%.3f render_objects=%.1f primitives=%.1f enemies=%d items=%d active_physics=%d monitoring_areas=%d" % [
		scenario,
		phase,
		"PASS" if gate_ok else "FAIL",
		average_ms,
		p95_ms,
		worst_ms,
		total_physics_ms / sample_count,
		total_process_ms / sample_count,
		total_render_objects / sample_count,
		total_primitives / sample_count,
		_count_enemies(),
		_count_items(),
		_count_active_physics(),
		_count_monitoring_areas(),
	])
	return gate_ok


func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var index := clampi(int(ceil(float(sorted.size() - 1) * percentile)), 0, sorted.size() - 1)
	return float(sorted[index])


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _selected_rooms(limit: int) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = []
	for room in _dungeon.layout.rooms:
		rooms.append(room)
	rooms.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		return a.position.x + a.position.y < b.position.x + b.position.y
	)
	if rooms.size() > limit:
		rooms.resize(limit)
	return rooms


func _nearest_room(world_position: Vector3) -> Rect2i:
	var best := Rect2i()
	var best_distance := INF
	for room in _dungeon.layout.rooms:
		var distance := _room_center_position(room).distance_squared_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = room
	return best


func _room_floor_positions(room: Rect2i, limit: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var grid: Array = _dungeon.layout.grid
	var offset := Vector3(-float(_dungeon.layout.width * _dungeon.layout.tile_size) / 2.0, 0.5,
		-float(_dungeon.layout.height * _dungeon.layout.tile_size) / 2.0)
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			if y >= 0 and y < grid.size() and x >= 0 and x < grid[y].size() and int(grid[y][x]) == 1:
				result.append(offset + Vector3(x * _dungeon.layout.tile_size, 0.0, y * _dungeon.layout.tile_size))
				if result.size() >= limit:
					return result
	return result


func _room_center_position(room: Rect2i) -> Vector3:
	var cell := room.position + Vector2i(room.size.x / 2, room.size.y / 2)
	var offset := Vector3(-float(_dungeon.layout.width * _dungeon.layout.tile_size) / 2.0, 0.5,
		-float(_dungeon.layout.height * _dungeon.layout.tile_size) / 2.0)
	return offset + Vector3(cell.x * _dungeon.layout.tile_size, 0.0, cell.y * _dungeon.layout.tile_size)


func _ring_positions(center: Vector3, count: int, min_radius: float, max_radius: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in range(count):
		var ratio := float(i) / float(maxi(count - 1, 1))
		var radius := lerpf(min_radius, max_radius, ratio)
		var angle := float(i) * 2.39996323
		result.append(center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	return result


func _count_enemies() -> int:
	var count := 0
	for node in _walk(_dungeon):
		if node.has_meta("enemy_type"):
			count += 1
	return count


func _count_items() -> int:
	var count := 0
	for node in _walk(_dungeon):
		if node.has_meta("item_tag") and String(node.get_meta("item_tag")) == ITEM_TAGS.MATERIAL:
			count += 1
	return count


func _count_active_physics() -> int:
	var count := 0
	for node in _walk(_dungeon):
		if node is CollisionObject3D and bool(node.get_meta("stream_physics_active", true)):
			count += 1
	return count


func _count_monitoring_areas() -> int:
	var count := 0
	for node in _walk(_dungeon):
		if node is Area3D and (node as Area3D).monitoring:
			count += 1
	return count


func _walk(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	var index := 0
	while index < nodes.size():
		for child in nodes[index].get_children():
			nodes.append(child)
		index += 1
	return nodes


func _wait_frames(count: int) -> void:
	for _i in range(maxi(count, 0)):
		await get_tree().process_frame


func _cleanup_dungeon() -> void:
	if _dungeon != null and is_instance_valid(_dungeon):
		remove_child(_dungeon)
		_dungeon.queue_free()
	_dungeon = null
	_player = null


func _finish(exit_code: int) -> void:
	_flush_output()
	await get_tree().process_frame
	get_tree().quit(exit_code)


func _emit(line: String) -> void:
	print(line)
	_output_lines.append(line)


func _flush_output() -> void:
	if _output_path.is_empty():
		return
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		push_warning("DUNGEON_STRESS could not write %s" % _output_path)
		return
	for line in _output_lines:
		file.store_line(line)
	file.close()


func _parse_args() -> void:
	_scenario = _get_string_arg("scenario", _scenario)
	_seed_value = _get_int_arg("seed", _seed_value)
	_sample_frames = _get_int_arg("sample-frames", _sample_frames)
	_warmup_frames = _get_int_arg("warmup-frames", _warmup_frames)
	_extra_enemies = _get_int_arg("extra-enemies", _extra_enemies)
	_extra_items_per_room = _get_int_arg("extra-items-per-room", _extra_items_per_room)
	_output_path = _get_string_arg("output", _output_path)


func _get_int_arg(key: String, default_value: int) -> int:
	var value := _get_string_arg(key, "")
	return int(value) if not value.is_empty() else default_value


func _get_string_arg(key: String, default_value: String) -> String:
	var prefix := "--%s=" % key
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return default_value
