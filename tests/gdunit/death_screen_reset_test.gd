extends GdUnitTestSuite
## 死亡回归场景状态重置测试
## 验证：死亡 → 遣送酒馆 → 重新进入地牢时，死亡屏幕等残留 UI 状态被正确清理

func test_set_world_space_resets_death_screen_source() -> void:
	var script := load("res://scenes/ui/ui.gd") as GDScript
	var source := script.source_code
	# set_world_space 必须重置死亡屏幕
	assert_bool(source.contains("death_screen.modulate = Color.TRANSPARENT")) \
		.override_failure_message("set_world_space 应将死亡屏幕 modulate 重置为 TRANSPARENT").is_true()

func test_set_world_space_kills_death_tween_source() -> void:
	var script := load("res://scenes/ui/ui.gd") as GDScript
	var source := script.source_code
	# set_world_space 必须杀死死亡屏幕 tween，防止 tween 恢复 modulate
	assert_bool(source.contains("death_tween.kill()")) \
		.override_failure_message("set_world_space 应 kill 死亡 tween 防止覆盖重置").is_true()

func test_key_ui_residue_removed() -> void:
	# 彩色钥匙玩法已废弃：UI / CombatHUD / 场景均不应再保留钥匙栏残留
	var ui_source := (load("res://scenes/ui/ui.gd") as GDScript).source_code
	var hud_source := (load("res://scenes/ui/combat_hud.gd") as GDScript).source_code
	var hud_scene := FileAccess.get_file_as_string("res://scenes/ui/combat_hud.tscn")
	var events_source := (load("res://globals/core/game_events.gd") as GDScript).source_code
	var log_source := (load("res://scenes/ui/combat_log.gd") as GDScript).source_code
	assert_bool(ui_source.contains("key_container")) \
		.override_failure_message("UI 层不应再引用 key_container").is_false()
	assert_bool(hud_source.contains("key_container")) \
		.override_failure_message("CombatHUD 脚本应移除 key_container 残留").is_false()
	assert_bool(hud_scene.contains("KeyContainer") or hud_scene.contains("key_texture.tscn")) \
		.override_failure_message("CombatHUD 场景应移除 KeyContainer / key_texture 引用").is_false()
	assert_bool(events_source.contains("current_keys_changed")) \
		.override_failure_message("GameEvents 应移除 current_keys_changed 残留信号").is_false()
	assert_bool(log_source.contains("current_keys_changed") or log_source.contains("_on_keys_changed")) \
		.override_failure_message("CombatLog 应移除钥匙信号监听").is_false()
	assert_bool(ResourceLoader.exists("res://scenes/ui/key_texture.tscn")) \
		.override_failure_message("废弃的 key_texture.tscn 不应存在").is_false()

func test_set_world_space_resets_hurt_vignette_source() -> void:
	var script := load("res://scenes/ui/ui.gd") as GDScript
	var source := script.source_code
	# set_world_space 必须重置受伤渐晕效果
	assert_bool(source.contains("hurt_vignette.modulate.a = 0.0")) \
		.override_failure_message("set_world_space 应重置 hurt_vignette alpha 为 0").is_true()

func test_on_player_dead_stores_tween_reference() -> void:
	var script := load("res://scenes/ui/ui.gd") as GDScript
	var source := script.source_code
	# on_player_dead 必须存储 tween 引用，以便 set_world_space 能 kill 它
	assert_bool(source.contains("death_tween = create_tween()")) \
		.override_failure_message("on_player_dead 应存储 death_tween 引用").is_true()

func test_death_flow_does_not_emit_level_restarted() -> void:
	# 死亡主路径应调用 extract_to_tavern，而非 emit level_restarted
	# level_restarted 会触发 World.on_level_restarted 重载地牢，而非遣送酒馆
	var script := load("res://scenes/characters/player/state/player_state_dying.gd") as GDScript
	var source := script.source_code
	var extract_pos := source.find("extract_to_tavern")
	var restart_pos := source.find("GameEvents.level_restarted.emit()")
	assert_bool(extract_pos != -1).is_true()
	# level_restarted 只能在 fallback 分支（extract_to_tavern 之后）
	if restart_pos != -1:
		assert_bool(restart_pos > extract_pos) \
			.override_failure_message("level_restarted 应仅在 extract_to_tavern 之后的 fallback 中").is_true()

func test_world_load_space_calls_set_world_space() -> void:
	# World.load_space 必须调用 _update_shared_ui → set_world_space
	# 确保每次场景切换都触发 UI 状态重置
	var script := load("res://scenes/world/world.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("_update_shared_ui")) \
		.override_failure_message("load_space 应调用 _update_shared_ui").is_true()
	assert_bool(source.contains("set_world_space")) \
		.override_failure_message("_update_shared_ui 应调用 set_world_space").is_true()

func test_set_world_space_reset_runs_on_all_transitions() -> void:
	# 验证 set_world_space 中的重置逻辑在函数末尾（不在 if visible 块内）
	# 确保无论目标空间是什么（dungeon/tavern/intro），都执行重置
	var script := load("res://scenes/ui/ui.gd") as GDScript
	var source := script.source_code
	var func_start := source.find("func set_world_space")
	var func_end := source.find("const CHARACTER_PANEL_PREFAB")
	assert_bool(func_start != -1 and func_end != -1).is_true()
	var func_body := source.substr(func_start, func_end - func_start)
	# 死亡屏幕重置不应在 "if visible" 块内（必须在 if 块外，对所有空间生效）
	var visible_block_start := func_body.find("if visible:")
	var death_reset_pos := func_body.find("death_screen.modulate = Color.TRANSPARENT")
	assert_bool(visible_block_start != -1 and death_reset_pos != -1).is_true()
	assert_bool(death_reset_pos > visible_block_start) \
		.override_failure_message("死亡屏幕重置应在 if visible 块之后（对所有空间生效）").is_true()
