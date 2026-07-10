extends Node
## 地牢怪物生成器（autoload: DungeonSpawner）。
## 按房间类型分类生成怪物：普通房间生成弱怪/精英，BOSS 房间只生成 BOSS 类。
## 与 procedural_dungeon.gd 协作：地牢生成完毕后调用 spawn_enemies() 注入怪物。
##
## 怪物种类以体素模型为准（assets/meshes/characters/voxel_*.glb）：
## - goblin   (voxel_goblin_32px)   — 普通精英，持盾
## - rat      (voxel_rat_12px)      — 弱怪，速度快
## - skeleton (voxel_skeleton_48px) — 中等，持剑
## - slime    (voxel_slime_18px)    — 弱怪，近战
## - troll    (voxel_troll_64x)     — 普通怪，高血量大体型
## - necrolord(voxel_necrolord_80px)— BOSS 级，法系
## - dragon   (voxel_dragon_256px)  — BOSS 级，龙息
##
## BOSS 房间：龙和死灵领主二选一随机刷新
## 普通房间：所有 5 种普通怪按区域权重出现

const GOBLIN_PREFAB := preload("res://scenes/characters/enemies/goblin.tscn")
const RAT_PREFAB := preload("res://scenes/characters/enemies/rat.tscn")
const SKELETON_PREFAB := preload("res://scenes/characters/enemies/skeleton.tscn")
const SLIME_PREFAB := preload("res://scenes/characters/enemies/slime.tscn")
const TROLL_PREFAB := preload("res://scenes/characters/enemies/troll.tscn")
const NECROLORD_PREFAB := preload("res://scenes/characters/enemies/necrolord.tscn")
const DRAGON_PREFAB := preload("res://scenes/characters/enemies/dragon.tscn")

# BOSS 类怪物：只允许在 BOSS 房间生成（龙和死灵领主二选一）
const BOSS_TYPES := ["necrolord", "dragon"]
# 普通类怪物：可在任何非起始房间生成（巨魔降为普通怪）
const NORMAL_TYPES := ["goblin", "rat", "skeleton", "slime", "troll"]
const BODY_SIZE_BY_TYPE: Dictionary = {
	"rat": "small",
	"slime": "small",
	"goblin": "medium",
	"skeleton": "medium",
	"troll": "large",
	"necrolord": "large",
	"dragon": "huge",
}

# 各区域怪物配置（普通房间用）：弱怪权重 + 精英权重 + 数量倍率 + 属性倍率
# BOSS 房间使用 BOSS_ZONE_CONFIG
const ZONE_ENEMY_CONFIG: Dictionary = {
	0: {  # 幽暗地牢 — 最弱，适合初始
		"types": {"rat": 30, "slime": 25, "skeleton": 20, "goblin": 15, "troll": 10},
		"count_per_room": 1.5,
		"hp_mult": 0.8, "speed_mult": 0.9, "dmg_mult": 0.8,
		"boss": {"necrolord": 50, "dragon": 50},
	},
	1: {  # 寂静之森
		"types": {"rat": 25, "slime": 20, "skeleton": 20, "goblin": 20, "troll": 15},
		"count_per_room": 2.0,
		"hp_mult": 1.0, "speed_mult": 1.0, "dmg_mult": 1.0,
		"boss": {"necrolord": 50, "dragon": 50},
	},
	2: {  # 深邃洞窟
		"types": {"slime": 20, "skeleton": 25, "rat": 15, "goblin": 20, "troll": 20},
		"count_per_room": 2.5,
		"hp_mult": 1.2, "speed_mult": 1.1, "dmg_mult": 1.1,
		"boss": {"necrolord": 50, "dragon": 50},
	},
	3: {  # 荒芜墓园
		"types": {"skeleton": 25, "rat": 10, "slime": 15, "goblin": 25, "troll": 25},
		"count_per_room": 3.0,
		"hp_mult": 1.4, "speed_mult": 1.15, "dmg_mult": 1.3,
		"boss": {"necrolord": 50, "dragon": 50},
	},
	4: {  # 熔岩火山
		"types": {"skeleton": 15, "slime": 10, "rat": 5, "goblin": 30, "troll": 40},
		"count_per_room": 3.5,
		"hp_mult": 1.8, "speed_mult": 1.25, "dmg_mult": 1.5,
		"boss": {"necrolord": 50, "dragon": 50},
	},
	5: {  # 古代遗迹
		"types": {"skeleton": 10, "rat": 5, "slime": 5, "goblin": 35, "troll": 45},
		"count_per_room": 4.0,
		"hp_mult": 2.2, "speed_mult": 1.3, "dmg_mult": 1.8,
		"boss": {"necrolord": 50, "dragon": 50},
	},
}

