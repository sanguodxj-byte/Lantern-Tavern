extends GdUnitTestSuite
## 服务事务测试（0805 架构审查）：覆盖 P0 幂等、P1 原子提交/常客来访隔离/
## 存档边界、P2 失败不消费盛酒器，以及 quote 纯计算契约。

const SPAWNER_SCRIPT := "res://scenes/tavern/customer_spawner.gd"
const ENTITY_SCENE := "res://scenes/tavern/customer_entity.tscn"
const TRIGGER_SCRIPT := "res://scenes/tavern/brewing/customer_serve_trigger.gd"
const CARRY_SCRIPT := "res://scenes/tavern/brewing/brew_player_carry.gd"
const COORD_SCRIPT := "res://scenes/tavern/brewing/tavern_brewing_coordinator.gd"

var ts: Node
var tm: Node
var spawner: Node
var _saved_gold: int
var _served_signal_count: int = 0

func _on_served_probe(_customer_data) -> void:
	_served_signal_count += 1

func before_test() -> void:
	ts = Engine.get_main_loop().root.get_node("TavernSettlement")
	tm = Engine.get_main_loop().root.get_node("TavernManager")
	_saved_gold = tm.gold
	ts.rumor_reputation = 0
	for race in ts.faction_reputation.keys():
		ts.faction_reputation[race] = 0
	spawner = Node3D.new()
	spawner.set_script(load(SPAWNER_SCRIPT))
	add_child(spawner)
	var seat := Marker3D.new()
	add_child(seat)
	spawner._seats = [seat]

func after_test() -> void:
	tm.gold = _saved_gold
	if is_instance_valid(spawner):
		spawner.queue_free()

func _spawn_seated_entity(race: String) -> Node3D:
	var entity: Node3D = load(ENTITY_SCENE).instantiate()
	add_child(entity)
	entity.customer_data = ts.generate_customer(race)
	entity.assign_spawner(spawner)
	entity._state = "seated"
	spawner._occupied_seats[0] = entity
	return entity

func _make_iron_goblin(entity: Node3D, iron: int) -> void:
	entity.customer_data.liked = {"腐败": 2, "甜美": 1}
	entity.customer_data.hated = ["苦涩"]
	entity.customer_data.hated_levels = {"苦涩": 0}
	entity.customer_data.carry_type = "iron"
	entity.customer_data.iron_amount = iron

# ---------------------------------------------------------------------------
# P0 — 幂等：同一 visit 最多成功提交一次
# ---------------------------------------------------------------------------

func test_double_serve_same_visit_commits_once() -> void:
	var entity := _spawn_seated_entity("goblin")
	_make_iron_goblin(entity, 12)
	var gold_before: int = tm.gold
	var rep_before: int = ts.faction_reputation["goblin"]
	# 第一次：完整提交
	var r1: Variant = spawner.serve_seated_customer(0, {"腐败": 6, "甜美": 5}, 0)
	assert_bool(r1.committed).is_true()
	assert_str(r1.tier).is_equal("极佳")
	assert_int(tm.gold).is_equal(gold_before + 12)
	# 同帧第二次请求（无 await）：幂等闸门直接返回缓存，零写入
	var r2: Variant = spawner.serve_seated_customer(0, {"腐败": 6, "甜美": 5}, 0)
	assert_int(tm.gold).is_equal(gold_before + 12)
	assert_str(r2.transaction_id).is_equal(r1.transaction_id)
	assert_bool(r2.committed).is_true()
	assert_int(ts.faction_reputation["goblin"]).is_equal(rep_before + 1)
	assert_int(entity.customer_data.individual_affinity).is_equal(15)
	assert_str(entity.customer_data.service_state).is_equal("COMMITTED")
	# 实体应立即退出可交互态（3 秒计时只控制离场表现）
	assert_str(entity._state).is_equal("served")

