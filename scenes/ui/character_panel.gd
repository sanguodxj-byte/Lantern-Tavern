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

## 使用 Variant 以支持测试中注入 mock player（运行时动态分派 .equipment / .health）。
## 生产环境中 GameState.player 返回真实 Player 实例。
var current_player: Variant = null
var current_eq_mesh: Node3D = null

# ── 拖拽支持 ──────────────────────────────────────────────────────────────
const DROP_ZONE_SCRIPT := preload("res://scenes/ui/loot_drop_zone.gd")
const DRAG_THRESHOLD := 8.0

## 装备槽定义 — key 对齐 EquipmentComponent API:
##   armor 槽: head/body/hands/feet (armor_slots 字典 key)
##   weapon 槽: weapon_0..3 (weapon_slots 数组索引)
##   node_var: 对应 @onready 变量名
const SLOT_DEFS: Array = [
	{"key": "head", "node": "slot_head", "tr_key": "EQ_SLOT_HEAD", "kind": "armor"},
	{"key": "body", "node": "slot_body", "tr_key": "EQ_SLOT_CHEST", "kind": "armor"},
	{"key": "hands", "node": "slot_hands", "tr_key": "EQ_SLOT_HANDS", "kind": "armor"},
	{"key": "feet", "node": "slot_feet", "tr_key": "EQ_SLOT_FEET", "kind": "armor"},
	{"key": "weapon_0", "node": "slot_main_hand", "tr_key": "EQ_SLOT_MAIN", "kind": "weapon", "index": 0},
	{"key": "weapon_1", "node": "slot_off_hand", "tr_key": "EQ_SLOT_OFF", "kind": "weapon", "index": 1},
	{"key": "weapon_2", "node": "slot_back", "tr_key": "EQ_SLOT_BACK", "kind": "weapon", "index": 2},
	{"key": "weapon_3", "node": "slot_ring", "tr_key": "EQ_SLOT_ACC", "kind": "weapon", "index": 3},
]

## 拖放状态
var _slot_drag_start_pos: Vector2 = Vector2.ZERO
var _slot_drag_key: String = ""
var _gear_drag_start_pos: Vector2 = Vector2.ZERO
var _gear_drag_index: int = -1

@onready var equip_slots_container: VBoxContainer = $PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipmentSlots

# Skills Database
var skills_database: Array = [
	{"name": "Heavy Strike (重击)", "desc": "Channels physical power into a single devastating blow, dealing 150% physical damage. Can stun low-tier enemies on impact.", "cooldown": "6.0 seconds", "cost": "None"},
	{"name": "Swift Slash (迅捷回旋)", "desc": "Performs a rapid 360-degree sweep with the main-hand weapon, hitting all nearby monsters and dealing 80% slash damage.", "cooldown": "4.0 seconds", "cost": "None"},
	{"name": "Shield Wall (坚盾壁垒)", "desc": "Raises the shield in defense, raising Guard Rating and damage reduction by 100% for 3 seconds. Blocked attacks recovery speed increases.", "cooldown": "12.0 seconds", "cost": "None"},
	{"name": "Adrenaline Rush (绝境苏醒)", "desc": "Passive: When HP drops below 30%, increases attack speed, recovery speed and movement speed by 40% until health is restored.", "cooldown": "Passive", "cost": "None"},
]

# 武器/流派中文名映射
var WEAPON_TYPE_NAMES: Dictionary = {
	"one_hand_melee": tr("单手近战"),
	"two_hand": tr("双手武器"),
	"longbow": tr("长弓"),
	"crossbow": tr("轻弩"),
	"wand": tr("法杖"),
	"grimoire": tr("魔导书"),
	"unarmed": tr("徒手"),
}

