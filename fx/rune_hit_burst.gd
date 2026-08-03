class_name RuneHitBurst
extends Node3D

## 符文命中爆发特效 — 一次性播放后自动销毁。
## 对应符文之语机制被动：
##   FIRE_EXPLOSION   → rune_word_throw_explosion（焰投之语）
##   STORM             → rune_word_storm（风暴之语）
##   LIGHTNING_CHAIN   → rune_word_thunder_stream（雷穿之语）
##   SMOKE_TRAP        → rune_word_smoke_trap（烟泥之语）
##   TREMOR            → rune_word_tremor（流震之语）
##   DARK_DRAIN        → rune_word_dark_drain（暗渊之语）
##   HOLY_LIGHT        → rune_word_blinding_light（炫光之语）
##
## 使用 ParticleProcessMaterial（非 ShaderMaterial）保持简洁；
## 粒子使用 BILLBOARD_PARTICLES 朝向相机。_ready 中 one_shot 发射，
## finished 信号连接 queue_free 自动清理；点光源在粒子寿命内淡出。

# ParticleProcessMaterial.EmissionShape.EMISSION_SHAPE_SPHERE
const _EMISSION_SHAPE_SPHERE := 1

enum BurstType { FIRE_EXPLOSION, STORM, LIGHTNING_CHAIN, SMOKE_TRAP, TREMOR, DARK_DRAIN, HOLY_LIGHT }

## 每种爆发类型的形态配置。
## color:  自然色（调用方未显式指定 color 时使用）
## amount: 粒子数（保持低量以兼顾性能）
## radius: 球形发射半径（决定覆盖范围）
## dir / spread / vel / gravity / turb: 见 StatusAura 注释
## lifetime: 粒子寿命（同时决定点光源淡出时长与 finished 触发时机）
## scale:   相对 QuadMesh 基础尺寸的缩放（烟雾云更大，雷电更细）
## light_e / light_r: 起始点光源能量与范围
const BURST_CONFIG := {
	BurstType.FIRE_EXPLOSION:  {"color": Color(1.0, 0.45, 0.1), "amount": 30, "radius": 0.3, "dir": Vector3(0, 1, 0), "spread": 180.0, "vel": 4.0, "gravity": Vector3(0, -2, 0), "turb": 0.0, "lifetime": 0.8, "scale": 1.3, "light_e": 2.5, "light_r": 4.0},
	BurstType.STORM:           {"color": Color(0.3, 0.7, 1.0),  "amount": 40, "radius": 1.0, "dir": Vector3(0, 1, 0), "spread": 180.0, "vel": 1.5, "gravity": Vector3(0, -0.5, 0), "turb": 0.6, "lifetime": 1.2, "scale": 1.2, "light_e": 1.5, "light_r": 4.5},
	BurstType.LIGHTNING_CHAIN: {"color": Color(1.0, 0.9, 0.2),  "amount": 20, "radius": 0.6, "dir": Vector3(0, 1, 0), "spread": 180.0, "vel": 3.0, "gravity": Vector3.ZERO,       "turb": 1.0, "lifetime": 0.5, "scale": 1.0, "light_e": 3.0, "light_r": 4.0},
	BurstType.SMOKE_TRAP:      {"color": Color(0.4, 0.4, 0.4),  "amount": 30, "radius": 0.5, "dir": Vector3(0, 1, 0), "spread": 120.0, "vel": 0.8, "gravity": Vector3(0, -0.3, 0), "turb": 0.4, "lifetime": 1.5, "scale": 2.0, "light_e": 0.3, "light_r": 2.5},
	BurstType.TREMOR:          {"color": Color(0.7, 0.5, 0.3),  "amount": 24, "radius": 0.6, "dir": Vector3(0, 1, 0), "spread": 180.0, "vel": 3.5, "gravity": Vector3(0, -3, 0), "turb": 0.0, "lifetime": 0.7, "scale": 1.5, "light_e": 0.5, "light_r": 3.0},
	BurstType.DARK_DRAIN:      {"color": Color(0.5, 0.15, 0.6), "amount": 28, "radius": 0.7, "dir": Vector3(0, -1, 0), "spread": 180.0, "vel": 0.6, "gravity": Vector3(0, 1.5, 0), "turb": 0.5, "lifetime": 1.0, "scale": 1.0, "light_e": 1.0, "light_r": 3.0},
	BurstType.HOLY_LIGHT:      {"color": Color(1.0, 0.85, 0.3), "amount": 26, "radius": 0.4, "dir": Vector3(0, 1, 0), "spread": 60.0,  "vel": 2.5, "gravity": Vector3(0, -1, 0), "turb": 0.2, "lifetime": 1.0, "scale": 1.2, "light_e": 3.0, "light_r": 5.0},
}

