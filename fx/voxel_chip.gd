class_name VoxelChip
extends Node3D

## 体素碎屑：被击部位表面的小方块碎片飞溅，颜色 = 该部位体素本色。
## 配合 BodyPartResolver + VoxelPalette 实现"被击部位体素纹理相关"特效。

## 配置色：fx_helper 在 add_child 之前先 setup()，_ready 发射前先应用它，消除首帧白色闪现。
var _color := Color.WHITE

func _chip_node() -> GPUParticles3D:
	return get_node_or_null("Chips") as GPUParticles3D

func setup(hit_pos: Vector3, color: Color) -> void:
	# setup() is intentionally called before add_child() so the particle color is
	# ready on its first rendered frame. Positioning is only legal once inside
	# the scene tree; FxHelper applies the world position after insertion.
	if is_inside_tree():
		global_position = hit_pos
	_color = color
	_apply_color(color)

func _apply_color(c: Color) -> void:
	var chips := _chip_node()
	if chips == null or chips.process_material == null:
		return
	chips.process_material.color = c

func _ready() -> void:
	# 先应用已配置颜色（入树前已由 setup 设定），再发射，避免首帧白色闪现。
	_apply_color(_color)
	var chips := _chip_node()
	if chips != null:
		chips.emitting = true
		chips.finished.connect(queue_free)
