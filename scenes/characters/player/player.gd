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
const PLAYER_ANIMATION_PROFILE := preload("res://globals/visual/player_animation_profile.gd")
const PLAYER_VISION_LIGHT_NAME := "PlayerVisionLight"
const PLAYER_VISION_TERRAIN_MASK := 1 << 0
const DUNGEON_RENDERING_CONFIG := preload("res://scenes/expedition/dungeon_rendering_config.gd")
const HITBOX_BUILDER := preload("res://globals/combat/combat_hitbox_builder.gd")
const SKILL_DISPATCHER := preload("res://scenes/characters/player/player_skill_dispatcher.gd")
const SPE := preload("res://globals/combat/style_passive_effects.gd")
const Service := preload("res://globals/core/service.gd")
const COMBAT_PROGRESSION := preload("res://globals/combat/combat_progression.gd")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const CHEST_LOOT_PANEL_SCENE := preload("res://scenes/ui/chest_loot_panel.tscn")
const RWPH := preload("res://globals/combat/rune_word_passive_hooks.gd")
const COMBAT_BUFF_COMPONENT := preload("res://scenes/characters/component/combat_buff_component.gd")
const AIM_HELPER := preload("res://scenes/characters/player/player_aim_helper.gd")
const SPELL_ACCESS_POLICY := preload("res://globals/combat/spell_access_policy.gd")
const PLAYER_SPELL_CASTER := preload("res://scenes/characters/player/player_spell_caster.gd")
const ARCANE_SWORD_PASSIVE_ID := SPELL_ACCESS_POLICY.ARCANE_SWORD_PASSIVE_ID
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

## Mouse action state captured at the Player input boundary. Polling
## Input.is_action_pressed() from a short-lived child state can miss the
## release edge when the viewport changes focus or consumes the mouse event.
## Keep the last observed state here so attack preparation and network intent
## handling use the same press/hold/release signal.
var _weapon_action_held: Dictionary = {}
var _weapon_action_pressed: Dictionary = {}
var _weapon_action_pressed_frame: Dictionary = {}

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
## 固定法术施法控制器：选槽、单机权威调用或联机意图上送。
var spell_caster := PLAYER_SPELL_CASTER.new()

# 符文之语「奔雷之语」奔跑撞击冷却（秒，0 = 可触发）
var _sprint_impact_cd: float = 0.0

## 兼容性：combat_buffs 字典直接访问（委托给 buffs 组件）
var combat_buffs: Dictionary:
	get:
		return buffs.get_buffs_dict()

## 战斗运行时计时/状态组件（从 player.gd 提取，模式同 CombatBuffComponent）：
## 近战冷却 / 轻弩装弹 / 二段跳 / 完美格挡·残影 buff / 流派专精被动运行时状态
const PLAYER_COMBAT_RUNTIME := preload("res://scenes/characters/player/player_combat_runtime.gd")
var combat_rt := PLAYER_COMBAT_RUNTIME.new()

## 外部状态机/测试引用的战斗常量（实际值由 PlayerCombatRuntime 统一定义）
const MELEE_CHARGE_FULL_SEC := PLAYER_COMBAT_RUNTIME.MELEE_CHARGE_FULL_SEC      # 蓄满所需按住时长（秒）
const MELEE_CHARGE_MAX_MULT := PLAYER_COMBAT_RUNTIME.MELEE_CHARGE_MAX_MULT      # 蓄满伤害倍率（doc21 #1）
const PERFECT_BLOCK_BUFF_MULT := PLAYER_COMBAT_RUNTIME.PERFECT_BLOCK_BUFF_MULT  # 完美格挡后下次攻击 ×1.5（doc21 #6）
const SIDESTEP_BUFF_MULT := PLAYER_COMBAT_RUNTIME.SIDESTEP_BUFF_MULT            # 残影首次攻击 ×1.3（doc21 #7）
const CROSSBOW_RELOAD_FALLBACK_SEC := PLAYER_COMBAT_RUNTIME.CROSSBOW_RELOAD_FALLBACK_SEC
# 符文之语「奔雷之语」奔跑撞击参数
const SPRINT_IMPACT_CD_SEC := 0.5           # 同一目标撞击冷却（秒）
const SPRINT_IMPACT_MIN_SPEED := 5.0        # 触发撞击所需的最低水平移速（m/s）
const SPRINT_IMPACT_DAMAGE_PER_SPEED := 2.5 # 伤害 = 当前水平速度 × 此系数
const SPRINT_IMPACT_KNOCKBACK := 4.0        # 撞击击退力（m/s）
const SPRINT_IMPACT_STUN_SEC := 0.3         # 撞击眩晕（秒）
const SPRINT_IMPACT_PHYSICAL_MULT := 1.5    # 被撞者撞墙时的地形撞击伤害倍率

## 兼容性属性：测试直接读写主/副手近战冷却（委托给 combat_rt）
var _melee_cd_primary: float:
	get:
		return combat_rt.melee_cd_primary
	set(value):
		combat_rt.melee_cd_primary = value
var _melee_cd_secondary: float:
	get:
		return combat_rt.melee_cd_secondary
	set(value):
		combat_rt.melee_cd_secondary = value

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

