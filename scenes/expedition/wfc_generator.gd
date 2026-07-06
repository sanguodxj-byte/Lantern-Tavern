extends Node
class_name WFC_RoomGenerator

# Tile types define state collapsed
enum TileType { EMPTY, FLOOR, WALL, LOOT, RESOURCE, PILLAR }

# ANY sentinel: used inside RoomTemplate.layout to mean "any tile is valid here"
const ANY := -1

# ─────────────────────────────────────────────────────────────────────────────
# RoomTemplate: a pre-authored layout that pins certain cells before WFC runs.
# Cells set to ANY (-1) are left in full superposition and resolved by WFC.
# Cells set to a TileType value are hard-pinned to that single state.
# ─────────────────────────────────────────────────────────────────────────────
class RoomTemplate:
	var name: String
	var width: int
	var height: int
	# layout[y][x]: int — either TileType value or ANY (-1)
	var layout: Array = []
	var spawn_weight: int = 1

	func _init(p_name: String, p_width: int, p_height: int,
			p_layout: Array, p_weight: int = 1) -> void:
		name = p_name
		width = p_width
		height = p_height
		layout = p_layout
		spawn_weight = p_weight

# ─────────────────────────────────────────────────────────────────────────────
# Template helper utilities
# ─────────────────────────────────────────────────────────────────────────────

## Build a grid with border WALL and inner ANY cells.
static func _base_grid(w: int, h: int) -> Array:
	var result: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			if x == 0 or x == w - 1 or y == 0 or y == h - 1:
				row.append(TileType.WALL)
			else:
				row.append(ANY)
		result.append(row)
	return result

## Safe single-cell setter (bounds-checked, never touches the border).
static func _set_cell(g: Array, x: int, y: int, val: int) -> void:
	if y >= 0 and y < g.size() and x >= 0 and x < g[y].size():
		g[y][x] = val

# ─────────────────────────────────────────────────────────────────────────────
# 12 Preset Room Templates
# Each template is a distinct spatial archetype with at most a handful of
# hard-pinned tiles.  Border is always WALL; inner cells are ANY unless noted.
# ─────────────────────────────────────────────────────────────────────────────

## 1. Empty Chamber — 纯空旷，边界墙，内部全由 WFC 随机决定，无固定摆件
static func _make_empty_chamber(w: int, h: int) -> RoomTemplate:
	return RoomTemplate.new("EmptyChamber", w, h, _base_grid(w, h), 8)

## 2. Pillar Hall — 对称石柱大厅：1/3 和 2/3 位置固定石柱
static func _make_pillar_hall(w: int, h: int) -> RoomTemplate:
	var g: Array = _base_grid(w, h)
	var px1 := clampi(w / 3,     1, w - 2)
	var px2 := clampi(2 * w / 3, 1, w - 2)
	var py1 := clampi(h / 3,     1, h - 2)
	var py2 := clampi(2 * h / 3, 1, h - 2)
	_set_cell(g, px1, py1, TileType.PILLAR)
	_set_cell(g, px2, py1, TileType.PILLAR)
	_set_cell(g, px1, py2, TileType.PILLAR)
	_set_cell(g, px2, py2, TileType.PILLAR)
	return RoomTemplate.new("PillarHall", w, h, g, 6)

## 3. Treasure Corner — 四角宝物：左上/右上 LOOT，左下/右下 RESOURCE
static func _make_treasure_corner(w: int, h: int) -> RoomTemplate:
	var g: Array = _base_grid(w, h)
	_set_cell(g, 1,     1,     TileType.LOOT)
	_set_cell(g, w - 2, 1,     TileType.LOOT)
	_set_cell(g, 1,     h - 2, TileType.RESOURCE)
	_set_cell(g, w - 2, h - 2, TileType.RESOURCE)
	# 固定内层边框为 FLOOR 回廊，确保四角固定物互相连通（否则 WFC 可能生成断路）
	for x in range(2, w - 2):
		if g[1][x] == ANY:
			_set_cell(g, x, 1, TileType.FLOOR)
		if g[h - 2][x] == ANY:
			_set_cell(g, x, h - 2, TileType.FLOOR)
	for y in range(2, h - 2):
		if g[y][1] == ANY:
			_set_cell(g, 1, y, TileType.FLOOR)
		if g[y][w - 2] == ANY:
			_set_cell(g, w - 2, y, TileType.FLOOR)
	return RoomTemplate.new("TreasureCorner", w, h, g, 5)

