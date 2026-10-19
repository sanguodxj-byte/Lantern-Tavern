extends GdUnitTestSuite

# D4（0856 审查）：经营 HUD 订单必须来自真实顾客（TavernSettlement.Customer /
# CustomerSpawner），与结算使用同一套中文 16 口味体系；展示口味键必须 ∈
# BrewingData.FLAVOR_NAME_TO_ENUM。不再消费旧 monster_preferences.json 英文口味假订单。

const TavernHUD := preload("res://scenes/ui/tavern_hud.gd")
const BrewingData := preload("res://globals/tavern/brewing_data.gd")

## 构造同构 customer_data（TavernSettlement.Customer 字段子集）。
func _mock_customer(race: String, liked: Dictionary, hated: Array) -> Dictionary:
	return {
		"race_id": race,
		"display_name": race,
		"real_name": "",
		"liked": liked,
		"hated": hated,
	}


func test_orders_from_real_customer_use_chinese_flavor_keys() -> void:
	var cust := _mock_customer("goblin", {"甜美": 4, "腐败": 2}, ["苦涩", "咸度"])
	var orders: Array = TavernHUD.build_orders_from_customers([cust])
	assert_int(orders.size()).is_equal(1)
	var order: Dictionary = orders[0]
	assert_str(String(order["customer_name"])).is_equal("goblin")
	var liked: Array = order["liked_flavors"]
	assert_int(liked.size()).is_equal(2)
	# 每个展示口味键必须属于正式口味体系（D4 契约）。
	for entry in liked:
		assert_bool(BrewingData.FLAVOR_NAME_TO_ENUM.has(String(entry["name"]))).is_true()
	for name in order["hated_flavors"]:
		assert_bool(BrewingData.FLAVOR_NAME_TO_ENUM.has(String(name))).is_true()


func test_orders_filter_unknown_flavor_keys() -> void:
	# 旧英文键（sweet/umami 等）不属于正式体系 → 被过滤，不进入展示。
	var cust := _mock_customer("spider", {"sweet": 3}, ["salty"])
	var orders: Array = TavernHUD.build_orders_from_customers([cust])
	assert_int(orders.size()).is_equal(1)
	var order: Dictionary = orders[0]
	assert_int((order["liked_flavors"] as Array).size()).is_equal(0)
	assert_int((order["hated_flavors"] as Array).size()).is_equal(0)


func test_orders_empty_when_no_customers() -> void:
	assert_int(TavernHUD.build_orders_from_customers([]).size()).is_equal(0)
	assert_int(TavernHUD.build_orders_from_customers([null]).size()).is_equal(0)


func test_orders_multiple_customers_preserved() -> void:
	var a := _mock_customer("goblin", {"甜美": 3}, [])
	var b := _mock_customer("elf", {"香醇": 5}, ["剧毒"])
	var orders: Array = TavernHUD.build_orders_from_customers([a, b])
	assert_int(orders.size()).is_equal(2)


func test_hud_no_longer_reads_legacy_preference_json() -> void:
	# 禁止模式守卫（D4/D5）：生产 HUD 不得再读取 monster_preferences.json 生成假订单，
	# 也不得再读取过期 brewing_materials.json。
	var source := (load("res://scenes/ui/tavern_hud.gd") as GDScript).source_code
	assert_bool(source.contains("res://data/monster_preferences.json")).is_false()
	assert_bool(source.contains("res://data/brewing_materials.json")).is_false()


func test_customer_spawner_registers_to_group() -> void:
	# TavernHUD 依赖 customer_spawner 组查找当前顾客。
	var script := load("res://scenes/tavern/customer_spawner.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains('add_to_group("customer_spawner")')).is_true()
