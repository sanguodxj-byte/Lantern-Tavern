## DungeonSpawnPlanner — 敌人/掉落/宝箱位置规划（阶段 6）。
#
# 职责：把 procedural_dungeon.gd 的 _spawn_dungeon_enemies/_spawn_dungeon_items 与
# DungeonSpawner.spawn_enemies 的“按房间分类、按区域权重、跳起始房、boss 房二选一”规则
# 抽成 spawn spec 填入 DungeonLayout，**不 instantiate prefab、不调 ItemSpawner autoload、不 add_child**。
# 实例化延后到 DungeonSpawner（兼容）或 DungeonSceneBuilder（阶段 7）按 spec instantiate。
#
# 严格遵守（重构方案六）：
#   - 不加载 enemy/*.tscn / pickable_item.tscn / chest.tscn / boss_chest.tscn
#   - spec 用稳定字符串 ID（enemy_type/item_id/chest_type），不持 PackedScene 引用
#   - 必须验证：敌人不在墙内、不在陷阱伤害中心；掉落不在不可达格；
#     Boss 只在 Boss 房间；起始房间不生普通敌人
class_name DungeonSpawnPlanner
extends RefCounted

# 区域权重 / BOSS 声明从 data/enemy_roster.json 加载，再按已验收名单过滤。
# 规划期不读 DungeonSpawner autoload，避免对全局单例的隐式依赖。
const ROSTER_PATH := "res://data/enemy_roster.json"
const MODEL_TIERS := preload("res://data/character_model_tiers.gd")
static var ZONE_ENEMY_CONFIG: Dictionary = {}
static var BOSS_TYPES: Array = []
static var NORMAL_TYPES: Array = []
static var _roster_loaded := false

