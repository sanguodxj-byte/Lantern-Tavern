class_name PlayerStateData

var damage: int
var impact_direction: Vector3
var knockback_force: float = 0.0  # ARPG 实时击退力（米/秒），0 表示用状态默认值
var grabbed_enemy: Node = null   # 抓取技能目标敌人（GRABBING 状态用）
var weapon_input_action: String = ""
var weapon_attack_hand: String = "primary"
var weapon_release_state: int = -1
var weapon_charge_started_msec: int = 0

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

func set_weapon_attack(input_action: String, attack_hand: String, release_state: int) -> PlayerStateData:
	weapon_input_action = input_action
	weapon_attack_hand = attack_hand
	weapon_release_state = release_state
	weapon_charge_started_msec = Time.get_ticks_msec()
	return self
