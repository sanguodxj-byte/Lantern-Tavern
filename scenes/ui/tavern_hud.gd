extends Control
class_name TavernHUD

@onready var order_list: VBoxContainer = $OrderPanel/ScrollContainer/OrderList
@onready var inventory_list: ItemList = $InventoryPanel/ScrollContainer/InventoryList
@onready var next_day_btn: Button = $ControlPanel/NextDayButton
@onready var status_label: Label = $ControlPanel/StatusLabel
@onready var title_label: Label = $Title

var selected_ingredients: Array[String] = []
var active_orders: Array = []

## 材料类型色彩编码（与装备界面品质色阶同语言：数据驱动、暗底可读）
const COLOR_GATHER := Color(0.42, 0.80, 0.47, 1.0)   # 采集类 → 绿
const COLOR_DROP := Color(0.52, 0.58, 0.92, 1.0)     # 怪物掉落 → 蓝紫

func _ready() -> void:
	next_day_btn.pressed.connect(_on_next_day_pressed)
	inventory_list.item_selected.connect(_on_inventory_item_selected)

	# 0805 审查 P1：订单 HUD 不再是一次性快照——订阅 CustomerSpawner 的
	# 顾客生命周期事件，顾客生成/服务/离场时增量刷新（含 HUD 打开期间）。
	_connect_customer_events()
	_load_tavern_data()


func _input(event: InputEvent) -> void:
	var is_tab: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB
	if not is_tab and not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	var owner: Node = self
	while owner != null:
		if owner.has_method("close_tavern_hud"):
			owner.close_tavern_hud()
			return
		owner = owner.get_parent()


## D4（0856 审查）：从真实顾客数据生成订单视图模型（只读投影）。
## customers: Array of customer_data（TavernSettlement.Customer 或同构字典）。
## 返回订单字典数组；每个展示口味键保证 ∈ BrewingData.FLAVOR_NAME_TO_ENUM。
static func build_orders_from_customers(customers: Array) -> Array:
	var orders: Array = []
	for cust in customers:
		if cust == null:
			continue
		var liked: Dictionary = {}
		if "liked" in cust and cust.liked is Dictionary:
			liked = cust.liked
		var hated: Array = []
		if "hated" in cust and cust.hated is Array:
			hated = cust.hated
		var liked_flavors: Array = []
		for flavor_name in liked.keys():
			# 只投影正式口味体系内的键（D4：展示值必须与结算规则同源）。
			if BrewingData.FLAVOR_NAME_TO_ENUM.has(String(flavor_name)):
				liked_flavors.append({
					"name": String(flavor_name),
					"target": int(liked[flavor_name]),
				})
		var hated_flavors: Array = []
		for flavor_name in hated:
			if BrewingData.FLAVOR_NAME_TO_ENUM.has(String(flavor_name)):
				hated_flavors.append(String(flavor_name))
		var display_name := "顾客"
		if "display_name" in cust and not String(cust.display_name).is_empty():
			display_name = String(cust.display_name)
		elif "race_id" in cust:
			display_name = String(cust.race_id)
		# 0805 审查 P1：满足状态从权威事务状态投影（不再永远 false）
		var satisfied := false
		if "service_state" in cust:
			satisfied = String(cust.service_state) == "COMMITTED"
		orders.append({
			"customer_name": display_name,
			"liked_flavors": liked_flavors,
			"hated_flavors": hated_flavors,
			"satisfied": satisfied,
		})
	return orders

## 取当前真实顾客数据（通过 CustomerSpawner 公开只读快照 API；
## 0805 审查 P1：不再读取私有 _active_customers 字段）。
func _collect_current_customers() -> Array:
	var tree := get_tree()
	if tree == null:
		return []
	var spawner: Node = tree.get_first_node_in_group("customer_spawner")
	if spawner == null:
		return []
	if not spawner.has_method("snapshot_active_visits"):
		return []
	return spawner.snapshot_active_visits()

## 订阅顾客生命周期事件（0805 审查 P1）。挂载顺序不保证时在
## _populate_orders 中兜底重连；is_connected 保证不会重复连接。
func _connect_customer_events() -> void:
	var spawner: Node = _get_spawner()
	if spawner == null:
		return
	for signal_name in ["customer_spawned", "customer_served", "customer_left"]:
		if not spawner.is_connected(signal_name, _on_customer_event):
			spawner.connect(signal_name, _on_customer_event)

func _get_spawner() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("customer_spawner")

## 顾客生成/服务/离场事件 → 全量重建订单列表（顾客数量小，重建成本可忽略；
## 保证与权威 visit 状态收敛）。
func _on_customer_event(_customer_data = null) -> void:
	_connect_customer_events()  # 兜底：若事件早于本 HUD 挂载，先补齐连接
	_populate_orders()

func _load_tavern_data() -> void:
	# 加载当前真实顾客订单（D4：与结算同源，不再随机生成英文口味假订单）
	_populate_orders()

	# Load player's collected materials
	_populate_inventory()

	# Update Gold in Title
	_update_gold_display()

	# Clear cauldron (酿造操作已由 brewing_panel.tscn 接管，此处仅清旧状态)
	selected_ingredients.clear()

