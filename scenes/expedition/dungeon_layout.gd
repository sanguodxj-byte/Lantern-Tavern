## DungeonLayout — 地牢生成的统一结果契约（阶段 1）。
#
# 设计原则（见地牢重构方案）：
#   - 纯 RefCounted，不持有任何 Godot 场景节点（Node/Node3D/PackedScene/Mesh/Material/Light3D/PhysicsBody3D）。
#   - prefab 通过稳定字符串/枚举 ID 引用，不直接 preload .tscn。
#   - 生成阶段产出此对象；场景实例化、streaming、runtime 都以它为输入。
#   - 关键点（player_spawn/extraction/boss）由生成器明确填入，调用方不再重复推导。
#
# 兼容：字段名与 isaac_room_dungeon_generator 的产出（grid/rooms/room_roles/ceiling_heights）对齐，
# procedural_dungeon.gd 的 _room_roles key（start/boss/extraction/stairs/reward）原样保留。
class_name DungeonLayout
extends RefCounted

# ── 生成元数据 ──────────────────────────────────────────────
var seed: int = 0
var zone: int = 0
var tile_size: float = 3.0
var width: int = 0
var height: int = 0
var algorithm: String = "isaac"  # 产出此布局的算法名，用于追溯

# ── 网格与地形 ──────────────────────────────────────────────
# grid: Array<Array<int>>，value 为 BSP_DungeonGenerator.TileType 枚举值
var grid: Array = []
# heights: Array<Array<float>>，每格天花板高度（米），与 grid 同形
var heights: Array = []
# rooms: Array[Rect2i]，所有房间矩形
var rooms: Array[Rect2i] = []
# room_roles: Dictionary<String, Rect2i>，特殊房间矩形，key ∈ {start,boss,extraction,stairs,reward}
var room_roles: Dictionary = {}

# ── 关键点（格坐标，未命中用 (-1,-1)）────────────────────────
var player_spawn_cell := Vector2i(-1, -1)
var extraction_cell := Vector2i(-1, -1)
var boss_cell := Vector2i(-1, -1)
var stairs_cell := Vector2i(-1, -1)
var reward_cell := Vector2i(-1, -1)

# ── 规划产物（Dictionary，稳定 ID，不含 Node/PackedScene）─────
# door_specs: Array<Dictionary>，每项 {inside:Vector2i, outside:Vector2i, dir:Vector2i, boss:bool}
var door_specs: Array[Dictionary] = []
# hazard_anchors: Array<Dictionary>，每项 {hazard_type:String, anchor_cell:Vector2i, direction:Vector2i, room_index:int, safe_approach_cells:Array, kick_lane:Dictionary}
var hazard_anchors: Array[Dictionary] = []
# kick_lanes: Array<Dictionary>，每项 {start:Vector2i, end:Vector2i, length_cells:int, hazard_index:int}
var kick_lanes: Array[Dictionary] = []
# terrain_features: Array<Dictionary>，大型房间地形特征（pillar_hall/great_hall 等）
var terrain_features: Array[Dictionary] = []

# ── 生规划产物（阶段 6 填充）────────────────────────────────
# enemy_spawn_specs: Array<Dictionary>，每项 {enemy_type:String, cell:Vector2i, room_index:int, is_elite:bool, zone:int}
var enemy_spawn_specs: Array[Dictionary] = []
# item_spawn_specs: Array<Dictionary>，每项 {item_type:String, item_id:String, cell:Vector2i, room_index:int}
var item_spawn_specs: Array[Dictionary] = []
# chest_spawn_specs: Array<Dictionary>，每项 {chest_type:String, cell:Vector2i, room_index:int}
var chest_spawn_specs: Array[Dictionary] = []


## 是否为空布局（未生成或生成失败）
func is_empty() -> bool:
	return grid.is_empty() or width <= 0 or height <= 0

## 网格在 (x,y) 是否为地板格（TileType.FLOOR == 1）
func is_floor_at(x: int, y: int) -> bool:
	if x < 0 or y < 0 or y >= grid.size() or x >= grid[y].size():
		return false
	return int(grid[y][x]) == 1

## 网格在 cell 是否为地板格
func is_floor_cell(cell: Vector2i) -> bool:
	return is_floor_at(cell.x, cell.y)

## 关键点是否已命中（未被设置）
func is_key_cell_missing(cell: Vector2i) -> bool:
	return cell.x < 0 or cell.y < 0

## cell 是否落在任一特殊 role 房间矩形内
func cell_role(cell: Vector2i) -> String:
	for key in room_roles.keys():
		if (room_roles[key] as Rect2i).has_point(cell):
			return String(key)
	return ""

## cell 是否落在 start 房间内
func is_start_room_cell(cell: Vector2i) -> bool:
	return room_roles.has("start") and (room_roles["start"] as Rect2i).has_point(cell)

