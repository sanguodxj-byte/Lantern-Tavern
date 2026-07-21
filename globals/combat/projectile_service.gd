extends Node
## 投射物服务（autoload: ProjectileService）。
## 职责：
##   1. 维护投射物定义注册表（ProjectileData by id）
##   2. 提供统一的投射物生成 API（spawn / spawn_for_weapon / spawn_for_skill）
##   3. 根据武器类型 / 技能流派自动选择对应投射物
##
## 数据流：
##   PlayerStateShooting / PlayerSkillDispatcher
##     → ProjectileService.spawn_for_weapon(weapon, transform, player)
##     → 实例化 ProjectileEntity 场景 + 注入 ProjectileData
##     → 添加到当前关卡
##     → ProjectileEntity._ready() 设置速度并飞行
##     → body_entered → CombatBridge.resolve_projectile_attack → Enemy.try_receive_hit_result

const CB := preload("res://globals/combat/combat_bridge.gd")
const SD := preload("res://globals/combat/skill_data.gd")
const Service := preload("res://globals/core/service.gd")
const PD := preload("res://data/projectile_data.gd")
const PROJECTILE_PREFAB := preload("res://scenes/equipment/projectile_entity.tscn")

# 体素投射物视觉场景（箭矢 / 弩箭）
const VOXEL_ARROW_SCENE := preload("res://assets/meshes/projectiles/voxel_arrow.tscn")
const VOXEL_BOLT_SCENE := preload("res://assets/meshes/projectiles/voxel_bolt.tscn")

# 武器耐久磨损（与 PlayerStateSlashing 一致）
const WEAPON_CONDITION_WEAR := 2

# 对象池最大容量
const POOL_MAX_SIZE := 32

## 注册表：id → ProjectileData
var _registry: Dictionary = {}

## 投射物对象池：已停用、可复用的 ProjectileEntity 列表
var _projectile_pool: Array[Node3D] = []

## 武器类型 → 默认投射物 id 映射
const WEAPON_PROJECTILE_MAP: Dictionary = {
	"longbow": "arrow",
	"crossbow": "bolt",
	"wand": "elemental_bolt",
	"grimoire": "arcane_bolt",
}

## 技能 id → 特殊投射物 id 映射（覆盖武器默认投射物）
const SKILL_PROJECTILE_MAP: Dictionary = {
	"贯穿射击": "piercing_arrow",
	"双发连射": "arrow",  # 双发由 dispatcher 连续生成两次
	"刺钩弩箭": "barbed_bolt",
	"元素弹": "elemental_bolt",
	"寒冰新星": "frost_nova_bolt",
	"雷暴术": "thunder_bolt",
	"弩箭齐射": "volley_bolt",
	"压制齐射": "volley_arrow",
}

## 技能流派 → 默认投射物 id 映射（当技能无专属投射物时按流派回退）
const SCHOOL_PROJECTILE_MAP: Dictionary = {
	SD.School.LONGBOW: "arrow",
	SD.School.LIGHT_CROSSBOW: "bolt",
	SD.School.ENCHANT_WAND: "elemental_bolt",
	SD.School.GRIMOIRE: "arcane_bolt",
}


func _ready() -> void:
	_register_defaults()


