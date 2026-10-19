extends Node3D

## 酒馆顾客生成调度器。挂在 tavern.tscn 的 CustomerSeats 同级下。
## 营业开始时按声望来店率生成顾客，分配座位，驱动服务-结算-离场流程。
##
## 0805 架构审查：本节点是顾客服务的"权威入口"。一笔服务 =
##   quote（TavernSettlement 纯计算）→ 奖励接收端预检 → commit（好感/声望）
##   → 入账（金币/材料/装备）→ 实体退出可交互态 → 事件发布。
## 任何 visit 只能成功提交一次；重复请求返回第一次缓存结果（幂等）。

signal customer_spawned(customer_data)
signal customer_served(customer_data)
signal customer_left(customer_data)

## TavernSettlement 脚本常量：用于访问内部类 SettlementResult
## （新文件 class_name 在 headless 全局类缓存未刷新时无法解析）。
const TS := preload("res://globals/tavern/tavern_settlement.gd")

@export var max_concurrent_customers: int = 4
@export var spawn_interval: float = 3.0

@onready var tavern_interior: Node = get_parent()

var _active_customers: Array = []
var _spawn_timer: float = 0.0
var _seats: Array = []
var _occupied_seats: Dictionary = {}  # seat_idx → customer
var _is_open: bool = false
## 营业代际（2351 审查 P1）：每次 start_service/stop_service 递增；待处理的延迟离场
## 回调捕获创建时的 epoch，只在 epoch 与当前一致时才清理登记——防止旧营业的回调
## 误清新一轮营业中同 seat_idx 的登记。
var _service_epoch: int = 0

const CUSTOMER_SCENE := preload("res://scenes/tavern/customer_entity.tscn")

func _ready() -> void:
	# D4（0856 审查）：注册为组，TavernHUD 据此读取当前真实顾客生成订单
	# （不再消费旧 monster_preferences.json 假订单）。
	add_to_group("customer_spawner")

func start_service() -> void:
	_service_epoch += 1
	# 优先用已注入的 _seats（测试场景）；为空时才从酒馆场景取
	if _seats.is_empty() and tavern_interior != null and "seat_markers" in tavern_interior:
		_seats = tavern_interior.seat_markers
	_is_open = true
	_spawn_timer = 0.0

func stop_service() -> void:
	_is_open = false
	# 营业代际递增使待处理的离场回调失效，并主动清空登记（顾客已离场）。
	_service_epoch += 1
	for cust in _active_customers:
		if is_instance_valid(cust):
			if "customer_data" in cust and cust.customer_data != null:
				customer_left.emit(cust.customer_data)
			cust.leave()
	_active_customers.clear()
	_occupied_seats.clear()

func _process(delta: float) -> void:
	if not _is_open:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0 and _active_customers.size() < max_concurrent_customers:
		_try_spawn_customer()
		_spawn_timer = spawn_interval

func _try_spawn_customer() -> void:
	var free_idx: int = _find_free_seat()
	if free_idx == -1:
		return
	var ts: Node = _get_settlement()
	if ts == null:
		return
	# 按声望来店率筛选可生成的种族
	var race_id: String = _pick_race_by_visit_rate()
	if race_id == "":
		return
	var cust_data = ts.generate_customer(race_id)
	var entity: Node3D = CUSTOMER_SCENE.instantiate()
	entity.customer_data = cust_data
	entity.assign_spawner(self)
	# 从入口出生
	entity.global_position = Vector3(0, 0, 7)
	var seat: Marker3D = _seats[free_idx]
	entity.assign_seat(seat)
	_occupied_seats[free_idx] = entity
	add_child(entity)
	_active_customers.append(entity)
	customer_spawned.emit(cust_data)

func _find_free_seat() -> int:
	for i in range(_seats.size()):
		if not _occupied_seats.has(i):
			return i
	return -1

func _pick_race_by_visit_rate() -> String:
	# 按各势力声望阶梯的来店率加权随机
	var ts: Node = _get_settlement()
	if ts == null:
		return ""
	var races: Array = ["goblin", "minotaur", "cyclops", "ghost", "elf", "human"]
	var weights: Array = []
	for r in races:
		weights.append(ts.get_prestige_tier(r).visit_rate)
	var total: float = 0.0
	for w in weights:
		total += w
	var roll: float = randf() * total
	var cumul: float = 0.0
	for i in range(races.size()):
		cumul += weights[i]
		if roll <= cumul:
			return races[i]
	return races[races.size() - 1]

