extends SceneTree
## Place remade brewing-material models in a dungeon-like room and capture real 3D views.
##
## Usage:
## "D:/123/Godot_v4.7-stable_mono_win64.exe" --path "D:/123/Lantern Tavern" --script res://tools/dungeon_material_visual_capture.gd
##
## Optional:
##   -- --ids=rat_tail,glowshroom,rusty_nail
##   -- --overview-only

const OUTPUT_DIR := "res://reports/dungeon_materials_preview"
const IMAGE_SIZE := Vector2i(1280, 800)
const CLOSE_SIZE := Vector2i(640, 640)
const MATERIAL_MODELS := preload("res://data/material_model_registry.gd")

const DEFAULT_IDS := [
	"rat_tail", "moldy_bread", "rusty_nail", "dungeon_moss", "bone_shard",
	"stale_water", "prison_lichen", "cellar_mushroom", "blackberry", "glowshroom",
	"moongrass", "pixie_dust", "poison_berry", "deeprock_moss", "black_rye_root",
	"stalactite_sap", "goblin_nail", "mistflower", "wolfear_herb", "cyclops_beard",
	"geothermal_ear", "luminous_fern", "quartz_dust", "blindfish_jerky",
	"skeleton_dust", "goblin_ear", "giant_rat_tail", "slime_jelly", "troll_blood",
	"soul_gem", "dragon_scale",
]

var _had_error := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ids := _parse_ids()
	var overview_only := _has_flag("--overview-only")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	print("[DungeonMaterialCapture] ids=%d overview_only=%s" % [ids.size(), overview_only])

	var overview_path := await _capture_overview(ids)
	if overview_path.is_empty():
		_fail("overview capture failed")
	else:
		print("[DungeonMaterialCapture] overview -> %s" % overview_path)

	if not overview_only:
		for mat_id in ids:
			var path := await _capture_closeup(String(mat_id))
			if path.is_empty():
				_fail("closeup failed for %s" % mat_id)
			else:
				print("[DungeonMaterialCapture] closeup %s -> %s" % [mat_id, path])

	if _had_error:
		print("[DungeonMaterialCapture] finished WITH ERRORS")
		quit(1)
		return
	print("[DungeonMaterialCapture] done -> %s" % OUTPUT_DIR)
	quit(0)


func _parse_ids() -> Array[String]:
	var args := OS.get_cmdline_user_args()
	var selected: Array[String] = []
	for arg in args:
		if String(arg).begins_with("--ids="):
			for part in String(arg).substr(6).split(",", false):
				var id := String(part).strip_edges()
				if not id.is_empty():
					selected.append(id)
	if selected.is_empty():
		for id in DEFAULT_IDS:
			selected.append(String(id))
	return selected


func _has_flag(flag: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if String(arg) == flag:
			return true
	return false


func _capture_overview(ids: Array[String]) -> String:
	var vp := _make_viewport(IMAGE_SIZE)
	var stage := _build_dungeon_room(vp, Vector3(9.5, 0.0, 7.5))
	var cols := 7
	var spacing := 0.95
	var origin := Vector3(-((mini(cols, ids.size()) - 1) * spacing) * 0.5, 0.0, -2.0)
	var index := 0
	for mat_id in ids:
		var item := _spawn_pickable_material(String(mat_id), stage)
		if item == null:
			_fail("failed to spawn %s" % mat_id)
			continue
		var row := index / cols
		var col := index % cols
		var cell := origin + Vector3(col * spacing, 0.0, row * spacing)
		# Keep models on the floor for readable overview; runtime still uses spawn_offset.
		item.position = cell
		if MATERIAL_MODELS.should_random_yaw(String(mat_id)):
			item.rotation.y = float(index) * 0.37
		index += 1

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 4.2, 5.6)
	vp.add_child(cam)
	cam.look_at(Vector3(0.0, 0.05, 0.0), Vector3.UP)
	cam.fov = 50.0
	cam.current = true
	await _settle_frames(18)
	var out_path := "%s/dungeon_materials_overview.png" % OUTPUT_DIR
	var ok := _save_viewport(vp, out_path)
	_teardown_viewport(vp)
	return out_path if ok else ""


func _capture_closeup(mat_id: String) -> String:
	var vp := _make_viewport(CLOSE_SIZE)
	var stage := _build_dungeon_room(vp, Vector3(4.0, 0.0, 4.0))
	var item := _spawn_pickable_material(mat_id, stage)
	if item == null:
		_teardown_viewport(vp)
		return ""
	# Visual rotation is already applied on the GLB root inside the holder.
	item.position = Vector3.ZERO

	var bounds := _global_bounds(item)
	var center := bounds.get_center()
	if bounds.size.length_squared() < 0.0001:
		center = item.global_position + Vector3(0, 0.15, 0)
		bounds = AABB(center - Vector3(0.12, 0.12, 0.12), Vector3(0.24, 0.24, 0.24))
	var distance := maxf(bounds.size.length() * 2.4, 0.55)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 42.0
	vp.add_child(cam)
	cam.position = center + Vector3(0.55, 0.42, 0.85).normalized() * distance
	cam.look_at(center, Vector3.UP)
	cam.current = true
	await _settle_frames(14)
	var out_path := "%s/dungeon_material_%s_closeup.png" % [OUTPUT_DIR, mat_id]
	var ok := _save_viewport(vp, out_path)
	_teardown_viewport(vp)
	return out_path if ok else ""


