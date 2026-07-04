extends Control
## 酿酒台/吧台操作面板（夜晚营业阶段玩家交互入口）。
## 接入 FermentationSystem 的 Keg 状态机 + BrewingData 的中文键数据。
## 三大操作：下料 / 开缸取酒 / 选择陈酿。
## 挂载到 tavern_ui.tscn 的 BrewingPanel 节点区域。

const BD := preload("res://globals/brewing_data.gd")
const FS := preload("res://globals/fermentation_system.gd")

# UI 节点引用（由 _ready 动态查找，避免硬编码路径导致场景结构变动时断裂）
var keg_status_list: ItemList
var material_grid: ItemList
var selected_ingredients_label: Label
var brew_button: Button
var open_keg_button: Button
var seal_aging_button: Button
var status_label: Label

# 当前选中桶位（-1 = 未选）
var selected_keg_index: int = -1
# 当前下料篮：{material_id: count}
var brewing_basket: Dictionary = {}

# 选中的材料 id（用于下料篮增减）
var _selected_material_id: String = ""

signal brew_started(keg_index: int)
signal keg_opened(keg_index: int, flavors: Dictionary)
signal keg_sealed(keg_index: int)

# ============================================================================
# 1. 初始化
# ============================================================================

func _ready() -> void:
	_find_ui_nodes()
	_connect_signals()
	_refresh_all()

## 动态查找 UI 节点（容忍节点缺失，便于测试环境运行）
## 支持两种布局：节点为直接子节点，或嵌套在 ButtonRow 下
func _find_ui_nodes() -> void:
	keg_status_list = get_node_or_null("KegStatusList")
	material_grid = get_node_or_null("MaterialGrid")
	selected_ingredients_label = get_node_or_null("SelectedIngredientsLabel")
	brew_button = get_node_or_null("BrewButton")
	if brew_button == null:
		brew_button = get_node_or_null("ButtonRow/BrewButton")
	open_keg_button = get_node_or_null("OpenKegButton")
	if open_keg_button == null:
		open_keg_button = get_node_or_null("ButtonRow/OpenKegButton")
	seal_aging_button = get_node_or_null("SealAgingButton")
	if seal_aging_button == null:
		seal_aging_button = get_node_or_null("ButtonRow/SealAgingButton")
	status_label = get_node_or_null("StatusLabel")

func _connect_signals() -> void:
	if brew_button:
		brew_button.pressed.connect(_on_brew_pressed)
	if open_keg_button:
		open_keg_button.pressed.connect(_on_open_keg_pressed)
	if seal_aging_button:
		seal_aging_button.pressed.connect(_on_seal_aging_pressed)
	if material_grid:
		material_grid.item_selected.connect(_on_material_selected)
	if keg_status_list:
		keg_status_list.item_selected.connect(_on_keg_selected)

# ============================================================================
# 2. 数据获取（通过 autoload 单例，避免 preload 静态调用非静态函数）
# ============================================================================

func _get_fermentation_system() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("FermentationSystem")

func _get_tavern_manager() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("TavernManager")

## 获取玩家材料库存（中文键 material_id → 数量）
func _get_inventory() -> Dictionary:
	var tm: Node = _get_tavern_manager()
	if tm == null:
		return {}
	if "materials_inventory" in tm:
		return tm.materials_inventory
	return {}

## 获取当前游戏天数
func _get_current_day() -> int:
	var tm: Node = _get_tavern_manager()
	if tm == null:
		return 1
	if "day" in tm:
		return int(tm.day)
	return 1

# ============================================================================
# 3. UI 刷新
# ============================================================================

## 全量刷新：桶位状态 + 材料库存 + 下料篮
func _refresh_all() -> void:
	_refresh_keg_status()
	_refresh_material_grid()
	_refresh_basket_display()

## 刷新桶位状态列表
func _refresh_keg_status() -> void:
	if keg_status_list == null:
		return
	keg_status_list.clear()
	var fs: Node = _get_fermentation_system()
	if fs == null:
		keg_status_list.add_item("（发酵系统未加载）")
		return
	if not "kegs" in fs:
		keg_status_list.add_item("（桶位数据缺失）")
		return
	var kegs: Array = fs.kegs
	if kegs.is_empty():
		keg_status_list.add_item("（无酒桶，需扩建）")
		return
	for i in range(kegs.size()):
		var keg = kegs[i]
		var status_text: String = fs.get_keg_status_text(i)
		var display: String = "桶%d: %s" % [i + 1, status_text]
		if keg.recipe_name != "":
			display += " [%s]" % keg.recipe_name
		keg_status_list.add_item(display)

