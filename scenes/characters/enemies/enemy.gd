class_name Enemy
extends CharacterBody3D

signal dead(death_transform: Transform3D)
signal screamed

const DURATION_RAGDOLL_SIMULATION := 3.0
const GRAVITY := 20.0
const HITBOX_BUILDER := preload("res://globals/combat/combat_hitbox_builder.gd")
const PHYSICAL_IMPACT := preload("res://globals/combat/physical_impact_resolver.gd")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const VOXEL_RAGDOLL := preload("res://scenes/characters/component/voxel_ragdoll.gd")
const ENEMY_TARGETING := preload("res://scenes/characters/enemies/behavior/enemy_targeting.gd")
const ENEMY_MOVEMENT_CONTROLLER := preload("res://scenes/characters/enemies/behavior/enemy_movement_controller.gd")
const SES := preload("res://globals/combat/status_effect_system.gd")
const Service := preload("res://globals/core/service.gd")
const COMBAT_PROGRESSION := preload("res://globals/combat/combat_progression.gd")
const DEFAULT_DETECTION_RANGE := 5.0
## 满暗蚀全图追击倍率：补偿远距出生点与低速敌人的长距离追击时间。
const DARK_EROSION_HUNT_SPEED_MULTIPLIER := 4.0
## 视野射线高度（米）：从角色中心质量发射，避免贴地射线漏检矮墙
const LOS_RAY_HEIGHT := 0.85
## 怪物渲染优化：网格最远可见距离（米）。配合既有 24m 流式半径进一步远裁剪，避免远处怪物空耗 draw call。
const ENEMY_VISIBILITY_RANGE_END := 36.0
## 怪物独立视觉层（第 2 层）：主相机可见，但玩家视野补光只作用于第 1 层地形。
const ENEMY_RENDER_LAYER := 1 << 1
## 近距离阈值（米）：此距离内的怪物无视视锥始终渲染并播放动画，避免屏幕边缘近怪闪烁。
const ENEMY_NEAR_ANIM_DISTANCE := 8.0
## 离屏/远距优化轮询间隔（秒），避免每帧对每个怪物做视锥检测。
const RENDER_OPT_INTERVAL := 0.2
## 视野射线检测节流间隔（秒）：物理射线较贵，缓存结果，最多每 0.2s 重测一次。
## 仅影响"初次发现玩家"的索敌延迟，已登记玩家不依赖此检测，不影响追击手感。
const LOS_INTERVAL := 0.2
## 敌人 imposter LOD 距离（米）：超过此距离且处于 MOVING 状态则隐藏蒙皮网格、改用 Sprite3D billboard 替身，
## 省 CPU 蒙皮 + draw call（对齐 Barony 远敌换贴片）。近处/攻击等非 MOVING 状态仍用完整骨架网格以保留可读招式。
const ENEMY_IMPOSTER_LOD_DISTANCE := 12.0
## AI 模拟半径（米）：与 imposter LOD 边界对齐。超过此距离且未与玩家交战（未登记）的敌人
## 视为"远距替身带"，跳过巡逻/索敌等寻路 AI，仅保留物理静止。避免对玩家看不见的 18–36m 敌人
## 空算 A* 与导航查询（P-C：把 AI 半径从 ~36m 物理激活半径解耦到 LOD 边界）。
const AI_SIM_RADIUS_M := 18.0
## imposter 截图分辨率（正方形像素）
const ENEMY_IMPOSTER_CAPTURE_SIZE := 256
## 已生成的 billboard 纸片优先于运行时 3D 截图；角色素材按敌人基础类型独立注册。
const AUTHORED_IMPOSTER_TEXTURES := {
	"goblin": "res://assets/textures/enemies/goblin_billboard_4x4.png",
}

## 每种敌人只捕获一次 imposter；同批刷新的同类实例等待首个捕获任务并共享贴图。
static var _imposter_texture_cache: Dictionary = {}
static var _imposter_capture_in_flight: Dictionary = {}

@onready var action_audio_stream_player: AudioStreamPlayer3D = %ActionAudioStreamPlayer
@onready var animation_player: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var equipment: EquipmentComponent = %EquipmentComponent
@onready var health: HealthComponent = %HealthComponent
@onready var nav_agent: NavigationAgent3D = %NavigationAgent3D
@onready var skeleton_simulator: PhysicalBoneSimulator3D = _find_physical_bone_simulator()
@onready var physical_bone_head: PhysicalBone3D = _find_physical_bone("Physical Bone Head")
@onready var physical_bone_torso: PhysicalBone3D = _find_physical_bone("Physical Bone Torso")
## 死亡碎裂（伪布娃娃）组件。所有敌人在 _ready 中均创建此组件，
## 死亡时优先使用体素碎裂效果（VoxelRagdoll），骨骼布娃娃（skeleton_simulator）仅作回退。
var voxel_ragdoll: VoxelRagdoll = null
@onready var player_detection_area: Area3D = %PlayerDetectionArea
@onready var player_detection_shape: CollisionShape3D = %PlayerDetectionArea/CollisionShape3D
@onready var vocal_audio_stream_player: AudioStreamPlayer3D = %VocalAudioStreamPlayer
@onready var weapon_reach_raycast: RayCast3D = %WeaponReachRaycast

@export var duration_between_attacks: int
@export var duration_stun : int
## Attack telegraph duration before the weapon hit window starts.
@export_range(0.0, 2.0, 0.05) var attack_windup_seconds: float = 0.5
var _player: Player = null
@export var player: Player:
	get:
		return _player
	set(value):
		_player = value
		if _targeting != null:
			_targeting.observe_external_target(value)
@export var speed: float
@export var is_elite: bool = false
@export var is_boss_type: bool = false
## 0 表示按最终最大生命值自动计算；正数用于特殊怪物显式覆写。
@export_range(0, 100000, 1) var experience_reward: int = 0
@export_enum("small", "medium", "large", "huge") var body_size: String = "medium"
## 巡逻半径（米），无玩家时在此范围内随机巡逻
@export var patrol_radius: float = 5.0
## 统一索敌距离（米）。100% 暗蚀会绕过此限制强制追击。
@export var detection_range: float = DEFAULT_DETECTION_RANGE
## 水平视野半角；默认 60°，即正前方 120° 视野锥。
@export_range(1.0, 179.0, 1.0) var vision_half_angle_degrees: float = 60.0
## 攻击模式：人形怪物使用装备武器，非人形怪物使用身体攻击。
const ATTACK_MODE_WEAPON := "weapon"
const ATTACK_MODE_BODY := "body"
@export_enum("weapon", "body") var attack_mode: String = ATTACK_MODE_WEAPON
## 非人形身体攻击的有效距离，不读取 WeaponData.reach。
@export var body_attack_reach: float = 1.25
## 基础材质覆盖（已废弃：保留属性向后兼容场景文件，不再用于 material_override）。
## GLB 内嵌纹理由 VoxelLightingAdapter 统一适配（toon 着色 + vertex_color_use_as_albedo），
## 无需手动覆写。早期添加此属性是为了“修复纯白问题”，但实际原因是 GLB 材质未开启
## vertex_color_use_as_albedo，VOXEL_LIGHTING 已正确处理此问题。
@export var base_material: Material


