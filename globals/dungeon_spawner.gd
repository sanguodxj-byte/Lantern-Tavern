extends Node
## 地牢怪物生成器（autoload: DungeonSpawner）。
## 按 ZoneManager 区域配置怪物种类、数量、属性，在地牢生成后批量实例化。
## 与 procedural_dungeon.gd 协作：地牢生成完毕后调用 spawn_enemies() 注入怪物。
##
## 策划案对齐：
## - 幽暗森林(difficulty 1): goblin 为主，少量 kobold
## - 深邃洞窟(difficulty 2): kobold 为主，少量 goblin
## - 荒芜墓园(difficulty 3): kobold + goblin 混合，属性强化
## - 熔岩火山(difficulty 4): 全 kobold，属性大幅强化

const GOBLIN_PREFAB := preload("res://scenes/characters/enemies/goblin.tscn")
const KOBOLD_PREFAB := preload("res://scenes/characters/enemies/kobold.tscn")

# 各区域怪物配置：种类权重 + 数量倍率 + 属性倍率
const ZONE_ENEMY_CONFIG: Dictionary = {
	0: {  # 幽暗森林
		"types": {"goblin": 70, "kobold": 30},
		"count_per_room": 1.5,
		"hp_mult": 1.0, "speed_mult": 1.0, "dmg_mult": 1.0,
	},
	1: {  # 深邃洞窟
		"types": {"goblin": 40, "kobold": 60},
		"count_per_room": 2.0,
		"hp_mult": 1.2, "speed_mult": 1.1, "dmg_mult": 1.1,
	},
	2: {  # 荒芜墓园
		"types": {"goblin": 50, "kobold": 50},
		"count_per_room": 2.5,
		"hp_mult": 1.4, "speed_mult": 1.15, "dmg_mult": 1.3,
	},
	3: {  # 熔岩火山
		"types": {"kobold": 100},
		"count_per_room": 3.0,
		"hp_mult": 1.8, "speed_mult": 1.25, "dmg_mult": 1.5,
	},
}

# 怪物基础属性（goblin.tscn/kobold.tscn 的 @export 默认值参考）
const GOBLIN_BASE_HP := 10
const KOBOLD_BASE_HP := 10
const GOBLIN_BASE_SPEED := 2.0
const KOBOLD_BASE_SPEED := 2.5

## 在地牢 floor 格子（grid[y][x]==1）批量生成怪物。
## parent: 地牢节点；grid: BSP 二维数组；zone: ZoneManager 区域 id；
## player: Player 实例（注入到 enemy.player）；spawn_pos: 玩家出生点（含地牢偏移，避免怪物刷在玩家脸上）。
## tile_size: 格子尺寸；偏移由 grid 尺寸自行重算（与 procedural_dungeon._generate_visuals 对齐）。
func spawn_enemies(parent: Node, grid: Array, zone: int, player: Node, spawn_pos: Vector3, tile_size: float = 3.0, _offset: Vector3 = Vector3.ZERO) -> Array:
	var config: Dictionary = ZONE_ENEMY_CONFIG.get(zone, ZONE_ENEMY_CONFIG[0])
	# 重算偏移（与 _generate_visuals 同公式），确保与 player_spawn_pos/cell_pos 对齐
	var grid_width: int = grid[0].size() if grid.size() > 0 else 0
	var grid_height: int = grid.size()
	var offset_x: float = -(float(grid_width) * tile_size) / 2.0
	var offset_z: float = -(float(grid_height) * tile_size) / 2.0
	var offset: Vector3 = Vector3(offset_x, 0, offset_z)
	var enemy_positions: Array = _collect_enemy_spawn_positions(grid, spawn_pos, tile_size, offset)
	var count: int = int(enemy_positions.size() * float(config.get("count_per_room", 1.5)) * 0.3)
	count = clampi(count, 3, 12)  # 最少 3 只，最多 12 只
	var spawned: Array = []
	for i in range(count):
		if enemy_positions.is_empty():
			break
		var idx: int = randi() % enemy_positions.size()
		var pos: Vector3 = enemy_positions.pop_at(idx)
		var enemy_type: String = _pick_enemy_type(config.types)
		var enemy: Node = _instantiate_enemy(enemy_type, pos, player, config)
		parent.add_child(enemy)
		# 入树后设置位置（避免 !is_inside_tree 警告）
		enemy.global_position = pos
		spawned.append(enemy)
	print("[DungeonSpawner] Spawned %d enemies (zone %d, type %s)" % [spawned.size(), zone, config.types])
	return spawned

## 收集适合刷怪的地板格子（远离玩家出生点 >= 6 米）
func _collect_enemy_spawn_positions(grid: Array, spawn_pos: Vector3, tile_size: float, offset: Vector3) -> Array:
	var positions: Array = []
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if grid[y][x] == 1:  # FLOOR
				var pos: Vector3 = offset + Vector3(x * tile_size, 0.5, y * tile_size)
				if pos.distance_to(spawn_pos) >= 6.0:
					positions.append(pos)
	return positions

## 按权重随机选择怪物种类
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

## 实例化怪物并应用区域属性倍率
func _instantiate_enemy(enemy_type: String, pos: Vector3, player: Node, config: Dictionary) -> Node:
	var prefab: PackedScene = GOBLIN_PREFAB if enemy_type == "goblin" else KOBOLD_PREFAB
	var enemy: Node = prefab.instantiate()
	# 注入 player 引用（敌人 AI 追击需要；用 set_meta 避免类型/信号错误）
	enemy.set_meta("player_ref", player)
	enemy.set_meta("spawn_pos", pos)
	enemy.set_meta("hp_mult", float(config.get("hp_mult", 1.0)))
	enemy.set_meta("speed_mult", float(config.get("speed_mult", 1.0)))
	return enemy

## 获取区域怪物配置（供 UI/测试查询）
func get_zone_config(zone: int) -> Dictionary:
	return ZONE_ENEMY_CONFIG.get(zone, ZONE_ENEMY_CONFIG[0])
