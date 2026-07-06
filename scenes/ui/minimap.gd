class_name CombatMinimap
extends Control

## 旋转小地图（右上角）。
## 棕色=墙体，淡黄色=地面，红色=敌人，玩家=箭头(永远朝上)。
## 小地图跟随视角(yaw)旋转，玩家箭头固定朝上。
## 自动从 ProceduralDungeon._grid 或场景碰撞体获取地图数据。
##
## 性能策略：
##   - 绘制每帧执行（读取玩家位置/朝向，轻量）
##   - 引用刷新 & 碰撞体缓存每 update_interval 秒执行一次（重量级）

@export var map_size: int = 180          # 小地图像素边长
@export var world_radius: float = 25.0   # 可见世界半径(米)
@export var update_interval: float = 0.3  # 数据刷新间隔(秒)——仅影响引用/缓存
@export var bg_alpha: float = 0.55

var _scale: float = 1.0
var _timer: float = 0.0
var _player: Node = null
var _level: Node = null

# 缓存的地图数据
var _cached_grid: Array = []
var _grid_offset: Vector3 = Vector3.ZERO
var _grid_tile_size: float = 3.0
var _has_grid: bool = false

# 缓存的碰撞体 AABB 列表（酒馆/非程序化场景用）
var _cached_colliders: Array[AABB] = []

# 缓存的敌人列表（_refresh_references 节流刷新，_draw 只读）
var _cached_enemies: Array[Enemy] = []

# 颜色常量
const COL_BG := Color(0.04, 0.03, 0.06, 0.55)
const COL_WALL := Color(0.45, 0.30, 0.18, 0.92)
const COL_FLOOR := Color(0.85, 0.78, 0.45, 0.45)
const COL_ENEMY := Color(0.90, 0.12, 0.10, 0.95)
const COL_PLAYER := Color(0.20, 0.85, 0.30, 1.0)
const COL_FRAME := Color(0.25, 0.18, 0.10, 0.85)


func _ready() -> void:
	custom_minimum_size = Vector2(map_size, map_size)
	_scale = (map_size / 2.0) / world_radius
	set_process(true)


func _process(delta: float) -> void:
	# 周期性刷新引用和缓存（重量级操作）
	_timer += delta
	if _timer >= update_interval:
		_timer = 0.0
		_refresh_references()

	# 每帧重绘——只读取玩家位置/朝向，保证旋转丝滑
	queue_redraw()


func _refresh_references() -> void:
	if not is_instance_valid(_player):
		_player = _find_player()
	if not is_instance_valid(_level):
		_level = _find_level()
		_cache_grid_data()
		_cache_colliders()
	# 敌人列表节流刷新（避免 _draw 每帧 get_nodes_in_group 全组扫描）
	_refresh_enemy_cache()


## 刷新敌人缓存：仅保留有效、存活、在树内的敌人
func _refresh_enemy_cache() -> void:
	var raw: Array = get_tree().get_nodes_in_group("enemies")
	_cached_enemies.clear()
	for e in raw:
		if not (e is Enemy):
			continue
		var enemy := e as Enemy
		if not enemy.is_inside_tree():
			continue
		if "state" in enemy and enemy.state == Enemy.State.DEAD:
			continue
		_cached_enemies.append(enemy)


func _find_player() -> Node:
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.get("current_player") and is_instance_valid(gs.get("current_player")):
		return gs.current_player
	return null


func _find_level() -> Node:
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.get("current_level") and is_instance_valid(gs.get("current_level")):
		return gs.current_level
	# fallback: 查找 ProceduralDungeon 或 tavern
	var tree := get_tree()
	if tree and tree.current_scene:
		for n in tree.current_scene.get_children():
			if n is BaseLevel or n.has_method("is_procedural"):
				return n
	return null


func _cache_grid_data() -> void:
	_has_grid = false
	if _level == null or not is_instance_valid(_level):
		return
	if "is_procedural" in _level and _level.is_procedural() and "_grid" in _level:
		_cached_grid = _level._grid
		if "TILE_SIZE" in _level:
			_grid_tile_size = _level.TILE_SIZE
		var gw: int = _cached_grid[0].size() if _cached_grid.size() > 0 else 0
		var gh: int = _cached_grid.size()
		var ox: float = -(float(gw) * _grid_tile_size) / 2.0
		var oz: float = -(float(gh) * _grid_tile_size) / 2.0
		_grid_offset = Vector3(ox, 0, oz)
		_has_grid = true


## 缓存碰撞体 AABB 列表（酒馆/非程序化场景），避免每帧 find_children
func _cache_colliders() -> void:
	_cached_colliders.clear()
	if _level == null or not is_instance_valid(_level):
		return
	var bodies: Array = _level.find_children("*", "StaticBody3D", true, false)
	for body in bodies:
		if not body is StaticBody3D:
			continue
		var col := body as StaticBody3D
		for child in col.get_children():
			if not child is CollisionShape3D:
				continue
			var cs := child as CollisionShape3D
			if cs.shape == null:
				continue
			var aabb := _shape_aabb(cs)
			if aabb.size == Vector3.ZERO:
				continue
			# 转世界 AABB
			var world_aabb := aabb
			var pos := cs.global_position
			if cs.global_position != Vector3.ZERO or cs.rotation != Vector3.ZERO:
				world_aabb = _world_aabb(cs, aabb)
			_cached_colliders.append(world_aabb)


