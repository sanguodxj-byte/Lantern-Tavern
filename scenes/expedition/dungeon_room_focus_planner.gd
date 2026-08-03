class_name DungeonRoomFocusPlanner
extends RefCounted

const RUNTIME_CONFIG := preload("res://scenes/expedition/dungeon_runtime_config.gd")
const KEY_CELL_LABELS := ["player_spawn_cell", "extraction_cell", "boss_cell", "stairs_cell", "reward_cell"]
const ELEVATION_HEIGHT_M := 1.0
const CLIFF_HEIGHT_M := 1.5
const MIN_CLIFF_LENGTH_CELLS := 4
const MAX_CLIFF_LENGTH_CELLS := 7
const DECOR_SEED_SALT := 0x4D4150
const BLOCKING_DECOR := ["rubble", "small_crate", "barrel", "ritual_totem", "stalagmite_cluster", "sarcophagus"]

func plan(layout: DungeonLayout) -> void:
	if layout == null or layout.is_empty():
		return
	layout.room_focus_specs.clear()
	layout.room_composition_specs.clear()
	layout.terrain_features.clear()
	layout.decor_specs.clear()
	_ensure_floor_elevations(layout)
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed ^ DECOR_SEED_SALT
	var depth_field := layout.compute_floor_distance_field()
	var special_rooms := _select_special_rooms(layout)
	for room_index in range(layout.rooms.size()):
		var room: Rect2i = layout.rooms[room_index]
		if _is_start_room(layout, room):
			continue
		var composition_kind := _composition_kind_for_room(room_index, special_rooms)
		var focus_kind := _focus_kind_for_room(layout, room_index, room, composition_kind)
		var focus_cell := _pick_focus_cell(layout, room, focus_kind)
		var composition := _build_composition(layout, room_index, room, composition_kind, focus_cell)
		layout.room_composition_specs.append(composition)
		var theme := _room_theme(layout, room_index)
		_plan_room_environment(layout, room_index, room, theme, composition, focus_cell, depth_field, rng)
		if focus_cell.x < 0:
			continue
		layout.room_focus_specs.append({
			"focus_kind": focus_kind,
			"cell": focus_cell,
			"room_index": room_index,
		})

func _room_theme(layout: DungeonLayout, room_index: int) -> String:
	if room_index < layout.room_metadata.size():
		return String(layout.room_metadata[room_index].get("theme", "mixed"))
	return "mixed"

func _plan_room_environment(layout: DungeonLayout, room_index: int, room: Rect2i, theme: String, composition: Dictionary, focus_cell: Vector2i, depth_field: Dictionary, rng: RandomNumberGenerator) -> void:
	var depth := layout.depth_of_room_with_field(room, depth_field)
	var count := mini(1 + int(room.size.x * room.size.y / 45) + (1 if depth >= 12 else 0), 4)
	var kinds: Array[String] = _decor_kinds_for_theme(theme, composition.get("composition_kind", "battle"))
	var used_cells: Dictionary = {}
	for i in range(count):
		var decor_kind: String = "ritual_totem" if theme == "ritual" and i == 0 else kinds[rng.randi_range(0, kinds.size() - 1)]
		var placement := RUNTIME_CONFIG.dungeon_decor_placement_for(decor_kind)
		var candidates := _candidate_cells_for_placement(layout, room, focus_cell, composition, placement, used_cells)
		# 仪式图腾是主题身份锚点；即使房间没有墙边，也要退回普通地面格，不能丢失身份。
		if candidates.is_empty() and decor_kind == "ritual_totem":
			placement = "floor"
			candidates = _candidate_cells_for_placement(layout, room, focus_cell, composition, placement, used_cells)
		# 某个主题的首选摆放位不足时，换同主题的另一种装饰，保持布局密度但不把墙挂物硬塞到房间中央。
		if candidates.is_empty():
			for alternate_kind in kinds:
				var alternate_placement := RUNTIME_CONFIG.dungeon_decor_placement_for(alternate_kind)
				var alternate_candidates := _candidate_cells_for_placement(layout, room, focus_cell, composition, alternate_placement, used_cells)
				if not alternate_candidates.is_empty():
					decor_kind = alternate_kind
					placement = alternate_placement
					candidates = alternate_candidates
					break
		if candidates.is_empty():
			break
		var candidate_index := rng.randi_range(0, candidates.size() - 1)
		var cell: Vector2i = candidates[candidate_index]
		used_cells[cell] = true
		var wall_direction := _wall_direction_for_cell(layout, cell)
		var scene_path := RUNTIME_CONFIG.dungeon_decor_scene_path(decor_kind)
		if scene_path.is_empty():
			continue
		layout.decor_specs.append({
			"decor_kind": decor_kind,
			"scene_path": scene_path,
			"cell": cell,
			"room_index": room_index,
			"rotation_quarters": _rotation_quarters_for_wall(wall_direction) if placement == "wall" else rng.randi_range(0, 3),
			"blocks_navigation": BLOCKING_DECOR.has(decor_kind),
			"theme": theme,
			"placement": placement,
			"wall_direction": wall_direction,
		})
	layout.terrain_features.append({
		"feature_kind": "room_environment",
		"room_index": room_index,
		"theme": theme,
		"decor_count": count,
		"depth_cells": depth,
	})