## 吧台调用：为指定座位的顾客上酒并结算（0805 审查：服务事务权威入口）。
## 幂等：同一 visit 已 COMMITTED 时直接返回首次缓存结果，不再写任何状态。
func serve_seated_customer(seat_idx: int, brew_flavors: Dictionary, menu_price: int) -> Variant:
	if not _occupied_seats.has(seat_idx):
		return TS.SettlementResult.failed("NO_SEAT")
	var entity: Node3D = _occupied_seats[seat_idx]
	if not is_instance_valid(entity):
		return TS.SettlementResult.failed("INVALID_ENTITY")
	var cust_data: Variant = entity.get("customer_data")
	if cust_data == null:
		return TS.SettlementResult.failed("NO_CUSTOMER_DATA")
	# P0 幂等闸门：已提交的 visit 返回首次结果，不重复发奖
	if cust_data.service_state == "COMMITTED":
		return cust_data.service_result
	var ts: Node = _get_settlement()
	if ts == null:
		return TS.SettlementResult.failed("NO_SETTLEMENT")
	# 1. 纯计算（不写全局）
	var quote_result: Variant = ts.quote(brew_flavors, menu_price, cust_data)
	if quote_result == null:
		return TS.SettlementResult.failed("SETTLE_FAILED")
	# 2. 奖励接收端预检：装备入包是唯一可能失败的接收端（背包容量）。
	#    容量不足 → 整笔服务拒绝（committed=false），好感/声望/金币零写入。
	var gear: Dictionary = quote_result.gear_gained if quote_result.gear_gained is Dictionary else {}
	if not gear.is_empty() and gear.has("id"):
		var gs: Node = _get_game_state()
		if gs == null or not _equipment_can_fit(gs):
			return TS.SettlementResult.failed("BACKPACK_FULL")
	# 3. 原子提交（预检后各接收端不可失败）
	ts.mark_committed(cust_data, quote_result)
	ts.commit(cust_data, quote_result)
	_credit_settlement(quote_result)
	# 4. 实体立即退出可交互态（离场动画仍由 _schedule_leave 延迟控制）
	if entity.has_method("on_served"):
		entity.on_served(quote_result)
	customer_served.emit(cust_data)
	# 5. 安排延迟离场
	call_deferred("_schedule_leave", entity, seat_idx)
	return quote_result

## 服务触发器入口：按顾客实体定位其座位并走 serve_seated_customer 完整链路。
func serve_entity(entity: Node3D, brew_flavors: Dictionary, menu_price: int) -> Variant:
	for seat_idx in _occupied_seats:
		if _occupied_seats[seat_idx] == entity:
			return serve_seated_customer(seat_idx, brew_flavors, menu_price)
	return TS.SettlementResult.failed("NO_SEAT")

## 结算入账：把 SettlementResult 的金币/赠礼材料/装备盲盒写入
## TavernManager（金币、仓库）与 GameState（随身装备）。
## 0805 审查 P1：只在事务已 COMMITTED 时调用（预检保证各写入不会失败）。
func _credit_settlement(result: Variant) -> void:
	if result == null or not bool(result.committed):
		return
	var gold_gained: int = int(result.gold_gained)
	var gift: Dictionary = result.gift_material if result.gift_material is Dictionary else {}
	var gear: Dictionary = result.gear_gained if result.gear_gained is Dictionary else {}
	if gold_gained > 0:
		var tm: Node = _get_tavern_manager()
		if tm != null and "gold" in tm:
			tm.gold = int(tm.gold) + gold_gained
	if not gift.is_empty():
		var tm2: Node = _get_tavern_manager()
		if tm2 != null and tm2.has_method("add_material"):
			for mat_id in gift:
				tm2.add_material(String(mat_id), int(gift[mat_id]))
	if not gear.is_empty() and gear.has("id"):
		var gs: Node = _get_game_state()
		if gs != null and gs.has_method("add_carried_equipment"):
			gs.add_carried_equipment(String(gear["id"]), 1)

## 装备奖励容量预检（0805 审查 P1）：背包剩余空间不足 1 格时拒绝整笔服务。
func _equipment_can_fit(gs: Node) -> bool:
	if "expedition_inventory" in gs:
		var inv: Variant = gs.expedition_inventory
		if inv != null and inv.has_method("get_space_free"):
			return int(inv.get_space_free()) >= 1
	return true

func _schedule_leave(entity: Node3D, seat_idx: int) -> void:
	# 2351 审查 P1：捕获创建时的营业代际；3 秒后离场。营业代际变化
	# （stop_service/新一轮 start_service）后旧回调不得清理新营业的登记。
	var epoch := _service_epoch
	var visit_data: Variant = entity.get("customer_data") if is_instance_valid(entity) else null
	get_tree().create_timer(3.0).timeout.connect(func():
		if epoch != _service_epoch:
			return
		if is_instance_valid(entity):
			entity.leave()
		if visit_data != null:
			customer_left.emit(visit_data)
		_occupied_seats.erase(seat_idx)
		_active_customers.erase(entity)
	)

func active_customer_count() -> int:
	return _active_customers.size()

## 只读快照 API（0805 审查 P1）：返回当前活动顾客的 customer_data 列表。
## TavernHUD 首次打开时调用一次做全量快照，之后靠事件增量收敛；
## UI 不再读取私有 _active_customers 字段。
func snapshot_active_visits() -> Array:
	var visits: Array = []
	for entity in _active_customers:
		if entity != null and is_instance_valid(entity) and "customer_data" in entity:
			visits.append(entity.customer_data)
	return visits

func _get_settlement() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("TavernSettlement")

func _get_tavern_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("TavernManager")

func _get_game_state() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("GameState")
