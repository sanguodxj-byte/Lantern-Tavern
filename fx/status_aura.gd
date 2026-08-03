class_name StatusAura
extends Node3D

## 状态效果光环 — 挂载到敌人身上，显示当前活跃的状态效果粒子。
## 每种状态效果有独立的粒子颜色与运动形态（上浮 / 下滴 / 旋绕等）。
##
## 持续型特效：不使用 one_shot，只要敌人有效且该 debuff 仍活跃就一直播放；
## 状态消失、敌人失效或阵亡时自动 queue_free。
## 节点通过 setup(enemy, status_type) 配置；颜色/运动由 STATUS_CONFIG 驱动。

# ParticleProcessMaterial.EmissionShape.EMISSION_SHAPE_SPHERE（与既有 fx 场景一致，使用数值避免枚举解析差异）
const _EMISSION_SHAPE_SPHERE := 1
## 跟随宿主时的垂直偏移（米）：粒子云位于角色中心质量略上方
const FOLLOW_OFFSET := Vector3(0.0, 1.0, 0.0)

## 每种状态效果的显示配置。
## color:  粒子与点光源颜色（与术语表/符文机制对齐）
## dir:    发射方向
## spread: 发射锥半角（度）
## vel:    初始速度（米/秒），实际 min = vel*0.7，max = vel
## gravity: 粒子后续重力（上浮类用小负值，下滴类用正值）
## radius: 球形发射半径（决定光环覆盖范围）
## turb:   湍流影响强度（>0 启用，旋绕/波动类形态）
## light_e / light_r: 点光源能量与范围
const STATUS_CONFIG := {
	"burn":       {"color": Color(1.0, 0.4, 0.1),  "dir": Vector3(0, 1, 0),  "spread": 30.0,  "vel": 0.8, "gravity": Vector3(0, -0.5, 0), "radius": 0.45, "turb": 0.0, "light_e": 0.7, "light_r": 2.0},
	"poison":     {"color": Color(0.3, 0.8, 0.2),  "dir": Vector3(0, 1, 0),  "spread": 180.0, "vel": 0.4, "gravity": Vector3(0, -0.2, 0), "radius": 0.40, "turb": 0.3, "light_e": 0.35, "light_r": 1.6},
	"slow":       {"color": Color(0.3, 0.5, 1.0),  "dir": Vector3(0, 1, 0),  "spread": 180.0, "vel": 0.2, "gravity": Vector3.ZERO,        "radius": 0.40, "turb": 0.0, "light_e": 0.4, "light_r": 1.8},
	"blind":      {"color": Color(0.6, 0.3, 0.8),  "dir": Vector3(0, 1, 0),  "spread": 180.0, "vel": 0.3, "gravity": Vector3.ZERO,        "radius": 0.45, "turb": 0.5, "light_e": 0.3, "light_r": 1.8},
	"fear":       {"color": Color(0.9, 0.9, 0.9),  "dir": Vector3(0, 1, 0),  "spread": 180.0, "vel": 0.3, "gravity": Vector3.ZERO,        "radius": 0.45, "turb": 0.4, "light_e": 0.3, "light_r": 1.6},
	"corrupt":    {"color": Color(0.5, 0.1, 0.15), "dir": Vector3(0, -1, 0), "spread": 60.0,  "vel": 0.5, "gravity": Vector3(0, 1.5, 0),  "radius": 0.35, "turb": 0.0, "light_e": 0.4, "light_r": 1.6},
	"stun":       {"color": Color(1.0, 0.9, 0.2),  "dir": Vector3(0, 1, 0),  "spread": 180.0, "vel": 0.6, "gravity": Vector3.ZERO,        "radius": 0.40, "turb": 0.6, "light_e": 0.5, "light_r": 1.8},
	"ensnare":    {"color": Color(0.6, 0.4, 0.2),  "dir": Vector3(0, 1, 0),  "spread": 120.0, "vel": 0.3, "gravity": Vector3(0, -0.5, 0), "radius": 0.40, "turb": 0.0, "light_e": 0.3, "light_r": 1.6},
	"wet":        {"color": Color(0.2, 0.6, 0.9),  "dir": Vector3(0, 1, 0),  "spread": 60.0,  "vel": 0.5, "gravity": Vector3(0, -2.0, 0), "radius": 0.40, "turb": 0.0, "light_e": 0.3, "light_r": 1.6},
	"choke":      {"color": Color(0.4, 0.4, 0.4),  "dir": Vector3(0, 1, 0),  "spread": 180.0, "vel": 0.3, "gravity": Vector3.ZERO,        "radius": 0.40, "turb": 0.3, "light_e": 0.25, "light_r": 1.4},
	"tremor":     {"color": Color(0.7, 0.5, 0.3),  "dir": Vector3(0, 1, 0),  "spread": 180.0, "vel": 0.4, "gravity": Vector3(0, -1.0, 0), "radius": 0.40, "turb": 0.0, "light_e": 0.3, "light_r": 1.6},
	"terror":     {"color": Color(0.4, 0.2, 0.5),  "dir": Vector3(0, 1, 0),  "spread": 180.0, "vel": 0.3, "gravity": Vector3.ZERO,        "radius": 0.45, "turb": 0.4, "light_e": 0.3, "light_r": 1.6},
	"armor_break":{"color": Color(0.8, 0.6, 0.3),  "dir": Vector3(0, 1, 0),  "spread": 120.0, "vel": 0.4, "gravity": Vector3(0, -1.0, 0), "radius": 0.40, "turb": 0.0, "light_e": 0.3, "light_r": 1.6},
	"sunder":     {"color": Color(0.9, 0.5, 0.2),  "dir": Vector3(0, 1, 0),  "spread": 120.0, "vel": 0.5, "gravity": Vector3(0, -1.0, 0), "radius": 0.40, "turb": 0.0, "light_e": 0.35, "light_r": 1.7},
}