# 怪物基础属性（各 .tscn 的 @export 默认值参考）
const BASE_HP: Dictionary = {
	"goblin": 10, "rat": 3, "skeleton": 12, "slime": 6,
	"troll": 20, "necrolord": 25, "dragon": 40,
}
const BASE_SPEED: Dictionary = {
	"goblin": 2.0, "rat": 3.5, "skeleton": 1.8, "slime": 1.5,
	"troll": 1.0, "necrolord": 1.3, "dragon": 0.8,
}

# 精英怪额外属性倍率
const ELITE_HP_MULT := 2.0
const ELITE_SPEED_MULT := 1.1
const ELITE_DMG_MULT := 1.5

## 在地牢房间内生成怪物。
## parent: 地牢节点；grid: 二维数组；zone: ZoneManager 区域 id；
## player: Player 实例；spawn_pos: 玩家出生点；
## tile_size: 格子尺寸；rooms: 所有房间矩形数组；room_roles: 房间角色字典。
func spawn_enemies(parent: Node, grid: Array, zone: int, player: Node, spawn_pos: Vector3, tile_size: float = 3.0, _offset: Vector3 = Vector3.ZERO, rooms: Array = [], room_roles: Dictionary = {}) -> Array:
	var config: Dictionary = ZONE_ENEMY_CONFIG.get(zone, ZONE_ENEMY_CONFIG[0])
	# 重算偏移（与 _generate_visuals 同公式）
	var grid_width: int = grid[0].size() if grid.size() > 0 else 0
	var grid_height: int = grid.size()
	var offset_x: float = -(float(grid_width) * tile_size) / 2.0
	var offset_z: float = -(float(grid_height) * tile_size) / 2.0
	var offset: Vector3 = Vector3(offset_x, 0, offset_z)

	var spawned: Array = []

	# 如果没有房间信息，回退到旧逻辑（全地图散布）
	if rooms.is_empty():
		spawned = _spawn_scattered(parent, grid, config, zone, player, spawn_pos, tile_size, offset)
		print("[DungeonSpawner] Spawned %d enemies (fallback scattered, zone %d)" % [spawned.size(), zone])
		return spawned

	# 按房间分类生成
	var start_room: Rect2i = room_roles.get("start", Rect2i())
	var boss_room: Rect2i = room_roles.get("boss", Rect2i())

	for room in rooms:
		var room_rect: Rect2i = room
		# 跳过起始房间
		if room_rect == start_room:
			continue
		# 收集该房间内的地板格
		var cell_positions: Array = _collect_room_floor_cells(grid, room_rect, tile_size, offset, spawn_pos)
		if cell_positions.is_empty():
			continue

		if room_rect == boss_room:
			# BOSS 房间：只生成 BOSS 类怪物
			spawned.append_array(_spawn_in_room(parent, cell_positions, config, zone, player, true))
		else:
			# 普通房间：只生成普通怪物
			spawned.append_array(_spawn_in_room(parent, cell_positions, config, zone, player, false))

	print("[DungeonSpawner] Spawned %d enemies (zone %d, rooms %d, boss_room %s)" % [spawned.size(), zone, rooms.size(), boss_room != Rect2i()])
	return spawned

