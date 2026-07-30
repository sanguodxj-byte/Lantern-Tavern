class_name CombatMinimap
extends Control

## 旋转小地图（右上角）。
## 棕色=墙体，淡黄色=地面，红色=敌人，玩家=箭头(永远朝上)。
## 小地图跟随视角(yaw)旋转，玩家箭头固定朝上。
## 自动从 ProceduralDungeon.layout.grid 或场景碰撞体获取地图数据。
##
## 迷雾探索（Fog of War）：
##   - 未探索区域：完全隐藏（黑色背景）
##   - 已探索但当前不可见：半透明（迷雾覆盖）
##   - 当前可见：完整颜色
##
## 探索进度同步（与大地图一致）：
##   小地图以"已探索区域包围盒"为基准自动缩放，展示完整探索进度，
##   而非仅玩家周围 world_radius 的局部窗口（探索区域较大时自动缩小）。
##
## 性能策略：
##   - 绘制每帧执行（读取玩家位置/朝向，轻量）
const Service := preload("res://globals/core/service.gd")
##   - 引用刷新 & 碰撞体缓存每 update_interval 秒执行一次（重量级）

@export var map_size: int = 180          # 小地图像素边长
@export var world_radius: float = 25.0   # 可见世界半径(米)
@export var update_interval: float = 0.3  # 数据刷新间隔(秒)——仅影响引用/缓存
@export var bg_alpha: float = 0.55
## 迷雾探索视野半径（米）：玩家周围此范围内的格子被标记为"当前可见"
@export var fog_vision_radius: float = 12.0

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

# ── 迷雾探索状态 ──
# 已探索的格子（grid 坐标 Vector2i → true），跨帧持久
var _explored_cells: Dictionary = {}
# 已探索的碰撞体世界格子（非 grid 场景用，key = "x,y" → true）
var _explored_collision_cells: Dictionary = {}
# 非程序化场景的虚拟探索格子尺寸（米）
const _collision_cell_size: float = 3.0
# 当前帧可见格子集合（每帧重建，仅含 fog_vision_radius 内的格子）
var _visible_cells: Dictionary = {}
# 雾帧计时器：避免每帧都做探索标记（节流到每 ~0.1s）
var _fog_timer: float = 0.0

# ── 视图变换（与大地图一致的“探索进度”视图）──
# 小地图以“已探索区域包围盒”为基准做自动缩放，展示完整探索进度
# （而非仅玩家周围 world_radius 的局部窗口），与大地图保持一致。
var _view_center: Vector3 = Vector3.ZERO   # 当前绘制中心（世界坐标，y=0）
var _view_scale: float = 1.0               # 当前绘制缩放（像素/米）
var _view_cgx: int = 0                     # 网格遍历中心 X
var _view_cgy: int = 0                     # 网格遍历中心 Y
var _view_cell_r: int = 0                  # 网格遍历半径（格）
# 非程序化场景（碰撞体）视图参数
var _view_ccx: int = 0
var _view_ccz: int = 0
var _view_cell_rc: int = 0

# 颜色常量
const COL_BG := Color(0.02, 0.021, 0.024, 0.88)
const COL_WALL := Color(0.42, 0.24, 0.15, 0.96)
const COL_FLOOR := Color(0.82, 0.72, 0.48, 0.58)
const COL_ENEMY := Color(0.90, 0.12, 0.10, 0.95)
const COL_PLAYER := Color(0.78, 0.82, 0.88, 1.0)
const COL_FRAME := Color(0.78, 0.48, 0.22, 0.96)
# 迷雾颜色：已探索但当前不可见的区域
const COL_FOG_FLOOR := Color(0.18, 0.18, 0.20, 0.38)
const COL_FOG_WALL := Color(0.14, 0.145, 0.16, 0.52)
# 未探索区域的迷雾覆盖色（绘制在背景上）
const COL_UNEXPLORED := Color(0.02, 0.021, 0.024, 0.92)


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

	# 节流探索标记（每 ~0.1s 标记一次当前可见格子）
	_fog_timer += delta
	if _fog_timer >= 0.1:
		_fog_timer = 0.0
		_mark_explored_cells()

	# 每帧重建当前可见格子集合并重绘
	_update_visible_cells()
	queue_redraw()


