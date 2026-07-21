class_name UiScreen
extends Control

## 所有“页面型” UI 的最小生命周期契约。
## 页面脚本只负责呈现与发出意图，导航由 UiNavigation 统一处理。

signal opened(payload: Dictionary)
signal closed(result: Dictionary)
signal navigation_requested(route: StringName, payload: Dictionary)

enum Lifecycle {
	CLOSED,
	OPEN,
}

var lifecycle: Lifecycle = Lifecycle.CLOSED
var screen_payload: Dictionary = {}


func _ready() -> void:
	# 场景直接作为主场景运行时可能默认 visible；此时视为已打开，
	# 但不重复触发 opened，避免场景实例化产生伪生命周期事件。
	lifecycle = Lifecycle.OPEN if visible else Lifecycle.CLOSED
	configure_screen()
	if not navigation_requested.is_connected(_on_navigation_requested):
		navigation_requested.connect(_on_navigation_requested)


## 页面只在这里集中声明默认配置点；子页面不需要重写 _ready() 来拼接生命周期逻辑。
func configure_screen() -> void:
	pass


func open(payload: Dictionary = {}) -> void:
	screen_payload = payload.duplicate(true)
	lifecycle = Lifecycle.OPEN
	visible = true
	on_screen_opened(screen_payload.duplicate(true))
	opened.emit(screen_payload.duplicate(true))


func close(result: Dictionary = {}) -> void:
	lifecycle = Lifecycle.CLOSED
	visible = false
	on_screen_closed(result.duplicate(true))
	closed.emit(result.duplicate(true))


func request_navigation(route: StringName, payload: Dictionary = {}) -> void:
	navigation_requested.emit(route, payload.duplicate(true))


func _on_navigation_requested(route: StringName, payload: Dictionary) -> void:
	UiNavigation.navigate(route, payload)


func is_open() -> bool:
	return lifecycle == Lifecycle.OPEN


func payload() -> Dictionary:
	return screen_payload.duplicate(true)


## 子页面的呈现 seam。保持接口小，便于页面通过测试直接驱动。
func on_screen_opened(_payload: Dictionary) -> void:
	pass


func on_screen_closed(_result: Dictionary) -> void:
	pass