## 注册默认投射物定义
func _register_defaults() -> void:
	# ── 箭矢（长弓）── 中等下坠
	var arrow: Resource = PD.create("arrow", 22.0, "ranged")
	arrow.display_name = tr("箭矢")
	arrow.gravity_scale = 0.20
	arrow.collision_radius = 0.08
	arrow.collision_length = 0.6
	arrow.lifetime = 4.0
	arrow.default_color = Color(0.7, 0.5, 0.25)
	arrow.flight_sound_key = "sword-fly"
	arrow.impact_sound_key = "sword-hit-wall"
	arrow.visual_scene = VOXEL_ARROW_SCENE
	register(arrow)

	# ── 弩箭（轻弩）── 下坠最小（近乎直线，极微弱抛物线）
	var bolt: Resource = PD.create("bolt", 28.0, "ranged")
	bolt.display_name = tr("弩箭")
	bolt.gravity_scale = 0.04
	bolt.collision_radius = 0.07
	bolt.collision_length = 0.5
	bolt.lifetime = 3.5
	bolt.default_color = Color(0.6, 0.6, 0.65)
	bolt.flight_sound_key = "sword-fly"
	bolt.impact_sound_key = "sword-hit-wall"
	bolt.visual_scene = VOXEL_BOLT_SCENE
	register(bolt)

	# ── 贯穿箭（贯穿射击技能，穿透多目标）──
	var piercing_arrow: Resource = PD.create("piercing_arrow", 24.0, "ranged")
	piercing_arrow.display_name = tr("贯穿箭")
	piercing_arrow.gravity_scale = 0.0
	piercing_arrow.collision_radius = 0.08
	piercing_arrow.collision_length = 0.7
	piercing_arrow.lifetime = 4.0
	piercing_arrow.pierce_count = 5
	piercing_arrow.pierce_falloff_percent = 15.0
	piercing_arrow.default_color = Color(0.9, 0.85, 0.5)
	piercing_arrow.default_emission = 1.0
	piercing_arrow.flight_sound_key = "sword-fly"
	piercing_arrow.visual_scene = VOXEL_ARROW_SCENE
	register(piercing_arrow)

	# ── 刺钩弩箭（击退+减速）──
	var barbed_bolt: Resource = PD.create("barbed_bolt", 26.0, "ranged")
	barbed_bolt.display_name = "刺钩弩箭"
	barbed_bolt.gravity_scale = 0.05
	barbed_bolt.collision_radius = 0.09
	barbed_bolt.collision_length = 0.55
	barbed_bolt.lifetime = 3.5
	barbed_bolt.default_color = Color(0.8, 0.3, 0.2)
	barbed_bolt.visual_scene = VOXEL_BOLT_SCENE
	register(barbed_bolt)

	# ── 齐射箭（压制齐射/弩箭齐射，AoE 爆炸）──
	var volley_arrow: Resource = PD.create("volley_arrow", 20.0, "ranged")
	volley_arrow.display_name = tr("齐射箭")
	volley_arrow.gravity_scale = 0.3
	volley_arrow.collision_radius = 0.08
	volley_arrow.collision_length = 0.5
	volley_arrow.lifetime = 3.0
	volley_arrow.impact_aoe_radius = 2.0
	volley_arrow.default_color = Color(0.6, 0.5, 0.3)
	volley_arrow.visual_scene = VOXEL_ARROW_SCENE
	register(volley_arrow)

	var volley_bolt: Resource = PD.create("volley_bolt", 24.0, "ranged")
	volley_bolt.display_name = tr("齐射弩箭")
	volley_bolt.gravity_scale = 0.1
	volley_bolt.collision_radius = 0.08
	volley_bolt.collision_length = 0.5
	volley_bolt.lifetime = 3.0
	volley_bolt.impact_aoe_radius = 2.5
	volley_bolt.default_color = Color(0.7, 0.6, 0.4)
	volley_bolt.visual_scene = VOXEL_BOLT_SCENE
	register(volley_bolt)

	# ── 元素弹（附魔法杖）──
	var elemental_bolt: Resource = PD.create("elemental_bolt", 16.0, "spell")
	elemental_bolt.display_name = "元素弹"
	elemental_bolt.gravity_scale = 0.0
	elemental_bolt.collision_radius = 0.18
	elemental_bolt.collision_length = 0.18
	elemental_bolt.lifetime = 3.0
	elemental_bolt.default_color = Color(1.0, 0.5, 0.1)
	elemental_bolt.default_emission = 2.0
	elemental_bolt.impact_sound_key = "sword-hit-wall"
	register(elemental_bolt)

	# ── 奥术弹（魔导书）──
	var arcane_bolt: Resource = PD.create("arcane_bolt", 14.0, "spell")
	arcane_bolt.display_name = tr("奥术弹")
	arcane_bolt.gravity_scale = 0.0
	arcane_bolt.collision_radius = 0.2
	arcane_bolt.collision_length = 0.2
	arcane_bolt.lifetime = 3.0
	arcane_bolt.default_color = Color(0.4, 0.3, 0.9)
	arcane_bolt.default_emission = 2.0
	register(arcane_bolt)

	# ── 寒冰新星弹（命中后 AoE 冰冻）──
	var frost_nova: Resource = PD.create("frost_nova_bolt", 12.0, "spell")
	frost_nova.display_name = "寒冰新星"
	frost_nova.gravity_scale = 0.0
	frost_nova.collision_radius = 0.22
	frost_nova.collision_length = 0.22
	frost_nova.lifetime = 2.5
	frost_nova.impact_aoe_radius = 2.25
	frost_nova.default_color = Color(0.3, 0.7, 1.0)
	frost_nova.default_emission = 2.5
	register(frost_nova)

	# ── 雷暴弹（命中后 AoE 眩晕）──
	var thunder: Resource = PD.create("thunder_bolt", 18.0, "spell")
	thunder.display_name = tr("雷暴")
	thunder.gravity_scale = 0.0
	thunder.collision_radius = 0.2
	thunder.collision_length = 0.2
	thunder.lifetime = 2.0
	thunder.impact_aoe_radius = 3.0
	thunder.default_color = Color(1.0, 1.0, 0.3)
	thunder.default_emission = 3.0
	register(thunder)


