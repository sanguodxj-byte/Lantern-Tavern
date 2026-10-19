extends SceneTree

## Quick compilation check for new rune system files.
## Usage: godot --headless --script res://tools/load_check.gd
##
## 架构审查 P2-3：不能只靠 load() != null 判定成功——脚本 Compile Error 时 load()
## 返回的脚本对象可能非空但「已损坏」（source_code 为空 / reload 报错）。
## 这里对 GDScript 检查 source_code 非空、can_instantiate，并对目标脚本执行 reload()
## 做权威编译校验——reload() 会重编目标及其依赖，任何 Compile Error 返回 ERR_COMPILATION_FAILED，
## 防止「目标 OK、依赖编译失败」的假阳性（架构审查 A7，rune_effect_hooks.gd 案例）。

func _init() -> void:
	var files := [
		"res://globals/combat/status_effect_system.gd",
		"res://globals/combat/rune_effect_hooks.gd",
		"res://globals/combat/rune_word_passive_hooks.gd",
		"res://globals/combat/corrupt_zone_driver.gd",
		"res://globals/combat/rune_data.gd",
		"res://globals/combat/rune_word_data.gd",
		"res://scenes/characters/player/player_skill_dispatcher.gd",
		"res://scenes/equipment/projectile_entity.gd",
		"res://scenes/characters/player/state/player_state_slashing.gd",
	]
	var exe := OS.get_executable_path()
	var ok := true
	for path in files:
		var script := load(path)
		if script == null:
			push_error("FAILED to load: " + path)
			ok = false
			continue
		# 快速本地检查：目标脚本自身源码真实且可实例化。
		if script is GDScript:
			var gd := script as GDScript
			if gd.source_code.is_empty():
				push_error("SCRIPT COMPILE FAILED (empty source): " + path)
				ok = false
				continue
			if gd.can_instantiate() == false:
				push_error("SCRIPT COMPILE FAILED (cannot instantiate): " + path)
				ok = false
				continue
		# A7 权威验证：子进程重新解析目标及其完整依赖图（含 .tscn 内嵌脚本）。
		# 依赖链上任何 Compile Error 都会在子进程 stderr 出现——捕获即判失败，
		# 杜绝「目标 OK、依赖编译失败」的假阳性。
		var output: Array = []
		var exit_code := OS.execute(exe, [
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tools/load_check_validator.gd", path,
		], output)
		var joined := "\n".join(output)
		var dep_failed := joined.contains("SCRIPT ERROR") or joined.contains("Parse Error") \
			or joined.contains("Compilation failed") or joined.contains("Failed to load script")
		if exit_code != 0 or dep_failed:
			push_error("SCRIPT COMPILE FAILED (dependency/compile error, subprocess exit %d): %s" % [exit_code, path])
			ok = false
			continue
		print("OK: " + path)
	if ok:
		print("All files compiled successfully.")
	else:
		print("Some files failed to compile!")
	quit(0 if ok else 1)
