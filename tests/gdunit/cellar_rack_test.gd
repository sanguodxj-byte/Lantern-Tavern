extends GdUnitTestSuite
## 窖藏位 (CellarRack / CellarRackSlot) 测试：
## 放桶 → 发酵计时（FermentationSystem）→ 开缸取酒 → 盛酒器。

const RACK_SCRIPT := "res://scenes/tavern/brewing/cellar_rack.gd"
const CARRY_SCRIPT := "res://scenes/tavern/brewing/brew_player_carry.gd"
const FS := preload("res://globals/tavern/fermentation_system.gd")

var bfs: Node
var fs: Node
var rack: Node
var carry: Node

func before_test() -> void:
	bfs = Engine.get_main_loop().root.get_node("BrewFlowSystem")
	fs = Engine.get_main_loop().root.get_node("FermentationSystem")
	bfs.reset()
	fs.setup_kegs(1)
	rack = load(RACK_SCRIPT).new()
	add_child(rack)
	carry = load(CARRY_SCRIPT).new()
	add_child(carry)
	carry.clear()
	rack.set_carry(carry)

func after_test() -> void:
	if is_instance_valid(rack):
		rack.queue_free()
	if is_instance_valid(carry):
		carry.queue_free()

func test_rack_slot_count_follows_keg_capacity() -> void:
	assert_int(rack.get_slot_count()).is_equal(1)
	fs.setup_kegs(2)
	var rack2: Node = load(RACK_SCRIPT).new()
	add_child(rack2)
	assert_int(rack2.get_slot_count()).is_equal(2)
	rack2.queue_free()

func test_place_keg_starts_fermentation() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	carry.set_keg(token)
	var slot: Node = rack.slots[0]
	assert_bool(slot.can_interact()).is_true()
	slot.interact()
	assert_int(slot.token).is_equal(token)
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.FERMENTING)
	assert_bool(carry.is_holding()).is_false()
	assert_str(slot.status_label.text).contains("发酵")

func test_cannot_place_when_no_free_keg() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 1})
	carry.set_keg(token)
	rack.slots[0].interact()
	# 第二桶：无空桶位 → 放桶失败，玩家仍扛着
	var token2: int = bfs.register_filled_keg({"blackberry": 1})
	carry.set_keg(token2)
	assert_bool(rack.slots[0].can_interact()).is_false()
	rack.slots[0].interact()
	assert_bool(carry.is_keg()).is_true()

func test_open_keg_after_fermentation() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	carry.set_keg(token)
	var slot: Node = rack.slots[0]
	slot.interact()
	# 隔夜发酵完成
	fs.advance_day()
	bfs.sync_keg_state(token)
	assert_bool(slot.can_interact()).is_true()
	assert_str(slot.status_label.text).contains("开缸")
	slot.interact()
	assert_bool(carry.is_serving()).is_true()
	assert_int(carry.serving_flavors.get("果香", 0)).is_equal(6)
	assert_int(slot.token).is_equal(-1)
	# 桶位回归空桶
	assert_int(fs.kegs[0].state).is_equal(FS.KegState.EMPTY)

func test_open_fermenting_keg_rejected() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	carry.set_keg(token)
	var slot: Node = rack.slots[0]
	slot.interact()
	assert_bool(slot.can_interact()).is_false()
	slot.interact()
	assert_bool(carry.is_holding()).is_false()

func test_recipe_keg_sets_menu_price() -> void:
	# 亮莓果汁配方（人类标价 30）
	var ings := {"blackberry": 2, "glowshroom": 1, "pixie_dust": 1}
	var token: int = bfs.register_filled_keg(ings)
	carry.set_keg(token)
	var slot: Node = rack.slots[0]
	slot.interact()
	fs.advance_day()
	bfs.sync_keg_state(token)
	slot.interact()
	assert_bool(carry.is_serving()).is_true()
	assert_int(carry.serving_price).is_equal(30)
	assert_str(carry.serving_recipe_name).is_equal("亮莓果汁")

func test_custom_keg_defaults_menu_price() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 1})
	carry.set_keg(token)
	var slot: Node = rack.slots[0]
	slot.interact()
	fs.advance_day()
	bfs.sync_keg_state(token)
	slot.interact()
	assert_bool(carry.is_serving()).is_true()
	assert_int(carry.serving_price).is_equal(30)

func test_rack_refresh_restores_placed_kegs() -> void:
	var token: int = bfs.register_filled_keg({"blackberry": 2})
	carry.set_keg(token)
	rack.slots[0].interact()
	# 场景重载：新 rack 实例 refresh()
	var rack2: Node = load(RACK_SCRIPT).new()
	add_child(rack2)
	rack2.set_carry(carry)
	rack2.refresh()
	assert_int(rack2.slots[0].token).is_equal(token)
	rack2.queue_free()
