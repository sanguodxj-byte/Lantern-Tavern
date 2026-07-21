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
	tree.root.remove_child(panel)
	panel.free()
	real_player.free()
	gs.current_player = previous_player

