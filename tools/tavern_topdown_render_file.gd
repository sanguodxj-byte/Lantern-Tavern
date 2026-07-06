extends SceneTree

const CAPTURE_SCENE := "res://tools/tavern_topdown_capture_scene.tscn"
const OUTPUT_PATH := "res://reports/tavern_step09_actual_topdown_render.png"

var _frames := 0

func _initialize() -> void:
	print("TOPDOWN_RENDER_SCRIPT_START")
	root.size = Vector2i(1600, 1100)
	var packed := load(CAPTURE_SCENE) as PackedScene
	if packed == null:
		printerr("Failed to load capture scene")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	print("TOPDOWN_RENDER_SCENE_ADDED")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 90:
		return false

	var image := root.get_texture().get_image()
	var err := image.save_png(OUTPUT_PATH)
	if err != OK:
		printerr("Failed to save topdown render: %d" % err)
		quit(1)
		return true
	print("TOPDOWN_RENDER_SAVED %s" % OUTPUT_PATH)
	quit(0)
	return true
