class_name PlayerStateData

var damage: int
var impact_direction: Vector3

func set_damage(dmg: int) -> PlayerStateData:
	damage = dmg
	return self

func set_impact_direction(direction: Vector3) -> PlayerStateData:
	impact_direction = direction
	return self