var _current_status: String = ""
var _enemy: Node = null
var _cfg: Dictionary = {}

func _particles_node() -> GPUParticles3D:
	return get_node_or_null("Particles") as GPUParticles3D

func _light_node() -> OmniLight3D:
	return get_node_or_null("Light") as OmniLight3D

## 由战斗系统在生成光环后调用：绑定宿主敌人与状态类型。
## 可在 add_child 之前或之后调用（节点不在树中时缓存配置，_ready 再应用）。
func setup(enemy: Node, status_type: String) -> void:
	_enemy = enemy
	_current_status = status_type
	_cfg = STATUS_CONFIG.get(status_type, {})
	if is_inside_tree():
		_apply_config()

func _ready() -> void:
	_apply_config()
	var particles := _particles_node()
	if particles != null:
		particles.emitting = true

func _apply_config() -> void:
	var particles := _particles_node()
	if particles == null:
		return
	var mat := particles.process_material as ParticleProcessMaterial
	if mat == null:
		return
	var color: Color = _cfg.get("color", Color.WHITE)
	mat.color = color
	mat.direction = _cfg.get("dir", Vector3.UP)
	mat.spread = float(_cfg.get("spread", 30.0))
	var vel: float = float(_cfg.get("vel", 0.5))
	mat.initial_velocity_min = vel * 0.7
	mat.initial_velocity_max = vel
	mat.gravity = _cfg.get("gravity", Vector3.ZERO)
	mat.emission_shape = _EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = float(_cfg.get("radius", 0.4))
	var turb: float = float(_cfg.get("turb", 0.0))
	if turb > 0.0:
		mat.turbulence_enabled = true
		mat.turbulence_noise_scale = 2.0
		mat.turbulence_influence_min = 0.0
		mat.turbulence_influence_max = turb
	else:
		mat.turbulence_enabled = false
	var light := _light_node()
	if light != null:
		light.light_color = color
		light.light_energy = float(_cfg.get("light_e", 0.4))
		light.omni_range = float(_cfg.get("light_r", 1.8))

func _process(_delta: float) -> void:
	# 宿主失效：立即销毁光环
	if not is_instance_valid(_enemy) or not _enemy.is_inside_tree():
		queue_free()
		return
	# 状态已不活跃：销毁光环
	if not _is_status_active_on_enemy():
		queue_free()
		return
	# 跟随宿主位置（中心质量略上方）
	var host := _enemy as Node3D
	if host != null:
		global_position = host.global_position + FOLLOW_OFFSET

## 通过敌人 combat_debuffs 字典查询状态是否仍活跃。
## 敌人不暴露该字典时回退为“只要敌人有效就持续”，避免硬耦合 Enemy 类。
func _is_status_active_on_enemy() -> bool:
	if _current_status.is_empty():
		return true
	var debuffs = _enemy.get("combat_debuffs")
	if debuffs is Dictionary:
		return (debuffs as Dictionary).has(_current_status)
	return true
