extends GdUnitTestSuite

const COMBAT_PROGRESSION := preload("res://globals/combat/combat_progression.gd")
const ATTR_PANEL_SCRIPT := preload("res://globals/combat/attr_panel.gd")

var _attributes


func before_test() -> void:
	_attributes = auto_free(ATTR_PANEL_SCRIPT.new())


func test_melee_final_damage_awards_equal_sword_and_strength_experience() -> void:
	var awarded := COMBAT_PROGRESSION.award_damage(_attributes, "sword", "melee", 18)
	assert_int(awarded).is_equal(18)
	assert_int(_attributes.get_proficiency("sword")).is_equal(18)
	assert_int(int(_attributes.attr_exp["str"])).is_equal(18)
	assert_int(int(_attributes.attr_exp["dex"])).is_equal(0)


func test_ranged_and_spell_damage_use_their_documented_attributes() -> void:
	COMBAT_PROGRESSION.award_damage(_attributes, "bow", "ranged", 7)
	COMBAT_PROGRESSION.award_damage(_attributes, "staff", "spell", 11)
	assert_int(_attributes.get_proficiency("bow")).is_equal(7)
	assert_int(_attributes.get_proficiency("staff")).is_equal(11)
	assert_int(int(_attributes.attr_exp["dex"])).is_equal(7)
	assert_int(int(_attributes.attr_exp["mag"])).is_equal(11)


func test_invalid_or_zero_damage_does_not_award_progression() -> void:
	assert_int(COMBAT_PROGRESSION.award_damage(_attributes, "sword", "melee", 0)).is_equal(0)
	assert_int(COMBAT_PROGRESSION.award_damage(_attributes, "sword", "unknown", 9)).is_equal(0)
	assert_int(COMBAT_PROGRESSION.award_damage(_attributes, "", "melee", 9)).is_equal(0)
	assert_bool(_attributes.weapon_proficiency.is_empty()).is_true()
	assert_int(int(_attributes.attr_exp["str"])).is_equal(0)


func test_damage_award_unlocks_milestone_and_checks_skill_thresholds() -> void:
	_attributes.attrs["str"] = 15
	COMBAT_PROGRESSION.award_damage(_attributes, "sword", "melee", 20)
	assert_bool(_attributes.proficiency_milestones["sword"].has(20)).is_true()
	assert_bool(_attributes.has_skill("防御姿态")).is_true()


func test_shield_block_awards_equal_shield_and_constitution_for_physical_only() -> void:
	assert_int(COMBAT_PROGRESSION.award_shield_block(_attributes, "ranged", 13)).is_equal(13)
	assert_int(_attributes.get_proficiency("shield")).is_equal(13)
	assert_int(int(_attributes.attr_exp["con"])).is_equal(13)
	assert_int(COMBAT_PROGRESSION.award_shield_block(_attributes, "spell", 21)).is_equal(0)
	assert_int(_attributes.get_proficiency("shield")).is_equal(13)
	assert_int(int(_attributes.attr_exp["con"])).is_equal(13)


func test_enemy_progression_is_guarded_by_effective_damage_and_slashing_has_no_duplicate_award() -> void:
	var enemy_source := FileAccess.get_file_as_string("res://scenes/characters/enemies/enemy.gd")
	var hit_start := enemy_source.find("func try_receive_hit_result")
	var hit_end := enemy_source.find("\nfunc ", hit_start + 1)
	var hit_body := enemy_source.substr(hit_start, hit_end - hit_start)
	assert_bool(hit_body.find("if damage_applied:") < hit_body.find("COMBAT_PROGRESSION.award_player_damage")) \
		.override_failure_message("成长奖励必须位于敌人实际受伤判定之后").is_true()
	var slash_source := FileAccess.get_file_as_string("res://scenes/characters/player/state/player_state_slashing.gd")
	assert_bool(not slash_source.contains("_accumulate_combat_exp")) \
		.override_failure_message("近战状态不得保留第二套固定命中奖励").is_true()


func test_player_shield_growth_uses_shield_block_gate() -> void:
	var player_source := FileAccess.get_file_as_string("res://scenes/characters/player/player.gd")
	assert_str(player_source).contains("COMBAT_PROGRESSION.award_player_shield_block")
	assert_str(player_source).contains("if _is_shield_block():")


func test_runtime_award_only_writes_current_local_player_context() -> void:
	var saved_state := AttrPanel.serialize()
	var saved_player: Player = GameState.current_player
	var saved_context: Variant = GameState._player_context
	AttrPanel.reset()
	var local_player: Player = auto_free(Player.new()) as Player
	var remote_player: Player = auto_free(Player.new()) as Player
	GameState.current_player = local_player
	GameState._player_context = null
	assert_int(COMBAT_PROGRESSION.award_player_damage(remote_player, "sword", "melee", 9)).is_equal(0)
	assert_int(AttrPanel.get_proficiency("sword")).is_equal(0)
	assert_int(COMBAT_PROGRESSION.award_player_damage(local_player, "sword", "melee", 9)).is_equal(9)
	assert_int(AttrPanel.get_proficiency("sword")).is_equal(9)
	AttrPanel.deserialize(saved_state)
	GameState.current_player = saved_player
	GameState._player_context = saved_context
