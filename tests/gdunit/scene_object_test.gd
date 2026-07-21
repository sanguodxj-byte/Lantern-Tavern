extends GdUnitTestSuite

const SceneObjectScript := preload("res://scenes/props/scene_object.gd")

func test_scene_object_has_interaction_and_hit_entrypoints() -> void:
	var obj = SceneObjectScript.new()
	assert_bool(obj.has_method("interact")).is_true()
	assert_bool(obj.has_method("try_receive_hit")).is_true()
	assert_bool(obj.has_method("try_receive_furniture_impact")).is_true()
	obj.free()


func test_interact_marks_and_destroys_scene_object() -> void:
	var obj = SceneObjectScript.new()
	obj.interact()
	assert_bool(obj.was_interacted).is_true()
	assert_bool(obj.is_destroyed).is_true()
	obj.free()
