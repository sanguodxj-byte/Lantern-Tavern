class_name TavernBrewingCoordinator
extends Node3D
## 酒馆 3D 酿酒流程总装节点（挂在 tavern.tscn 的 Brewing 节点）。
## 职责：
##   - 在玩家相机下挂载 BrewPlayerCarry（手持原料/麦汁/盛酒器/扛桶）；
##   - 在酿酒室放置 炼药锅站/原料架/倒桶台，在酒窖放置窖藏位；
##   - 场景（每天）重载后按 BrewFlowSystem 恢复炼药锅下料篮与已窖藏酒桶。
## 逻辑状态全部走 BrewFlowSystem/FermentationSystem/BrewingData。

const CAULDRON_STATION := preload("res://scenes/tavern/brewing/brew_cauldron_station.gd")
const INGREDIENT_SOURCE := preload("res://scenes/tavern/brewing/brew_ingredient_source.gd")
const BARREL_STATION := preload("res://scenes/tavern/brewing/brew_barrel_station.gd")
const CELLAR_RACK := preload("res://scenes/tavern/brewing/cellar_rack.gd")
const PLAYER_CARRY := preload("res://scenes/tavern/brewing/brew_player_carry.gd")

var carry: BrewPlayerCarry = null
var cauldron: BrewCauldronStation = null
var ingredient_source: BrewIngredientSource = null
var barrel_station: BrewBarrelStation = null
var cellar_rack: CellarRack = null

func _ready() -> void:
	add_to_group("tavern_brewing")
	# 玩家由 tavern_manager_node._ready 生成（父节点晚于子节点），延迟一帧装配。
	call_deferred("_setup")

func _setup() -> void:
	var tavern: Node = get_parent()
	# 仅在真实酒馆上下文装配（父节点标记 is_tavern；测试/编辑器挂载不装配，
	# 避免在测试根节点上误建站台与替换 carry）。
	if tavern == null or not tavern.has_meta("is_tavern"):
		return
	var player: Node = tavern.get_node_or_null("Player")
	_mount_carry(player)
	_build_stations(tavern)
	_refresh_from_flow()

func _mount_carry(player: Node) -> void:
	if carry != null and is_instance_valid(carry):
		carry.queue_free()
	carry = PLAYER_CARRY.new()
	carry.name = "BrewCarry"
	if player != null:
		var camera: Node = player.get_node_or_null("MainCamera")
		if camera != null:
			camera.add_child(carry)
			return
	player.add_child(carry) if player != null else add_child(carry)

func _build_stations(tavern: Node) -> void:
	# 酿酒室（BreweryFloor: x[-1,3] z[-8.7,-6.25]）
	cauldron = CAULDRON_STATION.new()
	cauldron.name = "BrewCauldron"
	cauldron.position = Vector3(0.6, 0, -7.8)
	add_child(cauldron)

	ingredient_source = INGREDIENT_SOURCE.new()
	ingredient_source.name = "IngredientSource"
	ingredient_source.position = Vector3(-0.5, 0, -6.6)
	add_child(ingredient_source)

	barrel_station = BARREL_STATION.new()
	barrel_station.name = "BarrelStation"
	barrel_station.position = Vector3(2.3, 0, -7.6)
	add_child(barrel_station)

	# 酒窖（CellarFloor: x[-5,3] z[-8.7,-3.55]，地板 y=-3.04）
	cellar_rack = CELLAR_RACK.new()
	cellar_rack.name = "CellarRack"
	cellar_rack.position = Vector3(2.0, -3.04, -7.2)
	add_child(cellar_rack)

	cauldron.carry = carry
	ingredient_source.carry = carry
	barrel_station.carry = carry
	cellar_rack.set_carry(carry)

## 按 BrewFlowSystem 恢复炼药锅下料篮 / 台上满桶 / 窖藏桶位。
func _refresh_from_flow() -> void:
	if cauldron != null:
		cauldron._refresh_from_flow()
	if barrel_station != null:
		barrel_station._refresh_from_flow()
	if cellar_rack != null:
		cellar_rack.refresh()
