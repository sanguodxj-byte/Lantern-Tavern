extends GdUnitTestSuite
## 原料架 (BrewIngredientSource / BrewIngredientSlot) 测试：
## 仓库原料 → 取用为手持原料。

const SOURCE_SCRIPT := "res://scenes/tavern/brewing/brew_ingredient_source.gd"
const CARRY_SCRIPT := "res://scenes/tavern/brewing/brew_player_carry.gd"

var tm: Node
var source: Node
var carry: Node
var _saved_inventory: Dictionary

func before_test() -> void:
	tm = Engine.get_main_loop().root.get_node("TavernManager")
	_saved_inventory = tm.materials_inventory.duplicate()
	tm.materials_inventory = {"blackberry": 3, "glowshroom": 1, "moldy_bread": 2}
	source = load(SOURCE_SCRIPT).new()
	add_child(source)
	carry = load(CARRY_SCRIPT).new()
	add_child(carry)
	carry.clear()
	source.carry = carry
	source.refresh_slots()

func after_test() -> void:
	tm.materials_inventory = _saved_inventory
	if is_instance_valid(source):
		source.queue_free()
	if is_instance_valid(carry):
		carry.queue_free()

func test_slots_built_from_inventory() -> void:
	assert_int(source.slots.size()).is_equal(3)

func test_slot_can_interact_returns_ingredient() -> void:
	var slot: Node = source.slots[0]
	assert_bool(slot.can_interact()).is_true()
	slot.interact()
	assert_bool(carry.is_ingredient()).is_true()
	# 仓库扣减 1 份
	assert_int(tm.materials_inventory.get(slot.material_id, 0)).is_equal(2)

func test_slot_rejects_when_hand_busy() -> void:
	var slot: Node = source.slots[0]
	carry.set_ingredient("blackberry")
	assert_bool(slot.can_interact()).is_false()
	slot.interact()
	# 未取用（手持被占用）
	assert_int(tm.materials_inventory.get(slot.material_id, 0)).is_equal(3)

func test_slot_hides_when_exhausted() -> void:
	var slot: Node = null
	for s in source.slots:
		if String(s.material_id) == "glowshroom":
			slot = s
			break
	assert_object(slot).is_not_null()
	slot.interact()
	source.refresh_slots()
	# glowshroom 数量为 0 → 旧槽位被重建移除
	assert_bool(slot.is_queued_for_deletion()).is_true()
	for s in source.slots:
		if is_instance_valid(s):
			assert_bool(String(s.material_id) != "glowshroom").is_true()

func test_slots_rebuild_after_inventory_change() -> void:
	tm.materials_inventory = {"blackberry": 1}
	source.refresh_slots()
	assert_int(source.slots.size()).is_equal(1)
	assert_str(source.slots[0].material_id).is_equal("blackberry")

func test_max_slots_cap() -> void:
	var many := {}
	for i in range(12):
		many["mat_%d" % i] = 5
	tm.materials_inventory = many
	source.refresh_slots()
	assert_int(source.slots.size()).is_less_equal(source.MAX_SLOTS)

func test_slot_interaction_verb_named() -> void:
	var slot: Node = source.slots[0]
	assert_bool(String(slot.interaction_name).length() > 0).is_true()
	assert_bool(String(slot.interaction_verb).length() > 0).is_true()
