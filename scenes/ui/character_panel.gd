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

# Left Column - Battle Stats Panel (below 3D viewport)
@onready var battle_stats_container: VBoxContainer = %BattleStatsContainer

# 3D Viewport Controls
@onready var eq_viewport: SubViewport = %EqSubViewport
@onready var eq_camera_pivot: Node3D = %EqCameraPivot
@onready var eq_light: DirectionalLight3D = %EqLight

@onready var ap_ref: Node = null  # AttrPanel reference

# Right Column - Tabs
@onready var gear_list: ItemList = %GearList
@onready var eq_name_lbl: Label = %EqNameVal
@onready var eq_dmg_lbl: Label = %EqDmgVal
@onready var eq_cond_lbl: Label = %EqCondVal
@onready var eq_desc_lbl: Label = %EqDescVal

# Right Column - Stats Labels (kept for backward compat)
@onready var hp_val: Label = %HPVal
@onready var gold_val: Label = %GoldVal
@onready var dmg_val: Label = %DmgVal
@onready var def_val: Label = %DefVal
@onready var reach_val: Label = %ReachVal

# Right Column - Skills
@onready var skills_list: ItemList = %SkillsList
@onready var skill_details_val: Label = %SkillDetailsVal

# Right Column - Proficiency
@onready var prof_list: ItemList = %ProfList

var current_player: Player = null
var current_eq_mesh: Node3D = null

# Skills Database
var skills_database: Array = [
	{"name": "Heavy Strike (重击)", "desc": "Channels physical power into a single devastating blow, dealing 150% physical damage. Can stun low-tier enemies on impact.", "cooldown": "6.0 seconds", "cost": "15 Stamina"},
	{"name": "Swift Slash (迅捷回旋)", "desc": "Performs a rapid 360-degree sweep with the main-hand weapon, hitting all nearby monsters and dealing 80% slash damage.", "cooldown": "4.0 seconds", "cost": "10 Stamina"},
	{"name": "Shield Wall (坚盾壁垒)", "desc": "Raises the shield in defense, raising Guard Rating and damage reduction by 100% for 3 seconds. Blocked attacks recovery speed increases.", "cooldown": "12.0 seconds", "cost": "20 Stamina"},
	{"name": "Adrenaline Rush (绝境苏醒)", "desc": "Passive: When HP drops below 30%, increases attack speed, recovery speed and movement speed by 40% until health is restored.", "cooldown": "Passive", "cost": "None"},
]

# 武器/流派中文名映射
const WEAPON_TYPE_NAMES: Dictionary = {
	"one_hand_melee": "单手近战",
	"two_hand": "双手武器",
	"longbow": "长弓",
	"crossbow": "轻弩",
	"wand": "法杖",
	"grimoire": "魔导书",
	"unarmed": "徒手",
}

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
	current_player = GameState.player if GameState != null and GameState.has_method("get_player") else null
	if not current_player and GameState != null and "player" in GameState:
		current_player = GameState.player
	
	# Get AttrPanel reference
	ap_ref = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	
	_update_ui_translations()
	_setup_slots_text()
	_load_attributes()
	_load_gear_list()
	_load_skills_list()
	_refresh_battle_stats()
	_refresh_proficiency()
	
	# Select first item in gear list by default
	if gear_list.item_count > 0:
		gear_list.select(0)
		_on_gear_selected(0)

# ==================== Battle Stats Panel (Left Column) ====================

