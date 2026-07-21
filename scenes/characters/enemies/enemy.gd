class_name Enemy
extends CharacterBody3D

signal dead(death_transform: Transform3D)
signal screamed

const AIR_FRICTION := 20.0
const DURATION_RAGDOLL_SIMULATION := 3.0
const GRAVITY := 20.0
const HITBOX_BUILDER := preload("res://globals/combat/combat_hitbox_builder.gd")
const PHYSICAL_IMPACT := preload("res://globals/combat/physical_impact_resolver.gd")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const VOXEL_RAGDOLL := preload("res://scenes/characters/component/voxel_ragdoll.gd")
const DEFAULT_DETECTION_RANGE := 5.0
## 视野射线高度（米）：从角色中心质量发射，避免贴地射线漏检矮墙
const LOS_RAY_HEIGHT := 0.85
## 怪物渲染优化：网格最远可见距离（米）。配合既有 24m 流式半径进一步远裁剪，避免远处怪物空耗 draw call。
const ENEMY_VISIBILITY_RANGE_END := 60.0
## 近距离阈值（米）：此距离内的怪物无视视锥始终渲染并播放动画，避免屏幕边缘近怪闪烁。
const ENEMY_NEAR_ANIM_DISTANCE := 12.0
## 离屏/远距优化轮询间隔（秒），避免每帧对每个怪物做视锥检测。
const RENDER_OPT_INTERVAL := 0.2
## 视野射线检测节流间隔（秒）：物理射线较贵，缓存结果，最多每 0.2s 重测一次。
## 仅影响"初次发现玩家"的索敌延迟，已登记玩家不依赖此检测，不影响追击手感。
const LOS_INTERVAL := 0.2
## 敌人 imposter LOD 距离（米）：超过此距离且处于 MOVING 状态则隐藏蒙皮网格、改用 Sprite3D billboard 替身，
## 省 CPU 蒙皮 + draw call（对齐 Barony 远敌换贴片）。近处/攻击等非 MOVING 状态仍用完整骨架网格以保留可读招式。
const ENEMY_IMPOSTER_LOD_DISTANCE := 18.0
## AI 模拟半径（米）：与 imposter LOD 边界对齐。超过此距离且未与玩家交战（未登记）的敌人
## 视为"远距替身带"，跳过巡逻/索敌等寻路 AI，仅保留物理静止。避免对玩家看不见的 18–36m 敌人
## 空算 A* 与导航查询（P-C：把 AI 半径从 ~36m 物理激活半径解耦到 LOD 边界）。
const AI_SIM_RADIUS_M := 18.0
## imposter 截图分辨率（正方形像素）
const ENEMY_IMPOSTER_CAPTURE_SIZE := 256

## 每种敌人只捕获一次 imposter；同批刷新的同类实例等待首个捕获任务并共享贴图。
static var _imposter_texture_cache: Dictionary = {}
static var _imposter_capture_in_flight: Dictionary = {}

@onready var action_audio_stream_player: AudioStreamPlayer3D = %ActionAudioStreamPlayer
@onready var animation_player: AnimationPlayer = $character/AnimationPlayer
@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var equipment: EquipmentComponent = %EquipmentComponent
@onready var health: HealthComponent = %HealthComponent
@onready var nav_agent: NavigationAgent3D = %NavigationAgent3D
@onready var skeleton_simulator: PhysicalBoneSimulator3D = %PhysicalBoneSimulator3D
@onready var physical_bone_head: PhysicalBone3D = %"Physical Bone Head"
@onready var physical_bone_torso: PhysicalBone3D = %"Physical Bone Torso"
## 死亡碎裂（伪布娃娃）组件。所有敌人在 _ready 中均创建此组件，
## 死亡时优先使用体素碎裂效果（VoxelRagdoll），骨骼布娃娃（skeleton_simulator）仅作回退。
var voxel_ragdoll: VoxelRagdoll = null
@onready var player_detection_area: Area3D = %PlayerDetectionArea
@onready var player_detection_shape: CollisionShape3D = %PlayerDetectionArea/CollisionShape3D
@onready var vocal_audio_stream_player: AudioStreamPlayer3D = %VocalAudioStreamPlayer
@onready var weapon_reach_raycast: RayCast3D = %WeaponReachRaycast

