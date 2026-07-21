extends Node
## 地牢怪物生成器（autoload: DungeonSpawner）。
## 按房间类型分类生成怪物：普通房间生成弱怪/精英，BOSS 房间只生成 BOSS 类。
## 与 procedural_dungeon.gd 协作：地牢生成完毕后调用 spawn_enemies() 注入怪物。
##
## data/enemy_roster.json 声明完整重建队列；CharacterModelTiers.ACCEPTED_IDS
## 是唯一允许运行时加载和生成的子集。

const ROSTER_PATH := "res://data/enemy_roster.json"
const MODEL_TIERS := preload("res://data/character_model_tiers.gd")

## 用于单元测试：如果为 true，则实例化普通的 CharacterBody3D 节点，不加载完整怪物预制件
var use_mock_nodes := false

# 运行时由 _ready 从 roster 填充
var _roster: Dictionary = {}
var _enemies_by_id: Dictionary = {}  # id -> entry
var _prefabs: Dictionary = {}  # id -> PackedScene
var BOSS_TYPES: Array = []
var NORMAL_TYPES: Array = []
var BODY_SIZE_BY_TYPE: Dictionary = {}
var ZONE_ENEMY_CONFIG: Dictionary = {}
var BASE_HP: Dictionary = {}
var BASE_SPEED: Dictionary = {}

# 精英怪额外属性倍率
const ELITE_HP_MULT := 2.0
const ELITE_SPEED_MULT := 1.1
const ELITE_DMG_MULT := 1.5

func _ready() -> void:
	_load_roster()


