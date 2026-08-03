extends GdUnitTestSuite
## 倒桶台 (BrewBarrelStation) 测试：麦汁倒入 → 液面上升 → 扛起满桶。

const STATION_SCRIPT := "res://scenes/tavern/brewing/brew_barrel_station.gd"
const CARRY_SCRIPT := "res://scenes/tavern/brewing/brew_player_carry.gd"

var bfs: Node
var station: Node
var carry: Node

func before_test() -> void:
	bfs = Engine.get_main_loop().root.get_node("BrewFlowSystem")
	bfs.reset()
	station = load(STATION_SCRIPT).new()
	add_child(station)
	carry = load(CARRY_SCRIPT).new()
	add_child(carry)
	carry.clear()
	station.carry = carry

func after_test() -> void:
	if is_instance_valid(station):
		station.queue_free()
	if is_instance_valid(carry):
		carry.queue_free()

func test_can_interact_false_when_empty() -> void:
	assert_bool(station.can_interact()).is_false()

func test_pour_wort_fills_barrel() -> void:
	carry.set_wort({"blackberry": 2, "glowshroom": 1})
	assert_bool(station.can_interact()).is_true()
	station.interact()
	assert_float(station.fill_level).is_equal(1.0)
	assert_int(station.keg_token).is_greater_equal(0)
	assert_bool(carry.is_holding()).is_false()
	assert_bool(station.liquid_box.visible).is_true()
	# 已登记一桶酒（BrewFlowSystem）
	assert_object(bfs.find_keg(station.keg_token)).is_not_null()

func test_lift_keg_gives_player_carry() -> void:
	carry.set_wort({"blackberry": 2})
	station.interact()
	station.interact()
	assert_bool(carry.is_keg()).is_true()
	assert_int(carry.keg_token).is_greater_equal(0)
	assert_float(station.fill_level).is_equal(0.0)
	assert_int(station.keg_token).is_equal(-1)
	assert_bool(station.liquid_box.visible).is_false()

func test_pour_requires_wort() -> void:
	carry.set_ingredient("blackberry")
	station.interact()
	assert_float(station.fill_level).is_equal(0.0)

func test_lift_requires_empty_hand() -> void:
	carry.set_wort({"blackberry": 2})
	station.interact()
	carry.set_ingredient("blackberry")
	assert_bool(station.can_interact()).is_false()
	station.interact()
	assert_float(station.fill_level).is_equal(1.0)

func test_refresh_restores_orphan_keg() -> void:
	# 模拟上一场景遗留：已登记但未窖藏的酒桶（keg_index = -1）
	var token: int = bfs.register_filled_keg({"blackberry": 1})
	station._refresh_from_flow()
	assert_int(station.keg_token).is_equal(token)
	assert_float(station.fill_level).is_equal(1.0)

func test_filled_barrel_carries_original_ingredients() -> void:
	var ings := {"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}
	carry.set_wort(ings)
	station.interact()
	var keg = bfs.find_keg(station.keg_token)
	assert_object(keg).is_not_null()
	assert_int(keg.ingredients["blackberry"]).is_equal(2)
	assert_int(keg.ingredients.size()).is_equal(3)