func _refresh_battle_stats() -> void:
	# 清空并重新生成战斗属性面板
	for c in battle_stats_container.get_children():
		c.queue_free()
	
	if ap_ref == null:
		ap_ref = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap_ref == null:
		var fallback := Label.new()
		fallback.text = tr("AttrPanel not available")
		battle_stats_container.add_child(fallback)
		return
	
	var attrs: Dictionary = ap_ref.get_player_attrs()
	var level: int = ap_ref.get_level()
	
	# 角色信息标题
	var title := Label.new()
	title.text = tr("— Battle Attributes —")
	title.add_theme_font_size_override("font_size", 18)
	battle_stats_container.add_child(title)
	
	# 等级
	_add_stat_row("等级 Lv", str(level))
	
	# 6 属性
	var attr_labels := {
		"str": "STR 力量", "dex": "DEX 敏捷", "mag": "MAG 魔力",
		"con": "CON 体质", "agi": "AGI 灵巧", "per": "PER 感知"
	}
	for key in ["str", "dex", "mag", "con", "agi", "per"]:
		var val: int = int(attrs.get(key, 0))
		_add_stat_row(attr_labels[key], str(val))
	
	# 分隔线
	var sep := HSeparator.new()
	battle_stats_container.add_child(sep)
	
	# 衍生面板数值
	_add_stat_row("HP 上限", str(ap_ref.compute_max_hp()))
	_add_stat_row("物防", str(ap_ref.compute_physical_def()))
	_add_stat_row("闪避率", "%.1f%%" % ap_ref.compute_evade_rate())
	_add_stat_row("暴击率", "%.1f%%" % ap_ref.compute_crit_rate())
	_add_stat_row("移速倍率", "%.0f%%" % (ap_ref.compute_move_speed_mult() * 100.0))
	_add_stat_row("负重上限", str(ap_ref.compute_carry_weight()))
	
	# 分隔线
	var sep2 := HSeparator.new()
	battle_stats_container.add_child(sep2)
	
	# 已解锁里程碑
	var ms_title := Label.new()
	ms_title.text = tr("— Passive Milestones —")
	ms_title.add_theme_font_size_override("font_size", 16)
	battle_stats_container.add_child(ms_title)
	
	var ms_list := ""
	if ap_ref.unlocked_milestones.size() > 0:
		for ms in ap_ref.unlocked_milestones:
			ms_list += "• %s\n" % ms
	else:
		ms_list = tr("(None unlocked yet)")
	var ms_label := Label.new()
	ms_label.text = ms_list
	ms_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battle_stats_container.add_child(ms_label)

func _add_stat_row(label_text: String, value_text: String) -> void:
	var hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := Label.new()
	val.text = value_text
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	hbox.add_child(lbl)
	hbox.add_child(val)
	battle_stats_container.add_child(hbox)

# ==================== Proficiency Tab ====================

func _refresh_proficiency() -> void:
	prof_list.clear()
	if ap_ref == null:
		ap_ref = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap_ref == null:
		prof_list.add_item(tr("AttrPanel not available"))
		return
	
	var prof: Dictionary = ap_ref.weapon_proficiency
	if prof.is_empty():
		prof_list.add_item(tr("— No proficiency data yet —"))
		return
	
	# 按已知武器类型排序输出
	var type_order: Array = ["one_hand_melee", "two_hand", "longbow", "crossbow", "wand", "grimoire", "unarmed"]
	for wt in type_order:
		var label: String = WEAPON_TYPE_NAMES.get(wt, wt)
		var val: int = int(prof.get(wt, 0))
		prof_list.add_item("%s: 熟练度 Lv %d" % [label, val])

# ==================== Existing Functions ====================

func _setup_slots_text() -> void:
	if current_player and is_instance_valid(current_player) and current_player.equipment:
		if current_player.equipment.has_weapon():
			slot_main_hand.text = tr("Main Hand\n[%s]") % current_player.equipment.weapon_data.get_full_display_name()
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
	if current_player and is_instance_valid(current_player):
		hp_val.text = tr("%d / %d") % [current_player.health.current_life, current_player.health.max_life]
	else:
		hp_val.text = tr("100 / 100")
	if TavernManager:
		gold_val.text = tr("%d Gold") % TavernManager.gold
	else:
		gold_val.text = tr("100 Gold")
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
	if current_player and is_instance_valid(current_player) and current_player.equipment:
		if current_player.equipment.has_weapon():
			var w = current_player.equipment.weapon_data
			gear_list.add_item(w.name + tr(" (Equipped)"))
			gear_list.set_item_metadata(gear_list.item_count - 1, {"type": "weapon", "data": w})
		if current_player.equipment.has_shield():
			var s = current_player.equipment.shield_data
			gear_list.add_item(s.name + tr(" (Equipped)"))
			gear_list.set_item_metadata(gear_list.item_count - 1, {"type": "shield", "data": s})
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
		_inspect_weapon(current_player.equipment.weapon_data)
	else:
		_inspect_slot("MainHand", tr("Fists"), tr("Bare knuckles. Useful when weapon breaks, but damage reach is extremely limited."))

