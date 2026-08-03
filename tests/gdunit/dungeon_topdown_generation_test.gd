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
const LEGEND_HEIGHT := 200
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
const COLOR_ROOM_FOCUS := Color(1.0, 0.55, 0.08, 1.0)
const COLOR_TAGGED_ITEM := Color(0.05, 0.20, 1.0, 1.0)
const COLOR_DOOR := Color(0.10, 0.70, 1.0, 1.0)
const COLOR_PLATFORM := Color(0.26, 0.48, 0.72, 1.0)
const COLOR_CLIFF_CELL := Color(0.48, 0.28, 0.16, 1.0)
const COLOR_CLIFF_EDGE := Color(1.0, 0.74, 0.18, 1.0)
const COLOR_CLIFF_RAMP := Color(0.92, 0.58, 0.12, 1.0)
const COLOR_RAMP := Color(0.62, 0.42, 0.18, 1.0)
const COLOR_BRIDGE := Color(0.64, 0.30, 0.12, 1.0)
const COLOR_BOUNDARY := Color(0.70, 0.70, 0.76, 1.0)
const COLOR_COVER := Color(0.42, 0.30, 0.22, 1.0)
const COLOR_HAZARD_WARNING := Color(1.0, 0.30, 0.05, 1.0)
const COLOR_DOOR_TRANSITION := Color(0.22, 0.72, 0.92, 1.0)
const LEGEND_TEXT_COLOR := Color(0.86, 0.84, 0.74, 1.0)
const LEGEND_BORDER_COLOR := Color(0.55, 0.55, 0.52, 1.0)
const LABEL_BITMAP_WIDTH := 12
const LABEL_BITMAP_HEIGHT := 12
const LABEL_BITMAP_ADVANCE := 12
const LEGEND_ROW_HEIGHT := 16
var LABEL_BITMAPS := {
    "空": [
        "............",
        ".#########..",
        ".#.......#..",
        "...#...#....",
        "...#....#...",
        ".##.....##..",
        "..#######...",
        ".....#......",
        ".....#......",
        ".#########..",
        "............",
        "............"
    ],
    "白": [
        "............",
        "....##......",
        "..#######...",
        "..#.....#...",
        "..#.....#...",
        "..#.....#...",
        "..#######...",
        "..#.....#...",
        "..#.....#...",
        "..#######...",
        "............",
        "............"
    ],
    "墙": [
        "............",
        "..#.######..",
        "..#..#.##...",
        ".###...#....",
        "..########..",
        "..#.........",
        "..########..",
        ".##.#.####..",
        "....#.#.##..",
        "....######..",
        "............",
        "............"
    ],
    "体": [
        "............",
        "...#..#.....",
        "..########..",
        "..#...#.....",
        ".##..###....",
        "..#.#.#.#...",
        "..###.#.#...",
        "..########..",
        "..#...#.....",
        "..#...#.....",
        "............",
        "............"
    ],
    "地": [
        "............",
        "..#.#..#....",
        "..#.#..###..",
        ".####.####..",
        "..####.#.#..",
        "..#.#..#.#..",
        "..###..###..",
        ".##.#....#..",
        "....#....#..",
        ".....#####..",
        "............",
        "............"
    ],
    "面": [
        "............",
        ".#########..",
        "....#.......",
        ".#########..",
        ".#.#...#.#..",
        ".#.#####.#..",
        ".#.#...#.#..",
        ".#.#####.#..",
        ".#.#...#.#..",
        ".#########..",
        "............",
        "............"
    ],
    "战": [
        "............",
        "...#...###..",
        "...##..#....",
        "...#...###..",
        "...#.###....",
        "...#...#.#..",
        ".####..##...",
        ".#..#...##..",
        ".#..#..###..",
        ".####.#..#..",
        "............",
        "............"
    ],
    "利": [
        "............",
        "..####...#..",
        "...#...#.#..",
        "...#...#.#..",
        ".#####.#.#..",
        "...#...#.#..",
        "...##..#.#..",
        "..##.#...#..",
        ".#.#.....#..",
        "...#....##..",
        "............",
        "............"
    ],
    "品": [
        "............",
        "...######...",
        "...#....#...",
        "...#....#...",
        "...######...",
        "............",
        ".####.####..",
        ".#..#.#..#..",
        ".#..#.#..#..",
        ".####.####..",
        "............",
        "............"
    ],
    "资": [
        "............",
        "..##.#####..",
        "....#..#.#..",
        "...#..#.#...",
        ".##.##..##..",
        "............",
        "..#######...",
        "..#..#..#...",
        "...##.##....",
        ".###....##..",
        "............",
        "............"
    ],
    "源": [
        "............",
        ".#########..",
        "...#.####...",
        ".#.#.#..#...",
        "..##.####...",
        "...#.#..#...",
        "..##.####...",
        "..##.#.##...",
        ".#.#.#.#.#..",
        ".#.##.##.#..",
        "............",
        "............"
    ],
    "柱": [
        "............",
        "...#..##....",
        ".###.#####..",
        "...#...#....",
        "...#...#....",
        "..##...#....",
        ".###.####...",
        "...#...#....",
        "...#...#....",
        "...#######..",
        "............",
        "............"
    ],
    "子": [
        "............",
        "..#######...",
        ".......#....",
        "......#.....",
        ".....#......",
        ".#########..",
        ".....#......",
        ".....#......",
        ".....#......",
        "...###......",
        "............",
        "............"
    ],
    "玩": [
        "............",
        ".########...",
        "..#.........",
        "..#.........",
        "..########..",
        ".###.#..#...",
        "..#..#..#...",
        "..###...##..",
        ".##.#...##..",
        "...#....##..",
        "............",
        "............"
    ],
    "家": [
        "............",
        ".#########..",
        ".#.......#..",
        ".#.#######..",
        "....##......",
        "...#..#.#...",
        ".########...",
        ".##.###.#...",
        "...#..#.##..",
        ".##.##......",
        "............",
        "............"
    ],
    "敌": [
        "............",
        ".####.#.....",
        "...#..####..",
        "...#.#..#...",
        ".####.#.#...",
        "...#..#.#...",
        ".####.#.#...",
        ".#..#..#....",
        ".#..#.#.#...",
        ".#####..##..",
        "............",
        "............"
    ],
    "人": [
        "............",
        ".....#......",
        ".....#......",
        ".....#......",
        "....#.#.....",
        "....#.#.....",
        "...#...#....",
        "...#....#...",
        "..#.....#...",
        ".#.......#..",
        "............",
        "............"
    ],
    "装": [
        "............",
        ".#########..",
        "...#...#....",
        "...#...#....",
        ".###.####...",
        ".....#......",
        ".#########..",
        ".###...##...",
        "...###..#...",
        "...#....##..",
        "............",
        "............"
    ],
    "备": [
        "............",
        "...######...",
        ".###...#....",
        "....###.....",
        "...#...##...",
        ".##.....##..",
        "..#######...",
        "..#######...",
        "..#..#..#...",
        "..#######...",
        "............",
        "............"
    ],
    "材": [
        "............",
        "...#....#...",
        ".###.#####..",
        "...#....#...",
        "...#....#...",
        "..##....#...",
        ".###..###...",
        "...###..#...",
        "...#....#...",
        "...#...##...",
        "............",
        "............"
    ],
    "料": [
        "............",
        ".#.#..#.#...",
        "..##...##...",
        "...#....#...",
        ".###.#..#...",
        "...#..#.#...",
        "..##...###..",
        ".#.#.##.#...",
        "...#....#...",
        "...#....#...",
        "............",
        "............"
    ],
    "容": [
        "............",
        ".#########..",
        ".#.#...#.#..",
        "..##.#..#...",
        "....#.#.....",
        "...#...##...",
        ".#########..",
        "...#....#...",
        "...#....#...",
        "...######...",
        "............",
        "............"
    ],
    "器": [
        "............",
        "..###.###...",
        "..#.#.#.#...",
        "..###.###...",
        ".....#.#....",
        ".#########..",
        ".####.####..",
        "..#.#.#.#...",
        "..#.#.#.#...",
        "..###.###...",
        "............",
        "............"
    ],
    "陷": [
        "............",
        ".###..###...",
        ".#.#.#..#...",
        ".#.##...#...",
        ".##...#.....",
        ".#.###..##..",
        ".#.####.##..",
        ".####....#..",
        ".#..#....#..",
        ".#..######..",
        "............",
        "............"
    ],
    "阱": [
        "............",
        ".###..#.#...",
        ".#.#######..",
        ".#.#..#.#...",
        ".##...#.#...",
        ".#.#..#.#...",
        ".#.#######..",
        ".###..#.#...",
        ".#...#..#...",
        ".#..#...#...",
        "............",
        "............"
    ],
    "形": [
        "............",
        ".#########..",
        "...#.#..#...",
        "...#.#......",
        "...#.#...#..",
        ".########...",
        "...#.#..#...",
        "..#..#...#..",
        "..#..#..#...",
        ".#...#..#...",
        "............",
        "............"
    ],
    "门": [
        "............",
        ".#########..",
        ".........#..",
        ".#.......#..",
        ".#.......#..",
        ".#.......#..",
        ".#.......#..",
        ".#.......#..",
        ".#.......#..",
        ".#......##..",
        "............",
        "............"
    ],
    "撤": [
        "............",
        "..#####.#...",
        ".####...##..",
        "..##..#.##..",
        "..####.#.#..",
        "..##..#.##..",
        ".######.##..",
        "..#####.#...",
        "..##..#.##..",
        ".###.###.#..",
        "............",
        "............"
    ],
    "离": [
        "............",
        ".#########..",
        "...#...#....",
        "..#.###.#...",
        "..##...##...",
        "..#######...",
        ".#########..",
        ".#.#...#.#..",
        ".#.####.##..",
        ".#......##..",
        "............",
        "............"
    ],
    "点": [
        "............",
        ".....#####..",
        ".....#......",
        ".....#......",
        "..#######...",
        "..#.....#...",
        "..#######...",
        "............",
        "..##..#.#...",
        ".#..#..#.#..",
        "............",
        "............"
    ],
    "楼": [
        "............",
        "...###.###..",
        ".#########..",
        "...#..###...",
        "...#.#.##...",
        "..###..#.#..",
        ".#########..",
        "...#..#.#...",
        "...#..###...",
        "...###..##..",
        "............",
        "............"
    ],
    "梯": [
        "............",
        "...#.##.#...",
        ".#########..",
        "...#...#.#..",
        "...#######..",
        "..###..#....",
        ".#########..",
        "...#.#.#.#..",
        "...##..###..",
        "...#...#....",
        "............",
        "............"
    ],
    "特": [
        "............",
        ".#.#.####...",
        ".###...#....",
        ".#.#...#....",
        "...#######..",
        "...#....#...",
        ".#########..",
        "...#..#.#...",
        "...#....#...",
        "...#...##...",
        "............",
        "............"
    ],
    "殊": [
        "............",
        ".###.#.#....",
        "..#..####...",
        "..###..#....",
        ".#.#...#....",
        ".#.#######..",
        "..##..###...",
        "...#.#.##...",
        "..#.#..#.#..",
        ".#.....#....",
        "............",
        "............"
    ],
    "物": [
        "............",
        ".#.#.#......",
        ".###.#####..",
        ".#.##.#.##..",
        "...#..#.##..",
        "...#..#.##..",
        ".###.#.###..",
        "...##..#.#..",
        "...#..#..#..",
        "...#.#..#...",
        "............",
        "............"
    ],
    "焦": [
        "............",
        "..######....",
        "..#.........",
        "..#####.....",
        "....#.......",
        "....#.......",
        "....#.......",
        "....#.......",
        "....#.......",
        "..########..",
        "............",
        "............"
    ],
    "建": [
        "............",
        "....#.......",
        "...###......",
        "..#####.....",
        "....#.......",
        "..#######...",
        "....#.......",
        "...###......",
        "..#####.....",
        "............",
        "............",
        "............"
    ],
    "筑": [
        "............",
        "..######....",
        "....#.......",
        ".#########..",
        "..#...#.....",
        "..#...#.....",
        "..#######...",
        ".....#......",
        "....###.....",
        "...#####....",
        "............",
        "............"
    ],
}


