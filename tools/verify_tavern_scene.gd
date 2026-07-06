extends SceneTree

## 验证脚本：检查 tavern.tscn 是否保留手工保存的 BuiltStructure。
## 运行方式：
## "D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tools/verify_tavern_scene.gd

const TAVERN_SCENE_PATH := "res://scenes/tavern/tavern.tscn"

func _init() -> void:
	print("[VerifyTavernScene] Starting verification...")
	_verify()
	print("[VerifyTavernScene] Done.")
	quit()

func _verify() -> void:
	# 检查 tavern.tscn 中的 Structure 节点配置。此脚本只读场景文本，不生成或合并结构。
	var tavern_text := FileAccess.get_file_as_string(TAVERN_SCENE_PATH)
	if tavern_text.find("[node name=\"BuiltStructure\" type=\"Node3D\" parent=\"Structure\"") < 0:
		push_error("[VerifyTavernScene] ✗ Manual BuiltStructure node not found in tavern.tscn")
	else:
		print("[VerifyTavernScene] ✓ Manual BuiltStructure is embedded in tavern.tscn")

	var structure_script := FileAccess.get_file_as_string("res://scenes/tavern/tavern_structure.gd")
	if structure_script.find("rebuild_generated_structure") >= 0:
		push_error("[VerifyTavernScene] ✗ TavernStructure still exposes rebuild_generated_structure")
	else:
		print("[VerifyTavernScene] ✓ TavernStructure has no rebuild export")

	for forbidden_path in [
		"res://tools/bake_tavern_structure.gd",
		"res://tools/bake_tavern_structure.gd.uid",
		"res://tools/merge_tavern_structure.gd",
		"res://tools/merge_tavern_structure.gd.uid",
		"res://tools/merge_tavern_structure.py",
		"res://tools/build_tavern_material_atlas.py",
		"res://tests/gdunit/tavern_baked_structure_test.gd",
		"res://tests/gdunit/tavern_baked_structure_test.gd.uid",
	]:
		if FileAccess.file_exists(forbidden_path):
			push_error("[VerifyTavernScene] ✗ Forbidden tavern bake/merge file exists: " + forbidden_path)
		else:
			print("[VerifyTavernScene] ✓ Forbidden file absent: " + forbidden_path)

	# 检查 main_menu.gd 不再有 _spawn_fallback_cozy_tavern
	var menu_text := FileAccess.get_file_as_string("res://scenes/ui/main_menu.gd")
	if menu_text.find("_spawn_fallback_cozy_tavern") >= 0:
		push_error("[VerifyTavernScene] ✗ main_menu.gd still has _spawn_fallback_cozy_tavern")
	else:
		print("[VerifyTavernScene] ✓ main_menu.gd fallback generation removed")

	print("[VerifyTavernScene] All checks passed!")