func _refresh_references() -> void:
	if not is_instance_valid(_player):
		_player = _find_player()
	if not is_instance_valid(_level):
		# 关卡切换：重置迷雾探索状态
		reset_fog()
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
	var gs := Service.game_state()
	if gs and gs.get("current_player") and is_instance_valid(gs.get("current_player")):
		return gs.current_player
	return null


func _find_level() -> Node:
	var gs := Service.game_state()
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
	# 阶段 9：ProceduralDungeon 旧字段 _grid/TILE_SIZE 已退役，地形网格统一读 layout.grid / layout.tile_size
	if _level.has_method("is_procedural") and _level.is_procedural() and "layout" in _level and _level.layout != null:
		var lvl_layout = _level.layout
		if lvl_layout.grid.is_empty():
			return
		_cached_grid = lvl_layout.grid
		_grid_tile_size = lvl_layout.tile_size
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


# ── 迷雾探索逻辑 ──────────────────────────────────────────

## 标记玩家周围 fog_vision_radius 内的格子为已探索
func _mark_explored_cells() -> void:
	if not is_instance_valid(_player):
		return
	var ppos: Vector3 = _player.global_position
	if _has_grid and not _cached_grid.is_empty():
		_mark_grid_explored(ppos)
	else:
		_mark_collision_explored(ppos)


func _mark_grid_explored(ppos: Vector3) -> void:
	var gw: int = _cached_grid[0].size() if _cached_grid.size() > 0 else 0
	var gh: int = _cached_grid.size()
	if gw == 0 or gh == 0:
		return
	var pgx: float = (ppos.x - _grid_offset.x) / _grid_tile_size
	var pgy: float = (ppos.z - _grid_offset.z) / _grid_tile_size
	var cell_radius: int = int(ceil(fog_vision_radius / _grid_tile_size)) + 1
	for dy in range(-cell_radius, cell_radius + 1):
		for dx in range(-cell_radius, cell_radius + 1):
			var gx: int = int(pgx) + dx
			var gy: int = int(pgy) + dy
			if gx < 0 or gx >= gw or gy < 0 or gy >= gh:
				continue
			# 只标记非空格子
			var cell_type: int = int(_cached_grid[gy][gx])
			if cell_type == 0:
				continue
			# 检查实际世界距离是否在视野范围内
			var wx: float = (gx + 0.5) * _grid_tile_size + _grid_offset.x - ppos.x
			var wz: float = (gy + 0.5) * _grid_tile_size + _grid_offset.z - ppos.z
			if wx * wx + wz * wz <= fog_vision_radius * fog_vision_radius:
				_explored_cells[Vector2i(gx, gy)] = true


func _mark_collision_explored(ppos: Vector3) -> void:
	# 非程序化场景：用虚拟格子标记已探索区域
	var cx: int = int(round(ppos.x / _collision_cell_size))
	var cz: int = int(round(ppos.z / _collision_cell_size))
	var cell_r: int = int(ceil(fog_vision_radius / _collision_cell_size)) + 1
	for dy in range(-cell_r, cell_r + 1):
		for dx in range(-cell_r, cell_r + 1):
			var wx: float = (cx + dx) * _collision_cell_size - ppos.x
			var wz: float = (cz + dy) * _collision_cell_size - ppos.z
			if wx * wx + wz * wz <= fog_vision_radius * fog_vision_radius:
				_explored_collision_cells["%d,%d" % [cx + dx, cz + dy]] = true


## 每帧重建当前可见格子集合（fog_vision_radius 内的格子）
func _update_visible_cells() -> void:
	_visible_cells.clear()
	if not is_instance_valid(_player):
		return
	var ppos: Vector3 = _player.global_position
	if _has_grid and not _cached_grid.is_empty():
		var gw: int = _cached_grid[0].size() if _cached_grid.size() > 0 else 0
		var gh: int = _cached_grid.size()
		if gw == 0 or gh == 0:
			return
		var pgx: float = (ppos.x - _grid_offset.x) / _grid_tile_size
		var pgy: float = (ppos.z - _grid_offset.z) / _grid_tile_size
		var cell_radius: int = int(ceil(fog_vision_radius / _grid_tile_size)) + 1
		for dy in range(-cell_radius, cell_radius + 1):
			for dx in range(-cell_radius, cell_radius + 1):
				var gx: int = int(pgx) + dx
				var gy: int = int(pgy) + dy
				if gx < 0 or gx >= gw or gy < 0 or gy >= gh:
					continue
				var wx: float = (gx + 0.5) * _grid_tile_size + _grid_offset.x - ppos.x
				var wz: float = (gy + 0.5) * _grid_tile_size + _grid_offset.z - ppos.z
				if wx * wx + wz * wz <= fog_vision_radius * fog_vision_radius:
					_visible_cells[Vector2i(gx, gy)] = true


