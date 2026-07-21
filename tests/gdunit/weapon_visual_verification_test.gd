extends GdUnitTestSuite

# 地牢战斧与素材建模三视图视觉确认截图工具
# 运行指令:
# "D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a tests/gdunit/weapon_visual_verification_test.gd

const PROCEDURAL_DUNGEON_PATH := "res://scenes/expedition/procedural_dungeon.tscn"

# 待检查的资产定义
const TEST_MODELS := {
	"spot_voxel_32x": "res://assets/temp_test/voxel_spot_32x.glb",
	"spot_voxel_64x": "res://assets/temp_test/voxel_spot_64x.glb",
	"ironclad_voxel_32x": "res://assets/temp_test/voxel_ironclad_32x.glb",
	"ironclad_voxel_64x": "res://assets/temp_test/voxel_ironclad_64x.glb",
	"deeprock_moss": "res://assets/models/materials/materials_deeprock_moss.glb",
	"black_rye_root": "res://assets/models/materials/materials_black_rye_root.glb"
}

const MATERIAL_IDS := [
	"rat_tail", "moldy_bread", "rusty_nail", "dungeon_moss", "bone_shard",
	"stale_water", "prison_lichen", "cellar_mushroom", "blackberry", "glowshroom",
	"moongrass", "pixie_dust", "poison_berry", "deeprock_moss", "black_rye_root",
	"stalactite_sap", "goblin_nail", "mistflower", "wolfear_herb", "cyclops_beard",
	"geothermal_ear", "luminous_fern", "quartz_dust", "blindfish_jerky"
]

func test_generate_dungeon_screenshots() -> void:
	# 1. 确保报告保存目录存在
	var dir := DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("reports/weapons_preview")
		dir.make_dir_recursive("reports/materials_preview")
	
	# 2. 实例化纯净 Node3D
	print("[开始] 创建测试纯净 3D 渲染容器...")
	var dungeon = Node3D.new()
	add_child(dungeon)
	
	var spawn_pos: Vector3 = Vector3(0.0, 0.0, 0.0)
	print("[测试] 纯净 3D 容器就绪。物品放置点 =", spawn_pos)
	
	# 3. 创建 SubViewport 用于渲染截图
	var svp := SubViewport.new()
	svp.size = Vector2i(512, 512)
	svp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svp.transparent_bg = false
	add_child(svp)
	
	# 将地牢移至 SubViewport 中以便独立渲染
	remove_child(dungeon)
	svp.add_child(dungeon)
	
	# 4. 在放置区加入两个亮白色补光灯（主灯和辅助灯）以提供充足对比度
	var light_main := OmniLight3D.new()
	light_main.light_color = Color("#ffffff")
	light_main.light_energy = 8.0
	light_main.omni_range = 6.0
	light_main.position = spawn_pos + Vector3(1.0, 1.5, 1.0)
	dungeon.add_child(light_main)
	
	var light_fill := OmniLight3D.new()
	light_fill.light_color = Color("#ffeacc") # 偏黄暖光，模拟火把
	light_fill.light_energy = 4.0
	light_fill.omni_range = 5.0
	light_fill.position = spawn_pos + Vector3(-1.0, 0.8, -1.0)
	dungeon.add_child(light_fill)
	
	# 5. 循环处理新规格测试模型
	for model_id in TEST_MODELS:
		var glb_path: String = TEST_MODELS[model_id]
		await _process_model_capture(svp, dungeon, spawn_pos, model_id, glb_path, false)
		
	# 7. 清理场景
	light_main.queue_free()
	light_fill.queue_free()
	svp.remove_child(dungeon)
	dungeon.queue_free()
	svp.queue_free()
	print("[完成] 所有模型三视图截图生成完毕！")