## 敌人状态机枚举。LAUNCHED 为致命击退飞行态（延迟死亡）。
enum State {MOVING, IMPALING, DYING, DEAD, SLASHING, HURT, BLOCKING, STUNNED, LAUNCHED}

var pushback_force := Vector3.ZERO
var state: State
var state_node: EnemyState
var _targeting: RefCounted = null
var movement_controller: RefCounted = null
var time_since_last_attack: int
var combat_debuffs: Dictionary = {}
var physical_impact_enabled: bool = false
var physical_impact_damage_mult: float = 1.0
var physical_impact_min_speed: float = 4.0
var physical_impact_full_speed: float = 14.0
var _last_physical_impact_msec: int = -100000
## 出生位置，巡逻时以此为中心
var spawn_position: Vector3 = Vector3.ZERO
## 收集到的可视网格（用于离屏剔除/冻结动画）
var _visual_meshes: Array[MeshInstance3D] = []
## 离屏/远距优化节流计时
var _render_opt_timer := 0.0
var _los_cache_timer := 0.0
var _los_cache_result := false
## imposter 替身 Sprite3D（优先使用 authored billboard，缺少时才运行时截图）。
var _imposter_sprite: Sprite3D = null
var _imposter_texture_ready := false
## 是否已切到远处 LOD（隐藏蒙皮、显示替身）
var _lod_is_far := false
## 死亡碎裂已激活：激活后 LOD 系统不再修改原始网格可见性，避免碎裂后原模型重新显示。
var _death_ragdoll_active := false
var _normal_collision_mask := 0
## Multiple hitbox/physics callbacks can request the same death in one frame.
## Keep the transition deferred and idempotent so DYING is entered once.
var _death_transition_queued := false
## 与 AI 当前追击目标分离，只记录最近一次有效玩家伤害来源。
var kill_credit_player: Player = null
var _experience_awarded := false

func _find_physical_bone_simulator() -> PhysicalBoneSimulator3D:
	return find_child("PhysicalBoneSimulator3D", true, false) as PhysicalBoneSimulator3D

func _find_physical_bone(node_name: String) -> PhysicalBone3D:
	return find_child(node_name, true, false) as PhysicalBone3D

func _remove_unused_physical_bones() -> void:
	if skeleton_simulator == null:
		return
	# 所有敌人死亡表现都由 VoxelRagdoll 负责；遗留物理骨没有任何运行时用途。
	# 仅设 active=false/layer=0 仍会为每只继承 goblin 场景的敌人保留 10 个 Body RID
	# 和 10 个 Joint RID。立即 detach + free 才能从 PhysicsServer 彻底移除这些资源。
	var obsolete_simulator := skeleton_simulator
	skeleton_simulator = null
	physical_bone_head = null
	physical_bone_torso = null
	obsolete_simulator.active = false
	var parent := obsolete_simulator.get_parent()
	if parent != null:
		parent.remove_child(obsolete_simulator)
	obsolete_simulator.free()

func _ready() -> void:
	_targeting = ENEMY_TARGETING.new(self)
	PhysicsSetup.setup_enemy(self)
	_normal_collision_mask = collision_mask
	_configure_navigation_agent()
	VOXEL_LIGHTING.apply_to_tree(self, true)
	add_to_group("enemies")
	_configure_detection_range()
	_apply_spawner_multipliers()
	_ensure_weapon_loadout()
	# 移除 3D 血条后，屏幕顶部 EnemyHealthBar HUD 已直接读取 enemy.health 显示血量，
	# 此处不再驱动 3D 血条刷新。
	_collect_visual_meshes()
	_apply_visibility_range()
	_build_imposter_sprite()
	_update_render_optimization()
	# 所有敌人均挂载死亡碎裂（伪布娃娃）组件。场景中的遗留 PhysicalBone 节点
	# 不参与动画或死亡表现，进入树后立即释放其 Body/Joint RID。
	_remove_unused_physical_bones()
	voxel_ragdoll = VOXEL_RAGDOLL.new()
	add_child(voxel_ragdoll)
	spawn_position = global_position
	if has_meta("spawn_pos"):
		var configured_spawn: Variant = get_meta("spawn_pos")
		if configured_spawn is Vector3:
			spawn_position = configured_spawn
			global_position = configured_spawn
	if has_meta("patrol_center"):
		var configured_patrol_center: Variant = get_meta("patrol_center")
		if configured_patrol_center is Vector3:
			spawn_position = configured_patrol_center
	if has_meta("patrol_radius"):
		patrol_radius = maxf(float(get_meta("patrol_radius", patrol_radius)), 1.0)
	switch_state(State.MOVING)

func _configure_navigation_agent() -> void:
	if nav_agent == null or collision_shape == null:
		return
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return
	# PhysicsSetup 已按 body_size 统一了实际碰撞胶囊；导航代理必须使用同一包络，
	# 否则代理会贴墙或钻入角落时才被物理碰撞纠正。
	nav_agent.radius = capsule.radius + capsule.margin
	nav_agent.height = capsule.height
	# 烘焙导航点位于角色脚底上方约半格；若阈值恰好等于该垂直差，
	# get_next_path_position() 会一直返回当前位置的 waypoint，造成有路径但零速。
	nav_agent.path_desired_distance = maxf(nav_agent.path_desired_distance, 0.75)
	# Godot 代理会反向应用此偏移：+0.5 将导航点从 y=0.5 对齐到脚底 y=0，
	# 避免水平 waypoint 被垂直差卡住。
	nav_agent.path_height_offset = 0.5
	movement_controller = ENEMY_MOVEMENT_CONTROLLER.new(self, nav_agent)
	movement_controller.configure()
	# 流式注册可能发生在 _ready 之前；此时 controller 已把 meta 设为 false，
	# 但 movement_controller 尚不存在。创建后必须补同步，避免远敌重新以默认 true 注册 RVO。
	movement_controller.set_streaming_active(bool(get_meta("stream_physics_active")) \
		if has_meta("stream_physics_active") else true)

