class_name ManaComponent
extends Node

## 蓝量组件（法力/精力）—— 与 HealthComponent 对称的资源组件。
## 由 CombatHUD 自动注入到 Player，支持被动回复与技能消耗。

@export var max_mana: int = 100
@export var current_mana: int = 100
@export var regen_per_sec: float = 5.0

var _accumulated: float = 0.0


func _process(delta: float) -> void:
	regen(delta)


## 被动回复蓝量（按帧累计小数，到 1 才入账）
func regen(delta: float) -> void:
	if current_mana >= max_mana:
		_accumulated = 0.0
		return
	_accumulated += regen_per_sec * delta
	while _accumulated >= 1.0 and current_mana < max_mana:
		current_mana = mini(current_mana + 1, max_mana)
		_accumulated -= 1.0


## 消耗蓝量，成功返回 true，不足返回 false
func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if current_mana < amount:
		return false
	current_mana -= amount
	return true


## 恢复蓝量
func restore(amount: int) -> void:
	current_mana = clampi(current_mana + amount, 0, max_mana)


## 设置最大蓝量并修正当前值
func set_max(new_max: int) -> void:
	max_mana = maxi(new_max, 1)
	current_mana = clampi(current_mana, 0, max_mana)


## 蓝量比例 (0.0 ~ 1.0)
func ratio() -> float:
	if max_mana <= 0:
		return 0.0
	return float(current_mana) / float(max_mana)
