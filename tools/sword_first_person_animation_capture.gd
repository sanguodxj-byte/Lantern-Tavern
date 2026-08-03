extends SceneTree

## Focused real-3D review capture for the iron longsword's independent ViewModel.
## This intentionally does not instantiate the third-person player character.

const VIEW_MODEL_SCENE: PackedScene = preload("res://scenes/characters/player/view_model.tscn")
const SWORD_SCENE: PackedScene = preload("res://assets/meshes/weapons/weapons_voxel_sword.glb")
const QUALITY := preload("res://tools/first_person_capture_quality.gd")
const OUTPUT_ROOT := "res://reports/first_person_animation"
const VIEWPORT_SIZE := Vector2i(960, 540)
const CONTACT_FRAME_SIZE := Vector2i(480, 270)
const TIMELINE_FRAME_COUNT := 21
const TIMELINE_COLUMNS := 7
const ACTION := &"vm_sword_slash"
const PHASES := [
	{"name": "00_hold", "progress": 0.0},
	{"name": "01_preparation", "progress": 0.075 / 0.48},
	{"name": "02_windup", "progress": 0.17 / 0.48},
	{"name": "03_strike", "progress": 0.285 / 0.48},
	{"name": "04_follow_through", "progress": 0.365 / 0.48},
	{"name": "05_recovery", "progress": 1.0},
]

var _viewport: SubViewport
var _view_model: ViewModel
var _frames: Array[Image] = []
var _timeline_frames: Array[Image] = []
var _failed := false
var _output_dir := "%s/sword_standard" % OUTPUT_ROOT


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	_build_capture_world()
	await process_frame
	await process_frame
	_equip_iron_longsword()
	await process_frame

	for phase: Dictionary in PHASES:
		_view_model.sample_action(ACTION, float(phase["progress"]))
		await process_frame
		await process_frame
		_capture_phase(String(phase["name"]))

	_save_contact_sheet()
	for frame_index in TIMELINE_FRAME_COUNT:
		var progress := float(frame_index) / float(TIMELINE_FRAME_COUNT - 1)
		_view_model.sample_action(ACTION, progress)
		await process_frame
		await process_frame
		_capture_timeline_frame(frame_index)
	_save_timeline_contact_sheet()
	if _failed:
		quit(1)
		return
	print("[SwordFirstPersonCapture] saved %d phases to %s" % [_frames.size(), _output_dir])
	quit(0)


func _build_capture_world() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "SwordFirstPersonCaptureViewport"
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


func _equip_iron_longsword() -> void:
	var weapon := WeaponData.new()
	weapon.id = "sword"
	weapon.name_zh = "铁制长剑"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "one_hand_melee"
	weapon.attack_type = "melee"
	weapon.skill_school = "one_hand_sword"
	weapon.view_model_profile = "sword"
	weapon.material_tier = "iron"
	weapon.glb_mesh = SWORD_SCENE
	_view_model.set_weapon(weapon)
	_view_model.set_weapon_animation_variant("standard")


func _capture_phase(phase_name: String) -> void:
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("empty image for %s" % phase_name)
		return
	var output_path := "%s/%s.png" % [_output_dir, phase_name]
	if image.save_png(output_path) != OK:
		_fail("failed to save %s" % output_path)
		return
	if not _validate_frame(image, phase_name):
		return
	_frames.append(image)


func _save_contact_sheet() -> void:
	if _frames.size() != PHASES.size():
		_fail("contact sheet expected %d frames, got %d" % [PHASES.size(), _frames.size()])
		return
	var sheet := Image.create(PHASES.size() * CONTACT_FRAME_SIZE.x, CONTACT_FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	for index in _frames.size():
		var destination := Vector2i(index * CONTACT_FRAME_SIZE.x, 0)
		var frame := _frames[index].duplicate()
		frame.convert(Image.FORMAT_RGBA8)
		frame.resize(CONTACT_FRAME_SIZE.x, CONTACT_FRAME_SIZE.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, CONTACT_FRAME_SIZE), destination)
	var output_path := "%s/contact_sheet.png" % _output_dir
	if sheet.save_png(output_path) != OK:
		_fail("failed to save %s" % output_path)


func _capture_timeline_frame(frame_index: int) -> void:
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("empty timeline image %02d" % frame_index)
		return
	var output_path := "%s/timeline_%02d.png" % [_output_dir, frame_index]
	if image.save_png(output_path) != OK:
		_fail("failed to save %s" % output_path)
		return
	if not _validate_frame(image, "timeline_%02d" % frame_index):
		return
	_timeline_frames.append(image)


func _save_timeline_contact_sheet() -> void:
	if _timeline_frames.size() != TIMELINE_FRAME_COUNT:
		_fail("timeline expected %d frames, got %d" % [TIMELINE_FRAME_COUNT, _timeline_frames.size()])
		return
	var rows := ceili(float(TIMELINE_FRAME_COUNT) / float(TIMELINE_COLUMNS))
	var sheet_size := Vector2i(TIMELINE_COLUMNS * CONTACT_FRAME_SIZE.x, rows * CONTACT_FRAME_SIZE.y)
	var sheet := Image.create(sheet_size.x, sheet_size.y, false, Image.FORMAT_RGBA8)
	for index in _timeline_frames.size():
		var column := index % TIMELINE_COLUMNS
		var row := index / TIMELINE_COLUMNS
		var destination := Vector2i(column * CONTACT_FRAME_SIZE.x, row * CONTACT_FRAME_SIZE.y)
		var frame := _timeline_frames[index].duplicate()
		frame.convert(Image.FORMAT_RGBA8)
		frame.resize(CONTACT_FRAME_SIZE.x, CONTACT_FRAME_SIZE.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, CONTACT_FRAME_SIZE), destination)
	var output_path := "%s/timeline_contact_sheet.png" % _output_dir
	if sheet.save_png(output_path) != OK:
		_fail("failed to save %s" % output_path)


func _validate_frame(image: Image, frame_name: String) -> bool:
	var metrics := QUALITY.analyze(image)
	var issues := QUALITY.validate(metrics)
	if not issues.is_empty():
		for issue in issues:
			_fail("%s: %s (%s)" % [frame_name, issue, QUALITY.describe(metrics)])
		return false
	print("[SwordFirstPersonCapture] %s %s" % [frame_name, QUALITY.describe(metrics)])
	return true


func _fail(message: String) -> void:
	_failed = true
	printerr("[SwordFirstPersonCapture] %s" % message)
