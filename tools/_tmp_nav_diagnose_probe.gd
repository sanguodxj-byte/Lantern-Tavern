extends SceneTree

const DEBUG_TAG := "[DEBUG-NAV-DIAG]"
const DUNGEON_SCENE := "res://scenes/expedition/procedural_dungeon.tscn"
const TEST_SECONDS := 0.1

var _level: Node = null
var _player: Node3D = null
var _start_positions: Dictionary = {}
var _last_positions: Dictionary = {}
var _last_sample_time := 0.0
var _elapsed := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(DUNGEON_SCENE) as PackedScene
	if packed == null:
		print("%s scene_load_failed path=%s" % [DEBUG_TAG, DUNGEON_SCENE])
		quit(2)
		return
	_level = packed.instantiate()
	_level.set("generation_seed", 20260723)
	# The autoloaded ZoneManager may point at a non-combat zone during editor runs.
	# Keep this probe scoped to the production dungeon with the normal enemy roster.
	_level.set("dungeon_zone", 0)
	_level.set("spawn_population_enabled", true)
	root.add_child(_level)
	await process_frame
	await process_frame
	var game_state: Node = root.get_node_or_null("GameState")
	_player = game_state.get("current_player") as Node3D if game_state != null else null
	if _player == null:
		print("%s player_missing level=%s" % [DEBUG_TAG, _level.get_path()])
		quit(3)
		return
	var player_health: Node = _player.get("health") as Node
	if player_health != null:
		player_health.set("max_life", 100000)
		player_health.set("current_life", 100000)
	var runtime: Node = _find_runtime()
	var enemy_count_before: int = get_nodes_in_group("enemies").size()
	print("%s ready player=%s enemies=%d navigation_regions=%d runtime=%s" % [
		DEBUG_TAG,
		str(_player.global_position),
		enemy_count_before,
		_level.find_children("*", "NavigationRegion3D", true, false).size(),
		str(runtime),
	])
	print("%s layout_zone=%s rooms=%d spawn_specs=%d" % [
		DEBUG_TAG,
		str(_level.get("dungeon_zone")),
		int(_level.layout.rooms.size()) if _level.get("layout") != null else -1,
		int(_level.layout.enemy_spawn_specs.size()) if _level.get("layout") != null else -1,
	])
	var builder: Variant = (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).new()
	var obstacle_faces: PackedVector3Array = builder._build_navigation_obstacle_faces(_level.layout, _level.build_result)
	print("%s obstacle_faces=%d obstacle_boxes=%d wall_transforms=%d decor_bodies=%d door_bodies=%d chest_roots=%d" % [
		DEBUG_TAG,
		obstacle_faces.size(),
		obstacle_faces.size() / 36,
		_count_wall_transforms(),
		_count_static_bodies(_level.build_result.decor_root),
		_count_static_bodies(_level.build_result.collision_root),
		_count_chest_roots(_level.build_result.interaction_root),
	])
	if runtime == null:
		print("%s runtime_missing" % DEBUG_TAG)
		quit(4)
		return
	runtime.apply_monster_hunt_pressure(true)
	await _wait_physics_frames(30)
	_capture_positions()
	while _elapsed < TEST_SECONDS:
		await physics_frame
		_elapsed += 1.0 / float(Engine.physics_ticks_per_second)
		if _elapsed - _last_sample_time >= 1.0:
			_last_sample_time = _elapsed
			_sample("t=%.1f" % _elapsed)
	_sample("final")
	print("%s complete" % DEBUG_TAG)
	_level.queue_free()
	await process_frame
	quit()


func _find_runtime() -> Node:
	for node in _level.find_children("*", "DungeonRuntime", true, false):
		return node
	return _level.find_child("DungeonRuntime", true, false)

func _count_wall_transforms() -> int:
	var count := 0
	for group in _level.build_result.wall_transforms_by_height.values():
		count += (group.get("transforms", []) as Array).size()
	return count

func _count_static_bodies(root_node: Node) -> int:
	return root_node.find_children("*", "StaticBody3D", true, false).size() if root_node != null else 0

func _count_chest_roots(root_node: Node) -> int:
	var count := 0
	if root_node == null:
		return count
	for node in root_node.find_children("*", "StaticBody3D", true, false):
		if node.has_meta("topdown_kind") and String(node.get_meta("topdown_kind")) == "chest":
			count += 1
	return count