func _is_cell_visible(gx: int, gy: int) -> bool:
	return _visible_cells.has(Vector2i(gx, gy))


func _is_cell_explored(gx: int, gy: int) -> bool:
	return _explored_cells.has(Vector2i(gx, gy))


func _is_collision_cell_explored(cx: int, cz: int) -> bool:
	return _explored_collision_cells.has("%d,%d" % [cx, cz])


func _is_collision_cell_visible(ppos: Vector3, wx: float, wz: float) -> bool:
	return wx * wx + wz * wz <= fog_vision_radius * fog_vision_radius


# ── 绘制 ──────────────────────────────────────────────────

func _draw() -> void:
	if not is_instance_valid(_player):
		return

	var center := size / 2.0
	var yaw: float = _player.rotation.y
	var ppos: Vector3 = _player.global_position

	# 计算当前视图变换（以已探索区域为基准，展示完整探索进度）
	_update_view(ppos)

	# 背景：像素风圆形（用方块逐格绘制）
	_draw_pixel_circle_bg(center, map_size / 2.0)

	if _has_grid:
		_draw_grid_map(center, ppos, yaw)
	else:
		_draw_collision_map(center, ppos, yaw)

	# 敌人（仅当前视野范围内显示）
	_draw_enemies(center, ppos, yaw)

	# 玩家箭头（永远朝上，绘制在相对视图中心的位置）
	_draw_player_arrow_at(center, ppos, yaw)

	# 未探索区域遮罩：在已绘制内容上覆盖深色迷雾
	_draw_fog_overlay(center, ppos, yaw)


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
## 修复旋转视角时的网格空隙：用旋转多边形替代 draw_rect 绘制每个格子，
## 确保相邻格子在任意旋转角度下都无缝拼接。
func _draw_grid_map(center: Vector2, ppos: Vector3, yaw: float) -> void:
	if _cached_grid.is_empty():
		return
	var gw: int = _cached_grid[0].size() if _cached_grid.size() > 0 else 0
	var gh: int = _cached_grid.size()
	if gw == 0 or gh == 0:
		return

	# 遍历中心与半径由 _update_view() 统一计算：
	# 已探索区域较大时自动缩小以展示完整探索进度（与大地图一致），
	# 否则退化为玩家中心局部视图。
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var half_map := map_size / 2.0
	var half_tile: float = _grid_tile_size * 0.5

	for dy in range(-_view_cell_r, _view_cell_r + 1):
		for dx in range(-_view_cell_r, _view_cell_r + 1):
			var gx: int = _view_cgx + dx
			var gy: int = _view_cgy + dy
			if gx < 0 or gx >= gw or gy < 0 or gy >= gh:
				continue
			var cell_type: int = int(_cached_grid[gy][gx])
			if cell_type == 0:  # EMPTY — 不绘制
				continue

			# 迷雾：未探索的格子跳过（不绘制，保持黑色背景）
			var explored := _is_cell_explored(gx, gy)
			if not explored:
				continue

			var visible := _is_cell_visible(gx, gy)

			# 格子四角的世界偏移（相对当前视图中心）
			var corner_wx: Array[float] = [
				(gx) * _grid_tile_size + _grid_offset.x - _view_center.x - half_tile,
				(gx + 1) * _grid_tile_size + _grid_offset.x - _view_center.x - half_tile,
				(gx + 1) * _grid_tile_size + _grid_offset.x - _view_center.x - half_tile,
				(gx) * _grid_tile_size + _grid_offset.x - _view_center.x - half_tile,
			]
			var corner_wz: Array[float] = [
				(gy) * _grid_tile_size + _grid_offset.z - _view_center.z - half_tile,
				(gy) * _grid_tile_size + _grid_offset.z - _view_center.z - half_tile,
				(gy + 1) * _grid_tile_size + _grid_offset.z - _view_center.z - half_tile,
				(gy + 1) * _grid_tile_size + _grid_offset.z - _view_center.z - half_tile,
			]

			# 旋转并转屏幕坐标
			var screen_pts: PackedVector2Array = []
			var all_outside := true
			for i in range(4):
				var rx: float = corner_wx[i] * cos_y - corner_wz[i] * sin_y
				var rz: float = corner_wx[i] * sin_y + corner_wz[i] * cos_y
				var sx: float = center.x + rx * _view_scale
				var sy: float = center.y + rz * _view_scale
				screen_pts.append(Vector2(sx, sy))
				# 粗略裁剪检测
				var ddx: float = sx - center.x
				var ddy: float = sy - center.y
				if ddx * ddx + ddy * ddy <= (half_map + _grid_tile_size * _view_scale) * (half_map + _grid_tile_size * _view_scale):
					all_outside = false

			if all_outside:
				continue

			# 根据可见/迷雾状态选择颜色
			var color: Color
			if visible:
				color = COL_FLOOR if cell_type != 2 else COL_WALL
			else:
				# 已探索但当前不可见：迷雾色
				color = COL_FOG_FLOOR if cell_type != 2 else COL_FOG_WALL

			# 用旋转多边形绘制，消除旋转时的网格空隙
			if screen_pts.size() >= 3:
				draw_colored_polygon(screen_pts, color)


