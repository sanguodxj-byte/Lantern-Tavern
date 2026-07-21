extends Control
class_name TavernHUD

@onready var order_list: VBoxContainer = $OrderPanel/ScrollContainer/OrderList
@onready var inventory_list: ItemList = $InventoryPanel/ScrollContainer/InventoryList
@onready var next_day_btn: Button = $ControlPanel/NextDayButton
@onready var status_label: Label = $ControlPanel/StatusLabel
@onready var title_label: Label = $Title

var selected_ingredients: Array[String] = []
var active_orders: Array = []
var monster_presets: Array = []

func _ready() -> void:
	next_day_btn.pressed.connect(_on_next_day_pressed)
	inventory_list.item_selected.connect(_on_inventory_item_selected)

	_load_monster_preferences()
	_load_tavern_data()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_toggle_pause_menu()


func _toggle_pause_menu() -> void:
	var pm := get_node_or_null("../PauseMenu") as CanvasLayer
	if pm == null:
		pm = get_node_or_null("PauseMenu") as CanvasLayer
	if pm == null:
		return
	# PauseMenu 的 class_name 自带 pause/resume
	if pm.get("is_paused"):
		pm.resume()
	else:
		pm.pause()

func _load_monster_preferences() -> void:
	var path = "res://data/monster_preferences.json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				monster_presets = json.data
				return

	# Fallback presets if file doesn't exist
	monster_presets = [
		{"id": "goblin", "name": tr("goblin"), "liked_flavors": ["sweet", "umami"], "disliked_flavors": ["bitter", "salty"]},
		{"id": "spider", "name": tr("spider"), "liked_flavors": ["gaminess", "salty"], "disliked_flavors": ["spicy", "sweet"]},
		{"id": "slime", "name": tr("slime"), "liked_flavors": ["sour", "sweet"], "disliked_flavors": ["salty", "earthy"]}
	]

func _load_tavern_data() -> void:
	# Load current customer orders
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
	# Clear old orders
	for child in order_list.get_children():
		child.queue_free()

	active_orders.clear()
	if monster_presets.is_empty():
		_load_monster_preferences()

	var temp_presets = monster_presets.duplicate()
	temp_presets.shuffle()

	for i in range(min(3, temp_presets.size())):
		var monster = temp_presets[i]
		var liked = monster["liked_flavors"][randi() % monster["liked_flavors"].size()]
		var disliked = monster["disliked_flavors"][randi() % monster["disliked_flavors"].size()]
		var val = randi_range(2, 5)

		var order = {
			"monster_id": monster["id"],
			"monster_name": monster["name"],
			"liked_flavor": liked,
			"disliked_flavor": disliked,
			"target_value": val,
			"satisfied": false
		}
		active_orders.append(order)
		_create_order_ui(order)

func _create_order_ui(order: Dictionary) -> void:
	var panel = PanelContainer.new()
	var vbox = VBoxContainer.new()

	var name_label = Label.new()
	name_label.text = tr("Customer: %s") % order["monster_name"]

	var req_label = Label.new()
	req_label.text = tr("Likes: %s (%s: %d+)") % [order["liked_flavor"].capitalize(), order["liked_flavor"].capitalize(), order["target_value"]]
	req_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))

	var warn_label = Label.new()
	warn_label.text = tr("Dislikes: %s (AVOID!)") % order["disliked_flavor"].capitalize()
	warn_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	if order["satisfied"]:
		var sat_label = Label.new()
		sat_label.text = tr("[SERVED & SATISFIED]")
		sat_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		vbox.add_child(sat_label)

	vbox.add_child(name_label)
	vbox.add_child(req_label)
	vbox.add_child(warn_label)
	panel.add_child(vbox)
	order_list.add_child(panel)

func _material_display_name(item_id: String) -> String:
	var BD := load("res://globals/tavern/brewing_data.gd")
	if BD != null and BD.has_method("get_material_name"):
		return String(BD.call("get_material_name", item_id))
	return tr(item_id.replace("_", " ").capitalize())


func _populate_inventory() -> void:
	inventory_list.clear()
	if TavernManager:
		for item_id in TavernManager.materials_inventory.keys():
			var qty = TavernManager.materials_inventory[item_id]
			var display_name = _material_display_name(String(item_id))
			var idx = inventory_list.add_item("%s (x%d)" % [display_name, qty])
			inventory_list.set_item_metadata(idx, item_id)
	else:
		# Mock data for editor preview
		var mock_items = ["wild_glowcap", "frost_berry", "goblin_ear"]
		for item in mock_items:
			var idx = inventory_list.add_item("%s (x3)" % _material_display_name(item))
			inventory_list.set_item_metadata(idx, item)

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
