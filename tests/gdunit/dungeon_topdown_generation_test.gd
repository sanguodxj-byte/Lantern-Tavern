extends GdUnitTestSuite

var dungeon: ProceduralDungeon = null

func before() -> void:
	load("res://scenes/expedition/dungeon_rendering_config.gd")
	var spawner: Node = Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")
	if spawner != null:
		spawner.set("use_mock_nodes", true)

func after() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")
	if spawner != null:
		spawner.set("use_mock_nodes", false)
	if is_instance_valid(dungeon):
		if dungeon.get_parent() != null:
			dungeon.get_parent().remove_child(dungeon)
		dungeon.free()
		dungeon = null


const OUTPUT_PATH := "res://reports/dungeon_topdown_generation_test.png"
const CELL_PX := 8
const LEGEND_WIDTH := 72
const MARGIN := 2

const COLOR_EMPTY := Color(0.02, 0.02, 0.025, 1.0)
const COLOR_FLOOR := Color(0.38, 0.38, 0.36, 1.0)
const COLOR_WALL := Color(0.12, 0.12, 0.14, 1.0)
const COLOR_LOOT_CELL := Color(0.38, 0.28, 0.13, 1.0)
const COLOR_RESOURCE_CELL := Color(0.18, 0.28, 0.16, 1.0)
const COLOR_PILLAR := Color(0.22, 0.22, 0.24, 1.0)
const COLOR_PLAYER := Color(0.10, 0.95, 0.25, 1.0)
const COLOR_ENEMY := Color(0.95, 0.10, 0.10, 1.0)
const COLOR_PICKABLE := Color(1.0, 0.86, 0.14, 1.0)
const COLOR_MATERIAL := Color(0.18, 0.80, 0.32, 1.0)
const COLOR_CONTAINER := Color(0.95, 0.48, 0.08, 1.0)
const COLOR_EXTRACTION := Color(0.0, 0.95, 0.85, 1.0)
const COLOR_STAIRS := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_HAZARD := Color(0.95, 0.0, 0.95, 1.0)
const COLOR_TERRAIN_FEATURE := Color(0.55, 0.36, 0.18, 1.0)
const COLOR_TAGGED_ITEM := Color(0.05, 0.20, 1.0, 1.0)


