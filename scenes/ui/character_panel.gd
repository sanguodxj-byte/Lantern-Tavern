extends Control
class_name CharacterPanel

@onready var return_btn: Button = $PanelContainer/VBoxContainer/Header/ReturnBtn

# Left Column - Slots
@onready var slot_head: Button = $PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipmentSlots/SlotHead
@onready var slot_body: Button = $PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipmentSlots/SlotBody
@onready var slot_hands: Button = $PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipmentSlots/SlotHands
@onready var slot_feet: Button = $PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipmentSlots/SlotFeet

@onready var slot_main_hand: Button = $PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipmentSlots/SlotMainHand
@onready var slot_off_hand: Button = $PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipmentSlots/SlotOffHand
@onready var slot_back: Button = $PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipmentSlots/SlotBack
@onready var slot_ring: Button = $PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipmentSlots/SlotRing

# 3D Viewport Controls
@onready var eq_viewport: SubViewport = %EqSubViewport
@onready var eq_camera_pivot: Node3D = %EqCameraPivot
@onready var eq_light: DirectionalLight3D = %EqLight

# Right Column - Tabs (Inventory)
@onready var gear_list: ItemList = %GearList
@onready var eq_name_lbl: Label = %EqNameVal
@onready var eq_dmg_lbl: Label = %EqDmgVal
@onready var eq_cond_lbl: Label = %EqCondVal
@onready var eq_desc_lbl: Label = %EqDescVal

# Right Column - Tabs (Stats)
@onready var hp_val: Label = %HPVal
@onready var gold_val: Label = %GoldVal
@onready var dmg_val: Label = %DmgVal
@onready var def_val: Label = %DefVal
@onready var reach_val: Label = %ReachVal

# Right Column - Tabs (Skills)
@onready var skills_list: ItemList = %SkillsList
@onready var skill_details_val: Label = %SkillDetailsVal

var current_eq_mesh: Node3D = null
var current_player: Player = null

# Custom Skills Database
var skills_database: Array = [
	{
		"name": "Heavy Strike (重击)",
		"desc": "Channels physical power into a single devastating blow, dealing 150% physical damage. Can stun low-tier enemies on impact.",
		"cooldown": "6.0 seconds",
		"cost": "15 Stamina"
	},
	{
		"name": "Swift Slash (迅捷回旋)",
		"desc": "Performs a rapid 360-degree sweep with the main-hand weapon, hitting all nearby monsters and dealing 80% slash damage.",
		"cooldown": "4.0 seconds",
		"cost": "10 Stamina"
	},
	{
		"name": "Shield Wall (坚盾壁垒)",
		"desc": "Raises the shield in defense, raising Guard Rating and damage reduction by 100% for 3 seconds. Blocked attacks recovery speed increases.",
		"cooldown": "12.0 seconds",
		"cost": "20 Stamina"
	},
	{
		"name": "Adrenaline Rush (绝境苏醒)",
		"desc": "Passive: When HP drops below 30%, increases attack speed, recovery speed and movement speed by 40% until health is restored.",
		"cooldown": "Passive",
		"cost": "None"
	}
]

func _ready() -> void:
	add_to_group("character_panel")
	return_btn.pressed.connect(_on_return_pressed)
	
	# Connect slots signals
	slot_head.pressed.connect(func(): _inspect_slot("Head", tr("Head Armor"), tr("Basic adventuring hood providing minimal defense but high comfort.")))
	slot_body.pressed.connect(func(): _inspect_slot("Chest", tr("Chest Armor (Leather)"), tr("Reinforced leather tunic, offering decent protection against bites and scratches.")))
	slot_hands.pressed.connect(func(): _inspect_slot("Hands", tr("Gloves"), tr("Thick leather wrap to protect knuckles during close combat and shield grips.")))
	slot_feet.pressed.connect(func(): _inspect_slot("Feet", tr("Boots"), tr("Heavy dungeon travel boots protecting feet from acid traps and mud.")))
	
	slot_main_hand.pressed.connect(_on_main_hand_pressed)
	slot_off_hand.pressed.connect(_on_off_hand_pressed)
	slot_back.pressed.connect(func(): _inspect_slot("Back", tr("Back Slot [Empty]"), tr("Can hold spare ranged weapons like Short Bows or Crossbows.")))
	slot_ring.pressed.connect(func(): _inspect_slot("Accessory", tr("Accessory Ring"), tr("Copper signet ring carved with tiny tavern engravings. Increases max stamina slightly.")))
	
	gear_list.item_selected.connect(_on_gear_selected)
	skills_list.item_selected.connect(_on_skill_selected)
	
	# Try to find reference to active player in session
	current_player = GameState.player if GameState.has_method("get_player") else null
	if not current_player and "player" in GameState:
		current_player = GameState.player
		
	_update_ui_translations()
	_setup_slots_text()
	_load_attributes()
	_load_gear_list()
	_load_skills_list()
	
	# Select first item in gear list by default
	if gear_list.item_count > 0:
		gear_list.select(0)
		_on_gear_selected(0)
	else:
		_inspect_dummy_model()