@export var duration_between_attacks: int
@export var duration_stun : int
@export var player: Player
@export var speed: float
@export var is_elite: bool = false
@export var is_boss_type: bool = false
@export_enum("small", "medium", "large", "huge") var body_size: String = "medium"
## 巡逻半径（米），无玩家时在此范围内随机巡逻
@export var patrol_radius: float = 5.0
## 统一索敌距离（米）。100% 暗蚀会绕过此限制强制追击。
@export var detection_range: float = DEFAULT_DETECTION_RANGE
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
## imposter 替身 Sprite3D（运行时 Viewport 截图生成贴图，billboard）。仅在出生时可空（headless 跳过截图）。
var _imposter_sprite: Sprite3D = null
## 是否已切到远处 LOD（隐藏蒙皮、显示替身）
var _lod_is_far := false
## 死亡碎裂已激活：激活后 LOD 系统不再修改原始网格可见性，避免碎裂后原模型重新显示。
var _death_ragdoll_active := false

func _ready() -> void:
	PhysicsSetup.setup_enemy(self)
	VOXEL_LIGHTING.apply_to_tree(self, true)
	add_to_group("enemies")
	_configure_detection_range()
	player_detection_area.body_entered.connect(on_player_detected)
	player_detection_area.body_exited.connect(on_player_lost)
	_apply_spawner_multipliers()
	# 移除 3D 血条后，屏幕顶部 EnemyHealthBar HUD 已直接读取 enemy.health 显示血量，
	# 此处不再驱动 3D 血条刷新。
	_collect_visual_meshes()
	_apply_visibility_range()
	_build_imposter_sprite()
	_update_render_optimization()
	# 所有敌人均挂载死亡碎裂（伪布娃娃）组件。
	# 体素怪物使用 _rig.glb（Blender 合并的单蒙皮网格 + 骨架），skeleton_simulator 非 null 但
	# PhysicalBone3D 的 collision_layer=0 且蒙皮网格不跟随骨骼 → 骨骼布娃娃无效，怪物原样留在原地。
	# VoxelRagdoll 优先用于所有敌人的死亡碎裂效果；skeleton_simulator 仅作回退。
	voxel_ragdoll = VOXEL_RAGDOLL.new()
	add_child(voxel_ragdoll)
	switch_state(State.MOVING)

func _configure_detection_range() -> void:
	if player_detection_shape == null:
		return
	var sphere := player_detection_shape.shape as SphereShape3D
	if sphere == null:
		return
	sphere = sphere.duplicate() as SphereShape3D
	sphere.radius = detection_range
	player_detection_shape.shape = sphere

## 应用 DungeonSpawner 通过 meta 注入的属性倍率（hp_mult / speed_mult / dmg_mult）
func _apply_spawner_multipliers() -> void:
	if has_meta("hp_mult"):
		var hp_mult: float = float(get_meta("hp_mult", 1.0))
		health.max_life = int(health.max_life * hp_mult)
		health.current_life = health.max_life
	if has_meta("speed_mult"):
		var spd_mult: float = float(get_meta("speed_mult", 1.0))
		speed *= spd_mult
	if has_meta("is_boss_type"):
		is_boss_type = bool(get_meta("is_boss_type", false))
	if has_meta("body_size"):
		body_size = String(get_meta("body_size", "medium"))

## 收集角色可视网格，供离屏剔除与远距冻结使用。
## 不再覆写 material_override：GLB 内嵌纹理由 VOXEL_LIGHTING.apply_to_tree 统一适配
## （toon 着色 + vertex_color_use_as_albedo），保留原始纹理外观。
func _collect_visual_meshes() -> void:
	_visual_meshes.clear()
	var root := get_node_or_null("character")
	var base: Node = root if root != null else self
	for child in base.find_children("*", "MeshInstance3D", true, false):
		_visual_meshes.append(child as MeshInstance3D)


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
	var target: Node = player if has_registered_player() else GameState.current_player
	if target == null or not is_instance_valid(target):
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
	var lod_far := dist > ENEMY_IMPOSTER_LOD_DISTANCE and state == State.MOVING
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
		_imposter_sprite.visible = far

