extends SceneTree

const ENEMY_SCENES := [
	"res://scenes/characters/enemies/goblin.tscn",
	"res://scenes/characters/enemies/kobold.tscn",
	"res://scenes/characters/enemies/skeleton.tscn",
	"res://scenes/characters/enemies/slime.tscn",
	"res://scenes/characters/enemies/spider.tscn",
	"res://scenes/characters/enemies/troll.tscn",
	"res://scenes/characters/enemies/dragon.tscn",
	"res://scenes/characters/enemies/rock_golem.tscn",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for scene_path in ENEMY_SCENES:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			print("ANIM_PROBE missing_scene=%s" % scene_path)
			continue
		var enemy := packed.instantiate()
		root.add_child(enemy)
		await process_frame
		var animation_player := enemy.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if animation_player == null:
			print("ANIM_PROBE missing_player=%s" % scene_path)
			enemy.free()
			continue
		for animation_name in animation_player.get_animation_list():
			var animation := animation_player.get_animation(animation_name)
			for track_index in animation.get_track_count():
				for key_index in animation.track_get_key_count(track_index):
					_scan_value("%s animation=%s track=%d key=%d path=%s" % [
						scene_path, String(animation_name), track_index, key_index,
						String(animation.track_get_path(track_index)),
					], animation.track_get_key_value(track_index, key_index))
		animation_player.play("run")
		for _i in 10:
			animation_player.advance(0.1)
			await process_frame
		_scan_tree(scene_path, enemy)
		enemy.free()
	quit()

func _scan_value(label: String, value: Variant) -> void:
	if value is Vector3 and not _is_finite_vector(value):
		print("ANIM_PROBE nonfinite_vector %s value=%s" % [label, str(value)])
	elif value is Quaternion and not _is_finite_quaternion(value):
		print("ANIM_PROBE nonfinite_quaternion %s value=%s" % [label, str(value)])
	elif value is Basis and not _is_finite_basis(value):
		print("ANIM_PROBE nonfinite_basis %s value=%s" % [label, str(value)])
	elif value is Transform3D and (not _is_finite_basis(value.basis) or not _is_finite_vector(value.origin)):
		print("ANIM_PROBE nonfinite_transform %s value=%s" % [label, str(value)])

func _scan_tree(scene_path: String, node: Node) -> void:
	if node is Node3D:
		var node_3d := node as Node3D
		if not _is_finite_vector(node_3d.global_position) or not _is_finite_basis(node_3d.global_basis):
			print("ANIM_PROBE nonfinite_node scene=%s path=%s pos=%s basis=%s" % [
				scene_path, String(node_3d.get_path()), str(node_3d.global_position), str(node_3d.global_basis),
			])
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		for bone_index in skeleton.get_bone_count():
			var rotation := skeleton.get_bone_pose_rotation(bone_index)
			if not _is_finite_quaternion(rotation):
				print("ANIM_PROBE nonfinite_bone scene=%s path=%s bone=%s rotation=%s" % [
					scene_path, String(skeleton.get_path()), skeleton.get_bone_name(bone_index), str(rotation),
				])
	for child in node.get_children():
		_scan_tree(scene_path, child)

func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func _is_finite_quaternion(value: Quaternion) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z) and is_finite(value.w)

func _is_finite_basis(value: Basis) -> bool:
	return _is_finite_vector(value.x) and _is_finite_vector(value.y) and _is_finite_vector(value.z)
