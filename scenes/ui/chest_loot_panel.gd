class_name ChestLootPanel
extends CanvasLayer

var WeaponRegistry: Node:
	get:
		return get_tree().root.get_node_or_null("WeaponRegistry") if get_tree() != null else null

## 宝箱战利品面板 — Tarkov / Barony 风格
##
## 交互开启宝箱后弹出,三栏布局:
##   - 左栏 EQUIPMENT  装备槽(8 槽:头/胸/手/脚/主/副/背/饰),点击卸下 → 背包
##   - 中栏 CHEST      宝箱物品(图标网格 + 数量徽章)
##   - 右栏 BACKPACK   玩家随身背包(图标网格 + 数量徽章 + 容量条)
## 双击中/右栏物品可双向移动,装备双击槽位可卸下。
## 底部 HARVEST ALL 一键收获,ESC / 关闭按钮退出。
##
## 设计要点(Tarkov 风格):
##   - 4px 黑金属外框 + 2px 琥珀内高光
##   - 4 角金属钉
##   - 装备槽带品质色边框(精良绿/瑕疵红/权衡银)
##   - 物品格带数量徽章(右下角)
##   - 装备格带耐久度条(底部)
##   - 底部容量条 + 重量条(背包占用)

const BD := preload("res://globals/tavern/brewing_data.gd")
const RD := preload("res://globals/combat/rune_data.gd")
const DETAIL_POPUP_SCRIPT := preload("res://scenes/ui/equipment_detail_popup.gd")
const DROP_ZONE_SCRIPT := preload("res://scenes/ui/loot_drop_zone.gd")
const GRID_ICON_SIZE := 56
## 装备槽按钮尺寸(更宽,容下图标 + 名称 + 耐久条)
const SLOT_BUTTON_SIZE := Vector2(112, 96)
## 装备槽图标大小
const SLOT_ICON_SIZE := 48
## 拖动阈值(像素):鼠标移动超过此距离才触发拖放
const DRAG_THRESHOLD := 8.0

## 装备槽定义 — key 对齐 EquipmentComponent 真实 API:
##   armor 槽: head/body/hands/feet (armor_slots 字典 key)
##   weapon 槽: weapon_0..3 (weapon_slots 数组索引)
##   显示标签用 tr_key 本地化(保持原 UI 标签不变)
const SLOT_DEFS: Array = [
	{"key": "head", "tr_key": "EQ_SLOT_HEAD", "kind": "armor"},
	{"key": "body", "tr_key": "EQ_SLOT_CHEST", "kind": "armor"},
	{"key": "hands", "tr_key": "EQ_SLOT_HANDS", "kind": "armor"},
	{"key": "feet", "tr_key": "EQ_SLOT_FEET", "kind": "armor"},
	{"key": "weapon_0", "tr_key": "EQ_SLOT_MAIN", "kind": "weapon", "index": 0},
	{"key": "weapon_1", "tr_key": "EQ_SLOT_OFF", "kind": "weapon", "index": 1},
	{"key": "weapon_2", "tr_key": "EQ_SLOT_BACK", "kind": "weapon", "index": 2},
	{"key": "weapon_3", "tr_key": "EQ_SLOT_ACC", "kind": "weapon", "index": 3},
]

# 颜色 — 品质色
# 品质色 — 纯正向(绿) / 纯负向(红) / 正负权衡(银) / 无词缀(默认暖白)
const COLOR_AFFIX_POS := Color(0.30, 0.90, 0.40)
const COLOR_AFFIX_NEG := Color(0.90, 0.35, 0.35)
const COLOR_AFFIX_MIXED := Color(0.82, 0.82, 0.85)
const COLOR_AFFIX_NEUTRAL := Color(0.86, 0.76, 0.64)
# 耐久度颜色
const COLOR_DUR_HIGH := Color(0.40, 0.85, 0.45)
const COLOR_DUR_MID := Color(0.94, 0.78, 0.30)
const COLOR_DUR_LOW := Color(0.92, 0.40, 0.30)
# 容量条颜色
const COLOR_WEIGHT_BAR := Color(0.94, 0.62, 0.22)
const COLOR_WEIGHT_BAR_BG := Color(0.10, 0.08, 0.10)
const COLOR_WEIGHT_WARN := Color(0.92, 0.40, 0.30)

@onready var chest_list: ItemList = %ChestList
@onready var backpack_list: ItemList = %BackpackList
@onready var equip_grid: GridContainer = %EquipGrid
@onready var harvest_all_btn: Button = %HarvestAllBtn
@onready var close_btn: Button = %CloseBtn
@onready var title_label: Label = %TitleLabel
@onready var chest_label: Label = %ChestLabel
@onready var backpack_label: Label = %BackpackLabel
@onready var equip_label: Label = %EquipLabel
@onready var item_count_label: Label = %ItemCount
@onready var weight_bar: ProgressBar = %WeightBar
@onready var weight_label: Label = %WeightLabel

