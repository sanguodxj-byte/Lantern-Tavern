extends RefCounted
## CommandRouter（docs/25 §3.2 / §11）—— 把经过 CommandValidator 验证的客户端命令
## 路由到对应的服务器权威子系统（Interaction / Combat / Loot / Movement / Dungeon / ...，均属地牢内联机系统）。
##
## 纯逻辑、无场景树依赖。权威处理器由 SessionRoot 在 init 时通过
## register_handler(cmd_type, callable) 注入，便于单测用假处理器替换。
##
## 处理器契约：func handler(command: Dictionary, ctx: PlayerContext) -> Dictionary
##   返回：{"success": bool, "event": Dictionary, "error_code": String}
##   也可直接返回事件字典（将被包裹为 success=true）。
##
## 归属 Phase：3（SessionRoot 配套）。不声明 class_name，规避 headless 类注册/uid 问题。

const ERROR_NO_HANDLER := "INVALID_STATE"
const ERROR_BAD_COMMAND := "INVALID_TARGET"

var _handlers: Dictionary

func _init() -> void:
	# 引用类型必须在 _init 内按实例独立初始化：
	# GDScript 类级 `= {}` 字面量会被所有实例共享，导致多玩家路由表相互污染。
	_handlers = {}

## 注册某命令类型的处理器（SessionRoot 在 init 阶段调用）。
func register_handler(command_type: String, handler: Callable) -> void:
	if command_type == "" or not handler.is_valid():
		return
	_handlers[command_type] = handler

func unregister_handler(command_type: String) -> void:
	_handlers.erase(command_type)

func has_handler(command_type: String) -> bool:
	return _handlers.has(command_type)

## 路由一条命令。command 必须含 "type" 字段（字符串）。
## 找不到处理器 → command_rejected(INVALID_STATE)。
## 找到 → 调用处理器并以包裹结构返回其结果（兼容处理器直接返回事件字典）。
func route(command: Dictionary, ctx: PlayerContext) -> Dictionary:
	if not command.has("type") or not (command["type"] is String):
		return {"success": false, "event": {}, "error_code": ERROR_BAD_COMMAND}
	var cmd_type: String = command["type"]
	if not _handlers.has(cmd_type):
		return {"success": false, "event": {}, "error_code": ERROR_NO_HANDLER}
	var handler: Callable = _handlers[cmd_type]
	var out = handler.call(command, ctx)
	if out is Dictionary and out.has("success"):
		return out
	# 兼容：处理器直接返回事件字典 → 包裹为 success=true
	return {"success": true, "event": (out if out is Dictionary else {}), "error_code": ""}
