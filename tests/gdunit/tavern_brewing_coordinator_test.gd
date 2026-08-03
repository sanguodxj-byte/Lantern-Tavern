extends GdUnitTestSuite
## 酒馆 3D 酿酒总装（tavern.tscn Brewing 节点 + TavernBrewingCoordinator）测试：
## 玩家进入酿酒室/酒窖时，炼药锅站/原料架/倒桶台/窖藏位/手持组件齐备，
## 且全部可交互（复用玩家选择射线交互模式）。

var _tm: Node
var _phase_before: int
var _tutorial_before: bool

func before_test() -> void:
	_tm = Engine.get_main_loop().root.get_node("TavernManager")
	_phase_before = _tm.current_phase
	_tutorial_before = _tm.tutorial_active
	_tm.current_phase = _tm.Phase.NIGHT_TAVERN
	_tm.tutorial_active = false
	_tm.tutorial_completed = true

func after_test() -> void:
	_tm.current_phase = _phase_before
	_tm.tutorial_active = _tutorial_before

func test_tavern_mounts_brewing_coordinator() -> void:
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	await await_idle_frame()
	var brewing: Node = tavern.get_node_or_null("Brewing")
	assert_object(brewing).is_not_null()
	assert_bool(brewing.is_in_group("tavern_brewing")).is_true()
	tavern.queue_free()

func test_coordinator_builds_all_stations() -> void:
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	await await_idle_frame()
	var brewing: Node = tavern.get_node_or_null("Brewing")
	assert_object(brewing.get_node_or_null("BrewCauldron")).is_not_null()
	assert_object(brewing.get_node_or_null("IngredientSource")).is_not_null()
	assert_object(brewing.get_node_or_null("BarrelStation")).is_not_null()
	assert_object(brewing.get_node_or_null("CellarRack")).is_not_null()
	tavern.queue_free()

func test_cauldron_and_stations_positioned_in_brewing_room() -> void:
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	await await_idle_frame()
	var brewing: Node = tavern.get_node_or_null("Brewing")
	var cauldron: Node3D = brewing.get_node_or_null("BrewCauldron") as Node3D
	var rack: Node3D = brewing.get_node_or_null("CellarRack") as Node3D
	var barrel: Node3D = brewing.get_node_or_null("BarrelStation") as Node3D
	# 酿酒室范围：x[-1,3] z[-8.7,-6.25]
	assert_float(cauldron.global_position.x).is_greater(-1.0)
	assert_float(cauldron.global_position.x).is_less(3.0)
	assert_float(cauldron.global_position.z).is_less(-6.25)
	assert_float(cauldron.global_position.z).is_greater(-8.7)
	# 酒窖范围：x[-5,3] y≈-3.04 z[-8.7,-3.55]
	assert_float(rack.global_position.y).is_less(-2.0)
	assert_float(rack.global_position.z).is_less(-6.0)
	# 倒桶台与炼药锅、原料架同在酿酒室
	assert_float(barrel.global_position.z).is_less(-6.25)
	tavern.queue_free()

func test_carry_mounted_on_player() -> void:
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	await await_idle_frame()
	var player: Node = tavern.get_node_or_null("Player")
	assert_object(player).is_not_null()
	var brewing: Node = tavern.get_node_or_null("Brewing")
	var carry: Node = brewing.get("carry")
	assert_object(carry).is_not_null()
	# 挂在玩家相机下（跟随视角）
	var camera: Node = player.get_node_or_null("MainCamera")
	assert_bool(carry.get_parent() == camera).is_true()
	tavern.queue_free()

func test_stations_wired_to_carry() -> void:
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	await await_idle_frame()
	var brewing: Node = tavern.get_node_or_null("Brewing")
	assert_object(brewing.get("carry")).is_not_null()
	assert_object(brewing.get_node("BrewCauldron").get("carry")).is_not_null()
	assert_object(brewing.get_node("IngredientSource").get("carry")).is_not_null()
	assert_object(brewing.get_node("BarrelStation").get("carry")).is_not_null()
	assert_object(brewing.get_node("CellarRack").get("carry")).is_not_null()
	tavern.queue_free()

func test_customer_spawner_present_and_serving_night_phase() -> void:
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	await await_idle_frame()
	var spawner: Node = tavern.get_node_or_null("CustomerSpawner")
	assert_object(spawner).is_not_null()
	assert_bool(spawner._is_open).is_true()
	tavern.queue_free()

func test_brewing_stations_are_interactable_contract() -> void:
	# 复用玩家 _can_interact_collider 契约：interact() + can_interact() + interaction_name
	for path in [
		"res://scenes/tavern/brewing/brew_cauldron_station.gd",
		"res://scenes/tavern/brewing/brew_ingredient_slot.gd",
		"res://scenes/tavern/brewing/brew_barrel_station.gd",
		"res://scenes/tavern/brewing/cellar_rack_slot.gd",
		"res://scenes/tavern/brewing/customer_serve_trigger.gd",
	]:
		var script := load(path) as GDScript
		assert_object(script).is_not_null()
		var instance: Object = script.new()
		assert_bool(instance.has_method("interact")).is_true()
		assert_bool(instance.has_method("can_interact")).is_true()
		assert_bool("interaction_name" in instance).is_true()
		instance.free()

func test_cellar_rack_uses_voxel_barrels_and_labels() -> void:
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	await await_idle_frame()
	var brewing: Node = tavern.get_node_or_null("Brewing")
	var rack: Node = brewing.get_node_or_null("CellarRack")
	assert_int(rack.get_slot_count()).is_greater_equal(1)
	for slot in rack.slots:
		assert_object(slot.status_label).is_not_null()
		assert_bool(String(slot.status_label.text).length() > 0).is_true()
	tavern.queue_free()