static func _ensure_roster() -> void:
	if _roster_loaded and not ZONE_ENEMY_CONFIG.is_empty():
		return
	_roster_loaded = true
	BOSS_TYPES.clear()
	NORMAL_TYPES.clear()
	ZONE_ENEMY_CONFIG.clear()
	if not FileAccess.file_exists(ROSTER_PATH):
		_set_fallback_roster()
		return
	var file := FileAccess.open(ROSTER_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var data: Dictionary = json.data
	var declared_bosses: Dictionary = {}
	for t in data.get("boss_types", []):
		declared_bosses[String(t)] = true
	for entry in data.get("enemies", []):
		var eid: String = String(entry.get("id", ""))
		if eid.is_empty() or not MODEL_TIERS.is_accepted(eid):
			continue
		if declared_bosses.has(eid):
			BOSS_TYPES.append(eid)
		else:
			NORMAL_TYPES.append(eid)
	var zw: Dictionary = data.get("zone_weights", {})
	for zone_key in zw.keys():
		var zid: int = int(zone_key)
		var zcfg: Dictionary = zw[zone_key]
		var types: Dictionary = {}
		for k in zcfg.get("types", {}).keys():
			var enemy_id := String(k)
			var w: float = float(zcfg["types"][k])
			if w > 0.0 and NORMAL_TYPES.has(enemy_id):
				types[enemy_id] = w
		var boss: Dictionary = {}
		for k in zcfg.get("boss", {}).keys():
			var boss_id := String(k)
			var w2: float = float(zcfg["boss"][k])
			if w2 > 0.0 and BOSS_TYPES.has(boss_id):
				boss[boss_id] = w2
		ZONE_ENEMY_CONFIG[zid] = {
			"types": types,
			"count_per_room": float(zcfg.get("count_per_room", 1.5)),
			"boss": boss,
		}

# 各区域材料池（多候选，取代旧的单固定材料）。规划期用 layout.seed 派生的
# 种子 roll，同一 seed 产出完全相同、不同 seed 互不相同、单次探险内多种材料。
# 与 globals/tavern/loot_table.gd、brewing_data.gd 的材料 id 对齐。
const ZONE_MATERIAL_POOLS: Dictionary = {
	0: ["blackberry", "glowshroom", "moongrass"],
	1: ["glowshroom", "moongrass", "mistflower"],
	2: ["moongrass", "goblin_nail", "mistflower"],
	3: ["goblin_nail", "mistflower", "wolfear_herb"],
	4: ["mistflower", "wolfear_herb", "blackberry"],
	5: ["wolfear_herb", "goblin_nail", "glowshroom"],
}


## 规划敌人 spec：填入 layout.enemy_spawn_specs。不实例化。
func plan_enemy_spawns(layout: DungeonLayout) -> Array:
	_ensure_roster()
	layout.enemy_spawn_specs.clear()
	if layout.is_empty():
		return []
	var zone_cfg: Dictionary = ZONE_ENEMY_CONFIG.get(layout.zone, ZONE_ENEMY_CONFIG.get(0, {}))
	var spawn_cell := layout.player_spawn_cell
	# 敌人域 RNG（与掉落/陷阱错开）+ 房间深度场（BFS 距离），用于方差与深度梯度
	var rng := _seeded_rng(layout, 0x454E45)  # "ENE"
	var depth_field := layout.compute_floor_distance_field()
	for room in layout.rooms:
		if layout.is_start_room_cell(room.position) or _room_is_start_room(layout, room):
			continue  # 起始房间不生普通敌人
		if _room_is_boss_room(layout, room):
			# Boss 房间：只从已验收 boss 中选择，落在 boss_cell 或房间可走格。
			var boss_type := _pick_boss_type(zone_cfg)
			if boss_type.is_empty():
				continue
			var boss_cell := _pick_room_floor_cell(layout, room, layout.boss_cell)
			if boss_cell.x >= 0:
				layout.enemy_spawn_specs.append({
					"enemy_type": boss_type, "cell": boss_cell,
					"room_index": _find_room_index(layout, room),
					"is_elite": true, "zone": layout.zone,
				})
			continue
		# 普通房间：按 count_per_room（含方差）取 floor 格，按权重选 type
		# TEMP: 某些 zone 的 types 为空（例如当前仅 L0 放满怪）→ 不刷普通怪
		var type_weights: Dictionary = zone_cfg.get("types", {})
		if type_weights.is_empty():
			continue
		var floor_cells := _collect_room_floor_cells(layout, room, spawn_cell)
		# 排除 hazard 锚点格：敌人不可直接落在陷阱伤害中心（"敌人不在陷阱"契约的规划期落实）
		floor_cells = _exclude_hazard_anchor_cells(layout, floor_cells)
		if floor_cells.is_empty():
			continue
		var depth: int = layout.depth_of_room_with_field(room, depth_field)
		var target_count := _calc_room_enemy_count(zone_cfg, floor_cells.size(), depth, rng)
		var used: Dictionary = {}
		for _i in range(target_count):
			var cell: Vector2i = _pick_unused_cell(floor_cells, used)
			if cell.x < 0:
				break
			used[cell] = true
			var enemy_type := _pick_weighted(type_weights)
			if enemy_type.is_empty():
				continue
			layout.enemy_spawn_specs.append({
				"enemy_type": enemy_type, "cell": cell,
				"room_index": _find_room_index(layout, room),
				"is_elite": false, "zone": layout.zone,
			})
	return layout.enemy_spawn_specs

## 规划掉落 spec：填入 layout.item_spawn_specs。不实例化、不读 ItemSpawner autoload。
## 规则：每个非起始、非 boss 房间掉一个材料；材料 id 从区域池按 layout.seed 派生的
## 种子 roll（同 seed 同掉落、跨房间有变化），打破“每房恒 blackberry”的单调拾取。
func plan_item_spawns(layout: DungeonLayout) -> Array:
	layout.item_spawn_specs.clear()
	if layout.is_empty():
		return []
	var rng := _seeded_rng(layout, 0x4D4154)  # "MAT" 域盐，与敌人/陷阱序列错开
	for room in layout.rooms:
		if layout.is_start_room_cell(room.position) or _room_is_start_room(layout, room):
			continue
		if _room_is_boss_room(layout, room):
			continue  # boss 房间走 chest，不放散落材料
		var floor_cells := _collect_room_floor_cells(layout, room, layout.player_spawn_cell)
		if floor_cells.is_empty():
			continue
		# 与 procedural 旧逻辑一致：每房间最多 1 个材料，落在首个可走格（不与敌人/陷阱抢位）
		var cell: Vector2i = floor_cells[0]
		var item_id: String = _pick_material_from_pool(layout.zone, rng)
		layout.item_spawn_specs.append({
			"item_type": "material", "item_id": item_id, "cell": cell,
			"room_index": _find_room_index(layout, room),
		})
	return layout.item_spawn_specs

## 规划宝箱 spec：填入 layout.chest_spawn_specs。boss 房间 = boss_chest；其余 LOOT 格 = normal_chest。
func plan_chest_spawns(layout: DungeonLayout) -> Array:
	layout.chest_spawn_specs.clear()
	if layout.is_empty():
		return []
	# boss 房间：boss_chest 落在 reward_cell 或房间可走格
	if layout.room_roles.has("boss"):
		var boss_room: Rect2i = layout.room_roles["boss"]
		var chest_cell := _pick_room_floor_cell(layout, boss_room, layout.reward_cell)
		if chest_cell.x >= 0:
			layout.chest_spawn_specs.append({
				"chest_type": "boss_chest", "cell": chest_cell,
				"room_index": _find_room_index(layout, boss_room),
			})
	# 其余房间：扫 grid 找 TileType.LOOT(3) 格，放 normal_chest
	for y in range(layout.grid.size()):
		for x in range(layout.grid[y].size()):
			if int(layout.grid[y][x]) == 3:  # LOOT
				var cell: Vector2i = Vector2i(x, y)
				if layout.is_boss_room_cell(cell):
					continue  # boss 房间的 LOOT 已走 boss_chest
				layout.chest_spawn_specs.append({
					"chest_type": "normal_chest", "cell": cell,
					"room_index": _find_room_index_by_cell(layout, cell),
				})
	return layout.chest_spawn_specs

## 校验规划结果合理性。返回 {valid:bool, errors:Array[String]}。不修改 layout。
func validate_plan(layout: DungeonLayout) -> Dictionary:
	_ensure_roster()
	var errors: Array = []
	if layout.is_empty():
		return {"valid": true, "errors": errors}
	# 收集 hazard 锚点格（敌人不能直接位于陷阱伤害中心）
	var hazard_cells := {}
	for anchor in layout.hazard_anchors:
		hazard_cells[anchor["anchor_cell"]] = true
	for spec in layout.enemy_spawn_specs:
		var cell: Vector2i = spec["cell"]
		if not layout.is_floor_cell(cell):
			errors.append("enemy spec at %s not on floor" % str(cell))
		if hazard_cells.has(cell):
			errors.append("enemy spec at %s overlaps hazard anchor" % str(cell))
		if layout.is_start_room_cell(cell):
			errors.append("enemy spec at %s in start room" % str(cell))
		var et: String = spec["enemy_type"]
		if not MODEL_TIERS.is_accepted(et):
			errors.append("enemy type '%s' is not accepted" % et)
		if not NORMAL_TYPES.has(et) and not BOSS_TYPES.has(et):
			errors.append("enemy type '%s' is not declared in the accepted enemy roster" % et)
		if et in BOSS_TYPES:
			# Boss 只在 Boss 房间
			if not layout.is_boss_room_cell(cell):
				errors.append("boss type '%s' at %s not in boss room" % [et, str(cell)])
	for spec in layout.chest_spawn_specs:
		var cell: Vector2i = spec["cell"]
		var chest_type: String = spec["chest_type"]
		# normal_chest 落在 TileType.LOOT(3) 格，不是 FLOOR(1)；放行 LOOT 格
		var is_loot: bool = (cell.y < layout.grid.size() and cell.x < layout.grid[cell.y].size() and int(layout.grid[cell.y][cell.x]) == 3)
		if chest_type == "normal_chest" and is_loot:
			pass  # LOOT 格放行
		elif not layout.is_floor_cell(cell):
			errors.append("chest spec at %s not on floor/loot" % str(cell))
		var ct: String = spec["chest_type"]
		if ct == "boss_chest" and not layout.is_boss_room_cell(cell):
			errors.append("boss_chest at %s not in boss room" % str(cell))
	return {"valid": errors.is_empty(), "errors": errors}


# ── 内部 ─────────────────────────────────────────────────────
func _room_is_start_room(layout: DungeonLayout, room: Rect2i) -> bool:
	return layout.room_roles.has("start") and room == (layout.room_roles["start"] as Rect2i)

func _room_is_boss_room(layout: DungeonLayout, room: Rect2i) -> bool:
	return layout.room_roles.has("boss") and room == (layout.room_roles["boss"] as Rect2i)

func _find_room_index(layout: DungeonLayout, room: Rect2i) -> int:
	for i in range(layout.rooms.size()):
		if layout.rooms[i] == room:
			return i
	return -1

func _find_room_index_by_cell(layout: DungeonLayout, cell: Vector2i) -> int:
	for i in range(layout.rooms.size()):
		if (layout.rooms[i] as Rect2i).has_point(cell):
			return i
	return -1

func _collect_room_floor_cells(layout: DungeonLayout, room: Rect2i, exclude_near: Vector2i) -> Array:
	var cells: Array = []
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			if not layout.is_floor_at(x, y):
				continue
			var cell := Vector2i(x, y)
			# 与出生格距离 ≥ 2（procedural 的 spawn_pos 距离近似的格距）
			if exclude_near.x >= 0 and absi(cell.x - exclude_near.x) + absi(cell.y - exclude_near.y) < 2:
				continue
			cells.append(cell)
	return cells

func _pick_room_floor_cell(layout: DungeonLayout, room: Rect2i, preferred: Vector2i) -> Vector2i:
	if not layout.is_key_cell_missing(preferred) and layout.is_floor_cell(preferred) and room.has_point(preferred):
		return preferred
	var cells := _collect_room_floor_cells(layout, room, Vector2i(-1, -1))
	if cells.is_empty():
		return Vector2i(-1, -1)
	return cells[0]

# 从候选格中剔除 hazard 锚点格（敌人不应落在陷阱伤害中心）。hazard_anchors 为空时原样返回。
func _exclude_hazard_anchor_cells(layout: DungeonLayout, cells: Array) -> Array:
	if layout.hazard_anchors.is_empty():
		return cells
	var blocked := {}
	for anchor in layout.hazard_anchors:
		blocked[anchor["anchor_cell"]] = true
	var out: Array = []
	for c in cells:
		if not blocked.has(c):
			out.append(c)
	return out

func _calc_room_enemy_count(zone_cfg: Dictionary, floor_cell_count: int, depth: int, rng: RandomNumberGenerator) -> int:
	var base: int = int(ceil(float(zone_cfg.get("count_per_room", 1.5))))
	# 同房间数方差 ±1（至少 1 个），打破“每房恒 2 敌”的平板节奏
	var lo: int = max(1, base - 1)
	var hi: int = base + 1
	var count: int = rng.randi_range(lo, hi)
	# 深度梯度：越深越险，每 12 格 +1（浅层保留喘息房手感；上限由 floor 格数封顶）
	count += int(depth / 12)
	return min(count, floor_cell_count)

func _pick_unused_cell(floor_cells: Array, used: Dictionary) -> Vector2i:
	for c in floor_cells:
		var cell: Vector2i = c
		if not used.has(cell):
			return cell
	return Vector2i(-1, -1)

func _pick_weighted(types: Dictionary) -> String:
	_ensure_roster()
	var accepted_weights: Dictionary = {}
	var total := 0
	for k in types.keys():
		var enemy_id := String(k)
		var weight := int(types[k])
		var is_roster_enemy := NORMAL_TYPES.has(enemy_id) or BOSS_TYPES.has(enemy_id)
		if not MODEL_TIERS.is_accepted(enemy_id) or not is_roster_enemy or weight <= 0:
			continue
		accepted_weights[enemy_id] = weight
		total += weight
	if total <= 0:
		return ""
	var roll := randi() % total
	var acc := 0
	for k in accepted_weights.keys():
		acc += int(accepted_weights[k])
		if roll < acc:
			return String(k)
	return String(accepted_weights.keys()[0])

func _pick_boss_type(zone_cfg: Dictionary) -> String:
	var accepted_bosses: Dictionary = {}
	var boss_cfg: Dictionary = zone_cfg.get("boss", {})
	for key in boss_cfg.keys():
		var boss_id := String(key)
		if BOSS_TYPES.has(boss_id) and MODEL_TIERS.is_accepted(boss_id):
			accepted_bosses[boss_id] = boss_cfg[key]
	return _pick_weighted(accepted_bosses)


static func _set_fallback_roster() -> void:
	BOSS_TYPES = ["dragon", "rock_golem"]
	NORMAL_TYPES = ["goblin", "skeleton", "troll", "orc_raider"]
	for zone in range(6):
		ZONE_ENEMY_CONFIG[zone] = {
			"types": {
				"goblin": 50, "skeleton": 50, "troll": 50, "orc_raider": 50,
			} if zone == 0 else {},
			"count_per_room": 1.5,
			"boss": {"dragon": 50, "rock_golem": 50},
		}

# 各区域材料池（与 procedural_dungeon.gd 的 MATERIALS_CONFIG 对齐，但去 randf 随机，按区域取首个）
func _pick_material_from_pool(zone: int, rng: RandomNumberGenerator) -> String:
	var pool: Array = ZONE_MATERIAL_POOLS.get(zone, ["blackberry"])
	var idx: int = rng.randi_range(0, pool.size() - 1)
	return String(pool[idx])

## 由 layout.seed 派生一个独立 RandomNumberGenerator，域盐隔离地形/敌人/掉落/陷阱序列。
## 保证“同 seed 同规划、不同 seed 不同”，且规划期可复现（便于测试与联机指纹一致）。
func _seeded_rng(layout: DungeonLayout, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var s: int = layout.seed
	if s == 0:
		s = 1  # 避免 seed=0 序列与未注入 rng 退化重合
	# 组合哈希：layout.seed ^ (salt * 黄金比素数 2654435761)，落到正 32-bit
	var mixed: int = (s ^ (salt * 2654435761)) & 0x7FFFFFFF
	rng.seed = mixed
	return rng
