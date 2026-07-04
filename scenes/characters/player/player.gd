class_name Player
extends CharacterBody3D

const SPIKE_DAMAGE := 5
const GROUND_FRICTION := 15.0
const MAX_ANGLE_LOOK_UP := deg_to_rad(70)
const MAX_ANGLE_LOOK_DOWN := deg_to_rad(-70)
# 技能/战斗桥接预加载（_on_skill_released 分发用）
const AS_DB := preload("res://globals/action_skills.gd")
const SD_DB := preload("res://globals/skill_data.gd")
const CB_LIB := preload("res://globals/combat_bridge.gd")
const CE_LIB := preload("res://globals/combat_engine.gd")
# 夜晚营业阶段酿酒台近距离检测（BrewingStation_Table @ -5,0,-4）
const BREWING_STATION_POS := Vector3(-5.0, 0.0, -4.0)
const BREWING_STATION_RANGE := 2.5

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

enum State {MOVING, PICKING_UP, THROWING, SLASHING, KICKING, BLOCKING, HURT, DYING, GRABBING, CHARGING}

var chest_interact_time : float = 0.0
const CHEST_OPEN_DURATION := 5.0

var current_possible_action : String = ""
var current_pickable_focused_item : PickableItem = null
var input_dir := Vector2.ZERO
var pushback_force := Vector3.ZERO
var state: State
var state_node: PlayerState

func _ready() -> void:
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.register_player(self)
	GameEvents.player_spawned.emit(self)
	GameEvents.current_keys_changed.connect(on_current_keys_changed)
	# 连接 SkillRuntime 信号
	var sr: Node = Engine.get_main_loop().root.get_node_or_null("SkillRuntime")
	if sr != null:
		sr.skill_released.connect(_on_skill_released)
	switch_state(State.MOVING)
	# 角色自身发光——地牢极暗时照亮周围
	_setup_player_light()

func _setup_player_light() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.6)
	light.light_energy = 0.8
	light.omni_range = 8.0
	light.omni_attenuation = 0.6
	light.position = Vector3(0, 1.5, 0)
	add_child(light)

func _process(_delta: float) -> void:
	input_dir = Input.get_vector("strafe_left", "strafe_right", "backward", "forward")
	_handle_skill_input()

## F/G 键技能释放：F 键动作技能（无媒介限制），G 键武器流派技能（受媒介限制）
func _handle_skill_input() -> void:
	var sr: Node = Engine.get_main_loop().root.get_node_or_null("SkillRuntime")
	if sr == null:
		return
	# F 键：动作技能（复用现有 kick 输入映射，F 键 physical_keycode 70）
	if Input.is_action_just_pressed("kick"):
		var f_skill: String = sr.get_slot_skill(sr.SLOT_F_ACTION)
		if f_skill != "":
			var main_type := "one_hand_melee" if equipment.has_weapon() else ""
			var off_type := "shield" if equipment.has_shield() else ""
			sr.start_release(f_skill, main_type, off_type)
	# G 键：武器流派技能
	if Input.is_action_just_pressed("skill_g"):
		var g_skill: String = sr.get_slot_skill(sr.SLOT_G_WEAPON)
		if g_skill != "":
			var main_type := "one_hand_melee" if equipment.has_weapon() else ""
			var off_type := "shield" if equipment.has_shield() else ""
			sr.start_release(g_skill, main_type, off_type)

func _physics_process(delta: float) -> void:
	process_gravity()
	process_pushback(delta)
	move_and_slide()
	check_for_selection()
	# 推进技能运行时 CD 与施法前摇
	var sr: Node = Engine.get_main_loop().root.get_node_or_null("SkillRuntime")
	if sr != null:
		sr.tick(delta)
	# 夜晚营业阶段：靠近酿酒台显示 brewing_panel
	_check_brewing_station_proximity()
	# Hold E (use action) for 5 seconds to open Chest interactively
	if select_raycast.is_colliding() and select_raycast.get_collider() is Chest:
		var chest = select_raycast.get_collider() as Chest
		if Input.is_action_pressed("use"):
			chest_interact_time += delta
			if chest_interact_time >= CHEST_OPEN_DURATION:
				chest_interact_time = 0.0
				chest.open_chest(true) # true = interactively opened, drops all loot
		else:
			chest_interact_time = 0.0
	else:
		chest_interact_time = 0.0
	check_for_possible_action()

## 夜晚营业阶段靠近酿酒台（BrewingStation_Table @ -5,0,-4）时显示 brewing_panel，离开隐藏。
## 仅在酒馆场景且夜晚营业阶段生效。
func _check_brewing_station_proximity() -> void:
	# 仅夜晚营业阶段生效
	var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	if tm == null or tm.current_phase != tm.Phase.NIGHT_TAVERN:
		return
	var panel: Control = _find_brewing_panel()
	if panel == null:
		return
	var dist: float = global_position.distance_to(BREWING_STATION_POS)
	panel.visible = dist < BREWING_STATION_RANGE

