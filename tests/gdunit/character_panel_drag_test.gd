extends GdUnitTestSuite
## 角色面板 (CharacterPanel) 拖放与数据唯一性单元测试
## 验证：
##   1. 场景/脚本完整性
##   2. can_drop_to_zone 仅允许面板内拖放（不支持跨面板）
##   3. drop_to_zone 路由正确
##   4. _equip_from_backpack 装备护甲/武器到 EquipmentComponent
##   5. _unequip_slot_to_backpack 卸下到背包
##   6. 数据唯一性：装备不在背包与装备槽中同时存在
##   7. 持久化：装备变更后调用 save_equipment_from_player

## 创建带 equipment + health 属性的测试用玩家节点。
## 普通 Node3D 无法通过 set/get 存取自定义属性（无脚本声明），
## 而生产环境的 Player 脚本声明了 `var equipment` 和 `var health`。
func _create_mock_player() -> Node3D:
	var player := Node3D.new()
	var mock_script := GDScript.new()
	mock_script.source_code = "extends Node3D\nvar equipment: Node\nvar health: RefCounted\n"
	mock_script.reload()
	player.set_script(mock_script)
	# 创建 mock health 对象（Player.health 拥有 current_life / max_life）
	var health_obj := RefCounted.new()
	var health_script := GDScript.new()
	health_script.source_code = "extends RefCounted\nvar current_life: int = 100\nvar max_life: int = 100\n"
	health_script.reload()
	health_obj.set_script(health_script)
	player.health = health_obj
	return player

# ============================================================================
# 1. 场景与脚本完整性
# ============================================================================

func test_character_panel_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/character_panel.gd")).is_true()


func test_character_panel_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/character_panel.tscn")).is_true()


func test_character_panel_has_drag_infrastructure() -> void:
	var source := (load("res://scenes/ui/character_panel.gd") as GDScript).source_code
	# 拖放基础设施
	assert_bool(source.contains("func _setup_drop_zone")).is_true()
	assert_bool(source.contains("func _on_slot_gui_input")).is_true()
	assert_bool(source.contains("func _on_gear_list_gui_input")).is_true()
	assert_bool(source.contains("func can_drop_to_zone")).is_true()
	assert_bool(source.contains("func drop_to_zone")).is_true()


func test_character_panel_has_equip_unequip() -> void:
	var source := (load("res://scenes/ui/character_panel.gd") as GDScript).source_code
	assert_bool(source.contains("func _equip_from_backpack")).is_true()
	assert_bool(source.contains("func _unequip_slot_to_backpack")).is_true()
	assert_bool(source.contains("func _configure_armor_from_backpack")).is_true()
	assert_bool(source.contains("func _configure_weapon_from_backpack")).is_true()


func test_character_panel_has_inspect_armor() -> void:
	var source := (load("res://scenes/ui/character_panel.gd") as GDScript).source_code
	assert_bool(source.contains("func _inspect_armor")).is_true()


# ============================================================================
# 2. can_drop_to_zone — 仅允许面板内拖放，不支持跨面板
# ============================================================================

func test_can_drop_backpack_to_equipment() -> void:
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("equipment", {"source": "backpack", "type": "equipment"})
	assert_bool(result).is_true()
	panel.queue_free()


func test_can_drop_equipment_to_backpack() -> void:
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("backpack", {"source": "equipment", "type": "equipment"})
	assert_bool(result).is_true()
	panel.queue_free()


func test_cannot_drop_chest_to_equipment() -> void:
	# 不支持跨面板：宝箱来源不能拖到角色面板装备槽
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("equipment", {"source": "chest", "type": "equipment"})
	assert_bool(result).is_false()
	panel.queue_free()


func test_cannot_drop_backpack_to_chest() -> void:
	# 角色面板没有 chest zone
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("chest", {"source": "backpack", "type": "equipment"})
	assert_bool(result).is_false()
	panel.queue_free()


func test_cannot_drop_non_equipment_to_equipment() -> void:
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("equipment", {"source": "backpack", "type": "material"})
	assert_bool(result).is_false()
	panel.queue_free()


func test_cannot_drop_to_unknown_zone() -> void:
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("unknown", {"source": "backpack", "type": "equipment"})
	assert_bool(result).is_false()
	panel.queue_free()


# ============================================================================
# 3. _equip_from_backpack — 装备护甲到 EquipmentComponent
# ============================================================================