## 阶段 9 接线：按 DungeonLayout.enemy_spawn_specs 实例化怪物，不再重读 grid/rooms/room_roles。
## layout: 已规划 enemy_spawn_specs 的 DungeonLayout（DungeonSpawnPlanner.plan_enemy_spawns 产出）
## spawn_root: 敌人节点容器（DungeonBuildResult.spawn_root）
## player: Player 实例，注入敌人 AI
## 倍率从 layout.zone 查 ZONE_ENEMY_CONFIG；boss 类型 spec.is_elite=true 走 elite 倍率。
func spawn_enemies_from_layout(layout: DungeonLayout, spawn_root: Node, player: Node) -> Array:
	var spawned: Array = []
	if layout == null or layout.is_empty() or spawn_root == null or not is_instance_valid(spawn_root):
		return spawned
	var zone_cfg: Dictionary = ZONE_ENEMY_CONFIG.get(layout.zone, ZONE_ENEMY_CONFIG[0])
	for spec in layout.enemy_spawn_specs:
		var enemy_type: String = spec["enemy_type"]
		var cell: Vector2i = spec["cell"]
		# 格坐标 → 世界坐标（与 procedural 的 OFFSET 公式一致：居中）
		var offset_x: float = -(float(layout.width) * layout.tile_size) / 2.0
		var offset_z: float = -(float(layout.height) * layout.tile_size) / 2.0
		var pos: Vector3 = Vector3(offset_x, 0.5, offset_z) + Vector3(cell.x * layout.tile_size, 0.0, cell.y * layout.tile_size)
		# boss 类型走 elite_ 前缀，触 _instantiate_enemy 的 is_elite 倍率链
		var instantiate_type: String = enemy_type
		if bool(spec.get("is_elite", false)) and not enemy_type.begins_with("elite_"):
			instantiate_type = "elite_" + enemy_type
		var enemy: Node = _instantiate_enemy(instantiate_type, pos, player, zone_cfg)
		spawn_root.add_child(enemy)
		enemy.global_position = pos
		spawned.append(enemy)
	print("[DungeonSpawner] Spawned %d enemies from layout specs (zone %d, specs %d)" % [spawned.size(), layout.zone, layout.enemy_spawn_specs.size()])
	return spawned

## 收集房间内所有地板格的世界坐标
func _collect_room_floor_cells(grid: Array, room: Rect2i, tile_size: float, offset: Vector3, spawn_pos: Vector3) -> Array:
	var positions: Array = []
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			if y < 0 or y >= grid.size() or x < 0 or x >= grid[y].size():
				continue
			if grid[y][x] == 1:  # FLOOR
				var pos: Vector3 = offset + Vector3(x * tile_size, 0.5, y * tile_size)
				# 起始房间附近的格子也跳过（额外安全距离）
				if pos.distance_to(spawn_pos) >= tile_size * 3.0:
					positions.append(pos)
	return positions

## 在房间内生成怪物
func _spawn_in_room(parent: Node, cell_positions: Array, config: Dictionary, zone: int, player: Node, is_boss_room: bool) -> Array:
	var spawned: Array = []
	if cell_positions.is_empty():
		return spawned

	var count_per_room: float = float(config.get("count_per_room", 1.5))
	# BOSS 房间：龙和死灵领主二选一，固定 1 只
	var count: int
	if is_boss_room:
		count = 1
	else:
		count = int(cell_positions.size() * count_per_room * 0.25)
		count = clampi(count, 1, 5)  # 每个普通房间 1-5 只

	# 打乱位置列表
	cell_positions.shuffle()

	for i in range(count):
		if cell_positions.is_empty():
			break
		var pos: Vector3 = cell_positions.pop_at(0)
		var enemy_type: String
		if is_boss_room:
			enemy_type = _pick_boss_type(config)
		else:
			enemy_type = _pick_enemy_type(config.types)
		var enemy: Node = _instantiate_enemy(enemy_type, pos, player, config)
		parent.add_child(enemy)
		enemy.global_position = pos
		spawned.append(enemy)

	return spawned

## 旧逻辑：无房间信息时全地图散布生成
func _spawn_scattered(parent: Node, grid: Array, config: Dictionary, zone: int, player: Node, spawn_pos: Vector3, tile_size: float, offset: Vector3) -> Array:
	var enemy_positions: Array = _collect_enemy_spawn_positions(grid, spawn_pos, tile_size, offset)
	var count: int = int(enemy_positions.size() * float(config.get("count_per_room", 1.5)) * 0.3)
	count = clampi(count, 4, 16)
	var spawned: Array = []
	for i in range(count):
		if enemy_positions.is_empty():
			break
		var idx: int = randi() % enemy_positions.size()
		var pos: Vector3 = enemy_positions.pop_at(idx)
		var enemy_type: String = _pick_enemy_type(config.types)
		var enemy: Node = _instantiate_enemy(enemy_type, pos, player, config)
		parent.add_child(enemy)
		enemy.global_position = pos
		spawned.append(enemy)
	return spawned

## 收集适合刷怪的地板格子（远离玩家出生点，避免出生房刷怪）
func _collect_enemy_spawn_positions(grid: Array, spawn_pos: Vector3, tile_size: float, offset: Vector3) -> Array:
	var positions: Array = []
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if grid[y][x] == 1:  # FLOOR
				var pos: Vector3 = offset + Vector3(x * tile_size, 0.5, y * tile_size)
				if pos.distance_to(spawn_pos) >= tile_size * 4.0:
					positions.append(pos)
	return positions

