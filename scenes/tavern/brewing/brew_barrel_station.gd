class_name BrewBarrelStation
extends StaticBody3D
## 倒桶台（酿酒室）：玩家把麦汁倒入空酒桶（液面随倒入上升），
## 装满后扛起酒桶搬运到酒窖窖藏位。
## 逻辑状态（酒桶 token / 装满标记）由 BrewFlowSystem autoload 持有。

const FS := preload("res://globals/tavern/fermentation_system.gd")
const VF := preload("res://scenes/tavern/brewing/brew_visual_factory.gd")
const LAYER_SCENE_OBJECT := 64

var carry: BrewPlayerCarry = null

## 桶内液面（0..1）
var fill_level: float = 0.0
## 当前已装桶的 token；-1 = 台上无桶
var keg_token: int = -1

var barrel_visual: VoxelProp = null
var liquid_box: MeshInstance3D = null
var status_label: Label3D = null

func _ready() -> void:
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	_build_visual()
	_build_interact_collision()
	_refresh_from_flow()

func _build_visual() -> void:
	barrel_visual = VF.make_voxel_prop("barrel")
	add_child(barrel_visual)
	liquid_box = VF.make_liquid_box(0.34, 0.02, 0.34, Color(0.78, 0.45, 0.18, 0.95))
	liquid_box.position = Vector3(0, 0.28, 0)
	liquid_box.visible = false
	add_child(liquid_box)
	status_label = VF.make_status_label()
	status_label.position = Vector3(0, 1.05, 0)
	add_child(status_label)

func _build_interact_collision() -> void:
	var col := CollisionShape3D.new()
	col.name = "InteractShape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.1, 0.9)
	col.shape = shape
	col.position = Vector3(0, 0.55, 0)
	add_child(col)

# ============================================================================
# 交互
# ============================================================================

var interaction_name: String = "倒桶台"


func can_interact() -> bool:
	var pouring: bool = carry != null and carry.is_wort() and fill_level < 1.0
	var lifting: bool = fill_level >= 1.0 and (carry == null or not carry.is_holding())
	return pouring or lifting


func interact(_source_player: Node = null) -> void:
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return
	if carry != null and carry.is_wort() and fill_level < 1.0:
		_pour_wort()
		return
	if fill_level >= 1.0 and (carry == null or not carry.is_holding()):
		_lift_keg()
		return


## 倒入麦汁：液面升满（一锅麦汁 = 一桶）。
func _pour_wort() -> void:
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return
	var ingredients: Dictionary = carry.wort_ingredients.duplicate()
	var token: int = bfs.register_filled_keg(ingredients)
	if token < 0:
		return
	keg_token = token
	fill_level = 1.0
	carry.clear()
	_sync_fill_visual(true)
	set_status(tr("酒桶已装满，扛起搬到酒窖"))


## 扛起满桶：交还给玩家手持（酒桶 token 保留）。
func _lift_keg() -> void:
	var bfs := _get_brew_flow_system()
	if bfs == null or keg_token < 0:
		return
	var keg = bfs.find_keg(keg_token)
	if keg == null:
		return
	if carry != null:
		carry.set_keg(keg_token)
	keg_token = -1
	fill_level = 0.0
	_sync_fill_visual(false)
	set_status(tr("已扛起酒桶，前往酒窖窖藏位"))


## 恢复场景状态（场景重载后由 coordinator 调用）：
## 若存在尚未窖藏的已装桶，则台上重新出现满桶。
func _refresh_from_flow() -> void:
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return
	for keg in bfs.active_kegs:
		if keg.keg_index < 0 and fill_level < 1.0:
			keg_token = keg.token
			fill_level = 1.0
			break
	_sync_fill_visual(fill_level >= 1.0)

func _sync_fill_visual(filled: bool) -> void:
	if liquid_box != null:
		liquid_box.visible = filled
	if barrel_visual != null:
		barrel_visual.visible = true

func set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
		status_label.visible = true

func _get_brew_flow_system() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("BrewFlowSystem")
