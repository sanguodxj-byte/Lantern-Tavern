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
const P95_FRAME_MS := 16.67
const MAX_FRAME_MS := 25.0
const MAX_AVG_FRAME_MS := 16.0
const MIN_ONE_PERCENT_LOW_FPS := 60.0
const DEFAULT_SEED := 94021
const DEFAULT_SAMPLE_FRAMES := 90
const DEFAULT_WARMUP_FRAMES := 90
const DEFAULT_EXTRA_ENEMIES := 48
const DEFAULT_EXTRA_ITEMS_PER_ROOM := 4
const SCENARIOS := ["no_enemies", "dense_monsters", "multi_room_population", "cross_room_traversal"]

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
_await _run()


func _run() -> void:
__parse_args()
_# 压力测量必须绕过显示器 VSync，否则 GPU/CPU 超预算会被 60 Hz 帧间隔掩盖。
_DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
_get_window().size = Vector2i(1280, 720)
_if _scenario == "all":
__for scenario in SCENARIOS:
____scenario = scenario
___if not await _run_isolated_scenario():
_____finish(2)
____return
___finish(0)
__return
_if not SCENARIOS.has(_scenario):
__push_error("DUNGEON_STRESS unknown scenario: %s" % _scenario)
___finish(2)
__return
_var ok := await _run_isolated_scenario()
__finish(0 if ok else 2)


func _run_isolated_scenario() -> bool:
__output_lines.clear()
_if _output_path.is_empty():
___output_path = "res://reports/dungeon_stress_%s.txt" % _scenario
_seed(_seed_value)
_var boot_started := Time.get_ticks_usec()
__dungeon = DUNGEON_SCENE.instantiate() as ProceduralDungeon
_if _dungeon == null:
__push_error("DUNGEON_STRESS could not instantiate production dungeon")
__return false
__dungeon.generation_seed = _seed_value
__dungeon.spawn_population_enabled = _scenario != "no_enemies"
_add_child(_dungeon)
_await _wait_frames(_warmup_frames)
_if _dungeon.layout == null or _dungeon.build_result == null:
__push_error("DUNGEON_STRESS production dungeon did not finish building")
__return false
__player = GameState.resolve_player_node(0) as Node3D
_if _player == null or not is_instance_valid(_player):
__push_error("DUNGEON_STRESS production Player was not spawned")
__return false
_var boot_ms := float(Time.get_ticks_usec() - boot_started) / 1000.0
__emit("DUNGEON_STRESS scenario=%s seed=%d boot_ms=%.3f rooms=%d base_enemies=%d base_items=%d" % [
___scenario,
___seed_value,
__boot_ms,
___dungeon.layout.rooms.size(),
___count_enemies(),
___count_items(),
_])

_var gate_ok := true
_match _scenario:
__"no_enemies":
___gate_ok = await _run_no_enemies()
__"dense_monsters":
___gate_ok = await _run_dense_monsters()
__"multi_room_population":
___gate_ok = await _run_multi_room_population(false)
__"cross_room_traversal":
___gate_ok = await _run_multi_room_population(true)
__cleanup_dungeon()
__flush_output()
_return gate_ok


func _run_no_enemies() -> bool:
_# 与密集敌人场景使用同种子、同地牢环境和同玩家；唯一差异是关闭生产人口生成，
_# 用作判断敌人模型/AI/物理是否为主要瓶颈的严格基线。
_await _wait_frames(_warmup_frames)
__emit("DUNGEON_STRESS setup=no_enemies enemies=%d items=%d" % [_count_enemies(), _count_items()])
_return await _sample_phase("no_enemies", "environment_only")


func _run_dense_monsters() -> bool:
_var room := _nearest_room(_player.global_position)
_var positions := _room_floor_positions(room, _extra_enemies)
_if positions.size() < _extra_enemies:
__positions = _ring_positions(_player.global_position, _extra_enemies, 3.0, 11.0)
_var spawned_enemies := _spawn_extra_enemies(positions)
_var item_positions := _ring_positions(_player.global_position, 24, 2.5, 9.0)
_var spawned_items := _spawn_extra_items(item_positions)
_await _wait_frames(_warmup_frames)
__emit("DUNGEON_STRESS setup=dense_monsters extra_enemies=%d extra_items=%d" % [spawned_enemies, spawned_items])
_return await _sample_phase("dense_monsters", "dense_arena")


