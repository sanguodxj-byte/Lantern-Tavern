class_name BrewPlayerCarry
extends Node3D
## 玩家手持酿酒物品组件（挂在玩家相机下，跟随视角）。
## 4 种手持状态：手持原料 / 手持麦汁 / 盛酒器 / 扛桶。
## 手持物品不进入背包网格；与对应 3D 装置交互后消费；场景重载后由
## tavern_brewing_coordinator 重建（空手）。

enum CarryKind {
	NONE,
	INGREDIENT,   # 手持原料（待投入炼药锅）
	WORT,         # 手持麦汁（待倒入倒桶台）
	SERVING,      # 盛酒器（待端给顾客）
	KEG,          # 扛桶（满桶，待放入窖藏位）
}

const VF := preload("res://scenes/tavern/brewing/brew_visual_factory.gd")
const FS := preload("res://globals/tavern/fermentation_system.gd")

var kind: int = CarryKind.NONE

# INGREDIENT
var material_id: String = ""
# WORT
var wort_ingredients: Dictionary = {}
# SERVING
var serving_flavors: Dictionary = {}
var serving_price: int = 0
var serving_recipe_name: String = ""
# KEG
var keg_token: int = -1

var _visual_root: Node3D = null

# ============================================================================
# 1. 状态设置
# ============================================================================

func set_ingredient(mat_id: String) -> void:
	_clear_visual()
	kind = CarryKind.INGREDIENT
	material_id = mat_id
	_visual_root = Node3D.new()
	_visual_root.name = "CarryVisual"
	_visual_root.position = Vector3(0.0, -0.3, -0.55)
	var visual := VF.make_material_visual(mat_id)
	visual.scale = Vector3.ONE * 1.15
	_visual_root.add_child(visual)
	add_child(_visual_root)


func set_wort(ingredients: Dictionary) -> void:
	_clear_visual()
	kind = CarryKind.WORT
	wort_ingredients = ingredients.duplicate()
	_visual_root = Node3D.new()
	_visual_root.name = "CarryVisual"
	_visual_root.position = Vector3(0.0, -0.42, -0.5)
	# 木桶 + 麦汁液面
	var bucket := VF.make_voxel_prop("bucket")
	bucket.scale = Vector3.ONE * 0.9
	_visual_root.add_child(bucket)
	var liquid := VF.make_liquid_box(0.30, 0.05, 0.30, Color(0.82, 0.55, 0.22, 0.9))
	liquid.position = Vector3(0.0, 0.28, 0.0)
	_visual_root.add_child(liquid)
	add_child(_visual_root)


func set_serving(flavors: Dictionary, price: int, recipe_name: String = "") -> void:
	_clear_visual()
	kind = CarryKind.SERVING
	serving_flavors = flavors.duplicate()
	serving_price = price
	serving_recipe_name = recipe_name
	_visual_root = Node3D.new()
	_visual_root.name = "CarryVisual"
	_visual_root.position = Vector3(0.0, -0.34, -0.5)
	# 木酒杯 + 啤酒泡沫
	var tankard := VF.make_voxel_prop("tankard")
	tankard.scale = Vector3.ONE * 1.1
	_visual_root.add_child(tankard)
	var foam := VF.make_liquid_box(0.24, 0.04, 0.2, Color(1.0, 0.85, 0.5, 0.95))
	foam.position = Vector3(0.0, 0.26, 0.0)
	_visual_root.add_child(foam)
	add_child(_visual_root)


func set_keg(token: int) -> void:
	_clear_visual()
	kind = CarryKind.KEG
	keg_token = token
	_visual_root = Node3D.new()
	_visual_root.name = "CarryVisual"
	_visual_root.position = Vector3(0.0, -0.45, -0.55)
	var barrel := VF.make_voxel_prop("barrel")
	barrel.scale = Vector3.ONE * 0.9
	_visual_root.add_child(barrel)
	add_child(_visual_root)


func clear() -> void:
	_clear_visual()
	kind = CarryKind.NONE
	material_id = ""
	wort_ingredients.clear()
	serving_flavors.clear()
	serving_price = 0
	serving_recipe_name = ""
	keg_token = -1


func _clear_visual() -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.queue_free()
	_visual_root = null

# ============================================================================
# 2. 查询
# ============================================================================

func is_holding() -> bool:
	return kind != CarryKind.NONE

func is_ingredient() -> bool:
	return kind == CarryKind.INGREDIENT

func is_wort() -> bool:
	return kind == CarryKind.WORT

func is_serving() -> bool:
	return kind == CarryKind.SERVING

func is_keg() -> bool:
	return kind == CarryKind.KEG

## 手持状态名（用于交互提示）
func get_kind_name() -> String:
	match kind:
		CarryKind.INGREDIENT: return tr("手持原料")
		CarryKind.WORT: return tr("手持麦汁")
		CarryKind.SERVING: return tr("盛酒器")
		CarryKind.KEG: return tr("扛着酒桶")
	return tr("空手")