func test_generated_dungeon_topdown_map_includes_monsters_and_items() -> void:
	seed(94021)
	var dungeon_scene := load("res://scenes/expedition/procedural_dungeon.tscn") as PackedScene
	dungeon = dungeon_scene.instantiate() as ProceduralDungeon
	dungeon.dungeon_zone = 0
	# Use the same explicit layout seed as the planner contracts; seeding the
	# global RNG alone cannot control DungeonGenerator's local RNG selection.
	dungeon.generation_seed = 94021
	add_child(dungeon)
	await await_idle_frame()
	await await_idle_frame()
	for _i in range(48):
		var spawned_enemy_count := _count_markers(_collect_topdown_markers(dungeon), "enemy")
		if spawned_enemy_count >= dungeon.layout.enemy_spawn_specs.size():
			break
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
	var room_focus_count := _count_markers(markers, "room_focus")
	var door_count := _count_markers(markers, "door")
	var platform_count := _count_markers(markers, "platform")
	var cliff_count := _count_markers(markers, "cliff")
	var cliff_edge_count := _count_markers(markers, "cliff_edge")
	var cliff_ramp_count := _count_markers(markers, "cliff_ramp")
	var ramp_count := _count_markers(markers, "ramp")
	var bridge_count := _count_markers(markers, "bridge")
	var boundary_count := _count_markers(markers, "boundary")
	var cover_count := _count_markers(markers, "cover")
	var warning_count := _count_markers(markers, "hazard_warning")
	var door_transition_count := _count_markers(markers, "door_transition")
	assert_int(enemy_count) \
		.override_failure_message("俯视测试图敌人过少: %d，必须等待并生成完整人口" % enemy_count) \
		.is_greater_equal(12)
	assert_int(enemy_count) \
		.override_failure_message("俯视测试图未捕获完整敌人计划: actual=%d planned=%d" % [enemy_count, dungeon.layout.enemy_spawn_specs.size()]) \
		.is_greater_equal(dungeon.layout.enemy_spawn_specs.size())
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
		.is_greater_equal(4)
	assert_int(hazard_count) \
		.override_failure_message("俯视测试图陷阱过多: %d，应该由少量战斗锚点组成" % hazard_count) \
		.is_less_equal(6)
	assert_int(terrain_feature_count) \
		.override_failure_message("大房间需要生成额外地形特征，避免空旷") \
		.is_greater_equal(4)
	assert_int(room_focus_count) \
		.override_failure_message("主题房间必须生成可识别的焦点建筑") \
		.is_greater_equal(6)
	assert_int(door_count) \
		.override_failure_message("俯视测试图必须标出地牢门位置") \
		.is_greater_equal(1)
	assert_int(platform_count) \
		.override_failure_message("俯视测试图必须标出高台") \
		.is_greater_equal(1)
	assert_int(cliff_count) \
		.override_failure_message("俯视测试图必须逐格标出悬崖高台，不能只显示普通平台色") \
		.is_greater_equal(4)
	assert_int(cliff_edge_count) \
		.override_failure_message("悬崖必须有可审查的连续崖边标记") \
		.is_greater_equal(1)
	assert_int(cliff_ramp_count) \
		.override_failure_message("悬崖必须有一格可辨认的坡道入口") \
		.is_greater_equal(1)
	assert_int(ramp_count) \
		.override_failure_message("俯视测试图必须标出坡道") \
		.is_greater_equal(1)
	assert_int(bridge_count) \
		.override_failure_message("俯视测试图必须标出桥") \
		.is_greater_equal(1)
	assert_int(boundary_count) \
		.override_failure_message("高台必须有封闭边界标记") \
		.is_greater_equal(1)
	assert_int(cover_count) \
		.override_failure_message("战斗房必须有掩体标记") \
		.is_greater_equal(2)
	assert_int(warning_count) \
		.override_failure_message("陷阱必须有独立警示区域标记") \
		.is_greater_equal(hazard_count)
	assert_int(door_transition_count) \
		.override_failure_message("门必须有门前过渡标记") \
		.is_greater_equal(door_count)
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
	_assert_door_markers_are_room_boundaries(dungeon, markers)
	_assert_cliff_render_markers(dungeon, markers)

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
		var room_density := _count_markers_in_room(markers, room, ["hazard", "terrain_feature", "room_focus", "cover", "platform", "ramp", "bridge"])
		assert_int(room_density) \
			.override_failure_message("大房间仍然过于空旷，需要至少 2 个地形/陷阱锚点: %s count=%d" % [room, room_density]) \
			.is_greater_equal(2)

	var image := _render_topdown_image(grid, dungeon.layout.heights, markers, dungeon.layout.floor_elevations)
	var map_pixel_height := MARGIN * 2 + dungeon.layout.height * CELL_PX
	assert_int(image.get_height()).is_greater(map_pixel_height)
	assert_bool(_legend_has_rendered_pixels(image, map_pixel_height)).is_true()
	_ensure_reports_dir()
	var err := image.save_png(OUTPUT_PATH)
	assert_int(err) \
		.override_failure_message("无法保存地牢俯视测试图: %s" % OUTPUT_PATH) \
		.is_equal(OK)
	print("[DungeonTopdown] saved=%s enemies=%d items=%d materials=%d hazards=%d terrain=%d focus=%d cliffs=%d cliff_edges=%d cliff_ramps=%d doors=%d extraction=%d stairs=%d markers=%d" % [OUTPUT_PATH, enemy_count, item_count, material_count, hazard_count, terrain_feature_count, room_focus_count, cliff_count, cliff_edge_count, cliff_ramp_count, door_count, extraction_count, stairs_count, markers.size()])


