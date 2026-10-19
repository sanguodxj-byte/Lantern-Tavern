extends SceneTree

## 弓/弩第一人称握持与动作真实渲染捕获。
## 用途：校准弓（longbow）与弩（crossbow）的第一人称握持姿态（hold/aim）与
##       拉弓/射击/装填动作（bow_draw/bow_release/crossbow_fire/crossbow_reload）。
## 运行（需要非 headless 渲染器）：
##   "D:/123/Godot_v4.7-stable_mono_win64.exe" --path "D:/123/Lantern Tavern" --script res://tools/bow_crossbow_first_person_capture.gd
## 输出：reports/first_person_animation/{bow_standard,crossbow_standard}/{phase}.png + contact_sheet.png
## 注意：--script 模式下 autoload 可能未注册导致 view_model.gd 编译失败（裸场景）；
##       动作播放的真实验证由 tests/gdunit/first_person_bow_crossbow_verify_test.gd 承担。

const VIEW_MODEL_SCENE: PackedScene = preload("res://scenes/characters/player/view_model.tscn")
const BOW_SCENE: PackedScene = preload("res://assets/meshes/weapons/weapons_voxel_longbow.glb")
const CROSSBOW_SCENE: PackedScene = preload("res://assets/meshes/weapons/weapons_voxel_crossbow.glb")
const QUALITY := preload("res://tools/first_person_capture_quality.gd")
const OUTPUT_ROOT := "res://reports/first_person_animation"
const VIEWPORT_SIZE := Vector2i(960, 540)
const CONTACT_FRAME_SIZE := Vector2i(480, 270)

## 每个武器捕获的相位：握持（hold）与瞄准（aim）姿态优先；动作为次。
const BOW_PHASES := [
	{"name": "00_hold", "action": &"vm_bow_hold", "progress": 0.0, "aim": false},
	{"name": "01_aim", "action": &"vm_bow_aim", "progress": 0.35, "aim": true},
	{"name": "02_draw_25", "action": &"vm_bow_draw", "progress": 0.25, "aim": true},
	{"name": "03_draw_75", "action": &"vm_bow_draw", "progress": 0.75, "aim": true},
	{"name": "04_release", "action": &"vm_bow_release", "progress": 0.5, "aim": true},
]
const CROSSBOW_PHASES := [
	{"name": "00_hold", "action": &"vm_crossbow_hold", "progress": 0.0, "aim": false},
	{"name": "01_aim", "action": &"vm_crossbow_aim", "progress": 0.35, "aim": true},
	{"name": "02_fire", "action": &"vm_crossbow_fire", "progress": 0.5, "aim": true},
	{"name": "03_reload_mid", "action": &"vm_crossbow_reload", "progress": 0.45, "aim": false},
	{"name": "04_reload_end", "action": &"vm_crossbow_reload", "progress": 0.95, "aim": false},
]

var _viewport: SubViewport
var _view_model: ViewModel
var _frames: Array[Image] = []
var _failed := false
var _output_dir := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[BowCrossbowCapture] requires a non-headless renderer.")
		quit(4)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))

	var bow_ok := await _capture_weapon(
		"bow_standard", BOW_SCENE, &"bow", &"longbow", BOW_PHASES)
	var crossbow_ok := await _capture_weapon(
		"crossbow_standard", CROSSBOW_SCENE, &"crossbow", &"crossbow", CROSSBOW_PHASES)
	quit(0 if bow_ok and crossbow_ok else 1)


func _capture_weapon(
	dir_name: String,
	glb: PackedScene,
	profile: StringName,
	weapon_class: String,
	phases: Array
) -> bool:
	_output_dir = "%s/%s" % [OUTPUT_ROOT, dir_name]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	_frames.clear()
	_build_capture_world()
	await process_frame
	await process_frame
	_equip_weapon(glb, profile, weapon_class)
	await process_frame

	for phase: Dictionary in phases:
		var action_name := StringName(phase["action"])
		var progress := float(phase["progress"])
		# 统一用 sample_action 固定进度采样：hold 0.0 即真实持握姿态
		# （begin_weapon_hold 内部即 sample_action(hold, 0.0)），aim/draw/reload
		# 在作者化 .tres 各关键帧间精确取姿，避免依赖动画播放时序。
		_view_model.sample_action(action_name, progress)
		_view_model.set_aiming(bool(phase["aim"]))
		await process_frame
		await process_frame
		_capture_phase(String(phase["name"]))

	var phases_ok := not _failed and _frames.size() == phases.size()
	if phases_ok:
		_save_contact_sheet(dir_name, phases.size())
	_view_model.queue_free()
	_viewport.queue_free()
	print("[BowCrossbowCapture] %s done: %d frames" % [dir_name, _frames.size()])
	_failed = false
	return phases_ok


func _build_capture_world() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "BowCrossbowCaptureViewport"
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

func _equip_weapon(glb: PackedScene, profile: StringName, weapon_class: String) -> void:
	var weapon := WeaponData.new()
	weapon.id = "longbow" if profile == &"bow" else "crossbow"
	weapon.name_zh = "长弓" if profile == &"bow" else "轻弩"
	weapon.item_tag = "weapon"
	weapon.weapon_class = weapon_class
	weapon.attack_type = "ranged"
	weapon.skill_school = "longbow" if profile == &"bow" else "light_crossbow"
	weapon.view_model_profile = String(profile)
	weapon.material_tier = "wood"
	weapon.glb_mesh = glb
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


func _save_contact_sheet(dir_name: String, phase_count: int) -> void:
	if _frames.size() != phase_count:
		_fail("contact sheet expected %d frames, got %d" % [phase_count, _frames.size()])
		return
	var sheet := Image.create(phase_count * CONTACT_FRAME_SIZE.x, CONTACT_FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	for index in _frames.size():
		var destination := Vector2i(index * CONTACT_FRAME_SIZE.x, 0)
		var frame := _frames[index].duplicate()
		frame.convert(Image.FORMAT_RGBA8)
		frame.resize(CONTACT_FRAME_SIZE.x, CONTACT_FRAME_SIZE.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, CONTACT_FRAME_SIZE), destination)
	var output_path := "%s/contact_sheet.png" % _output_dir
	if sheet.save_png(output_path) != OK:
		_fail("failed to save %s" % output_path)


func _validate_frame(image: Image, frame_name: String) -> bool:
	var metrics := QUALITY.analyze(image)
	var issues := QUALITY.validate(metrics)
	if not issues.is_empty():
		for issue in issues:
			_fail("%s: %s (%s)" % [frame_name, issue, QUALITY.describe(metrics)])
		return false
	print("[BowCrossbowCapture] %s %s" % [frame_name, QUALITY.describe(metrics)])
	return true


func _fail(message: String) -> void:
	_failed = true
	printerr("[BowCrossbowCapture] %s" % message)
