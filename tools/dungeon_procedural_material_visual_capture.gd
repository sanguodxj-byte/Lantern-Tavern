extends Node3D
## Place remade brewing-material models inside a real procedural dungeon and capture 3D views.
##
## Usage:
## "D:/123/Godot_v4.7-stable_mono_win64.exe" --path "D:/123/Lantern Tavern" res://tools/dungeon_procedural_material_visual_capture_scene.tscn
##
## Optional:
##   -- --seed=94021
##   -- --overview-only
##   -- --gallery-only
##   -- --ids=rat_tail,glowshroom

const OUTPUT_DIR := "res://reports/dungeon_materials_preview"
const IMAGE_SIZE := Vector2i(1600, 1000)
const CLOSE_SIZE := Vector2i(720, 720)
const DEFAULT_SEED := 94021
const MATERIAL_MODELS := preload("res://data/material_model_registry.gd")

const ROSTER_IDS := [
	"rat_tail", "moldy_bread", "rusty_nail", "dungeon_moss", "bone_shard",
	"stale_water", "prison_lichen", "cellar_mushroom", "blackberry", "glowshroom",
	"moongrass", "pixie_dust", "poison_berry", "deeprock_moss", "black_rye_root",
	"stalactite_sap", "goblin_nail", "mistflower", "wolfear_herb", "cyclops_beard",
	"geothermal_ear", "luminous_fern", "quartz_dust", "blindfish_jerky",
	"skeleton_dust", "goblin_ear", "giant_rat_tail", "slime_jelly", "troll_blood",
	"soul_gem", "dragon_scale",
]

const SAMPLE_CLOSEUP_IDS := [
	"rat_tail", "glowshroom", "deeprock_moss", "rusty_nail",
	"soul_gem", "dragon_scale", "slime_jelly", "moongrass",
]

var _had_error := false
var _layout = null
var _build_result = null
var _dungeon: Node3D = null
var _camera: Camera3D = null
var _spawned_natural: Array[Node3D] = []
var _spawned_gallery: Array[Node3D] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var seed_value := _get_int_arg("--seed=", DEFAULT_SEED)
	var overview_only := _has_flag("--overview-only")
	var gallery_only := _has_flag("--gallery-only")
	var selected_ids := _parse_ids()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	seed(seed_value)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().size = IMAGE_SIZE
	print("[DungeonProceduralMaterialCapture] seed=%d overview_only=%s gallery_only=%s" % [
		seed_value, overview_only, gallery_only
	])

	_dungeon = await _build_procedural_dungeon(seed_value)
	if _dungeon == null:
		_fail("failed to build procedural dungeon")
		get_tree().quit(1)
		return

	if not gallery_only:
		_spawn_natural_materials()
	_spawn_gallery_materials(selected_ids)
	_force_capture_visibility(_dungeon)
	_camera = Camera3D.new()
	_camera.name = "CaptureCamera"
	_dungeon.add_child(_camera)
	_camera.current = true
	await _settle_frames(20)
	print("[DungeonProceduralMaterialCapture] dungeon ready; capturing...")

	var overview_path := await _capture_elevated_overview()
	if overview_path.is_empty():
		_fail("elevated overview failed")
	else:
		print("[DungeonProceduralMaterialCapture] overview -> %s" % overview_path)

	var eye_path := await _capture_eyelevel()
	if eye_path.is_empty():
		_fail("eyelevel capture failed")
	else:
		print("[DungeonProceduralMaterialCapture] eyelevel -> %s" % eye_path)

	var gallery_path := await _capture_gallery()
	if gallery_path.is_empty():
		_fail("gallery capture failed")
	else:
		print("[DungeonProceduralMaterialCapture] gallery -> %s" % gallery_path)

	var totem := _find_planned_decor("ritual_totem")
	if totem != null:
		var totem_path := await _capture_insitu_closeup(totem, "ritual_totem")
		if totem_path.is_empty():
			_fail("insitu closeup failed for ritual_totem")
		else:
			print("[DungeonProceduralMaterialCapture] insitu ritual_totem -> %s" % totem_path)
	else:
		_fail("fixed seed generated no instantiated ritual_totem")

	if not overview_only and not gallery_only:
		var close_ids: Array[String] = []
		for id in SAMPLE_CLOSEUP_IDS:
			if selected_ids.has(String(id)):
				close_ids.append(String(id))
		# Prefer natural spawns when present, else gallery holders.
		for mat_id in close_ids:
			var node := _find_spawned(mat_id)
			if node == null:
				continue
			var path := await _capture_insitu_closeup(node, mat_id)
			if path.is_empty():
				_fail("insitu closeup failed for %s" % mat_id)
			else:
				print("[DungeonProceduralMaterialCapture] insitu %s -> %s" % [mat_id, path])

	if _had_error:
		print("[DungeonProceduralMaterialCapture] finished WITH ERRORS")
		get_tree().quit(1)
		return
	print("[DungeonProceduralMaterialCapture] done -> %s" % OUTPUT_DIR)
	await get_tree().process_frame
	get_tree().quit(0)


