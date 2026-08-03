class_name ViewModel
extends Node3D

## First-person presentation layer. It owns only local visual weapon/shield
## copies. No hand, arm, body or other character geometry is instantiated here.
## The third-person character rig remains independent and authoritative for
## gameplay animation timing and state exit.
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const VISUAL_STATE_MACHINE := preload("res://scenes/characters/player/first_person_weapon_visual_state_machine.gd")
const WEAPON_MOUNT_PROFILE := preload("res://globals/visual/weapon_mount_profile.gd")
const PLAYER_ANIMATION_PROFILE := preload("res://globals/visual/player_animation_profile.gd")
const FIRST_PERSON_EQUIPMENT_MOTION := preload("res://scenes/characters/player/first_person_equipment_motion.gd")
const FIRST_PERSON_ANIMATION_LIBRARY := preload("res://scenes/characters/player/first_person_animation_library.gd")
const FIRST_PERSON_WEAPON_ANIMATION_CATALOG := preload("res://scenes/characters/player/first_person_weapon_animation_catalog.gd")
## Fallback layer used until the dedicated weapon camera finds the main camera.
## Keeping this as layer 1 avoids a missing weapon during scene initialization.
const VIEW_MODEL_RENDER_LAYER := 1
## Dedicated layer (第 11 层) rendered only by the独立武器相机。MainCamera 的
## cull_mask=1 天然排除本层，因此武器/盾牌不会被主相机重复渲染或被墙体遮挡。
const WEAPON_VIEW_RENDER_LAYER := 1 << 10
## 武器叠加层的 CanvasLayer 序号：需低于战斗 HUD(15)/UI(20)，高于 3D 世界(0)。
const WEAPON_OVERLAY_CANVAS_LAYER := 5
const MUZZLE_FORWARD_OFFSET := 0.6
const DEFAULT_WEAPON_CAMERA_FOV := 68.0
## 武器叠加层在私有世界中渲染，无法直接吃到主世界灯光。
## 以下常量控制按节流采样主世界光照并镜像到叠加层灯组的参数。
## 同步周期（秒）：区域环境光与方向光在生成时固定，火把/视野灯随移动变化，
## 0.2s 足以跟踪移动变化，又不会每帧遍历场景树。
const OVERLAY_LIGHT_SYNC_INTERVAL := 0.2
## 参与叠加层补光的局部光源采样半径（米）。视野灯与火把都在该半径内。
const OVERLAY_LOCAL_LIGHT_RADIUS := 12.0
## 一次补光采样计入的局部光源数量上限，避免亮区堆叠过量。
const OVERLAY_LOCAL_LIGHT_MAX := 10
## 环境光下限：即使区域环境光极暗，武器仍需保持可读的基础轮廓。
const OVERLAY_AMBIENT_FLOOR := 0.15
## 方向光（主光）能量下限：保留体素明暗分面，避免完全压黑。
const OVERLAY_KEY_ENERGY_FLOOR := 0.15
## 局部光源总能量缩放系数，把多灯能量压回可读范围。
const OVERLAY_LOCAL_ENERGY_SCALE := 0.35
## 叠加层补光颜色上限，防止暖色火把把补光推到过饱和。
const OVERLAY_FILL_ENERGY_MAX := 2.5
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
const DEFAULT_SHIELD_POSITION := Vector3(-0.30, -0.12, -0.55)
const DEFAULT_SHIELD_ROTATION := Vector3(6.0, -20.0, 8.0)
@export var view_position := DEFAULT_VIEW_POSITION
@export var view_rotation_degrees := DEFAULT_VIEW_ROTATION
@export var aim_position := DEFAULT_AIM_POSITION
@export var aim_rotation_degrees := DEFAULT_AIM_ROTATION
@export_range(0.0, 1.0) var weapon_sway_strength := 1.0
## 第一人称装备动作开关：只控制武器/盾牌副本，不触碰角色骨骼或战斗时序。
@export var equipment_animation_enabled := true
## 命中停帧时长（毫秒）：命中确认后短暂冻结本地 ActionPivot 采样（仅视觉）。
## 不修改 Engine.time_scale / SceneTree.paused，也不延迟伤害结算或联机状态。
@export_range(0, 100, 5) var hit_stop_duration_msec := 40.0
## 移动、视角惯性、冲刺、腾空、落地与后坐的附加运动强度。
@export_range(0.0, 1.5, 0.05) var equipment_motion_intensity := 1.0
## 瞄准姿态的指数平滑速度；高于 0 可避免瞬移到准星中心。
@export_range(1.0, 30.0, 0.5) var aim_blend_speed := 14.0
## 是否启用独立武器相机（消除贴墙穿模、允许独立 FOV）。
@export var use_weapon_camera := true
## 独立视图 FOV 可避免主相机高 FOV 把近景装备拉成长条；设为 0 才跟随主相机。
@export var weapon_camera_fov := DEFAULT_WEAPON_CAMERA_FOV
## Near solid geometry retracts and lowers the complete first-person rig before
## it can intersect the surface. The player's capsule normally keeps walls at
## least 0.25 m from the centered camera, so that distance means fully stowed.
@export_range(0.2, 1.5, 0.01) var weapon_obstruction_distance := 0.75
@export_range(0.05, 0.5, 0.01) var weapon_obstruction_full_distance := 0.25
@export var weapon_obstruction_offset := Vector3(0.0, -0.22, 0.30)
@export_range(1.0, 40.0, 0.5) var weapon_obstruction_smoothing := 18.0
## 盾牌在第一人称视图空间中的持握位姿（相对主相机）。
@export var shield_view_position := DEFAULT_SHIELD_POSITION
@export var shield_view_rotation_degrees := DEFAULT_SHIELD_ROTATION
@export_enum("standard", "alternate", "heavy") var default_weapon_animation_variant := "standard"

