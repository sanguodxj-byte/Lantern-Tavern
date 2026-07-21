extends Node3D

const DungeonGenerator := preload("res://scenes/expedition/dungeon_generator.gd")
const DungeonGenerationConfig := preload("res://scenes/expedition/dungeon_generation_config.gd")
const DungeonHazardPlanner := preload("res://scenes/expedition/dungeon_hazard_planner.gd")
const DungeonSpawnPlanner := preload("res://scenes/expedition/dungeon_spawn_planner.gd")
const DungeonSceneBuilder := preload("res://scenes/expedition/dungeon_scene_builder.gd")
const DungeonStreamingController := preload("res://scenes/expedition/dungeon_streaming_controller.gd")

var _sample_frames := 90
var _warmup_frames := 20
var _angles: Array[float] = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]
var _output_path := "res://reports/dungeon_view_perf_probe_metrics.txt"
var _output_lines: Array[String] = []


func _ready() -> void:
	_run()


func _run() -> void:
	_sample_frames = _get_int_arg("sample-frames", _sample_frames)
	_warmup_frames = _get_int_arg("warmup-frames", _warmup_frames)
	_angles = _get_angle_arg(_angles)
	_output_path = _get_string_arg("output", _output_path)
	_output_lines.clear()

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().size = Vector2i(1280, 720)
	var seed_value := _get_int_arg("seed", 94021)
	seed(seed_value)

	var probe := _build_probe_dungeon(seed_value)
	if probe.is_empty():
		push_error("DUNGEON_VIEW_PROBE could not build dungeon")
		get_tree().quit(2)
		return
	var dungeon := probe["root"] as Node3D
	var streaming_controller := probe["streaming_controller"] as DungeonStreamingController
	var observer := probe["observer"] as Node3D
	var camera := probe["camera"] as Camera3D
	var layout = probe["layout"]
	await get_tree().process_frame
	await get_tree().process_frame

	var base_counts := _count_scene(dungeon)
	var enemy_types := {}
	for spec in layout.enemy_spawn_specs:
		enemy_types[String(spec.get("enemy_type", ""))] = true
	_emit("DUNGEON_VIEW_PROBE scene seed=%d generation_ms=%.3f build_ms=%.3f nodes=%d multimeshes=%d mesh_instances=%d occluders=%d lights=%d physics_bodies=%d areas=%d streamed_physics=%d terrain_chunks=%d environment_lights=%d enemy_spawns=%d enemy_types=%d imposter_captures=%d" % [
		seed_value,
		float(probe["generation_ms"]),
		float(probe["build_ms"]),
		base_counts["nodes"],
		base_counts["multimeshes"],
		base_counts["mesh_instances"],
		base_counts["occluders"],
		base_counts["lights"],
		base_counts["physics_bodies"],
		base_counts["areas"],
		_count_chunk_entries(streaming_controller._physics_chunks),
		streaming_controller._terrain_chunks.size(),
		_count_chunk_entries(streaming_controller._light_chunks),
		layout.enemy_spawn_specs.size(),
		enemy_types.size(),
		enemy_types.size(),
	])

	for angle in _angles:
		observer.rotation.y = deg_to_rad(angle)
		camera.rotation.x = 0.0
		streaming_controller.update_streaming(true)
		await _wait_frames(_warmup_frames)
		var sample := await _sample_angle(dungeon, streaming_controller, camera, observer, angle)
		_print_sample(sample)

	remove_child(dungeon)
	dungeon.queue_free()
	_flush_output()
	await get_tree().process_frame
	get_tree().quit(0)


