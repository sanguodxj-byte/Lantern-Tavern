class_name ViewModel
extends Node3D

## Local-only first person weapon presentation. Combat timing stays in PlayerState.
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const VISUAL_STATE_MACHINE := preload("res://scenes/characters/player/first_person_weapon_visual_state_machine.gd")
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
const DEFAULT_VIEW_POSITION := Vector3(0.22, -0.26, -0.58)
const DEFAULT_VIEW_ROTATION := Vector3(12.0, 4.0, -4.0)
const DEFAULT_AIM_POSITION := Vector3(0.0, -0.16, -0.52)
const DEFAULT_AIM_ROTATION := Vector3(4.0, 0.0, -1.0)
const DEFAULT_SHIELD_POSITION := Vector3(-0.30, -0.22, -0.42)
const DEFAULT_SHIELD_ROTATION := Vector3(6.0, -20.0, 8.0)

@export var view_position := DEFAULT_VIEW_POSITION
@export var view_rotation_degrees := DEFAULT_VIEW_ROTATION
@export var aim_position := DEFAULT_AIM_POSITION
@export var aim_rotation_degrees := DEFAULT_AIM_ROTATION
@export_range(0.0, 1.0) var weapon_sway_strength := 1.0
## 第一人称武器动作动画开关（控制挥砍/拉弓/后坐的 ViewModel 演出）。
## 注意：武器 GLB 本身不含手臂/手部几何；玩家自身身体（含手臂）已在
## Player._hide_character_body() 中移入第 10 渲染层，对主相机不可见。
## 因此本开关只决定“武器自身是否摆动”，永不显示任何手臂。
## 默认开启：玩家能看到完整的第一人称武器动画（需求：不要看到手臂，但要看到武器动画）。
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
@onready var muzzle_point: Node3D = $BobPivot/AimPivot/ActionPivot/WeaponSocket/MuzzlePoint
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animator: ViewModelAnimator = ViewModelAnimator.new()

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
## Explicitly models the visual-only press/hold/release/recover phases.
var visual_state_machine: RefCounted = VISUAL_STATE_MACHINE.new()
## 当前实际使用的视图渲染层（独立相机激活时为 WEAPON_VIEW_RENDER_LAYER，否则回退层）。
var _active_view_layer := VIEW_MODEL_RENDER_LAYER
var _main_camera: Camera3D
var _weapon_camera: Camera3D
var _weapon_subviewport: SubViewport

func _ready() -> void:
	_reset_base()
	_apply_shield_pose()
	animator.bind(action_pivot, animation_player)
	_setup_weapon_camera()
	var game_events := get_tree().root.get_node_or_null("GameEvents")
	if game_events != null and game_events.has_signal("weapon_changed"):
		game_events.weapon_changed.connect(_on_weapon_changed)
	if game_events != null and game_events.has_signal("shield_changed"):
		game_events.shield_changed.connect(_on_shield_changed)

func _process(delta: float) -> void:
	_bob_time += delta
	# BobPivot is exclusively owned by this script.
	var amplitude := 0.004 * weapon_sway_strength * lerpf(1.0, 0.25, _aim_weight)
	bob_pivot.position = Vector3(0.0, sin(_bob_time * 1.7) * amplitude, 0.0)
	visual_state_machine.tick(delta)
	_sync_weapon_camera()

## 构建独立武器相机：一个共享主世界的 SubViewport + 只渲染武器层的相机，
## 经透明背景 CanvasLayer 叠加到画面之上。武器/盾牌因此只与武器层做深度测试，
## 永不被世界墙体遮挡（消除贴墙穿模）。headless 时跳过（回退到第 1 层）。
## 主相机引用延迟到 _sync_weapon_camera 通过视口获取，故无论 ViewModel 挂在
## 哪个节点下都能工作；确认主相机存在后才把武器切到专属渲染层，避免无主相机时武器消失。
func _setup_weapon_camera() -> void:
	if not use_weapon_camera:
		return
	if DisplayServer.get_name() == "headless":
		return
	_weapon_subviewport = SubViewport.new()
	_weapon_subviewport.own_world_3d = false
	_weapon_subviewport.transparent_bg = true
	_weapon_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_weapon_subviewport.handle_input_locally = false
	_weapon_subviewport.audio_listener_enable_3d = false
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay := CanvasLayer.new()
	overlay.name = "WeaponOverlay"
	overlay.layer = WEAPON_OVERLAY_CANVAS_LAYER
	_weapon_camera = Camera3D.new()
	_weapon_camera.cull_mask = WEAPON_VIEW_RENDER_LAYER
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
	# 确认主相机存在后，才把武器/盾牌切到专属渲染层（仅武器相机可见）。
	if _active_view_layer != WEAPON_VIEW_RENDER_LAYER:
		_active_view_layer = WEAPON_VIEW_RENDER_LAYER
		_apply_active_view_layer_to_spawned()
	_weapon_camera.global_transform = _main_camera.global_transform
	_weapon_camera.fov = weapon_camera_fov if weapon_camera_fov > 0.0 else _main_camera.fov
	_weapon_camera.near = _main_camera.near
	_weapon_camera.far = _main_camera.far

