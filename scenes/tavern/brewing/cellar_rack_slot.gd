class_name CellarRackSlot
extends StaticBody3D
## 窖藏位上的单个桶位：放桶（开始发酵计时）→ 状态显示（发酵中/已熟成）→ 开缸取酒。
## 发酵状态机走 FermentationSystem（BrewFlowSystem 中转），本节点只做 3D 呈现与交互。

const FS := preload("res://globals/tavern/fermentation_system.gd")
const BFS := preload("res://globals/tavern/brew_flow_system.gd")
const BD := preload("res://globals/tavern/brewing_data.gd")
const VF := preload("res://scenes/tavern/brewing/brew_visual_factory.gd")
const LAYER_SCENE_OBJECT := 64

## 当前占用本桶位的酒桶 token；-1 = 空位
var token: int = -1
var carry: BrewPlayerCarry = null
var rack: Node = null

var barrel_visual: VoxelProp = null
var status_label: Label3D = null

func _ready() -> void:
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	_build_visual()
	_build_interact_collision()
	_sync_visual()

func _build_visual() -> void:
	barrel_visual = VF.make_voxel_prop("barrel")
	barrel_visual.position = Vector3(0, 0.55, 0)
	barrel_visual.visible = false
	add_child(barrel_visual)
	status_label = VF.make_status_label()
	status_label.position = Vector3(0, 1.45, 0)
	status_label.font_size = 22
	add_child(status_label)

func _build_interact_collision() -> void:
	var col := CollisionShape3D.new()
	col.name = "InteractShape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.4, 0.8)
	col.shape = shape
	col.position = Vector3(0, 0.7, 0)
	add_child(col)

# ============================================================================
# 交互
# ============================================================================

var interaction_name: String = "窖藏位"


func can_interact() -> bool:
	var placing: bool = carry != null and carry.is_keg() and token < 0
	var opening: bool = token >= 0 and _can_open()
	return placing or opening


func interact(_source_player: Node = null) -> void:
	if carry != null and carry.is_keg() and token < 0:
		_place_keg()
		return
	if token >= 0 and _can_open():
		_open_keg()
		return


## 放桶：接入 FermentationSystem 发酵计时（BrewFlowSystem.place_keg_on_rack）。
func _place_keg() -> void:
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return
	var carried_token: int = carry.keg_token
	var day: int = _get_current_day()
	if not bfs.place_keg_on_rack(carried_token, day):
		set_status(tr("发酵桶位已满，先开缸腾位"))
		return
	token = carried_token
	carry.clear()
	bfs.sync_keg_state(token)
	_sync_visual()
	set_status(tr("已窖藏，发酵中（明日熟成）"))


## 开缸取酒：拿到盛酒器（口味 + 菜单标价），供端给顾客。
func _open_keg() -> void:
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return
	var flavors: Dictionary = bfs.open_rack_keg(token)
	if flavors.is_empty():
		return
	token = -1
	var price: int = _menu_price_for(flavors)
	var recipe_name: String = ""
	if flavors.has("__recipe_id__"):
		recipe_name = BD.get_recipe_name(String(flavors["__recipe_id__"]))
	flavors.erase("__recipe_id__")
	if carry != null:
		carry.set_serving(flavors, price, recipe_name)
	_sync_visual()
	set_status(tr("开缸取酒，端给顾客"))


## 菜单标价：匹配酒谱的人类标价，无标价/自定义组合用默认基准价。
func _menu_price_for(flavors: Dictionary) -> int:
	var recipe_id: String = String(flavors.get("__recipe_id__", ""))
	if not recipe_id.is_empty():
		var recipe: Dictionary = BD.RECIPES_DB.get(recipe_id, {})
		var price: Variant = recipe.get("price", null)
		if price != null and int(price) > 0:
			return int(price)
	return 30

# ============================================================================
# 状态同步
# ============================================================================

func _can_open() -> bool:
	var bfs := _get_brew_flow_system()
	if bfs == null or token < 0:
		return false
	bfs.sync_keg_state(token)
	var keg = bfs.find_keg(token)
	if keg == null:
		return false
	_sync_visual()
	return keg.state == FS.KegState.READY or keg.state == FS.KegState.AGING or keg.state == FS.KegState.AGED


## 同步桶位视觉：酒桶出现/消失 + 状态文字。
func _sync_visual() -> void:
	var bfs := _get_brew_flow_system()
	var occupied: bool = token >= 0
	if barrel_visual != null:
		barrel_visual.visible = occupied
	if not occupied:
		if status_label != null:
			status_label.text = tr("空位：放入满桶窖藏")
			status_label.visible = true
		return
	var status_text := tr("发酵中")
	if bfs != null:
		bfs.sync_keg_state(token)
		var keg = bfs.find_keg(token)
		if keg != null:
			match keg.state:
				FS.KegState.FERMENTING: status_text = tr("发酵中（明日熟成）")
				FS.KegState.READY: status_text = tr("已熟成，交互开缸")
				FS.KegState.AGING: status_text = tr("陈酿中 %d/%d") % [keg.aging_days, FS.AGING_MAX_DAYS]
				FS.KegState.AGED: status_text = tr("陈酿封顶，交互开缸")
	if status_label != null:
		status_label.text = status_text
		status_label.visible = true


func set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
		status_label.visible = true

func _get_brew_flow_system() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("BrewFlowSystem")

func _get_current_day() -> int:
	var tm := _get_tavern_manager()
	if tm == null:
		return 1
	if "day" in tm:
		return int(tm.day)
	return 1

func _get_tavern_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("TavernManager")