# ── 碰撞体扫描地图（酒馆/非程序化场景）──────────────────
func _draw_collision_map(center: Vector2, ppos: Vector3, yaw: float) -> void:
	if _cached_colliders.is_empty():
		return
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var half_map := map_size / 2.0
	var half_map_sq := (half_map - 2.0) * (half_map - 2.0)
	for world_aabb in _cached_colliders:
		var center_pos := world_aabb.get_center()
		# 迷雾：碰撞体中心所在虚拟格子是否已探索
		var cx: int = int(round(center_pos.x / _collision_cell_size))
		var cz: int = int(round(center_pos.z / _collision_cell_size))
		if not _is_collision_cell_explored(cx, cz):
			continue

		# 判断当前是否可见（仅视野范围内高亮为墙色）
		var wx: float = center_pos.x - ppos.x
		var wz: float = center_pos.z - ppos.z
		var visible := _is_collision_cell_visible(ppos, wx, wz)

		# 计算 AABB 底面四角在屏幕上的位置（相对 _view_center 旋转缩放）
		var corners := [
			Vector3(world_aabb.position.x, 0, world_aabb.position.z),
			Vector3(world_aabb.end.x, 0, world_aabb.position.z),
			Vector3(world_aabb.end.x, 0, world_aabb.end.z),
			Vector3(world_aabb.position.x, 0, world_aabb.end.z),
		]
		var screen_pts: PackedVector2Array = []
		var all_outside := true
		for c in corners:
			var rxw: float = c.x - _view_center.x
			var rzw: float = c.z - _view_center.z
			var rx: float = rxw * cos_y - rzw * sin_y
			var rz: float = rxw * sin_y + rzw * cos_y
			var sx: float = center.x + rx * _view_scale
			var sy: float = center.y + rz * _view_scale
			screen_pts.append(Vector2(sx, sy))
			var ddx: float = sx - center.x
			var ddy: float = sy - center.y
			if ddx * ddx + ddy * ddy <= half_map_sq:
				all_outside = false
		if all_outside:
			continue

		# 根据可见/迷雾选择颜色
		var color: Color = COL_WALL if visible else COL_FOG_WALL
		if screen_pts.size() >= 3:
			draw_colored_polygon(screen_pts, color)


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