func _build_procedural_dungeon(seed_value: int) -> Node3D:
	var dungeon := Node3D.new()
	dungeon.name = "ProceduralMaterialDungeon"
	add_child(dungeon)
	_configure_environment(dungeon)

	var config := DungeonGenerationConfig.default_for_zone(0)
	config.seed = seed_value
	# Slightly smaller map keeps visual capture responsive while remaining a real dungeon.
	config.width = 30
	config.height = 30
	config.target_room_count = 9
	config.enable_hazards = false
	config.enable_spawn_planning = true

	var generation_started := Time.get_ticks_usec()
	print("[DungeonProceduralMaterialCapture] generating layout...")
	_layout = DungeonGenerator.new().generate(config)
	if _layout == null or _layout.is_empty():
		_fail("DungeonGenerator returned empty layout")
		return null
	DungeonHazardPlanner.new().plan(_layout)
	DungeonRoomFocusPlanner.new().plan(_layout)
	var spawn_planner := DungeonSpawnPlanner.new()
	spawn_planner.plan_enemy_spawns(_layout)
	spawn_planner.plan_item_spawns(_layout)
	spawn_planner.plan_chest_spawns(_layout)
	var generation_ms := float(Time.get_ticks_usec() - generation_started) / 1000.0
	var ritual_totems := 0
	for decor_spec in _layout.decor_specs:
		if String(decor_spec.get("decor_kind", "")) == "ritual_totem":
			ritual_totems += 1
	print("[DungeonProceduralMaterialCapture] layout ready rooms=%d specs=%d decor=%d ritual_totems=%d gen_ms=%.1f" % [
		_layout.rooms.size(), _layout.item_spawn_specs.size(), _layout.decor_specs.size(), ritual_totems, generation_ms
	])

	var build_started := Time.get_ticks_usec()
	print("[DungeonProceduralMaterialCapture] building scene...")
	_build_result = DungeonSceneBuilder.new().build(_layout, dungeon)
	var build_ms := float(Time.get_ticks_usec() - build_started) / 1000.0
	if _build_result == null or not _build_result.is_built():
		_fail("DungeonSceneBuilder failed")
		return null
	print("[DungeonProceduralMaterialCapture] build done ms=%.1f" % build_ms)
	await _settle_frames(8)
	return dungeon


func _configure_environment(dungeon: Node3D) -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.018, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.44)
	env.ambient_light_energy = 0.42
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.08, 0.10)
	env.fog_density = 0.006
	world_env.environment = env
	dungeon.add_child(world_env)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.72, 0.80, 0.92)
	fill.light_energy = 0.32
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-50.0, 28.0, 0.0)
	dungeon.add_child(fill)


func _spawn_natural_materials() -> void:
	_spawned_natural.clear()
	if _layout == null or _dungeon == null:
		return
	var offset := _layout_offset()
	var spawn_root: Node3D = _build_result.spawn_root if _build_result != null and _build_result.spawn_root != null else _dungeon
	for spec in _layout.item_spawn_specs:
		if String(spec.get("item_type", "")) != "material":
			continue
		var mat_id := String(spec.get("item_id", ""))
		if mat_id.is_empty():
			continue
		var cell: Vector2i = spec["cell"]
		var cell_pos := offset + Vector3(float(cell.x) * _layout.tile_size, 0.0, float(cell.y) * _layout.tile_size)
		var wall_dir := _find_wall_direction(cell)
		var world_pos := _position_for_material(mat_id, cell_pos, wall_dir)
		var holder := _spawn_material_visual(mat_id, world_pos, spawn_root, wall_dir, "natural")
		if holder != null:
			_spawned_natural.append(holder)
	print("[DungeonProceduralMaterialCapture] natural materials spawned=%d" % _spawned_natural.size())


