extends GdUnitTestSuite

const DEBUG_TAG := "[DEBUG-NAV-DIAG]"
const DUNGEON_SCENE := "res://scenes/expedition/procedural_dungeon.tscn"
const HUNT_COMPLETION_DISTANCE := 3.5


func test_actual_dungeon_navigation_diagnosis() -> void:
	var packed: PackedScene = load(DUNGEON_SCENE) as PackedScene
	assert_object(packed).is_not_null()
	if packed == null:
		return
	var level: ProceduralDungeon = packed.instantiate() as ProceduralDungeon
	level.generation_seed = 20260723
	level.dungeon_zone = 0
	level.spawn_population_enabled = true
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = GameState.current_player as Player
	var runtime: DungeonRuntime = null
	var runtime_nodes: Array[Node] = level.find_children("*", "DungeonRuntime", true, false)
	if not runtime_nodes.is_empty():
		runtime = runtime_nodes[0] as DungeonRuntime
	assert_object(player).is_not_null()
	assert_object(runtime).is_not_null()
	if player == null or runtime == null:
		level.queue_free()
		return
	player.health.max_life = 100000
	player.health.current_life = 100000
	var regions := level.find_children("*", "NavigationRegion3D", true, false)
	print("%s ready player=%s enemies=%d regions=%d" % [
		DEBUG_TAG,
		str(player.global_position),
		get_tree().get_nodes_in_group("enemies").size(),
		regions.size(),
	])
	for node in regions:
		var region := node as NavigationRegion3D
		var map := region.get_navigation_map()
		print("%s region=%s map_valid=%s map_iteration=%d polygons=%d" % [
			DEBUG_TAG,
			str(region.get_path()),
			str(map.is_valid()),
			NavigationServer3D.map_get_iteration_id(map) if map.is_valid() else 0,
			region.navigation_mesh.get_polygon_count() if region.navigation_mesh != null else 0,
		])
	var builder: Variant = (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).new()
	var obstacle_faces: PackedVector3Array = builder._build_navigation_obstacle_faces(level.layout, level.build_result)
	print("%s layout=%dx%d tile=%.2f floor_transforms=%d walkable_cells=%d" % [
		DEBUG_TAG,
		level.layout.width,
		level.layout.height,
		level.layout.tile_size,
		level.build_result.floor_transforms.size(),
		_count_walkable_cells(level.layout),
	])
	var wall_box_count := 0
	for group in level.build_result.wall_transforms_by_height.values():
		wall_box_count += (group.get("transforms", []) as Array).size()
	print("%s obstacle_faces=%d obstacle_boxes=%d wall_boxes=%d decor_bodies=%d collision_bodies=%d chest_roots=%d" % [
		DEBUG_TAG,
		obstacle_faces.size(),
		obstacle_faces.size() / 36,
		wall_box_count,
		level.build_result.decor_root.find_children("*", "StaticBody3D", true, false).size(),
		level.build_result.collision_root.find_children("*", "StaticBody3D", true, false).size(),
		_count_chest_roots(level.build_result.interaction_root),
	])
	for anchor in level.layout.hazard_anchors:
		var cell: Vector2i = anchor.get("anchor_cell", Vector2i(-1, -1))
		var offset := Vector3(-float(level.layout.width) * level.layout.tile_size * 0.5, 0.0, -float(level.layout.height) * level.layout.tile_size * 0.5)
		var world := offset + Vector3(cell.x * level.layout.tile_size, 0.0, cell.y * level.layout.tile_size)
		print("%s hazard type=%s cell=%s world=%s" % [DEBUG_TAG, str(anchor.get("hazard_type", "")), str(cell), str(world)])
	# Drive the same source of truth as production. Calling the runtime helper
	# alone is transient because ExplorationPressure emits periodic snapshots.
	assert_object(runtime.exploration_pressure).is_not_null()
	if runtime.exploration_pressure != null:
		runtime.exploration_pressure.threat_level = 100.0
		runtime.on_pressure_changed(runtime.exploration_pressure.make_snapshot())
	await _wait_for_enemy_population(level.layout.enemy_spawn_specs.size())
	await _wait_physics_frames(30)
	var start_positions: Dictionary = {}
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy != null:
			start_positions[enemy.get_instance_id()] = enemy.global_position
	_sample("t=0", player, start_positions, level)
	# 30 秒真实物理帧：覆盖全图追击、跨房间路径和持续接触攻击。
	for i in range(1800):
		await get_tree().physics_frame
		if i % 300 == 299:
			_sample("t=%.1f" % (float(i + 1) / 60.0), player, start_positions, level)
	var final_metrics := _sample("final", player, start_positions, level)
	assert_int(int(final_metrics["forced_active"])).is_equal(int(final_metrics["forced_hunt"]))
	assert_int(int(final_metrics["moving_without_target"])).is_equal(0)
	assert_int(int(final_metrics["moving_without_path"])).is_equal(0)
	assert_int(int(final_metrics["dead_or_dying"])).is_equal(0)
	assert_int(int(final_metrics["far_moving"])).is_equal(0)
	level.queue_free()
	await get_tree().process_frame