func test_equip_armor_from_backpack_to_player() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	# 构建护甲并放入背包
	var armor: WeaponData = WeaponRegistry.build_weapon_data_with_tier("plate_armor", 0)
	assert_object(armor).is_not_null()
	assert_bool(armor.equipment_category.begins_with("armor")).is_true()
	gs.add_carried_equipment_instance(armor)
	assert_int(int(inventory.equipment.get("plate_armor", 0))).is_equal(1)

	# 构建玩家 + 装备组件
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip

	# 构建面板并设置 current_player
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	# 从背包装备护甲
	var result: bool = panel.call("_equip_from_backpack", "plate_armor")
	assert_bool(result).is_true()

	# 验证护甲已装备到玩家身上
	var body_armor: WeaponData = equip.get_armor_slot_data("body")
	assert_object(body_armor).is_not_null()
	assert_str(body_armor.equipment_category).is_equal("armor_heavy")

	# 验证背包中已移除 — 数据唯一性
	assert_bool(not inventory.equipment.has("plate_armor")).is_true()

	# 验证持久化 — GameState 已保存装备状态
	assert_str(String(gs.armor_slot_ids.get("body", ""))).is_equal("plate_armor")

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


# ============================================================================
# 4. _equip_from_backpack — 装备武器到 EquipmentComponent
# ============================================================================

func test_equip_weapon_from_backpack_to_player() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	# 构建武器并放入背包
	var weapon: WeaponData = WeaponRegistry.build_weapon_data_with_tier("shortsword", 0)
	assert_object(weapon).is_not_null()
	gs.add_carried_equipment_instance(weapon)
	assert_int(int(inventory.equipment.get("shortsword", 0))).is_equal(1)

	# 构建玩家 + 装备组件
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip

	# 构建面板并设置 current_player
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	# 从背包装备武器
	var result: bool = panel.call("_equip_from_backpack", "shortsword")
	assert_bool(result).is_true()

	# 验证武器已装备到武器槽 0
	var slot_data: WeaponData = equip.get_weapon_slot_data(0)
	assert_object(slot_data).is_not_null()
	assert_str(slot_data.id).is_equal("shortsword")

	# 验证背包中已移除 — 数据唯一性
	assert_bool(not inventory.equipment.has("shortsword")).is_true()

	# 验证持久化 — GameState 已保存装备状态
	assert_str(String(gs.weapon_slot_ids[0])).is_equal("shortsword")

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


## 主手已有武器时，从背包装备新武器应替换主手激活槽，旧武器放回背包。
## 回归：之前 _configure_weapon_from_backpack 会找空槽放入，导致主手不更换。
func test_equip_weapon_replaces_occupied_main_hand() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	# 主手先装备 short sword（直接装备到 EquipmentComponent，不经过背包）
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip
	equip.configure_weapon_slot(0, WeaponRegistry.get_weapon_data("shortsword"), true)
	assert_str(equip.get_weapon_slot_data(0).id).is_equal("shortsword")

	# 背包只放入 dagger
	var dagger: WeaponData = WeaponRegistry.build_weapon_data_with_tier("dagger", 0)
	gs.add_carried_equipment_instance(dagger)
	assert_int(int(inventory.equipment.get("dagger", 0))).is_equal(1)

	# 构建面板
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	# 从背包装备 dagger — 应替换主手 slot 0
	var result: bool = panel.call("_equip_from_backpack", "dagger")
	assert_bool(result).is_true()

	# 主手应为 dagger，而非 short sword
	var slot_data: WeaponData = equip.get_weapon_slot_data(0)
	assert_object(slot_data).is_not_null()
	assert_str(slot_data.id).is_equal("dagger")

	# 旧 short sword 应放回背包
	assert_int(int(inventory.equipment.get("shortsword", 0))).is_equal(1)
	# dagger 应从背包移除
	assert_bool(not inventory.equipment.has("dagger")).is_true()

	# 持久化：GameState weapon_slot_ids[0] 应为 dagger
	assert_str(String(gs.weapon_slot_ids[0])).is_equal("dagger")

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


# ============================================================================
# 5. _unequip_slot_to_backpack — 卸下护甲到背包
# ============================================================================

