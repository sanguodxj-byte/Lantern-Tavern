class_name CellarRack
extends StaticBody3D
## 窖藏位（酒窖）：一组酒桶桶位，每个桶位由 CellarRackSlot 承载。
## 桶位数与 FermentationSystem 的发酵桶位对齐（Lv1 = 1 桶，上限 2 个物理槽位）。
## 场景重载后由 coordinator 调用 refresh() 恢复已窖藏的酒桶。

const FS := preload("res://globals/tavern/fermentation_system.gd")
const VF := preload("res://scenes/tavern/brewing/brew_visual_factory.gd")
const LAYER_SCENE_OBJECT := 64

const MAX_PHYSICAL_SLOTS := 2

var carry: BrewPlayerCarry = null
var slots: Array[Node] = []

func _ready() -> void:
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	_build_rack_visual()
	_build_slots()

func _build_rack_visual() -> void:
	# 木架：双 bench 叠放（下层承重、上层承桶）
	var lower := VF.make_voxel_prop("bench")
	lower.scale = Vector3.ONE * 0.8
	lower.position = Vector3(0, 0.28, 0)
	add_child(lower)

func _build_slots() -> void:
	var fs := _get_fermentation_system()
	var slot_count: int = 1
	if fs != null and "max_kegs" in fs:
		slot_count = clampi(int(fs.max_kegs), 1, MAX_PHYSICAL_SLOTS)
	for i in range(slot_count):
		var slot := CellarRackSlot.new()
		slot.name = "Slot_%d" % i
		slot.position = Vector3(0, 0.25, i * 1.35)
		add_child(slot)
		slot.carry = carry
		slots.append(slot)

func set_carry(node: BrewPlayerCarry) -> void:
	carry = node
	for slot in slots:
		if slot != null:
			slot.carry = node

## 场景重载后恢复：把 BrewFlowSystem 中已窖藏的酒桶映射回桶位。
func refresh() -> void:
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return
	for slot in slots:
		if slot == null:
			continue
		slot.token = -1
	for keg in bfs.active_kegs:
		if keg.keg_index < 0 or keg.keg_index >= slots.size():
			continue
		var slot: CellarRackSlot = slots[keg.keg_index]
		slot.token = keg.token
		slot.rack = self
		slot._sync_visual()

func get_slot_count() -> int:
	return slots.size()

func _get_fermentation_system() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("FermentationSystem")

func _get_brew_flow_system() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("BrewFlowSystem")
