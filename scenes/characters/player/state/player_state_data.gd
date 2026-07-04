class_name PlayerStateData

var damage: int
var impact_direction: Vector3
var knockback_force: float = 0.0  # ARPG 实时击退力（米/秒），0 表示用状态默认值
var grabbed_enemy: Node = null   # 抓取技能目标敌人（GRABBING 状态用）

func set_damage(dmg: int) -> PlayerStateData:
	damage = dmg
	return self

func set_impact_direction(direction: Vector3) -> PlayerStateData:
	impact_direction = direction
	return self

func set_knockback_force(force: float) -> PlayerStateData:
	knockback_force = force
	return self

func set_grabbed_enemy(enemy: Node) -> PlayerStateData:
	grabbed_enemy = enemy
	return self

func get_grabbed_enemy() -> Node:
	return grabbed_enemy