func _draw() -> void:
	if not is_instance_valid(_player):
		return

	var center := size / 2.0
	var yaw: float = _player.rotation.y
	var ppos: Vector3 = _player.global_position

	# 背景：像素风圆形（用方块逐格绘制）
	_draw_pixel_circle_bg(center, map_size / 2.0)

	if _has_grid:
		_draw_grid_map(center, ppos, yaw)
	else:
		_draw_collision_map(center, ppos, yaw)

	# 敌人
	_draw_enemies(center, ppos, yaw)

	# 玩家箭头（永远朝上）
	_draw_player_arrow(center)


## 像素风圆形背景：逐格方块绘制圆内区域 + 像素边框
func _draw_pixel_circle_bg(center: Vector2, radius: float) -> void:
	var r := int(radius)
	var cx := int(center.x)
	var cy := int(center.y)
	var r_sq := r * r
	# 逐行扫描，绘制圆内方块
	for py in range(-r, r + 1):
		var row_w: int = int(sqrt(maxf(r_sq - py * py, 0.0)))
		if row_w <= 0:
			continue
		var draw_y := cy + py
		# 背景填充
		draw_rect(Rect2(cx - row_w, draw_y, row_w * 2, 1), COL_BG, true)
	# 像素边框：绘制圆环上的方块
	for py in range(-r, r + 1):
		var row_w: int = int(sqrt(maxf(r_sq - py * py, 0.0)))
		if row_w <= 0:
			continue
		var draw_y := cy + py
		# 左右边缘像素
		draw_rect(Rect2(cx - row_w, draw_y, 1, 1), COL_FRAME, true)
		draw_rect(Rect2(cx + row_w - 1, draw_y, 1, 1), COL_FRAME, true)


# ── 网格地图（地牢）──────────────────────────────────────
func _draw_grid_map(center: Vector2, ppos: Vector3, yaw: float) -> void:
	if _cached_grid.is_empty():
		return
	var gw: int = _cached_grid[0].size() if _cached_grid.size() > 0 else 0
	var gh: int = _cached_grid.size()
	if gw == 0 or gh == 0:
		return

	# 玩家所在格子
	var pgx: float = (ppos.x - _grid_offset.x) / _grid_tile_size
	var pgy: float = (ppos.z - _grid_offset.z) / _grid_tile_size
	# 可见格子半径
	var cell_radius: int = int(ceil(world_radius / _grid_tile_size)) + 1
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var half_map := map_size / 2.0
	var psz: float = maxf(_grid_tile_size * _scale, 2.0)

	for dy in range(-cell_radius, cell_radius + 1):
		for dx in range(-cell_radius, cell_radius + 1):
			var gx: int = int(pgx) + dx
			var gy: int = int(pgy) + dy
			if gx < 0 or gx >= gw or gy < 0 or gy >= gh:
				continue
			var cell_type: int = int(_cached_grid[gy][gx])
			if cell_type == 0:  # EMPTY — 不绘制
				continue
			# 格子中心相对玩家的世界偏移
			var wx: float = (gx + 0.5) * _grid_tile_size + _grid_offset.x - ppos.x
			var wz: float = (gy + 0.5) * _grid_tile_size + _grid_offset.z - ppos.z
			# 旋转（yaw 旋转使玩家朝向"朝上"）
			var rx: float = wx * cos_y - wz * sin_y
			var rz: float = wx * sin_y + wz * cos_y
			# 转屏幕坐标
			var sx: float = center.x + rx * _scale
			var sy: float = center.y + rz * _scale
			# 裁剪圆外（用平方距离避免 sqrt）
			var ddx: float = sx - center.x
			var ddy: float = sy - center.y
			if ddx * ddx + ddy * ddy > half_map * half_map:
				continue
			var color: Color = COL_FLOOR
			if cell_type == 2:  # WALL
				color = COL_WALL
			var rect := Rect2(sx - psz * 0.5, sy - psz * 0.5, psz, psz)
			draw_rect(rect, color, true)


# ── 碰撞体扫描地图（酒馆/非程序化场景）──────────────────
func _draw_collision_map(center: Vector2, ppos: Vector3, yaw: float) -> void:
	if _cached_colliders.is_empty():
		return
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	for world_aabb in _cached_colliders:
		# 检查是否在可见范围内
		var center_pos := world_aabb.get_center()
		var dist_to_player := Vector2(center_pos.x - ppos.x, center_pos.z - ppos.z).length()
		if dist_to_player > world_radius + world_aabb.size.length():
			continue
		_draw_aabb_on_map(center, world_aabb, ppos, cos_y, sin_y, COL_WALL)