## cell 是否落在 boss 房间内
func is_boss_room_cell(cell: Vector2i) -> bool:
	return room_roles.has("boss") and (room_roles["boss"] as Rect2i).has_point(cell)

## cell 是否落在 reward 房间内或 boss 房间内（boss 房间默认含 reward 检）
func is_boss_reward_cell(cell: Vector2i) -> bool:
	if room_roles.has("reward") and (room_roles["reward"] as Rect2i).has_point(cell):
		return true
	return is_boss_room_cell(cell)

## 深拷贝：grid/heights 逐层复制，避免共享内层数组
func duplicate_layout() -> DungeonLayout:
	var copy := DungeonLayout.new()
	copy.seed = seed
	copy.zone = zone
	copy.tile_size = tile_size
	copy.width = width
	copy.height = height
	copy.algorithm = algorithm
	copy.grid = grid.duplicate(true)
	copy.heights = heights.duplicate(true)
	copy.rooms = rooms.duplicate()
	copy.room_roles = {}
	for k in room_roles.keys():
		copy.room_roles[k] = room_roles[k]  # Rect2i 值类型直接赋值
	copy.player_spawn_cell = player_spawn_cell
	copy.extraction_cell = extraction_cell
	copy.boss_cell = boss_cell
	copy.stairs_cell = stairs_cell
	copy.reward_cell = reward_cell
	copy.door_specs = door_specs.duplicate(true)
	copy.hazard_anchors = hazard_anchors.duplicate(true)
	copy.kick_lanes = kick_lanes.duplicate(true)
	copy.terrain_features = terrain_features.duplicate(true)
	copy.enemy_spawn_specs = enemy_spawn_specs.duplicate(true)
	copy.item_spawn_specs = item_spawn_specs.duplicate(true)
	copy.chest_spawn_specs = chest_spawn_specs.duplicate(true)
	return copy

## 验证布局内部一致性。返回 Dictionary 报告：
##   {valid:bool, errors:Array[String], warnings:Array[String]}
## 不修改自身。第一版只报告，不修复。
func validate() -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var report := {"valid": true, "errors": errors, "warnings": warnings}

	if width <= 0 or height <= 0:
		report["valid"] = false
		errors.append("layout dimensions are zero (width=%d, height=%d)" % [width, height])
		return report
	if grid.size() != height:
		report["valid"] = false
		errors.append("grid row count %d != height %d" % [grid.size(), height])
	if not grid.is_empty() and grid[0].size() != width:
		report["valid"] = false
		errors.append("grid col count %d != width %d" % [grid[0].size(), width])
	if heights.size() != height or (not heights.is_empty() and heights[0].size() != width):
		report["valid"] = false
		errors.append("heights shape mismatch grid")
	# 关键点要么 (-1,-1) 未命中，要么必须落在网格内且为地板
	for label in ["player_spawn_cell", "extraction_cell", "boss_cell", "stairs_cell", "reward_cell"]:
		var cell: Vector2i = get(label)
		if is_key_cell_missing(cell):
			warnings.append("key cell %s not set" % label)
			continue
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
			report["valid"] = false
			errors.append("key cell %s=%s out of grid bounds" % [label, str(cell)])
			continue
		if not is_floor_cell(cell):
			warnings.append("key cell %s=%s not on floor" % [label, str(cell)])
	# player_spawn 与 boss 必须不是同一房间
	if not is_key_cell_missing(player_spawn_cell) and not is_key_cell_missing(boss_cell):
		if is_start_room_cell(boss_cell) or is_boss_room_cell(player_spawn_cell):
			report["valid"] = false
			errors.append("player_spawn and boss overlap same room")
	# 必须有 start role 房间
	if not room_roles.has("start"):
		report["valid"] = false
		errors.append("room_roles missing required 'start' role")
	if not room_roles.has("boss"):
		report["valid"] = false
		errors.append("room_roles missing required 'boss' role")
	# room_roles 的每个值必须是 Rect2i
	for k in room_roles.keys():
		if not (room_roles[k] is Rect2i):
			report["valid"] = false
			errors.append("room_roles['%s'] is not Rect2i" % k)
	# door_specs/hazard_anchors 等不能含 Node/PackedScene 引用（按设计禁止）
	for spec in door_specs:
		if _spec_contains_node_ref(spec):
			report["valid"] = false
			errors.append("door_spec contains Node/PackedScene reference: %s" % str(spec.keys()))
	for spec in hazard_anchors:
		if _spec_contains_node_ref(spec):
			report["valid"] = false
			errors.append("hazard_anchor contains Node/PackedScene reference")
	return report

## 检查 spec Dictionary 是否含被禁止的 Node/PackedScene 引用（生成阶段不允许）
func _spec_contains_node_ref(spec: Dictionary) -> bool:
	for k in spec.keys():
		var v = spec[k]
		if v is Node:
			return true
		if v is PackedScene:  # PackedScene 是 Resource 子类，单独判
			return true
	return false