func _spawn_pickable_material(mat_id: String, parent: Node) -> Node3D:
	# Load the production GLB directly. Avoid PickableItem here: running this file via
	# --script can compile before PhysicsSetup autoload is available.
	var glb_path := MATERIAL_MODELS.get_model_path(mat_id)
	if glb_path.is_empty():
		glb_path = "res://assets/models/materials/materials_%s.glb" % mat_id
	if not ResourceLoader.exists(glb_path):
		_fail("missing glb for %s (%s)" % [mat_id, glb_path])
		return null
	var packed := load(glb_path) as PackedScene
	if packed == null:
		_fail("cannot load glb packed scene for %s" % mat_id)
		return null
	var visual := packed.instantiate() as Node3D
	if visual == null:
		_fail("glb instantiate failed for %s" % mat_id)
		return null
	var holder := Node3D.new()
	holder.name = "Material_%s" % mat_id
	holder.set_meta("material_id", mat_id)
	holder.set_meta("item_tag", "material")
	parent.add_child(holder)
	holder.add_child(visual)
	# Match PickableItem material path: visual rotation on the model root.
	visual.position = MATERIAL_MODELS.get_visual_offset(mat_id)
	visual.rotation_degrees = MATERIAL_MODELS.get_visual_rotation_degrees(mat_id)
	return holder


func _build_dungeon_room(vp: SubViewport, room_size: Vector3) -> Node3D:
	_add_environment(vp)
	var stage := Node3D.new()
	stage.name = "DungeonMaterialStage"
	vp.add_child(stage)

	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(room_size.x, 0.12, room_size.z)
	floor_mesh.mesh = floor_box
	floor_mesh.position = Vector3(0.0, -0.06, 0.0)
	floor_mesh.material_override = _stone_mat(Color(0.22, 0.21, 0.19))
	stage.add_child(floor_mesh)

	# Four low walls for dungeon context / occlusion read.
	for wall_def in [
		{"pos": Vector3(0.0, 0.7, -room_size.z * 0.5), "size": Vector3(room_size.x, 1.4, 0.18)},
		{"pos": Vector3(0.0, 0.7, room_size.z * 0.5), "size": Vector3(room_size.x, 1.4, 0.18)},
		{"pos": Vector3(-room_size.x * 0.5, 0.7, 0.0), "size": Vector3(0.18, 1.4, room_size.z)},
		{"pos": Vector3(room_size.x * 0.5, 0.7, 0.0), "size": Vector3(0.18, 1.4, room_size.z)},
	]:
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = wall_def["size"]
		wall.mesh = box
		wall.position = wall_def["pos"]
		wall.material_override = _stone_mat(Color(0.16, 0.155, 0.145))
		stage.add_child(wall)

	# Torch-like warm key light + cool fill, matching dungeon mood.
	var key := OmniLight3D.new()
	key.light_color = Color(1.0, 0.72, 0.38)
	key.light_energy = 6.0
	key.omni_range = 14.0
	key.shadow_enabled = false
	key.position = Vector3(-2.4, 2.2, 2.0)
	stage.add_child(key)

	var fill := OmniLight3D.new()
	fill.light_color = Color(0.55, 0.68, 0.85)
	fill.light_energy = 2.4
	fill.omni_range = 16.0
	fill.position = Vector3(3.2, 2.8, -2.5)
	stage.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.75, 0.8, 0.9)
	rim.light_energy = 0.55
	rim.rotation_degrees = Vector3(-42, 35, 0)
	stage.add_child(rim)
	return stage


func _stone_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	mat.metallic = 0.0
	return mat


func _make_viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	return vp


func _add_environment(vp: SubViewport) -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.022, 0.028)
	env.ambient_light_source = 1
	env.ambient_light_color = Color(0.34, 0.36, 0.40)
	env.ambient_light_energy = 0.75
	world_env.environment = env
	vp.add_child(world_env)


func _settle_frames(count: int) -> void:
	for _i in count:
		await process_frame
	RenderingServer.force_draw()


func _save_viewport(vp: SubViewport, res_path: String) -> bool:
	var tex := vp.get_texture()
	if tex == null:
		_fail("viewport texture null for %s" % res_path)
		return false
	var img := tex.get_image()
	if img == null:
		var rid := tex.get_rid()
		if rid.is_valid():
			img = RenderingServer.texture_2d_get(rid)
	if img == null:
		_fail("viewport image null for %s" % res_path)
		return false
	# Reject mostly-black captures.
	var lit := 0
	var step_x := maxi(1, img.get_width() / 32)
	var step_y := maxi(1, img.get_height() / 32)
	for y in range(0, img.get_height(), step_y):
		for x in range(0, img.get_width(), step_x):
			var c := img.get_pixel(x, y)
			if c.a > 0.05 and (c.r + c.g + c.b) > 0.12:
				lit += 1
	if lit < 20:
		_fail("capture mostly blank: %s lit=%d" % [res_path, lit])
		return false
	var err := img.save_png(res_path)
	if err != OK:
		_fail("save_png failed (%d): %s" % [err, res_path])
		return false
	return true


func _teardown_viewport(vp: SubViewport) -> void:
	if vp != null:
		vp.queue_free()


func _global_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var has := false
	if node is VisualInstance3D:
		bounds = (node as VisualInstance3D).global_transform * (node as VisualInstance3D).get_aabb()
		has = true
	for child in node.get_children():
		var child_bounds := _global_bounds(child)
		if child_bounds.size.length_squared() <= 0.0:
			continue
		if has:
			bounds = bounds.merge(child_bounds)
		else:
			bounds = child_bounds
			has = true
	return bounds if has else AABB()


func _fail(message: String) -> void:
	_had_error = true
	push_error("[DungeonMaterialCapture] %s" % message)