func _configure_detection_range() -> void:
	if player_detection_shape != null:
		var sphere := player_detection_shape.shape as SphereShape3D
		if sphere != null:
			sphere = sphere.duplicate() as SphereShape3D
			sphere.radius = detection_range
			player_detection_shape.shape = sphere
	if player_detection_area != null:
		# MOVING 状态已用距离、视野锥和节流 LOS 主动感知玩家。保留节点供场景和
		# 测试兼容，但退出 PhysicsServer broadphase，避免每只活跃敌人常驻一个 Area3D。
		player_detection_area.monitoring = false
		player_detection_area.monitorable = false
		player_detection_area.collision_layer = 0
		player_detection_area.collision_mask = 0

## 应用 DungeonSpawner 通过 meta 注入的属性倍率（hp_mult / speed_mult / dmg_mult）
func _apply_spawner_multipliers() -> void:
	# player_ref 仅是生成器提供的候选玩家引用，不代表敌人已经看见或交战。
	# 真正目标由 should_chase_player 的距离/视野/LOS 或受击/满暗蚀路径登记。
	if has_meta("hp_mult"):
		var hp_mult: float = float(get_meta("hp_mult", 1.0))
		health.max_life = int(health.max_life * hp_mult)
		health.current_life = health.max_life
	if has_meta("speed_mult"):
		var spd_mult: float = float(get_meta("speed_mult", 1.0))
		speed *= spd_mult
	if movement_controller != null:
		movement_controller.set_max_speed(speed)
	if has_meta("is_boss_type"):
		is_boss_type = bool(get_meta("is_boss_type", false))
	if has_meta("body_size"):
		body_size = String(get_meta("body_size", "medium"))
	if has_meta("attack_mode"):
		var configured_attack_mode := String(get_meta("attack_mode", ATTACK_MODE_WEAPON))
		if configured_attack_mode in [ATTACK_MODE_WEAPON, ATTACK_MODE_BODY]:
			attack_mode = configured_attack_mode

func _ensure_weapon_loadout() -> void:
	if attack_mode != ATTACK_MODE_WEAPON or equipment == null:
		return
	var current_data: WeaponData = equipment.weapon_data
	var configured_id := String(get_meta("weapon_id", ""))
	var data: WeaponData = null
	if not configured_id.is_empty():
		data = WeaponRegistry.get_weapon_data(configured_id)
	elif current_data != null:
		data = WeaponRegistry.resolve_weapon_data(current_data)
	if data == null:
		data = WeaponRegistry.get_weapon_data("shortsword")
	if data == null:
		return
	var current_id := String(current_data.id) if current_data != null else ""
	if current_data == null or current_id != String(data.id) or not equipment.has_weapon():
		equipment.configure_weapon_slot(0, data, true)

## 收集角色可视网格，供离屏剔除与远距冻结使用。
## 不再覆写 material_override：GLB 内嵌纹理由 VOXEL_LIGHTING.apply_to_tree 统一适配
## （toon 着色 + vertex_color_use_as_albedo），保留原始纹理外观。
func _collect_visual_meshes() -> void:
	_visual_meshes.clear()
	var root := get_node_or_null("character")
	var base: Node = root if root != null else self
	for child in base.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		mesh.layers = ENEMY_RENDER_LAYER
		_visual_meshes.append(mesh)


## 设置网格最远可见距离，配合既有 24m 流式半径进一步远裁剪，避免远处怪物空耗 draw call。
func _apply_visibility_range() -> void:
	for m in _visual_meshes:
		if is_instance_valid(m):
			m.visibility_range_end = ENEMY_VISIBILITY_RANGE_END
			m.visibility_range_end_margin = 8.0

## 离屏/远距优化：远离相机视野或超出近距离阈值的怪物冻结动画，节省 CPU 蒙皮开销。
## DYING/DEAD 及非 MOVING（攻击/受击）状态不冻结，避免打断 await animation_finished 的状态机。
func _update_render_optimization() -> void:
	if state == State.DYING or state == State.DEAD:
		_set_animation_paused(false)
		_set_lod_far(false)
		return
	# P1-5：统一目标解析（已登记玩家 → 会话注册表 → player_ref → 单机全局）。
	var target: Node = _resolve_target_player()
	if target == null or not is_instance_valid(target) or not target is Node3D or not target.is_inside_tree():
		_set_animation_paused(false)
		_set_lod_far(false)
		return
	var cam = target.get("camera") if "camera" in target else null
	var cam3d := (cam as Camera3D) if (cam != null and is_instance_valid(cam)) else null
	var dist := global_position.distance_to(target.global_position)
	var in_view := cam3d != null and cam3d.is_position_in_frustum(global_position)
	# 非移动状态（攻击/受击等）始终播放，避免冻结破坏状态机 await；
	# 移动状态仅在视野内或近距离内播放，其余冻结。
	var should_animate := state != State.MOVING or in_view or dist <= ENEMY_NEAR_ANIM_DISTANCE
	_set_animation_paused(not should_animate)
	# P3 距离 LOD：仅 MOVING 状态的远处敌人隐藏蒙皮网格、显示 imposter 替身（省 CPU 蒙皮 + draw call）。
	# 攻击/受击等非 MOVING 状态始终用完整骨架网格，保留可读招式；近处敌人同样用完整网格。
	var lod_far := _imposter_texture_ready and dist > ENEMY_IMPOSTER_LOD_DISTANCE and state == State.MOVING
	_set_lod_far(lod_far)

func _set_animation_paused(paused: bool) -> void:
	if animation_player == null:
		return
	animation_player.speed_scale = 0.0 if paused else 1.0

## 切换远距 LOD：隐藏/恢复蒙皮网格，并显示/隐藏 imposter 替身。
## _visual_meshes 仅含 MeshInstance3D（碰撞/物理体不在其中，不受影响）。
func _set_lod_far(far: bool) -> void:
	if far == _lod_is_far:
		return
	_lod_is_far = far
	# 死亡碎裂已激活时，原始网格可见性由 VoxelRagdoll 管理（已隐藏），LOD 不再干预。
	if not _death_ragdoll_active:
		for m in _visual_meshes:
			if is_instance_valid(m):
				m.visible = not far
	if _imposter_sprite != null:
		_imposter_sprite.visible = far and _imposter_texture_ready

## 创建 imposter 替身 Sprite3D（billboard）。
## 节点本身始终创建（便于 LOD 切换在 headless 测试下也可断言）。
func _build_imposter_sprite() -> void:
	_imposter_sprite = Sprite3D.new()
	_imposter_sprite.name = "ImposterSprite"
	_imposter_sprite.billboard = 1  # Sprite3D.BillboardMode.ENABLED (Godot 4.7 不暴露该枚举常量名，0=Disabled/1=Enabled/2=Y-Billboard)
	_imposter_sprite.centered = true
	_imposter_sprite.position = Vector3(0.0, 1.15, 0.0)
	_imposter_sprite.pixel_size = 0.009
	_imposter_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_imposter_sprite.shaded = true
	_imposter_sprite.layers = ENEMY_RENDER_LAYER
	_imposter_sprite.visibility_range_end = 120.0
	_imposter_sprite.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_imposter_sprite.visible = false
	add_child(_imposter_sprite)
	_build_imposter_texture()