func _on_off_hand_pressed() -> void:
	if current_player and is_instance_valid(current_player) and current_player.equipment and current_player.equipment.has_shield():
		_inspect_shield(current_player.equipment.shield_data)
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

func _inspect_weapon(w) -> void:
	eq_name_lbl.text = w.name
	eq_dmg_lbl.text = tr("%d - %d Physical") % [w.damage_min, w.damage_max]
	eq_cond_lbl.text = tr("%d / %d") % [w.condition, w.max_condition]
	eq_desc_lbl.text = tr("A close-combat weapon suited for slashing dungeon monsters.")
	# 显示角色持该武器，并从当前玩家复制盾牌
	var shield_data = null
	if current_player != null and is_instance_valid(current_player) and current_player.equipment != null and current_player.equipment.has_shield():
		shield_data = current_player.equipment.shield_data
	_spawn_preview_character(w, shield_data)

func _inspect_shield(s) -> void:
	eq_name_lbl.text = s.name
	eq_dmg_lbl.text = tr("N/A")
	eq_cond_lbl.text = tr("%d / %d") % [s.condition, s.max_condition]
	eq_desc_lbl.text = tr("A sturdy buckler used to block attacks and stun opponents.")
	# 显示角色持该盾，并从当前玩家复制武器
	var weapon_data = null
	if current_player != null and is_instance_valid(current_player) and current_player.equipment != null and current_player.equipment.has_weapon():
		weapon_data = current_player.equipment.weapon_data
	_spawn_preview_character(weapon_data, s)

