class_name FirstPersonEquipmentMotion
extends RefCounted

## Additive, presentation-only motion for first-person weapons and shields.
##
## The controller never reads input or gameplay state directly. Player/ViewModel
## supplies local velocity, grounded state and look deltas; the resulting
## transform is applied only to the visual equipment root. Combat timing,
## hitboxes, damage and the third-person rig remain authoritative elsewhere.

const MAX_FRAME_DELTA_SEC := 1.0 / 15.0
const MAX_SIMULATION_STEP_SEC := 1.0 / 120.0
const REFERENCE_RUN_SPEED := 6.5
const MAX_LOOK_DELTA_PIXELS := 72.0

const DEFAULT_PROFILE := {
	"mass": 1.0,
	"bob": 1.0,
	"sway": 1.0,
	"sprint": 1.0,
	"recoil": 1.0,
}

## Equipment mass changes cadence and response without changing gameplay speed.
## Light tools settle quickly; heavy two-handed silhouettes carry more lag and
## follow-through while keeping the reticle and camera stable.
const PROFILE_SETTINGS := {
	&"unarmed": {"mass": 0.72, "bob": 0.85, "sway": 0.90, "sprint": 0.85, "recoil": 0.75},
	&"dagger": {"mass": 0.72, "bob": 1.08, "sway": 1.16, "sprint": 1.05, "recoil": 0.72},
	&"shortsword": {"mass": 0.86, "bob": 1.02, "sway": 1.08, "sprint": 1.00, "recoil": 0.82},
	&"sword": {"mass": 1.00, "bob": 0.96, "sway": 1.00, "sprint": 0.96, "recoil": 0.88},
	&"greatsword": {"mass": 1.34, "bob": 0.78, "sway": 1.18, "sprint": 0.82, "recoil": 1.16},
	&"axe": {"mass": 1.24, "bob": 0.82, "sway": 1.14, "sprint": 0.86, "recoil": 1.12},
	&"warhammer": {"mass": 1.40, "bob": 0.74, "sway": 1.22, "sprint": 0.78, "recoil": 1.22},
	&"spear": {"mass": 1.18, "bob": 0.84, "sway": 1.08, "sprint": 0.88, "recoil": 1.02},
	&"bow": {"mass": 0.92, "bob": 0.90, "sway": 0.92, "sprint": 0.94, "recoil": 0.72},
	&"crossbow": {"mass": 1.18, "bob": 0.82, "sway": 0.88, "sprint": 0.86, "recoil": 1.20},
	&"staff": {"mass": 1.08, "bob": 0.86, "sway": 1.02, "sprint": 0.90, "recoil": 0.92},
	&"grimoire": {"mass": 0.84, "bob": 0.92, "sway": 0.86, "sprint": 0.92, "recoil": 0.78},
	&"shield": {"mass": 1.30, "bob": 0.72, "sway": 1.06, "sprint": 0.76, "recoil": 1.24},
}

var _profile_id: StringName = &"sword"
var _profile: Dictionary = DEFAULT_PROFILE
var _local_velocity := Vector3.ZERO
var _smoothed_local_velocity := Vector3.ZERO
var _previous_smoothed_velocity := Vector3.ZERO
var _grounded := true
var _last_grounded := true
var _sprinting := false
var _last_vertical_velocity := 0.0
var _look_impulse := Vector2.ZERO

var _elapsed_sec := 0.0
var _gait_phase := 0.0
var _movement_weight := 0.0
var _sprint_weight := 0.0

var _position := Vector3.ZERO
var _position_velocity := Vector3.ZERO
var _rotation := Vector3.ZERO
var _rotation_velocity := Vector3.ZERO
var _recoil_position := Vector3.ZERO
var _recoil_position_velocity := Vector3.ZERO
var _recoil_rotation := Vector3.ZERO
var _recoil_rotation_velocity := Vector3.ZERO
var _landing_position := Vector3.ZERO
var _landing_position_velocity := Vector3.ZERO
var _landing_rotation := Vector3.ZERO
var _landing_rotation_velocity := Vector3.ZERO
var _shield_impact_position := Vector3.ZERO
var _shield_impact_position_velocity := Vector3.ZERO
var _shield_impact_rotation := Vector3.ZERO
var _shield_impact_rotation_velocity := Vector3.ZERO


func _init() -> void:
	set_profile(_profile_id)