func _ready() -> void:
	# 角色身体材质适配：与 enemy.gd 保持一致，由 VoxelLightingAdapter 统一适配 GLB 内嵌材质。
	# 仅适配 character 节点，避免与 ViewModel 的武器/盾牌专用适配（apply_weapon_tree）冲突。
	# 开关关闭时 _adapt_material 对 StandardMaterial3D 返回 null（不设 override），
	# 对 ShaderMaterial 写入 pixel_lighting_enabled=0.0（回退标准 Lambert）。
	var _char_node := get_node_or_null("character")
	if _char_node != null:
		VOXEL_LIGHTING.apply_to_tree(_char_node, true)
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
	# ViewModel 自己持有第一人称武器/盾牌视觉副本和动作库，第三人称
	# AnimationPlayer 仍单独负责角色骨骼、命中动作时序与状态退出。
	# 监听武器变更：重新隐藏第三人称装备网格并同步第一人称视觉副本。
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
	# 初始同步：如果已有武器，直接同步第一人称视觉副本。
	_sync_view_model_weapon()

## 统一生命周期清理：场景切换或 queue_free 时解绑全局信号、注销 GameState、
## 清除焦点/弹窗、安全释放 state_node。避免全局引用残留和已释放对象回调。
func _exit_tree() -> void:
	# 1. 解绑 _ready 中连接的全局信号（防止 Player 释放后信号回调解引用失效对象）
	if GameEvents.weapon_changed.is_connected(_on_weapon_changed_for_view):
		GameEvents.weapon_changed.disconnect(_on_weapon_changed_for_view)
	if GameEvents.chest_opened.is_connected(_on_chest_opened):
		GameEvents.chest_opened.disconnect(_on_chest_opened)
	var sr: Node = Service.skill_runtime()
	if sr != null and is_instance_valid(sr) and sr.skill_released.is_connected(_on_skill_released):
		sr.skill_released.disconnect(_on_skill_released)
	# 2. 注销 GameState 全局引用（current_player → null）
	var gs = Service.game_state()
	if gs != null:
		gs.unregister_player(self)
	# 3. 清除拾取焦点和悬浮窗（防止 UI 残留在已销毁的玩家上）
	if current_pickable_focused_item != null and is_instance_valid(current_pickable_focused_item):
		current_pickable_focused_item.unhighlight()
	current_pickable_focused_item = null
	if current_possible_action != "":
		GameEvents.interaction_hint_changed.emit("", "", Vector2.ZERO)
	current_possible_action = ""
	_last_possible_action_collider = null
	# 4. 安全释放 state_node：_begin_exit 同步断开信号、禁用处理、调用 _on_exit
	if state_node != null and is_instance_valid(state_node):
		state_node._begin_exit()
		state_node.queue_free()
		state_node = null

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
	# 流派专精被动运行时衰减（暴风骤雨层数过期 / 元素环倒计时，doc21 §一）
	combat_rt.tick_style_passives(delta)
	# 符文之语持续型被动（明护恢复/知苦自伤/构造体攻击等）
	RWPH.on_player_tick(self, delta)

func _hide_character_body() -> void:
	var character_node := get_node_or_null("character")
	if character_node == null:
		return
	_set_render_layer_recursive(character_node, CHARACTER_BODY_RENDER_LAYER)

## 武器变更回调：重新隐藏角色身体，并同步第一人称视觉副本
func _on_weapon_changed_for_view(_weapon_data: Variant) -> void:
	# 拾取/切换武器后，EquipedItem 会新建 GLB 网格（默认在 layer 1）
	# 需要重新将这些网格移到第 10 层，使摄像机（cull_mask=1）不渲染它们
	_hide_character_body()
	# 同步第一人称视觉副本；它不参与装备、碰撞或伤害逻辑。
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
	var vision_config := DUNGEON_RENDERING_CONFIG.default()
	var existing := get_node_or_null(PLAYER_VISION_LIGHT_NAME) as OmniLight3D
	if existing != null:
		existing.visible = true
		existing.light_color = vision_config.player_vision_color
		existing.light_energy = vision_config.player_vision_base_energy
		existing.omni_range = vision_config.player_vision_base_range
		existing.omni_attenuation = vision_config.player_vision_attenuation
		existing.shadow_enabled = false
		existing.distance_fade_enabled = false
		existing.light_cull_mask = PLAYER_VISION_TERRAIN_MASK
		existing.position = Vector3(0, 1.5, 0)
		return
	var light := OmniLight3D.new()
	light.name = PLAYER_VISION_LIGHT_NAME
	light.light_color = vision_config.player_vision_color
	light.visible = true
	light.light_energy = vision_config.player_vision_base_energy
	light.omni_range = vision_config.player_vision_base_range
	light.omni_attenuation = vision_config.player_vision_attenuation
	light.shadow_enabled = false
	light.distance_fade_enabled = false
	light.light_cull_mask = PLAYER_VISION_TERRAIN_MASK
	light.position = Vector3(0, 1.5, 0)
	add_child(light)

func _process(delta: float) -> void:
	input_dir = Input.get_vector("strafe_left", "strafe_right", "backward", "forward") if movement_input_enabled else Vector2.ZERO
	_handle_jump_input()
	if combat_input_enabled:
		_handle_skill_input()
	_process_passive_effects(delta)
	# 平滑过渡摄像机 FOV（望远镜效果）
	if camera != null and is_instance_valid(camera):
		camera.fov = lerpf(camera.fov, target_camera_fov, delta * FOV_LERP_SPEED)

