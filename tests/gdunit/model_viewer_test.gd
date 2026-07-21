extends GdUnitTestSuite

# ── Helper: create a ModelViewer instance without adding it to the tree ────
func _make_viewer() -> Control:
	var script := load("res://scenes/ui/model_viewer.gd")
	var viewer: Control = script.new()
	return viewer


func _with_zh_locale(callable: Callable) -> void:
	## 图鉴展示名以中文为翻译键；断言时固定 zh。
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	callable.call()
	TranslationServer.set_locale(prev)


# ── _filename_to_display_name tests ───────────────────────────────────────

func test_filename_localizes_equipment_display_names() -> void:
	_with_zh_locale(func():
		var v := _make_viewer()
		assert_str(v._filename_to_display_name("weapons_axe.glb")).is_equal("战斧")
		assert_str(v._filename_to_display_name("weapons_shortsword.glb")).is_equal("短剑")
		assert_str(v._filename_to_display_name("weapons_voxel_longsword.glb")).is_equal("长剑")
		v.free()
	)


func test_filename_localizes_armor_display_names() -> void:
	_with_zh_locale(func():
		var v := _make_viewer()
		assert_str(v._filename_to_display_name("armor_chain_armor.glb")).is_equal("锁子甲")
		assert_str(v._filename_to_display_name("armor_plate_armor.glb")).is_equal("板甲")
		assert_str(v._filename_to_display_name("armor_cloth_armor.glb")).is_equal("布甲")
		v.free()
	)


func test_filename_strips_props_prefix() -> void:
	_with_zh_locale(func():
		var v := _make_viewer()
		assert_str(v._filename_to_display_name("props_fireplace.glb")).is_equal("壁炉")
		v.free()
	)


func test_filename_strips_materials_prefix() -> void:
	_with_zh_locale(func():
		var v := _make_viewer()
		assert_str(v._filename_to_display_name("materials_voxel_glowcap.glb")).is_equal("荧光菇")
		# 策划材料大表 / 模型清单：游戏内与图鉴同一本地化名
		assert_str(v._filename_to_display_name("materials_blackberry.glb")).is_equal("黑莓")
		assert_str(v._filename_to_display_name("materials_skeleton_dust.glb")).is_equal("白骨粉末")
		v.free()
	)


func test_filename_strips_environment_prefix() -> void:
	_with_zh_locale(func():
		var v := _make_viewer()
		assert_str(v._filename_to_display_name("environment_tutorial_road_blocker.glb")).is_equal("教程道路障碍")
		assert_str(v._filename_to_display_name("environment_tutorial_cart_wreck.glb")).is_equal("教程损坏马车")
		v.free()
	)


func test_filename_localizes_monsters_and_strips_rig_resolution_suffixes() -> void:
	_with_zh_locale(func():
		var v := _make_viewer()
		assert_str(v._filename_to_display_name("voxel_goblin_32px.glb")).is_equal("哥布林")
		assert_str(v._filename_to_display_name("voxel_dragon_256px.glb")).is_equal("巨龙")
		assert_str(v._filename_to_display_name("voxel_troll_64x.glb")).is_equal("巨魔")
		assert_str(v._filename_to_display_name("voxel_rat_12px.glb")).is_equal("巨鼠")
		assert_str(v._filename_to_display_name("voxel_orc_raider_48px_rig.glb")).is_equal("兽人掠夺者")
		assert_str(v._filename_to_display_name("voxel_shadow_assassin_48px_rig.glb")).is_equal("暗影刺客")
		assert_str(v._filename_to_display_name("voxel_rock_golem_80px.glb")).is_equal("岩石魔像")
		assert_str(v._filename_to_display_name("voxel_rock_golem_80px_rig.glb")).is_equal("岩石魔像")
		v.free()
	)


