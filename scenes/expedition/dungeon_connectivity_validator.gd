## DungeonConnectivityValidator — 连通性与可达性验证（阶段 4）。
#
# 职责：对 DungeonLayout 做纯数据验证，报告连通性、关键点可达、孤立房间、主路径是否依赖危险地形。
# 严格遵守：只报告，不修改 layout（见重构方案八：自动改墙会隐藏算法问题，生成失败应由
#   DungeonGenerator 明确重试或降级）。本类不创建场景节点。
class_name DungeonConnectivityValidator
extends RefCounted

# 阶段 9 条 7：可达比阈值代码落实（原 _ready 里只写注释"isaac 不保 100% 连通，reachable 90%+ 即放行"）。
# 调用方可覆写；默认 0.9 与 procedural_dungeon.gd._ready 的放行契约一致。
var reachable_ratio_threshold: float = 0.9

## 完整验证，返回报告 Dictionary：
## {valid:bool, reachable_floor_count:int, floor_count:int,
##  unreachable_cells:Array[Vector2i], unreachable_rooms:Array[Rect2i],
##  missing_required_points:Array[String], main_path_uses_hazard:bool,
##  reachable_ratio:float, ratio_below_threshold:bool}
func validate(layout: DungeonLayout) -> Dictionary:
	var report := {
		"valid": true,
		"reachable_floor_count": 0,
		"floor_count": 0,
		"unreachable_cells": [],
		"unreachable_rooms": [],
		"missing_required_points": [],
		"main_path_uses_hazard": false,
		"reachable_ratio": 0.0,
		"ratio_below_threshold": false,
	}
	if layout.is_empty():
		report["valid"] = false
		return report
	var floors := _collect_floor_cells(layout)
	report["floor_count"] = floors.size()
	if floors.is_empty():
		report["valid"] = false
		return report
	# 关键点是否命中（未命中提前报告，避免 BFS 起点空）
	var start_cell := _pick_bfs_start(layout, floors)
	if start_cell.x < 0:
		report["valid"] = false
		report["missing_required_points"].append("player_spawn_cell")
		return report
	var reachable := _bfs_reachable(layout, start_cell)
	report["reachable_floor_count"] = reachable.size()
	# 不可达格 = floor_count - reachable，且不在 reachable 集合内
	var reachable_set := {}
	for c in reachable:
		reachable_set[c] = true
	var unreachable: Array = []
	for f in floors:
		if not reachable_set.has(f):
			unreachable.append(f)
	report["unreachable_cells"] = unreachable
	# 阶段 9 条 7：可达比代码落实（不再只写注释）
	var ratio: float = 0.0
	if report["floor_count"] > 0:
		ratio = float(reachable.size()) / float(report["floor_count"])
	report["reachable_ratio"] = ratio
	report["ratio_below_threshold"] = ratio < reachable_ratio_threshold
	# 关键点可达
	var missing: Array = []
	for label in ["player_spawn_cell", "extraction_cell", "boss_cell", "stairs_cell", "reward_cell"]:
		var cell: Vector2i = layout.get(label)
		if layout.is_key_cell_missing(cell):
			# 未命中：extraction/stairs 是可选 role（extraction 概率出现），不强制 missing
			# 但 player_spawn/boss 是必命中
			if label == "player_spawn_cell" or label == "boss_cell":
				missing.append(label)
			continue
		if not reachable_set.has(cell):
			missing.append(label)
	report["missing_required_points"] = missing
	if not missing.is_empty():
		report["valid"] = false
	# 孤立房间：整房间无一格在 reachable 集合内
	var isolated_rooms: Array = []
	for room in layout.rooms:
		var any_reachable := false
		for y in range(room.position.y, room.position.y + room.size.y):
			for x in range(room.position.x, room.position.x + room.size.x):
				if reachable_set.has(Vector2i(x, y)):
					any_reachable = true
					break
			if any_reachable:
				break
		if not any_reachable:
			isolated_rooms.append(room)
	report["unreachable_rooms"] = isolated_rooms
	if not isolated_rooms.is_empty():
		report["valid"] = false
	# 主路径是否依赖危险地形：player_spawn 到 boss 的最短路径中是否含 hazard anchor 锚点格
	report["main_path_uses_hazard"] = _main_path_uses_hazard(layout, start_cell, layout.boss_cell)
	if report["main_path_uses_hazard"]:
		# 不强制 invalid（危险地形可绕行），只报告
		pass
	return report

