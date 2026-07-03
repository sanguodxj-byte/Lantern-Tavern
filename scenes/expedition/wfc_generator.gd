extends Node
class_name WFC_RoomGenerator

# Tile types define state collapsed
enum TileType { EMPTY, FLOOR, WALL, LOOT, RESOURCE, PILLAR }

# Grid size for a template room
const GRID_WIDTH = 10
const GRID_HEIGHT = 10

# Adjacency Rules Dictionary
# Key: TileType, Value: Array of allowed neighbor TileTypes in [North, South, East, West] directions
# For simplicity, we define a list of compatible neighbors for each tile type
var compatibility_rules: Dictionary = {
	TileType.EMPTY: [TileType.EMPTY, TileType.WALL],
	TileType.FLOOR: [TileType.FLOOR, TileType.WALL, TileType.LOOT, TileType.RESOURCE, TileType.PILLAR],
	TileType.WALL: [TileType.WALL, TileType.EMPTY, TileType.FLOOR],
	TileType.LOOT: [TileType.FLOOR],
	TileType.RESOURCE: [TileType.FLOOR],
	TileType.PILLAR: [TileType.FLOOR]
}

# Representing the superposition state of each cell in the room grid
# Each cell holds an array of possible TileTypes
var grid_superposition: Array = []

func _ready():
	randomize()

# Initialize superposition state for the 10x10 template grid
func initialize_grid():
	grid_superposition.clear()
	for y in range(GRID_HEIGHT):
		var row = []
		for x in range(GRID_WIDTH):
			# On border, force it to be WALL or EMPTY to align structure
			if x == 0 or x == GRID_WIDTH - 1 or y == 0 or y == GRID_HEIGHT - 1:
				row.append([TileType.WALL, TileType.EMPTY])
			else:
				# Inside, superposition of all possible tiles
				row.append([TileType.FLOOR, TileType.LOOT, TileType.RESOURCE, TileType.PILLAR, TileType.WALL])
		grid_superposition.append(row)

# Core WFC Collapse Loop
func collapse_room() -> Array:
	initialize_grid()
	
	# Keep collapsing until all cells are resolved
	while true:
		var min_entropy_pos = find_lowest_entropy_cell()
		if min_entropy_pos == Vector2i(-1, -1):
			# No superposition left, collapse complete!
			break
			
		var cx = min_entropy_pos.x
		var cy = min_entropy_pos.y
		
		# Collapse this cell by choosing one of its remaining possibilities randomly
		var possible_states = grid_superposition[cy][cx]
		if possible_states.is_empty():
			# Contradiction occurred! Reset and try again
			print("WFC Contradiction encountered, retrying...")
			initialize_grid()
			continue
			
		var chosen_state = possible_states[randi() % possible_states.size()]
		grid_superposition[cy][cx] = [chosen_state]
		
		# Propagate constraints across the grid
		propagate_constraints(cx, cy)
		
	# Convert grid of arrays to single output array
	var final_grid = []
	for y in range(GRID_HEIGHT):
		var row = []
		for x in range(GRID_WIDTH):
			row.append(grid_superposition[y][x][0])
		final_grid.append(row)
		
	return final_grid

func find_lowest_entropy_cell() -> Vector2i:
	var min_entropy = 999
	var best_pos = Vector2i(-1, -1)
	
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var possible_count = grid_superposition[y][x].size()
			if possible_count > 1 and possible_count < min_entropy:
				min_entropy = possible_count
				best_pos = Vector2i(x, y)
				
	return best_pos

# Basic Constraint Propagation (Simplified check)
func propagate_constraints(start_x: int, start_y: int):
	var queue = [Vector2i(start_x, start_y)]
	var directions = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]
	
	while queue.size() > 0:
		var curr = queue.pop_front()
		
		for dir in directions:
			var nx = curr.x + dir.x
			var ny = curr.y + dir.y
			
			if nx >= 0 and nx < GRID_WIDTH and ny >= 0 and ny < GRID_HEIGHT:
				var neighbor_possibilities = grid_superposition[ny][nx]
				if neighbor_possibilities.size() <= 1:
					continue # Already fully collapsed, skip
					
				# Filter neighbor possibilities based on compatibility rules
				var valid_next_states = []
				for curr_possible_state in grid_superposition[curr.y][curr.x]:
					var allowed_neighbors = compatibility_rules[curr_possible_state]
					for r in allowed_neighbors:
						if not r in valid_next_states:
							valid_next_states.append(r)
							
				var new_possibilities = []
				for state in neighbor_possibilities:
					if state in valid_next_states:
						new_possibilities.append(state)
						
				# If we reduced possibilities, propagate further
				if new_possibilities.size() < neighbor_possibilities.size():
					grid_superposition[ny][nx] = new_possibilities
					queue.append(Vector2i(nx, ny))
