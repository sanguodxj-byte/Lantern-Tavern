class_name ViewModel
extends Node3D

## First-person presentation layer. It owns a local visual weapon/盾牌副本 and
## a separate arm skeleton. The third-person character rig remains independent
## and authoritative for gameplay animation timing and state exit.
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const VISUAL_STATE_MACHINE := preload("res://scenes/characters/player/first_person_weapon_visual_state_machine.gd")
const WEAPON_MOUNT_PROFILE := preload("res://globals/visual/weapon_mount_profile.gd")
const PLAYER_ANIMATION_PROFILE := preload("res://globals/visual/player_animation_profile.gd")
const FIRST_PERSON_ARM_ANIMATOR := preload("res://scenes/characters/player/first_person_arm_animator.gd")
## Fallback layer used when the dedicated weapon camera is unavailable
## (headless tests, or ViewModel not parented under a Camera3D). Keeping this
## as layer 1 means the MainCamera still renders the weapon in that case.
const VIEW_MODEL_RENDER_LAYER := 1
## Dedicated layer (第 11 层) rendered only by the独立武器相机。MainCamera 的
## cull_mask=1 天然排除本层，因此武器/盾牌不会被主相机重复渲染或被墙体遮挡。
const WEAPON_VIEW_RENDER_LAYER := 1 << 10
## 武器叠加层的 CanvasLayer 序号：需低于战斗 HUD(15)/UI(20)，高于 3D 世界(0)。
const WEAPON_OVERLAY_CANVAS_LAYER := 5
const MUZZLE_FORWARD_OFFSET := 0.6
## GLB weapons are authored at world-readable voxel scale.  A first-person
## socket needs a smaller presentation scale so the weapon reads as a held
## object instead of filling the whole camera.
const DEFAULT_WEAPON_VIEW_SCALE := 0.36
## Imported voxel weapon axes. A handled weapon is never corrected by turning
## only its blade. WeaponOrientation is the static whole-assembly pivot for
## asset-level corrections; the crossbow uses the canonical imported-axis map.
const WEAPON_LENGTH_AXIS := Vector3.UP
const BLADE_WIDTH_AXIS := Vector3.RIGHT
const BLADE_THICKNESS_AXIS := Vector3.BACK
const DEFAULT_VIEW_POSITION := Vector3(0.22, -0.26, -0.58)
const DEFAULT_VIEW_ROTATION := Vector3(12.0, 4.0, -4.0)
const DEFAULT_AIM_POSITION := Vector3(0.0, -0.16, -0.52)
const DEFAULT_AIM_ROTATION := Vector3(4.0, 0.0, -1.0)
const DEFAULT_SHIELD_POSITION := Vector3(-0.30, -0.22, -0.42)
const DEFAULT_SHIELD_ROTATION := Vector3(6.0, -20.0, 8.0)
const FIRST_PERSON_ARM_NODE_NAMES: Array[StringName] = [
	&"LowerArm_R", &"Hand_R", &"LowerArm_L", &"Hand_L",
	&"LowerArm.R", &"Hand.R", &"LowerArm.L", &"Hand.L",
]

@export var view_position := DEFAULT_VIEW_POSITION
@export var view_rotation_degrees := DEFAULT_VIEW_ROTATION
@export var aim_position := DEFAULT_AIM_POSITION
@export var aim_rotation_degrees := DEFAULT_AIM_ROTATION
@export_range(0.0, 1.0) var weapon_sway_strength := 1.0
## 第一人称武器动作动画开关（控制挥砍/拉弓/后坐的 ViewModel 演出）。
## 注意：武器 GLB 本身不含手臂/手部几何；第一人称使用独立复制的玩家视觉模型，
## 只显示六个手臂骨骼挂点，并由 FirstPersonArmAnimator 驱动。此开关控制第一人称
## 武器与手臂的局部视觉动作，不会写入第三人称角色骨骼或改变战斗时序。
## 默认开启：玩家能看到完整的第一人称武器动画和握持手臂。
@export var arm_animation_enabled := true
## 是否启用独立武器相机（消除贴墙穿模、允许独立 FOV）。
@export var use_weapon_camera := true
## >0 时武器相机使用该 FOV；否则每帧跟随主相机 FOV。
@export var weapon_camera_fov := 0.0
## 盾牌在第一人称视图空间中的持握位姿（相对主相机）。
@export var shield_view_position := DEFAULT_SHIELD_POSITION
@export var shield_view_rotation_degrees := DEFAULT_SHIELD_ROTATION

@onready var bob_pivot: Node3D = $BobPivot
@onready var shield_socket: Node3D = $BobPivot/ShieldSocket
@onready var aim_pivot: Node3D = $BobPivot/AimPivot
@onready var action_pivot: Node3D = $BobPivot/AimPivot/ActionPivot
@onready var weapon_socket: Node3D = $BobPivot/AimPivot/ActionPivot/WeaponSocket
@onready var weapon_orientation: Node3D = $BobPivot/AimPivot/ActionPivot/WeaponSocket/WeaponOrientation
@onready var muzzle_point: Node3D = $BobPivot/AimPivot/ActionPivot/WeaponSocket/MuzzlePoint
@onready var first_person_arms_root: Node3D = $BobPivot/AimPivot/ActionPivot/FirstPersonArms
@onready var first_person_arm_model: Node3D = $BobPivot/AimPivot/ActionPivot/FirstPersonArms/PlayerVisualModel
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animator: ViewModelAnimator = ViewModelAnimator.new()
@onready var first_person_arm_animator: RefCounted = FIRST_PERSON_ARM_ANIMATOR.new()

## Compatibility alias. It is the action layer, never a second writable holder.
var weapon_holder: Node3D:
	get: return action_pivot

