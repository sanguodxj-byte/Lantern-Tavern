class_name PixelView
extends SubViewportContainer
## 复古像素 3D 视图（方案2：低分辨率渲染 + 最近邻放大）。
## SubViewport 共享主视口的 World3D，内部相机每帧同步主视口当前相机；
## 主视口自身关闭 3D 渲染避免双重渲染。UI（CanvasLayer）不受影响，保持全分辨率。

const SHRINK := 4  # 1920/4 = 480，整数倍缩放避免像素抖动

var _viewport: SubViewport
var _camera: Camera3D
var _main_3d_disabled := false


func _ready() -> void:
	process_priority = 100  # 在玩家相机更新之后同步
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	stretch_shrink = SHRINK
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = false
	_viewport.handle_input_locally = false
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	add_child(_viewport)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)


func _process(_delta: float) -> void:
	var source := get_viewport().get_camera_3d()
	if source == null or not is_instance_valid(source):
		return
	if not _main_3d_disabled:
		# 主视口 3D 渲染关闭；相机的 current 状态与 3D 拾取不受影响。
		get_viewport().disable_3d = true
		_main_3d_disabled = true
		_camera.current = true
	_camera.global_transform = source.global_transform
	_camera.projection = source.projection
	_camera.fov = source.fov
	_camera.size = source.size
	_camera.near = source.near
	_camera.far = source.far
	_camera.cull_mask = source.cull_mask
	_camera.h_offset = source.h_offset
	_camera.v_offset = source.v_offset
	_camera.environment = source.environment
	_camera.attributes = source.attributes