func _handle_spell_input() -> void:
	if Input.is_action_just_pressed("spell_slot_1"): spell_caster.select_slot(0)
	elif Input.is_action_just_pressed("spell_slot_2"): spell_caster.select_slot(1)
	elif Input.is_action_just_pressed("spell_slot_3"): spell_caster.select_slot(2)
	elif Input.is_action_just_pressed("spell_slot_4"): spell_caster.select_slot(3)
	elif Input.is_action_just_pressed("spell_slot_5"): spell_caster.select_slot(4)
	var spell_ui_open := false
	var gs := Service.game_state()
	if gs != null and gs.has_method("is_spell_interface_open"):
		spell_ui_open = bool(gs.is_spell_interface_open())
	if Input.is_action_just_pressed("cast_spell") and not spell_ui_open:
		spell_caster.cast_selected(self, get_tree().current_scene)

## F/G 键技能释放：F 键动作技能（无媒介限制），G 键武器流派技能（受媒介限制）
func _handle_skill_input() -> void:
	_handle_spell_input()
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
			var weapon = equipment.weapon_data if equipment != null and equipment.has_weapon() else null
			var main_type := CB_LIB.get_weapon_class(weapon)
			var off_type := "shield" if (equipment != null and equipment.has_shield()) else ""
			sr.start_release(g_skill, main_type, off_type, self, sr.SLOT_G_WEAPON)

## Jump is handled at the Player boundary so a just-pressed Space event is not
## lost when a short-lived attack, aim, block, or hurt state owns the child
## state loop for that frame. The state-specific movement code only integrates
## velocity; it no longer competes for the edge-triggered input event.
func _handle_jump_input() -> void:
	if not movement_input_enabled or not Input.is_action_just_pressed("jump"):
		return
	if is_character_panel_visible() or state == State.DYING:
		return
	do_jump()

func _physics_process(delta: float) -> void:
	process_gravity()
	process_pushback(delta)
	move_and_slide()
	_sync_first_person_equipment_motion()
	if has_meta("equipment_preview"):
		return
	# 符文之语「奔雷之语」：奔跑撞击敌人
	_check_sprint_impact(delta)
	check_for_selection()
	# 推进技能运行时 CD 与施法前摇
	var sr: Node = Service.skill_runtime()
	if sr != null:
		sr.tick(delta)
	buffs.tick(delta)
	# 战斗运行时计时推进：近战冷却 / 轻弩装弹 / 残影窗口 / 落地重置二段跳
	combat_rt.tick_physics(delta, is_on_floor())
	# Hold E (use action) for 5 seconds to open Chest interactively
	# 宝箱战利品面板打开时不处理宝箱交互
	if _chest_loot_panel != null and is_instance_valid(_chest_loot_panel) and _chest_loot_panel.visible:
		chest_interact_time = 0.0
		pass
	else:
		# 统一取有效碰撞体：过滤已释放对象（queue_free 一帧延迟导致的失效引用）。
		# 旧实现分别调用 select_raycast.get_collider() 且无 is_instance_valid 守卫，
		# 宝箱/门在被 queue_free 后下一帧仍可能被射线命中并解引用为已释放对象。
		var select_collider := _get_valid_select_collider()
		if select_collider is Chest and _can_interact_collider(select_collider):
			var chest := select_collider as Chest
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
			if interaction_input_enabled and select_collider != null and not (select_collider is PickableItem) and select_collider.has_method("interact") and _can_interact_collider(select_collider) and Input.is_action_just_pressed("use"):
				# 联机客户端：上送交互意图，由服务器权威执行（禁止本地直接调用 collider.interact）
				if is_network_controlled() and multiplayer_driver != null:
					multiplayer_driver.send_interact(_entity_id_of(select_collider))
				else:
					select_collider.interact(self)
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
	_track_weapon_action_input(event)
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
		# 法术编辑界面持有鼠标期间，Player 不得把左键点击抢回捕获模式。
		# 防御：Player 不在场景树（headless 单测/预制体）时 get_tree() 为 null，跳过 HUD 查询。
		var tree := get_tree()
		var hud: Node = tree.get_first_node_in_group("combat_hud") if tree != null else null
		var spell_ui_visible: bool = hud != null and hud.has_method("is_spell_interface_visible") and hud.is_spell_interface_visible()
		if not is_panel_visible and not spell_ui_visible and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
			
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not is_panel_visible:
		if view_model != null and is_instance_valid(view_model) and view_model.has_method("add_look_input"):
			view_model.add_look_input(event.relative)
		# 瞄准时降低鼠标灵敏度（望远镜效果），使远距离瞄准更精细
		var sens_mult := AIM_SENSITIVITY_MULT if is_weapon_aiming else 1.0
		var sens := mouse_sensitivity * sens_mult
		rotate_y(-event.relative.x * sens) # PI 3.14 => 180 degrees 
		camera.rotate_x(-event.relative.y * sens)
		camera.rotation.x = clampf(camera.rotation.x, MAX_ANGLE_LOOK_DOWN, MAX_ANGLE_LOOK_UP)


## Supplies presentation-only locomotion state to the weapon/shield ViewModel.
## The ViewModel never reads movement input itself and cannot affect physics.
func _sync_first_person_equipment_motion() -> void:
	if view_model == null or not is_instance_valid(view_model) or not view_model.has_method("set_motion_state"):
		return
	var local_velocity := global_transform.basis.inverse() * velocity
	var sprinting := movement_input_enabled and Input.is_action_pressed("run")
	view_model.set_motion_state(local_velocity, is_on_floor(), sprinting)

