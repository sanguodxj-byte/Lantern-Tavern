extends GdUnitTestSuite

## 教程场景截图测试 - 使用SubViewport在headless模式下渲染截图

var intro_instance: Node3D = null

func before_test():
	var packed := load("res://scenes/intro/new_game_intro.tscn") as PackedScene
	assert_bool(packed != null).is_true()
	intro_instance = packed.instantiate() as Node3D
	assert_bool(intro_instance != null).is_true()
	add_child(intro_instance)
	await get_tree().process_frame
	await get_tree().process_frame

func after_test():
	if intro_instance and is_instance_valid(intro_instance):
		intro_instance.queue_free()

func test_glb_assets_load_with_meshes() -> void:
	var glb_paths := [
		"res://assets/models/environment/environment_tutorial_cart_wreck.glb",
		"res://assets/models/environment/environment_tutorial_forest_cluster.glb",
		"res://assets/models/environment/environment_tutorial_entrance_ruins.glb",
		"res://assets/models/environment/environment_tutorial_road_blocker.glb"
	]
	for path in glb_paths:
		var packed := load(path) as PackedScene
		print("[GLB] 检查: " + path)
		assert_bool(packed != null).is_true()
		var inst := packed.instantiate() as Node3D
		assert_bool(inst != null).is_true()
		var mesh_count := _count_meshes(inst)
		print("[GLB] %s -> Mesh数量=%d" % [path, mesh_count])
		assert_int(mesh_count).is_greater(0)
		inst.queue_free()

func test_scene_tree_has_visual_content() -> void:
	var set_dressing := intro_instance.get_node_or_null("SetDressing")
	assert_bool(set_dressing != null).is_true()

	var mesh_count := _count_meshes(set_dressing)
	print("[场景] SetDressing下Mesh数量=%d" % mesh_count)
	assert_int(mesh_count).is_greater(0)

	print("[场景树]:")
	_print_tree(intro_instance, 0)

func test_capture_screenshot_via_subviewport() -> void:
	# 在headless模式下，主视口用dummy渲染器无法截图
	# 使用独立的SubViewport + RenderingServer来渲染
	var svp := SubViewport.new()
	svp.size = Vector2i(1920, 1080)
	svp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svp.transparent_bg = false
	add_child(svp)

	# 将教程场景移到SubViewport中
	remove_child(intro_instance)
	svp.add_child(intro_instance)

	# 创建相机
	var camera := Camera3D.new()
	camera.position = Vector3(0, 5, 12)
	camera.rotation_degrees = Vector3(-25, 0, 0)
	camera.fov = 65
	camera.current = true
	intro_instance.add_child(camera)

	# 等待多帧确保渲染完成
	for i in range(10):
		await get_tree().process_frame

	# 从SubViewport获取截图
	var tex := svp.get_texture()
	assert_bool(tex != null).is_true()

	var img := tex.get_image()
	if img != null:
		img.flip_y()
		var save_path := "res://reports/intro_scene_screenshot.png"
		var err := img.save_png(save_path)
		print("[截图] 保存路径=" + save_path + " 结果=" + str(err) + " 图片尺寸=" + str(img.get_size()))
		assert_int(err).is_equal(OK)
	else:
		print("[截图] img为null，尝试用RenderingServer直接渲染")
		# 使用RenderingServer API直接渲染
		_capture_via_rendering_server(svp)

	# 清理
	svp.remove_child(intro_instance)
	add_child(intro_instance)
	camera.queue_free()
	svp.queue_free()

func _capture_via_rendering_server(svp: SubViewport) -> void:
	# 尝试直接从渲染目标获取
	var rid := svp.get_texture().get_rid()
	if rid.is_valid():
		print("[截图] SubViewport RID有效，尝试获取图像")
		var img := RenderingServer.texture_2d_get(rid)
		if img != null:
			img.flip_y()
			var err := img.save_png("res://reports/intro_scene_screenshot.png")
			print("[截图] RenderingServer方式结果=" + str(err))
		else:
			print("[截图] RenderingServer返回null图像")
	else:
		print("[截图] SubViewport RID无效")

func _count_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count += 1
	for child in node.get_children():
		count += _count_meshes(child)
	return count

func _print_tree(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var info := indent + node.name + " (" + node.get_class() + ")"
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			info += " [mesh=" + mi.mesh.get_class() + "]"
		else:
			info += " [MESH=NULL!]"
	print(info)
	for child in node.get_children():
		_print_tree(child, depth + 1)