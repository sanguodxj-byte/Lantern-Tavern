class_name EnemyStateData

var damage: int
var impact_direction: Vector3
var impulse: Vector3
var knockback_force: float
var thrown_item: ThrownItem
var thrown_item_basis: Basis
## 是否暴击（供伤害飘字等表现层使用）
var is_crit: bool = false

func set_thrown_item(source: ThrownItem) -> EnemyStateData:
	thrown_item = source
	return self
	
func set_thrown_item_basis(basis: Basis) -> EnemyStateData:
	thrown_item_basis = basis
	return self
	
func set_impulse(source: Vector3) -> EnemyStateData:
	impulse = source
	return self

func set_damage(dmg: int) -> EnemyStateData:
	damage = dmg
	return self

func set_impact_direction(direction: Vector3) -> EnemyStateData:
	impact_direction = direction
	return self

func set_knockback_force(force: float) -> EnemyStateData:
	knockback_force = force
	return self

func set_crit(crit: bool) -> EnemyStateData:
	is_crit = crit
	return self