@onready var bob_pivot: Node3D = $BobPivot
@onready var aim_pivot: Node3D = $BobPivot/AimPivot
@onready var shield_action_pivot: Node3D = $BobPivot/AimPivot/ShieldActionPivot
@onready var shield_impact_pivot: Node3D = $BobPivot/AimPivot/ShieldActionPivot/ShieldImpactPivot
@onready var shield_socket: Node3D = $BobPivot/AimPivot/ShieldActionPivot/ShieldImpactPivot/ShieldSocket
@onready var shield_orientation: Node3D = $BobPivot/AimPivot/ShieldActionPivot/ShieldImpactPivot/ShieldSocket/ShieldOrientation
@onready var action_pivot: Node3D = $BobPivot/AimPivot/ActionPivot
@onready var weapon_socket: Node3D = $BobPivot/AimPivot/ActionPivot/WeaponSocket
@onready var weapon_orientation: Node3D = $BobPivot/AimPivot/ActionPivot/WeaponSocket/WeaponOrientation
@onready var muzzle_point: Node3D = $BobPivot/AimPivot/ActionPivot/WeaponSocket/MuzzlePoint
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animator: ViewModelAnimator = ViewModelAnimator.new()
@onready var equipment_motion: RefCounted = FIRST_PERSON_EQUIPMENT_MOTION.new()

## Compatibility alias. It is the action layer, never a second writable holder.
var weapon_holder: Node3D:
	get: return action_pivot

var _base_transform := Transform3D.IDENTITY
var _current_weapon_node: Node3D
var _current_weapon_data: WeaponData
var _current_weapon_animation_variant := "standard"
var _current_weapon_profile: StringName = &"unarmed"
var _current_shield_node: Node3D
var _current_shield_data: Resource
var _aim_weight := 0.0
var _aim_target_weight := 0.0
var _motion_local_velocity := Vector3.ZERO
var _motion_grounded := true
var _motion_sprinting := false
var _weapon_obstruction_weight := 0.0
var _queued_action_generation := 0
## 命中停帧剩余时间（秒）。命中确认后冻结本地 ActionPivot 动画采样，
## 用于打击感反馈；仅影响本地视觉，不修改 time_scale / 不冻结敌人。
var _hit_stop_remaining_sec := 0.0
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
## 叠加层光照镜像用的灯组引用（在 _setup_weapon_camera 中建立）。
var _overlay_environment: Environment
var _overlay_key_light: DirectionalLight3D
var _overlay_fill_light: DirectionalLight3D
var _overlay_camera_fill: OmniLight3D
## 主世界光照采样缓存：方向光与相机附近的局部光源，按周期刷新。
var _sync_lighting_timer := 0.0
var _cached_zone_directional: DirectionalLight3D
var _cached_local_lights: Array[Light3D] = []
## Legacy compatibility flag. Production never binds ViewModel to the
## third-person AnimationPlayer; the value remains false forever. Kept only so
## old callers/tests of bind_shared_character_animation() keep their contract.
var _uses_shared_character_animation := false

