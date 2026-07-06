extends SceneTree

const OUTPUT_DIR := "res://reports/props_preview"
const IMAGE_SIZE := Vector2i(512, 512)
const MARGIN := 36
const BG := Color(0.08, 0.085, 0.09, 1.0)
const GRID := Color(0.16, 0.16, 0.17, 1.0)
const OUTLINE := Color(0.02, 0.02, 0.025, 1.0)
const SCENES := {
	"table": "res://scenes/props/decor/table.tscn",
	"chair": "res://scenes/props/decor/chair.tscn",
	"bench": "res://scenes/props/decor/bench.tscn",
	"lit_candles": "res://scenes/props/decor/lit_candles.tscn",
	"fireplace": "res://scenes/props/decor/fireplace.tscn",
	"torch": "res://scenes/props/torch/torch.tscn",
	"barrel": "res://scenes/props/barrel/barrel.tscn",
	"chest": "res://scenes/props/chest/chest.tscn",
	"boss_chest": "res://scenes/props/chest/boss_chest.tscn",
}

var _had_error := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for item_id in SCENES.keys():
		await _capture_scene(item_id, SCENES[item_id])

	if _had_error:
		quit(1)
		return
	print("[VoxelPropThreeView] done -> %s" % OUTPUT_DIR)
	quit(0)


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


func _voxel_boxes(root_node: Node) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	for mesh_instance in _collect_meshes(root_node):
		var box := mesh_instance.mesh as BoxMesh
		if box == null:
			continue
		var aabb := mesh_instance.get_aabb()
		var min_v := (mesh_instance.global_position + aabb.position) * 32.0
		var max_v := (mesh_instance.global_position + aabb.position + aabb.size) * 32.0
		boxes.append({
			"name": String(mesh_instance.name),
			"min": Vector3(roundf(min_v.x), roundf(min_v.y), roundf(min_v.z)),
			"max": Vector3(roundf(max_v.x), roundf(max_v.y), roundf(max_v.z)),
			"color": _box_color(String(mesh_instance.name)),
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
		return _depth_value(a, view_name) < _depth_value(b, view_name)
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