func _track_weapon_action_input(event: InputEvent) -> void:
	if event == null:
		return
	var action_name := ""
	var mouse_event: InputEventMouseButton = null
	if event is InputEventMouseButton:
		mouse_event = event as InputEventMouseButton
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				action_name = "action"
			MOUSE_BUTTON_RIGHT:
				# 合法施法媒介下，右键由 CombatHUD 用作按住法术界面入口，不能同时进入格挡。
				if can_open_spell_interface():
					_weapon_action_held["block"] = false
					return
				action_name = "block"
	if action_name == "":
		return
	var panel_visible := is_inside_tree() and is_character_panel_visible()
	var action_is_held := mouse_event != null and mouse_event.pressed and not panel_visible
	_weapon_action_held[action_name] = action_is_held
	if action_is_held:
		_weapon_action_pressed[action_name] = true
		_weapon_action_pressed_frame[action_name] = Engine.get_process_frames()

## Consume a mouse attack press captured at the Player boundary.
## The one-frame grace period covers an input event that arrives just before a
## state transition; stale presses are discarded so cooldowns cannot replay it.
func consume_weapon_action_pressed(action_name: String) -> bool:
	if not bool(_weapon_action_pressed.get(action_name, false)):
		return false
	var pressed_frame := int(_weapon_action_pressed_frame.get(action_name, -1))
	_weapon_action_pressed[action_name] = false
	_weapon_action_pressed_frame.erase(action_name)
	if pressed_frame < 0 or Engine.get_process_frames() - pressed_frame > 1:
		return false
	return true

## Returns the input state captured from the latest mouse event. For actions
## driven programmatically or by a future non-mouse binding, keep the Input
## fallback until that action has emitted its first mouse event.
func is_weapon_action_held(action_name: String) -> bool:
	if _weapon_action_held.has(action_name):
		return bool(_weapon_action_held[action_name])
	return Input.is_action_pressed(action_name)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_weapon_action_held.clear()
		_weapon_action_pressed.clear()
		_weapon_action_pressed_frame.clear()