func test_filename_handles_hyphens() -> void:
	_with_zh_locale(func():
		var v := _make_viewer()
		assert_str(v._filename_to_display_name("barrel-fragmented.glb")).is_equal("破碎木桶")
		assert_str(v._filename_to_display_name("door-frame.glb")).is_equal("Door Frame")
		assert_str(v._filename_to_display_name("ceiling-tiles.glb")).is_equal("Ceiling Tiles")
		assert_str(v._filename_to_display_name("crate-large.glb")).is_equal("Crate Large")
		v.free()
	)


func test_filename_handles_meshy_ai_model() -> void:
	var v := _make_viewer()
	var name: String = v._filename_to_display_name("Meshy_AI_Crimson_Ironclad_0705221238_texture.glb")
	assert_str(name).is_equal("Crimson Ironclad")
	v.free()


func test_filename_simple_names() -> void:
	_with_zh_locale(func():
		var v := _make_viewer()
		assert_str(v._filename_to_display_name("voxel_character.glb")).is_equal("角色模型")
		assert_str(v._filename_to_display_name("torch.glb")).is_equal("火把")
		assert_str(v._filename_to_display_name("voxel_buckler.glb")).is_equal("圆盾")
		v.free()
	)


func test_filename_localizes_all_scanned_model_families() -> void:
	_with_zh_locale(func():
		var v := _make_viewer()
		var localized_models := {
			"wall_lantern.tscn": "壁灯",
			"voxel_elemental_frost_48px_rig.glb": "寒霜元素",
			"voxel_animated_armor_48px_rig.glb": "活化盔甲",
			"materials_voxel_bone_shard_sample.glb": "骨片样本",
			"voxel_arrow.tscn": "箭矢",
		}
		for file_name in localized_models:
			assert_str(v._filename_to_display_name(file_name)).is_equal(localized_models[file_name])
		v.free()
	)


# ── GLB scan config tests ─────────────────────────────────────────────────

func test_glb_scan_config_has_expected_categories() -> void:
	var v := _make_viewer()
	var config: Dictionary = v._GLB_SCAN_CONFIG
	assert_bool(config.has("Characters & Monsters")).is_true()
	assert_bool(config.has("Dungeon Props")).is_false()
	assert_bool(config.has("Dungeon Structures")).is_true()
	assert_bool(config.has("Voxel Materials")).is_true()
	assert_bool(config.has("Environment")).is_true()
	v.free()


func test_scan_directories_exist() -> void:
	var v := _make_viewer()
	for category in v._GLB_SCAN_CONFIG.keys():
		for dir_path in v._GLB_SCAN_CONFIG[category]:
			var dir := DirAccess.open(dir_path)
			assert_object(dir) \
				.override_failure_message("Directory not found: %s (category: %s)" % [dir_path, category]) \
				.is_not_null()
	v.free()


# ── Directory content tests (verify real models exist) ────────────────────

func _count_glbs_in_dir(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return -1
	var count := 0
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".glb") and not fn.ends_with(".import"):
			count += 1
		fn = dir.get_next()
	dir.list_dir_end()
	return count


func test_characters_dir_has_glb_models() -> void:
	assert_int(_count_glbs_in_dir("res://assets/meshes/characters/")).is_greater_equal(5)


func test_weapons_dir_has_glb_models() -> void:
	assert_int(_count_glbs_in_dir("res://assets/meshes/weapons/")).is_greater_equal(10)


func test_armor_dir_has_glb_models() -> void:
	assert_int(_count_glbs_in_dir("res://assets/meshes/armor/")).is_greater_equal(4)


func _count_tscns_in_dir(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return -1
	var count := 0
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".tscn") and fn.begins_with("baked_"):
			count += 1
		fn = dir.get_next()
	dir.list_dir_end()
	return count


func test_props_dir_has_baked_tscn_models() -> void:
	assert_int(_count_tscns_in_dir("res://assets/meshes/props/")).is_greater_equal(10)


func test_materials_dir_has_glb_models() -> void:
	assert_int(_count_glbs_in_dir("res://assets/models/materials/")).is_greater_equal(3)