## 刷新材料库存网格（仅显示库存 > 0 的材料）
func _refresh_material_grid() -> void:
	if material_grid == null:
		return
	material_grid.clear()
	brewing_basket.clear()
	var inventory: Dictionary = _get_inventory()
	if inventory.is_empty():
		material_grid.add_item("（无材料，需白天探索收集）")
		return
	for mat_id in inventory:
		var count: int = int(inventory[mat_id])
		if count <= 0:
			continue
		var mat_name: String = BD.get_material_name(mat_id)
		var display: String = "%s ×%d" % [mat_name, count]
		var idx: int = material_grid.add_item(display)
		material_grid.set_item_metadata(idx, mat_id)

## 刷新下料篮显示
func _refresh_basket_display() -> void:
	if selected_ingredients_label == null:
		return
	if brewing_basket.is_empty():
		selected_ingredients_label.text = "下料篮：空"
		return
	var parts: Array = []
	for mat_id in brewing_basket:
		var count: int = int(brewing_basket[mat_id])
		var mat_name: String = BD.get_material_name(mat_id)
		parts.append("%s×%d" % [mat_name, count])
	selected_ingredients_label.text = "下料篮：" + ", ".join(parts)

## 刷新操作按钮可用状态（基于选中桶位）
func _refresh_buttons_for_keg(keg_index: int) -> void:
	var fs: Node = _get_fermentation_system()
	if fs == null or keg_index < 0:
		_set_buttons_disabled(true)
		return
	if not "kegs" in fs or keg_index >= fs.kegs.size():
		_set_buttons_disabled(true)
		return
	var keg = fs.kegs[keg_index]
	# EMPTY：可下料
	if keg.state == FS.KegState.EMPTY:
		if brew_button: brew_button.disabled = brewing_basket.is_empty()
		if open_keg_button: open_keg_button.disabled = true
		if seal_aging_button: seal_aging_button.disabled = true
	# READY：可开缸或陈酿
	elif keg.state == FS.KegState.READY:
		if brew_button: brew_button.disabled = true
		if open_keg_button: open_keg_button.disabled = false
		if seal_aging_button: seal_aging_button.disabled = false
	# AGING：可开缸
	elif keg.state == FS.KegState.AGING:
		if brew_button: brew_button.disabled = true
		if open_keg_button: open_keg_button.disabled = false
		if seal_aging_button: seal_aging_button.disabled = true
	# AGED：可开缸
	elif keg.state == FS.KegState.AGED:
		if brew_button: brew_button.disabled = true
		if open_keg_button: open_keg_button.disabled = false
		if seal_aging_button: seal_aging_button.disabled = true
	# FERMENTING：均不可操作
	else:
		_set_buttons_disabled(true)

func _set_buttons_disabled(disabled: bool) -> void:
	if brew_button: brew_button.disabled = disabled
	if open_keg_button: open_keg_button.disabled = disabled
	if seal_aging_button: seal_aging_button.disabled = disabled

# ============================================================================
# 4. 操作：下料 / 开缸 / 陈酿
# ============================================================================

## 下料：把 brewing_basket 投入空桶，启动发酵
func _on_brew_pressed() -> void:
	if brewing_basket.is_empty():
		_set_status("下料篮为空，请先选择材料")
		return
	var fs: Node = _get_fermentation_system()
	if fs == null:
		_set_status("发酵系统未加载")
		return
	# 选中的桶位必须为空
	var target_keg: int = selected_keg_index
	if target_keg < 0:
		# 自动找第一个空桶
		target_keg = _find_empty_keg(fs)
		if target_keg < 0:
			_set_status("无空桶可用，请先开缸或扩建")
			return
	# 校验选中桶是否为空
	if fs.kegs[target_keg].state != FS.KegState.EMPTY:
		_set_status("桶%d非空，请选择空桶" % (target_keg + 1))
		return
	# 扣减库存
	if not _deduct_inventory(brewing_basket):
		_set_status("材料库存不足")
		return
	# 启动发酵
	var keg_index: int = fs.start_brewing(brewing_basket.duplicate(), _get_current_day())
	if keg_index < 0:
		_set_status("下料失败")
		return
	brewing_basket.clear()
	selected_keg_index = keg_index
	_set_status("已下料至桶%d，发酵中（明日完成）" % (keg_index + 1))
	brew_started.emit(keg_index)
	_refresh_all()
	_refresh_buttons_for_keg(keg_index)