func _candidate_cells_for_placement(layout: DungeonLayout, room: Rect2i, focus_cell: Vector2i,
		composition: Dictionary, placement: String, used_cells: Dictionary) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y in range(room.position.y + 1, room.position.y + room.size.y - 1):
		for x in range(room.position.x + 1, room.position.x + room.size.x - 1):
			var cell := Vector2i(x, y)
			if used_cells.has(cell) or not _is_environment_cell_allowed(layout, cell, focus_cell, composition):
				continue
			var wall_direction := _wall_direction_for_cell(layout, cell)
			var near_edge := _is_near_room_edge(cell, room)
			var focus_distance := absi(cell.x - focus_cell.x) + absi(cell.y - focus_cell.y)
			match placement:
				"wall":
					if wall_direction == Vector2i.ZERO:
						continue
				"edge":
					if not near_edge and wall_direction == Vector2i.ZERO:
						continue
				"anchor":
					if focus_distance < 2:
						continue
				_:
					# 普通地面装饰远离房间焦点一格，避免所有物体回到视觉中心。
					if focus_distance <= 1:
						continue
			candidates.append(cell)
	return candidates


func _is_near_room_edge(cell: Vector2i, room: Rect2i) -> bool:
	return cell.x <= room.position.x + 1 or cell.y <= room.position.y + 1 \
			or cell.x >= room.position.x + room.size.x - 2 \
			or cell.y >= room.position.y + room.size.y - 2


func _wall_direction_for_cell(layout: DungeonLayout, cell: Vector2i) -> Vector2i:
	for direction in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var neighbor: Vector2i = cell + direction
		if neighbor.y < 0 or neighbor.y >= layout.grid.size() \
				or neighbor.x < 0 or neighbor.x >= layout.grid[neighbor.y].size():
			continue
		if int(layout.grid[neighbor.y][neighbor.x]) == 2:
			return direction
	return Vector2i.ZERO


func _rotation_quarters_for_wall(direction: Vector2i) -> int:
	match direction:
		Vector2i(0, -1): return 2
		Vector2i(1, 0): return 1
		Vector2i(-1, 0): return 3
		_: return 0

func _decor_kinds_for_theme(theme: String, composition_kind: String) -> Array[String]:
	if composition_kind == "ambush":
		return ["rubble", "small_crate", "barrel", "stalagmite_cluster", "fungus_patch"]
	match theme:
		"resource": return ["rubble", "barrel", "small_crate", "fungus_patch", "stalagmite_cluster"]
		"loot", "stash": return ["small_crate", "bones", "rubble", "sarcophagus", "fungus_patch"]
		"ritual": return ["ritual_totem", "bones", "floor_candelabrum", "plank", "stalagmite_cluster", "fungus_patch"]
		"pillars": return ["floor_candelabrum", "wall_candelabrum", "iron_bar_grate", "wall_chain", "stalagmite_cluster"]
		_: return ["rubble", "bones", "plank", "wall_chain", "fungus_patch", "stalagmite_cluster"]

func _is_environment_cell_allowed(layout: DungeonLayout, cell: Vector2i, focus_cell: Vector2i, composition: Dictionary) -> bool:
	if not layout.is_floor_cell(cell) or cell == focus_cell:
		return false
	if composition.get("cover_cells", []).has(cell) or composition.get("platform_cells", []).has(cell) or composition.get("bridge_cells", []).has(cell):
		return false
	if composition.get("door_transition_cells", []).has(cell):
		return false
	for label in KEY_CELL_LABELS:
		var key_cell: Vector2i = layout.get(label)
		if not layout.is_key_cell_missing(key_cell) and cell == key_cell:
			return false
	for anchor in layout.hazard_anchors:
		var hazard_cell: Vector2i = anchor.get("anchor_cell", Vector2i(-1, -1))
		if maxi(absi(cell.x - hazard_cell.x), absi(cell.y - hazard_cell.y)) <= 1:
			return false
	return true

