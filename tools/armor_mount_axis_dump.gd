extends SceneTree
## Dump bone axes + mesh AABBs for armor mount calibration (headless-safe).

const RIG := "res://scenes/characters/player/player_visual_model.tscn"
const PIECES := {
	"head": "res://assets/meshes/armor/armor_voxel_leather_helmet.glb",
	"body": "res://assets/meshes/armor/armor_voxel_leather_armor.glb",
	"hands": "res://assets/meshes/armor/armor_voxel_leather_bracers.glb",
	"feet": "res://assets/meshes/armor/armor_voxel_leather_boots.glb",
}
const BONES := ["Head", "Torso", "LowerArm.L", "LowerArm.R", "Foot.L", "Foot.R", "LowerLeg.L", "LowerLeg.R", "Hips", "UpperLeg.L", "UpperLeg.R"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rig := (load(RIG) as PackedScene).instantiate() as Node3D
	root.add_child(rig)
	await process_frame
	await process_frame
	var sk := _skel(rig)
	if sk == null:
		push_error("no skeleton")
		quit(1)
		return
	print("=== BONE AXES (global basis columns = local X/Y/Z in world) ===")
	for bone_name in BONES:
		var idx := sk.find_bone(bone_name)
		if idx < 0:
			print("MISSING ", bone_name)
			continue
		var gt := sk.global_transform * sk.get_bone_global_pose(idx)
		var b := gt.basis.orthonormalized()
		var o := gt.origin
		print("%s origin=(%.3f, %.3f, %.3f)" % [bone_name, o.x, o.y, o.z])
		print("  X= mon(%.3f, %.3f, %.3f)  Y=(%.3f, %.3f, %.3f)  Z=(%.3f, %.3f, %.3f)" % [
			b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z
		])
		print("  | lenY=%.3f  up·Y=%.3f  forward_guess=-Z·world_fwd?" % [b.y.length(), b.y.dot(Vector3.UP)])
	print("=== MESH LOCAL AABB ===")
	for slot in PIECES.keys():
		var inst := (load(String(PIECES[slot])) as PackedScene).instantiate() as Node3D
		root.add_child(inst)
		await process_frame
		var aabb := _aabb(inst)
		print("%s aabb pos=(%.3f,%.3f,%.3f) size=(%.3f,%.3f,%.3f) end=(%.3f,%.3f,%.3f)" % [
			slot, aabb.position.x, aabb.position.y, aabb.position.z,
			aabb.size.x, aabb.size.y, aabb.size.z,
			aabb.end.x, aabb.end.y, aabb.end.z
		])
		inst.queue_free()
	# Suggest feet rotation: map mesh +Y(up) -> world up in bone space, mesh +Z(toe) -> bone +Y
	print("=== FEET SUGGESTION ===")
	for bn in ["Foot.L", "Foot.R"]:
		var idx2 := sk.find_bone(bn)
		if idx2 < 0:
			continue
		var gt2 := sk.global_transform * sk.get_bone_global_pose(idx2)
		var bone_b := gt2.basis.orthonormalized()
		# desired: mesh_up(+Y) -> world UP expressed in bone local
		# desired: mesh_toe(+Z) -> bone +Y (along bone)
		var up_in_bone: Vector3 = bone_b.transposed() * Vector3.UP
		var toe_in_bone := Vector3(0, 1, 0) # bone +Y
		print("%s up_in_bone=(%.3f, %.3f, %.3f) toe_target=bone+Y" % [bn, up_in_bone.x, up_in_bone.y, up_in_bone.z])
		# Build basis with columns = where mesh axes go in bone space
		# mesh X -> orthogonal, mesh Y -> up_in_bone, mesh Z -> toe projected
		var mesh_y := up_in_bone.normalized()
		var mesh_z := toe_in_bone.normalized()
		# re-orthogonalize
		mesh_z = (mesh_z - mesh_y * mesh_y.dot(mesh_z)).normalized()
		if mesh_z.length() < 0.1:
			mesh_z = Vector3(1, 0, 0) if abs(mesh_y.dot(Vector3(1,0,0))) < 0.9 else Vector3(0,0,1)
			mesh_z = (mesh_z - mesh_y * mesh_y.dot(mesh_z)).normalized()
		var mesh_x := mesh_y.cross(mesh_z).normalized()
		mesh_z = mesh_x.cross(mesh_y).normalized()
		var target := Basis(mesh_x, mesh_y, mesh_z)
		var e := target.get_euler()
		print("  target_euler_deg=(%.1f, %.1f, %.1f)" % [rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)])
		# ankle seat: boot origin near sole; shift so mid-ankle volume at bone origin
		# boot aabb roughly y 0..0.25, want ankle ~ y 0.12 at origin after rot
	print("done")
	quit(0)

func _skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var f := _skel(c)
		if f != null:
			return f
	return null

func _aabb(n: Node) -> AABB:
	var result := AABB()
	var first := true
	if n is VisualInstance3D:
		var la: AABB = (n as VisualInstance3D).get_aabb()
		var gt: Transform3D = (n as Node3D).global_transform
		# convert 8 corners
		for i in range(8):
			var corner := gt * la.get_endpoint(i)
			if first:
				result = AABB(corner, Vector3.ZERO)
				first = false
			else:
				result = result.expand(corner)
	for c in n.get_children():
		var child_aabb := _aabb(c)
		if child_aabb.size.length() > 0.0 or child_aabb.position != Vector3.ZERO:
			if first:
				result = child_aabb
				first = false
			else:
				result = result.merge(child_aabb)
	return result