# 核心处理：加载、放置、定位相机、截图保存
func _process_model_capture(svp: SubViewport, dungeon: Node3D, spawn_pos: Vector3, item_id: String, glb_path: String, is_weapon: bool) -> void:
	if not FileAccess.file_exists(glb_path):
		print("[跳过] 模型不存在: ", glb_path)
		return
		
	var packed := load(glb_path) as PackedScene
	if not packed:
		print("[错误] 无法加载 GLB: ", glb_path)
		return
		
	var inst := packed.instantiate() as Node3D
	if not inst:
		return
		
	dungeon.add_child(inst)
	
	# 确定物体的尺寸以调整相机距离
	var max_dim: float = 0.25
	var mesh_inst: MeshInstance3D = _find_mesh_instance(inst)
	if mesh_inst and mesh_inst.mesh:
		var aabb: AABB = mesh_inst.mesh.get_aabb()
		max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		print("[模型] %s (Mesh: %s) AABB 尺寸 = %s, max_dim = %.3f" % [item_id, mesh_inst.name, aabb.size, max_dim])
		
		if "spot" in item_id or "ironclad" in item_id:
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.roughness = 0.8
			mat.specular = 0.1
			mesh_inst.set_surface_override_material(0, mat)
			print("  [材质] 强制应用顶点色 albedo 材质到 %s" % item_id)
	else:
		print("[模型] %s 未找到 MeshInstance3D，使用默认最大维度 0.25" % item_id)
		
	# 调整物体位置和旋转：略微抬起放置在地面上方，以斜角或正面放置以防平躺看不清
	var height_offset: float = max_dim * 0.5
	inst.position = spawn_pos + Vector3(0, height_offset, 0)
	
	# 给一定的倾斜度（例如 25 度），利于观察立体轮廓（对战斧特别有效）
	if is_weapon:
		inst.rotation_degrees = Vector3(0, 45, 15)
	else:
		inst.rotation_degrees = Vector3(15, 30, 0)
		
	# 设置三视图相机 parameters
	# 距离计算：一般在 max_dim 的 1.5 到 2.5 倍之间，武器可以稍远，素材需要贴近
	var distance: float = maxf(max_dim * 2.2, 0.25)
	if is_weapon:
		distance = maxf(max_dim * 1.5, 0.8) # 武器较大，拉远一点
		
	var target_pos: Vector3 = spawn_pos + Vector3(0, height_offset, 0)
	
	var views: Dictionary = {
		"front": spawn_pos + Vector3(0, height_offset, distance), # 正面
		"side": spawn_pos + Vector3(distance, height_offset, 0),  # 侧面
		"top": spawn_pos + Vector3(0, height_offset + distance, 0.001)  # 顶面（微小Z偏置避免与 look_at 向上向量共线）
	}
	
	# 循环截图三个视角
	for view_name in views:
		var cam_pos: Vector3 = views[view_name]
		var camera := Camera3D.new()
		dungeon.add_child(camera)
		camera.position = cam_pos
		
		# 俯视图特殊的向上向量
		if view_name == "top":
			camera.look_at(target_pos, Vector3(0, 0, -1))
		else:
			camera.look_at(target_pos, Vector3.UP)
			
		camera.current = true
		
		# 等待多帧以便渲染管线捕获
		for i in range(5):
			await get_tree().process_frame
			
		# 强行强制渲染引擎更新所有 Viewport，确保 FBO 写入了真实的 3D 内容
		RenderingServer.force_draw()
			
		# 保存截图
		var save_dir = "weapons_preview" if is_weapon else "materials_preview"
		var save_path := "res://reports/%s/%s_%s.png" % [save_dir, item_id, view_name]
		
		var tex := svp.get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				# img.flip_y()
				var err := img.save_png(save_path)
				if err == OK:
					print("  [截图成功] %s (%s) -> %s" % [item_id, view_name, save_path])
				else:
					print("  [截图失败] %s 保存错误码=%d" % [item_id, err])
			else:
				# 备用方案：通过 RenderingServer
				var rid := tex.get_rid()
				if rid.is_valid():
					var rs_img := RenderingServer.texture_2d_get(rid)
					if rs_img:
						# rs_img.flip_y()
						rs_img.save_png(save_path)
						print("  [截图成功-RS] %s (%s) -> %s" % [item_id, view_name, save_path])
		
		camera.queue_free()
		
	# 清理实例
	inst.queue_free()

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found = _find_mesh_instance(child)
		if found:
			return found
	return null

func _clear_enemies(node: Node) -> void:
	if node is CharacterBody3D and node.name != "Player":
		node.queue_free()
		return
	for child in node.get_children():
		_clear_enemies(child)

func _clear_player_and_ui(node: Node) -> void:
	# 遍历地牢节点，销毁 Player 角色、Camera3D 与 HUD CanvasLayer
	for child in node.get_children():
		if child.name.contains("Player") or child.name.contains("player") or child is CanvasLayer or child is Camera3D:
			child.queue_free()
		else:
			_clear_player_and_ui(child)
