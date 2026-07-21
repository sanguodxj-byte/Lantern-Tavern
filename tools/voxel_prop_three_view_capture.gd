extends SceneTree

const OUTPUT_DIR := "res://reports/props_preview"
const IMAGE_SIZE := Vector2i(256, 256)
const MARGIN := 36
const BG := Color(0.08, 0.085, 0.09, 1.0)
const GRID := Color(0.16, 0.16, 0.17, 1.0)
const OUTLINE := Color(0.02, 0.02, 0.025, 1.0)
const SCENES := {
	"tutorial_cart_wreck": "res://assets/models/environment/environment_tutorial_cart_wreck.glb",
	"tutorial_forest_cluster": "res://assets/models/environment/environment_tutorial_forest_cluster.glb",
	"tutorial_entrance_ruins": "res://assets/models/environment/environment_tutorial_entrance_ruins.glb",
	"tutorial_road_blocker": "res://assets/models/environment/environment_tutorial_road_blocker.glb",
	"tutorial_road_tile": "res://scenes/environment/tutorial/voxel_road_tile.tscn",
	"tutorial_road_shoulder": "res://scenes/environment/tutorial/voxel_road_shoulder.tscn",
	"tutorial_boulder": "res://scenes/environment/tutorial/voxel_boulder.tscn",
	"table": "res://scenes/props/decor/table.tscn",
	"chair": "res://scenes/props/decor/chair.tscn",
	"bench": "res://scenes/props/decor/bench.tscn",
	"lit_candles": "res://scenes/props/decor/lit_candles.tscn",
	"tankard": "res://scenes/props/decor/tankard.tscn",
	"goblet": "res://scenes/props/decor/goblet.tscn",
	"bottle_set": "res://scenes/props/decor/bottle_set.tscn",
	"wall_notice": "res://scenes/props/decor/wall_notice.tscn",
	"chandelier": "res://scenes/props/decor/chandelier.tscn",
	"wall_lantern": "res://scenes/props/decor/wall_lantern.tscn",
	"fireplace": "res://scenes/props/decor/fireplace.tscn",
	"torch": "res://scenes/props/torch/torch.tscn",
	"barrel": "res://scenes/props/barrel/barrel.tscn",
	"chest": "res://scenes/props/chest/chest.tscn",
	"boss_chest": "res://scenes/props/chest/boss_chest.tscn",
	"weapon_rack": "res://scenes/props/decor/weapon_rack.tscn",
}

const WEAPON_SCENES := {
	"shortsword": "res://assets/meshes/weapons/weapons_voxel_shortsword.glb",
	"greatsword": "res://assets/meshes/weapons/weapons_voxel_greatsword.glb",
	"axe": "res://assets/meshes/weapons/weapons_voxel_axe.glb",
	"warhammer": "res://assets/meshes/weapons/weapons_voxel_warhammer.glb",
	"spear": "res://assets/meshes/weapons/weapons_voxel_spear.glb",
	"dagger": "res://assets/meshes/weapons/weapons_voxel_dagger.glb",
	"longbow": "res://assets/meshes/weapons/weapons_voxel_longbow.glb",
	"crossbow": "res://assets/meshes/weapons/weapons_voxel_crossbow.glb",
	"staff": "res://assets/meshes/weapons/weapons_voxel_staff.glb",
	"grimoire": "res://assets/meshes/weapons/weapons_voxel_grimoire.glb",
	"shield": "res://assets/meshes/weapons/weapons_voxel_shield.glb",
	"sword": "res://assets/meshes/weapons/weapons_voxel_sword.glb",
}

const MONSTER_SCENES := {
	"orc_raider": "res://assets/meshes/characters/voxel_orc_raider_48px.glb",
	"dragon": "res://assets/meshes/characters/voxel_dragon_256px.glb",
	"rock_golem": "res://assets/meshes/characters/voxel_rock_golem_80px.glb",
	"goblin": "res://assets/meshes/characters/voxel_goblin_32px.glb",
	"skeleton": "res://assets/meshes/characters/voxel_skeleton_48px.glb",
	"troll": "res://assets/meshes/characters/voxel_troll_64x.glb",
	"player": "res://assets/meshes/characters/voxel_player_54px.glb",
	"minotaur": "res://assets/meshes/characters/voxel_minotaur_72px.glb",
	"slime": "res://assets/meshes/characters/voxel_slime_24px.glb",
	"spider": "res://assets/meshes/characters/voxel_spider_30px.glb",
	"drow_blade": "res://assets/meshes/characters/voxel_drow_blade_48px.glb",
	"plague_doctor": "res://assets/meshes/characters/voxel_plague_doctor_64px.glb",
	"cultist_pyromancer": "res://assets/meshes/characters/voxel_cultist_pyromancer_64px.glb",
	"bandit_crossbowman": "res://assets/meshes/characters/voxel_bandit_crossbowman_56px.glb",
	"duergar_miner": "res://assets/meshes/characters/voxel_duergar_miner_48px.glb",
	"kobold": "res://assets/meshes/characters/voxel_kobold_42px.glb",
	"zombie": "res://assets/meshes/characters/voxel_zombie_56px.glb",
}

