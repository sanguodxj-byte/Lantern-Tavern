extends GdUnitTestSuite

const PANEL_SCENE := preload("res://scenes/ui/level_up_panel.tscn")
const ATTR_PANEL_SCRIPT := preload("res://globals/combat/attr_panel.gd")
const GAME_STATE_SCRIPT := preload("res://globals/core/game_state.gd")


func test_level_up_panel_shows_six_attributes_and_rune_opportunity() -> void:
	var attrs: Node = auto_free(ATTR_PANEL_SCRIPT.new())
	var game_state: Node = auto_free(GAME_STATE_SCRIPT.new())
	attrs.accumulate_level_exp(100)
	var panel: LevelUpPanel = auto_free(PANEL_SCENE.instantiate())
	panel.configure(attrs, game_state)
	add_child(panel)
	await await_idle_frame()
	assert_bool(panel.visible).is_true()
	for node_name in ["StrButton", "DexButton", "MagButton", "ConButton", "AgiButton", "PerButton"]:
		assert_object(panel.get_node("%" + node_name)).is_instanceof(Button)
	assert_bool(panel.rune_opportunity_button.visible).is_true()
	assert_str(panel.rune_opportunity_button.text).contains("互斥")
	assert_str(panel.pending_label.text).contains("1")


func test_attribute_selection_updates_stat_and_closes_last_choice() -> void:
	var attrs: Node = auto_free(ATTR_PANEL_SCRIPT.new())
	var game_state: Node = auto_free(GAME_STATE_SCRIPT.new())
	attrs.accumulate_level_exp(100)
	var panel: LevelUpPanel = auto_free(PANEL_SCENE.instantiate())
	panel.configure(attrs, game_state)
	add_child(panel)
	await await_idle_frame()
	panel._choose_attribute("str")
	assert_int(attrs.get_attr("str")).is_equal(6)
	assert_int(attrs.get_pending_level_choices()).is_equal(0)
	assert_bool(panel.visible).is_false()


func test_rune_branch_displays_three_candidates_and_adds_selected_rune() -> void:
	var attrs: Node = auto_free(ATTR_PANEL_SCRIPT.new())
	var game_state: Node = auto_free(GAME_STATE_SCRIPT.new())
	attrs.accumulate_level_exp(100)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9911
	attrs.begin_level_up_rune_choice(rng)
	var panel: LevelUpPanel = auto_free(PANEL_SCENE.instantiate())
	panel.configure(attrs, game_state)
	add_child(panel)
	await await_idle_frame()
	assert_bool(panel.rune_choice.visible).is_true()
	assert_bool(panel.main_choice.visible).is_false()
	assert_bool(attrs.choose_level_up_attribute("con")).is_false()
	assert_int(attrs.get_pending_level_choices()).is_equal(1)
	for button in panel.rune_buttons:
		assert_bool(button.visible).is_true()
		assert_str(String(button.get_meta("rune_id", ""))).is_not_empty()
	var selected_id := String(panel.rune_buttons[0].get_meta("rune_id"))
	panel._choose_rune(0)
	assert_int(int(game_state.carried_runes.get(selected_id, 0))).is_equal(1)
	assert_int(attrs.get_pending_level_choices()).is_equal(0)
	assert_bool(panel.visible).is_false()


func test_multiple_level_choices_keep_panel_open_until_queue_is_empty() -> void:
	var attrs: Node = auto_free(ATTR_PANEL_SCRIPT.new())
	var game_state: Node = auto_free(GAME_STATE_SCRIPT.new())
	attrs.accumulate_level_exp(350)
	var panel: LevelUpPanel = auto_free(PANEL_SCENE.instantiate())
	panel.configure(attrs, game_state)
	add_child(panel)
	await await_idle_frame()
	panel._choose_attribute("dex")
	assert_int(attrs.get_pending_level_choices()).is_equal(1)
	assert_bool(panel.visible).is_true()
	panel._choose_attribute("per")
	assert_int(attrs.get_pending_level_choices()).is_equal(0)
	assert_bool(panel.visible).is_false()


func test_panel_restores_the_players_previous_input_flags_after_choice() -> void:
	var attrs: Node = auto_free(ATTR_PANEL_SCRIPT.new())
	var game_state: Node = auto_free(GAME_STATE_SCRIPT.new())
	var player: Player = auto_free(Player.new())
	player.movement_input_enabled = false
	player.interaction_input_enabled = true
	player.combat_input_enabled = true
	game_state.current_player = player
	attrs.accumulate_level_exp(100)
	var panel: LevelUpPanel = auto_free(PANEL_SCENE.instantiate())
	panel.configure(attrs, game_state)
	add_child(panel)
	await await_idle_frame()
	assert_bool(player.movement_input_enabled).is_false()
	assert_bool(player.interaction_input_enabled).is_false()
	assert_bool(player.combat_input_enabled).is_false()
	panel._choose_attribute("agi")
	assert_bool(player.movement_input_enabled).is_false()
	assert_bool(player.interaction_input_enabled).is_true()
	assert_bool(player.combat_input_enabled).is_true()
