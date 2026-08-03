extends GdUnitTestSuite
## 炼药锅站 (BrewCauldronStation) 测试：投料 → 蒸煮 → 取麦汁的 3D 交互闭环。

const CAULDRON_SCRIPT := "res://scenes/tavern/brewing/brew_cauldron_station.gd"
const CARRY_SCRIPT := "res://scenes/tavern/brewing/brew_player_carry.gd"

var bfs: Node
var station: Node
var carry: Node

func before_test() -> void:
	bfs = Engine.get_main_loop().root.get_node("BrewFlowSystem")
	bfs.reset()
	station = load(CAULDRON_SCRIPT).new()
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

func test_station_builds_cauldron_visual() -> void:
	assert_object(station.cauldron_visual).is_not_null()
	assert_str(station.cauldron_visual.prop_kind).is_equal("brew_cauldron")
	assert_object(station.status_label).is_not_null()

func test_can_interact_false_when_idle_and_empty_hand() -> void:
	assert_bool(station.can_interact()).is_false()

func test_interact_with_ingredient_adds_to_cauldron() -> void:
	carry.set_ingredient("blackberry")
	assert_bool(station.can_interact()).is_true()
	station.interact()
	assert_int(bfs.cauldron_basket.get("blackberry", 0)).is_equal(1)
	assert_bool(carry.is_holding()).is_false()
	# 投料后自动开火蒸煮
	assert_int(bfs.cauldron_state).is_equal(bfs.CauldronState.BOILING)

func test_multiple_ingredients_stack() -> void:
	carry.set_ingredient("blackberry")
	station.interact()
	carry.set_ingredient("glowshroom")
	station.interact()
	carry.set_ingredient("blackberry")
	station.interact()
	assert_int(bfs.cauldron_basket.get("blackberry", 0)).is_equal(2)
	assert_int(bfs.cauldron_basket.get("glowshroom", 0)).is_equal(1)

func test_stack_visual_capped() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	bfs.add_to_cauldron("blackberry")
	station._refresh_basket_visual()
	assert_int(station._stack_visuals.size()).is_less_equal(station.STACK_VISUAL_CAP)

func test_interact_takes_wort_when_ready() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.start_boiling()
	bfs.tick_boil(bfs.BOIL_DURATION_SEC)
	assert_int(bfs.cauldron_state).is_equal(bfs.CauldronState.READY)
	assert_bool(station.can_interact()).is_true()
	station.interact()
	assert_bool(carry.is_wort()).is_true()
	assert_int(carry.wort_ingredients.get("blackberry", 0)).is_equal(1)
	# 炼药锅回归空锅
	assert_int(bfs.cauldron_state).is_equal(bfs.CauldronState.IDLE)
	assert_bool(bfs.cauldron_basket.is_empty()).is_true()

func test_interact_rejects_wort_when_hand_busy() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.start_boiling()
	bfs.tick_boil(bfs.BOIL_DURATION_SEC)
	carry.set_ingredient("blackberry")
	assert_bool(station.can_interact()).is_false()

func test_interact_rejects_ingredient_when_cauldron_ready() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.start_boiling()
	bfs.tick_boil(bfs.BOIL_DURATION_SEC)
	carry.set_ingredient("glowshroom")
	station.interact()
	# 未被投入
	assert_int(bfs.cauldron_basket.get("glowshroom", 0)).is_equal(0)
	assert_bool(carry.is_holding()).is_true()

func test_boiling_visual_progress_label() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.start_boiling()
	bfs.tick_boil(bfs.BOIL_DURATION_SEC * 0.5)
	station._sync_boil_visuals()
	assert_bool(station.fire_particles.emitting).is_true()
	assert_bool(station.steam_particles.emitting).is_true()
	assert_bool(station.fire_light.visible).is_true()
	assert_str(station.status_label.text).contains("50")

func test_ready_visual_stops_fire_and_steam() -> void:
	bfs.add_to_cauldron("blackberry")
	bfs.start_boiling()
	bfs.tick_boil(bfs.BOIL_DURATION_SEC)
	station._sync_boil_visuals()
	assert_bool(station.fire_particles.emitting).is_false()
	assert_bool(station.steam_particles.emitting).is_false()
	assert_str(station.status_label.text).contains("麦汁")
