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
var generation_attempt: int = 1
var quality_report: Dictionary = {}

# ── 网格与地形 ──────────────────────────────────────────────
# grid: Array<Array<int>>，value 为 BSP_DungeonGenerator.TileType 枚举值
var grid: Array = []
# heights: Array<Array<float>>，每格天花板高度（米），以 float 存储但严格为整数米层，与 grid 同形
var heights: Array = []
# floor_elevations: Array<Array<float>>，每格可行走地面高度（米）；未配置时默认为 0
var floor_elevations: Array = []
# rooms: Array[Rect2i]，所有房间矩形
var rooms: Array[Rect2i] = []
var room_metadata: Array[Dictionary] = []
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
# terrain_features: Array<Dictionary>，大型房间地形特征（pillar_hall/great_hall/cliff 等）
var terrain_features: Array[Dictionary] = []
# decor_specs: 单格体素道具规划；只含稳定 prefab ID/路径与格坐标，不含 Node/资源实例
var decor_specs: Array[Dictionary] = []
var room_focus_specs: Array[Dictionary] = []
# room_composition_specs: 房间主题、掩体、高低差、悬崖、门前过渡和战斗扇区的纯数据描述
var room_composition_specs: Array[Dictionary] = []

# ── 生规划产物（阶段 6 填充）────────────────────────────────
# enemy_spawn_specs: Array<Dictionary>，附带 combat_role/sector/patrol_center_cell 等编排字段
var enemy_spawn_specs: Array[Dictionary] = []
# item_spawn_specs: Array<Dictionary>，每项 {item_type:String, item_id:String, cell:Vector2i, room_index:int}
var item_spawn_specs: Array[Dictionary] = []
# chest_spawn_specs: Array<Dictionary>，每项 {chest_type:String, cell:Vector2i, room_index:int}
var chest_spawn_specs: Array[Dictionary] = []


## 是否为空布局（未生成或生成失败）
func is_empty() -> bool:
	return grid.is_empty() or width <= 0 or height <= 0

## 推导玩家出生点的世界坐标（单格 → Vector3）。
## 这是【唯一】出生点算法来源：procedural_dungeon.gd（单人/真实场景路径）
## 与 DungeonSessionController（联机 listen-server / 专用服务器路径）都经本方法计算，
## 避免两端漂移导致权威出生点不一致（破坏跨进程地牢指纹与实体位置确定性）。
##   - 优先用 player_spawn_cell（生成器产出的确定性关键点）。
##   - 未命中时回退到 start 房间矩形中心（兼容老布局 / 单格缺失）。
##   - 都不可用时回退到原点 (0, 0.5, 0)。
func calc_player_spawn_pos() -> Vector3:
	if is_empty():
		return Vector3(0, 0.5, 0)
	if not is_key_cell_missing(player_spawn_cell):
		var offset_x: float = -(float(width) * tile_size) / 2.0
		var offset_z: float = -(float(height) * tile_size) / 2.0
		return Vector3(offset_x + player_spawn_cell.x * tile_size, 0.5, offset_z + player_spawn_cell.y * tile_size)
	if room_roles.has("start"):
		# 与 procedural_dungeon._rect_center_cell 的整数整除语义一致（奇尺寸房间下
		# 与 Rect2i.get_center() 的浮点中心结果不同，必须保持整数以不动真实游戏路径）。
		var start_rect: Rect2i = room_roles["start"]
		var center: Vector2i = start_rect.position + Vector2i(start_rect.size.x / 2, start_rect.size.y / 2)
		var offset_x: float = -(float(width) * tile_size) / 2.0
		var offset_z: float = -(float(height) * tile_size) / 2.0
		return Vector3(offset_x + center.x * tile_size, 0.5, offset_z + center.y * tile_size)
	return Vector3(0, 0.5, 0)

## 将格坐标转换为以地牢中心为原点的世界坐标。
## category 非空时，为实体应用稳定的格内偏移；空 category 保留地形格中心。
## 所有运行时生成器都应通过此入口计算位置，避免各自复制 OFFSET 公式。
func cell_to_world(cell: Vector2i, vertical_offset: float = 0.0,
		category: String = "", variant_index: int = 0) -> Vector3:
	var offset_x: float = -(float(width) * tile_size) / 2.0
	var offset_z: float = -(float(height) * tile_size) / 2.0
	var subcell := Vector2.ZERO
	if not category.is_empty():
		subcell = subcell_offset_for(category, cell, variant_index)
	return Vector3(
		offset_x + cell.x * tile_size + subcell.x,
		floor_height_at(cell) + vertical_offset,
		offset_z + cell.y * tile_size + subcell.y)