func set_profile(profile_id: StringName) -> void:
	_profile_id = profile_id if PROFILE_SETTINGS.has(profile_id) else &"sword"
	_profile = PROFILE_SETTINGS.get(_profile_id, DEFAULT_PROFILE)


func get_profile_id() -> StringName:
	return _profile_id


func get_profile_mass() -> float:
	return float(_profile.get("mass", 1.0))


func set_motion_state(local_velocity: Vector3, grounded: bool, sprinting: bool) -> void:
	_local_velocity = local_velocity if local_velocity.is_finite() else Vector3.ZERO
	_grounded = grounded
	_sprinting = sprinting


func add_look_input(relative: Vector2) -> void:
	if not is_finite(relative.x) or not is_finite(relative.y):
		return
	_look_impulse += relative
	_look_impulse.x = clampf(_look_impulse.x, -MAX_LOOK_DELTA_PIXELS, MAX_LOOK_DELTA_PIXELS)
	_look_impulse.y = clampf(_look_impulse.y, -MAX_LOOK_DELTA_PIXELS, MAX_LOOK_DELTA_PIXELS)


func add_recoil(strength: float = 1.0, horizontal_bias: float = 0.0) -> void:
	var scaled_strength := clampf(strength, 0.0, 2.0) * float(_profile.get("recoil", 1.0))
	var clamped_bias := clampf(horizontal_bias, -1.0, 1.0)
	_recoil_position += Vector3(clamped_bias * 0.006, -0.006, 0.052) * scaled_strength
	_recoil_rotation += Vector3(
		deg_to_rad(5.4),
		deg_to_rad(clamped_bias * 1.8),
		deg_to_rad(-clamped_bias * 1.2)
	) * scaled_strength


func add_shield_impact(strength: float = 1.0, horizontal_bias: float = 0.0) -> void:
	var scaled_strength := clampf(strength, 0.0, 2.0)
	var clamped_bias := clampf(horizontal_bias, -1.0, 1.0)
	_shield_impact_position += Vector3(clamped_bias * 0.012, -0.008, 0.055) * scaled_strength
	_shield_impact_rotation += Vector3(
		deg_to_rad(4.0),
		deg_to_rad(clamped_bias * 3.2),
		deg_to_rad(-clamped_bias * 2.4)
	) * scaled_strength


func step(
	delta: float,
	aim_weight: float = 0.0,
	action_weight: float = 0.0,
	intensity: float = 1.0
) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var remaining := minf(delta, MAX_FRAME_DELTA_SEC)
	while remaining > 0.000001:
		var substep := minf(remaining, MAX_SIMULATION_STEP_SEC)
		_step_subframe(
			substep,
			clampf(aim_weight, 0.0, 1.0),
			clampf(action_weight, 0.0, 1.0),
			clampf(intensity, 0.0, 1.5)
		)
		remaining -= substep


func get_transform() -> Transform3D:
	var final_position := _position + _recoil_position + _landing_position
	var final_rotation := _rotation + _recoil_rotation + _landing_rotation
	final_position.x = clampf(final_position.x, -0.20, 0.20)
	final_position.y = clampf(final_position.y, -0.20, 0.20)
	final_position.z = clampf(final_position.z, -0.20, 0.20)
	final_rotation.x = clampf(final_rotation.x, -0.38, 0.38)
	final_rotation.y = clampf(final_rotation.y, -0.38, 0.38)
	final_rotation.z = clampf(final_rotation.z, -0.38, 0.38)
	return Transform3D(Basis.from_euler(final_rotation), final_position)


func get_position_offset() -> Vector3:
	return get_transform().origin


func get_rotation_offset() -> Vector3:
	return get_transform().basis.get_euler()


func get_shield_impact_transform() -> Transform3D:
	return Transform3D(Basis.from_euler(_shield_impact_rotation), _shield_impact_position)


func clear_shield_impact() -> void:
	_shield_impact_position = Vector3.ZERO
	_shield_impact_position_velocity = Vector3.ZERO
	_shield_impact_rotation = Vector3.ZERO
	_shield_impact_rotation_velocity = Vector3.ZERO


