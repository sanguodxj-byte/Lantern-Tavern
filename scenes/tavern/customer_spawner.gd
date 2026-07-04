extends Node3D

## 酒馆顾客生成调度器。挂在 tavern.tscn 的 CustomerSeats 同级下。
## 营业开始时按声望来店率生成顾客，分配座位，驱动服务-结算-离场流程。

@export var max_concurrent_customers: int = 4
@export var spawn_interval: float = 3.0

@onready var tavern_interior: Node = get_parent()

var _active_customers: Array = []
var _spawn_timer: float = 0.0
var _seats: Array = []
var _occupied_seats: Dictionary = {}  # seat_idx → customer
var _is_open: bool = false

const CUSTOMER_SCENE := preload("res://scenes/tavern/customer_entity.tscn")

func start_service() -> void:
	# 优先用已注入的 _seats（测试场景）；为空时才从酒馆场景取
	if _seats.is_empty() and tavern_interior != null and "seat_markers" in tavern_interior:
		_seats = tavern_interior.seat_markers
	_is_open = true
	_spawn_timer = 0.0

func stop_service() -> void:
	_is_open = false
	# 所有顾客离场
	for cust in _active_customers:
		if is_instance_valid(cust):
			cust.leave()

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
	# 从入口出生
	entity.global_position = Vector3(0, 0, 7)
	var seat: Marker3D = _seats[free_idx]
	entity.assign_seat(seat)
	_occupied_seats[free_idx] = entity
	add_child(entity)
	_active_customers.append(entity)

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

func serve_seated_customer(seat_idx: int, brew_flavors: Dictionary, menu_price: int) -> Variant:
	# 吧台调用：为指定座位的顾客上酒并结算
	if not _occupied_seats.has(seat_idx):
		return {}
	var entity: Node3D = _occupied_seats[seat_idx]
	if not is_instance_valid(entity):
		return {}
	var result: Variant = entity.serve(brew_flavors, menu_price)
	# 结算后安排离场（延迟由 customer_entity 自行处理台词显示）
	call_deferred("_schedule_leave", entity, seat_idx)
	return result

func _schedule_leave(entity: Node3D, seat_idx: int) -> void:
	# 3 秒后离场，让玩家看到台词
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(entity):
			entity.leave()
		_occupied_seats.erase(seat_idx)
		_active_customers.erase(entity)
	)

func active_customer_count() -> int:
	return _active_customers.size()

func _get_settlement() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("TavernSettlement")
