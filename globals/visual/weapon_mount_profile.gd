class_name WeaponMountProfile
extends RefCounted

## Static whole-assembly corrections for equipment mounted on shared hand bones.
## These are presentation transforms only; Skeleton3D remains the animation
## authority and each weapon still has one runtime mesh instance.
const CROSSBOW_POSITION := Vector3(0.20, -1.10, -1.10)
## The source model's Blender Z axis is the body length axis; GLB import exposes
## it as local +Y, then CROSSBOW_ASSET_BASIS remaps it to mount +X. The stock
## points back toward the camera (+Z), while the rail/body front extends along
## -X toward the reticle. Keep this axis fixed and roll only around it.
const CROSSBOW_BODY_ROLL_DEGREES := 45.0
const CROSSBOW_MOUNT_BASIS_BASE := Basis(
	# Keep the body axis fixed: +X is the stock direction toward the player and
	# -X sends the rail toward the reticle. The y/z frame is the roll-zero frame
	# for the hand socket; CROSSBOW_BODY_ROLL_DEGREES is applied around +X.
	Vector3(0.72350395, 0.022456616, -0.689955),
	Vector3(-0.68778365, -0.062153592, -0.72325002),
	Vector3(-0.05912489, 0.99781397, -0.029522943)
)
## The final mount basis is calculated from the base frame so this one angle is
## the only manual tuning knob. The rotation is around local +X, which is the
## imported Blender-Z body axis after CROSSBOW_ASSET_BASIS is applied.
## Blender's Z axis is imported as Godot Y in this GLB. The raw mesh therefore
## arrives as X = limb span, Y = body length, Z = thickness. Remap the
## imported body +Y onto the mount's +X rear axis, with the limb span staying
## lateral and the thickness staying vertical.
const CROSSBOW_ASSET_BASIS := Basis(
	Vector3(0.0, 0.0, 1.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.0, 1.0, 0.0)
)
## First-person-only camera framing. The dedicated overlay mirrors the
## ViewModel's camera-relative transform. Keep this value scoped to presentation
## code; gameplay and shared character animation do not consume it.
const CROSSBOW_FIRST_PERSON_CAMERA_OFFSET := Vector3(0.0, -0.30, 0.0)
## Camera roll stays zero. The signed +45-degree local body-axis rotation above
## levels the gray limb assembly, so the body axis itself does not move.
const CROSSBOW_FIRST_PERSON_CAMERA_ROLL_DEGREES := 0.0


static func apply(equiped_object: Node3D, weapon_class: String) -> void:
	if equiped_object == null or weapon_class.to_lower() != "crossbow":
		return
	equiped_object.transform = Transform3D(crossbow_mount_basis(), CROSSBOW_POSITION)


static func crossbow_mount_basis() -> Basis:
	return CROSSBOW_MOUNT_BASIS_BASE * Basis(
		Vector3.RIGHT,
		deg_to_rad(CROSSBOW_BODY_ROLL_DEGREES)
	)


static func apply_asset_orientation(equiped_object: Node3D, weapon_class: String) -> void:
	if equiped_object == null or weapon_class.to_lower() != "crossbow":
		return
	equiped_object.transform = Transform3D(CROSSBOW_ASSET_BASIS, Vector3.ZERO)


static func first_person_camera_offset(weapon_class: String) -> Vector3:
	if weapon_class.to_lower() == "crossbow":
		return CROSSBOW_FIRST_PERSON_CAMERA_OFFSET
	return Vector3.ZERO


static func first_person_camera_roll_degrees(weapon_class: String) -> float:
	if weapon_class.to_lower() == "crossbow":
		return CROSSBOW_FIRST_PERSON_CAMERA_ROLL_DEGREES
	return 0.0


static func first_person_action_camera_offset(
	weapon_class: String,
	animation_name: String,
	progress: float
) -> Vector3:
	if weapon_class.to_lower() != "crossbow" or animation_name != "crossbow_reload":
		return Vector3.ZERO
	var t := clampf(progress, 0.0, 1.0)
	if t < 0.22:
		return Vector3(0.08, 0.08, 0.04) * (t / 0.22)
	if t < 0.72:
		return Vector3(0.14, 0.18, 0.08)
	return Vector3(0.14, 0.18, 0.08) * (1.0 - (t - 0.72) / 0.28)
