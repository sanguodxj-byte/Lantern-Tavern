class_name MainCamera
extends Camera3D

## B2 命中冲击（Hit Impact）：命中确认后施加低幅度镜头旋转脉冲。
## 幅度限制在 0.5°~1.5°（docs/task.md 阶段 5），受 Settings.camera_impact_enabled 控制，
## 关闭时不施加任何冲击。冲击是瞬态偏移，随时间衰减回基线，不残留永久旋转。
const IMPACT_PITCH_DEG := 0.8
const IMPACT_CRIT_PITCH_DEG := 1.4
const IMPACT_RECOVER_SEC := 0.12

var duration_map : Dictionary[GameEvents.ImpactIntensity, int] = {
	GameEvents.ImpactIntensity.LOW: 70,
	GameEvents.ImpactIntensity.MEDIUM: 110,
	GameEvents.ImpactIntensity.HIGH: 160,
}
var current_intensity : GameEvents.ImpactIntensity
var intensity_map : Dictionary[GameEvents.ImpactIntensity, float] = {
	GameEvents.ImpactIntensity.LOW: 0.015,
	GameEvents.ImpactIntensity.MEDIUM: 0.035,
	GameEvents.ImpactIntensity.HIGH: 0.06,
}
var initial_transform: Transform3D
var is_shaking := false
var is_wakeup_blink_playing := false
var time_start_shaking := Time.get_ticks_msec()

## B2 命中冲击状态：当前目标俯仰偏移（度）、剩余恢复时间（秒）与上一帧已施加的偏移。
var _impact_pitch_deg := 0.0
var _impact_time_left := 0.0
var _impact_applied_deg := 0.0

func _ready() -> void:
	GameEvents.impact_felt.connect(on_impact_felt)
	if GameEvents.has_signal("player_hit_enemy"):
		GameEvents.player_hit_enemy.connect(_on_player_hit_enemy)

func _process(delta: float) -> void:
	if is_shaking:
		var duration_since_start_shake := Time.get_ticks_msec() - time_start_shaking
		if duration_since_start_shake < duration_map[current_intensity]:
			var shake_intensity := intensity_map[current_intensity]
			var offset := Vector3(randf_range(-shake_intensity, shake_intensity), randf_range(-shake_intensity, shake_intensity), 0)
			transform.origin = initial_transform.origin + offset
		else:
			transform.origin = initial_transform.origin
			is_shaking = false
	_update_hit_impact(delta)

func play_wakeup_blink() -> void:
	is_wakeup_blink_playing = true
	var tween := create_tween()
	tween.tween_property(self, "fov", 68.0, 0.12)
	tween.tween_interval(0.08)
	tween.tween_property(self, "fov", 75.0, 0.22)
	tween.finished.connect(func() -> void:
		is_wakeup_blink_playing = false
	)

func on_impact_felt(intensity: GameEvents.ImpactIntensity) -> void:
	if not is_shaking:
		is_shaking = true
		time_start_shaking = Time.get_ticks_msec()
		initial_transform = transform
		current_intensity = intensity

## B2 命中冲击入口：玩家命中敌人时施加低幅度俯仰脉冲。
## 受 Settings.camera_impact_enabled 控制，关闭时完全不施加冲击。
func _on_player_hit_enemy(hit_data: Dictionary) -> void:
	if not Settings.camera_impact_enabled:
		return
	var pitch := IMPACT_CRIT_PITCH_DEG if bool(hit_data.get("is_crit", false)) else IMPACT_PITCH_DEG
	_impact_pitch_deg = maxf(_impact_pitch_deg, pitch)
	_impact_time_left = IMPACT_RECOVER_SEC

## 逐帧更新冲击：先移除上一帧施加的偏移（恢复玩家控制的基线），
## 再按剩余时间衰减后重新施加，保证瞬态且衰减回基线。
func _update_hit_impact(delta: float) -> void:
	rotation_degrees.x -= _impact_applied_deg
	_impact_applied_deg = 0.0
	if _impact_time_left <= 0.0:
		_impact_pitch_deg = 0.0
		return
	_impact_time_left = maxf(_impact_time_left - delta, 0.0)
	var step := delta / IMPACT_RECOVER_SEC
	_impact_pitch_deg = lerpf(_impact_pitch_deg, 0.0, step)
	if _impact_time_left <= 0.0:
		_impact_pitch_deg = 0.0
	rotation_degrees.x += _impact_pitch_deg
	_impact_applied_deg = _impact_pitch_deg
