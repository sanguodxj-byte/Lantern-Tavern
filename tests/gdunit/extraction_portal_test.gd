extends GdUnitTestSuite

const PORTAL_SCRIPT := preload("res://scenes/expedition/extraction_portal.gd")
const CAPTURE_TOOL := "res://tools/extraction_guidance_visual_capture.gd"
const CAPTURE_SCENE := "res://tools/extraction_guidance_visual_capture.tscn"

## 信号回调统一用成员函数（GDScript lambda 捕获在 gdUnit 断言环境不可靠）。
var _starts: Array = []
var _cancelled: Array = []
var _requests: Array = []

func _on_started(p: Player, _duration: float) -> void:
	_starts.append(p)

func _on_cancelled(_p: Player, reason: String) -> void:
	_cancelled.append(reason)

func _on_requested(p: Player) -> void:
	_requests.append(p)

func _bind(portal: ExtractionPortal) -> void:
	_starts.clear()
	_cancelled.clear()
	_requests.clear()
	portal.extraction_started.connect(_on_started)
	portal.extraction_cancelled.connect(_on_cancelled)
	portal.extraction_requested.connect(_on_requested)


func test_entering_area_auto_starts_countdown() -> void:
	# 2026-08-06（用户裁定）：踏入区域即自动开始撤离倒计时（无需交互）。
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	_bind(portal)
	portal._on_body_entered(player)

	assert_int(_starts.size()).is_equal(1)
	assert_bool(portal.is_extracting()).is_true()
	portal.free()
	player.free()


func test_portal_trigger_uses_project_player_collision_contract() -> void:
	var portal := load("res://scenes/expedition/extraction_portal.tscn").instantiate() as ExtractionPortal
	add_child(portal)
	await await_idle_frame()
	var area := portal.get_node("ExtractionArea") as Area3D

	assert_object(area).is_not_null()
	assert_int(area.collision_layer).is_equal(PhysicsSetup.LAYER_TRIGGER)
	assert_int(area.collision_mask).is_equal(PhysicsSetup.LAYER_PLAYER)
	assert_bool(area.monitoring).is_true()
	portal.queue_free()


func test_auto_countdown_completes_after_duration() -> void:
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	_bind(portal)
	portal.normal_extraction_duration = 1.0
	portal.heavy_extraction_duration = 1.0
	portal._on_body_entered(player)
	portal.advance_extraction(0.4)
	portal.advance_extraction(0.4)
	assert_int(_requests.size()).is_equal(0)
	portal.advance_extraction(0.4)
	assert_int(_requests.size()).is_equal(1)
	assert_bool(portal.is_extracting()).is_false()
	portal.free()
	player.free()


func test_normal_and_heavy_loads_use_documented_durations() -> void:
	assert_float(ExtractionPortal.duration_for_load(20, 30)).is_equal(1.5)
	assert_float(ExtractionPortal.duration_for_load(21, 30)).is_equal(2.0)
	assert_float(ExtractionPortal.duration_for_load(30, 30)).is_equal(2.0)
	assert_float(ExtractionPortal.duration_for_load(0, 0)).is_equal(1.5)


func test_movement_inside_area_does_not_cancel_countdown() -> void:
	# 2026-08-06（用户裁定）：区域内可自由移动，倒计时不受影响。
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	_bind(portal)
	portal.normal_extraction_duration = 2.0
	portal.heavy_extraction_duration = 2.0
	portal._on_body_entered(player)
	# 玩家在区域内任意移动（模拟多次位移）——不重置不取消。
	# 未入树 Node3D 写 global_position 会触发 Godot 变换 ERROR，改用本地 position。
	player.position = Vector3(0.5, 0, 0.3)
	portal.advance_extraction(1.0)
	player.position = Vector3(-0.4, 0, 0.2)
	portal.advance_extraction(0.5)
	assert_bool(portal.is_extracting()).is_true()
	assert_int(_cancelled.size()).is_equal(0)
	assert_float(portal.get_extraction_progress(player)).is_equal_approx(0.75, 0.01)
	portal.free()
	player.free()


