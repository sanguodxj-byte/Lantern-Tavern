extends GdUnitTestSuite

# Tests for CustomerEntity chat lines and state transitions
# Tests for scene resource existence

func _customer_entity_script():
	return load("res://scenes/tavern/customer_entity.gd")


func _make_customer() -> Node:
	var customer: Node = _customer_entity_script().new()
	auto_free(customer)
	return customer


func test_perfect_lines_not_empty() -> void:
	var c = _make_customer()
	assert_bool(c.LINES_PERFECT.size() > 0).is_true()


func test_satisfied_lines_not_empty() -> void:
	var c = _make_customer()
	assert_bool(c.LINES_SATISFIED.size() > 0).is_true()


func test_normal_lines_not_empty() -> void:
	var c = _make_customer()
	assert_bool(c.LINES_NORMAL.size() > 0).is_true()


func test_refuse_lines_not_empty() -> void:
	var c = _make_customer()
	assert_bool(c.LINES_REFUSE.size() > 0).is_true()


func test_human_cheap_lines_not_empty() -> void:
	var c = _make_customer()
	assert_bool(c.LINES_HUMAN_CHEAP.size() > 0).is_true()


func test_human_normal_lines_not_empty() -> void:
	var c = _make_customer()
	assert_bool(c.LINES_HUMAN_NORMAL.size() > 0).is_true()


func test_human_expensive_lines_not_empty() -> void:
	var c = _make_customer()
	assert_bool(c.LINES_HUMAN_EXPENSIVE.size() > 0).is_true()


func test_human_refuse_lines_not_empty() -> void:
	var c = _make_customer()
	assert_bool(c.LINES_HUMAN_REFUSE.size() > 0).is_true()


func test_enter_lines_not_empty() -> void:
	var c = _make_customer()
	assert_bool(c.LINES_ENTER.size() > 0).is_true()


func test_all_chat_lines_are_strings() -> void:
	var c = _make_customer()
	var all_lines := []
	all_lines.append_array(c.LINES_PERFECT)
	all_lines.append_array(c.LINES_SATISFIED)
	all_lines.append_array(c.LINES_NORMAL)
	all_lines.append_array(c.LINES_REFUSE)
	all_lines.append_array(c.LINES_HUMAN_CHEAP)
	all_lines.append_array(c.LINES_HUMAN_NORMAL)
	all_lines.append_array(c.LINES_HUMAN_EXPENSIVE)
	all_lines.append_array(c.LINES_HUMAN_REFUSE)
	all_lines.append_array(c.LINES_ENTER)
	for line in all_lines:
		assert_bool(typeof(line) == TYPE_STRING).is_true()


func test_customer_default_move_speed() -> void:
	var c = _make_customer()
	assert_float(c.move_speed).is_equal(1.5)


func test_pickable_item_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/equipment/pickable_item.tscn")).is_true()


func test_equiped_item_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/equipment/equiped_item.tscn")).is_true()


func test_thrown_item_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/equipment/thrown_item.tscn")).is_true()


func test_chest_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/props/chest/chest.tscn")).is_true()


func test_spikes_trap_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/traps/spikes_trap.tscn")).is_true()


func test_acid_trap_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/traps/acid_trap.tscn")).is_true()


func test_destructible_item_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/props/destructible_item.tscn")).is_true()