var _had_error := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var user_args := OS.get_cmdline_user_args()
	var requested_asset := _requested_asset(user_args)
	if _had_error:
		quit(1)
		return
	if not requested_asset.is_empty():
		if MONSTER_SCENES.has(requested_asset):
			await _capture_monster(requested_asset)
		elif WEAPON_SCENES.has(requested_asset):
			await _capture_scene(requested_asset, String(WEAPON_SCENES[requested_asset]))
		else:
			await _capture_scene(requested_asset, String(SCENES[requested_asset]))
		_finish()
		return
	if user_args.has("--tutorial-only"):
		for item_id in SCENES.keys():
			if item_id.begins_with("tutorial_"):
				await _capture_scene(item_id, SCENES[item_id])
	else:
		for item_id in SCENES.keys():
			await _capture_scene(item_id, SCENES[item_id])

	_finish()


func _finish() -> void:
	if _had_error:
		quit(1)
		return
	print("[VoxelPropThreeView] done -> %s" % OUTPUT_DIR)
	quit(0)


func _requested_asset(user_args: PackedStringArray) -> String:
	var selected := ""
	var tutorial_only := false
	for arg in user_args:
		if arg == "--tutorial-only":
			tutorial_only = true
			continue
		if not arg.begins_with("--asset="):
			_fail("[VoxelPropThreeView] unsupported selector; model capture requires exactly one --asset=<model_id>")
			return ""
		var candidate := arg.trim_prefix("--asset=").strip_edges()
		if candidate.is_empty() or not selected.is_empty():
			_fail("[VoxelPropThreeView] --asset requires exactly one model id")
			return ""
		selected = candidate
	if tutorial_only and not selected.is_empty():
		_fail("[VoxelPropThreeView] --tutorial-only cannot be combined with --asset")
		return ""
	if not selected.is_empty() \
			and not MONSTER_SCENES.has(selected) \
			and not WEAPON_SCENES.has(selected) \
			and not SCENES.has(selected):
		_fail("[VoxelPropThreeView] unknown asset: %s" % selected)
		return ""
	return selected


func _capture_scene(item_id: String, scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("[VoxelPropThreeView] missing scene: %s" % scene_path)
		return

	var inst := packed.instantiate() as Node3D
	if inst == null:
		_fail("[VoxelPropThreeView] scene root is not Node3D: %s" % scene_path)
		return

	root.add_child(inst)
	await process_frame
	await process_frame

	var boxes := _voxel_boxes(inst)
	if boxes.is_empty():
		_fail("[VoxelPropThreeView] empty model: %s" % scene_path)
		inst.queue_free()
		return
	for view_name in ["front", "side", "top"]:
		var image := _draw_projection(boxes, view_name)
		var output_path := "%s/%s_%s.png" % [OUTPUT_DIR, item_id, view_name]
		var err := image.save_png(output_path)
		if err != OK:
			_fail("[VoxelPropThreeView] failed to save %s err=%d" % [output_path, err])
		else:
			print("[VoxelPropThreeView] saved %s boxes=%d" % [output_path, boxes.size()])

	inst.queue_free()
	await process_frame

func _capture_monster(monster_id: String) -> void:
	var scene_path: String = String(MONSTER_SCENES.get(monster_id, ""))
	if scene_path.is_empty():
		_fail("[VoxelPropThreeView] unknown monster id: %s" % monster_id)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("[VoxelPropThreeView] missing monster rig: %s" % monster_id)
		return
	var inst := packed.instantiate() as Node3D
	root.add_child(inst)
	await process_frame
	var boxes := _voxel_boxes(inst)
	if boxes.is_empty():
		_fail("[VoxelPropThreeView] empty monster: %s" % monster_id)
	else:
		for view_name in ["front", "side", "top"]:
			var image := _draw_projection(boxes, view_name)
			var err := image.save_png("res://reports/characters_preview/voxel_%s_%s.png" % [monster_id, view_name])
			if err != OK: _fail("[VoxelPropThreeView] failed monster screenshot: %s" % monster_id)
	inst.queue_free()
	await process_frame


func _voxel_boxes(root_node: Node) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	for mesh_instance in _collect_meshes(root_node):
		if mesh_instance.mesh == null:
			continue
		var aabb := mesh_instance.get_aabb()
		var min_v := (mesh_instance.global_position + aabb.position) * 32.0
		var max_v := (mesh_instance.global_position + aabb.position + aabb.size) * 32.0
		var color := Color(0.58, 0.34, 0.16, 1.0)
		var active_mat = mesh_instance.get_active_material(0)
		if active_mat is BaseMaterial3D:
			color = active_mat.albedo_color
		else:
			color = _box_color(String(mesh_instance.name))
		boxes.append({
			"name": String(mesh_instance.name),
			"min": Vector3(roundf(min_v.x), roundf(min_v.y), roundf(min_v.z)),
			"max": Vector3(roundf(max_v.x), roundf(max_v.y), roundf(max_v.z)),
			"color": color,
		})
	return boxes


func _draw_projection(boxes: Array[Dictionary], view_name: String) -> Image:
	var bounds := _projected_bounds(boxes, view_name)
	var span_x := maxf(bounds.size.x, 1.0)
	var span_y := maxf(bounds.size.y, 1.0)
	var scale := minf(
		float(IMAGE_SIZE.x - MARGIN * 2) / span_x,
		float(IMAGE_SIZE.y - MARGIN * 2) / span_y
	)

	var image := Image.create(IMAGE_SIZE.x, IMAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(BG)
	_draw_grid(image)

	var sorted := boxes.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _draw_order_value(a, view_name) < _draw_order_value(b, view_name)
	)
	for box in sorted:
		var rect := _project_box(box, view_name, bounds.position, scale)
		_fill_rect(image, rect.grow(1), OUTLINE)
		_fill_rect(image, rect, box["color"])
	return image


func _projected_bounds(boxes: Array[Dictionary], view_name: String) -> Rect2:
	var initialized := false
	var min_p := Vector2.ZERO
	var max_p := Vector2.ZERO
	for box in boxes:
		var p0 := _project_point(box["min"], view_name)
		var p1 := _project_point(box["max"], view_name)
		var a := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y))
		var b := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y))
		if not initialized:
			min_p = a
			max_p = b
			initialized = true
		else:
			min_p = Vector2(minf(min_p.x, a.x), minf(min_p.y, a.y))
			max_p = Vector2(maxf(max_p.x, b.x), maxf(max_p.y, b.y))
	return Rect2(min_p, max_p - min_p)