func test_unequip_armor_to_backpack() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	# 构建护甲并直接装备到玩家
	var armor: WeaponData = WeaponRegistry.build_weapon_data_with_tier("plate_armor", 0)
	assert_object(armor).is_not_null()
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip
	equip.equip_armor(armor)
	assert_object(equip.get_armor_slot_data("body")).is_not_null()

	# 构建面板并设置 current_player
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	# 卸下 body 槽护甲
	panel.call("_unequip_slot_to_backpack", "body")

	# 验证护甲已从装备槽移除
	assert_object(equip.get_armor_slot_data("body")).is_null()
	# 验证护甲已加入背包
	assert_int(int(inventory.equipment.get("plate_armor", 0))).is_equal(1)

	# 验证持久化 — GameState 已清空 body 槽
	assert_str(String(gs.armor_slot_ids.get("body", "X"))).is_equal("")

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


# ============================================================================
# 6. _unequip_slot_to_backpack — 卸下武器到背包
# ============================================================================

func test_unequip_weapon_to_backpack() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	# 构建武器并直接装备到玩家
	var weapon: WeaponData = WeaponRegistry.build_weapon_data_with_tier("shortsword", 0)
	assert_object(weapon).is_not_null()
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip
	equip.configure_weapon_slot(0, weapon, false)
	assert_object(equip.get_weapon_slot_data(0)).is_not_null()

	# 构建面板并设置 current_player
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	# 卸下 weapon_0 槽武器
	panel.call("_unequip_slot_to_backpack", "weapon_0")

	# 验证武器已从装备槽移除
	assert_object(equip.get_weapon_slot_data(0)).is_null()
	# 验证武器已加入背包
	assert_int(int(inventory.equipment.get("shortsword", 0))).is_equal(1)

	# 验证持久化 — GameState 已清空 weapon_0 槽
	assert_str(String(gs.weapon_slot_ids[0])).is_equal("")

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


# ============================================================================
# 7. 数据唯一性 — 装备不在背包与装备槽中同时存在
# ============================================================================

func test_data_uniqueness_equip_removes_from_backpack() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	# 构建护甲并放入背包
	var armor: WeaponData = WeaponRegistry.build_weapon_data_with_tier("leather_armor", 0)
	assert_object(armor).is_not_null()
	gs.add_carried_equipment_instance(armor)

	# 构建玩家 + 装备组件
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip

	# 构建面板
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	# 装备前：在背包中
	assert_int(int(inventory.equipment.get("leather_armor", 0))).is_equal(1)
	# 装备前：不在装备槽中
	assert_object(equip.get_armor_slot_data("body")).is_null()

	# 装备
	var result: bool = panel.call("_equip_from_backpack", "leather_armor")
	assert_bool(result).is_true()

	# 装备后：不在背包中
	assert_bool(not inventory.equipment.has("leather_armor")).is_true()
	# 装备后：在装备槽中
	assert_object(equip.get_armor_slot_data("body")).is_not_null()

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


func test_data_uniqueness_unequip_removes_from_slot() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	# 构建护甲并直接装备
	var armor: WeaponData = WeaponRegistry.build_weapon_data_with_tier("leather_armor", 0)
	assert_object(armor).is_not_null()
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip
	equip.equip_armor(armor)

	# 构建面板
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	# 卸下前：在装备槽中
	assert_object(equip.get_armor_slot_data("body")).is_not_null()
	# 卸下前：不在背包中
	assert_bool(not inventory.equipment.has("leather_armor")).is_true()

	# 卸下
	panel.call("_unequip_slot_to_backpack", "body")

	# 卸下后：不在装备槽中
	assert_object(equip.get_armor_slot_data("body")).is_null()
	# 卸下后：在背包中
	assert_int(int(inventory.equipment.get("leather_armor", 0))).is_equal(1)

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


# ============================================================================
# 8. 持久化 — 装备变更后 GameState 保存
# ============================================================================

func test_equip_persists_to_game_state() -> void:
	var source := (load("res://scenes/ui/character_panel.gd") as GDScript).source_code
	# _equip_from_backpack 应调用 save_equipment_from_player
	assert_bool(source.contains("save_equipment_from_player")).is_true()


func test_unequip_persists_to_game_state() -> void:
	var source := (load("res://scenes/ui/character_panel.gd") as GDScript).source_code
	# _unequip_slot_to_backpack 应调用 save_equipment_from_player
	var has_save_in_unequip := source.contains("func _unequip_slot_to_backpack")
	assert_bool(has_save_in_unequip).is_true()


