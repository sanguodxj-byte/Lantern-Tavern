extends GdUnitTestSuite
## 场景冒烟测试 —— 属性错误的 CI 闸门。
##
## 背景：GDScript 解析器无法在编译期校验属性名是否存在于目标类型，
## `btn.text_vertical_alignment = ...` 这类“语法合法、语义非法”的赋值
## 只有真正实例化场景并执行 _ready() 时才会被 Object.set() 拒绝并抛出
## "Invalid assignment of property or key ..." 运行时错误。
##
## 本测试用一个自定义 Logger (OS.add_logger) 捕获 ERROR_TYPE_SCRIPT /
## ERROR_TYPE_ERROR，对每个独立场景实例化后断言零错误，让这类 bug 在
## CI 阶段自动失败，绝不进入手动运行时排错。
##
## 扩展：新增独立可实例化的根场景时，把路径加进 SCENES 白名单即可。
## （子面板 / 组件型场景若依赖父节点路径，不应加入，以免误报。）

# 独立可实例化的 UI 根场景白名单。
const SCENES := [
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/zone_select.tscn",
	"res://scenes/ui/tavern_ui.tscn",
	"res://scenes/ui/model_viewer.tscn",
	"res://scenes/ui/character_panel.tscn",
	"res://scenes/ui/pause_menu.tscn",
	"res://scenes/ui/ui.tscn",
	"res://scenes/ui/expedition_hud.tscn",
]

var _collector: _ErrorCollector


func before_test() -> void:
	_collector = _ErrorCollector.new()


func test_all_scenes_instantiate_without_errors() -> void:
	var failures: Array[String] = []
	for path in SCENES:
		_collector.clear()
		var packed := load(path) as PackedScene
		if packed == null:
			failures.append("%s:\n  -> 无法加载场景" % path)
			continue
		var inst := packed.instantiate()
		if inst == null:
			failures.append("%s:\n  -> 无法实例化场景" % path)
			continue
		# 挂到 root 触发 _ready()；属性错误在此时被捕获。
		Engine.get_main_loop().root.add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		inst.queue_free()
		await get_tree().process_frame
		if _collector.has_errors():
			var block := "%s:" % path
			for e in _collector.errors():
				block += "\n  -> %s" % str(e)
			failures.append(block)
	# 汇总断言：任一场景报错即失败，并列出全部出错场景与错误信息。
	var report := ""
	for f in failures:
		report += f + "\n\n"
	assert_bool(failures.is_empty()) \
		.override_failure_message("以下场景实例化时触发脚本错误（属性/节点/信号误用等），请修复后再提交:\n" + report) \
		.is_true()


# 自定义 Logger：镜像 gdUnit4 的 GdUnitScriptErrorCollector 模式，
# 捕获脚本错误与引擎错误，供断言查询。
class _ErrorCollector extends Logger:
	var _errors: Array[String] = []

	func _init() -> void:
		OS.add_logger(self)

	func _log_error(
		_function: String,
		_source_file: String,
		_source_line: int,
		message: String,
		_rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array
		) -> void:
		if error_type == ErrorType.ERROR_TYPE_SCRIPT or error_type == ErrorType.ERROR_TYPE_ERROR:
			_errors.append(message)

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func has_errors() -> bool:
		return not _errors.is_empty()

	func errors() -> Array:
		return _errors

	func clear() -> void:
		_errors.clear()
