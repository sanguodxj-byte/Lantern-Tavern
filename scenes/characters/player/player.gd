class_name Player
extends CharacterBody3D

const SPIKE_DAMAGE := 5
const GROUND_FRICTION := 15.0
const MAX_ANGLE_LOOK_UP := deg_to_rad(70)
const MAX_ANGLE_LOOK_DOWN := deg_to_rad(-70)
# 技能/战斗桥接预加载（_on_skill_released 分发用）
const AS_DB := preload("res://globals/combat/action_skills.gd")
const SD_DB := preload("res://globals/combat/skill_data.gd")
const CB_LIB := preload("res://globals/combat/combat_bridge.gd")
const CE_LIB := preload("res://globals/combat/combat_engine.gd")
const DETAIL_POPUP := preload("res://scenes/ui/equipment_detail_popup.gd")
const PLAYER_STATE_AIMING := preload("res://scenes/characters/player/state/player_state_aiming.gd")
const PLAYER_STATE_ATTACK_PREPARING := preload("res://scenes/characters/player/state/player_state_attack_preparing.gd")
const PLAYER_STATE_SHOOTING := preload("res://scenes/characters/player/state/player_state_shooting.gd")
const PLAYER_VISION_LIGHT_NAME := "PlayerVisionLight"
const HITBOX_BUILDER := preload("res://globals/combat/combat_hitbox_builder.gd")
const SKILL_DISPATCHER := preload("res://scenes/characters/player/player_skill_dispatcher.gd")
const Service := preload("res://globals/core/service.gd")
const CHEST_LOOT_PANEL_SCENE := preload("res://scenes/ui/chest_loot_panel.tscn")
const COMBAT_BUFF_COMPONENT := preload("res://scenes/characters/component/combat_buff_component.gd")
const AIM_HELPER := preload("res://scenes/characters/player/player_aim_helper.gd")
@export var acceleration: float
@export var jump_force: float
@export var gravity: float
@export var mouse_sensitivity: float
@export var run_speed: float
@export var walk_speed: float

@onready var action_audio_stream_player: AudioStreamPlayer3D = %ActionAudioStreamPlayer
@onready var animation_player: AnimationPlayer = $character/AnimationPlayer
@onready var camera: Camera3D = %MainCamera
@onready var footstep_audio_stream_player: AudioStreamPlayer3D = %FootstepAudioStreamPlayer
@onready var kick_raycast: RayCast3D = %KickRaycast
@onready var equipment: EquipmentComponent = %EquipmentComponent
@onready var health: HealthComponent = %HealthComponent
@onready var select_raycast: RayCast3D = %SelectRaycast
@onready var vocal_audio_stream_player: AudioStreamPlayer3D = %VocalAudioStreamPlayer
@onready var weapon_reach_raycast: RayCast3D = %WeaponReachRaycast
@onready var view_model: Node3D = %ViewModel

## 角色身体渲染层（第 10 层），主摄像机 cull_mask=1 不渲染此层
const CHARACTER_BODY_RENDER_LAYER := 1 << 9

enum State {MOVING, PICKING_UP, THROWING, ATTACK_PREPARING, SLASHING, SHOOTING, AIMING, KICKING, BLOCKING, HURT, DYING, GRABBING, CHARGING}

## 联机输入模式（Phase 1：权威边界门控）
## LOCAL         = 单机，本地直接执行所有权威操作（移动/战斗/交互/拾取/投掷/格挡）
## NETWORK_CLIENT= 远端客户端：所有权威操作经 multiplayer_driver 上送服务器，本地【不】执行
## NETWORK_SERVER= 房主（同时是服务器）：本地即为权威，可直接执行
enum InputMode {
	LOCAL,
	NETWORK_CLIENT,
	NETWORK_SERVER,
}

var chest_interact_time : float = 0.0
const CHEST_OPEN_DURATION := 5.0

var movement_input_enabled := true
var interaction_input_enabled := true
var combat_input_enabled := true

## 联机输入模式与驱动（Phase 1）。单机恒为 LOCAL；房主=NETWORK_SERVER；远端客户端=NETWORK_CLIENT。
var input_mode: InputMode = InputMode.LOCAL
var multiplayer_driver: Node = null

## 配置联机输入：挂上 ClientCommandDriver 并设定本玩家的联机身份。
## mode 默认 NETWORK_CLIENT（远端客户端）；房主传 NETWORK_SERVER。
func configure_network_input(driver: Node, mode: InputMode = InputMode.NETWORK_CLIENT) -> void:
	multiplayer_driver = driver
	input_mode = mode

## 是否为「被远程服务器控制的客户端」——本地只上送意图+播放表现，绝不直接执行权威操作。
## 注意：NETWORK_SERVER（房主）虽处联机，但本地即权威，故不算「被控制」，仍需本地执行。
func is_network_controlled() -> bool:
	return input_mode == InputMode.NETWORK_CLIENT

## 取节点的服务器实体 id（联机交互/拾取/攻击定位用）；无则 0（服务器按玩家位置/朝向推断）。
func _entity_id_of(node: Object) -> int:
	if node != null and node.get("entity_id") != null:
		return int(node.get("entity_id"))
	return 0

var current_possible_action : String = ""
var current_pickable_focused_item : PickableItem = null
## 上一次交互检测命中的 collider，用于跳过未变时的字符串构造与信号发射
var _last_possible_action_collider: Object = null
var input_dir := Vector2.ZERO
var pushback_force := Vector3.ZERO
var state: State
var state_node: PlayerState
## 战斗 buff 管理器（从 player.gd 提取为独立组件）
var buffs := COMBAT_BUFF_COMPONENT.new()

## 兼容性：combat_buffs 字典直接访问（委托给 buffs 组件）
var combat_buffs: Dictionary:
	get:
		return buffs.get_buffs_dict()