# ── 迷雾遮罩 ──────────────────────────────────────────────
## 在所有地图内容绘制完毕后，对未探索区域覆盖深色迷雾。
## 使用径向遮罩：以玩家为中心的圆形渐变，已探索区域之外的像素被加深。
func _draw_fog_overlay(center: Vector2, ppos: Vector3, yaw: float) -> void:
	# 使用一个简单的径向遮罩：玩家视野范围外的已绘制区域被半透明黑色覆盖
	# 这里不再额外绘制遮罩——_draw_grid_map 和 _draw_collision_map 已经
	# 通过跳过未探索格子 + 迷雾色实现了迷雾效果。
	# 此函数保留为扩展点，未来可添加更复杂的迷雾渐变。
	pass


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
		# 敌人仅在当前视野范围内显示（迷雾中不显示敌人）
		var vdx: float = epos.x - ppos.x
		var vdz: float = epos.z - ppos.z
		if vdx * vdx + vdz * vdz > fog_vision_radius * fog_vision_radius:
			continue
		# 地图坐标（相对当前视图中心）
		var wx: float = epos.x - _view_center.x
		var wz: float = epos.z - _view_center.z
		var rx: float = wx * cos_y - wz * sin_y
		var rz: float = wx * sin_y + wz * cos_y
		var sx: float = center.x + rx * _view_scale
		var sy: float = center.y + rz * _view_scale
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


# ── 视图变换计算 ──────────────────────────────────────────
## 根据已探索区域计算当前绘制中心(_view_center)与缩放(_view_scale)，
## 以及遍历窗口(_view_cgx/_view_cgy/_view_cell_r 或碰撞体等价参数)。
## 目标：展示完整探索进度（与大地图一致），而非仅玩家周围的局部窗口。
## 当已探索区域足够大（自适应缩放 < 局部缩放）时，以已探索区域包围盒为
## 基准自动缩小；否则退化为玩家中心、world_radius 半径的局部视图（旧行为）。
func _update_view(ppos: Vector3) -> void:
	if _has_grid and not _cached_grid.is_empty():
		var keys: Array = _explored_cells.keys()
		if keys.size() > 0:
			var min_gx := 100000000
			var max_gx := -100000000
			var min_gy := 100000000
			var max_gy := -100000000
			for k in keys:
				var v: Vector2i = k
				if v.x < min_gx: min_gx = v.x
				if v.x > max_gx: max_gx = v.x
				if v.y < min_gy: min_gy = v.y
				if v.y > max_gy: max_gy = v.y
			var bcx: float = (float(min_gx) + float(max_gx) + 1.0) * 0.5 * _grid_tile_size + _grid_offset.x
			var bcz: float = (float(min_gy) + float(max_gy) + 1.0) * 0.5 * _grid_tile_size + _grid_offset.z
			var bw: float = float(max_gx - min_gx + 1) * _grid_tile_size
			var bh: float = float(max_gy - min_gy + 1) * _grid_tile_size
			var fit: float = (map_size * 0.9) / maxf(maxf(bw, bh), 0.001)
			if fit < _scale:
				_view_center = Vector3(bcx, 0.0, bcz)
				_view_scale = fit
				_view_cgx = int((bcx - _grid_offset.x) / _grid_tile_size)
				_view_cgy = int((bcz - _grid_offset.z) / _grid_tile_size)
				var half_gx: int = int(ceil(float(max_gx - min_gx) * 0.5)) + 2
				var half_gy: int = int(ceil(float(max_gy - min_gy) * 0.5)) + 2
				_view_cell_r = maxi(half_gx, half_gy)
			else:
				_view_center = ppos
				_view_scale = _scale
				_view_cgx = int((ppos.x - _grid_offset.x) / _grid_tile_size)
				_view_cgy = int((ppos.z - _grid_offset.z) / _grid_tile_size)
				_view_cell_r = int(ceil(world_radius / _grid_tile_size)) + 1
		else:
			_view_center = ppos
			_view_scale = _scale
			_view_cgx = int((ppos.x - _grid_offset.x) / _grid_tile_size)
			_view_cgy = int((ppos.z - _grid_offset.z) / _grid_tile_size)
			_view_cell_r = int(ceil(world_radius / _grid_tile_size)) + 1
	else:
		# 非程序化场景：基于已探索碰撞体格子包围盒
		var ckeys: Array = _explored_collision_cells.keys()
		if ckeys.size() > 0:
			var min_x := 100000000.0
			var max_x := -100000000.0
			var min_z := 100000000.0
			var max_z := -100000000.0
			for k in ckeys:
				var parts: PackedStringArray = String(k).split(",")
				if parts.size() < 2:
					continue
				var cx: int = int(parts[0])
				var cz: int = int(parts[1])
				var wx: float = cx * _collision_cell_size
				var wz: float = cz * _collision_cell_size
				if wx < min_x: min_x = wx
				if wx > max_x: max_x = wx
				if wz < min_z: min_z = wz
				if wz > max_z: max_z = wz
			var bcx: float = (min_x + max_x) * 0.5
			var bcz: float = (min_z + max_z) * 0.5
			var bw: float = (max_x - min_x) + _collision_cell_size
			var bh: float = (max_z - min_z) + _collision_cell_size
			var fit: float = (map_size * 0.9) / maxf(maxf(bw, bh), 0.001)
			if fit < _scale:
				_view_center = Vector3(bcx, 0.0, bcz)
				_view_scale = fit
				_view_ccx = int(round(bcx / _collision_cell_size))
				_view_ccz = int(round(bcz / _collision_cell_size))
				var half_x: int = int(ceil((max_x - min_x) * 0.5 / _collision_cell_size)) + 2
				var half_z: int = int(ceil((max_z - min_z) * 0.5 / _collision_cell_size)) + 2
				_view_cell_rc = maxi(half_x, half_z)
			else:
				_view_center = ppos
				_view_scale = _scale
				_view_ccx = int(round(ppos.x / _collision_cell_size))
				_view_ccz = int(round(ppos.z / _collision_cell_size))
				_view_cell_rc = int(ceil(world_radius / _collision_cell_size)) + 1
		else:
			_view_center = ppos
			_view_scale = _scale
			_view_ccx = int(round(ppos.x / _collision_cell_size))
			_view_ccz = int(round(ppos.z / _collision_cell_size))
			_view_cell_rc = int(ceil(world_radius / _collision_cell_size)) + 1