func test_customer_served_signal_emitted_once() -> void:
	var entity := _spawn_seated_entity("goblin")
	_make_iron_goblin(entity, 6)
	_served_signal_count = 0
	spawner.customer_served.connect(_on_served_probe)
	spawner.serve_seated_customer(0, {"腐败": 3, "甜美": 2}, 0)
	spawner.serve_seated_customer(0, {"腐败": 3, "甜美": 2}, 0)
	assert_int(_served_signal_count).is_equal(1)

# ---------------------------------------------------------------------------
# P1 — 原子提交：奖励接收端预检失败 → 整笔服务拒绝，无半结算
# ---------------------------------------------------------------------------

func test_backpack_full_rejects_service_and_retry_succeeds() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node("GameState")
	var inv = gs.expedition_inventory
	var saved_limit: int = inv.space_limit
	inv.space_limit = 0
	var entity := _spawn_seated_entity("goblin")
	entity.customer_data.liked = {"腐败": 2, "甜美": 1}
	entity.customer_data.hated = ["苦涩"]
	entity.customer_data.hated_levels = {"苦涩": 0}
	entity.customer_data.carry_type = "gear"
	entity.customer_data.gear_item = {"id": "shortsword"}
	var gold_before: int = tm.gold
	var r1: Variant = spawner.serve_seated_customer(0, {"腐败": 6, "甜美": 5}, 0)
	assert_bool(r1.committed).is_false()
	assert_str(r1.error_code).is_equal("BACKPACK_FULL")
	# 零副作用：金币/声望/好感均未写入，交易状态保持 WAITING 可重试
	assert_int(tm.gold).is_equal(gold_before)
	assert_int(ts.faction_reputation["goblin"]).is_equal(0)
	assert_int(entity.customer_data.individual_affinity).is_equal(0)
	assert_str(entity.customer_data.service_state).is_equal("WAITING")
	assert_str(entity._state).is_equal("seated")
	# 腾出空间后重试成功，装备入包
	inv.space_limit = saved_limit
	var r2: Variant = spawner.serve_seated_customer(0, {"腐败": 6, "甜美": 5}, 0)
	assert_bool(r2.committed).is_true()
	assert_int(int(inv.equipment.get("shortsword", 0))).is_equal(1)
	gs.remove_carried_equipment("shortsword", 1)
	inv.space_limit = saved_limit

# ---------------------------------------------------------------------------
# P2 — 失败不消费盛酒器
# ---------------------------------------------------------------------------

func test_trigger_keeps_carry_when_commit_fails() -> void:
	var entity := _spawn_seated_entity("goblin")
	_make_iron_goblin(entity, 9)
	var coord: Node = load(COORD_SCRIPT).new()
	coord.name = "CoordinatorMock"
	add_child(coord)
	var carry: Node = load(CARRY_SCRIPT).new()
	add_child(carry)
	carry.clear()
	coord.carry = carry
	carry.set_serving({"腐败": 6, "甜美": 5}, 0)
	var trigger: Node = entity.get_node("ServeTrigger")
	# 制造失败：实体从座位登记移除 → serve_entity 返回 NO_SEAT
	spawner._occupied_seats.erase(0)
	trigger.interact()
	assert_bool(carry.is_serving()).is_true()
	assert_bool(carry.is_holding()).is_true()
	coord.queue_free()
	carry.queue_free()

# ---------------------------------------------------------------------------
# P1 — quote 纯计算 / commit 一次性写入
# ---------------------------------------------------------------------------