## 近战攻击冷却系统（仅近战武器；远程走各自装弹/蓄力逻辑，doc21 #3 急速 cd_reduce 作用对象）
## 主手(左键)与副手(双持右键)独立计时。计时归零即就绪。
var _melee_cd_primary: float = 0.0
var _melee_cd_primary_max: float = 0.0
var _melee_cd_secondary: float = 0.0
var _melee_cd_secondary_max: float = 0.0
const MELEE_CD_BASE := 0.45            # 单手近战基础冷却（秒）
const MELEE_CD_TWO_HAND_MULT := 1.5    # 双手武器冷却倍率
const MELEE_CD_DUAL_WIELD := 0.38      # 双持副手冷却（秒）
const CD_REDUCE_MULT := 0.85           # 急速被动：冷却 ×0.85
const MELEE_CHARGE_FULL_SEC := 0.8      # 蓄满所需按住时长（秒）
const MELEE_CHARGE_MAX_MULT := 2.0      # 蓄满伤害倍率（×2.0，doc21 #1）

## 完美格挡·增伤（doc21 #6 perfect_block_empower）：完美格挡成功后下次攻击 ×1.5
const PERFECT_BLOCK_BUFF_MULT := 1.5
## 残影（doc21 #7 afterimage）：侧垫步成功后首次攻击 ×1.3，窗口 1.5s
const SIDESTEP_BUFF_MULT := 1.3
const SIDESTEP_BUFF_SEC := 1.5

## 轻弩装弹系统（doc21 reload_shot：每次射击后须装弹，装弹完成前不允许连续发射）
var _crossbow_reload_remaining: float = 0.0
var _crossbow_reload_total: float = 0.0
const CROSSBOW_RELOAD_FALLBACK_SEC := 1.2   # 武器未声明 reload_time 时的兜底装弹时长

## 二段跳 / 空中冲刺（doc21 #4 air_dash 机制类被动，需解锁后才可用）
var _air_jumps_used: int = 0
const AIR_JUMPS_MAX := 1                     # 离地后可追加的跳跃次数（=1 即二段跳）
const AIR_JUMP_FORCE_MULT := 0.92           # 空中跳力度相对地面跳

## 完美格挡·增伤 buff（doc21 #6）：完美格挡成功后置位，下次攻击命中时消费（切武器不清除、连续完美格挡仅刷新）
var _perfect_block_buff_active: bool = false
## 残影 buff（doc21 #7 afterimage）：侧垫步成功后激活，限时窗口内首次攻击命中消费
var _sidestep_buff_remaining: float = 0.0

var is_weapon_aiming := false
var default_camera_fov := 75.0
## 瞄准时目标 FOV（望远镜效果），在 _process 中平滑过渡
var target_camera_fov := 75.0
## 瞄准 FOV 缩减量（度数越大缩放越强）
const AIM_FOV_REDUCTION := 25.0
## 瞄准时鼠标灵敏度倍率（越低越精细）
const AIM_SENSITIVITY_MULT := 0.35
## FOV 平滑过渡速度
const FOV_LERP_SPEED := 12.0

## 当前打开的宝箱战利品面板（null 表示未打开）
var _chest_loot_panel: Node = null

## 玩家体素网格统一材质（已废弃：保留属性向后兼容场景文件，不再用于 material_override）。
## GLB 内嵌纹理由 VoxelLightingAdapter 统一适配，与 enemy.gd 保持一致。
@export var base_material: Material = null

## 收集角色可视网格（不再覆写 material_override，保留 GLB 内嵌纹理）。
func _collect_visual_meshes_player() -> void:
	var character_node := get_node_or_null("character")
	if character_node == null:
		return
	var queue: Array[Node] = [character_node]
	while not queue.is_empty():
		var n: Node = queue.pop_back()
		if n is MeshInstance3D:
			pass  # 仅遍历，不覆写材质
		queue.append_array(n.get_children())

func _ready() -> void:
	_collect_visual_meshes_player()
	if has_meta("equipment_preview"):

		movement_input_enabled = false
		interaction_input_enabled = false
		combat_input_enabled = false
		_setup_player_light()
		return
	# 最优先隐藏角色身体：把它移到第 10 渲染层，使主相机（cull_mask=1）不可见。
	# 必须在任何可能抛错的初始化（物理装配 / 装备同步）之前执行——
	# 否则一旦后续逻辑异常中断 _ready，身体会停留在第 1 层，第一人称下“看见自己手臂/身体”穿帮。
	_hide_character_body()
	PhysicsSetup.setup_player(self)
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if camera != null:
		default_camera_fov = camera.fov
		target_camera_fov = camera.fov
	# 注：身体已在 _ready 开头隐藏；武器变更回调 _on_weapon_changed_for_view 会再次隐藏。
	# 监听武器变更：拾取/切换武器后重新隐藏角色手上武器网格 + 同步 ViewModel
	GameEvents.weapon_changed.connect(_on_weapon_changed_for_view)
	var gs = Service.game_state()
	if gs:
		gs.register_player(self)
	GameEvents.player_spawned.emit(self)

	GameEvents.chest_opened.connect(_on_chest_opened)
	# 监听 SkillRuntime 信号
	var sr: Node = Service.skill_runtime()
	if sr != null:
		sr.skill_released.connect(_on_skill_released)
		# 按当前双轨阶梯（属性/熟练度）重算并授予机制类被动（doc21 §5/§7）
		sr.recompute_mechanism_passives()
	switch_state(State.MOVING)
	# 角色自身发光——地牢极暗时照亮周围
	_setup_player_light()
	# 初始同步：如果已有武器，直接推送到 ViewModel
	_sync_view_model_weapon()

var _passive_toughness_timer: float = 0.0