func reset() -> void:
	_local_velocity = Vector3.ZERO
	_smoothed_local_velocity = Vector3.ZERO
	_previous_smoothed_velocity = Vector3.ZERO
	_grounded = true
	_last_grounded = true
	_sprinting = false
	_last_vertical_velocity = 0.0
	_look_impulse = Vector2.ZERO
	_elapsed_sec = 0.0
	_gait_phase = 0.0
	_movement_weight = 0.0
	_sprint_weight = 0.0
	_position = Vector3.ZERO
	_position_velocity = Vector3.ZERO
	_rotation = Vector3.ZERO
	_rotation_velocity = Vector3.ZERO
	_recoil_position = Vector3.ZERO
	_recoil_position_velocity = Vector3.ZERO
	_recoil_rotation = Vector3.ZERO
	_recoil_rotation_velocity = Vector3.ZERO
	_landing_position = Vector3.ZERO
	_landing_position_velocity = Vector3.ZERO
	_landing_rotation = Vector3.ZERO
	_landing_rotation_velocity = Vector3.ZERO
	clear_shield_impact()


func _step_subframe(delta: float, aim_weight: float, action_weight: float, intensity: float) -> void:
	_elapsed_sec += delta
	var velocity_blend := 1.0 - exp(-10.0 * delta)
	_previous_smoothed_velocity = _smoothed_local_velocity
	_smoothed_local_velocity = _smoothed_local_velocity.lerp(_local_velocity, velocity_blend)
	var acceleration := (_smoothed_local_velocity - _previous_smoothed_velocity) / maxf(delta, 0.0001)
	acceleration.x = clampf(acceleration.x, -14.0, 14.0)
	acceleration.y = clampf(acceleration.y, -18.0, 18.0)
	acceleration.z = clampf(acceleration.z, -14.0, 14.0)

	var horizontal_speed := Vector2(_smoothed_local_velocity.x, _smoothed_local_velocity.z).length()
	var speed_ratio := clampf(horizontal_speed / REFERENCE_RUN_SPEED, 0.0, 1.0)
	var moving_target := smoothstep(0.08, 0.45, horizontal_speed) if _grounded else 0.0
	_movement_weight = _damp(_movement_weight, moving_target, 11.0, delta)
	var sprint_target := 1.0 if _sprinting and _grounded and speed_ratio > 0.55 else 0.0
	_sprint_weight = _damp(_sprint_weight, sprint_target, 8.0, delta)

	if _grounded and _movement_weight > 0.01:
		var cadence := lerpf(7.0, 11.2, speed_ratio) / sqrt(maxf(get_profile_mass(), 0.35))
		_gait_phase = fmod(_gait_phase + cadence * delta, TAU)

	if _grounded and not _last_grounded:
		var landing_strength := clampf(absf(_last_vertical_velocity) / 9.0, 0.16, 1.0)
		_landing_position += Vector3(0.0, -0.038, 0.030) * landing_strength
		_landing_rotation += Vector3(deg_to_rad(3.2), 0.0, 0.0) * landing_strength
	elif not _grounded and _last_grounded and _local_velocity.y > 0.1:
		_landing_position += Vector3(0.0, 0.010, -0.012)
		_landing_rotation += Vector3(deg_to_rad(-1.2), 0.0, 0.0)
	_last_grounded = _grounded
	_last_vertical_velocity = _local_velocity.y

	var bob_scale := float(_profile.get("bob", 1.0))
	var sway_scale := float(_profile.get("sway", 1.0))
	var sprint_scale := float(_profile.get("sprint", 1.0))
	var gait_sin := sin(_gait_phase)
	var gait_double := sin(_gait_phase * 2.0)
	var gait_double_cos := cos(_gait_phase * 2.0)
	var bob_position := Vector3(
		gait_sin * 0.009,
		gait_double_cos * 0.007 - 0.0035,
		-gait_double * 0.004
	) * _movement_weight * bob_scale
	var bob_rotation := Vector3(
		gait_double_cos * deg_to_rad(0.65),
		gait_sin * deg_to_rad(0.75),
		-gait_sin * deg_to_rad(1.15)
	) * _movement_weight * bob_scale

	var idle_weight := 1.0 - _movement_weight
	var breath := sin(_elapsed_sec * 1.55)
	var breath_position := Vector3(0.0, breath * 0.0022, 0.0) * idle_weight
	var breath_rotation := Vector3(deg_to_rad(breath * 0.18), 0.0, deg_to_rad(breath * 0.10)) * idle_weight

	var look_position := Vector3(
		-_look_impulse.x * 0.00022,
		_look_impulse.y * 0.00016,
		0.0
	) * sway_scale
	var look_rotation := Vector3(
		_look_impulse.y * 0.00055,
		_look_impulse.x * 0.00062,
		_look_impulse.x * 0.00034
	) * sway_scale
	_look_impulse *= exp(-18.0 * delta)

	var inertia_position := Vector3(-acceleration.x * 0.00042, -acceleration.y * 0.00020, acceleration.z * 0.00032) * sway_scale
	var strafe_ratio := clampf(_smoothed_local_velocity.x / REFERENCE_RUN_SPEED, -1.0, 1.0)
	var inertia_rotation := Vector3(
		clampf(acceleration.z * 0.00035, -0.010, 0.010),
		clampf(-acceleration.x * 0.00042, -0.012, 0.012),
		deg_to_rad(-strafe_ratio * 1.6)
	) * sway_scale

	var sprint_position := Vector3(0.075, -0.090, 0.065) * _sprint_weight * sprint_scale
	var sprint_rotation := Vector3(deg_to_rad(7.0), deg_to_rad(-4.0), deg_to_rad(-11.0)) * _sprint_weight * sprint_scale
	var airborne_position := Vector3(0.0, clampf(_smoothed_local_velocity.y * 0.0024, -0.018, 0.018), 0.0) if not _grounded else Vector3.ZERO
	var airborne_rotation := Vector3(clampf(-_smoothed_local_velocity.y * 0.0018, -0.018, 0.018), 0.0, 0.0) if not _grounded else Vector3.ZERO

	var aim_damping := lerpf(1.0, 0.16, aim_weight)
	var action_damping := lerpf(1.0, 0.48, action_weight)
	var motion_scale := intensity * aim_damping * action_damping
	var target_position := (
		bob_position + breath_position + look_position + inertia_position
		+ sprint_position + airborne_position
	) * motion_scale
	var target_rotation := (
		bob_rotation + breath_rotation + look_rotation + inertia_rotation
		+ sprint_rotation + airborne_rotation
	) * motion_scale

	var mass := get_profile_mass()
	var response_hz := 4.0 / maxf(mass, 0.45)
	var position_step := _spring_vec3(_position, _position_velocity, target_position, response_hz, 0.92, delta)
	_position = position_step[0]
	_position_velocity = position_step[1]
	var rotation_step := _spring_vec3(_rotation, _rotation_velocity, target_rotation, response_hz * 0.92, 0.88, delta)
	_rotation = rotation_step[0]
	_rotation_velocity = rotation_step[1]

	var recoil_position_step := _spring_vec3(_recoil_position, _recoil_position_velocity, Vector3.ZERO, 5.4 / mass, 0.72, delta)
	_recoil_position = recoil_position_step[0]
	_recoil_position_velocity = recoil_position_step[1]
	var recoil_rotation_step := _spring_vec3(_recoil_rotation, _recoil_rotation_velocity, Vector3.ZERO, 5.0 / mass, 0.68, delta)
	_recoil_rotation = recoil_rotation_step[0]
	_recoil_rotation_velocity = recoil_rotation_step[1]
	var landing_position_step := _spring_vec3(_landing_position, _landing_position_velocity, Vector3.ZERO, 4.4, 0.76, delta)
	_landing_position = landing_position_step[0]
	_landing_position_velocity = landing_position_step[1]
	var landing_rotation_step := _spring_vec3(_landing_rotation, _landing_rotation_velocity, Vector3.ZERO, 4.1, 0.74, delta)
	_landing_rotation = landing_rotation_step[0]
	_landing_rotation_velocity = landing_rotation_step[1]
	var shield_position_step := _spring_vec3(_shield_impact_position, _shield_impact_position_velocity, Vector3.ZERO, 6.2, 0.62, delta)
	_shield_impact_position = shield_position_step[0]
	_shield_impact_position_velocity = shield_position_step[1]
	var shield_rotation_step := _spring_vec3(_shield_impact_rotation, _shield_impact_rotation_velocity, Vector3.ZERO, 5.8, 0.58, delta)
	_shield_impact_rotation = shield_rotation_step[0]
	_shield_impact_rotation_velocity = shield_rotation_step[1]


func _spring_vec3(
	value: Vector3,
	velocity: Vector3,
	target: Vector3,
	frequency_hz: float,
	damping_ratio: float,
	delta: float
) -> Array[Vector3]:
	var omega := TAU * maxf(frequency_hz, 0.01)
	var acceleration := (target - value) * (omega * omega) - velocity * (2.0 * damping_ratio * omega)
	velocity += acceleration * delta
	value += velocity * delta
	return [value, velocity]


func _damp(current: float, target: float, response: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-response * delta))