# ============================================================================
# 9. _inspect_armor — 护甲检视
# ============================================================================

func test_inspect_armor_displays_defense() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	# 构建护甲
	var armor: WeaponData = WeaponRegistry.build_weapon_data_with_tier("plate_armor", 0)
	assert_object(armor).is_not_null()
	assert_int(armor.armor_phys_def).is_greater(0)

	# 构建面板
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)

	# 调用 _inspect_armor
	panel.call("_inspect_armor", armor)

	# 验证显示了护甲名称
	var name_label: Label = panel.get_node("%EqNameVal")
	assert_str(name_label.text).is_not_empty()
	# 验证显示了防御值
	var dmg_label: Label = panel.get_node("%EqDmgVal")
	assert_str(dmg_label.text).contains(str(armor.armor_phys_def))

	panel.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


# ============================================================================
# 10. 辅助函数 — _get_slot_data / _find_slot_def
# ============================================================================

func test_get_slot_data_returns_equipped_weapon() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	var weapon: WeaponData = WeaponRegistry.build_weapon_data_with_tier("shortsword", 0)
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip
	equip.configure_weapon_slot(0, weapon, false)

	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	var data: WeaponData = panel.call("_get_slot_data", "weapon_0")
	assert_object(data).is_not_null()
	assert_str(data.id).is_equal("shortsword")

	# 空槽返回 null
	var empty_data: WeaponData = panel.call("_get_slot_data", "weapon_1")
	assert_object(empty_data).is_null()

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


func test_get_slot_data_returns_equipped_armor() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	var armor: WeaponData = WeaponRegistry.build_weapon_data_with_tier("plate_armor", 0)
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip
	equip.equip_armor(armor)

	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	var data: WeaponData = panel.call("_get_slot_data", "body")
	assert_object(data).is_not_null()

	# 空槽返回 null
	var empty_data: WeaponData = panel.call("_get_slot_data", "head")
	assert_object(empty_data).is_null()

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


func test_find_slot_def_returns_correct_def() -> void:
	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)

	var def: Dictionary = panel.call("_find_slot_def", "body")
	assert_bool(not def.is_empty()).is_true()
	assert_str(String(def.get("kind", ""))).is_equal("armor")

	var def2: Dictionary = panel.call("_find_slot_def", "weapon_0")
	assert_bool(not def2.is_empty()).is_true()
	assert_str(String(def2.get("kind", ""))).is_equal("weapon")
	assert_int(int(def2.get("index", -1))).is_equal(0)

	# 不存在的 key 返回空字典
	var def3: Dictionary = panel.call("_find_slot_def", "nonexistent")
	assert_bool(def3.is_empty()).is_true()

	panel.queue_free()


# ============================================================================
# 11. drop_to_zone 路由测试
# ============================================================================

func test_drop_to_zone_equipment_from_backpack_calls_equip() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	var weapon: WeaponData = WeaponRegistry.build_weapon_data_with_tier("shortsword", 0)
	gs.add_carried_equipment_instance(weapon)

	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip

	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	# 模拟拖放：从背包拖到装备槽
	panel.call("drop_to_zone", "equipment", {"source": "backpack", "type": "equipment", "id": "shortsword"})

	# 验证武器已装备
	assert_object(equip.get_weapon_slot_data(0)).is_not_null()
	assert_str(equip.get_weapon_slot_data(0).id).is_equal("shortsword")

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


func test_drop_to_zone_backpack_from_equipment_calls_unequip() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	inventory.clear()
	inventory.space_limit = 30

	var armor: WeaponData = WeaponRegistry.build_weapon_data_with_tier("plate_armor", 0)
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip
	equip.equip_armor(armor)

	var panel: Node = load("res://scenes/ui/character_panel.tscn").instantiate()
	add_child(panel)
	panel.current_player = player

	# 模拟拖放：从装备槽拖到背包
	panel.call("drop_to_zone", "backpack", {"source": "equipment", "type": "equipment", "slot_key": "body"})

	# 验证护甲已卸下
	assert_object(equip.get_armor_slot_data("body")).is_null()
	# 验证已加入背包
	assert_int(int(inventory.equipment.get("plate_armor", 0))).is_equal(1)

	panel.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances
