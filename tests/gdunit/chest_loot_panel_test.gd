extends GdUnitTestSuite
## 宝箱战利品面板 (ChestLootPanel) 单元测试
## 验证：面板场景完整性、宝箱交互开启流程、战利品数据生成、一键收获逻辑

const BD := preload("res://globals/tavern/brewing_data.gd")

## 创建带 equipment 属性的测试用玩家节点。
## 普通 Node3D 无法通过 set/get 存取自定义属性（无脚本声明），
## 而生产环境的 Player 脚本声明了 `var equipment`。
## 测试中用运行时脚本为 Node3D 添加该属性，使 get("equipment") 正常返回。
func _create_mock_player() -> Node3D:
	var player := Node3D.new()
	var mock_script := GDScript.new()
	mock_script.source_code = "extends Node3D\nvar equipment: Node\nvar movement_input_enabled: bool = true\nvar interaction_input_enabled: bool = true\nvar combat_input_enabled: bool = true\n"
	mock_script.reload()
	player.set_script(mock_script)
	return player

# ============================================================================
# 1. 场景与脚本完整性
# ============================================================================

func test_chest_loot_panel_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/chest_loot_panel.gd")).is_true()


func test_chest_loot_panel_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/chest_loot_panel.tscn")).is_true()


func test_chest_loot_panel_scene_instantiates() -> void:
	var scene := load("res://scenes/ui/chest_loot_panel.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var panel: Node = scene.instantiate()
	assert_object(panel).is_not_null()
	panel.free()


func test_chest_loot_panel_has_required_nodes() -> void:
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	assert_object(panel.get_node("%ChestList")).is_not_null()
	assert_object(panel.get_node("%BackpackList")).is_not_null()
	assert_object(panel.get_node("%HarvestAllBtn")).is_not_null()
	assert_object(panel.get_node("%CloseBtn")).is_not_null()
	assert_object(panel.get_node("%TitleLabel")).is_not_null()
	# 新增节点(优化后必须有)
	assert_object(panel.get_node("%WeightBar")).is_not_null()
	assert_object(panel.get_node("%WeightLabel")).is_not_null()
	assert_object(panel.get_node("%EquipLabel")).is_not_null()
	panel.queue_free()


# ============================================================================
# 1b. 优化新增:无 emoji、品质颜色、装备槽可点击、容量条
# ============================================================================

func test_chest_loot_panel_source_has_no_emoji() -> void:
	# 严禁在 chest_loot_panel 中使用任何 emoji 字符
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# 检查常见 emoji 范围(也包括一些箭头/符号/中点字符用作 UI 装饰时也算)
	# 这里只检查真正意义上的 emoji 范围,箭头 → 属于 Unicode 而非 emoji。
	var emoji_pattern := RegEx.new()
	emoji_pattern.compile("[\\x{1F300}-\\x{1FAFF}\\x{2600}-\\x{27BF}\\x{1F000}-\\x{1F1FF}]")
	var result := emoji_pattern.search(source)
	assert_bool(result == null) \
		.override_failure_message("chest_loot_panel.gd 中不允许出现 emoji 字符").is_true()


func test_chest_loot_panel_scene_has_no_emoji() -> void:
	# 直接读 .tscn 文本检查 emoji
	var f := FileAccess.open("res://scenes/ui/chest_loot_panel.tscn", FileAccess.READ)
	assert_object(f).is_not_null()
	var text := f.get_as_text()
	f.close()
	var emoji_pattern := RegEx.new()
	emoji_pattern.compile("[\\x{1F300}-\\x{1FAFF}\\x{2600}-\\x{27BF}\\x{1F000}-\\x{1F1FF}]")
	var result := emoji_pattern.search(text)
	assert_bool(result == null) \
		.override_failure_message("chest_loot_panel.tscn 中不允许出现 emoji 字符").is_true()


func test_chest_loot_panel_uses_tarkov_lootframe_theme() -> void:
	# 验证 tscn 中 LootFrame PanelContainer 引用了 LootFrame 主题变体
	var f := FileAccess.open("res://scenes/ui/chest_loot_panel.tscn", FileAccess.READ)
	assert_object(f).is_not_null()
	var text := f.get_as_text()
	f.close()
	assert_bool(text.contains("theme_type_variation = &\"LootFrame\"")) \
		.override_failure_message("LootFrame 必须使用 LootFrame 主题变体(4px 黑金属外框)").is_true()
	# 拆开 or
	var has_section := text.contains("LootSection\"")
	var has_section_alt := text.contains("LootSectionAlt\"")
	assert_bool(has_section or has_section_alt) \
		.override_failure_message("子区段必须使用 LootSection/LootSectionAlt 主题变体").is_true()


func test_chest_loot_panel_equip_slot_supports_click_to_unequip() -> void:
	# 验证装备槽按钮的 connect 处理
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("_on_equip_slot_pressed")) \
		.override_failure_message("装备槽点击应连接到 _on_equip_slot_pressed").is_true()
	# GDScript 不支持跨行 or,拆为两段分别断言
	var has_bind := source.contains("pressed.connect(_on_equip_slot_pressed.bind")
	var has_simple := source.contains("pressed.connect(_on_equip_slot_pressed")
	assert_bool(has_bind or has_simple) \
		.override_failure_message("装备槽按钮 pressed 信号应连接卸下处理").is_true()


