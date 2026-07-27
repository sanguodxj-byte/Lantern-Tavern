class_name FirstPersonArmAnimator
extends RefCounted

## 第一人称手臂姿态层。
##
## 它绑定 ViewModel 自己的 Skeleton3D，只写六个手臂骨骼的 pose，不写玩家
## 第三人称 Skeleton3D。第一人称武器仍由 ViewModel 的 AnimationPlayer 驱动，
## 两者共享动作 ID 与归一化进度，因此视觉可以独立而不会改变战斗时序。

const ARM_BONES: Array[StringName] = [
	&"UpperArm.R", &"LowerArm.R", &"Hand.R",
	&"UpperArm.L", &"LowerArm.L", &"Hand.L",
]

var _skeleton: Skeleton3D
var _weapon_profile: StringName = &"unarmed"

func bind(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	reset_pose()

func set_weapon_profile(profile: StringName) -> void:
	_weapon_profile = profile

func sample_action(action_name: StringName, normalized_progress: float) -> void:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return
	var progress := clampf(normalized_progress, 0.0, 1.0)
	var pose := _pose_for(action_name, progress)
	for bone_name in ARM_BONES:
		var bone_index := _skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var rotation_degrees: Vector3 = pose.get(bone_name, Vector3.ZERO)
		_skeleton.set_bone_pose_rotation(
			bone_index,
			Basis.from_euler(Vector3(deg_to_rad(rotation_degrees.x), deg_to_rad(rotation_degrees.y), deg_to_rad(rotation_degrees.z))).get_rotation_quaternion()
		)
		_skeleton.set_bone_pose_position(bone_index, Vector3.ZERO)

func play_action(action_name: StringName) -> void:
	sample_action(action_name, 0.0)

func reset_pose() -> void:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return
	for bone_name in ARM_BONES:
		var bone_index := _skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		_skeleton.set_bone_pose_rotation(bone_index, Quaternion.IDENTITY)
		_skeleton.set_bone_pose_position(bone_index, Vector3.ZERO)

func _pose_for(action_name: StringName, progress: float) -> Dictionary:
	var action := String(action_name).trim_prefix("vm_")
	var hold := _hold_pose(_weapon_profile)
	if action.ends_with("_hold"):
		return _interpolate(hold, _charge_pose(_weapon_profile), progress)
	if action in ["idle", "equip"]:
		return hold
	if action == "melee_charge":
		return _interpolate(hold, _charge_pose(_weapon_profile), progress)
	if action == "bow_draw":
		return _interpolate(_hold_pose(&"bow"), _charge_pose(&"bow"), progress)
	if action.ends_with("_guard") or action in ["bow_aim", "crossbow_aim", "shield_block"]:
		return _guard_pose(_weapon_profile)
	if action == "crossbow_reload":
		return _interpolate(_hold_pose(&"crossbow"), _reload_pose(), progress)
	if action == "crossbow_fire":
		return _attack_cycle(_guard_pose(&"crossbow"), _attack_peak(&"crossbow"), progress)
	if action == "bow_release":
		return _attack_cycle(_guard_pose(&"bow"), _attack_peak(&"bow"), progress)
	if action.ends_with("_heavy_swing"):
		return _attack_cycle(_charge_pose(_weapon_profile), _heavy_peak(_weapon_profile), progress)
	if action in [
		"claw_swipe", "shortsword_attack", "shortsword_thrust", "sword_attack", "sword_slash",
		"stab_dagger", "dagger_attack", "greatsword_attack", "axe_attack", "warhammer_attack",
		"thrust_spear", "spear_attack", "staff_attack", "wand_cast", "grimoire_attack", "bash_shield",
	]:
		var attack_start := _guard_pose(_weapon_profile) if _weapon_profile in [&"bow", &"crossbow"] else _charge_pose(_weapon_profile)
		return _attack_cycle(attack_start, _attack_peak(_weapon_profile), progress)
	return hold

func _attack_cycle(start: Dictionary, peak: Dictionary, progress: float) -> Dictionary:
	if progress <= 0.5:
		return _interpolate(start, peak, progress * 2.0)
	return _interpolate(peak, start, (progress - 0.5) * 2.0)

func _interpolate(first: Dictionary, second: Dictionary, weight: float) -> Dictionary:
	var result := {}
	for bone_name in ARM_BONES:
		var a: Vector3 = first.get(bone_name, Vector3.ZERO)
		var b: Vector3 = second.get(bone_name, Vector3.ZERO)
		result[bone_name] = a.lerp(b, clampf(weight, 0.0, 1.0))
	return result

func _hold_pose(profile: StringName) -> Dictionary:
	match profile:
		&"unarmed": return _pose({"UpperArm.R": Vector3(-18, 0, 24), "LowerArm.R": Vector3(-28, 0, 0), "UpperArm.L": Vector3(-18, 0, -24), "LowerArm.L": Vector3(-28, 0, 0)})
		&"shortsword": return _pose({"UpperArm.R": Vector3(-28, 0, 28), "LowerArm.R": Vector3(-42, 0, 0), "Hand.R": Vector3(0, -18, 18)})
		&"sword": return _pose({"UpperArm.R": Vector3(-32, 0, 22), "LowerArm.R": Vector3(-46, 0, 0), "Hand.R": Vector3(0, -22, 22)})
		&"dagger": return _pose({"UpperArm.R": Vector3(-18, 8, 42), "LowerArm.R": Vector3(-24, 0, 0), "Hand.R": Vector3(0, -42, 8), "UpperArm.L": Vector3(-12, 0, -18)})
		&"greatsword": return _pose({"UpperArm.R": Vector3(-52, 0, 32), "LowerArm.R": Vector3(-34, 0, 0), "UpperArm.L": Vector3(-52, 0, -32), "LowerArm.L": Vector3(-34, 0, 0)})
		&"axe": return _pose({"UpperArm.R": Vector3(-58, -12, 42), "LowerArm.R": Vector3(-28, 0, 0), "UpperArm.L": Vector3(-44, 10, -34), "LowerArm.L": Vector3(-36, 0, 0)})
		&"warhammer": return _pose({"UpperArm.R": Vector3(-62, 8, 28), "LowerArm.R": Vector3(-26, 0, 0), "UpperArm.L": Vector3(-48, -10, -26), "LowerArm.L": Vector3(-38, 0, 0)})
		&"spear": return _pose({"UpperArm.R": Vector3(-30, -10, 15), "LowerArm.R": Vector3(-60, 0, 0), "UpperArm.L": Vector3(-24, 8, -18), "LowerArm.L": Vector3(-44, 0, 0)})
		&"bow": return _pose({"UpperArm.R": Vector3(-24, -8, 20), "LowerArm.R": Vector3(-44, 0, 0), "UpperArm.L": Vector3(-42, 8, -22), "LowerArm.L": Vector3(-54, 0, 0)})
		&"crossbow": return _pose({"UpperArm.R": Vector3(-30, 0, 25), "LowerArm.R": Vector3(-40, 0, 0), "UpperArm.L": Vector3(-48, 8, -20), "LowerArm.L": Vector3(-58, 0, 0)})
		&"staff": return _pose({"UpperArm.R": Vector3(-38, -6, 28), "LowerArm.R": Vector3(-54, 0, 0), "Hand.R": Vector3(0, -16, 16)})
		&"grimoire": return _pose({"UpperArm.R": Vector3(-22, 8, 34), "LowerArm.R": Vector3(-30, 0, 0), "UpperArm.L": Vector3(-34, -8, -30), "LowerArm.L": Vector3(-42, 0, 0)})
		&"shield": return _pose({"UpperArm.R": Vector3(-22, 0, 20), "LowerArm.R": Vector3(-30, 0, 0), "UpperArm.L": Vector3(-42, -18, -42), "LowerArm.L": Vector3(-58, 0, 0)})
	return {}

func _charge_pose(profile: StringName) -> Dictionary:
	match profile:
		&"unarmed": return _pose({"UpperArm.R": Vector3(-34, -8, 30), "LowerArm.R": Vector3(-38, 8, 0), "UpperArm.L": Vector3(-34, 8, -30), "LowerArm.L": Vector3(-38, -8, 0)})
		&"shortsword": return _pose({"UpperArm.R": Vector3(-38, -16, 36), "LowerArm.R": Vector3(-52, -8, 0), "Hand.R": Vector3(0, -26, 22)})
		&"sword": return _pose({"UpperArm.R": Vector3(-44, -4, 28), "LowerArm.R": Vector3(-54, -6, 0), "Hand.R": Vector3(0, -28, 28)})
		&"dagger": return _pose({"UpperArm.R": Vector3(-28, 12, 48), "LowerArm.R": Vector3(-30, -8, 0), "Hand.R": Vector3(0, -48, 14), "UpperArm.L": Vector3(-20, 0, -24)})
		&"greatsword": return _pose({"UpperArm.R": Vector3(-32, 0, 40), "LowerArm.R": Vector3(-42, 0, 0), "UpperArm.L": Vector3(-32, 0, -40), "LowerArm.L": Vector3(-42, 0, 0)})
		&"axe": return _pose({"UpperArm.R": Vector3(-36, -18, 48), "LowerArm.R": Vector3(-36, 0, 0), "UpperArm.L": Vector3(-32, 12, -40), "LowerArm.L": Vector3(-44, 0, 0)})
		&"warhammer": return _pose({"UpperArm.R": Vector3(-42, 12, 36), "LowerArm.R": Vector3(-34, 0, 0), "UpperArm.L": Vector3(-34, -10, -34), "LowerArm.L": Vector3(-46, 0, 0)})
		&"spear": return _pose({"UpperArm.R": Vector3(-36, -14, 18), "LowerArm.R": Vector3(-68, 0, 0), "UpperArm.L": Vector3(-30, 10, -22), "LowerArm.L": Vector3(-52, 0, 0)})
		&"bow": return _pose({"UpperArm.R": Vector3(-32, -10, 22), "LowerArm.R": Vector3(-54, 0, 0), "UpperArm.L": Vector3(-48, 8, -24), "LowerArm.L": Vector3(-62, 0, 0)})
		&"crossbow": return _pose({"UpperArm.R": Vector3(-36, 0, 28), "LowerArm.R": Vector3(-48, 0, 0), "UpperArm.L": Vector3(-52, 8, -22), "LowerArm.L": Vector3(-62, 0, 0)})
		&"staff": return _pose({"UpperArm.R": Vector3(-44, -8, 34), "LowerArm.R": Vector3(-62, 0, 0), "Hand.R": Vector3(0, -22, 20)})
		&"grimoire": return _pose({"UpperArm.R": Vector3(-30, 10, 40), "LowerArm.R": Vector3(-36, 0, 0), "UpperArm.L": Vector3(-40, -10, -34), "LowerArm.L": Vector3(-48, 0, 0)})
		&"shield": return _pose({"UpperArm.R": Vector3(-28, 0, 26), "LowerArm.R": Vector3(-36, 0, 0), "UpperArm.L": Vector3(-50, -20, -48), "LowerArm.L": Vector3(-64, 0, 0)})
	return _hold_pose(profile)

func _guard_pose(profile: StringName) -> Dictionary:
	var pose := _hold_pose(profile)
	match profile:
		&"unarmed": pose.merge(_pose({"UpperArm.R": Vector3(-48, -22, 38), "LowerArm.R": Vector3(-58, 18, 0), "UpperArm.L": Vector3(-48, 22, -38), "LowerArm.L": Vector3(-58, -18, 0)}))
		&"dagger": pose.merge(_pose({"UpperArm.R": Vector3(-26, 18, 52), "LowerArm.R": Vector3(-32, 0, 0)}))
		&"greatsword": pose.merge(_pose({"UpperArm.R": Vector3(-78, -8, 38), "LowerArm.R": Vector3(-48, 0, 0), "UpperArm.L": Vector3(-78, 8, -38), "LowerArm.L": Vector3(-48, 0, 0)}))
		&"axe": pose.merge(_pose({"UpperArm.R": Vector3(-86, -18, 52), "LowerArm.R": Vector3(-42, 0, 0), "UpperArm.L": Vector3(-64, 18, -48), "LowerArm.L": Vector3(-50, 0, 0)}))
		&"warhammer": pose.merge(_pose({"UpperArm.R": Vector3(-96, 4, 44), "LowerArm.R": Vector3(-34, 0, 0), "UpperArm.L": Vector3(-72, -4, -42), "LowerArm.L": Vector3(-52, 0, 0)}))
		&"spear": pose.merge(_pose({"UpperArm.R": Vector3(-46, -16, 10), "LowerArm.R": Vector3(-78, 0, 0), "UpperArm.L": Vector3(-42, 14, -14), "LowerArm.L": Vector3(-62, 0, 0)}))
		&"bow": pose.merge(_pose({"UpperArm.R": Vector3(-40, -12, 22), "LowerArm.R": Vector3(-62, 0, 0), "UpperArm.L": Vector3(-54, 10, -24), "LowerArm.L": Vector3(-68, 0, 0)}))
		&"crossbow": pose.merge(_pose({"UpperArm.R": Vector3(-36, 0, 28), "LowerArm.R": Vector3(-50, 0, 0), "UpperArm.L": Vector3(-54, 8, -22), "LowerArm.L": Vector3(-64, 0, 0)}))
		&"shield": pose.merge(_pose({"UpperArm.L": Vector3(-60, -24, -54), "LowerArm.L": Vector3(-78, 0, 0)}))
		_: pose.merge(_pose({"UpperArm.R": Vector3(-54, -12, 32), "LowerArm.R": Vector3(-64, 0, 0)}))
	return pose

func _attack_peak(profile: StringName) -> Dictionary:
	match profile:
		&"unarmed": return _pose({"UpperArm.R": Vector3(25, 10, -25), "LowerArm.R": Vector3(15, 0, 0), "UpperArm.L": Vector3(25, -10, 25), "LowerArm.L": Vector3(15, 0, 0)})
		&"shortsword": return _pose({"UpperArm.R": Vector3(-76, -90, 36), "LowerArm.R": Vector3(118, 142, -86), "Hand.R": Vector3(142, 0, -24)})
		&"sword": return _pose({"UpperArm.R": Vector3(-42, -18, 4), "LowerArm.R": Vector3(-50, 8, 0), "Hand.R": Vector3(0, -38, 30)})
		&"dagger": return _pose({"UpperArm.R": Vector3(18, 12, -22), "LowerArm.R": Vector3(10, 0, 0), "UpperArm.L": Vector3(-52, -8, -32), "LowerArm.L": Vector3(-42, 0, 0)})
		&"greatsword": return _pose({"UpperArm.R": Vector3(28, 0, -22), "LowerArm.R": Vector3(22, 0, 0), "UpperArm.L": Vector3(28, 0, 22), "LowerArm.L": Vector3(22, 0, 0)})
		&"axe": return _pose({"UpperArm.R": Vector3(42, -12, -34), "LowerArm.R": Vector3(34, 0, 0), "UpperArm.L": Vector3(42, 12, 34), "LowerArm.L": Vector3(34, 0, 0)})
		&"warhammer": return _pose({"UpperArm.R": Vector3(54, 8, -28), "LowerArm.R": Vector3(42, 0, 0), "UpperArm.L": Vector3(54, -8, 28), "LowerArm.L": Vector3(42, 0, 0)})
		&"spear": return _pose({"UpperArm.R": Vector3(-40, -15, 10), "LowerArm.R": Vector3(-80, 0, 0), "UpperArm.L": Vector3(-34, 12, -10), "LowerArm.L": Vector3(-62, 0, 0)})
		&"bow": return _pose({"UpperArm.R": Vector3(-18, -4, 10), "LowerArm.R": Vector3(-34, 0, 0), "UpperArm.L": Vector3(-30, 6, -12), "LowerArm.L": Vector3(-42, 0, 0)})
		&"crossbow": return _pose({"UpperArm.R": Vector3(-30, 0, 25), "LowerArm.R": Vector3(-40, 0, 0), "UpperArm.L": Vector3(-40, 8, -18), "LowerArm.L": Vector3(-50, 0, 0)})
		&"staff": return _pose({"UpperArm.R": Vector3(-60, -24, 42), "LowerArm.R": Vector3(-82, 0, 0), "Hand.R": Vector3(0, 18, -20)})
		&"grimoire": return _pose({"UpperArm.R": Vector3(-54, 18, 46), "LowerArm.R": Vector3(-62, 0, 0), "UpperArm.L": Vector3(-54, -18, -44), "LowerArm.L": Vector3(-68, 0, 0)})
		&"shield": return _pose({"UpperArm.L": Vector3(-10, -42, -12), "LowerArm.L": Vector3(-22, 0, 0)})
	return _hold_pose(profile)

func _heavy_peak(profile: StringName) -> Dictionary:
	var pose := _attack_peak(profile)
	match profile:
		&"greatsword": pose.merge(_pose({"UpperArm.R": Vector3(-112, -22, 56), "LowerArm.R": Vector3(-66, 0, 0), "UpperArm.L": Vector3(-106, 22, -56), "LowerArm.L": Vector3(-64, 0, 0), "Hand.R": Vector3(148, 0, -28), "Hand.L": Vector3(148, 0, 28)}))
		&"axe": pose.merge(_pose({"UpperArm.R": Vector3(-108, -38, 70), "LowerArm.R": Vector3(-52, 0, 0), "UpperArm.L": Vector3(-94, 28, -58), "LowerArm.L": Vector3(-62, 0, 0), "Hand.R": Vector3(132, -18, -34), "Hand.L": Vector3(132, 18, 34)}))
		&"warhammer": pose.merge(_pose({"UpperArm.R": Vector3(-126, 22, 56), "LowerArm.R": Vector3(-60, 0, 0), "UpperArm.L": Vector3(-118, -18, -52), "LowerArm.L": Vector3(-70, 0, 0), "Hand.R": Vector3(154, 18, -26), "Hand.L": Vector3(154, -18, 26)}))
		&"spear": pose.merge(_pose({"UpperArm.R": Vector3(-80, -28, 20), "LowerArm.R": Vector3(-92, 0, 0), "UpperArm.L": Vector3(-70, 20, -18), "LowerArm.L": Vector3(-82, 0, 0)}))
	return pose

func _reload_pose() -> Dictionary:
	return _pose({"UpperArm.R": Vector3(-30, 0, 25), "LowerArm.R": Vector3(-40, 0, 0), "UpperArm.L": Vector3(8, 14, -22), "LowerArm.L": Vector3(-12, 0, 0), "Hand.L": Vector3(0, 22, -12)})

func _pose(values: Dictionary) -> Dictionary:
	return values
