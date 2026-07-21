class_name ProjectileEntity
extends RigidBody3D
## 投射物实体（RigidBody3D）。
## 由 ProjectileService.spawn 实例化，沿 -Z 方向飞行，命中敌人后通过 CombatBridge 结算伤害。
## 支持穿透（pierce_count）、AoE 爆炸（impact_aoe_radius）、环境销毁等。
## 参考实现：scenes/equipment/thrown_item.gd（投掷武器）

const CB := preload("res://globals/combat/combat_bridge.gd")
const CE := preload("res://globals/combat/combat_engine.gd")
const Service := preload("res://globals/core/service.gd")
const PD := preload("res://data/projectile_data.gd")

## 投射物定义
@export var projectile_data: Resource

## 发射者（Player 节点），用于战斗结算与仇恨归属
@export var source_player: Node3D

## 武器数据（用于伤害投骰），可为空（纯法术技能时）
@export var weapon_data: Resource

## 技能定义（可选，武器流派技能释放时传入）
@export var skill_data: Dictionary = {}

## 主手武器类型 id（CombatBridge.get_weapon_class 结果）
@export var main_hand_type: String = ""

## 副手武器类型 id
@export var off_hand_type: String = ""

## 攻方属性字典
@export var attacker_attrs: Dictionary = {}

## 攻方等级
@export var attacker_level: int = 1

## 是否背袭（投射物默认 false）
@export var is_backstab: bool = false

## 武器耐久磨损值（命中时从源玩家装备扣除，0=不磨损）
@export var weapon_condition_wear: int = 0

@onready var audio_stream_player_3d: AudioStreamPlayer3D = %AudioStreamPlayer3D
@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var visual_root: Node3D = %VisualRoot

## 已命中目标列表（穿透用）
var _hit_targets: Array[Node] = []

## 当前伤害倍率（穿透衰减后）
var _current_damage_mult: float = 1.0

## 剩余穿透次数
var _pierce_remaining: int = 0

## 飞行方向（单位向量）
var _flight_direction: Vector3 = Vector3.FORWARD

## 是否已销毁（防止重复销毁）
var _is_destroyed: bool = false

## 存活计时器
var _lifetime_timer: SceneTreeTimer = null

## 共享材质缓存——按 projectile_data 的资源路径索引，避免每次生成创建新 StandardMaterial3D
static var _shared_spell_materials: Dictionary = {}  # { resource_path: StandardMaterial3D }
static var _shared_arrow_shaft_materials: Dictionary = {}
static var _shared_arrow_head_materials: Dictionary = {}


func _ready() -> void:
	if projectile_data == null:
		push_warning("ProjectileEntity: projectile_data 为空，立即销毁")
		queue_free()
		return
	# 重置状态（对象池复用时需要）
	_is_destroyed = false
	_hit_targets.clear()
	_current_damage_mult = 1.0
	# 物理设置
	PhysicsSetup.setup_projectile(self)
	gravity_scale = projectile_data.gravity_scale
	_pierce_remaining = projectile_data.pierce_count
	# 碰撞形状
	_build_collision_shape()
	# 视觉外观（先清理旧视觉，再构建新视觉）
	_clear_visual()
	_build_visual()
	# 飞行方向 = -Z（spawn_transform 的前方）
	_flight_direction = -global_transform.basis.z.normalized()
	# 设置初速度
	linear_velocity = _flight_direction * projectile_data.speed
	# 自旋
	if projectile_data.spin_speed > 0.0:
		angular_velocity = global_transform.basis.y * deg_to_rad(projectile_data.spin_speed)
	# 飞行音效
	if projectile_data.flight_sound_key != "" and audio_stream_player_3d != null:
		AudioManager.play(projectile_data.flight_sound_key, audio_stream_player_3d)
	# 碰撞信号（对象池复用时可能已连接，需检查）
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	# 存活计时
	_lifetime_timer = get_tree().create_timer(projectile_data.lifetime)
	_lifetime_timer.timeout.connect(_on_lifetime_expired)

## 清理视觉子节点（对象池复用前调用）
## 使用 free() 立即释放，避免 queue_free() 延迟导致复用时新旧视觉并存。
func _clear_visual() -> void:
	if visual_root == null:
		return
	for child in visual_root.get_children():
		child.free()


## 构建碰撞形状（盒形，沿 Z 轴拉长）
func _build_collision_shape() -> void:
	if collision_shape == null:
		return
	var box := BoxShape3D.new()
	var r: float = projectile_data.collision_radius
	var l: float = projectile_data.collision_length
	box.size = Vector3(r * 2.0, r * 2.0, l)
	collision_shape.shape = box
	collision_shape.position = Vector3.ZERO


## 构建视觉外观
func _build_visual() -> void:
	if visual_root == null:
		return
	if projectile_data.visual_scene != null:
		var instance: Node = projectile_data.visual_scene.instantiate()
		if instance != null:
			visual_root.add_child(instance)
		return
	# 无预制场景 → 按伤害类型生成默认外观
	match projectile_data.damage_type:
		"spell":
			_build_default_spell_visual()
		_:
			_build_default_arrow_visual()