func switch_state(new_state: State, data: PlayerStateData = PlayerStateData.new()) -> void:
	if state_node != null and is_instance_valid(state_node):
		# 受保护退出：同步断开 transition_requested 信号、禁用处理循环、调用 _on_exit，
		# 确保旧状态在新状态 _enter_tree 前完全退出，防止 queue_free 延迟窗口内重入切换。
		state_node._begin_exit()
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

	# 角色面板可见时统一抑制交互提示：面板打开后摄像机冻结，射线仍命中物体，
	# 不抑制会导致拾取/交互悬浮窗残留在面板之上。
	if is_character_panel_visible():
		if current_possible_action != "":
			GameEvents.interaction_hint_changed.emit("", "", Vector2.ZERO)
		current_possible_action = ""
		_last_possible_action_collider = null
		return

	# 先确定当前碰撞体，仅据此判断是否需要重建提示字符串（避免每帧无谓的 tr()/拼接）
	# 统一经 _get_valid_select_collider() 取有效碰撞体，收口 is_instance_valid 过滤
	# 仅调用一次：select_collider 用于 hint 分支构建，current_collider 额外含 kick 门 fallback 用于变化检测
	var select_collider: Object = _get_valid_select_collider()
	if select_collider != null and not _can_interact_collider(select_collider):
		select_collider = null
	var current_collider: Object = select_collider
	if current_collider == null and combat_input_enabled and _raycast_is_colliding(kick_raycast):
		var kick_collider = kick_raycast.get_collider()
		if kick_collider != null and is_instance_valid(kick_collider) and kick_collider is Door:
			current_collider = kick_collider

	var collider_changed := current_collider != _last_possible_action_collider
	# 宝箱开启动画进度（百分比）每帧变化，必须重建字符串
	var chest_in_progress := current_collider is Chest and Input.is_action_pressed("use")
	# 碰撞体未变且非宝箱进度更新：提示内容与上一帧完全一致，跳过 tr()/拼接/emit
	if not collider_changed and not chest_in_progress:
		if current_collider == null and not current_possible_action.is_empty():
			GameEvents.interaction_hint_changed.emit("", "", Vector2.ZERO)
			current_possible_action = ""
			_last_possible_action_collider = null
		return

	var new_action := ""
	var hint_type := ""
	var hint_screen_pos := Vector2.ZERO
	# 复用 select_collider 构建 hint（kick 门走下方 current_collider 分支）
	var collider: Object = select_collider
	if collider is PickableItem and _can_interact_collider(collider):
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
	elif collider != null and collider.has_method("interact") and _can_interact_collider(collider):
		var action_name := tr("Object")
		if "interaction_name" in collider and String(collider.interaction_name) != "":
			action_name = tr(String(collider.interaction_name))
		var verb := tr("[E] Interact")
		if "interaction_verb" in collider and String(collider.interaction_verb) != "":
			verb = "[E] %s" % tr(String(collider.interaction_verb))
		new_action = "%s\n%s" % [action_name, verb]
		hint_type = "interact"
	# select_raycast 命中时计算屏幕坐标用于悬浮窗定位（显示在物体右侧）
	if collider != null:
		hint_screen_pos = _get_raycast_screen_position(select_raycast)
	elif current_collider != null:
		# select 未命中但 kick_raycast 命中 Door：current_collider 已校验为有效 Door
		# 拾取/开门等提示统一显示在物体右侧的悬浮窗（已移除底部提示）
		new_action = tr(current_collider.get_kick_prompt())
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
	# 角色面板可见时抑制物品检视：避免世界悬浮窗（z_index=200）叠在面板上。
	# 面板打开后摄像机冻结，射线仍命中物品，不抑制会导致悬浮窗卡在面板之上。
	if is_character_panel_visible():
		if current_pickable_focused_item != null and is_instance_valid(current_pickable_focused_item):
			current_pickable_focused_item.unhighlight()
		current_pickable_focused_item = null
		GameEvents.item_detail_changed.emit({}, Vector2.ZERO)
		return
	var target_node: Node = null
	# 统一经 _get_valid_select_collider() 取有效碰撞体，收口 is_instance_valid 过滤
	var select_collider := _get_valid_select_collider()
	if select_collider is PickableItem:
		target_node = select_collider
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
		_play_first_person_block_impact(source_enemy, damage)
		# 持盾格挡：0.3s 完美窗口内不消耗盾牌耐久
		if _is_shield_block() and not _is_in_block_grace_window():
			equipment.apply_shield_damage(damage)
		if _is_shield_block():
			COMBAT_PROGRESSION.award_player_shield_block(self, "melee", damage)
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
	# 符文之语：闪避检定（完全免伤）
	if RWPH.try_dodge(self):
		AudioManager.play("dodge", action_audio_stream_player)
		return
	# 穿透格挡的攻击无视格挡状态，直接造成伤害
	var can_hurt: bool = state_node.can_get_hurt() or result.ignores_block
	if can_hurt:
		var final_damage: int = result.final_damage
		# 蓄势（TWO_HAND）：蓄力期间减伤 30%，累积伤害到释放时叠加
		final_damage = combat_rt.apply_charging_accumulation(final_damage)
		final_damage = ME.apply_elemental_aegis(final_damage, result.attack_type == "spell")
		final_damage = ME.apply_thick_skin(final_damage)
		# 奥术护盾（SPELL）：法术蓝量转化的护盾吸收伤害
		final_damage = combat_rt.absorb_with_arcane_shield(final_damage)
		final_damage = buffs.consume_damage_absorb(final_damage, health.max_life if health != null else 0)
		# 符文之语：受伤伤害修正（解脱减伤/大地护甲/不朽保命/狂暴增伤）
		var rwph_reduce := RWPH.get_damage_reduce_pct(self)
		if rwph_reduce > 0.0:
			final_damage = int(round(float(final_damage) * (1.0 - rwph_reduce)))
		final_damage = RWPH.on_player_take_damage(self, final_damage, source_enemy)
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
		_accumulate_armor_proficiency(false)
	elif state == State.BLOCKING:
		AudioManager.play("block", action_audio_stream_player)
		FxHelper.call_deferred("create_block_number", global_position, result.final_damage)
		_play_first_person_block_impact(source_enemy, result.final_damage)
		var in_grace := _is_in_block_grace_window()
		# 持盾格挡：完美窗口内不消耗盾牌耐久；双手武器格挡不消耗耐久
		if _is_shield_block() and not in_grace:
			equipment.apply_shield_damage(result.final_damage)
		if _is_shield_block():
			COMBAT_PROGRESSION.award_player_shield_block(self, result.attack_type, result.final_damage)
		# 完美格挡成功（窗口内）→ 触发完美格挡·增伤标记（下次攻击 ×1.5，doc21 #6）
		# 同时作用于持盾完美格挡与双手武器精确格挡；连续完美格挡仅刷新不叠加
		if in_grace and has_mechanism_passive("perfect_block_empower"):
			set_perfect_block_buff()
		# 折射（ONE_HAND_SHIELD）：格挡远程/法系攻击时 100% 反射
		var is_ranged_or_spell: bool = result.attack_type == "ranged" or result.attack_type == "spell"
		var reflect_pct: float = SPE.try_reflect_attack(is_ranged_or_spell, true)
		if reflect_pct > 0.0 and source_enemy != null and is_instance_valid(source_enemy):
			var reflected_dmg: int = maxi(1, int(round(float(result.final_damage) * reflect_pct)))
			source_enemy.try_receive_hit(self, reflected_dmg)
			# 折射：盾牌耐久消耗加倍
			if _is_shield_block() and not in_grace:
				equipment.apply_shield_damage(result.final_damage)
		source_enemy.try_stun()
		_accumulate_armor_proficiency(true)


## Adds a local shield jolt on a successful block without changing damage,
## stun, durability or network authority.
func _play_first_person_block_impact(source_enemy: Enemy, damage: int) -> void:
	if view_model == null or not is_instance_valid(view_model) or not view_model.has_method("play_block_impact"):
		return
	var horizontal_bias := 0.0
	if source_enemy != null and is_instance_valid(source_enemy):
		var world_direction := global_position.direction_to(source_enemy.global_position)
		horizontal_bias = clampf((global_transform.basis.inverse() * world_direction).x, -1.0, 1.0)
	var strength := clampf(float(maxi(damage, 1)) / 24.0, 0.35, 1.35)
	view_model.play_block_impact(strength, horizontal_bias)