var _base_transform := Transform3D.IDENTITY
var _current_weapon_node: Node3D
var _current_weapon_data: WeaponData
var _current_shield_node: Node3D
var _current_shield_data: Resource
var _aim_weight := 0.0
var _bob_time := 0.0
var _queued_action_generation := 0
## Delayed first-person clips (currently crossbow reload) use their own generation.
## Fire cleanup must not cancel a reload that was scheduled by the same shot.
var _shared_followup_generation := 0
## Explicitly models the visual-only press/hold/release/recover phases.
var visual_state_machine: RefCounted = VISUAL_STATE_MACHINE.new()
## 当前实际使用的视图渲染层（独立相机激活时为 WEAPON_VIEW_RENDER_LAYER，否则回退层）。
var _active_view_layer := VIEW_MODEL_RENDER_LAYER
var _main_camera: Camera3D
var _weapon_camera: Camera3D
var _weapon_subviewport: SubViewport
var _weapon_overlay_root: Node3D
var _weapon_overlay_node: Node3D
var _shield_overlay_node: Node3D
var _first_person_arm_skeleton: Skeleton3D

## Legacy compatibility fields. Production no longer binds ViewModel to the
## third-person AnimationPlayer; the value remains false.
var _shared_character_animation_player: AnimationPlayer
var _shared_weapon_placeholder: Node3D
var _shared_shield_placeholder: Node3D
var _shared_muzzle_source: Node3D
var _uses_shared_character_animation := false
## AnimationPlayer.current_animation is empty after a paused seek in Godot 4.7.
## Keep the sampled clip here so persistent hold/defense poses can still be
## cancelled deterministically.
var _shared_sampled_action: StringName = &""

func _ready() -> void:
	_reset_base()
	_apply_shield_pose()
	_configure_first_person_arms()
	animator.bind(action_pivot, animation_player)
	first_person_arm_animator.bind(_first_person_arm_skeleton)
	first_person_arm_animator.set_weapon_profile(&"unarmed")
	_setup_weapon_camera()
	var game_events := get_tree().root.get_node_or_null("GameEvents")
	if game_events != null and game_events.has_signal("weapon_changed"):
		game_events.weapon_changed.connect(_on_weapon_changed)
	if game_events != null and game_events.has_signal("shield_changed"):
		game_events.shield_changed.connect(_on_shield_changed)

## Deprecated compatibility hook. First-person is intentionally independent:
## the caller's third-person animation player is never adopted or stopped.
func bind_shared_character_animation(
	shared_animation_player: AnimationPlayer,
	shared_weapon_placeholder: Node3D,
	shared_shield_placeholder: Node3D = null,
	shared_muzzle_source: Node3D = null
) -> void:
	# Arguments are intentionally ignored. This method remains only for old
	# callers/tests and cannot merge the two visual channels again.
	_shared_character_animation_player = null
	_shared_weapon_placeholder = null
	_shared_shield_placeholder = null
	_shared_muzzle_source = null
	_shared_sampled_action = &""
	_uses_shared_character_animation = false

func _configure_first_person_arms() -> void:
	if first_person_arm_model == null or not is_instance_valid(first_person_arm_model):
		return
	# The imported player rig is authored around the third-person body origin.
	# Shift the duplicated arms onto the first-person weapon grip; this is a
	# ViewModel-only calibration and does not alter the gameplay skeleton.
	# Ready pose stays in the lower-right weapon presentation area. Attack
	# actions move the shared ActionPivot toward the reticle when released.
	first_person_arm_model.position = Vector3(0.10, -0.70, -0.18)
	first_person_arm_model.scale = Vector3.ONE * 0.78
	var imported_animation_player := first_person_arm_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if imported_animation_player != null:
		imported_animation_player.stop()
	_first_person_arm_skeleton = first_person_arm_model.find_child("Skeleton3D", true, false) as Skeleton3D
	# The duplicated model is a render-only arm source. Hide every imported mesh,
	# then reveal only the forearm and hand attachments on the active view layer.
	_set_render_layer_recursive(first_person_arm_model, 0)
	if _first_person_arm_skeleton == null:
		return
	for node_name in FIRST_PERSON_ARM_NODE_NAMES:
		var arm_node := _first_person_arm_skeleton.get_node_or_null(String(node_name))
		if arm_node != null:
			_set_render_layer_recursive(arm_node, _active_view_layer)

func _sync_first_person_arm_animation() -> void:
	if _first_person_arm_skeleton == null or animation_player == null:
		return
	if not animation_player.is_playing() or animation_player.current_animation.is_empty():
		return
	var length := animation_player.current_animation_length
	var progress := animation_player.current_animation_position / length if length > 0.0 else 0.0
	first_person_arm_animator.sample_action(animation_player.current_animation, progress)

func _process(delta: float) -> void:
	_bob_time += delta
	# BobPivot is exclusively owned by this script.
	var amplitude := 0.004 * weapon_sway_strength * lerpf(1.0, 0.25, _aim_weight)
	bob_pivot.position = Vector3(0.0, sin(_bob_time * 1.7) * amplitude, 0.0)
	visual_state_machine.tick(delta)
	_sync_first_person_arm_animation()
	_sync_weapon_camera()

