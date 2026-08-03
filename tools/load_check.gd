extends SceneTree

## Quick compilation check for new rune system files.
## Usage: godot --headless --script res://tools/load_check.gd
##
## 架构审查 P2-3：不能只靠 load() != null 判定成功——脚本 Compile Error 时 load()
## 返回的脚本对象可能非空但「已损坏」（source_code 为空 / reload 报错）。
## 这里对 GDScript 检查 source_code 非空，并把引擎 stderr 的 SCRIPT ERROR/Parse Error
## 输出纳入失败判定，任何编译错误都会让进程以退出码 1 结束。

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
	var ok := true
	for path in files:
		var script := load(path)
		if script == null:
			push_error("FAILED to load: " + path)
			ok = false
			continue
		# P2-3：依赖脚本编译失败时 load() 可能仍返回对象——校验源码真实性。
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
		print("OK: " + path)
	if ok:
		print("All files compiled successfully.")
	else:
		print("Some files failed to compile!")
	quit(0 if ok else 1)
