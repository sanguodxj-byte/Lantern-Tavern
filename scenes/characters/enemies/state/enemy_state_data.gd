class_name EnemyStateData

var damage: int
var impulse: Vector3
var thrown_item: ThrownItem
var thrown_item_basis: Basis

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