func _ready() -> void:
	add_to_group("character_panel")
	theme = preload("res://scenes/ui/lantern_theme.tres")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return_btn.pressed.connect(_on_return_pressed)
	
	# Connect slots signals — 点击检视
	slot_head.pressed.connect(func(): _inspect_slot("Head", tr("Head Armor"), tr("Basic adventuring hood providing minimal defense but high comfort.")))
	slot_body.pressed.connect(func(): _inspect_slot("Chest", tr("Chest Armor (Leather)"), tr("Reinforced leather tunic, offering decent protection against bites and scratches.")))
	slot_hands.pressed.connect(func(): _inspect_slot("Hands", tr("Gloves"), tr("Thick leather wrap to protect knuckles during close combat and shield grips.")))
	slot_feet.pressed.connect(func(): _inspect_slot("Feet", tr("Boots"), tr("Heavy dungeon travel boots protecting feet from acid traps and mud.")))
	
	slot_main_hand.pressed.connect(_on_main_hand_pressed)
	slot_off_hand.pressed.connect(_on_off_hand_pressed)
	slot_back.pressed.connect(func(): _inspect_slot("Back", tr("Back Slot [Empty]"), tr("Can hold spare ranged weapons like Short Bows or Crossbows.")))
	slot_ring.pressed.connect(func(): _inspect_slot("Accessory", tr("Accessory Ring"), tr("Copper signet ring carved with tiny tavern engravings. Increases max health slightly.")))
	
	gear_list.item_selected.connect(_on_gear_selected)
	skills_list.item_selected.connect(_on_skill_selected)
	
	# Try to find reference to active player in session
	current_player = GameState.player if GameState != null and GameState.has_method("get_player") else null
	if not current_player and GameState != null and "player" in GameState:
		current_player = GameState.player
	
	ap_ref = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	
	_update_ui_translations()
	_setup_slots_text()
	_load_attributes()
	_load_gear_list()
	_load_skills_list()
	_refresh_battle_stats()
	_refresh_proficiency()
	
	# 拖放支持：装备槽和背包容器设为 drop zone
	_setup_drop_zone(equip_slots_container, "equipment")
	_setup_drop_zone(gear_list, "backpack")
	# 装备槽按钮监听 gui_input 以检测拖出手势
	for slot_def in SLOT_DEFS:
		var btn: Button = get(slot_def["node"])
		if btn != null:
			btn.gui_input.connect(_on_slot_gui_input.bind(btn, slot_def["key"]))
	# 背包列表监听 gui_input 以检测拖出手势
	gear_list.gui_input.connect(_on_gear_list_gui_input)

	# Select first item in gear list by default
	if gear_list.item_count > 0:
		gear_list.select(0)
		_on_gear_selected(0)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or (key_event.keycode != KEY_ESCAPE and key_event.keycode != KEY_TAB):
		return
	get_viewport().set_input_as_handled()
	_on_return_pressed()

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
	_add_stat_row(tr("等级 Lv"), str(level))
	
	# 6 属性
	var attr_labels := {
		"str": tr("STR 力量"), "dex": tr("DEX 敏捷"), "mag": tr("MAG 魔力"),
		"con": tr("CON 体质"), "agi": tr("AGI 灵巧"), "per": tr("PER 感知")
	}
	for key in ["str", "dex", "mag", "con", "agi", "per"]:
		var val: int = int(attrs.get(key, 0))
		_add_stat_row(attr_labels[key], str(val))
	
	# 分隔线
	var sep := HSeparator.new()
	battle_stats_container.add_child(sep)
	
	# 衍生面板数值
	_add_stat_row(tr("HP 上限"), str(ap_ref.compute_max_hp()))
	_add_stat_row(tr("物防"), str(ap_ref.compute_physical_def()))
	_add_stat_row(tr("闪避率"), "%.1f%%" % ap_ref.compute_evade_rate())
	_add_stat_row(tr("暴击率"), "%.1f%%" % ap_ref.compute_crit_rate())
	_add_stat_row(tr("移速倍率"), "%.0f%%" % (ap_ref.compute_move_speed_mult() * 100.0))
	_add_stat_row(tr("负重上限"), str(ap_ref.compute_carry_weight()))
	
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
		prof_list.add_item(tr("%s: 熟练度 Lv %d") % [label, val])

# ==================== Existing Functions ====================