## 受击后累积体质经验（防御韧性训练）
func _accumulate_defense_exp() -> void:
	var ap: Node = Service.attr_panel()
	if ap != null:
		ap.accumulate_attr("con", 2)  # 每次受击 +2 体质经验

## 受击后累积护甲熟练度经验（策划案 35 §6.1）
## 穿甲受击 +1 经验，格挡命中 +2 经验
func _accumulate_armor_proficiency(is_blocked: bool) -> void:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return
	var ap: Node = tree.root.get_node_or_null("ArmorProficiency")
	if ap != null:
		ap.on_hit_received(is_blocked)

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

func is_active_spell_focus_weapon() -> bool:
	var weapon := get_active_hand_weapon_data()
	if weapon == null:
		return false
	var profile := String(PLAYER_ANIMATION_PROFILE.profile_for_weapon(weapon))
	return profile == "staff" or profile == "grimoire"

## 当前武器是否为弩（弩无需拉弓蓄力，点击即射）
func is_active_weapon_crossbow() -> bool:
	return equipment != null and equipment.is_active_weapon_crossbow()

func is_active_weapon_two_handed() -> bool:
	return equipment != null and equipment.is_active_weapon_two_handed()

## 双手近战专精「重型挥舞」是否替换本次基础攻击动作。
## 远程/法系虽然数据层 hands=two_hand，但不属于 TWO_HAND 近战流派。
func should_use_heavy_swing_animation() -> bool:
	if not is_active_weapon_two_handed() or get_active_weapon_attack_type() != "melee":
		return false
	return has_mechanism_passive("passive_style_twohand_heavy_swing")

func can_block_with_active_equipment() -> bool:
	return equipment != null and equipment.can_block()

func can_dual_wield_attack_with_active_equipment() -> bool:
	return equipment != null and equipment.can_dual_wield()

func get_primary_weapon_release_state() -> int:
	if not can_start_weapon_attack("primary"):
		return -1
	return State.SHOOTING if is_active_weapon_ranged() else State.SLASHING

## 当前手是否允许开始一次武器攻击。
## 远程武器使用自身装填/射击限制；近战武器必须先通过对应手的冷却。
func can_start_weapon_attack(hand: String = "primary") -> bool:
	if not combat_input_enabled:
		return false
	if is_active_weapon_ranged():
		return true
	# Primary melee attacks remain available as unarmed attacks before the
	# first weapon pickup. Secondary attacks still require hand equipment.
	if hand == "secondary" and not has_active_hand_equipment():
		return false
	return not is_melee_on_cooldown(hand)

func get_primary_weapon_action_state() -> int:
	if get_primary_weapon_release_state() == -1:
		return -1
	return State.ATTACK_PREPARING

func make_primary_weapon_attack_data() -> PlayerStateData:
	return PlayerStateData.new().set_weapon_attack("action", "primary", get_primary_weapon_release_state())

func get_secondary_weapon_release_state() -> int:
	if not combat_input_enabled or not has_active_hand_equipment():
		return -1
	if not is_active_weapon_ranged() and is_melee_on_cooldown("secondary"):
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
	if can_dual_wield_attack_with_active_equipment() and get_secondary_weapon_release_state() != -1:
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

func prepare_attack_hitbox(target_mask: int, radius_mult: float = 1.0) -> Area3D:
	var attach_to := _get_active_attack_hitbox_parent()
	return HITBOX_BUILDER.ensure_hitbox(self, attach_to, _get_active_attack_reach(), target_mask, radius_mult)

func set_attack_hitbox_active(hitbox: Area3D, active: bool) -> void:
	HITBOX_BUILDER.set_active(hitbox, active)

func _get_active_attack_hitbox_parent() -> Node3D:
	if equipment == null:
		return null
	var mount: Node3D = equipment.get_active_weapon_placeholder() if equipment.has_method("get_active_weapon_placeholder") else equipment.weapon_placeholder
	if mount == null or mount.get_child_count() == 0:
		return null
	return mount.get_child(0) as Node3D

func _get_active_attack_reach() -> float:
	if weapon_reach_raycast != null:
		return maxf(absf(weapon_reach_raycast.target_position.z), 0.8)
	var weapon := get_active_hand_weapon_data()
	return maxf(weapon.reach * CombatHitboxBuilder.REACH_SCALE, 0.8) if weapon != null else 1.2
	
## 酸液伤害入口：与 try_receive_hit 保持一致的生命周期守卫。
## state_node 在状态切换帧间或 _ready 完成 switch_state(State.MOVING) 前可能为 null，
## 缺守卫会触发 "Cannot call method 'can_die' on a null instance" 崩溃。
func take_acid_damage() -> void:
	if state_node == null or not is_instance_valid(state_node) or state_node.is_queued_for_deletion():
		return
	if state == State.HURT or state == State.DYING:
		return
	if state_node.can_die():
		switch_state(State.DYING)

## 尖刺陷阱伤害入口：统一生命周期守卫 + 重入受击保护 + 参数校验。
## 缺 HURT/DYING 守卫时，已在受击硬直中踩刺会重入 HURT 并打断当前受击动画，
## 与 try_receive_hit 拒绝重入受击的行为不一致；spikes_trap 可能已被 queue_free。
func take_spike_damage(spikes_trap: SpikesTrap) -> void:
	if spikes_trap == null or not is_instance_valid(spikes_trap):
		return
	if state_node == null or not is_instance_valid(state_node) or state_node.is_queued_for_deletion():
		return
	if state == State.HURT or state == State.DYING:
		return
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
# 近战攻击冷却（仅近战武器；实际逻辑已提取到 PlayerCombatRuntime）
# ============================================================================

