extends Node

const BLOOD_SPURT_PREFAB := preload("res://fx/blood_spurt.tscn")
const METAL_SPARK_PREFAB := preload("res://fx/metal_spark.tscn")
const DAMAGE_NUMBER_PREFAB := preload("res://fx/damage_number.tscn")
const VOXEL_CHIP_PREFAB := preload("res://fx/voxel_chip.tscn")
const DamageNumberScript := preload("res://fx/damage_number.gd")

func create_metal_spark(spark_position: Vector3) -> void:
	var parent := _fx_parent()
	if parent == null:
		return
	var spark := METAL_SPARK_PREFAB.instantiate()
	parent.add_child(spark)
	spark.global_position = spark_position

func create_blood_fx(blood_transform: Transform3D, show_sparks : bool = true) -> void:
	var parent := _fx_parent()
	if parent == null:
		return
	var blood := BLOOD_SPURT_PREFAB.instantiate()
	blood.is_sparks_shown = show_sparks
	parent.add_child(blood)
	blood.global_transform = blood_transform


## 在命中点生成体素碎屑，颜色由被击部位的体素本色决定（"被击部位体素纹理相关"）。
func create_voxel_chip(hit_pos: Vector3, color: Color) -> Node3D:
	var parent := _fx_parent()
	if parent == null:
		return null
	var chip: Node3D = VOXEL_CHIP_PREFAB.instantiate() as Node3D
	if chip == null:
		return null
	# 先配置颜色再入树：voxel_chip._ready 会在发射前应用该颜色，避免白色首帧闪现。
	if chip.has_method("setup"):
		chip.call("setup", hit_pos, color)
	parent.add_child(chip)
	chip.global_position = hit_pos  # 入树后按世界坐标校正位置
	return chip


## 在世界坐标生成伤害/治疗飘字（永久面向摄像机，像素字体）。
## kind 使用 DamageNumber.Kind；也可用 create_damage_number_flags 按标志选择样式。
func create_damage_number(world_pos: Vector3, amount: int, kind: int = 0) -> Node3D:
	var parent := _fx_parent()
	if parent == null:
		return null
	var node: Node3D = DAMAGE_NUMBER_PREFAB.instantiate() as Node3D
	if node == null:
		return null
	parent.add_child(node)
	node.global_position = world_pos + Vector3(0.0, DamageNumberScript.VERTICAL_SPAWN_OFFSET, 0.0)
	if node.has_method("setup"):
		node.call("setup", amount, kind)
	return node


func create_damage_number_flags(world_pos: Vector3, amount: int, is_crit: bool = false, is_heal: bool = false, is_block: bool = false, is_miss: bool = false) -> Node3D:
	var kind: int = DamageNumberScript.kind_from_flags(is_crit, is_heal, is_block, is_miss)
	return create_damage_number(world_pos, amount, kind)


func create_heal_number(world_pos: Vector3, amount: int) -> Node3D:
	return create_damage_number(world_pos, amount, DamageNumberScript.Kind.HEAL)


func create_block_number(world_pos: Vector3, amount: int = 0) -> Node3D:
	return create_damage_number(world_pos, amount, DamageNumberScript.Kind.BLOCK)


func _fx_parent() -> Node:
	if GameState != null and is_instance_valid(GameState.current_level) and GameState.current_level.is_inside_tree():
		return GameState.current_level
	var tree := get_tree()
	if tree != null and tree.current_scene != null and tree.current_scene.is_inside_tree():
		return tree.current_scene
	return self
