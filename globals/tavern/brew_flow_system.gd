extends Node
## 3D 酿酒流程状态中枢（autoload: BrewFlowSystem）。
## 承载全 3D 酿造链路的跨场景状态：锅炉投料篮/蒸煮状态机、麦汁、
## 已装桶的酒桶（待搬运/已窖藏），并把窖藏桶位接回现有 FermentationSystem 的
## Keg 状态机与 BrewingData（策划案 09/10/11/12/13）。
## 仅保存逻辑状态；3D 视觉由酒馆场景内的 tavern_brewing_coordinator 重建。

const FS := preload("res://globals/tavern/fermentation_system.gd")

# ============================================================================
# 1. 锅炉状态机（策划案 10：蒸煮阶段）
# ============================================================================

enum CauldronState {
	IDLE,     # 空锅/可投料
	BOILING,  # 蒸煮中（加热→沸腾→蒸汽粒子随进度增强）
	READY,    # 蒸煮完成，麦汁可取出
}

const BOIL_DURATION_SEC := 20.0  # 一锅蒸煮时长（秒）

# 下料篮：{material_id: count}
var cauldron_basket: Dictionary = {}
var cauldron_state: int = CauldronState.IDLE
var boil_progress: float = 0.0

# ============================================================================
# 2. 已装桶酒桶（倒桶台装满 → 酒窖窖藏位）
# ============================================================================

class ActiveKeg:
	var token: int = -1            # 本系统内的唯一标识（倒桶台生成）
	var ingredients: Dictionary = {} # 下料篮材料组合（交给 FermentationSystem）
	var keg_index: int = -1        # 窖藏后对应的 FermentationSystem 桶位；-1 = 尚未窖藏
	var state: int = FS.KegState.EMPTY  # 镜像 FermentationSystem 桶状态

var active_kegs: Array[ActiveKeg] = []
var _next_token: int = 0

# ============================================================================
# 3. 锅炉操作
# ============================================================================

## 向锅炉投入一份原料。返回 true 表示投入成功。
## 锅炉 READY 时不能投料（必须先取走麦汁）。
func add_to_cauldron(material_id: String) -> bool:
	if material_id.is_empty():
		return false
	if cauldron_state == CauldronState.READY:
		return false
	cauldron_basket[material_id] = int(cauldron_basket.get(material_id, 0)) + 1
	return true

## 启动蒸煮。要求下料篮非空且锅炉未在蒸煮。
func start_boiling() -> bool:
	if cauldron_basket.is_empty():
		return false
	if cauldron_state == CauldronState.BOILING:
		return false
	cauldron_state = CauldronState.BOILING
	boil_progress = 0.0
	return true

## 推进蒸煮进度（由 3D 锅炉站每帧调用）。
## 进度到达 1.0 后转为 READY。
func tick_boil(delta: float) -> void:
	if cauldron_state != CauldronState.BOILING:
		return
	boil_progress = minf(1.0, boil_progress + delta / BOIL_DURATION_SEC)
	if boil_progress >= 1.0:
		cauldron_state = CauldronState.READY

## 取走麦汁：锅炉 READY 时返回 true 并清空锅炉。
func take_wort() -> bool:
	if cauldron_state != CauldronState.READY:
		return false
	cauldron_basket.clear()
	cauldron_state = CauldronState.IDLE
	boil_progress = 0.0
	return true

## 查询是否可继续投料（READY 时必须先取麦汁）
func can_add_ingredient() -> bool:
	return cauldron_state != CauldronState.READY

# ============================================================================
# 4. 酒桶生命周期（倒桶台 → 窖藏位 → 开缸）
# ============================================================================

## 倒桶台装满后登记一桶待搬运麦汁桶。返回 token（-1 表示失败）。
func register_filled_keg(ingredients: Dictionary) -> int:
	if ingredients.is_empty():
		return -1
	var keg := ActiveKeg.new()
	keg.token = _next_token
	_next_token += 1
	keg.ingredients = ingredients.duplicate()
	keg.keg_index = -1
	keg.state = FS.KegState.EMPTY
	active_kegs.append(keg)
	return keg.token