## 构建独立武器相机：透明私有 SubViewport 经 CanvasLayer 叠加到画面之上。
## 武器/盾牌视觉副本只与自身深度测试，永不被世界墙体遮挡；headless 时回退到第 1 层。
## 主相机引用延迟到 _sync_weapon_camera 通过视口获取，故无论 ViewModel 挂在
## 哪个节点下都能工作；确认主相机存在后才把武器切到专属渲染层，避免无主相机时武器消失。
func _setup_weapon_camera() -> void:
	if not use_weapon_camera:
		return
	if DisplayServer.get_name() == "headless":
		return
	_weapon_subviewport = SubViewport.new()
	# A SubViewport does not reliably draw Node3D instances that belong to the
	# parent viewport even when both viewports share World3D. Give the overlay a
	# tiny private world and mirror only the weapon visual into it.
	_weapon_subviewport.own_world_3d = true
	_weapon_subviewport.transparent_bg = true
	_weapon_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_weapon_subviewport.handle_input_locally = false
	_weapon_subviewport.audio_listener_enable_3d = false
	var viewport_size: Vector2i = get_viewport().size
	_weapon_subviewport.size = Vector2i(maxi(viewport_size.x, 1), maxi(viewport_size.y, 1))
	_weapon_overlay_root = Node3D.new()
	_weapon_overlay_root.name = "WeaponOverlayRoot"
	_weapon_subviewport.add_child(_weapon_overlay_root)
	# Keep a fill light for any imported surface that remains light-dependent;
	# StandardMaterial3D surfaces are additionally made unshaded on the mirror.
	var weapon_fill_light := DirectionalLight3D.new()
	weapon_fill_light.name = "WeaponOverlayFillLight"
	weapon_fill_light.light_color = Color(1.0, 0.92, 0.82)
	weapon_fill_light.light_energy = 1.8
	weapon_fill_light.shadow_enabled = false
	weapon_fill_light.light_cull_mask = VIEW_MODEL_RENDER_LAYER
	weapon_fill_light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	_weapon_subviewport.add_child(weapon_fill_light)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay := CanvasLayer.new()
	overlay.name = "WeaponOverlay"
	overlay.layer = WEAPON_OVERLAY_CANVAS_LAYER
	_weapon_camera = Camera3D.new()
	_weapon_camera.cull_mask = VIEW_MODEL_RENDER_LAYER
	_weapon_camera.near = 0.001
	_weapon_camera.current = true
	container.add_child(_weapon_subviewport)
	_weapon_subviewport.add_child(_weapon_camera)
	overlay.add_child(container)
	add_child(overlay)

## 每帧把武器相机对齐到主相机（含受击抖动/唤醒 FOV 闪动），保证武器与世界一致。
func _sync_weapon_camera() -> void:
	if _weapon_camera == null:
		return
	if _main_camera == null or not is_instance_valid(_main_camera):
		_main_camera = get_viewport().get_camera_3d()
	if _main_camera == null or not is_instance_valid(_main_camera):
		return
	var viewport_size: Vector2i = get_viewport().size
	var desired_size := Vector2i(maxi(viewport_size.x, 1), maxi(viewport_size.y, 1))
	if _weapon_subviewport.size != desired_size:
		_weapon_subviewport.size = desired_size
	# 确认主相机存在后，才把武器/盾牌切到专属渲染层（仅武器相机可见）。
	if _active_view_layer != WEAPON_VIEW_RENDER_LAYER:
		_active_view_layer = WEAPON_VIEW_RENDER_LAYER
		_apply_active_view_layer_to_spawned()
	var camera_offset := WEAPON_MOUNT_PROFILE.first_person_camera_offset(
		String(resolve_weapon_profile(_current_weapon_data))
	)
	if _uses_shared_character_animation and is_instance_valid(_shared_character_animation_player):
		var shared_animation := String(_shared_character_animation_player.current_animation)
		var shared_length := _shared_character_animation_player.current_animation_length
		var shared_progress := _shared_character_animation_player.current_animation_position / shared_length if shared_length > 0.0 else 0.0
		camera_offset += WEAPON_MOUNT_PROFILE.first_person_action_camera_offset(
			String(resolve_weapon_profile(_current_weapon_data)),
			shared_animation,
			shared_progress
		)
	var camera_roll := WEAPON_MOUNT_PROFILE.first_person_camera_roll_degrees(
		String(resolve_weapon_profile(_current_weapon_data))
	)
	# The overlay camera lives in its private world. Its local origin is the
	# first-person camera; _sync_weapon_overlay() places the mirrored weapon
	# relative to the same offset and roll.
	_weapon_camera.global_transform = Transform3D.IDENTITY
	_weapon_camera.fov = weapon_camera_fov if weapon_camera_fov > 0.0 else _main_camera.fov
	_weapon_camera.near = _main_camera.near
	_weapon_camera.far = _main_camera.far
	_sync_weapon_overlay(camera_offset, camera_roll)


func _sync_weapon_overlay(camera_offset: Vector3, camera_roll: float) -> void:
	if _main_camera == null or not is_instance_valid(_main_camera):
		return
	if _weapon_overlay_root == null or not is_instance_valid(_weapon_overlay_root):
		return
	var camera_local := Transform3D(
		Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(camera_roll))),
		camera_offset
	)
	if is_instance_valid(_current_weapon_node):
		if _weapon_overlay_node == null or not is_instance_valid(_weapon_overlay_node):
			_refresh_weapon_overlay()
		if is_instance_valid(_weapon_overlay_node):
			_weapon_overlay_node.transform = _overlay_transform_for(_current_weapon_node, camera_local)
	if is_instance_valid(_current_shield_node):
		if _shield_overlay_node == null or not is_instance_valid(_shield_overlay_node):
			_refresh_shield_overlay()
		if is_instance_valid(_shield_overlay_node):
			_shield_overlay_node.transform = _overlay_transform_for(_current_shield_node, camera_local)


func _overlay_transform_for(source: Node3D, camera_local: Transform3D) -> Transform3D:
	var source_relative_to_main := _main_camera.global_transform.affine_inverse() * source.global_transform
	return camera_local.affine_inverse() * source_relative_to_main

## 当渲染层切换时，把已生成的武器/盾牌网格重新设到新层。
func _apply_active_view_layer_to_spawned() -> void:
	if is_instance_valid(_current_weapon_node):
		_set_render_layer_recursive(_current_weapon_node, _active_view_layer)
	if is_instance_valid(_current_shield_node):
		_set_render_layer_recursive(_current_shield_node, _active_view_layer)
	if is_instance_valid(first_person_arm_model) and _first_person_arm_skeleton != null:
		for node_name in FIRST_PERSON_ARM_NODE_NAMES:
			var arm_node := _first_person_arm_skeleton.get_node_or_null(String(node_name))
			if arm_node != null:
				# Keep the arm model in the main camera pass. The weapon itself is
				# mirrored into the dedicated overlay viewport below.
				_set_render_layer_recursive(arm_node, VIEW_MODEL_RENDER_LAYER)
	if _uses_shared_character_animation:
		_set_shared_equipment_render_layer()

