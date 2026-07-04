extends SceneTree

func _init():
	print("--- TEXTURE LOAD TEST ---")
	var tex = load("res://assets/meshes/walls/walls-tiles_dungeon-texture.png")
	print("Loaded texture: ", tex)
	if tex == null:
		print("FAIL: Texture returned null!")
	else:
		print("PASS: Texture loaded successfully: ", tex.get_class(), " size: ", tex.get_size())
		
	var tex2 = load("res://assets/meshes/walls/ceiling-tiles_dungeon-texture.png")
	print("Loaded ceiling texture: ", tex2)
	if tex2 == null:
		print("FAIL: Ceiling texture returned null!")
	else:
		print("PASS: Ceiling texture loaded successfully: ", tex2.get_class())
	quit()
