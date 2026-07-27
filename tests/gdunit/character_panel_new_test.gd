extends GdUnitTestSuite

func test_character_panel_skills_loading() -> void:
	var scene = load("res://scenes/ui/character_panel.tscn")
	assert_object(scene).is_not_null()
	var panel = scene.instantiate()
	assert_object(panel).is_not_null()
	panel.free()

func test_character_panel_slots_inspection() -> void:
	var scene = load("res://scenes/ui/character_panel.tscn")
	var panel = scene.instantiate() as CharacterPanel
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.add_child(panel)
		
	# Inspect head armor slot
	panel._inspect_slot("Head", "Cozy Hood", "A very cozy hood.")
	assert_str(panel.eq_name_lbl.text).is_equal("Cozy Hood")
	assert_str(panel.eq_desc_lbl.text).is_equal("A very cozy hood.")
	
	# Cleanup
	if tree:
		tree.root.remove_child(panel)
	panel.free()


func test_character_panel_own_world_3d() -> void:
	var scene = load("res://scenes/ui/character_panel.tscn")
	assert_object(scene).is_not_null()
	
	var panel = scene.instantiate() as CharacterPanel
	
	# Verify that root visible default is false
	assert_bool(panel.visible).is_false()
	
	# Verify that EqSubViewport exists for 3D preview
	var viewport = panel.get_node("%EqSubViewport") as SubViewport
	assert_object(viewport).is_not_null()
	assert_bool(viewport.own_world_3d).is_true()
	
	# Verify that BattleStatsContainer also exists below the preview
	var stats = panel.get_node("%BattleStatsContainer") as VBoxContainer
	assert_object(stats).is_not_null()
	
	panel.free()


func test_ui_toggle_character_panel_first_time() -> void:
	var ui_scene = load("res://scenes/ui/ui.tscn")
	assert_object(ui_scene).is_not_null()
	
	var ui = ui_scene.instantiate() as UI
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.add_child(ui)
		
	# Verify initial state
	assert_object(ui.character_panel_instance).is_null()
	
	# Act: Toggle character panel for the first time
	ui.toggle_character_panel()
	
	# Assert: It should be instantiated and visible immediately
	assert_object(ui.character_panel_instance).is_not_null()
	assert_object(ui.character_panel_instance).is_instanceof(TavernEquipmentPanel)
	assert_bool(ui.character_panel_instance.visible).is_true()
	
	# Cleanup
	if tree:
		tree.root.remove_child(ui)
	ui.free()


func test_character_panel_preview_does_not_replace_current_player() -> void:
	var scene = load("res://scenes/ui/character_panel.tscn")
	var panel = scene.instantiate() as CharacterPanel
	var tree = Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node("GameState")
	var previous_player = gs.current_player
	var real_player := Player.new()
	gs.current_player = real_player
	tree.root.add_child(panel)
	panel._spawn_preview_character(null, null)
	assert_object(gs.current_player).is_equal(real_player)
	# 回归：预览 Player 必须携带 equipment_preview meta，
	# Player._ready 检测此 meta 后跳过 GameState.register_player。
	assert_bool(panel.current_eq_mesh.has_meta("equipment_preview")) \
		.override_failure_message("预览 Player 必须设置 equipment_preview meta 以跳过注册").is_true()
	tree.root.remove_child(panel)
	panel.free()
	real_player.free()
	gs.current_player = previous_player


## 回归：EquipmentPanelPlayerFinder._register_current_player 必须走 register_player 而非直写。
func test_finder_register_current_player_uses_register_player() -> void:
	var src: String = _source("res://scenes/ui/equipment_panel_player_finder.gd")
	var fn_start: int = src.find("static func _register_current_player")
	assert_int(fn_start).is_greater(0)
	var fn_end: int = src.find("\nstatic func", fn_start + 1)
	if fn_end == -1:
		fn_end = src.length()
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("register_player")) \
		.override_failure_message("_register_current_player 必须调用 register_player 而非直写 current_player").is_true()
	# 不得直写 current_player（应走 register_player），用局部变量避免多行 and 表达式解析问题
	var direct_write: bool = fn_body.contains("gs.set(\"current_player\"") or fn_body.contains("gs.current_player =")
	assert_bool(not direct_write) \
		.override_failure_message("_register_current_player 不得直写 current_player").is_true()


static func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code