func _run_multi_room_population(traverse: bool) -> bool:
_var rooms := _selected_rooms(10)
_var enemy_positions: Array[Vector3] = []
_var item_positions: Array[Vector3] = []
_for room in rooms:
__var floor_positions := _room_floor_positions(room, 8)
__if floor_positions.is_empty():
___floor_positions.append(_room_center_position(room))
__for i in range(2):
___enemy_positions.append(floor_positions[i % floor_positions.size()])
__for i in range(_extra_items_per_room):
___item_positions.append(floor_positions[(i + 2) % floor_positions.size()])
_var spawned_enemies := _spawn_extra_enemies(enemy_positions)
_var spawned_items := _spawn_extra_items(item_positions)
_await _wait_frames(_warmup_frames)
__emit("DUNGEON_STRESS setup=%s extra_enemies=%d extra_items=%d populated_rooms=%d" % [
__"cross_room_traversal" if traverse else "multi_room_population",
__spawned_enemies,
__spawned_items,
__rooms.size(),
_])
_if not traverse:
__return await _sample_phase("multi_room_population", "all_rooms_static")
_var gate_ok := true
_var room_index := 0
_for room in rooms:
___player.global_position = _room_center_position(room)
___player.velocity = Vector3.ZERO
__if _dungeon.streaming_controller != null:
____dungeon.streaming_controller.update_streaming(true)
__await _wait_frames(20)
__var phase_ok := await _sample_phase("cross_room_traversal", "room_%02d" % room_index)
__gate_ok = gate_ok and phase_ok
__room_index += 1
_return gate_ok


func _spawn_extra_enemies(positions: Array[Vector3]) -> int:
_var spawner := Service.dungeon_spawner()
_if spawner == null or _dungeon.build_result.spawn_root == null:
__return 0
_var plan: Array = spawner.build_enemy_spawn_plan(_dungeon.layout, _player)
_var valid_plan: Array[Dictionary] = []
_for raw_desc in plan:
__var desc: Dictionary = raw_desc
__var base_type := String(desc.get("enemy_type", "")).trim_prefix("elite_")
__if not base_type.is_empty() and ResourceLoader.exists("res://scenes/characters/enemies/%s.tscn" % base_type):
___valid_plan.append(desc)
_if valid_plan.is_empty():
__return 0
_var spawned := 0
_for i in range(positions.size()):
__var desc := valid_plan[i % valid_plan.size()].duplicate(true)
__desc["pos"] = positions[i]
__var enemy: Node = spawner.instantiate_enemy_descriptor(
___desc, _dungeon.build_result.spawn_root, _player, _dungeon.layout
__)
__if enemy != null:
___# player_ref 已由生成器作为候选引用注入；不能把压力场景敌人预先标记为已交战，
___# 否则会绕过 AI_SIM_RADIUS_M 并夸大生产地牢 AI 开销。
___spawned += 1
_return spawned


func _spawn_extra_items(positions: Array[Vector3]) -> int:
_var spawner := Service.item_spawner()
_if spawner == null or _dungeon.build_result.spawn_root == null:
__return 0
_var spawned := 0
_for position in positions:
__var item: Node = spawner.spawn_item_by_tag(
___ITEM_TAGS.MATERIAL, position, _dungeon.build_result.spawn_root, _dungeon.dungeon_zone
__)
__if item != null:
___spawned += 1
_return spawned