func _setup_slots_text() -> void:
	# 所有 8 个装备槽统一从 EquipmentComponent 读取真实数据（数据源唯一）
	for slot_def in SLOT_DEFS:
		var btn: Button = get(slot_def["node"])
		if btn == null:
			continue
		_setup_slot_icon_display(btn)
		var kind: String = slot_def["kind"]
		var key: String = slot_def["key"]
		var data = null
		if current_player != null and is_instance_valid(current_player) and current_player.equipment != null:
			var eq = current_player.equipment
			if kind == "armor":
				if eq.has_method("get_armor_slot_data"):
					data = eq.get_armor_slot_data(key)
			else:
				var idx: int = int(slot_def.get("index", 0))
				if idx == 0 and eq.has_method("has_weapon") and eq.has_weapon():
					data = eq.weapon_data
				elif idx == 1 and eq.has_method("has_shield") and eq.has_shield():
					data = eq.shield_data
				elif eq.has_method("get_weapon_slot_data"):
					data = eq.get_weapon_slot_data(idx)
		_apply_slot_display(btn, slot_def, data)

## 将装备数据应用到槽位按钮显示
func _apply_slot_display(btn: Button, slot_def: Dictionary, data) -> void:
	var label_text: String = tr(slot_def.get("tr_key", slot_def["key"]))
	if data != null:
		var display_name = data.get_full_display_name() if data.has_method("get_full_display_name") else data.name
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_equipment_id(String(data.id)) if WeaponRegistry != null else null
		if icon != null:
			btn.icon = icon
			btn.text = ""
		else:
			btn.icon = null
			btn.text = "%s\n[%s]" % [label_text, display_name]
		btn.tooltip_text = _build_equipment_tooltip(display_name, data)
		btn.modulate = _affix_color_for(data)
	else:
		btn.icon = null
		btn.text = "%s\n[%s]" % [label_text, tr("Empty")]
		btn.tooltip_text = ""
		btn.modulate = Color.WHITE

## 词缀品质色
func _affix_color_for(data) -> Color:
	if data == null or not "affixes" in data or data.affixes.is_empty():
		return Color.WHITE
	return WeaponData.get_affix_color(data.affixes)

## 配置装备槽按钮的图标显示属性
func _setup_slot_icon_display(button: Button) -> void:
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

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
	# 配置为网格图标模式
	gear_list.icon_mode = ItemList.ICON_MODE_TOP
	gear_list.fixed_icon_size = Vector2i(64, 64)
	gear_list.max_columns = 0  # 自动换行
	gear_list.same_column_width = true
	gear_list.fixed_column_width = 80
	# 背包列表显示玩家携带的未装备物品（GameState carried equipment）
	# 与酒馆面板/宝箱面板同一数据源，确保数据唯一
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs != null and gs.has_method("get_carried_equipment_dict"):
		var carried: Dictionary = gs.get_carried_equipment_dict()
		for equip_id in carried.keys():
			var count: int = int(carried[equip_id])
			if count <= 0:
				continue
			var data: WeaponData = null
			if gs.has_method("get_carried_equipment_instance"):
				data = gs.get_carried_equipment_instance(equip_id)
			if data == null and WeaponRegistry != null:
				data = WeaponRegistry.get_weapon_data(equip_id)
			if data == null:
				continue
			var display_name = data.get_full_display_name() if data.has_method("get_full_display_name") else data.name
			var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_equipment_id(equip_id) if WeaponRegistry != null else null
			var label_text := "x%d" % count if count > 1 else ""
			var idx: int = gear_list.add_item(label_text, icon)
			gear_list.set_item_metadata(idx, {"type": "equipment", "id": equip_id, "count": count, "data": data})
			gear_list.set_item_tooltip(idx, _build_equipment_tooltip(display_name, data))