func test_chest_loot_panel_uses_weight_bar() -> void:
	# 重量条应使用 ProgressBar 而非自绘,且有更新函数
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("_update_weight_bar")) \
		.override_failure_message("应有 _update_weight_bar 更新函数").is_true()
	# 拆开 or 避免 GDScript 解析歧义
	var has_space_limit := source.contains("space_limit")
	var has_inventory := source.contains("expedition_inventory")
	assert_bool(has_space_limit or has_inventory) \
		.override_failure_message("重量条应读取背包空间上限").is_true()


func test_chest_loot_panel_uses_affix_quality_color() -> void:
	# 装备槽应使用品质色 modulate
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("get_affix_color")) \
		.override_failure_message("装备槽应使用 get_affix_color 决定品质色").is_true()
	# 拆开 or
	var has_btn_modulate := source.contains("btn.modulate = affix_color")
	var has_plain_modulate := source.contains("modulate = affix_color")
	assert_bool(has_btn_modulate or has_plain_modulate) \
		.override_failure_message("装备槽按钮 modulate 应使用品质色").is_true()


func test_chest_loot_panel_uses_equip_slot_theme_variation() -> void:
	# 装备槽按钮应使用 LootEquipSlot 主题变体
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("&\"LootEquipSlot\"")) \
		.override_failure_message("装备槽按钮应使用 LootEquipSlot 主题变体").is_true()


func test_theme_has_loot_equip_slot_variation() -> void:
	# lantern_theme.tres 必须有 LootEquipSlot 主题变体
	var f := FileAccess.open("res://scenes/ui/lantern_theme.tres", FileAccess.READ)
	assert_object(f).is_not_null()
	var text := f.get_as_text()
	f.close()
	assert_bool(text.contains("LootEquipSlot/base_type")) \
		.override_failure_message("lantern_theme.tres 必须注册 LootEquipSlot 主题变体").is_true()
	assert_bool(text.contains("LootEquipSlotNormal")) \
		.override_failure_message("LootEquipSlot 应有 normal 样式").is_true()
	assert_bool(text.contains("LootEquipSlotHover")) \
		.override_failure_message("LootEquipSlot 应有 hover 样式").is_true()
	assert_bool(text.contains("LootEquipSlotDisabled")) \
		.override_failure_message("LootEquipSlot 应有 disabled 样式(空槽)").is_true()


func test_chest_loot_panel_joins_character_panel_group() -> void:
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	assert_bool(panel.is_in_group("character_panel")).is_true()
	panel.queue_free()


# ============================================================================
# 2. GameEvents 信号
# ============================================================================

func test_game_events_has_chest_opened_signal() -> void:
	var script := load("res://globals/core/game_events.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("signal chest_opened")) \
		.override_failure_message("GameEvents 缺少 chest_opened 信号").is_true()


# ============================================================================
# 3. chest.gd 新行为验证
# ============================================================================

func test_chest_has_loot_data_property() -> void:
	var script := load("res://scenes/props/chest/chest.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("var loot_data")) \
		.override_failure_message("chest.gd 缺少 loot_data 属性").is_true()


func test_chest_has_close_loot_panel_method() -> void:
	var script := load("res://scenes/props/chest/chest.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func close_loot_panel")) \
		.override_failure_message("chest.gd 缺少 close_loot_panel 方法").is_true()


func test_chest_open_interactive_emits_signal() -> void:
	var script := load("res://scenes/props/chest/chest.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("GameEvents.chest_opened.emit")) \
		.override_failure_message("交互开启宝箱时应发射 chest_opened 信号").is_true()


func test_chest_open_interactive_does_not_spawn_physical() -> void:
	var script := load("res://scenes/props/chest/chest.gd") as GDScript
	var source := script.source_code
	# 交互开启走 _generate_loot_data 路径，不调用 _spawn_loot_physical
	assert_bool(source.contains("if by_interact:")) \
		.override_failure_message("open_chest 应根据 by_interact 分支").is_true()
	assert_bool(source.contains("_generate_loot_data()")) \
		.override_failure_message("交互开启应调用 _generate_loot_data").is_true()
	# 确认交互开启不再调用 queue_free（面板关闭时才销毁）
	var interact_block_start := source.find("if by_interact:")
	var interact_block_end := source.find("else:", interact_block_start)
	var interact_block := source.substr(interact_block_start, interact_block_end - interact_block_start)
	assert_bool(not interact_block.contains("queue_free()")) \
		.override_failure_message("交互开启不应立即 queue_free").is_true()


func test_chest_melee_still_spawns_physical() -> void:
	var script := load("res://scenes/props/chest/chest.gd") as GDScript
	var source := script.source_code
	# 攻击破坏走 _spawn_loot_physical 路径，仍调用 queue_free
	var else_block_start := source.find("_spawn_loot_physical()")
	var else_block := source.substr(else_block_start, 200)
	assert_bool(else_block.contains("queue_free()")) \
		.override_failure_message("攻击破坏宝箱应仍调用 queue_free").is_true()


func test_chest_close_loot_panel_frees_chest() -> void:
	var script := load("res://scenes/props/chest/chest.gd") as GDScript
	var source := script.source_code
	var close_block_start := source.find("func close_loot_panel()")
	var close_block := source.substr(close_block_start, 300)
	assert_bool(close_block.contains("queue_free()")) \
		.override_failure_message("close_loot_panel 应调用 queue_free 销毁宝箱").is_true()


# ============================================================================
# 4. player.gd 集成验证
# ============================================================================

func test_player_connects_chest_opened_signal() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("GameEvents.chest_opened.connect(_on_chest_opened)")) \
		.override_failure_message("player.gd 未连接 chest_opened 信号").is_true()


func test_player_has_on_chest_opened_handler() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _on_chest_opened")) \
		.override_failure_message("player.gd 缺少 _on_chest_opened 方法").is_true()


func test_player_has_chest_loot_panel_scene_preload() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("CHEST_LOOT_PANEL_SCENE")) \
		.override_failure_message("player.gd 未预加载 chest_loot_panel 场景").is_true()


