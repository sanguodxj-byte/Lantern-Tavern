extends Node
## PerfMonitor（⑪ 性能压测 HUD）：FPS / 帧耗时 / Draw Call / 网络下发速率，
## 默认隐藏，按 F3 切换显示。仅作开发期观测，不影响游戏逻辑。
##
## 读数来源：
##   * FPS / 帧耗时 —— Engine.get_frames_per_second()
##   * 渲染负载    —— Performance.RENDER_TOTAL_OBJECTS_IN_FRAME / RENDER_TOTAL_PRIMITIVES_IN_FRAME
##                    （与项目既有 dungeon_view_perf_probe.gd 同源稳定 API）
##   * 网络速率   —— NetworkManager.get_net_stats() 每秒增量（消息数/秒）

const NM_PATH := "/root/NetworkManager"

var _layer: CanvasLayer = null
var _label: Label = null
var _visible: bool = false

# 网络速率统计
var _last_net: Dictionary = {}
var _net_rate: float = 0.0
var _net_total: int = 0
var _rate_accum: float = 0.0

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 128
	_layer.name = "PerfHUD"
	add_child(_layer)
	_label = Label.new()
	_label.name = "PerfLabel"
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.position = Vector2(12, 12)
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.4))
	_label.add_theme_font_size_override("font_size", 16)
	_label.visible = false
	_layer.add_child(_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		toggle()

func toggle() -> void:
	_visible = not _visible
	if _label != null:
		_label.visible = _visible

func _process(delta: float) -> void:
	if not _visible or _label == null:
		return
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = (1000.0 / fps) if fps > 0.0 else 0.0

	# 网络速率（每秒增量）
	_rate_accum += delta
	var nm: Node = get_node_or_null(NM_PATH)
	if nm != null and nm.has_method("get_net_stats"):
		var cur: Dictionary = nm.get_net_stats()
		if _rate_accum >= 1.0:
			var inc: int = 0
			for k in cur.keys():
				var v: int = int(cur.get(k, 0))
				var prev: int = int(_last_net.get(k, 0))
				inc += maxi(0, v - prev)
				_last_net[k] = v
			_net_rate = float(inc) / _rate_accum
			_net_total = 0
			for k in cur.keys():
				_net_total += int(cur.get(k, 0))
			_rate_accum = 0.0

	var lines := PackedStringArray()
	lines.append("FPS: %.0f  (%.1f ms)" % [fps, frame_ms])
	lines.append("RenderObjs: %d" % _render_objects())
	lines.append("Primitives: %d" % _render_primitives())
	lines.append("Net: %.0f msg/s  (total %d)" % [_net_rate, _net_total])
	_label.text = "\n".join(lines)

func _render_objects() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))

func _render_primitives() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