func _capture_positions() -> void:
	for node in get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null:
			continue
		var id := enemy.get_instance_id()
		_start_positions[id] = enemy.global_position
		_last_positions[id] = enemy.global_position


func _sample(label: String) -> void:
	var enemies: Array[Node] = get_nodes_in_group("enemies")
	var no_target := 0
	var no_path := 0
	var inactive := 0
	var no_move := 0
	var no_progress := 0
	var path_total := 0
	var path_count := 0
	var forced_hunt := 0
	var forced_hunt_inactive := 0
	var stream_inactive := 0
	var dead_or_dying := 0
	var parent_disabled := 0
	var stuck_details: Array[String] = []
	for node in enemies:
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		var id := enemy.get_instance_id()
		var target_ok := enemy.has_navigation_target()
		var path := enemy.nav_agent.get_current_navigation_path() if enemy.nav_agent != null else PackedVector3Array()
		var path_size := path.size()
		var distance := enemy.global_position.distance_to(_player.global_position)
		var moved_since_last := enemy.global_position.distance_to(_last_positions.get(id, enemy.global_position))
		var moved_total := enemy.global_position.distance_to(_start_positions.get(id, enemy.global_position))
		var is_forced_hunt := bool(enemy.get_meta("dark_erosion_hunt", false))
		var stream_active := bool(enemy.get_meta("stream_physics_active", true))
		var parent_node := enemy.get_parent()
		if is_forced_hunt:
			forced_hunt += 1
			if not enemy.is_physics_processing():
				forced_hunt_inactive += 1
		if not stream_active:
			stream_inactive += 1
		if enemy.state == Enemy.State.DEAD or enemy.state == Enemy.State.DYING:
			dead_or_dying += 1
		if parent_node != null and parent_node.process_mode == Node.PROCESS_MODE_DISABLED:
			parent_disabled += 1
		var map := enemy.nav_agent.get_navigation_map() if enemy.nav_agent != null else RID()
		var map_iteration := NavigationServer3D.map_get_iteration_id(map) if map.is_valid() else 0
		path_total += path_size
		path_count += 1 if path_size > 0 else 0
		if not target_ok:
			no_target += 1
		if path_size == 0:
			no_path += 1
		if not enemy.is_physics_processing():
			inactive += 1
		if moved_since_last < 0.01:
			no_move += 1
		if moved_total < 0.1 and distance > 2.0:
			no_progress += 1
		if stuck_details.size() < 12 and (not target_ok or path_size == 0 or moved_total < 0.1 or not enemy.is_physics_processing()):
			stuck_details.append("id=%d pos=%s dist=%.2f target=%s visible=%s path=%d map=%d iter=%d moved=%.2f state=%s forced=%s stream=%s physics=%s mode=%d parent_mode=%d" % [
				id,
				str(enemy.global_position),
				distance,
				str(target_ok),
				str(enemy.is_target_visible()),
				path_size,
				1 if map.is_valid() else 0,
				map_iteration,
				moved_total,
				str(enemy.state),
				str(is_forced_hunt),
				str(stream_active),
				str(enemy.is_physics_processing()),
				enemy.process_mode,
				parent_node.process_mode if parent_node != null else -1,
			])
		_last_positions[id] = enemy.global_position
	print("%s %s enemies=%d target_missing=%d path_missing=%d physics_inactive=%d frame_no_move=%d no_progress=%d path_with_data=%d path_avg=%.2f forced_hunt=%d forced_inactive=%d stream_inactive=%d dead_or_dying=%d parent_disabled=%d" % [
		DEBUG_TAG,
		label,
		enemies.size(),
		no_target,
		no_path,
		inactive,
		no_move,
		no_progress,
		path_count,
		float(path_total) / float(maxi(1, path_count)),
		forced_hunt,
		forced_hunt_inactive,
		stream_inactive,
		dead_or_dying,
		parent_disabled,
	])
	for detail in stuck_details:
		print("%s detail %s" % [DEBUG_TAG, detail])


func _wait_physics_frames(count: int) -> void:
	for _i in count:
		await physics_frame
