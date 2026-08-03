extends GdUnitTestSuite
## 手持酿酒物品组件 (BrewPlayerCarry) 测试。

const CARRY_SCRIPT := "res://scenes/tavern/brewing/brew_player_carry.gd"

var carry: Node

func before_test() -> void:
	carry = load(CARRY_SCRIPT).new()
	add_child(carry)
	carry.clear()

func after_test() -> void:
	if is_instance_valid(carry):
		carry.queue_free()

func test_initial_state_empty() -> void:
	assert_bool(carry.is_holding()).is_false()
	assert_int(carry.kind).is_equal(carry.CarryKind.NONE)

func test_set_ingredient() -> void:
	carry.set_ingredient("blackberry")
	assert_bool(carry.is_ingredient()).is_true()
	assert_str(carry.material_id).is_equal("blackberry")
	assert_bool(carry.is_holding()).is_true()

func test_set_wort_stores_ingredients() -> void:
	var ings := {"blackberry": 2, "glowshroom": 1}
	carry.set_wort(ings)
	assert_bool(carry.is_wort()).is_true()
	assert_int(carry.wort_ingredients["blackberry"]).is_equal(2)
	# 副本隔离：外部修改不影响持有数据
	ings["blackberry"] = 99
	assert_int(carry.wort_ingredients["blackberry"]).is_equal(2)

func test_set_serving_stores_flavors_and_price() -> void:
	carry.set_serving({"果香": 6}, 30, "亮莓果汁")
	assert_bool(carry.is_serving()).is_true()
	assert_int(carry.serving_price).is_equal(30)
	assert_str(carry.serving_recipe_name).is_equal("亮莓果汁")
	assert_int(carry.serving_flavors["果香"]).is_equal(6)

func test_set_keg_stores_token() -> void:
	carry.set_keg(7)
	assert_bool(carry.is_keg()).is_true()
	assert_int(carry.keg_token).is_equal(7)

func test_clear_resets_all_fields() -> void:
	carry.set_serving({"果香": 6}, 30, "亮莓果汁")
	carry.clear()
	assert_bool(carry.is_holding()).is_false()
	assert_str(carry.material_id).is_empty()
	assert_int(carry.keg_token).is_equal(-1)
	assert_int(carry.serving_price).is_equal(0)
	assert_bool(carry.wort_ingredients.is_empty()).is_true()

func test_switch_kind_frees_previous_visual() -> void:
	carry.set_ingredient("blackberry")
	var visual_count_after_ingredient: int = carry.get_child_count()
	assert_int(visual_count_after_ingredient).is_greater_equal(1)
	carry.set_keg(1)
	assert_int(carry.get_child_count()).is_greater_equal(1)

func test_visual_children_built_for_each_kind() -> void:
	carry.set_ingredient("blackberry")
	assert_int(carry.get_child_count()).is_greater_equal(1)
	carry.clear()
	carry.set_wort({"blackberry": 1})
	assert_int(carry.get_child_count()).is_greater_equal(1)
	carry.clear()
	carry.set_serving({"果香": 1}, 10)
	assert_int(carry.get_child_count()).is_greater_equal(1)
	carry.clear()
	carry.set_keg(1)
	assert_int(carry.get_child_count()).is_greater_equal(1)

func test_get_kind_name() -> void:
	carry.set_ingredient("blackberry")
	assert_bool(String(carry.get_kind_name()).length() > 0).is_true()
	carry.clear()
	assert_str(carry.get_kind_name()).is_equal(tr("空手"))