func test_hurt_does_not_cancel_countdown() -> void:
	# 2026-08-06（用户裁定）：受击不取消撤离（逃离塔科夫式：可边战斗边撤离）。
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	_bind(portal)
	portal._on_body_entered(player)
	portal._physics_process(0.5)  # 推进（等价 advance）
	# 受伤事件不再取消（旧 _on_player_hurt 逻辑已移除）
	assert_bool(portal.is_extracting()).is_true()
	assert_int(_cancelled.size()).is_equal(0)
	portal.free()
	player.free()


func test_leaving_area_resets_countdown() -> void:
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	_bind(portal)
	portal.normal_extraction_duration = 2.0
	portal.heavy_extraction_duration = 2.0
	portal._on_body_entered(player)
	portal.advance_extraction(1.0)
	assert_float(portal.get_extraction_progress(player)).is_equal_approx(0.5, 0.01)
	portal._on_body_exited(player)

	assert_bool(portal.is_extracting()).is_false()
	assert_array(_cancelled).contains(["left_area"])
	# 重新进入 → 重新计时（进度从 0 开始）
	portal._on_body_entered(player)
	assert_float(portal.get_extraction_progress(player)).is_equal_approx(0.0, 0.01)
	portal.free()
	player.free()


func test_two_players_countdown_independently() -> void:
	# 2026-08-06（per-peer）：多玩家各自倒计时互不影响。
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player_a := Player.new()
	var player_b := Player.new()
	_bind(portal)
	portal.normal_extraction_duration = 1.0
	portal.heavy_extraction_duration = 1.0
	portal._on_body_entered(player_a)
	portal._on_body_entered(player_b)
	portal.advance_extraction(1.0)  # A 完成，B 也满

	assert_int(_requests.size()).is_equal(2)
	assert_bool(portal.is_extracting()).is_false()
	portal.free()
	player_a.free()
	player_b.free()


func test_completed_guidance_emits_one_extraction_request() -> void:
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	_bind(portal)
	portal.normal_extraction_duration = 0.1
	portal.heavy_extraction_duration = 0.1
	portal._on_body_entered(player)
	portal.advance_extraction(0.1)
	portal.advance_extraction(1.0)
	# 完成后再进入不再触发（_completed 保护）
	portal._on_body_entered(player)

	assert_int(_requests.size()).is_equal(1)
	portal.free()
	player.free()


func test_interact_is_noop_and_does_not_start_or_cancel() -> void:
	# 2026-08-06（用户裁定）：不再需要交互——interact 为空实现。
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	_bind(portal)
	portal.interact(player)
	assert_bool(portal.is_extracting()).is_false()
	assert_int(_starts.size()).is_equal(0)
	assert_int(_cancelled.size()).is_equal(0)
	portal.free()
	player.free()


func test_visual_capture_uses_production_portal_and_pixel_hud() -> void:
	assert_bool(FileAccess.file_exists(CAPTURE_TOOL)).is_true()
	assert_object(load(CAPTURE_SCENE) as PackedScene).is_not_null()
	var source := (load(CAPTURE_TOOL) as GDScript).source_code
	assert_bool(source.contains("res://scenes/expedition/extraction_portal.tscn")).is_true()
	assert_bool(source.contains("res://scenes/ui/expedition_hud.tscn")).is_true()
	assert_bool(source.contains("portal._set_visual_progress(0.64)")).is_true()
	assert_bool(source.contains("hud.update_extraction_progress(0.64, 0.5)")).is_true()
	assert_bool(source.contains("make_terrain_mat(\"BARONY_FLOOR\"")) \
		.override_failure_message("真实撤离传送门截图的底面不能使用纯色占位材质").is_true()
