class_name SaveSection
extends RefCounted

## 存档领域分区协议（ADR-005）。
## 持久化领域自声明 schema/序列化/反序列化/重置；SaveManager 只编排注册表、
## 版本迁移与槽位 IO——不再在中央文件逐领域 if/has_method 聚合。
##
## 迁移方式（ADR-005 决策 2）：每轮功能改动迁移一个领域；未迁移领域保留
## SaveManager 旧路径，迁移领域经 sections 注册表读写，两者并存兼容。
##
## 生命周期：由 SaveManager（组合根）在 _ready 注册；被注册领域持有对
## 对应 autoload 的引用或经 Service 访问。

## 全局唯一分区键（存档 JSON 中 data["sections"][key]）。
var section_key: String = ""

## 序列化本领域为可 JSON 化字典（不含 section_key 包装）。
func serialize() -> Dictionary:
	return {}

## 从字典恢复本领域（未知字段忽略；缺省按领域默认）。
func deserialize(_data: Dictionary) -> void:
	pass

## 新游戏重置本领域到初始状态。
func reset() -> void:
	pass
