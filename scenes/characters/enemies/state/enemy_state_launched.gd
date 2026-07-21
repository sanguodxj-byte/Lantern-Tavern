class_name EnemyStateLaunched
extends EnemyState

## 致命击退飞行态（Barony 风格：被打飞到墙上再四散）。
## 敌人受到“致命击退”后，不直接进入 DYING，而是保持物理推进飞行，
## 直到撞到墙/天花板或落地且击退衰减停稳（或飞行超时）才结算死亡，
## 让布娃娃 / 体素碎裂从撞击点四散。

const WALL_IMPACT_MAX_NORMAL_Y := 0.65  # 与 physical_impact_resolver 一致：法线 y>0.65 视为地面
const SETTLE_SPEED := 0.6
const PUSHBACK_SETTLE := 0.5
const MIN_FLIGHT_MSEC := 120
const MAX_FLIGHT_TIME := 2.0

var time_start := Time.get_ticks_msec()
var _resolved := false

func _enter_tree() -> void:
	# 已进入死亡流程：本状态自行监听撞墙结算死亡，关闭物理撞击伤害的自触发切换，
	# 避免 _check_physical_impact_damage 对已 dead 的敌人重复结算。
	enemy.physical_impact_enabled = false
	if enemy.animation_player != null and enemy.animation_player.has_animation("hurt"):
		enemy.animation_player.play("hurt")

func _physics_process(_delta: float) -> void:
	enemy.process_movement(_delta)
	_evaluate_contact()
	if not _resolved:
		_watch_timeout()

## 撞击评估：撞墙/天花板立即结算；落地且击退衰减停稳也结算。
func _evaluate_contact() -> void:
	if _resolved or Time.get_ticks_msec() - time_start < MIN_FLIGHT_MSEC:
		return
	var wall_normal := _find_wall_normal()
	if not wall_normal.is_zero_approx():
		_resolve(wall_normal)
		return
	if enemy.is_on_floor() and enemy.velocity.length() < SETTLE_SPEED \
			and enemy.pushback_force.length() < PUSHBACK_SETTLE:
		_resolve_settled()

## 遍历 slide collision，返回最“水平”的墙体/天花板法线（排除地面，与物理撞击结算一致）。
func _find_wall_normal() -> Vector3:
	var best := Vector3.ZERO
	var best_horiz := 1.0
	for i in range(enemy.get_slide_collision_count()):
		var c := enemy.get_slide_collision(i)
		if c == null:
			continue
		var n := c.get_normal()
		if n.y > WALL_IMPACT_MAX_NORMAL_Y:
			continue
		var horiz := Vector2(n.x, n.z).length()
		if horiz < best_horiz:
			best_horiz = horiz
			best = n
	return best

func _watch_timeout() -> void:
	if Time.get_ticks_msec() - time_start > int(MAX_FLIGHT_TIME * 1000.0) and not _resolved:
		_resolve_settled()

## 撞墙/天花板结算：沿撞击法线方向（与 _apply_physical_impact_damage 同号约定）四散。
func _resolve(normal: Vector3) -> void:
	_resolved = true
	transition_state(Enemy.State.DYING, compute_death_data(normal))

## 无墙结算（落地停稳 / 飞行超时）：原地轻抛四散。
func _resolve_settled() -> void:
	_resolved = true
	transition_state(Enemy.State.DYING, compute_death_data(Vector3.UP))

## 计算从撞击点结算死亡所用的状态数据：撞墙沿法线四散（与 _apply_physical_impact_damage 同号约定），
## 无墙（传入 Vector3.ZERO / Vector3.UP 哨兵）则原地轻抛。供 transition 与单测复用。
func compute_death_data(normal: Vector3) -> EnemyStateData:
	var data := EnemyStateData.new()
	if normal == Vector3.ZERO or normal == Vector3.UP:
		data.set_impact_direction(Vector3.ZERO)
		data.set_impulse(Vector3.UP * 80.0)
	else:
		var impact_dir := (-normal).normalized()
		data.set_impact_direction(impact_dir)
		data.set_impulse(impact_dir * 120.0 + Vector3.UP * 80.0)
	return data

## 外部 / 测试可调用：模拟撞墙，立即结算死亡并从给定墙法线方向四散。
## 传入 Vector3.UP 表示“无墙原地结算”。
func trigger_wall_impact(normal: Vector3 = Vector3.UP) -> void:
	if _resolved:
		return
	if normal == Vector3.UP:
		_resolve_settled()
	else:
		_resolve(normal)

func can_die() -> bool:
	return false

func can_get_hurt() -> bool:
	return false
