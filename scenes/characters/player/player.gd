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
## 主摄像机渲染层（仅第 1 层）
const CAMERA_RENDER_MASK := 1

enum State {MOVING, PICKING_UP, THROWING, ATTACK_PREPARING, SLASHING, SHOOTING, AIMING, KICKING, BLOCKING, HURT, DYING, GRABBING, CHARGING}

var chest_interact_time : float = 0.0
const CHEST_OPEN_DURATION := 5.0

var movement_input_enabled := true
var interaction_input_enabled := true
var combat_input_enabled := true

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

func _ready() -> void:
	PhysicsSetup.setup_player(self)
	if has_meta("equipment_preview"):
		movement_input_enabled = false
		interaction_input_enabled = false
		combat_input_enabled = false
		_setup_player_light()
		return
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if camera != null:
		default_camera_fov = camera.fov
		target_camera_fov = camera.fov
	# 隐藏角色身体：将角色模型网格设到第 10 渲染层（摄像机 cull_mask=1 不渲染）
	# 第一人称视角下角色自身身体不可见，避免遮挡武器视图模型
	_hide_character_body()
	# 监听武器变更：拾取/切换武器后重新隐藏角色手上武器网格 + 同步 ViewModel
	GameEvents.weapon_changed.connect(_on_weapon_changed_for_view)
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.register_player(self)
	GameEvents.player_spawned.emit(self)
	GameEvents.current_keys_changed.connect(on_current_keys_changed)
	GameEvents.chest_opened.connect(_on_chest_opened)
	# 连接 SkillRuntime 信号
	var sr: Node = Service.skill_runtime()
	if sr != null:
		sr.skill_released.connect(_on_skill_released)
	switch_state(State.MOVING)
	# 角色自身发光——地牢极暗时照亮周围
	_setup_player_light()
	# 初始同步：如果已有武器，直接推送到 ViewModel
	_sync_view_model_weapon()

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
	light.light_energy = 2.4
	light.omni_range = 10.0
	light.omni_attenuation = 0.45
	light.shadow_enabled = false
	light.distance_fade_enabled = false
	light.position = Vector3(0, 1.5, 0)
	add_child(light)

func _process(delta: float) -> void:
	input_dir = Input.get_vector("strafe_left", "strafe_right", "backward", "forward") if movement_input_enabled else Vector2.ZERO
	if combat_input_enabled:
		_handle_skill_input()
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
		if f_skill != "":
			var weapon = equipment.weapon_data if equipment.has_weapon() else null
			var main_type := CB_LIB.get_weapon_class(weapon)
			var off_type := "shield" if equipment.has_shield() else ""
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
				chest.open_chest(true) # true = interactively opened, shows loot panel
		else:
			chest_interact_time = 0.0
	else:
		chest_interact_time = 0.0
		if interaction_input_enabled and _raycast_is_colliding(select_raycast):
			var collider := select_raycast.get_collider()
			if collider != null and not (collider is PickableItem) and collider.has_method("interact") and Input.is_action_just_pressed("use"):
				collider.interact(self)
	check_for_possible_action()

func process_movement(delta: float, speed_multiplier: float = 1.0) -> void:
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

func process_pushback(delta: float) -> void:
	pushback_force = pushback_force.move_toward(Vector3.ZERO, delta * GROUND_FRICTION)
	velocity += pushback_force

func _input(event: InputEvent) -> void:
	var is_panel_visible := is_character_panel_visible()
	# 宝箱战利品面板打开时也视为面板可见，阻止鼠标重新捕获
	if not is_panel_visible and _chest_loot_panel != null and is_instance_valid(_chest_loot_panel) and _chest_loot_panel.visible:
		is_panel_visible = true

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
	if state_node != null:
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
	state_node = state_map[new_state].new(self, data)
	state_node.transition_requested.connect(switch_state)
	state_node.name = "State: " + State.keys()[new_state]
	state = new_state
	add_child(state_node)

func process_gravity() -> void:
	if not is_on_floor():
		velocity.y -= gravity