func _set_shared_equipment_render_layer() -> void:
	if is_instance_valid(_shared_weapon_placeholder):
		_set_render_layer_recursive(_shared_weapon_placeholder, _active_view_layer)
		_apply_first_person_weapon_materials(_shared_weapon_placeholder)
	if is_instance_valid(_shared_shield_placeholder):
		_set_render_layer_recursive(_shared_shield_placeholder, _active_view_layer)

## The weapon overlay is an isolated render pass. Preserve each imported
## surface's texture/color but avoid making it dependent on a Light3D that is
## not registered in the nested SubViewport's scenario.
func _apply_first_person_weapon_materials(root: Node) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if not mesh_instance.has_meta("first_person_materials_applied"):
			var override_copy := _make_first_person_unshaded_material(mesh_instance.material_override)
			if override_copy != null:
				mesh_instance.material_override = override_copy
			if mesh_instance.mesh != null:
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					var surface_material := mesh_instance.get_surface_override_material(surface_index)
					if surface_material == null:
						surface_material = mesh_instance.mesh.surface_get_material(surface_index)
					var surface_copy := _make_first_person_unshaded_material(surface_material)
					if surface_copy != null:
						mesh_instance.set_surface_override_material(surface_index, surface_copy)
			mesh_instance.set_meta("first_person_materials_applied", true)
	for child in root.get_children():
		_apply_first_person_weapon_materials(child)


func _make_first_person_unshaded_material(source: Material) -> Material:
	if not source is BaseMaterial3D:
		return source
	var copy := (source as BaseMaterial3D).duplicate() as BaseMaterial3D
	if copy == null:
		return source
	# The weapon overlay has its own World3D and must not depend on dungeon lights.
	# BaseMaterial3D covers every imported standard-material subtype while keeping
	# the GLB texture/color maps intact.
	copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return copy

func _reset_base() -> void:
	_base_transform = Transform3D(Basis.from_euler(_degrees_to_radians(view_rotation_degrees)), view_position)
	if is_instance_valid(aim_pivot):
		aim_pivot.transform = _base_transform
	if is_instance_valid(action_pivot):
		action_pivot.transform = Transform3D.IDENTITY

func _on_weapon_changed(weapon_data: Variant) -> void:
	set_weapon(weapon_data as WeaponData)

func _on_shield_changed(shield_data: Variant) -> void:
	set_shield(shield_data as Resource)

## 第一人称盾牌视觉。shield_data 可为 ShieldData 或“盾即武器”的 WeaponData，
## 二者均暴露 glb_mesh。挂到独立的 ShieldSocket（左手侧），走同一套体素光照与视图渲染层。
func set_shield(shield_data: Resource) -> void:
	clear_shield()
	_current_shield_data = shield_data
	if shield_data == null:
		return
	if _uses_shared_character_animation:
		# Kept unreachable in production; legacy callers cannot re-enable sharing.
		_set_shared_equipment_render_layer()
		return
	if not ("glb_mesh" in shield_data):
		return
	var glb: PackedScene = shield_data.get("glb_mesh") as PackedScene
	if glb == null:
		return
	_apply_shield_pose()
	_current_shield_node = glb.instantiate() as Node3D
	if _current_shield_node == null:
		return
	shield_socket.add_child(_current_shield_node)
	VOXEL_LIGHTING.apply_weapon_tree(_current_shield_node, _material_tier_for(_current_shield_data))
	_set_render_layer_recursive(_current_shield_node, _active_view_layer)
	_refresh_shield_overlay()

func clear_shield() -> void:
	_current_shield_data = null
	if is_instance_valid(_current_shield_node):
		# 同步释放：盾牌是 ViewModel 独占的静态网格（无自身 _process），
		# 立即移除可避免切换/卸下盾牌后残留一帧旧网格。
		_current_shield_node.free()
	_current_shield_node = null
	if is_instance_valid(_shield_overlay_node):
		_shield_overlay_node.free()
	_shield_overlay_node = null

func _apply_shield_pose() -> void:
	if is_instance_valid(shield_socket):
		shield_socket.transform = Transform3D(Basis.from_euler(_degrees_to_radians(shield_view_rotation_degrees)), shield_view_position)

func set_weapon(weapon_data: WeaponData) -> void:
	clear_weapon()
	_current_weapon_data = weapon_data
	set_weapon_profile(resolve_weapon_profile(weapon_data))
	if weapon_data == null:
		return
	if _uses_shared_character_animation:
		# Kept unreachable in production; the ViewModel always owns its visual copy.
		_set_shared_equipment_render_layer()
		return
	_apply_weapon_pose_offsets(weapon_data)
	var profile := resolve_weapon_profile(weapon_data)
	_apply_weapon_mount_pose(profile)
	if weapon_data.glb_mesh == null or weapon_data.item_tag == "shield" or weapon_data.weapon_class == "shield":
		return
	_current_weapon_node = weapon_data.glb_mesh.instantiate() as Node3D
	if _current_weapon_node == null:
		return
	_current_weapon_node.scale = Vector3.ONE * _weapon_view_scale(weapon_data)
	_current_weapon_node.set_meta("visual_only", true)
	_apply_weapon_asset_orientation()
	weapon_orientation.add_child(_current_weapon_node)
	VOXEL_LIGHTING.apply_weapon_tree(_current_weapon_node, weapon_data.material_tier)
	_set_render_layer_recursive(_current_weapon_node, _active_view_layer)
	_refresh_weapon_overlay()
	play_action(&"vm_equip")

func clear_weapon() -> void:
	visual_state_machine.cancel()
	stop_action(true)
	_shared_followup_generation += 1
	_current_weapon_data = null
	set_weapon_profile(&"unarmed")
	if is_instance_valid(_current_weapon_node):
		_current_weapon_node.queue_free()
		_current_weapon_node = null
	if is_instance_valid(_weapon_overlay_node):
		_weapon_overlay_node.free()
	_weapon_overlay_node = null
	view_position = DEFAULT_VIEW_POSITION
	view_rotation_degrees = DEFAULT_VIEW_ROTATION
	aim_position = DEFAULT_AIM_POSITION
	aim_rotation_degrees = DEFAULT_AIM_ROTATION
	weapon_socket.transform = Transform3D.IDENTITY
	weapon_orientation.transform = Transform3D.IDENTITY
	_reset_base()