## 构建装备 tooltip（含词缀信息）
func _build_equipment_tooltip(display_name: String, data) -> String:
	var parts: Array[String] = [display_name]
	if data != null and "affixes" in data and not data.affixes.is_empty():
		var quality_label := WeaponData.get_affix_quality_label(data.affixes)
		if not quality_label.is_empty():
			parts.append("[%s]" % quality_label)
		for affix_line in WeaponData.get_affix_detail_lines(data.affixes):
			parts.append(affix_line)
	return "\n".join(parts)

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
	match meta.get("type", ""):
		"equipment":
			var data = meta.get("data", null)
			if data != null:
				# 判定装备类型：护甲 / 盾 / 武器
				# 使用 equipment_category / item_tag 判定，与 EquipmentComponent._is_armor_equipment 同源
				if data.equipment_category.begins_with("armor") or data.item_tag.begins_with("armor"):
					_inspect_armor(data)
				elif data.item_tag == "shield" or data.equipment_category == "shields":
					_inspect_shield(data)
				else:
					_inspect_weapon(data)
		"weapon":
			_inspect_weapon(meta["data"])
		"shield":
			_inspect_shield(meta["data"])
		"material":
			_inspect_material(meta["id"])

func _inspect_weapon(w) -> void:
	# 使用含词缀前缀的完整显示名
	var display_name = w.get_full_display_name() if w.has_method("get_full_display_name") else w.name
	eq_name_lbl.text = display_name
	# 根据词缀品质设置名称颜色
	if "affixes" in w and not w.affixes.is_empty():
		eq_name_lbl.add_theme_color_override("font_color", WeaponData.get_affix_color(w.affixes))
	else:
		eq_name_lbl.remove_theme_color_override("font_color")
	eq_dmg_lbl.text = tr("%d - %d Physical") % [w.damage_min, w.damage_max]
	eq_cond_lbl.text = tr("%d / %d") % [w.condition, w.max_condition]
	# 描述中包含词缀效果
	var desc := tr("A close-combat weapon suited for slashing dungeon monsters.")
	if "affixes" in w and not w.affixes.is_empty():
		var affix_lines := WeaponData.get_affix_detail_lines(w.affixes)
		if not affix_lines.is_empty():
			desc += "\n" + "\n".join(affix_lines)
	eq_desc_lbl.text = desc
	# 显示角色持该武器，并从当前玩家复制盾牌
	var shield_data = null
	if current_player != null and is_instance_valid(current_player) and current_player.equipment != null and current_player.equipment.has_shield():
		shield_data = current_player.equipment.shield_data
	_spawn_preview_character(w, shield_data)

func _inspect_shield(s) -> void:
	var display_name = s.get_full_display_name() if s.has_method("get_full_display_name") else s.name
	eq_name_lbl.text = display_name
	if "affixes" in s and not s.affixes.is_empty():
		eq_name_lbl.add_theme_color_override("font_color", WeaponData.get_affix_color(s.affixes))
	else:
		eq_name_lbl.remove_theme_color_override("font_color")
	eq_dmg_lbl.text = tr("N/A")
	eq_cond_lbl.text = tr("%d / %d") % [s.condition, s.max_condition]
	var desc := tr("A sturdy buckler used to block attacks and stun opponents.")
	if "affixes" in s and not s.affixes.is_empty():
		var affix_lines := WeaponData.get_affix_detail_lines(s.affixes)
		if not affix_lines.is_empty():
			desc += "\n" + "\n".join(affix_lines)
	eq_desc_lbl.text = desc
	# 显示角色持该盾，并从当前玩家复制武器
	var weapon_data = null
	if current_player != null and is_instance_valid(current_player) and current_player.equipment != null and current_player.equipment.has_weapon():
		weapon_data = current_player.equipment.weapon_data
	_spawn_preview_character(weapon_data, s)

func _inspect_material(mat_id: String) -> void:
	var mat_name = load("res://globals/tavern/brewing_data.gd").get_material_name(String(mat_id))
	var desc = tr("An ingredient collected from the deep dungeon vaults.")
	if TavernManager and TavernManager.materials_db.has(mat_id):
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