func _ready() -> void:
	_reset_base()
	_apply_shield_pose()
	animator.bind(action_pivot, animation_player)
	equipment_motion.set_profile(&"unarmed")
	_setup_weapon_camera()
	var game_events := get_tree().root.get_node_or_null("GameEvents")
	if game_events != null and game_events.has_signal("weapon_changed"):
		game_events.weapon_changed.connect(_on_weapon_changed)
	if game_events != null and game_events.has_signal("shield_changed"):
		game_events.shield_changed.connect(_on_shield_changed)
	if game_events != null and game_events.has_signal("player_hit_enemy"):
		game_events.player_hit_enemy.connect(_on_player_hit_enemy)

## Deprecated compatibility hook. First-person is intentionally independent:
## the caller's third-person animation player is never adopted or stopped.
func bind_shared_character_animation(
	_shared_animation_player: AnimationPlayer,
	_shared_weapon_placeholder: Node3D,
	_shared_shield_placeholder: Node3D = null,
	_shared_muzzle_source: Node3D = null
) -> void:
	# Arguments are intentionally ignored. This method remains only for old
	# callers/tests and cannot merge the two visual channels again.
	_uses_shared_character_animation = false

func _process(delta: float) -> void:
	if _hit_stop_remaining_sec > 0.0:
		_hit_stop_remaining_sec = maxf(_hit_stop_remaining_sec - delta, 0.0)
	_update_aim_blend(delta)
	_update_weapon_obstruction(delta)
	visual_state_machine.tick(delta)
	equipment_motion.set_motion_state(_motion_local_velocity, _motion_grounded, _motion_sprinting)
	equipment_motion.step(
		delta,
		_aim_weight,
		_procedural_action_weight(),
		equipment_motion_intensity * weapon_sway_strength
	)
	var equipment_transform: Transform3D = equipment_motion.get_transform()
	equipment_transform.origin += weapon_obstruction_offset * _weapon_obstruction_weight
	bob_pivot.transform = equipment_transform
	shield_impact_pivot.transform = equipment_motion.get_shield_impact_transform()
	_sync_weapon_camera()
	_sync_weapon_overlay_lighting(delta)


func set_motion_state(local_velocity: Vector3, grounded: bool, sprinting: bool) -> void:
	_motion_local_velocity = local_velocity if local_velocity.is_finite() else Vector3.ZERO
	_motion_grounded = grounded
	_motion_sprinting = sprinting


func add_look_input(relative: Vector2) -> void:
	equipment_motion.add_look_input(relative)


func play_block_impact(strength: float = 1.0, horizontal_bias: float = 0.0) -> void:
	if _current_shield_data == null:
		return
	equipment_motion.add_shield_impact(strength, horizontal_bias)


## 命中确认后的本地视觉停帧（Hit-Stop）。仅冻结第一人称武器/盾牌的
## ActionPivot 动画采样 30~50ms，不修改 Engine.time_scale、SceneTree.paused
## 或联机状态，也不延迟服务器伤害与敌人行为。
func play_hit_stop() -> void:
	if not equipment_animation_enabled:
		return
	_hit_stop_remaining_sec = maxf(_hit_stop_remaining_sec, hit_stop_duration_msec / 1000.0)


func is_hit_stop_active() -> bool:
	return _hit_stop_remaining_sec > 0.0


## 玩家命中敌人信号（enemy.gd 发射）→ 触发本地停帧。is_crit 时略长。
func _on_player_hit_enemy(hit_data: Dictionary) -> void:
	play_hit_stop()
	if bool(hit_data.get("is_crit", false)):
		_hit_stop_remaining_sec = maxf(_hit_stop_remaining_sec, hit_stop_duration_msec * 1.5 / 1000.0)