## 该格子是否应被绘制（在遍历窗口内且已探索）。供测试验证“探索进度可见性”。
func _cell_in_draw_window(gx: int, gy: int) -> bool:
	if not _is_cell_explored(gx, gy):
		return false
	if gx < _view_cgx - _view_cell_r or gx > _view_cgx + _view_cell_r:
		return false
	if gy < _view_cgy - _view_cell_r or gy > _view_cgy + _view_cell_r:
		return false
	return true


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


## 玩家箭头绘制在相对视图中心的真实位置（探索进度视图下玩家未必在屏幕中心）。
## 箭头永远朝上（小地图风格）。
func _draw_player_arrow_at(screen_center: Vector2, ppos: Vector3, yaw: float) -> void:
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var wx: float = ppos.x - _view_center.x
	var wz: float = ppos.z - _view_center.z
	var rx: float = wx * cos_y - wz * sin_y
	var rz: float = wx * sin_y + wz * cos_y
	var sx: float = screen_center.x + rx * _view_scale
	var sy: float = screen_center.y + rz * _view_scale
	var s: float = 5.0
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(sx, sy - s),       # 顶点
		Vector2(sx - s, sy + s),   # 左下
		Vector2(sx + s, sy + s),   # 右下
	])
	draw_colored_polygon(pts, COL_PLAYER)
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


## 重置迷雾探索状态（场景切换时调用）
func reset_fog() -> void:
	_explored_cells.clear()
	_explored_collision_cells.clear()
	_visible_cells.clear()


## 获取已探索格子数（供测试用）
func get_explored_count() -> int:
	return _explored_cells.size() + _explored_collision_cells.size()


## 手动标记格子为已探索（供测试用）
func mark_cell_explored(gx: int, gy: int) -> void:
	_explored_cells[Vector2i(gx, gy)] = true


# ── 大地图数据共享接口 ────────────────────────────────────

## 返回网格数据字典（供 LargeMap 读取，避免重复缓存）
func get_grid_data() -> Dictionary:
	return {
		"grid": _cached_grid,
		"offset": _grid_offset,
		"tile_size": _grid_tile_size,
		"has_grid": _has_grid,
		"colliders": _cached_colliders,
	}


## 返回已探索格子集合（grid 坐标 Vector2i → true）
func get_explored_cells() -> Dictionary:
	return _explored_cells


## 返回已探索碰撞体格子集合（"x,y" → true，非程序化场景用）
func get_explored_collision_cells() -> Dictionary:
	return _explored_collision_cells


## 返回节流刷新的敌人缓存
func get_cached_enemies() -> Array[Enemy]:
	return _cached_enemies


## 返回玩家引用
func get_player() -> Node:
	return _player
