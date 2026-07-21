extends GdUnitTestSuite

const LIBRARY_PATH := "res://scenes/characters/player/view_model_animation_library.tres"


func test_library_contains_all_required_actions() -> void:
	var library := load(LIBRARY_PATH) as AnimationLibrary
	assert_object(library).is_not_null()
	for action_name in ViewModelAnimator.REQUIRED_ACTIONS:
		assert_bool(library.has_animation(action_name)).is_true()


func test_sample_action_clamps_progress_and_samples_requested_pose() -> void:
	var fixture := _make_animator()
	var result: String = fixture.animator.sample_action(&"vm_slash_one_hand", 4.0)
	assert_str(result).is_equal("vm_slash_one_hand")
	assert_float(fixture.player.current_animation_position).is_equal_approx(0.46, 0.001)


func test_unknown_action_falls_back_to_default_action() -> void:
	var fixture := _make_animator()
	var result: String = fixture.animator.sample_action(&"vm_unknown", 0.5)
	assert_str(result).is_equal("vm_slash_default")
	assert_float(fixture.player.current_animation_position).is_equal_approx(0.225, 0.001)


func test_stop_action_restores_only_action_pivot() -> void:
	var fixture := _make_animator()
	fixture.pivot.position = Vector3(1.0, 2.0, 3.0)
	fixture.animator.stop_action()
	assert_bool(fixture.pivot.transform.is_equal_approx(Transform3D.IDENTITY)).is_true()

func test_view_model_exposes_delayed_visual_follow_up() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("func play_action_after(")
	assert_str(script.source_code).contains("_queued_action_generation")

func test_crossbow_reload_is_queued_after_fire_feedback() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	var reload_start := source.find("func start_crossbow_reload()")
	var reload_body := source.substr(reload_start, 900)
	assert_str(reload_body).contains("play_action_after")
	assert_str(reload_body).contains("0.24")


func test_library_tracks_only_action_pivot() -> void:
	var library := load(LIBRARY_PATH) as AnimationLibrary
	var tracked_actions := 0
	for action_name in ViewModelAnimator.REQUIRED_ACTIONS:
		var animation := library.get_animation(action_name)
		if animation.get_track_count() > 0:
			tracked_actions += 1
		for track_index in animation.get_track_count():
			assert_bool(String(animation.track_get_path(track_index)).begins_with("ActionPivot")).is_true()
	assert_int(tracked_actions).is_greater_equal(2)


func _make_animator() -> Dictionary:
	var root := auto_free(Node3D.new())
	var pivot := Node3D.new()
	pivot.name = "ActionPivot"
	root.add_child(pivot)
	var player := AnimationPlayer.new()
	root.add_child(player)
	var library := load(LIBRARY_PATH) as AnimationLibrary
	return {
		"animator": ViewModelAnimator.new(pivot, player, library),
		"pivot": pivot,
		"player": player,
	}
