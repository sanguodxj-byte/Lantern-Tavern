extends SceneTree
# Visual-effects evaluation capture.
# Runs headless, renders each effect in its own isolated SubViewport with
# deterministic lighting, and saves PNGs into res://reports/visual_eval/.
# Unlike the topdown capture scripts, this does NOT override materials — it
# shows the real StandardMaterial3D / ShaderMaterial assets in use.

const OUT_DIR := "res://reports/visual_eval"
const VPSIZE := Vector2i(1280, 800)

var _had_error := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("[VisualEval] start")

	await _shot_tavern_interior("tavern_interior_c", Vector3(3.5, 1.7, 1.0), Vector3(3.5, 1.3, -3.0))
	await _shot_tavern_interior("tavern_interior_d", Vector3(1.0, 1.7, -2.0), Vector3(5.5, 1.3, -2.5))
	await _shot_fireplace()
	await _shot_torch()
	await _shot_liquid()
	await _shot_spark()

	if _had_error:
		print("[VisualEval] finished WITH ERRORS")
		quit(1)
		return
	print("[VisualEval] done -> %s" % OUT_DIR)
	quit(0)


# ------------------------------------------------------------------ helpers

func _make_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.name = "EvalVP"
	vp.size = VPSIZE
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(vp)
	return vp


func _add_env(vp: SubViewport, ambient_energy: float) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.017, 0.022, 1.0)
	e.ambient_light_source = 1  # AMBIENT_LIGHT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	e.ambient_light_energy = ambient_energy
	e.glow_enabled = false
	env.environment = e
	vp.add_child(env)


func _add_camera(vp: SubViewport, pos: Vector3, look: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.position = pos
	vp.add_child(cam)
	cam.look_at(look, Vector3(0.0, 1.0, 0.0))
	cam.make_current()
	return cam


func _add_warm_fill(vp: SubViewport, pos: Vector3, energy: float, range_m: float) -> void:
	var omni := OmniLight3D.new()
	omni.position = pos
	omni.light_energy = energy
	omni.omni_range = range_m
	omni.light_color = Color(0.95, 0.74, 0.5)
	vp.add_child(omni)


func _add_dir(vp: SubViewport, energy: float) -> void:
	var d := DirectionalLight3D.new()
	d.light_energy = energy
	d.position = Vector3(0.0, 8.0, 3.0)
	vp.add_child(d)
	d.look_at(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0))


func _save(vp: SubViewport, name: String, wait_frames: int = 50) -> void:
	# Render a handful of frames so particles/effects tick and lights settle.
	for i in wait_frames:
		await process_frame
	var img := vp.get_texture().get_image()
	if img == null:
		printerr("[VisualEval] null image for %s" % name)
		_had_error = true
		vp.queue_free()
		return
	var colors := _color_count(img)
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	if err != OK:
		printerr("[VisualEval] save failed %s err=%d" % [path, err])
		_had_error = true
	else:
		print("[VisualEval] saved %s colors=%d" % [path, colors])
		if colors < 6:
			printerr("[VisualEval] WARN %s looks mostly blank (colors=%d)" % [name, colors])
	vp.queue_free()


func _color_count(image: Image) -> int:
	var colors := {}
	var step_x := maxi(image.get_width() / 100, 1)
	var step_y := maxi(image.get_height() / 70, 1)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var c := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]
			colors[key] = true
	return colors.size()


# -------------------------------------------------------------------- shots

func _shot_tavern_interior(name: String, cam_pos: Vector3, look: Vector3) -> void:
	var vp := _make_viewport()
	_add_env(vp, 0.22)
	_add_dir(vp, 0.45)
	# Warm "torch pool" fill lights so the interior reads warm, matching art dir.
	_add_warm_fill(vp, Vector3(3.5, 2.2, 1.0), 2.4, 7.0)
	_add_warm_fill(vp, Vector3(0.5, 2.0, -2.0), 1.8, 6.0)
	_add_warm_fill(vp, Vector3(6.5, 2.0, -2.0), 1.8, 6.0)

	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	if tavern == null:
		printerr("[VisualEval] cannot load tavern.tscn")
		_had_error = true
		vp.queue_free()
		return
	vp.add_child(tavern)
	_add_camera(vp, cam_pos, look)
	await _save(vp, name)


func _shot_fireplace() -> void:
	var vp := _make_viewport()
	_add_env(vp, 0.18)
	_add_warm_fill(vp, Vector3(0.0, 1.2, 1.0), 2.6, 6.0)
	_add_dir(vp, 0.3)

	# Isolated single-quad billboard fire (fire_flame.gdshader) on a quad.
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 1.1)
	mi.mesh = q
	mi.material_override = load("res://materials/fire_flame.tres")
	mi.position = Vector3(0.0, 0.55, 0.0)
	vp.add_child(mi)
	_add_camera(vp, Vector3(0.0, 0.6, 2.0), Vector3(0.0, 0.55, 0.0))
	await _save(vp, "fire_billboard")


func _shot_torch() -> void:
	var vp := _make_viewport()
	_add_env(vp, 0.16)
	_add_warm_fill(vp, Vector3(0.0, 1.4, 1.2), 2.6, 6.0)
	_add_dir(vp, 0.25)

	var torch := load("res://scenes/props/torch/torch.tscn").instantiate() as Node3D
	if torch == null:
		printerr("[VisualEval] cannot load torch.tscn")
		_had_error = true
		vp.queue_free()
		return
	vp.add_child(torch)
	_add_camera(vp, Vector3(0.0, 1.5, 2.2), Vector3(0.0, 1.3, -0.25))
	await _save(vp, "fire_particles")


func _shot_liquid() -> void:
	var vp := _make_viewport()
	_add_env(vp, 0.2)
	_add_dir(vp, 0.5)
	_add_warm_fill(vp, Vector3(1.5, 1.5, 1.5), 1.6, 6.0)

	# Thin cylinder so its top face normal points +Y (liquid_alchemy expects +Y).
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 0.08
	mi.mesh = cyl
	mi.material_override = load("res://materials/liquid_alchemy.tres")
	mi.position = Vector3(0.0, 0.04, 0.0)
	vp.add_child(mi)
	_add_camera(vp, Vector3(0.9, 0.9, 1.4), Vector3(0.0, 0.05, 0.0))
	await _save(vp, "liquid_alchemy")


func _shot_spark() -> void:
	var vp := _make_viewport()
	_add_env(vp, 0.16)
	_add_dir(vp, 0.4)
	_add_warm_fill(vp, Vector3(0.0, 1.0, 1.2), 1.8, 5.0)

	var spark := load("res://fx/metal_spark.tscn").instantiate() as Node3D
	if spark == null:
		printerr("[VisualEval] cannot load metal_spark.tscn")
		_had_error = true
		vp.queue_free()
		return
	vp.add_child(spark)
	# One-shot particle system: trigger emission (already starts in _ready).
	if spark is GPUParticles3D:
		(spark as GPUParticles3D).restart()
	_add_camera(vp, Vector3(0.0, 0.3, 0.8), Vector3(0.0, 0.3, 0.0))
	await _save(vp, "metal_spark", 12)
