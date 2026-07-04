extends Node3D

## 酒馆顾客 3D 实体。轻量级：不继承战斗 CharacterBody3D，仅负责
## 在座位间移动 + 头顶对话气泡显示满意度台词（策划案 12 §5.0 隐性化表达）。

@export var move_speed: float = 1.5

var customer_data  # TavernSettlement.Customer 引用
var seat_marker: Marker3D
var _state: String = "walking"  # walking / seated / leaving
var _chat_label: Label3D
var _chat_timer: float = 0.0

# 满意度台词池（策划案 12 §5.2，四档情绪反差强烈）
const LINES_PERFECT := ["神迹！这股香醇彻底征服了我！不虚此生！"]
const LINES_SATISFIED := ["噢噢噢！太正宗了！这就是我想要的味道！"]
const LINES_NORMAL := ["啧，味道勉强凑合。润润喉咙还行。"]
const LINES_REFUSE := ["呸！这什么恶心的马尿！别指望我留下铁片！"]
const LINES_HUMAN_CHEAP := ["价格公道，老板实在。"]
const LINES_HUMAN_NORMAL := ["嗯……还行吧。"]
const LINES_HUMAN_EXPENSIVE := ["这价格……算了，下次不来了。"]
const LINES_HUMAN_REFUSE := ["宰客！再也不来了！"]
const LINES_ENTER := ["来一杯。", "老板，上酒。", "今晚生意不错。"]

func _ready() -> void:
	_setup_chat_label()

func _setup_chat_label() -> void:
	_chat_label = Label3D.new()
	_chat_label.name = "ChatBubble"
	_chat_label.position = Vector3(0, 2.2, 0)
	_chat_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_chat_label.font_size = 28
	_chat_label.outline_size = 12
	_chat_label.outline_modulate = Color.BLACK
	_chat_label.modulate = Color(1, 0.95, 0.7)
	_chat_label.visible = false
	_chat_label.no_depth_test = true
	add_child(_chat_label)

func _process(delta: float) -> void:
	match _state:
		"walking":
			_move_toward_seat(delta)
		"seated":
			_chat_timer -= delta
			if _chat_timer <= 0 and _chat_label.visible:
				_chat_label.visible = false
		"leaving":
			_move_toward_exit(delta)

func assign_seat(marker: Marker3D) -> void:
	seat_marker = marker

func serve(brew_flavors: Dictionary, menu_price: int) -> Variant:
	# 调用 TavernSettlement 结算并显示对应台词
	var ts: Node = _get_settlement()
	if ts == null or customer_data == null:
		return {}
	var result = ts.settle(brew_flavors, menu_price, customer_data)
	_show_reaction_line(result)
	return result

func show_enter_line() -> void:
	_show_line(_pick(LINES_ENTER))

func leave() -> void:
	_state = "leaving"

func _move_toward_seat(delta: float) -> void:
	if seat_marker == null:
		return
	var target: Vector3 = seat_marker.global_position
	var to: Vector3 = target - global_position
	var dist: float = to.length()
	if dist < 0.1:
		_state = "seated"
		look_at(seat_marker.global_position + Vector3(0, 0, 1))
		show_enter_line()
		return
	global_position += to.normalized() * move_speed * delta
	look_at(target)

func _move_toward_exit(delta: float) -> void:
	# 朝 +Z 方向离场（酒馆入口方向）
	var target: Vector3 = Vector3(global_position.x, 0, 8)
	var to: Vector3 = target - global_position
	if to.length() < 0.3:
		queue_free()
		return
	global_position += to.normalized() * move_speed * delta
	look_at(target)

func _show_reaction_line(result) -> void:
	var line: String = ""
	if customer_data.race_id == "human":
		match result.tier:
			"实惠赞赏": line = _pick(LINES_HUMAN_CHEAP)
			"合理接受": line = _pick(LINES_HUMAN_NORMAL)
			"昂贵抱怨": line = _pick(LINES_HUMAN_EXPENSIVE)
			"暴利拒付", "摔杯拒付": line = _pick(LINES_HUMAN_REFUSE)
	else:
		match result.tier:
			"极佳": line = _pick(LINES_PERFECT)
			"满意": line = _pick(LINES_SATISFIED)
			"一般": line = _pick(LINES_NORMAL)
			"完全不合": line = _pick(LINES_REFUSE)
	_show_line(line)

func _show_line(text: String) -> void:
	if _chat_label == null:
		return
	_chat_label.text = text
	_chat_label.visible = true
	_chat_timer = 4.0

func _pick(arr: Array) -> String:
	return arr[randi() % arr.size()]

func _get_settlement() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("TavernSettlement")