const DETAIL_POPUP_SCRIPT := preload("res://scenes/ui/equipment_detail_popup.gd")
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
	# 标记为装备预览实例：Player._ready 检测此 meta 后跳过 GameState.register_player，
	# 避免预览实例覆盖真实 current_player。必须在 add_child 前设置以在 _ready 前生效。
	player_instance.set_meta("equipment_preview", true)

	# 先加到视口激活 _ready，确保所有 @onready 变量初始化
	eq_viewport.add_child(player_instance)
	current_eq_mesh = player_instance
	player_instance.position = Vector3(0, -0.8, 0)
	player_instance.rotation = Vector3(0, deg_to_rad(225), 0)
	
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


# ============================================================================
# 护甲检视
# ============================================================================

## 检视护甲装备 — 显示护甲属性和词缀
func _inspect_armor(a) -> void:
	var display_name = a.get_full_display_name() if a.has_method("get_full_display_name") else a.name
	eq_name_lbl.text = display_name
	if "affixes" in a and not a.affixes.is_empty():
		eq_name_lbl.add_theme_color_override("font_color", WeaponData.get_affix_color(a.affixes))
	else:
		eq_name_lbl.remove_theme_color_override("font_color")
	eq_dmg_lbl.text = tr("Defense %d") % int(a.armor_phys_def)
	eq_cond_lbl.text = tr("%d / %d") % [a.condition, a.max_condition]
	var desc := tr("Protective armor worn by the adventurer.")
	if "armor_type" in a and not String(a.armor_type).is_empty():
		desc += " [" + tr(String(a.armor_type).capitalize()) + "]"
	if "affixes" in a and not a.affixes.is_empty():
		var affix_lines := WeaponData.get_affix_detail_lines(a.affixes)
		if not affix_lines.is_empty():
			desc += "\n" + "\n".join(affix_lines)
	eq_desc_lbl.text = desc
	# 护甲不显示武器/盾预览，仅显示角色模型
	_spawn_preview_character(null, null)


# ============================================================================
# 拖放支持 — 装备槽拖出 + 背包列表拖出 + drop zone 接收
# 所有数据操作经 EquipmentComponent + GameState，确保数据源唯一。
# ============================================================================

## 将节点设置为拖放目标，附加 loot_drop_zone.gd 脚本并记录面板引用
func _setup_drop_zone(node: Control, zone_id: String) -> void:
	if node == null:
		return
	node.set_script(DROP_ZONE_SCRIPT)
	node.set_meta("drop_panel", self)
	node.set_meta("zone_id", zone_id)