func _sample_phase(scenario: String, phase: String) -> bool:
_var frame_times: Array[float] = []
_var total_render_objects := 0.0
_var total_primitives := 0.0
_var total_physics_ms := 0.0
_var total_process_ms := 0.0
_var max_physics_ms := 0.0
_var max_process_ms := 0.0
_var worst_ms := 0.0
_var frame_started_usec := Time.get_ticks_usec()
_for _i in range(maxi(_sample_frames, 1)):
__await get_tree().process_frame
__var frame_ms := float(Time.get_ticks_usec() - frame_started_usec) / 1000.0
__frame_started_usec = Time.get_ticks_usec()
__frame_times.append(frame_ms)
__worst_ms = maxf(worst_ms, frame_ms)
__total_render_objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
__total_primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
__var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
__var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
__total_physics_ms += physics_ms
__total_process_ms += process_ms
__max_physics_ms = maxf(max_physics_ms, physics_ms)
__max_process_ms = maxf(max_process_ms, process_ms)
_var p95_ms := _percentile(frame_times, 0.95)
_var p99_ms := _percentile(frame_times, 0.99)
_var average_ms := _average(frame_times)
_var one_percent_low_fps := 1000.0 / maxf(p99_ms, 0.001)
_var sample_count := float(maxi(_sample_frames, 1))
_var physics_breakdown := _collect_physics_breakdown()
_var runtime_breakdown := _collect_runtime_breakdown()
_var gate_ok := average_ms <= MAX_AVG_FRAME_MS and p95_ms <= P95_FRAME_MS \
__and one_percent_low_fps >= MIN_ONE_PERCENT_LOW_FPS and worst_ms <= MAX_FRAME_MS
__emit("DUNGEON_STRESS scenario=%s phase=%s gate=%s avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f one_percent_low_fps=%.1f worst_ms=%.3f physics_ms=%.3f process_ms=%.3f max_physics_ms=%.3f max_process_ms=%.3f render_objects=%.1f primitives=%.1f enemies=%d items=%d active_enemy_bodies=%d active_item_bodies=%d active_areas=%d active_static_colliders=%d active_bone_bodies=%d active_fragment_bodies=%d active_other_bodies=%d active_physics_total=%d monitoring_areas=%d visible_meshes=%d enemy_meshes=%d item_meshes=%d environment_meshes=%d visible_particles=%d visible_lights=%d active_animation_players=%d active_ai_enemies=%d avoidance_agents=%d" % [
__scenario,
__phase,
__"PASS" if gate_ok else "FAIL",
__average_ms,
__p95_ms,
__p99_ms,
__one_percent_low_fps,
__worst_ms,
__total_physics_ms / sample_count,
__total_process_ms / sample_count,
__max_physics_ms,
__max_process_ms,
__total_render_objects / sample_count,
__total_primitives / sample_count,
___count_enemies(),
___count_items(),
__int(physics_breakdown["enemy_bodies"]),
__int(physics_breakdown["item_bodies"]),
__int(physics_breakdown["areas"]),
__int(physics_breakdown["static_colliders"]),
__int(physics_breakdown["bone_bodies"]),
__int(physics_breakdown["fragment_bodies"]),
__int(physics_breakdown["other_bodies"]),
__int(physics_breakdown["total"]),
___count_monitoring_areas(),
__int(runtime_breakdown["visible_meshes"]),
__int(runtime_breakdown["enemy_meshes"]),
__int(runtime_breakdown["item_meshes"]),
__int(runtime_breakdown["environment_meshes"]),
__int(runtime_breakdown["visible_particles"]),
__int(runtime_breakdown["visible_lights"]),
__int(runtime_breakdown["active_animation_players"]),
__int(runtime_breakdown["active_ai_enemies"]),
__int(runtime_breakdown["avoidance_agents"]),
_])
_return gate_ok


func _percentile(values: Array[float], percentile: float) -> float:
_if values.is_empty():
__return 0.0
_var sorted: Array = values.duplicate()
_sorted.sort()
_var index := clampi(int(ceil(float(sorted.size() - 1) * percentile)), 0, sorted.size() - 1)
_return float(sorted[index])


func _average(values: Array[float]) -> float:
_if values.is_empty():
__return 0.0
_var total := 0.0
_for value in values:
__total += value
_return total / float(values.size())


func _selected_rooms(limit: int) -> Array[Rect2i]:
_var rooms: Array[Rect2i] = []
_for room in _dungeon.layout.rooms:
__rooms.append(room)
_rooms.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
__return a.position.x + a.position.y < b.position.x + b.position.y
_)
_if rooms.size() > limit:
__rooms.resize(limit)
_return rooms