func test_generated_dungeon_topdown_map_includes_monsters_and_items() -> void:
	seed(94021)
	var dungeon_scene := load("res://scenes/expedition/procedural_dungeon.tscn") as PackedScene
	dungeon = dungeon_scene.instantiate() as ProceduralDungeon
	dungeon.dungeon_zone = 0
	add_child(dungeon)
	await await_idle_frame()
	await await_idle_frame()

	var grid: Array = dungeon.layout.grid
	assert_bool(grid.is_empty()) \
		.override_failure_message("地牢网格为空，无法生成俯视测试图") \
		.is_false()

	var markers := _collect_topdown_markers(dungeon)
	var enemy_count := _count_markers(markers, "enemy")
	var item_count := _count_item_markers(markers)
	var material_count := _count_markers(markers, "material")
	var extraction_count := _count_markers(markers, "extraction")
	var stairs_count := _count_markers(markers, "stairs")
	var hazard_count := _count_markers(markers, "hazard")
	var terrain_feature_count := _count_markers(markers, "terrain_feature")
	assert_int(enemy_count) \
		.override_failure_message("俯视测试图需要包含生成后的怪物") \
		.is_greater_equal(4)
	assert_int(item_count) \
		.override_failure_message("俯视测试图需要包含生成后的物品/容器/宝箱") \
		.is_greater_equal(1)
	assert_int(material_count) \
		.override_failure_message("素材生成过多，应只比敌人略多: materials=%d enemies=%d" % [material_count, enemy_count]) \
		.is_less_equal(enemy_count + 5)
	assert_int(stairs_count) \
		.override_failure_message("俯视测试图必须包含下层台阶 DownstairsPortal") \
		.is_greater_equal(1)
	assert_int(hazard_count) \
		.override_failure_message("俯视测试图必须包含伤害地形/陷阱") \
		.is_greater_equal(8)
	assert_int(terrain_feature_count) \
		.override_failure_message("大房间需要生成额外地形特征，避免空旷") \
		.is_greater_equal(4)
	assert_int(_unique_hazard_node_names(markers).size()) \
		.override_failure_message("陷阱类型过少，需要至少两类陷阱") \
		.is_greater_equal(2)

	assert_bool(dungeon.layout.room_roles.has("stairs")).is_true()
	var stairs_cell := _first_marker_cell(markers, "stairs")
	assert_bool(_room_contains_cell(dungeon.layout.room_roles["stairs"], stairs_cell)).is_true()
	if dungeon.layout.room_roles.has("extraction"):
		assert_int(extraction_count) \
			.override_failure_message("抽中撤离点时，俯视图必须包含 ExtractionPortal") \
			.is_greater_equal(1)
		var extraction_cell := _first_marker_cell(markers, "extraction")
		assert_bool(_room_contains_cell(dungeon.layout.room_roles["extraction"], extraction_cell)).is_true()
		assert_bool(dungeon.layout.room_roles["extraction"] == dungeon.layout.room_roles["boss"]) \
			.override_failure_message("撤离点必须位于末端 Boss 房间") \
			.is_true()
	else:
		assert_int(extraction_count) \
			.override_failure_message("未抽中撤离点的楼层不应生成 ExtractionPortal") \
			.is_equal(0)
	_assert_trap_placement_semantics(dungeon)

	for marker in markers:
		var cell: Vector2i = marker["cell"]
		assert_bool(_is_cell_near_walkable(grid, cell, 1)) \
			.override_failure_message("俯视标记落在不可达区域附近之外: %s at %s" % [marker["kind"], cell]) \
			.is_true()
		if String(marker["kind"]) == "hazard" and dungeon.layout.room_roles.has("start"):
			assert_bool(_room_contains_cell(dungeon.layout.room_roles["start"], cell)) \
				.override_failure_message("伤害地形/陷阱不应生成在出生房间: %s" % cell) \
				.is_false()

	for room in _large_non_start_rooms(dungeon):
		var room_density := _count_markers_in_room(markers, room, ["hazard", "terrain_feature"])
		assert_int(room_density) \
			.override_failure_message("大房间仍然过于空旷，需要至少 2 个地形/陷阱锚点: %s count=%d" % [room, room_density]) \
			.is_greater_equal(2)

	var image := _render_topdown_image(grid, dungeon.layout.heights, markers)
	_ensure_reports_dir()
	var err := image.save_png(OUTPUT_PATH)
	assert_int(err) \
		.override_failure_message("无法保存地牢俯视测试图: %s" % OUTPUT_PATH) \
		.is_equal(OK)
	print("[DungeonTopdown] saved=%s enemies=%d items=%d materials=%d hazards=%d terrain=%d extraction=%d stairs=%d markers=%d" % [OUTPUT_PATH, enemy_count, item_count, material_count, hazard_count, terrain_feature_count, extraction_count, stairs_count, markers.size()])


func _collect_topdown_markers(dungeon: ProceduralDungeon) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	_collect_topdown_markers_recursive(dungeon, dungeon, markers)
	return markers


func _collect_topdown_markers_recursive(node: Node, dungeon: ProceduralDungeon, markers: Array[Dictionary]) -> void:
	if node is Player:
		_append_marker(markers, dungeon, node as Node3D, "player")
	elif node is Enemy or node.has_meta("enemy_type"):
		_append_marker(markers, dungeon, node as Node3D, "enemy")
	elif node.has_meta("item_tag") and node is Node3D:
		var tag := String(node.get_meta("item_tag"))
		if tag == "material":
			_append_marker(markers, dungeon, node as Node3D, "material")
		elif tag == "container" or tag == "treasure":
			_append_marker(markers, dungeon, node as Node3D, "container")
		else:
			_append_marker(markers, dungeon, node as Node3D, "tagged_item")
	elif node is PickableItem:
		_append_marker(markers, dungeon, node as Node3D, "pickable")
	elif node is Chest:
		_append_marker(markers, dungeon, node as Node3D, "container")
	elif _is_hazard_node(node):
		_append_marker(markers, dungeon, node as Node3D, "hazard")
	elif _is_extraction_portal_node(node):
		_append_marker(markers, dungeon, node as Node3D, "extraction")
	elif _is_stairs_node(node):
		_append_marker(markers, dungeon, node as Node3D, "stairs")
	elif _is_terrain_feature_node(node):
		_append_marker(markers, dungeon, node as Node3D, "terrain_feature")
	for child in node.get_children():
		_collect_topdown_markers_recursive(child, dungeon, markers)


