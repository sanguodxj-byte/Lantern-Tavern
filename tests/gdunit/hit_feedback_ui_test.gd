extends GdUnitTestSuite

## 战斗命中反馈 UI 测试：
## 1. 准心 Hitmarker 接线
## 2. 受击闪红 play_hurt_flash
## 3. 敌人命中信号覆盖 try_receive_hit / try_receive_hit_result


func test_game_events_has_player_hit_enemy_signal() -> void:
	var source := (load("res://globals/core/game_events.gd") as GDScript).source_code
	assert_bool(source.contains("signal player_hit_enemy")).is_true()
	assert_bool(GameEvents.has_signal("player_hit_enemy")).is_true()


func test_enemy_emits_player_hit_enemy_on_result_and_legacy_hit() -> void:
	var source := (load("res://scenes/characters/enemies/enemy.gd") as GDScript).source_code
	# try_receive_hit_result 路径
	assert_bool(source.contains("player_hit_enemy.emit")).is_true()
	# 旧 try_receive_hit 路径也应发射，避免近战/道具硬编码伤害无反馈
	var legacy_start := source.find("func try_receive_hit(")
	var result_start := source.find("func try_receive_hit_result")
	assert_int(legacy_start).is_greater(-1)
	assert_int(result_start).is_greater(legacy_start)
	var legacy_body := source.substr(legacy_start, result_start - legacy_start)
	assert_bool(legacy_body.contains("player_hit_enemy.emit")) \
		.override_failure_message("try_receive_hit 也应 emit player_hit_enemy 供准心 Hitmarker").is_true()


func test_ui_play_hurt_flash_exists_and_resets() -> void:
	var source := (load("res://scenes/ui/ui.gd") as GDScript).source_code
	assert_bool(source.contains("func play_hurt_flash")).is_true()
	assert_bool(source.contains("HURT_FLASH_PEAK_A")).is_true()
	assert_bool(source.contains("hurt_flash_tween")).is_true()
	# 场景切换时必须 kill 闪红 tween，避免残留
	assert_bool(source.contains("hurt_flash_tween.kill()")).is_true()


func test_ui_on_player_hurt_triggers_flash_outside_intro() -> void:
	var source := (load("res://scenes/ui/ui.gd") as GDScript).source_code
	assert_bool(source.contains("play_hurt_flash()")).is_true()
	# intro 不闪；不再限制仅 dungeon（酒馆也可能受击表现）
	assert_bool(source.contains('world_space == "intro"')) \
		.override_failure_message("on_player_hurt 应跳过 intro 过场").is_true()
	# 旧的「仅 dungeon」限制应已移除
	var func_start := source.find("func on_player_hurt")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("\nfunc ", func_start + 1)
	var body := source.substr(func_start, func_end - func_start)
	assert_bool(body.contains('world_space != "dungeon"')) \
		.override_failure_message("受击闪红不应再限制为仅 dungeon").is_false()


func test_enemy_hit_feedback_cannot_trigger_camera_or_player_hurt_flash() -> void:
	for path in [
		"res://scenes/characters/enemies/state/enemy_state_hurt.gd",
		"res://scenes/characters/enemies/state/enemy_state_blocking.gd",
		"res://scenes/characters/enemies/state/enemy_state_dying.gd",
		"res://scenes/characters/enemies/state/enemy_state_impaling.gd",
	]:
		# GDScript.source_code may be stale while the editor/import cache is warm.
		var source := FileAccess.get_file_as_string(path)
		assert_bool(source.contains("GameEvents.player_hurt.emit")).is_false()
		assert_bool(source.contains("GameEvents.impact_felt.emit")) \
			.override_failure_message("敌人命中反馈不应触发玩家相机冲击/灰屏: %s" % path).is_false()

	var hurt_source := FileAccess.get_file_as_string("res://scenes/characters/enemies/state/enemy_state_hurt.gd")
	assert_bool(hurt_source.contains("if skel != null and enemy.is_inside_tree():")).is_true()
	assert_bool(hurt_source.contains("var part_color := Color(0.6, 0.6, 0.6)")).is_false()
	# 旧精确匹配 is_equal_approx(Color(0.60,...)) 仅拦截回退灰，漏过 armor/metal/stone/leg 等近灰部位色；
	# 现改为 _is_gray_flash_color 色度+明度判定，扩大拦截范围。
	assert_bool(hurt_source.contains("part_color.is_equal_approx(Color(0.60, 0.60, 0.60, 1.0))")).is_false()
	assert_bool(hurt_source.contains("_is_gray_flash_color")).is_true()
	assert_bool(hurt_source.contains("func _is_gray_flash_color")).is_true()


