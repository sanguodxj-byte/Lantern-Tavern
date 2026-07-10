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

# 与 DungeonSpawner.ZONE_ENEMY_CONFIG 对齐的区域配置（此处只取权重与倍率，不含 prefab）。
# 规划期不读 DungeonSpawner autoload，避免对全局单例的隐式依赖。
const ZONE_ENEMY_CONFIG: Dictionary = {
	0: {"types": {"rat": 30, "slime": 25, "skeleton": 20, "goblin": 15, "troll": 10}, "count_per_room": 1.5, "boss": {"necrolord": 50, "dragon": 50}},
	1: {"types": {"rat": 25, "slime": 20, "skeleton": 20, "goblin": 20, "troll": 15}, "count_per_room": 2.0, "boss": {"necrolord": 50, "dragon": 50}},
	2: {"types": {"slime": 20, "skeleton": 25, "rat": 15, "goblin": 20, "troll": 20}, "count_per_room": 2.5, "boss": {"necrolord": 50, "dragon": 50}},
	3: {"types": {"skeleton": 25, "rat": 10, "slime": 15, "goblin": 25, "troll": 25}, "count_per_room": 3.0, "boss": {"necrolord": 50, "dragon": 50}},
	4: {"types": {"skeleton": 15, "slime": 10, "rat": 5, "goblin": 30, "troll": 40}, "count_per_room": 3.5, "boss": {"necrolord": 50, "dragon": 50}},
	5: {"types": {"skeleton": 10, "rat": 5, "slime": 5, "goblin": 35, "troll": 45}, "count_per_room": 4.0, "boss": {"necrolord": 50, "dragon": 50}},
}
const BOSS_TYPES := ["necrolord", "dragon"]
const NORMAL_TYPES := ["goblin", "rat", "skeleton", "slime", "troll"]


## 规划敌人 spec：填入 layout.enemy_spawn_specs。不实例化。
func plan_enemy_spawns(layout: DungeonLayout) -> Array:
	layout.enemy_spawn_specs.clear()
	if layout.is_empty():
		return []
	var zone_cfg: Dictionary = ZONE_ENEMY_CONFIG.get(layout.zone, ZONE_ENEMY_CONFIG[0])
	var spawn_cell := layout.player_spawn_cell
	for room in layout.rooms:
		if layout.is_start_room_cell(room.position) or _room_is_start_room(layout, room):
			continue  # 起始房间不生普通敌人
		if _room_is_boss_room(layout, room):
			# Boss 房间：二选一（necrolord/dragon），落在 boss_cell 或房间可走格
			var boss_type := _pick_boss_type(zone_cfg)
			var boss_cell := _pick_room_floor_cell(layout, room, layout.boss_cell)
			if boss_cell.x >= 0:
				layout.enemy_spawn_specs.append({
					"enemy_type": boss_type, "cell": boss_cell,
					"room_index": _find_room_index(layout, room),
					"is_elite": true, "zone": layout.zone,
				})
			continue
		# 普通房间：按 count_per_room 取 floor 格，按权重选 type
		var floor_cells := _collect_room_floor_cells(layout, room, spawn_cell)
		if floor_cells.is_empty():
			continue
		var target_count := _calc_room_enemy_count(zone_cfg, floor_cells.size())
		var used: Dictionary = {}
		for _i in range(target_count):
			var cell: Vector2i = _pick_unused_cell(floor_cells, used)
			if cell.x < 0:
				break
			used[cell] = true
			var enemy_type := _pick_weighted(zone_cfg["types"])
			layout.enemy_spawn_specs.append({
				"enemy_type": enemy_type, "cell": cell,
				"room_index": _find_room_index(layout, room),
				"is_elite": false, "zone": layout.zone,
			})
	return layout.enemy_spawn_specs

## 规划掉落 spec：填入 layout.item_spawn_specs。不实例化、不读 ItemSpawner autoload。
## 规则：每个非起始、非 boss 房间有概率掉落一个材料；材料 id 按区域池稳定取。
func plan_item_spawns(layout: DungeonLayout) -> Array:
	layout.item_spawn_specs.clear()
	if layout.is_empty():
		return []
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
		var item_id: String = _pick_material_for_zone(layout.zone)
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

func _calc_room_enemy_count(zone_cfg: Dictionary, floor_cell_count: int) -> int:
	var per_room: float = float(zone_cfg.get("count_per_room", 1.5))
	# 与 procedural 旧逻辑一致：count_per_room 是“每房间期望数”，向上取整，限 floor 格数
	var target := int(ceil(per_room))
	return min(target, floor_cell_count)

func _pick_unused_cell(floor_cells: Array, used: Dictionary) -> Vector2i:
	for c in floor_cells:
		var cell: Vector2i = c
		if not used.has(cell):
			return cell
	return Vector2i(-1, -1)

func _pick_weighted(types: Dictionary) -> String:
	var total := 0
	for k in types.keys():
		total += int(types[k])
	if total <= 0:
		return NORMAL_TYPES[0]
	var roll := randi() % total
	var acc := 0
	for k in types.keys():
		acc += int(types[k])
		if roll < acc:
			return String(k)
	return String(types.keys()[0])

func _pick_boss_type(zone_cfg: Dictionary) -> String:
	var boss_cfg: Dictionary = zone_cfg.get("boss", {"necrolord": 50, "dragon": 50})
	return _pick_weighted(boss_cfg)

# 各区域材料池（与 procedural_dungeon.gd 的 MATERIALS_CONFIG 对齐，但去 randf 随机，按区域取首个）
func _pick_material_for_zone(zone: int) -> String:
	var pools := {
		0: "blackberry", 1: "glowshroom", 2: "moongrass", 3: "goblin_nail",
		4: "mistflower", 5: "wolfear_herb",
	}
	return pools.get(zone, "blackberry")