## 触发一次近战攻击冷却（hand: "primary" 左键主手 / "secondary" 双持副手）
func start_melee_cooldown(hand: String) -> void:
	combat_rt.start_melee_cooldown(hand, is_active_weapon_two_handed(), has_mechanism_passive("cd_reduce"))

## 急速被动（cd_reduce）：冷却 ×0.85
## 暴风骤雨（unarmed_flurry_storm）：徒手连击每层 -5% CD（最高 -60%）
func get_melee_cd_multiplier() -> float:
	return combat_rt.get_melee_cd_multiplier(has_mechanism_passive("cd_reduce"))

## 某手是否处于近战冷却中
func is_melee_on_cooldown(hand: String) -> bool:
	return combat_rt.is_melee_on_cooldown(hand)

## 某手冷却恢复比例 0..1（1=就绪）。无近战武器/远程时恒为 1（就绪、不显示环）
func get_melee_cd_fill(hand: String) -> float:
	return combat_rt.get_melee_cd_fill(hand)

## 查询机制类被动（操作强化，doc21 §3）是否已拥有
func has_mechanism_passive(id: String) -> bool:
	var sr: Node = Service.skill_runtime()
	if sr != null and sr.has_method("has_mechanism_passive"):
		return sr.has_mechanism_passive(id)
	return false

# ============================================================================
# 流派专精被动公共 API（doc21 §一；实际逻辑已提取到 PlayerCombatRuntime）
# ============================================================================

## 记录近战攻击命中（由攻击状态机调用）
## 用于追踪：交错挥砍连携、暴风骤雨层数
func record_melee_hit(hand: String) -> void:
	combat_rt.record_melee_hit(hand, has_mechanism_passive("passive_style_unarmed_flurry_storm"))

## 消耗蓄势累积的额外伤害（由双手攻击释放时调用）
## 返回累积的伤害值并清空池
func consume_accumulation_bonus() -> float:
	return combat_rt.consume_accumulation_bonus()

## 设置双手蓄力状态（由攻击蓄力状态机调用）
func set_charging_twohand(is_charging: bool) -> void:
	combat_rt.set_charging_twohand(is_charging)

## 触发元素环（由施法路径调用）
func trigger_elemental_ring() -> void:
	combat_rt.trigger_elemental_ring()

## 触发奥术护盾（由施法路径调用，将消耗蓝量转化为护盾）
func trigger_arcane_barrier(mana_spent: int) -> void:
	combat_rt.trigger_arcane_barrier(mana_spent)

## 获取流派被动运行时状态字典（供 CombatBridge.build_player_attack 使用）
func get_style_context() -> Dictionary:
	return combat_rt.get_style_context()

## 计算近战蓄力伤害倍率：未装备蓄力被动或蓄力为 0 → 1.0（无增伤）
func get_melee_charge_multiplier(charge_ratio: float) -> float:
	# 符文之语「瞬蓄之语」：无需蓄力即可获得满蓄力增伤
	if has_mechanism_passive("charge_free"):
		return MELEE_CHARGE_MAX_MULT
	if charge_ratio <= 0.0:
		return 1.0
	if not has_mechanism_passive("charge"):
		return 1.0
	return lerpf(1.0, MELEE_CHARGE_MAX_MULT, clampf(charge_ratio, 0.0, 1.0))

# ============================================================================
# 符文之语「奔雷之语」：奔跑撞击敌人
# ============================================================================

## 奔跑撞击检测：拥有 rune_word_sprint_impact 且正在奔跑（速度达标）时，
## 用 kick_raycast 探测前方敌人并施加撞击伤害 + 击退（带冷却）。
## 冲撞技能（CHARGING 状态）有自己的命中结算，此处跳过避免重复。
func _check_sprint_impact(delta: float) -> void:
	if not has_mechanism_passive("rune_word_sprint_impact"):
		return
	if state == State.CHARGING or state == State.DYING:
		return
	_sprint_impact_cd = maxf(0.0, _sprint_impact_cd - delta)
	if _sprint_impact_cd > 0.0:
		return
	if not movement_input_enabled or not Input.is_action_pressed("run"):
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed < SPRINT_IMPACT_MIN_SPEED:
		return
	if not _raycast_is_colliding(kick_raycast):
		return
	var collider := kick_raycast.get_collider()
	if collider == null or not is_instance_valid(collider):
		return
	var enemy := collider as Enemy
	if enemy == null:
		return
	_apply_sprint_impact_to_enemy(enemy, hspeed)
	_sprint_impact_cd = SPRINT_IMPACT_CD_SEC

