extends Node3D

const DUNGEON_SCENE := preload("res://scenes/expedition/procedural_dungeon.tscn")
const OUTPUT_PATH := "res://reports/dungeon_real_overview.png"
const EXPLORATION_OUTPUT_PATH := "res://reports/dungeon_real_exploration.png"
const DEFAULT_SEED := 94021
const IMAGE_SIZE := Vector2i(1600, 1000)

var _dungeon: ProceduralDungeon = null
var _camera: Camera3D = null
var _had_error := false
var _capture_room := Rect2i()

func _ready() -> void:
vcall_deferred("_capture")

func _capture() -> void:
vDisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
vget_window().size = IMAGE_SIZE
vvar seed_value := _get_int_arg("--seed=", DEFAULT_SEED)
v_dungeon = DUNGEON_SCENE.instantiate() as ProceduralDungeon
vif _dungeon == null:
vv_fail("无法实例化生产地牢")
vv_finish(1)
vvreturn
v_dungeon.generation_seed = seed_value
v_dungeon.spawn_population_enabled = true
vadd_child(_dungeon)
vawait _wait_frames(72)
vif _dungeon.layout == null or _dungeon.build_result == null:
vv_fail("生产地牢未完成生成")
vv_finish(1)
vvreturn
v_hide_material_items()
v_hide_ceilings()
v_hide_game_hud()
v_disable_game_cameras()
vvar target := _pick_capture_target()
vvar room_span := _pick_capture_span()
vif not _activate_capture_room(target):
vv_finish(1)
vvreturn
vawait _wait_frames(8)
v_hide_ceilings()
v_force_enemy_visuals()
v_camera = Camera3D.new()
v_camera.name = "DungeonCaptureCamera"
vadd_child(_camera)
v_camera.current = true
v_camera.cull_mask = 0xFFFFF
v_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
v_camera.fov = 58.0
v_camera.near = 0.05
v_camera.far = 180.0
v_camera.global_position = target + Vector3(room_span * 0.72, room_span * 0.62, room_span * 0.86)
v_camera.look_at(target + Vector3(0.0, 0.25, 0.0), Vector3.UP)
vawait _wait_frames(18)
v_force_enemy_visuals()
vif not _save_viewport(OUTPUT_PATH):
vv_finish(1)
vvreturn
vif not await _save_exploration_view():
vv_finish(1)
vvreturn
vprint("[DungeonRealOverviewCapture] saved=%s exploration=%s seed=%d enemies=%d hazards=%d focus=%d" % [
vvOUTPUT_PATH,
vvEXPLORATION_OUTPUT_PATH,
vvseed_value,
vv_count_nodes_with_meta("enemy_type"),
vv_count_nodes_with_meta("hazard_anchor"),
vv_count_nodes_with_meta("room_focus"),
v])
v_finish(0)

func _save_exploration_view() -> bool:
vvar wall_bay := _find_capture_room_wall_bay()
vif wall_bay == null:
vv_fail("截图目标房间没有墙龛，无法生成探索视角")
vvreturn false
vvar cell: Vector2i = wall_bay.get_meta("wall_cell", Vector2i(-1, -1))
vvar direction: Vector2i = wall_bay.get_meta("wall_direction", Vector2i.ZERO)
vif cell.x < 0 or direction == Vector2i.ZERO:
vv_fail("墙龛缺少有效的格坐标或朝向元数据")
vvreturn false
vvar wall_plane := _cell_to_world(cell) + Vector3(float(direction.x), 0.0, float(direction.y)) * _dungeon.layout.tile_size * 0.5
vvar inward := -Vector3(float(direction.x), 0.0, float(direction.y))
vvar tangent := Vector3(float(-direction.y), 0.0, float(direction.x))
v_camera.fov = 64.0
v_camera.global_position = wall_plane + inward * 6.2 + tangent * 1.35 + Vector3.UP * 1.55
v_camera.look_at(wall_plane + inward * 0.72 + Vector3.UP * 1.28, Vector3.UP)
vawait _wait_frames(18)
vreturn _save_viewport(EXPLORATION_OUTPUT_PATH)