## 优先加载 authored 纸片素材；没有素材时才用子 Viewport 从前视角生成运行时回退贴图。
## headless 无 GPU 截图时只跳过运行时回退，已注册的 authored 贴片仍可正常加载。
func _build_imposter_texture() -> void:
	if _imposter_sprite == null:
		return
	var authored_path := String(AUTHORED_IMPOSTER_TEXTURES.get(_imposter_cache_key(), ""))
	if not authored_path.is_empty():
		var authored_texture := load(authored_path) as Texture2D
		if authored_texture != null:
			_set_imposter_texture(authored_texture, 4, 4)
			return
	# headless 检测：--headless 会被引擎从 OS.get_cmdline_args() 消费掉，
	# OS.has_feature("headless") 在 gdUnit 上下文也不可靠，唯有 DisplayServer 名称可靠。
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		return
	if Engine.is_editor_hint():
		return
	var cache_key := _imposter_cache_key()
	var cached_texture = _imposter_texture_cache.get(cache_key)
	if cached_texture is Texture2D:
		_set_imposter_texture(cached_texture)
		return
	if _imposter_capture_in_flight.has(cache_key):
		await _wait_for_shared_imposter(cache_key)
		return
	_imposter_capture_in_flight[cache_key] = true
	var vp := SubViewport.new()
	vp.size = Vector2(ENEMY_IMPOSTER_CAPTURE_SIZE, ENEMY_IMPOSTER_CAPTURE_SIZE)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.transparent_bg = true
	var capture_environment := Environment.new()
	capture_environment.background_mode = Environment.BG_COLOR
	capture_environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	capture_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	capture_environment.ambient_light_color = Color(0.65, 0.7, 0.78)
	capture_environment.ambient_light_energy = 0.9
	var capture_world_environment := WorldEnvironment.new()
	capture_world_environment.environment = capture_environment
	vp.add_child(capture_world_environment)
	var capture_light := DirectionalLight3D.new()
	capture_light.light_energy = 1.3
	capture_light.look_at_from_position(Vector3(-3.0, 5.0, -4.0), Vector3(0.0, 0.8, 0.0), Vector3.UP)
	vp.add_child(capture_light)
	var cam := Camera3D.new()
	cam.cull_mask = ENEMY_RENDER_LAYER
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 35.0
	cam.position = Vector3(0.0, 1.0, -2.6)
	# 相机尚未加入 SubViewport 场景树；使用 position 版本避免 Node3D.look_at 的入树要求。
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.9, 0.0), Vector3(0, 1, 0))
	vp.add_child(cam)
	cam.make_current()
	var src := get_node_or_null("character")
	if src != null:
		var clone := src.duplicate()
		_strip_clone_for_capture(clone)
		vp.add_child(clone)
	add_child(vp)
	# 等两帧让子 Viewport 完成一次渲染，再抓取贴图。
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_instance_valid(vp) or _imposter_sprite == null:
		_imposter_capture_in_flight.erase(cache_key)
		if is_instance_valid(vp):
			vp.queue_free()
		return
	var captured_texture: ImageTexture = null
	var vt := vp.get_texture()
	if vt != null:
		var img := vt.get_image()
		if img != null:
			captured_texture = ImageTexture.create_from_image(img)
	vp.queue_free()
	_finish_imposter_capture(cache_key, captured_texture)

func _imposter_cache_key() -> String:
	var base_type := String(get_meta("enemy_base_type", ""))
	if not base_type.is_empty():
		return base_type
	if not scene_file_path.is_empty():
		return scene_file_path
	var character_root := get_node_or_null("character")
	if character_root != null and not character_root.scene_file_path.is_empty():
		return character_root.scene_file_path
	return String(get_script().resource_path)

func _wait_for_shared_imposter(cache_key: String) -> void:
	while _imposter_capture_in_flight.has(cache_key):
		if not is_inside_tree():
			return
		await get_tree().process_frame
	var cached_texture = _imposter_texture_cache.get(cache_key)
	if cached_texture is Texture2D and _imposter_sprite != null:
		_set_imposter_texture(cached_texture)

func _finish_imposter_capture(cache_key: String, texture: ImageTexture) -> void:
	_imposter_capture_in_flight.erase(cache_key)
	if texture != null:
		_imposter_texture_cache[cache_key] = texture
		_set_imposter_texture(texture)

func _set_imposter_texture(texture: Texture2D, hframes: int = 1, vframes: int = 1) -> void:
	if texture == null or _imposter_sprite == null:
		return
	_imposter_sprite.texture = texture
	_imposter_sprite.hframes = hframes
	_imposter_sprite.vframes = vframes
	_imposter_sprite.frame = 0
	var frame_height := float(texture.get_height()) / float(maxi(vframes, 1))
	var target_height := 1.7
	match body_size:
		"small":
			target_height = 0.85
		"large":
			target_height = 2.21
		"huge":
			target_height = 2.72
	_imposter_sprite.pixel_size = target_height / frame_height
	_imposter_sprite.position.y = target_height * 0.5
	_imposter_texture_ready = true

## 截图用的克隆体只保留骨架 + 蒙皮网格，移除灯光/粒子/音频/碰撞/物理骨等无关节点，得到干净剪影。
func _strip_clone_for_capture(node: Node) -> void:
	for child in node.get_children():
		if child is OmniLight3D or child is GPUParticles3D or child is AudioStreamPlayer3D \
				or child is Area3D or child is CollisionShape3D or child is CollisionPolygon3D \
				or child is PhysicalBoneSimulator3D or child is PhysicalBone3D:
			child.queue_free()
		else:
			_strip_clone_for_capture(child)

func _process(delta: float) -> void:
	# 无状态效果时跳过两次空 Dictionary keys() 扫描。远距休眠敌人仍会由
	# streaming 停止 _process；已激活但无 debuff 的常态敌人也不再承担空状态开销。
	if not combat_debuffs.is_empty():
		_tick_combat_debuffs(delta)
		SES.process_tick(self, delta)
	if _targeting != null and _targeting.has_pending_memory():
		_targeting.tick(delta)
	_render_opt_timer -= delta
	if _render_opt_timer <= 0.0:
		_render_opt_timer = RENDER_OPT_INTERVAL
		_update_render_optimization()
	_los_cache_timer = maxf(0.0, _los_cache_timer - delta)

func prepare_attack_hitbox(target_mask: int) -> Area3D:
	var attach_to := _get_active_attack_hitbox_parent()
	return HITBOX_BUILDER.ensure_hitbox(self, attach_to, _get_active_attack_reach(), target_mask)

