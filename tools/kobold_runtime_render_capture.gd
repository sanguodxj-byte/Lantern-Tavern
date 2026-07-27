extends SceneTree
## Real 3D capture of Kobold in the project's canonical dungeon battle scene.
## Strictly uses existing scene "res://scenes/expedition/procedural_dungeon.tscn".
## Absolutely zero new scene files created.

const DUNGEON_SCENE_PATH := "res://scenes/expedition/procedural_dungeon.tscn"
const KOBOLD_RIG_PATH := "res://assets/meshes/characters/voxel_kobold_42px_rig.glb"

var _had_error := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("reports/characters_preview")

	# Load Canonical Existing Dungeon Battle Scene
	var dungeon_scene := load(DUNGEON_SCENE_PATH) as PackedScene
	if dungeon_scene == null:
		_fail("Cannot load canonical dungeon scene.")
		quit(1)
		return

	var dungeon := dungeon_scene.instantiate() as ProceduralDungeon
	dungeon.dungeon_zone = 0
	root.add_child(dungeon)

	for i in 10:
		await process_frame

	# Instantiate Kobold character inside the dungeon scene
	var kobold_packed := load(KOBOLD_RIG_PATH) as PackedScene
	if kobold_packed == null:
		_fail("Cannot load kobold rig.")
		quit(1)
		return

	var kobold := kobold_packed.instantiate() as Node3D
	dungeon.add_child(kobold)
	kobold.position = Vector3(2.0, 0.0, 2.0)

	for i in 10:
		await process_frame

	var anim_player := kobold.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player == null:
		_fail("AnimationPlayer missing on kobold rig.")
		quit(1)
		return

	# Camera setup inside dungeon scene
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(camera)
	camera.current = true

	var views := [
		{"name": "preview", "dir": Vector3(0.65, 0.35, -1.0).normalized()},
		{"name": "side", "dir": Vector3(1.0, 0.1, 0.0).normalized()},
		{"name": "front", "dir": Vector3(0.0, 0.1, -1.0).normalized()},
	]

	var walk_anim := anim_player.get_animation("run")
	if walk_anim != null:
		var walk_phases := [
			{"name": "stride_right", "progress": 0.15},
			{"name": "stride_left", "progress": 0.75},
		]
		anim_player.play("run")
		for phase in walk_phases:
			anim_player.seek(walk_anim.length * phase["progress"], true)
			anim_player.advance(0.0)
			for f in 6:
				await process_frame

			var center := kobold.position + Vector3(0, 0.6, 0)
			camera.size = 2.2
			var dist := 3.5

			for view in views:
				camera.position = center + view["dir"] * dist
				camera.look_at(center, Vector3.UP)
				for f in 10:
					await process_frame

				var img := root.get_viewport().get_texture().get_image()
				if img != null:
					var save_path := "res://reports/characters_preview/dungeon_scene_kobold_walk_%s_%s.png" % [phase["name"], view["name"]]
					var err := img.save_png(save_path)
					if err == OK:
						print("SAVED_DUNGEON_RENDER: ", save_path)
					else:
						_fail("Failed save_png: " + save_path)

	quit(1 if _had_error else 0)


func _fail(message: String) -> void:
	_had_error = true
	push_error(message)