func test_player_input_respects_chest_panel_visibility() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	# player.gd 应引用 _chest_loot_panel（面板生命周期管理 + 宝箱交互跳过）
	assert_bool(source.contains("_chest_loot_panel")) \
		.override_failure_message("player.gd 应引用 _chest_loot_panel").is_true()
	# _physics_process 应在面板可见时跳过宝箱交互
	assert_bool(source.contains("_chest_loot_panel") and source.contains("chest_interact_time = 0.0")) \
		.override_failure_message("面板打开时应重置 chest_interact_time").is_true()


func test_player_check_for_possible_action_respects_chest_panel() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	# check_for_possible_action 应在面板可见时提前返回
	var fn_start := source.find("func check_for_possible_action()")
	var fn_block := source.substr(fn_start, 500)
	assert_bool(fn_block.contains("_chest_loot_panel")) \
		.override_failure_message("check_for_possible_action 应检查 _chest_loot_panel 可见性").is_true()


# ============================================================================
# 5. chest_loot_panel.gd 逻辑验证
# ============================================================================

func test_panel_has_show_for_chest_method() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func show_for_chest")) \
		.override_failure_message("chest_loot_panel 缺少 show_for_chest 方法").is_true()


func test_panel_has_take_item_method() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _take_item")) \
		.override_failure_message("chest_loot_panel 缺少 _take_item 方法").is_true()


func test_panel_has_take_all_method() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _take_all")) \
		.override_failure_message("chest_loot_panel 缺少 _take_all 方法").is_true()


func test_panel_has_close_method() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _close")) \
		.override_failure_message("chest_loot_panel 缺少 _close 方法").is_true()


func test_panel_takes_material_adds_to_backpack() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	# _take_material 应更新 _backpack_materials
	assert_bool(source.contains("_backpack_materials[mat_id]")) \
		.override_failure_message("_take_material 应更新背包材料缓存").is_true()
	# 应调用 GameState.add_carried_material
	assert_bool(source.contains("gs.add_carried_material") or source.contains("add_carried_material")) \
		.override_failure_message("_take_material 应记录到 GameState").is_true()
	assert_bool(source.contains("tm.add_material") or source.contains("TavernManager.add_material")) \
		.override_failure_message("宝箱材料不应直接写入 TavernManager 仓库").is_false()

func test_panel_takes_rune_adds_to_backpack() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("_loot_runes")) \
		.override_failure_message("宝箱面板应维护 _loot_runes").is_true()
	assert_bool(source.contains("_take_rune")) \
		.override_failure_message("宝箱面板应支持取走符文").is_true()
	assert_bool(source.contains("add_carried_rune")) \
		.override_failure_message("取走符文必须写入 GameState.add_carried_rune").is_true()


func test_panel_takes_equipment_adds_specific_id_to_backpack() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("add_carried_equipment_instance(data)")) \
		.override_failure_message("宝箱装备应把完整 data 实例记录到 GameState 背包").is_true()


func test_panel_returns_equipment_to_chest_using_rolled_instance() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("remove_carried_equipment_instance")) \
		.override_failure_message("从背包回存宝箱必须优先取出完整装备实例").is_true()
	assert_bool(source.contains("data.duplicate() as WeaponData")) \
		.override_failure_message("回存宝箱的装备必须复制实例，不能退化为注册表共享对象").is_true()
	assert_bool(source.contains("func _return_material_to_chest")) \
		.override_failure_message("背包回存材料应使用独立函数，避免缩进分支解析错误").is_true()