func _nearest_room(world_position: Vector3) -> Rect2i:
_var best := Rect2i()
_var best_distance := INF
_for room in _dungeon.layout.rooms:
__var distance := _room_center_position(room).distance_squared_to(world_position)
__if distance < best_distance:
___best_distance = distance
___best = room
_return best


func _room_floor_positions(room: Rect2i, limit: int) -> Array[Vector3]:
_var result: Array[Vector3] = []
_var grid: Array = _dungeon.layout.grid
_var offset := Vector3(-float(_dungeon.layout.width * _dungeon.layout.tile_size) / 2.0, 0.5,
__-float(_dungeon.layout.height * _dungeon.layout.tile_size) / 2.0)
_for y in range(room.position.y, room.position.y + room.size.y):
__for x in range(room.position.x, room.position.x + room.size.x):
___if y >= 0 and y < grid.size() and x >= 0 and x < grid[y].size() and int(grid[y][x]) == 1:
____result.append(offset + Vector3(x * _dungeon.layout.tile_size, 0.0, y * _dungeon.layout.tile_size))
____if result.size() >= limit:
_____return result
_return result


func _room_center_position(room: Rect2i) -> Vector3:
_var cell := room.position + Vector2i(room.size.x / 2, room.size.y / 2)
_var offset := Vector3(-float(_dungeon.layout.width * _dungeon.layout.tile_size) / 2.0, 0.5,
__-float(_dungeon.layout.height * _dungeon.layout.tile_size) / 2.0)
_return offset + Vector3(cell.x * _dungeon.layout.tile_size, 0.0, cell.y * _dungeon.layout.tile_size)