func _collect_topdown_markers(dungeon: ProceduralDungeon) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	_collect_topdown_markers_recursive(dungeon, dungeon, markers)
	_append_layout_terrain_markers(dungeon, markers)
	return markers


func _append_layout_terrain_markers(dungeon: ProceduralDungeon, markers: Array[Dictionary]) -> void:
	if dungeon == null or dungeon.layout == null:
		return
	# 悬崖的语义来源是规划器的 terrain_features，而不是某个视觉节点的颜色。
	# 这样即使实例化/流送顺序改变，俯视图仍能逐格审查真实悬崖布局。
	for feature_index in range(dungeon.layout.terrain_features.size()):
		var feature: Dictionary = dungeon.layout.terrain_features[feature_index]
		if String(feature.get("feature_kind", "")) != "cliff":
			continue
		var room_index := int(feature.get("room_index", -1))
		var feature_name := "CliffFeature_%d" % feature_index
		for cell_value in feature.get("cells", []):
			var cell: Vector2i = cell_value
			markers.append({
				"kind": "cliff",
				"cell": cell,
				"name": feature_name,
				"room_index": room_index,
				"height_m": float(feature.get("elevation_m", 0.0)),
			})
		for edge_value in feature.get("edges", []):
			var edge: Dictionary = edge_value
			markers.append({
				"kind": "cliff_edge",
				"cell": edge.get("cell", Vector2i(-1, -1)),
				"dir": edge.get("dir", Vector2i.ZERO),
				"name": feature_name,
				"room_index": room_index,
			})
		var ramp_cell: Vector2i = feature.get("ramp_cell", Vector2i(-1, -1))
		if ramp_cell.x >= 0:
			var ramp_direction := Vector2i.ZERO
			for spec in dungeon.layout.room_composition_specs:
				if int(spec.get("room_index", -1)) != room_index:
					continue
				for ramp_value in spec.get("ramp_specs", []):
					var ramp_spec: Dictionary = ramp_value
					if ramp_spec.get("cell", Vector2i(-1, -1)) == ramp_cell:
						ramp_direction = ramp_spec.get("dir", Vector2i.ZERO)
						break
				if ramp_direction != Vector2i.ZERO:
					break
			markers.append({
				"kind": "cliff_ramp",
				"cell": ramp_cell,
				"dir": ramp_direction,
				"name": feature_name,
				"room_index": room_index,
			})


