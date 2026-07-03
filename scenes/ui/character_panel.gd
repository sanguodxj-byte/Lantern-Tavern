extends Control
class_name CharacterPanel

@onready var tab_container: TabContainer = $PanelContainer/VBoxContainer/TabContainer
@onready var return_btn: Button = $PanelContainer/VBoxContainer/Header/ReturnBtn

# Attributes Controls
@onready var hp_val: Label = %HPVal
@onready var gold_val: Label = %GoldVal
@onready var dmg_val: Label = %DmgVal
@onready var def_val: Label = %DefVal
@onready var reach_val: Label = %ReachVal
@onready var speed_val: Label = %SpeedVal
@onready var desc_val: Label = %DescVal

# Equipment Controls
@onready var gear_list: ItemList = %GearList
@onready var eq_viewport: SubViewport = %EqSubViewport
@onready var eq_camera_pivot: Node3D = %EqCameraPivot
@onready var eq_light: DirectionalLight3D = %EqLight
@onready var eq_name_lbl: Label = %EqNameVal
@onready var eq_cond_lbl: Label = %EqCondVal
@onready var eq_dmg_lbl: Label = %EqDmgVal
@onready var eq_reach_lbl: Label = %EqReachVal
@onready var eq_desc_lbl: Label = %EqDescVal

# Quests Controls
@onready var quest_tree: Tree = %QuestTree
@onready var quest_details: Label = %QuestDetailsVal

var current_eq_mesh: Node3D = null
var current_player: Player = null

# Custom Quests DB
var quests_database: Array = [
	{
		"title": "Gathering Ingredients for Glowcap Ale (收集荧光浆果材料)",
		"desc": "The local travelers love the sweet-sour, glowing taste of Glowcap Ale. Gather the necessary materials in the dungeon.",
		"requirements": {
			"wild_glowcap": 1,
			"frost_berry": 1,
			"mountain_barley": 1
		},
		"reward": "150 Gold, 20 Rep"
	},
	{
		"title": "Slime Core Preservation (收集史莱姆核心)",
		"desc": "Tavern brewing requires highly elastic stabilizers. Defeat Slimes in the procedural dungeon to collect jelly.",
		"requirements": {
			"slime_jelly": 2
		},
		"reward": "100 Gold, 15 Rep"
	},
	{
		"title": "Fire Bloom Inferno Brewing (恶魔烈焰特调)",
		"desc": "Brew a dynamic and spicy drink for the Fire Imps. Gather Fire Bloom in the dungeon vaults.",
		"requirements": {
			"fire_bloom": 2,
			"imp_horn_dust": 1
		},
		"reward": "250 Gold, 35 Rep"
	}
]

func _ready() -> void:
	return_btn.pressed.connect(_on_return_pressed)
	gear_list.item_selected.connect(_on_gear_selected)
	
	# Try to find reference to active player in session
	current_player = GameState.player if "player" in GameState else null
	
	_load_attributes()
	_load_gear_list()
	_load_quests_tree()
	
	# Select first item in gear list by default
	if gear_list.item_count > 0:
		gear_list.select(0)
		_on_gear_selected(0)

func _process(delta: float) -> void:
	# Rotate equipped weapon model slowly in the inspect viewport
	if current_eq_mesh and is_instance_valid(current_eq_mesh):
		current_eq_mesh.rotate_y(0.5 * delta)

func _load_attributes() -> void:
	# Load HP
	if current_player and is_instance_valid(current_player):
		hp_val.text = "%d / %d" % [current_player.health.current_life, current_player.health.max_life]
	else:
		hp_val.text = "100 / 100 (Default)"
		
	# Load Gold
	if TavernManager:
		gold_val.text = "%d Gold" % TavernManager.gold
	else:
		gold_val.text = "100 Gold"
		
	# Attack stats based on active weapon
	var base_dmg_min = 1
	var base_dmg_max = 2
	var reach = 2.0
	var speed = 1.0
	var defense = 0
	
	if current_player and is_instance_valid(current_player) and current_player.equipment:
		if current_player.equipment.has_weapon():
			var w_data = current_player.equipment.weapon_data
			base_dmg_min = w_data.damage_min
			base_dmg_max = w_data.damage_max
			reach = w_data.reach
			speed = w_data.throw_movement_speed / 10.0
		if current_player.equipment.has_shield():
			defense = current_player.equipment.shield_data.condition
			
	dmg_val.text = "%d - %d Physical" % [base_dmg_min, base_dmg_max]
	reach_val.text = "%.1f meters" % reach
	speed_val.text = "%.1f attack factor" % speed
	def_val.text = "%d Guard Rating" % defense
	desc_val.text = "A brave adventurer exploring Wave Function Collapse dungeons to gather valuable brewing ingredients for the Cozy Tavern."

