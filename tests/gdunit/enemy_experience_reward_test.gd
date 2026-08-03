extends GdUnitTestSuite

const ATTR_PANEL_SCRIPT := preload("res://globals/combat/attr_panel.gd")

var _saved_attr_state: Dictionary
var _saved_player: Player


func before() -> void:
	_saved_attr_state = AttrPanel.serialize()
	_saved_player = GameState.current_player
	AttrPanel.reset()
	GameState.current_player = null
	GameState._player_context = null


func after() -> void:
	AttrPanel.deserialize(_saved_attr_state)
	GameState.current_player = _saved_player
	GameState._player_context = null


func test_default_experience_reward_scales_from_final_max_life() -> void:
	var enemy := Enemy.new()
	enemy.health = HealthComponent.new()
	enemy.health.max_life = 12
	assert_int(enemy.get_experience_reward()).is_equal(24)
	enemy.health.free()
	enemy.free()


func test_elite_and_boss_experience_multipliers_are_exclusive() -> void:
	var enemy := Enemy.new()
	enemy.health = HealthComponent.new()
	enemy.health.max_life = 20
	enemy.is_elite = true
	assert_int(enemy.get_experience_reward()).is_equal(60)
	enemy.is_boss_type = true
	assert_int(enemy.get_experience_reward()).is_equal(120)
	enemy.health.free()
	enemy.free()


func test_explicit_experience_reward_overrides_health_formula() -> void:
	var enemy := Enemy.new()
	enemy.health = HealthComponent.new()
	enemy.health.max_life = 999
	enemy.experience_reward = 77
	assert_int(enemy.get_experience_reward()).is_equal(77)
	enemy.health.free()
	enemy.free()


func test_kill_credit_is_separate_from_ai_target() -> void:
	var enemy := Enemy.new()
	var target := Player.new()
	var killer := Player.new()
	enemy.player = target
	enemy.register_kill_credit(killer)
	assert_object(enemy.player).is_same(target)
	assert_object(enemy.kill_credit_player).is_same(killer)
	killer.free()
	target.free()
	enemy.free()


func test_blocked_hit_does_not_replace_last_effective_damage_source() -> void:
	var enemy := Enemy.new()
	var effective_killer := Player.new()
	var blocked_attacker := Player.new()
	enemy.register_kill_credit(effective_killer)
	enemy.register_kill_credit(blocked_attacker, false)
	assert_object(enemy.kill_credit_player).is_same(effective_killer)
	blocked_attacker.free()
	effective_killer.free()
	enemy.free()


func test_award_kill_experience_is_idempotent_for_current_player() -> void:
	var enemy := Enemy.new()
	enemy.health = HealthComponent.new()
	enemy.health.max_life = 10
	var killer := Player.new()
	GameState.current_player = killer
	GameState._player_context = null
	enemy.register_kill_credit(killer)
	assert_int(enemy.award_kill_experience()).is_equal(20)
	assert_int(AttrPanel.level_exp).is_equal(20)
	assert_int(enemy.award_kill_experience()).is_equal(0)
	assert_int(AttrPanel.level_exp).is_equal(20)
	killer.free()
	enemy.health.free()
	enemy.free()


func test_dying_state_awards_experience_inside_once_only_death_effects() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/characters/enemies/state/enemy_state_dying.gd")
	assert_str(source).contains("_death_effects_started = true")
	assert_str(source).contains("enemy.award_kill_experience()")
	assert_bool(source.find("_death_effects_started = true") < source.find("enemy.award_kill_experience()")) \
		.override_failure_message("经验结算必须位于死亡副作用的一次性守卫之后").is_true()

func test_request_death_awards_current_player_before_deferred_death_effects() -> void:
	var stage := Node3D.new()
	add_child(stage)
	var layout := DungeonLayout.new()
	layout.width = 8
	layout.height = 8
	layout.tile_size = 3.0
	for _y in range(layout.height):
		var row: Array = []
		for _x in range(layout.width):
			row.append(1)
		layout.grid.append(row)
	var streaming := DungeonStreamingController.new()
	stage.add_child(streaming)
	streaming.configure(layout, DungeonBuildResult.new())
	var enemy_scene := load("res://scenes/characters/enemies/slime.tscn") as PackedScene
	var enemy := enemy_scene.instantiate() as Enemy
	stage.add_child(enemy)
	var killer := Player.new()
	killer.position = Vector3.ZERO
	GameState.current_player = killer
	GameState._player_context = null
	streaming.register_physics_node(enemy)
	streaming.set_player(killer)
	assert_bool(bool(enemy.get_meta("stream_physics_active", false))) \
		.override_failure_message("玩家所在 chunk 内的敌人物理必须保持激活").is_true()
	enemy.health.max_life = 10
	enemy.register_kill_credit(killer)
	var before := AttrPanel.level_exp
	enemy.request_death(EnemyStateData.new(), true)
	assert_int(AttrPanel.level_exp - before).is_equal(20)
	await get_tree().process_frame
	assert_int(AttrPanel.level_exp - before).is_equal(20)
	await get_tree().process_frame
	assert_int(AttrPanel.level_exp - before).is_equal(20)
	GameState.current_player = null
	streaming.clear()
	streaming.queue_free()
	killer.free()
	stage.queue_free()