func _build_probe_dungeon(seed_value: int) -> Dictionary:
	var dungeon := Node3D.new()
	dungeon.name = "DungeonPerfProbeRoot"
	add_child(dungeon)
	_configure_probe_environment(dungeon)

	var config := DungeonGenerationConfig.default_for_zone(0)
	config.seed = seed_value
	var generation_started := Time.get_ticks_usec()
	var layout = DungeonGenerator.new().generate(config)
	if layout == null or layout.is_empty():
		dungeon.queue_free()
		return {}
	DungeonHazardPlanner.new().plan(layout)
	var spawn_planner := DungeonSpawnPlanner.new()
	spawn_planner.plan_enemy_spawns(layout)
	spawn_planner.plan_item_spawns(layout)
	spawn_planner.plan_chest_spawns(layout)
	var generation_ms := float(Time.get_ticks_usec() - generation_started) / 1000.0

	var build_started := Time.get_ticks_usec()
	var build_result = DungeonSceneBuilder.new().build(layout, dungeon)
	var build_ms := float(Time.get_ticks_usec() - build_started) / 1000.0
	if build_result == null or not build_result.is_built():
		dungeon.queue_free()
		return {}

	var streaming_controller := DungeonStreamingController.new()
	dungeon.add_child(streaming_controller)
	streaming_controller.configure(layout, build_result)
	var observer_data := _create_probe_observer(dungeon, layout)
	var observer := observer_data["observer"] as Node3D
	streaming_controller.set_player(observer)
	for node in _walk(dungeon):
		if node is OmniLight3D or node is SpotLight3D:
			streaming_controller.register_light(node as Light3D)
	streaming_controller.update_streaming(true)
	return {
		"root": dungeon,
		"layout": layout,
		"build_result": build_result,
		"streaming_controller": streaming_controller,
		"observer": observer,
		"camera": observer_data["camera"],
		"generation_ms": generation_ms,
		"build_ms": build_ms,
	}


func _create_probe_observer(dungeon: Node3D, layout) -> Dictionary:
	var observer := Node3D.new()
	observer.name = "PerfObserver"
	observer.position = layout.calc_player_spawn_pos()
	dungeon.add_child(observer)
	var camera := Camera3D.new()
	camera.name = "PerfCamera"
	camera.position = Vector3(0.0, 1.2, 0.0)
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 120.0
	observer.add_child(camera)
	camera.current = true
	return {"observer": observer, "camera": camera}


func _configure_probe_environment(dungeon: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.018, 0.025)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.30, 0.34, 0.42)
	environment.ambient_light_energy = 0.22
	environment.fog_enabled = true
	environment.fog_density = 0.012
	world_environment.environment = environment
	dungeon.add_child(world_environment)
	var ambient_directional := DirectionalLight3D.new()
	ambient_directional.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	ambient_directional.light_energy = 0.15
	ambient_directional.shadow_enabled = false
	dungeon.add_child(ambient_directional)


func _wait_frames(count: int) -> void:
	for _i in range(maxi(count, 0)):
		await get_tree().process_frame


func _sample_angle(dungeon: Node3D, streaming_controller: DungeonStreamingController,
		camera: Camera3D, observer: Node3D, angle: float) -> Dictionary:
	var total_delta := 0.0
	var worst_delta := 0.0
	var total_objects := 0.0
	var total_primitives := 0.0
	for _i in range(_sample_frames):
		await get_tree().process_frame
		var delta := get_process_delta_time()
		total_delta += delta
		worst_delta = maxf(worst_delta, delta)
		total_objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		total_primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)

	var visibility := _measure_visibility(dungeon, camera)
	visibility["yaw"] = angle
	visibility["avg_ms"] = (total_delta / float(maxi(_sample_frames, 1))) * 1000.0
	visibility["worst_ms"] = worst_delta * 1000.0
	visibility["render_objects"] = total_objects / float(maxi(_sample_frames, 1))
	visibility["primitives"] = total_primitives / float(maxi(_sample_frames, 1))
	visibility["player_chunk"] = streaming_controller._world_to_chunk(observer.global_position)
	return visibility