## 默认法术弹外观：发光球体
func _build_default_spell_visual() -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = projectile_data.collision_radius
	sphere.height = projectile_data.collision_radius * 2.0
	mi.mesh = sphere
	mi.material_override = _get_shared_spell_material()
	visual_root.add_child(mi)
	# 附加点光源
	var light := OmniLight3D.new()
	light.light_color = projectile_data.default_color
	light.light_energy = 1.5
	light.omni_range = 3.0
	light.omni_attenuation = 1.5
	visual_root.add_child(light)


## 获取共享的法术弹材质（同一 projectile_data 资源复用同一个材质实例）
func _get_shared_spell_material() -> StandardMaterial3D:
	var key := projectile_data.resource_path
	if _shared_spell_materials.has(key):
		return _shared_spell_materials[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = projectile_data.default_color
	mat.emission_enabled = true
	mat.emission = projectile_data.default_color
	mat.emission_energy_multiplier = maxf(projectile_data.default_emission, 1.5)
	mat.roughness = 0.3
	mat.metallic = 0.0
	_shared_spell_materials[key] = mat
	return mat


## 默认箭矢外观：细长圆柱 + 箭头
func _build_default_arrow_visual() -> void:
	var shaft := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.02
	cylinder.bottom_radius = 0.02
	cylinder.height = projectile_data.collision_length * 0.7
	shaft.mesh = cylinder
	shaft.rotation_degrees.x = 90.0  # 圆柱默认沿 Y，旋转到沿 Z
	shaft.material_override = _get_shared_arrow_shaft_material()
	visual_root.add_child(shaft)
	# 箭头（小锥体）
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.05
	cone.height = 0.12
	head.mesh = cone
	head.rotation_degrees.x = 90.0
	head.position.z = -projectile_data.collision_length * 0.4
	head.material_override = _get_shared_arrow_head_material()
	visual_root.add_child(head)


## 获取共享的箭杆材质
func _get_shared_arrow_shaft_material() -> StandardMaterial3D:
	var key := projectile_data.resource_path
	if _shared_arrow_shaft_materials.has(key):
		return _shared_arrow_shaft_materials[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = projectile_data.default_color
	mat.roughness = 0.6
	_shared_arrow_shaft_materials[key] = mat
	return mat


## 获取共享的箭头材质（全局唯一，不随 projectile_data 变化）
func _get_shared_arrow_head_material() -> StandardMaterial3D:
	const HEAD_KEY := "__arrow_head__"
	if _shared_arrow_head_materials.has(HEAD_KEY):
		return _shared_arrow_head_materials[HEAD_KEY] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.7, 0.75)
	mat.metallic = 0.8
	mat.roughness = 0.3
	_shared_arrow_head_materials[HEAD_KEY] = mat
	return mat


## 碰撞体进入
func _on_body_entered(body: Node) -> void:
	if _is_destroyed or not is_instance_valid(self):
		return
	# 忽略发射者自身
	if body == source_player:
		return
	# 敌人命中
	if body is Enemy and is_instance_valid(body):
		_resolve_enemy_hit(body as Enemy)
		return
	if body != null and body.has_method("try_receive_hit"):
		_resolve_scene_object_hit(body)
		return
	# 环境物体命中（墙/地板/场景物体）
	if projectile_data.destroy_on_environment:
		_destroy_with_impact()


## 对敌人命中结算
func _resolve_enemy_hit(enemy: Enemy) -> void:
	# 穿透：已命中过的目标跳过
	if _hit_targets.has(enemy):
		return
	_hit_targets.append(enemy)
	# AoE 爆炸：命中时对该半径内所有敌人造成伤害
	if projectile_data.impact_aoe_radius > 0.0:
		_resolve_aoe_impact(enemy)
		_destroy_with_impact()
		return
	# 单体伤害结算
	_resolve_single_hit(enemy)
	# 武器耐久磨损
	_apply_weapon_wear()
	# 穿透判定
	if _pierce_remaining > 0:
		_pierce_remaining -= 1
		_apply_pierce_falloff()
	else:
		_destroy_with_impact()


func _resolve_scene_object_hit(body: Node) -> void:
	if _hit_targets.has(body):
		return
	_hit_targets.append(body)
	var damage := int(max(1.0, float(skill_data.get("damage_mult", 1.0)) * 3.0 * _current_damage_mult))
	body.try_receive_hit(source_player, damage)
	_apply_weapon_wear()
	_play_impact_sound()
	_destroy_with_impact()


## 单体伤害结算
func _resolve_single_hit(enemy: Enemy) -> void:
	if source_player == null or not is_instance_valid(source_player):
		return
	var result = CB.resolve_projectile_attack(
		source_player, enemy, weapon_data, main_hand_type, off_hand_type,
		attacker_attrs, attacker_level, _flight_direction, is_backstab,
		skill_data, _current_damage_mult
	)
	if result.hit:
		enemy.try_receive_hit_result(source_player, result)
		_apply_lifesteal(result)
		_apply_skill_debuff(enemy)
	# 命中音效
	_play_impact_sound()


## AoE 爆炸伤害结算：对半径内所有敌人造成伤害
func _resolve_aoe_impact(trigger_enemy: Enemy) -> void:
	if source_player == null or not is_instance_valid(source_player):
		return
	var enemies := _find_enemies_in_radius(projectile_data.impact_aoe_radius)
	if enemies.is_empty() and trigger_enemy != null:
		enemies.append(trigger_enemy)
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if _hit_targets.has(enemy):
			continue
		_hit_targets.append(enemy)
		var result = CB.resolve_projectile_attack(
			source_player, enemy, weapon_data, main_hand_type, off_hand_type,
			attacker_attrs, attacker_level, _flight_direction, is_backstab,
			skill_data, _current_damage_mult
		)
		if result.hit:
			enemy.try_receive_hit_result(source_player, result)
			_apply_lifesteal(result)
			_apply_skill_debuff(enemy)
	_play_impact_sound()


## 查找半径内的敌人
func _find_enemies_in_radius(radius: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return result
	# 用 PhysicsShapeQuery3D 查询
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = global_position
	query.collision_mask = PhysicsSetup.LAYER_ENEMY
	var intersections := space_state.intersect_shape(query)
	for intersection in intersections:
		var collider: Node = intersection.get("collider")
		if collider is Enemy:
			result.append(collider as Enemy)
	return result


## 对敌人施加技能 debuff（减速/防降等）
func _apply_skill_debuff(enemy: Enemy) -> void:
	if skill_data.is_empty() or enemy == null:
		return
	if not enemy.has_method("apply_combat_debuff"):
		return
	var buff_type := String(skill_data.get("buff_type", ""))
	var duration := float(skill_data.get("buff_sec", 0.0))
	if duration <= 0.0 or buff_type == "":
		return
	match buff_type:
		"def_down", "slow", "evade_down", "ground_ice", "root_and_dmg_down", "slow_and_haste":
			enemy.apply_combat_debuff(buff_type, duration, skill_data.get("buff_value", 0))


## 穿透衰减
func _apply_pierce_falloff() -> void:
	var falloff: float = projectile_data.pierce_falloff_percent / 100.0
	_current_damage_mult *= (1.0 - falloff)
	_current_damage_mult = maxf(_current_damage_mult, 0.1)


## 武器耐久磨损
func _apply_weapon_wear() -> void:
	if weapon_condition_wear <= 0 or source_player == null:
		return
	if not is_instance_valid(source_player):
		return
	if source_player.has_method("get") and "equipment" in source_player:
		var eq: Node = source_player.get("equipment")
		if eq != null and eq.has_method("apply_weapon_damage"):
			eq.apply_weapon_damage(weapon_condition_wear)


## 吸血
func _apply_lifesteal(result) -> void:
	if result.lifesteal_amount <= 0 or source_player == null:
		return
	if not is_instance_valid(source_player):
		return
	if source_player.has_method("get") and "health" in source_player:
		var health: Node = source_player.get("health")
		if health != null and health.has_method("heal"):
			health.heal(result.lifesteal_amount)
			FxHelper.create_heal_number(source_player.global_position, result.lifesteal_amount)


## 命中音效
func _play_impact_sound() -> void:
	if projectile_data.impact_sound_key == "":
		return
	if audio_stream_player_3d != null:
		AudioManager.play(projectile_data.impact_sound_key, audio_stream_player_3d)


## 销毁并播放命中特效
func _destroy_with_impact() -> void:
	if _is_destroyed:
		return
	_is_destroyed = true
	# 命中特效
	if projectile_data.impact_scene != null:
		var fx: Node = projectile_data.impact_scene.instantiate()
		if fx != null:
			var parent: Node = _get_spawn_parent()
			if parent != null:
				parent.add_child(fx)
				if fx is Node3D:
					(fx as Node3D).global_transform = global_transform
	# 取消计时器
	if _lifetime_timer != null and _lifetime_timer.timeout.is_connected(_on_lifetime_expired):
		_lifetime_timer.timeout.disconnect(_on_lifetime_expired)
	# 停止物理运动
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# 归还到对象池（而非直接 queue_free）
	_return_to_pool()


## 存活超时
func _on_lifetime_expired() -> void:
	if _is_destroyed:
		return
	_is_destroyed = true
	# 停止物理运动
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# 归还到对象池（而非直接 queue_free）
	_return_to_pool()


## 将投射物归还到对象池，供下次复用
func _return_to_pool() -> void:
	var ps: Node = Service.projectile_service()
	if ps != null and ps.has_method("return_projectile_to_pool"):
		ps.return_projectile_to_pool(self)
	else:
		queue_free()


## 获取生成父节点（当前关卡）
func _get_spawn_parent() -> Node:
	var gs: Node = Service.game_state()
	if gs != null and gs.get("current_level") != null:
		var level: Node = gs.get("current_level")
		if is_instance_valid(level):
			return level
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	if get_parent() != null:
		return get_parent()
	return tree.root if tree != null else self
