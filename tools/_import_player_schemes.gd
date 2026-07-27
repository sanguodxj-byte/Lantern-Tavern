extends SceneTree
func _initialize():
	call_deferred("_run")
func _run():
	for id in ["player_scheme_a","player_scheme_b","player_scheme_c","player_scheme_d","player_scheme_e"]:
		var path = "res://assets/meshes/characters/voxel_%s.glb" % id
		var res = load(path)
		print("load ", path, " -> ", res)
	quit(0)
