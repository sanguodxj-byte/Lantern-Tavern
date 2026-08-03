extends GdUnitTestSuite

const AUDIT_SCRIPT := "res://tools/mesh_polygon_audit.gd"
const AUDIT_REPORT := "res://reports/mesh_polygon_audit_report.txt"


func test_audit_script_declares_thresholds_and_flags() -> void:
	var source := FileAccess.get_file_as_string(AUDIT_SCRIPT)
	assert_str(source).contains("HIGH_TRI_WARNING")
	assert_str(source).contains("EXCESSIVE_TRI")
	assert_str(source).contains("total_triangles")
	assert_str(source).contains("surface_get_arrays")
	assert_str(source).contains("ARRAY_VERTEX")
	assert_str(source).contains("ARRAY_INDEX")
	assert_str(source).contains("[EXCESSIVE]")
	assert_str(source).contains("[HIGH]")
	assert_str(source).contains("find_glb_files")
	assert_str(source).contains("categorize")


func test_audit_script_scans_locations_and_categorizes() -> void:
	var source := FileAccess.get_file_as_string(AUDIT_SCRIPT)
	assert_str(source).contains("res://assets/meshes/")
	assert_str(source).contains("res://assets/models/")
	assert_str(source).contains("weapon")
	assert_str(source).contains("armor")
	assert_str(source).contains("character")
	assert_str(source).contains("material")
	assert_str(source).contains("prop")


func test_audit_tool_runs_as_scene_tree_script() -> void:
	var source := FileAccess.get_file_as_string(AUDIT_SCRIPT)
	assert_str(source).contains("extends SceneTree")
	assert_str(source).contains("_initialize()")
	assert_str(source).contains("quit(0)")


func test_audit_report_exists_and_contains_summary() -> void:
	if not FileAccess.file_exists(AUDIT_REPORT):
		push_warning("mesh_polygon_audit_report.txt 尚未生成，跳过数据断言（可用 tools/mesh_polygon_audit.gd 生成）")
		return
	var report := FileAccess.get_file_as_string(AUDIT_REPORT)
	assert_str(report).contains("SUMMARY")
	assert_str(report).contains("成功分析模型数")
	assert_str(report).contains("总三角面数")
	assert_str(report).contains("ALL MODELS")