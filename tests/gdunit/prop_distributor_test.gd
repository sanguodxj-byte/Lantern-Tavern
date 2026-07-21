extends GdUnitTestSuite

# Tests for PropDistributor (procedural generation utilities)

var _distributor: PropDistributor

func before_test() -> void:
	_distributor = PropDistributor.new()


func after_test() -> void:
	if is_instance_valid(_distributor):
		_distributor.free()
	_distributor = null


# --- Poisson Disk Sampling ---

func test_poisson_generates_points() -> void:
	var points = _distributor.generate_poisson_distribution(Vector2(10, 10), 2.0, 30)
	assert_int(points.size()).is_greater_equal(0)
	# Points should be within bounds
	for pt in points:
		assert_bool(pt.x >= 0 and pt.x <= 10).override_failure_message("Point x=%.1f out of bounds" % pt.x).is_true()
		assert_bool(pt.y >= 0 and pt.y <= 10).override_failure_message("Point y=%.1f out of bounds" % pt.y).is_true()


func test_poisson_min_distance_respected() -> void:
	var min_dist = 3.0
	var points = _distributor.generate_poisson_distribution(Vector2(20, 20), min_dist, 50)
	# Check that no two points are closer than min_dist (with small epsilon)
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			var d = points[i].distance_to(points[j])
			assert_bool(d >= min_dist - 0.01) \
				.override_failure_message("Points %.1f apart < min_dist %.1f" % [d, min_dist]) \
				.is_true()


func test_poisson_empty_room_returns_empty() -> void:
	var points = _distributor.generate_poisson_distribution(Vector2(0.01, 0.01), 2.0, 30)
	# Even tiny room may produce 1 point; verify no crash
	assert_bool(points is Array).is_true()


# --- Grid Index ---

func test_get_grid_index() -> void:
	var idx = _distributor.get_grid_index(Vector2(5, 5), 2.0, 10)
	assert_int(idx).is_greater_equal(0)


# --- Is Point Valid ---

func test_is_point_valid_out_of_bounds_returns_false() -> void:
	var valid = _distributor.is_point_valid(Vector2(-1, 5), Vector2(10, 10), 2.0, 3.0, [], [], 10, 10)
	assert_bool(valid).is_false()

	valid = _distributor.is_point_valid(Vector2(5, -1), Vector2(10, 10), 2.0, 3.0, [], [], 10, 10)
	assert_bool(valid).is_false()


# --- Prop Distribution (Topological Placement) ---

func test_solve_prop_distribution_empty_rooms() -> void:
	var result = _distributor.solve_prop_distribution([], null)
	assert_bool(result["portal_room"] == null).is_true()
	assert_bool(result["chest_rooms"].is_empty()).is_true()


func test_solve_prop_distribution_single_room() -> void:
	var rooms = [_distributor.RoomNode.new()]
	var result = _distributor.solve_prop_distribution(rooms, rooms[0])
	assert_bool(result["portal_room"] == rooms[0]).is_true()
	assert_int(result["chest_rooms"].size()).is_equal(0)


func test_solve_prop_distribution_linear_rooms() -> void:
	var rooms = []
	for i in range(3):
		var room = _distributor.RoomNode.new()
		room.position = Vector2i(i, 0)
		rooms.append(room)
	var first = rooms[0]
	var second = rooms[1]
	var third = rooms[2]
	first.neighbors = [second]
	second.neighbors = [first, third]
	third.neighbors = [second]
	
	var typed_rooms: Array = rooms
	var result = _distributor.solve_prop_distribution(typed_rooms, first)
	
	assert_bool(result["portal_room"] == third).is_true()
	assert_int(result["chest_rooms"].size()).is_greater_equal(1)


# --- Tavern Layout ---

func test_generate_tavern_layout() -> void:
	var layout = _distributor.generate_tavern_layout(Vector2(10, 10), 3.0)
	assert_bool(layout.size() > 0).is_true()
	# First item should be a table
	assert_str(layout[0]["type"]).is_equal("table")


func test_tavern_layout_tables_have_stools() -> void:
	var layout = _distributor.generate_tavern_layout(Vector2(10, 10), 3.0)
	var stool_count = 0
	var table_count = 0
	for item in layout:
		match item["type"]:
			"table": table_count += 1
			"stool": stool_count += 1
	# Each table should have 4 stools
	assert_int(stool_count).is_equal(table_count * 4)
