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
const LAYOUT_QUALITY := preload("res://scenes/expedition/dungeon_layout_quality.gd")
const MAX_QUALITY_ATTEMPTS := 4

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
	var seed_source := RandomNumberGenerator.new()
	if config.seed != 0:
		seed_source.seed = config.seed
	else:
		seed_source.randomize()
	var base_seed: int = seed_source.seed
	var best_layout: DungeonLayout = null
	var best_score := -1.0
	for attempt in range(MAX_QUALITY_ATTEMPTS):
		var attempt_seed := base_seed + attempt * 104729
		var layout := _build_isaac_layout(config, attempt_seed)
		var quality := LAYOUT_QUALITY.evaluate(layout)
		layout.quality_report = quality
		layout.generation_attempt = attempt + 1
		var score := _quality_score(quality)
		if best_layout == null or score > best_score:
			best_layout = layout
			best_score = score
		if bool(quality["valid"]):
			return layout
	push_warning("[DungeonGenerator] quality gate exhausted; using best layout score=%.3f report=%s" % [best_score, best_layout.quality_report])
	return best_layout

func _build_isaac_layout(config: DungeonGenerationConfig, generation_seed: int) -> DungeonLayout:
	var gen: Node = load(ISAAC_PATH).new()
	var rng := RandomNumberGenerator.new()
	rng.seed = generation_seed
	gen.set_rng(rng)
	var grid: Array = gen.generate_dungeon(config.width, config.height, config.target_room_count)
	var layout := DungeonLayout.new()
	layout.seed = config.seed if config.seed != 0 else generation_seed
	layout.zone = config.zone
	layout.tile_size = config.tile_size
	layout.width = config.width
	layout.height = config.height
	layout.algorithm = "isaac"
	layout.grid = grid
	layout.heights = DungeonGenerationConfig.normalize_height_grid(gen.ceiling_heights)
	layout.rooms = (gen.rooms).duplicate()
	layout.room_metadata = gen.room_metadata.duplicate(true)
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

func _quality_score(report: Dictionary) -> float:
	return clampf(
		float(report.get("walkable_ratio", 0.0)) * 1.5
		+ float(report.get("reachable_ratio", 0.0))
		+ minf(float(report.get("main_path_cells", 0)) / 30.0, 1.0)
		+ minf(float(report.get("room_count", 0)) / 18.0, 1.0) * 0.5,
		0.0,
		4.0
	)

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
		layout.heights = DungeonGenerationConfig.normalize_height_grid(gen.get("ceiling_heights"))
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
## player_spawn：优先 start 房中心格（若可走），否则首个可走格（行优先遍历）。
## 可走语义与 DungeonLayout.is_floor_cell / isaac walkable 一致（含 LOOT/RESOURCE/PILLAR）。
func _derive_player_spawn_cell(layout: DungeonLayout) -> Vector2i:
	var preferred := Vector2i(-1, -1)
	if layout.room_roles.has("start"):
		preferred = _rect_center_cell(layout.room_roles["start"])
		# preferred 必须可走才用，否则降级到首个可走格
		if preferred.x >= 0 and preferred.y >= 0 and layout.is_floor_cell(preferred):
			return preferred
	# 行优先遍历找首个可走格
	for y in range(layout.grid.size()):
		for x in range(layout.grid[y].size()):
			if layout.is_floor_at(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

## role 房间中心格：优先 room_roles[role] 中心（若可走），否则该 Rect 内首个可走格。
## 与 procedural_dungeon.gd:_spawn_extraction_portal / _spawn_downstairs_portal 的“先试中心、再扫 Rect”语义一致。
func _derive_role_center_cell(layout: DungeonLayout, role: String) -> Vector2i:
	if not layout.room_roles.has(role):
		return Vector2i(-1, -1)
	var room: Rect2i = layout.room_roles[role]
	var center := _rect_center_cell(room)
	if layout.is_floor_cell(center):
		return center
	# 中心不可走：扫 Rect 内首个可走格
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