## 4. Divided Arena — 中央竖墙将房间一分为二，mid_y 处留通道缺口，两侧各有宝物
static func _make_divided_arena(w: int, h: int) -> RoomTemplate:
	var g: Array = _base_grid(w, h)
	var mid_x := w / 2
	var gap_y  := h / 2
	for y in range(1, h - 1):
		if y != gap_y:
			_set_cell(g, mid_x, y, TileType.WALL)
	# 固定缺口格为 FLOOR，防止 WFC 将其填成 WALL 导致左右区域断路
	_set_cell(g, mid_x, gap_y, TileType.FLOOR)
	_set_cell(g, 1,     1,     TileType.LOOT)
	_set_cell(g, w - 2, h - 2, TileType.RESOURCE)
	return RoomTemplate.new("DividedArena", w, h, g, 4)

## 5. Altar Room — 祭坛室：中央固定宝箱，四对角放置石柱，神殿仪式感
static func _make_altar_room(w: int, h: int) -> RoomTemplate:
	var g: Array = _base_grid(w, h)
	var cx := w / 2
	var cy := h / 2
	_set_cell(g, cx, cy, TileType.LOOT)
	var off := 2
	_set_cell(g, clampi(cx - off, 1, w - 2), clampi(cy - off, 1, h - 2), TileType.PILLAR)
	_set_cell(g, clampi(cx + off, 1, w - 2), clampi(cy - off, 1, h - 2), TileType.PILLAR)
	_set_cell(g, clampi(cx - off, 1, w - 2), clampi(cy + off, 1, h - 2), TileType.PILLAR)
	_set_cell(g, clampi(cx + off, 1, w - 2), clampi(cy + off, 1, h - 2), TileType.PILLAR)
	return RoomTemplate.new("AltarRoom", w, h, g, 5)

## 6. Resource Depot — 资源仓库：三角分布固定资源点，左下有宝箱，采集感
static func _make_resource_depot(w: int, h: int) -> RoomTemplate:
	var g: Array = _base_grid(w, h)
	_set_cell(g, clampi(w / 4,     1, w - 2), clampi(h / 3,     1, h - 2), TileType.RESOURCE)
	_set_cell(g, clampi(3 * w / 4, 1, w - 2), clampi(h / 3,     1, h - 2), TileType.RESOURCE)
	_set_cell(g, clampi(w / 2,     1, w - 2), clampi(2 * h / 3, 1, h - 2), TileType.RESOURCE)
	_set_cell(g, 1, h - 2, TileType.LOOT)
	return RoomTemplate.new("ResourceDepot", w, h, g, 5)

## 7. Twin Treasure — 横墙隔成上下两区，mid_x 处留缺口，各侧正中有宝物
static func _make_twin_treasure(w: int, h: int) -> RoomTemplate:
	var g: Array = _base_grid(w, h)
	var mid_y := h / 2
	var gap_x  := w / 2
	for x in range(1, w - 1):
		if x != gap_x:
			_set_cell(g, x, mid_y, TileType.WALL)
	# 固定缺口格为 FLOOR，防止断路
	_set_cell(g, gap_x, mid_y, TileType.FLOOR)
	_set_cell(g, gap_x, 1,     TileType.LOOT)
	_set_cell(g, gap_x, h - 2, TileType.RESOURCE)
	return RoomTemplate.new("TwinTreasure", w, h, g, 4)

