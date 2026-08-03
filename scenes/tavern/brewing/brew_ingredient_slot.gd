class_name BrewIngredientSlot
extends StaticBody3D
## 原料架上的单个原料槽：展示一种材料的库存并响应"取用"交互。
## 交互成功后从酒馆仓库扣减 1 份，并交给玩家手持（BrewPlayerCarry）。

const VF := preload("res://scenes/tavern/brewing/brew_visual_factory.gd")
const BD := preload("res://globals/tavern/brewing_data.gd")
const LAYER_SCENE_OBJECT := 64

var material_id: String = ""
var source: Node = null  # BrewIngredientSource 引用（刷新用）

var interaction_name: String = "原料"
var interaction_verb: String = "取用"

var _visual: Node3D = null
var _count_label: Label3D = null
func _ready() -> void:
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	_build_visual()
	_build_interact_collision()

func setup(mat_id: String, owner: Node) -> void:
	material_id = mat_id
	source = owner
	interaction_verb = tr("取用 %s") % BD.get_material_name(mat_id)
	_build_visual()
	refresh()

func _build_visual() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = VF.make_material_visual(material_id)
	_visual.scale = Vector3.ONE * 0.85
	add_child(_visual)
	_count_label = VF.make_status_label()
	_count_label.font_size = 22
	_count_label.position = Vector3(0, 0.42, 0)
	add_child(_count_label)

func _build_interact_collision() -> void:
	var col := CollisionShape3D.new()
	col.name = "InteractShape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.34, 0.34, 0.34)
	col.shape = shape
	add_child(col)

## 刷新库存数量显示；库存为 0 时隐藏本槽。
func refresh() -> void:
	var inventory: Dictionary = _get_materials_inventory()
	var count: int = int(inventory.get(material_id, 0))
	if count <= 0:
		visible = false
		return
	visible = true
	if _count_label != null:
		_count_label.text = tr("%s ×%d") % [BD.get_material_name(material_id), count]

# ============================================================================
# 交互
# ============================================================================


func can_interact() -> bool:
	var carry := _get_carry()
	if carry != null and carry.is_holding():
		return false
	return int(_get_materials_inventory().get(material_id, 0)) > 0


func interact(_source_player: Node = null) -> void:
	var carry := _get_carry()
	if carry != null and carry.is_holding():
		_set_status(tr("先把手中物品放下或用掉"))
		return
	var tm := _get_tavern_manager()
	if tm == null:
		return
	if not tm.remove_from_inventory(material_id, 1):
		_set_status(tr("仓库没有足够的%s") % BD.get_material_name(material_id))
		return
	if carry != null:
		carry.set_ingredient(material_id)
	if source != null and source.has_method("refresh_slots"):
		source.refresh_slots()
	_set_status(tr("取用 %s（投到炼药锅蒸煮）") % BD.get_material_name(material_id))

func _set_status(text: String) -> void:
	if source != null and source.has_method("set_status"):
		source.set_status(text)

func _get_materials_inventory() -> Dictionary:
	var tm := _get_tavern_manager()
	if tm == null:
		return {}
	if "materials_inventory" in tm:
		return tm.materials_inventory
	return {}

func _get_carry() -> Node:
	if source != null and source.has_method("get_carry"):
		return source.get_carry()
	return null

func _get_tavern_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("TavernManager")