func _collect_topdown_markers_recursive(node: Node, dungeon: ProceduralDungeon, markers: Array[Dictionary]) -> void:
	if node is DungeonDoor:
		_append_door_marker(markers, node as DungeonDoor)
	elif node is Player:
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
	elif _is_room_focus_node(node):
		_append_marker(markers, dungeon, node as Node3D, "room_focus")
	elif _is_composition_marker_node(node):
		_append_marker(markers, dungeon, node as Node3D, String(node.get_meta("topdown_kind")))
	elif _is_terrain_feature_node(node):
		_append_marker(markers, dungeon, node as Node3D, "terrain_feature")
	for child in node.get_children():
		_collect_topdown_markers_recursive(child, dungeon, markers)


func _append_door_marker(markers: Array[Dictionary], door: DungeonDoor) -> void:
	var inside: Vector2i = door.get_meta("inside_cell", Vector2i(-1, -1))
	var outside: Vector2i = door.get_meta("outside_cell", Vector2i(-1, -1))
	markers.append({
		"kind": "door",
		"cell": inside,
		"outside": outside,
		"dir": outside - inside,
		"name": String(door.name),
	})


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


func _render_topdown_image(grid: Array, heights: Array, markers: Array[Dictionary], floor_elevations: Array = []) -> Image:
	var grid_width := int(grid[0].size())
	var grid_height := int(grid.size())
	var image_width := MARGIN * 2 + grid_width * CELL_PX
	var map_pixel_height := MARGIN * 2 + grid_height * CELL_PX
	var image_height := map_pixel_height + LEGEND_HEIGHT
	var image := Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)
	image.fill(COLOR_EMPTY)

	for y in range(grid_height):
		for x in range(grid_width):
			var height := float(heights[y][x]) if y < heights.size() and x < heights[y].size() else 3.0
			var floor_height := float(floor_elevations[y][x]) if y < floor_elevations.size() and x < floor_elevations[y].size() else 0.0
			_fill_cell(image, Vector2i(x, y), _cell_color(int(grid[y][x]), height, floor_height))

	var sorted_markers := markers.duplicate()
	sorted_markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _marker_priority(String(a["kind"])) < _marker_priority(String(b["kind"]))
	)
	for marker in sorted_markers:
		var kind := String(marker["kind"])
		if kind == "door":
			_draw_door_marker(image, marker["cell"], marker["dir"], _marker_color(kind))
		elif kind == "cliff_edge":
			_draw_cliff_edge_marker(image, marker["cell"], marker["dir"], _marker_color(kind))
		elif kind == "cliff":
			_draw_cliff_cell_marker(image, marker["cell"], _marker_color(kind))
		elif kind == "cliff_ramp":
			_draw_cliff_ramp_marker(image, marker["cell"], marker["dir"], _marker_color(kind))
		else:
			_draw_marker(image, marker["cell"], _marker_color(kind))

	_draw_legend(image, map_pixel_height)
	return image