func check_for_possible_action() -> void:
	var new_action := ""
	var hint_type := ""
	var hint_screen_pos := Vector2.ZERO
	var current_collider: Object = null
	# 宝箱战利品面板打开时不显示交互提示
	if _chest_loot_panel != null and is_instance_valid(_chest_loot_panel) and _chest_loot_panel.visible:
		if current_possible_action != "":
			# 空 hint_type 立即隐藏所有悬浮窗
			GameEvents.interaction_hint_changed.emit("", "", Vector2.ZERO)
		current_possible_action = ""
		_last_possible_action_collider = null
		return
	if _raycast_is_colliding(select_raycast):
		current_collider = select_raycast.get_collider()
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
			new_action = "%s\n%s" % [action_name, tr("[E] Interact")]
			hint_type = "interact"
		else:
			var item_name := ""
			if collider.has_method("get_item_name"):
				item_name = collider.get_item_name()
			new_action = "[E] %s %s" % [tr("Pick Up"), tr(item_name)]
			hint_type = "pickup"
		# 计算碰撞点的屏幕坐标用于悬浮窗定位（显示在物体右侧）
		hint_screen_pos = _get_raycast_screen_position(select_raycast)
	elif combat_input_enabled and _raycast_is_colliding(kick_raycast) and kick_raycast.get_collider() is Door:
		current_collider = kick_raycast.get_collider()
		var door := kick_raycast.get_collider() as Door
		# 拾取/开门等提示统一显示在物体右侧的悬浮窗（已移除底部提示）
		new_action = tr(door.get_kick_prompt())
		hint_type = "door"
		hint_screen_pos = _get_raycast_screen_position(kick_raycast)

	# 仅当 collider 变化、或宝箱开进度变化（new_action 含百分比）时才 emit
	var collider_changed := current_collider != _last_possible_action_collider
	if collider_changed or new_action != current_possible_action:
		# 唯一的交互提示：显示在物体右侧的悬浮窗（准星离开时 hint_type 为空，立即退出）
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
		if collider is PickableItem:
			target_node = collider
	if target_node != current_pickable_focused_item:
		if current_pickable_focused_item:
			current_pickable_focused_item.unhighlight()
		current_pickable_focused_item = target_node
	if current_pickable_focused_item is PickableItem:
		current_pickable_focused_item.highlight()
		GameEvents.item_detail_changed.emit(
			DETAIL_POPUP.detail_for_pickable_item(current_pickable_focused_item),
			_get_raycast_screen_position(select_raycast))
	else:
		GameEvents.item_detail_changed.emit({}, Vector2.ZERO)

func try_receive_hit(source_enemy: Enemy, damage: int) -> void:
	if state_node.can_get_hurt():
		var impact_direction := source_enemy.global_position.direction_to(global_position)
		var data := PlayerStateData.new().set_damage(damage).set_impact_direction(impact_direction)
		AudioManager.play("slash-hit", action_audio_stream_player)
		switch_state(State.HURT, data)
	elif state == State.BLOCKING:
		AudioManager.play("block", action_audio_stream_player)
		# 持盾格挡：0.3s 完美窗口内不消耗盾牌耐久
		if _is_shield_block() and not _is_in_block_grace_window():
			equipment.apply_shield_damage(damage)
		source_enemy.try_stun()

## ARPG 战斗结算入口：接受 CombatEngine.DamageResult（含向量击退/秒眩晕/最终伤害）
## 由 CombatBridge.resolve_enemy_attack 产出，替换原 try_receive_hit 的硬编码 damage
const ME := preload("res://globals/combat/milestone_effects.gd")
func try_receive_hit_result(source_enemy: Enemy, result) -> void:
	# 里程碑被动：侧垫步（AGI T1）受近战攻击 10% 概率完全免伤
	var is_melee: bool = result.attack_type == "melee"
	if ME.try_sidestep(is_melee):
		AudioManager.play("dodge", action_audio_stream_player)
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
		AudioManager.play("slash-hit", action_audio_stream_player)
		# 暴击或含眩晕时进入 HURT（HURT 状态本身有硬直）；后续可扩展专门的 STUNNED 状态
		switch_state(State.HURT, data)
		# 受击累积体质经验（防御韧性）
		_accumulate_defense_exp()
	elif state == State.BLOCKING:
		AudioManager.play("block", action_audio_stream_player)
		# 持盾格挡：0.3s 完美窗口内不消耗盾牌耐久；双手武器格挡不消耗耐久
		if _is_shield_block() and not _is_in_block_grace_window():
			equipment.apply_shield_damage(result.final_damage)
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
	return interaction_input_enabled and current_pickable_focused_item != null

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
	return maxf(weapon.reach, 0.8) if weapon != null else 1.2
	
func take_acid_damage() -> void:
	if state_node.can_die():
		switch_state(State.DYING)

func take_spike_damage(spikes_trap: SpikesTrap) -> void:
	var impact_direction := spikes_trap.global_position.direction_to(global_position)
	var data := PlayerStateData.new().set_damage(SPIKE_DAMAGE).set_impact_direction(impact_direction)
	switch_state(State.HURT, data)
	
func on_current_keys_changed(color: Door.KeyColor) -> void:
	if GameState.has_key(color):
		AudioManager.play("key-pickup", vocal_audio_stream_player)
	else:
		AudioManager.play("door-locked", vocal_audio_stream_player)

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

func _raycast_is_colliding(raycast: RayCast3D) -> bool:
	return raycast != null and is_instance_valid(raycast) and not raycast.is_queued_for_deletion() and raycast.is_colliding()

func is_character_panel_visible() -> bool:
	for node in get_tree().get_nodes_in_group("character_panel"):
		if node.is_inside_tree() and node.visible:
			return true
	return false
	
	
	
