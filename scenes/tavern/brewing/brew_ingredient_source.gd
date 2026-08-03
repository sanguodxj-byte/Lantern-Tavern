class_name BrewIngredientSource
extends StaticBody3D
## 原料架（酿酒室）：陈列酒馆仓库可用原料，玩家逐个取用为手持原料。
## 由 tavern_brewing_coordinator 放置，随 TavernManager 材料库存刷新。

const VF := preload("res://scenes/tavern/brewing/brew_visual_factory.gd")
const BD := preload("res://globals/tavern/brewing_data.gd")
const LAYER_SCENE_OBJECT := 64

const MAX_SLOTS := 6

var carry: BrewPlayerCarry = null
var status_label: Label3D = null
var slots: Array[Node] = []

func _ready() -> void:
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	_build_shelf_visual()
	_build_status_label()
	refresh_slots()
	if not Engine.is_editor_hint():
		set_process(false)

## 构建木架本体（复用 bench 体素道具作为货架）。
func _build_shelf_visual() -> void:
	var bench := VF.make_voxel_prop("bench")
	bench.scale = Vector3.ONE * 0.85
	bench.position = Vector3(0, 0.32, 0)
	add_child(bench)

func _build_status_label() -> void:
	status_label = VF.make_status_label()
	status_label.position = Vector3(0, 1.25, 0)
	status_label.font_size = 24
	add_child(status_label)

## 按库存重建原料槽（最多 MAX_SLOTS 种，按数量降序）。
func refresh_slots() -> void:
	for slot in slots:
		if is_instance_valid(slot):
			slot.queue_free()
	slots.clear()
	var inventory := _get_materials_inventory()
	var sorted_ids: Array = inventory.keys()
	sorted_ids.sort_custom(func(a, b): return int(inventory[a]) > int(inventory[b]))
	for mat_id in sorted_ids:
		if slots.size() >= MAX_SLOTS:
			break
		var count: int = int(inventory[mat_id])
		if count <= 0:
			continue
		var slot := BrewIngredientSlot.new()
		slot.name = "Slot_%s" % mat_id
		var idx: int = slots.size()
		slot.position = Vector3(-0.42 + idx * 0.17, 0.62, 0.06)
		add_child(slot)
		slot.setup(String(mat_id), self)
		slots.append(slot)
	if slots.is_empty():
		set_status(tr("仓库没有原料，白天探索收集后可用"))

func set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
		status_label.visible = true

func get_carry() -> Node:
	return carry

func _get_materials_inventory() -> Dictionary:
	var tm := _get_tavern_manager()
	if tm == null:
		return {}
	if "materials_inventory" in tm:
		return tm.materials_inventory
	return {}

func _get_tavern_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("TavernManager")