func _update_gold_display() -> void:
	if TavernManager:
		title_label.text = tr("COZY BREWING TAVERN (Gold: %d)") % TavernManager.gold
	else:
		title_label.text = tr("COZY BREWING TAVERN (Gold: 100)")

func _populate_orders() -> void:
	# 兜底：若 HUD 挂载早于 spawner 就绪，事件订阅在此补齐
	_connect_customer_events()
	# Clear old orders
	for child in order_list.get_children():
		child.queue_free()

	active_orders.clear()
	# D4（0856 审查）：订单来自当前真实顾客（CustomerSpawner），与结算规则同源。
	active_orders = build_orders_from_customers(_collect_current_customers())
	for order in active_orders:
		_create_order_ui(order)

func _create_order_ui(order: Dictionary) -> void:
	var panel = PanelContainer.new()
	# 固定列对齐：客户名 | 喜好 | 厌恶，与装备界面网格的列对齐语言一致
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var name_label = Label.new()
	name_label.custom_minimum_size = Vector2(200, 0)
	name_label.text = ("[已满足] " if order["satisfied"] else "") + tr("Customer: %s") % order["customer_name"]
	if order["satisfied"]:
		name_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))

	var req_label = Label.new()
	req_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	req_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var liked_texts: Array[String] = []
	for liked in order["liked_flavors"]:
		liked_texts.append("%s %d+" % [liked["name"], liked["target"]])
	var req_text := tr("Likes") + ": " + ", ".join(liked_texts)
	if liked_texts.is_empty():
		req_text = tr("Likes") + ": -"
	req_label.text = req_text
	req_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))

	var warn_label = Label.new()
	warn_label.custom_minimum_size = Vector2(200, 0)
	var hated_texts: Array[String] = []
	for hated in order["hated_flavors"]:
		hated_texts.append(String(hated))
	var warn_text := tr("Dislikes") + ": " + ", ".join(hated_texts)
	if hated_texts.is_empty():
		warn_text = tr("Dislikes") + ": -"
	warn_label.text = warn_text
	warn_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	row.add_child(name_label)
	row.add_child(req_label)
	row.add_child(warn_label)
	panel.add_child(row)
	order_list.add_child(panel)

func _material_display_name(item_id: String) -> String:
	var BD := load("res://globals/tavern/brewing_data.gd")
	if BD != null and BD.has_method("get_material_name"):
		return String(BD.call("get_material_name", item_id))
	return tr(item_id.replace("_", " ").capitalize())


func _material_type_of(item_id: String) -> String:
	# 决策 G3 / D5：不再消费过期的 data/brewing_materials.json（旧英文 ID，与
	# BrewingData.MATERIALS_DB 的正式 56 材料不一致）。材料类型改为按正式注册表
	# 判定：MATERIALS_DB 已登记（可酿造采集材料）→ gather；其余（怪物掉落等）→ drop。
	var BD := load("res://globals/tavern/brewing_data.gd")
	if BD != null and "MATERIALS_DB" in BD and BD.MATERIALS_DB.has(item_id):
		return "gather"
	return "drop"


func _material_type_color(item_id: String) -> Color:
	match _material_type_of(item_id):
		"gather":
			return COLOR_GATHER
		"drop":
			return COLOR_DROP
	return Color(0.9, 0.71, 0.4, 1.0)


func _populate_inventory() -> void:
	inventory_list.clear()
	if TavernManager:
		for item_id in TavernManager.materials_inventory.keys():
			var qty = TavernManager.materials_inventory[item_id]
			var display_name = _material_display_name(String(item_id))
			var idx = inventory_list.add_item("%s    x%d" % [display_name, qty])
			inventory_list.set_item_metadata(idx, item_id)
			inventory_list.set_item_custom_fg_color(idx, _material_type_color(String(item_id)))
	else:
		# Mock data for editor preview
		var mock_items = ["wild_glowcap", "frost_berry", "goblin_ear"]
		for item in mock_items:
			var idx = inventory_list.add_item("%s    x3" % _material_display_name(item))
			inventory_list.set_item_metadata(idx, item)
			inventory_list.set_item_custom_fg_color(idx, _material_type_color(item))

func _on_inventory_item_selected(index: int) -> void:
	var item_id = inventory_list.get_item_metadata(index)
	if item_id == null or typeof(item_id) != TYPE_STRING:
		return

	# Check if we have enough of it in the cauldron already (can't add more than we have in inventory)
	if TavernManager:
		var available_qty = TavernManager.materials_inventory.get(item_id, 0)
		var already_selected_qty = 0
		for sel in selected_ingredients:
			if sel == item_id:
				already_selected_qty += 1
		if already_selected_qty >= available_qty:
			status_label.text = tr("Not enough %s left!") % _material_display_name(String(item_id))
			return

		# Add to cauldron (酿造操作已由 brewing_panel.tscn 接管)
		selected_ingredients.append(item_id)
		var display_name = _material_display_name(String(item_id))
		status_label.text = tr("Added %s to cauldron.") % display_name

func _on_brew_pressed() -> void:
	# 酿造操作已由 brewing_panel.tscn 接管，此函数保留为空实现避免外部调用断裂
	pass

func _on_next_day_pressed() -> void:
	if TavernManager:
		TavernManager.start_next_day()
	else:
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")
