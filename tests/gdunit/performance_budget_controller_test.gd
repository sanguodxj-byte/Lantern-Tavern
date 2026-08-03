extends GdUnitTestSuite

const CONTROLLER_SCRIPT := preload("res://globals/perf/performance_budget_controller.gd")

func test_degrades_only_after_required_slow_windows() -> void:
	var controller := CONTROLLER_SCRIPT.new()
	add_child(controller)
	controller.set_process(false)
	controller._tier_hold_elapsed = controller.MIN_TIER_HOLD_SECONDS
	_submit_window(controller, controller.DEGRADE_FRAME_MS + 1.0)
	assert_int(controller.quality_tier).is_equal(controller.QualityTier.FULL)
	_submit_window(controller, controller.DEGRADE_FRAME_MS + 1.0)
	assert_int(controller.quality_tier).is_equal(controller.QualityTier.BALANCED)
	controller.queue_free()

func test_quality_hold_prevents_immediate_cascade_degrade() -> void:
	var controller := CONTROLLER_SCRIPT.new()
	add_child(controller)
	controller.set_process(false)
	controller._tier_hold_elapsed = controller.MIN_TIER_HOLD_SECONDS
	_submit_window(controller, controller.EMERGENCY_FRAME_MS + 1.0)
	assert_int(controller.quality_tier).is_equal(controller.QualityTier.BALANCED)
	_submit_window(controller, controller.EMERGENCY_FRAME_MS + 1.0)
	assert_int(controller.quality_tier).is_equal(controller.QualityTier.BALANCED)
	controller.queue_free()

func test_recovery_requires_long_stable_fast_period() -> void:
	var controller := CONTROLLER_SCRIPT.new()
	add_child(controller)
	controller.set_process(false)
	controller.force_quality_tier(controller.QualityTier.PERFORMANCE)
	controller._tier_hold_elapsed = controller.MIN_TIER_HOLD_SECONDS
	for _i in range(controller.RECOVER_WINDOWS_REQUIRED - 1):
		_submit_window(controller, controller.RECOVER_FRAME_MS - 1.0)
	assert_int(controller.quality_tier).is_equal(controller.QualityTier.PERFORMANCE)
	_submit_window(controller, controller.RECOVER_FRAME_MS - 1.0)
	assert_int(controller.quality_tier).is_equal(controller.QualityTier.BALANCED)
	controller.queue_free()

func test_emergency_tier_never_changes_gameplay_or_network_rates() -> void:
	var script := load("res://globals/perf/performance_budget_controller.gd") as GDScript
	var source: String = script.source_code
	assert_bool(source.contains("scaling_3d_scale")).is_true()
	assert_bool(not source.contains("enemy_count")).is_true()
	assert_bool(not source.contains("physics_ticks_per_second")).is_true()
	assert_bool(not source.contains("SNAPSHOT_BROADCAST_HZ")).is_true()
	assert_bool(not source.contains("damage")).is_true()

func _submit_window(controller: Node, frame_ms: float) -> void:
	for _i in range(controller.WINDOW_SIZE):
		controller.submit_frame_time_ms(frame_ms)