## 当渲染层切换时，把已生成的武器/盾牌网格重新设到新层。
func _apply_active_view_layer_to_spawned() -> void:
	if is_instance_valid(_current_weapon_node):
		_set_render_layer_recursive(_current_weapon_node, _active_view_layer)
	if is_instance_valid(_current_shield_node):
		_set_render_layer_recursive(_current_shield_node, _active_view_layer)

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

func clear_shield() -> void:
	_current_shield_data = null
	if is_instance_valid(_current_shield_node):
		# 同步释放：盾牌是 ViewModel 独占的静态网格（无自身 _process），
		# 立即移除可避免切换/卸下盾牌后残留一帧旧网格。
		_current_shield_node.free()
	_current_shield_node = null

func _apply_shield_pose() -> void:
	if is_instance_valid(shield_socket):
		shield_socket.transform = Transform3D(Basis.from_euler(_degrees_to_radians(shield_view_rotation_degrees)), shield_view_position)

func set_weapon(weapon_data: WeaponData) -> void:
	clear_weapon()
	_current_weapon_data = weapon_data
	if weapon_data == null:
		return
	_apply_weapon_pose_offsets(weapon_data)
	var profile := resolve_weapon_profile(weapon_data)
	set_weapon_profile(profile)
	_apply_weapon_mount_pose(profile)
	if weapon_data.glb_mesh == null or weapon_data.item_tag == "shield" or weapon_data.weapon_class == "shield":
		return
	_current_weapon_node = weapon_data.glb_mesh.instantiate() as Node3D
	if _current_weapon_node == null:
		return
	_current_weapon_node.scale = Vector3.ONE * _weapon_view_scale_for(resolve_weapon_profile(weapon_data))
	weapon_socket.add_child(_current_weapon_node)
	VOXEL_LIGHTING.apply_weapon_tree(_current_weapon_node, weapon_data.material_tier)
	_set_render_layer_recursive(_current_weapon_node, _active_view_layer)
	play_action(&"vm_equip")

func clear_weapon() -> void:
	visual_state_machine.cancel()
	stop_action(true)
	_current_weapon_data = null
	if is_instance_valid(_current_weapon_node):
		_current_weapon_node.queue_free()
	_current_weapon_node = null
	view_position = DEFAULT_VIEW_POSITION
	view_rotation_degrees = DEFAULT_VIEW_ROTATION
	aim_position = DEFAULT_AIM_POSITION
	aim_rotation_degrees = DEFAULT_AIM_ROTATION
	weapon_socket.transform = Transform3D.IDENTITY
	_reset_base()

func _set_render_layer_recursive(node: Node, layer: int) -> void:
	if node is GeometryInstance3D:
		node.layers = layer
	for child in node.get_children():
		_set_render_layer_recursive(child, layer)

func _material_tier_for(data: Resource) -> String:
	if data != null and "material_tier" in data:
		return String(data.get("material_tier"))
	return ""


func _weapon_view_scale_for(profile: StringName) -> float:
	match profile:
		&"shortsword": return 0.42
		&"sword": return 0.36
		&"dagger": return 0.44
		&"spear": return 0.32
		&"heavy": return 0.32
		&"bow": return 0.36
		&"crossbow": return 0.38
		_: return DEFAULT_WEAPON_VIEW_SCALE