# Fixed 45 degree pose is managed inside _normalize_inspect_scale

func _setup_slots_text() -> void:
	# Check if player has weapons/shields, update text
	if current_player and is_instance_valid(current_player) and current_player.equipment:
		if current_player.equipment.has_weapon():
			slot_main_hand.text = tr("Main Hand\n[%s]") % current_player.equipment.weapon_data.name
		else:
			slot_main_hand.text = tr("Main Hand\n[Fists]")
			
		if current_player.equipment.has_shield():
			slot_off_hand.text = tr("Off Hand\n[%s]") % current_player.equipment.shield_data.name
		else:
			slot_off_hand.text = tr("Off Hand\n[Empty]")
	else:
		slot_main_hand.text = tr("Main Hand\n[Sword]")
		slot_off_hand.text = tr("Off Hand\n[Shield]")

func _load_attributes() -> void:
	# Load HP
	if current_player and is_instance_valid(current_player):
		hp_val.text = tr("%d / %d") % [current_player.health.current_life, current_player.health.max_life]
	else:
		hp_val.text = tr("100 / 100")
			
	# Load Gold
	if TavernManager:
		gold_val.text = tr("%d Gold") % TavernManager.gold
	else:
		gold_val.text = tr("100 Gold")
			
	# Attack stats based on active weapon
	var base_dmg_min = 1
	var base_dmg_max = 2
	var reach = 2.0
	var defense = 0
	
	if current_player and is_instance_valid(current_player) and current_player.equipment:
		if current_player.equipment.has_weapon():
			var w_data = current_player.equipment.weapon_data
			base_dmg_min = w_data.damage_min
			base_dmg_max = w_data.damage_max
			reach = w_data.reach
		if current_player.equipment.has_shield():
			defense = current_player.equipment.shield_data.condition
			
	dmg_val.text = tr("%d - %d Physical") % [base_dmg_min, base_dmg_max]
	reach_val.text = tr("%.1f meters") % reach
	def_val.text = tr("%d Guard Rating") % defense

func _load_gear_list() -> void:
	gear_list.clear()
	
	# Load equipped weapon/shield first
	if current_player and is_instance_valid(current_player) and current_player.equipment:
		if current_player.equipment.has_weapon():
			var w = current_player.equipment.weapon_data
			gear_list.add_item(w.name + tr(" (Equipped)"))
			gear_list.set_item_metadata(gear_list.item_count - 1, {"type": "weapon", "data": w})
		if current_player.equipment.has_shield():
			var s = current_player.equipment.shield_data
			gear_list.add_item(s.name + tr(" (Equipped)"))
			gear_list.set_item_metadata(gear_list.item_count - 1, {"type": "shield", "data": s})

	# Load materials from inventory
	if TavernManager:
		for mat_id in TavernManager.inventory.keys():
			var count = TavernManager.inventory[mat_id]
			if count > 0:
				var mat_name = mat_id.capitalize().replace("_", " ")
				if TavernManager.materials_db.has(mat_id):
					mat_name = tr(TavernManager.materials_db[mat_id]["name"])
				gear_list.add_item("%s (x%d)" % [mat_name, count])
				gear_list.set_item_metadata(gear_list.item_count - 1, {"type": "material", "id": mat_id})
	else:
		# Fallback items if TavernManager is not initialized
		gear_list.add_item("Wild Glowcap (x3)")
		gear_list.set_item_metadata(0, {"type": "material", "id": "wild_glowcap"})
		gear_list.add_item("Frost Berry (x2)")
		gear_list.set_item_metadata(1, {"type": "material", "id": "frost_berry"})

func _load_skills_list() -> void:
	skills_list.clear()
	for i in range(skills_database.size()):
		skills_list.add_item(tr(skills_database[i]["name"]))
	
	if skills_list.item_count > 0:
		skills_list.select(0)
		_on_skill_selected(0)

