class_name ChestLootPanel
extends CanvasLayer

## 宝箱战利品面板
## 交互开启宝箱后弹出，左侧显示宝箱内容与玩家背包，支持双击取物与一键收获。

const BD := preload("res://globals/tavern/brewing_data.gd")
const RD := preload("res://globals/combat/rune_data.gd")

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
var _loot_materials: Array = []  # Array of {material_id, name}
var _loot_runes: Array = []      # Array of RuneData dictionaries

## 背包材料缓存（material_id → 数量）
var _backpack_materials: Dictionary = {}
var _backpack_runes: Dictionary = {}

func _ready() -> void:
	visible = false
	# 加入 character_panel 组，使 is_character_panel_visible() 返回 true，
	# 从而阻止玩家状态机在面板打开时响应战斗/移动输入
	add_to_group("character_panel")
	harvest_all_btn.pressed.connect(_on_harvest_all_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	chest_list.item_activated.connect(_on_chest_item_activated)
	# 鼠标进入时释放捕获
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

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
	_loot_materials = []
	_loot_runes = []
	if _chest == null or not is_instance_valid(_chest):
		return
	var data: Dictionary = _chest.loot_data
	_loot_weapon = data.get("weapon", null)
	_loot_materials = data.get("materials", []).duplicate()
	_loot_runes = data.get("runes", []).duplicate(true)

## 加载玩家当前背包材料
func _load_backpack() -> void:
	_backpack_materials.clear()
	_backpack_runes.clear()
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

## 刷新整个面板显示
func _refresh_display() -> void:
	_refresh_chest_list()
	_refresh_backpack_list()
	_update_buttons()

## 刷新宝箱物品列表
func _refresh_chest_list() -> void:
	chest_list.clear()
	# 装备
	if _loot_weapon != null:
		var display_name: String = _loot_weapon.get_full_display_name()
		var category_label: String = _equipment_category_label(_loot_weapon)
		var idx: int = chest_list.add_item("%s\n[%s]" % [display_name, category_label])
		chest_list.set_item_metadata(idx, {"type": "equipment", "data": _loot_weapon})
	# 材料
	for i in range(_loot_materials.size()):
		var mat_entry: Dictionary = _loot_materials[i]
		var mat_id: String = mat_entry.get("material_id", "")
		var mat_name: String = mat_entry.get("name", mat_id)
		var idx: int = chest_list.add_item("%s ×1" % mat_name)
		chest_list.set_item_metadata(idx, {"type": "material", "id": mat_id, "name": mat_name, "loot_index": i})
	for i in range(_loot_runes.size()):
		var rune_entry: Dictionary = _loot_runes[i]
		var rune_id: String = rune_entry.get("id", "")
		if rune_id == "":
			continue
		var idx: int = chest_list.add_item("%s ×1" % RD.get_rune_name(rune_id))
		chest_list.set_item_metadata(idx, {"type": "rune", "id": rune_id, "loot_index": i})
	if chest_list.item_count == 0:
		chest_list.add_item("（宝箱已空）")
		chest_list.set_item_disabled(0, true)

## 刷新背包列表
func _refresh_backpack_list() -> void:
	backpack_list.clear()
	if _backpack_materials.is_empty() and _backpack_runes.is_empty():
		backpack_list.add_item("（背包为空）")
		backpack_list.set_item_disabled(0, true)
		return
	for mat_id in _backpack_materials.keys():
		var count: int = int(_backpack_materials[mat_id])
		var mat_name: String = BD.get_material_name(mat_id)
		var idx: int = backpack_list.add_item("%s ×%d" % [mat_name, count])
		backpack_list.set_item_metadata(idx, {"type": "material", "id": mat_id})
	for rune_id in _backpack_runes.keys():
		var count: int = int(_backpack_runes[rune_id])
		var idx: int = backpack_list.add_item("%s ×%d" % [RD.get_rune_name(String(rune_id)), count])
		backpack_list.set_item_metadata(idx, {"type": "rune", "id": String(rune_id)})

## 更新按钮可用状态
func _update_buttons() -> void:
	var has_loot: bool = _loot_weapon != null or not _loot_materials.is_empty() or not _loot_runes.is_empty()
	harvest_all_btn.disabled = not has_loot

## 获取装备类别显示标签
func _equipment_category_label(data: WeaponData) -> String:
	var cat: String = data.equipment_category
	match cat:
		"shields":
			return tr("盾牌")
		"armor_light":
			return tr("轻甲")
		"armor_heavy":
			return tr("重甲")
		"accessories":
			return tr("饰品")
		_:
			return tr("武器")

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
	# 从宝箱数据中移除
	_loot_weapon = null
	if _chest != null and is_instance_valid(_chest):
		_chest.loot_data["weapon"] = null

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
	# 取走装备
	if _loot_weapon != null:
		var data: WeaponData = _loot_weapon
		if _add_equipment_to_backpack(data):
			_loot_weapon = null
			if _chest != null and is_instance_valid(_chest):
				_chest.loot_data["weapon"] = null
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
	var cat: String = data.equipment_category
	if cat == "shields":
		return gs.add_carried_shield(data.id)
	if cat.begins_with("armor") or cat == "accessories":
		return gs.add_carried_equipment(data.id, 1)
	return gs.add_carried_weapon(data.id)

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