func _cell_color(cell_type: int, height: float = 3.0, floor_height: float = 0.0) -> Color:
	var height_t := clampf((height - 3.0) / 2.2, 0.0, 1.0)
	if floor_height > 0.1:
		if floor_height >= 1.4:
			return COLOR_CLIFF_CELL
		return COLOR_PLATFORM.lerp(Color(0.42, 0.66, 0.86, 1.0), clampf(floor_height / 2.0, 0.0, 1.0))
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
		"room_focus":
			return COLOR_ROOM_FOCUS
		"door":
			return COLOR_DOOR
		"platform":
			return COLOR_PLATFORM
		"cliff":
			return COLOR_CLIFF_CELL
		"cliff_edge":
			return COLOR_CLIFF_EDGE
		"cliff_ramp":
			return COLOR_CLIFF_RAMP
		"ramp":
			return COLOR_RAMP
		"bridge":
			return COLOR_BRIDGE
		"boundary":
			return COLOR_BOUNDARY
		"cover":
			return COLOR_COVER
		"hazard_warning":
			return COLOR_HAZARD_WARNING
		"door_transition":
			return COLOR_DOOR_TRANSITION
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


func _draw_door_marker(image: Image, cell: Vector2i, direction: Vector2i, color: Color) -> void:
	var start := Vector2i(MARGIN + cell.x * CELL_PX, MARGIN + cell.y * CELL_PX)
	var rect: Rect2i
	if direction.x != 0:
		var boundary_x := start.x + (CELL_PX if direction.x > 0 else 0)
		rect = Rect2i(boundary_x - 1, start.y + 1, 3, CELL_PX - 2)
	else:
		var boundary_y := start.y + (CELL_PX if direction.y > 0 else 0)
		rect = Rect2i(start.x + 1, boundary_y - 1, CELL_PX - 2, 3)
	_fill_rect(image, rect, color)


