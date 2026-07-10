extends Node
class_name IsaacRoomDungeonGenerator

const ROOM_SIZE := 5
const ROOM_SPACING := 8
const TARGET_ROOM_COUNT := 14
const MACRO_RADIUS := 2
const EXTRACTION_ROOM_PROBABILITY := 0.2
const SHORTCUT_CONNECTOR_SIZE := 5
const MERGED_ROOM_CONNECTION_WIDTH := 5
const ROOM_CENTER_JITTER := 2
const ROOM_SHAPES := [
	"square", "compact", "wide", "tall", "pocket_cave", "circle", "ellipse", "noise_cavern", "jagged_cavern",
	"cross", "l_room", "alcove", "offset_chamber", "double_chamber", "crescent", "pillar_hall",
	"great_hall", "split_chamber", "diamond", "ring", "broken_ring"
]
const GUARANTEED_ROOM_SHAPES := [
	"pocket_cave", "circle", "ellipse", "noise_cavern", "jagged_cavern", "double_chamber", "offset_chamber",
	"crescent", "l_room", "split_chamber"
]
const START_ROOM_SHAPES := ["wide", "tall", "alcove", "offset_chamber"]
const ROOM_CONTENT_THEMES := ["empty", "loot", "resource", "pillars", "mixed", "stash", "ritual"]

var rooms: Array[Rect2i] = []
var room_roles: Dictionary = {}
var room_metadata: Array[Dictionary] = []
var ceiling_heights: Array = []

# 阶段 9 条 6：可控随机源。set_rng 注入后所有 rand* 走 _rng，使生成可复现；
# 未注入时 fallback 全局 _randi()/_randf()（保旧行为，不破现 procedural 路径）。
var _rng: RandomNumberGenerator = null

## 注入可控随机源。rng.seed 由调用方设；DungeonGenerator 用 config.seed 配 rng 后注入。
func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng

func _randi() -> int:
	return _rng.randi() if _rng != null else randi()

func _randf() -> float:
	return _rng.randf() if _rng != null else randf()

func _randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to) if _rng != null else randi_range(from, to)

func _randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to) if _rng != null else randf_range(from, to)

## 受控 shuffle：_rng 注入时用 Fisher-Yates 走 _rng.randi_range，否则 fallback 全局 Array.shuffle()。
## Godot 4 的 Array.shuffle() 用全局随机源不受 _rng 控制，导致同 seed 不复现 —— 必须走本 wrapper。
func _shuffle(arr: Array) -> Array:
	if _rng == null:
		arr.shuffle()
		return arr
	# Fisher-Yates 用 _rng.randi_range 控序
	var n := arr.size()
	for i in range(n - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr

var _macro_rooms: Array[Vector2i] = []
var _macro_room_set: Dictionary = {}
var _shortcut_macro_connections: Array[Dictionary] = []
var _shortcut_connector_rects: Array[Rect2i] = []
var _merged_macro_connections: Array[Dictionary] = []
var _merged_partition_rects: Array[Rect2i] = []
var _room_defs: Dictionary = {}
var _start_macro := Vector2i.ZERO
var _width := 0
var _height := 0


func generate_dungeon(width: int, height: int, target_room_count: int = TARGET_ROOM_COUNT) -> Array:
	_width = width
	_height = height
	rooms.clear()
	room_roles.clear()
	room_metadata.clear()
	_macro_rooms.clear()
	_macro_room_set.clear()
	_shortcut_macro_connections.clear()
	_shortcut_connector_rects.clear()
	_merged_macro_connections.clear()
	_merged_partition_rects.clear()
	_room_defs.clear()
	_start_macro = Vector2i.ZERO

	var grid := _make_filled_grid(width, height, BSP_DungeonGenerator.TileType.WALL)
	ceiling_heights = _make_height_grid(width, height, 3.4)
	_generate_room_graph(clampi(target_room_count, 6, 18))
	_start_macro = _pick_start_macro()
	_build_room_defs()
	_assign_room_roles()
	_ensure_merged_room_connection_count(3)
	_carve_rooms_and_corridors(grid)
	_mark_special_room_cells(grid)
	_ensure_walkable_connectivity(grid)
	_lock_outer_walls(grid)
	return grid


func get_terminal_macro_rooms() -> Array[Vector2i]:
	var terminals: Array[Vector2i] = []
	for room in _macro_rooms:
		if _neighbor_count(room) <= 1 and room != _start_macro:
			terminals.append(room)
	return terminals


func get_terminal_rooms() -> Array[Rect2i]:
	var terminal_rooms: Array[Rect2i] = []
	for macro in get_terminal_macro_rooms():
		terminal_rooms.append(_room_rect_for_macro(macro))
	return terminal_rooms


func get_macro_connection_pairs() -> Array[Dictionary]:
	var connections: Array[Dictionary] = []
	for macro in _macro_rooms:
		for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
			var next: Vector2i = macro + dir
			if _macro_room_set.has(next):
				connections.append({"a": macro, "b": next})
	for connection in _shortcut_macro_connections:
		connections.append(connection.duplicate())
	return connections


func get_shortcut_macro_connection_pairs() -> Array[Dictionary]:
	var connections: Array[Dictionary] = []
	for connection in _shortcut_macro_connections:
		connections.append(connection.duplicate())
	return connections


func get_shortcut_connector_rects() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for rect in _shortcut_connector_rects:
		rects.append(rect)
	return rects


func get_merged_macro_connection_pairs() -> Array[Dictionary]:
	var connections: Array[Dictionary] = []
	for connection in _merged_macro_connections:
		connections.append(connection.duplicate())
	return connections


func get_merged_partition_rects() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for rect in _merged_partition_rects:
		rects.append(rect)
	return rects


func _generate_room_graph(target_room_count: int) -> void:
	_add_macro_room(Vector2i.ZERO)
	while _macro_rooms.size() < target_room_count:
		var allow_loop_candidate := _macro_rooms.size() >= 5 and _macro_rooms.size() % 3 == 0
		var candidates := _collect_growth_candidates(allow_loop_candidate)
		if candidates.is_empty() and allow_loop_candidate:
			candidates = _collect_growth_candidates(false)
		if candidates.is_empty():
			break
		for candidate in candidates:
			var loop_bonus := 5.0 if int(candidate["neighbors"]) >= 2 else 0.0
			candidate["score"] = float(candidate["distance"]) + loop_bonus + _randf() * 0.75
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["score"]) > float(b["score"])
		)
		_add_macro_room(candidates[0]["cell"])
	_ensure_terminal_count(4)
	_ensure_shortcut_connection_count(3)