## 8. Fortress Vault — 守卫宝库：中央宝箱，直接邻居固定为 FLOOR，外围 2 格外有 WALL 屏障（三面）
## 最小 7×7；尺寸不足时降级为 EmptyChamber
static func _make_fortress_vault(w: int, h: int) -> RoomTemplate:
	if w < 7 or h < 7:
		return _make_empty_chamber(w, h)
	var g: Array = _base_grid(w, h)
	var cx := w / 2
	var cy := h / 2
	# 中央宝箱
	_set_cell(g, cx, cy, TileType.LOOT)
	# LOOT 的 4 个直接邻居固定为 FLOOR（避免 LOOT 直接相邻 WALL 导致约束矛盾）
	_set_cell(g, cx,     clampi(cy - 1, 1, h - 2), TileType.FLOOR)
	_set_cell(g, cx,     clampi(cy + 1, 1, h - 2), TileType.FLOOR)
	_set_cell(g, clampi(cx - 1, 1, w - 2), cy,     TileType.FLOOR)
	_set_cell(g, clampi(cx + 1, 1, w - 2), cy,     TileType.FLOOR)
	# 外围屏障：三面 WALL 在距宝箱 2 格外（北、西、东），南侧留通道
	_set_cell(g, cx,                           clampi(cy - 2, 1, h - 2), TileType.WALL)
	_set_cell(g, clampi(cx - 2, 1, w - 2), cy,                          TileType.WALL)
	_set_cell(g, clampi(cx + 2, 1, w - 2), cy,                          TileType.WALL)
	# 固定南侧纵向通道：从 LOOT 正下方到南内边界，保证宝箱始终可达
	for y in range(cy + 1, h - 1):
		_set_cell(g, cx, y, TileType.FLOOR)
	# 固定南内行横向通道（y=h-2），连接左右区域到南通道
	for x in range(1, w - 1):
		if g[h - 2][x] == ANY:
			_set_cell(g, x, h - 2, TileType.FLOOR)
	return RoomTemplate.new("FortressVault", w, h, g, 3)

## 9. Labyrinth Cell — S 形迷宫路径：左段遮挡上半，右段遮挡下半，末端宝箱
## 最小 6×6；尺寸不足时降级为 EmptyChamber
static func _make_labyrinth_cell(w: int, h: int) -> RoomTemplate:
	if w < 6 or h < 6:
		return _make_empty_chamber(w, h)
	var g: Array = _base_grid(w, h)
	var wx1   := clampi(w / 3,     1, w - 2)
	var wx2   := clampi(2 * w / 3, 1, w - 2)
	var mid_y := h / 2
	# 上半段竖墙（y=1 到 mid_y-1，在 mid_y 自然断开形成通道）
	for y in range(1, mid_y):
		_set_cell(g, wx1, y, TileType.WALL)
	# 下半段竖墙（y=mid_y+1 到 h-2，在 mid_y 自然断开）
	for y in range(mid_y + 1, h - 1):
		_set_cell(g, wx2, y, TileType.WALL)
	# 末端宝箱固定在右上角
	_set_cell(g, w - 2, 1, TileType.LOOT)
	# 固定整个 mid_y 行为 FLOOR，确保 S 路径的连接行始终凌驾
	for x in range(1, w - 1):
		if g[mid_y][x] == ANY:
			_set_cell(g, x, mid_y, TileType.FLOOR)
	# 固定 LOOT 到 mid_y 的纵向通道为 FLOOR（保证宝箱始终通达）
	for y in range(2, mid_y):
		if g[y][w - 2] == ANY:
			_set_cell(g, w - 2, y, TileType.FLOOR)
	return RoomTemplate.new("LabyrinthCell", w, h, g, 4)

## 10. Ring Hall — 十字圣殿：中央宝箱，四正方向等距石柱，古典神庙感
static func _make_ring_hall(w: int, h: int) -> RoomTemplate:
	var g: Array = _base_grid(w, h)
	var cx   := w / 2
	var cy   := h / 2
	var ring := 2
	_set_cell(g, cx, cy, TileType.LOOT)  # 中央宝箱
	_set_cell(g, cx,                         clampi(cy - ring, 1, h - 2), TileType.PILLAR)
	_set_cell(g, cx,                         clampi(cy + ring, 1, h - 2), TileType.PILLAR)
	_set_cell(g, clampi(cx - ring, 1, w - 2), cy,                         TileType.PILLAR)
	_set_cell(g, clampi(cx + ring, 1, w - 2), cy,                         TileType.PILLAR)
	return RoomTemplate.new("RingHall", w, h, g, 4)