func _project_box(box: Dictionary, view_name: String, origin: Vector2, scale: float) -> Rect2i:
	var p0 := _project_point(box["min"], view_name)
	var p1 := _project_point(box["max"], view_name)
	var a := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y))
	var b := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y))
	var x := MARGIN + int(roundf((a.x - origin.x) * scale))
	var y := IMAGE_SIZE.y - MARGIN - int(roundf((b.y - origin.y) * scale))
	var w := maxi(1, int(roundf((b.x - a.x) * scale)))
	var h := maxi(1, int(roundf((b.y - a.y) * scale)))
	return Rect2i(x, y, w, h)


func _project_point(point: Vector3, view_name: String) -> Vector2:
	match view_name:
		"front":
			return Vector2(point.x, point.y)
		"side":
			return Vector2(point.z, point.y)
		"top":
			return Vector2(point.x, point.z)
		_:
			return Vector2(point.x, point.y)


func _depth_value(box: Dictionary, view_name: String) -> float:
	var min_v: Vector3 = box["min"]
	var max_v: Vector3 = box["max"]
	match view_name:
		"front":
			return (min_v.z + max_v.z) * 0.5
		"side":
			return (min_v.x + max_v.x) * 0.5
		"top":
			return (min_v.y + max_v.y) * 0.5
		_:
			return 0.0


func _draw_order_value(box: Dictionary, view_name: String) -> float:
	var depth := _depth_value(box, view_name)
	if view_name == "front":
		return -depth
	return depth


func _draw_grid(image: Image) -> void:
	for p in range(MARGIN, IMAGE_SIZE.x - MARGIN + 1, 32):
		_fill_rect(image, Rect2i(p, MARGIN, 1, IMAGE_SIZE.y - MARGIN * 2), GRID)
	for p in range(MARGIN, IMAGE_SIZE.y - MARGIN + 1, 32):
		_fill_rect(image, Rect2i(MARGIN, p, IMAGE_SIZE.x - MARGIN * 2, 1), GRID)


func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for py in range(rect.position.y, rect.position.y + rect.size.y):
		for px in range(rect.position.x, rect.position.x + rect.size.x):
			if px >= 0 and py >= 0 and px < image.get_width() and py < image.get_height():
				image.set_pixel(px, py, color)


func _collect_meshes(root_node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root_node is MeshInstance3D:
		result.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		result.append_array(_collect_meshes(child))
	return result


func _box_color(name: String) -> Color:
	if name.contains("Iron") or name.contains("Plate") or name.contains("Cup") or name.contains("Band") or name.contains("Wrap") or name.contains("Arm"):
		return Color(0.34, 0.36, 0.37, 1.0)
	if name.contains("Candle"):
		return Color(0.82, 0.72, 0.48, 1.0)
	if name.contains("Stone") or name.contains("Hearth") or name.contains("Jamb") or name.contains("Mantel"):
		return Color(0.45, 0.45, 0.42, 1.0)
	if name.contains("Log") or name.contains("Wood") or name.contains("Handle"):
		return Color(0.45, 0.24, 0.11, 1.0)
	if name.contains("Leg") or name.contains("Rail") or name.contains("Apron"):
		return Color(0.38, 0.20, 0.10, 1.0)
	return Color(0.58, 0.34, 0.16, 1.0)


func _fail(message: String) -> void:
	_had_error = true
	push_error(message)
