extends Control
class_name TavernHUD

@onready var order_list: VBoxContainer = $OrderPanel/ScrollContainer/OrderList
@onready var cauldron_list: ItemList = $BrewingPanel/CauldronList
@onready var inventory_list: ItemList = $InventoryPanel/ScrollContainer/InventoryList
@onready var brew_btn: Button = $BrewingPanel/BrewButton
@onready var next_day_btn: Button = $ControlPanel/NextDayButton
@onready var status_label: Label = $ControlPanel/StatusLabel
@onready var title_label: Label = $Title

var selected_ingredients: Array[String] = []
var active_orders: Array = []
var monster_presets: Array = []

func _ready() -> void:
	brew_btn.pressed.connect(_on_brew_pressed)
	next_day_btn.pressed.connect(_on_next_day_pressed)
	inventory_list.item_selected.connect(_on_inventory_item_selected)
		
	_load_monster_preferences()
	_load_tavern_data()

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
		{"id": "goblin", "name": "哥布林", "liked_flavors": ["sweet", "umami"], "disliked_flavors": ["bitter", "salty"]},
		{"id": "spider", "name": "巨型蜘蛛", "liked_flavors": ["gaminess", "salty"], "disliked_flavors": ["spicy", "sweet"]},
		{"id": "slime", "name": "史莱姆", "liked_flavors": ["sour", "sweet"], "disliked_flavors": ["salty", "earthy"]}
	]

func _load_tavern_data() -> void:
	# Load current customer orders
	_populate_orders()
	
	# Load player's collected materials
	_populate_inventory()
	
	# Update Gold in Title
	_update_gold_display()
	
	# Clear cauldron
	selected_ingredients.clear()
	cauldron_list.clear()

func _update_gold_display() -> void:
	if TavernManager:
		title_label.text = "COZY BREWING TAVERN (Gold: %d)" % TavernManager.gold
	else:
		title_label.text = "COZY BREWING TAVERN (Gold: 100)"

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
	name_label.text = "Customer: %s" % order["monster_name"]
	
	var req_label = Label.new()
	req_label.text = "Likes: %s (%s: %d+)" % [order["liked_flavor"].capitalize(), order["liked_flavor"].capitalize(), order["target_value"]]
	req_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	
	var warn_label = Label.new()
	warn_label.text = "Dislikes: %s (AVOID!)" % order["disliked_flavor"].capitalize()
	warn_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	
	if order["satisfied"]:
		var sat_label = Label.new()
		sat_label.text = "[SERVED & SATISFIED]"
		sat_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		vbox.add_child(sat_label)
		
	vbox.add_child(name_label)
	vbox.add_child(req_label)
	vbox.add_child(warn_label)
	panel.add_child(vbox)
	order_list.add_child(panel)

func _populate_inventory() -> void:
	inventory_list.clear()
	if TavernManager:
		for item_id in TavernManager.materials_inventory.keys():
			var qty = TavernManager.materials_inventory[item_id]
			var display_name = item_id.replace("_", " ").capitalize()
			var idx = inventory_list.add_item("%s (x%d)" % [display_name, qty])
			inventory_list.set_item_metadata(idx, item_id)
	else:
		# Mock data for editor preview
		var mock_items = ["wild_glowcap", "frost_berry", "goblin_ear"]
		for item in mock_items:
			var idx = inventory_list.add_item("%s (x3)" % item.replace("_", " ").capitalize())
			inventory_list.set_item_metadata(idx, item)

func _on_inventory_item_selected(index: int) -> void:
	var item_id = inventory_list.get_item_metadata(index)
	
	# Check if we have enough of it in the cauldron already (can't add more than we have in inventory)
	if TavernManager:
		var available_qty = TavernManager.materials_inventory.get(item_id, 0)
		var already_selected_qty = 0
		for sel in selected_ingredients:
			if sel == item_id:
				already_selected_qty += 1
		if already_selected_qty >= available_qty:
			status_label.text = "Not enough %s left!" % item_id.replace("_", " ").capitalize()
			return
			
	# Add to cauldron
	selected_ingredients.append(item_id)
	var display_name = item_id.replace("_", " ").capitalize()
	cauldron_list.add_item(display_name)
	status_label.text = "Added %s to cauldron." % display_name

func _on_brew_pressed() -> void:
	if selected_ingredients.is_empty():
		status_label.text = "The cauldron is empty!"
		return
		
	if not TavernManager:
		status_label.text = "Mock Brew: Served! (+40 Gold)"
		selected_ingredients.clear()
		cauldron_list.clear()
		return
		
	# Store the list of ingredients being brewed
	var ingredients_to_brew = selected_ingredients.duplicate()
	
	# Brew drink using TavernManager
	var drink = TavernManager.brew_drink(ingredients_to_brew)
	if drink.is_empty():
		status_label.text = "Brew failed! Check your ingredients."
		return
		
	# Match to customer order
	var served_order = null
	var highest_match_score = -999
	
	for order in active_orders:
		if order["satisfied"]:
			continue
			
		var score = 0
		var liked_val = drink["flavors"].get(order["liked_flavor"], 0)
		var disliked_val = drink["flavors"].get(order["disliked_flavor"], 0)
		
		if liked_val >= order["target_value"]:
			score += 100
		elif liked_val > 0:
			score += 20
			
		if disliked_val > 0:
			score -= 50
			
		if score > highest_match_score and score > -999:
			highest_match_score = score
			served_order = order
			
	# Calculate payment
	var base_payout = 20 * drink["quality"]
	var bonus_payout = 0
	var penalty_payout = 0
	var msg = ""
	
	if served_order != null:
		var liked_val = drink["flavors"].get(served_order["liked_flavor"], 0)
		var disliked_val = drink["flavors"].get(served_order["disliked_flavor"], 0)
		
		if liked_val >= served_order["target_value"]:
			bonus_payout = 30
			served_order["satisfied"] = true
			msg = "Brewed quality %d drink! Served to %s who LOVED it!" % [drink["quality"], served_order["monster_name"]]
		else:
			msg = "Brewed quality %d drink! Served to %s who drank it." % [drink["quality"], served_order["monster_name"]]
			
		if disliked_val > 0:
			penalty_payout = -15
			msg += " But they hated the %s flavor!" % served_order["disliked_flavor"].capitalize()
	else:
		msg = "Brewed quality %d drink! Served to general customers." % drink["quality"]
		
	var total_payout = max(5, base_payout + bonus_payout + penalty_payout)
	TavernManager.gold += total_payout
	msg += " (+%d Gold)" % total_payout
	
	# Update displays
	status_label.text = msg
	_update_gold_display()
	
	# Redraw orders UI with updated satisfaction
	for child in order_list.get_children():
		child.queue_free()
	for order in active_orders:
		_create_order_ui(order)
		
	# Clear cauldron and refresh inventory
	selected_ingredients.clear()
	cauldron_list.clear()
	_populate_inventory()

func _on_next_day_pressed() -> void:
	if TavernManager:
		TavernManager.enter_phase(TavernManager.Phase.DAY_EXPEDITION)
	else:
		get_tree().change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")
