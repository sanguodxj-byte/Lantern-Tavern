## DungeonHazardPlanner — 危险地形规划（阶段 5）。
#
# 职责：从 procedural_dungeon.gd 迁出 9 个 hazard 规划函数，输出 hazard_anchors / kick_lanes
# Dictionary 填入 DungeonLayout，**不 instantiate prefab、不 add_child、不加载 .tscn**。
# prefab 映射（spikes/acid/flame_vent）延后到 DungeonSceneBuilder（阶段 7）。
#
# 严格遵守（重构方案五）：
#   - 不加载 spikes_trap.tscn / acid_trap.tscn / flame_vent_trap.tscn
#   - 只输出 hazard_type 字符串，由后续 SceneBuilder 映射 prefab
#   - 必须验证：不在出生点/撤离点/宝箱交互点/关键门前/阻断主路径；
#     至少一条安全绕行路线；至少一条合法踢击路线（KickLane）。
class_name DungeonHazardPlanner
extends RefCounted

const LARGE_ROOM_AREA := 48  # 与 procedural_dungeon.gd / DungeonGenerationConfig.large_room_area 对齐

## 规划全部房间的危险锚点与踢击路线，就地填入 layout.hazard_anchors / layout.kick_lanes。
## 不返回值；调用方持 layout 引用读取结果。
func plan(layout: DungeonLayout) -> void:
	layout.hazard_anchors.clear()
	layout.kick_lanes.clear()
	if layout.is_empty() or not layout.is_floor_at(0, 0):
		return
	var used_cells: Array[Vector2i] = []
	# 关键点禁放区：出生格、撤离格、宝箱格、boss 格（安全先就）
	var forbidden := _collect_forbidden_cells(layout)
	for room in layout.rooms:
		if layout.is_start_room_cell(room.position) or _room_is_start_room(layout, room):
			continue
		var candidates := _collect_hazard_candidates_for_room(layout, room)
		if candidates.is_empty():
			continue
		candidates.shuffle()
		var room_target_count := _get_hazard_anchor_count_for_room(room, candidates.size())
		var room_spawned := 0
		var room_index := _find_room_index(layout, room)
		for candidate in candidates:
			if room_spawned >= room_target_count:
				break
			var cell: Vector2i = candidate["cell"]
			var min_gap := 2 if room.size.x * room.size.y >= LARGE_ROOM_AREA else 3
			if _is_near_used_hazard_cell(cell, used_cells, min_gap):
				continue
			if forbidden.has(cell):
				continue
			var hazard_type := _pick_hazard_type(room, room_spawned)
			var kick_lane := _build_kick_lane(layout, cell, candidate["dir"])
			if kick_lane.is_empty():
				continue  # 无合法踢击路线 → 跳过此锚点（避免“只对玩家有利”的死陷阱）
			var anchor := {
				"hazard_type": hazard_type,
				"anchor_cell": cell,
				"direction": candidate["dir"],
				"room_index": room_index,
				"safe_approach_cells": _collect_safe_approach_cells(layout, cell, candidate["dir"]),
				"kick_lane_index": layout.kick_lanes.size(),
			}
			layout.hazard_anchors.append(anchor)
			layout.kick_lanes.append({
				"start": kick_lane["start"],
				"end": kick_lane["end"],
				"length_cells": kick_lane["length_cells"],
				"hazard_index": layout.hazard_anchors.size() - 1,
			})
			used_cells.append(cell)
			room_spawned += 1