## 创建 imposter 替身 Sprite3D（billboard）。贴图在 _build_imposter_texture 内运行时截图生成。
## 节点本身始终创建（便于 LOD 切换在 headless 测试下也可断言），仅截图步骤在 headless 跳过。
func _build_imposter_sprite() -> void:
	_imposter_sprite = Sprite3D.new()
	_imposter_sprite.name = "ImposterSprite"
	_imposter_sprite.billboard = 1  # Sprite3D.BillboardMode.ENABLED (Godot 4.7 不暴露该枚举常量名，0=Disabled/1=Enabled/2=Y-Billboard)
	_imposter_sprite.centered = true
	_imposter_sprite.position = Vector3(0.0, 0.9, 0.0)
	_imposter_sprite.pixel_size = 0.009
	_imposter_sprite.visibility_range_end = 120.0
	_imposter_sprite.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_imposter_sprite.visible = false
	add_child(_imposter_sprite)
	_build_imposter_texture()

## 运行时用子 Viewport 从前视角渲染自身蒙皮网格一帧，生成贴图赋给 imposter。
## headless 无 GPU 截图，直接跳过（imposter 仍按 LOD 切换，只是无贴图）。
func _build_imposter_texture() -> void:
	if _imposter_sprite == null:
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
		_imposter_sprite.texture = cached_texture
		return
	if _imposter_capture_in_flight.has(cache_key):
		await _wait_for_shared_imposter(cache_key)
		return
	_imposter_capture_in_flight[cache_key] = true
	var vp := SubViewport.new()
	vp.size = Vector2(ENEMY_IMPOSTER_CAPTURE_SIZE, ENEMY_IMPOSTER_CAPTURE_SIZE)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.transparent_bg = true
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 35.0
	cam.position = Vector3(0.0, 1.0, 2.6)
	# 相机尚未加入 SubViewport 场景树；使用 position 版本避免 Node3D.look_at 的入树要求。
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.9, 0.0), Vector3(0, 1, 0))
	vp.add_child(cam)
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
		_imposter_sprite.texture = cached_texture

func _finish_imposter_capture(cache_key: String, texture: ImageTexture) -> void:
	if texture != null:
		_imposter_texture_cache[cache_key] = texture
	_imposter_capture_in_flight.erase(cache_key)
	if texture != null and _imposter_sprite != null:
		_imposter_sprite.texture = texture

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
	_tick_combat_debuffs(delta)
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
	if equipment == null or equipment.weapon_placeholder == null:
		return null
	if equipment.weapon_placeholder.get_child_count() == 0:
		return null
	return equipment.weapon_placeholder.get_child(0) as Node3D

func _get_active_attack_reach() -> float:
	if weapon_reach_raycast != null:
		return maxf(absf(weapon_reach_raycast.target_position.z), 0.8)
	var weapon := equipment.weapon_data if equipment != null and equipment.has_weapon() else null
	return maxf(weapon.reach * CombatHitboxBuilder.REACH_SCALE, 0.8) if weapon != null else 1.2
	
func switch_state(new_state: State, data: EnemyStateData = EnemyStateData.new()) -> void:
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

func impale(thrown_item: ThrownItem, item_basis: Basis) -> void:
	var state_data := EnemyStateData.new().set_thrown_item(thrown_item).set_thrown_item_basis(item_basis)
	if state_node.can_get_hurt():
		switch_state(State.IMPALING, state_data)
	else:
		var hit_direction := thrown_item.global_position.direction_to(global_position)
		state_data.set_impact_direction(hit_direction)
		switch_state(State.BLOCKING, state_data)
	screamed.emit()

func try_receive_furniture_impact(thrown_item: ThrownItem) -> void:
	if equipment.has_shield():
		equipment.drop_shield()
		var hit_direction := thrown_item.global_position.direction_to(global_position)
		var data := EnemyStateData.new().set_impact_direction(hit_direction).set_knockback_force(2.5)
		switch_state(State.STUNNED, data)
	else:
		switch_state(State.DYING)

func try_receive_thrown_enemy_impact(source_enemy: Enemy, source_player: Player = null) -> void:
	if source_player != null:
		player = source_player
	screamed.emit()
	var hit_direction := source_enemy.global_position.direction_to(global_position) if source_enemy != null else Vector3.ZERO
	var data := EnemyStateData.new().set_damage(6).set_impact_direction(hit_direction).set_knockback_force(5.0)
	if equipment.has_shield():
		equipment.drop_shield()
		switch_state(State.STUNNED, data)
	else:
		switch_state(State.HURT, data)

