class_name DungeonLayoutQuality
extends RefCounted

const MIN_WALKABLE_RATIO := 0.27
const MIN_REACHABLE_RATIO := 0.95
const MIN_MAIN_PATH_CELLS := 12
const MIN_ROOM_COUNT := 6

static func evaluate(layout: DungeonLayout) -> Dictionary:
	var walkable_cells := _collect_walkable_cells(layout)
	var walkable_count: int = walkable_cells.size()
	var total_cells: int = maxi(1, layout.width * layout.height)
	var floor_ratio := float(walkable_count) / float(total_cells)
	var reachable := _reachable_cells(layout, walkable_cells)
	var reachable_ratio := 0.0 if walkable_count == 0 else float(reachable.size()) / float(walkable_count)
	var main_path := _distance_between(layout, layout.player_spawn_cell, layout.boss_cell)
	var dead_ends := 0
	var junctions := 0
	for cell in walkable_cells:
		var degree := _walkable_neighbor_count(layout, cell)
		if degree <= 1:
			dead_ends += 1
		elif degree >= 3:
			junctions += 1
	var bbox := _walkable_bounds(walkable_cells)
	var bbox_ratio := 0.0 if bbox == Rect2i() else float(bbox.size.x * bbox.size.y) / float(total_cells)
	var checks := {
		"walkable_ratio": floor_ratio >= MIN_WALKABLE_RATIO,
		"reachable_ratio": reachable_ratio >= MIN_REACHABLE_RATIO,
		"main_path": main_path >= MIN_MAIN_PATH_CELLS,
		"room_count": layout.rooms.size() >= MIN_ROOM_COUNT,
	}
	var valid := true
	for passed in checks.values():
		if not bool(passed):
			valid = false
	return {
		"valid": valid,
		"walkable_count": walkable_count,
		"walkable_ratio": floor_ratio,
		"reachable_count": reachable.size(),
		"reachable_ratio": reachable_ratio,
		"main_path_cells": main_path,
		"room_count": layout.rooms.size(),
		"dead_end_count": dead_ends,
		"junction_count": junctions,
		"occupied_bbox": bbox,
		"occupied_bbox_ratio": bbox_ratio,
		"checks": checks,
	}

static func _collect_walkable_cells(layout: DungeonLayout) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(layout.grid.size()):
		for x in range(layout.grid[y].size()):
			if layout.is_floor_at(x, y):
				cells.append(Vector2i(x, y))
	return cells

static func _reachable_cells(layout: DungeonLayout, walkable_cells: Array[Vector2i]) -> Dictionary:
	var result := {}
	if walkable_cells.is_empty():
		return result
	var start := layout.player_spawn_cell if layout.is_floor_cell(layout.player_spawn_cell) else walkable_cells[0]
	var queue: Array[Vector2i] = [start]
	result[start] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + direction
			if result.has(next) or not layout.is_floor_cell(next):
				continue
			result[next] = true
			queue.append(next)
	return result

static func _distance_between(layout: DungeonLayout, start: Vector2i, target: Vector2i) -> int:
	if not layout.is_floor_cell(start) or not layout.is_floor_cell(target):
		return -1
	var queue: Array[Vector2i] = [start]
	var distance := {start: 0}
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == target:
			return int(distance[current])
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + direction
			if distance.has(next) or not layout.is_floor_cell(next):
				continue
			distance[next] = int(distance[current]) + 1
			queue.append(next)
	return -1

static func _walkable_neighbor_count(layout: DungeonLayout, cell: Vector2i) -> int:
	var count := 0
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if layout.is_floor_cell(cell + direction):
			count += 1
	return count

static func _walkable_bounds(cells: Array[Vector2i]) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var min_x := cells[0].x
	var max_x := cells[0].x
	var min_y := cells[0].y
	var max_y := cells[0].y
	for cell in cells:
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)
	return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))