func _select_special_rooms(layout: DungeonLayout) -> Dictionary:
	var result := {
		"hall": -1,
		"ambush": -1,
		"elevation": -1,
		"trap": -1,
		"reward": _room_index_for_role(layout, "reward"),
		"boss": _room_index_for_role(layout, "boss"),
	}
	var occupied: Dictionary = {}
	for key in ["boss", "reward"]:
		var role_index := int(result[key])
		if role_index >= 0:
			occupied[role_index] = true
	result["hall"] = _largest_available_room(layout, occupied)
	if int(result["hall"]) >= 0:
		occupied[int(result["hall"])] = true
	result["cliff"] = _largest_available_cliff_room(layout, occupied)
	if int(result["cliff"]) >= 0:
		occupied[int(result["cliff"])] = true
	result["elevation"] = _available_role_or_room(layout, "stairs", occupied)
	if int(result["elevation"]) >= 0:
		occupied[int(result["elevation"])] = true
	result["trap"] = _room_with_hazard(layout, occupied)
	if int(result["trap"]) >= 0:
		occupied[int(result["trap"])] = true
	result["ambush"] = _room_with_multiple_entrances(layout, occupied)
	return result

func _composition_kind_for_room(room_index: int, special_rooms: Dictionary) -> String:
	for kind in ["boss", "reward", "cliff", "elevation", "ambush", "trap", "hall"]:
		if int(special_rooms.get(kind, -1)) == room_index:
			return kind
	return "battle"

func _focus_kind_for_room(layout: DungeonLayout, room_index: int, room: Rect2i, composition_kind: String) -> String:
	if composition_kind == "boss":
		return "boss_altar"
	if composition_kind == "reward":
		return "treasure_niche"
	if composition_kind == "elevation":
		return "stairs_shrine"
	if composition_kind == "cliff":
		return "cliff_overlook"
	if composition_kind == "hall":
		return "guard_post"
	if composition_kind == "ambush":
		return "battle_cross"
	if composition_kind == "trap":
		return "ritual_circle"
	if room_index < layout.room_metadata.size():
		match String(layout.room_metadata[room_index].get("theme", "")):
			"ritual":
				return "ritual_circle"
			"resource":
				return "resource_cluster"
			"pillars":
				return "guard_post"
			"mixed":
				return "battle_cross"
			"loot", "stash":
				return "treasure_niche"
	return "waystone"