func _refresh_weapon_overlay() -> void:
	if _weapon_overlay_root == null or not is_instance_valid(_weapon_overlay_root):
		return
	if is_instance_valid(_weapon_overlay_node):
		_weapon_overlay_node.free()
	_weapon_overlay_node = null
	if not is_instance_valid(_current_weapon_node):
		return
	_weapon_overlay_node = _current_weapon_node.duplicate() as Node3D
	if _weapon_overlay_node == null:
		return
	_weapon_overlay_node.name = "WeaponOverlayVisual"
	_weapon_overlay_root.add_child(_weapon_overlay_node)
	_set_render_layer_recursive(_weapon_overlay_node, VIEW_MODEL_RENDER_LAYER)
	_apply_first_person_weapon_materials(_weapon_overlay_node)


func _refresh_shield_overlay() -> void:
	if _weapon_overlay_root == null or not is_instance_valid(_weapon_overlay_root):
		return
	if is_instance_valid(_shield_overlay_node):
		_shield_overlay_node.free()
	_shield_overlay_node = null
	if not is_instance_valid(_current_shield_node):
		return
	_shield_overlay_node = _current_shield_node.duplicate() as Node3D
	if _shield_overlay_node == null:
		return
	_shield_overlay_node.name = "ShieldOverlayVisual"
	_weapon_overlay_root.add_child(_shield_overlay_node)
	_set_render_layer_recursive(_shield_overlay_node, VIEW_MODEL_RENDER_LAYER)
	_apply_first_person_weapon_materials(_shield_overlay_node)

func _set_render_layer_recursive(node: Node, layer: int) -> void:
	if node is GeometryInstance3D:
		node.layers = layer
	for child in node.get_children():
		_set_render_layer_recursive(child, layer)

func _material_tier_for(data: Resource) -> String:
	if data != null and "material_tier" in data:
		return String(data.get("material_tier"))
	return ""


## 首选 weapons.json 中作者化的 first_person.view_scale（经 WeaponRegistry），
## 未配置时回落到按 profile 的默认值。
func _weapon_view_scale(weapon_data: WeaponData) -> float:
	var params := _first_person_params_for(weapon_data)
	if params.has("view_scale"):
		return float(params["view_scale"])
	return _weapon_view_scale_for(resolve_weapon_profile(weapon_data))

func _first_person_params_for(weapon_data: WeaponData) -> Dictionary:
	if weapon_data == null or String(weapon_data.id).is_empty():
		return {}
	var registry: Node = Service.weapon_registry()
	if registry == null:
		return {}
	return registry.get_first_person_params(weapon_data.id)

func _weapon_view_scale_for(profile: StringName) -> float:
	match profile:
		&"unarmed": return 0.36
		&"shortsword": return 0.42
		&"sword": return 0.22
		&"dagger": return 0.44
		&"greatsword": return 0.32
		&"axe": return 0.30
		&"warhammer": return 0.28
		&"spear": return 0.32
		&"bow": return 0.36
		&"crossbow": return 0.38
		&"staff": return 0.34
		&"grimoire": return 0.40
		&"shield": return 0.42
		_: return DEFAULT_WEAPON_VIEW_SCALE

## Fixed weapon-to-hand presentation.  ActionPivot owns the attack motion;
## WeaponSocket owns the authored first-person grip/axis correction so the
## attack rotates around a believable ready pose instead of the raw GLB axis.
func _apply_weapon_mount_pose(profile: StringName) -> void:
	var mount_position := Vector3.ZERO
	var mount_rotation := Vector3.ZERO
	# 首选 weapons.json 作者化挂载位姿（经 WeaponRegistry），未配置时回落到 profile 默认
	var params := _first_person_params_for(_current_weapon_data)
	if params.has("mount_position") and params.has("mount_rotation"):
		mount_position = _vector3_from_array(params["mount_position"])
		mount_rotation = _vector3_from_array(params["mount_rotation"])
		var authored_basis := Basis.from_euler(_degrees_to_radians(mount_rotation))
		weapon_socket.transform = Transform3D(authored_basis, mount_position)
		return
	match profile:
		&"shortsword":
			# Start lower and farther right so the center stays clear; the
			# attack drives the whole weapon forward along the view axis.
			mount_position = Vector3(0.12, 0.02, -0.02)
			mount_rotation = Vector3(-8.0, -12.0, -135.0)
		&"sword":
			# Keep the sword's diagonal ready direction. The whole-weapon
			# front/back turn is applied by WeaponOrientation below.
			mount_position = Vector3(0.08, 0.06, -0.01)
			mount_rotation = Vector3(-10.0, -8.0, -140.0)
		&"dagger":
			mount_position = Vector3(0.12, 0.04, -0.04)
			mount_rotation = Vector3(-4.0, -18.0, -118.0)
		&"greatsword":
			mount_position = Vector3(-0.02, 0.08, -0.01)
			mount_rotation = Vector3(-14.0, -8.0, -135.0)
		&"axe":
			mount_position = Vector3(-0.04, 0.07, -0.02)
			mount_rotation = Vector3(-18.0, 8.0, -120.0)
		&"warhammer":
			mount_position = Vector3(-0.05, 0.05, -0.02)
			mount_rotation = Vector3(-20.0, 12.0, -112.0)
		&"spear":
			mount_position = Vector3(0.04, 0.03, -0.01)
			mount_rotation = Vector3(-8.0, -4.0, -155.0)
		&"bow":
			mount_position = Vector3(0.16, -0.01, -0.02)
			mount_rotation = Vector3(0.0, 0.0, -90.0)
		&"crossbow":
			mount_position = Vector3(0.14, -0.02, -0.04)
			mount_rotation = Vector3(-6.0, 6.0, -90.0)
		&"staff":
			mount_position = Vector3(0.10, 0.03, -0.02)
			mount_rotation = Vector3(-12.0, -4.0, -148.0)
		&"grimoire":
			mount_position = Vector3(0.14, 0.08, -0.04)
			mount_rotation = Vector3(-2.0, -20.0, -96.0)
		&"shield":
			mount_position = Vector3(-0.28, -0.02, -0.02)
			mount_rotation = Vector3(8.0, -18.0, 10.0)
	var mount_basis := Basis.from_euler(_degrees_to_radians(mount_rotation))
	weapon_socket.transform = Transform3D(mount_basis, mount_position)