func has_registered_player() -> bool:
	return player != null and is_instance_valid(player)

## 是否应运行完整 AI（索敌/巡逻/寻路）本帧。
## 已与玩家交战（已登记 player）、或受暗蚀强制追击、或玩家进入 AI_SIM_RADIUS_M 内的敌人返回 true；
## 远距未交战的替身带敌人返回 false，其 MOVING 状态将跳过寻路 AI 仅保持物理静止（P-C）。
func is_ai_active() -> bool:
	if bool(get_meta("dark_erosion_hunt", false)):
		return true
	if has_registered_player():
		return true
	var target: Node = GameState.current_player
	if target != null and is_instance_valid(target):
		return global_position.distance_to(target.global_position) <= AI_SIM_RADIUS_M
	return false

func should_chase_player() -> bool:
	var forced_hunt := bool(get_meta("dark_erosion_hunt", false))
	var target: Node = player if has_registered_player() else GameState.current_player
	if target == null or not is_instance_valid(target):
		player = null
		return false
	if forced_hunt:
		player = target
		return true
	if global_position.distance_to(target.global_position) <= detection_range:
		# 初次发现玩家（尚未登记）需通过视野检测，禁止跨墙发现
		# 已登记的玩家允许绕墙短暂追击，由 on_player_lost 处理脱战
		if not has_registered_player() and not has_line_of_sight_to(target):
			return false
		player = target
		return true
	if target == player:
		player = null
	return false

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
	if has_registered_player() and equipment.has_weapon():
		return weapon_reach_raycast.is_colliding()
	return false

func try_receive_hit(source_player: Player, damage: int) -> void:
	if state_node == null or not is_instance_valid(state_node) or state_node.is_queued_for_deletion():
		return
	if state == State.HURT or state == State.DYING or state == State.DEAD:
		return
	player = source_player
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
	if state_node.can_get_hurt():
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
	player = source_player
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
	if state_node.can_get_hurt() or result.ignores_block:
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
	player = source_player
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

func process_pushback(delta: float) -> void:
	pushback_force = pushback_force.move_toward(Vector3.ZERO, delta * AIR_FRICTION)
	velocity += pushback_force

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
		call_deferred("_deferred_switch_to_dying", data)

## 延迟切换到 DYING 状态：由 _apply_physical_impact_damage 通过 call_deferred 调用，
## 确保状态切换及 EnemyStateDying._enter_tree 中的物理操作在物理步骤之外执行。
func _deferred_switch_to_dying(data: EnemyStateData) -> void:
	if not is_instance_valid(self) or state_node == null or not is_instance_valid(state_node):
		return
	if not state_node.is_queued_for_deletion() and state_node.can_die():
		switch_state(State.DYING, data)

func apply_combat_debuff(debuff_type: String, duration_sec: float, value: Variant) -> void:
	if debuff_type == "" or duration_sec <= 0.0:
		return
	combat_debuffs[debuff_type] = {"remaining": duration_sec, "value": value}

func get_combat_speed_multiplier() -> float:
	var mult := float(get_meta("environment_activity_mult", 1.0))
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
	return maxf(mult, 0.0)

func get_combat_defense_penalty() -> int:
	if not combat_debuffs.has("def_down"):
		return 0
	return int(combat_debuffs["def_down"].get("value", 0))

func get_combat_evade_penalty() -> float:
	if not combat_debuffs.has("evade_down"):
		return 0.0
	return float(combat_debuffs["evade_down"].get("value", 0.0))

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
		# 视野检测：玩家在索敌范围内但被墙遮挡时不发现
		if has_line_of_sight_to(body):
			player = body

func on_player_lost(body: Player) -> void:
	if body == player and not bool(get_meta("dark_erosion_hunt", false)):
		player = null

func take_acid_damage() -> void:
	if state_node.can_die():
		switch_state(State.DYING)
		
func take_spike_damage(_spikes_trap: SpikesTrap) -> void:
	if state_node.can_die():
		AudioManager.play("spikes", action_audio_stream_player)
		switch_state(State.DYING)