## 在 CanvasLayer/HUDLayer/tavern_ui 下查找 BrewingPanel 节点
func _find_brewing_panel() -> Control:
	var root: Node = Engine.get_main_loop().root
	# 遍历场景树查找 BrewingPanel（挂在 CanvasLayer 之下）
	for child in root.get_children():
		if child is CanvasLayer:
			for sub in child.get_children():
				if sub.has_node("BrewingPanel"):
					return sub.get_node("BrewingPanel") as Control
	return null

func process_movement(delta: float, speed_multiplier: float = 1.0) -> void:
	var input_3d_space := Vector3(input_dir.x, 0, -input_dir.y)
	var target_speed := run_speed if Input.is_action_pressed("run") else walk_speed
	target_speed *= speed_multiplier
	# 里程碑被动：轻捷之行（AGI T2）移速 +10%
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap != null:
		target_speed *= ap.compute_move_speed_mult()
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
	var is_panel_visible := false
	for node in get_tree().get_nodes_in_group("character_panel"):
		if node.is_inside_tree() and node.visible:
			is_panel_visible = true
			break

	if event is InputEventMouseButton and event.pressed:
		if not is_panel_visible and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
			
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not is_panel_visible:
		rotate_y(-event.relative.x * mouse_sensitivity) # PI 3.14 => 180 degrees 
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
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
	if select_raycast.is_colliding():
		var collider = select_raycast.get_collider()
		if collider is PickableItem:
			var item_name = collider.get_item_name()
			new_action = "%s\n%s" % [item_name, tr("[E] Pick Up")]
		elif collider is Chest:
			if Input.is_action_pressed("use"):
				var progress = int((chest_interact_time / CHEST_OPEN_DURATION) * 100.0)
				progress = clampi(progress, 0, 100)
				new_action = "%s\n%s %d%%" % [tr("Chest"), tr("Opening..."), progress]
			else:
				new_action = "%s\n%s" % [tr("Chest"), tr("Hold [E] to Open (5s)")]
		else:
			new_action = tr("[E] Pick Up")
	elif kick_raycast.is_colliding() and kick_raycast.get_collider() is Door:
		new_action = tr("[F] Open")
		
	if new_action != current_possible_action:
		GameEvents.possible_action_changed.emit(new_action)
	current_possible_action = new_action

func check_for_selection() -> void:
	var target_node: Node = null
	if select_raycast.is_colliding():
		var collider := select_raycast.get_collider()
		if collider is PickableItem:
			target_node = collider
	if target_node != current_pickable_focused_item:
		if current_pickable_focused_item:
			current_pickable_focused_item.unhighlight()
		current_pickable_focused_item = target_node
		if current_pickable_focused_item is PickableItem:
			current_pickable_focused_item.highlight()

func try_receive_hit(source_enemy: Enemy, damage: int) -> void:
	if state_node.can_get_hurt():
		var impact_direction := source_enemy.global_position.direction_to(global_position)
		var data := PlayerStateData.new().set_damage(damage).set_impact_direction(impact_direction)
		AudioManager.play("slash-hit", action_audio_stream_player)
		switch_state(State.HURT, data)
	elif state == State.BLOCKING:
		AudioManager.play("block", action_audio_stream_player)
		equipment.apply_shield_damage(damage)
		source_enemy.try_stun()

## ARPG 战斗结算入口：接受 CombatEngine.DamageResult（含向量击退/秒眩晕/最终伤害）
## 由 CombatBridge.resolve_enemy_attack 产出，替换原 try_receive_hit 的硬编码 damage
const CB := preload("res://globals/combat_bridge.gd")
const ME := preload("res://globals/milestone_effects.gd")

func try_receive_hit_result(source_enemy: Enemy, result) -> void:
	# 里程碑被动：侧垫步（AGI T1）受近战攻击 10% 概率完全免伤
	var is_melee: bool = true  # 集成期默认近战，待 DamageResult 携带 attack_type 后精确判定
	if ME.try_sidestep(is_melee):
		AudioManager.play("dodge", action_audio_stream_player)
		return  # 完全免伤，跳过伤害结算
	if state_node.can_get_hurt():
		var impact_direction := source_enemy.global_position.direction_to(global_position)
		if result.knockback_impulse != Vector3.ZERO:
			impact_direction = result.knockback_impulse.normalized()
		var data := PlayerStateData.new().set_damage(result.final_damage).set_impact_direction(impact_direction)
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
		equipment.apply_shield_damage(result.final_damage)
		source_enemy.try_stun()

## 受击后累积体质经验（防御韧性训练）
func _accumulate_defense_exp() -> void:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap != null:
		ap.accumulate_attr("con", 2)  # 每次受击 +2 体质经验

func can_pickup_object() -> bool:
	return current_pickable_focused_item != null
	
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


# ============================================================================
# 技能释放效果分发（由 SkillRuntime.skill_released 信号驱动）
# ============================================================================