func set_attack_hitbox_active(hitbox: Area3D, active: bool) -> void:
	HITBOX_BUILDER.set_active(hitbox, active)

func _get_active_attack_hitbox_parent() -> Node3D:
	if not uses_weapon_attack() or equipment == null or equipment.weapon_placeholder == null:
		return null
	if equipment.weapon_placeholder.get_child_count() == 0:
		return null
	return equipment.weapon_placeholder.get_child(0) as Node3D

func _get_active_attack_reach() -> float:
	if attack_mode == ATTACK_MODE_BODY:
		return maxf(body_attack_reach, 0.8)
	if weapon_reach_raycast != null:
		return maxf(absf(weapon_reach_raycast.target_position.z), 0.8)
	var weapon := equipment.weapon_data if equipment != null and equipment.has_weapon() else null
	return maxf(weapon.reach * CombatHitboxBuilder.REACH_SCALE, 0.8) if weapon != null else 1.2

func uses_weapon_attack() -> bool:
	return attack_mode == ATTACK_MODE_WEAPON and equipment != null and equipment.has_weapon()

## 敌人类型 id（供攻击招式档案/图鉴查询）：
## 生成器注入的 enemy_base_type 优先（精英带 elite_ 前缀），回退到场景文件名。
func get_enemy_type_id() -> String:
	if has_meta("enemy_base_type"):
		var base_type := String(get_meta("enemy_base_type"))
		if not base_type.is_empty():
			return base_type
	if not scene_file_path.is_empty():
		return scene_file_path.get_file().get_basename()
	return ""

func get_attack_weapon() -> WeaponData:
	return equipment.weapon_data if uses_weapon_attack() else null
	
func switch_state(new_state: State, data: EnemyStateData = EnemyStateData.new()) -> void:
	if new_state != State.MOVING:
		stop_navigation()
	if state_node != null and is_instance_valid(state_node):
		# The previous state is freed at the end of the frame. Disable it now so
		# its physics loop cannot run after a re-entrant combat transition.
		state_node.set_process(false)
		state_node.set_physics_process(false)
		state_node.queue_free()
	var state_map := {
		State.BLOCKING: EnemyStateBlocking,
		State.DEAD: EnemyStateDead,
		State.DYING: EnemyStateDying,
		State.HURT: EnemyStateHurt,
		State.IMPALING: EnemyStateImpaling,
		State.LAUNCHED: EnemyStateLaunched,
		State.MOVING: EnemyStateMoving,
		State.SLASHING: EnemyStateSlashing,
		State.STUNNED: EnemyStateStunned,
	}
	var next_state_node: EnemyState = state_map[new_state].new(self, data)
	next_state_node.transition_requested.connect(switch_state)
	next_state_node.name = "State: " + State.keys()[new_state]
	state = new_state
	state_node = next_state_node
	# Use the local node. _enter_tree() may synchronously request another state;
	# reading the mutable state_node property here would add the replacement node
	# a second time and leave the original transition half-applied.
	add_child(next_state_node)

## 进入致命击退飞行态（LAUNCHED）。
## 供 EnemyStateHurt 等外部状态文件调用，避免它们直接引用 Enemy.State.LAUNCHED
## 而触发 Enemy ↔ EnemyState 循环依赖导致的枚举成员解析失败。
func enter_launched_state(data: EnemyStateData) -> void:
	switch_state(State.LAUNCHED, data)


## Queue death outside the current physics callback. Death effects add and
## impulse visual bodies, so entering DYING synchronously is unsafe.
func request_death(data: EnemyStateData = EnemyStateData.new(), bypass_can_die: bool = false) -> void:
	if not is_instance_valid(self) or state_node == null or not is_instance_valid(state_node):
		return
	if state == State.DYING or state == State.DEAD or _death_transition_queued:
		return
	if not bypass_can_die and (state_node.is_queued_for_deletion() or not state_node.can_die()):
		return
	# 经验结算不能依赖 DYING 状态节点的延迟副作用：chunk 流送可能在同一窗口
	# 暂停状态节点的 process，导致死亡特效/掉落尚未执行时奖励丢失。此处只会
	# 为已登记且仍是本机当前玩家的有效击杀结算一次；死亡状态保留幂等兜底调用。
	award_kill_experience()
	_death_transition_queued = true
	call_deferred("_deferred_switch_to_dying", data, bypass_can_die)

func register_kill_credit(source_player: Player, damage_applied: bool = true) -> void:
	if damage_applied and source_player != null and is_instance_valid(source_player):
		kill_credit_player = source_player

## 默认经验随怪物最终生命成长；精英 1.5 倍，Boss 3 倍。
func get_experience_reward() -> int:
	if experience_reward > 0:
		return experience_reward
	var max_life := health.max_life if health != null else 1
	var reward := maxi(10, max_life * 2)
	if is_boss_type or bool(get_meta("is_boss_type", false)) or bool(get_meta("is_boss", false)):
		reward = int(ceil(float(reward) * 3.0))
	elif is_elite or bool(get_meta("is_elite", false)):
		reward = int(ceil(float(reward) * 1.5))
	return reward

## 只向本机当前玩家的属性上下文结算一次；联机权威击杀由服务器会话处理。
func award_kill_experience() -> int:
	if _experience_awarded or kill_credit_player == null or not is_instance_valid(kill_credit_player):
		return 0
	var gs := Service.game_state()
	if gs == null or gs.current_player != kill_credit_player:
		return 0
	var context = gs.player_context() if gs.has_method("player_context") else null
	var attributes: Node = context.attributes if context != null else Service.attr_panel()
	if attributes == null or not attributes.has_method("accumulate_level_exp"):
		return 0
	_experience_awarded = true
	var reward := get_experience_reward()
	attributes.accumulate_level_exp(reward)
	return reward

func impale(thrown_item: ThrownItem, item_basis: Basis) -> void:
	var can_be_impaled := state_node.can_get_hurt()
	if thrown_item != null and thrown_item.source is Player:
		register_kill_credit(thrown_item.source as Player, can_be_impaled)
		if can_be_impaled and thrown_item.weapon_data != null:
			var effective_damage := health.current_life if health != null else 0
			COMBAT_PROGRESSION.award_player_damage(
				thrown_item.source,
				thrown_item.weapon_data.proficiency_key,
				"ranged",
				effective_damage
			)
	var state_data := EnemyStateData.new().set_thrown_item(thrown_item).set_thrown_item_basis(item_basis)
	if can_be_impaled:
		switch_state(State.IMPALING, state_data)
	else:
		var hit_direction := thrown_item.global_position.direction_to(global_position)
		state_data.set_impact_direction(hit_direction)
		switch_state(State.BLOCKING, state_data)
	screamed.emit()