## 对敌人施加奔跑撞击伤害：伤害随速度增长，附带击退与短眩晕，
## 并启用物理撞击（被撞者撞墙时受额外地形撞击伤害）。
func _apply_sprint_impact_to_enemy(enemy: Enemy, speed: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var forward := -global_transform.basis.z.normalized()
	var result := CE_LIB.DamageResult.new()
	result.hit = true
	result.final_damage = int(max(1.0, speed * SPRINT_IMPACT_DAMAGE_PER_SPEED))
	result.knockback_force = SPRINT_IMPACT_KNOCKBACK
	result.knockback_impulse = forward * SPRINT_IMPACT_KNOCKBACK
	result.stun_duration = SPRINT_IMPACT_STUN_SEC
	result.physical_impact_enabled = true
	result.physical_impact_damage_mult = SPRINT_IMPACT_PHYSICAL_MULT
	enemy.try_receive_hit_result(self, result)

## 完美格挡·增伤 buff：完美格挡成功时置位（doc21 #6）
func set_perfect_block_buff() -> void:
	combat_rt.set_perfect_block_buff()

## 消费完美格挡·增伤 buff：返回 true 并已消费（下次攻击命中时调用，仅一次）
func consume_perfect_block_buff() -> bool:
	return combat_rt.consume_perfect_block_buff()

## 残影 buff：侧垫步成功触发后激活（doc21 #7 afterimage，需装备该机制被动）
func set_sidestep_buff() -> void:
	combat_rt.set_sidestep_buff()

## 消费残影 buff：窗口内且首次攻击命中时返回 true 并清零（仅一次）
func consume_sidestep_buff() -> bool:
	return combat_rt.consume_sidestep_buff()

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
	combat_rt.start_crossbow_reload(sec)
	# Queue the first-person reload after the release clip. The third-person
	# AnimationPlayer remains untouched and owns the shooting state's exit signal.
	var fire_animation_delay := 0.24
	if animation_player != null and animation_player.has_animation("crossbow_fire"):
		fire_animation_delay = animation_player.get_animation("crossbow_fire").length + 0.01
	if view_model != null and is_instance_valid(view_model) and view_model.has_method("play_action_after"):
		view_model.play_action_after(&"vm_crossbow_reload", fire_animation_delay, 1.2 / maxf(sec, 0.01))

## 弩是否正在装弹（装弹完成前不允许连续发射）
func is_crossbow_reloading() -> bool:
	return combat_rt.is_crossbow_reloading()

## 弩装弹恢复比例 0..1（1=就绪可射）
func get_crossbow_reload_fill() -> float:
	return combat_rt.get_crossbow_reload_fill()

# ============================================================================
# 跳跃 / 二段跳
# ============================================================================

## 执行一次跳跃：地面跳为基准跳；空中跳仅在拥有 air_dash 机制被动且仍有次数时触发（doc21 #4）
func do_jump() -> void:
	if is_on_floor():
		velocity.y = jump_force
		combat_rt.reset_air_jumps()
		AudioManager.play("jump", vocal_audio_stream_player)
		return
	if has_mechanism_passive("air_dash") and combat_rt.try_use_air_jump():
		velocity.y = jump_force * PLAYER_COMBAT_RUNTIME.AIR_JUMP_FORCE_MULT
		AudioManager.play("jump", vocal_audio_stream_player)

## 获取 select_raycast 当前命中的有效碰撞体。
## 统一收口 is_instance_valid 过滤，避免 _physics_process / check_for_selection /
## check_for_possible_action 各自重复处理 queue_free 一帧延迟导致的失效引用。
## 返回 null 表示射线未命中或碰撞体已释放。
func _get_valid_select_collider() -> Object:
	if not _raycast_is_colliding(select_raycast):
		return null
	var collider := select_raycast.get_collider()
	if collider == null or not is_instance_valid(collider):
		return null
	return collider

## 统一判断准心目标是否有当前可执行的交互。
## has_method("interact") 只是实现细节，不能单独作为提示资格；
## 没有名称/能力声明的装饰物仍可保留碰撞和受击逻辑，但不显示悬浮提示。
func _can_interact_collider(collider: Object) -> bool:
	if collider == null or not is_instance_valid(collider):
		return false
	if collider is PickableItem:
		return _pickable_item_has_interaction_payload(collider as PickableItem)
	if collider is Chest:
		return not bool(collider.get("is_opened"))
	if collider.has_method("can_interact"):
		return collider.has_method("interact") and bool(collider.can_interact())
	if collider is Door:
		return not String(collider.get("tutorial_locked_message")).strip_edges().is_empty()
	if not collider.has_method("interact"):
		return false
	if "interaction_name" in collider:
		return not String(collider.get("interaction_name")).strip_edges().is_empty()
	return false

func _pickable_item_has_interaction_payload(item: PickableItem) -> bool:
	if item == null or not is_instance_valid(item) or not item.has_method("get_item_name"):
		return false
	return item.weapon_data != null or item.shield_data != null \
		or item.furniture_data != null or not item.material_id.strip_edges().is_empty() \
		or not item.rune_id.strip_edges().is_empty()

func _raycast_is_colliding(raycast: RayCast3D) -> bool:
	return raycast != null and is_instance_valid(raycast) and not raycast.is_queued_for_deletion() and raycast.is_colliding()

## 是否具备按住右键打开法术界面的资格：魔导书、法杖，或单手剑 + 奥法之剑被动。
func can_open_spell_interface() -> bool:
	if equipment == null:
		return false
	var weapon: WeaponData = equipment.get_active_weapon_data()
	return SPELL_ACCESS_POLICY.can_use_spell_interface(weapon, has_mechanism_passive(ARCANE_SWORD_PASSIVE_ID))


func is_character_panel_visible() -> bool:
	var scene_tree := get_tree()
	if scene_tree == null:
		return false
	for node in scene_tree.get_nodes_in_group("character_panel"):
		if node.is_inside_tree() and node.visible:
			return true
	return false