func test_panel_collects_armor_as_carried_equipment_instance() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	var old_materials: Dictionary = inventory.materials.duplicate()
	var old_runes: Dictionary = inventory.runes.duplicate()
	var old_equipment: Dictionary = inventory.equipment.duplicate()
	var old_instances: Dictionary = inventory.equipment_instances.duplicate(true)
	var old_limit: int = inventory.space_limit
	inventory.clear()
	inventory.space_limit = 30

	var armor: WeaponData = WeaponRegistry.build_weapon_data_with_tier("plate_armor", 0)
	assert_object(armor).is_not_null()
	assert_bool(armor.equipment_category.begins_with("armor")).is_true()
	var chest := Chest.new()
	chest.loot_data = {"weapon": armor, "weapons": [armor], "materials": [], "runes": []}
	add_child(chest)
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	panel.show_for_chest(chest, null)
	panel.call("_take_item", 0)

	assert_int(int(inventory.equipment.get("plate_armor", 0))).is_equal(1)
	var stored: WeaponData = gs.get_carried_equipment_instance("plate_armor")
	assert_object(stored).is_not_null()
	assert_str(stored.equipment_category).is_equal("armor_heavy")
	assert_str(stored.armor_slot).is_equal("body")
	assert_int(stored.armor_phys_def).is_greater(0)
	assert_bool(chest.loot_data["weapons"].is_empty()).is_true()

	panel.queue_free()
	chest.queue_free()
	inventory.materials = old_materials
	inventory.runes = old_runes
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances
	inventory.space_limit = old_limit


func test_panel_take_all_keeps_overflow_loot_when_backpack_full() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("remaining_materials")) \
		.override_failure_message("_take_all 应保留容量不足时没拿走的材料").is_true()
	assert_bool(source.contains("remaining_runes")) \
		.override_failure_message("_take_all 应保留容量不足时没拿走的符文").is_true()
	assert_bool(source.contains("_add_equipment_to_backpack(data)")) \
		.override_failure_message("_take_all 应先确认装备入包成功再从宝箱移除").is_true()


func test_panel_close_restores_player_input() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	var close_block_start := source.find("func _close()")
	var close_block := source.substr(close_block_start, 500)
	assert_bool(close_block.contains("movement_input_enabled = true")) \
		.override_failure_message("_close 应恢复玩家移动输入").is_true()
	assert_bool(close_block.contains("interaction_input_enabled = true")) \
		.override_failure_message("_close 应恢复玩家交互输入").is_true()
	assert_bool(close_block.contains("combat_input_enabled = true")) \
		.override_failure_message("_close 应恢复玩家战斗输入").is_true()
	assert_bool(close_block.contains("MOUSE_MODE_CAPTURED")) \
		.override_failure_message("_close 应恢复鼠标捕获模式").is_true()


func test_panel_close_calls_chest_close_loot_panel() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	var close_block_start := source.find("func _close()")
	var close_block := source.substr(close_block_start, 500)
	assert_bool(close_block.contains("close_loot_panel")) \
		.override_failure_message("_close 应调用 chest.close_loot_panel()").is_true()


func test_panel_show_sets_mouse_visible() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("MOUSE_MODE_VISIBLE")) \
		.override_failure_message("面板显示时应设置鼠标为可见模式").is_true()


func test_panel_handles_esc_and_tab() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("KEY_ESCAPE")) \
		.override_failure_message("面板应支持 ESC 关闭").is_true()
	assert_bool(source.contains("KEY_TAB")) \
		.override_failure_message("面板应支持 TAB 关闭").is_true()


# ============================================================================
# 6. 集成测试：宝箱交互开启 → 面板显示 → 一键收获 → 关闭
# ============================================================================

func test_chest_interactive_open_generates_loot_data() -> void:
	# 验证交互开启宝箱后 loot_data 结构正确
	var chest := Chest.new()
	# 不在场景树中时 LootTable 不可达，loot_data 应为空字典
	chest.open_chest(true)
	assert_bool(chest.is_opened).is_true()
	# loot_data 应被初始化（即使 LootTable 不可达）
	if not chest.loot_data.is_empty():
		assert_bool(chest.loot_data.has("weapon")).is_true()
		assert_bool(chest.loot_data.has("materials")).is_true()
		assert_bool(chest.loot_data.has("runes")).is_true()
	chest.free()


func test_chest_melee_open_does_not_generate_loot_data() -> void:
	# 攻击开启走物理掉落路径，不生成 loot_data
	var chest := Chest.new()
	chest.open_chest(false)
	assert_bool(chest.is_opened).is_true()
	# loot_data 应保持默认空字典
	assert_bool(chest.loot_data.is_empty()).is_true()
	chest.free()


func test_panel_scene_has_correct_layer() -> void:
	var scene := load("res://scenes/ui/chest_loot_panel.tscn") as PackedScene
	var panel: Node = scene.instantiate()
	# CanvasLayer 层级应高于 UI 层 (20)
	assert_int((panel as CanvasLayer).layer).is_greater_equal(20)
	panel.free()


# ============================================================================
# 7. 网格图标模式 + 词缀显示验证
# ============================================================================

func test_chest_list_uses_grid_icon_mode() -> void:
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var chest_list: ItemList = panel.get_node("%ChestList")
	assert_int(chest_list.icon_mode).is_equal(ItemList.ICON_MODE_TOP)
	assert_int(chest_list.fixed_icon_size.x).is_equal(56)
	assert_int(chest_list.fixed_icon_size.y).is_equal(56)
	assert_int(chest_list.max_columns).is_equal(0)
	assert_bool(chest_list.same_column_width).is_true()
	panel.queue_free()