## Fixed weapon-to-hand presentation.  ActionPivot owns the attack motion;
## WeaponSocket owns the authored first-person grip/axis correction so the
## attack rotates around a believable ready pose instead of the raw GLB axis.
func _apply_weapon_mount_pose(profile: StringName) -> void:
	var mount_position := Vector3.ZERO
	var mount_rotation := Vector3.ZERO
	match profile:
		&"shortsword":
			# Start lower and farther right so the center stays clear; the
			# attack drives the whole weapon forward along the view axis.
			mount_position = Vector3(0.12, 0.02, -0.02)
			mount_rotation = Vector3(-8.0, -12.0, -135.0)
		&"sword":
			# The longsword stays farther right and slightly higher than the
			# shortsword, with a broader one-hand cutting lane.
			mount_position = Vector3(0.08, 0.06, -0.01)
			mount_rotation = Vector3(-10.0, -8.0, -140.0)
		&"one_hand":
			# The sword GLB is authored blade-down around its guard.  Put the
			# guard at the right-hand ready point and turn the blade up-left.
			mount_position = Vector3(0.03, 0.12, -0.02)
			mount_rotation = Vector3(-10.0, -10.0, -135.0)
		&"dagger":
			mount_position = Vector3(0.06, 0.08, -0.02)
			mount_rotation = Vector3(-8.0, -14.0, -135.0)
		&"heavy":
			mount_position = Vector3(-0.02, 0.08, -0.01)
			mount_rotation = Vector3(-14.0, -8.0, -135.0)
		&"spear":
			mount_position = Vector3(0.04, 0.03, -0.01)
			mount_rotation = Vector3(-8.0, -4.0, -155.0)
	weapon_socket.transform = Transform3D(Basis.from_euler(_degrees_to_radians(mount_rotation)), mount_position)

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
	if weapon_data == null:
		return &"one_hand"
	var explicit_profile := weapon_data.view_model_profile.strip_edges().to_lower()
	if not explicit_profile.is_empty():
		return StringName(explicit_profile)
	var weapon_class := weapon_data.weapon_class.to_lower()
	var tags: Array = weapon_data.tags
	if tags.has("dagger"):
		return &"dagger"
	if tags.has("spear") or "spear" in weapon_class:
		return &"spear"
	if weapon_class == "two_hand":
		return &"heavy"
	if weapon_class == "crossbow" or tags.has("crossbow"):
		return &"crossbow"
	if weapon_class == "longbow" or tags.has("bow"):
		return &"bow"
	if weapon_class == "wand":
		return &"wand"
	return &"one_hand"

func resolve_melee_action(weapon_data: WeaponData = _current_weapon_data) -> StringName:
	match resolve_weapon_profile(weapon_data):
		&"shortsword": return &"vm_shortsword_thrust"
		&"sword": return &"vm_sword_slash"
		&"dagger": return &"vm_stab_dagger"
		&"spear": return &"vm_thrust_spear"
		&"heavy": return &"vm_slash_heavy"
		_: return &"vm_slash_one_hand"

## The normalized hold pose is shared by melee and bow preparation.  A
## crossbow skips this path and uses its short fire recoil instead.
func resolve_hold_action(weapon_data: WeaponData = _current_weapon_data) -> StringName:
	match resolve_weapon_profile(weapon_data):
		&"shortsword": return &"vm_shortsword_hold"
		&"sword": return &"vm_sword_hold"
		&"bow": return &"vm_bow_draw"
		_: return &"vm_melee_charge"


func resolve_release_action(weapon_data: WeaponData = _current_weapon_data) -> StringName:
	match resolve_weapon_profile(weapon_data):
		&"bow": return &"vm_bow_release"
		&"crossbow": return &"vm_crossbow_fire"
		&"wand": return &"vm_wand_cast"
		_: return resolve_melee_action(weapon_data)

func get_base_transform() -> Transform3D:
	return _base_transform

func get_muzzle_global_transform() -> Transform3D:
	if is_instance_valid(muzzle_point):
		return muzzle_point.global_transform
	return weapon_socket.global_transform.translated_local(Vector3(0.0, 0.0, -MUZZLE_FORWARD_OFFSET))

func get_muzzle_global_position() -> Vector3:
	return get_muzzle_global_transform().origin

func set_aim_weight(weight: float) -> void:
	_aim_weight = clampf(weight, 0.0, 1.0)
	_base_transform = Transform3D(Basis.from_euler(_degrees_to_radians(view_rotation_degrees).lerp(_degrees_to_radians(aim_rotation_degrees), _aim_weight)), view_position.lerp(aim_position, _aim_weight))
	aim_pivot.transform = _base_transform