## 11. Checkerboard — 棋盘密集石柱：内部偶数格全为石柱，奇数格全为走道，中央覆盖宝箱
## 最小 7×7；尺寸不足时降级为 EmptyChamber
static func _make_checkerboard(w: int, h: int) -> RoomTemplate:
	if w < 7 or h < 7:
		return _make_empty_chamber(w, h)
	var g: Array = _base_grid(w, h)
	# 每隔一格放一根石柱（从内部边距2开始，步长2）
	for y in range(2, h - 2, 2):
		for x in range(2, w - 2, 2):
			_set_cell(g, x, y, TileType.PILLAR)
	# 中央宝箱覆盖（可能会覆盖一个棋盘柱）
	_set_cell(g, w / 2, h / 2, TileType.LOOT)
	return RoomTemplate.new("CheckerHall", w, h, g, 4)

## 12. Crypt — 地下墓穴：沿中轴两侧对称排列短墙段（似棺椁），中央走道两端各有宝箱
## 最小 7×5；尺寸不足时降级为 EmptyChamber
static func _make_crypt(w: int, h: int) -> RoomTemplate:
	if w < 7 or h < 5:
		return _make_empty_chamber(w, h)
	var g: Array = _base_grid(w, h)
	var step: int = max(3, w / 4)
	# 沿 x 轴等间距放上下对称的 1×2 墙段（第1、2行 和 倒数第2、3行）
	var bx: int = step
	while bx < w - step:
		var bxc: int = clampi(bx, 1, w - 2)
		_set_cell(g, bxc, 1,     TileType.WALL)
		_set_cell(g, bxc, 2,     TileType.WALL)
		_set_cell(g, bxc, h - 3, TileType.WALL)
		_set_cell(g, bxc, h - 2, TileType.WALL)
		bx += step
	# 走道两端固定宝箱
	_set_cell(g, 1,     h / 2, TileType.LOOT)
	_set_cell(g, w - 2, h / 2, TileType.LOOT)
	# 固定整条中央走廊行（y=h/2）为 FLOOR（跳过边界和宝箱格），保证完全连通
	for x in range(2, w - 2):
		if g[h / 2][x] == ANY:
			_set_cell(g, x, h / 2, TileType.FLOOR)
	return RoomTemplate.new("Crypt", w, h, g, 4)

# ─────────────────────────────────────────────────────────────────────────────
# Template registry & weighted selection
# ─────────────────────────────────────────────────────────────────────────────
func get_template_for_size(w: int, h: int) -> RoomTemplate:
	var pool: Array = []

	# ── 始终可用（任意尺寸） ───────────────────────────────────────────────
	pool.append(_make_empty_chamber(w, h))
	pool.append(_make_treasure_corner(w, h))
	pool.append(_make_resource_depot(w, h))

	# ── 最小 5×5 ──────────────────────────────────────────────────────────
	if w >= 5 and h >= 5:
		pool.append(_make_pillar_hall(w, h))
		pool.append(_make_altar_room(w, h))
		pool.append(_make_ring_hall(w, h))

	# ── 最小 6×5 ──────────────────────────────────────────────────────────
	if w >= 6 and h >= 5:
		pool.append(_make_divided_arena(w, h))
		pool.append(_make_twin_treasure(w, h))

	# ── 最小 6×6 ──────────────────────────────────────────────────────────
	if w >= 6 and h >= 6:
		pool.append(_make_labyrinth_cell(w, h))
		pool.append(_make_crypt(w, h))

	# ── 最小 7×7 ──────────────────────────────────────────────────────────
	if w >= 7 and h >= 7:
		pool.append(_make_checkerboard(w, h))
		pool.append(_make_fortress_vault(w, h))

	# ── 加权随机选择 ───────────────────────────────────────────────────────
	var total_weight := 0
	for t in pool:
		total_weight += t.spawn_weight

	var r := randi() % total_weight
	var cumulative := 0
	for t in pool:
		cumulative += t.spawn_weight
		if r < cumulative:
			return t
	return pool[0]

# ─────────────────────────────────────────────────────────────────────────────
# WFC Core
# ─────────────────────────────────────────────────────────────────────────────

# Grid size for a template room, can be dynamically configured
var grid_width: int = 10
var grid_height: int = 10

# Adjacency Rules Dictionary
# Key: TileType, Value: Array of allowed neighbor TileTypes
var compatibility_rules: Dictionary = {
	TileType.EMPTY:    [TileType.EMPTY, TileType.WALL],
	TileType.FLOOR:    [TileType.FLOOR, TileType.WALL, TileType.LOOT, TileType.RESOURCE, TileType.PILLAR],
	TileType.WALL:     [TileType.WALL, TileType.EMPTY, TileType.FLOOR],
	TileType.LOOT:     [TileType.FLOOR],
	TileType.RESOURCE: [TileType.FLOOR],
	TileType.PILLAR:   [TileType.FLOOR]
}