func test_backpack_list_uses_grid_icon_mode() -> void:
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var backpack_list: ItemList = panel.get_node("%BackpackList")
	assert_int(backpack_list.icon_mode).is_equal(ItemList.ICON_MODE_TOP)
	assert_int(backpack_list.fixed_icon_size.x).is_equal(56)
	assert_int(backpack_list.fixed_icon_size.y).is_equal(56)
	assert_int(backpack_list.max_columns).is_equal(0)
	assert_bool(backpack_list.same_column_width).is_true()
	panel.queue_free()


func test_panel_has_equipment_tooltip_builder() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _build_equipment_tooltip")) \
		.override_failure_message("chest_loot_panel 应有 _build_equipment_tooltip 方法").is_true()
	assert_bool(source.contains("get_affix_quality_label")) \
		.override_failure_message("_build_equipment_tooltip 应调用 get_affix_quality_label").is_true()
	assert_bool(source.contains("get_affix_detail_lines")) \
		.override_failure_message("_build_equipment_tooltip 应调用 get_affix_detail_lines").is_true()


func test_panel_uses_detail_popup_icons() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("DETAIL_POPUP_SCRIPT")) \
		.override_failure_message("chest_loot_panel 应引用 DETAIL_POPUP_SCRIPT 获取图标").is_true()
	assert_bool(source.contains("icon_for_equipment_id")) \
		.override_failure_message("应使用 icon_for_equipment_id 获取装备图标").is_true()
	assert_bool(source.contains("icon_for_material")) \
		.override_failure_message("应使用 icon_for_material 获取材料图标").is_true()
	assert_bool(source.contains("icon_for_rune")) \
		.override_failure_message("应使用 icon_for_rune 获取符文图标").is_true()


func test_panel_equipment_items_use_icons_not_text() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	# 装备项应使用空文本 + 图标（add_item("", icon)），而非纯文字行
	var refresh_start := source.find("func _refresh_chest_list()")
	var refresh_block := source.substr(refresh_start, 800)
	assert_bool(refresh_block.contains("add_item(\"\", icon)")) \
		.override_failure_message("宝箱装备项应使用空文本+图标模式").is_true()
	assert_bool(refresh_block.contains("set_item_tooltip")) \
		.override_failure_message("宝箱装备项应设置 tooltip 含词缀信息").is_true()


func test_panel_backpack_equipment_uses_icons_and_tooltips() -> void:
	var script := load("res://scenes/ui/chest_loot_panel.gd") as GDScript
	var source := script.source_code
	var refresh_start := source.find("func _refresh_backpack_list()")
	var refresh_block := source.substr(refresh_start, 2000)
	assert_bool(refresh_block.contains("icon_for_equipment_id")) \
		.override_failure_message("背包装备项应使用 icon_for_equipment_id 获取图标").is_true()
	assert_bool(refresh_block.contains("set_item_tooltip")) \
		.override_failure_message("背包装备项应设置 tooltip").is_true()
	assert_bool(refresh_block.contains("_build_equipment_tooltip")) \
		.override_failure_message("背包装备项应使用 _build_equipment_tooltip 构建词缀信息").is_true()


# ============================================================================
# 8. 本地化验证:不得同时显示双语
# ============================================================================

func test_chest_loot_panel_tscn_has_no_bilingual_text() -> void:
	# .tscn 中所有 text 属性不得包含 "  /  " 双语分隔模式
	var f := FileAccess.open("res://scenes/ui/chest_loot_panel.tscn", FileAccess.READ)
	assert_object(f).is_not_null()
	var text := f.get_as_text()
	f.close()
	# 检查 text = "xxx  /  yyy" 模式(双语分隔)
	var bilingual_pattern := RegEx.new()
	bilingual_pattern.compile("text\\s*=\\s*\"[^\"]*  /  [^\"]*\"")
	var result := bilingual_pattern.search(text)
	assert_bool(result == null) \
		.override_failure_message("chest_loot_panel.tscn 中不得包含双语 text 属性(英文  /  中文)").is_true()


func test_chest_loot_panel_gd_has_no_bilingual_strings() -> void:
	# .gd 源码中不得在字符串字面量中包含 CJK 中文字符
	# (注释中的中文是允许的,只检查字符串字面量)
	# tr() 调用中的 key 是纯英文,不会包含 CJK 字符
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# 移除注释行(以 # 开头的行),只检查代码
	var lines := source.split("\n")
	var code_only := ""
	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		code_only += line + "\n"
	# 检查字符串字面量中是否包含 CJK 统一表意文字(U+4E00 - U+9FFF)
	var cjk_pattern := RegEx.new()
	cjk_pattern.compile("\"[^\"]*[\\x{4e00}-\\x{9fff}][^\"]*\"")
	var result := cjk_pattern.search(code_only)
	assert_bool(result == null) \
		.override_failure_message("chest_loot_panel.gd 代码中不得包含中文字符串字面量(应使用 tr() 本地化)").is_true()