func _load_gear_list() -> void:
	gear_list.clear()
	
	# Standard items from database to inspect
	gear_list.add_item("Short Sword (短剑)", load("res://assets/textures/icons/icon-weapon.png"))
	gear_list.set_item_metadata(0, "res://data/weapons/shortsword.tres")
	
	gear_list.add_item("Axe (战斧)", load("res://assets/textures/icons/icon-weapon.png"))
	gear_list.set_item_metadata(1, "res://data/weapons/axe.tres")
	
	gear_list.add_item("Buckler (圆盾)", load("res://assets/textures/icons/icon-shield.png"))
	gear_list.set_item_metadata(2, "res://data/shields/buckler.tres")

func _on_gear_selected(index: int) -> void:
	var res_path = gear_list.get_item_metadata(index)
	_inspect_equipment(res_path)

func _inspect_equipment(res_path: String) -> void:
	# Clear previous inspection model
	if current_eq_mesh and is_instance_valid(current_eq_mesh):
		current_eq_mesh.queue_free()
		current_eq_mesh = null
		
	if not ResourceLoader.exists(res_path):
		return
		
	var resource = load(res_path)
	if not resource:
		return
		
	# Populate Stats Labels
	eq_name_lbl.text = resource.name
	eq_cond_lbl.text = "%d / %d (Stable)" % [resource.condition, resource.max_condition]
	
	if "damage_min" in resource:
		eq_dmg_lbl.text = "%d - %d Phys" % [resource.damage_min, resource.damage_max]
		eq_reach_lbl.text = "%.1f meters" % resource.reach
		eq_desc_lbl.text = "A versatile close-combat weapon suited for slashing dungeon monsters."
	else:
		# It's a shield
		eq_dmg_lbl.text = "N/A (Blocking Focus)"
		eq_reach_lbl.text = "1.0 meters"
		eq_desc_lbl.text = "A sturdy lightweight buckler used to block incoming attacks and stun opponents."
		
	# Spawn dynamic 3D inspect model inside the subviewport
	var mesh_scene = resource.glb_mesh
	if mesh_scene:
		var instance = mesh_scene.instantiate()
		eq_viewport.add_child(instance)
		current_eq_mesh = instance
		
		# Center and adjust scale recursively
		_normalize_inspect_scale(instance)

func _normalize_inspect_scale(instance: Node3D) -> void:
	var result: Array[MeshInstance3D] = []
	_gather_meshes(instance, result)
	
	if not result.is_empty():
		var aabb = result[0].get_aabb()
		for i in range(1, result.size()):
			aabb = aabb.merge(result[i].get_aabb())
			
		var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		instance.scale = Vector3(1.2 / max_dim, 1.2 / max_dim, 1.2 / max_dim)
		instance.position = Vector3(0, -aabb.position.y * (1.2 / max_dim) - 0.4, 0)
	else:
		instance.position = Vector3(0, -0.3, 0)

func _gather_meshes(node: Node, arr: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		arr.append(node)
	for child in node.get_children():
		_gather_meshes(child, arr)

func _load_quests_tree() -> void:
	quest_tree.clear()
	var root = quest_tree.create_item()
	quest_tree.hide_root = true
	
	for i in range(quests_database.size()):
		var q = quests_database[i]
		var q_item = quest_tree.create_item(root)
		
		# Determine completion progress dynamically
		var total_req = 0
		var completed_req = 0
		for item_id in q["requirements"].keys():
			var needed = q["requirements"][item_id]
			total_req += needed
			var inventory_has = TavernManager.inventory.get(item_id, 0) if TavernManager else 0
			completed_req += min(inventory_has, needed)
			
		var status_str = "[Active]"
		if completed_req >= total_req:
			status_str = "[Ready to Hand In (可交付)]"
			q_item.set_custom_color(0, Color(0.2, 1.0, 0.2))
		else:
			status_str = "[%d/%d Gained]" % [completed_req, total_req]
			
		q_item.set_text(0, "%s  %s" % [q["title"], status_str])
		q_item.set_metadata(0, i)
		
	quest_tree.item_selected.connect(_on_quest_selected)
	_select_first_quest()

func _select_first_quest() -> void:
	var root = quest_tree.get_root()
	if root:
		var first = root.get_first_child()
		if first:
			first.select(0)

func _on_quest_selected() -> void:
	var selected = quest_tree.get_selected()
	if not selected:
		return
		
	var idx = selected.get_metadata(0)
	var q = quests_database[idx]
	
	var details = "QUEST DETAILS:\n%s\n\n" % q["desc"]
	details += "REQUIRED MATERIALS (收集进度):\n"
	
	for item_id in q["requirements"].keys():
		var needed = q["requirements"][item_id]
		var has_count = TavernManager.inventory.get(item_id, 0) if TavernManager else 0
		var display_name = TavernManager.materials_db[item_id]["name"] if TavernManager else item_id
		
		details += "- %s: %d / %d  %s\n" % [
			display_name, 
			has_count, 
			needed, 
			"(OK)" if has_count >= needed else "(Incomplete)"
		]
		
	details += "\nREWARDS:\n%s" % q["reward"]
	quest_details.text = details

func _on_return_pressed() -> void:
	# Check if we are running in-game or from the menu
	if get_parent() is CanvasLayer and "player" in GameState:
		# Toggle overlay off
		self.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