## 网格在 (x,y) 是否为可走格。
## 与 isaac `_is_walkable_grid_cell` 一致：FLOOR/LOOT/RESOURCE/PILLAR 均可走，
## 仅 EMPTY/WALL 不可走。旧实现只认 FLOOR==1，会导致 LOOT/RESOURCE 关键点“缺失”
## 以及可达比被严重低估。
func is_floor_at(x: int, y: int) -> bool:
	if x < 0 or y < 0 or y >= grid.size() or x >= grid[y].size():
		return false
	var cell_type := int(grid[y][x])
	return cell_type != 0 and cell_type != 2  # EMPTY=0, WALL=2

## 网格在 cell 是否为可走格
func is_floor_cell(cell: Vector2i) -> bool:
	return is_floor_at(cell.x, cell.y)

func floor_height_at(cell: Vector2i) -> float:
	if cell.y < 0 or cell.y >= floor_elevations.size():
		return 0.0
	if cell.x < 0 or cell.x >= floor_elevations[cell.y].size():
		return 0.0
	return float(floor_elevations[cell.y][cell.x])

## 返回实体在所属格内的确定性水平偏移（米）。
##
## 地图格的原点仍是地形盒体中心；只有可移动/可拾取/装饰实体使用该偏移，
## 从而保留网格拓扑，同时避免敌人、材料、宝箱和装饰全部叠在格中心。
## 偏移只依赖布局种子、类别、格坐标和同类序号，不读取全局 RNG，保证重放/联机一致。
func subcell_offset_for(category: String, cell: Vector2i, variant_index: int = 0) -> Vector2:
	var radius := minf(maxf(tile_size * 0.12, 0.08), 0.34)
	var hash_value := _subcell_hash(category, cell, variant_index)
	# 四个对角锚点让同一格内的不同类别自然分散；哈希只决定该类别的朝向。
	var anchors: Array[Vector2] = [
		Vector2(-1.0, -1.0),
		Vector2(1.0, -1.0),
		Vector2(1.0, 1.0),
		Vector2(-1.0, 1.0),
	]
	var category_phase := absi(category.hash()) % anchors.size()
	var anchor: Vector2 = anchors[(hash_value + category_phase) % anchors.size()]
	# 轻微轴向变化避免连续房间出现完全相同的棋盘纹理。
	if ((hash_value >> 2) & 1) == 1:
		anchor = Vector2(anchor.y, anchor.x)
	return anchor * radius

func _subcell_hash(category: String, cell: Vector2i, variant_index: int) -> int:
	var value: int = int(seed) & 0x7fffffff
	value = int((value * 1103515245 + cell.x * 374761393 + cell.y * 668265263) & 0x7fffffff)
	value = int((value + variant_index * 214013 + category.hash()) & 0x7fffffff)
	return value

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

## BFS 距离场：从 player_spawn_cell 在可走格上扩散，返回 {"x,y": 步数} 的 Dictionary。
## 用于“房间深度”估算（越深越险、喘息房选择）。player_spawn 缺失时返回空。
## 纯数据、无 Node 引用，规划期可安全调用。
func compute_floor_distance_field() -> Dictionary:
	var field := {}
	if is_key_cell_missing(player_spawn_cell):
		return field
	var start_key := "%d,%d" % [player_spawn_cell.x, player_spawn_cell.y]
	var queue: Array = [player_spawn_cell]
	var visited := {}
	visited[start_key] = true
	field[start_key] = 0
	while not queue.is_empty():
		var next_q: Array = []
		for c in queue:
			var c_key := "%d,%d" % [c.x, c.y]
			var d: int = int(field[c_key])
			for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var n: Vector2i = c + dir
				if n.x < 0 or n.y < 0 or n.y >= grid.size() or n.x >= grid[n.y].size():
					continue
				if not is_floor_cell(n):
					continue
				var n_key := "%d,%d" % [n.x, n.y]
				if visited.has(n_key):
					continue
				visited[n_key] = true
				field[n_key] = d + 1
				next_q.append(n)
		queue = next_q
	return field

## 房间到出生点的最近可走格 BFS 距离（借已算好的 field；无记录则回退曼哈顿距离）。
func depth_of_room_with_field(room: Rect2i, field: Dictionary) -> int:
	var best := -1
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			var cell := Vector2i(x, y)
			if not is_floor_cell(cell):
				continue
			var key := "%d,%d" % [cell.x, cell.y]
			if field.has(key):
				var d: int = int(field[key])
				if best < 0 or d < best:
					best = d
	if best < 0:
		var center := room.position + Vector2i(room.size.x / 2, room.size.y / 2)
		best = absi(center.x - player_spawn_cell.x) + absi(center.y - player_spawn_cell.y)
	return best

