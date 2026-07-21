extends GdUnitTestSuite

## 无效引用检测测试
## 扫描所有 .tres / .tscn / .gd 文件中的 res:// 路径引用，
## 验证被引用的资源是否实际存在于磁盘上。
## 自动发现断链引用，防止因资产清理 / 移动导致的运行时崩溃。

const SKIP_DIRS := [
	"addons", ".godot", ".godot_udtest", "reports", ".git",
	".catpaw", ".claude", ".workbuddy", "__pycache__",
]
const SKIP_PATH_PREFIXES := [
	"res://reports/",        # 运行时输出路径
	"res://.godot/",         # Godot 导入缓存
	"res://nonexistent",     # 测试中的故意不存在路径
	"res://path1",           # 测试 mock 路径
	"res://path2",]
const FORMAT_SPECIFIER := ["%s", "%d", "%08x", "%x", "%02x", "%03d"]

## 获取项目根目录下的所有需要扫描的文件
func _collect_files(extensions: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	var dir := DirAccess.open("res://")
	if dir == null:
		return result
	_walk(dir, "res://", extensions, result)
	return result

func _walk(dir: DirAccess, base_path: String, extensions: PackedStringArray, result: PackedStringArray) -> void:
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if not file_name.begins_with(".") and not SKIP_DIRS.has(file_name):
				var sub_dir := DirAccess.open(base_path + file_name + "/")
				if sub_dir != null:
					_walk(sub_dir, base_path + file_name + "/", extensions, result)
		else:
			var ext := file_name.get_extension()
			if extensions.has(ext):
				result.append(base_path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

## 判断路径是否应跳过（格式化字符串、输出路径等）
func _should_skip(res_path: String) -> bool:
	for prefix in SKIP_PATH_PREFIXES:
		if res_path.begins_with(prefix):
			return true
	for fmt in FORMAT_SPECIFIER:
		if res_path.contains(fmt):
			return true
	return false

## 从文本行中提取 res:// 路径
func _extract_res_paths(line: String) -> PackedStringArray:
	var paths: PackedStringArray = []
	var search_start := 0
	while true:
		var idx := line.find("res://", search_start)
		if idx < 0:
			break
		# 提取路径直到引号、空格、逗号或行尾
		var end := idx + 6
		while end < line.length():
			var ch := line[end]
			if ch == '"' or ch == "'" or ch == " " or ch == "\t" or ch == "," or ch == ")" or ch == "]" or ch == "\n":
				break
			end += 1
		var path := line.substr(idx, end - idx)
		# 清理尾部反斜杠（如 test 中的转义引号）
		path = path.trim_suffix("\\")
		if not path.is_empty():
			paths.append(path)
		search_start = end
	return paths

## 判断行是否为注释（GDScript 注释或 .tscn/.tres 注释）
func _is_comment_line(line: String) -> bool:
	var trimmed := line.strip_edges(true, false)
	return trimmed.begins_with("#") or trimmed.begins_with(";")

## 判断路径是否在测试中的负向断言（检查不存在）
func _is_negative_assertion(line: String) -> bool:
	return line.contains("not ResourceLoader.exists") or line.contains("ResourceLoader.exists(") and line.contains("is_false")

func test_no_invalid_ext_resource_in_tscn_files() -> void:
	var files := _collect_files(PackedStringArray(["tscn", "tres"]))
	assert_int(files.size()).is_greater(0)
	var invalid: PackedStringArray = []
	for file_path in files:
		var f := FileAccess.open(file_path, FileAccess.READ)
		if f == null:
			continue
		var line_num := 0
		while not f.eof_reached():
			var line := f.get_line()
			line_num += 1
			# 只检查 ext_resource 行
			if not line.contains("ext_resource"):
				continue
			for res_path in _extract_res_paths(line):
				if _should_skip(res_path):
					continue
				if not ResourceLoader.exists(res_path) and not FileAccess.file_exists(res_path):
					invalid.append("%s:%d -> %s" % [file_path, line_num, res_path])
		f.close()
	if not invalid.is_empty():
		var msg := "Invalid ext_resource references found:\n" + "\n".join(invalid)
		assert_bool(false).override_failure_message(msg).is_true()
	else:
		assert_bool(true).is_true()

func test_no_invalid_preload_in_gd_files() -> void:
	var files := _collect_files(PackedStringArray(["gd"]))
	assert_int(files.size()).is_greater(0)
	var invalid: PackedStringArray = []
	for file_path in files:
		# 跳过测试文件中的 mock 路径和 addons
		if file_path.contains("/addons/"):
			continue
		var f := FileAccess.open(file_path, FileAccess.READ)
		if f == null:
			continue
		var line_num := 0
		while not f.eof_reached():
			var line := f.get_line()
			line_num += 1
			# 跳过注释行
			if _is_comment_line(line):
				continue
			# 检查 preload("res://...") 调用
			if line.contains("preload(") or line.contains('preload("'):
				for res_path in _extract_res_paths(line):
					if _should_skip(res_path):
						continue
					if not ResourceLoader.exists(res_path) and not FileAccess.file_exists(res_path):
						invalid.append("%s:%d -> %s" % [file_path, line_num, res_path])
		f.close()
	if not invalid.is_empty():
		var msg := "Invalid preload references found:\n" + "\n".join(invalid)
		assert_bool(false).override_failure_message(msg).is_true()
	else:
		assert_bool(true).is_true()

func test_no_invalid_load_in_gd_files() -> void:
	var files := _collect_files(PackedStringArray(["gd"]))
	assert_int(files.size()).is_greater(0)
	var invalid: PackedStringArray = []
	for file_path in files:
		if file_path.contains("/addons/"):
			continue
		var f := FileAccess.open(file_path, FileAccess.READ)
		if f == null:
			continue
		var line_num := 0
		while not f.eof_reached():
			var line := f.get_line()
			line_num += 1
			if _is_comment_line(line):
				continue
			# 跳过负向断言（测试检查资源不存在的情况）
			if _is_negative_assertion(line):
				continue
			# 检查 load("res://...") 调用
			if line.contains("load(") and not line.contains("preload("):
				for res_path in _extract_res_paths(line):
					if _should_skip(res_path):
						continue
					if not ResourceLoader.exists(res_path) and not FileAccess.file_exists(res_path):
						invalid.append("%s:%d -> %s" % [file_path, line_num, res_path])
		f.close()
	if not invalid.is_empty():
		var msg := "Invalid load references found:\n" + "\n".join(invalid)
		assert_bool(false).override_failure_message(msg).is_true()
	else:
		assert_bool(true).is_true()

func test_critical_shaders_exist() -> void:
	# 验证关键 shader 文件存在
	var critical_shaders := [
		"res://assets/shaders/dungeon_terrain.gdshader",
		"res://assets/shaders/blur_overlay.gdshader",
	]
	for shader_path in critical_shaders:
		assert_bool(ResourceLoader.exists(shader_path)) \
			.override_failure_message("Critical shader missing: %s" % shader_path) \
			.is_true()

func test_critical_textures_exist() -> void:
	# 验证关键 UI 纹理存在
	var critical_textures := [
		"res://assets/textures/tick.png",
		"res://assets/textures/cursor.png",
		"res://assets/textures/icons/icon-heart.png",
		"res://assets/textures/icons/icon-weapon.png",
		"res://assets/textures/icons/icon-shield.png",
	]
	for tex_path in critical_textures:
		assert_bool(ResourceLoader.exists(tex_path)) \
			.override_failure_message("Critical texture missing: %s" % tex_path) \
			.is_true()

func test_audio_manager_sounds_exist() -> void:
	# 验证 AudioManager 引用的所有声音文件存在
	var audio_manager_path := "res://globals/core/audio_manager.tscn"
	var scene := load(audio_manager_path) as PackedScene
	assert_object(scene).is_not_null()
	if scene == null:
		return
	# AudioManager 实例化后检查 sound_files
	var instance := scene.instantiate()
	assert_object(instance).is_not_null()
	if instance == null:
		return
	var sound_files: Array = instance.get("sound_files")
	for stream in sound_files:
		if stream is AudioStream:
			assert_object(stream).is_not_null()
			assert_str(stream.resource_path).is_not_empty()
	instance.queue_free()

func test_no_orphaned_import_files() -> void:
	# 检查是否有孤立的 .import 文件（源文件不存在的 .import）
	var files := _collect_files(PackedStringArray(["import"]))
	var orphaned: PackedStringArray = []
	for import_path in files:
		var f := FileAccess.open(import_path, FileAccess.READ)
		if f == null:
			continue
		while not f.eof_reached():
			var line := f.get_line()
			if line.begins_with("source_file="):
				var source := line.trim_prefix("source_file=").trim_prefix('"').trim_suffix('"')
				if not source.is_empty() and not FileAccess.file_exists(source):
					orphaned.append("%s (source: %s)" % [import_path, source])
				break
		f.close()
	if not orphaned.is_empty():
		var msg := "Orphaned .import files found:\n" + "\n".join(orphaned)
		assert_bool(false).override_failure_message(msg).is_true()
	else:
		assert_bool(true).is_true()
