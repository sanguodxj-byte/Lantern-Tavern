extends SceneTree

func _initialize() -> void:
	var path := "res://assets/meshes/characters/voxel_kobold_42px_rig.glb"
	var packed := load(path) as PackedScene
	if packed == null:
		print("ERROR: Cannot load ", path)
		quit(1)
		return
	var inst := packed.instantiate()
	var anim_player: AnimationPlayer = null
	for child in inst.get_children():
		if child is AnimationPlayer:
			anim_player = child
			break
		for grand in child.get_children():
			if grand is AnimationPlayer:
				anim_player = grand
				break
	if anim_player != null:
		print("KOBOLD_ANIMATIONS: ", anim_player.get_animation_list())
	else:
		print("No AnimationPlayer found!")
	inst.free()
	quit(0)