func try_receive_furniture_impact(thrown_item: ThrownItem) -> void:
	var blocked_by_shield := equipment.has_shield()
	if thrown_item != null and thrown_item.source is Player:
		register_kill_credit(thrown_item.source as Player, not blocked_by_shield)
	if blocked_by_shield:
		equipment.drop_shield()
		var hit_direction := thrown_item.global_position.direction_to(global_position)
		var data := EnemyStateData.new().set_impact_direction(hit_direction).set_knockback_force(2.5)
		switch_state(State.STUNNED, data)
	else:
		request_death()

func try_receive_thrown_enemy_impact(source_enemy: Enemy, source_player: Player = null) -> void:
	var blocked_by_shield := equipment.has_shield()
	if source_player != null:
		player = source_player
		register_kill_credit(source_player, not blocked_by_shield)
	screamed.emit()
	var hit_direction := source_enemy.global_position.direction_to(global_position) if source_enemy != null else Vector3.ZERO
	var data := EnemyStateData.new().set_damage(6).set_impact_direction(hit_direction).set_knockback_force(5.0)
	if blocked_by_shield:
		equipment.drop_shield()
		switch_state(State.STUNNED, data)
	else:
		switch_state(State.HURT, data)

func has_registered_player() -> bool:
	return player != null and is_instance_valid(player)

## P1-5：目标玩家唯一解析（替代裸读 GameState.current_player）。
## 优先级：已登记交战玩家 player → 会话注册表（player_peer_id 锚定，联机 per-peer）→
## 生成器候选 player_ref → 单机全局 current_player（resolve_player_node(0)）。
func _resolve_target_player() -> Node:
	if has_registered_player():
		return player
	var peer_id: int = int(get_meta("player_peer_id", 0))
	if peer_id > 0:
		var resolved: Node = GameState.resolve_player_node(peer_id)
		if resolved != null and is_instance_valid(resolved):
			return resolved
	if has_meta("player_ref"):
		var ref := get_meta("player_ref") as Node
		if ref != null and is_instance_valid(ref):
			return ref
	return GameState.resolve_player_node(0)

## 是否应运行完整 AI（索敌/巡逻/寻路）本帧。
## 已与玩家交战（已登记 player）、或受暗蚀强制追击、或玩家进入 AI_SIM_RADIUS_M 内的敌人返回 true；
## 远距未交战的替身带敌人返回 false，其 MOVING 状态将跳过寻路 AI 仅保持物理静止（P-C）。
func is_ai_active() -> bool:
	_sync_dark_erosion_collision_mode()
	if bool(get_meta("dark_erosion_hunt", false)):
		return true
	# 受击或实际发现后登记的目标在短时离开 AI 半径时仍保持追击；生成器的
	# player_ref 不写入 player，因此不会让全地图敌人从出生起永久运行 AI。
	if has_registered_player():
		return true
	# P1-5：统一目标解析（会话注册表 / player_ref / 单机全局）。
	var target: Node = _resolve_target_player()
	if target == null or not is_instance_valid(target):
		# 场景中无玩家（出生点/加载/纯巡逻场景）：保留出生点巡逻，
		# 与 enemy.gd "巡逻半径（米），无玩家时在此范围内随机巡逻" 的文档契约一致。
		return true
	return global_position.distance_squared_to(target.global_position) <= AI_SIM_RADIUS_M * AI_SIM_RADIUS_M