func test_chest_loot_panel_gd_uses_tr_for_dynamic_strings() -> void:
	# 验证动态字符串使用 tr() 而非硬编码
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# item_count_label 应使用 tr()
	assert_bool(source.contains("tr(\"items  chest %d  /  bag %d    weight  %.2fkg\")")) \
		.override_failure_message("item_count 应使用 tr() 本地化").is_true()
	# weight_label 应使用 tr()
	assert_bool(source.contains("tr(\"BAG  %d / %d  (%d%%)\")")) \
		.override_failure_message("weight_label 应使用 tr() 本地化").is_true()
	# tooltip 应使用 tr()
	assert_bool(source.contains("tr(\"click to unequip\")")) \
		.override_failure_message("卸下 tooltip 应使用 tr() 本地化").is_true()
	assert_bool(source.contains("tr(\"Empty slot\")")) \
		.override_failure_message("空槽 tooltip 应使用 tr() 本地化").is_true()
	# 装备槽标签应使用 tr_key + tr()
	assert_bool(source.contains("tr(slot_tr_key)")) \
		.override_failure_message("装备槽标签应使用 tr(slot_tr_key) 本地化").is_true()
	# 耐久度应使用 tr()
	assert_bool(source.contains("tr(\"Durability %d/%d\")")) \
		.override_failure_message("耐久度文本应使用 tr() 本地化").is_true()


func test_chest_loot_panel_gd_uses_tr_for_empty_label() -> void:
	# [Empty] 标签应使用 tr()
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("tr(\"[Empty]\")")) \
		.override_failure_message("[Empty] 标签应使用 tr() 本地化").is_true()


func test_chest_loot_panel_translation_keys_exist_in_csv() -> void:
	# 验证所有新增的翻译 key 都存在于 translations.csv 中
	var f := FileAccess.open("res://scenes/ui/localization/translations.csv", FileAccess.READ)
	assert_object(f).is_not_null()
	var csv_text := f.get_as_text()
	f.close()
	var required_keys := [
		"LOOT", "CLOSE", "EQUIPMENT", "CHEST", "BACKPACK", "HARVEST ALL",
		"click slot to unequip", "double-click a gear item to equip",
		"double-click to loot", "double-click to store",
		"hover items to inspect", "click to unequip", "Empty slot",
		"[Empty]",
		"items  chest %d  /  bag %d    weight  %.2fkg",
		"BAG  %d / %d  (%d%%)",
		"EQ_SLOT_HEAD", "EQ_SLOT_CHEST", "EQ_SLOT_HANDS", "EQ_SLOT_FEET",
		"EQ_SLOT_MAIN", "EQ_SLOT_OFF", "EQ_SLOT_BACK", "EQ_SLOT_ACC",
	]
	var csv_lines := csv_text.split("\n")
	for key in required_keys:
		# CSV 格式: key,en,zh — 检查是否有以 "key," 开头的行
		var prefix: String = String(key) + ","
		var found := false
		for line in csv_lines:
			if line.begins_with(prefix):
				found = true
				break
		assert_bool(found) \
			.override_failure_message("translations.csv 缺少 key: " + key).is_true()


# ============================================================================
# 9. 装备数据源同源验证 — 使用 EquipmentComponent 真实 API
# ============================================================================

func test_panel_load_equipment_uses_get_armor_slot_data() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("get_armor_slot_data")) \
		.override_failure_message("_load_equipment 应调用 equip.get_armor_slot_data 读取护甲").is_true()


func test_panel_load_equipment_uses_get_weapon_slot_data() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("get_weapon_slot_data")) \
		.override_failure_message("_load_equipment 应调用 equip.get_weapon_slot_data 读取武器").is_true()


func test_panel_slot_defs_use_body_not_chest() -> void:
	# SLOT_DEFS 中护甲槽 key 应为 "body"（对应 armor_slots["body"]），不是 "chest"
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# "body" 应出现在 SLOT_DEFS 中
	var body_in_defs := source.contains('"key": "body"')
	assert_bool(body_in_defs) \
		.override_failure_message("SLOT_DEFS 应包含 key=\"body\" (对齐 armor_slots)").is_true()
	# 不应有 "chest" 作为 slot key（tr_key 是 EQ_SLOT_CHEST，但 key 是 body）
	var chest_key := source.contains('"key": "chest"')
	assert_bool(not chest_key) \
		.override_failure_message("SLOT_DEFS 不应包含 key=\"chest\"（应使用 key=\"body\"）").is_true()


func test_panel_slot_defs_use_weapon_indices_not_main_hand() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# 不应使用不存在的 "main_hand"/"off_hand" 作为 slot key
	assert_bool(not source.contains('"key": "main_hand"')) \
		.override_failure_message("不应使用 key=\"main_hand\"（weapon_slots 是数组索引）").is_true()
	assert_bool(not source.contains('"key": "off_hand"')) \
		.override_failure_message("不应使用 key=\"off_hand\"（weapon_slots 是数组索引）").is_true()
	# 应使用 weapon_0..3
	assert_bool(source.contains('"key": "weapon_0"')) \
		.override_failure_message("SLOT_DEFS 应包含 key=\"weapon_0\"").is_true()


func test_panel_no_longer_references_nonexistent_get_slot_data() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# 不应再调用不存在的 get_slot_data / equipped_items / unequip_slot / set_slot_data
	assert_bool(not source.contains("get_slot_data")) \
		.override_failure_message("不应再调用不存在的 equip.get_slot_data").is_true()
	assert_bool(not source.contains('"equipped_items" in equip')) \
		.override_failure_message("不应再引用不存在的 equipped_items 字段").is_true()
	assert_bool(not source.contains('equip.call("unequip_slot"')) \
		.override_failure_message("不应再调用不存在的 unequip_slot 方法").is_true()
	assert_bool(not source.contains('equip.call("set_slot_data"')) \
		.override_failure_message("不应再调用不存在的 set_slot_data 方法").is_true()


