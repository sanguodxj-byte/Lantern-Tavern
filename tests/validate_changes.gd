extends SceneTree

## 验证脚本：将结果写入文件以绕过 stdout 捕获问题。

func _initialize() -> void:
	var results: Array[String] = []
	results.append("=== VALIDATION START ===")

	# 1. 验证 PlayerState 基类加载
	var ps_script = load("res://scenes/characters/player/state/player_state.gd")
	if ps_script == null:
		results.append("[FAIL] PlayerState 脚本加载失败")
		_write_results(results)
		quit(1)
		return
	results.append("[OK] PlayerState 脚本加载成功")

	# 2. 验证 PlayerState 有 _begin_exit 方法
	if not ps_script.has_method("_begin_exit"):
		results.append("[FAIL] PlayerState 缺少 _begin_exit 方法")
		_write_results(results)
		quit(1)
		return
	results.append("[OK] PlayerState._begin_exit 存在")

	# 3. 验证 PlayerState 有 _on_exit 方法
	if not ps_script.has_method("_on_exit"):
		results.append("[FAIL] PlayerState 缺少 _on_exit 方法")
		_write_results(results)
		quit(1)
		return
	results.append("[OK] PlayerState._on_exit 存在")

	# 4. 验证 player.gd 加载
	var player_script = load("res://scenes/characters/player/player.gd")
	if player_script == null:
		results.append("[FAIL] player.gd 脚本加载失败")
		_write_results(results)
		quit(1)
		return
	results.append("[OK] player.gd 脚本加载成功")

	# 5. 验证 player.gd 源码包含 _begin_exit 调用
	var src = player_script.source_code
	if not src.contains("_begin_exit()"):
		results.append("[FAIL] player.gd 未调用 _begin_exit()")
		_write_results(results)
		quit(1)
		return
	results.append("[OK] player.gd 包含 _begin_exit() 调用")

	# 6. 验证 switch_state 调用 _begin_exit
	var switch_start = src.find("func switch_state")
	if switch_start < 0:
		results.append("[FAIL] 找不到 switch_state 函数")
	else:
		var switch_end = src.find("\nfunc ", switch_start + 1)
		var switch_body = src.substr(switch_start, switch_end - switch_start)
		if switch_body.contains("_begin_exit()"):
			results.append("[OK] switch_state 调用 _begin_exit()")
		else:
			results.append("[FAIL] switch_state 未调用 _begin_exit()")

	# 7. 验证 _exit_tree 调用 _begin_exit
	var exit_start = src.find("func _exit_tree")
	if exit_start < 0:
		results.append("[FAIL] 找不到 _exit_tree 函数")
	else:
		var exit_end = src.find("\nfunc ", exit_start + 1)
		var exit_body = src.substr(exit_start, exit_end - exit_start)
		if exit_body.contains("_begin_exit()"):
			results.append("[OK] _exit_tree 调用 _begin_exit()")
		else:
			results.append("[FAIL] _exit_tree 未调用 _begin_exit()")

	# 8. 验证 equipment_panel_player_finder.gd
	var finder_script = load("res://scenes/ui/equipment_panel_player_finder.gd")
	if finder_script == null:
		results.append("[FAIL] equipment_panel_player_finder.gd 加载失败")
	else:
		var finder_src = finder_script.source_code
		var fn_start = finder_src.find("static func _register_current_player")
		if fn_start < 0:
			results.append("[FAIL] 找不到 _register_current_player")
		else:
			var fn_end = finder_src.find("\nstatic func", fn_start + 1)
			if fn_end == -1:
				fn_end = finder_src.length()
			var fn_body = finder_src.substr(fn_start, fn_end - fn_start)
			if fn_body.contains("register_player"):
				results.append("[OK] _register_current_player 使用 register_player")
			else:
				results.append("[FAIL] _register_current_player 未使用 register_player")

	# 9. 验证 character_panel.gd
	var panel_script = load("res://scenes/ui/character_panel.gd")
	if panel_script == null:
		results.append("[FAIL] character_panel.gd 加载失败")
	else:
		var panel_src = panel_script.source_code
		if panel_src.contains('set_meta("equipment_preview", true)'):
			results.append("[OK] character_panel.gd 设置 equipment_preview meta")
		else:
			results.append("[FAIL] character_panel.gd 未设置 equipment_preview meta")

	# 10. 验证 transition_state 有 _is_exiting 守卫
	var ps_src = ps_script.source_code
	var ts_start = ps_src.find("func transition_state")
	if ts_start < 0:
		results.append("[FAIL] 找不到 transition_state 函数")
	else:
		var ts_end = ps_src.find("\nfunc ", ts_start + 1)
		var ts_body = ps_src.substr(ts_start, ts_end - ts_start)
		if ts_body.contains("if _is_exiting:") and ts_body.contains("return"):
			results.append("[OK] transition_state 有 _is_exiting 守卫")
		else:
			results.append("[FAIL] transition_state 缺少 _is_exiting 守卫")

	results.append("=== VALIDATION END ===")
	_write_results(results)
	quit(0)

func _write_results(results: Array[String]) -> void:
	var f = FileAccess.open("res://validation_results.txt", FileAccess.WRITE)
	if f:
		for line in results:
			f.store_line(line)
		f.close()