# ============================================================================
# 注册表 API
# ============================================================================

## 注册投射物定义
func register(data: Resource) -> void:
	if data == null or data.id.is_empty():
		return
	_registry[data.id] = data

## 按 id 获取投射物定义
func get_data(id: String) -> Resource:
	return _registry.get(id, null)

## 获取所有已注册的投射物 id
func get_registered_ids() -> Array:
	return _registry.keys()

## 投射物 id 是否已注册
func has_projectile(id: String) -> bool:
	return _registry.has(id)


# ============================================================================
# 生成 API
# ============================================================================

## 根据武器类型选择投射物 id
func get_projectile_id_for_weapon(weapon) -> String:
	if weapon == null:
		return ""
	var weapon_class := CB.get_weapon_class(weapon)
	return WEAPON_PROJECTILE_MAP.get(weapon_class, "")

## 根据技能选择投射物 id（优先技能专属，回退流派默认）
func get_projectile_id_for_skill(skill: Dictionary, weapon) -> String:
	var skill_id := String(skill.get("id", ""))
	if SKILL_PROJECTILE_MAP.has(skill_id):
		return SKILL_PROJECTILE_MAP[skill_id]
	var school: int = int(skill.get("school", -1))
	if SCHOOL_PROJECTILE_MAP.has(school):
		return SCHOOL_PROJECTILE_MAP[school]
	# 回退到武器默认投射物
	return get_projectile_id_for_weapon(weapon)

## 生成投射物（核心 API）
## projectile_id: 投射物定义 id
## spawn_transform: 生成位置与朝向（-Z 为飞行方向）
## source_player: 发射者 Player 节点
## weapon: 武器数据（WeaponData，可空）
## skill: 技能定义字典（可空）
func spawn(projectile_id: String, spawn_transform: Transform3D, source_player: Node3D, weapon = null, skill: Dictionary = {}) -> Node:
	var data: Resource = get_data(projectile_id)
	if data == null:
		push_warning("ProjectileService: 投射物 id '%s' 未注册" % projectile_id)
		return null
	var parent: Node = _get_spawn_parent()
	if parent == null:
		push_warning("ProjectileService: 无法获取生成父节点")
		return null
	# 从对象池获取或实例化新投射物
	var projectile: Node3D = _acquire_projectile()
	if projectile == null:
		push_warning("ProjectileService: ProjectileEntity 场景实例化失败")
		return null
	# 在 add_child 之前设置所有属性，确保 _ready() 能正确读取
	projectile.set("projectile_data", data)
	projectile.set("source_player", source_player)
	projectile.set("weapon_data", weapon)
	projectile.set("skill_data", skill)
	# 填充战斗结算参数
	projectile.set("main_hand_type", CB.get_weapon_class(weapon))
	projectile.set("off_hand_type", _get_off_hand_type(source_player))
	projectile.set("attacker_attrs", _get_attrs(source_player))
	projectile.set("attacker_level", _get_level(source_player))
	projectile.set("weapon_condition_wear", WEAPON_CONDITION_WEAR)
	# 先设置本地 transform（add_child 前 global_transform 不可用）
	projectile.transform = spawn_transform
	# 如果是池中复用的节点，标记需要重新 _ready
	if projectile.get_parent() == null and projectile.is_inside_tree() == false:
		projectile.request_ready()
	# 添加到场景树（触发 _ready，此时所有属性已就绪）
	parent.add_child(projectile)
	# 确保全局变换正确（父节点非原点时需要）
	projectile.global_transform = spawn_transform
	return projectile

## 为武器生成投射物（远程武器普通攻击用）
func spawn_for_weapon(weapon, spawn_transform: Transform3D, source_player: Node3D) -> Node:
	var pid := get_projectile_id_for_weapon(weapon)
	if pid.is_empty():
		return null
	return spawn(pid, spawn_transform, source_player, weapon, {})