func _draw_cliff_cell_marker(image: Image, cell: Vector2i, color: Color) -> void:
	# 两条硬边对角线让悬崖高台在密集标记下仍可逐格识别，底色仍保留高度语义。
	var start := Vector2i(MARGIN + cell.x * CELL_PX, MARGIN + cell.y * CELL_PX)
	for offset in range(1, CELL_PX - 1):
		var px_a := start.x + offset
		var py_a := start.y + offset
		var px_b := start.x + CELL_PX - 1 - offset
		var py_b := start.y + offset
		if px_a >= 0 and py_a >= 0 and px_a < image.get_width() and py_a < image.get_height():
			image.set_pixel(px_a, py_a, color)
		if px_b >= 0 and py_b >= 0 and px_b < image.get_width() and py_b < image.get_height():
			image.set_pixel(px_b, py_b, color)


func _draw_cliff_edge_marker(image: Image, cell: Vector2i, direction: Vector2i, color: Color) -> void:
	var start := Vector2i(MARGIN + cell.x * CELL_PX, MARGIN + cell.y * CELL_PX)
	var rect: Rect2i
	if direction.x != 0:
		var boundary_x := start.x + (CELL_PX if direction.x > 0 else 0)
		rect = Rect2i(boundary_x - 1, start.y, 3, CELL_PX)
	else:
		var boundary_y := start.y + (CELL_PX if direction.y > 0 else 0)
		rect = Rect2i(start.x, boundary_y - 1, CELL_PX, 3)
	_fill_rect(image, rect, color)


func _draw_cliff_ramp_marker(image: Image, cell: Vector2i, direction: Vector2i, color: Color) -> void:
	var start := Vector2i(MARGIN + cell.x * CELL_PX, MARGIN + cell.y * CELL_PX)
	var center := Vector2i(start.x + CELL_PX / 2, start.y + CELL_PX / 2)
	var step := Vector2i(signi(direction.x), signi(direction.y))
	if step == Vector2i.ZERO:
		step = Vector2i(0, 1)
	for index in range(1, 4):
		var px := center.x + step.x * index
		var py := center.y + step.y * index
		if px >= 0 and py >= 0 and px < image.get_width() and py < image.get_height():
			image.set_pixel(px, py, color)
			if step.x == 0 and px + 1 < image.get_width():
				image.set_pixel(px + 1, py, color)
			elif step.y == 0 and py + 1 < image.get_height():
				image.set_pixel(px, py + 1, color)


func _draw_legend(image: Image, map_pixel_height: int) -> void:
	_ensure_annotation_bitmaps()
	var entries: Array = [
		{"label": "空白", "color": COLOR_EMPTY},
		{"label": "墙体", "color": COLOR_WALL},
		{"label": "地面", "color": COLOR_FLOOR},
		{"label": "战利品", "color": COLOR_LOOT_CELL},
		{"label": "资源", "color": COLOR_RESOURCE_CELL},
		{"label": "柱子", "color": COLOR_PILLAR},
		{"label": "玩家", "color": COLOR_PLAYER},
		{"label": "敌人", "color": COLOR_ENEMY},
		{"label": "装备", "color": COLOR_PICKABLE},
		{"label": "材料", "color": COLOR_MATERIAL},
		{"label": "容器", "color": COLOR_CONTAINER},
		{"label": "陷阱", "color": COLOR_HAZARD},
		{"label": "地形", "color": COLOR_TERRAIN_FEATURE},
		{"label": "焦点建筑", "color": COLOR_ROOM_FOCUS},
		{"label": "门", "color": COLOR_DOOR},
		{"label": "门前", "color": COLOR_DOOR_TRANSITION},
		{"label": "平台", "color": COLOR_PLATFORM},
		{"label": "悬崖", "color": COLOR_CLIFF_CELL},
		{"label": "崖边", "color": COLOR_CLIFF_EDGE},
		{"label": "坡道", "color": COLOR_RAMP},
		{"label": "桥", "color": COLOR_BRIDGE},
		{"label": "边界", "color": COLOR_BOUNDARY},
		{"label": "掩体", "color": COLOR_COVER},
		{"label": "警示", "color": COLOR_HAZARD_WARNING},
		{"label": "撤离点", "color": COLOR_EXTRACTION},
		{"label": "楼梯", "color": COLOR_STAIRS},
		{"label": "特殊物品", "color": COLOR_TAGGED_ITEM},
	]
	var x := MARGIN
	var y := map_pixel_height + 8
	for entry in entries:
		var label := String(entry["label"])
		var entry_width := 9 + 3 + label.length() * LABEL_BITMAP_ADVANCE + 5
		if x + entry_width > image.get_width() - MARGIN:
			x = MARGIN
			y += LEGEND_ROW_HEIGHT
		_draw_legend_swatch(image, x, y + 1, entry["color"])
		_draw_label_bitmap(image, label, x + 12, y + 2, LEGEND_TEXT_COLOR)
		x += entry_width


