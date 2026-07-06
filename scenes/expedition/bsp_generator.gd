extends Node
class_name BSP_DungeonGenerator

enum TileType { EMPTY, FLOOR, WALL, LOOT, RESOURCE, PILLAR }

var width: int
var height: int
var grid: Array = []
var ceiling_heights: Array = []
var rooms: Array[Rect2i] = []

class Leaf:
	var x: int
	var y: int
	var w: int
	var h: int
	var child_1: Leaf = null
	var child_2: Leaf = null
	var room: Rect2i = Rect2i()
	var corridors: Array[Rect2i] = []

	func _init(px: int, py: int, pw: int, ph: int):
		x = px
		y = py
		w = pw
		h = ph

	func split(min_size: int) -> bool:
		if child_1 != null or child_2 != null:
			return false # Already split

		# Decide vertical or horizontal split
		var split_horizontally = randf() > 0.5
		if w > h * 1.25:
			split_horizontally = false
		elif h > w * 1.25:
			split_horizontally = true

		var max_size = w if not split_horizontally else h
		if max_size < min_size * 2:
			return false # Too small to split

		var split_point = randi_range(min_size, max_size - min_size)

		if split_horizontally:
			child_1 = Leaf.new(x, y, w, split_point)
			child_2 = Leaf.new(x, y + split_point, w, h - split_point)
		else:
			child_1 = Leaf.new(x, y, split_point, h)
			child_2 = Leaf.new(x + split_point, y, w - split_point, h)

		return true

	## Carve rooms using WFC_RoomGenerator for interior layout.
	## The WFC output grid maps 1-to-1 onto generator.grid in the [room_x, room_y] region.
	func create_rooms(min_room_size: int, generator: BSP_DungeonGenerator) -> void:
		if child_1 != null or child_2 != null:
			if child_1 != null:
				child_1.create_rooms(min_room_size, generator)
			if child_2 != null:
				child_2.create_rooms(min_room_size, generator)

			if child_1 != null and child_2 != null:
				generator.create_corridor(child_1.get_room(), child_2.get_room())
		else:
			# ── Compute safe room bounds within this leaf ─────────────────────
			var max_rw := w - 2
			var max_rh := h - 2
			if max_rw < min_room_size or max_rh < min_room_size:
				return  # Leaf too small to carve a valid room

			var room_w := randi_range(min_room_size, max_rw)
			var room_h := randi_range(min_room_size, max_rh)
			var room_x := randi_range(x + 1, x + w - room_w - 1)
			var room_y := randi_range(y + 1, y + h - room_h - 1)
			room = Rect2i(room_x, room_y, room_w, room_h)
			generator.rooms.append(room)

			# ── Determine ceiling height from room area ────────────────────────
			var room_ceiling_height := 3.0
			var area := room_w * room_h
			if area <= 16:
				room_ceiling_height = 3.0
			elif area <= 36:
				room_ceiling_height = 3.8
			else:
				room_ceiling_height = 4.6

			# ── Use WFC_RoomGenerator to fill the interior layout ─────────────
			var wfc := WFC_RoomGenerator.new()
			# Select and apply a template appropriate for this room's size
			var template := wfc.get_template_for_size(room_w, room_h)
			var wfc_grid := wfc.collapse_room(room_w, room_h, template)
			wfc.free()

			# ── Blit WFC output into the global dungeon grid ──────────────────
			for ry in range(room_h):
				for rx in range(room_w):
					var gx := room_x + rx
					var gy := room_y + ry
					var wfc_tile: int = wfc_grid[ry][rx]

					# Inner WFC WALL stays as is (room sub-structure / pillars etc.)
					# Outer WFC WALL on the room boundary keeps WALL in global grid
					generator.grid[gy][gx] = wfc_tile
					# Ceiling height: special tiles get the same room height
					if wfc_tile != TileType.WALL and wfc_tile != TileType.EMPTY:
						generator.ceiling_heights[gy][gx] = room_ceiling_height
					else:
						# Sub-structure walls inherit a slightly lower ceiling
						generator.ceiling_heights[gy][gx] = room_ceiling_height

	func get_room() -> Rect2i:
		if child_1 == null and child_2 == null:
			return room

		var l_room := Rect2i()
		var r_room := Rect2i()
		if child_1 != null:
			l_room = child_1.get_room()
		if child_2 != null:
			r_room = child_2.get_room()

		if l_room != Rect2i() and r_room != Rect2i():
			return l_room if randf() > 0.5 else r_room
		elif l_room != Rect2i():
			return l_room
		else:
			return r_room

func generate_dungeon(p_width: int, p_height: int, min_leaf_size: int = 8, min_room_size: int = 4) -> Array:
	width = p_width
	height = p_height

	# Fill entire grid with WALL initially, and set default ceiling height
	grid = []
	ceiling_heights = []
	rooms.clear()
	for y in range(height):
		var row_grid := []
		var row_height := []
		for x in range(width):
			row_grid.append(TileType.WALL)
			row_height.append(3.0)
		grid.append(row_grid)
		ceiling_heights.append(row_height)

	var root_leaf := Leaf.new(0, 0, width, height)
	var leaves: Array[Leaf] = [root_leaf]

	var did_split := true
	while did_split:
		did_split = false
		var new_leaves: Array[Leaf] = []
		for l in leaves:
			if l.child_1 == null and l.child_2 == null:
				if l.w > min_leaf_size * 2 or l.h > min_leaf_size * 2:
					if l.split(min_leaf_size):
						new_leaves.append(l.child_1)
						new_leaves.append(l.child_2)
						did_split = true
		for nl in new_leaves:
			leaves.append(nl)

	# Carve rooms (now WFC-powered) and corridors
	root_leaf.create_rooms(min_room_size, self)

	# Ensure absolute outermost boundary is always WALL (prevent escape)
	for y in range(height):
		for x in range(width):
			if x == 0 or x == width - 1 or y == 0 or y == height - 1:
				grid[y][x] = TileType.WALL

	return grid

func create_corridor(room_a: Rect2i, room_b: Rect2i) -> void:
	var p1 := Vector2i(room_a.position.x + room_a.size.x / 2, room_a.position.y + room_a.size.y / 2)
	var p2 := Vector2i(room_b.position.x + room_b.size.x / 2, room_b.position.y + room_b.size.y / 2)

	var start_x := p1.x
	var start_y := p1.y
	var end_x := p2.x
	var end_y := p2.y

	if randf() > 0.5:
		# Horizontal then vertical
		for x in range(min(start_x, end_x), max(start_x, end_x) + 1):
			_dig(x, start_y)
		for y in range(min(start_y, end_y), max(start_y, end_y) + 1):
			_dig(end_x, y)
	else:
		# Vertical then horizontal
		for y in range(min(start_y, end_y), max(start_y, end_y) + 1):
			_dig(start_x, y)
		for x in range(min(start_x, end_x), max(start_x, end_x) + 1):
			_dig(x, end_y)

func _dig(x: int, y: int) -> void:
	if x > 0 and x < width - 1 and y > 0 and y < height - 1:
		# Only dig if we do not overwrite established loot, resource or pillars
		if grid[y][x] == TileType.WALL:
			grid[y][x] = TileType.FLOOR
			ceiling_heights[y][x] = 2.4