## 校验规划结果的合理性。返回 Dictionary 报告（不修改 layout）。
func validate_plan(layout: DungeonLayout) -> Dictionary:
	var errors: Array = []
	if layout.is_empty():
		return {"valid": true, "errors": errors}
	var forbidden := _collect_forbidden_cells(layout)
	for anchor in layout.hazard_anchors:
		var cell: Vector2i = anchor["anchor_cell"]
		if forbidden.has(cell):
			errors.append("hazard anchor at %s overlaps forbidden key cell" % str(cell))
		if not layout.is_floor_cell(cell):
			errors.append("hazard anchor at %s not on floor" % str(cell))
		# 每锚点必有对应 kick_lane
		if not anchor.has("kick_lane_index"):
			errors.append("hazard anchor at %s missing kick_lane_index" % str(cell))
		else:
			var idx: int = anchor["kick_lane_index"]
			if idx < 0 or idx >= layout.kick_lanes.size():
				errors.append("hazard anchor at %s kick_lane_index %d out of range" % [str(cell), idx])
	return {"valid": errors.is_empty(), "errors": errors}


# ── 从 procedural_dungeon.gd 迁出的规划函数（去节点、纯数据）──────────────────
func _collect_hazard_candidates_for_room(layout: DungeonLayout, room: Rect2i) -> Array:
	var candidates: Array = []
	var entrances := _find_room_entrance_cells(layout, room)
	var inner := room.grow(-1)
	if inner.size.x <= 0 or inner.size.y <= 0:
		return candidates
	# spawn_pos 用 player_spawn_cell 近似（规划期无 Vector3，用格距判）
	var spawn_cell := layout.player_spawn_cell
	for y in range(inner.position.y, inner.position.y + inner.size.y):
		for x in range(inner.position.x, inner.position.x + inner.size.x):
			if not layout.is_floor_at(x, y):
				continue
			var cell := Vector2i(x, y)
			# 与出生格距离 ≥ 4 格（procedural 的 tile_size*4.0 近似 → 4 格）
			if spawn_cell.x >= 0 and abs(cell.x - spawn_cell.x) + abs(cell.y - spawn_cell.y) < 4:
				continue
			var entrance_padding := 1 if min(room.size.x, room.size.y) <= 5 else 2
			if _is_near_room_entrance(cell, entrances, entrance_padding):
				continue
			if _is_narrow_passage_cell(layout, cell):
				continue
			var lane_dir := _find_kick_lane_direction(layout, x, y, 2)
			if lane_dir != Vector2i.ZERO:
				candidates.append({"cell": cell, "dir": lane_dir})
	return candidates

func _get_hazard_anchor_count_for_room(room: Rect2i, candidate_count: int) -> int:
	if candidate_count <= 0:
		return 0
	var area := room.size.x * room.size.y
	if area < 20:
		return min(candidate_count, 1)
	if area < 48:
		return min(candidate_count, 1)
	if area < 80:
		return min(candidate_count, 3)
	return min(candidate_count, 4)

func _find_room_entrance_cells(layout: DungeonLayout, room: Rect2i) -> Array:
	var entrances: Array = []
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			if not layout.is_floor_at(x, y):
				continue
			var cell := Vector2i(x, y)
			if not _is_on_room_edge(cell, room):
				continue
			for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var outside: Vector2i = cell + dir
				if room.has_point(outside):
					continue
				if layout.is_floor_cell(outside):
					entrances.append(cell)
					break
	return entrances

func _is_on_room_edge(cell: Vector2i, room: Rect2i) -> bool:
	return cell.x == room.position.x \
		or cell.y == room.position.y \
		or cell.x == room.position.x + room.size.x - 1 \
		or cell.y == room.position.y + room.size.y - 1

func _is_near_room_entrance(cell: Vector2i, entrances: Array, padding_cells: int) -> bool:
	for entrance in entrances:
		if abs(cell.x - entrance.x) + abs(cell.y - entrance.y) <= padding_cells:
			return true
	return false

func _is_narrow_passage_cell(layout: DungeonLayout, cell: Vector2i) -> bool:
	var open_neighbors := 0
	for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var next: Vector2i = cell + dir
		if layout.is_floor_cell(next):
			open_neighbors += 1
	return open_neighbors <= 2