func _collect_growth_candidates(allow_loop_candidates: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for room in _macro_rooms:
		for dir in _dirs():
			var candidate: Vector2i = room + dir
			if seen.has(candidate) or _macro_room_set.has(candidate):
				continue
			seen[candidate] = true
			if abs(candidate.x) > MACRO_RADIUS or abs(candidate.y) > MACRO_RADIUS:
				continue
			var neighbors := _neighbor_count(candidate)
			if neighbors != 1 and not (allow_loop_candidates and neighbors == 2):
				continue
			result.append({
				"cell": candidate,
				"neighbors": neighbors,
				"distance": abs(candidate.x) + abs(candidate.y),
			})
	return result


func _ensure_terminal_count(min_count: int) -> void:
	var guard := 0
	while get_terminal_macro_rooms().size() < min_count and guard < 20:
		guard += 1
		var candidates := _collect_growth_candidates()
		if candidates.is_empty():
			return
		for candidate in candidates:
			var cell: Vector2i = candidate["cell"]
			candidate["branch_gain"] = 1 if _would_increase_terminal_count(cell) else 0
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var score_a := int(a["branch_gain"]) * 100 + int(a["distance"])
			var score_b := int(b["branch_gain"]) * 100 + int(b["distance"])
			return score_a > score_b
		)
		_add_macro_room(candidates[0]["cell"])


func _ensure_shortcut_connection_count(min_count: int) -> void:
	var candidates := _collect_shortcut_candidates()
	candidates = _shuffle(candidates)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["distance"]) < int(b["distance"])
	)
	for candidate in candidates:
		if _shortcut_macro_connections.size() >= min_count:
			return
		_shortcut_macro_connections.append({
			"a": candidate["a"],
			"b": candidate["b"],
		})


func _ensure_merged_room_connection_count(min_count: int) -> void:
	var candidates := _collect_adjacent_merge_candidates()
	candidates = _shuffle(candidates)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"])
	)
	var used_rooms: Dictionary = {}
	for candidate in candidates:
		if _merged_macro_connections.size() >= min_count:
			return
		var a: Vector2i = candidate["a"]
		var b: Vector2i = candidate["b"]
		if _is_boss_macro(a) or _is_boss_macro(b):
			continue
		if used_rooms.has(a) or used_rooms.has(b):
			continue
		used_rooms[a] = true
		used_rooms[b] = true
		_merged_macro_connections.append({
			"a": a,
			"b": b,
		})


func _collect_adjacent_merge_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for macro in _macro_rooms:
		for dir in [Vector2i.RIGHT, Vector2i.DOWN]:
			var next: Vector2i = macro + dir
			if not _macro_room_set.has(next):
				continue
			var key := _connection_key(macro, next)
			if seen.has(key):
				continue
			seen[key] = true
			if _is_boss_macro(macro) or _is_boss_macro(next):
				continue
			var terminal_penalty := 2 if _neighbor_count(macro) <= 1 or _neighbor_count(next) <= 1 else 0
			result.append({
				"a": macro,
				"b": next,
				"score": _neighbor_count(macro) + _neighbor_count(next) - terminal_penalty,
			})
	return result


func _collect_shortcut_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for i in range(_macro_rooms.size()):
		for j in range(i + 1, _macro_rooms.size()):
			var a: Vector2i = _macro_rooms[i]
			var b: Vector2i = _macro_rooms[j]
			if not _is_valid_shortcut_pair(a, b):
				continue
			var key := _connection_key(a, b)
			if seen.has(key):
				continue
			seen[key] = true
			result.append({
				"a": a,
				"b": b,
				"distance": abs(a.x - b.x) + abs(a.y - b.y),
			})
	return result


func _is_valid_shortcut_pair(a: Vector2i, b: Vector2i) -> bool:
	if _neighbor_count(a) <= 1 or _neighbor_count(b) <= 1:
		return false
	var delta: Vector2i = b - a
	var distance: int = abs(delta.x) + abs(delta.y)
	if distance < 2 or distance > 3:
		return false
	if delta.x != 0 and delta.y != 0:
		return false
	var dir := Vector2i(signi(delta.x), signi(delta.y))
	for step in range(1, distance):
		if _macro_room_set.has(a + dir * step):
			return false
	return true


func _assign_room_roles() -> void:
	var terminals := get_terminal_macro_rooms()
	terminals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _graph_distance(_start_macro, a) > _graph_distance(_start_macro, b)
	)
	var start_rect := _room_rect_for_macro(_start_macro)
	room_roles["start"] = start_rect
	var fallback: Vector2i = terminals[0] if not terminals.is_empty() else _fallback_non_start_macro()
	var boss: Vector2i = _take_terminal_role(terminals, fallback)
	room_roles["boss"] = _room_rect_for_macro(boss)
	if _randf() < EXTRACTION_ROOM_PROBABILITY:
		room_roles["extraction"] = _room_rect_for_macro(boss)
	var stairs: Vector2i = _take_terminal_role(terminals, boss)
	room_roles["stairs"] = _room_rect_for_macro(stairs)
	var reward: Vector2i = _take_terminal_role(terminals, boss)
	room_roles["reward"] = _room_rect_for_macro(reward)


func _pick_start_macro() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for macro in _macro_rooms:
		if macro == Vector2i.ZERO:
			continue
		if _neighbor_count(macro) >= 2:
			candidates.append(macro)
	if candidates.is_empty():
		for macro in _macro_rooms:
			if macro != Vector2i.ZERO:
				candidates.append(macro)
	if candidates.is_empty():
		return Vector2i.ZERO
	candidates = _shuffle(candidates)
	return candidates[0]


func _fallback_non_start_macro() -> Vector2i:
	for macro in _macro_rooms:
		if macro != _start_macro:
			return macro
	return _start_macro


func _carve_rooms_and_corridors(grid: Array) -> void:
	for macro in _macro_rooms:
		var room_def: Dictionary = _room_defs[macro]
		var rect: Rect2i = room_def["rect"]
		rooms.append(rect)
		room_metadata.append(room_def.duplicate())
		_carve_varied_room(grid, room_def)
		_apply_room_height(rect, float(room_def["height"]))
	for macro in _macro_rooms:
		for dir in _dirs():
			var next: Vector2i = macro + dir
			if _macro_room_set.has(next) and _macro_rooms.find(macro) < _macro_rooms.find(next):
				_carve_corridor(grid, _room_connection_cell(macro), _room_connection_cell(next))
	for connection in _merged_macro_connections:
		_carve_merged_room_connection(grid, connection["a"], connection["b"])
	for connection in _shortcut_macro_connections:
		_carve_shortcut_connection(grid, connection["a"], connection["b"])
	_apply_room_content(grid)


func _mark_special_room_cells(grid: Array) -> void:
	if room_roles.has("reward"):
		_mark_walkable_cell(grid, _rect_center(room_roles["reward"]), BSP_DungeonGenerator.TileType.LOOT)
	if room_roles.has("boss"):
		var boss_center := _rect_center(room_roles["boss"])
		_mark_walkable_cell(grid, boss_center + Vector2i(-1, 0), BSP_DungeonGenerator.TileType.RESOURCE)
		_mark_walkable_cell(grid, boss_center + Vector2i(1, 0), BSP_DungeonGenerator.TileType.RESOURCE)
	_ensure_terminal_room_rewards(grid)


