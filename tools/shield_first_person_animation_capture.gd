extends SceneTree

## Real-3D review capture for independent off-hand shield motion beside a sword.
## Only equipment meshes are instantiated; no player scene or character rig is used.

const VIEW_MODEL_SCENE: PackedScene = preload("res://scenes/characters/player/view_model.tscn")
const SWORD_SCENE: PackedScene = preload("res://assets/meshes/weapons/weapons_voxel_sword.glb")
const SHIELD_SCENE: PackedScene = preload("res://assets/meshes/weapons/weapons_voxel_shield.glb")
const QUALITY := preload("res://tools/first_person_capture_quality.gd")
const OUTPUT_DIR := "res://reports/first_person_animation/sword_shield_standard"
const VIEWPORT_SIZE := Vector2i(960, 540)
const CONTACT_FRAME_SIZE := Vector2i(480, 270)
const CONTACT_COLUMNS := 4

var _viewport: SubViewport
var _view_model: ViewModel
var _frames: Array[Image] = []
var _failed := false
var _weapon_action_baseline := Transform3D.IDENTITY
var _weapon_socket_baseline := Transform3D.IDENTITY


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_build_capture_world()
	await process_frame
	await process_frame
	_equip_sword_and_shield()
	await process_frame
	_view_model.sample_action(&"vm_sword_hold", 0.0)
	await process_frame
	_weapon_action_baseline = _view_model.action_pivot.transform
	_weapon_socket_baseline = _view_model.weapon_socket.transform

	await _sample_phase("00_ready", &"vm_shield_block", 0.0)
	await _sample_phase("01_guard_raise", &"vm_shield_block", 0.38)
	await _sample_phase("02_guard_locked", &"vm_shield_block", 0.999)

	_view_model.play_block_impact(1.0, 0.30)
	await process_frame
	_assert_weapon_unchanged("03_block_impact")
	_capture_phase("03_block_impact")
	for _frame in 24:
		await process_frame
	_assert_weapon_unchanged("04_impact_settle")
	_capture_phase("04_impact_settle")

	_view_model.equipment_motion.clear_shield_impact()
	_view_model.shield_impact_pivot.transform = Transform3D.IDENTITY
	await _sample_phase("05_bash_windup", &"vm_bash_shield", 0.36)
	await _sample_phase("06_bash_contact", &"vm_bash_shield", 0.60)
	await _sample_phase("07_recovered", &"vm_bash_shield", 1.0)
	_save_contact_sheet()

	_view_model.stop_action(true)
	await process_frame
	if not _view_model.shield_impact_pivot.transform.is_equal_approx(Transform3D.IDENTITY):
		_fail("shield impact pivot did not reset cleanly")
	if _failed:
		quit(1)
		return
	print("[ShieldFirstPersonCapture] saved %d phases to %s" % [_frames.size(), OUTPUT_DIR])
	quit(0)


func _build_capture_world() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "ShieldFirstPersonCaptureViewport"
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
	for forbidden_name in ["PlayerVisualModel", "Skeleton3D", "BoneAttachment3D"]:
		if _view_model.find_child(forbidden_name, true, false) != null:
			_fail("forbidden character node in ViewModel: %s" % forbidden_name)


func _equip_sword_and_shield() -> void:
	var sword := WeaponData.new()
	sword.id = "sword"
	sword.name_zh = "铁制长剑"
	sword.item_tag = "weapon"
	sword.weapon_class = "one_hand_melee"
	sword.attack_type = "melee"
	sword.skill_school = "one_hand_sword"
	sword.view_model_profile = "sword"
	sword.material_tier = "iron"
	sword.glb_mesh = SWORD_SCENE
	_view_model.set_weapon(sword)
	_view_model.set_weapon_animation_variant("standard")

	var shield := WeaponData.new()
	shield.id = "shield"
	shield.name_zh = "破圆木盾"
	shield.item_tag = "shield"
	shield.weapon_class = "shield"
	shield.attack_type = "shield"
	shield.view_model_profile = "shield"
	shield.material_tier = "wood"
	shield.glb_mesh = SHIELD_SCENE
	_view_model.set_shield(shield)


func _sample_phase(phase_name: String, action: StringName, progress: float) -> void:
	_view_model.sample_action(action, progress)
	await process_frame
	await process_frame
	_assert_weapon_unchanged(phase_name)
	_capture_phase(phase_name)


func _assert_weapon_unchanged(stage: String) -> void:
	if not _view_model.action_pivot.transform.is_equal_approx(_weapon_action_baseline):
		_fail("%s moved main-hand ActionPivot" % stage)
	if not _view_model.weapon_socket.transform.is_equal_approx(_weapon_socket_baseline):
		_fail("%s moved main-hand WeaponSocket" % stage)


func _capture_phase(phase_name: String) -> void:
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("empty image for %s" % phase_name)
		return
	var output_path := "%s/%s.png" % [OUTPUT_DIR, phase_name]
	if image.save_png(output_path) != OK:
		_fail("failed to save %s" % output_path)
		return
	var metrics := QUALITY.analyze(image)
	var issues := QUALITY.validate(metrics, 4200, 230, 0.28, 8)
	if not issues.is_empty():
		for issue in issues:
			_fail("%s: %s (%s)" % [phase_name, issue, QUALITY.describe(metrics)])
		return
	print("[ShieldFirstPersonCapture] %s %s" % [phase_name, QUALITY.describe(metrics)])
	_frames.append(image)


func _save_contact_sheet() -> void:
	if _frames.size() != 8:
		_fail("contact sheet expected 8 frames, got %d" % _frames.size())
		return
	var rows := ceili(float(_frames.size()) / float(CONTACT_COLUMNS))
	var sheet := Image.create(
		CONTACT_COLUMNS * CONTACT_FRAME_SIZE.x,
		rows * CONTACT_FRAME_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	for index in _frames.size():
		var frame := _frames[index].duplicate()
		frame.convert(Image.FORMAT_RGBA8)
		frame.resize(CONTACT_FRAME_SIZE.x, CONTACT_FRAME_SIZE.y, Image.INTERPOLATE_LANCZOS)
		var destination := Vector2i(
			(index % CONTACT_COLUMNS) * CONTACT_FRAME_SIZE.x,
			(index / CONTACT_COLUMNS) * CONTACT_FRAME_SIZE.y
		)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, CONTACT_FRAME_SIZE), destination)
	var output_path := "%s/contact_sheet.png" % OUTPUT_DIR
	if sheet.save_png(output_path) != OK:
		_fail("failed to save %s" % output_path)


func _fail(message: String) -> void:
	_failed = true
	printerr("[ShieldFirstPersonCapture] %s" % message)