## 装备槽 gui_input: 检测从装备槽拖出（卸下到背包）
func _on_slot_gui_input(event: InputEvent, btn: Button, slot_key: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_slot_drag_start_pos = event.position
			_slot_drag_key = slot_key
		else:
			_slot_drag_key = ""
	elif event is InputEventMouseMotion and _slot_drag_key != "":
		if event.position.distance_to(_slot_drag_start_pos) > DRAG_THRESHOLD:
			var data: WeaponData = _get_slot_data(slot_key)
			if data != null:
				var payload: Dictionary = {
					"source": "equipment",
					"type": "equipment",
					"slot_key": slot_key,
					"data": data,
				}
				var preview := Label.new()
				preview.text = String(data.get_full_display_name()) if data.has_method("get_full_display_name") else slot_key
				btn.force_drag(payload, preview)
			_slot_drag_key = ""


## 背包列表 gui_input: 检测拖动手势并发起 force_drag；右键快速装备
func _on_gear_list_gui_input(event: InputEvent) -> void:
	# 右键快速装备
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var index := gear_list.get_item_at_position(event.position, true)
		if index < 0 or index >= gear_list.item_count:
			return
		var meta = gear_list.get_item_metadata(index)
		if typeof(meta) != TYPE_DICTIONARY or meta.get("type", "") != "equipment":
			return
		gear_list.select(index)
		_equip_from_backpack(String(meta.get("id", "")))
		_refresh_after_change()
		get_viewport().set_input_as_handled()
		return
	# 左键拖动检测
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_gear_drag_start_pos = event.position
			_gear_drag_index = 0  # 标记拖动进行中
		else:
			_gear_drag_index = -1
	elif event is InputEventMouseMotion and _gear_drag_index >= 0:
		if event.position.distance_to(_gear_drag_start_pos) > DRAG_THRESHOLD:
			var idx := gear_list.get_item_at_position(_gear_drag_start_pos, true)
			if idx >= 0 and idx < gear_list.item_count:
				var meta = gear_list.get_item_metadata(idx)
				if typeof(meta) == TYPE_DICTIONARY and meta.get("type", "") == "equipment":
					_start_gear_drag(meta)
			_gear_drag_index = -1


## 从背包列表发起拖放
func _start_gear_drag(meta: Dictionary) -> void:
	var payload: Dictionary = {
		"source": "backpack",
		"type": "equipment",
		"id": String(meta.get("id", "")),
	}
	var preview := Label.new()
	var data = meta.get("data", null)
	if data != null and data.has_method("get_full_display_name"):
		preview.text = String(data.get_full_display_name())
	else:
		preview.text = String(meta.get("id", ""))
	gear_list.force_drag(payload, preview)


## drop zone 回调: 判断是否可接收拖放
## 角色面板仅支持面板内拖放（背包 ↔ 装备槽），不支持跨面板。
func can_drop_to_zone(zone_id: String, data: Dictionary) -> bool:
	var source := String(data.get("source", ""))
	var item_type := String(data.get("type", ""))
	match zone_id:
		"equipment":
			# 接收来自背包的装备拖放（装备到玩家）
			return source == "backpack" and item_type == "equipment"
		"backpack":
			# 接收来自装备槽的拖放（卸下到背包）
			return source == "equipment" and item_type == "equipment"
	return false


## drop zone 回调: 处理拖放
func drop_to_zone(zone_id: String, data: Dictionary) -> void:
	var source := String(data.get("source", ""))
	match zone_id:
		"equipment":
			if source == "backpack":
				var item_id := String(data.get("id", ""))
				_equip_from_backpack(item_id)
		"backpack":
			if source == "equipment":
				var slot_key := String(data.get("slot_key", ""))
				_unequip_slot_to_backpack(slot_key)
	_refresh_after_change()


# ============================================================================
# 装备 / 卸下 — 数据源唯一: EquipmentComponent + GameState
# ============================================================================

## 从背包装备到玩家身上。
## 使用 configure_armor_slot / configure_weapon_slot 直接配置槽位，
## 旧装备先放回背包，新装备从背包移除。
## 装备变更同步持久化到 GameState，与酒馆面板/宝箱面板同源。
func _equip_from_backpack(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	if current_player == null or not is_instance_valid(current_player):
		return false
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return false
	var equip = current_player.equipment
	if equip == null:
		return false
	# 从背包取出装备实例（保留词缀/耐久）
	var data: WeaponData = null
	if gs.has_method("remove_carried_equipment_instance"):
		data = gs.remove_carried_equipment_instance(item_id)
	if data == null:
		if WeaponRegistry != null:
			data = WeaponRegistry.get_weapon_data(item_id)
		if data == null:
			return false
		if gs.has_method("remove_carried_equipment"):
			gs.remove_carried_equipment(item_id, 1)
	# 判定类型并分流装备
	var equipped: bool = false
	if equip.has_method("is_armor_equipment") and equip.is_armor_equipment(data):
		equipped = _configure_armor_from_backpack(equip, data)
	elif equip.has_method("configure_weapon_slot"):
		equipped = _configure_weapon_from_backpack(equip, data)
	if not equipped:
		# 装备失败，放回背包
		gs.add_carried_equipment_instance(data)
		return false
	# 持久化装备变更到 GameState（与酒馆面板/宝箱面板同源）
	if gs.has_method("save_equipment_from_player"):
		gs.save_equipment_from_player(current_player)
	return true


## 从背包装备护甲到玩家身上（使用 configure_armor_slot 直接配置）。
## 旧护甲先放回背包，避免物理掉落物。
func _configure_armor_from_backpack(equip: Node, data: WeaponData) -> bool:
	if equip == null or data == null:
		return false
	if not equip.has_method("configure_armor_slot"):
		return false
	var target_slot := String(data.armor_slot)
	if target_slot.is_empty():
		target_slot = "body"
	# 旧护甲放回背包
	if equip.has_method("get_armor_slot_data"):
		var existing: WeaponData = equip.get_armor_slot_data(target_slot)
		if existing != null:
			_add_equipment_to_backpack(existing)
	return equip.configure_armor_slot(target_slot, data)


## 从背包装备武器到玩家身上（使用 configure_weapon_slot 直接配置）。
## 角色面板基于 zone 拖放，用户无法选择具体槽位，因此始终替换当前激活槽
## （主手），旧武器先放回背包。若用户想填入空槽可使用酒馆面板的槽位按钮。
func _configure_weapon_from_backpack(equip: Node, data: WeaponData) -> bool:
	if equip == null or data == null:
		return false
	if not equip.has_method("configure_weapon_slot"):
		return false
	var target_idx := int(equip.active_weapon_slot) if "active_weapon_slot" in equip else 0
	if equip.has_method("get_weapon_slot_data"):
		var existing: WeaponData = equip.get_weapon_slot_data(target_idx)
		if existing != null:
			# 同 id 武器不重复装备，直接激活
			if String(existing.id) == String(data.id):
				return true
			_add_equipment_to_backpack(existing)
	return equip.configure_weapon_slot(target_idx, data, true)


## 卸下指定槽位装备到背包（拖放 / 右键路径）
func _unequip_slot_to_backpack(slot_key: String) -> void:
	if slot_key.is_empty():
		return
	if current_player == null or not is_instance_valid(current_player):
		return
	var equip = current_player.equipment
	if equip == null:
		return
	var slot_def := _find_slot_def(slot_key)
	if slot_def.is_empty():
		return
	var kind: String = String(slot_def.get("kind", ""))
	var data: WeaponData = _get_slot_data(slot_key)
	if data == null:
		return
	# 放入背包
	if not _add_equipment_to_backpack(data):
		return
	# 清除槽位
	if kind == "armor":
		if equip.has_method("configure_armor_slot"):
			equip.configure_armor_slot(slot_key, null)
	else:
		var idx: int = int(slot_def.get("index", -1))
		if idx >= 0 and equip.has_method("configure_weapon_slot"):
			equip.configure_weapon_slot(idx, null, false)
	# 持久化
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs != null and gs.has_method("save_equipment_from_player"):
		gs.save_equipment_from_player(current_player)


## 添加装备到背包（GameState carried equipment — 唯一数据源）
func _add_equipment_to_backpack(data: WeaponData) -> bool:
	if data == null:
		return false
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return false
	if gs.has_method("add_carried_equipment_instance"):
		return gs.add_carried_equipment_instance(data)
	return gs.add_carried_equipment(data.id, 1)


# ============================================================================
# 辅助函数
# ============================================================================

## 获取指定槽位的装备数据
func _get_slot_data(slot_key: String) -> WeaponData:
	if current_player == null or not is_instance_valid(current_player):
		return null
	var eq = current_player.equipment
	if eq == null:
		return null
	for slot_def in SLOT_DEFS:
		if String(slot_def["key"]) == slot_key:
			var kind: String = slot_def["kind"]
			if kind == "armor":
				if eq.has_method("get_armor_slot_data"):
					return eq.get_armor_slot_data(slot_key)
			else:
				var idx: int = int(slot_def.get("index", 0))
				if eq.has_method("get_weapon_slot_data"):
					return eq.get_weapon_slot_data(idx)
			break
	return null


## 查找 SLOT_DEFS 中 key 匹配的定义
func _find_slot_def(slot_key: String) -> Dictionary:
	for def in SLOT_DEFS:
		if String(def.get("key", "")) == slot_key:
			return def
	return {}


## 装备变更后刷新面板显示
func _refresh_after_change() -> void:
	_setup_slots_text()
	_load_gear_list()
	_load_attributes()
