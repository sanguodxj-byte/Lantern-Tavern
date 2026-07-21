extends GdUnitTestSuite

const FSM := preload("res://scenes/characters/player/first_person_weapon_visual_state_machine.gd")


func test_hold_release_recovery_sequence_is_explicit() -> void:
	var machine = FSM.new()

	assert_int(machine.state).is_equal(FSM.State.IDLE)
	assert_bool(machine.begin_hold(&"one_hand")).is_true()
	assert_int(machine.state).is_equal(FSM.State.HOLDING)
	assert_bool(machine.set_hold_progress(0.75)).is_true()
	assert_float(machine.hold_ratio).is_equal_approx(0.75, 0.001)
	assert_bool(machine.begin_release(&"vm_slash_one_hand", 0.46)).is_true()
	assert_int(machine.state).is_equal(FSM.State.RELEASING)
	assert_float(machine.charge_ratio_at_release).is_equal_approx(0.75, 0.001)
	assert_bool(machine.finish_release()).is_true()
	assert_int(machine.state).is_equal(FSM.State.RECOVERING)
	machine.tick(FSM.RECOVERY_DURATION_SEC)
	assert_int(machine.state).is_equal(FSM.State.IDLE)


func test_hold_progress_and_release_progress_are_clamped() -> void:
	var machine = FSM.new()
	machine.begin_hold(&"one_hand")
	machine.set_hold_progress(3.0)
	assert_float(machine.hold_ratio).is_equal(1.0)
	machine.begin_release(&"vm_slash_one_hand", 0.46)
	machine.set_release_progress(-2.0)
	assert_float(machine.release_progress).is_equal(0.0)
	machine.set_release_progress(2.0)
	assert_float(machine.release_progress).is_equal(1.0)


func test_release_is_visual_only_and_does_not_accept_a_second_release() -> void:
	var machine = FSM.new()
	machine.begin_hold(&"one_hand")
	assert_bool(machine.begin_release(&"vm_slash_one_hand", 0.46)).is_true()
	assert_bool(machine.begin_release(&"vm_slash_heavy", 0.78)).is_true()
	assert_str(String(machine.release_action)).is_equal("vm_slash_one_hand")
	assert_bool(machine.begin_hold(&"one_hand")).is_false()


func test_cancel_returns_to_idle_without_attack_side_effects() -> void:
	var machine = FSM.new()
	machine.begin_hold(&"one_hand")
	machine.set_hold_progress(1.0)
	machine.cancel()
	assert_int(machine.state).is_equal(FSM.State.IDLE)
	assert_float(machine.hold_ratio).is_equal(0.0)
	assert_float(machine.release_progress).is_equal(0.0)


func test_view_model_exposes_visual_hold_release_api() -> void:
	var script := load("res://scenes/characters/player/view_model.gd") as GDScript
	assert_str(script.source_code).contains("begin_weapon_hold")
	assert_str(script.source_code).contains("update_weapon_hold")
	assert_str(script.source_code).contains("release_weapon_hold")
	assert_str(script.source_code).contains("finish_weapon_release")
	assert_str(script.source_code).contains("visual_state_machine")


func test_attack_state_forwards_hold_and_release_without_owning_visual_timing() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/characters/player/state/player_state_attack_preparing.gd")
	assert_str(source).contains("begin_weapon_hold")
	assert_str(source).contains("update_weapon_hold")
	assert_str(source).contains("release_weapon_hold")
	assert_str(source).contains("transition_state(release_state, state_data)")


func test_slashing_state_still_samples_combat_authoritative_progress() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/characters/player/state/player_state_slashing.gd")
	assert_str(source).contains("begin_weapon_release")
	assert_str(source).contains("sample_action")
	assert_str(source).contains("CombatSlashAnimator")
	assert_str(source).contains("is_player_hit_active")