func _find_capture_room_wall_bay() -> Node3D:
vvar anchor_cell := Vector2i(-1, -1)
vfor node in _walk(_dungeon):
vvif bool(node.get_meta("room_light_anchor", false)) \
vvvvand int(node.get_meta("room_index", -1)) == _capture_room_index():
vvvanchor_cell = node.get_meta("wall_cell", Vector2i(-1, -1))
vvvbreak
vvar best_bay: Node3D = null
vvar best_distance := INF
vfor node in _walk(_dungeon):
vvif not node is Node3D or not bool(node.get_meta("wall_architecture", false)):
vvvcontinue
vvvar cell: Vector2i = node.get_meta("wall_cell", Vector2i(-1, -1))
vvif not _capture_room.has_point(cell):
vvvcontinue
vvvar distance := 0.0 if anchor_cell.x < 0 else float(abs(cell.x - anchor_cell.x) + abs(cell.y - anchor_cell.y))
vvif distance < best_distance:
vvvbest_distance = distance
vvvbest_bay = node as Node3D
vreturn best_bay

func _capture_room_index() -> int:
vfor room_index in range(_dungeon.layout.rooms.size()):
vvif _dungeon.layout.rooms[room_index] == _capture_room:
vvvreturn room_index
vreturn -1

func _activate_capture_room(target: Vector3) -> bool:
vvar player := GameState.resolve_player_node(0) as Node3D
vif player == null or not is_instance_valid(player):
vv_fail("生产地牢没有有效的当前玩家，无法激活截图目标 chunk")
vvreturn false
vplayer.global_position = target + Vector3(0.0, 0.85, 0.0)
vif player is CharacterBody3D:
vv(player as CharacterBody3D).velocity = Vector3.ZERO
vif _dungeon.streaming_controller == null or not is_instance_valid(_dungeon.streaming_controller):
vv_fail("生产地牢没有流送控制器，无法激活截图目标 chunk")
vvreturn false
v_dungeon.streaming_controller.set_player(player)
v_dungeon.streaming_controller.update_streaming(true)
vreturn true

func _disable_game_cameras() -> void:
vfor node in _walk(_dungeon):
vvif node is Camera3D:
vvv(node as Camera3D).current = false

func _hide_game_hud() -> void:
vfor node in _walk(_dungeon):
vvif node is CanvasLayer:
vvv(node as CanvasLayer).visible = false

func _hide_material_items() -> void:
vfor node in _walk(_dungeon):
vvif not node.has_meta("item_tag") or String(node.get_meta("item_tag")) != "material":
vvvcontinue
vvif node is Node3D:
vvv(node as Node3D).visible = false

func _force_enemy_visuals() -> void:
vvar player := GameState.resolve_player_node(0) as Node3D
vif player != null and is_instance_valid(player):
vvvar player_model := player.get_node_or_null("character") as Node3D
vvif player_model != null:
vvvplayer_model.visible = false
vfor node in _walk(_dungeon):
vvif not node.has_meta("enemy_type"):
vvvcontinue
vvvar enemy := node as Node3D
vvif enemy == null:
vvvcontinue
vvenemy.visible = true
vvfor mesh in enemy.find_children("*", "MeshInstance3D", true, false):
vvv(mesh as MeshInstance3D).visible = true
vvvar imposter := enemy.get_node_or_null("ImposterSprite") as Sprite3D
vvif imposter != null:
vvvimposter.visible = false

func _hide_ceilings() -> void:
vfor node in _walk(_dungeon):
vvif not node is MultiMeshInstance3D:
vvvcontinue
vvvar node_name := String(node.name).to_lower()
vvif node_name.contains("ceiling") or node_name.contains("lintel"):
vvv(node as Node3D).visible = false

