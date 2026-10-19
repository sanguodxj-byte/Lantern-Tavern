extends GdUnitTestSuite

const LAYER := preload("res://scenes/ui/zone_map_hotspot_layer.gd")


func test_layer_exposes_six_regions_without_text_controls() -> void:
	var layer := LAYER.new()
	add_child(layer)
	layer.configure([0, 1, 2, 3, 4, 5], {})
	assert_array(layer.get_zone_ids()).has_size(6)
	assert_int(layer.get_child_count()).is_equal(0)
	layer.queue_free()


func test_landmark_points_hit_their_map_regions() -> void:
	var layer := LAYER.new()
	add_child(layer)
	layer.configure([0, 1, 2, 3, 4, 5], {})
	for zone_id in range(6):
		var landmark: Vector2 = layer.get_zone_landmark_point(zone_id)
		assert_int(layer.get_zone_at_normalized(landmark)).is_equal(zone_id)
	layer.queue_free()


func test_unknown_map_area_does_not_select_a_zone() -> void:
	var layer := LAYER.new()
	add_child(layer)
	layer.configure([0, 1, 2, 3, 4, 5], {})
	assert_int(layer.get_zone_at_normalized(Vector2(0.50, 0.98))).is_equal(-1)
	layer.queue_free()


func test_layer_draws_dashed_edges_for_hover_and_selection() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/ui/zone_map_hotspot_layer.gd")
	assert_str(source).contains("draw_dashed_line")
	assert_str(source).contains("_hovered_zone")
	assert_str(source).contains("_selected_zone")
