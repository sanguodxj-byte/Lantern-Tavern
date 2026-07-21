extends Node

## 全局设置（持久化到 user://settings.cfg）。
## 目前承载 show_fps（FPS 显示开关）。
## 注意：autoload 脚本禁止 class_name（同名单例冲突会隐藏 autoload 单例），
## 因此本脚本不写 class_name，运行时通过全局名 "Settings" 引用。

const SAVE_PATH := "user://settings.cfg"
const SECTION := "video"

var show_fps: bool = false
signal settings_changed

func _ready() -> void:
	_load()

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		show_fps = cfg.get_value(SECTION, "show_fps", false)

## 设置 FPS 显示开关并持久化；值变化才写盘并广播，避免无谓 IO。
func set_show_fps(enabled: bool) -> void:
	if show_fps == enabled:
		return
	show_fps = enabled
	_save()
	settings_changed.emit()

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # 文件不存在时忽略错误，后续 save 新建
	cfg.set_value(SECTION, "show_fps", show_fps)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("[Settings] 保存设置失败: " + str(err))