func _apply_weapon_asset_orientation() -> void:
	weapon_orientation.transform = Transform3D.IDENTITY
	if resolve_weapon_profile(_current_weapon_data) == &"crossbow":
		WEAPON_MOUNT_PROFILE.apply_asset_orientation(weapon_orientation, "crossbow")

func _apply_weapon_pose_offsets(weapon_data: WeaponData) -> void:
	var profile := resolve_weapon_profile(weapon_data)
	if profile == &"bow":
		view_position = Vector3(0.20, -0.24, -0.42)
		view_rotation_degrees = Vector3(0.0, 0.0, -6.0)
		aim_position = Vector3(0.05, -0.14, -0.38)
		aim_rotation_degrees = Vector3(0.0, 0.0, -2.0)
	elif profile == &"crossbow":
		view_position = Vector3(0.20, -0.24, -0.46)
		view_rotation_degrees = Vector3(-6.0, 6.0, 0.0)
		aim_position = Vector3(0.0, -0.16, -0.40)
		aim_rotation_degrees = Vector3(-2.0, 0.0, 0.0)
	else:
		view_position = DEFAULT_VIEW_POSITION
		view_rotation_degrees = DEFAULT_VIEW_ROTATION
		aim_position = DEFAULT_AIM_POSITION
		aim_rotation_degrees = DEFAULT_AIM_ROTATION
	_reset_base()

func resolve_weapon_profile(weapon_data: WeaponData) -> StringName:
	return PLAYER_ANIMATION_PROFILE.profile_for_weapon(weapon_data)

func resolve_melee_action(
	weapon_data: WeaponData = _current_weapon_data,
	heavy_swing: bool = false
) -> StringName:
	return PLAYER_ANIMATION_PROFILE.view_model_action(
		PLAYER_ANIMATION_PROFILE.attack_animation(weapon_data, heavy_swing)
	)

## The normalized hold pose is shared by melee and bow preparation.  A
## crossbow uses a dedicated ready-to-aim pose because it has no string-charge
## phase and must not inherit a melee swing/throw silhouette.
func resolve_hold_action(weapon_data: WeaponData = _current_weapon_data) -> StringName:
	return PLAYER_ANIMATION_PROFILE.view_model_action(
		PLAYER_ANIMATION_PROFILE.hold_animation(weapon_data)
	)


func resolve_defense_action(
	weapon_data: WeaponData = _current_weapon_data,
	has_shield: bool = false
) -> StringName:
	var defense_animation := PLAYER_ANIMATION_PROFILE.defense_animation(weapon_data, has_shield)
	if defense_animation.is_empty():
		return &""
	return PLAYER_ANIMATION_PROFILE.view_model_action(defense_animation)


func resolve_release_action(weapon_data: WeaponData = _current_weapon_data) -> StringName:
	return PLAYER_ANIMATION_PROFILE.view_model_action(
		PLAYER_ANIMATION_PROFILE.release_animation(weapon_data)
	)

func get_base_transform() -> Transform3D:
	return _base_transform

func get_muzzle_global_transform() -> Transform3D:
	if _uses_shared_character_animation:
		if is_instance_valid(_shared_muzzle_source) and not PLAYER_ANIMATION_PROFILE.uses_off_hand(_current_weapon_data):
			return _shared_muzzle_source.global_transform
		var shared_mount := _shared_shield_placeholder if PLAYER_ANIMATION_PROFILE.uses_off_hand(_current_weapon_data) else _shared_weapon_placeholder
		if is_instance_valid(shared_mount):
			return shared_mount.global_transform
	if is_instance_valid(muzzle_point):
		return muzzle_point.global_transform
	return weapon_socket.global_transform.translated_local(Vector3(0.0, 0.0, -MUZZLE_FORWARD_OFFSET))

func get_muzzle_global_position() -> Vector3:
	return get_muzzle_global_transform().origin

func set_aim_weight(weight: float) -> void:
	_aim_weight = clampf(weight, 0.0, 1.0)
	if _uses_shared_character_animation:
		# Aiming changes camera FOV only.  Moving the held weapon here would
		# create a second pose layer that diverges from the character skeleton.
		if _aim_weight > 0.5 and resolve_weapon_profile(_current_weapon_data) == &"crossbow":
			# Do not cut a fire/reload clip when the state machine restores the
			# right-button aim state.  Reload finishes in the same aim pose.
			if _shared_character_animation_player.current_animation not in [&"crossbow_fire", &"crossbow_reload"]:
				_play_shared_action(&"vm_crossbow_aim")
		return
	_base_transform = Transform3D(Basis.from_euler(_degrees_to_radians(view_rotation_degrees).lerp(_degrees_to_radians(aim_rotation_degrees), _aim_weight)), view_position.lerp(aim_position, _aim_weight))
	aim_pivot.transform = _base_transform

func set_aiming(enabled: bool) -> void:
	set_aim_weight(1.0 if enabled else 0.0)

func set_weapon_profile(profile_id: StringName) -> void:
	animator.set_weapon_profile(profile_id)
	first_person_arm_animator.set_weapon_profile(profile_id)


## Begins the local visual hold phase.  It does not start combat or alter
## damage; PlayerState still decides whether release is allowed.
func begin_weapon_hold() -> bool:
	var accepted: bool = visual_state_machine.begin_hold(resolve_weapon_profile(_current_weapon_data))
	if accepted:
		sample_action(resolve_hold_action(), 0.0)
	return accepted