func _append_marker(markers: Array[Dictionary], dungeon: ProceduralDungeon, node: Node3D, kind: String) -> void:
	markers.append({
		"kind": kind,
		"cell": _world_to_grid_cell(dungeon, node.global_position),
		"name": String(node.name),
	})


func _world_to_grid_cell(dungeon: ProceduralDungeon, world_pos: Vector3) -> Vector2i:
	var grid: Array = dungeon.layout.grid
	var grid_width := int(grid[0].size()) if not grid.is_empty() else 0
	var grid_height := int(grid.size())
	var offset_x := -(float(grid_width) * ProceduralDungeon.TILE_SIZE) / 2.0
	var offset_z := -(float(grid_height) * ProceduralDungeon.TILE_SIZE) / 2.0
	return Vector2i(
		roundi((world_pos.x - offset_x) / ProceduralDungeon.TILE_SIZE),
		roundi((world_pos.z - offset_z) / ProceduralDungeon.TILE_SIZE)
	)


func _render_topdown_image(grid: Array, heights: Array, markers: Array[Dictionary]) -> Image:
	var grid_width := int(grid[0].size())
	var grid_height := int(grid.size())
	var image_width := MARGIN * 2 + grid_width * CELL_PX + LEGEND_WIDTH
	var image_height := MARGIN * 2 + grid_height * CELL_PX
	var image := Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)
	image.fill(COLOR_EMPTY)

	for y in range(grid_height):
		for x in range(grid_width):
			var height := float(heights[y][x]) if y < heights.size() and x < heights[y].size() else 3.0
			_fill_cell(image, Vector2i(x, y), _cell_color(int(grid[y][x]), height))

	var sorted_markers := markers.duplicate()
	sorted_markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _marker_priority(String(a["kind"])) < _marker_priority(String(b["kind"]))
	)
	for marker in sorted_markers:
		_draw_marker(image, marker["cell"], _marker_color(String(marker["kind"])))

	_draw_legend(image, grid_width)
	return image


func _cell_color(cell_type: int, height: float = 3.0) -> Color:
	var height_t := clampf((height - 3.0) / 2.2, 0.0, 1.0)
	match cell_type:
		BSP_DungeonGenerator.TileType.EMPTY:
			return COLOR_EMPTY
		BSP_DungeonGenerator.TileType.FLOOR:
			return COLOR_FLOOR.lerp(Color(0.55, 0.53, 0.48, 1.0), height_t)
		BSP_DungeonGenerator.TileType.WALL:
			return COLOR_WALL
		BSP_DungeonGenerator.TileType.LOOT:
			return COLOR_LOOT_CELL.lerp(Color(0.60, 0.43, 0.18, 1.0), height_t)
		BSP_DungeonGenerator.TileType.RESOURCE:
			return COLOR_RESOURCE_CELL.lerp(Color(0.28, 0.42, 0.22, 1.0), height_t)
		BSP_DungeonGenerator.TileType.PILLAR:
			return COLOR_PILLAR
		_:
			return COLOR_FLOOR


func _marker_color(kind: String) -> Color:
	match kind:
		"player":
			return COLOR_PLAYER
		"enemy":
			return COLOR_ENEMY
		"pickable":
			return COLOR_PICKABLE
		"material":
			return COLOR_MATERIAL
		"container":
			return COLOR_CONTAINER
		"extraction":
			return COLOR_EXTRACTION
		"stairs":
			return COLOR_STAIRS
		"hazard":
			return COLOR_HAZARD
		"terrain_feature":
			return COLOR_TERRAIN_FEATURE
		_:
			return COLOR_TAGGED_ITEM


func _fill_cell(image: Image, cell: Vector2i, color: Color) -> void:
	var start := Vector2i(MARGIN + cell.x * CELL_PX, MARGIN + cell.y * CELL_PX)
	for py in range(start.y, start.y + CELL_PX):
		for px in range(start.x, start.x + CELL_PX):
			image.set_pixel(px, py, color)


