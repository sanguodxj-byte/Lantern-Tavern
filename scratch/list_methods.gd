extends SceneTree

func _init() -> void:
	var s: GDScript = load("res://tests/gdunit/skill_effects_test.gd")
	print("METHODS:", s.get_script_method_list().size())
	for m in s.get_script_method_list():
		print(" - ", m.name)
	quit()
