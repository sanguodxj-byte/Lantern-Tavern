## DungeonGenerator — 统一地牢生成出口（阶段 3）。
#
# 职责：按 DungeonGenerationConfig.algorithm 选择 isaac/wfc/bsp 旧生成器，
# 把它们的散落产出（grid/rooms/room_roles/heights）包装进 DungeonLayout，
# 并复刻 procedural_dungeon.gd 的关键点推导语义（player_spawn/extraction/boss/stairs/reward cell），
# 使调用方不再需要“重复解释”生成结果。
#
# 严格遵守：生成阶段不创建 Godot 场景节点（见重构方案原则 3）。
# 不修改 isaac/wfc/bsp 生成器内部；只做包装 + 数据推导。
class_name DungeonGenerator
extends RefCounted

const ISAAC_PATH := "res://scenes/expedition/isaac_room_dungeon_generator.gd"
const BSP_PATH := "res://scenes/expedition/bsp_generator.gd"
const WFC_PATH := "res://scenes/expedition/wfc_generator.gd"

## 按配置生成地牢布局。失败时返回空 DungeonLayout（is_empty()==true）。
## 不抛异常；调用方应检查 layout.is_empty() 与 layout.validate()。
func generate(config: DungeonGenerationConfig) -> DungeonLayout:
	var report := config.validate()
	if not report["valid"]:
		push_warning("[DungeonGenerator] config invalid: %s" % str(report["errors"]))
		return DungeonLayout.new()
	match config.algorithm:
		"isaac":
			return _generate_with_isaac(config)
		"bsp":
			return _generate_with_bsp(config)
		"wfc":
			return _generate_with_wfc(config)
		_:
			return _generate_with_isaac(config)


# ── isaac 包装 ──────────────────────────────────────────────
func _generate_with_isaac(config: DungeonGenerationConfig) -> DungeonLayout:
	var gen: Node = load(ISAAC_PATH).new()
	# isaac 当前无 seed 字段、用全局 randi()/randf() —— 本包装层不修改其内部，
	# 阶段 11 再给 isaac 补 RandomNumberGenerator 注入能力。
	# 这里把 config.seed 仅记入 layout.seed 供追溯，不能真正固定复现。
	var grid: Array = gen.generate_dungeon(config.width, config.height, config.target_room_count)
	var layout := DungeonLayout.new()
	layout.seed = config.seed
	layout.zone = config.zone
	layout.tile_size = config.tile_size
	layout.width = config.width
	layout.height = config.height
	layout.algorithm = "isaac"
	layout.grid = grid
	layout.heights = (gen.ceiling_heights).duplicate(true)
	layout.rooms = (gen.rooms).duplicate()
	layout.room_roles = {}
	for k in gen.room_roles.keys():
		layout.room_roles[k] = gen.room_roles[k]  # Rect2i 值类型直接赋
	# 推导关键点（复刻 procedural_dungeon.gd 语义，不创建节点）
	layout.player_spawn_cell = _derive_player_spawn_cell(layout)
	layout.extraction_cell = _derive_role_center_cell(layout, "extraction")
	layout.boss_cell = _derive_role_center_cell(layout, "boss")
	layout.stairs_cell = _derive_role_center_cell(layout, "stairs")
	layout.reward_cell = _derive_role_center_cell(layout, "reward")
	gen.free()
	return layout

# ── bsp 包装（bsp 无 room_roles，关键点全 (-1,-1)，由 connectivity validator 报告）────
func _generate_with_bsp(config: DungeonGenerationConfig) -> DungeonLayout:
	var gen: Node = load(BSP_PATH).new()
	# bsp generate_dungeon(width, height, target_room_count, seed) — 旧实现签名各异，保守调
	var grid: Array = []
	if gen.has_method("generate_dungeon"):
		grid = gen.generate_dungeon(config.width, config.height)
	var layout := DungeonLayout.new()
	layout.seed = config.seed
	layout.zone = config.zone
	layout.tile_size = config.tile_size
	layout.width = config.width
	layout.height = config.height
	layout.algorithm = "bsp"
	layout.grid = grid
	layout.heights = []
	if gen.get("ceiling_heights") != null:
		layout.heights = (gen.get("ceiling_heights")).duplicate(true)
	layout.rooms = []
	if gen.get("rooms") != null:
		for r in gen.get("rooms"):
			layout.rooms.append(r)
	layout.room_roles = {}  # bsp 无 role 概念
	gen.free()
	return layout

# ── wfc 包装（wfc 输出同样无 room_roles；关键点由 validator 报告缺失）────
func _generate_with_wfc(config: DungeonGenerationConfig) -> DungeonLayout:
	var gen: Node = load(WFC_PATH).new()
	var grid: Array = []
	if gen.has_method("generate"):
		grid = gen.generate(config.width, config.height)
	elif gen.has_method("generate_dungeon"):
		grid = gen.generate_dungeon(config.width, config.height)
	var layout := DungeonLayout.new()
	layout.seed = config.seed
	layout.zone = config.zone
	layout.tile_size = config.tile_size
	layout.width = config.width
	layout.height = config.height
	layout.algorithm = "wfc"
	layout.grid = grid
	layout.heights = []
	layout.rooms = []
	layout.room_roles = {}
	gen.free()
	return layout


# ── 关键点推导（复刻 procedural_dungeon.gd 语义）──────────────────
## player_spawn：优先 start 房中心格（若该格为 FLOOR），否则首个 FLOOR 格（行优先遍历）。
## 与 procedural_dungeon.gd:633-730 一致：preferred = start center；遍历命中 cell_type==1。
func _derive_player_spawn_cell(layout: DungeonLayout) -> Vector2i:
	var preferred := Vector2i(-1, -1)
	if layout.room_roles.has("start"):
		preferred = _rect_center_cell(layout.room_roles["start"])
		# preferred 必须是 FLOOR 才用，否则降级到首个 FLOOR
		if preferred.x >= 0 and preferred.y >= 0 and layout.is_floor_cell(preferred):
			return preferred
	# 行优先遍历找首个 FLOOR 格（与 procedural_dungeon.gd 的嵌套 for y/x 顺序一致）
	for y in range(layout.grid.size()):
		for x in range(layout.grid[y].size()):
			if int(layout.grid[y][x]) == 1:  # TileType.FLOOR
				return Vector2i(x, y)
	return Vector2i(-1, -1)

## role 房间中心格：优先 room_roles[role] 中心（若 FLOOR），否则该 Rect 内首个 FLOOR 格。
## 与 procedural_dungeon.gd:_spawn_extraction_portal / _spawn_downstairs_portal 的“先试中心、再扫 Rect”语义一致。
func _derive_role_center_cell(layout: DungeonLayout, role: String) -> Vector2i:
	if not layout.room_roles.has(role):
		return Vector2i(-1, -1)
	var room: Rect2i = layout.room_roles[role]
	var center := _rect_center_cell(room)
	if layout.is_floor_cell(center):
		return center
	# 中心非 FLOOR：扫 Rect 内首个 FLOOR 格
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			if layout.is_floor_at(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _rect_center_cell(rect: Rect2i) -> Vector2i:
	return Vector2i(
		rect.position.x + rect.size.x / 2,
		rect.position.y + rect.size.y / 2,
	)