func _spawn_gallery_materials(ids: Array[String]) -> void:
	_spawned_gallery.clear()
	if _layout == null or _dungeon == null or ids.is_empty():
		return
	var room: Rect2i = _pick_gallery_room()
	var cells := _collect_room_floor_cells(room)
	if cells.is_empty():
		_fail("gallery room has no floor cells")
		return
	var offset := _layout_offset()
	var spawn_root: Node3D = _build_result.spawn_root if _build_result != null and _build_result.spawn_root != null else _dungeon
	var cols := 7
	var center := Vector3(
		(float(room.position.x) + float(room.size.x) * 0.5) * _layout.tile_size,
		0.0,
		(float(room.position.y) + float(room.size.y) * 0.5) * _layout.tile_size
	) + offset
	var spacing := minf(_layout.tile_size * 0.42, 1.15)
	var index := 0
	for mat_id in ids:
		var row := index / cols
		var col := index % cols
		var local := Vector3(
			(float(col) - float(mini(cols, ids.size()) - 1) * 0.5) * spacing,
			0.0,
			(float(row) - 1.0) * spacing
		)
		var world_pos := center + local
		var holder := _spawn_material_visual(String(mat_id), world_pos, spawn_root, Vector3.ZERO, "gallery")
		if holder != null:
			if MATERIAL_MODELS.should_random_yaw(String(mat_id)):
				holder.rotation.y = float(index) * 0.41
			_spawned_gallery.append(holder)
		index += 1
	print("[DungeonProceduralMaterialCapture] gallery materials spawned=%d room=%s" % [
		_spawned_gallery.size(), str(room)
	])


func _spawn_material_visual(mat_id: String, world_pos: Vector3, parent: Node, wall_dir: Vector3, source: String) -> Node3D:
	var glb_path := MATERIAL_MODELS.get_model_path(mat_id)
	if glb_path.is_empty():
		glb_path = "res://assets/models/materials/materials_%s.glb" % mat_id
	if not ResourceLoader.exists(glb_path):
		_fail("missing glb for %s (%s)" % [mat_id, glb_path])
		return null
	var packed := load(glb_path) as PackedScene
	if packed == null:
		_fail("cannot load glb for %s" % mat_id)
		return null
	var visual := packed.instantiate() as Node3D
	if visual == null:
		_fail("instantiate failed for %s" % mat_id)
		return null
	var holder := Node3D.new()
	holder.name = "Material_%s_%s" % [source, mat_id]
	holder.set_meta("material_id", mat_id)
	holder.set_meta("item_tag", "material")
	holder.set_meta("spawn_source", source)
	parent.add_child(holder)
	holder.global_position = world_pos + MATERIAL_MODELS.get_spawn_offset(mat_id)
	if wall_dir != Vector3.ZERO and MATERIAL_MODELS.should_align_to_wall(mat_id):
		holder.rotation.y = atan2(wall_dir.x, wall_dir.z)
	holder.add_child(visual)
	visual.position = MATERIAL_MODELS.get_visual_offset(mat_id)
	visual.rotation_degrees = MATERIAL_MODELS.get_visual_rotation_degrees(mat_id)
	return holder


func _capture_elevated_overview() -> String:
	# Hide ceilings so floor-scattered materials remain readable from above.
	_set_ceiling_visible(false)
	var span_x: float = float(_layout.width) * _layout.tile_size if _layout != null else 40.0
	var span_z: float = float(_layout.height) * _layout.tile_size if _layout != null else 40.0
	var center := _gallery_center()
	if center == Vector3.ZERO:
		center = Vector3(0.0, 0.2, 0.0)
	center.y = 0.2
	var span := maxf(span_x, span_z)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.far = 260.0
	_camera.global_position = center + Vector3(span * 0.08, maxf(span * 0.28, 12.0), span * 0.18)
	_camera.look_at(center, Vector3.UP)
	_camera.current = true
	get_window().size = IMAGE_SIZE
	await _settle_frames(18)
	var out_path := "%s/dungeon_procedural_materials_overview.png" % OUTPUT_DIR
	var ok := _save_current_viewport(out_path)
	_set_ceiling_visible(true)
	return out_path if ok else ""