func _draw_marker(image: Image, cell: Vector2i, color: Color) -> void:
	var center := Vector2i(MARGIN + cell.x * CELL_PX + CELL_PX / 2, MARGIN + cell.y * CELL_PX + CELL_PX / 2)
	var radius: int = maxi(2, CELL_PX / 2)
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if Vector2(x - center.x, y - center.y).length() <= float(radius):
				image.set_pixel(x, y, color)


func _draw_legend(image: Image, grid_width: int) -> void:
	var x := MARGIN + grid_width * CELL_PX + 10
	var y := MARGIN + 8
	var colors: Array[Color] = [
		COLOR_WALL,
		COLOR_FLOOR,
		COLOR_PLAYER,
		COLOR_ENEMY,
		COLOR_PICKABLE,
		COLOR_MATERIAL,
		COLOR_CONTAINER,
		COLOR_HAZARD,
		COLOR_TERRAIN_FEATURE,
		COLOR_EXTRACTION,
		COLOR_STAIRS,
		COLOR_TAGGED_ITEM,
	]
	for color in colors:
		_fill_rect(image, Rect2i(x, y, 14, 14), color)
		y += 20


func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for py in range(rect.position.y, rect.position.y + rect.size.y):
		for px in range(rect.position.x, rect.position.x + rect.size.x):
			if px >= 0 and py >= 0 and px < image.get_width() and py < image.get_height():
				image.set_pixel(px, py, color)


func _count_markers(markers: Array[Dictionary], kind: String) -> int:
	var count := 0
	for marker in markers:
		if String(marker["kind"]) == kind:
			count += 1
	return count


func _count_item_markers(markers: Array[Dictionary]) -> int:
	var count := 0
	for marker in markers:
		if String(marker["kind"]) in ["pickable", "material", "container", "tagged_item"]:
			count += 1
	return count


func _marker_priority(kind: String) -> int:
	match kind:
		"material":
			return 8
		"tagged_item":
			return 10
		"pickable":
			return 20
		"container":
			return 30
		"enemy":
			return 40
		"extraction":
			return 50
		"stairs":
			return 52
		"hazard":
			return 55
		"terrain_feature":
			return 57
		"player":
			return 60
		_:
			return 0


func _is_extraction_portal_node(node: Node) -> bool:
	if not (node is Node3D):
		return false
	if node.name == "ExtractionPortal":
		return true
	return node.has_meta("topdown_kind") and String(node.get_meta("topdown_kind")) == "extraction"


func _is_hazard_node(node: Node) -> bool:
	if not (node is Node3D):
		return false
	if node is SpikesTrap or node is AcidTrap or String(node.name) == "FlameVentTrap":
		return true
	return node.has_meta("hazard_anchor") or (node.has_meta("topdown_kind") and String(node.get_meta("topdown_kind")) == "hazard")


func _is_terrain_feature_node(node: Node) -> bool:
	return node is Node3D and node.has_meta("topdown_kind") and String(node.get_meta("topdown_kind")) == "terrain_feature"


func _is_stairs_node(node: Node) -> bool:
	if not (node is Node3D):
		return false
	if node.name == "DownstairsPortal":
		return true
	return node.has_meta("topdown_kind") and String(node.get_meta("topdown_kind")) == "stairs"


func _is_cell_near_walkable(grid: Array, cell: Vector2i, radius: int) -> bool:
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			if y < 0 or y >= grid.size():
				continue
			if x < 0 or x >= grid[y].size():
				continue
			var cell_type := int(grid[y][x])
			if cell_type != BSP_DungeonGenerator.TileType.EMPTY and cell_type != BSP_DungeonGenerator.TileType.WALL:
				return true
	return false


func _first_marker_cell(markers: Array[Dictionary], kind: String) -> Vector2i:
	for marker in markers:
		if String(marker["kind"]) == kind:
			return marker["cell"]
	return Vector2i(-999, -999)


func _room_contains_cell(room: Rect2i, cell: Vector2i) -> bool:
	return cell.x >= room.position.x \
		and cell.y >= room.position.y \
		and cell.x < room.position.x + room.size.x \
		and cell.y < room.position.y + room.size.y


