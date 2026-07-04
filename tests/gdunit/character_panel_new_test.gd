extends GdUnitTestSuite

func test_character_panel_skills_loading() -> void:
	var scene = load("res://scenes/ui/character_panel.tscn")
	assert_object(scene).is_not_null()
	var panel = scene.instantiate()
	assert_object(panel).is_not_null()
	panel.queue_free()

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
	
	# Verify that EqSubViewport has own_world_3d set to true
	var viewport = panel.get_node("%EqSubViewport") as SubViewport
	assert_object(viewport).is_not_null()
	assert_bool(viewport.own_world_3d).is_true()
	
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
	assert_bool(ui.character_panel_instance.visible).is_true()
	
	# Cleanup
	if tree:
		tree.root.remove_child(ui)
	ui.free()