func _ensure_annotation_bitmaps() -> void:
	var additions := {
		"台": ["............", "...######...", ".....#......", ".#########..", ".....#......", "....###.....", "...#####....", "..#######...", "............", "............", "............", "............"],
		"悬": ["............", ".#..#####...", ".#.#...#....", ".###...#....", ".#.#...#....", ".#..#####...", "....#.......", "...###......", "..#####.....", ".#######....", "............", "............"],
		"崖": ["............", ".#########..", ".....#......", "....###.....", "...#####....", "..#######...", ".#.......#..", ".#..###..#..", ".#.#...#.#..", ".#########..", "............", "............"],
		"坡": ["............", ".###...##...", ".#.#..#.....", ".###..####..", ".#...#......", ".#..######..", ".#..#.......", ".#..######..", "............", "............", "............", "............"],
		"道": ["............", "....#.......", "...###......", ".#########..", "....#.......", "...#####....", "....#.......", ".#########..", "............", "............", "............", "............"],
		"桥": ["............", "..#.....#...", ".#########..", "....###.....", "...#####....", "..#######...", "....#.......", "....#.......", "............", "............", "............", "............"],
		"落": ["............", ".#########..", "....#.......", "...###......", "..#####.....", "............", ".#########..", ".#..#..#....", ".#..#..#....", ".#######....", "............", "............"],
		"差": ["............", "..#######...", "....#.......", ".#########..", ".....#......", "....###.....", "...#####....", "..#######...", "............", "............", "............", "............"],
		"边": ["............", ".#########..", "....#.......", "...###......", "..#####.....", ".....#......", ".#########..", "....#.......", "...###......", "............", "............", "............"],
		"界": ["............", ".#########..", "....#.......", "..#######...", "....#.......", ".#########..", "...#...#....", "..#.....#...", ".#.......#..", "............", "............", "............"],
		"掩": ["............", ".#..######..", ".#####......", "..#..####...", ".#########..", "..#..#......", "..#..######..", ".#........#.", "............", "............", "............", "............"],
		"警": ["............", ".#########..", "..#.#.#.....", ".#########..", "...#...#....", "..#######...", "...#...#....", "..#######...", "............", "............", "............", "............"],
		"示": ["............", ".#########..", ".....#......", "...#####....", "..#######...", ".....#......", "....###.....", "...#####....", "............", "............", "............", "............"],
		"前": ["............", ".#########..", "...#####....", "....#.......", ".#########..", ".....#......", "....###.....", "...#####....", "............", "............", "............", "............"],
	}
	for key in additions.keys():
		if not LABEL_BITMAPS.has(key):
			LABEL_BITMAPS[key] = additions[key]


func _draw_legend_swatch(image: Image, x: int, y: int, color: Color) -> void:
	_fill_rect(image, Rect2i(x, y, 9, 9), LEGEND_BORDER_COLOR)
	_fill_rect(image, Rect2i(x + 1, y + 1, 7, 7), color)


func _draw_label_bitmap(image: Image, label: String, x: int, y: int, color: Color) -> void:
	for index in range(label.length()):
		var character := label.substr(index, 1)
		var bitmap: Array = LABEL_BITMAPS.get(character, [])
		for bitmap_y in range(bitmap.size()):
			var row := String(bitmap[bitmap_y])
			for bitmap_x in range(row.length()):
				if row.substr(bitmap_x, 1) == "#":
					image.set_pixel(x + index * LABEL_BITMAP_ADVANCE + bitmap_x, y + bitmap_y, color)