func test_environment_dir_has_glb_models() -> void:
	assert_int(_count_glbs_in_dir("res://assets/models/environment/")).is_greater_equal(3)


# ── Source code structural tests ──────────────────────────────────────────

func test_add_to_category_handles_name_collision() -> void:
	var v := _make_viewer()
	var db: Dictionary = {}
	v._add_to_category(db, "Test", "Axe", "res://path1.glb")
	v._add_to_category(db, "Test", "Axe", "res://path2.glb")
	# Second entry should get " (Alt)" suffix
	assert_bool(db["Test"].has("Axe")).is_true()
	assert_bool(db["Test"].has("Axe (Alt)")).is_true()
	assert_str(db["Test"]["Axe"]).is_equal("res://path1.glb")
	assert_str(db["Test"]["Axe (Alt)"]).is_equal("res://path2.glb")
	v.free()


func test_source_uses_weapon_registry() -> void:
	var source: String = load("res://scenes/ui/model_viewer.gd").source_code
	assert_bool(source.contains("WeaponRegistry")).is_true()


func test_source_has_dynamic_scanning() -> void:
	var source: String = load("res://scenes/ui/model_viewer.gd").source_code
	assert_bool(source.contains("_build_asset_database")).is_true()
	assert_bool(source.contains("_scan_glb_directory")).is_true()
	assert_bool(source.contains("DirAccess")).is_true()


func test_source_has_no_obj_references() -> void:
	# The model viewer should only use GLB models, not OBJ.
	var source: String = load("res://scenes/ui/model_viewer.gd").source_code
	assert_bool(source.contains(".obj")).is_false()
	assert_bool(source.contains("_classify_obj")).is_false()
	assert_bool(source.contains("_obj_to_display_name")).is_false()
	assert_bool(source.contains("_add_obj_models")).is_false()
	assert_bool(source.contains("_OBJ_DIR")).is_false()
	assert_bool(source.contains("_OBJ_MONSTERS")).is_false()


func test_script_loads_without_syntax_errors() -> void:
	var script := load("res://scenes/ui/model_viewer.gd")
	assert_object(script).is_not_null()
	assert_bool(script is GDScript).is_true()


func test_camera_rotation() -> void:
	var viewer = load("res://scenes/ui/model_viewer.tscn").instantiate()
	get_tree().root.add_child(viewer)
	
	var initial_rot_y = viewer.camera_pivot.rotation.y
	var initial_rot_x = viewer.camera_pivot.rotation.x
	
	# Simulate drag rotation
	viewer._rotate_camera(Vector2(10.0, 20.0))
	
	assert_float(viewer.camera_pivot.rotation.y).is_not_equal(initial_rot_y)
	assert_float(viewer.camera_pivot.rotation.x).is_not_equal(initial_rot_x)
	
	# Verify clamp bounds (-80 deg / 80 deg)
	viewer._rotate_camera(Vector2(0.0, 1000.0))
	assert_bool(is_equal_approx(viewer.camera_pivot.rotation.x, deg_to_rad(-80.0))).is_true()
	
	viewer._rotate_camera(Vector2(0.0, -2000.0))
	assert_bool(is_equal_approx(viewer.camera_pivot.rotation.x, deg_to_rad(80.0))).is_true()
	
	viewer.queue_free()


func test_camera_zoom() -> void:
	var viewer = load("res://scenes/ui/model_viewer.tscn").instantiate()
	get_tree().root.add_child(viewer)
	
	var initial_z = viewer.camera.position.z
	
	# Simulate zoom in
	viewer._zoom_camera(-1.0)
	assert_float(viewer.camera.position.z).is_less(initial_z)
	
	# Simulate zoom out
	viewer._zoom_camera(2.0)
	assert_float(viewer.camera.position.z).is_greater(initial_z)
	
	# Verify clamp bounds [0.5, 10.0]
	viewer._zoom_camera(-100.0)
	assert_bool(is_equal_approx(viewer.camera.position.z, 0.5)).is_true()
	
	viewer._zoom_camera(100.0)
	assert_bool(is_equal_approx(viewer.camera.position.z, 10.0)).is_true()
	
	viewer.queue_free()