func _ensure_walkable_connectivity(grid: Array) -> void:
	var guard := 0
	while guard < 16:
		guard += 1
		var components := _collect_walkable_components(grid)
		if components.size() <= 1:
			return
		components.sort_custom(func(a: Array, b: Array) -> bool:
			return a.size() > b.size()
		)
		var main_component: Array = components[0]
		var island: Array = components[1]
		var bridge := _nearest_cells_between_components(main_component, island)
		if bridge.is_empty():
			return
		_carve_corridor(grid, bridge["main"], bridge["island"])


func _collect_walkable_components(grid: Array) -> Array:
	var components: Array = []
	var visited: Dictionary = {}
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var start := Vector2i(x, y)
			if visited.has(start) or not _is_walkable_grid_cell(grid, start):
				continue
			var component: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start]
			visited[start] = true
			while not queue.is_empty():
				var current: Vector2i = queue.pop_front()
				component.append(current)
				for dir in _dirs():
					var next: Vector2i = current + dir
					if visited.has(next) or not _is_walkable_grid_cell(grid, next):
						continue
					visited[next] = true
					queue.append(next)
			components.append(component)
	return components


func _nearest_cells_between_components(main_component: Array, island: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 999999
	for main_cell in main_component:
		for island_cell in island:
			var distance: int = absi(main_cell.x - island_cell.x) + absi(main_cell.y - island_cell.y)
			if distance >= best_distance:
				continue
			best_distance = distance
			best = {
				"main": main_cell,
				"island": island_cell,
			}
	return best


func _is_walkable_grid_cell(grid: Array, cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= grid.size() or cell.x < 0 or cell.x >= grid[cell.y].size():
		return false
	var cell_type := int(grid[cell.y][cell.x])
	return cell_type != BSP_DungeonGenerator.TileType.EMPTY and cell_type != BSP_DungeonGenerator.TileType.WALL


func _build_room_defs() -> void:
	var shape_queue := _build_shape_queue()
	var theme_index := 0
	for macro in _macro_rooms:
		var shape: String = _take_next_room_shape(shape_queue, macro)
		var theme: String = ROOM_CONTENT_THEMES[theme_index % ROOM_CONTENT_THEMES.size()]
		if macro == _start_macro:
			shape = _pick_start_room_shape(macro)
			theme = "empty"
		var size := _size_for_room_shape(shape, macro)
		size = _constrain_size_for_neighbors(size, macro)
		var center := _relaxed_room_center(macro, size)
		var rect := _clamped_room_rect(center, size)
		var height := _height_for_room(macro, shape)
		_room_defs[macro] = {
			"macro": macro,
			"center": center,
			"rect": rect,
			"shape": shape,
			"theme": theme,
			"height": height,
			"area": rect.size.x * rect.size.y,
		}
		theme_index += 1


func _build_shape_queue() -> Array[String]:
	var queue: Array[String] = []
	for shape in GUARANTEED_ROOM_SHAPES:
		queue.append(String(shape))
	queue = _shuffle(queue)
	var distinctive_extras: Array[String] = []
	var rectilinear_extras: Array[String] = []
	for shape in ROOM_SHAPES:
		var shape_name := String(shape)
		if shape_name in queue:
			continue
		if _shape_family(shape_name) == "rectilinear":
			rectilinear_extras.append(shape_name)
		else:
			distinctive_extras.append(shape_name)
	distinctive_extras = _shuffle(distinctive_extras)
	rectilinear_extras = _shuffle(rectilinear_extras)
	queue.append_array(distinctive_extras)
	queue.append_array(rectilinear_extras)
	return queue


func _take_next_room_shape(shape_queue: Array[String], macro: Vector2i) -> String:
	if shape_queue.is_empty():
		shape_queue.append_array(_build_shape_queue())
	if shape_queue.is_empty():
		return "square"
	var fallback := shape_queue[0]
	for i in range(shape_queue.size()):
		var candidate := String(shape_queue[i])
		if not _shape_conflicts_with_defined_neighbors(macro, candidate):
			shape_queue.remove_at(i)
			return candidate
	shape_queue.pop_front()
	return fallback


func _shape_conflicts_with_defined_neighbors(macro: Vector2i, shape: String) -> bool:
	var family := _shape_family(shape)
	for dir in _dirs():
		var neighbor: Vector2i = macro + dir
		if not _room_defs.has(neighbor):
			continue
		if _shape_family(String(_room_defs[neighbor]["shape"])) == family:
			return true
	return false


func _shape_family(shape: String) -> String:
	if shape in ["square", "compact", "wide", "tall", "great_hall", "pillar_hall"]:
		return "rectilinear"
	if shape == "circle":
		return "round"
	if shape == "ellipse":
		return "oval"
	if shape == "diamond":
		return "diamond"
	if shape in ["pocket_cave", "noise_cavern", "jagged_cavern", "crescent"]:
		return "organic"
	return "asymmetric"


func _pick_start_room_shape(macro: Vector2i) -> String:
	var index := absi(macro.x * 17 + macro.y * 31 + _randi()) % START_ROOM_SHAPES.size()
	return START_ROOM_SHAPES[index]


func _size_for_room_shape(shape: String, macro: Vector2i) -> Vector2i:
	var base_sizes := {
		"square": Vector2i(5, 5),
		"compact": Vector2i(3, 3),
		"wide": Vector2i(7, 5),
		"tall": Vector2i(5, 7),
		"pocket_cave": Vector2i(5, 3),
		"circle": Vector2i(9, 9),
		"ellipse": Vector2i(11, 7),
		"noise_cavern": Vector2i(11, 9),
		"jagged_cavern": Vector2i(13, 9),
		"cross": Vector2i(9, 9),
		"l_room": Vector2i(9, 9),
		"alcove": Vector2i(9, 7),
		"offset_chamber": Vector2i(11, 9),
		"double_chamber": Vector2i(13, 7),
		"crescent": Vector2i(11, 11),
		"pillar_hall": Vector2i(9, 9),
		"great_hall": Vector2i(11, 7),
		"split_chamber": Vector2i(9, 9),
		"diamond": Vector2i(9, 9),
		"ring": Vector2i(9, 9),
		"broken_ring": Vector2i(11, 11),
	}
	var size: Vector2i = base_sizes.get(shape, Vector2i(5, 5))
	if shape != "compact" and _randf() < 0.45:
		var axis_roll := _randi_range(0, 2)
		if axis_roll != 1:
			size.x += 2
		if axis_roll != 0:
			size.y += 2
	if shape in ["double_chamber", "jagged_cavern", "broken_ring"] and _randf() < 0.35:
		size += Vector2i(2, 0) if _randf() < 0.5 else Vector2i(0, 2)
	size.x = clampi(size.x, 3, 13)
	size.y = clampi(size.y, 3, 13)
	if size.x % 2 == 0:
		size.x += 1
	if size.y % 2 == 0:
		size.y += 1
	return size


func _constrain_size_for_neighbors(size: Vector2i, macro: Vector2i) -> Vector2i:
	var constrained := size
	if _macro_room_set.has(macro + Vector2i.LEFT) or _macro_room_set.has(macro + Vector2i.RIGHT):
		constrained.x = mini(constrained.x, ROOM_SPACING - 1)
	if _macro_room_set.has(macro + Vector2i.UP) or _macro_room_set.has(macro + Vector2i.DOWN):
		constrained.y = mini(constrained.y, ROOM_SPACING - 1)
	constrained.x = maxi(constrained.x, 3)
	constrained.y = maxi(constrained.y, 3)
	if constrained.x % 2 == 0:
		constrained.x -= 1
	if constrained.y % 2 == 0:
		constrained.y -= 1
	return constrained


func _clamped_room_rect(center: Vector2i, size: Vector2i) -> Rect2i:
	var pos := center - Vector2i(size.x / 2, size.y / 2)
	pos.x = clampi(pos.x, 1, _width - size.x - 1)
	pos.y = clampi(pos.y, 1, _height - size.y - 1)
	return Rect2i(pos, size)


func _relaxed_room_center(macro: Vector2i, size: Vector2i) -> Vector2i:
	var base := _macro_to_grid_center(macro)
	var max_x := ROOM_CENTER_JITTER
	var max_y := ROOM_CENTER_JITTER
	if _macro_room_set.has(macro + Vector2i.LEFT) or _macro_room_set.has(macro + Vector2i.RIGHT):
		max_x = 1
	if _macro_room_set.has(macro + Vector2i.UP) or _macro_room_set.has(macro + Vector2i.DOWN):
		max_y = 1
	if size.x >= ROOM_SPACING - 1:
		max_x = 0
	if size.y >= ROOM_SPACING - 1:
		max_y = 0
	var jitter := Vector2i(_randi_range(-max_x, max_x), _randi_range(-max_y, max_y))
	var center := base + jitter
	var half_size := Vector2i(size.x / 2, size.y / 2)
	center.x = clampi(center.x, 1 + half_size.x, _width - half_size.x - 2)
	center.y = clampi(center.y, 1 + half_size.y, _height - half_size.y - 2)
	return center


func _carve_varied_room(grid: Array, room_def: Dictionary) -> void:
	var rect: Rect2i = room_def["rect"]
	var shape := String(room_def["shape"])
	match shape:
		"square", "compact", "wide", "tall":
			_carve_rect(grid, rect, BSP_DungeonGenerator.TileType.FLOOR)
		"circle":
			_carve_ellipse_room(grid, rect, 0.0)
		"ellipse":
			_carve_ellipse_room(grid, rect, 0.08)
		"pocket_cave":
			_carve_ellipse_room(grid, rect, 0.0)
		"noise_cavern":
			_carve_noise_cavern_room(grid, rect, room_def["macro"])
		"jagged_cavern":
			_carve_jagged_cavern_room(grid, rect, room_def["macro"])
		"cross":
			_carve_cross_room(grid, rect)
		"l_room":
			_carve_l_room(grid, rect, room_def["macro"])
		"alcove":
			_carve_alcove_room(grid, rect)
		"offset_chamber":
			_carve_offset_chamber_room(grid, rect, room_def["macro"])
		"double_chamber":
			_carve_double_chamber_room(grid, rect, room_def["macro"])
		"crescent":
			_carve_crescent_room(grid, rect, room_def["macro"])
		"pillar_hall":
			_carve_rect(grid, rect, BSP_DungeonGenerator.TileType.FLOOR)
			_carve_pillar_hall(grid, rect)
		"great_hall":
			_carve_rect(grid, rect, BSP_DungeonGenerator.TileType.FLOOR)
			_carve_great_hall(grid, rect)
		"split_chamber":
			_carve_rect(grid, rect, BSP_DungeonGenerator.TileType.FLOOR)
			_carve_split_chamber(grid, rect, room_def["macro"])
		"diamond":
			_carve_diamond_room(grid, rect)
		"ring":
			_carve_rect(grid, rect, BSP_DungeonGenerator.TileType.FLOOR)
			_carve_ring_room(grid, rect)
		"broken_ring":
			_carve_broken_ring_room(grid, rect, room_def["macro"])
		_:
			_carve_rect(grid, rect, BSP_DungeonGenerator.TileType.FLOOR)
	var center := _rect_center(rect)
	_carve_rect(grid, Rect2i(center - Vector2i(1, 1), Vector2i(3, 3)), BSP_DungeonGenerator.TileType.FLOOR)


func _carve_cross_room(grid: Array, rect: Rect2i) -> void:
	var center := _rect_center(rect)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(center.x - 1, center.x + 2):
			_set_cell(grid, Vector2i(x, y), BSP_DungeonGenerator.TileType.FLOOR)
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(center.y - 1, center.y + 2):
			_set_cell(grid, Vector2i(x, y), BSP_DungeonGenerator.TileType.FLOOR)


func _carve_l_room(grid: Array, rect: Rect2i, macro: Vector2i) -> void:
	var center := _rect_center(rect)
	var horizontal_rect: Rect2i
	var vertical_rect: Rect2i
	if macro.x >= 0:
		horizontal_rect = Rect2i(rect.position, Vector2i(rect.size.x, maxi(3, rect.size.y / 2 + 1)))
	else:
		horizontal_rect = Rect2i(Vector2i(rect.position.x, center.y - 1), Vector2i(rect.size.x, rect.position.y + rect.size.y - center.y + 1))
	if macro.y >= 0:
		vertical_rect = Rect2i(Vector2i(rect.position.x, rect.position.y), Vector2i(maxi(3, rect.size.x / 2 + 1), rect.size.y))
	else:
		vertical_rect = Rect2i(Vector2i(center.x - 1, rect.position.y), Vector2i(rect.position.x + rect.size.x - center.x + 1, rect.size.y))
	_carve_rect(grid, horizontal_rect, BSP_DungeonGenerator.TileType.FLOOR)
	_carve_rect(grid, vertical_rect, BSP_DungeonGenerator.TileType.FLOOR)


func _carve_alcove_room(grid: Array, rect: Rect2i) -> void:
	var core := rect.grow(-1)
	_carve_rect(grid, core, BSP_DungeonGenerator.TileType.FLOOR)
	var center := _rect_center(rect)
	_carve_rect(grid, Rect2i(Vector2i(rect.position.x, center.y - 1), Vector2i(rect.size.x, 3)), BSP_DungeonGenerator.TileType.FLOOR)
	_carve_rect(grid, Rect2i(Vector2i(center.x - 1, rect.position.y), Vector2i(3, rect.size.y)), BSP_DungeonGenerator.TileType.FLOOR)


func _carve_ellipse_room(grid: Array, rect: Rect2i, edge_slop: float = 0.0) -> void:
	var center := Vector2(rect.position) + (Vector2(rect.size) - Vector2.ONE) * 0.5
	var radius_x := maxf(float(rect.size.x - 1) * 0.5, 1.0)
	var radius_y := maxf(float(rect.size.y - 1) * 0.5, 1.0)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var normalized := pow((float(x) - center.x) / radius_x, 2.0) + pow((float(y) - center.y) / radius_y, 2.0)
			if normalized <= 1.0 + edge_slop:
				_set_cell(grid, Vector2i(x, y), BSP_DungeonGenerator.TileType.FLOOR)


func _carve_noise_cavern_room(grid: Array, rect: Rect2i, macro: Vector2i) -> void:
	var center := Vector2(rect.position) + (Vector2(rect.size) - Vector2.ONE) * 0.5
	var radius_x := maxf(float(rect.size.x - 1) * 0.5, 1.0)
	var radius_y := maxf(float(rect.size.y - 1) * 0.5, 1.0)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = _randi()
	noise.frequency = 0.42
	noise.fractal_octaves = 2
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var dx := (float(x) - center.x) / radius_x
			var dy := (float(y) - center.y) / radius_y
			var radial := sqrt(dx * dx + dy * dy)
			var boundary_noise := noise.get_noise_2d(float(x + macro.x * 37), float(y + macro.y * 41)) * 0.18
			if radial <= 0.88 + boundary_noise:
				_set_cell(grid, Vector2i(x, y), BSP_DungeonGenerator.TileType.FLOOR)


func _carve_jagged_cavern_room(grid: Array, rect: Rect2i, macro: Vector2i) -> void:
	var center := Vector2(rect.position) + (Vector2(rect.size) - Vector2.ONE) * 0.5
	var radius_x := maxf(float(rect.size.x - 1) * 0.5, 1.0)
	var radius_y := maxf(float(rect.size.y - 1) * 0.5, 1.0)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = _randi()
	noise.frequency = 0.72
	noise.fractal_octaves = 3
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var dx := (float(x) - center.x) / radius_x
			var dy := (float(y) - center.y) / radius_y
			var radial := sqrt(dx * dx + dy * dy)
			var n := noise.get_noise_2d(float(x + macro.x * 53), float(y + macro.y * 59))
			if radial <= 0.76 + n * 0.32:
				_set_cell(grid, Vector2i(x, y), BSP_DungeonGenerator.TileType.FLOOR)
	_carve_rect(grid, Rect2i(_rect_center(rect) - Vector2i(1, 1), Vector2i(3, 3)), BSP_DungeonGenerator.TileType.FLOOR)


func _carve_offset_chamber_room(grid: Array, rect: Rect2i, macro: Vector2i) -> void:
	var center := _rect_center(rect)
	var main_size := Vector2i(maxi(5, rect.size.x - 4), maxi(5, rect.size.y - 4))
	var main_offset := Vector2i(1 if macro.x >= 0 else rect.size.x - main_size.x - 1, 1)
	var wing_size := Vector2i(maxi(3, rect.size.x / 2), maxi(3, rect.size.y / 2))
	var wing_offset := Vector2i(rect.size.x - wing_size.x - 1 if macro.x >= 0 else 1, rect.size.y - wing_size.y - 1)
	_carve_rect(grid, Rect2i(rect.position + main_offset, main_size), BSP_DungeonGenerator.TileType.FLOOR)
	_carve_rect(grid, Rect2i(rect.position + wing_offset, wing_size), BSP_DungeonGenerator.TileType.FLOOR)
	_carve_rect(grid, Rect2i(center - Vector2i(1, 1), Vector2i(3, 3)), BSP_DungeonGenerator.TileType.FLOOR)


func _carve_double_chamber_room(grid: Array, rect: Rect2i, macro: Vector2i) -> void:
	var center := _rect_center(rect)
	if abs(macro.x) >= abs(macro.y):
		var left := Rect2i(rect.position + Vector2i(0, 1), Vector2i(maxi(3, rect.size.x / 2 - 1), rect.size.y - 2))
		var right := Rect2i(Vector2i(center.x + 1, rect.position.y + 1), Vector2i(rect.position.x + rect.size.x - center.x - 1, rect.size.y - 2))
		_carve_rect(grid, left, BSP_DungeonGenerator.TileType.FLOOR)
		_carve_rect(grid, right, BSP_DungeonGenerator.TileType.FLOOR)
		_carve_rect(grid, Rect2i(Vector2i(center.x - 1, center.y - 1), Vector2i(3, 3)), BSP_DungeonGenerator.TileType.FLOOR)
	else:
		var top := Rect2i(rect.position + Vector2i(1, 0), Vector2i(rect.size.x - 2, maxi(3, rect.size.y / 2 - 1)))
		var bottom := Rect2i(Vector2i(rect.position.x + 1, center.y + 1), Vector2i(rect.size.x - 2, rect.position.y + rect.size.y - center.y - 1))
		_carve_rect(grid, top, BSP_DungeonGenerator.TileType.FLOOR)
		_carve_rect(grid, bottom, BSP_DungeonGenerator.TileType.FLOOR)
		_carve_rect(grid, Rect2i(Vector2i(center.x - 1, center.y - 1), Vector2i(3, 3)), BSP_DungeonGenerator.TileType.FLOOR)


func _carve_crescent_room(grid: Array, rect: Rect2i, macro: Vector2i) -> void:
	var center := Vector2(rect.position) + (Vector2(rect.size) - Vector2.ONE) * 0.5
	var bite_dir := Vector2(1.0 if macro.x >= 0 else -1.0, 0.25 if macro.y >= 0 else -0.25)
	var bite_center := center + bite_dir.normalized() * maxf(2.0, float(mini(rect.size.x, rect.size.y)) * 0.22)
	var radius_x := maxf(float(rect.size.x - 1) * 0.5, 1.0)
	var radius_y := maxf(float(rect.size.y - 1) * 0.5, 1.0)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var p := Vector2(float(x), float(y))
			var outer := pow((p.x - center.x) / radius_x, 2.0) + pow((p.y - center.y) / radius_y, 2.0)
			var inner := pow((p.x - bite_center.x) / (radius_x * 0.72), 2.0) + pow((p.y - bite_center.y) / (radius_y * 0.72), 2.0)
			if outer <= 1.0 and inner > 0.72:
				_set_cell(grid, Vector2i(x, y), BSP_DungeonGenerator.TileType.FLOOR)
	_carve_rect(grid, Rect2i(_rect_center(rect) - Vector2i(1, 1), Vector2i(3, 3)), BSP_DungeonGenerator.TileType.FLOOR)


func _carve_pillar_hall(grid: Array, rect: Rect2i) -> void:
	if rect.size.x < 7 or rect.size.y < 7:
		return
	var offsets := [
		Vector2i(2, 2),
		Vector2i(rect.size.x - 3, 2),
		Vector2i(2, rect.size.y - 3),
		Vector2i(rect.size.x - 3, rect.size.y - 3),
	]
	for offset in offsets:
		_set_cell(grid, rect.position + offset, BSP_DungeonGenerator.TileType.PILLAR)


func _carve_great_hall(grid: Array, rect: Rect2i) -> void:
	var center := _rect_center(rect)
	for x in range(rect.position.x + 2, rect.position.x + rect.size.x - 2, 3):
		_set_cell(grid, Vector2i(x, center.y - 2), BSP_DungeonGenerator.TileType.PILLAR)
		_set_cell(grid, Vector2i(x, center.y + 2), BSP_DungeonGenerator.TileType.PILLAR)


func _carve_split_chamber(grid: Array, rect: Rect2i, macro: Vector2i) -> void:
	var center := _rect_center(rect)
	if abs(macro.x) >= abs(macro.y):
		for y in range(rect.position.y + 1, rect.position.y + rect.size.y - 1):
			if abs(y - center.y) <= 1:
				continue
			_set_cell(grid, Vector2i(center.x, y), BSP_DungeonGenerator.TileType.WALL)
	else:
		for x in range(rect.position.x + 1, rect.position.x + rect.size.x - 1):
			if abs(x - center.x) <= 1:
				continue
			_set_cell(grid, Vector2i(x, center.y), BSP_DungeonGenerator.TileType.WALL)


func _carve_diamond_room(grid: Array, rect: Rect2i) -> void:
	var center := _rect_center(rect)
	var radius := mini(rect.size.x, rect.size.y) / 2
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if abs(x - center.x) + abs(y - center.y) <= radius:
				_set_cell(grid, Vector2i(x, y), BSP_DungeonGenerator.TileType.FLOOR)


func _carve_ring_room(grid: Array, rect: Rect2i) -> void:
	var notches := [
		Rect2i(rect.position, Vector2i(2, 2)),
		Rect2i(Vector2i(rect.position.x + rect.size.x - 2, rect.position.y), Vector2i(2, 2)),
		Rect2i(Vector2i(rect.position.x, rect.position.y + rect.size.y - 2), Vector2i(2, 2)),
		Rect2i(rect.position + rect.size - Vector2i(2, 2), Vector2i(2, 2)),
	]
	for notch in notches:
		_carve_rect(grid, notch, BSP_DungeonGenerator.TileType.WALL)


func _carve_broken_ring_room(grid: Array, rect: Rect2i, macro: Vector2i) -> void:
	_carve_rect(grid, rect, BSP_DungeonGenerator.TileType.FLOOR)
	var inner := rect.grow(-2)
	if inner.size.x > 2 and inner.size.y > 2:
		_carve_rect(grid, inner, BSP_DungeonGenerator.TileType.WALL)
	var center := _rect_center(rect)
	_carve_rect(grid, Rect2i(center - Vector2i(1, 1), Vector2i(3, 3)), BSP_DungeonGenerator.TileType.FLOOR)
	var gap_side := absi(macro.x * 3 + macro.y * 5 + _randi()) % 4
	match gap_side:
		0:
			_carve_rect(grid, Rect2i(Vector2i(center.x - 1, rect.position.y), Vector2i(3, rect.size.y / 2 + 1)), BSP_DungeonGenerator.TileType.FLOOR)
		1:
			_carve_rect(grid, Rect2i(Vector2i(center.x - 1, center.y), Vector2i(3, rect.position.y + rect.size.y - center.y)), BSP_DungeonGenerator.TileType.FLOOR)
		2:
			_carve_rect(grid, Rect2i(Vector2i(rect.position.x, center.y - 1), Vector2i(rect.size.x / 2 + 1, 3)), BSP_DungeonGenerator.TileType.FLOOR)
		_:
			_carve_rect(grid, Rect2i(Vector2i(center.x, center.y - 1), Vector2i(rect.position.x + rect.size.x - center.x, 3)), BSP_DungeonGenerator.TileType.FLOOR)


func _apply_room_content(grid: Array) -> void:
	for room_def in room_metadata:
		var rect: Rect2i = room_def["rect"]
		var theme := String(room_def["theme"])
		match theme:
			"loot":
				_mark_walkable_cell(grid, _rect_center(rect) + Vector2i(0, -1), BSP_DungeonGenerator.TileType.LOOT)
			"resource":
				_mark_walkable_cell(grid, _rect_center(rect) + Vector2i(-1, 0), BSP_DungeonGenerator.TileType.RESOURCE)
				_mark_walkable_cell(grid, _rect_center(rect) + Vector2i(1, 0), BSP_DungeonGenerator.TileType.RESOURCE)
			"pillars":
				_mark_corner_pillars(grid, rect)
			"mixed":
				_mark_walkable_cell(grid, _rect_center(rect) + Vector2i(0, 1), BSP_DungeonGenerator.TileType.LOOT)
				_mark_corner_pillars(grid, rect)
			"stash":
				_mark_walkable_cell(grid, _rect_center(rect) + Vector2i(-1, -1), BSP_DungeonGenerator.TileType.LOOT)
				_mark_walkable_cell(grid, _rect_center(rect) + Vector2i(1, 1), BSP_DungeonGenerator.TileType.RESOURCE)
			"ritual":
				_mark_corner_pillars(grid, rect)
				_mark_walkable_cell(grid, _rect_center(rect), BSP_DungeonGenerator.TileType.RESOURCE)


func _mark_corner_pillars(grid: Array, rect: Rect2i) -> void:
	if rect.size.x < 5 or rect.size.y < 5:
		return
	for offset in [Vector2i(1, 1), Vector2i(rect.size.x - 2, rect.size.y - 2)]:
		_mark_existing_floor_cell(grid, rect.position + offset, BSP_DungeonGenerator.TileType.PILLAR)


func _mark_walkable_cell(grid: Array, cell: Vector2i, cell_type: int) -> void:
	if not _is_inside_grid(cell):
		return
	if int(grid[cell.y][cell.x]) == BSP_DungeonGenerator.TileType.WALL:
		_set_cell(grid, cell, BSP_DungeonGenerator.TileType.FLOOR)
	_set_cell(grid, cell, cell_type)


func _mark_existing_floor_cell(grid: Array, cell: Vector2i, cell_type: int) -> void:
	if not _is_inside_grid(cell):
		return
	if int(grid[cell.y][cell.x]) == BSP_DungeonGenerator.TileType.FLOOR:
		_set_cell(grid, cell, cell_type)


func _ensure_terminal_room_rewards(grid: Array) -> void:
	for terminal in get_terminal_rooms():
		if _count_cells_in_rect(grid, terminal, BSP_DungeonGenerator.TileType.LOOT) >= 1:
			continue
		var resource_count := _count_cells_in_rect(grid, terminal, BSP_DungeonGenerator.TileType.RESOURCE)
		var candidates := _walkable_reward_candidates(grid, terminal)
		var index := 0
		while resource_count < 3 and index < candidates.size():
			var cell: Vector2i = candidates[index]
			index += 1
			if int(grid[cell.y][cell.x]) == BSP_DungeonGenerator.TileType.RESOURCE:
				continue
			_set_cell(grid, cell, BSP_DungeonGenerator.TileType.RESOURCE)
			resource_count += 1


func _walkable_reward_candidates(grid: Array, rect: Rect2i) -> Array[Vector2i]:
	var center := _rect_center(rect)
	var candidates: Array[Vector2i] = []
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			if not _is_inside_grid(cell):
				continue
			var cell_type := int(grid[y][x])
			if cell_type == BSP_DungeonGenerator.TileType.FLOOR or cell_type == BSP_DungeonGenerator.TileType.RESOURCE:
				candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(Vector2(center)) < Vector2(b).distance_squared_to(Vector2(center))
	)
	return candidates


func _count_cells_in_rect(grid: Array, rect: Rect2i, cell_type: int) -> int:
	var count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if y < 0 or y >= grid.size() or x < 0 or x >= grid[y].size():
				continue
			if int(grid[y][x]) == cell_type:
				count += 1
	return count


func _carve_rect(grid: Array, rect: Rect2i, cell_type: int) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			_set_cell(grid, Vector2i(x, y), cell_type)


func _carve_corridor(grid: Array, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var current := from_cell
	var previous := current
	var step_count := 0
	var guard := 0
	while current != to_cell and guard < 128:
		guard += 1
		_carve_corridor_brush(grid, current, previous, step_count)
		previous = current
		var delta := to_cell - current
		var move_x := delta.x != 0
		var move_y := delta.y != 0
		if move_x and move_y:
			var x_weight := 0.62 if absi(delta.x) >= absi(delta.y) else 0.38
			if _randf() < x_weight:
				current.x += signi(delta.x)
			else:
				current.y += signi(delta.y)
		elif move_x:
			current.x += signi(delta.x)
		elif move_y:
			current.y += signi(delta.y)
		step_count += 1
	_carve_corridor_brush(grid, to_cell, previous, step_count)


func _carve_corridor_brush(grid: Array, cell: Vector2i, previous: Vector2i, step_count: int) -> void:
	_set_cell(grid, cell, BSP_DungeonGenerator.TileType.FLOOR)
	var travel := cell - previous
	if travel == Vector2i.ZERO:
		return
	var perpendicular := Vector2i(-signi(travel.y), signi(travel.x))
	if step_count % 3 == 0:
		_set_cell(grid, cell + perpendicular, BSP_DungeonGenerator.TileType.FLOOR)
	if step_count % 5 == 2:
		_set_cell(grid, cell - perpendicular, BSP_DungeonGenerator.TileType.FLOOR)


func _carve_shortcut_connection(grid: Array, from_macro: Vector2i, to_macro: Vector2i) -> void:
	var from_cell := _room_connection_cell(from_macro)
	var to_cell := _room_connection_cell(to_macro)
	_carve_corridor(grid, from_cell, to_cell)

	var delta: Vector2i = to_macro - from_macro
	var distance: int = abs(delta.x) + abs(delta.y)
	if distance <= 1:
		return
	var dir := Vector2i(signi(delta.x), signi(delta.y))
	for step in range(1, distance):
		var connector_center := _relaxed_connector_center(from_macro + dir * step, dir)
		var connector_rect := Rect2i(
			connector_center - Vector2i(SHORTCUT_CONNECTOR_SIZE / 2, SHORTCUT_CONNECTOR_SIZE / 2),
			Vector2i(SHORTCUT_CONNECTOR_SIZE, SHORTCUT_CONNECTOR_SIZE)
		)
		_shortcut_connector_rects.append(connector_rect)
		_carve_rect(grid, connector_rect, BSP_DungeonGenerator.TileType.FLOOR)
		_apply_room_height(connector_rect, 3.2)


func _carve_merged_room_connection(grid: Array, from_macro: Vector2i, to_macro: Vector2i) -> void:
	if not _room_defs.has(from_macro) or not _room_defs.has(to_macro):
		return
	var from_rect: Rect2i = _room_defs[from_macro]["rect"]
	var to_rect: Rect2i = _room_defs[to_macro]["rect"]
	var from_center := _rect_center(from_rect)
	var to_center := _rect_center(to_rect)
	var delta: Vector2i = to_macro - from_macro
	var half_width := MERGED_ROOM_CONNECTION_WIDTH / 2
	var bridge: Rect2i
	if abs(delta.x) >= abs(delta.y):
		var left_rect := from_rect if from_center.x <= to_center.x else to_rect
		var right_rect := to_rect if from_center.x <= to_center.x else from_rect
		var x0 := left_rect.position.x + left_rect.size.x - 1
		var x1 := right_rect.position.x
		var y := roundi(float(from_center.y + to_center.y) * 0.5)
		bridge = Rect2i(
			Vector2i(mini(x0, x1) - 1, y - half_width),
			Vector2i(absi(x1 - x0) + 3, MERGED_ROOM_CONNECTION_WIDTH)
		)
	else:
		var top_rect := from_rect if from_center.y <= to_center.y else to_rect
		var bottom_rect := to_rect if from_center.y <= to_center.y else from_rect
		var y0 := top_rect.position.y + top_rect.size.y - 1
		var y1 := bottom_rect.position.y
		var x := roundi(float(from_center.x + to_center.x) * 0.5)
		bridge = Rect2i(
			Vector2i(x - half_width, mini(y0, y1) - 1),
			Vector2i(MERGED_ROOM_CONNECTION_WIDTH, absi(y1 - y0) + 3)
		)
	_carve_rect(grid, bridge, BSP_DungeonGenerator.TileType.FLOOR)
	_carve_compound_partition_walls(grid, from_rect, to_rect, delta)
	_carve_corridor(grid, from_center, _rect_center(bridge))
	_carve_corridor(grid, to_center, _rect_center(bridge))
	_apply_room_height(bridge, minf(float(_room_defs[from_macro]["height"]), float(_room_defs[to_macro]["height"])))


func _carve_compound_partition_walls(grid: Array, from_rect: Rect2i, to_rect: Rect2i, delta: Vector2i) -> void:
	for rect in [from_rect, to_rect]:
		if rect.size.x < 5 or rect.size.y < 5:
			continue
		if abs(delta.x) >= abs(delta.y):
			var x := clampi(_rect_center(rect).x, rect.position.x + 2, rect.position.x + rect.size.x - 3)
			var upper_height: int = mini(3, maxi(2, rect.size.y / 3))
			var lower_height: int = mini(3, maxi(2, rect.size.y / 3))
			_add_partition_wall(grid, Rect2i(Vector2i(x, rect.position.y + 1), Vector2i(1, upper_height)))
			_add_partition_wall(grid, Rect2i(Vector2i(x, rect.position.y + rect.size.y - 1 - lower_height), Vector2i(1, lower_height)))
		else:
			var y := clampi(_rect_center(rect).y, rect.position.y + 2, rect.position.y + rect.size.y - 3)
			var left_width: int = mini(3, maxi(2, rect.size.x / 3))
			var right_width: int = mini(3, maxi(2, rect.size.x / 3))
			_add_partition_wall(grid, Rect2i(Vector2i(rect.position.x + 1, y), Vector2i(left_width, 1)))
			_add_partition_wall(grid, Rect2i(Vector2i(rect.position.x + rect.size.x - 1 - right_width, y), Vector2i(right_width, 1)))


func _add_partition_wall(grid: Array, rect: Rect2i) -> void:
	var wall_count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			if not _is_inside_grid(cell):
				continue
			if int(grid[y][x]) != BSP_DungeonGenerator.TileType.FLOOR:
				continue
			_set_cell(grid, cell, BSP_DungeonGenerator.TileType.WALL)
			wall_count += 1
	if wall_count > 0:
		_merged_partition_rects.append(rect)


func _room_connection_cell(macro: Vector2i) -> Vector2i:
	if _room_defs.has(macro):
		return _rect_center(_room_defs[macro]["rect"])
	return _macro_to_grid_center(macro)


func _is_boss_macro(macro: Vector2i) -> bool:
	return room_roles.has("boss") and _room_defs.has(macro) and (_room_defs[macro]["rect"] as Rect2i) == (room_roles["boss"] as Rect2i)


func _relaxed_connector_center(macro: Vector2i, corridor_dir: Vector2i) -> Vector2i:
	var base := _macro_to_grid_center(macro)
	var perpendicular := Vector2i(-corridor_dir.y, corridor_dir.x)
	var offset := _randi_range(-ROOM_CENTER_JITTER, ROOM_CENTER_JITTER)
	var center := base + perpendicular * offset
	var half := SHORTCUT_CONNECTOR_SIZE / 2
	center.x = clampi(center.x, 1 + half, _width - half - 2)
	center.y = clampi(center.y, 1 + half, _height - half - 2)
	return center


func _set_cell(grid: Array, cell: Vector2i, cell_type: int) -> void:
	if cell.y <= 0 or cell.y >= grid.size() - 1:
		return
	if cell.x <= 0 or cell.x >= grid[cell.y].size() - 1:
		return
	grid[cell.y][cell.x] = cell_type


func _is_inside_grid(cell: Vector2i) -> bool:
	return cell.y > 0 and cell.y < _height - 1 and cell.x > 0 and cell.x < _width - 1


func _lock_outer_walls(grid: Array) -> void:
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if x == 0 or y == 0 or x == grid[y].size() - 1 or y == grid.size() - 1:
				grid[y][x] = BSP_DungeonGenerator.TileType.WALL


func _add_macro_room(cell: Vector2i) -> void:
	_macro_rooms.append(cell)
	_macro_room_set[cell] = true


func _neighbor_count(cell: Vector2i) -> int:
	var count := 0
	for dir in _dirs():
		if _macro_room_set.has(cell + dir):
			count += 1
	return count


func _connection_key(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var tmp := a
		a = b
		b = tmp
	return "%d,%d:%d,%d" % [a.x, a.y, b.x, b.y]


func _would_increase_terminal_count(candidate: Vector2i) -> bool:
	for dir in _dirs():
		var neighbor: Vector2i = candidate + dir
		if not _macro_room_set.has(neighbor):
			continue
		return neighbor == Vector2i.ZERO or _neighbor_count(neighbor) > 1
	return false


func _take_terminal_role(terminals: Array[Vector2i], fallback: Vector2i) -> Vector2i:
	if terminals.is_empty():
		return fallback
	return terminals.pop_front()


func _graph_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	if from_cell == to_cell:
		return 0
	var queue: Array[Vector2i] = [from_cell]
	var distance: Dictionary = {from_cell: 0}
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for dir in _dirs():
			var next: Vector2i = current + dir
			if not _macro_room_set.has(next) or distance.has(next):
				continue
			distance[next] = int(distance[current]) + 1
			if next == to_cell:
				return int(distance[next])
			queue.append(next)
	return 0


func _macro_to_room_rect(macro: Vector2i) -> Rect2i:
	return _room_rect_for_macro(macro)


func _room_rect_for_macro(macro: Vector2i) -> Rect2i:
	if _room_defs.has(macro):
		return _room_defs[macro]["rect"]
	var center := _macro_to_grid_center(macro)
	var fallback_size := Vector2i(ROOM_SIZE, ROOM_SIZE)
	return _clamped_room_rect(center, fallback_size)


func _macro_to_grid_center(macro: Vector2i) -> Vector2i:
	return Vector2i(_width / 2, _height / 2) + macro * ROOM_SPACING


func _rect_center(rect: Rect2i) -> Vector2i:
	return rect.position + Vector2i(rect.size.x / 2, rect.size.y / 2)


func _apply_room_height(rect: Rect2i, height: float) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if y >= 0 and y < ceiling_heights.size() and x >= 0 and x < ceiling_heights[y].size():
				ceiling_heights[y][x] = height


func _height_for_room(macro: Vector2i, shape: String = "") -> float:
	var dist: int = abs(macro.x) + abs(macro.y)
	var shape_bonus := 0.0
	if shape == "pillar_hall" or shape == "cross" or shape == "great_hall":
		shape_bonus = 0.6
	elif shape == "circle" or shape == "ellipse" or shape == "noise_cavern":
		shape_bonus = 0.4
	elif shape == "wide" or shape == "tall" or shape == "ring" or shape == "split_chamber":
		shape_bonus = 0.25
	if dist >= 4:
		return 4.6 + shape_bonus
	if dist >= 2:
		return 3.8 + shape_bonus
	return 3.0 + shape_bonus


func _make_filled_grid(width: int, height: int, cell_type: int) -> Array:
	var result: Array = []
	for y in range(height):
		var row: Array = []
		for x in range(width):
			row.append(cell_type)
		result.append(row)
	return result


func _make_height_grid(width: int, height: int, value: float) -> Array:
	var result: Array = []
	for y in range(height):
		var row: Array = []
		for x in range(width):
			row.append(value)
		result.append(row)
	return result


func _dirs() -> Array[Vector2i]:
	return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
