class_name FirstPersonAnimationLibrary
extends RefCounted

## 第一人称动作库。
##
## 这些动作只写入 ViewModel 的 ActionPivot / WeaponSocket，不触碰玩家
## 第三人称骨骼。命中时间、状态转换和退出信号仍由第三人称动作负责。

const STYLE_PROFILES: Array[StringName] = [
	&"unarmed", &"shortsword", &"sword", &"dagger", &"greatsword", &"axe",
	&"warhammer", &"spear", &"bow", &"crossbow", &"staff", &"grimoire", &"shield",
]

const REQUIRED_ACTIONS: Array[StringName] = [
	&"vm_idle", &"vm_equip", &"vm_melee_charge", &"vm_bow_draw",
	&"vm_crossbow_reload",
	&"vm_unarmed_hold", &"vm_unarmed_guard", &"vm_claw_swipe",
	&"vm_shortsword_hold", &"vm_shortsword_guard", &"vm_shortsword_thrust",
	&"vm_sword_hold", &"vm_sword_guard", &"vm_sword_slash",
	&"vm_dagger_hold", &"vm_dagger_guard", &"vm_stab_dagger",
	&"vm_greatsword_hold", &"vm_greatsword_guard", &"vm_greatsword_attack",
	&"vm_greatsword_heavy_swing",
	&"vm_axe_hold", &"vm_axe_guard", &"vm_axe_attack", &"vm_axe_heavy_swing",
	&"vm_warhammer_hold", &"vm_warhammer_guard", &"vm_warhammer_attack",
	&"vm_warhammer_heavy_swing",
	&"vm_spear_hold", &"vm_spear_guard", &"vm_thrust_spear", &"vm_spear_heavy_swing",
	&"vm_bow_hold", &"vm_bow_aim", &"vm_bow_release",
	&"vm_crossbow_hold", &"vm_crossbow_aim", &"vm_crossbow_fire",
	&"vm_staff_hold", &"vm_staff_guard", &"vm_staff_attack",
	&"vm_grimoire_hold", &"vm_grimoire_guard", &"vm_grimoire_attack",
	&"vm_shield_hold", &"vm_shield_block", &"vm_bash_shield",
	# 旧调用名保留为同一套第一人称资源的兼容别名。
	&"vm_shortsword_attack", &"vm_sword_attack", &"vm_slash_one_hand",
	&"vm_slash_heavy", &"vm_slash_default", &"vm_stab_default", &"vm_wand_cast",
]