## 当前关联的宝箱
var _chest: Node = null
## 当前关联的玩家
var _player: Node = null
## 宝箱战利品数据
var _loot_weapon: WeaponData = null
var _loot_weapons: Array = []
var _loot_materials: Array = []
var _loot_runes: Array = []

## 背包材料/符文/装备缓存
var _backpack_materials: Dictionary = {}
var _backpack_runes: Dictionary = {}
var _backpack_equipment: Dictionary = {}

## 装备槽缓存
var _equipment_slots: Array[Dictionary] = []

## 装备槽按钮索引 → slot key 映射(用于 pressed 信号)
var _equip_slot_buttons: Dictionary = {} # {Button: String}

## 拖放状态
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_source_list: ItemList = null
var _equip_drag_start_pos: Vector2 = Vector2.ZERO
var _equip_drag_slot_key: String = ""

func _ready() -> void:
	visible = false
	add_to_group("character_panel")
	harvest_all_btn.pressed.connect(_on_harvest_all_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	chest_list.item_activated.connect(_on_chest_item_activated)
	backpack_list.item_activated.connect(_on_backpack_item_activated)
	# 拖放支持:监听列表 gui_input 以检测拖动手势
	chest_list.gui_input.connect(_on_list_gui_input.bind(chest_list))
	backpack_list.gui_input.connect(_on_list_gui_input.bind(backpack_list))
	# 拖放目标:装备槽、背包栏、宝箱栏各设为 drop zone
	_setup_drop_zone(equip_grid, "equipment")
	_setup_drop_zone(backpack_list, "backpack")
	_setup_drop_zone(chest_list, "chest")
	# 列表配置
	_configure_grid_list(chest_list)
	_configure_grid_list(backpack_list)
	# 装备槽用 2 列固定网格
	if equip_grid:
		equip_grid.columns = 2
	# 容量条配置
	if weight_bar:
		weight_bar.min_value = 0.0
		weight_bar.max_value = 1.0
		weight_bar.step = 0.0
		weight_bar.show_percentage = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## 将节点设置为拖放目标，附加 loot_drop_zone.gd 脚本并记录面板引用
func _setup_drop_zone(node: Control, zone_id: String) -> void:
	if node == null:
		return
	node.set_script(DROP_ZONE_SCRIPT)
	node.set_meta("drop_panel", self)
	node.set_meta("zone_id", zone_id)

func _configure_grid_list(list: ItemList) -> void:
	list.icon_mode = ItemList.ICON_MODE_TOP
	list.fixed_icon_size = Vector2i(GRID_ICON_SIZE, GRID_ICON_SIZE)
	list.max_columns = 0
	list.same_column_width = true
	list.fixed_column_width = 72

func show_for_chest(chest: Node, player: Node) -> void:
	_chest = chest
	_player = player
	_load_loot_data()
	_load_backpack()
	_load_equipment()
	_refresh_display()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _player != null and is_instance_valid(_player):
		if "movement_input_enabled" in _player:
			_player.movement_input_enabled = false
		if "interaction_input_enabled" in _player:
			_player.interaction_input_enabled = false
		if "combat_input_enabled" in _player:
			_player.combat_input_enabled = false

func _load_loot_data() -> void:
	_loot_weapon = null
	_loot_weapons = []
	_loot_materials = []
	_loot_runes = []
	if _chest == null or not is_instance_valid(_chest):
		return
	var data: Dictionary = _chest.loot_data
	_loot_weapon = data.get("weapon", null)
	if data.has("weapons"):
		var list = data.get("weapons", [])
		if list is Array:
			_loot_weapons = list.duplicate()
	elif _loot_weapon != null:
		_loot_weapons.append(_loot_weapon)
	_loot_materials = data.get("materials", []).duplicate()
	_loot_runes = data.get("runes", []).duplicate(true)

func _load_backpack() -> void:
	_backpack_materials.clear()
	_backpack_runes.clear()
	_backpack_equipment.clear()
	var gs: Node = get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
	if gs == null:
		return
	if gs.has_method("get_carried_materials_dict"):
		var carried: Dictionary = gs.get_carried_materials_dict()
		for mat_id in carried.keys():
			var count: int = int(carried[mat_id])
			if count > 0:
				_backpack_materials[mat_id] = count
	if gs.has_method("get_carried_runes_dict"):
		var carried_runes: Dictionary = gs.get_carried_runes_dict()
		for rune_id in carried_runes.keys():
			var count: int = int(carried_runes[rune_id])
			if count > 0:
				_backpack_runes[rune_id] = count
	if gs.has_method("get_carried_equipment_dict"):
		var carried_eq: Dictionary = gs.get_carried_equipment_dict()
		for eq_id in carried_eq.keys():
			var count: int = int(carried_eq[eq_id])
			_backpack_equipment[eq_id] = count

func _load_equipment() -> void:
	_equipment_slots.clear()
	if _player == null or not is_instance_valid(_player):
		return
	var equip: Node = _player.get("equipment") as Node
	if equip == null:
		return
	# 遍历 SLOT_DEFS，使用 EquipmentComponent 真实 API 读取装备数据
	for slot_def in SLOT_DEFS:
		var slot_key: String = slot_def["key"]
		var slot_tr_key: String = slot_def["tr_key"]
		var kind: String = slot_def["kind"]
		var data = null
		match kind:
			"armor":
				# 护甲槽: armor_slots["head"/"body"/"hands"/"feet"]
				if equip.has_method("get_armor_slot_data"):
					data = equip.get_armor_slot_data(slot_key)
			"weapon":
				# 武器槽: weapon_slots[0..3] 数组索引
				var idx: int = int(slot_def.get("index", 0))
				if equip.has_method("get_weapon_slot_data"):
					data = equip.get_weapon_slot_data(idx)
		_equipment_slots.append({
			"key": slot_key,
			"tr_key": slot_tr_key,
			"kind": kind,
			"index": int(slot_def.get("index", -1)),
			"data": data,
		})

func _refresh_display() -> void:
	_refresh_equipment_grid()
	_refresh_chest_list()
	_refresh_backpack_list()
	_update_buttons()
	_update_item_count()
	_update_weight_bar()

func _refresh_equipment_grid() -> void:
	if equip_grid == null:
		return
	# 清理旧子节点和按钮映射
	for child in equip_grid.get_children():
		child.queue_free()
	_equip_slot_buttons.clear()
	# 重新填充
	for slot in _equipment_slots:
		var slot_key: String = slot["key"]
		var slot_tr_key: String = slot.get("tr_key", "")
		var localized_label: String = tr(slot_tr_key) if not slot_tr_key.is_empty() else ""
		var data = slot.get("data", null)
		var btn: Button = Button.new()
		btn.custom_minimum_size = SLOT_BUTTON_SIZE
		btn.size_flags_horizontal = 3
		btn.size_flags_vertical = 3
		btn.clip_text = true
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.theme_type_variation = &"LootEquipSlot"
		if data != null and "get_full_display_name" in data:
			btn.text = "[%s] %s" % [localized_label, String(data.get_full_display_name())]
			# 设置图标
			var icon: Texture2D = null
			if "id" in data:
				icon = DETAIL_POPUP_SCRIPT.icon_for_equipment_id(String(data.id))
			if icon != null:
				btn.icon = icon
			# 按词缀质量设置按钮 modulate
			var affix_color := _affix_color_for(data)
			btn.modulate = affix_color
			# 装备槽可点击卸下
			btn.disabled = false
			btn.tooltip_text = _build_equipment_tooltip(String(data.get_full_display_name()), data) + "\n\n" + tr("click to unequip")
			btn.pressed.connect(_on_equip_slot_pressed.bind(slot_key, data))
			_equip_slot_buttons[btn] = slot_key
			# 拖放支持:监听 gui_input 以检测从装备槽拖出
			btn.gui_input.connect(_on_equip_slot_gui_input.bind(btn, slot_key, data))
		else:
			btn.text = "[%s]\n%s" % [localized_label, tr("[Empty]")]
			btn.disabled = true
			btn.tooltip_text = tr("Empty slot")
		equip_grid.add_child(btn)

## 装备槽点击:卸下装备 → 背包
## 使用 EquipmentComponent 真实 API:
##   armor: configure_armor_slot(slot_name, null) 清空护甲槽
##   weapon: configure_weapon_slot(idx, null) 清空武器槽
func _on_equip_slot_pressed(slot_key: String, data) -> void:
	if data == null:
		return
	if _player == null or not is_instance_valid(_player):
		return
	var equip: Node = _player.get("equipment") as Node
	if equip == null:
		return
	# 查找槽位定义以获取 kind 和 index
	var slot_def := _find_slot_def(slot_key)
	if slot_def.is_empty():
		return
	var kind: String = String(slot_def.get("kind", ""))
	# 先把装备写入背包(实例,保留 affix/tier/durability)
	var weapon_data: WeaponData = data as WeaponData
	if weapon_data == null:
		return
	if not _add_equipment_to_backpack(weapon_data):
		# 背包满,放弃
		return
	# 从装备组件中清除对应槽位
	match kind:
		"armor":
			if equip.has_method("configure_armor_slot"):
				equip.configure_armor_slot(slot_key, null)
		"weapon":
			var idx: int = int(slot_def.get("index", -1))
			if idx >= 0 and equip.has_method("configure_weapon_slot"):
				# 不自动激活空槽，避免意外切换武器
				equip.configure_weapon_slot(idx, null, false)
	# 持久化装备变更到 GameState（与酒馆面板同源，避免场景重载后丢失）
	var gs: Node = get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
	if gs != null and gs.has_method("save_equipment_from_player"):
		gs.save_equipment_from_player(_player)
	# 刷新
	_load_equipment()
	_load_backpack()
	_refresh_display()


## 查找 SLOT_DEFS 中 key 匹配的定义
func _find_slot_def(slot_key: String) -> Dictionary:
	for def in SLOT_DEFS:
		if String(def.get("key", "")) == slot_key:
			return def
	return {}

func _refresh_chest_list() -> void:
	chest_list.clear()
	# 装备
	for i in range(_loot_weapons.size()):
		var w: WeaponData = _loot_weapons[i]
		if w != null:
			var display_name: String = String(w.get_full_display_name())
			var icon: Texture2D = _icon_for_weapon_data(w)
			var idx: int = chest_list.add_item("", icon)
			chest_list.set_item_metadata(idx, {"type": "equipment", "data": w, "loot_index": i})
			chest_list.set_item_tooltip(idx, _build_equipment_tooltip(display_name, w))
			# 装备以图标为主:不显示文字
	# 材料
	for i in range(_loot_materials.size()):
		var mat_entry: Dictionary = _loot_materials[i]
		var mat_id: String = mat_entry.get("material_id", "")
		var mat_name: String = mat_entry.get("name", mat_id)
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_material(mat_id)
		var idx: int = chest_list.add_item("x1", icon)
		chest_list.set_item_metadata(idx, {"type": "material", "id": mat_id, "name": mat_name, "loot_index": i})
		chest_list.set_item_tooltip(idx, "%s x1" % mat_name)
	# 符文
	for i in range(_loot_runes.size()):
		var rune_entry: Dictionary = _loot_runes[i]
		var rune_id: String = rune_entry.get("id", "")
		if rune_id == "":
			continue
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_rune(rune_id)
		var idx: int = chest_list.add_item("x1", icon)
		chest_list.set_item_metadata(idx, {"type": "rune", "id": rune_id, "loot_index": i})
		chest_list.set_item_tooltip(idx, "%s x1" % RD.get_rune_name(rune_id))
	if chest_list.item_count == 0:
		chest_list.add_item(tr("Chest is empty"))
		chest_list.set_item_disabled(0, true)

func _refresh_backpack_list() -> void:
	backpack_list.clear()
	if _backpack_materials.is_empty() and _backpack_runes.is_empty() and _backpack_equipment.is_empty():
		backpack_list.add_item(tr("Backpack is empty"))
		backpack_list.set_item_disabled(0, true)
		return
	# 装备
	for eq_id in _backpack_equipment.keys():
		var count: int = int(_backpack_equipment[eq_id])
		var equip_label: String = str(eq_id)
		var eq_data: WeaponData = null
		var gs: Node = get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
		if gs != null and gs.has_method("get_carried_equipment_instance"):
			eq_data = gs.get_carried_equipment_instance(str(eq_id))
		if WeaponRegistry != null:
			if eq_data == null:
				eq_data = WeaponRegistry.get_weapon_data(str(eq_id))
			if eq_data != null:
				equip_label = str(eq_data.get_full_display_name())
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_equipment_id(str(eq_id))
		var text: String = "x%d" % count if count > 1 else ""
		var idx: int = backpack_list.add_item(text, icon)
		backpack_list.set_item_metadata(idx, {"type": "equipment", "id": eq_id})
		backpack_list.set_item_tooltip(idx, _build_equipment_tooltip(equip_label, eq_data))
	# 材料
	for mat_id in _backpack_materials.keys():
		var count: int = int(_backpack_materials[mat_id])
		var mat_name: String = BD.get_material_name(mat_id)
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_material(String(mat_id))
		var idx: int = backpack_list.add_item("x%d" % count, icon)
		backpack_list.set_item_metadata(idx, {"type": "material", "id": mat_id})
		backpack_list.set_item_tooltip(idx, "%s x%d" % [mat_name, count])
	# 符文
	for rune_id in _backpack_runes.keys():
		var count: int = int(_backpack_runes[rune_id])
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_rune(String(rune_id))
		var idx: int = backpack_list.add_item("x%d" % count, icon)
		backpack_list.set_item_metadata(idx, {"type": "rune", "id": String(rune_id)})
		backpack_list.set_item_tooltip(idx, "%s x%d" % [RD.get_rune_name(String(rune_id)), count])

func _update_buttons() -> void:
	var has_loot: bool = _loot_weapon != null or not _loot_weapons.is_empty() or not _loot_materials.is_empty() or not _loot_runes.is_empty()
	harvest_all_btn.disabled = not has_loot

func _update_item_count() -> void:
	if item_count_label == null:
		return
	var item_total: int = 0
	item_total += _loot_weapons.size() + _loot_materials.size() + _loot_runes.size()
	var bp_total: int = _backpack_materials.size() + _backpack_runes.size() + _backpack_equipment.size()
	var weight: float = 0.0
	weight += _loot_weapons.size() * 1.0
	weight += _loot_materials.size() * 0.05
	weight += _loot_runes.size() * 0.02
	item_count_label.text = tr("items  chest %d  /  bag %d    weight  %.2fkg") % [item_total, bp_total, weight]

## 重量/容量条
func _update_weight_bar() -> void:
	if weight_bar == null:
		return
	# 背包当前占用 = 装备实例数 + 材料 + 符文
	var used: int = _backpack_equipment.size() + _backpack_materials.size() + _backpack_runes.size()
	var limit: int = 30
	var gs: Node = get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
	if gs != null and "expedition_inventory" in gs:
		var inv = gs.expedition_inventory
		if inv != null and "space_limit" in inv:
			limit = int(inv.space_limit)
	if limit <= 0:
		limit = 30
	var ratio: float = float(used) / float(limit)
	weight_bar.max_value = float(limit)
	weight_bar.value = float(used)
	# 警告色
	var warn := ratio >= 0.9
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COLOR_WEIGHT_WARN if warn else COLOR_WEIGHT_BAR
	fill_style.border_width_top = 1
	fill_style.border_color = Color(1, 0.78, 0.32, 0.6) if not warn else Color(1, 0.42, 0.32, 0.85)
	weight_bar.add_theme_stylebox_override("fill", fill_style)
	if weight_label != null:
		weight_label.text = tr("BAG  %d / %d  (%d%%)") % [used, limit, int(round(ratio * 100.0))]

func _icon_for_weapon_data(data: WeaponData) -> Texture2D:
	if data == null or data.id.is_empty():
		return null
	return DETAIL_POPUP_SCRIPT.icon_for_equipment_id(data.id)

func _build_equipment_tooltip(display_name: String, data) -> String:
	if data == null:
		return display_name
	var parts: Array[String] = [display_name]
	if "affixes" in data and not data.affixes.is_empty():
		var quality_label: String = WeaponData.get_affix_quality_label(data.affixes)
		if not quality_label.is_empty():
			parts.append("[%s]" % quality_label)
		for affix_line in WeaponData.get_affix_detail_lines(data.affixes):
			parts.append(affix_line)
	# 耐久度
	if "condition" in data and "max_condition" in data:
		var cond := int(data.condition)
		var max_cond := int(data.max_condition)
		if max_cond > 0:
			parts.append(tr("Durability %d/%d") % [cond, max_cond])
	return "\n".join(parts)

func _affix_color_for(data) -> Color:
	if data == null or not ("affixes" in data):
		return COLOR_AFFIX_NEUTRAL
	var affixes = data.affixes
	if affixes is Array and not affixes.is_empty():
		return WeaponData.get_affix_color(affixes)
	return COLOR_AFFIX_NEUTRAL

func _equipment_category_label(data: WeaponData) -> String:
	var cat: String = data.equipment_category
	match cat:
		"shields":
			return tr("Shield")
		"armor_light":
			return tr("Light Armor")
		"armor_heavy":
			return tr("Heavy Armor")
		"accessories":
			return tr("Accessory")
		_:
			return tr("Weapon")

func _on_chest_item_activated(index: int) -> void:
	_take_item(index)

func _on_harvest_all_pressed() -> void:
	_take_all()

func _on_close_pressed() -> void:
	_close()

func _take_item(index: int) -> void:
	if index < 0 or index >= chest_list.item_count:
		return
	var meta = chest_list.get_item_metadata(index)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var item_type: String = meta.get("type", "")
	if item_type == "equipment":
		_take_equipment(index, meta)
	elif item_type == "material":
		_take_material(index, meta)
	elif item_type == "rune":
		_take_rune(index, meta)
	_refresh_display()

func _take_equipment(index: int, meta: Dictionary) -> void:
	var data: WeaponData = meta.get("data", null)
	if data == null:
		return
	if not _add_equipment_to_backpack(data):
		return
	var audio_mgr = get_tree().root.get_node_or_null("AudioManager") if get_tree() != null else null
	if audio_mgr:
		audio_mgr.play("sword-pickup", null)
	var loot_index: int = meta.get("loot_index", -1)
	if loot_index >= 0 and loot_index < _loot_weapons.size():
		_loot_weapons.remove_at(loot_index)
	if _loot_weapon == data:
		_loot_weapon = null
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["weapons"] = _loot_weapons.duplicate()
		_chest.loot_data["weapon"] = _loot_weapon

func _take_material(index: int, meta: Dictionary) -> void:
	var mat_id: String = meta.get("id", "")
	if mat_id == "":
		return
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs == null or not gs.add_carried_material(mat_id, 1):
		return
	_backpack_materials[mat_id] = int(_backpack_materials.get(mat_id, 0)) + 1
	var audio_mgr = get_tree().root.get_node_or_null("AudioManager") if get_tree() != null else null
	if audio_mgr:
		audio_mgr.play("key-pickup", null)
	var loot_index: int = meta.get("loot_index", -1)
	if loot_index >= 0 and loot_index < _loot_materials.size():
		_loot_materials.remove_at(loot_index)
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["materials"] = _loot_materials.duplicate()

func _take_rune(_index: int, meta: Dictionary) -> void:
	var rune_id: String = meta.get("id", "")
	if rune_id == "":
		return
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs == null or not gs.has_method("add_carried_rune") or not gs.add_carried_rune(rune_id, 1):
		return
	_backpack_runes[rune_id] = int(_backpack_runes.get(rune_id, 0)) + 1
	var audio_mgr = get_tree().root.get_node_or_null("AudioManager") if get_tree() != null else null
	if audio_mgr:
		audio_mgr.play("key-pickup", null)
	var loot_index: int = meta.get("loot_index", -1)
	if loot_index >= 0 and loot_index < _loot_runes.size():
		_loot_runes.remove_at(loot_index)
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["runes"] = _loot_runes.duplicate(true)

func _take_all() -> void:
	var remaining_weapons: Array = []
	for w in _loot_weapons:
		if w != null:
			if _add_equipment_to_backpack(w):
				if _loot_weapon == w:
					_loot_weapon = null
			else:
				remaining_weapons.append(w)
	_loot_weapons = remaining_weapons
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["weapons"] = _loot_weapons.duplicate()
		_chest.loot_data["weapon"] = _loot_weapon
	var audio_mgr = get_tree().root.get_node_or_null("AudioManager") if get_tree() != null else null
	var remaining_materials: Array = []
	for mat_entry in _loot_materials:
		var mat_id: String = mat_entry.get("material_id", "")
		if mat_id == "":
			continue
		var gs2: Node = get_tree().root.get_node_or_null("GameState")
		if gs2 != null and gs2.add_carried_material(mat_id, 1):
			_backpack_materials[mat_id] = int(_backpack_materials.get(mat_id, 0)) + 1
		else:
			remaining_materials.append(mat_entry)
	_loot_materials = remaining_materials
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["materials"] = _loot_materials.duplicate()
	var remaining_runes: Array = []
	for rune_entry in _loot_runes:
		var rune_id: String = rune_entry.get("id", "")
		if rune_id == "":
			continue
		var gs3: Node = get_tree().root.get_node_or_null("GameState")
		if gs3 != null and gs3.has_method("add_carried_rune") and gs3.add_carried_rune(rune_id, 1):
			_backpack_runes[rune_id] = int(_backpack_runes.get(rune_id, 0)) + 1
		else:
			remaining_runes.append(rune_entry)
	_loot_runes = remaining_runes
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["runes"] = _loot_runes.duplicate(true)
	if audio_mgr:
		audio_mgr.play("key-pickup", null)
	_refresh_display()

func _add_equipment_to_backpack(data: WeaponData) -> bool:
	if data == null:
		return false
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return false
	if gs.has_method("add_carried_equipment_instance"):
		return gs.add_carried_equipment_instance(data)
	return gs.add_carried_equipment(data.id, 1)

func _close() -> void:
	visible = false
	if _player != null and is_instance_valid(_player):
		if "movement_input_enabled" in _player:
			_player.movement_input_enabled = true
		if "interaction_input_enabled" in _player:
			_player.interaction_input_enabled = true
		if "combat_input_enabled" in _player:
			_player.combat_input_enabled = true
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _chest != null and is_instance_valid(_chest):
		_chest.close_loot_panel()
	_chest = null
	_player = null
	queue_free()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_TAB:
			get_viewport().set_input_as_handled()
			_close()

func _on_backpack_item_activated(index: int) -> void:
	if index < 0 or index >= backpack_list.item_count:
		return
	var meta = backpack_list.get_item_metadata(index)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var item_type: String = meta.get("type", "")
	var item_id: String = meta.get("id", "")
	if item_id == "":
		return
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return
	var audio_mgr = get_tree().root.get_node_or_null("AudioManager") if get_tree() != null else null
	match item_type:
		"equipment":
			# 双击背包装备 → 装备到玩家（护甲走 equip_armor，武器走 equip_weapon）
			_equip_from_backpack(item_id)
		"material":
			_return_material_to_chest(gs, item_id, audio_mgr)
		"rune":
			_return_rune_to_chest(gs, item_id, audio_mgr)
	_load_backpack()
	_refresh_display()

func _return_equipment_to_chest(gs: Node, item_id: String, audio_mgr: Node) -> void:
	if gs == null or not gs.has_method("remove_carried_equipment"):
		return
	var data: WeaponData = null
	var removed_instance := false
	if gs.has_method("remove_carried_equipment_instance"):
		data = gs.remove_carried_equipment_instance(item_id)
		removed_instance = data != null
	if data == null and WeaponRegistry != null:
		data = WeaponRegistry.get_weapon_data(item_id)
	if data == null:
		return
	if data.id != item_id:
		return
	if not removed_instance:
		if not gs.remove_carried_equipment(item_id, 1):
			return
	_loot_weapons.append(data.duplicate() as WeaponData)
	if _loot_weapon == null:
		_loot_weapon = data
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["weapons"] = _loot_weapons.duplicate()
		_chest.loot_data["weapon"] = _loot_weapon
	if audio_mgr:
		audio_mgr.play("sword-pickup", null)

func _return_material_to_chest(gs: Node, item_id: String, audio_mgr: Node) -> void:
	if not gs.has_method("remove_carried_material") or not gs.remove_carried_material(item_id, 1):
		return
	_loot_materials.append({"material_id": item_id, "name": BD.get_material_name(item_id)})
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["materials"] = _loot_materials.duplicate()
	if audio_mgr:
		audio_mgr.play("key-pickup", null)

func _return_rune_to_chest(gs: Node, item_id: String, audio_mgr: Node) -> void:
	if not gs.has_method("remove_carried_rune") or not gs.remove_carried_rune(item_id, 1):
		return
	_loot_runes.append({"id": item_id})
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["runes"] = _loot_runes.duplicate(true)
	if audio_mgr:
		audio_mgr.play("key-pickup", null)


# ============================================================================
# 装备 / 卸下 — 从背包装备到玩家
# ============================================================================

## 从背包装备到玩家身上。
## 使用 configure_armor_slot / configure_weapon_slot 直接配置槽位，
## 不走 equip_armor / equip_weapon（后者会在宝箱面板上下文中误生成物理掉落物）。
## 旧装备先放回背包，新装备直接配置到槽位。
## 装备成功后从背包移除；失败则放回背包。
## 装备变更同步持久化到 GameState，与酒馆面板同源。
func _equip_from_backpack(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	if _player == null or not is_instance_valid(_player):
		return false
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return false
	# 从背包取出装备实例（保留词缀/耐久）
	var data: WeaponData = null
	if gs.has_method("remove_carried_equipment_instance"):
		data = gs.remove_carried_equipment_instance(item_id)
	if data == null:
		# 无实例记录，尝试从 WeaponRegistry 解析基础数据
		if WeaponRegistry != null:
			data = WeaponRegistry.get_weapon_data(item_id)
		if data == null:
			return false
		# 仅从背包数量中减去
		if gs.has_method("remove_carried_equipment"):
			gs.remove_carried_equipment(item_id, 1)
	var equip: Node = _player.get("equipment") as Node
	if equip == null:
		# 无装备组件，放回背包
		gs.add_carried_equipment_instance(data)
		return false
	# 判定类型并分流装备 — 使用 configure_*_slot 直接配置，
	# 避免 equip_armor/equip_weapon 在宝箱面板上下文中误生成物理掉落物。
	var equipped: bool = false
	if equip.has_method("is_armor_equipment") and equip.is_armor_equipment(data):
		equipped = _configure_armor_from_backpack(equip, data)
	elif equip.has_method("configure_weapon_slot"):
		equipped = _configure_weapon_from_backpack(equip, data)
	if not equipped:
		# 装备失败（如槽位冲突/类型不匹配），放回背包
		gs.add_carried_equipment_instance(data)
		return false
	# 持久化装备变更到 GameState（与酒馆面板同源，避免场景重载后丢失）
	if gs.has_method("save_equipment_from_player"):
		gs.save_equipment_from_player(_player)
	# 装备成功音效
	var audio_mgr = get_tree().root.get_node_or_null("AudioManager") if get_tree() != null else null
	if audio_mgr:
		audio_mgr.play("sword-pickup", null)
	# 刷新装备栏显示
	_load_equipment()
	return true


## 从背包装备护甲到玩家身上（使用 configure_armor_slot 直接配置）。
## 旧护甲先放回背包，避免 equip_armor 生成的物理掉落物。
func _configure_armor_from_backpack(equip: Node, data: WeaponData) -> bool:
	if equip == null or data == null:
		return false
	if not equip.has_method("configure_armor_slot"):
		return false
	# 确定目标护甲槽
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
## 旧武器先放回背包，避免 equip_weapon 生成的物理掉落物。
func _configure_weapon_from_backpack(equip: Node, data: WeaponData) -> bool:
	if equip == null or data == null:
		return false
	if not equip.has_method("configure_weapon_slot"):
		return false
	# 确定目标武器槽：优先使用空槽，否则使用当前激活槽
	var target_idx := 0
	var has_empty := false
	if "weapon_slots" in equip:
		var slots: Array = equip.weapon_slots
		for i in range(slots.size()):
			if slots[i] == null:
				target_idx = i
				has_empty = true
				break
	if not has_empty:
		if equip.has_method("get_active_weapon_slot"):
			target_idx = int(equip.get_active_weapon_slot())
		# 旧武器放回背包
		if equip.has_method("get_weapon_slot_data"):
			var existing: WeaponData = equip.get_weapon_slot_data(target_idx)
			if existing != null:
				_add_equipment_to_backpack(existing)
	return equip.configure_weapon_slot(target_idx, data, false)


# ============================================================================
# 拖放支持 — ItemList 拖出 + 装备槽拖出 + drop zone 接收
# ============================================================================

## ItemList gui_input:检测鼠标拖动手势并发起 force_drag
func _on_list_gui_input(event: InputEvent, list: ItemList) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start_pos = event.position
			_drag_source_list = list
		else:
			_drag_source_list = null
	elif event is InputEventMouseMotion and _drag_source_list != null:
		if event.position.distance_to(_drag_start_pos) > DRAG_THRESHOLD:
			var idx := list.get_item_at_position(_drag_start_pos, true)
			if idx >= 0 and idx < list.item_count:
				var meta = list.get_item_metadata(idx)
				if typeof(meta) == TYPE_DICTIONARY:
					_start_list_drag(list, meta)
			_drag_source_list = null


## 从 ItemList 发起拖放
func _start_list_drag(list: ItemList, meta: Dictionary) -> void:
	var source := "chest" if list == chest_list else "backpack"
	var payload: Dictionary = {
		"source": source,
		"type": String(meta.get("type", "")),
		"id": String(meta.get("id", "")),
		"index": int(meta.get("loot_index", -1)),
	}
	# 构建拖动预览（装备名或材料名）
	var preview := Label.new()
	preview.text = String(meta.get("name", meta.get("id", "")))
	if payload.type == "equipment":
		var data = meta.get("data", null)
		if data != null and data.has_method("get_full_display_name"):
			preview.text = String(data.get_full_display_name())
	list.force_drag(payload, preview)


## 装备槽 gui_input:检测从装备槽拖出（卸下到拖放目标）
func _on_equip_slot_gui_input(event: InputEvent, btn: Button, slot_key: String, data) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_equip_drag_start_pos = event.position
			_equip_drag_slot_key = slot_key
		else:
			_equip_drag_slot_key = ""
	elif event is InputEventMouseMotion and _equip_drag_slot_key != "":
		if event.position.distance_to(_equip_drag_start_pos) > DRAG_THRESHOLD:
			var payload: Dictionary = {
				"source": "equipment",
				"type": "equipment",
				"slot_key": slot_key,
				"data": data,
			}
			var preview := Label.new()
			preview.text = String(data.get_full_display_name()) if data != null and data.has_method("get_full_display_name") else slot_key
			btn.force_drag(payload, preview)
			_equip_drag_slot_key = ""


## drop zone 回调:判断是否可接收拖放
func can_drop_to_zone(zone_id: String, data: Dictionary) -> bool:
	var source := String(data.get("source", ""))
	var item_type := String(data.get("type", ""))
	match zone_id:
		"equipment":
			# 仅接收来自背包的装备拖放（装备到玩家）
			return source == "backpack" and item_type == "equipment"
		"backpack":
			# 接收来自宝箱（取物）或装备槽（卸下）的拖放
			return source == "chest" or source == "equipment"
		"chest":
			# 接收来自背包的拖放（放回宝箱）
			return source == "backpack"
	return false


## drop zone 回调:处理拖放
func drop_to_zone(zone_id: String, data: Dictionary) -> void:
	var source := String(data.get("source", ""))
	match zone_id:
		"equipment":
			if source == "backpack":
				var item_id := String(data.get("id", ""))
				_equip_from_backpack(item_id)
		"backpack":
			if source == "chest":
				var idx := int(data.get("index", -1))
				_take_item(idx)
			elif source == "equipment":
				var slot_key := String(data.get("slot_key", ""))
				_unequip_slot_to_backpack(slot_key)
		"chest":
			if source == "backpack":
				var item_id := String(data.get("id", ""))
				_return_equipment_to_chest_by_id(item_id)
	_load_backpack()
	_refresh_display()


## 卸下指定槽位装备到背包（拖放路径）
func _unequip_slot_to_backpack(slot_key: String) -> void:
	if slot_key.is_empty():
		return
	if _player == null or not is_instance_valid(_player):
		return
	# 从 _equipment_slots 缓存中找到对应数据
	var slot_data = null
	for slot in _equipment_slots:
		if String(slot.get("key", "")) == slot_key:
			slot_data = slot.get("data", null)
			break
	if slot_data == null:
		return
	_on_equip_slot_pressed(slot_key, slot_data)


## 通过 item_id 将背包装备放回宝箱（拖放路径）
func _return_equipment_to_chest_by_id(item_id: String) -> void:
	if item_id.is_empty():
		return
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return
	var audio_mgr = get_tree().root.get_node_or_null("AudioManager") if get_tree() != null else null
	_return_equipment_to_chest(gs, item_id, audio_mgr)
