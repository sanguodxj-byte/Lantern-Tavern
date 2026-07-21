extends GdUnitTestSuite

## Regression coverage for stale AnimationPlayer signals during combat state changes.
## The player and enemy share animation players across states. A signal emitted by
## the previous state must not transition the current state.

func test_player_slash_ignores_unrelated_animation_finished() -> void:
	var player := Player.new()
	var state := PlayerStateSlashing.new(player, PlayerStateData.new())
	player.state_node = state
	var transitions: Array = []
	state.transition_requested.connect(func(new_state, _data): transitions.append(new_state))

	state.on_animation_finished("hurt")

	assert_array(transitions).is_empty()
	state.free()
	player.free()


func test_enemy_slash_ignores_unrelated_animation_finished() -> void:
	var enemy := Enemy.new()
	var state := EnemyStateSlashing.new(enemy, EnemyStateData.new())
	enemy.state_node = state
	var transitions: Array = []
	state.transition_requested.connect(func(new_state, _data): transitions.append(new_state))

	state.on_animation_finished("hurt")

	assert_array(transitions).is_empty()
	state.free()
	enemy.free()


func test_enemy_hurt_ignores_unrelated_animation_finished() -> void:
	var enemy := Enemy.new()
	var state := EnemyStateHurt.new(enemy, EnemyStateData.new())
	enemy.state_node = state
	var transitions: Array = []
	state.transition_requested.connect(func(new_state, _data): transitions.append(new_state))

	state.on_animation_finished("slash")

	assert_array(transitions).is_empty()
	state.free()
	enemy.free()


func test_hurt_states_reject_reentrant_hits() -> void:
	var player := Player.new()
	var player_state := PlayerStateHurt.new(player, PlayerStateData.new())
	assert_bool(player_state.can_get_hurt()).is_false()
	player_state.free()
	player.free()

	var enemy := Enemy.new()
	var enemy_state := EnemyStateHurt.new(enemy, EnemyStateData.new())
	assert_bool(enemy_state.can_get_hurt()).is_false()
	enemy_state.free()
	enemy.free()


func test_state_switch_uses_a_local_node_during_enter_tree() -> void:
	for path in ["res://scenes/characters/player/player.gd", "res://scenes/characters/enemies/enemy.gd"]:
		var source := (load(path) as GDScript).source_code
		assert_bool(source.contains("var next_state_node")).is_true()
		assert_bool(source.contains("add_child(next_state_node)")).is_true()


func test_hit_entry_ignores_hurt_and_dead_actors() -> void:
	var player_source := (load("res://scenes/characters/player/player.gd") as GDScript).source_code
	var enemy_source := (load("res://scenes/characters/enemies/enemy.gd") as GDScript).source_code
	assert_bool(player_source.contains("if state == State.HURT or state == State.DYING")).is_true()
	assert_bool(enemy_source.contains("if state == State.HURT or state == State.DYING or state == State.DEAD")).is_true()