## 是否所有地板格连通（reachable_floor_count == floor_count）
## 注意：避开 Godot Object 原生 is_connected(StringName,Callable)；改名 is_floor_connected。
func is_floor_connected(layout: DungeonLayout) -> bool:
	var r := validate(layout)
	return int(r["reachable_floor_count"]) == int(r["floor_count"])

## 某格是否可达（BFS 从 player_spawn 出发）
func is_cell_reachable(layout: DungeonLayout, cell: Vector2i) -> bool:
	var reachable := collect_reachable_cells(layout, layout.player_spawn_cell)
	for c in reachable:
		if c == cell:
			return true
	return false

## BFS 收集从 start 出发可达的所有地板格
func collect_reachable_cells(layout: DungeonLayout, start: Vector2i) -> Array:
	if layout.is_empty() or not layout.is_floor_cell(start):
		return []
	return _bfs_reachable(layout, start)

## 等价于 validate() 的精简报告（只给 valid + missing）
func build_report(layout: DungeonLayout) -> Dictionary:
	return validate(layout)


# ── 内部 ─────────────────────────────────────────────────────
func _collect_floor_cells(layout: DungeonLayout) -> Array:
	var floors: Array = []
	for y in range(layout.grid.size()):
		for x in range(layout.grid[y].size()):
			if int(layout.grid[y][x]) == 1:
				floors.append(Vector2i(x, y))
	return floors

func _pick_bfs_start(layout: DungeonLayout, floors: Array) -> Vector2i:
	# 优先 player_spawn_cell，否则首个 FLOOR 格
	if not layout.is_key_cell_missing(layout.player_spawn_cell) and layout.is_floor_cell(layout.player_spawn_cell):
		return layout.player_spawn_cell
	if not floors.is_empty():
		return floors[0]
	return Vector2i(-1, -1)

func _bfs_reachable(layout: DungeonLayout, start: Vector2i) -> Array:
	var visited := {}
	var queue: Array = [start]
	visited[start] = true
	var dirs := [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in dirs:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0:
				continue
			if nxt.y >= layout.grid.size() or nxt.x >= layout.grid[nxt.y].size():
				continue
			if visited.has(nxt):
				continue
			if int(layout.grid[nxt.y][nxt.x]) != 1:  # 非地板不可走
				continue
			visited[nxt] = true
			queue.append(nxt)
	var result: Array = []
	for k in visited.keys():
		result.append(k)
	return result

## player_spawn 到 boss 的最短路径（BFS）中是否含 hazard anchor 锚点格。
## hazard 锚点格收集自 layout.hazard_anchors 的 anchor_cell 字段。
func _main_path_uses_hazard(layout: DungeonLayout, start: Vector2i, target: Vector2i) -> bool:
	if layout.is_key_cell_missing(target) or not layout.is_floor_cell(target):
		return false
	if layout.hazard_anchors.is_empty():
		return false
	# 收集 hazard 锚点格集合
	var hazard_cells := {}
	for spec in layout.hazard_anchors:
		if spec.has("anchor_cell"):
			hazard_cells[spec["anchor_cell"]] = true
	# BFS 同时记录最短路径上的节点（BFS 队列原生就是最短路径来源）
	var visited := {}
	var parent := {}
	var queue: Array = [start]
	visited[start] = true
	var dirs := [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == target:
			# 回溯最短路径，检查是否含 hazard 格
			var path_cells := {}
			var node: Vector2i = cur
			while node != start:
				if hazard_cells.has(node):
					return true
				path_cells[node] = true
				if not parent.has(node):
					break
				node = parent[node]
			return false
		for d in dirs:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0:
				continue
			if nxt.y >= layout.grid.size() or nxt.x >= layout.grid[nxt.y].size():
				continue
			if visited.has(nxt):
				continue
			if int(layout.grid[nxt.y][nxt.x]) != 1:
				continue
			visited[nxt] = true
			parent[nxt] = cur
			queue.append(nxt)
	return false  # target 不可达，不算“依赖 hazard”
