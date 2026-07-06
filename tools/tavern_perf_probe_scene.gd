extends Node3D

const TAVERN_SCENE := preload("res://scenes/tavern/tavern.tscn")

var _frames := 0
var _warmup_frames := 30
var _sample_frames := 180
var _mode := "current"
var _total_delta := 0.0
var _worst_delta := 0.0
var _node_count := 0
var _mesh_count := 0
var _collision_count := 0
var _light_count := 0
var _particle_count := 0


func _ready() -> void:
	_mode = _get_arg_value("mode", _mode)
	get_window().size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var tavern := TAVERN_SCENE.instantiate() as Node3D
	add_child(tavern)
	await get_tree().process_frame
	_apply_probe_mode(tavern)
	await get_tree().process_frame
	_count_scene(tavern)

	var camera := Camera3D.new()
	camera.name = "PerfProbeCamera"
	camera.position = Vector3(3.5, 9.5, 7.5)
	add_child(camera)
	camera.look_at(Vector3(3.5, 0.8, -2.2), Vector3.UP)
	camera.make_current()


func _process(delta: float) -> void:
	_frames += 1
	if _frames <= _warmup_frames:
		return
	_total_delta += delta
	_worst_delta = maxf(_worst_delta, delta)
	if _frames >= _warmup_frames + _sample_frames:
		var avg_ms := (_total_delta / float(_sample_frames)) * 1000.0
		var worst_ms := _worst_delta * 1000.0
		var fps := 1000.0 / avg_ms
		var object_count := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		var primitive_count := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		print("TAVERN_PERF mode=%s avg_ms=%.3f worst_ms=%.3f fps=%.1f nodes=%d meshes=%d collisions=%d lights=%d particles=%d render_objects=%d primitives=%d" % [
			_mode,
			avg_ms,
			worst_ms,
			fps,
			_node_count,
			_mesh_count,
			_collision_count,
			_light_count,
			_particle_count,
			object_count,
			primitive_count,
		])
		get_tree().quit(0)


func _count_scene(node: Node) -> void:
	_node_count += 1
	if node is MeshInstance3D:
		_mesh_count += 1
	if node is CollisionShape3D:
		_collision_count += 1
	if node is Light3D:
		_light_count += 1
	if node is GPUParticles3D or node is CPUParticles3D:
		_particle_count += 1
	for child in node.get_children():
		_count_scene(child)


func _get_arg_value(key: String, default_value: String) -> String:
	var prefix := "--%s=" % key
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	for arg in OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return default_value


func _apply_probe_mode(root: Node) -> void:
	match _mode:
		"simple_materials":
			_replace_shader_materials(root)
		"no_dynamic_fire":
			_disable_dynamic_fire(root)
		"no_shadows":
			_disable_shadows(root)
		"structure_only":
			_hide_non_structure(root)
		"props_only":
			_hide_structure(root)
		_:
			pass


func _replace_shader_materials(root: Node) -> void:
	var replacement := StandardMaterial3D.new()
	replacement.albedo_color = Color(0.65, 0.62, 0.55)
	replacement.roughness = 0.9
	for node in _walk(root):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		if mesh.material_override is ShaderMaterial:
			mesh.material_override = replacement
		for surface_index in mesh.get_surface_override_material_count():
			if mesh.get_surface_override_material(surface_index) is ShaderMaterial:
				mesh.set_surface_override_material(surface_index, replacement)


func _disable_dynamic_fire(root: Node) -> void:
	for node in _walk(root):
		if node is GPUParticles3D:
			(node as GPUParticles3D).emitting = false
			(node as GPUParticles3D).visible = false
		elif node is CPUParticles3D:
			(node as CPUParticles3D).emitting = false
			(node as CPUParticles3D).visible = false
		elif node is OmniLight3D or node is SpotLight3D:
			(node as Light3D).visible = false
		elif node is AudioStreamPlayer3D:
			(node as AudioStreamPlayer3D).stop()


func _disable_shadows(root: Node) -> void:
	for node in _walk(root):
		var light := node as Light3D
		if light != null:
			light.shadow_enabled = false


func _hide_non_structure(root: Node) -> void:
	for node in _walk(root):
		if node is Node3D and not _is_node_under_name(node, "Structure"):
			if node != root:
				(node as Node3D).visible = false


func _hide_structure(root: Node) -> void:
	for node in _walk(root):
		if node is Node3D and _is_node_under_name(node, "Structure"):
			(node as Node3D).visible = false


func _is_node_under_name(node: Node, ancestor_name: String) -> bool:
	var current := node
	while current != null:
		if current.name == ancestor_name:
			return true
		current = current.get_parent()
	return false


func _walk(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	var index := 0
	while index < nodes.size():
		for child in nodes[index].get_children():
			nodes.append(child)
		index += 1
	return nodes