# Representing the superposition state of each cell in the room grid
var grid_superposition: Array = []

# Max retries before falling back to a simple safe room
const MAX_RETRIES := 10

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## Collapse a room grid. Optionally pin cells from a RoomTemplate.
## Returns a 2D Array of TileType int values.
func collapse_room(width: int = 10, height: int = 10, template: RoomTemplate = null) -> Array:
	grid_width  = width
	grid_height = height

	if template == null:
		template = get_template_for_size(width, height)

	var retries := 0
	while retries < MAX_RETRIES:
		_initialize_grid_with_template(template)
		var ok := _run_collapse()
		if ok:
			var final_grid := _flatten_grid()
			if validate_grid(final_grid):
				return final_grid
		retries += 1
		print("[WFC] Retry %d / %d for template '%s' (%dx%d)..." \
			% [retries, MAX_RETRIES, template.name, width, height])

	var template_fallback := _make_template_fallback_grid(width, height, template)
	if validate_grid(template_fallback):
		print("[WFC] Max retries reached – using template fallback for '%s' (%dx%d)" % [template.name, width, height])
		return template_fallback

	print("[WFC] Max retries reached – falling back to EmptyChamber for %dx%d" % [width, height])
	return _make_fallback_grid(width, height)

func _make_template_fallback_grid(width: int, height: int, template: RoomTemplate) -> Array:
	if template == null or template.layout.is_empty():
		return []
	var result: Array = []
	for y in range(height):
		var row: Array = []
		for x in range(width):
			var cell := _get_template_cell(template, x, y)
			if cell == ANY:
				cell = TileType.FLOOR
			row.append(cell)
		result.append(row)
	return result

# ─────────────────────────────────────────────────────────────────────────────
# Initialization
# ─────────────────────────────────────────────────────────────────────────────
func _initialize_grid_with_template(template: RoomTemplate) -> void:
	grid_superposition.clear()
	var all_inner  := [TileType.FLOOR, TileType.LOOT, TileType.RESOURCE, TileType.PILLAR, TileType.WALL]
	var border_states := [TileType.WALL, TileType.EMPTY]

	for y in range(grid_height):
		var row: Array = []
		for x in range(grid_width):
			var pinned := _get_template_cell(template, x, y)
			if pinned != ANY:
				row.append([pinned])
			elif x == 0 or x == grid_width - 1 or y == 0 or y == grid_height - 1:
				row.append(border_states.duplicate())
			else:
				row.append(all_inner.duplicate())
		grid_superposition.append(row)

	# Initial propagation from all pinned cells to spread constraints early
	for y in range(grid_height):
		for x in range(grid_width):
			if grid_superposition[y][x].size() == 1:
				propagate_constraints(x, y)

func _get_template_cell(template: RoomTemplate, x: int, y: int) -> int:
	if template == null or template.layout.is_empty():
		return ANY
	if y >= template.layout.size():
		return ANY
	if x >= template.layout[y].size():
		return ANY
	return template.layout[y][x]

# ─────────────────────────────────────────────────────────────────────────────
# Core WFC loop
# ─────────────────────────────────────────────────────────────────────────────
func _run_collapse() -> bool:
	while true:
		var min_entropy_pos := find_lowest_entropy_cell()
		if min_entropy_pos == Vector2i(-1, -1):
			break

		var cx := min_entropy_pos.x
		var cy := min_entropy_pos.y
		var possible_states: Array = grid_superposition[cy][cx]

		if possible_states.is_empty():
			return false  # Contradiction

		var chosen_state: int = possible_states[randi() % possible_states.size()]
		grid_superposition[cy][cx] = [chosen_state]
		propagate_constraints(cx, cy)

	return true

func find_lowest_entropy_cell() -> Vector2i:
	var min_entropy := 999
	var best_pos := Vector2i(-1, -1)

	for y in range(grid_height):
		for x in range(grid_width):
			var possible_count: int = grid_superposition[y][x].size()
			if possible_count > 1 and possible_count < min_entropy:
				min_entropy = possible_count
				best_pos = Vector2i(x, y)

	return best_pos