## Keeps the ready pose active while the player is in the moving state.
## Moving state owns locomotion clips, but it must not replace an equipped
## weapon's grip with generic idle.  Sampling instead of replaying every frame
## also preserves the local first-person AnimationPlayer timeline.
func ensure_weapon_hold() -> bool:
	var action := resolve_hold_action(_current_weapon_data)
	if _uses_shared_character_animation:
		if _shared_character_animation_player == null or not is_instance_valid(_shared_character_animation_player):
			return false
		var shared_name := _resolve_shared_action(action)
		if not _shared_character_animation_player.has_animation(shared_name):
			return false
		if _shared_sampled_action != shared_name or _shared_character_animation_player.current_animation != shared_name:
			_sample_shared_action(action, 0.0)
		return true
	if animation_player == null or not animation_player.has_animation(action):
		return false
	if animation_player.current_animation != action or not animation_player.is_playing():
		sample_action(action, 0.0)
	return true


## Samples the held pose from 0..1 while the input remains down.
func update_weapon_hold(normalized_progress: float) -> bool:
	var accepted: bool = visual_state_machine.set_hold_progress(normalized_progress)
	if accepted:
		# sample_action(1.0) intentionally restores the action layer for a
		# completed one-shot animation. Holding is different: the final charge
		# pose must remain visible until the mouse button is released.
		sample_action(resolve_hold_action(), minf(clampf(normalized_progress, 0.0, 1.0), 0.999))
	return accepted


## Begins a persistent defense/aim pose.  The authoritative PlayerState still
## owns when the pose starts and ends; this method only selects the canonical
## per-style clip for the independent first-person visual rig.
func begin_weapon_defense(action_name: StringName = &"") -> bool:
	var action := action_name if action_name != &"" else resolve_defense_action(_current_weapon_data)
	if action == &"":
		return false
	# PlayerState passes the canonical third-person action (for example
	# "sword_guard").  The ViewModel owns a separate visual vocabulary, so
	# convert that name exactly once at this boundary.  Already-prefixed vm_*
	# calls remain compatible with older visual callers.
	if not String(action).begins_with("vm_"):
		action = PLAYER_ANIMATION_PROFILE.view_model_action(action)
	if _uses_shared_character_animation:
		_play_shared_action(action)
		return true
	if animation_player == null or not animation_player.has_animation(action):
		return false
	animator.play_action(action)
	first_person_arm_animator.play_action(action)
	return true


## Restores the shared rig to idle when a persistent defense/aim state exits.
func finish_weapon_defense(action_name: StringName = &"") -> void:
	if _uses_shared_character_animation:
		if _shared_character_animation_player == null or not is_instance_valid(_shared_character_animation_player):
			return
		var shared_name := _resolve_shared_action(action_name)
		if action_name == &"" or _shared_sampled_action == shared_name or _shared_character_animation_player.current_animation == shared_name:
			_play_shared_action(&"vm_idle")
		return
	stop_action(true)


## Marks the start of the visual release phase.  The actual attack state and
## hit window remain owned by PlayerState/CombatSlashAnimator.
func release_weapon_hold() -> bool:
	var action := resolve_release_action(_current_weapon_data)
	return visual_state_machine.begin_release(action, _action_length(action))


## Used by the authoritative attack state when it starts sampling its release
## animation. Calling it twice is safe, so the prepare/release boundary cannot
## create a second release or a visual snap.
func begin_weapon_release(action_name: StringName = &"") -> bool:
	var action := action_name if action_name != &"" else resolve_release_action(_current_weapon_data)
	if visual_state_machine.is_releasing():
		return true
	return visual_state_machine.begin_release(action, _action_length(action))


func finish_weapon_release() -> void:
	visual_state_machine.finish_release()
	stop_action(true)


func cancel_weapon_hold() -> void:
	visual_state_machine.cancel()
	if _uses_shared_character_animation:
		if _shared_character_animation_player != null and is_instance_valid(_shared_character_animation_player):
			var hold_name := _resolve_shared_action(resolve_hold_action(_current_weapon_data))
			if _shared_sampled_action == hold_name or _shared_character_animation_player.current_animation == hold_name:
				_play_shared_action(&"vm_idle")
		return
	stop_action(true)


func get_visual_weapon_state() -> int:
	return visual_state_machine.state


func get_visual_weapon_state_name() -> StringName:
	return visual_state_machine.state_name()


func _action_length(action_name: StringName) -> float:
	if _uses_shared_character_animation:
		var shared_name := _resolve_shared_action(action_name)
		if _shared_character_animation_player.has_animation(shared_name):
			return _shared_character_animation_player.get_animation(shared_name).length
		return 0.46
	if animation_player != null and animation_player.has_animation(action_name):
		return animation_player.get_animation(action_name).length
	return 0.46

func sample_action(action_name: StringName, normalized_progress: float) -> void:
	if _uses_shared_character_animation:
		_sample_shared_action(action_name, normalized_progress)
		return
	# 手臂动作动画屏蔽时武器保持静态持握位。
	if not arm_animation_enabled:
		return
	animator.sample_action(action_name, normalized_progress)
	first_person_arm_animator.sample_action(action_name, normalized_progress)

func play_action(action_name: StringName, custom_speed: float = 1.0) -> void:
	if _uses_shared_character_animation:
		_play_shared_action(action_name, custom_speed)
		return
	if not arm_animation_enabled:
		return
	_queued_action_generation += 1
	if _is_release_action(action_name):
		begin_weapon_release(action_name)
	animator.play_action(action_name, custom_speed)
	first_person_arm_animator.play_action(action_name)

