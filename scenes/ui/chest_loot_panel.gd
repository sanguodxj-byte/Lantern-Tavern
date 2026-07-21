# DEBUG LINE 1
# DEBUG LINE 2
# DEBUG LINE 3
# DEBUG LINE 4
# DEBUG LINE 5
class_name ChestLootPanel
extends CanvasLayer

var WeaponRegistry: Node:
	get:
		return get_tree().root.get_node_or_null("WeaponRegistry") if get_tree() != null else null

## 宝箱战利品面板
## 交互开启宝箱后弹出，左侧显示宝箱内容与玩家背包，支持双击取物与一键收获。

const BD := preload("res://globals/tavern/brewing_data.gd")
const RD := preload("res://globals/combat/rune_data.gd")
const DETAIL_POPUP_SCRIPT := preload("res://scenes/ui/equipment_detail_popup.gd")
const GRID_ICON_SIZE := 64

@onready var chest_list: ItemList = %ChestList
@onready var backpack_list: ItemList = %BackpackList
@onready var harvest_all_btn: Button = %HarvestAllBtn
@onready var close_btn: Button = %CloseBtn
@onready var title_label: Label = %TitleLabel
@onready var chest_label: Label = %ChestLabel
@onready var backpack_label: Label = %BackpackLabel

## 当前关联的宝箱
var _chest: Node = null
## 当前关联的玩家
var _player: Node = null
## 宝箱战利品数据（从 chest.loot_data 读取的副本）
var _loot_weapon: WeaponData = null
var _loot_weapons: Array = []     # 包含 WeaponData 对象的数组，供武器架等容器使用
var _loot_materials: Array = []  # Array of {material_id, name}
var _loot_runes: Array = []      # Array of RuneData dictionaries

## 背包材料缓存（material_id → 数量）
var _backpack_materials: Dictionary = {}
var _backpack_runes: Dictionary = {}
var _backpack_equipment: Dictionary = {} # 背包装备缓存（equipment_id → 数量）

