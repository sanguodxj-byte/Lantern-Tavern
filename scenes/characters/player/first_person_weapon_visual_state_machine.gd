class_name FirstPersonWeaponVisualStateMachine
extends RefCounted
## Local-only visual state machine for the first-person weapon.
##
## This class deliberately contains no combat, hitbox, damage, or input code.
## PlayerState remains the authority for when an attack starts and ends; this
## object only makes the hold/release visual phases explicit and testable.

signal state_changed(previous_state: int, next_state: int)
signal release_started(action_name: StringName, charge_ratio: float)

enum State {
	IDLE,
	HOLDING,
	RELEASING,
	RECOVERING,
}

const RECOVERY_DURATION_SEC := 0.10

var state: int = State.IDLE
var weapon_profile: StringName = &"one_hand"
var hold_ratio: float = 0.0
var charge_ratio_at_release: float = 0.0
var release_progress: float = 0.0
var release_action: StringName = &""
var release_duration_sec: float = 0.46

var _recovery_elapsed_sec: float = 0.0


func begin_hold(profile_id: StringName) -> bool:
	if state == State.RELEASING:
		return false
	if state == State.RECOVERING:
		reset()
	weapon_profile = profile_id
	hold_ratio = 0.0
	charge_ratio_at_release = 0.0
	release_progress = 0.0
	_set_state(State.HOLDING)
	return true


func set_hold_progress(progress: float) -> bool:
	if state != State.HOLDING:
		return false
	hold_ratio = clampf(progress, 0.0, 1.0)
	return true


func begin_release(action_name: StringName, duration_sec: float) -> bool:
	if state == State.RELEASING:
		return true
	if state == State.RECOVERING:
		reset()
	if state != State.HOLDING and state != State.IDLE:
		return false
	release_action = action_name
	release_duration_sec = maxf(duration_sec, 0.001)
	charge_ratio_at_release = hold_ratio
	release_progress = 0.0
	_set_state(State.RELEASING)
	release_started.emit(release_action, charge_ratio_at_release)
	return true


func set_release_progress(progress: float) -> bool:
	if state != State.RELEASING:
		return false
	release_progress = clampf(progress, 0.0, 1.0)
	return true


func finish_release() -> bool:
	if state != State.RELEASING:
		return false
	release_progress = 1.0
	_recovery_elapsed_sec = 0.0
	_set_state(State.RECOVERING)
	return true


func tick(delta: float) -> void:
	if state != State.RECOVERING:
		return
	_recovery_elapsed_sec += maxf(delta, 0.0)
	if _recovery_elapsed_sec >= RECOVERY_DURATION_SEC:
		reset()


func cancel() -> void:
	reset()


func reset() -> void:
	var previous := state
	state = State.IDLE
	hold_ratio = 0.0
	charge_ratio_at_release = 0.0
	release_progress = 0.0
	release_action = &""
	_recovery_elapsed_sec = 0.0
	if previous != State.IDLE:
		state_changed.emit(previous, State.IDLE)


func is_holding() -> bool:
	return state == State.HOLDING


func is_releasing() -> bool:
	return state == State.RELEASING


func is_recovering() -> bool:
	return state == State.RECOVERING


func state_name() -> StringName:
	match state:
		State.IDLE: return &"idle"
		State.HOLDING: return &"holding"
		State.RELEASING: return &"releasing"
		State.RECOVERING: return &"recovering"
		_: return &"unknown"


func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	var previous := state
	state = next_state
	state_changed.emit(previous, next_state)