func set_aiming(enabled: bool) -> void:
	set_aim_weight(1.0 if enabled else 0.0)

func set_weapon_profile(profile_id: StringName) -> void:
	animator.set_weapon_profile(profile_id)


## Begins the local visual hold phase.  It does not start combat or alter
## damage; PlayerState still decides whether release is allowed.
func begin_weapon_hold() -> bool:
	var accepted: bool = visual_state_machine.begin_hold(resolve_weapon_profile(_current_weapon_data))
	if accepted:
		sample_action(resolve_hold_action(), 0.0)
	return accepted


## Samples the held pose from 0..1 while the input remains down.
func update_weapon_hold(normalized_progress: float) -> bool:
	var accepted: bool = visual_state_machine.set_hold_progress(normalized_progress)
	if accepted:
		# sample_action(1.0) intentionally restores the action layer for a
		# completed one-shot animation. Holding is different: the final charge
		# pose must remain visible until the mouse button is released.
		sample_action(resolve_hold_action(), minf(clampf(normalized_progress, 0.0, 1.0), 0.999))
	return accepted


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
	stop_action(true)


func get_visual_weapon_state() -> int:
	return visual_state_machine.state


func get_visual_weapon_state_name() -> StringName:
	return visual_state_machine.state_name()


func _action_length(action_name: StringName) -> float:
	if animation_player != null and animation_player.has_animation(action_name):
		return animation_player.get_animation(action_name).length
	return 0.46

func sample_action(action_name: StringName, normalized_progress: float) -> void:
	# 手臂动作动画屏蔽时武器保持静态持握位。
	if not arm_animation_enabled:
		return
	animator.sample_action(action_name, normalized_progress)

func play_action(action_name: StringName, custom_speed: float = 1.0) -> void:
	if not arm_animation_enabled:
		return
	_queued_action_generation += 1
	if _is_release_action(action_name):
		begin_weapon_release(action_name)
	animator.play_action(action_name, custom_speed)

## Queues a purely visual follow-up without introducing a transform-writing Tween.
func play_action_after(action_name: StringName, delay_sec: float, custom_speed: float = 1.0) -> void:
	if not arm_animation_enabled:
		return
	_queued_action_generation += 1
	var generation := _queued_action_generation
	get_tree().create_timer(maxf(delay_sec, 0.0)).timeout.connect(func() -> void:
		if generation == _queued_action_generation and is_instance_valid(self):
			animator.play_action(action_name, custom_speed)
	)

func stop_action(reset_pose: bool = true) -> void:
	_queued_action_generation += 1
	animator.stop_action(reset_pose)
	if reset_pose and is_instance_valid(weapon_socket) and _current_weapon_data != null:
		# A thrust may animate the socket itself so the sword rotates around the
		# grip.  Restore the authored mount after cancellation/recovery.
		_apply_weapon_mount_pose(resolve_weapon_profile(_current_weapon_data))


func _is_release_action(action_name: StringName) -> bool:
	return action_name in [
		&"vm_shortsword_thrust", &"vm_sword_slash", &"vm_slash_one_hand", &"vm_slash_heavy", &"vm_stab_dagger",
		&"vm_thrust_spear", &"vm_bow_release", &"vm_crossbow_fire", &"vm_wand_cast",
	]

## Deprecated wrappers retained for one migration cycle.
func apply_slash_arc(progress_value: float, _side: float = 1.0) -> void:
	sample_action(resolve_melee_action(), progress_value)

func apply_melee_charge(charge_progress: float) -> void:
	sample_action(&"vm_melee_charge", charge_progress)

func apply_bow_pull(charge_progress: float) -> void:
	sample_action(&"vm_bow_draw", charge_progress)

func apply_recoil() -> void:
	match resolve_weapon_profile(_current_weapon_data):
		&"bow": play_action(&"vm_bow_release")
		&"crossbow": play_action(&"vm_crossbow_fire")
		&"wand": play_action(&"vm_wand_cast")
		_: play_action(&"vm_crossbow_fire")

func restore_transform() -> void:
	stop_action(true)

func _degrees_to_radians(value: Vector3) -> Vector3:
	return Vector3(deg_to_rad(value.x), deg_to_rad(value.y), deg_to_rad(value.z))