func _build_composition(layout: DungeonLayout, room_index: int, room: Rect2i, kind: String, focus_cell: Vector2i) -> Dictionary:
	var platform_cells: Array[Vector2i] = []
	var bridge_cells: Array[Vector2i] = []
	var ramp_specs: Array[Dictionary] = []
	var cliff_cells: Array[Vector2i] = []
	var cliff_edges: Array[Dictionary] = []
	var cliff_direction := Vector2i.ZERO
	if kind == "elevation":
		platform_cells = _pick_platform_cluster(layout, room, focus_cell)
		if not platform_cells.is_empty():
			var ramp := _pick_ramp_cell(layout, room, platform_cells, focus_cell)
			if not ramp.is_empty():
				ramp_specs.append(ramp)
			var bridge := _pick_bridge_cell(layout, room, platform_cells, ramp, focus_cell)
			if bridge.x >= 0:
				bridge_cells.append(bridge)
		for cell in platform_cells + bridge_cells:
			if cell.y >= 0 and cell.y < layout.floor_elevations.size() and cell.x >= 0 and cell.x < layout.floor_elevations[cell.y].size():
				layout.floor_elevations[cell.y][cell.x] = ELEVATION_HEIGHT_M
	elif kind == "cliff":
		var cliff := _pick_cliff_feature(layout, room, focus_cell)
		for cell_value in cliff.get("cells", []):
			cliff_cells.append(cell_value)
		for edge_value in cliff.get("edges", []):
			cliff_edges.append(edge_value)
		cliff_direction = cliff.get("direction", Vector2i.ZERO)
		for cliff_cell in cliff_cells:
			platform_cells.append(cliff_cell)
		for ramp_value in cliff.get("ramp_specs", []):
			ramp_specs.append(ramp_value)
		for cell in cliff_cells:
			if cell.y >= 0 and cell.y < layout.floor_elevations.size() and cell.x >= 0 and cell.x < layout.floor_elevations[cell.y].size():
				layout.floor_elevations[cell.y][cell.x] = CLIFF_HEIGHT_M
	var elevated_cells: Array[Vector2i] = platform_cells + bridge_cells
	var ramp_cells: Array[Vector2i] = []
	for ramp_spec in ramp_specs:
		ramp_cells.append(ramp_spec["cell"])
	var cover_cells := _pick_cover_cells(layout, room, kind, focus_cell, elevated_cells, ramp_cells)
	var boundary_edges := _build_boundary_edges(elevated_cells, ramp_cells)
	var warning_cells := _hazard_cells_in_room(layout, room_index)
	var composition := {
		"room_index": room_index,
		"composition_kind": kind,
		"focus_cell": focus_cell,
		"cover_cells": cover_cells,
		"platform_cells": platform_cells,
		"bridge_cells": bridge_cells,
		"ramp_specs": ramp_specs,
		"boundary_edges": boundary_edges,
		"warning_cells": warning_cells,
		"door_transition_cells": _find_room_entrance_cells(layout, room),
		"enemy_sectors": _build_enemy_sectors(layout, room, kind, elevated_cells, focus_cell),
		"elevation_m": CLIFF_HEIGHT_M if kind == "cliff" and not elevated_cells.is_empty() else (ELEVATION_HEIGHT_M if not elevated_cells.is_empty() else 0.0),
		"cliff_cells": cliff_cells,
		"cliff_edges": cliff_edges,
		"cliff_direction": cliff_direction,
	}
	if kind == "cliff" and cliff_cells.size() >= MIN_CLIFF_LENGTH_CELLS:
		layout.terrain_features.append({
			"feature_kind": "cliff",
			"room_index": room_index,
			"cells": cliff_cells.duplicate(),
			"edges": cliff_edges.duplicate(true),
			"length_cells": cliff_cells.size(),
			"direction": cliff_direction,
			"ramp_cell": ramp_specs[0].get("cell", Vector2i(-1, -1)) if not ramp_specs.is_empty() else Vector2i(-1, -1),
			"elevation_m": CLIFF_HEIGHT_M,
		})
	return composition

func _build_enemy_sectors(layout: DungeonLayout, room: Rect2i, kind: String, elevated_cells: Array[Vector2i], focus_cell: Vector2i) -> Array[Dictionary]:
	var center := _nearest_floor_cell(layout, room, room.position + Vector2i(room.size.x / 2, room.size.y / 2), focus_cell)
	var left := _nearest_floor_cell(layout, room, room.position + Vector2i(1, room.size.y / 2), focus_cell)
	var right := _nearest_floor_cell(layout, room, room.position + Vector2i(room.size.x - 2, room.size.y / 2), focus_cell)
	var rear := _nearest_floor_cell(layout, room, room.position + Vector2i(room.size.x / 2, 1), focus_cell)
	var sectors: Array[Dictionary] = [
		{"name": "left_flank", "combat_role": "melee_flank", "center": left, "radius_cells": 2},
		{"name": "right_flank", "combat_role": "melee_flank", "center": right, "radius_cells": 2},
		{"name": "rear_guard", "combat_role": "rear_guard", "center": rear, "radius_cells": 2},
	]
	if kind == "boss":
		sectors = [{"name": "focus", "combat_role": "elite_focus", "center": center, "radius_cells": 2}]
	elif kind in ["elevation", "cliff"] and not elevated_cells.is_empty():
		sectors[2] = {"name": "elevated_rear", "combat_role": "elevated_guard", "center": elevated_cells[0], "radius_cells": 2}
	return sectors

func _pick_cover_cells(layout: DungeonLayout, room: Rect2i, kind: String, focus_cell: Vector2i, elevated_cells: Array[Vector2i], ramp_cells: Array[Vector2i]) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(room.size.x - 2, 1),
		Vector2i(1, room.size.y - 2), Vector2i(room.size.x - 2, room.size.y - 2),
	]
	if kind == "ambush":
		offsets = [Vector2i(1, 2), Vector2i(room.size.x - 2, room.size.y - 2), Vector2i(1, room.size.y - 3)]
	elif kind == "trap":
		offsets = [Vector2i(1, 1), Vector2i(room.size.x - 2, room.size.y - 2)]
	var result: Array[Vector2i] = []
	for offset in offsets:
		var cell := room.position + offset
		if not _is_composition_cell_allowed(layout, room, cell, focus_cell, elevated_cells + ramp_cells):
			continue
		result.append(cell)
		if result.size() >= (4 if kind == "hall" else 3):
			break
	return result

