extends SceneTree

const VIEW_MODEL_SCENE: PackedScene = preload("res://scenes/characters/player/view_model.tscn")
const DAGGER_SCENE: PackedScene = preload("res://assets/meshes/weapons/weapons_voxel_dagger.glb")
const QUALITY := preload("res://tools/first_person_capture_quality.gd")
const OUTPUT_DIR := "res://reports/first_person_animation/dagger_standard"
const VIEWPORT_SIZE := Vector2i(960, 540)
const CONTACT_FRAME_SIZE := Vector2i(480, 270)
const TIMELINE_FRAME_COUNT := 21
const TIMELINE_COLUMNS := 7
const ACTION := &"vm_stab_dagger"
const PHASES := [
	{"name": "00_hold", "progress": 0.0},
	{"name": "01_preparation", "progress": 0.18},
	{"name": "02_acceleration", "progress": 0.36},
	{"name": "03_contact", "progress": 0.58},
	{"name": "04_follow", "progress": 0.78},
	{"name": "05_recovery", "progress": 1.0},
]

var _viewport: SubViewport
var _view_model: ViewModel
var _frames: Array[Image] = []
var _timeline_frames: Array[Image] = []
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_build_capture_world()
	await process_frame
	await process_frame
	_equip_dagger()
	await process_frame
	for phase: Dictionary in PHASES:
		_view_model.sample_action(ACTION, float(phase["progress"]))
		await process_frame
		await process_frame
		_capture_phase(String(phase["name"]))
	_save_contact_sheet()
	for frame_index in TIMELINE_FRAME_COUNT:
		_view_model.sample_action(ACTION, float(frame_index) / float(TIMELINE_FRAME_COUNT - 1))
		await process_frame
		await process_frame
		_capture_timeline_frame(frame_index)
	_save_timeline_contact_sheet()
	if _failed:
		quit(1)
		return
	print("[DaggerFirstPersonCapture] saved %d phases to %s" % [_frames.size(), OUTPUT_DIR])
	quit(0)


func _build_capture_world() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "DaggerFirstPersonCaptureViewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(_viewport)
	QUALITY.configure_review_world(_viewport)
	var camera := Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.fov = ViewModel.DEFAULT_WEAPON_CAMERA_FOV
	camera.near = 0.001
	camera.current = true
	_viewport.add_child(camera)
	_view_model = VIEW_MODEL_SCENE.instantiate() as ViewModel
	_view_model.use_weapon_camera = false
	_view_model.weapon_sway_strength = 0.0
	camera.add_child(_view_model)


func _equip_dagger() -> void:
	var weapon := WeaponData.new()
	weapon.id = "dagger"
	weapon.name_zh = "匕首"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "one_hand_melee"
	weapon.attack_type = "melee"
	weapon.skill_school = "dagger"
	weapon.view_model_profile = "dagger"
	weapon.material_tier = "iron"
	weapon.glb_mesh = DAGGER_SCENE
	_view_model.set_weapon(weapon)
	_view_model.set_weapon_animation_variant("standard")
	_view_model.view_position = Vector3(0.10, -0.06, -0.58)
	_view_model.view_rotation_degrees = Vector3(6.0, 2.0, -4.0)
	_view_model.call("_reset_base")


func _capture_phase(phase_name: String) -> void:
	var image := _viewport.get_texture().get_image()
	if not _save_and_validate(image, "%s/%s.png" % [OUTPUT_DIR, phase_name], phase_name):
		return
	_frames.append(image)


func _capture_timeline_frame(frame_index: int) -> void:
	var image := _viewport.get_texture().get_image()
	var frame_name := "timeline_%02d" % frame_index
	if not _save_and_validate(image, "%s/%s.png" % [OUTPUT_DIR, frame_name], frame_name):
		return
	_timeline_frames.append(image)


func _save_and_validate(image: Image, output_path: String, frame_name: String) -> bool:
	if image == null or image.is_empty():
		_fail("empty image for %s" % frame_name)
		return false
	if image.save_png(output_path) != OK:
		_fail("failed to save %s" % output_path)
		return false
	var metrics := QUALITY.analyze(image)
	var issues := QUALITY.validate(metrics, 900, 170, 0.28, 12)
	if not issues.is_empty():
		for issue in issues:
			_fail("%s: %s (%s)" % [frame_name, issue, QUALITY.describe(metrics)])
		return false
	print("[DaggerFirstPersonCapture] %s %s" % [frame_name, QUALITY.describe(metrics)])
	return true


func _save_contact_sheet() -> void:
	if _frames.size() != PHASES.size():
		_fail("contact sheet expected %d frames, got %d" % [PHASES.size(), _frames.size()])
		return
	_save_sheet(_frames, PHASES.size(), 1, "%s/contact_sheet.png" % OUTPUT_DIR)


func _save_timeline_contact_sheet() -> void:
	if _timeline_frames.size() != TIMELINE_FRAME_COUNT:
		_fail("timeline expected %d frames, got %d" % [TIMELINE_FRAME_COUNT, _timeline_frames.size()])
		return
	var rows := ceili(float(TIMELINE_FRAME_COUNT) / float(TIMELINE_COLUMNS))
	_save_sheet(_timeline_frames, TIMELINE_COLUMNS, rows, "%s/timeline_contact_sheet.png" % OUTPUT_DIR)


func _save_sheet(images: Array[Image], columns: int, rows: int, output_path: String) -> void:
	var sheet := Image.create(columns * CONTACT_FRAME_SIZE.x, rows * CONTACT_FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	for index in images.size():
		var frame := images[index].duplicate()
		frame.convert(Image.FORMAT_RGBA8)
		frame.resize(CONTACT_FRAME_SIZE.x, CONTACT_FRAME_SIZE.y, Image.INTERPOLATE_LANCZOS)
		var destination := Vector2i(index % columns, index / columns) * CONTACT_FRAME_SIZE
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, CONTACT_FRAME_SIZE), destination)
	if sheet.save_png(output_path) != OK:
		_fail("failed to save %s" % output_path)


func _fail(message: String) -> void:
	_failed = true
	printerr("[DaggerFirstPersonCapture] %s" % message)