func _find_kick_lane_direction(layout: DungeonLayout, x: int, y: int, min_lane_cells: int = 2) -> Vector2i:
	for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var clear := true
		for step in range(1, min_lane_cells + 1):
			var probe: Vector2i = Vector2i(x, y) + dir * step
			if not layout.is_floor_cell(probe):
				clear = false
				break
		if clear:
			return dir
	return Vector2i.ZERO

func _is_walkable_hazard_cell(layout: DungeonLayout, x: int, y: int) -> bool:
	return layout.is_floor_at(x, y)

func _is_near_used_hazard_cell(cell: Vector2i, used_cells: Array, min_gap: int) -> bool:
	for used in used_cells:
		if abs(cell.x - used.x) + abs(cell.y - used.y) < min_gap:
			return true
	return false

# ── hazard planner 独有（procedural 无对应）：hazard_type 映射 + kick_lane 构造 + safe_approach 收集 ──
## prefab 选择迁出 procedural 的 _pick_hazard_trap_prefab，但只返回 hazard_type 字符串。
func _pick_hazard_type(room: Rect2i, placement_index: int) -> String:
	var area := room.size.x * room.size.y
	if area >= LARGE_ROOM_AREA:
		var roll := (placement_index) % 3  # 去掉 procedural 的 randi_range，规划期需确定
		match roll:
			0:
				return "spikes"
			1:
				return "acid"
			_:
				return "flame_vent"
	# 小房间：spikes 或 acid
	if placement_index % 2 == 0:
		return "spikes"
	return "acid"

## 沿 dir 构造 KickLane：start = cell + dir*1（被踢起跳格），end = cell + dir*（max_lane）。
## procedural 只校验“方向上 min_lane_cells=2 格畅通”；这里把 lane 长度也算出来（≥2）。
func _build_kick_lane(layout: DungeonLayout, cell: Vector2i, dir: Vector2i) -> Dictionary:
	var max_lane := 0
	for step in range(1, 6):  # 上限 5 格避免长踢进墙
		var probe: Vector2i = cell + dir * step
		if not layout.is_floor_cell(probe):
			break
		max_lane = step
	if max_lane < 2:
		return {}
	return {
		"start": cell + dir,
		"end": cell + dir * max_lane,
		"length_cells": max_lane,
	}

## 收集安全站位格：踢击起跳格周围的“非伤害格”。玩家站此格才能安全逼近引怪踢。
func _collect_safe_approach_cells(layout: DungeonLayout, cell: Vector2i, dir: Vector2i) -> Array:
	var safe: Array = []
	# 反方向（玩家站位侧）的邻格
	var approach_dir := Vector2i(-dir.x, -dir.y)
	for step in range(1, 4):
		var probe: Vector2i = cell + approach_dir * step
		if not layout.is_floor_cell(probe):
			break
		# 不在 hazard 锚点格上
		if probe != cell:
			safe.append(probe)
	return safe

func _room_is_start_room(layout: DungeonLayout, room: Rect2i) -> bool:
	return layout.room_roles.has("start") and room == (layout.room_roles["start"] as Rect2i)

func _find_room_index(layout: DungeonLayout, room: Rect2i) -> int:
	for i in range(layout.rooms.size()):
		if layout.rooms[i] == room:
			return i
	return -1

## 收集关键点禁放格：出生格 + 撤离格 + 宝箱格 + boss 格 + 楼梯格
func _collect_forbidden_cells(layout: DungeonLayout) -> Dictionary:
	var forbidden := {}
	for label in ["player_spawn_cell", "extraction_cell", "boss_cell", "stairs_cell", "reward_cell"]:
		var cell: Vector2i = layout.get(label)
		if not layout.is_key_cell_missing(cell):
			forbidden[cell] = true
	# 加上 forbidden 周围 1 格（避免“门一开就踩陷阱”）
	var expanded := {}
	for c in forbidden.keys():
		expanded[c] = true
		for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]:
			var n: Vector2i = c + d
			expanded[n] = true
	return expanded