func _procedural_action_weight() -> float:
	match visual_state_machine.state:
		VISUAL_STATE_MACHINE.State.HOLDING:
			return 0.55
		VISUAL_STATE_MACHINE.State.RELEASING:
			return 0.90
		VISUAL_STATE_MACHINE.State.RECOVERING:
			return 0.65
	return 0.0


func obstruction_weight_for_distance(hit_distance: float) -> float:
	if hit_distance < 0.0:
		return 0.0
	var full_distance := minf(weapon_obstruction_full_distance, weapon_obstruction_distance)
	var distance_span := maxf(weapon_obstruction_distance - full_distance, 0.001)
	return clampf((weapon_obstruction_distance - hit_distance) / distance_span, 0.0, 1.0)


func _update_weapon_obstruction(delta: float) -> void:
	var target_weight := _sample_weapon_obstruction_weight()
	var blend := 1.0 - exp(-weapon_obstruction_smoothing * maxf(delta, 0.0))
	_weapon_obstruction_weight = lerpf(_weapon_obstruction_weight, target_weight, blend)


func _sample_weapon_obstruction_weight() -> float:
	if _main_camera == null or not is_instance_valid(_main_camera):
		_main_camera = get_parent() as Camera3D
	if _main_camera == null or not is_instance_valid(_main_camera):
		return 0.0
	var world := _main_camera.get_world_3d()
	if world == null:
		return 0.0
	var ray_from := _main_camera.global_position
	var ray_to := _main_camera.to_global(Vector3(0.0, 0.0, -weapon_obstruction_distance))
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collision_mask = (
		PhysicsSetup.MASK_VISION_OBSTRUCTION
		| PhysicsSetup.LAYER_ENEMY
	)
	query.collide_with_areas = false
	var body := _main_camera.get_parent()
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	var hit_position: Vector3 = hit.get("position", ray_to)
	return obstruction_weight_for_distance(ray_from.distance_to(hit_position))

