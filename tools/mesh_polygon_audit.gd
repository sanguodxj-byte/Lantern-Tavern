#!/usr/bin/env -S godot -s
extends SceneTree

## Mesh Polygon Audit Tool
##
## Scans all GLB model files in the project and reports:
##   - Per-model triangle count, vertex count, surface count
##   - Category breakdown (character, weapon, prop, armor, etc.)
##   - Flags models with excessive polygons (voxel style should be <2000 tri)
##
## Usage (headless):
##   "D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s res://tools/mesh_polygon_audit.gd
##
## Output: reports/mesh_polygon_audit_report.txt

const OUTPUT_PATH := "res://reports/mesh_polygon_audit_report.txt"
const HIGH_TRI_WARNING := 3000
const EXCESSIVE_TRI := 8000

var _lines: Array[String] = []
var _models: Array[Dictionary] = []
var _cat_stats: Dictionary = {}


func _initialize() -> void:
	print("MESH_AUDIT START")
	_run()
	flush_output()
	await process_frame
	quit(0)


func _run() -> void:
	emit_line("================================================================")
	emit_line("  MESH POLYGON AUDIT REPORT")
	emit_line("  扫描所有 GLB 模型，统计顶点/三角面数")
	emit_line("================================================================")
	emit_line("")

	var glb_files := find_glb_files()
	emit_line("发现 %d 个 GLB 文件" % glb_files.size())
	emit_line("")

	var total_tri := 0
	var total_vert := 0
	var high_models: Array[Dictionary] = []
	var excessive_models: Array[Dictionary] = []
	var total_files := glb_files.size()

	for i in range(total_files):
		var fp := glb_files[i]
		emit_line("  [%d/%d] 正在分析: %s" % [i + 1, total_files, fp])
		var result := analyze_glb(fp)
		if result == null:
			emit_line("  [SKIP] %s — 无法加载" % fp)
			continue
		_models.append(result)
		total_tri += result["total_triangles"]
		total_vert += result["total_vertices"]

		var cat: String = result["category"]
		if not _cat_stats.has(cat):
			_cat_stats[cat] = {"count": 0, "triangles": 0, "vertices": 0}
		_cat_stats[cat]["count"] += 1
		_cat_stats[cat]["triangles"] += result["total_triangles"]
		_cat_stats[cat]["vertices"] += result["total_vertices"]

		if result["total_triangles"] >= EXCESSIVE_TRI:
			excessive_models.append(result)
		elif result["total_triangles"] >= HIGH_TRI_WARNING:
			high_models.append(result)

	# 输出总体统计
	emit_line("")
	emit_line("================================================================")
	emit_line("  SUMMARY")
	emit_line("================================================================")
	emit_line("  成功分析模型数: %d" % _models.size())
	emit_line("  总三角面数: %d" % total_tri)
	emit_line("  总顶点数: %d" % total_vert)
	emit_line("  平均三角面/模型: %.1f" % (float(total_tri) / maxi(_models.size(), 1)))
	emit_line("")

	# 按类别统计
	emit_line("--- 类别三角面统计 ---")
	var cat_sorted: Array[String] = []
	for c in _cat_stats.keys():
		cat_sorted.append(c)
	cat_sorted.sort()
	for cat in cat_sorted:
		var s: Dictionary = _cat_stats[cat]
		var avg := float(s["triangles"]) / maxi(int(s["count"]), 1)
		emit_line("  %s: %d 模型, %d 三角面, avg=%.1f" % [cat, int(s["count"]), int(s["triangles"]), avg])
	emit_line("")

	# 按三角面降序排列所有模型
	_models.sort_custom(func(a, b): return int(a["total_triangles"]) > int(b["total_triangles"]))

	emit_line("================================================================")
	emit_line("  ALL MODELS (sorted by triangle count, descending)")
	emit_line("================================================================")
	for r in _models:
		var flag := ""
		if int(r["total_triangles"]) >= EXCESSIVE_TRI:
			flag = "  [EXCESSIVE]"
		elif int(r["total_triangles"]) >= HIGH_TRI_WARNING:
			flag = "  [HIGH]"
		var pct := float(int(r["total_triangles"])) / float(maxi(total_tri, 1)) * 100.0
		emit_line("  %s|%s| tri=%d vert=%d surf=%d (%.1f%%)%s" % [
			(String(r["category"])).substr(0, 15).rpad(16),
			(String(r["short_name"])).substr(0, 36).rpad(37),
			int(r["total_triangles"]),
			int(r["total_vertices"]),
			int(r["surface_count"]),
			pct,
			flag,
		])

	# 高面数警告
	emit_line("")
	emit_line("================================================================")
	emit_line("  HIGH TRIANGLE MODELS (>%d triangles)" % HIGH_TRI_WARNING)
	emit_line("================================================================")
	if high_models.is_empty() and excessive_models.is_empty():
		emit_line("  无 — 所有模型面数合理")
	else:
		if not excessive_models.is_empty():
			emit_line("")
			emit_line("  >>> EXCESSIVE (>%d triangles):" % EXCESSIVE_TRI)
			for r in excessive_models:
				emit_line("    %s/%s: %d triangles, %d vertices" % [r["category"], r["short_name"], int(r["total_triangles"]), int(r["total_vertices"])])
		if not high_models.is_empty():
			emit_line("")
			emit_line("  >>> HIGH (>%d triangles):" % HIGH_TRI_WARNING)
			for r in high_models:
				emit_line("    %s/%s: %d triangles, %d vertices" % [r["category"], r["short_name"], int(r["total_triangles"]), int(r["total_vertices"])])

	emit_line("")
	emit_line("================================================================")
	emit_line("  NOTES")
	emit_line("================================================================")
	emit_line("  - 体素风格模型通常每个体素块 = 12-24 三角面 (2-12 quad)")
	emit_line("  - 30px 级别角色 = 约 500-1500 triangles 为正常")
	emit_line("  - 50px 级别角色 = 约 1000-3000 triangles 为正常")
	emit_line("  - 80px 级别角色 = 约 2000-5000 triangles 为正常")
	emit_line("  - 龙(256px)作为BOSS可能有 5000-15000 triangles")
	emit_line("  - 如果模型面数异常高，可能是网格未合并或布线不合理")
	emit_line("")


