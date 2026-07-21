class_name SetPieceRoom
extends Resource

## 作者化「房间印章」：手工设计的特殊房间，作为数据资源可被编辑/增删，无需改生成代码。
## tile_pattern 在 isaac 生成时被「盖章」进地牢网格，经 DungeonSceneBuilder 现有瓦片→节点管道实例化。
## 本资源是纯数据，不持有任何 Node/PackedScene（遵守 DungeonLayout 契约的 no-Node 原则）。
##
## 设计依据：docs/set_piece_room_design.md §4.1。数据模型外置自 WFC_RoomGenerator.RoomTemplate（wfc_generator.gd:15）。

# 瓦片类型与 BSP/WFC 同枚举（见 bsp_generator.gd / wfc_generator.gd）。
# 0=EMPTY 1=FLOOR 2=WALL 3=LOOT 4=RESOURCE 5=PILLAR；-1=ANY（交由 isaac 决定，默认雕为 FLOOR）。
const TILE_EMPTY := 0
const TILE_FLOOR := 1
const TILE_WALL := 2
const TILE_LOOT := 3
const TILE_RESOURCE := 4
const TILE_PILLAR := 5
const TILE_ANY := -1

@export var id: String = ""                          # 唯一 ID，如 "boss_arena_cruciform"
@export var display_name: String = ""

# tile_pattern[y][x]: int（TileType 或 ANY）。边界（首末行/列）必须为 WALL。
# 保持为无类型 Array 以兼容 .tres 嵌套数组序列化（与 WFC RoomTemplate.layout 同做法）。
@export var tile_pattern: Array = []

# door_anchors：连接锚点（局部瓦片坐标，相对 tile_pattern 左上角）。
# 每项 {edge:String("N"|"S"|"E"|"W"), cell:Vector2i(local), dir:Vector2i(朝外单位向量)}
@export var door_anchors: Array[Dictionary] = []

@export var weight: float = 1.0                      # 被选权重（越大越常出现）
@export var allowed_zones: Array[int] = []           # 空=所有 zone
@export var min_depth: int = 0                        # 距出生点最小 BFS 深度（格）
@export var max_depth: int = 999999                  # 距出生点最大 BFS 深度
@export var required_role: String = ""               # ""/"boss"/"extraction"/"reward"/"stairs" —— 强占该 role 的 macro 槽
@export var blocked_roles: Array[String] = []        # 不可出现在这些 role 房间（如 "start" 不放陷阱房）
@export var spawn_overrides: Dictionary = {}         # {enemy:Array, item:Array, chest:Array} 覆盖默认 spawn 规划
@export var ceiling_height: float = 3.4              # 该房间天花板高度（覆盖 zone 默认）

## 由 tile_pattern 尺寸推导占用的 macro 格数（每 macro = ROOM_SPACING 瓦片，含缓冲）。
## 不存储 footprint，避免与 ROOM_SPACING 常量重复耦合（注入时读 IsaacRoomDungeonGenerator.ROOM_SPACING）。
func macro_footprint(spacing: int) -> Vector2i:
	var h: int = tile_pattern.size()
	if h <= 0:
		return Vector2i(1, 1)
	var w: int = (tile_pattern[0] as Array).size()
	var fx: int = int(ceil(float(w) / float(spacing)))
	var fy: int = int(ceil(float(h) / float(spacing)))
	return Vector2i(fx, fy)

## 校验：图案矩形、边界为 WALL、door_anchor 在界内。用于编辑器/测试期与注册表加载门禁。
func is_valid() -> bool:
	if tile_pattern.is_empty():
		return false
	var h: int = tile_pattern.size()
	var w: int = (tile_pattern[0] as Array).size()
	if w <= 0:
		return false
	for row in tile_pattern:
		if (row as Array).size() != w:
			return false
	# 边界必须是 WALL
	var top := tile_pattern[0] as Array
	var bottom := tile_pattern[h - 1] as Array
	for x in range(w):
		if int(top[x]) != TILE_WALL or int(bottom[x]) != TILE_WALL:
			return false
	for y in range(h):
		var row_y := tile_pattern[y] as Array
		if int(row_y[0]) != TILE_WALL or int(row_y[w - 1]) != TILE_WALL:
			return false
	for a in door_anchors:
		var c: Vector2i = a.get("cell", Vector2i(-1, -1))
		if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
			return false
	return true
