extends SceneTree
## Orientation probe for armor mounts.

const RIG_PATH := "res://scenes/characters/player/player_visual_model.tscn"
const OUT := "res://reports/armor_sets_preview"
const HELMET := "res://assets/meshes/armor/armor_voxel_leather_helmet.glb"
const BODY := "res://assets/meshes/armor/armor_voxel_leather_armor.glb"
const BRACER := "res://assets/meshes/armor/armor_voxel_leather_bracers.glb"
const BOOT := "res://assets/meshes/armor/armor_voxel_leather_boots.glb"

var _vp: SubViewport
var _stage: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("needs non-headless")
		quit(4)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(900, 900)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	await process_frame
	_stage = Node3D.new()
	_vp.add_child(_stage)
	_env()

	var head_cands := [
		Vector3(0, 0, 0), Vector3(0, 180, 0), Vector3(0, 90, 0), Vector3(0, -90, 0),
		Vector3(90, 0, 0), Vector3(-90, 0, 0), Vector3(90, 180, 0), Vector3(-90, 180, 0),
		Vector3(0, 0, 90), Vector3(0, 0, -90), Vector3(180, 0, 0), Vector3(0, 180, 90),
	]
	var i := 0
	for e in head_cands:
		await _shot("Head", HELMET, e, 1.45, Vector3(0, 0.1, 0), "head_ori_%02d" % i)
		i += 1

	var body_cands := [
		Vector3(0, 0, 0), Vector3(0, 180, 0), Vector3(90, 0, 0), Vector3(-90, 0, 0),
		Vector3(90, 180, 0), Vector3(-90, 180, 0), Vector3(0, 90, 0), Vector3(180, 0, 0),
	]
	i = 0
	for e in body_cands:
		await _shot("Torso", BODY, e, 1.35, Vector3(0, 0.05, 0), "body_ori_%02d" % i)
		i += 1

	var hand_cands := [
		Vector3(0, 0, 0), Vector3(90, 0, 0), Vector3(-90, 0, 0), Vector3(0, 90, 0),
		Vector3(0, 0, 90), Vector3(90, 90, 0), Vector3(-90, 90, 0), Vector3(0, 180, 0),
	]
	i = 0
	for e in hand_cands:
		await _shot("LowerArm.R", BRACER, e, 1.4, Vector3(0, 0.05, 0), "hand_ori_%02d" % i)
		i += 1

	var foot_cands := [
		Vector3(0, 0, 0), Vector3(90, 0, 0), Vector3(-90, 0, 0), Vector3(0, 180, 0),
		Vector3(-90, 180, 0), Vector3(90, 180, 0), Vector3(0, 90, 0), Vector3(-90, 90, 0),
	]
	i = 0
	for e in foot_cands:
		await _shot("Foot.R", BOOT, e, 1.4, Vector3(0, 0.02, 0), "foot_ori_%02d" % i)
		i += 1

	print("orientation probe complete")
	quit(0)


func _shot(bone: String, glb: String, euler_deg: Vector3, scale: float, pos: Vector3, stem: String) -> void:
	for c in _stage.get_children():
		if String(c.name).begins_with("Probe"):
			c.queue_free()
	await process_frame

	var rig := (load(RIG_PATH) as PackedScene).instantiate() as Node3D
	rig.name = "ProbeChar"
	_stage.add_child(rig)
	var sk := _skel(rig)
	var attach := BoneAttachment3D.new()
	attach.bone_name = bone
	sk.add_child(attach)
	var mesh := (load(glb) as PackedScene).instantiate() as Node3D
	attach.add_child(mesh)
	var basis := Basis.from_euler(Vector3(deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)))
	basis = basis.scaled(Vector3.ONE * scale)
	mesh.transform = Transform3D(basis, pos)
	_layers(rig, 0xFFFFF)

	var cam := Camera3D.new()
	cam.name = "ProbeCam"
	cam.cull_mask = 0xFFFFF
	_stage.add_child(cam)
	cam.current = true
	var center := Vector3(0, 0.95, 0)
	cam.global_position = center + Vector3(1.2, 0.35, 1.6)
	cam.look_at(center, Vector3.UP)
	await process_frame
	await process_frame
	await process_frame
	var img := _vp.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, stem])
	print("Saved ", stem, " euler=", euler_deg)
	cam.queue_free()
	rig.queue_free()
	await process_frame


func _skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var f := _skel(c)
		if f != null:
			return f
	return null


func _env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.45, 0.5)
	e.ambient_light_energy = 0.7
	we.environment = e
	_stage.add_child(we)
	var l := DirectionalLight3D.new()
	l.light_energy = 1.5
	l.rotation_degrees = Vector3(-40, 30, 0)
	_stage.add_child(l)
	var o := OmniLight3D.new()
	o.light_energy = 2.0
	o.position = Vector3(-1.5, 2.2, 1.5)
	_stage.add_child(o)


func _layers(n: Node, layers: int) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).layers = layers
	for c in n.get_children():
		_layers(c, layers)
