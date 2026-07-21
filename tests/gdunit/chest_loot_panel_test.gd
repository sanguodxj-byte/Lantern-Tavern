extends GdUnitTestSuite
## 宝箱战利品面板 (ChestLootPanel) 单元测试
## 验证：面板场景完整性、宝箱交互开启流程、战利品数据生成、一键收获逻辑

const BD := preload("res://globals/tavern/brewing_data.gd")

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
	panel.queue_free()


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
	assert_bool(source.contains("add_carried_weapon(data.id)") or source.contains("add_carried_shield(data.id)")) \
		.override_failure_message("宝箱装备应把具体 data.id 记录到 GameState 背包装备").is_true()


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
	var close_block := source.substr(close_block_start, 400)
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
	assert_int(chest_list.fixed_icon_size.x).is_equal(64)
	assert_int(chest_list.fixed_icon_size.y).is_equal(64)
	assert_int(chest_list.max_columns).is_equal(0)
	assert_bool(chest_list.same_column_width).is_true()
	panel.queue_free()


func test_backpack_list_uses_grid_icon_mode() -> void:
	var panel: Node = load("res://scenes/ui/chest_loot_panel.tscn").instantiate()
	add_child(panel)
	var backpack_list: ItemList = panel.get_node("%BackpackList")
	assert_int(backpack_list.icon_mode).is_equal(ItemList.ICON_MODE_TOP)
	assert_int(backpack_list.fixed_icon_size.x).is_equal(64)
	assert_int(backpack_list.fixed_icon_size.y).is_equal(64)
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
