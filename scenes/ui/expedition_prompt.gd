extends Control
## 出发探险提示：屏幕中心环形进度条 + "出发"文字。
## 玩家在酒馆内按住 depart 输入累积进度，松开重置；满进度后跳转区域选择→地牢。
## 仅在酒馆场景且白天探险阶段显示判定。

const HOLD_DURATION: float = 2.0  # 按住出发键持续时间（秒）
const DEPART_ACTION := "depart"

## 环形纹理参数
const RING_TEX_SIZE := 128
const RING_OUTER_RADIUS := 60.0
const RING_THICKNESS := 12.0

@onready var ring: TextureProgressBar = $RingCenter/RingProgress
@onready var depart_text: Label = $RingCenter/DepartText

var hold_time: float = 0.0
var is_complete: bool = false

func _ready() -> void:
	visible = false
	# 程序化生成环形纹理，替代外部图标资源
	var ring_tex := _create_ring_texture()
	ring.texture_under = ring_tex
	ring.texture_progress = ring_tex
	ring.value = 0.0

## 生成一张带抗锯齿边缘的环形（圆环）白色纹理。
## 配合 TextureProgressBar 的 radial_fill 实现扇形进度填充效果。
func _create_ring_texture() -> ImageTexture:
	var image := Image.create(RING_TEX_SIZE, RING_TEX_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(RING_TEX_SIZE / 2.0, RING_TEX_SIZE / 2.0)
	var outer_r := RING_OUTER_RADIUS
	var inner_r := outer_r - RING_THICKNESS
	for y in range(RING_TEX_SIZE):
		for x in range(RING_TEX_SIZE):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			# 硬边缘像素风填充，不使用任何抗锯齿渐变
			if d >= inner_r and d <= outer_r:
				image.set_pixel(x, y, Color(1, 1, 1, 1.0))
	return ImageTexture.create_from_image(image)

func _process(delta: float) -> void:
	if is_complete:
		return
	# 仅酒馆白天探险阶段响应
	if not _is_in_tavern_day_phase():
		visible = false
		hold_time = 0.0
		ring.value = 0.0
		return
	# 按住独立出发键累积进度，F/G 保留给技能栏。
	if Input.is_action_pressed(DEPART_ACTION):
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
	depart_text.text = tr("Depart!")
	# 延迟 0.3 秒让玩家看到满进度反馈
	await get_tree().create_timer(0.3).timeout
	var world := _find_world()
	if world != null and world.has_method("open_zone_select"):
		world.call("open_zone_select")
	else:
		get_tree().change_scene_to_file("res://scenes/ui/zone_select.tscn")

## 判定当前是否在酒馆场景且白天探险阶段
func _is_in_tavern_day_phase() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var tm: Node = tree.root.get_node_or_null("TavernManager")
	if tm == null:
		return false
	return tm.current_phase == tm.Phase.DAY_EXPEDITION

func _find_world() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("load_space") and node.has_method("open_zone_select"):
			return node
		node = node.get_parent()
	return null