# Basic Constraint Propagation (BFS-based)
func propagate_constraints(start_x: int, start_y: int) -> void:
	var queue := [Vector2i(start_x, start_y)]
	var directions := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]

	while queue.size() > 0:
		var curr: Vector2i = queue.pop_front()

		for dir in directions:
			var nx: int = curr.x + dir.x
			var ny: int = curr.y + dir.y

			if nx < 0 or nx >= grid_width or ny < 0 or ny >= grid_height:
				continue

			var neighbor_possibilities: Array = grid_superposition[ny][nx]
			if neighbor_possibilities.size() <= 1:
				continue

			var valid_next_states: Array = []
			for curr_possible_state in grid_superposition[curr.y][curr.x]:
				var allowed_neighbors: Array = compatibility_rules[curr_possible_state]
				for r in allowed_neighbors:
					if not r in valid_next_states:
						valid_next_states.append(r)

			var new_possibilities: Array = []
			for state in neighbor_possibilities:
				if state in valid_next_states:
					new_possibilities.append(state)

			if new_possibilities.size() < neighbor_possibilities.size():
				grid_superposition[ny][nx] = new_possibilities
				queue.append(Vector2i(nx, ny))

# ─────────────────────────────────────────────────────────────────────────────
# Post-processing validation
# ─────────────────────────────────────────────────────────────────────────────

## Run all post-collapse checks. Returns true when the grid is valid.
func validate_grid(grid: Array) -> bool:
	return check_connectivity(grid) and check_density(grid)

## BFS reachability: every walkable cell (FLOOR/LOOT/RESOURCE/PILLAR) must be
## reachable from the first walkable cell found.
func check_connectivity(grid: Array) -> bool:
	var walkable_types := [TileType.FLOOR, TileType.LOOT, TileType.RESOURCE, TileType.PILLAR]
	var rows := grid.size()
	if rows == 0:
		return false
	var cols: int = grid[0].size()

	var start := Vector2i(-1, -1)
	for y in range(rows):
		for x in range(cols):
			if grid[y][x] in walkable_types:
				start = Vector2i(x, y)
				break
		if start != Vector2i(-1, -1):
			break

	if start == Vector2i(-1, -1):
		return false

	var visited: Dictionary = {}
	var queue: Array = [start]
	visited[start] = true
	var count := 0

	while queue.size() > 0:
		var curr: Vector2i = queue.pop_front()
		count += 1
		for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var nb: Vector2i = Vector2i(curr.x + dir.x, curr.y + dir.y)
			if nb.x < 0 or nb.x >= cols or nb.y < 0 or nb.y >= rows:
				continue
			if visited.has(nb):
				continue
			if grid[nb.y][nb.x] in walkable_types:
				visited[nb] = true
				queue.append(nb)

	var total_walkable := 0
	for y in range(rows):
		for x in range(cols):
			if grid[y][x] in walkable_types:
				total_walkable += 1

	return count == total_walkable

## Density check: LOOT + RESOURCE tiles must not exceed 15% of all interior cells.
func check_density(grid: Array) -> bool:
	var rows := grid.size()
	if rows == 0:
		return true
	var cols: int = grid[0].size()
	var interior_count := 0
	var special_count  := 0

	for y in range(1, rows - 1):
		for x in range(1, cols - 1):
			interior_count += 1
			if grid[y][x] == TileType.LOOT or grid[y][x] == TileType.RESOURCE:
				special_count += 1

	if interior_count == 0:
		return true
	return float(special_count) / float(interior_count) <= 0.15

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
func _flatten_grid() -> Array:
	var final_grid: Array = []
	for y in range(grid_height):
		var row: Array = []
		for x in range(grid_width):
			var cell: Array = grid_superposition[y][x]
			row.append(cell[0] if not cell.is_empty() else TileType.FLOOR)
		final_grid.append(row)
	return final_grid

## Safe fallback: border WALL, interior FLOOR — always passes validation.
func _make_fallback_grid(w: int, h: int) -> Array:
	var result: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(TileType.WALL if (x == 0 or x == w - 1 or y == 0 or y == h - 1) else TileType.FLOOR)
		result.append(row)
	return result
