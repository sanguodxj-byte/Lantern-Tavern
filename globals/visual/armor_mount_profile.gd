class_name ArmorMountProfile
extends RefCounted

## Mount transforms for wearable armor on voxel_player_54px.
## Character faces world -Z. Body/helmet are authored Blender +Y front
## which becomes mesh -Z after glTF Y-up export; Head/Torso bones already
## carry a 180° Y rest, so an extra 180° Y is required for front to match face.
## Boots: mesh +Y = up, mesh +Z = toe (from Blender -Y) → world -Z forward.
## Piece meshes carry bulk per docs/armor_piece_size_table.md; keep scale < 1.3.

const HEAD_SCALE := 1.16
const BODY_SCALE := 1.12
const HANDS_SCALE := 1.18
const FEET_SCALE := 1.20
const BOOT_ANKLE_HEIGHT := 0.08

## Measured rest-pose eulers (deg) so mesh +Y→world up, mesh +Z→world -Z.
const FOOT_L_EULER_DEG := Vector3(-73.03, -145.01, -145.01)
const FOOT_R_EULER_DEG := Vector3(-73.03, 145.01, 145.01)


static func local_transform(slot_name: String, side: String = "") -> Transform3D:
	match slot_name:
		"head":
			# 180° Y: authored front (mesh -Z) → character face (world -Z).
			var basis := Basis.from_euler(Vector3(0.0, PI, 0.0)).scaled(Vector3.ONE * HEAD_SCALE)
			# Nest pot-helm on cranium (Head bone ~ neck base).
			return Transform3D(basis, Vector3(0.0, -0.02, 0.0))
		"body":
			var basis := Basis.from_euler(Vector3(0.0, PI, 0.0)).scaled(Vector3.ONE * BODY_SCALE)
			# Raise so cuirass top covers shoulder yoke (~y 1.28), not mid-belly.
			return Transform3D(basis, Vector3(0.0, 0.14, 0.0))
		"hands":
			# Forearm tube along mesh +Y; bone +Y points down the forearm.
			var basis := Basis.IDENTITY.scaled(Vector3.ONE * HANDS_SCALE)
			if side == "L":
				basis = basis.scaled(Vector3(-1.0, 1.0, 1.0))
			return Transform3D(basis, Vector3(0.0, 0.02, 0.0))
		"feet":
			var basis := _feet_basis(side).scaled(Vector3.ONE * FEET_SCALE)
			# Seat sole near ground: shift along mesh -Y (up axis) by ankle height.
			var pos: Vector3 = basis * Vector3(0.0, -BOOT_ANKLE_HEIGHT, 0.0)
			return Transform3D(basis, pos)
		_:
			return Transform3D.IDENTITY


static func _feet_basis(side: String) -> Basis:
	var euler_deg := FOOT_L_EULER_DEG if side == "L" else FOOT_R_EULER_DEG
	return Basis.from_euler(Vector3(
		deg_to_rad(euler_deg.x),
		deg_to_rad(euler_deg.y),
		deg_to_rad(euler_deg.z)
	))


static func min_oversized_scale() -> float:
	## Mesh envelopes already carry bulk; mount scale floor is mild.
	return 1.1