func test_quote_is_pure_until_commit() -> void:
	var cust = ts.generate_customer("goblin")
	cust.liked = {"腐败": 2, "甜美": 1}
	cust.hated = ["苦涩"]
	cust.hated_levels = {"苦涩": 0}
	cust.carry_type = "iron"
	cust.iron_amount = 12
	var rep_before: int = ts.faction_reputation["goblin"]
	var result: Variant = ts.quote({"腐败": 6, "甜美": 5}, 0, cust)
	assert_str(result.tier).is_equal("极佳")
	assert_bool(result.committed).is_false()
	assert_str(result.transaction_id).is_equal(cust.visit_id)
	# quote 不写任何状态
	assert_int(ts.faction_reputation["goblin"]).is_equal(rep_before)
	assert_int(cust.individual_affinity).is_equal(0)
	# commit 一次性写入
	ts.mark_committed(cust, result)
	ts.commit(cust, result)
	assert_bool(result.committed).is_true()
	assert_int(cust.individual_affinity).is_equal(15)
	assert_int(ts.faction_reputation["goblin"]).is_equal(rep_before + 1)

# ---------------------------------------------------------------------------
# P1 — 常客来访隔离：拷贝 profile，不复用名册对象，钱包每次新生成
# ---------------------------------------------------------------------------

func test_regular_visit_copies_profile_but_fresh_wallet() -> void:
	var profile = ts.generate_customer("goblin")
	profile.individual_affinity = 45
	profile.is_regular = true
	profile.display_name = profile.real_name
	ts.regular_customers["goblin"].append(profile)
	var regular_hits := 0
	for i in range(150):
		var visit = ts.generate_customer("goblin")
		if not visit.is_regular:
			continue
		regular_hits += 1
		# 绝不复用名册对象（0805 审查运行时探针：58 次回访全部复用旧对象）
		assert_bool(visit != profile).is_true()
		# 长期 profile 字段延续
		assert_int(visit.individual_affinity).is_equal(45)
		assert_str(visit.display_name).is_equal(visit.real_name)
		# 本次来访载荷新生成（名册对象已剥离载荷）
		assert_bool(visit.carry_type == "iron" or visit.carry_type == "gear").is_true()
		assert_str(visit.visit_id).is_not_empty()
	assert_bool(regular_hits > 0).is_true()

# ---------------------------------------------------------------------------
# P1 — 存档边界：名册只持久化长期 profile
# ---------------------------------------------------------------------------

func test_serialize_regular_excludes_visit_payload() -> void:
	var cust = ts.generate_customer("goblin")
	cust.individual_affinity = 45
	cust.is_regular = true
	cust.carry_type = "gear"
	cust.gear_item = {"id": "shortsword", "tier_index": 1}
	cust.iron_amount = 0
	cust.service_state = "COMMITTED"
	ts.regular_customers["goblin"].append(cust)
	var data: Dictionary = ts.serialize()
	var entry: Dictionary = data["regular_customers"]["goblin"][0]
	assert_bool(entry.has("gear_item")).is_false()
	assert_bool(entry.has("carry_type")).is_false()
	assert_bool(entry.has("iron_amount")).is_false()
	assert_bool(entry.has("visit_id")).is_false()
	assert_bool(entry.has("service_state")).is_false()
	# 长期字段完整保留
	assert_int(entry["individual_affinity"]).is_equal(45)
	assert_bool(entry["is_regular"]).is_true()

func test_deserialize_regular_ignores_legacy_payload() -> void:
	# 模拟旧存档：仍含 gear_item/carry_type/iron_amount 字段
	var legacy_entry := {
		"race_id": "goblin",
		"display_name": "格鲁姆",
		"real_name": "格鲁姆",
		"liked": {"腐败": 2},
		"hated": ["苦涩"],
		"hated_levels": {"苦涩": 0},
		"carry_type": "gear",
		"iron_amount": 0,
		"gear_item": {"id": "shortsword", "tier_index": 1},
		"individual_affinity": 45,
		"is_regular": true,
	}
	var restored = ts._customer_from_dict(legacy_entry)
	# 载荷不恢复；carry 回落到安全默认值（新来访时重新生成）
	assert_bool(restored.gear_item.is_empty()).is_true()
	assert_int(restored.iron_amount).is_equal(0)
	assert_int(restored.individual_affinity).is_equal(45)
	assert_bool(restored.is_regular).is_true()