## 深拷贝：grid/heights 逐层复制，避免共享内层数组
func duplicate_layout() -> DungeonLayout:
	var copy := DungeonLayout.new()
	copy.seed = seed
	copy.zone = zone
	copy.tile_size = tile_size
	copy.width = width
	copy.height = height
	copy.algorithm = algorithm
	copy.generation_attempt = generation_attempt
	copy.quality_report = quality_report.duplicate(true)
	copy.grid = grid.duplicate(true)
	copy.heights = heights.duplicate(true)
	copy.floor_elevations = floor_elevations.duplicate(true)
	copy.rooms = rooms.duplicate()
	copy.room_metadata = room_metadata.duplicate(true)
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
	copy.decor_specs = decor_specs.duplicate(true)
	copy.room_focus_specs = room_focus_specs.duplicate(true)
	copy.room_composition_specs = room_composition_specs.duplicate(true)
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
	elif heights.size() == height and (heights.is_empty() or heights[0].size() == width):
		for y in range(heights.size()):
			for x in range(heights[y].size()):
				if not DungeonGenerationConfig.is_integer_height(float(heights[y][x])):
					report["valid"] = false
					errors.append("height at (%d,%d) is not an integer meter layer: %s" % [x, y, heights[y][x]])
	if not floor_elevations.is_empty() and (floor_elevations.size() != height or floor_elevations[0].size() != width):
		report["valid"] = false
		errors.append("floor_elevations shape mismatch grid")
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
	for spec in room_composition_specs:
		if _spec_contains_node_ref(spec):
			report["valid"] = false
			errors.append("room_composition_spec contains Node/PackedScene reference")
	for spec in terrain_features:
		if _spec_contains_node_ref(spec):
			report["valid"] = false
			errors.append("terrain_feature contains Node/PackedScene reference")
	for spec in decor_specs:
		var decor_err := _check_spawn_spec(spec, ["decor_kind", "scene_path", "cell", "room_index", "blocks_navigation"])
		if not decor_err.is_empty():
			report["valid"] = false
			errors.append("decor_spec: %s" % decor_err)
		elif not String(spec.get("scene_path", "")).begins_with("res://scenes/props/"):
			report["valid"] = false
			errors.append("decor_spec scene_path must be a voxel prop scene")
	# 阶段 9 条 8：spawn spec 完整性校验（字段完备、cell 在格内、不含 Node/PackedScene 引用）
	for spec in enemy_spawn_specs:
		var es_err := _check_spawn_spec(spec, ["enemy_type", "cell", "room_index", "is_elite", "zone"])
		if not es_err.is_empty():
			report["valid"] = false
			errors.append("enemy_spawn_spec: %s" % es_err)
	for spec in item_spawn_specs:
		var is_err := _check_spawn_spec(spec, ["item_type", "item_id", "cell", "room_index"])
		if not is_err.is_empty():
			report["valid"] = false
			errors.append("item_spawn_spec: %s" % is_err)
	for spec in chest_spawn_specs:
		var cs_err := _check_spawn_spec(spec, ["chest_type", "cell", "room_index"])
		if not cs_err.is_empty():
			report["valid"] = false
			errors.append("chest_spawn_spec: %s" % cs_err)
	return report

## 校验单个 spawn spec 的字段完备性 + cell 在格内 + 不含 Node/PackedScene 引用。
## 返回空 String 表示通过；否则返回错误描述。
func _check_spawn_spec(spec: Dictionary, required_keys: Array) -> String:
	if _spec_contains_node_ref(spec):
		return "contains Node/PackedScene reference"
	for k in required_keys:
		if not spec.has(k):
			return "missing required field '%s'" % k
	if spec.has("cell"):
		var cell: Vector2i = spec["cell"]
		if not (cell is Vector2i):
			return "'cell' is not Vector2i"
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
			return "cell %s out of grid bounds (w=%d, h=%d)" % [str(cell), width, height]
	return ""

## 检查 spec Dictionary 是否含被禁止的 Node/PackedScene 引用（生成阶段不允许）
func _spec_contains_node_ref(spec: Dictionary) -> bool:
	for k in spec.keys():
		var v = spec[k]
		if v is Node:
			return true
		if v is PackedScene:  # PackedScene 是 Resource 子类，单独判
			return true
	return false