func _pick_platform_cluster(layout: DungeonLayout, room: Rect2i, focus_cell: Vector2i) -> Array[Vector2i]:
	var center := room.position + Vector2i(room.size.x / 2, room.size.y / 2)
	var origins: Array[Vector2i] = [
		center + Vector2i(1, -1), center + Vector2i(-2, -1),
		center + Vector2i(1, 1), center + Vector2i(-2, 1),
	]
	for origin in origins:
		var candidate: Array[Vector2i] = [origin, origin + Vector2i(1, 0), origin + Vector2i(0, 1), origin + Vector2i(1, 1)]
		var valid := true
		for cell in candidate:
			if not _is_composition_cell_allowed(layout, room, cell, focus_cell, []):
				valid = false
				break
		if valid:
			return candidate
	return []

func _pick_ramp_cell(layout: DungeonLayout, room: Rect2i, platform_cells: Array[Vector2i], focus_cell: Vector2i) -> Dictionary:
	var platform_cell: Vector2i = platform_cells[0]
	for direction_variant in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var direction: Vector2i = direction_variant
		var low_cell: Vector2i = platform_cell + direction
		if _is_composition_cell_allowed(layout, room, low_cell, focus_cell, platform_cells):
			return {"cell": low_cell, "dir": -direction, "high_cell": platform_cell}
	return {}

func _pick_bridge_cell(layout: DungeonLayout, room: Rect2i, platform_cells: Array[Vector2i], ramp: Dictionary, focus_cell: Vector2i) -> Vector2i:
	var ramp_cell: Vector2i = ramp.get("cell", Vector2i(-1, -1))
	for platform_cell in platform_cells:
		for direction_variant in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var direction: Vector2i = direction_variant
			var candidate: Vector2i = platform_cell + direction
			if candidate == ramp_cell:
				continue
			if _is_composition_cell_allowed(layout, room, candidate, focus_cell, platform_cells):
				return candidate
	return Vector2i(-1, -1)

func _build_boundary_edges(elevated_cells: Array[Vector2i], ramp_cells: Array[Vector2i]) -> Array[Dictionary]:
	var elevated := {}
	for cell in elevated_cells:
		elevated[cell] = true
	var ramp_set := {}
	for cell in ramp_cells:
		ramp_set[cell] = true
	var edges: Array[Dictionary] = []
	for cell in elevated_cells:
		for direction_variant in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var direction: Vector2i = direction_variant
			var neighbor: Vector2i = cell + direction
			if elevated.has(neighbor) or ramp_set.has(neighbor):
				continue
			edges.append({"cell": cell, "dir": direction})
	return edges