var _burst_type: int = BurstType.FIRE_EXPLOSION
var _tint := Color.WHITE
var _target_position := Vector3.ZERO

func _particles_node() -> GPUParticles3D:
	return get_node_or_null("Particles") as GPUParticles3D

func _light_node() -> OmniLight3D:
	return get_node_or_null("Light") as OmniLight3D

## 由战斗系统在生成爆发后调用。
## color 默认 Color.WHITE 作为哨兵：未显式指定时使用爆发类型自身的自然色。
func setup(burst_type: int, position: Vector3, color: Color = Color.WHITE) -> void:
	_burst_type = burst_type
	_tint = color
	_target_position = position
	if is_inside_tree():
		global_position = position
		_apply_burst_config()

func _ready() -> void:
	global_position = _target_position
	_apply_burst_config()
	var particles := _particles_node()
	if particles != null:
		particles.emitting = true
		particles.finished.connect(queue_free)
	_fade_light()

func _apply_burst_config() -> void:
	var particles := _particles_node()
	if particles == null:
		return
	var cfg: Dictionary = BURST_CONFIG.get(_burst_type, {})
	# 白色哨兵：未显式指定 tint 时回退到爆发类型的自然色
	var final_color: Color = _tint if _tint != Color.WHITE else cfg.get("color", Color.WHITE)
	particles.amount = int(cfg.get("amount", 24))
	particles.lifetime = float(cfg.get("lifetime", 0.8))
	var mat := particles.process_material as ParticleProcessMaterial
	if mat != null:
		mat.color = final_color
		mat.direction = cfg.get("dir", Vector3.UP)
		mat.spread = float(cfg.get("spread", 180.0))
		var vel: float = float(cfg.get("vel", 2.0))
		mat.initial_velocity_min = vel * 0.6
		mat.initial_velocity_max = vel
		mat.gravity = cfg.get("gravity", Vector3.ZERO)
		mat.emission_shape = _EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = float(cfg.get("radius", 0.4))
		var turb: float = float(cfg.get("turb", 0.0))
		if turb > 0.0:
			mat.turbulence_enabled = true
			mat.turbulence_noise_scale = 2.0
			mat.turbulence_influence_min = 0.0
			mat.turbulence_influence_max = turb
		else:
			mat.turbulence_enabled = false
		var sc: float = float(cfg.get("scale", 1.0))
		mat.scale_min = maxf(0.5, sc * 0.7)
		mat.scale_max = sc
	var light := _light_node()
	if light != null:
		light.light_color = final_color
		light.light_energy = float(cfg.get("light_e", 1.0))
		light.omni_range = float(cfg.get("light_r", 3.0))

## 点光源在粒子寿命内淡出至 0，制造“短暂闪光”效果。
## tween 绑定到本节点，queue_free 时自动终止。
func _fade_light() -> void:
	var light := _light_node()
	if light == null:
		return
	var particles := _particles_node()
	var fade_duration := 0.6
	if particles != null and particles.lifetime > 0.0:
		fade_duration = particles.lifetime
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, fade_duration)
