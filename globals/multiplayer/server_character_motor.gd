class_name ServerCharacterMotor
extends RefCounted

## 服务器权威移动马达（ServerCharacterMotor，架构审查 P0-1）。
##
## 背景：服务器移动曾经只是坐标数学积分（old_pos + dir * speed * dt），不使用碰撞世界，
## 客户端持续提交合法方向输入即可穿过墙/门/障碍（服务器权威积分 ≠ 服务器权威移动）。
##
## 本马达把「输入 → 权威位移」交给真实物理：
##   * 物理模式：绑定真实 CharacterBody3D（房主真实 Player / 远端 avatar），调用
##     move_and_slide()，由地牢碰撞几何约束位移——墙前持续输入不穿墙、门关闭不可穿过；
##   * 纯积分模式：无碰撞世界（headless 纯逻辑单测 / 无几何专用服务器）的确定性回退，
##     与旧 MovementAuthority.integrate_position 语义一致（自由移动，等价空碰撞空间）。
##
## MovementAuthority 只负责输入校验与速率政策（速度由调用方传入），
## 最终权威坐标由本马达产出。纯 RefCounted，可单测。

## 物理模式：经 move_and_slide 计算权威位移。
## body: CharacterBody3D（须已挂树且处于启用物理的世界，碰撞层/掩码已按玩家配置）。
## move_vec: 世界空间输入向量（x, z），分量已在 MovementAuthority 校验过 [-1,1] 且模长 <=1。
## sprint: 是否加速；dt: 服务器固定步长；speed: 速率政策输出（米/秒）。
## 返回 {"position": Vector3, "moved": Vector3, "collided": bool, "is_floor": bool}。
func move_body(body: CharacterBody3D, move_vec: Vector2, sprint: bool, dt: float, speed: float) -> Dictionary:
	var dir := Vector3(move_vec.x, 0.0, move_vec.y)
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	var old_pos: Vector3 = body.global_position
	body.velocity = dir * speed
	body.move_and_slide()
	return {
		"position": body.global_position,
		"moved": body.global_position - old_pos,
		"collided": body.get_slide_collision_count() > 0,
		"is_floor": body.is_on_floor(),
	}

## 纯积分：无碰撞世界的确定性回退（与旧 MovementAuthority.integrate_position 语义一致）。
func integrate_position(old_pos: Vector3, move_vec: Vector2, dt: float, speed: float) -> Vector3:
	if dt <= 0.0:
		return old_pos
	var dir := Vector3(move_vec.x, 0.0, move_vec.y)
	return old_pos + dir * speed * dt
