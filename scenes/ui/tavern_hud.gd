extends Control
class_name TavernHUD

@onready var order_list: VBoxContainer = $OrderPanel/ScrollContainer/OrderList
@onready var cauldron_list: ItemList = $BrewingPanel/CauldronList
@onready var inventory_list: ItemList = $InventoryPanel/ScrollContainer/InventoryList
@onready var brew_btn: Button = $BrewingPanel/BrewButton
@onready var next_day_btn: Button = $ControlPanel/NextDayButton

var selected_ingredients: Array[String] = []

func _ready() -> void:
	brew_btn.pressed.connect(_on_brew_pressed)
	next_day_btn.pressed.connect(_on_next_day_pressed)
	inventory_list.item_selected.connect(_on_inventory_item_selected)
	
	_load_tavern_data()

func _load_tavern_data() -> void:
	# Load current customer orders
	_populate_orders()
	
	# Load player's collected materials
	_populate_inventory()
	
	# Clear cauldron
	selected_ingredients.clear()
	cauldron_list.clear()

func _populate_orders() -> void:
	# Clear old orders
	for child in order_list.get_children():
		child.queue_free()
		
	# Spawn 3 dynamic mock customer orders
	var mock_requests = [
		{"monster": "Goblin", "dislikes": "bitter", "liked": "sweet", "flavor_req": "sweet: 3"},
		{"monster": "Spider", "dislikes": "sweet", "liked": "gaminess", "flavor_req": "gaminess: 4"},
		{"monster": "Slime", "dislikes": "salty", "liked": "sour", "flavor_req": "sour: 2"}
	]
	
	for req in mock_requests:
		var panel = PanelContainer.new()
		var vbox = VBoxContainer.new()
		
		var name_label = Label.new()
		name_label.text = "Customer: " + req["monster"]
		var req_label = Label.new()
		req_label.text = "Likes: " + req["liked"] + " (" + req["flavor_req"] + ")"
		var warn_label = Label.new()
		warn_label.text = "Dislikes: " + req["dislikes"] + " (AVOID!)"
		warn_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		
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
			inventory_list.add_item("%s (x%d)" % [item_id.capitalize(), qty])
	else:
		# Mock data for editor preview
		inventory_list.add_item("Wild Glowcap (x3)")
		inventory_list.add_item("Frost Berry (x2)")
		inventory_list.add_item("Goblin Ear (x1)")

func _on_inventory_item_selected(index: int) -> void:
	var item_text = inventory_list.get_item_text(index)
	var item_id = item_text.split(" ")[0].to_lower()
	
	# Add to cauldron
	selected_ingredients.append(item_id)
	cauldron_list.add_item(item_text.split(" ")[0])

func _on_brew_pressed() -> void:
	if selected_ingredients.is_empty():
		return
		
	# Brewing logic: Check flavor and serving
	var total_gold_earned = 25 # base value
	
	# Apply metabolic lore check: did we brew using a material the customer dislikes?
	# E.g., if we brewed for Goblin, did we add Goblin Ear (contains bitter)?
	var has_poisoned = false
	for ing in selected_ingredients:
		if ing.contains("goblin_ear") or ing.contains("goblin_tooth"):
			has_poisoned = true # Goblin dislikes bitter/salty!
			
	if has_poisoned:
		total_gold_earned = 5 # Penalized!
		print("Brew failed or penalized: Monster disliked the metabolic waste!")
	else:
		total_gold_earned += 15 # Reward!
		
	if TavernManager:
		TavernManager.gold += total_gold_earned
		
	# Clear brewing kettle
	selected_ingredients.clear()
	cauldron_list.clear()
	_populate_inventory()
	
	print("Brew served! Gold earned: ", total_gold_earned)

func _on_next_day_pressed() -> void:
	if TavernManager:
		TavernManager.enter_phase(TavernManager.Phase.DAY_EXPEDITION)
	else:
		get_tree().change_scene_to_file("res://scenes/expedition/expedition.tscn")