func is_target_in_facing_cone(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var offset := target.global_position - global_position
	offset.y = 0.0
	if offset.length_squared() <= 0.000001:
		return true
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.000001:
		return false
	return forward.normalized().dot(offset.normalized()) >= cos(deg_to_rad(vision_half_angle_degrees))

func is_target_visible() -> bool:
	return _targeting != null and _targeting.is_visible()

func has_navigation_target() -> bool:
	return _targeting != null and _targeting.has_navigation_goal()

func get_navigation_target_position() -> Vector3:
	return _targeting.navigation_target_position() if _targeting != null else global_position

func submit_navigation_velocity(value: Vector3) -> void:
	if movement_controller != null:
		movement_controller.submit_desired_velocity(value)
	else:
		velocity.x = value.x
		velocity.z = value.z

func stop_navigation() -> void:
	submit_navigation_velocity(Vector3.ZERO)

func apply_navigation_safe_velocity(value: Vector3) -> void:
	if movement_controller != null:
		movement_controller.apply_safe_velocity(value)

func refresh_navigation_avoidance() -> void:
	if movement_controller != null:
		movement_controller.refresh_navigation_avoidance()

func set_streaming_physics_active(active: bool) -> void:
	if movement_controller != null:
		movement_controller.set_streaming_active(active)

func set_navigation_max_speed(value: float) -> void:
	if movement_controller != null:
		movement_controller.set_max_speed(value)

func get_local_separation_velocity() -> Vector3:
	return movement_controller.get_local_separation_velocity() if movement_controller != null else Vector3.ZERO

func should_chase_player() -> bool:
	_sync_dark_erosion_collision_mode()
	var forced_hunt := bool(get_meta("dark_erosion_hunt", false))
	# P1-5：统一目标解析（已登记玩家 → 会话注册表 → player_ref → 单机全局）。
	var target: Node = _resolve_target_player()
	if target == null or not is_instance_valid(target):
		_player = null
		if _targeting != null:
			_targeting.clear()
		return false
	if forced_hunt:
		_player = target as Player
		if _targeting != null:
			_targeting.evaluate(_player, true)
		return true
	var candidate := target as Player
	if _targeting == null:
		return false
	var should_chase: bool = bool(_targeting.evaluate(candidate))
	if should_chase:
		_player = candidate
		return true
	if target == player:
		_player = null
	return false

func set_dark_erosion_hunt(active: bool) -> void:
	set_meta("dark_erosion_hunt", active)
	if movement_controller != null:
		movement_controller.set_dark_erosion_hunt(active)
	_notify_streaming_forced_hunt(active)
	_sync_dark_erosion_collision_mode()

func _notify_streaming_forced_hunt(active: bool) -> void:
	var level := GameState.current_level
	if level == null or not is_instance_valid(level):
		return
	var controller: Variant = level.get("streaming_controller")
	if controller != null and is_instance_valid(controller) \
			and controller.has_method("notify_forced_hunt_changed"):
		controller.notify_forced_hunt_changed(self, active)

func _sync_dark_erosion_collision_mode() -> void:
	var forced_hunt := bool(get_meta("dark_erosion_hunt", false))
	if forced_hunt and movement_controller != null:
		movement_controller.set_dark_erosion_hunt(forced_hunt)
	if _normal_collision_mask == 0:
		return
	if forced_hunt:
		# NavigationAgent3D already separates neighboring enemies. Removing only
		# the enemy bit prevents a full-erosion crowd from physically queueing at
		# a doorway while preserving wall/player collisions.
		collision_mask = _normal_collision_mask & ~PhysicsSetup.LAYER_ENEMY
	else:
		collision_mask = _normal_collision_mask

## 视野检测：从敌人中心质量到目标之间是否有墙壁/障碍物阻挡。
## 返回 true 表示视线畅通（可以看见目标），false 表示被遮挡（跨墙）。
func has_line_of_sight_to(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not is_inside_tree():
		return false
	# 节流：缓存窗口内直接返回上次结果，避免每帧对每个怪物做物理射线。
	if _los_cache_timer > 0.0:
		return _los_cache_result
	var world := get_world_3d()
	if world == null:
		return false
	var space := world.direct_space_state
	if space == null:
		return false
	var from := global_position + Vector3.UP * LOS_RAY_HEIGHT
	var to := target.global_position + Vector3.UP * LOS_RAY_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# 排除敌人自身碰撞体
	query.exclude = [get_rid()]
	# 仅检测墙壁/地形/场景物体（遮挡视线的物体）
	query.collision_mask = PhysicsSetup.MASK_VISION_OBSTRUCTION
	var result := space.intersect_ray(query)
	# 射线未命中任何遮挡物 → 视线畅通
	_los_cache_result = result.is_empty()
	_los_cache_timer = LOS_INTERVAL
	return _los_cache_result

func is_player_within_reach() -> bool:
	if not has_registered_player() or not is_target_visible():
		return false
	if attack_mode == ATTACK_MODE_BODY:
		return global_position.distance_to(player.global_position) <= maxf(body_attack_reach, 0.8)
	if not uses_weapon_attack() or weapon_reach_raycast == null:
		return false
	return weapon_reach_raycast.is_colliding()

func try_receive_hit(source_player: Player, damage: int) -> void:
	if state_node == null or not is_instance_valid(state_node) or state_node.is_queued_for_deletion():
		return
	if state == State.HURT or state == State.DYING or state == State.DEAD:
		return
	var damage_applied: bool = state_node.can_get_hurt()
	_player = source_player
	register_kill_credit(source_player, damage_applied)
	if _targeting != null:
		_targeting.mark_engaged_target(source_player)
	screamed.emit()
	var hit_direction := source_player.global_position.direction_to(global_position)
	var data := EnemyStateData.new().set_damage(damage).set_impact_direction(hit_direction)
	# 旧入口也发射命中信号，供准心 Hitmarker 使用
	if source_player != null and GameEvents != null and GameEvents.has_signal("player_hit_enemy"):
		GameEvents.player_hit_enemy.emit({
			"damage": damage,
			"is_crit": false,
			"position": global_position,
		})
	if damage_applied:
		switch_state(State.HURT, data)
	else:
		switch_state(State.BLOCKING, data)

## ARPG 战斗结算入口：接受 CombatEngine.DamageResult（含向量击退/秒眩晕/最终伤害）
## 由 CombatBridge.resolve_player_attack 产出，替换原 try_receive_hit 的硬编码 damage
func try_receive_hit_result(source_player: Player, result) -> void:
	if state_node == null or not is_instance_valid(state_node) or state_node.is_queued_for_deletion():
		return
	if state == State.HURT or state == State.DYING or state == State.DEAD:
		return
	var damage_applied: bool = state_node.can_get_hurt() or bool(result.ignores_block)
	_player = source_player
	register_kill_credit(source_player, damage_applied)
	if damage_applied:
		var proficiency_key := String(result.proficiency_key) if "proficiency_key" in result else ""
		COMBAT_PROGRESSION.award_player_damage(
			source_player,
			proficiency_key,
			String(result.attack_type),
			int(result.final_damage)
		)
	if _targeting != null:
		_targeting.mark_engaged_target(source_player)
	screamed.emit()
	var hit_direction := source_player.global_position.direction_to(global_position)
	# 若 result 含向量击退冲量，优先使用其方向
	var impact_dir := hit_direction
	if result.knockback_impulse != Vector3.ZERO:
		impact_dir = result.knockback_impulse.normalized()
	var data := EnemyStateData.new()
	data.set_damage(result.final_damage)
	data.set_impact_direction(impact_dir)
	# ARPG 实时击退力（米/秒），由 DamageResult.knockback_force 提供
	data.set_knockback_force(result.knockback_force)
	if "crit" in result:
		data.set_crit(bool(result.crit))
	# 准心 Hitmarker / 战斗反馈
	if source_player != null and GameEvents != null and GameEvents.has_signal("player_hit_enemy"):
		GameEvents.player_hit_enemy.emit({
			"damage": result.final_damage,
			"is_crit": bool(result.crit) if "crit" in result else false,
			"position": global_position,
		})
	physical_impact_enabled = bool(result.physical_impact_enabled)
	physical_impact_damage_mult = float(result.physical_impact_damage_mult)
	physical_impact_min_speed = float(result.physical_impact_min_speed)
	physical_impact_full_speed = float(result.physical_impact_full_speed)
	# 动作控制版：格挡由状态机判定（can_get_hurt = false → BLOCKING 状态），
	# 不再有概率格挡投骰。格挡反馈由 EnemyStateBlocking._enter_tree 播放。
	# 穿透格挡的攻击（ignores_block）无视格挡状态，直接造成伤害。
	# ARPG 秒数眩晕：若 result.stun_duration > 0，进入 STUNNED 状态
	if damage_applied:
		if result.stun_duration > 0.0 and state_node.can_get_stunned():
			# 临时改写 duration_stun 为秒数对应的毫秒（EnemyStateStunned 用 Time.get_ticks_msec 比对）
			# 策划案 ARPG 化：stun_duration 单位为秒，转毫秒供现有计时逻辑使用
			duration_stun = int(result.stun_duration * 1000.0)
			switch_state(State.STUNNED, data)
		else:
			switch_state(State.HURT, data)
	else:
		switch_state(State.BLOCKING, data)

func try_receive_kick(source_player: Player) -> void:
	_player = source_player
	register_kill_credit(source_player)
	if _targeting != null:
		_targeting.mark_engaged_target(source_player)
	screamed.emit()
	var hit_direction := source_player.global_position.direction_to(global_position)
	var data := EnemyStateData.new().set_impact_direction(hit_direction)
	if state_node.can_get_stunned() or not equipment.has_shield():
		if state == State.STUNNED:
			data.set_knockback_force(2.5)
		switch_state(State.STUNNED, data)
	else:
		switch_state(State.BLOCKING, data)

func try_stun() -> void:
	if state_node.can_get_stunned():
		switch_state(State.STUNNED)

func process_movement(delta: float) -> void:
	process_gravity(delta)
	process_pushback(delta)
	var impact_velocity := velocity
	move_and_slide()
	_check_physical_impact_damage(impact_velocity)
	_check_thrown_enemy_collision()

func process_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

func process_pushback(_delta: float) -> void:
	if pushback_force.is_zero_approx():
		return
	# DamageResult.knockback_force is a velocity impulse, not a per-frame force.
	# Applying it more than once integrated kick/charge into an unbounded speed boost.
	velocity += pushback_force
	pushback_force = Vector3.ZERO

func _check_thrown_enemy_collision() -> void:
	if not has_meta("is_thrown") or bool(get_meta("thrown_enemy_collision_resolved", false)):
		return
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		var body := collision.get_collider()
		if body is Enemy and body != self:
			set_meta("thrown_enemy_collision_resolved", true)
			call_deferred("_resolve_thrown_enemy_collision", body)
			return
	if velocity.length() < 0.5:
		_clear_thrown_enemy_meta()

func _resolve_thrown_enemy_collision(body: Node) -> void:
	if not is_instance_valid(self):
		return
	var source_player := get_meta("throw_source_player", null) as Player
	_clear_thrown_enemy_meta()
	if body is Enemy and is_instance_valid(body):
		(body as Enemy).try_receive_thrown_enemy_impact(self, source_player)

func _clear_thrown_enemy_meta() -> void:
	for key in ["is_thrown", "throw_velocity", "throw_source_player", "thrown_enemy_collision_resolved"]:
		if has_meta(key):
			remove_meta(key)

func _check_physical_impact_damage(impact_velocity: Vector3) -> void:
	var resolution := PHYSICAL_IMPACT.resolve_slide_collisions(
		self,
		impact_velocity,
		health.max_life,
		_get_physical_impact_spec(),
		_last_physical_impact_msec
	)
	if not bool(resolution.get("hit", false)):
		return
	_last_physical_impact_msec = int(resolution.get("time_msec", Time.get_ticks_msec()))
	_apply_physical_impact_damage(int(resolution.get("damage", 0)), resolution.get("normal", Vector3.ZERO))

func _get_physical_impact_spec() -> Dictionary:
	return {
		"enabled": physical_impact_enabled,
		"damage_mult": physical_impact_damage_mult,
		"min_speed": physical_impact_min_speed,
		"full_speed": physical_impact_full_speed,
	}

func _apply_physical_impact_damage(damage: int, normal: Vector3) -> void:
	health.take_damage(damage)
	if damage > 0 and is_inside_tree():
		FxHelper.call_deferred("create_damage_number_flags", global_position, damage, false)
	physical_impact_enabled = false
	if health.is_dead() and state_node != null and state_node.can_die():
		var impact_dir := -normal.normalized()
		var data := EnemyStateData.new().set_impulse(impact_dir * 120.0 + Vector3.UP * 80.0)
		# 延迟到物理步骤结束后再切换状态，避免在 _physics_process 中同步调用
		# switch_state(DYING) → EnemyStateDying._enter_tree 中的
		# physical_bones_start_simulation() / apply_impulse() / add_child() 等物理操作
		# 在物理引擎步进期间执行，导致引擎死锁/卡死（踢击设置 physical_impact_enabled=true 时触发）。
		request_death(data)

## 延迟切换到 DYING 状态：由 _apply_physical_impact_damage 通过 call_deferred 调用，
## 确保状态切换及 EnemyStateDying._enter_tree 中的物理操作在物理步骤之外执行。
func _deferred_switch_to_dying(data: EnemyStateData, bypass_can_die: bool = false) -> void:
	_death_transition_queued = false
	if not is_instance_valid(self) or state_node == null or not is_instance_valid(state_node):
		return
	if state == State.DYING or state == State.DEAD:
		return
	if not state_node.is_queued_for_deletion() and (bypass_can_die or state_node.can_die()):
		switch_state(State.DYING, data)

func apply_combat_debuff(debuff_type: String, duration_sec: float, value: Variant) -> void:
	if debuff_type == "" or duration_sec <= 0.0:
		return
	combat_debuffs[debuff_type] = {"remaining": duration_sec, "value": value}

func get_combat_speed_multiplier() -> float:
	var mult := float(get_meta("environment_activity_mult", 1.0))
	if bool(get_meta("dark_erosion_hunt", false)):
		mult *= DARK_EROSION_HUNT_SPEED_MULTIPLIER
	for debuff_type in combat_debuffs.keys():
		var value = combat_debuffs[debuff_type].get("value", 0)
		match debuff_type:
			"slow", "ground_ice":
				mult *= 1.0 - float(value) / 100.0
			"slow_and_haste":
				if typeof(value) == TYPE_DICTIONARY:
					mult *= 1.0 - float(value.get("slow_target", 0.0)) / 100.0
			"root_and_dmg_down":
				if typeof(value) == TYPE_DICTIONARY and bool(value.get("root", false)):
					mult = 0.0
	# 符文状态效果速度修正（se_ 前缀：定身/束缚/减速/窒息/震颤/恐惧等）
	mult *= SES.get_speed_multiplier(self)
	return maxf(mult, 0.0)

func get_combat_defense_penalty() -> int:
	var penalty := 0
	if combat_debuffs.has("def_down"):
		penalty += int(combat_debuffs["def_down"].get("value", 0))
	# 符文状态效果：破甲/粉碎
	penalty += SES.get_defense_penalty(self)
	return penalty

func get_combat_evade_penalty() -> float:
	var penalty := 0.0
	if combat_debuffs.has("evade_down"):
		penalty += float(combat_debuffs["evade_down"].get("value", 0.0))
	# 符文状态效果：致盲（闪避归零）
	penalty += SES.get_evade_penalty(self)
	return penalty

func _tick_combat_debuffs(delta: float) -> void:
	for debuff_type in combat_debuffs.keys():
		var debuff: Dictionary = combat_debuffs[debuff_type]
		var remaining := float(debuff.get("remaining", 0.0)) - delta
		if remaining <= 0.0:
			combat_debuffs.erase(debuff_type)
		else:
			debuff["remaining"] = remaining
			combat_debuffs[debuff_type] = debuff

func on_player_detected(body: Player) -> void:
	if body != null and global_position.distance_to(body.global_position) <= detection_range:
		if _targeting != null and _targeting.acquire_visible_target(body):
			_player = body

func on_player_lost(body: Player) -> void:
	if body == player and not bool(get_meta("dark_erosion_hunt", false)):
		# 目标感知 Module 负责最后已知位置和短暂记忆窗口。
		if _targeting != null and not _targeting.has_navigation_goal():
			_player = null

func take_acid_damage() -> void:
	if state_node.can_die():
		request_death()
		
func take_spike_damage(_spikes_trap: SpikesTrap) -> void:
	if state_node.can_die():
		AudioManager.play("spikes", action_audio_stream_player)
		request_death()
