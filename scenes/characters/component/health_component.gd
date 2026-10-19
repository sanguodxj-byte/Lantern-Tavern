class_name HealthComponent
extends Node

@export var max_life: int
@export var current_life: int

func take_damage(damage: int) -> void:
	current_life = clampi(current_life - damage, 0, max_life)

func heal(amount: int) -> void:
	current_life = clampi(current_life + amount, 0, max_life)

func is_dead() -> bool:
	return current_life == 0

## 权威镜像：设置最大生命（至少 1），并修正当前生命不越界。
## P1/A3 修复：联机客户端经此同步服务器权威 max_life。
func set_max_life(value: int) -> void:
	max_life = maxi(value, 1)
	current_life = clampi(current_life, 0, max_life)

## 权威镜像：设置当前生命（封顶 max_life，下限 0）。
## P1/A3 修复：联机客户端经此同步服务器权威 current_life。
func set_current_life(value: int) -> void:
	current_life = clampi(value, 0, max_life)