func _measure_visibility(root_node: Node, camera: Camera3D) -> Dictionary:
	var stats := {
		"active_terrain_nodes": 0,
		"active_terrain_instances": 0,
		"frustum_terrain_instances": 0,
		"visible_lights": 0,
		"frustum_lights": 0,
		"visible_meshes": 0,
		"frustum_meshes": 0,
		"active_physics_bodies": 0,
		"monitoring_areas": 0,
		"processing_characters": 0,
	}
	for node in _walk(root_node):
		if node is MultiMeshInstance3D:
			var mm_node := node as MultiMeshInstance3D
			if mm_node.is_inside_tree() and mm_node.is_visible_in_tree() and mm_node.multimesh != null:
				stats["active_terrain_nodes"] += 1
				var count := mm_node.multimesh.instance_count
				stats["active_terrain_instances"] += count
				for index in range(count):
					var pos := mm_node.global_transform * mm_node.multimesh.get_instance_transform(index).origin
					if camera.is_position_in_frustum(pos):
						stats["frustum_terrain_instances"] += 1
		elif node is Light3D:
			var light := node as Light3D
			if light.is_inside_tree() and light.is_visible_in_tree():
				stats["visible_lights"] += 1
				if camera.is_position_in_frustum(light.global_position):
					stats["frustum_lights"] += 1
		elif node is MeshInstance3D:
			var mesh := node as MeshInstance3D
			if mesh.is_inside_tree() and mesh.is_visible_in_tree():
				stats["visible_meshes"] += 1
				if camera.is_position_in_frustum(mesh.global_position):
					stats["frustum_meshes"] += 1
		elif node is CollisionObject3D:
			if bool(node.get_meta("stream_physics_active", true)):
				stats["active_physics_bodies"] += 1
			if node is Area3D and (node as Area3D).monitoring:
				stats["monitoring_areas"] += 1
			if node is CharacterBody3D and node.is_physics_processing():
				stats["processing_characters"] += 1
	return stats


func _print_sample(sample: Dictionary) -> void:
	_emit("DUNGEON_VIEW_PROBE yaw=%.1f avg_ms=%.3f worst_ms=%.3f render_objects=%.1f primitives=%.1f chunk=%s active_terrain_nodes=%d active_terrain_instances=%d frustum_terrain_instances=%d visible_lights=%d frustum_lights=%d visible_meshes=%d frustum_meshes=%d active_physics_bodies=%d monitoring_areas=%d processing_characters=%d" % [
		float(sample["yaw"]),
		float(sample["avg_ms"]),
		float(sample["worst_ms"]),
		float(sample["render_objects"]),
		float(sample["primitives"]),
		str(sample["player_chunk"]),
		int(sample["active_terrain_nodes"]),
		int(sample["active_terrain_instances"]),
		int(sample["frustum_terrain_instances"]),
		int(sample["visible_lights"]),
		int(sample["frustum_lights"]),
		int(sample["visible_meshes"]),
		int(sample["frustum_meshes"]),
		int(sample["active_physics_bodies"]),
		int(sample["monitoring_areas"]),
		int(sample["processing_characters"]),
	])


func _emit(line: String) -> void:
	print(line)
	_output_lines.append(line)


func _flush_output() -> void:
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		push_warning("DUNGEON_VIEW_PROBE could not write %s" % _output_path)
		return
	for line in _output_lines:
		file.store_line(line)
	file.close()


func _count_scene(root_node: Node) -> Dictionary:
	var counts := {
		"nodes": 0,
		"multimeshes": 0,
		"mesh_instances": 0,
		"occluders": 0,
		"lights": 0,
		"physics_bodies": 0,
		"areas": 0,
	}
	for node in _walk(root_node):
		counts["nodes"] += 1
		if node is MultiMeshInstance3D:
			counts["multimeshes"] += 1
		if node is MeshInstance3D:
			counts["mesh_instances"] += 1
		if node is OccluderInstance3D:
			counts["occluders"] += 1
		if node is Light3D:
			counts["lights"] += 1
		if node is PhysicsBody3D:
			counts["physics_bodies"] += 1
		if node is Area3D:
			counts["areas"] += 1
	return counts


func _count_chunk_entries(chunks: Dictionary) -> int:
	var count := 0
	for entries in chunks.values():
		count += (entries as Array).size()
	return count


func _walk(root_node: Node) -> Array[Node]:
	var nodes: Array[Node] = [root_node]
	var index := 0
	while index < nodes.size():
		for child in nodes[index].get_children():
			nodes.append(child)
		index += 1
	return nodes


func _get_int_arg(key: String, default_value: int) -> int:
	var prefix := "--%s=" % key
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return int(arg.substr(prefix.length()))
	return default_value


func _get_string_arg(key: String, default_value: String) -> String:
	var prefix := "--%s=" % key
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return default_value


func _get_angle_arg(default_value: Array[float]) -> Array[float]:
	var prefix := "--angles="
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if not arg.begins_with(prefix):
			continue
		var result: Array[float] = []
		for part in arg.substr(prefix.length()).split(",", false):
			result.append(float(part))
		return result if not result.is_empty() else default_value
	return default_value
