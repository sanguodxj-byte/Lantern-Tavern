class_name CombatSlashAnimator

const ANIMATION_NAME := "slash"
const PLAYER_SPEED_SCALE := 1.12
const ENEMY_SPEED_SCALE := 0.95
const BLEND_SEC := 0.04
const PLAYER_HIT_START := 0.28
const PLAYER_HIT_END := 0.78
const ENEMY_HIT_START := 0.34
const ENEMY_HIT_END := 0.86
const ARC_ROLL_RAD := 0.42
const ARC_YAW_RAD := 0.24
const ARC_FORWARD_OFFSET := 0.08
const TRAIL_NAME := "SlashTrail"
const TRAIL_SIZE := Vector2(0.42, 1.2)
const TRAIL_MAX_ALPHA := 0.34

static func player_animation_name(weapon) -> String:
	if weapon == null:
		return "claw_swipe"
	var item_tag := String(weapon.item_tag) if "item_tag" in weapon else ""
	var weapon_class := String(weapon.weapon_class) if "weapon_class" in weapon else ""
	var skill_school := String(weapon.skill_school) if "skill_school" in weapon else ""
	var tags: Array = weapon.tags if "tags" in weapon else []
	if item_tag == "shield" or weapon_class == "shield":
		return "bash_shield"
	if tags.has("dagger"):
		return "slash_dagger"
	if tags.has("spear") or skill_school == "spear":
		return "thrust_spear"
	if weapon_class == "two_hand":
		return "slash_heavy"
	return "slash_one_hand"

static func enemy_animation_name(weapon) -> String:
	if weapon == null:
		return "claw_swipe"
	return player_animation_name(weapon)

static func play(animation_player: AnimationPlayer, animation_name: String, speed_scale: float) -> int:
	if animation_player == null:
		return 400
	var resolved_name := animation_name if animation_player.has_animation(animation_name) else ANIMATION_NAME
	if not animation_player.has_animation(resolved_name):
		return 400
	animation_player.play(resolved_name, BLEND_SEC, speed_scale)
	var anim := animation_player.get_animation(resolved_name)
	return int(maxf(anim.length / maxf(speed_scale, 0.01), 0.05) * 1000.0)

static func progress(start_msec: int, duration_msec: int) -> float:
	return clampf(float(Time.get_ticks_msec() - start_msec) / float(maxi(duration_msec, 1)), 0.0, 1.0)

static func is_player_hit_active(progress_value: float) -> bool:
	return progress_value >= PLAYER_HIT_START and progress_value <= PLAYER_HIT_END

static func is_enemy_hit_active(progress_value: float) -> bool:
	return progress_value >= ENEMY_HIT_START and progress_value <= ENEMY_HIT_END

static func apply_weapon_arc(placeholder: Node3D, base_transform: Transform3D, progress_value: float, side: float = 1.0) -> void:
	if placeholder == null:
		return
	var windup := clampf(progress_value / PLAYER_HIT_START, 0.0, 1.0)
	var strike := clampf((progress_value - PLAYER_HIT_START) / maxf(PLAYER_HIT_END - PLAYER_HIT_START, 0.01), 0.0, 1.0)
	var recover := clampf((progress_value - PLAYER_HIT_END) / maxf(1.0 - PLAYER_HIT_END, 0.01), 0.0, 1.0)
	var roll := lerpf(-ARC_ROLL_RAD, ARC_ROLL_RAD, strike) * side
	var yaw := lerpf(-ARC_YAW_RAD, ARC_YAW_RAD, strike) * side
	if progress_value < PLAYER_HIT_START:
		roll = lerpf(0.0, -ARC_ROLL_RAD, windup) * side
		yaw = lerpf(0.0, -ARC_YAW_RAD, windup) * side
	elif progress_value > PLAYER_HIT_END:
		roll = lerpf(ARC_ROLL_RAD, 0.0, recover) * side
		yaw = lerpf(ARC_YAW_RAD, 0.0, recover) * side
	var offset := Vector3(0.0, 0.0, -sin(progress_value * PI) * ARC_FORWARD_OFFSET)
	var arc := Transform3D(Basis.from_euler(Vector3(0.0, yaw, roll)), offset)
	placeholder.transform = base_transform * arc
	_update_trail(placeholder, progress_value, side)

static func restore_weapon_arc(placeholder: Node3D, base_transform: Transform3D) -> void:
	if placeholder != null:
		placeholder.transform = base_transform
		set_trail_visible(placeholder, false)

static func set_trail_visible(placeholder: Node3D, visible: bool) -> void:
	var trail := _get_trail(placeholder, false)
	if trail != null:
		trail.visible = visible

static func _update_trail(placeholder: Node3D, progress_value: float, side: float) -> void:
	var trail := _get_trail(placeholder, true)
	if trail == null:
		return
	var strike := clampf((progress_value - PLAYER_HIT_START) / maxf(PLAYER_HIT_END - PLAYER_HIT_START, 0.01), 0.0, 1.0)
	var alpha := TRAIL_MAX_ALPHA * sin(strike * PI)
	if alpha <= 0.01:
		trail.visible = false
		return
	trail.visible = true
	trail.position = Vector3(0.0, 0.0, -0.42)
	trail.rotation = Vector3(0.0, 0.0, side * lerpf(-0.9, 0.9, strike))
	var mat := trail.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color.a = alpha
		mat.emission_energy_multiplier = lerpf(0.15, 0.55, alpha / TRAIL_MAX_ALPHA)

static func _get_trail(placeholder: Node3D, create: bool) -> MeshInstance3D:
	if placeholder == null:
		return null
	var trail := placeholder.get_node_or_null(TRAIL_NAME) as MeshInstance3D
	if trail != null or not create:
		return trail
	trail = MeshInstance3D.new()
	trail.name = TRAIL_NAME
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.mesh = _make_trail_mesh()
	trail.material_override = _make_trail_material()
	trail.visible = false
	placeholder.add_child(trail)
	return trail

static func _make_trail_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = TRAIL_SIZE
	mesh.orientation = PlaneMesh.FACE_Z
	return mesh

static func _make_trail_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.78, 0.32, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.42, 0.12)
	mat.emission_energy_multiplier = 0.25
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