## 按权重随机选择普通怪物种类
func _pick_enemy_type(types: Dictionary) -> String:
	var total: float = 0.0
	for k in types.keys():
		total += float(types[k])
	var roll: float = randf() * total
	var acc: float = 0.0
	for k in types.keys():
		acc += float(types[k])
		if roll <= acc:
			return k
	return types.keys()[0]

## 按权重随机选择 BOSS 类怪物种类（龙和死灵领主二选一）
func _pick_boss_type(config: Dictionary) -> String:
	var boss_config: Dictionary = config.get("boss", {"necrolord": 50, "dragon": 50})
	var total: float = 0.0
	for k in boss_config.keys():
		total += float(boss_config[k])
	var roll: float = randf() * total
	var acc: float = 0.0
	for k in boss_config.keys():
		acc += float(boss_config[k])
		if roll <= acc:
			return "elite_" + k
	return "elite_" + String(boss_config.keys()[0])

## 实例化怪物并应用区域属性倍率
## enemy_type 格式: "rat" / "skeleton" / "elite_goblin" / "elite_dragon"
func _instantiate_enemy(enemy_type: String, pos: Vector3, player: Node, config: Dictionary) -> Node:
	var is_elite := enemy_type.begins_with("elite_")
	var base_type := enemy_type.trim_prefix("elite_")
	var prefab: PackedScene = _get_enemy_prefab(base_type)
	var enemy: Node = prefab.instantiate()
	# 标记怪物类型（含 elite_ 前缀），供测试与运行时验证
	enemy.set_meta("enemy_type", enemy_type)
	enemy.set_meta("enemy_base_type", base_type)
	enemy.set_meta("is_boss_type", BOSS_TYPES.has(base_type))
	enemy.set_meta("is_boss", BOSS_TYPES.has(base_type))
	enemy.set_meta("enemy_rank", "boss" if BOSS_TYPES.has(base_type) else ("elite" if is_elite else "normal"))
	enemy.set_meta("body_size", get_body_size(base_type))
	# 注入 player 引用（敌人 AI 追击需要；用 set_meta 避免类型/信号错误）
	enemy.set_meta("player_ref", player)
	enemy.set_meta("spawn_pos", pos)
	# 应用区域属性倍率
	var zone_hp_mult: float = float(config.get("hp_mult", 1.0))
	var zone_spd_mult: float = float(config.get("speed_mult", 1.0))
	if is_elite:
		enemy.set_meta("hp_mult", zone_hp_mult * ELITE_HP_MULT)
		enemy.set_meta("speed_mult", zone_spd_mult * ELITE_SPEED_MULT)
		enemy.set("is_elite", true)
	else:
		enemy.set_meta("hp_mult", zone_hp_mult)
		enemy.set_meta("speed_mult", zone_spd_mult)
	enemy.set_meta("dmg_mult", float(config.get("dmg_mult", 1.0)) * (ELITE_DMG_MULT if is_elite else 1.0))
	return enemy

## 根据怪物类型获取对应预制体场景
static func _get_enemy_prefab(base_type: String) -> PackedScene:
	match base_type:
		"goblin":
			return GOBLIN_PREFAB
		"rat":
			return RAT_PREFAB
		"skeleton":
			return SKELETON_PREFAB
		"slime":
			return SLIME_PREFAB
		"troll":
			return TROLL_PREFAB
		"necrolord":
			return NECROLORD_PREFAB
		"dragon":
			return DRAGON_PREFAB
		_:
			return GOBLIN_PREFAB

## 获取区域怪物配置（供 UI/测试查询）
func get_zone_config(zone: int) -> Dictionary:
	return ZONE_ENEMY_CONFIG.get(zone, ZONE_ENEMY_CONFIG[0])

## 获取所有体素模型怪物种类列表（供 UI/测试查询）
func get_all_enemy_types() -> Array:
	return ["goblin", "rat", "skeleton", "slime", "troll", "necrolord", "dragon"]

## 获取 BOSS 类怪物种类列表
func get_boss_types() -> Array:
	return BOSS_TYPES.duplicate()

## 获取普通类怪物种类列表
func get_normal_types() -> Array:
	return NORMAL_TYPES.duplicate()

func get_body_size(enemy_type: String) -> String:
	var base_type: String = enemy_type.trim_prefix("elite_")
	return String(BODY_SIZE_BY_TYPE.get(base_type, "medium"))

## 判断怪物类型是否为 BOSS 类
func is_boss_type(enemy_type: String) -> bool:
	var base_type: String = enemy_type.trim_prefix("elite_")
	return BOSS_TYPES.has(base_type)
