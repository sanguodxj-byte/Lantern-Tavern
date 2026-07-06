class_name SnareTrap
extends Area3D

const SLOW_DURATION_SEC := 2.5
const SLOW_PERCENT := 45

func _ready() -> void:
	body_entered.connect(on_body_entered)


func on_body_entered(body: Node3D) -> void:
	if body is Enemy and body.has_method("apply_combat_debuff"):
		body.apply_combat_debuff("slow", SLOW_DURATION_SEC, SLOW_PERCENT)
	elif body is Player and body.has_method("add_combat_buff"):
		body.add_combat_buff("slow_and_haste", SLOW_DURATION_SEC, {"slow_target": SLOW_PERCENT, "haste_self": 0})