func _load_roster() -> void:
	if not FileAccess.file_exists(ROSTER_PATH):
		push_error("[DungeonSpawner] missing roster: %s" % ROSTER_PATH)
		_fallback_minimal_roster()
		return
	var file := FileAccess.open(ROSTER_PATH, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[DungeonSpawner] roster JSON parse failed")
		_fallback_minimal_roster()
		return
	_roster = json.data as Dictionary
	_enemies_by_id.clear()
	_prefabs.clear()
	BOSS_TYPES.clear()
	NORMAL_TYPES.clear()
	BODY_SIZE_BY_TYPE.clear()
	BASE_HP.clear()
	BASE_SPEED.clear()

	var declared_bosses: Dictionary = {}
	for t in _roster.get("boss_types", []):
		declared_bosses[String(t)] = true

	for entry in _roster.get("enemies", []):
		var eid: String = String(entry.get("id", ""))
		if eid.is_empty() or not MODEL_TIERS.is_accepted(eid):
			continue
		_enemies_by_id[eid] = entry
		BODY_SIZE_BY_TYPE[eid] = String(entry.get("body_size", "medium"))
		BASE_HP[eid] = int(entry.get("hp", 10))
		BASE_SPEED[eid] = float(entry.get("speed", 2.0))
		if declared_bosses.has(eid):
			BOSS_TYPES.append(eid)
		else:
			NORMAL_TYPES.append(eid)
		# 仅登记路径；PackedScene 懒加载，避免 headless 一次载入全部蒙皮 GLB 崩溃

	ZONE_ENEMY_CONFIG.clear()
	var zw: Dictionary = _roster.get("zone_weights", {})
	for zone_key in zw.keys():
		var zid: int = int(zone_key)
		var zcfg: Dictionary = zw[zone_key]
		# 未通过独立美术验收的 roster 条目只保留声明，不进入运行时权重。
		var types: Dictionary = {}
		for k in zcfg.get("types", {}).keys():
			var enemy_id := String(k)
			var w: float = float(zcfg["types"][k])
			if w <= 0.0 or not NORMAL_TYPES.has(enemy_id):
				continue
			types[enemy_id] = w
		var boss: Dictionary = {}
		for k in zcfg.get("boss", {}).keys():
			var boss_id := String(k)
			var w2: float = float(zcfg["boss"][k])
			if w2 <= 0.0 or not BOSS_TYPES.has(boss_id):
				continue
			boss[boss_id] = w2
		ZONE_ENEMY_CONFIG[zid] = {
			"types": types,
			"count_per_room": float(zcfg.get("count_per_room", 1.5)),
			"hp_mult": float(zcfg.get("hp_mult", 1.0)),
			"speed_mult": float(zcfg.get("speed_mult", 1.0)),
			"dmg_mult": float(zcfg.get("dmg_mult", 1.0)),
			"boss": boss,
		}
	print("[DungeonSpawner] roster loaded: %d enemies, %d zones" % [
		_enemies_by_id.size(), ZONE_ENEMY_CONFIG.size()
	])


func _fallback_minimal_roster() -> void:
	_roster.clear()
	_enemies_by_id.clear()
	_prefabs.clear()
	var fallback_boss_types: Array = ["dragon", "rock_golem"]
	var fallback_normal_types: Array = ["goblin", "skeleton", "troll", "orc_raider"]
	BOSS_TYPES.clear()
	NORMAL_TYPES.clear()
	for eid in fallback_boss_types:
		var boss_id := String(eid)
		if MODEL_TIERS.is_accepted(boss_id):
			BOSS_TYPES.append(boss_id)
	for eid in fallback_normal_types:
		var normal_id := String(eid)
		if MODEL_TIERS.is_accepted(normal_id):
			NORMAL_TYPES.append(normal_id)
	BODY_SIZE_BY_TYPE = {
		"goblin": "medium", "skeleton": "medium", "troll": "large", "orc_raider": "medium",
		"rock_golem": "large", "dragon": "huge",
	}
	BASE_HP = {
		"goblin": 10, "skeleton": 12, "troll": 20, "orc_raider": 14,
		"rock_golem": 32, "dragon": 40,
	}
	BASE_SPEED = {
		"goblin": 2.0, "skeleton": 1.8, "troll": 1.0, "orc_raider": 1.9,
		"rock_golem": 0.9, "dragon": 0.8,
	}
	for eid in NORMAL_TYPES + BOSS_TYPES:
		var enemy_id := String(eid)
		_enemies_by_id[enemy_id] = {
			"id": enemy_id,
			"body_size": BODY_SIZE_BY_TYPE.get(enemy_id, "medium"),
		}
	ZONE_ENEMY_CONFIG.clear()
	var fallback_normal_weights: Dictionary = {}
	for eid in NORMAL_TYPES:
		fallback_normal_weights[String(eid)] = 50
	var fallback_boss_weights: Dictionary = {}
	for eid in BOSS_TYPES:
		fallback_boss_weights[String(eid)] = 50
	var hp_mults := [0.8, 1.0, 1.2, 1.4, 1.8, 2.2]
	var speed_mults := [0.9, 1.0, 1.1, 1.15, 1.25, 1.3]
	var dmg_mults := [0.8, 1.0, 1.1, 1.3, 1.5, 1.8]
	for zone in range(6):
		ZONE_ENEMY_CONFIG[zone] = {
			"types": fallback_normal_weights.duplicate() if zone == 0 else {},
			"count_per_room": 1.5 if zone == 0 else 1.0,
			"hp_mult": hp_mults[zone],
			"speed_mult": speed_mults[zone],
			"dmg_mult": dmg_mults[zone],
			"boss": fallback_boss_weights.duplicate(),
		}


## 在地牢房间内生成怪物。
func spawn_enemies(parent: Node, grid: Array, zone: int, player: Node, spawn_pos: Vector3, tile_size: float = 3.0, _offset: Vector3 = Vector3.ZERO, rooms: Array = [], room_roles: Dictionary = {}) -> Array:
	if ZONE_ENEMY_CONFIG.is_empty():
		_load_roster()
	var config: Dictionary = ZONE_ENEMY_CONFIG.get(zone, ZONE_ENEMY_CONFIG.get(0, {}))
	var grid_width: int = grid[0].size() if grid.size() > 0 else 0
	var grid_height: int = grid.size()
	var offset_x: float = -(float(grid_width) * tile_size) / 2.0
	var offset_z: float = -(float(grid_height) * tile_size) / 2.0
	var offset: Vector3 = Vector3(offset_x, 0, offset_z)

	var spawned: Array = []

	if rooms.is_empty():
		spawned = _spawn_scattered(parent, grid, config, zone, player, spawn_pos, tile_size, offset)
		print("[DungeonSpawner] Spawned %d enemies (fallback scattered, zone %d)" % [spawned.size(), zone])
		return spawned

	var start_room: Rect2i = room_roles.get("start", Rect2i())
	var boss_room: Rect2i = room_roles.get("boss", Rect2i())

	for room in rooms:
		var room_rect: Rect2i = room
		if room_rect == start_room:
			continue
		var cell_positions: Array = _collect_room_floor_cells(grid, room_rect, tile_size, offset, spawn_pos)
		if cell_positions.is_empty():
			continue
		if room_rect == boss_room:
			spawned.append_array(_spawn_in_room(parent, cell_positions, config, zone, player, true))
		else:
			spawned.append_array(_spawn_in_room(parent, cell_positions, config, zone, player, false))

	print("[DungeonSpawner] Spawned %d enemies (zone %d, rooms %d, boss_room %s)" % [spawned.size(), zone, rooms.size(), boss_room != Rect2i()])
	return spawned


func spawn_enemies_from_layout(layout: DungeonLayout, spawn_root: Node, player: Node, batched: bool = false) -> Array:
	if ZONE_ENEMY_CONFIG.is_empty():
		_load_roster()
	var plan: Array = build_enemy_spawn_plan(layout, player)
	if batched:
		# 调用方（DungeonRuntime）将分帧实例化，以削平进场单帧卡顿与显存峰值尖峰。
		return plan
	var spawned: Array = []
	for desc in plan:
		var enemy: Node = instantiate_enemy_descriptor(desc, spawn_root, player, layout)
		if enemy != null:
			spawned.append(enemy)
	print("[DungeonSpawner] Spawned %d enemies from layout specs (zone %d, specs %d)" % [spawned.size(), layout.zone, layout.enemy_spawn_specs.size()])
	return spawned


## 仅构建敌人生成计划（描述符列表），不实例化。供运行时分帧生成。
func build_enemy_spawn_plan(layout: DungeonLayout, player: Node) -> Array:
	if ZONE_ENEMY_CONFIG.is_empty():
		_load_roster()
	var plan: Array = []
	if layout == null or layout.is_empty() or player == null:
		return plan
	for spec in layout.enemy_spawn_specs:
		var enemy_type: String = spec["enemy_type"]
		var cell: Vector2i = spec["cell"]
		var offset_x: float = -(float(layout.width) * layout.tile_size) / 2.0
		var offset_z: float = -(float(layout.height) * layout.tile_size) / 2.0
		var pos: Vector3 = Vector3(offset_x, 0.5, offset_z) + Vector3(cell.x * layout.tile_size, 0.0, cell.y * layout.tile_size)
		var instantiate_type: String = enemy_type
		if bool(spec.get("is_elite", false)) and not enemy_type.begins_with("elite_"):
			instantiate_type = "elite_" + enemy_type
		plan.append({"enemy_type": instantiate_type, "pos": pos})
	return plan


## 按单个描述符实例化一个敌人（供分帧生成）。失败返回 null。
func instantiate_enemy_descriptor(desc: Dictionary, spawn_root: Node, player: Node, layout: DungeonLayout) -> Node:
	if desc.is_empty() or spawn_root == null or not is_instance_valid(spawn_root) or player == null or layout == null:
		return null
	var zone_cfg: Dictionary = ZONE_ENEMY_CONFIG.get(layout.zone, ZONE_ENEMY_CONFIG.get(0, {}))
	var enemy: Node = _instantiate_enemy(desc["enemy_type"], desc["pos"], player, zone_cfg)
	if enemy == null:
		return null
	spawn_root.add_child(enemy)
	enemy.global_position = desc["pos"]
	return enemy


func _collect_room_floor_cells(grid: Array, room: Rect2i, tile_size: float, offset: Vector3, spawn_pos: Vector3) -> Array:
	var positions: Array = []
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			if y < 0 or y >= grid.size() or x < 0 or x >= grid[y].size():
				continue
			if grid[y][x] == 1:
				var pos: Vector3 = offset + Vector3(x * tile_size, 0.5, y * tile_size)
				if pos.distance_to(spawn_pos) >= tile_size * 3.0:
					positions.append(pos)
	return positions


func _spawn_in_room(parent: Node, cell_positions: Array, config: Dictionary, zone: int, player: Node, is_boss_room: bool) -> Array:
	var spawned: Array = []
	if cell_positions.is_empty():
		return spawned

	var count_per_room: float = float(config.get("count_per_room", 1.5))
	var count: int
	if is_boss_room:
		count = 1
	else:
		count = int(cell_positions.size() * count_per_room * 0.25)
		count = clampi(count, 1, 5)

	cell_positions.shuffle()

	for i in range(count):
		if cell_positions.is_empty():
			break
		var pos: Vector3 = cell_positions.pop_at(0)
		var enemy_type: String
		if is_boss_room:
			enemy_type = _pick_boss_type(config)
		else:
			enemy_type = _pick_enemy_type(config.get("types", {}))
		if enemy_type.is_empty():
			continue
		var enemy: Node = _instantiate_enemy(enemy_type, pos, player, config)
		if enemy == null:
			continue
		parent.add_child(enemy)
		enemy.global_position = pos
		spawned.append(enemy)

	return spawned


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
		var enemy_type: String = _pick_enemy_type(config.get("types", {}))
		if enemy_type.is_empty():
			continue
		var enemy: Node = _instantiate_enemy(enemy_type, pos, player, config)
		if enemy == null:
			continue
		parent.add_child(enemy)
		enemy.global_position = pos
		spawned.append(enemy)
	return spawned


func _collect_enemy_spawn_positions(grid: Array, spawn_pos: Vector3, tile_size: float, offset: Vector3) -> Array:
	var positions: Array = []
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if grid[y][x] == 1:
				var pos: Vector3 = offset + Vector3(x * tile_size, 0.5, y * tile_size)
				if pos.distance_to(spawn_pos) >= tile_size * 4.0:
					positions.append(pos)
	return positions


func _pick_enemy_type(types: Dictionary) -> String:
	var accepted_weights: Dictionary = {}
	var total: float = 0.0
	for k in types.keys():
		var enemy_id := String(k)
		var weight := float(types[k])
		if weight <= 0.0 or not NORMAL_TYPES.has(enemy_id) or not MODEL_TIERS.is_accepted(enemy_id):
			continue
		accepted_weights[enemy_id] = weight
		total += weight
	if total <= 0.0:
		return ""
	var roll: float = randf() * total
	var acc: float = 0.0
	for k in accepted_weights.keys():
		acc += float(accepted_weights[k])
		if roll <= acc:
			return String(k)
	return String(accepted_weights.keys()[0])


func _pick_boss_type(config: Dictionary) -> String:
	var boss_config: Dictionary = config.get("boss", {})
	var accepted_weights: Dictionary = {}
	var total: float = 0.0
	for k in boss_config.keys():
		var boss_id := String(k)
		var weight := float(boss_config[k])
		if weight <= 0.0 or not BOSS_TYPES.has(boss_id) or not MODEL_TIERS.is_accepted(boss_id):
			continue
		accepted_weights[boss_id] = weight
		total += weight
	if total <= 0.0:
		return ""
	var roll: float = randf() * total
	var acc: float = 0.0
	for k in accepted_weights.keys():
		acc += float(accepted_weights[k])
		if roll <= acc:
			return "elite_" + String(k)
	return "elite_" + String(accepted_weights.keys()[0])


func _instantiate_enemy(enemy_type: String, pos: Vector3, player: Node, config: Dictionary) -> Node:
	var is_elite := enemy_type.begins_with("elite_")
	var base_type := enemy_type.trim_prefix("elite_")
	if not MODEL_TIERS.is_accepted(base_type) or not _enemies_by_id.has(base_type):
		push_warning("[DungeonSpawner] rejected unaccepted or unknown enemy type: %s" % enemy_type)
		return null

	var enemy: Node
	if use_mock_nodes:
		enemy = CharacterBody3D.new()
	else:
		var prefab: PackedScene = _get_enemy_prefab(base_type)
		if prefab == null:
			push_warning("[DungeonSpawner] accepted enemy scene is missing or invalid: %s" % base_type)
			return null
		enemy = prefab.instantiate()

	enemy.set_meta("enemy_type", enemy_type)
	enemy.set_meta("enemy_base_type", base_type)
	enemy.set_meta("is_boss_type", BOSS_TYPES.has(base_type))
	enemy.set_meta("is_boss", BOSS_TYPES.has(base_type))
	enemy.set_meta("enemy_rank", "boss" if BOSS_TYPES.has(base_type) else ("elite" if is_elite else "normal"))
	enemy.set_meta("body_size", get_body_size(base_type))
	enemy.set_meta("player_ref", player)
	enemy.set_meta("spawn_pos", pos)
	var zone_hp_mult: float = float(config.get("hp_mult", 1.0))
	var zone_spd_mult: float = float(config.get("speed_mult", 1.0))
	if is_elite:
		enemy.set_meta("hp_mult", zone_hp_mult * ELITE_HP_MULT)
		enemy.set_meta("speed_mult", zone_spd_mult * ELITE_SPEED_MULT)
		if not use_mock_nodes:
			enemy.set("is_elite", true)
	else:
		enemy.set_meta("hp_mult", zone_hp_mult)
		enemy.set_meta("speed_mult", zone_spd_mult)
	enemy.set_meta("dmg_mult", float(config.get("dmg_mult", 1.0)) * (ELITE_DMG_MULT if is_elite else 1.0))
	return enemy


func _get_enemy_prefab(base_type: String) -> PackedScene:
	if not MODEL_TIERS.is_accepted(base_type) or not _enemies_by_id.has(base_type):
		return null
	if _prefabs.has(base_type):
		return _prefabs[base_type]
	# lazy load
	var path := "res://scenes/characters/enemies/%s.tscn" % base_type
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			_prefabs[base_type] = packed
			return packed
	return null


func get_zone_config(zone: int) -> Dictionary:
	if ZONE_ENEMY_CONFIG.is_empty():
		_load_roster()
	return ZONE_ENEMY_CONFIG.get(zone, ZONE_ENEMY_CONFIG.get(0, {}))


func get_all_enemy_types() -> Array:
	if _enemies_by_id.is_empty():
		_load_roster()
	var types: Array = []
	for eid in _enemies_by_id.keys():
		types.append(eid)
	types.sort()
	return types


func get_boss_types() -> Array:
	if BOSS_TYPES.is_empty():
		_load_roster()
	return BOSS_TYPES.duplicate()


func get_normal_types() -> Array:
	if NORMAL_TYPES.is_empty():
		_load_roster()
	return NORMAL_TYPES.duplicate()


func get_body_size(enemy_type: String) -> String:
	var base_type: String = enemy_type.trim_prefix("elite_")
	if not MODEL_TIERS.is_accepted(base_type) or not _enemies_by_id.has(base_type):
		return ""
	return String(BODY_SIZE_BY_TYPE.get(base_type, ""))


func is_boss_type(enemy_type: String) -> bool:
	if BOSS_TYPES.is_empty():
		_load_roster()
	var base_type: String = enemy_type.trim_prefix("elite_")
	return BOSS_TYPES.has(base_type)


func get_display_name(enemy_type: String) -> String:
	if _enemies_by_id.is_empty():
		_load_roster()
	var base_type: String = enemy_type.trim_prefix("elite_")
	if not MODEL_TIERS.is_accepted(base_type) or not _enemies_by_id.has(base_type):
		return ""
	var entry: Dictionary = _enemies_by_id.get(base_type, {})
	var name_zh := String(entry.get("name_zh", ""))
	# name_zh 作为翻译键：zh 原样显示，en 走 CSV 英文列
	return TranslationServer.translate(name_zh)


func get_drop_id(enemy_type: String) -> String:
	if _enemies_by_id.is_empty():
		_load_roster()
	var base_type: String = enemy_type.trim_prefix("elite_")
	if not MODEL_TIERS.is_accepted(base_type) or not _enemies_by_id.has(base_type):
		return ""
	var entry: Dictionary = _enemies_by_id.get(base_type, {})
	return String(entry.get("drop", ""))
