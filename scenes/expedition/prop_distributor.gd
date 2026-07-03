extends Node
class_name PropDistributor

# Helper structure for a Room Node
class RoomNode:
	var position: Vector2i
	var distance_from_start: int = -1
	var is_dead_end: bool = false
	var neighbors: Array = []

# --- 1. Poisson Disc Sampling for Resource/Gatherable scatter ---
# Generates points that are at least 'min_dist' apart, avoiding clustering
func generate_poisson_distribution(room_size: Vector2, min_dist: float, sample_count: int = 30) -> Array[Vector2]:
	var points = []
	var grid = []
	var cell_size = min_dist / sqrt(2)
	
	var cols = int(ceil(room_size.x / cell_size))
	var rows = int(ceil(room_size.y / cell_size))
	
	# Initialize active grid with null
	for i in range(cols * rows):
		grid.append(-1)
		
	var active_list = []
	
	# Spawn first point randomly
	var first_pt = Vector2(randf() * room_size.x, randf() * room_size.y)
	active_list.append(first_pt)
	points.append(first_pt)
	grid[get_grid_index(first_pt, cell_size, cols)] = points.size() - 1
	
	while active_list.size() > 0:
		var rand_idx = randi() % active_list.size()
		var parent_pt = active_list[rand_idx]
		var found_new_pt = false
		
		for attempt in range(sample_count):
			# Generate a point in an annulus [min_dist, 2 * min_dist] around parent
			var angle = randf() * 2.0 * PI
			var r = min_dist + randf() * min_dist
			var candidate = parent_pt + Vector2(cos(angle), sin(angle)) * r
			
			if is_point_valid(candidate, room_size, cell_size, min_dist, points, grid, cols, rows):
				points.append(candidate)
				active_list.append(candidate)
				grid[get_grid_index(candidate, cell_size, cols)] = points.size() - 1
				found_new_pt = true
				break
				
		if not found_new_pt:
			active_list.remove_at(rand_idx)
			
	return points

func get_grid_index(pt: Vector2, cell_size: float, cols: int) -> int:
	var col = int(pt.x / cell_size)
	var row = int(pt.y / cell_size)
	return row * cols + col

func is_point_valid(pt: Vector2, bounds: Vector2, cell_size: float, min_dist: float, points: Array, grid: Array, cols: int, rows: int) -> bool:
	if pt.x < 0 or pt.x >= bounds.x or pt.y < 0 or pt.y >= bounds.y:
		return false
		
	var col = int(pt.x / cell_size)
	var row = int(pt.y / cell_size)
	
	# Check neighboring cells in the grid
	var search_start_col = max(0, col - 2)
	var search_end_col = min(cols - 1, col + 2)
	var search_start_row = max(0, row - 2)
	var search_end_row = min(rows - 1, row + 2)
	
	for r in range(search_start_row, search_end_row + 1):
		for c in range(search_start_col, search_end_col + 1):
			var g_idx = r * cols + c
			var pt_idx = grid[g_idx]
			if pt_idx != -1:
				var other_pt = points[pt_idx]
				if pt.distance_to(other_pt) < min_dist:
					return false
					
	return true

# --- 2. Topological placement of Chests and Extraction Portals ---
# Scans Room Nodes graph, maps BFS distance from player spawn, and places props:
# - Portal placed in the topologically FURTHEST room.
# - Chests placed in DEAD ENDS (leaves of the layout tree).
func solve_prop_distribution(rooms: Array[RoomNode], start_room: RoomNode) -> Dictionary:
	var results = {
		"portal_room": null,
		"chest_rooms": []
	}
	
	if rooms.is_empty() or start_room == null:
		return results
		
	# BFS to map topological distance
	var queue = [start_room]
	start_room.distance_from_start = 0
	
	var max_dist = 0
	var furthest_room = start_room
	
	while queue.size() > 0:
		var curr = queue.pop_front()
		
		# Identify dead-ends (excluding start room)
		if curr.neighbors.size() == 1 and curr != start_room:
			curr.is_dead_end = true
			results["chest_rooms"].append(curr)
			
		for n in curr.neighbors:
			if n.distance_from_start == -1:
				n.distance_from_start = curr.distance_from_start + 1
				if n.distance_from_start > max_dist:
					max_dist = n.distance_from_start
					furthest_room = n
				queue.append(n)
				
	results["portal_room"] = furthest_room
	return results

# --- 3. Tavern Furniture Layout (Tables and Stools spacing) ---
# Places tables in a grid, and surrounding stools leaving 2.0m corridors for Navigation Agents
func generate_tavern_layout(floor_size: Vector2, table_spacing: float = 3.0) -> Array:
	var furniture_placements = [] # Array of dictionaries: {"type": String, "position": Vector3}
	
	var start_x = 2.0
	var start_y = 2.0
	var end_x = floor_size.x - 2.0
	var end_y = floor_size.y - 2.0
	
	var x = start_x
	while x <= end_x:
		var y = start_y
		while y <= end_y:
			# Table position
			var table_pos = Vector3(x, 0.0, y)
			furniture_placements.append({"type": "table", "position": table_pos})
			
			# Surround table with 4 stools (distanced 0.6 meters on orthographic axes)
			var stool_offsets = [
				Vector3(-0.6, 0.0, 0.0),
				Vector3(0.6, 0.0, 0.0),
				Vector3(0.0, 0.0, -0.6),
				Vector3(0.0, 0.0, 0.6)
			]
			for offset in stool_offsets:
				furniture_placements.append({"type": "stool", "position": table_pos + offset})
				
			y += table_spacing
		x += table_spacing
		
	return furniture_placements