func _process_passive_effects(delta: float) -> void:
	var sr: Node = Service.skill_runtime()
	if sr == null:
		return
	# 坚韧被动：每 5s 恢复 2% 最大生命值
	if sr.has_mechanism_passive("passive_toughness"):
		_passive_toughness_timer += delta
		if _passive_toughness_timer >= 5.0 and health != null and is_instance_valid(health):
			_passive_toughness_timer -= 5.0
			var heal_amt: int = maxi(1, int(round(float(health.max_life) * 0.02)))
			health.heal(heal_amt)

func _hide_character_body() -> void:
	var character_node := get_node_or_null("character")
	if character_node == null:
		return
	_set_render_layer_recursive(character_node, CHARACTER_BODY_RENDER_LAYER)

## 武器变更回调：重新隐藏角色手上新创建的武器网格 + 同步 ViewModel
func _on_weapon_changed_for_view(_weapon_data: Variant) -> void:
	# 拾取/切换武器后，EquipedItem 会新建 GLB 网格（默认在 layer 1）
	# 需要重新将这些网格移到第 10 层，使摄像机（cull_mask=1）不渲染它们
	_hide_character_body()
	# 同步 ViewModel 武器模型
	_sync_view_model_weapon()

## 直接将当前装备的武器推送到 ViewModel（不依赖信号）
func _sync_view_model_weapon() -> void:
	if view_model == null or not is_instance_valid(view_model):
		return
	if not view_model.has_method("set_weapon"):
		return
	var weapon := get_active_hand_weapon_data()
	view_model.set_weapon(weapon)

func _set_render_layer_recursive(node: Node, layer: int) -> void:
	if node is GeometryInstance3D:
		node.layers = layer
	for child in node.get_children():
		_set_render_layer_recursive(child, layer)

func _setup_player_light() -> void:
	var existing := get_node_or_null(PLAYER_VISION_LIGHT_NAME) as OmniLight3D
	if existing != null:
		existing.visible = true
		existing.light_energy = 2.4
		existing.omni_range = 10.0
		existing.omni_attenuation = 0.45
		existing.shadow_enabled = false
		existing.distance_fade_enabled = false
		existing.position = Vector3(0, 1.5, 0)
		return
	var light := OmniLight3D.new()
	light.name = PLAYER_VISION_LIGHT_NAME
	light.light_color = Color(1.0, 0.85, 0.6)
	light.visible = true
	light.light_energy = 2.4
	light.omni_range = 10.0
	light.omni_attenuation = 0.45
	light.shadow_enabled = false
	light.distance_fade_enabled = false
	light.position = Vector3(0, 1.5, 0)
	add_child(light)

func _is_inside_tavern() -> bool:
	var current: Node = self
	while current != null:
		if current.get_class() == "TavernInterior" or current is TavernInterior:
			return true
		current = current.get_parent()
	var gs = Service.game_state()
	if gs and gs.get("current_level") != null and gs.current_level is TavernInterior:
		return true
	return false

func _process(delta: float) -> void:
	input_dir = Input.get_vector("strafe_left", "strafe_right", "backward", "forward") if movement_input_enabled else Vector2.ZERO
	if combat_input_enabled:
		_handle_skill_input()
	_process_passive_effects(delta)
	# 平滑过渡摄像机 FOV（望远镜效果）
	if camera != null and is_instance_valid(camera):
		camera.fov = lerpf(camera.fov, target_camera_fov, delta * FOV_LERP_SPEED)

## F/G 键技能释放：F 键动作技能（无媒介限制），G 键武器流派技能（受媒介限制）
func _handle_skill_input() -> void:
	var sr: Node = Service.skill_runtime()
	if sr == null:
		return
	# F 键：动作技能（复用现有 kick 输入映射，F 键 physical_keycode 70）
	if Input.is_action_just_pressed("kick"):
		var f_skill: String = sr.get_slot_skill(sr.SLOT_F_ACTION)
		# 回退：F 槽为空时使用默认踢击，确保 F 键始终可用
		if f_skill == "":
			f_skill = sr.DEFAULT_F_SLOT_SKILL
		var weapon = equipment.weapon_data if equipment != null and equipment.has_weapon() else null
		var main_type := CB_LIB.get_weapon_class(weapon)
		var off_type := "shield" if (equipment != null and equipment.has_shield()) else ""
		sr.start_release(f_skill, main_type, off_type, self, sr.SLOT_F_ACTION)
	# G 键：武器流派技能
	if Input.is_action_just_pressed("skill_g"):
		var g_skill: String = sr.get_slot_skill(sr.SLOT_G_WEAPON)
		if g_skill != "":
			var weapon = equipment.weapon_data if equipment.has_weapon() else null
			var main_type := CB_LIB.get_weapon_class(weapon)
			var off_type := "shield" if equipment.has_shield() else ""
			sr.start_release(g_skill, main_type, off_type, self, sr.SLOT_G_WEAPON)