func _ready() -> void:
	visible = false
	# 加入 character_panel 组，使 is_character_panel_visible() 返回 true，
	# 从而阻止玩家状态机在面板打开时响应战斗/移动输入
	add_to_group("character_panel")
	harvest_all_btn.pressed.connect(_on_harvest_all_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	chest_list.item_activated.connect(_on_chest_item_activated)
	backpack_list.item_activated.connect(_on_backpack_item_activated)
	# 配置双列表为网格图标模式（与其他物品面板统一）
	_configure_grid_list(chest_list)
	_configure_grid_list(backpack_list)
	# 鼠标进入时释放捕获
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## 将 ItemList 配置为网格图标模式
func _configure_grid_list(list: ItemList) -> void:
	list.icon_mode = ItemList.ICON_MODE_TOP
	list.fixed_icon_size = Vector2i(GRID_ICON_SIZE, GRID_ICON_SIZE)
	list.max_columns = 0  # 自动换行
	list.same_column_width = true
	list.fixed_column_width = 80

## 显示战利品面板
func show_for_chest(chest: Node, player: Node) -> void:
	_chest = chest
	_player = player
	_load_loot_data()
	_load_backpack()
	_refresh_display()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# 暂停玩家输入
	if _player != null and is_instance_valid(_player):
		_player.movement_input_enabled = false
		_player.interaction_input_enabled = false
		_player.combat_input_enabled = false

## 从宝箱读取战利品数据
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

## 加载玩家当前背包材料与装备
func _load_backpack() -> void:
	_backpack_materials.clear()
	_backpack_runes.clear()
	_backpack_equipment.clear()
	var gs: Node = get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
	if gs == null:
		return
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
			if count > 0:
				_backpack_equipment[eq_id] = count

## 刷新整个面板显示
func _refresh_display() -> void:
	_refresh_chest_list()
	_refresh_backpack_list()
	_update_buttons()

## 刷新宝箱物品列表
func _refresh_chest_list() -> void:
	chest_list.clear()
	# 装备列表
	for i in range(_loot_weapons.size()):
		var w: WeaponData = _loot_weapons[i]
		if w != null:
			var display_name: String = String(w.get_full_display_name())
			var icon: Texture2D = _icon_for_weapon_data(w)
			var idx: int = chest_list.add_item("", icon)
			chest_list.set_item_metadata(idx, {"type": "equipment", "data": w, "loot_index": i})
			chest_list.set_item_tooltip(idx, _build_equipment_tooltip(display_name, w))
	# 材料
	for i in range(_loot_materials.size()):
		var mat_entry: Dictionary = _loot_materials[i]
		var mat_id: String = mat_entry.get("material_id", "")
		var mat_name: String = mat_entry.get("name", mat_id)
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_material(mat_id)
		var idx: int = chest_list.add_item("×1", icon)
		chest_list.set_item_metadata(idx, {"type": "material", "id": mat_id, "name": mat_name, "loot_index": i})
		chest_list.set_item_tooltip(idx, "%s ×1" % mat_name)
	for i in range(_loot_runes.size()):
		var rune_entry: Dictionary = _loot_runes[i]
		var rune_id: String = rune_entry.get("id", "")
		if rune_id == "":
			continue
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_rune(rune_id)
		var idx: int = chest_list.add_item("×1", icon)
		chest_list.set_item_metadata(idx, {"type": "rune", "id": rune_id, "loot_index": i})
		chest_list.set_item_tooltip(idx, "%s ×1" % RD.get_rune_name(rune_id))
	if chest_list.item_count == 0:
		chest_list.add_item(tr("Chest is empty"))
		chest_list.set_item_disabled(0, true)

## 刷新背包列表
func _refresh_backpack_list() -> void:
	backpack_list.clear()
	if _backpack_materials.is_empty() and _backpack_runes.is_empty() and _backpack_equipment.is_empty():
		backpack_list.add_item(tr("Backpack is empty"))
		backpack_list.set_item_disabled(0, true)
		return
	for mat_id in _backpack_materials.keys():
		var count: int = int(_backpack_materials[mat_id])
		var mat_name: String = BD.get_material_name(mat_id)
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_material(String(mat_id))
		var idx: int = backpack_list.add_item("×%d" % count, icon)
		backpack_list.set_item_metadata(idx, {"type": "material", "id": mat_id})
		backpack_list.set_item_tooltip(idx, "%s ×%d" % [mat_name, count])
	for rune_id in _backpack_runes.keys():
		var count: int = int(_backpack_runes[rune_id])
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_rune(String(rune_id))
		var idx: int = backpack_list.add_item("×%d" % count, icon)
		backpack_list.set_item_metadata(idx, {"type": "rune", "id": String(rune_id)})
		backpack_list.set_item_tooltip(idx, "%s ×%d" % [RD.get_rune_name(String(rune_id)), count])
	for eq_id in _backpack_equipment.keys():
		var count: int = int(_backpack_equipment[eq_id])
		var equip_label: String = str(eq_id)
		var eq_data: WeaponData = null
		if WeaponRegistry != null:
			eq_data = WeaponRegistry.get_weapon_data(str(eq_id))
			if eq_data != null:
				equip_label = str(eq_data.get_full_display_name())
		var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_equipment_id(str(eq_id))
		var idx: int = backpack_list.add_item("×%d" % count, icon)
		backpack_list.set_item_metadata(idx, {"type": "equipment", "id": eq_id})
		backpack_list.set_item_tooltip(idx, _build_equipment_tooltip(equip_label, eq_data))

## 更新按钮可用状态
func _update_buttons() -> void:
	var has_loot: bool = _loot_weapon != null or not _loot_weapons.is_empty() or not _loot_materials.is_empty() or not _loot_runes.is_empty()
	harvest_all_btn.disabled = not has_loot

## 获取装备图标（通过 WeaponData 的 id 查找）
func _icon_for_weapon_data(data: WeaponData) -> Texture2D:
	if data == null or data.id.is_empty():
		return null
	return DETAIL_POPUP_SCRIPT.icon_for_equipment_id(data.id)

## 构建装备 Tooltip（含词缀名称、品质标签、效果详情）
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
	return "\n".join(parts)

## 获取装备类别显示标签
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

## 双击宝箱物品 → 取走该物品
func _on_chest_item_activated(index: int) -> void:
	_take_item(index)

## 点击"一键收获"按钮 → 取走所有物品
func _on_harvest_all_pressed() -> void:
	_take_all()

## 点击"关闭"按钮
func _on_close_pressed() -> void:
	_close()

## 取走指定索引的物品
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

## 取走装备：放入随身背包，装备动作统一在装备面板中完成。
func _take_equipment(index: int, meta: Dictionary) -> void:
	var data: WeaponData = meta.get("data", null)
	if data == null:
		return
	if not _add_equipment_to_backpack(data):
		return
	# 播放拾取音效
	var audio_mgr = get_tree().root.get_node_or_null("AudioManager") if get_tree() != null else null
	if audio_mgr:
		audio_mgr.play("sword-pickup", null)
	# 从宝箱多装备数据中移除
	var loot_index: int = meta.get("loot_index", -1)
	if loot_index >= 0 and loot_index < _loot_weapons.size():
		_loot_weapons.remove_at(loot_index)
	if _loot_weapon == data:
		_loot_weapon = null
		
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["weapons"] = _loot_weapons.duplicate()
		_chest.loot_data["weapon"] = _loot_weapon

## 取走材料：记录到 GameState 随身背包（不直接写入酒馆仓库）
func _take_material(index: int, meta: Dictionary) -> void:
	var mat_id: String = meta.get("id", "")
	if mat_id == "":
		return
	# 记录到 GameState 随身背包；仓库只允许在酒馆场景手动转入。
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs == null or not gs.add_carried_material(mat_id, 1):
		return
	# 添加到背包显示缓存
	_backpack_materials[mat_id] = int(_backpack_materials.get(mat_id, 0)) + 1
	# 播放拾取音效
	var audio_mgr = get_tree().root.get_node_or_null("AudioManager") if get_tree() != null else null
	if audio_mgr:
		audio_mgr.play("key-pickup", null)
	# 从宝箱战利品中移除
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

## 一键收获：取走所有物品
func _take_all() -> void:
	# 取走所有装备
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
	# 取走所有材料
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
	# Keep this rolled instance, rather than reducing it to an id and losing its
	# affixes, tier and durability before the inventory tooltip can inspect it.
	if gs.has_method("add_carried_equipment_instance"):
		return gs.add_carried_equipment_instance(data)
	return gs.add_carried_equipment(data.id, 1)

## 关闭面板
func _close() -> void:
	visible = false
	# 恢复玩家输入
	if _player != null and is_instance_valid(_player):
		_player.movement_input_enabled = true
		_player.interaction_input_enabled = true
		_player.combat_input_enabled = true
	# 恢复鼠标捕获
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# 通知宝箱关闭并销毁
	if _chest != null and is_instance_valid(_chest):
		_chest.close_loot_panel()
	_chest = null
	_player = null
	# 从场景树中移除自身
	queue_free()

## ESC 键关闭面板
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_TAB:
			get_viewport().set_input_as_handled()
			_close()

## 双击背包项存入宝箱
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
	
	if item_type == "equipment":
		if gs.has_method("remove_carried_equipment") and gs.remove_carried_equipment(item_id, 1):
			if WeaponRegistry != null:
				var wdata = WeaponRegistry.get_weapon_data(item_id)
				if wdata != null:
					_loot_weapons.append(wdata)
					if _chest != null and is_instance_valid(_chest):
						_chest.loot_data["weapons"] = _loot_weapons.duplicate()
			if audio_mgr:
				audio_mgr.play("sword-pickup", null)
	elif item_type == "material":
		if gs.has_method("remove_carried_material") and gs.remove_carried_material(item_id, 1):
			var mat_name: String = BD.get_material_name(item_id)
			_loot_materials.append({"material_id": item_id, "name": mat_name})
			if _chest != null and is_instance_valid(_chest):
				_chest.loot_data["materials"] = _loot_materials.duplicate()
			if audio_mgr:
				audio_mgr.play("key-pickup", null)
	elif item_type == "rune":
		if gs.has_method("remove_carried_rune") and gs.remove_carried_rune(item_id, 1):
			_loot_runes.append({"id": item_id})
			if _chest != null and is_instance_valid(_chest):
				_chest.loot_data["runes"] = _loot_runes.duplicate(true)
			if audio_mgr:
				audio_mgr.play("key-pickup", null)
				
	_load_backpack()
	_refresh_display()
