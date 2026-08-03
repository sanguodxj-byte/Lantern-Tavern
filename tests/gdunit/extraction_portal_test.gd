extends GdUnitTestSuite

const PORTAL_SCRIPT := preload("res://scenes/expedition/extraction_portal.gd")
const CAPTURE_TOOL := "res://tools/extraction_guidance_visual_capture.gd"
const CAPTURE_SCENE := "res://tools/extraction_guidance_visual_capture.tscn"


func test_entering_portal_area_does_not_extract_automatically() -> void:
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	var requests: Array[Player] = []
	portal.extraction_requested.connect(func(requested_player: Player) -> void:
		requests.append(requested_player)
	)
	portal._on_body_entered(player)

	assert_int(requests.size()).is_equal(0)
	assert_bool(portal.is_extracting()).is_false()
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


func test_interaction_starts_timed_extraction_and_locks_movement() -> void:
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	portal.normal_extraction_duration = 1.5
	portal.heavy_extraction_duration = 1.5
	portal._on_body_entered(player)
	portal.interact(player)
	portal.advance_extraction(0.75)

	assert_bool(portal.is_extracting()).is_true()
	assert_bool(player.movement_input_enabled).is_false()
	assert_float(portal.get_extraction_progress()).is_equal_approx(0.5, 0.001)
	portal.cancel_extraction()
	assert_bool(player.movement_input_enabled).is_true()
	portal.free()
	player.free()


func test_normal_and_heavy_loads_use_documented_durations() -> void:
	assert_float(ExtractionPortal.duration_for_load(20, 30)).is_equal(1.5)
	assert_float(ExtractionPortal.duration_for_load(21, 30)).is_equal(2.0)
	assert_float(ExtractionPortal.duration_for_load(30, 30)).is_equal(2.0)
	assert_float(ExtractionPortal.duration_for_load(0, 0)).is_equal(1.5)


func test_hurt_cancels_extraction_and_restores_movement() -> void:
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	var reasons: Array[String] = []
	portal.extraction_cancelled.connect(func(_cancelled_player: Player, reason: String) -> void:
		reasons.append(reason)
	)
	portal._on_body_entered(player)
	portal.interact(player)
	portal._on_player_hurt(player)

	assert_bool(portal.is_extracting()).is_false()
	assert_bool(player.movement_input_enabled).is_true()
	assert_array(reasons).contains(["hurt"])
	portal.free()
	player.free()


func test_leaving_area_cancels_extraction() -> void:
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	var reasons: Array[String] = []
	portal.extraction_cancelled.connect(func(_cancelled_player: Player, reason: String) -> void:
		reasons.append(reason)
	)
	portal._on_body_entered(player)
	portal.interact(player)
	portal._on_body_exited(player)

	assert_bool(portal.is_extracting()).is_false()
	assert_array(reasons).contains(["left_area"])
	portal.free()
	player.free()


func test_second_interaction_cancels_active_extraction() -> void:
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	var reasons: Array[String] = []
	portal.extraction_cancelled.connect(func(_cancelled_player: Player, reason: String) -> void:
		reasons.append(reason)
	)
	portal._on_body_entered(player)
	portal.interact(player)
	portal.interact(player)

	assert_bool(portal.is_extracting()).is_false()
	assert_array(reasons).contains(["manual"])
	portal.free()
	player.free()


func test_completed_guidance_emits_one_extraction_request() -> void:
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	var requests: Array[Player] = []
	portal.normal_extraction_duration = 0.1
	portal.heavy_extraction_duration = 0.1
	portal.extraction_requested.connect(func(requested_player: Player) -> void:
		requests.append(requested_player)
	)
	portal._on_body_entered(player)
	portal.interact(player)
	portal.advance_extraction(0.1)
	portal.advance_extraction(1.0)

	assert_int(requests.size()).is_equal(1)
	assert_bool(portal.is_extracting()).is_false()
	assert_bool(player.movement_input_enabled).is_true()
	portal.free()
	player.free()


func test_interaction_outside_rune_center_is_rejected() -> void:
	var portal := PORTAL_SCRIPT.new() as ExtractionPortal
	var player := Player.new()
	var reasons: Array[String] = []
	portal.extraction_cancelled.connect(func(_cancelled_player: Player, reason: String) -> void:
		reasons.append(reason)
	)
	portal.interact(player)

	assert_bool(portal.is_extracting()).is_false()
	assert_array(reasons).contains(["not_inside"])
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
		.override_failure_message("真实撤离门截图的地面不能使用纯色占位材质").is_true()


func test_guidance_glow_preserves_voxel_shape_readability() -> void:
	var source := (load("res://scenes/expedition/extraction_portal.gd") as GDScript).source_code
	assert_bool(source.contains("emission_strength")).is_true()
	assert_bool(source.contains("PORTAL_LIGHT_IDLE + value * PORTAL_LIGHT_ACTIVE_BOOST")).is_true()

func test_portal_visuals_are_textured_and_separate_stone_from_runes() -> void:
	var portal := load("res://scenes/expedition/extraction_portal.tscn").instantiate() as ExtractionPortal
	add_child(portal)
	await await_idle_frame()
	var stone_count := 0
	var rune_count := 0
	for mesh_node in portal.find_children("*", "MeshInstance3D", true, false):
		var material := (mesh_node as MeshInstance3D).material_override as ShaderMaterial
		assert_object(material).is_not_null()
		assert_object(material.get_shader_parameter("atlas")).is_not_null()
		assert_float(material.get_shader_parameter("world_aligned_uv_enabled")).is_equal(1.0)
		if String(mesh_node.name).begins_with("Stone") or String(mesh_node.name).begins_with("PortalBase") or String(mesh_node.name).begins_with("TopBeam"):
			stone_count += 1
		else:
			rune_count += 1
	assert_int(stone_count).is_greater_equal(6)
	assert_int(rune_count).is_greater_equal(6)
	portal.queue_free()
