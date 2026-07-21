class_name ViewModelAnimator
extends RefCounted
## Owns first-person action sampling only.
## Combat code remains authoritative for timing and hit resolution.

const LIBRARY_PATH := "res://scenes/characters/player/view_model_animation_library.tres"
const LIBRARY_KEY := &""
const DEFAULT_ACTION := &"vm_slash_default"
const REQUIRED_ACTIONS: Array[StringName] = [
	&"vm_idle", &"vm_equip", &"vm_shortsword_hold", &"vm_shortsword_thrust", &"vm_sword_hold", &"vm_sword_slash",
	&"vm_slash_one_hand", &"vm_slash_heavy",
	&"vm_stab_dagger", &"vm_thrust_spear", &"vm_slash_default", &"vm_stab_default",
	&"vm_melee_charge", &"vm_bow_draw", &"vm_bow_release", &"vm_crossbow_fire",
	&"vm_crossbow_reload", &"vm_wand_cast",
]

var _action_pivot: Node3D
var _animation_player: AnimationPlayer
var _library: AnimationLibrary
var _warned_missing: Dictionary = {}
var _sampled_action: StringName = &""
var _weapon_profile: StringName = &"one_hand"


func _init(action_pivot: Node3D = null, animation_player: AnimationPlayer = null, library: AnimationLibrary = null) -> void:
	bind(action_pivot, animation_player, library)


func bind(action_pivot: Node3D, animation_player: AnimationPlayer, library: AnimationLibrary = null) -> void:
	_action_pivot = action_pivot
	_animation_player = animation_player
	_library = library if library != null else load(LIBRARY_PATH) as AnimationLibrary
	if _animation_player != null and _library != null and not _animation_player.has_animation_library(LIBRARY_KEY):
		_animation_player.add_animation_library(LIBRARY_KEY, _library)

func configure(animation_player: AnimationPlayer, action_pivot: Node3D) -> void:
	bind(action_pivot, animation_player)

func set_weapon_profile(profile_id: StringName) -> void:
	_weapon_profile = profile_id


func sample_action(action_name: StringName, normalized_progress: float) -> StringName:
	var resolved := resolve_action(action_name)
	if _animation_player == null or not _animation_player.has_animation(resolved):
		_warn_missing_once(resolved)
		return &""
	var animation := _animation_player.get_animation(resolved)
	if animation == null:
		_warn_missing_once(resolved)
		return &""
	if _sampled_action != resolved:
		_animation_player.play(resolved)
		_animation_player.pause()
		_sampled_action = resolved
	var clamped_progress := clampf(normalized_progress, 0.0, 1.0)
	_animation_player.seek(animation.length * clamped_progress, true)
	if clamped_progress >= 1.0:
		restore_action_pose()
	return resolved


func play_action(action_name: StringName, custom_speed: float = 1.0) -> StringName:
	var resolved := resolve_action(action_name)
	if _animation_player == null or not _animation_player.has_animation(resolved):
		_warn_missing_once(resolved)
		return &""
	_sampled_action = &""
	_animation_player.play(resolved, -1.0, custom_speed)
	return resolved


func stop_action(reset_pose: bool = true) -> void:
	if _animation_player != null:
		_animation_player.stop()
	_sampled_action = &""
	if reset_pose:
		restore_action_pose()


func resolve_action(action_name: StringName) -> StringName:
	if _animation_player != null and _animation_player.has_animation(action_name):
		return action_name
	if _animation_player != null and _animation_player.has_animation(DEFAULT_ACTION):
		return DEFAULT_ACTION
	return action_name


func restore_action_pose() -> void:
	if _action_pivot != null and is_instance_valid(_action_pivot):
		_action_pivot.transform = Transform3D.IDENTITY


func _warn_missing_once(action_name: StringName) -> void:
	if _warned_missing.has(action_name):
		return
	_warned_missing[action_name] = true
	push_warning("ViewModel animation is unavailable: %s" % action_name)