func _physics_process(delta: float) -> void:
	process_gravity()
	process_pushback(delta)
	move_and_slide()
	if has_meta("equipment_preview"):
		return
	check_for_selection()
	# 推进技能运行时 CD 与施法前摇
	var sr: Node = Service.skill_runtime()
	if sr != null:
		sr.tick(delta)
	buffs.tick(delta)
	# 近战攻击冷却倒计时（仅近战武器使用）
	_melee_cd_primary = maxf(0.0, _melee_cd_primary - delta)
	_melee_cd_secondary = maxf(0.0, _melee_cd_secondary - delta)
	# 轻弩装弹倒计时（仅弩使用，与近战 CD 正交）
	_crossbow_reload_remaining = maxf(0.0, _crossbow_reload_remaining - delta)
	# 残影 buff 窗口倒计时（侧垫步触发后 1.5s 内首次攻击增伤）
	_sidestep_buff_remaining = maxf(0.0, _sidestep_buff_remaining - delta)
	# 落地后重置空中跳跃次数（二段跳）
	if is_on_floor():
		_air_jumps_used = 0
	# Hold E (use action) for 5 seconds to open Chest interactively
	# 宝箱战利品面板打开时不处理宝箱交互
	if _chest_loot_panel != null and is_instance_valid(_chest_loot_panel) and _chest_loot_panel.visible:
		chest_interact_time = 0.0
		pass
	elif _raycast_is_colliding(select_raycast) and select_raycast.get_collider() is Chest:
		var chest = select_raycast.get_collider() as Chest
		if Input.is_action_pressed("use"):
			chest_interact_time += delta
			if chest_interact_time >= CHEST_OPEN_DURATION:
				chest_interact_time = 0.0
				# 联机客户端：上送交互意图，由服务器权威开启（地牢联机禁止本地执行）
				if is_network_controlled() and multiplayer_driver != null:
					multiplayer_driver.send_interact(_entity_id_of(chest))
				else:
					chest.open_chest(true) # true = interactively opened, shows loot panel
		else:
			chest_interact_time = 0.0
	else:
		chest_interact_time = 0.0
		if interaction_input_enabled and _raycast_is_colliding(select_raycast):
			var collider := select_raycast.get_collider()
			if collider != null and not (collider is PickableItem) and collider.has_method("interact") and Input.is_action_just_pressed("use"):
				# 联机客户端：上送交互意图，由服务器权威执行（禁止本地直接调用 collider.interact）
				if is_network_controlled() and multiplayer_driver != null:
					multiplayer_driver.send_interact(_entity_id_of(collider))
				else:
					collider.interact(self)
	check_for_possible_action()

func process_movement(delta: float, speed_multiplier: float = 1.0) -> void:
	# 任意全屏面板打开时禁止移动（经营 HUD / 装备面板 / 宝箱面板等均通过 character_panel 组统一管理）
	if is_character_panel_visible():
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)
		return
	var input_3d_space := Vector3(input_dir.x, 0, -input_dir.y)
	var target_speed := run_speed if movement_input_enabled and Input.is_action_pressed("run") else walk_speed
	target_speed *= speed_multiplier
	# 里程碑被动：轻捷之行（AGI T2）移速 +10%
	var ap: Node = Service.attr_panel()
	if ap != null:
		target_speed *= ap.compute_move_speed_mult()
	if equipment != null and equipment.has_method("get_armor_move_speed_mult"):
		target_speed *= equipment.get_armor_move_speed_mult()
	target_speed *= get_combat_speed_multiplier()
	var desired_velocity := transform.basis * input_3d_space * target_speed
	if input_3d_space == Vector3.ZERO:
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)