## 为技能生成投射物（远程/法术技能用）
func spawn_for_skill(skill: Dictionary, spawn_transform: Transform3D, source_player: Node3D, weapon = null) -> Node:
	var pid := get_projectile_id_for_skill(skill, weapon)
	if pid.is_empty():
		return null
	return spawn(pid, spawn_transform, source_player, weapon, skill)

## 双发生成（双发连射技能用）：生成两发投射物，第二发略带偏移
func spawn_double(projectile_id: String, spawn_transform: Transform3D, source_player: Node3D, weapon = null, skill: Dictionary = {}, spread_deg: float = 3.0) -> Array:
	var results: Array = []
	var first := spawn(projectile_id, spawn_transform, source_player, weapon, skill)
	if first != null:
		results.append(first)
	# 第二发带角度偏移
	var offset_transform := spawn_transform.rotated_local(Vector3.UP, deg_to_rad(spread_deg))
	var second := spawn(projectile_id, offset_transform, source_player, weapon, skill)
	if second != null:
		results.append(second)
	return results

## 散射生成（齐射技能用）：生成 count 发投射物，呈扇形散布
func spawn_spread(projectile_id: String, spawn_transform: Transform3D, source_player: Node3D, count: int, spread_deg: float, weapon = null, skill: Dictionary = {}) -> Array:
	var results: Array = []
	if count <= 0:
		return results
	var half_spread := spread_deg * 0.5
	var step := spread_deg / maxf(float(count - 1), 1.0)
	for i in range(count):
		var angle: float = -half_spread + step * float(i) if count > 1 else 0.0
		var t := spawn_transform.rotated_local(Vector3.UP, deg_to_rad(angle))
		var proj := spawn(projectile_id, t, source_player, weapon, skill)
		if proj != null:
			results.append(proj)
	return results


# ============================================================================
# 对象池
# ============================================================================

## 从对象池获取投射物，池空时实例化新的
func _acquire_projectile() -> Node3D:
	while not _projectile_pool.is_empty():
		var projectile: Node3D = _projectile_pool.pop_back()
		if is_instance_valid(projectile):
			return projectile
	# 池空或已失效，实例化新的
	return PROJECTILE_PREFAB.instantiate() as Node3D

## 将投射物归还到对象池供下次复用
func return_projectile_to_pool(projectile: Node3D) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	# 池已满，直接释放
	if _projectile_pool.size() >= POOL_MAX_SIZE:
		projectile.queue_free()
		return
	# 从场景树移除（但不释放）
	if projectile.get_parent() != null:
		projectile.get_parent().remove_child(projectile)
	# 停止物理与处理
	projectile.set_physics_process(false)
	projectile.set_process(false)
	_projectile_pool.append(projectile)

## 清空对象池（关卡切换时调用）
func clear_pool() -> void:
	for projectile in _projectile_pool:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_projectile_pool.clear()

## 获取当前对象池大小（测试/调试用）
func get_pool_size() -> int:
	return _projectile_pool.size()

# ============================================================================
# 内部辅助
# ============================================================================

## 获取生成父节点（当前关卡）
func _get_spawn_parent() -> Node:
	var gs: Node = Service.game_state()
	if gs != null:
		var level: Node = gs.get("current_level")
		if level != null and is_instance_valid(level):
			return level
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		if tree.current_scene != null:
			return tree.current_scene
		if tree.root != null:
			return tree.root
	return null

## 获取玩家属性字典
func _get_attrs(source_player: Node3D) -> Dictionary:
	var ap: Node = Service.attr_panel()
	if ap != null and ap.has_method("get_player_attrs"):
		return ap.get_player_attrs()
	return {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}

## 获取玩家等级
func _get_level(source_player: Node3D) -> int:
	var ap: Node = Service.attr_panel()
	if ap != null and ap.has_method("get_level"):
		return ap.get_level()
	return 1

## 获取副手武器类型
func _get_off_hand_type(source_player: Node3D) -> String:
	if source_player == null or not is_instance_valid(source_player):
		return ""
	if not source_player.has_method("get") or not "equipment" in source_player:
		return ""
	var eq: Node = source_player.get("equipment")
	if eq == null:
		return ""
	if eq.has_method("has_shield") and eq.has_shield():
		return "shield"
	return ""
