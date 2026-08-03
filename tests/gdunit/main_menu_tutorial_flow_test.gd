extends GdUnitTestSuite

func test_main_menu_tutorial_options() -> void:
	var main_menu_script := load("res://scenes/ui/main_menu.gd") as GDScript
	var source := main_menu_script.source_code
	
	# Check main menu has tutorial flow
	assert_bool(source.contains("tutorial_choice_panel")).is_true()
	assert_bool(source.contains("start_with_tutorial_btn")).is_true()
	assert_bool(source.contains("skip_tutorial_btn")).is_true()
	assert_bool(source.contains("TavernManager.start_new_game"))

func test_world_space_tutorial_integration() -> void:
	var world_script := load("res://scenes/world/world.gd") as GDScript
	var source := world_script.source_code
	
	# Check world space management
	assert_bool(source.contains("SPACE_INTRO")).is_true()
	assert_bool(source.contains("SPACE_TAVERN")).is_true()
	assert_bool(source.contains("SPACE_DUNGEON")).is_true()
	assert_bool(source.contains("INTRO_SCENE_PATH")).is_true()
	assert_bool(source.contains("load_space"))

func test_tutorial_localization_support() -> void:
	# Test that tutorial dialogue uses translation system
	var intro_script := load("res://scenes/intro/new_game_intro.gd") as GDScript
	var tutorial_script := load("res://scenes/tavern/tutorial_tavern_coordinator.gd") as GDScript
	
	var intro_source := intro_script.source_code
	var tutorial_source := tutorial_script.source_code
	
	# Check for translation calls
	assert_bool(intro_source.contains('tr("hey! you! finally wake')).is_true()
	assert_bool(intro_source.contains('tr("WASD Move')).is_true()
	assert_bool(tutorial_source.contains('tr("Move away from the door')).is_true()
	assert_bool(tutorial_source.contains('tr("Grab the barrel')).is_true()


func test_main_menu_origin_selection_integration() -> void:
	var main_menu_script := load("res://scenes/ui/main_menu.gd") as GDScript
	var source := main_menu_script.source_code
	
	# 出身选择界面已接入新游戏流程
	assert_bool(source.contains("ORIGIN_SELECT_UI_SCRIPT")).is_true()
	assert_bool(source.contains("_setup_origin_select_ui")).is_true()
	assert_bool(source.contains("_on_origin_selected")).is_true()
	assert_bool(source.contains("_pending_origin_id")).is_true()
	# start_new_game 调用应传入 origin_id 参数
	assert_bool(source.contains("start_new_game(true, _pending_origin_id)")).is_true()
	assert_bool(source.contains("start_new_game(false, _pending_origin_id)")).is_true()


func test_origin_select_ui_has_required_signals() -> void:
	var ui_script := load("res://scenes/ui/origin_select_ui.gd") as GDScript
	var source := ui_script.source_code
	
	assert_bool(source.contains("signal origin_selected")).is_true()
	assert_bool(source.contains("signal back_requested")).is_true()
	assert_bool(source.contains("func reset_selection")).is_true()
	# 预加载出身数据
	assert_bool(source.contains("origin_data.gd")).is_true()


func test_tavern_manager_start_new_game_accepts_origin_id() -> void:
	var tm_script := load("res://globals/tavern/tavern_manager.gd") as GDScript
	var source := tm_script.source_code
	
	# start_new_game 签名应接受 origin_id 参数
	assert_bool(source.contains("func start_new_game(with_tutorial: bool = true, origin_id: String = \"\")")).is_true()
	# 应记录并应用出身
	assert_bool(source.contains("selected_origin_id = origin_id")).is_true()
	assert_bool(source.contains("_apply_origin_to_game_state")).is_true()


func test_tavern_manager_start_new_game_calls_reset_all() -> void:
	var tm_script := load("res://globals/tavern/tavern_manager.gd") as GDScript
	var source := tm_script.source_code
	
	# start_new_game 应在应用出身效果前调用 SaveManager.reset_all() 重置全部子系统
	assert_bool(source.contains("reset_all")).is_true()
	assert_bool(source.contains("SaveManager")).is_true()


func test_tavern_manager_grants_starting_equipment() -> void:
	var tm_script := load("res://globals/tavern/tavern_manager.gd") as GDScript
	var source := tm_script.source_code
	
	# 应存在 _grant_starting_equipment 方法，且在 _apply_origin_to_game_state 中调用
	assert_bool(source.contains("func _grant_starting_equipment")).is_true()
	assert_bool(source.contains("_grant_starting_equipment(gs, origin)")).is_true()
	# 武器应装备到主手槽(0)
	assert_bool(source.contains("set_weapon_slot(0, starting_weapon)")).is_true()
	assert_bool(source.contains("set_active_weapon_slot(0)")).is_true()
	# 盾牌应加入随身背包
	assert_bool(source.contains("add_carried_equipment(starting_shield, 1)")).is_true()


func test_origin_starting_weapon_ids_match_weapons_json() -> void:
	# 验证所有出身的 starting_weapon 和 starting_shield 在 weapons.json 中存在
	var weapons_json_path := "res://data/weapons/weapons.json"
	var file := FileAccess.open(weapons_json_path, FileAccess.READ)
	assert_object(file).is_not_null()
	if file == null:
		return
	var json_text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	assert_bool(parsed is Dictionary).is_true()
	if not parsed is Dictionary:
		return
	var data := parsed as Dictionary
	var entries: Array = data.get("weapons", [])
	
	# 收集 weapons.json 中所有有效的 equipment id
	var valid_ids: Dictionary = {}
	for entry in entries:
		if entry is Dictionary:
			var eid: String = String(entry.get("id", ""))
			if eid != "":
				valid_ids[eid] = true
	
	# 验证每个出身的 starting_weapon 和 starting_shield
	var OD := preload("res://globals/combat/origin_data.gd")
	for origin_id in OD.get_all_ids():
		var origin: Dictionary = OD.get_origin(origin_id)
		var weapon_id: String = String(origin.get("starting_weapon", ""))
		var shield_id: String = String(origin.get("starting_shield", ""))
		# 武器 ID 必须存在于 weapons.json
		assert_str(weapon_id).is_not_empty()
		assert_bool(valid_ids.has(weapon_id)).is_true()
		# 盾牌 ID 如果非空，也必须存在
		if shield_id != "":
			assert_bool(valid_ids.has(shield_id)).is_true()
