extends Node

## 全局设置（持久化到 user://settings.cfg）。
## 目前承载 show_fps（FPS 显示开关）、pixel_shader_enabled（全局像素着色开关）
## 与 camera_impact_enabled（镜头冲击强度开关）。
## 注意：autoload 脚本禁止 class_name（同名单例冲突会隐藏 autoload 单例），
## 因此本脚本不写 class_name，运行时通过全局名 "Settings" 引用。

const SAVE_PATH := "user://settings.cfg"
const SECTION := "video"
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")

var show_fps: bool = false
## 全局像素着色开关。true 时体素模型走 toon/量化着色；false 时保持 GLB 原始材质。
var pixel_shader_enabled: bool = true
## 镜头冲击强度开关（B2）。true 时命中/受击会给 MainCamera 施加低幅度旋转冲击；
## false 时完全禁用镜头冲击，仅保留相机抖动等既有反馈。
var camera_impact_enabled: bool = true
signal settings_changed

func _ready() -> void:
	_load()
	# 启动时把持久化的开关同步到适配器，确保新加载的场景遵循用户偏好。
	VOXEL_LIGHTING.set_pixel_shader_enabled(pixel_shader_enabled)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		show_fps = cfg.get_value(SECTION, "show_fps", false)
		pixel_shader_enabled = cfg.get_value(SECTION, "pixel_shader_enabled", true)
		camera_impact_enabled = cfg.get_value(SECTION, "camera_impact_enabled", true)

## 设置 FPS 显示开关并持久化；值变化才写盘并广播，避免无谓 IO。
func set_show_fps(enabled: bool) -> void:
	if show_fps == enabled:
		return
	show_fps = enabled
	_save()
	settings_changed.emit()

## 设置镜头冲击强度开关并持久化。MainCamera 在播放冲击前查询该值，
## 关闭时跳过冲击旋转，保留既有抖动反馈。
func set_camera_impact_enabled(enabled: bool) -> void:
	if camera_impact_enabled == enabled:
		return
	camera_impact_enabled = enabled
	_save()
	settings_changed.emit()

## 设置全局像素着色开关并持久化。
## 更新适配器内部状态并清空材质缓存：缓存的 toon 材质在开关关闭后不应复用。
## 不遍历当前场景：设置菜单是纯 UI Control，体素着色效果在下一个含 3D 模型的
## 场景加载时由 World.load_space / main_menu._setup_3d_background 等调用方自动应用。
func set_pixel_shader_enabled(enabled: bool) -> void:
	if pixel_shader_enabled == enabled:
		return
	pixel_shader_enabled = enabled
	VOXEL_LIGHTING.set_pixel_shader_enabled(enabled)
	# 清空适配器缓存：开关切换后，缓存的 toon StandardMaterial3D 不应被
	# 新加载的场景复用。各场景加载时会重新调用 apply_to_tree。
	VOXEL_LIGHTING.clear_cache()
	_save()
	settings_changed.emit()

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # 文件不存在时忽略错误，后续 save 新建
	cfg.set_value(SECTION, "show_fps", show_fps)
	cfg.set_value(SECTION, "pixel_shader_enabled", pixel_shader_enabled)
	cfg.set_value(SECTION, "camera_impact_enabled", camera_impact_enabled)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("[Settings] 保存设置失败: " + str(err))