func _sample(label: String, player: Player, start_positions: Dictionary, level: ProceduralDungeon) -> Dictionary:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var hazards: Array[Node3D] = []
	for node in level.find_children("*", "Area3D", true, false):
		if node is Node3D and bool(node.get_meta("hazard_anchor", false)):
			hazards.append(node as Node3D)
	var target_missing := 0
	var path_missing := 0
	var inactive := 0
	var no_progress := 0
	var path_count := 0
	var path_total := 0
	var forced_hunt := 0
	var forced_inactive := 0
	var stream_inactive := 0
	var forced_stream_inactive := 0
	var dead_or_dying := 0
	var parent_disabled := 0
	var below_floor := 0
	var forced_active := 0
	var moving_without_target := 0
	var moving_without_path := 0
	var far_moving := 0
	var details: Array[String] = []
	for node in enemies:
		var enemy := node as Enemy
		if enemy == null:
			continue
		var agent := enemy.nav_agent
		var path: PackedVector3Array = agent.get_current_navigation_path() if agent != null else PackedVector3Array()
		var has_target := enemy.has_navigation_target()
		var distance := enemy.global_position.distance_to(player.global_position)
		var moved := enemy.global_position.distance_to(start_positions.get(enemy.get_instance_id(), enemy.global_position))
		var is_forced_hunt := bool(enemy.get_meta("dark_erosion_hunt", false))
		var stream_active := bool(enemy.get_meta("stream_physics_active", true))
		var parent_node := enemy.get_parent()
		if is_forced_hunt:
			forced_hunt += 1
			if enemy.state != Enemy.State.DEAD and enemy.state != Enemy.State.DYING:
				forced_active += 1
			if enemy.state == Enemy.State.MOVING:
				if distance > HUNT_COMPLETION_DISTANCE:
					far_moving += 1
				if not has_target:
					moving_without_target += 1
				if path.is_empty():
					moving_without_path += 1
			if not enemy.is_physics_processing():
				forced_inactive += 1
			if not stream_active:
				forced_stream_inactive += 1
		if not stream_active:
			stream_inactive += 1
		if enemy.state == Enemy.State.DEAD or enemy.state == Enemy.State.DYING:
			dead_or_dying += 1
		if parent_node != null and parent_node.process_mode == Node.PROCESS_MODE_DISABLED:
			parent_disabled += 1
		if enemy.global_position.y < -0.2:
			below_floor += 1
		if not has_target:
			target_missing += 1
		if path.is_empty():
			path_missing += 1
		else:
			path_count += 1
			path_total += path.size()
		if not enemy.is_physics_processing():
			inactive += 1
		if moved < 0.1 and distance > 2.0:
			no_progress += 1
		if details.size() < 16 and (enemy.state == Enemy.State.MOVING and (not has_target or path.is_empty() or moved < 0.1 or distance > HUNT_COMPLETION_DISTANCE or not enemy.is_physics_processing() or enemy.global_position.y < -0.2)):
			var map := agent.get_navigation_map() if agent != null else RID()
			var nearest := _nearest_hazard(enemy, hazards)
			var next_path := agent.get_next_path_position() if agent != null else Vector3.ZERO
			var target_position := enemy.get_navigation_target_position()
			var direct_path := NavigationServer3D.map_get_path(map, enemy.global_position, target_position, true) if map.is_valid() else PackedVector3Array()
			var desired: Vector3 = Vector3(enemy.movement_controller.get("desired_velocity")) if enemy.movement_controller != null else Vector3.ZERO
			var cell := _world_to_cell(enemy.global_position, level.layout)
			var cell_type := -1
			if cell.y >= 0 and cell.y < level.layout.grid.size() and cell.x >= 0 and cell.x < level.layout.grid[cell.y].size():
				cell_type = int(level.layout.grid[cell.y][cell.x])
			var slide_colliders: Array[String] = []
			var slide_contacts: Array[String] = []
			for collision_index in range(enemy.get_slide_collision_count()):
				var collision := enemy.get_slide_collision(collision_index)
				var collider := collision.get_collider() as Node
				if collider != null:
					slide_colliders.append("%s:%s" % [collider.get_path(), collider.get_class()])
					slide_contacts.append("point=%s normal=%s wall_boxes=%s" % [
						str(collision.get_position()),
						str(collision.get_normal()),
						_find_nearby_wall_boxes(enemy.global_position, level),
					])
			var enemy_health := enemy.health
			var state_node_name := enemy.state_node.get_class() if enemy.state_node != null else "null"
			details.append("id=%d pos=%s target_pos=%s next=%s path_first=%s path_last=%s direct_path=%d vel=%s desired=%s cell=%s cell_type=%d dist=%.2f target=%s visible=%s path=%d map=%s iter=%d moved=%.2f state=%s forced=%s stream=%s forced_active=%s physics=%s mode=%d parent_mode=%d y=%.2f nearest_hazard=%s hazard_dist=%.2f slides=%s" % [
				enemy.get_instance_id(),
				str(enemy.global_position),
				str(target_position),
				str(next_path),
				str(path[0]) if not path.is_empty() else "none",
				str(path[path.size() - 1]) if not path.is_empty() else "none",
				direct_path.size(),
				str(enemy.velocity),
				str(desired),
				str(cell),
				cell_type,
				distance,
				str(has_target),
				str(enemy.is_target_visible()),
				path.size(),
				str(map.is_valid()),
				NavigationServer3D.map_get_iteration_id(map) if map.is_valid() else 0,
				moved,
				str(enemy.state),
				str(is_forced_hunt),
				str(stream_active),
				str(bool(enemy.get_meta("stream_forced_hunt_active", false))),
				str(enemy.is_physics_processing()),
				enemy.process_mode,
				parent_node.process_mode if parent_node != null else -1,
				enemy.global_position.y,
				String(nearest.get("type", "")),
				float(nearest.get("distance", INF)),
				",".join(slide_colliders) + " contacts=" + ",".join(slide_contacts) + " health=%d/%d state_node=%s player_health=%d/%d player_state=%s" % [
					enemy_health.current_life if enemy_health != null else -1,
					enemy_health.max_life if enemy_health != null else -1,
					state_node_name,
					player.health.current_life if player != null and player.health != null else -1,
					player.health.max_life if player != null and player.health != null else -1,
					str(player.state) if player != null else "null",
				],
			])
	print("%s %s enemies=%d target_missing=%d path_missing=%d inactive=%d no_progress=%d far_moving=%d path_with_data=%d path_avg=%.2f forced_hunt=%d forced_inactive=%d stream_inactive=%d forced_stream_inactive=%d dead_or_dying=%d parent_disabled=%d below_floor=%d" % [
		DEBUG_TAG,
		label,
		enemies.size(),
		target_missing,
		path_missing,
		inactive,
		no_progress,
		far_moving,
		path_count,
		float(path_total) / float(maxi(1, path_count)),
		forced_hunt,
		forced_inactive,
		stream_inactive,
		forced_stream_inactive,
		dead_or_dying,
		parent_disabled,
		below_floor,
	])
	for detail in details:
		print("%s detail %s" % [DEBUG_TAG, detail])
	return {
		"forced_hunt": forced_hunt,
		"forced_active": forced_active,
		"moving_without_target": moving_without_target,
		"moving_without_path": moving_without_path,
		"far_moving": far_moving,
		"dead_or_dying": dead_or_dying,
	}