func test_sidebar_title_localization() -> void:
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	
	var viewer = load("res://scenes/ui/model_viewer.tscn").instantiate()
	get_tree().root.add_child(viewer)
	
	# Verify titles are localized if translations are loaded; otherwise fall back to English
	var has_translation = TranslationServer.translate(" MODEL VIEWER / EDITOR") != " MODEL VIEWER / EDITOR"
	if has_translation:
		assert_str(viewer.sidebar_title.text).contains("模型查看器")
		assert_str(viewer.inspector_title.text).contains("资源检查器")
	else:
		assert_str(viewer.sidebar_title.text).contains("MODEL VIEWER")
		assert_str(viewer.inspector_title.text).contains("ASSET INSPECTOR")
	
	TranslationServer.set_locale(original_locale)
	viewer.queue_free()


# ── Skeleton animation controls ───────────────────────────────────────────

func test_source_has_animation_controls() -> void:
	var source: String = load("res://scenes/ui/model_viewer.gd").source_code
	assert_bool(source.contains("_setup_animation_controls")).is_true()
	assert_bool(source.contains("_find_animation_player")).is_true()
	assert_bool(source.contains("_play_selected_animation")).is_true()
	assert_bool(source.contains("PlayAnimBtn")).is_true()


func test_scene_has_animation_ui_nodes() -> void:
	var viewer = load("res://scenes/ui/model_viewer.tscn").instantiate()
	get_tree().root.add_child(viewer)
	assert_object(viewer.anim_section).is_not_null()
	assert_object(viewer.anim_option).is_not_null()
	assert_object(viewer.play_anim_btn).is_not_null()
	assert_object(viewer.stop_anim_btn).is_not_null()
	assert_object(viewer.loop_anim_btn).is_not_null()
	# Hidden until a skinned model is loaded
	assert_bool(viewer.anim_section.visible).is_false()
	viewer.queue_free()


func test_rigged_model_shows_animation_controls() -> void:
	var rig_path := "res://assets/meshes/characters/voxel_goblin_32px_rig.glb"
	if not ResourceLoader.exists(rig_path):
		return  # skip if asset missing in this checkout

	var viewer = load("res://scenes/ui/model_viewer.tscn").instantiate()
	get_tree().root.add_child(viewer)
	await viewer._load_model("Voxel Goblin Rig", rig_path)

	assert_bool(viewer.anim_section.visible).is_true()
	assert_object(viewer.current_anim_player).is_not_null()
	assert_int(viewer.anim_option.item_count).is_greater(0)

	# Play button should start the selected animation
	viewer._on_play_anim_pressed()
	assert_bool(viewer.current_anim_player.is_playing()).is_true()

	viewer._on_stop_anim_pressed()
	assert_bool(viewer.current_anim_player.is_playing()).is_false()

	viewer.queue_free()


func test_character_scan_prefers_runtime_rig_over_static_duplicate() -> void:
	var viewer := _make_viewer()
	var db: Dictionary = {}
	var category := "Characters & Monsters"
	viewer._scan_glb_directory(db, category, "res://assets/meshes/characters/", true)
	var goblin_paths: Array[String] = []
	for tier_bucket in db[category].values():
		for path in (tier_bucket as Dictionary).values():
			if String(path).contains("voxel_goblin_32px"):
				goblin_paths.append(String(path))
	assert_array(goblin_paths).has_size(1)
	assert_str(goblin_paths[0]).ends_with("voxel_goblin_32px_rig.glb")
	viewer.free()