## Queues a purely visual follow-up without introducing a transform-writing Tween.
func play_action_after(action_name: StringName, delay_sec: float, custom_speed: float = 1.0) -> void:
	if _uses_shared_character_animation:
		# Reload/recoil follow-ups are represented by a character clip too.  A
		# separate generation is required because finish_weapon_release() calls
		# stop_action() after firing and must not cancel this queued reload.
		if _shared_character_animation_player == null or not is_instance_valid(_shared_character_animation_player):
			return
		_shared_followup_generation += 1
		var shared_generation := _shared_followup_generation
		get_tree().create_timer(maxf(delay_sec, 0.0)).timeout.connect(func() -> void:
			if shared_generation == _shared_followup_generation and is_instance_valid(self):
				_play_shared_action(action_name, custom_speed)
		)
		return
	if not arm_animation_enabled:
		return
	_queued_action_generation += 1
	var generation := _queued_action_generation
	get_tree().create_timer(maxf(delay_sec, 0.0)).timeout.connect(func() -> void:
		if generation == _queued_action_generation and is_instance_valid(self):
			animator.play_action(action_name, custom_speed)
			first_person_arm_animator.play_action(action_name)
	)

func stop_action(reset_pose: bool = true) -> void:
	if _uses_shared_character_animation:
		# PlayerState/CombatSlashAnimator owns the shared AnimationPlayer.  A
		# ViewModel cleanup callback must never stop that animation mid-state.
		return
	_queued_action_generation += 1
	animator.stop_action(reset_pose)
	if reset_pose:
		first_person_arm_animator.reset_pose()
	if reset_pose and is_instance_valid(weapon_socket) and _current_weapon_data != null:
		# A thrust may animate the socket itself so the sword rotates around the
		# grip.  Restore the authored mount after cancellation/recovery.
		_apply_weapon_mount_pose(resolve_weapon_profile(_current_weapon_data))

func _is_release_action(action_name: StringName) -> bool:
	var action_text := String(action_name)
	var canonical := action_text.trim_prefix("vm_")
	return canonical.ends_with("_attack") or canonical.ends_with("_heavy_swing") or canonical in [
		"claw_swipe", "bash_shield", "bow_release", "crossbow_fire",
		"shortsword_thrust", "sword_slash", "slash_one_hand", "slash_heavy",
		"stab_dagger", "thrust_spear", "wand_cast",
	]

func _resolve_shared_action(action_name: StringName) -> StringName:
	match action_name:
		&"vm_idle": return &"idle"
		&"vm_equip": return &"hold_weapon"
		&"vm_shortsword_hold": return &"shortsword_hold"
		&"vm_sword_hold": return &"sword_hold"
		&"vm_bow_draw": return &"bow_hold"
		&"vm_melee_charge": return &"greatsword_hold"
		&"vm_shortsword_thrust": return &"shortsword_attack"
		&"vm_sword_slash": return &"sword_attack"
		&"vm_slash_one_hand": return &"sword_attack"
		&"vm_slash_heavy": return &"greatsword_attack"
		&"vm_stab_dagger": return &"dagger_attack"
		&"vm_thrust_spear": return &"spear_attack"
		&"vm_crossbow_aim": return &"crossbow_aim"
		&"vm_crossbow_fire": return &"crossbow_fire"
		&"vm_crossbow_reload": return &"crossbow_reload"
		&"vm_bow_release": return &"bow_release"
		&"vm_wand_cast": return &"staff_attack"
		_:
			var candidate := String(action_name)
			if candidate.begins_with("vm_"):
				return StringName(candidate.substr(3))
			return action_name

func _sample_shared_action(action_name: StringName, normalized_progress: float) -> void:
	if _shared_character_animation_player == null or not is_instance_valid(_shared_character_animation_player):
		return
	var shared_name := _resolve_shared_action(action_name)
	if not _shared_character_animation_player.has_animation(shared_name):
		push_warning("Shared character animation is unavailable: %s" % shared_name)
		return
	var animation := _shared_character_animation_player.get_animation(shared_name)
	# Sampling is called every physics frame while charging/releasing. Calling
	# play() unconditionally resets the clip to time zero and can starve the
	# animation_finished signal. The authoritative state machine starts a new
	# clip; this layer only seeks when a different action is requested.
	if _shared_sampled_action != shared_name or _shared_character_animation_player.current_animation != shared_name:
		_shared_character_animation_player.play(shared_name)
	_shared_sampled_action = shared_name
	# Release clips are authoritative gameplay animations.  Seeking their visual
	# pose must not pause AnimationPlayer, otherwise animation_finished never
	# reaches PlayerStateSlashing/PlayerStateShooting and the player locks.
	var progress := clampf(normalized_progress, 0.0, 1.0)
	if _is_release_action(action_name):
		# At the terminal sample leave the player alone so its natural end can
		# emit animation_finished. Re-seeking to 0.999 can rewind a clip that
		# has already reached its end on the same frame.
		if progress < 1.0:
			_shared_character_animation_player.seek(animation.length * minf(progress, 0.999), true)
		return
	_shared_character_animation_player.seek(animation.length * progress, true)
	if not _is_release_action(action_name):
		_shared_character_animation_player.pause()

func _play_shared_action(action_name: StringName, custom_speed: float = 1.0) -> void:
	if _shared_character_animation_player == null or not is_instance_valid(_shared_character_animation_player):
		return
	var shared_name := _resolve_shared_action(action_name)
	if not _shared_character_animation_player.has_animation(shared_name):
		push_warning("Shared character animation is unavailable: %s" % shared_name)
		return
	_shared_sampled_action = shared_name
	_shared_character_animation_player.play(shared_name, -1.0, custom_speed)

## Deprecated wrappers retained for one migration cycle.
func apply_slash_arc(progress_value: float, _side: float = 1.0) -> void:
	sample_action(resolve_melee_action(), progress_value)

func apply_melee_charge(charge_progress: float) -> void:
	sample_action(&"vm_melee_charge", charge_progress)

func apply_bow_pull(charge_progress: float) -> void:
	sample_action(&"vm_bow_draw", charge_progress)

func apply_recoil() -> void:
	play_action(PLAYER_ANIMATION_PROFILE.view_model_action(
		PLAYER_ANIMATION_PROFILE.release_animation(_current_weapon_data)
	))

func restore_transform() -> void:
	stop_action(true)

func _degrees_to_radians(value: Vector3) -> Vector3:
	return Vector3(deg_to_rad(value.x), deg_to_rad(value.y), deg_to_rad(value.z))

func _vector3_from_array(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
