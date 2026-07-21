extends GdUnitTestSuite

const PREVIEW_SCENE := "res://scenes/debug/view_model_animation_preview.tscn"

func test_preview_scene_instantiates() -> void:
	var scene := load(PREVIEW_SCENE) as PackedScene
	assert_object(scene).is_not_null()
	var preview := auto_free(scene.instantiate())
	assert_object(preview.get_node_or_null("Camera3D/ViewModel")).is_not_null()
	assert_object(preview.get_node_or_null("CanvasLayer/Panel/WeaponSelector")).is_not_null()
	assert_object(preview.get_node_or_null("CanvasLayer/Panel/ActionSelector")).is_not_null()
	assert_object(preview.get_node_or_null("CanvasLayer/Panel/Progress")).is_not_null()

func test_preview_uses_registry_without_writing_assets() -> void:
	var script := load("res://scenes/debug/view_model_animation_preview.gd") as GDScript
	assert_str(script.source_code).contains("WeaponRegistry")
	assert_bool(script.source_code.contains("FileAccess.open")).is_false()
	assert_bool(script.source_code.contains("ResourceSaver.save")).is_false()

func test_view_model_animation_player_targets_only_action_layer() -> void:
	var library := load("res://scenes/characters/player/view_model_animation_library.tres") as AnimationLibrary
	for action_name in ViewModelAnimator.REQUIRED_ACTIONS:
		var animation := library.get_animation(action_name)
		for track_index in animation.get_track_count():
			assert_bool(String(animation.track_get_path(track_index)).begins_with("ActionPivot")).is_true()
