extends CanvasLayer

## 常驻 FPS 叠层。挂在 World 下，跨越酒馆/地牢。
## 可见性由 Settings.show_fps 控制（设置里开关）；显示时每 ~0.2s 刷新一次帧率。

@onready var label: Label = $Label

var _accum := 0.0

func _ready() -> void:
	if Settings != null:
		visible = Settings.show_fps
		if Settings.has_signal("settings_changed"):
			Settings.settings_changed.connect(_on_settings_changed)
	_refresh()

func _on_settings_changed() -> void:
	if Settings != null:
		visible = Settings.show_fps

func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= 0.2:
		_accum = 0.0
		_refresh()

func _refresh() -> void:
	if label != null:
		label.text = "FPS: %d" % Engine.get_frames_per_second()