func test_runtime_rig_preview_preserves_authored_root_transform() -> void:
	var rig_path := "res://assets/meshes/characters/voxel_goblin_32px_rig.glb"
	var viewer = load("res://scenes/ui/model_viewer.tscn").instantiate()
	get_tree().root.add_child(viewer)
	await viewer._load_model("Voxel Goblin Rig", rig_path)
	assert_float(viewer.current_model_node.position.length()).is_equal_approx(0.0, 0.0001)
	assert_float(viewer.current_model_node.scale.distance_to(Vector3.ONE)).is_equal_approx(0.0, 0.0001)
	viewer.queue_free()


func test_static_model_hides_animation_controls() -> void:
	# Weapons are static meshes without AnimationPlayer
	var weapon_path := "res://assets/meshes/weapons/weapons_voxel_axe.glb"
	if not ResourceLoader.exists(weapon_path):
		return

	var viewer = load("res://scenes/ui/model_viewer.tscn").instantiate()
	get_tree().root.add_child(viewer)
	await viewer._load_model("Axe", weapon_path)

	assert_bool(viewer.anim_section.visible).is_false()
	assert_object(viewer.current_anim_player).is_null()
	viewer.queue_free()


# ── Character model quality-tier subtags (docs/28, docs/29) ────────────────

func test_add_character_to_tier_nests_under_quality_subtag() -> void:
	_with_zh_locale(func():
		var v := _make_viewer()
		var db: Dictionary = {}
		var cat := "Characters & Monsters"
		v._add_character_to_tier(db, cat, "voxel_goblin_32px_rig.glb", "哥布林", "res://assets/meshes/characters/voxel_goblin_32px_rig.glb")
		v._add_character_to_tier(db, cat, "voxel_kobold_36px.glb", "狗头人", "res://assets/meshes/characters/voxel_kobold_36px.glb")
		v._add_character_to_tier(db, cat, "voxel_shadow_assassin_48px_rig.glb", "暗影刺客", "res://assets/meshes/characters/voxel_shadow_assassin_48px_rig.glb")
		assert_bool(db[cat].has("S 档")).is_true()
		assert_bool(db[cat]["S 档"].has("哥布林")).is_true()
		assert_bool(db[cat].has("D 档")).is_true()
		assert_bool(db[cat]["D 档"].has("狗头人")).is_true()
		assert_bool(db[cat].has("C 档")).is_true()
		assert_bool(db[cat]["C 档"].has("暗影刺客")).is_true()
		v.free()
	)


func test_category_is_tier_nested_detection() -> void:
	var v := _make_viewer()
	assert_bool(v._category_is_tier_nested({"S 档": {"哥布林": "res://a.glb"}})).is_true()
	assert_bool(v._category_is_tier_nested({"哥布林": "res://a.glb"})).is_false()
	v.free()


func test_count_category_leaves_counts_nested_models() -> void:
	var v := _make_viewer()
	var nested := {
		"S 档": {"a": "1", "b": "2"},
		"A 档": {"c": "3"},
	}
	assert_int(v._count_category_leaves(nested)).is_equal(3)
	assert_int(v._count_category_leaves({"a": "1", "b": "2"})).is_equal(2)
	v.free()


func test_material_display_matches_brewing_data_and_manifest() -> void:
	var v := _make_viewer()
	var BD := load("res://globals/tavern/brewing_data.gd")
	assert_str(v._resolve_material_display_name("blackberry")).is_equal(BD.get_material_name("blackberry"))
	assert_str(v._resolve_material_display_name("skeleton_dust")).is_equal(BD.get_material_name("skeleton_dust"))
	assert_str(v._resolve_material_display_name("soul_gem")).is_equal(BD.get_material_name("soul_gem"))
	assert_str(v._resolve_material_display_name("not_a_material")).is_empty()
	v.free()


func test_source_uses_character_model_tiers() -> void:
	var source: String = load("res://scenes/ui/model_viewer.gd").source_code
	assert_bool(source.contains("character_model_tiers.gd")).is_true()
	assert_bool(source.contains("_add_character_to_tier")).is_true()
	assert_bool(source.contains("TIER_ORDER")).is_true()
