extends SceneTree

## 第一人称全武器阵容真实渲染捕获。
## 覆盖：空手 + 全部 12 种武器 profile 的握持/攻击动作 + 施法动作 + 法术粒子效果。
## 运行（需要非 headless 渲染器）：
##   "D:/123/Godot_v4.7-stable_mono_win64.exe" --path "D:/123/Lantern Tavern" --script res://tools/first_person_roster_capture.gd
## 输出：reports/first_person_animation/roster_<profile>/<phase>.png

const VIEW_MODEL_SCENE: PackedScene = preload("res://scenes/characters/player/view_model.tscn")
const QUALITY := preload("res://tools/first_person_capture_quality.gd")
const PIXEL_SPELL_FX := preload("res://fx/pixel_spell_fx.gd")
const OUTPUT_ROOT := "res://reports/first_person_animation"
const VIEWPORT_SIZE := Vector2i(960, 540)

## profile → { weapon_id, weapon_class, skill_school, glb_path, hold_action, attack_action }
const ROSTER := [
	{"profile": "unarmed", "id": "", "class": "", "school": "", "glb": "", "hold": &"vm_unarmed_hold", "attack": &"vm_claw_swipe"},
	{"profile": "shortsword", "id": "shortsword", "class": "one_hand_melee", "school": "one_hand_sword", "glb": "res://assets/meshes/weapons/weapons_voxel_shortsword.glb", "hold": &"vm_shortsword_hold", "attack": &"vm_shortsword_thrust"},
	{"profile": "sword", "id": "sword", "class": "one_hand_melee", "school": "one_hand_sword", "glb": "res://assets/meshes/weapons/weapons_voxel_sword.glb", "hold": &"vm_sword_hold", "attack": &"vm_sword_slash"},
	{"profile": "dagger", "id": "dagger", "class": "one_hand_melee", "school": "dagger", "glb": "res://assets/meshes/weapons/weapons_voxel_dagger.glb", "hold": &"vm_dagger_hold", "attack": &"vm_stab_dagger"},
	{"profile": "greatsword", "id": "greatsword", "class": "two_hand", "school": "two_hand_sword", "glb": "res://assets/meshes/weapons/weapons_voxel_greatsword.glb", "hold": &"vm_greatsword_hold", "attack": &"vm_greatsword_attack"},
	{"profile": "axe", "id": "battle_axe", "class": "two_hand", "school": "two_hand_axe", "glb": "res://assets/meshes/weapons/weapons_voxel_axe.glb", "hold": &"vm_axe_hold", "attack": &"vm_axe_attack"},
	{"profile": "warhammer", "id": "warhammer", "class": "two_hand", "school": "war_hammer", "glb": "res://assets/meshes/weapons/weapons_voxel_warhammer.glb", "hold": &"vm_warhammer_hold", "attack": &"vm_warhammer_attack"},
	{"profile": "spear", "id": "spear", "class": "two_hand", "school": "spear", "glb": "res://assets/meshes/weapons/weapons_voxel_spear.glb", "hold": &"vm_spear_hold", "attack": &"vm_thrust_spear"},
	{"profile": "bow", "id": "longbow", "class": "longbow", "school": "longbow", "glb": "res://assets/meshes/weapons/weapons_voxel_longbow.glb", "hold": &"vm_bow_hold", "attack": &"vm_bow_release"},
	{"profile": "crossbow", "id": "crossbow", "class": "crossbow", "school": "light_crossbow", "glb": "res://assets/meshes/weapons/weapons_voxel_crossbow.glb", "hold": &"vm_crossbow_hold", "attack": &"vm_crossbow_fire"},
	{"profile": "staff", "id": "staff", "class": "staff", "school": "staff", "glb": "res://assets/meshes/weapons/weapons_voxel_staff.glb", "hold": &"vm_staff_hold", "attack": &"vm_staff_attack"},
	{"profile": "grimoire", "id": "grimoire", "class": "grimoire", "school": "grimoire", "glb": "res://assets/meshes/weapons/weapons_voxel_grimoire.glb", "hold": &"vm_grimoire_hold", "attack": &"vm_grimoire_attack"},
	{"profile": "shield", "id": "shield", "class": "shield", "school": "shield", "glb": "res://assets/meshes/weapons/weapons_voxel_shield.glb", "hold": &"vm_shield_hold", "attack": &"vm_bash_shield"},
]

