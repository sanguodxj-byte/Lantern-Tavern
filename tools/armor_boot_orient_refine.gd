extends SceneTree
const RIG := "res://scenes/characters/player/player_visual_model.tscn"
const OUT := "res://reports/armor_sets_preview"
const BOOT := "res://assets/meshes/armor/armor_voxel_leather_boots.glb"
const HELMET := "res://assets/meshes/armor/armor_voxel_leather_helmet.glb"
const BODY := "res://assets/meshes/armor/armor_voxel_leather_armor.glb"
const BRACER := "res://assets/meshes/armor/armor_voxel_leather_bracers.glb"
var _vp: SubViewport
var _stage: Node3D
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(4)
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(1000, 1000)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	await process_frame
	_stage = Node3D.new()
	_vp.add_child(_stage)
	_lights()
	var cands: Array[Vector3] = [
		Vector3(-90, 0, 0), Vector3(-90, 180, 0), Vector3(90, 0, 0), Vector3(0, 0, 0),
		Vector3(-90, 90, 0), Vector3(-90, -90, 0), Vector3(-60, 0, 0), Vector3(-120, 0, 0),
		Vector3(-90, 0, 90), Vector3(-90, 0, -90), Vector3(0, 90, 0), Vector3(-90, 45, 0),
	]
	for i in range(cands.size()):
		await _cap(cands[i], "bootfix_%02d" % i)
	print("boot refine done")
	quit(0)
func _cap(e: Vector3, stem: String) -> void:
	for c in _stage.get_children():
		if String(c.name).begins_with("P"):
			c.queue_free()
	await process_frame
	var rig: Node3D = (load(RIG) as PackedScene).instantiate() as Node3D
	rig.name = "P"
	_stage.add_child(rig)
	var sk: Skeleton3D = _sk(rig)
	_m(sk, "Head", HELMET, Vector3.ZERO, 1.55, Vector3(0, 0.1, 0), "")
	_m(sk, "Torso", BODY, Vector3.ZERO, 1.45, Vector3(0, 0.05, 0), "")
	_m(sk, "LowerArm.L", BRACER, Vector3.ZERO, 1.5, Vector3(0, 0.04, 0), "L")
	_m(sk, "LowerArm.R", BRACER, Vector3.ZERO, 1.5, Vector3(0, 0.04, 0), "R")
	_m(sk, "Foot.L", BOOT, e, 1.55, Vector3(0, 0.05, 0), "L")
	_m(sk, "Foot.R", BOOT, e, 1.55, Vector3(0, 0.05, 0), "R")
	_layers(rig, 0xFFFFF)
	var cam := Camera3D.new()
	cam.name = "PCam"
	cam.cull_mask = 0xFFFFF
	_stage.add_child(cam)
	cam.current = true
	var center := Vector3(0, 0.95, 0)
	cam.global_position = center + Vector3(0, 0.2, 2.4)
	cam.look_at(center, Vector3.UP)
	await process_frame
	await process_frame
	await process_frame
	_vp.get_texture().get_image().save_png("%s/%s_front.png" % [OUT, stem])
	cam.global_position = center + Vector3(2.4, 0.2, 0)
	cam.look_at(center, Vector3.UP)
	await process_frame
	await process_frame
	await process_frame
	_vp.get_texture().get_image().save_png("%s/%s_side.png" % [OUT, stem])
	print("Saved ", stem, " ", e)
	cam.queue_free()
	rig.queue_free()
	await process_frame
func _m(sk: Skeleton3D, bone: String, glb: String, euler: Vector3, sc: float, pos: Vector3, side: String) -> void:
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	sk.add_child(a)
	var m: Node3D = (load(glb) as PackedScene).instantiate() as Node3D
	a.add_child(m)
	var b := Basis.from_euler(Vector3(deg_to_rad(euler.x), deg_to_rad(euler.y), deg_to_rad(euler.z)))
	b = b.scaled(Vector3.ONE * sc)
	if side == "L":
		b = b.scaled(Vector3(-1, 1, 1))
	m.transform = Transform3D(b, pos)
func _sk(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var f: Skeleton3D = _sk(c)
		if f != null:
			return f
	return null
func _lights() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.7
	we.environment = e
	_stage.add_child(we)
	var l := DirectionalLight3D.new()
	l.light_energy = 1.5
	l.rotation_degrees = Vector3(-40, 35, 0)
	_stage.add_child(l)
	var o := OmniLight3D.new()
	o.light_energy = 2.0
	o.position = Vector3(-1.5, 2.0, 1.5)
	_stage.add_child(o)
func _layers(n: Node, layers: int) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).layers = layers
	for c in n.get_children():
		_layers(c, layers)