## 开缸取酒：把 READY/AGING/AGED 桶的酒取出
func _on_open_keg_pressed() -> void:
	if selected_keg_index < 0:
		_set_status("请先选择桶位")
		return
	var fs: Node = _get_fermentation_system()
	if fs == null:
		_set_status("发酵系统未加载")
		return
	var flavors: Dictionary = fs.open_keg(selected_keg_index)
	if flavors.is_empty():
		_set_status("桶%d不可开缸" % (selected_keg_index + 1))
		return
	var recipe_id: String = flavors.get("__recipe_id__", "")
	var msg: String = "桶%d开缸完成" % (selected_keg_index + 1)
	if recipe_id != "":
		msg += "，匹配经典酒谱【%s】" % BD.get_recipe_name(recipe_id)
	_set_status(msg)
	keg_opened.emit(selected_keg_index, flavors)
	_refresh_all()
	selected_keg_index = -1
	_refresh_buttons_for_keg(-1)

## 选择陈酿：把 READY 桶封存转入陈酿
func _on_seal_aging_pressed() -> void:
	if selected_keg_index < 0:
		_set_status("请先选择桶位")
		return
	var fs: Node = _get_fermentation_system()
	if fs == null:
		_set_status("发酵系统未加载")
		return
	if not fs.seal_for_aging(selected_keg_index):
		_set_status("桶%d不可陈酿（仅 READY 状态可封存）" % (selected_keg_index + 1))
		return
	_set_status("桶%d已封存陈酿，每日口味 +1，最多 3 天" % (selected_keg_index + 1))
	keg_sealed.emit(selected_keg_index)
	_refresh_all()
	_refresh_buttons_for_keg(selected_keg_index)

# ============================================================================
# 5. 选择交互
# ============================================================================

## 选中材料：加入下料篮（受库存上限约束）
func _on_material_selected(index: int) -> void:
	if material_grid == null or index < 0:
		return
	var mat_id = material_grid.get_item_metadata(index)
	if mat_id == null or typeof(mat_id) != TYPE_STRING or mat_id == "":
		return
	_selected_material_id = mat_id
	# 库存上限校验
	var inventory: Dictionary = _get_inventory()
	var available: int = int(inventory.get(mat_id, 0))
	var in_basket: int = int(brewing_basket.get(mat_id, 0))
	if in_basket >= available:
		_set_status("%s 库存不足（已选 %d/%d）" % [BD.get_material_name(mat_id), in_basket, available])
		return
	brewing_basket[mat_id] = in_basket + 1
	_set_status("已加入 %s 至下料篮" % BD.get_material_name(mat_id))
	_refresh_basket_display()
	# 若已选中空桶，刷新下料按钮
	if selected_keg_index >= 0:
		_refresh_buttons_for_keg(selected_keg_index)

## 选中桶位
func _on_keg_selected(index: int) -> void:
	if keg_status_list == null or index < 0:
		return
	selected_keg_index = index
	_refresh_buttons_for_keg(index)
	var fs: Node = _get_fermentation_system()
	if fs != null and "kegs" in fs and index < fs.kegs.size():
		_set_status("已选中桶%d" % (index + 1))

# ============================================================================
# 6. 辅助
# ============================================================================

## 从库存扣减下料篮中的材料
func _deduct_inventory(basket: Dictionary) -> bool:
	var tm: Node = _get_tavern_manager()
	if tm == null:
		return false
	if not "materials_inventory" in tm:
		return false
	var inventory: Dictionary = tm.materials_inventory
	for mat_id in basket:
		var need: int = int(basket[mat_id])
		var have: int = int(inventory.get(mat_id, 0))
		if have < need:
			return false
	for mat_id in basket:
		var need: int = int(basket[mat_id])
		tm.materials_inventory[mat_id] = int(tm.materials_inventory[mat_id]) - need
		if int(tm.materials_inventory[mat_id]) <= 0:
			tm.materials_inventory.erase(mat_id)
	return true

## 遍历找空桶索引
func _find_empty_keg(fs: Node) -> int:
	if not "kegs" in fs:
		return -1
	for i in range(fs.kegs.size()):
		if fs.kegs[i].state == FS.KegState.EMPTY:
			return i
	return -1

func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg
	print("[BrewingPanel] %s" % msg)

## 清空下料篮
func clear_basket() -> void:
	brewing_basket.clear()
	_refresh_basket_display()

## 供外部调用：白天结束时推进发酵时序
func on_day_advance() -> void:
	var fs: Node = _get_fermentation_system()
	if fs == null:
		return
	fs.advance_day()
	_refresh_all()