## 构建独立武器相机：透明私有 SubViewport 经 CanvasLayer 叠加到画面之上。
## 武器/盾牌视觉副本只与自身深度测试，永不被世界墙体或近处物体遮挡。
## 主相机引用延迟到 _sync_weapon_camera 通过视口获取，故无论 ViewModel 挂在
## 哪个节点下都能工作；确认主相机存在后才把武器切到专属渲染层，避免无主相机时武器消失。
func _setup_weapon_camera() -> void:
	if not use_weapon_camera:
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
	# The private overlay world has no dungeon lights. The overlay rig is driven
	# by _sync_weapon_overlay_lighting() to mirror the main world's actual
	# lighting state (zone directional + ambient + nearby local lights), so the
	# first-person weapon is lit like the world instead of a fixed neutral rig.
	var overlay_environment_node := WorldEnvironment.new()
	overlay_environment_node.name = "WeaponOverlayEnvironment"
	var overlay_environment := Environment.new()
	overlay_environment.background_mode = Environment.BG_COLOR
	overlay_environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	overlay_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	overlay_environment.ambient_light_color = Color(0.62, 0.69, 0.80)
	overlay_environment.ambient_light_energy = 0.85
	overlay_environment_node.environment = overlay_environment
	_weapon_subviewport.add_child(overlay_environment_node)
	var weapon_key_light := DirectionalLight3D.new()
	weapon_key_light.name = "WeaponOverlayKeyLight"
	weapon_key_light.light_color = Color(1.0, 0.90, 0.76)
	weapon_key_light.light_energy = 2.25
	weapon_key_light.shadow_enabled = false
	weapon_key_light.light_cull_mask = VIEW_MODEL_RENDER_LAYER
	weapon_key_light.rotation_degrees = Vector3(-38.0, -30.0, 0.0)
	_weapon_subviewport.add_child(weapon_key_light)
	var weapon_fill_light := DirectionalLight3D.new()
	weapon_fill_light.name = "WeaponOverlayFillLight"
	weapon_fill_light.light_color = Color(0.58, 0.72, 1.0)
	weapon_fill_light.light_energy = 0.90
	weapon_fill_light.shadow_enabled = false
	weapon_fill_light.light_cull_mask = VIEW_MODEL_RENDER_LAYER
	weapon_fill_light.rotation_degrees = Vector3(-18.0, 142.0, 0.0)
	_weapon_subviewport.add_child(weapon_fill_light)
	var weapon_camera_fill := OmniLight3D.new()
	weapon_camera_fill.name = "WeaponOverlayCameraFill"
	weapon_camera_fill.position = Vector3(0.24, 0.18, 0.10)
	weapon_camera_fill.light_color = Color(0.88, 0.93, 1.0)
	weapon_camera_fill.light_energy = 0.70
	weapon_camera_fill.omni_range = 3.0
	weapon_camera_fill.omni_attenuation = 0.65
	weapon_camera_fill.shadow_enabled = false
	weapon_camera_fill.light_cull_mask = VIEW_MODEL_RENDER_LAYER
	_weapon_subviewport.add_child(weapon_camera_fill)
	_overlay_environment = overlay_environment
	_overlay_key_light = weapon_key_light
	_overlay_fill_light = weapon_fill_light
	_overlay_camera_fill = weapon_camera_fill
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
	# SubViewportContainer.stretch owns resize propagation after setup. Writing
	# SubViewport.size here conflicts with the container and produces warnings.
	# 确认主相机存在后，才把武器/盾牌切到专属渲染层（仅武器相机可见）。
	if _active_view_layer != WEAPON_VIEW_RENDER_LAYER:
		_active_view_layer = WEAPON_VIEW_RENDER_LAYER
		_apply_active_view_layer_to_spawned()
	var camera_offset := WEAPON_MOUNT_PROFILE.first_person_camera_offset(
		String(resolve_weapon_profile(_current_weapon_data))
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


## 按周期采样主相机所在世界的真实光照，并镜像到叠加层灯组，使第一人称武器
## 与周围世界一样受光：区域方向光决定主光，区域环境光决定环境光，相机附近的
## 局部光源（视野灯/火把）决定补光。私有世界没有地牢灯，靠此镜像实现"正常受光"。
func _sync_weapon_overlay_lighting(delta: float) -> void:
	if _weapon_subviewport == null or not use_weapon_camera:
		return
	if _overlay_environment == null:
		return
	# 空手时没有可受光的装备，跳过场景树采样与灯组更新。
	if not is_instance_valid(_current_weapon_node) and not is_instance_valid(_current_shield_node):
		return
	_sync_lighting_timer -= delta
	if _sync_lighting_timer > 0.0:
		return
	_sync_lighting_timer = OVERLAY_LIGHT_SYNC_INTERVAL
	if _main_camera == null or not is_instance_valid(_main_camera):
		_main_camera = get_viewport().get_camera_3d()
	if _main_camera == null or not is_instance_valid(_main_camera):
		return
	var world := _main_camera.get_world_3d()
	if world == null:
		return
	_collect_world_lighting(world)
	_apply_world_lighting_to_overlay()


## 从主世界收集光照状态：环境光、主方向光、相机附近局部光源。
## world 来自主相机，包含场景 WorldEnvironment 与全部光源。
func _collect_world_lighting(world: World3D) -> void:
	_cached_zone_directional = null
	_cached_local_lights.clear()
	# 方向光在 Godot 中按"无限远"处理，主相机世界的首个活动方向光即区域主光。
	var lights: Array[Light3D] = []
	var light_root := _scene_light_root()
	DungeonLightingHelper.collect_scene_lights(light_root, lights)
	# 叠加层灯组挂在武器私有 SubViewport 下、与主世界同一棵树中；必须排除它们，
	# 否则会把自身灯组（含主光能量 2.25）当作场景光照反向采样回来。
	var main_viewport := _main_camera.get_viewport()
	var camera_position := _main_camera.global_position
	for light in lights:
		if light.get_viewport() != main_viewport:
			continue
		# 玩家视野灯是"照亮地形以便玩家看见"的辅助光源，并非世界真实光源；
		# 若采样它，武器叠加层会在任何黑暗区域都被自带的视野灯照亮，抵消暗区变暗。
		if DungeonLightingHelper.is_player_vision_light(light, Player.PLAYER_VISION_LIGHT_NAME):
			continue
		if light is DirectionalLight3D:
			if not light.visible:
				continue
			if _cached_zone_directional == null or light.light_energy > _cached_zone_directional.light_energy:
				_cached_zone_directional = light
			continue
		if not light.visible:
			continue
		if light.global_position.distance_to(camera_position) > OVERLAY_LOCAL_LIGHT_RADIUS:
			continue
		_cached_local_lights.append(light)
		if _cached_local_lights.size() >= OVERLAY_LOCAL_LIGHT_MAX:
			break


## 找相机所在场景的根，供 collect_scene_lights 遍历。
func _scene_light_root() -> Node:
	if _main_camera != null and is_instance_valid(_main_camera):
		var scene := _main_camera.get_tree().current_scene
		if scene != null:
			return scene
	return get_tree().root


## 把采样到的光照状态应用到叠加层灯组。没有主光/环境光时回退到预设值。
func _apply_world_lighting_to_overlay() -> void:
	# 区域环境光
	var world_ambient := Color(0.62, 0.69, 0.80)
	var world_ambient_energy := 0.85
	var world := _main_camera.get_world_3d() if is_instance_valid(_main_camera) else null
	if world != null and world.environment != null:
		world_ambient = world.environment.ambient_light_color
		world_ambient_energy = world.environment.ambient_light_energy
	_overlay_environment.ambient_light_color = world_ambient
	_overlay_environment.ambient_light_energy = maxf(world_ambient_energy, OVERLAY_AMBIENT_FLOOR)
	# 主方向光
	if is_instance_valid(_cached_zone_directional):
		var zone := _cached_zone_directional
		_overlay_key_light.light_color = zone.light_color
		_overlay_key_light.light_energy = maxf(zone.light_energy, OVERLAY_KEY_ENERGY_FLOOR)
		_overlay_key_light.rotation_degrees = zone.rotation_degrees
	# 相机附近局部光源 → 补光（视野灯/火把的加权色与能量）
	var total_color := Vector3.ZERO
	var total_energy := 0.0
	for light in _cached_local_lights:
		if light == null or not is_instance_valid(light):
			continue
		total_color += Vector3(light.light_color.r, light.light_color.g, light.light_color.b) * light.light_energy
		total_energy += light.light_energy
	if total_energy > 0.0001:
		var avg := total_color / total_energy
		_overlay_camera_fill.light_color = Color(
			clampf(avg.x, 0.0, 1.0),
			clampf(avg.y, 0.0, 1.0),
			clampf(avg.z, 0.0, 1.0),
		)
		_overlay_camera_fill.light_energy = clampf(total_energy * OVERLAY_LOCAL_ENERGY_SCALE, 0.0, OVERLAY_FILL_ENERGY_MAX)

## 当渲染层切换时，把已生成的武器/盾牌网格重新设到新层。
func _apply_active_view_layer_to_spawned() -> void:
	if is_instance_valid(_current_weapon_node):
		_set_render_layer_recursive(_current_weapon_node, _active_view_layer)
	if is_instance_valid(_current_shield_node):
		_set_render_layer_recursive(_current_shield_node, _active_view_layer)

## The weapon overlay is an isolated render pass. Preserve imported texture/color,
## but keep every surface lit and non-emissive like the world model.
func _apply_first_person_weapon_materials(root: Node) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if not mesh_instance.has_meta("first_person_materials_applied"):
			var override_copy := _make_first_person_lit_material(mesh_instance.material_override)
			if override_copy != null:
				mesh_instance.material_override = override_copy
			if mesh_instance.mesh != null:
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					var surface_material := mesh_instance.get_surface_override_material(surface_index)
					if surface_material == null:
						surface_material = mesh_instance.mesh.surface_get_material(surface_index)
					var surface_copy := _make_first_person_lit_material(surface_material)
					if surface_copy != null:
						mesh_instance.set_surface_override_material(surface_index, surface_copy)
			mesh_instance.set_meta("first_person_materials_applied", true)
	for child in root.get_children():
		_apply_first_person_weapon_materials(child)


func _make_first_person_lit_material(source: Material) -> Material:
	if not source is BaseMaterial3D:
		return source
	var copy := (source as BaseMaterial3D).duplicate() as BaseMaterial3D
	if copy == null:
		return source
	# BaseMaterial3D covers imported standard-material subtypes while keeping GLB
	# texture/color maps intact. The overlay receives its own neutral Light3D.
	copy.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	copy.emission_enabled = false
	copy.emission = Color.BLACK
	copy.emission_texture = null
	copy.emission_energy_multiplier = 0.0
	return copy

func _reset_base() -> void:
	_base_transform = Transform3D(Basis.from_euler(_degrees_to_radians(view_rotation_degrees)), view_position)
	if is_instance_valid(aim_pivot):
		aim_pivot.transform = _base_transform
	if is_instance_valid(action_pivot):
		action_pivot.transform = Transform3D.IDENTITY
	if is_instance_valid(shield_action_pivot):
		shield_action_pivot.transform = Transform3D.IDENTITY
	if is_instance_valid(shield_impact_pivot):
		shield_impact_pivot.transform = Transform3D.IDENTITY
	if is_instance_valid(shield_orientation):
		shield_orientation.transform = Transform3D.IDENTITY

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
	_current_shield_node.scale = Vector3.ONE * _shield_view_scale(shield_data)
	_current_shield_node.set_meta("visual_only", true)
	shield_orientation.add_child(_current_shield_node)
	VOXEL_LIGHTING.apply_weapon_tree(_current_shield_node, _material_tier_for(_current_shield_data))
	_set_render_layer_recursive(_current_shield_node, _active_view_layer)
	_refresh_shield_overlay()

func clear_shield() -> void:
	_current_shield_data = null
	equipment_motion.clear_shield_impact()
	if is_instance_valid(shield_action_pivot):
		shield_action_pivot.transform = Transform3D.IDENTITY
	if is_instance_valid(shield_impact_pivot):
		shield_impact_pivot.transform = Transform3D.IDENTITY
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
		var desired_transform := Transform3D(
			Basis.from_euler(_degrees_to_radians(shield_view_rotation_degrees)),
			shield_view_position
		)
		shield_socket.transform = aim_pivot.transform.affine_inverse() * desired_transform

func set_weapon(weapon_data: WeaponData) -> void:
	clear_weapon()
	_current_weapon_data = weapon_data
	set_weapon_profile(resolve_weapon_profile(weapon_data))
	_load_weapon_animation_library(weapon_data, default_weapon_animation_variant)
	if weapon_data == null:
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
	_current_weapon_data = null
	_current_weapon_animation_variant = default_weapon_animation_variant
	animator.set_library(FIRST_PERSON_ANIMATION_LIBRARY.build())
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


func _shield_view_scale(shield_data: Resource) -> float:
	if shield_data is WeaponData:
		return _weapon_view_scale(shield_data as WeaponData)
	return _weapon_view_scale_for(&"shield")


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
		&"shield": return 0.30
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

func set_weapon_animation_variant(variant: String) -> bool:
	if not FIRST_PERSON_WEAPON_ANIMATION_CATALOG.has_variant(variant):
		return false
	_current_weapon_animation_variant = variant.strip_edges().to_lower()
	if _current_weapon_data != null:
		_load_weapon_animation_library(_current_weapon_data, _current_weapon_animation_variant)
		stop_action(true)
	return true

func get_weapon_animation_variant() -> String:
	return _current_weapon_animation_variant

func _load_weapon_animation_library(weapon_data: WeaponData, variant: String) -> void:
	if weapon_data == null:
		animator.set_library(FIRST_PERSON_ANIMATION_LIBRARY.build())
		return
	_current_weapon_animation_variant = variant.strip_edges().to_lower()
	var library := FIRST_PERSON_ANIMATION_LIBRARY.load_for_weapon(weapon_data.id, _current_weapon_animation_variant)
	animator.set_library(library)

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
	if is_instance_valid(muzzle_point):
		return muzzle_point.global_transform
	return weapon_socket.global_transform.translated_local(Vector3(0.0, 0.0, -MUZZLE_FORWARD_OFFSET))

func get_muzzle_global_position() -> Vector3:
	return get_muzzle_global_transform().origin

func set_aim_weight(weight: float) -> void:
	_aim_target_weight = clampf(weight, 0.0, 1.0)
	_update_aim_transform()

func set_aiming(enabled: bool) -> void:
	set_aim_weight(1.0 if enabled else 0.0)


func get_aim_weight() -> float:
	return _aim_weight


func _update_aim_blend(delta: float) -> void:
	var blend := 1.0 - exp(-aim_blend_speed * maxf(delta, 0.0))
	_aim_weight = lerpf(_aim_weight, _aim_target_weight, blend)
	if absf(_aim_weight - _aim_target_weight) < 0.0001:
		_aim_weight = _aim_target_weight
	_update_aim_transform()


func _update_aim_transform() -> void:
	_base_transform = Transform3D(
		Basis.from_euler(
			_degrees_to_radians(view_rotation_degrees).lerp(
				_degrees_to_radians(aim_rotation_degrees),
				_aim_weight
			)
		),
		view_position.lerp(aim_position, _aim_weight)
	)
	if is_instance_valid(aim_pivot):
		aim_pivot.transform = _base_transform
	_apply_shield_pose()

func set_weapon_profile(profile_id: StringName) -> void:
	_current_weapon_profile = profile_id
	animator.set_weapon_profile(profile_id)
	equipment_motion.set_profile(profile_id)


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
	if animation_player == null or not animation_player.has_animation(action):
		return false
	animator.play_action(action)
	return true


## Restores the idle pose when a persistent defense/aim state exits.
func finish_weapon_defense(action_name: StringName = &"") -> void:
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
	if not equipment_animation_enabled:
		return
	# 命中停帧：保持命中瞬间的姿态，暂停本地 ActionPivot 动画采样。
	# 仅视觉冻结，不暂停 SceneTree / 不延迟服务器伤害 / 不冻结敌人。
	if _hit_stop_remaining_sec > 0.0:
		return
	animator.sample_action(action_name, normalized_progress)

func play_action(action_name: StringName, custom_speed: float = 1.0) -> void:
	if not equipment_animation_enabled:
		return
	_queued_action_generation += 1
	if _is_release_action(action_name):
		begin_weapon_release(action_name)
	animator.play_action(action_name, custom_speed)
	_apply_equipment_recoil_for_action(action_name)

## Queues a purely visual follow-up without introducing a transform-writing Tween.
func play_action_after(action_name: StringName, delay_sec: float, custom_speed: float = 1.0) -> void:
	if not equipment_animation_enabled:
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
	if reset_pose and is_instance_valid(shield_action_pivot):
		shield_action_pivot.transform = Transform3D.IDENTITY
	if reset_pose and is_instance_valid(shield_impact_pivot):
		shield_impact_pivot.transform = Transform3D.IDENTITY
	if reset_pose:
		equipment_motion.clear_shield_impact()
	if reset_pose and is_instance_valid(shield_orientation):
		shield_orientation.transform = Transform3D.IDENTITY
	if reset_pose:
		var reset_action := resolve_hold_action() if _current_weapon_data != null else &"vm_idle"
		animator.sample_action(reset_action, 0.0)
	if reset_pose and is_instance_valid(weapon_socket) and _current_weapon_data != null:
		# A thrust may animate the socket itself so the sword rotates around the
		# grip.  Restore the authored mount after cancellation/recovery.
		_apply_weapon_mount_pose(resolve_weapon_profile(_current_weapon_data))


func _apply_equipment_recoil_for_action(action_name: StringName) -> void:
	match action_name:
		&"vm_crossbow_fire":
			equipment_motion.add_recoil(1.0, 0.10)
		&"vm_bow_release":
			equipment_motion.add_recoil(0.36, -0.06)
		&"vm_staff_attack", &"vm_wand_cast":
			equipment_motion.add_recoil(0.32, 0.08)
		&"vm_grimoire_attack":
			equipment_motion.add_recoil(0.26, -0.08)

func _is_release_action(action_name: StringName) -> bool:
	var action_text := String(action_name)
	var canonical := action_text.trim_prefix("vm_")
	return canonical.ends_with("_attack") or canonical.ends_with("_heavy_swing") or canonical in [
		"claw_swipe", "bash_shield", "bow_release", "crossbow_fire",
		"shortsword_thrust", "sword_slash", "slash_one_hand", "slash_heavy",
		"stab_dagger", "thrust_spear", "wand_cast",
	]

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