# ============================================================================
# 10. 从背包装备到玩家 — _equip_from_backpack
# ============================================================================

func test_panel_has_equip_from_backpack_method() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("func _equip_from_backpack")) \
		.override_failure_message("chest_loot_panel 应有 _equip_from_backpack 方法").is_true()


func test_panel_equip_from_backpack_uses_is_armor_equipment() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("is_armor_equipment")) \
		.override_failure_message("_equip_from_backpack 应调用 is_armor_equipment 判定护甲").is_true()


func test_panel_equip_from_backpack_calls_equip_armor_for_armor() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# 装备护甲应通过 configure_armor_slot 直接配置，不走 equip_armor（后者会误生成物理掉落物）
	assert_bool(source.contains("_configure_armor_from_backpack")) \
		.override_failure_message("护甲应通过 _configure_armor_from_backpack → configure_armor_slot 装备").is_true()
	assert_bool(not source.contains("equip.equip_armor(data)")) \
		.override_failure_message("宝箱面板不应使用 equip.equip_armor(data)（会误生成物理掉落物）").is_true()


func test_panel_equip_from_backpack_calls_equip_weapon_for_weapon() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# 装备武器应通过 configure_weapon_slot 直接配置，不走 equip_weapon（后者会误生成物理掉落物）
	assert_bool(source.contains("_configure_weapon_from_backpack")) \
		.override_failure_message("武器应通过 _configure_weapon_from_backpack → configure_weapon_slot 装备").is_true()
	assert_bool(not source.contains("equip.equip_weapon(data)")) \
		.override_failure_message("宝箱面板不应使用 equip.equip_weapon(data)（会误生成物理掉落物）").is_true()


func test_panel_equip_from_backpack_persists_to_game_state() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# 装备变更后应调用 save_equipment_from_player 持久化到 GameState（与酒馆面板同源）
	assert_bool(source.contains("save_equipment_from_player")) \
		.override_failure_message("装备变更后应调用 save_equipment_from_player 持久化到 GameState").is_true()


func test_panel_equip_from_backpack_restores_on_failure() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# 装备失败时应放回背包
	assert_bool(source.contains("gs.add_carried_equipment_instance(data)")) \
		.override_failure_message("装备失败时应调 add_carried_equipment_instance 放回背包").is_true()


# ============================================================================
# 11. 卸下装备 — 使用真实 configure_armor_slot / configure_weapon_slot
# ============================================================================

func test_panel_unequip_uses_configure_armor_slot() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("equip.configure_armor_slot(slot_key, null)")) \
		.override_failure_message("卸下护甲应调 configure_armor_slot(slot_key, null)").is_true()


func test_panel_unequip_uses_configure_weapon_slot() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("equip.configure_weapon_slot(idx, null")) \
		.override_failure_message("卸下武器应调 configure_weapon_slot(idx, null)").is_true()


# ============================================================================
# 12. 双击背包装备 → 装备到玩家（不再放回宝箱）
# ============================================================================

func test_panel_backpack_double_click_equips_not_returns() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# _on_backpack_item_activated 的 equipment 分支应调 _equip_from_backpack
	var fn_start := source.find("func _on_backpack_item_activated")
	var fn_block := source.substr(fn_start, 800)
	assert_bool(fn_block.contains("_equip_from_backpack")) \
		.override_failure_message("双击背包装备应调 _equip_from_backpack 装备到玩家").is_true()


# ============================================================================
# 13. 拖放支持验证
# ============================================================================

func test_panel_has_drag_drop_methods() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("func _on_list_gui_input")) \
		.override_failure_message("应有 _on_list_gui_input 检测列表拖动").is_true()
	assert_bool(source.contains("func _on_equip_slot_gui_input")) \
		.override_failure_message("应有 _on_equip_slot_gui_input 检测装备槽拖动").is_true()
	assert_bool(source.contains("func can_drop_to_zone")) \
		.override_failure_message("应有 can_drop_to_zone 判断拖放目标").is_true()
	assert_bool(source.contains("func drop_to_zone")) \
		.override_failure_message("应有 drop_to_zone 处理拖放").is_true()
	assert_bool(source.contains("force_drag")) \
		.override_failure_message("应使用 force_drag 发起拖放").is_true()


func test_panel_drop_zone_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/loot_drop_zone.gd")).is_true()


func test_panel_sets_up_drop_zones() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	assert_bool(source.contains("_setup_drop_zone(equip_grid")) \
		.override_failure_message("应为 equip_grid 设置 drop zone").is_true()
	assert_bool(source.contains('_setup_drop_zone(backpack_list')) \
		.override_failure_message("应为 backpack_list 设置 drop zone").is_true()
	assert_bool(source.contains('_setup_drop_zone(chest_list')) \
		.override_failure_message("应为 chest_list 设置 drop zone").is_true()