func _capture_eyelevel() -> String:
	var focus_pos: Vector3 = _gallery_center()
	if focus_pos == Vector3.ZERO:
		var focus := _pick_focus_material()
		focus_pos = focus.global_position if focus != null else _layout.calc_player_spawn_pos()
	focus_pos.y = 0.15
	var eye: Vector3 = focus_pos + Vector3(-2.4, 1.55, 3.2)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 60.0
	_camera.near = 0.05
	_camera.far = 120.0
	_camera.global_position = eye
	_camera.look_at(focus_pos + Vector3(0.0, 0.25, 0.0), Vector3.UP)
	_camera.current = true
	get_window().size = IMAGE_SIZE
	await _settle_frames(16)
	var out_path := "%s/dungeon_procedural_materials_eyelevel.png" % OUTPUT_DIR
	return out_path if _save_current_viewport(out_path) else ""


func _capture_gallery() -> String:
	if _spawned_gallery.is_empty():
		_fail("no gallery materials to capture")
		return ""
	var center := _gallery_center()
	center.y = 0.2
	_set_ceiling_visible(false)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 48.0
	_camera.near = 0.05
	_camera.far = 120.0
	_camera.global_position = center + Vector3(3.2, 4.8, 5.4)
	_camera.look_at(center, Vector3.UP)
	_camera.current = true
	get_window().size = IMAGE_SIZE
	await _settle_frames(16)
	var out_path := "%s/dungeon_procedural_materials_gallery.png" % OUTPUT_DIR
	var ok := _save_current_viewport(out_path)
	_set_ceiling_visible(true)
	return out_path if ok else ""


func _capture_insitu_closeup(item: Node3D, mat_id: String) -> String:
	var bounds := _global_bounds(item)
	var center := bounds.get_center()
	if bounds.size.length_squared() < 0.0001:
		center = item.global_position + Vector3(0, 0.12, 0)
		bounds = AABB(center - Vector3(0.12, 0.12, 0.12), Vector3(0.24, 0.24, 0.24))
	var distance := maxf(bounds.size.length() * 2.6, 0.65)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 42.0
	_camera.near = 0.05
	_camera.far = 80.0
	_camera.global_position = center + Vector3(0.58, 0.48, 0.88).normalized() * distance
	_camera.look_at(center, Vector3.UP)
	_camera.current = true
	get_window().size = CLOSE_SIZE
	await _settle_frames(12)
	var out_path := "%s/dungeon_procedural_material_%s_insitu.png" % [OUTPUT_DIR, mat_id]
	var ok := _save_current_viewport(out_path)
	get_window().size = IMAGE_SIZE
	return out_path if ok else ""


func _find_planned_decor(decor_kind: String) -> Node3D:
	if _build_result == null or _build_result.decor_root == null:
		return null
	for node in _build_result.decor_root.get_children():
		if node is Node3D and bool(node.get_meta("planned_decor", false)) and String(node.get_meta("decor_kind", "")) == decor_kind:
			return node as Node3D
	return null


func _find_spawned(mat_id: String) -> Node3D:
	for node in _spawned_natural:
		if String(node.get_meta("material_id", "")) == mat_id:
			return node
	for node in _spawned_gallery:
		if String(node.get_meta("material_id", "")) == mat_id:
			return node
	return null


func _pick_focus_material() -> Node3D:
	if not _spawned_natural.is_empty():
		return _spawned_natural[0]
	if not _spawned_gallery.is_empty():
		return _spawned_gallery[0]
	return null


func _pick_gallery_room() -> Rect2i:
	if _layout == null:
		return Rect2i()
	var best: Rect2i = Rect2i()
	var best_area := -1
	for room in _layout.rooms:
		var rect: Rect2i = room
		if _layout.is_start_room_cell(rect.position):
			continue
		if _layout.room_roles.has("start") and rect == _layout.room_roles["start"]:
			continue
		var area := rect.size.x * rect.size.y
		if area > best_area:
			best_area = area
			best = rect
	if best_area > 0:
		return best
	if _layout.room_roles.has("start"):
		return _layout.room_roles["start"]
	if not _layout.rooms.is_empty():
		return _layout.rooms[0]
	return Rect2i()