func find_glb_files() -> Array[String]:
	var result: Array[String] = []
	var dirs := ["res://assets/meshes/", "res://assets/models/"]
	for d in dirs:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		result.append_array(walk_dir_for_glb(dir, d))
	result.sort()
	return result


func walk_dir_for_glb(dir: DirAccess, base_path: String) -> Array[String]:
	var result: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var full := base_path.trim_suffix("/") + "/" + fname
		if dir.current_is_dir():
			var sub := DirAccess.open(full)
			if sub != null:
				result.append_array(walk_dir_for_glb(sub, full))
		elif fname.ends_with(".glb"):
			result.append(full)
		fname = dir.get_next()
	dir.list_dir_end()
	return result


func categorize(path: String) -> String:
	var lower := path.to_lower()
	if "character" in lower or "voxel_" in lower:
		if "player" in lower:
			return "player"
		if "dragon" in lower:
			return "boss"
		return "character"
	if "weapon" in lower:
		return "weapon"
	if "armor" in lower:
		return "armor"
	if "shield" in lower:
		return "shield"
	if "prop" in lower:
		return "prop"
	if "material" in lower or "item" in lower:
		return "material"
	if "trap" in lower:
		return "trap"
	if "environment" in lower:
		return "environment"
	if "projectile" in lower:
		return "projectile"
	if "door" in lower:
		return "door"
	if "wall" in lower:
		return "wall"
	if "collectible" in lower:
		return "collectible"
	return "other"


func short_name(full_path: String) -> String:
	var parts := full_path.split("/")
	var fname := parts[-1] if parts.size() > 0 else full_path
	return fname.trim_suffix(".glb")


func analyze_glb(res_path: String) -> Dictionary:
	var res := ResourceLoader.load(res_path)
	if res == null:
		return make_result(res_path, 0, 0, 0)

	# 收集 Mesh 资源引用（不是 MeshInstance3D 节点）。Mesh 是缓存资源，
	# 即使实例节点被 free() 也仍有效，可安全在实例释放后统计。
	var meshes: Array[Mesh] = []

	if res is PackedScene:
		var inst: Node = res.instantiate()
		if inst == null:
			return make_result(res_path, 0, 0, 0)
		inst.name = "AuditInst"
		root.add_child(inst)
		collect_meshes(inst, meshes)
		root.remove_child(inst)
		inst.free()
	elif res is Mesh:
		meshes.append(res as Mesh)
	else:
		return make_result(res_path, 0, 0, 0)

	if meshes.is_empty():
		return make_result(res_path, 0, 0, 0)

	var total_tri := 0
	var total_vert := 0
	var total_surf := 0
	var seen_meshes: Dictionary = {}

	for mesh in meshes:
		if mesh == null or seen_meshes.has(mesh):
			continue
		seen_meshes[mesh] = true

		var surf_count := mesh.get_surface_count()
		total_surf += surf_count
		for si in range(surf_count):
			var arrays := mesh.surface_get_arrays(si)
			if arrays.is_empty() or arrays.size() < Mesh.ARRAY_MAX:
				continue
			var verts: Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Array = arrays[Mesh.ARRAY_INDEX]
			if indices != null and indices.size() > 0:
				total_tri += indices.size() / 3
			else:
				total_tri += verts.size() / 3
			total_vert += verts.size()

	return make_result(res_path, total_tri, total_vert, total_surf)


func make_result(path: String, tri: int, vert: int, surf: int) -> Dictionary:
	return {
		"file_path": path,
		"short_name": short_name(path),
		"category": categorize(path),
		"total_triangles": tri,
		"total_vertices": vert,
		"surface_count": surf,
	}


func collect_meshes(root_node: Node, out: Array[Mesh]) -> void:
	var stack: Array[Node] = [root_node]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				out.append(mi.mesh)
		for child in node.get_children():
			stack.append(child)


func emit_line(line: String) -> void:
	print(line)
	_lines.append(line)


func flush_output() -> void:
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("MESH_AUDIT could not write %s" % OUTPUT_PATH)
		return
	for line in _lines:
		file.store_line(line)
	file.close()
	print("MESH_AUDIT report written to %s" % OUTPUT_PATH)