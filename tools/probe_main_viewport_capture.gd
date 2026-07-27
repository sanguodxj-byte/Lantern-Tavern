extends SceneTree
## 最小验证：headless 下，root viewport texture.get_image() 能否拿到非空内容。
## 用 90 帧 _process 后读 root.get_texture().get_image() 并保存。
## 不动任何场景，纯测渲染管线。

const OUT_ABS := "D:/123/Lantern Tavern/reports/ui_runtime/probe_main_viewport.png"
const OUT_LOG := "D:/123/Lantern Tavern/reports/ui_runtime/probe_stderr.log"

var _log_file: FileAccess = null
var _frames: int = 0

func _log(msg: String) -> void:
	printerr(msg)
	if _log_file == null:
		_log_file = FileAccess.open(OUT_LOG, FileAccess.WRITE)
	if _log_file != null:
		_log_file.store_line(msg)
		_log_file.flush()

func _initialize() -> void:
	_log("[Probe] _initialize, root size=%s" % str(root.size))
	root.size = Vector2i(1920, 1080)
	# 加一个 Camera3D 看到一些东西
	var cam := Camera3D.new()
	cam.name = "ProbeCamera"
	root.add_child(cam)
	cam.position = Vector3(0, 1.6, 0)
	cam.make_current()
	# 放一盏灯
	var light := DirectionalLight3D.new()
	root.add_child(light)
	# 放一个 cube
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	cube.position = Vector3(0, 0, -3)
	root.add_child(cube)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_log("[Probe] frame 1, root size=%s, root.get_texture()=%s" % [str(root.size), str(root.get_texture())])
	if _frames == 30:
		RenderingServer.force_sync()
		RenderingServer.force_draw()
		_log("[Probe] frame 30 forced draw")
	if _frames < 90:
		return false
	# 截 root.get_texture()
	var tex := root.get_texture()
	if tex == null:
		_log("[Probe] FATAL: root.get_texture() null at frame 90")
		quit(2)
		return true
	_log("[Probe] frame 90: tex size=%s, rid valid=%s" % [str(tex.get_size()), str(tex.get_rid().is_valid())])
	# 多取几次，看是否需要 force_draw
	for i in range(3):
		var img := tex.get_image()
		if img != null and not img.is_empty():
			_log("[Probe] iter %d: img size=%s, sample pixel=%s" % [i, str(img.get_size()), str(img.get_pixel(img.get_width()/2, img.get_height()/2))])
			var err := img.save_png(OUT_ABS)
			_log("[Probe] save_png err=%d, file=%s" % [err, OUT_ABS])
			quit(0)
			return true
		_log("[Probe] iter %d: empty image, retrying after force_draw" % i)
		RenderingServer.force_sync()
		RenderingServer.force_draw()
		await process_frame
	_log("[Probe] FATAL: image still empty after 3 tries")
	quit(3)
	return true