var _viewport: SubViewport
var _view_model: ViewModel
var _failed := false
var _output_dir := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[RosterCapture] requires a non-headless renderer.")
		quit(4)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	var requested_profile := _requested_profile()
	if not requested_profile.is_empty():
		for spec in ROSTER:
			if String(spec["profile"]) == requested_profile:
				await _capture_weapon(spec)
				quit(0 if not _failed else 1)
				return
		printerr("[RosterCapture] unknown profile: %s" % requested_profile)
		quit(5)
		return

	for spec in ROSTER:
		await _capture_weapon(spec)

	# 法术粒子效果独立渲染（无武器状态，直接调用 PixelSpellFx.spawn）
	await _capture_spell_fx()

	quit(0 if not _failed else 1)


func _requested_profile() -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--profile="):
			return argument.trim_prefix("--profile=").strip_edges().to_lower()
	return ""


func _capture_weapon(spec: Dictionary) -> void:
	var profile := String(spec["profile"])
	_output_dir = "%s/roster_%s" % [OUTPUT_ROOT, profile]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	_build_capture_world()
	await process_frame
	await process_frame
	_equip_weapon(spec)
	await process_frame

	var phases := [
		{"name": "00_hold", "action": spec["hold"], "progress": 0.0, "aim": false},
		{"name": "01_attack_start", "action": spec["attack"], "progress": 0.25, "aim": false},
		{"name": "02_attack_peak", "action": spec["attack"], "progress": 0.5, "aim": false},
		{"name": "03_attack_end", "action": spec["attack"], "progress": 0.85, "aim": false},
	]
	for phase in phases:
		_view_model.sample_action(StringName(phase["action"]), float(phase["progress"]))
		_view_model.set_aiming(bool(phase["aim"]))
		await process_frame
		await process_frame
		_capture_phase(String(phase["name"]))

	_view_model.queue_free()
	_viewport.queue_free()
	print("[RosterCapture] %s done" % profile)


func _build_capture_world() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "RosterCaptureViewport"
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


func _equip_weapon(spec: Dictionary) -> void:
	if String(spec["glb"]).is_empty():
		# 空手：不挂武器，仅切 unarmed profile
		_view_model.set_weapon_profile(&"unarmed")
		_view_model.sample_action(spec["hold"], 0.0)
		return
	var weapon := WeaponData.new()
	weapon.id = String(spec["id"])
	weapon.weapon_class = String(spec["class"])
	weapon.attack_type = "ranged" if profile_is_ranged(String(spec["profile"])) else "melee"
	weapon.skill_school = String(spec["school"])
	weapon.view_model_profile = String(spec["profile"])
	weapon.material_tier = "iron"
	weapon.glb_mesh = load(String(spec["glb"])) as PackedScene
	if String(spec["profile"]) == "shield":
		# 盾牌走 ShieldSocket（副手链）：set_shield 挂盾，主手空置
		_view_model.set_weapon_profile(&"shield")
		_view_model.set_shield(weapon)
	else:
		_view_model.set_weapon(weapon)
	_view_model.set_weapon_animation_variant("standard")


func profile_is_ranged(profile: String) -> bool:
	return profile in ["bow", "crossbow", "staff", "grimoire"]


func _capture_phase(phase_name: String) -> void:
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("empty image for %s" % phase_name)
		return
	var output_path := "%s/%s.png" % [_output_dir, phase_name]
	if image.save_png(output_path) != OK:
		_fail("failed to save %s" % output_path)
		return
	var metrics := QUALITY.analyze(image)
	var issues := QUALITY.validate(metrics, 900, 170, 0.28, 12)
	if not issues.is_empty():
		for issue in issues:
			_fail("%s: %s (%s)" % [phase_name, issue, QUALITY.describe(metrics)])
		return
	print("[RosterCapture] %s/%s %s" % [
		_output_dir.get_file(), phase_name, QUALITY.describe(metrics)
	])


func _capture_spell_fx() -> void:
	_output_dir = "%s/roster_spell_fx" % OUTPUT_ROOT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	_build_capture_world()
	await process_frame
	await process_frame
	_view_model.set_weapon_profile(&"staff")
	await process_frame
	# 施法动作（staff attack = wand_cast 通道）+ 粒子
	_view_model.sample_action(&"vm_staff_attack", 0.35)
	var fx := PIXEL_SPELL_FX.spawn(
		_view_model.get_node_or_null("BobPivot/AimPivot"),
		{"imagery": "fireball", "color": Color(1.0, 0.55, 0.23), "phase": "cast"},
		Vector3(0.2, -0.05, -0.5),
		Vector3(0.0, 0.0, -1.0)
	)
	if fx != null:
		fx.set_process(false)  # 冻结在发射形态
	await process_frame
	await process_frame
	_capture_phase("cast_fireball_particles")
	_view_model.queue_free()
	_viewport.queue_free()
	print("[RosterCapture] spell fx done")


func _fail(message: String) -> void:
	_failed = true
	printerr("[RosterCapture] %s" % message)