static func build() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var neutral := _pose(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	_add_clip(library, &"vm_idle", 1.0, neutral, neutral, neutral, true)
	_add_clip(library, &"vm_equip", 0.32, _pose(Vector3(0.0, -0.06, 0.04), Vector3(-8.0, 0.0, 0.0), Vector3.ZERO), neutral, neutral, false)

	for profile in STYLE_PROFILES:
		_add_style_clips(library, profile)

	_add_clip(library, &"vm_melee_charge", 1.0, neutral, _pose(Vector3(0.05, 0.12, 0.04), Vector3(-8.0, -12.0, -24.0), Vector3.ZERO), _pose(Vector3(0.05, 0.12, 0.04), Vector3(-8.0, -12.0, -24.0), Vector3.ZERO), true)
	_add_clip(library, &"vm_bow_draw", 1.0, neutral, _pose(Vector3(-0.08, -0.04, 0.10), Vector3(-4.0, 8.0, -12.0), Vector3.ZERO), _pose(Vector3(-0.08, -0.04, 0.10), Vector3(-4.0, 8.0, -12.0), Vector3.ZERO), true)
	_add_clip(library, &"vm_crossbow_reload", 1.2, neutral, _pose(Vector3(0.04, -0.12, 0.05), Vector3(-10.0, 4.0, 8.0), Vector3.ZERO), neutral, false)

	# Legacy action names are aliases, never a second animation authority.
	_alias(library, &"vm_shortsword_attack", &"vm_shortsword_thrust")
	_alias(library, &"vm_sword_attack", &"vm_sword_slash")
	_alias(library, &"vm_slash_one_hand", &"vm_sword_slash", 0.46)
	_alias(library, &"vm_slash_heavy", &"vm_greatsword_attack", 0.78)
	_alias(library, &"vm_wand_cast", &"vm_staff_attack", 0.38)
	_alias(library, &"vm_slash_default", &"vm_sword_slash", 0.45)
	_alias(library, &"vm_stab_default", &"vm_dagger_hold", 0.40)
	return library


static func _add_style_clips(library: AnimationLibrary, profile: StringName) -> void:
	var hold := _style_pose(profile, &"hold")
	var charge := _style_pose(profile, &"charge")
	var guard := _style_pose(profile, &"guard")
	var attack := _style_pose(profile, &"attack")
	var attack_peak := _style_pose(profile, &"attack_peak")
	var heavy := _style_pose(profile, &"heavy")
	var hold_name := StringName("vm_%s_hold" % profile)
	var guard_name := StringName("vm_%s_guard" % profile)
	var attack_name := _attack_name(profile)
	if profile == &"bow":
		guard_name = &"vm_bow_aim"
	elif profile == &"crossbow":
		guard_name = &"vm_crossbow_aim"
	elif profile == &"shield":
		guard_name = &"vm_shield_block"
	var release_start := guard if profile in [&"bow", &"crossbow"] else charge
	_add_clip(library, hold_name, 1.0, hold, charge, charge, false)
	_add_clip(library, guard_name, 0.55, hold, guard, guard, true)
	_add_clip(library, attack_name, _attack_length(profile), release_start, attack_peak, hold, false)
	if profile in [&"greatsword", &"axe", &"warhammer", &"spear"]:
		_add_clip(library, StringName("vm_%s_heavy_swing" % profile), _attack_length(profile) + 0.25, charge, heavy, hold, false)


static func _attack_name(profile: StringName) -> StringName:
	match profile:
		&"unarmed": return &"vm_claw_swipe"
		&"shortsword": return &"vm_shortsword_thrust"
		&"sword": return &"vm_sword_slash"
		&"dagger": return &"vm_stab_dagger"
		&"greatsword": return &"vm_greatsword_attack"
		&"axe": return &"vm_axe_attack"
		&"warhammer": return &"vm_warhammer_attack"
		&"spear": return &"vm_thrust_spear"
		&"bow": return &"vm_bow_release"
		&"crossbow": return &"vm_crossbow_fire"
		&"staff": return &"vm_staff_attack"
		&"grimoire": return &"vm_grimoire_attack"
		&"shield": return &"vm_bash_shield"
	return &"vm_slash_default"


static func _attack_length(profile: StringName) -> float:
	match profile:
		&"dagger": return 0.30
		&"shortsword": return 0.42
		&"spear": return 0.50
		&"bow", &"crossbow": return 0.24
		&"greatsword", &"warhammer": return 0.72
		_: return 0.48


static func _style_pose(profile: StringName, phase: StringName) -> Dictionary:
	# 每个流派使用独立的握持、格挡和攻击空间；数值是相对第一人称
	# ActionPivot 的局部位姿，单位为米 / 度。
	match profile:
		&"unarmed":
			if phase == &"hold": return _pose(Vector3(0.0, 0.02, 0.0), Vector3(-4.0, 0.0, 0.0), Vector3.ZERO)
			if phase == &"charge": return _pose(Vector3(0.0, 0.08, -0.04), Vector3(-16.0, -8.0, 0.0), Vector3.ZERO)
			if phase == &"guard": return _pose(Vector3(0.0, 0.08, 0.02), Vector3(-12.0, 0.0, 0.0), Vector3.ZERO)
			if phase == &"attack_peak": return _pose(Vector3(0.0, 0.0, -0.18), Vector3(4.0, -10.0, 8.0), Vector3.ZERO)
			return _pose(Vector3(0.0, 0.04, 0.03), Vector3(-10.0, 0.0, -8.0), Vector3.ZERO)
		&"shortsword":
			if phase == &"hold": return _pose(Vector3(0.10, 0.02, -0.02), Vector3(-8.0, -12.0, -34.0), Vector3(0.0, 0.0, -10.0))
			if phase == &"charge": return _pose(Vector3(0.08, 0.10, 0.02), Vector3(-22.0, -28.0, -44.0), Vector3(0.0, 0.0, -16.0))
			if phase == &"guard": return _pose(Vector3(0.04, 0.10, -0.02), Vector3(-20.0, -8.0, -46.0), Vector3(0.0, 0.0, -16.0))
			if phase == &"attack_peak": return _pose(Vector3(0.10, 0.02, -0.32), Vector3(-2.0, -8.0, -34.0), Vector3(70.0, 0.0, 40.0))
			return _pose(Vector3(0.10, 0.02, -0.02), Vector3(-8.0, -12.0, -34.0), Vector3(0.0, 0.0, -10.0))
		&"sword":
			if phase == &"hold": return _pose(Vector3(0.08, 0.04, -0.02), Vector3(-12.0, -8.0, -42.0), Vector3(0.0, 0.0, -16.0))
			if phase == &"charge": return _pose(Vector3(0.02, 0.12, 0.02), Vector3(-30.0, -2.0, -56.0), Vector3(0.0, 0.0, -22.0))
			if phase == &"guard": return _pose(Vector3(0.00, 0.12, 0.02), Vector3(-24.0, 4.0, -58.0), Vector3(0.0, 0.0, -20.0))
			if phase == &"attack_peak": return _pose(Vector3(-0.30, -0.10, -0.08), Vector3(-12.0, 4.0, 18.0), Vector3(0.0, 0.0, -16.0))
			return _pose(Vector3(0.08, 0.04, -0.02), Vector3(-12.0, -8.0, -42.0), Vector3(0.0, 0.0, -16.0))
		&"dagger":
			if phase == &"hold": return _pose(Vector3(0.12, 0.02, -0.04), Vector3(-2.0, -18.0, -28.0), Vector3(0.0, 0.0, 18.0))
			if phase == &"charge": return _pose(Vector3(0.12, 0.08, 0.00), Vector3(-18.0, -24.0, -42.0), Vector3(0.0, 0.0, 24.0))
			if phase == &"guard": return _pose(Vector3(0.08, 0.08, -0.02), Vector3(-16.0, -28.0, -42.0), Vector3(0.0, 0.0, 24.0))
			if phase == &"attack_peak": return _pose(Vector3(0.08, 0.0, -0.26), Vector3(10.0, -22.0, -20.0), Vector3(0.0, 0.0, 20.0))
			return _pose(Vector3(0.12, 0.02, -0.04), Vector3(-2.0, -18.0, -28.0), Vector3(0.0, 0.0, 18.0))
		&"greatsword":
			if phase == &"hold": return _pose(Vector3(-0.02, 0.10, -0.02), Vector3(-16.0, -8.0, -46.0), Vector3(0.0, 0.0, -24.0))
			if phase == &"charge": return _pose(Vector3(-0.04, 0.18, 0.02), Vector3(12.0, 6.0, -38.0), Vector3(0.0, 0.0, -20.0))
			if phase == &"guard": return _pose(Vector3(-0.02, 0.16, 0.04), Vector3(-30.0, 0.0, -66.0), Vector3(0.0, 0.0, -30.0))
			if phase == &"heavy": return _pose(Vector3(0.04, 0.22, 0.02), Vector3(42.0, 10.0, 8.0), Vector3(0.0, 0.0, -18.0))
			if phase == &"attack_peak": return _pose(Vector3(-0.10, -0.06, -0.20), Vector3(-8.0, -2.0, 22.0), Vector3(0.0, 0.0, -22.0))
			return _pose(Vector3(-0.02, 0.10, -0.02), Vector3(-16.0, -8.0, -46.0), Vector3(0.0, 0.0, -24.0))
		&"axe":
			if phase == &"hold": return _pose(Vector3(-0.04, 0.08, -0.02), Vector3(-20.0, 8.0, -38.0), Vector3(0.0, 0.0, -30.0))
			if phase == &"charge": return _pose(Vector3(0.06, 0.16, 0.00), Vector3(8.0, -14.0, -4.0), Vector3(0.0, 0.0, -24.0))
			if phase == &"guard": return _pose(Vector3(-0.08, 0.18, 0.04), Vector3(-34.0, 12.0, -58.0), Vector3(0.0, 0.0, -34.0))
			if phase == &"heavy": return _pose(Vector3(0.18, 0.16, -0.04), Vector3(36.0, -24.0, 34.0), Vector3(0.0, 0.0, -28.0))
			if phase == &"attack_peak": return _pose(Vector3(-0.34, 0.00, -0.10), Vector3(-4.0, 8.0, 28.0), Vector3(0.0, 0.0, -28.0))
			return _pose(Vector3(-0.04, 0.08, -0.02), Vector3(-20.0, 8.0, -38.0), Vector3(0.0, 0.0, -30.0))
		&"warhammer":
			if phase == &"hold": return _pose(Vector3(-0.05, 0.06, -0.02), Vector3(-22.0, 12.0, -32.0), Vector3(0.0, 0.0, -34.0))
			if phase == &"charge": return _pose(Vector3(-0.02, 0.18, 0.02), Vector3(16.0, 10.0, -6.0), Vector3(0.0, 0.0, -28.0))
			if phase == &"guard": return _pose(Vector3(-0.10, 0.20, 0.06), Vector3(-38.0, 16.0, -52.0), Vector3(0.0, 0.0, -40.0))
			if phase == &"heavy": return _pose(Vector3(-0.04, 0.28, 0.00), Vector3(54.0, 16.0, 2.0), Vector3(0.0, 0.0, -30.0))
			if phase == &"attack_peak": return _pose(Vector3(-0.18, -0.02, -0.16), Vector3(-2.0, 12.0, 32.0), Vector3(0.0, 0.0, -32.0))
			return _pose(Vector3(-0.05, 0.06, -0.02), Vector3(-22.0, 12.0, -32.0), Vector3(0.0, 0.0, -34.0))
		&"spear":
			if phase == &"hold": return _pose(Vector3(0.04, 0.04, -0.04), Vector3(-10.0, -4.0, -52.0), Vector3(0.0, 0.0, -12.0))
			if phase == &"charge": return _pose(Vector3(0.02, 0.14, -0.10), Vector3(8.0, -2.0, -28.0), Vector3(0.0, 0.0, -8.0))
			if phase == &"guard": return _pose(Vector3(0.00, 0.12, -0.10), Vector3(-20.0, 0.0, -66.0), Vector3(0.0, 0.0, -16.0))
			if phase == &"heavy": return _pose(Vector3(0.02, 0.18, -0.12), Vector3(34.0, -4.0, -20.0), Vector3(0.0, 0.0, -10.0))
			if phase == &"attack_peak": return _pose(Vector3(0.02, 0.00, -0.42), Vector3(-8.0, 0.0, -52.0), Vector3(0.0, 0.0, -12.0))
			return _pose(Vector3(0.04, 0.04, -0.04), Vector3(-10.0, -4.0, -52.0), Vector3(0.0, 0.0, -12.0))
		&"bow":
			if phase == &"hold": return _pose(Vector3(0.16, -0.02, -0.02), Vector3(0.0, 0.0, -90.0), Vector3(0.0, 0.0, 0.0))
			if phase == &"charge": return _pose(Vector3(0.04, -0.02, -0.10), Vector3(-4.0, 0.0, -90.0), Vector3(0.0, 0.0, 0.0))
			if phase == &"guard": return _pose(Vector3(0.02, -0.02, -0.14), Vector3(-6.0, 0.0, -88.0), Vector3(0.0, 0.0, 0.0))
			if phase == &"attack_peak": return _pose(Vector3(-0.04, 0.02, -0.12), Vector3(-2.0, 0.0, -86.0), Vector3(0.0, 0.0, 0.0))
			return _pose(Vector3(0.16, -0.02, -0.02), Vector3(0.0, 0.0, -90.0), Vector3(0.0, 0.0, 0.0))
		&"crossbow":
			if phase == &"hold": return _pose(Vector3(0.14, -0.02, -0.04), Vector3(-6.0, 6.0, -90.0), Vector3(0.0, 0.0, 0.0))
			if phase == &"charge": return _pose(Vector3(0.04, -0.02, -0.12), Vector3(-10.0, 4.0, -90.0), Vector3(0.0, 0.0, 0.0))
			if phase == &"guard": return _pose(Vector3(0.00, -0.04, -0.18), Vector3(-12.0, 4.0, -90.0), Vector3(0.0, 0.0, 0.0))
			if phase == &"attack_peak": return _pose(Vector3(0.00, -0.02, -0.10), Vector3(-8.0, 6.0, -90.0), Vector3(0.0, 0.0, 0.0))
			return _pose(Vector3(0.14, -0.02, -0.04), Vector3(-6.0, 6.0, -90.0), Vector3(0.0, 0.0, 0.0))
		&"staff":
			if phase == &"hold": return _pose(Vector3(0.10, 0.03, -0.02), Vector3(-14.0, -4.0, -54.0), Vector3(0.0, 0.0, -14.0))
			if phase == &"charge": return _pose(Vector3(0.06, 0.12, -0.06), Vector3(-24.0, -2.0, -64.0), Vector3(0.0, 0.0, -18.0))
			if phase == &"guard": return _pose(Vector3(0.04, 0.12, 0.00), Vector3(-24.0, 0.0, -70.0), Vector3(0.0, 0.0, -18.0))
			if phase == &"attack_peak": return _pose(Vector3(0.08, 0.06, -0.20), Vector3(-34.0, -4.0, -48.0), Vector3(0.0, 0.0, -12.0))
			return _pose(Vector3(0.10, 0.03, -0.02), Vector3(-14.0, -4.0, -54.0), Vector3(0.0, 0.0, -14.0))
		&"grimoire":
			if phase == &"hold": return _pose(Vector3(0.14, 0.08, -0.04), Vector3(-4.0, -20.0, -86.0), Vector3(0.0, 0.0, 0.0))
			if phase == &"charge": return _pose(Vector3(0.08, 0.16, -0.08), Vector3(-12.0, -10.0, -94.0), Vector3(0.0, 0.0, 0.0))
			if phase == &"guard": return _pose(Vector3(0.04, 0.18, -0.02), Vector3(-18.0, -8.0, -100.0), Vector3(0.0, 0.0, 0.0))
			if phase == &"attack_peak": return _pose(Vector3(0.02, 0.02, -0.18), Vector3(-22.0, 10.0, -76.0), Vector3(0.0, 0.0, 0.0))
			return _pose(Vector3(0.14, 0.08, -0.04), Vector3(-4.0, -20.0, -86.0), Vector3(0.0, 0.0, 0.0))
		&"shield":
			if phase == &"hold": return _pose(Vector3(-0.20, -0.04, -0.12), Vector3(4.0, -18.0, 8.0), Vector3(0.0, 0.0, 12.0))
			if phase == &"charge": return _pose(Vector3(-0.24, 0.02, -0.20), Vector3(-4.0, -24.0, 12.0), Vector3(0.0, 0.0, 16.0))
			if phase == &"guard": return _pose(Vector3(-0.18, 0.02, -0.30), Vector3(-16.0, -24.0, 18.0), Vector3(0.0, 0.0, 16.0))
			if phase == &"attack_peak": return _pose(Vector3(-0.34, 0.00, -0.42), Vector3(-4.0, -30.0, 10.0), Vector3(0.0, 0.0, 18.0))
			return _pose(Vector3(-0.20, -0.04, -0.12), Vector3(4.0, -18.0, 8.0), Vector3(0.0, 0.0, 12.0))
	return _pose(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)


static func _add_clip(library: AnimationLibrary, action_name: StringName, length: float, start: Dictionary, peak: Dictionary, end: Dictionary, looped: bool = false) -> void:
	var animation := Animation.new()
	animation.resource_name = String(action_name)
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	# Keep a four-key layout (rest, wind-up, impact, recover). Existing visual
	# review tools inspect key 2 as the impact pose.
	_add_track(animation, NodePath("ActionPivot:position"), [start["p"], start["p"], peak["p"], end["p"]], [0.0, length * 0.25, length * 0.5, length])
	_add_track(animation, NodePath("ActionPivot:rotation"), [start["r"], start["r"], peak["r"], end["r"]], [0.0, length * 0.25, length * 0.5, length])
	var mount_rotation := deg_to_rad(_mount_rotation_z_for_action(action_name))
	var socket_values: Array = [start["s"], start["s"], peak["s"], end["s"]]
	for index in socket_values.size():
		socket_values[index] = socket_values[index] + Vector3(0.0, 0.0, mount_rotation)
	_add_track(animation, NodePath("ActionPivot/WeaponSocket:rotation"), socket_values, [0.0, length * 0.25, length * 0.5, length])
	library.add_animation(action_name, animation)


static func _mount_rotation_z_for_action(action_name: StringName) -> float:
	var action := String(action_name)
	if "shortsword" in action:
		return -135.0
	if "greatsword" in action:
		return -135.0
	if "sword" in action or "slash" in action:
		return -140.0
	if "dagger" in action or "stab" in action:
		return -118.0
	if "axe" in action:
		return -120.0
	if "warhammer" in action:
		return -112.0
	if "spear" in action or "thrust" in action:
		return -155.0
	if "crossbow" in action:
		return -90.0
	if "bow" in action:
		return -90.0
	if "staff" in action or "wand" in action:
		return -148.0
	if "grimoire" in action:
		return -96.0
	if "shield" in action or "bash" in action:
		return 10.0
	return 0.0


static func _add_track(animation: Animation, path: NodePath, values: Array, times: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, path)
	for index in values.size():
		animation.track_insert_key(track, float(times[index]), values[index])


static func _alias(library: AnimationLibrary, alias_name: StringName, source_name: StringName, length: float = -1.0) -> void:
	var source := library.get_animation(source_name)
	if source != null:
		var alias := source.duplicate() as Animation
		if length > 0.0:
			alias.length = length
		library.add_animation(alias_name, alias)


static func _pose(position: Vector3, rotation_degrees: Vector3, socket_rotation_degrees: Vector3) -> Dictionary:
	return {
		"p": position,
		"r": Vector3(deg_to_rad(rotation_degrees.x), deg_to_rad(rotation_degrees.y), deg_to_rad(rotation_degrees.z)),
		"s": Vector3(deg_to_rad(socket_rotation_degrees.x), deg_to_rad(socket_rotation_degrees.y), deg_to_rad(socket_rotation_degrees.z)),
	}