func _inspect_slot(slot_name: String, item_name: String, desc: String) -> void:
	eq_name_lbl.text = item_name
	eq_dmg_lbl.text = tr("N/A")
	eq_cond_lbl.text = tr("Immutable")
	eq_desc_lbl.text = desc
	
	_inspect_dummy_model()

func _on_main_hand_pressed() -> void:
	if current_player and is_instance_valid(current_player) and current_player.equipment and current_player.equipment.has_weapon():
		var w = current_player.equipment.weapon_data
		_inspect_weapon(w)
	else:
		_inspect_slot("MainHand", tr("Fists"), tr("Bare knuckles. Useful when weapon breaks, but damage reach is extremely limited."))

func _on_off_hand_pressed() -> void:
	if current_player and is_instance_valid(current_player) and current_player.equipment and current_player.equipment.has_shield():
		var s = current_player.equipment.shield_data
		_inspect_shield(s)
	else:
		_inspect_slot("OffHand", tr("Off Hand [Empty]"), tr("Can equip Bucklers or Heater Shields to block incoming strikes."))

func _on_gear_selected(index: int) -> void:
	var meta = gear_list.get_item_metadata(index)
	if not meta:
		return
		
	match meta["type"]:
		"weapon":
			_inspect_weapon(meta["data"])
		"shield":
			_inspect_shield(meta["data"])
		"material":
			_inspect_material(meta["id"])

func _inspect_weapon(w: WeaponData) -> void:
	eq_name_lbl.text = w.name
	eq_dmg_lbl.text = tr("%d - %d Physical") % [w.damage_min, w.damage_max]
	eq_cond_lbl.text = tr("%d / %d") % [w.condition, w.max_condition]
	eq_desc_lbl.text = tr("A close-combat weapon suited for slashing dungeon monsters.")
	
	_spawn_3d_model(w.glb_mesh)

func _inspect_shield(s: ShieldData) -> void:
	eq_name_lbl.text = s.name
	eq_dmg_lbl.text = tr("N/A")
	eq_cond_lbl.text = tr("%d / %d") % [s.condition, s.max_condition]
	eq_desc_lbl.text = tr("A sturdy buckler used to block attacks and stun opponents.")
	
	_spawn_3d_model(s.glb_mesh)

func _inspect_material(mat_id: String) -> void:
	var mat_name = mat_id.capitalize().replace("_", " ")
	var desc = tr("An ingredient collected from the deep dungeon vaults.")
	
	if TavernManager and TavernManager.materials_db.has(mat_id):
		mat_name = tr(TavernManager.materials_db[mat_id]["name"])
		desc = tr(TavernManager.materials_db[mat_id]["desc"])
		
	eq_name_lbl.text = mat_name
	eq_dmg_lbl.text = tr("N/A")
	eq_cond_lbl.text = tr("Material")
	eq_desc_lbl.text = desc
	
	# Load material mesh if available
	var obj_path = "res://assets/models/%s.obj" % mat_id
	if ResourceLoader.exists(obj_path):
		var mesh_res = load(obj_path)
		if mesh_res:
			_spawn_3d_material_mesh(mesh_res, mat_id)
		else:
			_inspect_dummy_model()
	else:
		_inspect_dummy_model()

func _on_skill_selected(index: int) -> void:
	var s = skills_database[index]
	var details = tr("SKILL DETAILS:") + "\n"
	details += "- " + tr("Name:") + " " + tr(s["name"]) + "\n"
	details += "- " + tr("Cooldown:") + " " + tr(s["cooldown"]) + "\n"
	details += "- " + tr("Cost:") + " " + tr(s["cost"]) + "\n\n"
	details += tr("DESCRIPTION:") + "\n" + tr(s["desc"])
	skill_details_val.text = details

func _inspect_dummy_model() -> void:
	if current_eq_mesh and is_instance_valid(current_eq_mesh):
		current_eq_mesh.queue_free()
		current_eq_mesh = null
		
	# Spawn a cozy default chest model in viewport
	var chest_path = "res://assets/models/chest.obj"
	if ResourceLoader.exists(chest_path):
		var mesh_res = load(chest_path)
		_spawn_3d_material_mesh(mesh_res, "chest")

