extends GdUnitTestSuite
## 铁甲卫士地牢内投放预览测试
## 在真实程序化地牢中放置 voxel_ironclad_64x，截图验证地牢上下文效果

const IRONCLAD_64X_PATH := "res://assets/temp_test/voxel_ironclad_64x.glb"
const DUNGEON_SCENE := "res://scenes/expedition/procedural_dungeon.tscn"

func test_ironclad_in_dungeon() -> void:
	var dir := DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("reports/dungeon_preview")

	if not FileAccess.file_exists(IRONCLAD_64X_PATH):
		print("[跳过] 64x GLB 文件不存在: ", IRONCLAD_64X_PATH)
		return

	print("[开始] 加载程序化地牢...")

	var svp := SubViewport.new()
	svp.size = Vector2i(1024, 1024)
	svp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svp.transparent_bg = false
	add_child(svp)

	var dungeon_packed := load(DUNGEON_SCENE) as PackedScene
	if not dungeon_packed:
		print("[错误] 无法加载地牢场景")
		svp.queue_free()
		return

	var dungeon := dungeon_packed.instantiate() as Node3D
	svp.add_child(dungeon)

	for i in range(30):
		await get_tree().process_frame

	var spawn_pos := Vector3.ZERO
	if "player_spawn_pos" in dungeon:
		spawn_pos = dungeon.get("player_spawn_pos")
	print("[地牢] 玩家出生点: ", spawn_pos)

	var ironclad_packed := load(IRONCLAD_64X_PATH) as PackedScene
	if not ironclad_packed:
		print("[错误] 无法加载 ironclad GLB")
		dungeon.queue_free()
		svp.queue_free()
		return

	var ironclad := ironclad_packed.instantiate() as Node3D
	dungeon.add_child(ironclad)
	ironclad.global_position = spawn_pos + Vector3(0, 0.5, 0)
	ironclad.rotation_degrees = Vector3(0, 180, 0)

	var mesh_inst := _find_mesh_instance(ironclad)
	if mesh_inst:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.7
		mat.specular = 0.15
		mesh_inst.set_surface_override_material(0, mat)
		print("[材质] 顶点色材质已应用")

	var boss_light := OmniLight3D.new()
	boss_light.light_color = Color(1.0, 0.85, 0.6)
	boss_light.light_energy = 8.0
	boss_light.omni_range = 5.0
	boss_light.position = spawn_pos + Vector3(0, 2.0, 0)
	dungeon.add_child(boss_light)

	for i in range(10):
		await get_tree().process_frame
	RenderingServer.force_draw()

	var shots := {
		"overview": spawn_pos + Vector3(4.0, 5.0, 4.0),
		"front": spawn_pos + Vector3(0, 1.5, 3.5),
		"dramatic": spawn_pos + Vector3(-3.0, 3.0, 2.0),
	}

	for shot_name in shots:
		var cam_pos: Vector3 = shots[shot_name]
		var camera := Camera3D.new()
		camera.fov = 60.0
		dungeon.add_child(camera)
		camera.global_position = cam_pos
		camera.look_at(spawn_pos + Vector3(0, 0.5, 0), Vector3.UP)
		camera.current = true

		for i in range(8):
			await get_tree().process_frame
		RenderingServer.force_draw()

		var tex := svp.get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				var save_path := "res://reports/dungeon_preview/ironclad_dungeon_%s.png" % shot_name
				var err := img.save_png(save_path)
				if err == OK:
					print("  [截图成功] %s -> %s" % [shot_name, save_path])
				else:
					print("  [截图失败] 错误码=%d" % err)

		camera.queue_free()

	boss_light.queue_free()
	ironclad.queue_free()
	dungeon.queue_free()
	svp.queue_free()
	print("[完成] 地牢预览截图生成完毕！")

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found = _find_mesh_instance(child)
		if found:
			return found
	return null