## 联机：服务器权威快照应用到本地真实 Player（位置/朝向由服务器决定，客户端不可信）。
## 由 ClientCommandDriver 在收到本机玩家 player_snapshot 时调用。
## 直接重写 global_position 并清零 velocity，避免与本地物理积分相互打架。
func apply_remote_snapshot(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO

func process_pushback(delta: float) -> void:
	pushback_force = pushback_force.move_toward(Vector3.ZERO, delta * GROUND_FRICTION)
	velocity += pushback_force

func _input(event: InputEvent) -> void:
	var is_panel_visible := is_character_panel_visible()

	if event is InputEventMouseButton and event.pressed:
		if not is_panel_visible and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				equipment.cycle_weapon_slot(-1)
				get_viewport().set_input_as_handled()
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				equipment.cycle_weapon_slot(1)
				get_viewport().set_input_as_handled()
				return
		if not is_panel_visible and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
			
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not is_panel_visible:
		# 瞄准时降低鼠标灵敏度（望远镜效果），使远距离瞄准更精细
		var sens_mult := AIM_SENSITIVITY_MULT if is_weapon_aiming else 1.0
		var sens := mouse_sensitivity * sens_mult
		rotate_y(-event.relative.x * sens) # PI 3.14 => 180 degrees 
		camera.rotate_x(-event.relative.y * sens)
		camera.rotation.x = clampf(camera.rotation.x, MAX_ANGLE_LOOK_DOWN, MAX_ANGLE_LOOK_UP)

func switch_state(new_state: State, data: PlayerStateData = PlayerStateData.new()) -> void:
	if state_node != null and is_instance_valid(state_node):
		# The previous state is freed at the end of the frame. Disable it now so
		# its physics loop cannot run after a re-entrant combat transition.
		state_node.set_process(false)
		state_node.set_physics_process(false)
		state_node.queue_free()
	var state_map := {
		State.BLOCKING: PlayerStateBlocking,
		State.DYING: PlayerStateDying,
		State.GRABBING: PlayerStateGrabbing,
		State.CHARGING: PlayerStateCharging,
		State.HURT: PlayerStateHurt,
		State.KICKING: PlayerStateKicking,
		State.MOVING: PlayerStateMoving,
		State.PICKING_UP: PlayerStatePickingUp,
		State.ATTACK_PREPARING: PLAYER_STATE_ATTACK_PREPARING,
		State.AIMING: PLAYER_STATE_AIMING,
		State.SHOOTING: PLAYER_STATE_SHOOTING,
		State.SLASHING: PlayerStateSlashing,
		State.THROWING: PlayerStateThrowing,
	}
	var next_state_node: PlayerState = state_map[new_state].new(self, data)
	next_state_node.transition_requested.connect(switch_state)
	next_state_node.name = "State: " + State.keys()[new_state]
	state = new_state
	state_node = next_state_node
	# Use the local node. _enter_tree() may synchronously request another state;
	# reading the mutable state_node property here would add the replacement node
	# a second time and leave the original transition half-applied.
	add_child(next_state_node)

func process_gravity() -> void:
	if not is_on_floor():
		velocity.y -= gravity

func check_for_possible_action() -> void:
	# 宝箱战利品面板打开时不显示交互提示
	if _chest_loot_panel != null and is_instance_valid(_chest_loot_panel) and _chest_loot_panel.visible:
		if current_possible_action != "":
			# 空 hint_type 立即隐藏所有悬浮窗
			GameEvents.interaction_hint_changed.emit("", "", Vector2.ZERO)
		current_possible_action = ""
		_last_possible_action_collider = null
		return

	# 先确定当前碰撞体，仅据此判断是否需要重建提示字符串（避免每帧无谓的 tr()/拼接）
	var current_collider: Object = null
	if _raycast_is_colliding(select_raycast):
		var sel_collider = select_raycast.get_collider()
		# 过滤已释放的碰撞体（拾取后 queue_free 可能仍有一帧物理延迟）
		if sel_collider != null and is_instance_valid(sel_collider):
			current_collider = sel_collider
	elif combat_input_enabled and _raycast_is_colliding(kick_raycast):
		var kick_collider = kick_raycast.get_collider()
		if kick_collider != null and is_instance_valid(kick_collider) and kick_collider is Door:
			current_collider = kick_collider

	var collider_changed := current_collider != _last_possible_action_collider
	# 宝箱开启动画进度（百分比）每帧变化，必须重建字符串
	var chest_in_progress := current_collider is Chest and Input.is_action_pressed("use")
	# 碰撞体未变且非宝箱进度更新：提示内容与上一帧完全一致，跳过 tr()/拼接/emit
	if not collider_changed and not chest_in_progress:
		return

	var new_action := ""
	var hint_type := ""
	var hint_screen_pos := Vector2.ZERO
	if _raycast_is_colliding(select_raycast):
		current_collider = select_raycast.get_collider()
		# 过滤已释放的碰撞体（与首次扫描一致）
		if current_collider != null and not is_instance_valid(current_collider):
			current_collider = null
		var collider = current_collider
		if collider is PickableItem:
			var item_name := ""
			if collider.has_method("get_item_name"):
				item_name = collider.get_item_name()
			new_action = "[E] %s %s" % [tr("Pick Up"), tr(item_name)]
			hint_type = "pickup"
		elif collider is Chest:
			if Input.is_action_pressed("use"):
				var progress = int((chest_interact_time / CHEST_OPEN_DURATION) * 100.0)
				progress = clampi(progress, 0, 100)
				new_action = "%s\n%s %d%%" % [tr("Chest"), tr("Opening..."), progress]
			else:
				new_action = "%s\n%s" % [tr("Chest"), tr("Hold [E] to Open (5s)")]
			hint_type = "chest"
		elif collider != null and collider.has_method("interact"):
			var action_name := tr("Object")
			if "interaction_name" in collider and String(collider.interaction_name) != "":
				action_name = tr(String(collider.interaction_name))
			var verb := tr("[E] Interact")
			if "interaction_verb" in collider and String(collider.interaction_verb) != "":
				verb = "[E] %s" % tr(String(collider.interaction_verb))
			new_action = "%s\n%s" % [action_name, verb]
			hint_type = "interact"
		elif collider != null and collider.has_method("get_item_name"):
			var item_name: String = collider.get_item_name()
			new_action = "[E] %s %s" % [tr("Pick Up"), tr(item_name)]
			hint_type = "pickup"
		# 计算碰撞点的屏幕坐标用于悬浮窗定位（显示在物体右侧）
		hint_screen_pos = _get_raycast_screen_position(select_raycast)
	elif combat_input_enabled and _raycast_is_colliding(kick_raycast):
		var kick_door = kick_raycast.get_collider()
		if kick_door != null and is_instance_valid(kick_door) and kick_door is Door:
			current_collider = kick_door
			var door := kick_door as Door
			# 拾取/开门等提示统一显示在物体右侧的悬浮窗（已移除底部提示）
			new_action = tr(door.get_kick_prompt())
			hint_type = "door"
			hint_screen_pos = _get_raycast_screen_position(kick_raycast)

	# collider 变化或宝箱进度变化时才到达此处，重建并 emit 提示
	GameEvents.interaction_hint_changed.emit(hint_type, new_action, hint_screen_pos)
	current_possible_action = new_action
	_last_possible_action_collider = current_collider

## 获取射线碰撞点在屏幕上的投影坐标
func _get_raycast_screen_position(raycast: RayCast3D) -> Vector2:
	if not _raycast_is_colliding(raycast) or camera == null or not is_instance_valid(camera):
		var vp := get_viewport()
		if vp != null:
			return vp.get_visible_rect().size * 0.5
		return Vector2(960, 540)
	var collision_point := raycast.get_collision_point()
	return camera.unproject_position(collision_point)

func check_for_selection() -> void:
	var target_node: Node = null
	if _raycast_is_colliding(select_raycast):
		var collider := select_raycast.get_collider()
		# 过滤已释放的碰撞体（拾取后 queue_free 可能仍有一帧物理延迟）
		if collider != null and is_instance_valid(collider) and collider is PickableItem:
			target_node = collider
	# 清理已失效的焦点引用
	if current_pickable_focused_item != null and not is_instance_valid(current_pickable_focused_item):
		current_pickable_focused_item = null
	if target_node != current_pickable_focused_item:
		if current_pickable_focused_item and is_instance_valid(current_pickable_focused_item):
			current_pickable_focused_item.unhighlight()
		current_pickable_focused_item = target_node
	if current_pickable_focused_item is PickableItem and is_instance_valid(current_pickable_focused_item):
		current_pickable_focused_item.highlight()
		GameEvents.item_detail_changed.emit(
			DETAIL_POPUP.detail_for_pickable_item(current_pickable_focused_item),
			_get_raycast_screen_position(select_raycast))
	else:
		GameEvents.item_detail_changed.emit({}, Vector2.ZERO)

func try_receive_hit(source_enemy: Enemy, damage: int) -> void:
	if state_node == null or not is_instance_valid(state_node) or state_node.is_queued_for_deletion():
		return
	if state == State.HURT or state == State.DYING:
		return
	if state_node.can_get_hurt():
		var impact_direction := source_enemy.global_position.direction_to(global_position)
		var data := PlayerStateData.new().set_damage(damage).set_impact_direction(impact_direction)
		AudioManager.play("slash-hit", action_audio_stream_player)
		switch_state(State.HURT, data)
	elif state == State.BLOCKING:
		AudioManager.play("block", action_audio_stream_player)
		FxHelper.call_deferred("create_block_number", global_position, damage)
		# 持盾格挡：0.3s 完美窗口内不消耗盾牌耐久
		if _is_shield_block() and not _is_in_block_grace_window():
			equipment.apply_shield_damage(damage)
		source_enemy.try_stun()

## ARPG 战斗结算入口：接受 CombatEngine.DamageResult（含向量击退/秒眩晕/最终伤害）
## 由 CombatBridge.resolve_enemy_attack 产出，替换原 try_receive_hit 的硬编码 damage
const ME := preload("res://globals/combat/milestone_effects.gd")
func try_receive_hit_result(source_enemy: Enemy, result) -> void:
	if state_node == null or not is_instance_valid(state_node) or state_node.is_queued_for_deletion():
		return
	if state == State.HURT or state == State.DYING:
		return
	# 里程碑被动：侧垫步（AGI T1）受近战攻击 10% 概率完全免伤
	var is_melee: bool = result.attack_type == "melee"
	if ME.try_sidestep(is_melee):
		AudioManager.play("dodge", action_audio_stream_player)
		# 残影 afterimage（doc21 #7）：侧垫步成功后 1.5s 内首次攻击 +30%
		if has_mechanism_passive("afterimage"):
			set_sidestep_buff()
		return  # 完全免伤，跳过伤害结算
	# 穿透格挡的攻击无视格挡状态，直接造成伤害
	var can_hurt: bool = state_node.can_get_hurt() or result.ignores_block
	if can_hurt:
		var final_damage: int = result.final_damage
		final_damage = ME.apply_elemental_aegis(final_damage, result.attack_type == "spell")
		final_damage = ME.apply_thick_skin(final_damage)
		final_damage = buffs.consume_damage_absorb(final_damage, health.max_life if health != null else 0)
		var impact_direction := source_enemy.global_position.direction_to(global_position)
		if result.knockback_impulse != Vector3.ZERO:
			impact_direction = result.knockback_impulse.normalized()
		var data := PlayerStateData.new().set_damage(final_damage).set_impact_direction(impact_direction)
		# ARPG 实时击退力（米/秒）：写入 pushback_force 直接施加冲量
		# player_state_hurt.gd 会用 impact_direction * PUSHBACK_FORCE 叠加，这里通过 data 传递击退力
		data.knockback_force = result.knockback_force
		if "crit" in result:
			data.set_crit(bool(result.crit))
		AudioManager.play("slash-hit", action_audio_stream_player)
		# 暴击或含眩晕时进入 HURT（HURT 状态本身有硬直）；后续可扩展专门的 STUNNED 状态
		switch_state(State.HURT, data)
		# 受击累积体质经验（防御韧性）
		_accumulate_defense_exp()
	elif state == State.BLOCKING:
		AudioManager.play("block", action_audio_stream_player)
		FxHelper.call_deferred("create_block_number", global_position, result.final_damage)
		var in_grace := _is_in_block_grace_window()
		# 持盾格挡：完美窗口内不消耗盾牌耐久；双手武器格挡不消耗耐久
		if _is_shield_block() and not in_grace:
			equipment.apply_shield_damage(result.final_damage)
		# 完美格挡成功（窗口内）→ 触发完美格挡·增伤标记（下次攻击 ×1.5，doc21 #6）
		# 同时作用于持盾完美格挡与双手武器精确格挡；连续完美格挡仅刷新不叠加
		if in_grace and has_mechanism_passive("perfect_block_empower"):
			set_perfect_block_buff()
		source_enemy.try_stun()

## 受击后累积体质经验（防御韧性训练）
func _accumulate_defense_exp() -> void:
	var ap: Node = Service.attr_panel()
	if ap != null:
		ap.accumulate_attr("con", 2)  # 每次受击 +2 体质经验

# ============================================================================
# 动作格挡辅助（动作控制版：格挡由状态机判定，非概率投骰）
# ============================================================================

## 当前是否处于格挡状态
func is_currently_blocking() -> bool:
	return state == State.BLOCKING and state_node != null and is_instance_valid(state_node)

## 当前格挡是否为持盾格挡（否则为双手武器格挡）
func _is_shield_block() -> bool:
	if not is_currently_blocking():
		return false
	if state_node.has_method("get_block_mode"):
		# PlayerStateBlocking.BlockMode.SHIELD == 0
		return state_node.get_block_mode() == 0
	return equipment != null and equipment.has_shield()

## 当前是否处于完美格挡窗口（进入格挡后 0.3s 内）
func _is_in_block_grace_window() -> bool:
	if not is_currently_blocking():
		return false
	if state_node.has_method("is_in_grace_window"):
		return state_node.is_in_grace_window()
	return false

func set_tutorial_input_enabled(movement_enabled: bool, interaction_enabled: bool, combat_enabled: bool) -> void:
	movement_input_enabled = movement_enabled
	interaction_input_enabled = interaction_enabled
	combat_input_enabled = combat_enabled
	if not movement_input_enabled:
		input_dir = Vector2.ZERO

func can_pickup_object() -> bool:
	return interaction_input_enabled and current_pickable_focused_item != null and is_instance_valid(current_pickable_focused_item)

## 以下装备查询方法为薄代理，实际逻辑已下沉到 EquipmentComponent
func has_active_hand_equipment() -> bool:
	return equipment != null and equipment.has_hand_equipment()

func get_active_hand_weapon_data() -> WeaponData:
	if equipment == null:
		return null
	return equipment.get_active_weapon_data()

func get_active_weapon_attack_type() -> String:
	if equipment == null:
		return ""
	return equipment.get_active_weapon_attack_type()

func is_active_weapon_ranged() -> bool:
	return equipment != null and equipment.is_active_weapon_ranged()

## 当前武器是否为弩（弩无需拉弓蓄力，点击即射）
func is_active_weapon_crossbow() -> bool:
	return equipment != null and equipment.is_active_weapon_crossbow()

func is_active_weapon_two_handed() -> bool:
	return equipment != null and equipment.is_active_weapon_two_handed()

func can_block_with_active_equipment() -> bool:
	return equipment != null and equipment.can_block()

func can_dual_wield_attack_with_active_equipment() -> bool:
	return equipment != null and equipment.can_dual_wield()

func get_primary_weapon_release_state() -> int:
	if not combat_input_enabled or not has_active_hand_equipment():
		return -1
	return State.SHOOTING if is_active_weapon_ranged() else State.SLASHING

func get_primary_weapon_action_state() -> int:
	if get_primary_weapon_release_state() == -1:
		return -1
	return State.ATTACK_PREPARING

func make_primary_weapon_attack_data() -> PlayerStateData:
	return PlayerStateData.new().set_weapon_attack("action", "primary", get_primary_weapon_release_state())

func get_secondary_weapon_release_state() -> int:
	if not combat_input_enabled or not has_active_hand_equipment():
		return -1
	if can_dual_wield_attack_with_active_equipment():
		return State.SLASHING
	return -1

func get_secondary_weapon_action_state() -> int:
	if not combat_input_enabled or not has_active_hand_equipment():
		return -1
	if is_active_weapon_ranged():
		return State.AIMING
	if can_block_with_active_equipment():
		return State.BLOCKING
	if can_dual_wield_attack_with_active_equipment():
		return State.ATTACK_PREPARING
	return -1

func make_secondary_weapon_attack_data() -> PlayerStateData:
	return PlayerStateData.new().set_weapon_attack("block", "secondary", get_secondary_weapon_release_state())

func set_weapon_aiming(enabled: bool) -> void:
	is_weapon_aiming = enabled
	if camera == null:
		return
	# 望远镜效果：瞄准时大幅缩减 FOV，由 _process 平滑过渡
	target_camera_fov = maxf(default_camera_fov - AIM_FOV_REDUCTION, 30.0) if enabled else default_camera_fov
	if view_model != null and is_instance_valid(view_model) and view_model.has_method("set_aiming"):
		view_model.set_aiming(enabled)

## 获取准心瞄准的世界坐标点。
## 从摄像机中心发射射线，命中物体返回命中点；未命中返回远端点。
## 投射物/投掷武器都朝此点发射。
## 实现已提取到 PlayerAimHelper，此处为薄代理。
func get_aim_point(max_distance: float = 100.0) -> Vector3:
	return AIM_HELPER.get_aim_point(camera, global_position, get_rid(), max_distance)

## 构造朝向准心点的发射变换（-Z 指向目标）。
## muzzle_pos: 枪口/弓口世界坐标
## 实现已提取到 PlayerAimHelper，此处为薄代理。
func get_aim_transform(muzzle_pos: Vector3) -> Transform3D:
	return AIM_HELPER.get_aim_transform(camera, muzzle_pos, get_rid())

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
	var weapon := get_active_hand_weapon_data()
	return maxf(weapon.reach * CombatHitboxBuilder.REACH_SCALE, 0.8) if weapon != null else 1.2
	
func take_acid_damage() -> void:
	if state_node.can_die():
		switch_state(State.DYING)

func take_spike_damage(spikes_trap: SpikesTrap) -> void:
	var impact_direction := spikes_trap.global_position.direction_to(global_position)
	var data := PlayerStateData.new().set_damage(SPIKE_DAMAGE).set_impact_direction(impact_direction)
	switch_state(State.HURT, data)
	


## 宝箱交互开启回调：显示战利品面板
func _on_chest_opened(chest: Node) -> void:
	if _chest_loot_panel != null and is_instance_valid(_chest_loot_panel):
		_chest_loot_panel.queue_free()
		_chest_loot_panel = null
	var panel := CHEST_LOOT_PANEL_SCENE.instantiate()
	get_tree().root.add_child(panel)
	_chest_loot_panel = panel
	panel.show_for_chest(chest, self)


# ============================================================================
# 技能释放效果分发（委托给 PlayerSkillDispatcher）
# ============================================================================

func _on_skill_released(skill_id: String) -> void:
	SKILL_DISPATCHER.on_skill_released(self, skill_id)

func apply_kick_hit(enemy: Enemy) -> void:
	SKILL_DISPATCHER.apply_kick_hit(self, enemy)

func apply_action_skill_hit_to_enemy(enemy: Enemy, skill: Dictionary) -> void:
	SKILL_DISPATCHER.apply_action_skill_hit(self, enemy, skill)

# ============================================================================
# 战斗 Buff 代理（实际逻辑已提取到 CombatBuffComponent）
# ============================================================================

func add_combat_buff(buff_type: String, duration_sec: float, value: Variant) -> void:
	buffs.add(buff_type, duration_sec, value)

func get_combat_defense_bonus() -> int:
	return buffs.get_defense_bonus()

func get_combat_evade_bonus() -> float:
	return buffs.get_evade_bonus()

func get_combat_speed_multiplier() -> float:
	return buffs.get_speed_multiplier()

# ============================================================================
# 近战攻击冷却（仅近战武器）
# ============================================================================

## 触发一次近战攻击冷却（hand: "primary" 左键主手 / "secondary" 双持副手）
func start_melee_cooldown(hand: String) -> void:
	var dur := _compute_melee_cd_duration(hand)
	if hand == "secondary":
		_melee_cd_secondary = dur
		_melee_cd_secondary_max = dur
	else:
		_melee_cd_primary = dur
		_melee_cd_primary_max = dur

func _compute_melee_cd_duration(hand: String) -> float:
	var dur := MELEE_CD_BASE
	if is_active_weapon_two_handed():
		dur = MELEE_CD_BASE * MELEE_CD_TWO_HAND_MULT
	elif hand == "secondary":
		dur = MELEE_CD_DUAL_WIELD
	return dur * get_melee_cd_multiplier()

## 急速被动（cd_reduce）：冷却 ×0.85
func get_melee_cd_multiplier() -> float:
	if has_mechanism_passive("cd_reduce"):
		return CD_REDUCE_MULT
	return 1.0

## 某手是否处于近战冷却中
func is_melee_on_cooldown(hand: String) -> bool:
	if hand == "secondary":
		return _melee_cd_secondary > 0.0001
	return _melee_cd_primary > 0.0001

## 某手冷却恢复比例 0..1（1=就绪）。无近战武器/远程时恒为 1（就绪、不显示环）
func get_melee_cd_fill(hand: String) -> float:
	if hand == "secondary":
		if _melee_cd_secondary_max <= 0.0:
			return 1.0
		return clampf(1.0 - _melee_cd_secondary / _melee_cd_secondary_max, 0.0, 1.0)
	if _melee_cd_primary_max <= 0.0:
		return 1.0
	return clampf(1.0 - _melee_cd_primary / _melee_cd_primary_max, 0.0, 1.0)

## 查询机制类被动（操作强化，doc21 §3）是否已拥有
func has_mechanism_passive(id: String) -> bool:
	var sr: Node = Service.skill_runtime()
	if sr != null and sr.has_method("has_mechanism_passive"):
		return sr.has_mechanism_passive(id)
	return false

## 计算近战蓄力伤害倍率：未装备蓄力被动或蓄力为 0 → 1.0（无增伤）
func get_melee_charge_multiplier(charge_ratio: float) -> float:
	if charge_ratio <= 0.0:
		return 1.0
	if not has_mechanism_passive("charge"):
		return 1.0
	return lerpf(1.0, MELEE_CHARGE_MAX_MULT, clampf(charge_ratio, 0.0, 1.0))

## 完美格挡·增伤 buff：完美格挡成功时置位（doc21 #6）
func set_perfect_block_buff() -> void:
	_perfect_block_buff_active = true

## 消费完美格挡·增伤 buff：返回 true 并已消费（下次攻击命中时调用，仅一次）
func consume_perfect_block_buff() -> bool:
	if _perfect_block_buff_active:
		_perfect_block_buff_active = false
		return true
	return false

## 残影 buff：侧垫步成功触发后激活（doc21 #7 afterimage，需装备该机制被动）
func set_sidestep_buff() -> void:
	_sidestep_buff_remaining = SIDESTEP_BUFF_SEC

## 消费残影 buff：窗口内且首次攻击命中时返回 true 并清零（仅一次）
func consume_sidestep_buff() -> bool:
	if _sidestep_buff_remaining > 0.0001:
		_sidestep_buff_remaining = 0.0
		return true
	return false

# ============================================================================
# 轻弩装弹（仅弩；弓无装弹，走各自蓄力/速射逻辑）
# ============================================================================

## 触发一次装弹（射击后调用）。装弹期间 is_crossbow_reloading() 为 true，阻塞再次射击。
func start_crossbow_reload() -> void:
	var w := get_active_hand_weapon_data()
	var sec := CROSSBOW_RELOAD_FALLBACK_SEC
	if w != null and w.reload_time > 0.0:
		sec = w.reload_time
	# 机制类被动「快速装弹 quick_reload」：装弹时长 -20%（doc21 #10）
	if has_mechanism_passive("quick_reload"):
		sec *= 0.8
	_crossbow_reload_remaining = sec
	_crossbow_reload_total = sec
	# Presentation only. Delay reload until the fire kick has remained visible.
	# Completion is still governed exclusively by the timer above.
	if view_model != null and is_instance_valid(view_model) and view_model.has_method("play_action_after"):
		view_model.play_action_after(&"vm_crossbow_reload", 0.24, 1.2 / maxf(sec, 0.01))

## 弩是否正在装弹（装弹完成前不允许连续发射）
func is_crossbow_reloading() -> bool:
	return _crossbow_reload_remaining > 0.0001

## 弩装弹恢复比例 0..1（1=就绪可射）
func get_crossbow_reload_fill() -> float:
	if _crossbow_reload_total <= 0.0:
		return 1.0
	return clampf(1.0 - _crossbow_reload_remaining / _crossbow_reload_total, 0.0, 1.0)

# ============================================================================
# 跳跃 / 二段跳
# ============================================================================

## 执行一次跳跃：地面跳为基准跳；空中跳仅在拥有 air_dash 机制被动且仍有次数时触发（doc21 #4）
func do_jump() -> void:
	if is_on_floor():
		velocity.y = jump_force
		_air_jumps_used = 0
		AudioManager.play("jump", vocal_audio_stream_player)
		return
	if has_mechanism_passive("air_dash") and _air_jumps_used < AIR_JUMPS_MAX:
		velocity.y = jump_force * AIR_JUMP_FORCE_MULT
		_air_jumps_used += 1
		AudioManager.play("jump", vocal_audio_stream_player)

func _raycast_is_colliding(raycast: RayCast3D) -> bool:
	return raycast != null and is_instance_valid(raycast) and not raycast.is_queued_for_deletion() and raycast.is_colliding()

func is_character_panel_visible() -> bool:
	for node in get_tree().get_nodes_in_group("character_panel"):
		if node.is_inside_tree() and node.visible:
			return true
	return false