func _ring_positions(center: Vector3, count: int, min_radius: float, max_radius: float) -> Array[Vector3]:
_var result: Array[Vector3] = []
_for i in range(count):
__var ratio := float(i) / float(maxi(count - 1, 1))
__var radius := lerpf(min_radius, max_radius, ratio)
__var angle := float(i) * 2.39996323
__result.append(center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
_return result


func _count_enemies() -> int:
_var count := 0
_for node in _walk(_dungeon):
__if node.has_meta("enemy_type"):
___count += 1
_return count


func _count_items() -> int:
_var count := 0
_for node in _walk(_dungeon):
__if node.has_meta("item_tag") and String(node.get_meta("item_tag")) == ITEM_TAGS.MATERIAL:
___count += 1
_return count


func _collect_physics_breakdown() -> Dictionary:
_var stats := {
__"enemy_bodies": 0,
__"item_bodies": 0,
__"areas": 0,
__"static_colliders": 0,
__"bone_bodies": 0,
__"fragment_bodies": 0,
__"other_bodies": 0,
__"total": 0,
_}
_for node in _walk(_dungeon):
__if not node is CollisionObject3D or not _is_collision_object_active(node as CollisionObject3D):
___continue
__stats["total"] += 1
__if node is PhysicalBone3D:
___stats["bone_bodies"] += 1
__elif node is Area3D:
___stats["areas"] += 1
__elif node is StaticBody3D:
___stats["static_colliders"] += 1
__elif node is CharacterBody3D and node.is_in_group("enemies"):
___stats["enemy_bodies"] += 1
__elif node is RigidBody3D and _is_fragment_body(node as RigidBody3D):
___stats["fragment_bodies"] += 1
__elif node is RigidBody3D and _is_item_body(node as RigidBody3D):
___stats["item_bodies"] += 1
__else:
___stats["other_bodies"] += 1
_return stats


func _is_collision_object_active(body: CollisionObject3D) -> bool:
_if body.has_meta("stream_physics_registered"):
__return bool(body.get_meta("stream_physics_active", false))
_if body is Area3D:
__var area := body as Area3D
__return area.monitoring or area.monitorable or area.collision_layer != 0 or area.collision_mask != 0
_if body is RigidBody3D:
__var rigid := body as RigidBody3D
__return not rigid.freeze and (rigid.collision_layer != 0 or rigid.collision_mask != 0)
_return body.collision_layer != 0 or body.collision_mask != 0


func _is_item_body(body: RigidBody3D) -> bool:
_return body is PickableItem or body.has_meta("item_tag") \
__or body.get_script() != null and String(body.get_script().resource_path).contains("equipment/")


func _is_fragment_body(body: RigidBody3D) -> bool:
_return bool(body.get_meta("voxel_ragdoll_fragment", false)) \
__or body.collision_layer == PhysicsSetup.LAYER_DEBRIS


func _collect_runtime_breakdown() -> Dictionary:
_var stats := {
__"visible_meshes": 0,
__"enemy_meshes": 0,
__"item_meshes": 0,
__"environment_meshes": 0,
__"visible_particles": 0,
__"visible_lights": 0,
__"active_animation_players": 0,
__"active_ai_enemies": 0,
__"avoidance_agents": 0,
_}
_for node in _walk(_dungeon):
__if node is GeometryInstance3D and node.is_visible_in_tree():
___stats["visible_meshes"] += 1
___var category := _render_category(node)
___stats["%s_meshes" % category] += 1
__elif node is GPUParticles3D and node.is_visible_in_tree() and (node as GPUParticles3D).emitting:
___stats["visible_particles"] += 1
__elif node is CPUParticles3D and node.is_visible_in_tree() and (node as CPUParticles3D).emitting:
___stats["visible_particles"] += 1
__elif node is Light3D and node.is_visible_in_tree():
___stats["visible_lights"] += 1
__elif node is AnimationPlayer and (node as AnimationPlayer).is_playing() \
____and not is_zero_approx((node as AnimationPlayer).speed_scale):
___stats["active_animation_players"] += 1
__elif node is NavigationAgent3D and (node as NavigationAgent3D).avoidance_enabled:
___stats["avoidance_agents"] += 1
__if node.is_in_group("enemies") and node.has_method("is_ai_active") \
____and node.is_physics_processing() and bool(node.call("is_ai_active")):
___stats["active_ai_enemies"] += 1
_return stats


func _render_category(node: Node) -> String:
_var current := node
_while current != null and current != _dungeon:
__if current.is_in_group("enemies") or current.has_meta("enemy_type"):
___return "enemy"
__if current is PickableItem or current.has_meta("item_tag"):
___return "item"
__current = current.get_parent()
_return "environment"


func _count_monitoring_areas() -> int:
_var count := 0
_for node in _walk(_dungeon):
__if node is Area3D and (node as Area3D).monitoring:
___count += 1
_return count


func _walk(root: Node) -> Array[Node]:
_var nodes: Array[Node] = [root]
_var index := 0
_while index < nodes.size():
__for child in nodes[index].get_children():
___nodes.append(child)
__index += 1
_return nodes


func _wait_frames(count: int) -> void:
_for _i in range(maxi(count, 0)):
__await get_tree().process_frame


func _cleanup_dungeon() -> void:
_if _dungeon != null and is_instance_valid(_dungeon):
__remove_child(_dungeon)
___dungeon.queue_free()
__dungeon = null
__player = null


func _finish(exit_code: int) -> void:
__flush_output()
_await get_tree().process_frame
_get_tree().quit(exit_code)


func _emit(line: String) -> void:
_print(line)
__output_lines.append(line)


func _flush_output() -> void:
_if _output_path.is_empty():
__return
_var file := FileAccess.open(_output_path, FileAccess.WRITE)
_if file == null:
__push_warning("DUNGEON_STRESS could not write %s" % _output_path)
__return
_for line in _output_lines:
__file.store_line(line)
_file.close()


func _parse_args() -> void:
__scenario = _get_string_arg("scenario", _scenario)
__seed_value = _get_int_arg("seed", _seed_value)
__sample_frames = _get_int_arg("sample-frames", _sample_frames)
__warmup_frames = _get_int_arg("warmup-frames", _warmup_frames)
__extra_enemies = _get_int_arg("extra-enemies", _extra_enemies)
__extra_items_per_room = _get_int_arg("extra-items-per-room", _extra_items_per_room)
__output_path = _get_string_arg("output", _output_path)


func _get_int_arg(key: String, default_value: int) -> int:
_var value := _get_string_arg(key, "")
_return int(value) if not value.is_empty() else default_value


func _get_string_arg(key: String, default_value: String) -> String:
_var prefix := "--%s=" % key
_for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
__if arg.begins_with(prefix):
___return arg.substr(prefix.length())
_return default_value