func _legend_has_rendered_pixels(image: Image, map_pixel_height: int) -> bool:
	var non_background := 0
	for y in range(map_pixel_height, image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			var difference := absf(pixel.r - COLOR_EMPTY.r) + absf(pixel.g - COLOR_EMPTY.g) + absf(pixel.b - COLOR_EMPTY.b)
			if difference > 0.08:
				non_background += 1
	return non_background > 900


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
		"room_focus":
			return 56
		"cliff":
			return 54
		"cliff_ramp":
			return 57
		"platform", "ramp", "bridge", "boundary", "cover":
			return 56
		"cliff_edge":
			return 80
		"hazard_warning":
			return 55
		"door":
			return 58
		"door_transition":
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


func _is_room_focus_node(node: Node) -> bool:
	return node is Node3D and node.has_meta("room_focus") and bool(node.get_meta("room_focus"))


func _is_composition_marker_node(node: Node) -> bool:
	if not node is Node3D or not node.has_meta("topdown_kind"):
		return false
	return String(node.get_meta("topdown_kind")) in [
		"platform", "ramp", "bridge", "boundary", "cover", "hazard_warning", "door_transition"
	]


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


func _assert_door_markers_are_room_boundaries(dungeon: ProceduralDungeon, markers: Array[Dictionary]) -> void:
	for marker in markers:
		if String(marker["kind"]) != "door":
			continue
		var inside: Vector2i = marker["cell"]
		var outside: Vector2i = marker["outside"]
		assert_int(absi(outside.x - inside.x) + absi(outside.y - inside.y)) \
			.override_failure_message("门标记必须连接相邻格: %s -> %s" % [inside, outside]).is_equal(1)
		assert_bool(dungeon.layout.is_floor_cell(inside)).is_true()
		assert_bool(dungeon.layout.is_floor_cell(outside)).is_true()
		for room in dungeon.layout.rooms:
			assert_bool(room.has_point(outside)) \
				.override_failure_message("门不能生成在房间内部: %s outside=%s room=%s" % [marker["name"], outside, room]) \
				.is_false()


func _assert_cliff_render_markers(dungeon: ProceduralDungeon, markers: Array[Dictionary]) -> void:
	var feature_cells := {}
	var feature_edges := {}
	var feature_ramps := {}
	for feature in dungeon.layout.terrain_features:
		if String(feature.get("feature_kind", "")) != "cliff":
			continue
		var room_index := int(feature.get("room_index", -1))
		var room: Rect2i = dungeon.layout.rooms[room_index]
		for cell_value in feature.get("cells", []):
			var cell: Vector2i = cell_value
			feature_cells[cell] = true
			assert_bool(room.has_point(cell)).is_true()
			assert_float(dungeon.layout.floor_height_at(cell)) \
				.override_failure_message("悬崖格高度必须是 1.5m: %s" % cell) \
				.is_equal_approx(1.5, 0.001)
		for edge_value in feature.get("edges", []):
			var edge: Dictionary = edge_value
			feature_edges[edge.get("cell", Vector2i(-1, -1))] = true
		var ramp_cell: Vector2i = feature.get("ramp_cell", Vector2i(-1, -1))
		if ramp_cell.x >= 0:
			feature_ramps[ramp_cell] = true
	var rendered_cells := {}
	var rendered_edges := {}
	var rendered_ramps := {}
	for marker in markers:
		match String(marker.get("kind", "")):
			"cliff":
				rendered_cells[marker.get("cell", Vector2i(-1, -1))] = true
			"cliff_edge":
				rendered_edges[marker.get("cell", Vector2i(-1, -1))] = true
			"cliff_ramp":
				rendered_ramps[marker.get("cell", Vector2i(-1, -1))] = true
	assert_int(rendered_cells.size()).is_equal(feature_cells.size())
	for cell in feature_cells.keys():
		assert_bool(rendered_cells.has(cell)) \
			.override_failure_message("2D 图缺少规划器输出的悬崖格标记: %s" % cell).is_true()
	for cell in feature_edges.keys():
		assert_bool(rendered_edges.has(cell)) \
			.override_failure_message("2D 图缺少规划器输出的崖边标记: %s" % cell).is_true()
	for cell in feature_ramps.keys():
		assert_bool(rendered_ramps.has(cell)) \
			.override_failure_message("2D 图缺少规划器输出的悬崖坡道入口标记: %s" % cell).is_true()


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
				assert_float(absf(hazard.rotation_degrees.x)) \
					.override_failure_message("地面尖刺不应有 X 轴旋转: %s rotation=%s" % [hazard.name, hazard.rotation_degrees]) \
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
			assert_object(hazard.find_child("VoxelModel", true, false)) \
				.override_failure_message("酸液陷阱缺少体素视觉节点 VoxelModel: %s" % hazard.name) \
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
	# 陷阱 prefab 内部也可能有 Area3D/Node3D；只记录 prefab 根，避免把
	# 碰撞体或视觉组件误判成独立陷阱并重复断言。
	if node is SpikesTrap or node is AcidTrap or String(node.name) == "FlameVentTrap" \
		or node.has_meta("hazard_anchor") \
		or (node.has_meta("topdown_kind") and String(node.get_meta("topdown_kind")) == "hazard"):
		if node is Node3D:
			hazards.append(node as Node3D)
		return
	for child in node.get_children():
		_collect_hazard_nodes(child, hazards)


func _ensure_reports_dir() -> void:
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("reports")