func _pick_capture_target() -> Vector3:
vvar best_room := Rect2i()
vvar best_score := -1.0
vfor room_index in range(_dungeon.layout.rooms.size()):
vvvar room: Rect2i = _dungeon.layout.rooms[room_index]
vvif _dungeon.layout.room_roles.has("start") and room == _dungeon.layout.room_roles["start"]:
vvvcontinue
vvvar enemy_count := _count_specs_in_room(_dungeon.layout.enemy_spawn_specs, room_index)
vvvar hazard_count := _count_specs_in_room(_dungeon.layout.hazard_anchors, room_index)
vvvar focus_count := _count_specs_in_room(_dungeon.layout.room_focus_specs, room_index)
vvvar composition := _composition_for_room(room_index)
vvvar door_count := _count_door_specs_in_room(room)
vvvar score := float(enemy_count * 12 + hazard_count * 5 + focus_count * 8 + door_count * 2)
vvscore += float(composition.get("cover_cells", []).size() * 4)
vvscore += float(composition.get("platform_cells", []).size() * 10)
vvscore += float(composition.get("ramp_specs", []).size() * 8)
vvscore += float(composition.get("boundary_edges", []).size() * 2)
vvif enemy_count > 0:
vvvscore += 20.0
vvscore += minf(float(room.size.x * room.size.y), 100.0) * 0.04
vvif score > best_score:
vvvbest_score = score
vvvbest_room = room
v_capture_room = best_room
vif best_score < 0.0:
vvreturn Vector3.ZERO
vvar cell := best_room.position + Vector2i(best_room.size.x / 2, best_room.size.y / 2)
vreturn _cell_to_world(cell)

func _pick_capture_span() -> float:
vvar room_area := maxi(1, _capture_room.size.x * _capture_room.size.y)
vreturn clampf(sqrt(float(room_area)) * _dungeon.layout.tile_size, 10.0, 22.0)

func _count_specs_in_room(specs: Array, room_index: int) -> int:
vvar count := 0
vfor spec in specs:
vvif int(spec.get("room_index", -1)) == room_index:
vvvcount += 1
vreturn count

func _count_door_specs_in_room(room: Rect2i) -> int:
vvar count := 0
vfor spec in _dungeon.layout.door_specs:
vvvar inside: Vector2i = spec.get("inside", Vector2i(-1, -1))
vvif room.has_point(inside):
vvvcount += 1
vreturn count

func _cell_to_world(cell: Vector2i) -> Vector3:
vvar offset_x := -float(_dungeon.layout.width * _dungeon.layout.tile_size) / 2.0
vvar offset_z := -float(_dungeon.layout.height * _dungeon.layout.tile_size) / 2.0
vreturn Vector3(offset_x + cell.x * _dungeon.layout.tile_size, _dungeon.layout.floor_height_at(cell), offset_z + cell.y * _dungeon.layout.tile_size)

func _composition_for_room(room_index: int) -> Dictionary:
vfor composition in _dungeon.layout.room_composition_specs:
vvif int(composition.get("room_index", -1)) == room_index:
vvvreturn composition
vreturn {}

func _count_nodes_with_meta(meta_name: String) -> int:
vvar count := 0
vfor node in _walk(_dungeon):
vvif node.has_meta(meta_name):
vvvcount += 1
vreturn count

func _save_viewport(path: String) -> bool:
vvar texture := get_viewport().get_texture()
vif texture == null:
vv_fail("viewport texture 为空")
vvreturn false
vvar image := texture.get_image()
vif image == null:
vv_fail("viewport image 为空")
vvreturn false
vvar lit_pixels := 0
vvar step_x := maxi(1, image.get_width() / 40)
vvar step_y := maxi(1, image.get_height() / 40)
vfor y in range(0, image.get_height(), step_y):
vvfor x in range(0, image.get_width(), step_x):
vvvvar color := image.get_pixel(x, y)
vvvif color.a > 0.05 and color.r + color.g + color.b > 0.08:
vvvvlit_pixels += 1
vif lit_pixels < 50:
vv_fail("截图过暗或为空: lit_pixels=%d" % lit_pixels)
vvreturn false
vreturn image.save_png(path) == OK

func _walk(root: Node) -> Array[Node]:
vvar nodes: Array[Node] = [root]
vvar index := 0
vwhile index < nodes.size():
vvfor child in nodes[index].get_children():
vvvnodes.append(child)
vvindex += 1
vreturn nodes

func _wait_frames(count: int) -> void:
vfor _index in range(count):
vvawait get_tree().process_frame

func _finish(exit_code: int) -> void:
vawait get_tree().process_frame
vget_tree().quit(exit_code)

func _fail(message: String) -> void:
v_had_error = true
vpush_error("[DungeonRealOverviewCapture] " + message)

func _get_int_arg(prefix: String, fallback: int) -> int:
vfor arg in OS.get_cmdline_user_args():
vvvar value := String(arg)
vvif value.begins_with(prefix) and value.substr(prefix.length()).is_valid_int():
vvvreturn int(value.substr(prefix.length()))
vreturn fallback