func _spawn_3d_model(mesh_scene: PackedScene) -> void:
	if current_eq_mesh and is_instance_valid(current_eq_mesh):
		current_eq_mesh.queue_free()
		current_eq_mesh = null
		
	if mesh_scene:
		var instance = mesh_scene.instantiate()
		eq_viewport.add_child(instance)
		current_eq_mesh = instance
		_normalize_inspect_scale(instance)

func _spawn_3d_material_mesh(mesh_res: ArrayMesh, mat_id: String) -> void:
	if current_eq_mesh and is_instance_valid(current_eq_mesh):
		current_eq_mesh.queue_free()
		current_eq_mesh = null
		
	if mesh_res:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh_res
		
		# Apply nice albedo color matching material types
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.6, 0.2)
		mat.roughness = 0.5
		
		var lower_id = mat_id.to_lower()
		if "glowcap" in lower_id:
			mat.albedo_color = Color(0.1, 0.5, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.05, 0.2, 0.5)
		elif "berry" in lower_id:
			mat.albedo_color = Color(0.9, 0.1, 0.2)
		elif "bloom" in lower_id:
			mat.albedo_color = Color(1.0, 0.3, 0.0)
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.1, 0.0)
		elif "lichen" in lower_id:
			mat.albedo_color = Color(0.3, 0.6, 0.4)
		elif "honeycomb" in lower_id:
			mat.albedo_color = Color(1.0, 0.7, 0.1)
		elif "grass" in lower_id:
			mat.albedo_color = Color(0.4, 0.8, 0.2)
		elif "chest" in lower_id:
			var chest_mat_path = "res://materials/chest_mat.tres"
			if ResourceLoader.exists(chest_mat_path):
				mi.material_override = load(chest_mat_path)
				mat = null
				
		if mat:
			mi.material_override = mat

		eq_viewport.add_child(mi)
		current_eq_mesh = mi
		_normalize_inspect_scale(mi)

func _normalize_inspect_scale(instance: Node3D) -> void:
	var result: Array[MeshInstance3D] = []
	_gather_meshes(instance, result)
	
	# Apply fixed 45 degree pose rotation on Y axis
	instance.rotation = Vector3(0, deg_to_rad(45), 0)
	
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

func _on_return_pressed() -> void:
	if get_parent() is CanvasLayer and "player" in GameState:
		self.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _update_ui_translations() -> void:
	$PanelContainer/VBoxContainer/Header/Title.text = " " + tr("Character Gear & Quest Log")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn.set_tab_title(0, tr("Items"))
	$PanelContainer/VBoxContainer/MainLayout/RightColumn.set_tab_title(1, tr("Stats"))
	$PanelContainer/VBoxContainer/MainLayout/RightColumn.set_tab_title(2, tr("Skills"))
	return_btn.text = tr("Close Panel")

	# Slot button texts
	slot_head.text = tr("Head\n[Empty]")
	slot_body.text = tr("Chest\n[Leather]")
	slot_hands.text = tr("Hands\n[Gloves]")
	slot_feet.text = tr("Feet\n[Boots]")
	slot_back.text = tr("Back\n[Empty]")
	slot_ring.text = tr("Accessory\n[Ring]")

	# Inspect detail labels
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/物品/VBox/InspectDetails/Grid/LabelName.text = tr("Name:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/物品/VBox/InspectDetails/Grid/LabelStat.text = tr("Power/Dmg:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/物品/VBox/InspectDetails/Grid/LabelCond.text = tr("Condition:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/物品/VBox/InspectDetails/Grid/LabelDesc.text = tr("Description:")

	# Inspect default empty values
	eq_name_lbl.text = tr("No item selected")
	eq_dmg_lbl.text = tr("N/A")
	eq_cond_lbl.text = tr("N/A")
	eq_desc_lbl.text = tr("N/A")

	# Stats tab labels
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Label.text = tr("Hero Specifications")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/HPLbl.text = tr("Life Force (HP):")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/GoldLbl.text = tr("Tavern Funds (Gold):")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/DmgLbl.text = tr("Weapon Damage:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/DefLbl.text = tr("Shield Defense:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/ReachLbl.text = tr("Attack Reach:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/SpeedLbl.text = tr("Attack Speed:")
	# Stats description panel
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DescPanel/VBox/Label.text = tr("Status Lore")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DescPanel/VBox/DescVal.text = tr("A brave adventurer...")

	# Skills tab default
	skill_details_val.text = tr("Select a skill to inspect its parameters...")

	# N/A / Immutable / Material stubs used in inspect callbacks
	# (set dynamically in _inspect_slot/_inspect_material)