func _collect_room_floor_cells(room: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if _layout == null or room.size == Vector2i.ZERO:
		return cells
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			var cell := Vector2i(x, y)
			if _layout.is_floor_cell(cell):
				cells.append(cell)
	return cells


func _layout_offset() -> Vector3:
	if _layout == null:
		return Vector3.ZERO
	var offset_x: float = -(float(_layout.width) * _layout.tile_size) / 2.0
	var offset_z: float = -(float(_layout.height) * _layout.tile_size) / 2.0
	return Vector3(offset_x, 0.0, offset_z)


func _position_for_material(mat_id: String, cell_pos: Vector3, wall_direction: Vector3) -> Vector3:
	var preference := MATERIAL_MODELS.get_location_preference(mat_id)
	if preference == "near_wall" and wall_direction != Vector3.ZERO:
		var wall_offset := minf(_layout.tile_size * 0.36, 1.1)
		var tangent := Vector3(-wall_direction.z, 0.0, wall_direction.x)
		return cell_pos + wall_direction * wall_offset + tangent * 0.1
	return cell_pos


func _find_wall_direction(cell: Vector2i) -> Vector3:
	if _layout == null or _layout.grid.is_empty():
		return Vector3.ZERO
	var candidates := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for direction in candidates:
		var nx: int = cell.x + direction.x
		var ny: int = cell.y + direction.y
		if ny < 0 or ny >= _layout.grid.size():
			continue
		if nx < 0 or nx >= _layout.grid[ny].size():
			continue
		if int(_layout.grid[ny][nx]) == 2:
			return Vector3(direction.x, 0.0, direction.y).normalized()
	return Vector3.ZERO


func _set_ceiling_visible(visible: bool) -> void:
	if _dungeon == null:
		return
	for node in _walk(_dungeon):
		var name_l := String(node.name).to_lower()
		if node is MultiMeshInstance3D and (name_l.contains("ceiling") or name_l.contains("lintel")):
			(node as Node3D).visible = visible


func _gallery_center() -> Vector3:
	if _spawned_gallery.is_empty():
		return Vector3.ZERO
	var acc := Vector3.ZERO
	for node in _spawned_gallery:
		acc += node.global_position
	return acc / float(_spawned_gallery.size())


func _force_capture_visibility(root: Node) -> void:
	for node in _walk(root):
		if node is Node3D:
			(node as Node3D).visible = true
		if node is GeometryInstance3D:
			var gi := node as GeometryInstance3D
			gi.visibility_range_begin = 0.0
			gi.visibility_range_end = 0.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if node is Light3D:
			(node as Light3D).visible = true


func _settle_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
	RenderingServer.force_draw()


func _save_current_viewport(res_path: String) -> bool:
	var tex := get_viewport().get_texture()
	if tex == null:
		_fail("viewport texture null for %s" % res_path)
		return false
	var img := tex.get_image()
	if img == null:
		var rid := tex.get_rid()
		if rid.is_valid():
			img = RenderingServer.texture_2d_get(rid)
	if img == null:
		_fail("viewport image null for %s" % res_path)
		return false
	var lit := 0
	var step_x := maxi(1, img.get_width() / 36)
	var step_y := maxi(1, img.get_height() / 36)
	for y in range(0, img.get_height(), step_y):
		for x in range(0, img.get_width(), step_x):
			var c := img.get_pixel(x, y)
			if c.a > 0.05 and (c.r + c.g + c.b) > 0.10:
				lit += 1
	if lit < 18:
		_fail("capture mostly blank: %s lit=%d" % [res_path, lit])
		return false
	var err := img.save_png(res_path)
	if err != OK:
		_fail("save_png failed (%d): %s" % [err, res_path])
		return false
	return true


func _global_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var has := false
	if node is VisualInstance3D:
		bounds = (node as VisualInstance3D).global_transform * (node as VisualInstance3D).get_aabb()
		has = true
	for child in node.get_children():
		var child_bounds := _global_bounds(child)
		if child_bounds.size.length_squared() <= 0.0:
			continue
		if has:
			bounds = bounds.merge(child_bounds)
		else:
			bounds = child_bounds
			has = true
	return bounds if has else AABB()


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		out.append(current)
		for child in current.get_children():
			stack.append(child)
	return out


func _parse_ids() -> Array[String]:
	var args := OS.get_cmdline_user_args()
	var selected: Array[String] = []
	for arg in args:
		if String(arg).begins_with("--ids="):
			for part in String(arg).substr(6).split(",", false):
				var id := String(part).strip_edges()
				if not id.is_empty():
					selected.append(id)
	if selected.is_empty():
		for id in ROSTER_IDS:
			selected.append(String(id))
	return selected


func _get_int_arg(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with(prefix):
			var raw := text.substr(prefix.length()).strip_edges()
			if raw.is_valid_int():
				return int(raw)
	return fallback


func _has_flag(flag: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if String(arg) == flag:
			return true
	return false


func _fail(message: String) -> void:
	_had_error = true
	push_error("[DungeonProceduralMaterialCapture] %s" % message)