func _find_nearby_wall_boxes(position: Vector3, level: ProceduralDungeon) -> String:
	if level == null or level.build_result == null:
		return "none"
	var boxes: Array[String] = []
	for wall_key in level.build_result.wall_transforms_by_height:
		var group: Dictionary = level.build_result.wall_transforms_by_height[wall_key]
		var size: Vector3 = group.get("size", Vector3.ZERO)
		for transform_value in group.get("transforms", []):
			var transform := transform_value as Transform3D
			var bounds := AABB(transform.origin - size * 0.5, size)
			var closest_x := clampf(position.x, bounds.position.x, bounds.end.x)
			var closest_z := clampf(position.z, bounds.position.z, bounds.end.z)
			var distance := Vector2(position.x - closest_x, position.z - closest_z).length()
			if distance <= 1.5:
				boxes.append("key=%s center=%s size=%s bounds=%s dist=%.3f" % [
					str(wall_key),
					str(transform.origin),
					str(size),
					str(bounds),
					distance,
				])
				if boxes.size() >= 8:
					return ";".join(boxes)
	return ";".join(boxes) if not boxes.is_empty() else "none"


func _nearest_hazard(enemy: Enemy, hazards: Array[Node3D]) -> Dictionary:
	var nearest := {"type": "", "distance": INF}
	for hazard in hazards:
		if hazard == null or not is_instance_valid(hazard):
			continue
		var distance := enemy.global_position.distance_to(hazard.global_position)
		if distance < float(nearest["distance"]):
			nearest = {
				"type": String(hazard.get_meta("hazard_type", hazard.name)),
				"distance": distance,
			}
	return nearest


func _count_chest_roots(root: Node) -> int:
	var count := 0
	if root == null:
		return count
	for node in root.find_children("*", "StaticBody3D", true, false):
		if node.has_meta("topdown_kind") and String(node.get_meta("topdown_kind")) == "chest":
			count += 1
	return count


func _count_walkable_cells(layout: DungeonLayout) -> int:
	var count := 0
	for row in layout.grid:
		for cell_type in row:
			if int(cell_type) in [1, 3, 4, 5]:
				count += 1
	return count


func _wait_for_enemy_population(expected_count: int) -> void:
	for _i in range(240):
		if get_tree().get_nodes_in_group("enemies").size() >= expected_count:
			return
		await get_tree().physics_frame


func _wait_physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func _world_to_cell(world_position: Vector3, layout: DungeonLayout) -> Vector2i:
	var offset_x := -(float(layout.width) * layout.tile_size) / 2.0
	var offset_z := -(float(layout.height) * layout.tile_size) / 2.0
	return Vector2i(
		roundi((world_position.x - offset_x) / layout.tile_size),
		roundi((world_position.z - offset_z) / layout.tile_size),
	)