func _shape_aabb(cs: CollisionShape3D) -> AABB:
	if cs.shape is BoxShape3D:
		var box := cs.shape as BoxShape3D
		return AABB(-box.size / 2.0, box.size)
	if cs.shape is CapsuleShape3D:
		var cap := cs.shape as CapsuleShape3D
		return AABB(Vector3(-cap.radius, -cap.height / 2.0, -cap.radius), Vector3(cap.radius * 2, cap.height, cap.radius * 2))
	if cs.shape is SphereShape3D:
		var sph := cs.shape as SphereShape3D
		return AABB(Vector3(-sph.radius, -sph.radius, -sph.radius), Vector3(sph.radius * 2, sph.radius * 2, sph.radius * 2))
	return AABB()


func _world_aabb(cs: CollisionShape3D, local_aabb: AABB) -> AABB:
	var pos := cs.global_position
	var result := AABB(pos + local_aabb.position, local_aabb.size)
	if cs.global_rotation != Vector3.ZERO:
		var r := local_aabb.size.length() / 2.0
		result = AABB(pos - Vector3(r, r, r), Vector3(r * 2, r * 2, r * 2))
	return result


func _draw_aabb_on_map(center: Vector2, aabb: AABB, ppos: Vector3, cos_y: float, sin_y: float, color: Color) -> void:
	# 取 AABB 底面四个角投影到小地图
	var corners := [
		Vector3(aabb.position.x, 0, aabb.position.z),
		Vector3(aabb.end.x, 0, aabb.position.z),
		Vector3(aabb.end.x, 0, aabb.end.z),
		Vector3(aabb.position.x, 0, aabb.end.z),
	]
	var screen_pts: PackedVector2Array = []
	for c in corners:
		var wx: float = c.x - ppos.x
		var wz: float = c.z - ppos.z
		var rx: float = wx * cos_y - wz * sin_y
		var rz: float = wx * sin_y + wz * cos_y
		var sx: float = center.x + rx * _scale
		var sy: float = center.y + rz * _scale
		screen_pts.append(Vector2(sx, sy))
	if screen_pts.size() >= 3:
		draw_colored_polygon(screen_pts, color)


# ── 敌人标记 ──────────────────────────────────────────────
func _draw_enemies(center: Vector2, ppos: Vector3, yaw: float) -> void:
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var half_map_minus: float = map_size / 2.0 - 2.0
	var half_map_minus_sq: float = half_map_minus * half_map_minus
	# 用 _refresh_references 节流刷新的缓存，避免每帧 get_nodes_in_group
	for enemy in _cached_enemies:
		if not is_instance_valid(enemy):
			continue
		var epos := enemy.global_position
		var wx: float = epos.x - ppos.x
		var wz: float = epos.z - ppos.z
		# 超出可见半径跳过（用平方距离）
		var dist_sq := wx * wx + wz * wz
		if dist_sq > world_radius * world_radius:
			continue
		var rx: float = wx * cos_y - wz * sin_y
		var rz: float = wx * sin_y + wz * cos_y
		var sx: float = center.x + rx * _scale
		var sy: float = center.y + rz * _scale
		# 裁剪圆外（用平方距离）
		var ddx: float = sx - center.x
		var ddy: float = sy - center.y
		if ddx * ddx + ddy * ddy > half_map_minus_sq:
			continue
		# 红色像素方块 (4x4)
		var psz: float = 4.0
		# 精英怪更大更亮
		if "is_elite" in enemy and enemy.is_elite:
			psz = 6.0
			draw_rect(Rect2(sx - psz * 0.5 - 1, sy - psz * 0.5 - 1, psz + 2, psz + 2), Color(1.0, 0.4, 0.2, 0.8), true)
		draw_rect(Rect2(sx - psz * 0.5, sy - psz * 0.5, psz, psz), COL_ENEMY, true)


# ── 玩家箭头（永远朝上）──────────────────────────────────
func _draw_player_arrow(center: Vector2) -> void:
	# 向上指的三角箭头，像素风
	var s: float = 5.0
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(center.x, center.y - s),       # 顶点
		Vector2(center.x - s, center.y + s),   # 左下
		Vector2(center.x + s, center.y + s),   # 右下
	])
	draw_colored_polygon(pts, COL_PLAYER)
	# 外框描边
	for i in range(3):
		var a := pts[i]
		var b := pts[(i + 1) % 3]
		draw_line(a, b, Color.BLACK, 1)


## 外部设置地图数据（供测试/自定义场景用）
func set_grid_data(grid: Array, offset: Vector3, tile_size: float) -> void:
	_cached_grid = grid
	_grid_offset = offset
	_grid_tile_size = tile_size
	_has_grid = grid.size() > 0


## 外部设置玩家引用（供测试用）
func set_player(p: Node) -> void:
	_player = p