func test_gray_flash_color_filter_logic() -> void:
	# 中明度近灰色 → 拦截（读作灰屏闪屏）
	var EnemyStateHurtScript := load("res://scenes/characters/enemies/state/enemy_state_hurt.gd") as GDScript
	# 精确回退灰
	assert_bool(EnemyStateHurtScript.call("_is_gray_flash_color", Color(0.60, 0.60, 0.60, 1.0))).is_true()
	# voxel_palette 近灰部位色：armor / metal / stone / UpperLeg
	assert_bool(EnemyStateHurtScript.call("_is_gray_flash_color", Color(0.60, 0.62, 0.68))).is_true()
	assert_bool(EnemyStateHurtScript.call("_is_gray_flash_color", Color(0.70, 0.72, 0.78))).is_true()
	assert_bool(EnemyStateHurtScript.call("_is_gray_flash_color", Color(0.55, 0.55, 0.58))).is_true()
	assert_bool(EnemyStateHurtScript.call("_is_gray_flash_color", Color(0.40, 0.42, 0.50))).is_true()
	# 合法命中色 → 保留（不拦截）
	# 骨白（高明度低色度，但明度 ≥ 0.85）
	assert_bool(EnemyStateHurtScript.call("_is_gray_flash_color", Color(0.92, 0.90, 0.82))).is_false()
	# 肤色 Head（高色度）
	assert_bool(EnemyStateHurtScript.call("_is_gray_flash_color", Color(0.82, 0.66, 0.50))).is_false()
	# 深棕 Foot（低明度，色度 0.10 但 value < 0.35）
	assert_bool(EnemyStateHurtScript.call("_is_gray_flash_color", Color(0.30, 0.25, 0.20))).is_false()
	# 血红（高色度）
	assert_bool(EnemyStateHurtScript.call("_is_gray_flash_color", Color(0.70, 0.05, 0.05))).is_false()
	# 绿皮 Torso（高色度）
	assert_bool(EnemyStateHurtScript.call("_is_gray_flash_color", Color(0.45, 0.50, 0.32))).is_false()


func test_ui_hurt_flash_runtime_raises_vignette_alpha() -> void:
	var ui_scene := load("res://scenes/ui/ui.tscn") as PackedScene
	assert_object(ui_scene).is_not_null()
	var ui: Node = ui_scene.instantiate()
	add_child(ui)
	await get_tree().process_frame
	ui.set("world_space", "dungeon")
	var vignette: Panel = ui.get_node_or_null("HurtVignette") as Panel
	assert_object(vignette).is_not_null()
	assert_float(vignette.modulate.a).is_equal_approx(0.0, 0.001)
	# 调用闪红
	assert_bool(ui.has_method("play_hurt_flash")).is_true()
	ui.call("play_hurt_flash")
	# 等一帧让 tween 启动
	await get_tree().process_frame
	await get_tree().create_timer(0.08).timeout
	# 峰值附近应明显 > 0
	assert_float(vignette.modulate.a).is_greater(0.1)
	ui.queue_free()


func test_crosshair_in_combat_hud_scene() -> void:
	var hud_scene := load("res://scenes/ui/combat_hud.tscn") as PackedScene
	assert_object(hud_scene).is_not_null()
	var hud := hud_scene.instantiate()
	add_child(hud)
	await get_tree().process_frame
	var cross := hud.get_node_or_null("Crosshair")
	assert_object(cross).is_not_null()
	assert_bool(cross.has_method("play_hit_flash")).is_true()
	assert_bool(cross.has_method("is_hit_flash_active")).is_true()
	cross.call("play_hit_flash", false)
	assert_bool(cross.call("is_hit_flash_active")).is_true()
	hud.queue_free()