func _large_non_start_rooms(dungeon: ProceduralDungeon) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for room in dungeon.layout.rooms:
		if dungeon.layout.room_roles.has("start") and room == (dungeon.layout.room_roles["start"] as Rect2i):
			continue
		if room.size.x * room.size.y >= DungeonRenderingConfig.default().large_room_area:
			result.append(room)
	return result


func _count_markers_in_room(markers: Array[Dictionary], room: Rect2i, kinds: Array[String]) -> int:
	var count := 0
	for marker in markers:
		if not (String(marker["kind"]) in kinds):
			continue
		if _room_contains_cell(room, marker["cell"]):
			count += 1
	return count


func _unique_hazard_node_names(markers: Array[Dictionary]) -> Array[String]:
	var seen: Dictionary = {}
	for marker in markers:
		if String(marker["kind"]) != "hazard":
			continue
		seen[String(marker["name"])] = true
	var result: Array[String] = []
	for name in seen.keys():
		result.append(String(name))
	return result


func _assert_trap_placement_semantics(dungeon: ProceduralDungeon) -> void:
	var hazards: Array[Node3D] = []
	_collect_hazard_nodes(dungeon, hazards)
	assert_int(hazards.size()) \
		.override_failure_message("需要可审查的陷阱节点") \
		.is_greater_equal(1)
	for hazard in hazards:
		if hazard is SpikesTrap:
			var mount := String(hazard.get_meta("spike_mount", ""))
			assert_bool(mount == "floor" or mount == "wall") \
				.override_failure_message("尖刺必须平躺在地面或贴墙立起: %s mount=%s" % [hazard.name, mount]) \
				.is_true()
			if mount == "floor":
				assert_float(absf(absf(hazard.rotation_degrees.x) - 90.0)) \
					.override_failure_message("地面尖刺必须平躺: %s rotation=%s" % [hazard.name, hazard.rotation_degrees]) \
					.is_less_equal(0.1)
				assert_float(hazard.position.y) \
					.override_failure_message("地面尖刺不能悬空: %s y=%.3f" % [hazard.name, hazard.position.y]) \
					.is_less_equal(0.2)
			else:
				assert_float(absf(hazard.rotation_degrees.x)) \
					.override_failure_message("墙面尖刺必须立起: %s rotation=%s" % [hazard.name, hazard.rotation_degrees]) \
					.is_less_equal(0.1)
				assert_float(hazard.position.y) \
					.override_failure_message("墙面尖刺需要离地贴墙: %s y=%.3f" % [hazard.name, hazard.position.y]) \
					.is_greater_equal(0.8)
				assert_bool(hazard.has_meta("wall_direction")) \
					.override_failure_message("墙面尖刺需要记录贴墙方向: %s" % hazard.name) \
					.is_true()
		elif hazard is AcidTrap:
			assert_bool(bool(hazard.get_meta("acid_ground_only", false))) \
				.override_failure_message("酸液只能生成在地面: %s" % hazard.name) \
				.is_true()
			assert_bool(bool(hazard.get_meta("acid_pit", false))) \
				.override_failure_message("酸液必须放入挖出的坑洞: %s" % hazard.name) \
				.is_true()
			assert_object(hazard.find_child("AcidPit", true, false)) \
				.override_failure_message("酸液陷阱缺少坑洞视觉节点 AcidPit: %s" % hazard.name) \
				.is_not_null()
			assert_float(absf(hazard.rotation_degrees.x)) \
				.override_failure_message("酸液不能贴墙或倾斜: %s rotation=%s" % [hazard.name, hazard.rotation_degrees]) \
				.is_less_equal(0.1)
			assert_float(absf(hazard.rotation_degrees.z)) \
				.override_failure_message("酸液不能贴墙或倾斜: %s rotation=%s" % [hazard.name, hazard.rotation_degrees]) \
				.is_less_equal(0.1)
			assert_float(hazard.position.y) \
				.override_failure_message("酸液应贴近地面坑洞: %s y=%.3f" % [hazard.name, hazard.position.y]) \
				.is_less_equal(0.08)


func _collect_hazard_nodes(node: Node, hazards: Array[Node3D]) -> void:
	if node is SpikesTrap or node is AcidTrap or _is_hazard_node(node):
		if node is Node3D:
			hazards.append(node as Node3D)
	for child in node.get_children():
		_collect_hazard_nodes(child, hazards)


func _ensure_reports_dir() -> void:
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("reports")