func _hazard_cells_in_room(layout: DungeonLayout, room_index: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for anchor in layout.hazard_anchors:
		if int(anchor.get("room_index", -1)) == room_index:
			cells.append(anchor.get("anchor_cell", Vector2i(-1, -1)))
	return cells

func _is_composition_cell_allowed(layout: DungeonLayout, room: Rect2i, cell: Vector2i, focus_cell: Vector2i, blocked: Array) -> bool:
	if not room.has_point(cell) or not layout.is_floor_cell(cell):
		return false
	if int(layout.grid[cell.y][cell.x]) == 5 or cell == focus_cell or blocked.has(cell):
		return false
	for label in KEY_CELL_LABELS:
		var key_cell: Vector2i = layout.get(label)
		if not layout.is_key_cell_missing(key_cell) and key_cell == cell:
			return false
	for anchor in layout.hazard_anchors:
		var hazard_cell: Vector2i = anchor.get("anchor_cell", Vector2i(-1, -1))
		if maxi(absi(cell.x - hazard_cell.x), absi(cell.y - hazard_cell.y)) <= 1:
			return false
	return true

func _nearest_floor_cell(layout: DungeonLayout, room: Rect2i, requested: Vector2i, excluded: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := 1_000_000
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			var cell := Vector2i(x, y)
			if not layout.is_floor_cell(cell) or int(layout.grid[y][x]) == 5 or cell == excluded:
				continue
			var distance := absi(cell.x - requested.x) + absi(cell.y - requested.y)
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best

func _pick_focus_cell(layout: DungeonLayout, room: Rect2i, focus_kind: String) -> Vector2i:
	var center := room.position + Vector2i(room.size.x / 2, room.size.y / 2)
	var candidates: Array[Vector2i] = [
		center, center + Vector2i(1, 0), center + Vector2i(-1, 0),
		center + Vector2i(0, 1), center + Vector2i(0, -1), room.position + Vector2i(1, 1),
	]
	for candidate in candidates:
		if not room.has_point(candidate) or not layout.is_floor_cell(candidate):
			continue
		if not _is_focus_cell_allowed(layout, room, candidate, focus_kind):
			continue
		return candidate
	return Vector2i(-1, -1)

func _is_focus_cell_allowed(layout: DungeonLayout, room: Rect2i, cell: Vector2i, focus_kind: String) -> bool:
	if int(layout.grid[cell.y][cell.x]) == 5:
		return false
	if room.size.x >= 5 and room.size.y >= 5 and not room.grow(-1).has_point(cell):
		return false
	for label in KEY_CELL_LABELS:
		var key_cell: Vector2i = layout.get(label)
		if not layout.is_key_cell_missing(key_cell) and key_cell == cell:
			return focus_kind == "boss_altar" and label != "boss_cell"
	for anchor in layout.hazard_anchors:
		if anchor.get("anchor_cell", Vector2i(-1, -1)) == cell:
			return false
	for spec in layout.enemy_spawn_specs:
		if spec.get("cell", Vector2i(-1, -1)) == cell:
			return false
	for spec in layout.item_spawn_specs:
		if spec.get("cell", Vector2i(-1, -1)) == cell:
			return false
	for spec in layout.chest_spawn_specs:
		if spec.get("cell", Vector2i(-1, -1)) == cell:
			return false
	return true

func _find_room_entrance_cells(layout: DungeonLayout, room: Rect2i) -> Array[Vector2i]:
	var entrances: Array[Vector2i] = []
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			var cell := Vector2i(x, y)
			if not layout.is_floor_cell(cell) or not _is_on_room_edge(cell, room):
				continue
			for direction_variant in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var direction: Vector2i = direction_variant
				var outside: Vector2i = cell + direction
				if not room.has_point(outside) and layout.is_floor_cell(outside):
					entrances.append(cell)
					break
	return entrances

func _is_on_room_edge(cell: Vector2i, room: Rect2i) -> bool:
	return cell.x == room.position.x or cell.y == room.position.y \
		or cell.x == room.position.x + room.size.x - 1 \
		or cell.y == room.position.y + room.size.y - 1

func _room_with_hazard(layout: DungeonLayout, occupied: Dictionary) -> int:
	for anchor in layout.hazard_anchors:
		var index := int(anchor.get("room_index", -1))
		if index >= 0 and not occupied.has(index) and not _is_start_room(layout, layout.rooms[index]):
			return index
	return _first_available_room(layout, occupied)

func _room_with_multiple_entrances(layout: DungeonLayout, occupied: Dictionary) -> int:
	for index in range(layout.rooms.size()):
		if occupied.has(index) or _is_start_room(layout, layout.rooms[index]):
			continue
		if _find_room_entrance_cells(layout, layout.rooms[index]).size() >= 2:
			return index
	return _first_available_room(layout, occupied)

func _largest_available_room(layout: DungeonLayout, occupied: Dictionary) -> int:
	var best := -1
	var best_area := -1
	for index in range(layout.rooms.size()):
		if occupied.has(index) or _is_start_room(layout, layout.rooms[index]):
			continue
		var area := layout.rooms[index].size.x * layout.rooms[index].size.y
		if area > best_area:
			best = index
			best_area = area
	return best


func _largest_available_cliff_room(layout: DungeonLayout, occupied: Dictionary) -> int:
	var candidates: Array[int] = []
	for index in range(layout.rooms.size()):
		if occupied.has(index) or _is_start_room(layout, layout.rooms[index]):
			continue
		candidates.append(index)
	candidates.sort_custom(func(a: int, b: int) -> bool:
		var area_a := layout.rooms[a].size.x * layout.rooms[a].size.y
		var area_b := layout.rooms[b].size.x * layout.rooms[b].size.y
		return area_a > area_b
	)
	for index in candidates:
		if not _pick_cliff_feature(layout, layout.rooms[index], Vector2i(-1, -1)).is_empty():
			return index
	return -1


## 选择一个房间内部的连续悬崖平台。
## 候选必须留在房间内部、长度至少 4 格、带一格斜坡，并且把悬崖格从低层
## 地面拓扑中移除后仍保持全部可走格连通。这样悬崖只改变房间内的垂直层次，
## 不会把房间入口或主路径切成两个孤岛。
func _pick_cliff_feature(layout: DungeonLayout, room: Rect2i, focus_cell: Vector2i) -> Dictionary:
	var axes: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	if room.size.y > room.size.x:
		axes.reverse()
	for axis in axes:
		var span := room.size.x if axis.x != 0 else room.size.y
		var interior_span := span - 2
		if interior_span < MIN_CLIFF_LENGTH_CELLS:
			continue
		var length := MIN_CLIFF_LENGTH_CELLS
		if interior_span > MIN_CLIFF_LENGTH_CELLS:
			length = mini(MAX_CLIFF_LENGTH_CELLS, interior_span - 1)
		if length < MIN_CLIFF_LENGTH_CELLS:
			continue
		var cross_start := room.position.y + 1 if axis.x != 0 else room.position.x + 1
		var cross_end := room.end.y - 1 if axis.x != 0 else room.end.x - 1
		var cross_values: Array[int] = []
		var cross_center := floori(float(cross_start + cross_end - 1) / 2.0)
		for delta in [0, -1, 1, -2, 2, -3, 3]:
			var cross_value := cross_center + int(delta)
			if cross_value >= cross_start and cross_value < cross_end and not cross_values.has(cross_value):
				cross_values.append(cross_value)
		var start_min := room.position.x + 1 if axis.x != 0 else room.position.y + 1
		var start_max := (room.end.x - 1 - length) if axis.x != 0 else (room.end.y - 1 - length)
		var start_center := floori(float(start_min + start_max) / 2.0)
		var start_values: Array[int] = []
		for delta in [0, -1, 1, -2, 2, -3, 3]:
			var start_value := start_center + int(delta)
			if start_value >= start_min and start_value <= start_max and not start_values.has(start_value):
				start_values.append(start_value)
		for cross_value in cross_values:
			for start_value in start_values:
				var cells: Array[Vector2i] = []
				for offset in range(length):
					var cell := Vector2i(
						start_value + offset if axis.x != 0 else cross_value,
						cross_value if axis.x != 0 else start_value + offset)
					cells.append(cell)
				if not _cliff_cells_are_allowed(layout, room, cells, focus_cell):
					continue
				var ramp := _pick_cliff_ramp(layout, room, cells)
				if ramp.is_empty():
					continue
				if not _cliff_preserves_connectivity(layout, cells):
					continue
				var ramp_cells: Array[Vector2i] = [ramp["cell"]]
				var edges := _build_cliff_edges(layout, cells, ramp_cells)
				if edges.is_empty():
					continue
				return {
					"cells": cells,
					"edges": edges,
					"ramp_specs": [ramp],
					"direction": axis,
				}
	return {}


func _cliff_cells_are_allowed(layout: DungeonLayout, room: Rect2i, cells: Array[Vector2i], focus_cell: Vector2i) -> bool:
	if cells.size() < MIN_CLIFF_LENGTH_CELLS:
		return false
	for cell in cells:
		if not room.has_point(cell) or not layout.is_floor_cell(cell):
			return false
		if int(layout.grid[cell.y][cell.x]) == 5 or _is_cliff_forbidden_cell(layout, cell):
			return false
		# The focus may deliberately sit on the overlook platform; it is a room
		# landmark, not a path blocker, so it is intentionally allowed here.
		if cell == focus_cell:
			continue
	return true


func _is_cliff_forbidden_cell(layout: DungeonLayout, cell: Vector2i) -> bool:
	for label in KEY_CELL_LABELS:
		var key_cell: Vector2i = layout.get(label)
		if not layout.is_key_cell_missing(key_cell) and key_cell == cell:
			return true
	for anchor in layout.hazard_anchors:
		var hazard_cell: Vector2i = anchor.get("anchor_cell", Vector2i(-1, -1))
		if maxi(absi(cell.x - hazard_cell.x), absi(cell.y - hazard_cell.y)) <= 1:
			return true
	return false


func _pick_cliff_ramp(layout: DungeonLayout, room: Rect2i, cliff_cells: Array[Vector2i]) -> Dictionary:
	var cliff_set := {}
	for cell in cliff_cells:
		cliff_set[cell] = true
	var middle := int(cliff_cells.size() / 2)
	var ordered_indices: Array[int] = []
	for delta in [0, -1, 1, -2, 2, -3, 3]:
		var index := middle + int(delta)
		if index >= 0 and index < cliff_cells.size() and not ordered_indices.has(index):
			ordered_indices.append(index)
	for index in ordered_indices:
		var high_cell: Vector2i = cliff_cells[index]
		for direction_variant in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var direction: Vector2i = direction_variant
			var low_cell := high_cell + direction
			if not room.has_point(low_cell) or cliff_set.has(low_cell) or not layout.is_floor_cell(low_cell):
				continue
			if int(layout.grid[low_cell.y][low_cell.x]) == 5 or _is_cliff_forbidden_cell(layout, low_cell):
				continue
			return {
				"cell": low_cell,
				"dir": high_cell - low_cell,
				"high_cell": high_cell,
				"feature": "cliff",
			}
	return {}


func _build_cliff_edges(layout: DungeonLayout, cliff_cells: Array[Vector2i], ramp_cells: Array[Vector2i]) -> Array[Dictionary]:
	var cliff_set := {}
	for cell in cliff_cells:
		cliff_set[cell] = true
	var ramp_set := {}
	for cell in ramp_cells:
		ramp_set[cell] = true
	var edges: Array[Dictionary] = []
	for cell in cliff_cells:
		for direction_variant in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var direction: Vector2i = direction_variant
			var neighbor := cell + direction
			if cliff_set.has(neighbor) or ramp_set.has(neighbor) or not layout.is_floor_cell(neighbor):
				continue
			edges.append({"cell": cell, "dir": direction})
	return edges


func _cliff_preserves_connectivity(layout: DungeonLayout, blocked_cells: Array[Vector2i]) -> bool:
	if layout == null or layout.is_empty():
		return false
	var blocked := {}
	for cell in blocked_cells:
		blocked[cell] = true
	var start := layout.player_spawn_cell
	if layout.is_key_cell_missing(start) or blocked.has(start) or not layout.is_floor_cell(start):
		var found_start := false
		for y in range(layout.grid.size()):
			for x in range(layout.grid[y].size()):
				var candidate := Vector2i(x, y)
				if layout.is_floor_cell(candidate) and not blocked.has(candidate):
					start = candidate
					found_start = true
					break
			if found_start:
				break
		if not found_start:
			return false
	if layout.is_key_cell_missing(start) or blocked.has(start):
		return false
	var visited := {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for direction_variant in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var direction: Vector2i = direction_variant
			var next := current + direction
			if visited.has(next) or blocked.has(next) or not layout.is_floor_cell(next):
				continue
			visited[next] = true
			queue.append(next)
	for y in range(layout.grid.size()):
		for x in range(layout.grid[y].size()):
			var cell := Vector2i(x, y)
			if layout.is_floor_cell(cell) and not blocked.has(cell) and not visited.has(cell):
				return false
	for label in KEY_CELL_LABELS:
		var key_cell: Vector2i = layout.get(label)
		if not layout.is_key_cell_missing(key_cell) and not blocked.has(key_cell) and not visited.has(key_cell):
			return false
	return true

func _available_role_or_room(layout: DungeonLayout, role: String, occupied: Dictionary) -> int:
	var role_index := _room_index_for_role(layout, role)
	if role_index >= 0 and not occupied.has(role_index) and not _is_start_room(layout, layout.rooms[role_index]):
		return role_index
	return _first_available_room(layout, occupied)

func _first_available_room(layout: DungeonLayout, occupied: Dictionary) -> int:
	for index in range(layout.rooms.size()):
		if not occupied.has(index) and not _is_start_room(layout, layout.rooms[index]):
			return index
	return -1

func _room_index_for_role(layout: DungeonLayout, role: String) -> int:
	if not layout.room_roles.has(role):
		return -1
	var target: Rect2i = layout.room_roles[role]
	for index in range(layout.rooms.size()):
		if layout.rooms[index] == target:
			return index
	return -1

func _is_start_room(layout: DungeonLayout, room: Rect2i) -> bool:
	return layout.room_roles.has("start") and room == (layout.room_roles["start"] as Rect2i)

func _ensure_floor_elevations(layout: DungeonLayout) -> void:
	if layout.floor_elevations.size() == layout.height and not layout.floor_elevations.is_empty() and layout.floor_elevations[0].size() == layout.width:
		for y in range(layout.height):
			for x in range(layout.width):
				layout.floor_elevations[y][x] = 0.0
		return
	layout.floor_elevations = []
	for y in range(layout.height):
		var row: Array = []
		for x in range(layout.width):
			row.append(0.0)
		layout.floor_elevations.append(row)