## 技能释放完成（施法前摇结束）后触发实际游戏内效果。
## 按技能 id 分发：动作技能→位移/状态切换；武器技能→CombatBridge 结算。
func _on_skill_released(skill_id: String) -> void:
	# 动作技能
	var action_skill: Dictionary = AS_DB.get_skill_by_id(skill_id)
	if not action_skill.is_empty():
		_dispatch_action_skill(action_skill)
		return
	# 武器流派技能
	var weapon_skill: Dictionary = SD_DB.get_skill_by_id(skill_id)
	if not weapon_skill.is_empty():
		_dispatch_weapon_skill(weapon_skill)

## 动作技能分发：踢击/冲撞/抓取投掷/滑铲/战术滑步
func _dispatch_action_skill(skill: Dictionary) -> void:
	var enum_val: int = int(skill.get("enum", -1))
	match enum_val:
		AS_DB.ActionSkill.KICK:
			# 踢击：复用现有 KICKING 状态（含踢门/踢敌逻辑）
			switch_state(State.KICKING)
		AS_DB.ActionSkill.CHARGE:
			# 冲撞：需先按 Shift 跑起来才能释放；锁定方向 + 加速 + 撞敌伤害击退
			if Input.is_action_pressed("run"):
				switch_state(State.CHARGING)
			else:
				print("[Player] 冲撞需要先按 Shift 跑起来")
		AS_DB.ActionSkill.GRAB_THROW:
			# 抓取投掷：前方 raycast 命中敌人 → GRABBING 状态手持 → 左键扔出
			if kick_raycast.is_colliding():
				var target := kick_raycast.get_collider() as Enemy
				if target != null:
					var data := PlayerStateData.new().set_grabbed_enemy(target)
					switch_state(State.GRABBING, data)
				else:
					print("[Player] 抓取未命中敌人")
			else:
				print("[Player] 抓取未命中敌人")
		AS_DB.ActionSkill.SLIDE:
			# 滑铲：低位前冲 + 无敌帧
			_apply_dash(int(skill.get("range_m", 4.0)), 8.0)
		AS_DB.ActionSkill.TACTICAL_STEP:
			# 战术滑步：短距侧移 + 闪避帧
			_apply_dash(int(skill.get("range_m", 3.0)), 6.0)

## 武器流派技能分发：通过 CombatBridge 结算前方敌人
func _dispatch_weapon_skill(skill: Dictionary) -> void:
	var weapon = equipment.weapon_data if equipment.has_weapon() else null
	var attrs := _get_player_attrs_inline()
	var level := _get_player_level_inline()
	var main_type := "one_hand_melee" if equipment.has_weapon() else ""
	var off_type := "shield" if equipment.has_shield() else ""
	if weapon_reach_raycast.is_colliding():
		var enemy := weapon_reach_raycast.get_collider() as Enemy
		if enemy != null:
			var atk_forward := -global_transform.basis.z.normalized()
			var def_forward := -enemy.global_transform.basis.z.normalized()
			var is_back: bool = CB_LIB.is_backstab(atk_forward, def_forward)
			var result = CB_LIB.resolve_player_attack(self, enemy, weapon, main_type, off_type, attrs, level, is_back)
			if result.hit:
				enemy.try_receive_hit_result(self, result)

## 向前冲刺位移（冲撞/滑铲/战术滑步通用）
## distance_m: 冲刺距离（米）；speed_mps: 冲刺速度（米/秒）
func _apply_dash(distance_m: int, speed_mps: float) -> void:
	var forward := -global_transform.basis.z.normalized()
	# 瞬时位移近似：直接施加 pushback_force 持续推动
	pushback_force += forward * speed_mps

## 对 kick_raycast 命中的敌人施加技能伤害（踢击/冲撞/抓取投掷通用）
func _apply_skill_hit_to_kick_raycast(skill: Dictionary) -> void:
	if not kick_raycast.is_colliding():
		return
	var enemy := kick_raycast.get_collider() as Enemy
	if enemy == null:
		return
	# 构造简化 DamageResult：动作技能无武器，用徒手基础伤害
	var knockback_m: float = float(skill.get("knockback_m", 0.0))
	var stun_sec: float = float(skill.get("stun_sec", 0.0))
	var forward := -global_transform.basis.z.normalized()
	var result := CE_LIB.DamageResult.new()
	result.hit = true
	result.final_damage = int(max(1, skill.get("damage_mult", 0.5) * 4))
	result.knockback_force = knockback_m * 2.0
	result.knockback_impulse = forward * knockback_m
	result.stun_duration = stun_sec
	enemy.try_receive_hit_result(self, result)

## 内联属性获取（避免与状态脚本重复，集成期简化为默认值+AttrPanel 读）
func _get_player_attrs_inline() -> Dictionary:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap != null:
		return ap.get_player_attrs()
	return {"str": 10, "dex": 10, "agi": 10, "con": 10, "per": 10, "mag": 10}

func _get_player_level_inline() -> int:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap != null:
		return ap.get_level()
	return 1
	
	
	