func _inspect_material(mat_id: String) -> void:
	var mat_name = mat_id.capitalize().replace("_", " ")
	var desc = tr("An ingredient collected from the deep dungeon vaults.")
	if TavernManager and TavernManager.materials_db.has(mat_id):
		mat_name = tr(TavernManager.materials_db[mat_id]["name"])
		desc = tr(TavernManager.materials_db[mat_id].get("desc", "An ingredient collected from the deep dungeon vaults."))
	eq_name_lbl.text = mat_name
	eq_dmg_lbl.text = tr("N/A")
	eq_cond_lbl.text = tr("Material")
	eq_desc_lbl.text = desc

	# Load material GLB model if available
	var glb_path := MaterialModelRegistry.get_model_path(mat_id)
	if glb_path.is_empty():
		glb_path = "res://assets/models/materials/materials_%s.glb" % mat_id
	if ResourceLoader.exists(glb_path):
		var packed_scene := load(glb_path) as PackedScene
		if packed_scene:
			var instance := packed_scene.instantiate() as Node3D
			if instance:
				_spawn_3d_material_glb(instance)
			else:
				_inspect_dummy_model()
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
	$PanelContainer/VBoxContainer/MainLayout/RightColumn.set_tab_title(3, tr("Proficiency"))
	return_btn.text = tr("Close Panel")
	slot_head.text = tr("Head\n[Empty]")
	slot_body.text = tr("Chest\n[Leather]")
	slot_hands.text = tr("Hands\n[Gloves]")
	slot_feet.text = tr("Feet\n[Boots]")
	slot_back.text = tr("Back\n[Empty]")
	slot_ring.text = tr("Accessory\n[Ring]")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/物品/VBox/InspectDetails/Grid/LabelName.text = tr("Name:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/物品/VBox/InspectDetails/Grid/LabelStat.text = tr("Power/Dmg:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/物品/VBox/InspectDetails/Grid/LabelCond.text = tr("Condition:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/物品/VBox/InspectDetails/Grid/LabelDesc.text = tr("Description:")
	eq_name_lbl.text = tr("No item selected")
	eq_dmg_lbl.text = tr("N/A")
	eq_cond_lbl.text = tr("N/A")
	eq_desc_lbl.text = tr("N/A")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Label.text = tr("Hero Specifications")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/HPLbl.text = tr("Life Force (HP):")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/GoldLbl.text = tr("Tavern Funds (Gold):")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/DmgLbl.text = tr("Weapon Damage:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/DefLbl.text = tr("Shield Defense:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/ReachLbl.text = tr("Attack Reach:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DetailsPanel/VBox/Grid/SpeedLbl.text = tr("Attack Speed:")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DescPanel/VBox/Label.text = tr("Status Lore")
	$PanelContainer/VBoxContainer/MainLayout/RightColumn/属性/HBox/DescPanel/VBox/DescVal.text = tr("A brave adventurer...")
	skill_details_val.text = tr("Select a skill to inspect its parameters...")

# 3D Preview Functions — 显示玩家角色模型+装备

const PLAYER_PREFAB := preload("res://scenes/characters/player/player.tscn")

func _inspect_dummy_model() -> void:
	# 无装备时显示基础角色
	_spawn_preview_character(null, null)

func _spawn_3d_model(mesh_scene: PackedScene) -> void:
	# 旧接口：由 _inspect_weapon/_inspect_shield 调用，改为显示角色+装备
	pass

func _spawn_3d_material_glb(instance: Node3D) -> void:
	# 材料预览：显示体素 GLB 模型
	_clear_preview()
	eq_viewport.add_child(instance)
	current_eq_mesh = instance
	# 居中缩放模型
	var aabb := AABB()
	var mesh_instances := _find_all_mesh_instances(instance)
	if not mesh_instances.is_empty():
		aabb = mesh_instances[0].get_aabb()
		for i in range(1, mesh_instances.size()):
			aabb = aabb.merge(mesh_instances[i].get_aabb())
		var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		if max_dim > 0:
			var scale_factor = 1.5 / max_dim
			instance.scale = Vector3(scale_factor, scale_factor, scale_factor)
			instance.position = Vector3(0, -aabb.position.y * scale_factor, 0)

func _find_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_mesh_instances(child))
	return result

func _clear_preview() -> void:
	if current_eq_mesh and is_instance_valid(current_eq_mesh):
		current_eq_mesh.queue_free()
		current_eq_mesh = null

func _spawn_preview_character(weapon_data, shield_data) -> void:
	_clear_preview()
	
	var player_instance := PLAYER_PREFAB.instantiate() as Player
	if player_instance == null:
		return
	var game_state: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	var previous_player: Player = game_state.current_player if game_state != null and "current_player" in game_state else null
	
	# 先加到视口激活 _ready，确保所有 @onready 变量初始化
	eq_viewport.add_child(player_instance)
	if game_state != null and "current_player" in game_state:
		game_state.current_player = previous_player
	current_eq_mesh = player_instance
	player_instance.position = Vector3(0, -0.8, 0)
	player_instance.rotation = Vector3(0, deg_to_rad(45), 0)
	
	# 此时 @onready 变量可用：关闭 UI 信号、移除多余组件
	if player_instance.equipment:
		player_instance.equipment.is_linked_to_ui = false
	if player_instance.camera:
		player_instance.camera.queue_free()
	var cs := player_instance.get_node_or_null("CollisionShape3D")
	if cs:
		cs.queue_free()
	for path in ["SelectRaycast", "KickRaycast", "WeaponReachRaycast"]:
		var n := player_instance.get_node_or_null(path)
		if n:
			n.queue_free()
	
	# 装备武器和盾牌（不发送 UI 信号）
	if weapon_data != null and player_instance.equipment:
		player_instance.equipment.configure_weapon_slot(0, weapon_data, true)
	if shield_data != null and player_instance.equipment:
		player_instance.equipment.equip_shield(shield_data)
	
	if player_instance.animation_player and player_instance.animation_player.has_animation("idle"):
		player_instance.animation_player.play("idle")

func _remove_preview_unnecessary(player_instance: Player) -> void:
	# 移除摄像机
	if player_instance.camera:
		player_instance.camera.queue_free()
	# 移除碰撞形状
	var cs := player_instance.get_node_or_null("CollisionShape3D")
	if cs:
		cs.queue_free()
	# 移除射线
	var to_remove := ["SelectRaycast", "KickRaycast", "WeaponReachRaycast"]
	for path in to_remove:
		var n := player_instance.get_node_or_null(path)
		if n:
			n.queue_free()
