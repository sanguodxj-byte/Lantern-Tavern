extends Control
## 出发探险提示：屏幕中心环形进度条 + "出发"文字。
## 玩家在酒馆内按住 F 键累积进度，松开重置；满进度后跳转区域选择→地牢。
## 仅在酒馆场景且白天探险阶段显示判定。

const HOLD_DURATION: float = 2.0  # 按住 F 持续时间（秒）

@onready var ring: TextureProgressBar = $RingCenter/RingProgress
@onready var depart_text: Label = $RingCenter/DepartText

var hold_time: float = 0.0
var is_complete: bool = false

func _ready() -> void:
	# 默认隐藏，仅按住 F 时显示
	visible = false
	ring.value = 0.0

func _process(delta: float) -> void:
	if is_complete:
		return
	# 仅酒馆白天探险阶段响应
	if not _is_in_tavern_day_phase():
		visible = false
		hold_time = 0.0
		ring.value = 0.0
		return
	# 按住 F 累积进度
	if Input.is_action_pressed("kick"):
		visible = true
		hold_time += delta
		ring.value = clampf(hold_time / HOLD_DURATION, 0.0, 1.0)
		if hold_time >= HOLD_DURATION:
			_on_progress_complete()
	else:
		# 松开重置
		if hold_time > 0.0:
			hold_time = 0.0
			ring.value = 0.0
		visible = false

## 进度满：跳转区域选择界面
func _on_progress_complete() -> void:
	is_complete = true
	depart_text.text = "出发!"
	# 延迟 0.3 秒让玩家看到满进度反馈
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/ui/zone_select.tscn")

## 判定当前是否在酒馆场景且白天探险阶段
func _is_in_tavern_day_phase() -> bool:
	var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	if tm == null:
		return false
	return tm.current_phase == tm.Phase.DAY_EXPEDITION