## 按 token 查找酒桶（无则返回 null）。
func find_keg(token: int) -> ActiveKeg:
	for keg in active_kegs:
		if keg.token == token:
			return keg
	return null

## 把满桶放到窖藏位：接入 FermentationSystem.start_brewing。
## 返回 true 表示窖藏成功并开始发酵。
func place_keg_on_rack(token: int, current_day: int) -> bool:
	var keg := find_keg(token)
	if keg == null or keg.keg_index >= 0:
		return false
	var fs: Node = _get_fermentation_system()
	if fs == null:
		return false
	var keg_index: int = fs.start_brewing(keg.ingredients, current_day)
	if keg_index < 0:
		return false
	keg.keg_index = keg_index
	keg.state = FS.KegState.FERMENTING
	return true

## 同步一个酒桶的状态到 FermentationSystem（发酵时序推进后由 UI/场景刷新调用）。
func sync_keg_state(token: int) -> void:
	var keg := find_keg(token)
	if keg == null or keg.keg_index < 0:
		return
	var fs: Node = _get_fermentation_system()
	if fs == null or keg.keg_index >= fs.kegs.size():
		return
	keg.state = fs.kegs[keg.keg_index].state

## 开缸取酒：返回口味字典（含 __recipe_id__ 元信息），空字典表示不可开缸。
## 成功后该桶从本系统移除（桶位回归 FermentationSystem 的空桶）。
func open_rack_keg(token: int) -> Dictionary:
	var keg := find_keg(token)
	if keg == null or keg.keg_index < 0:
		return {}
	var fs: Node = _get_fermentation_system()
	if fs == null:
		return {}
	var flavors: Dictionary = fs.open_keg(keg.keg_index)
	if flavors.is_empty():
		return {}
	active_kegs.erase(keg)
	return flavors

## 查询该桶当前是否可开缸（READY/AGING/AGED）。
func can_open_keg(token: int) -> bool:
	var keg := find_keg(token)
	if keg == null or keg.keg_index < 0:
		return false
	return keg.state == FS.KegState.READY or keg.state == FS.KegState.AGING or keg.state == FS.KegState.AGED

# ============================================================================
# 5. 存档 / 读档 / 重置
# ============================================================================

func serialize() -> Dictionary:
	var kegs_data: Array = []
	for keg in active_kegs:
		kegs_data.append({
			"token": keg.token,
			"ingredients": keg.ingredients.duplicate(),
			"keg_index": keg.keg_index,
			"state": keg.state,
		})
	return {
		"cauldron_basket": cauldron_basket.duplicate(),
		"cauldron_state": cauldron_state,
		"boil_progress": boil_progress,
		"active_kegs": kegs_data,
		"_next_token": _next_token,
	}

func deserialize(data: Dictionary) -> void:
	cauldron_basket = (data.get("cauldron_basket", {}) as Dictionary).duplicate()
	cauldron_state = int(data.get("cauldron_state", CauldronState.IDLE))
	boil_progress = float(data.get("boil_progress", 0.0))
	active_kegs.clear()
	var kegs_data: Array = data.get("active_kegs", [])
	for entry in kegs_data:
		if not entry is Dictionary:
			continue
		var keg := ActiveKeg.new()
		keg.token = int(entry.get("token", -1))
		keg.ingredients = (entry.get("ingredients", {}) as Dictionary).duplicate()
		keg.keg_index = int(entry.get("keg_index", -1))
		keg.state = int(entry.get("state", FS.KegState.EMPTY))
		active_kegs.append(keg)
	_next_token = int(data.get("_next_token", active_kegs.size()))

## 重置为初始状态（新游戏时调用）。
func reset() -> void:
	cauldron_basket.clear()
	cauldron_state = CauldronState.IDLE
	boil_progress = 0.0
	active_kegs.clear()
	_next_token = 0

func _get_fermentation_system() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("FermentationSystem")