func test_panel_can_drop_to_equipment_from_backpack() -> void:
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("equipment", {"source": "backpack", "type": "equipment"})
	assert_bool(result).is_true()
	panel.queue_free()


func test_panel_cannot_drop_to_equipment_from_chest() -> void:
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("equipment", {"source": "chest", "type": "equipment"})
	assert_bool(result).is_false()
	panel.queue_free()


func test_panel_can_drop_to_backpack_from_equipment() -> void:
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("backpack", {"source": "equipment", "type": "equipment"})
	assert_bool(result).is_true()
	panel.queue_free()


func test_panel_can_drop_to_backpack_from_chest() -> void:
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("backpack", {"source": "chest", "type": "material"})
	assert_bool(result).is_true()
	panel.queue_free()


func test_panel_can_drop_to_chest_from_backpack() -> void:
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var result: bool = panel.can_drop_to_zone("chest", {"source": "backpack", "type": "equipment"})
	assert_bool(result).is_true()
	panel.queue_free()


# ============================================================================
# 14. 集成测试：从背包装备护甲到玩家
# ============================================================================

func test_panel_equip_armor_from_backpack_to_player() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	var inventory = gs.expedition_inventory
	# 保存原始状态
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

	# 构建玩家 + 装备组件（用带 equipment 属性的 mock player）
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip

	# 构建面板
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var chest := Chest.new()
	chest.loot_data = {"weapon": null, "weapons": [], "materials": [], "runes": []}
	add_child(chest)
	panel.show_for_chest(chest, player)

	# 从背包装备护甲
	var result: bool = panel.call("_equip_from_backpack", "plate_armor")
	assert_bool(result).is_true()

	# 验证护甲已装备到玩家身上
	var body_armor: WeaponData = equip.get_armor_slot_data("body")
	assert_object(body_armor).is_not_null()
	assert_str(body_armor.equipment_category).is_equal("armor_heavy")

	# 验证背包中已移除
	assert_bool(not inventory.equipment.has("plate_armor")).is_true()

	panel.queue_free()
	chest.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


func test_panel_equip_weapon_from_backpack_to_player() -> void:
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

	# 构建玩家 + 装备组件（用带 equipment 属性的 mock player）
	var player := _create_mock_player()
	add_child(player)
	var equip := EquipmentComponent.new()
	add_child(equip)
	player.equipment = equip

	# 构建面板
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var chest := Chest.new()
	chest.loot_data = {"weapon": null, "weapons": [], "materials": [], "runes": []}
	add_child(chest)
	panel.show_for_chest(chest, player)

	# 从背包装备武器
	var result: bool = panel.call("_equip_from_backpack", "shortsword")
	assert_bool(result).is_true()

	# 验证武器已装备到武器槽 0
	var slot_data: WeaponData = equip.get_weapon_slot_data(0)
	assert_object(slot_data).is_not_null()
	assert_str(slot_data.id).is_equal("shortsword")

	# 验证背包中已移除
	assert_bool(not inventory.equipment.has("shortsword")).is_true()

	panel.queue_free()
	chest.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


# ============================================================================
# 15. 集成测试：卸下装备到背包
# ============================================================================

func test_panel_unequip_armor_to_backpack() -> void:
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

	# 构建面板
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var chest := Chest.new()
	chest.loot_data = {"weapon": null, "weapons": [], "materials": [], "runes": []}
	add_child(chest)
	panel.show_for_chest(chest, player)

	# 点击 body 槽卸下
	panel.call("_on_equip_slot_pressed", "body", equip.get_armor_slot_data("body"))

	# 验证护甲已从装备槽移除
	assert_object(equip.get_armor_slot_data("body")).is_null()
	# 验证护甲已加入背包
	assert_int(int(inventory.equipment.get("plate_armor", 0))).is_equal(1)

	panel.queue_free()
	chest.queue_free()
	equip.queue_free()
	player.queue_free()
	inventory.equipment = old_equipment
	inventory.equipment_instances = old_instances


# ============================================================================
# 16. 拖放逻辑验证
# ============================================================================

func test_panel_drop_to_equipment_equips_from_backpack() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	# drop_to_zone 的 equipment 分支应调 _equip_from_backpack
	var fn_start := source.find("func drop_to_zone")
	var fn_block := source.substr(fn_start, 500)
	assert_bool(fn_block.contains("_equip_from_backpack")) \
		.override_failure_message("拖放到装备区应调 _equip_from_backpack").is_true()


func test_panel_drop_to_backpack_unequips_from_equipment() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	var fn_start := source.find("func drop_to_zone")
	var fn_block := source.substr(fn_start, 600)
	assert_bool(fn_block.contains("_unequip_slot_to_backpack")) \
		.override_failure_message("从装备槽拖放到背包应调 _unequip_slot_to_backpack").is_true()


func test_panel_drop_to_chest_returns_from_backpack() -> void:
	var source := (load("res://scenes/ui/chest_loot_panel.gd") as GDScript).source_code
	var fn_start := source.find("func drop_to_zone")
	var fn_block := source.substr(fn_start, 600)
	assert_bool(fn_block.contains("_return_equipment_to_chest_by_id")) \
		.override_failure_message("从背包拖放到宝箱应调 _return_equipment_to_chest_by_id").is_true()
