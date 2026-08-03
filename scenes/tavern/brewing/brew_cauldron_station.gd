class_name BrewCauldronStation
extends StaticBody3D
## 炼药锅站（酿酒室 3D 装置，中世纪三足圆肚铁锅）。
## 投料：玩家手持原料与炼药锅交互 → 原料投入锅中（多份叠加可见）；
## 蒸煮：3D 可视化状态机（加热→沸腾→蒸汽粒子随进度增强→完成），进度实时可见；
## 取麦汁：蒸煮完成后交互取出麦汁（手持麦汁），供倒入倒桶台。
## 逻辑状态由 BrewFlowSystem autoload 持有，本节点只做 3D 呈现与交互。

const FS := preload("res://globals/tavern/fermentation_system.gd")
const BFS := preload("res://globals/tavern/brew_flow_system.gd")
const VF := preload("res://scenes/tavern/brewing/brew_visual_factory.gd")
const LAYER_SCENE_OBJECT := 64

## 炼药锅视觉
var cauldron_visual: VoxelProp
var liquid_box: MeshInstance3D
var ingredient_stack_root: Node3D
var steam_particles: GPUParticles3D
var fire_particles: GPUParticles3D
var fire_light: OmniLight3D
var status_label: Label3D

## 玩家手持组件（由 coordinator/setup 注入）
var carry: BrewPlayerCarry = null

var _stack_visuals: Array[Node3D] = []
var _basket_snapshot: Dictionary = {}

const STACK_VISUAL_CAP := 10
const POT_TOP_Y := 0.72

func _ready() -> void:
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	_build_visual()
	_build_interact_collision()
	_refresh_from_flow()
	if not Engine.is_editor_hint():
		set_process(true)

## 构建体素炼药锅本体 + 动态液体/蒸汽/火焰/标签。
func _build_visual() -> void:
	cauldron_visual = VF.make_voxel_prop("brew_cauldron")
	add_child(cauldron_visual)

	liquid_box = VF.make_liquid_box(0.78, 0.08, 0.64, Color(0.72, 0.42, 0.16, 0.9))
	liquid_box.position = Vector3(0, POT_TOP_Y, 0)
	liquid_box.visible = false
	add_child(liquid_box)

	ingredient_stack_root = Node3D.new()
	ingredient_stack_root.name = "IngredientStack"
	add_child(ingredient_stack_root)

	steam_particles = VF.make_steam_particles()
	steam_particles.position = Vector3(0, 1.35, 0)
	add_child(steam_particles)

	fire_particles = VF.make_fire_particles()
	fire_particles.position = Vector3(0, 0.12, 0)
	add_child(fire_particles)

	fire_light = VF.make_fire_light()
	fire_light.position = Vector3(0, 0.3, 0)
	add_child(fire_light)

	status_label = VF.make_status_label()
	status_label.position = Vector3(0, 1.55, 0)
	add_child(status_label)


func _build_interact_collision() -> void:
	var col := CollisionShape3D.new()
	col.name = "InteractShape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 1.5, 1.1)
	col.shape = shape
	col.position = Vector3(0, 0.75, 0)
	add_child(col)

# ============================================================================
# 交互
# ============================================================================

var interaction_name: String = "炼药锅"
var interaction_verb: String = "投入原料"


func can_interact() -> bool:
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return false
	var carrying_ingredient: bool = carry != null and carry.is_ingredient() \
		and bfs.can_add_ingredient()
	var ready_for_wort: bool = bfs.cauldron_state == BFS.CauldronState.READY \
		and (carry == null or not carry.is_holding())
	return carrying_ingredient or ready_for_wort


func interact(_source_player: Node = null) -> void:
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return
	if carry != null and carry.is_ingredient():
		if not bfs.can_add_ingredient():
			_set_status(tr("炼药锅里已有熟麦汁，先取出"))
			return
		var mat_id: String = carry.material_id
		if bfs.add_to_cauldron(mat_id):
			carry.clear()
			_refresh_basket_visual()
			# 投料后自动开火蒸煮
			if bfs.cauldron_basket.size() > 0 and bfs.cauldron_state == BFS.CauldronState.IDLE:
				bfs.start_boiling()
		return
	if bfs.cauldron_state == BFS.CauldronState.READY \
		and (carry == null or not carry.is_holding()):
		var ingredients: Dictionary = bfs.cauldron_basket.duplicate()
		if bfs.take_wort():
			if carry != null:
				carry.set_wort(ingredients)
			_set_status(tr("已取出麦汁，倒入倒桶台"))
		return

# ============================================================================
# 每帧：推进蒸煮 + 同步视觉
# ============================================================================

func _process(delta: float) -> void:
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return
	bfs.tick_boil(delta)
	_sync_boil_visuals()


## 同步炼药锅 3D 状态（状态/液体/蒸汽/火焰/进度标签）。
func _sync_boil_visuals() -> void:
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return
	match bfs.cauldron_state:
		BFS.CauldronState.IDLE:
			fire_particles.emitting = false
			fire_light.visible = false
			steam_particles.emitting = false
			liquid_box.visible = not bfs.cauldron_basket.is_empty()
			liquid_box.position.y = POT_TOP_Y
			if bfs.cauldron_basket.is_empty():
				_set_status(tr("在原料架取原料，投入炼药锅开酿"))
			else:
				_set_status(tr("原料已入锅"))
		BFS.CauldronState.BOILING:
			fire_particles.emitting = true
			fire_light.visible = true
			steam_particles.emitting = true
			steam_particles.amount = int(8 + 16 * bfs.boil_progress)
			liquid_box.visible = true
			liquid_box.position.y = POT_TOP_Y + 0.03 * bfs.boil_progress
			_set_status(tr("蒸煮 %d%%") % int(bfs.boil_progress * 100.0))
		BFS.CauldronState.READY:
			fire_particles.emitting = false
			fire_light.visible = false
			steam_particles.emitting = false
			liquid_box.visible = true
			liquid_box.position.y = POT_TOP_Y
			_set_status(tr("麦汁已熟，交互取麦汁"))


func _refresh_from_flow() -> void:
	_refresh_basket_visual()
	_sync_boil_visuals()


## 锅内原料堆叠视觉：按下料篮重建（复用材料模型/回退色块，最多显示 10 份）。
func _refresh_basket_visual() -> void:
	for visual in _stack_visuals:
		if is_instance_valid(visual):
			visual.queue_free()
	_stack_visuals.clear()
	var bfs := _get_brew_flow_system()
	if bfs == null:
		return
	var index := 0
	for mat_id in bfs.cauldron_basket:
		var count: int = int(bfs.cauldron_basket[mat_id])
		for _i in range(count):
			if index >= STACK_VISUAL_CAP:
				return
			var visual := VF.make_material_visual(String(mat_id))
			visual.scale = Vector3.ONE * 0.55
			var offset := _stack_offset(index)
			visual.position = Vector3(offset.x, POT_TOP_Y - 0.02 + offset.y, offset.z)
			ingredient_stack_root.add_child(visual)
			_stack_visuals.append(visual)
			index += 1


func _stack_offset(index: int) -> Vector3:
	var slot := index % 5
	var layer := index / 5
	var positions := [
		Vector3(0.18, 0, 0.12),
		Vector3(-0.18, 0, -0.12),
		Vector3(0.18, 0, -0.12),
		Vector3(-0.18, 0, 0.12),
		Vector3(0, 0, 0.16),
	]
	return positions[slot] + Vector3(0, layer * 0.07, 0)


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
		status_label.visible = true

func _get_brew_flow_system() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("BrewFlowSystem")
