extends SceneTree
## Wear-capture for complete armor sets on the player visual rig only.
## Avoids full Player controller scripts so --script mode does not need combat autoloads.

const RIG_PATH := "res://scenes/characters/player/player_visual_model.tscn"
const OUTPUT_DIR := "res://reports/armor_sets_preview"
const IMAGE_SIZE := Vector2i(1100, 1100)
const ArmorMount := preload("res://globals/visual/armor_mount_profile.gd")
const PX := 1.0 / 32.0

const SETS := {
	"leather": {
		"head": "res://assets/meshes/armor/armor_voxel_leather_helmet.glb",
		"body": "res://assets/meshes/armor/armor_voxel_leather_armor.glb",
		"hands": "res://assets/meshes/armor/armor_voxel_leather_bracers.glb",
		"feet": "res://assets/meshes/armor/armor_voxel_leather_boots.glb",
	},
	"iron": {
		"head": "res://assets/meshes/armor/armor_voxel_iron_helmet.glb",
		"body": "res://assets/meshes/armor/armor_voxel_chain_armor.glb",
		"hands": "res://assets/meshes/armor/armor_voxel_iron_bracers.glb",
		"feet": "res://assets/meshes/armor/armor_voxel_iron_boots.glb",
	},
}

var _viewport: SubViewport
var _stage: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Armor set wear capture requires a non-headless renderer.")
		quit(4)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	_viewport = SubViewport.new()
	_viewport.size = IMAGE_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	await process_frame

	_stage = Node3D.new()
	_viewport.add_child(_stage)
	_add_environment()
	_add_lights()

	for stem in SETS.keys():
		await _capture_set(String(stem), SETS[stem])

	print("Armor set wear capture complete")
	quit(0)


func _capture_set(stem: String, pieces: Dictionary) -> void:
	var rig_packed := load(RIG_PATH) as PackedScene
	if rig_packed == null:
		push_error("Missing player visual rig")
		quit(1)
		return
	var character := rig_packed.instantiate() as Node3D
	_stage.add_child(character)
	character.global_position = Vector3.ZERO
	await process_frame

	var skeleton := _find_skeleton(character)
	if skeleton == null:
		push_error("Skeleton3D not found on player visual")
		quit(1)
		return

	_mount(skeleton, "Head", pieces["head"], "head", "")
	_mount(skeleton, "Torso", pieces["body"], "body", "")
	_mount(skeleton, "LowerArm.L", pieces["hands"], "hands", "L")
	_mount(skeleton, "LowerArm.R", pieces["hands"], "hands", "R")
	_mount(skeleton, "Foot.L", pieces["feet"], "feet", "L")
	_mount(skeleton, "Foot.R", pieces["feet"], "feet", "R")
	_set_layers_recursive(character, 0xFFFFF)
	await process_frame
	await process_frame

	var cam := Camera3D.new()
	cam.cull_mask = 0xFFFFF
	_stage.add_child(cam)
	cam.current = true
	var center := Vector3(0.0, 0.95, 0.0)

	cam.global_position = center + Vector3(1.35, 0.45, -1.7)
	cam.look_at(center, Vector3.UP)
	await _save("%s_preview" % stem)

	cam.global_position = center + Vector3(0.0, 0.3, -2.35)
	cam.look_at(center, Vector3.UP)
	await _save("%s_front" % stem)

	cam.global_position = center + Vector3(2.35, 0.3, 0.0)
	cam.look_at(center, Vector3.UP)
	await _save("%s_side" % stem)

	cam.queue_free()
	character.queue_free()
	await process_frame


func _mount(skeleton: Skeleton3D, bone_name: String, glb_path: String, slot_name: String, side: String) -> void:
	var bone_idx := skeleton.find_bone(bone_name)
	if bone_idx < 0:
		push_warning("Bone missing: " + bone_name)
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = bone_name
	skeleton.add_child(attach)
	var packed := load(glb_path) as PackedScene
	if packed == null:
		push_warning("Missing glb " + glb_path)
		return
	var mesh_root := packed.instantiate() as Node3D
	attach.add_child(mesh_root)
	mesh_root.transform = _local_transform(slot_name, side)
	_set_layers_recursive(mesh_root, 0xFFFFF)


func _local_transform(slot_name: String, side: String) -> Transform3D:
	return ArmorMount.local_transform(slot_name, side)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _add_environment() -> void:
	var we := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.08, 0.10)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.4, 0.42, 0.46)
	environment.ambient_light_energy = 0.65
	we.environment = environment
	_stage.add_child(we)


func _add_lights() -> void:
	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	# Key from character front-right (faces world -Z).
	key.rotation_degrees = Vector3(-35.0, -140.0, 0.0)
	_stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_energy = 2.4
	fill.omni_range = 12.0
	fill.position = Vector3(1.6, 2.2, -1.8)
	_stage.add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_energy = 1.4
	rim.omni_range = 10.0
	rim.position = Vector3(-1.5, 1.8, 1.5)
	_stage.add_child(rim)


func _save(stem: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var tex := _viewport.get_texture()
	if tex == null:
		push_error("viewport texture null for " + stem)
		return
	var img := tex.get_image()
	if img == null:
		push_error("image null for " + stem)
		return
	var path := "%s/%s.png" % [OUTPUT_DIR, stem]
	var err := img.save_png(path)
	print("Saved ", path, " err=", err, " ", img.get_width(), "x", img.get_height())


func _set_layers_recursive(node: Node, layers: int) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers = layers
	for child in node.get_children():
		_set_layers_recursive(child, layers)
