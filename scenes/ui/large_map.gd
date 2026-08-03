class_name LargeMap
extends Control

## 大地图（M键切换）—— 小地图的放大版本。
## 显示整个已探索的地牢区域，北向朝上（不旋转）。
## 从小地图读取已探索格子状态，避免迷雾数据重复维护。
##
## 迷雾探索：
##   - 未探索区域：不绘制（黑色背景）
##   - 已探索但当前不可见：迷雾色（半透明）
##   - 当前可见：完整颜色
##
## 显示元素：
##   - 棕色=墙体，淡黄色=地面
##   - 红色=敌人（仅视野范围内）
##   - 玩家=箭头（显示朝向，北向朝上地图）

@export var padding: float = 24.0
@export var title_height: float = 30.0
@export var hint_height: float = 24.0

var _minimap: CombatMinimap = null

const PIXEL_FONT := preload("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf")

# 颜色常量（复用小地图配色）
const COL_OVERLAY := Color(0.01, 0.01, 0.015, 0.82)
const COL_PANEL_BG := Color(0.03, 0.025, 0.02, 0.96)
const COL_WALL := Color(0.42, 0.24, 0.15, 0.96)
const COL_FLOOR := Color(0.82, 0.72, 0.48, 0.58)
const COL_ENEMY := Color(0.90, 0.12, 0.10, 0.95)
const COL_PLAYER := Color(0.78, 0.82, 0.88, 1.0)
const COL_FRAME := Color(0.78, 0.48, 0.22, 0.96)
const COL_FOG_FLOOR := Color(0.30, 0.26, 0.18, 0.80)
const COL_FOG_WALL := Color(0.22, 0.14, 0.10, 0.88)
const COL_TITLE := Color(0.86, 0.72, 0.36, 1.0)
const COL_HINT := Color(0.6, 0.58, 0.55, 0.85)
# 非程序化场景的虚拟探索格子尺寸（与小地图一致）
const _collision_cell_size: float = 3.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## 绑定小地图引用（数据源）
func set_minimap(m: CombatMinimap) -> void:
	_minimap = m


func show_map() -> void:
	visible = true
	queue_redraw()


func hide_map() -> void:
	visible = false


func toggle() -> void:
	if visible:
		hide_map()
	else:
		show_map()


# ── 绘制 ──────────────────────────────────────────────────

func _draw() -> void:
	if not visible:
		return
	var vp := get_viewport().get_visible_rect().size
	# 全屏暗色遮罩
	draw_rect(Rect2(Vector2.ZERO, vp), COL_OVERLAY, true)
	# 面板区域
	var panel_rect := Rect2(padding, padding, vp.x - padding * 2.0, vp.y - padding * 2.0)
	draw_rect(panel_rect, COL_PANEL_BG, true)
	# 像素边框
	_draw_pixel_border(panel_rect)
	# 标题
	var title_y: float = panel_rect.position.y + 24
	draw_string(PIXEL_FONT, Vector2(panel_rect.position.x + 12, title_y), tr("地图"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COL_TITLE)
	# 提示
	var hint_y: float = panel_rect.end.y - 10
	draw_string(PIXEL_FONT, Vector2(panel_rect.position.x + 12, hint_y), tr("按 M 关闭"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_HINT)
	# 地图内容区域
	var map_area := Rect2(
		panel_rect.position.x + 8,
		panel_rect.position.y + title_height,
		panel_rect.size.x - 16,
		panel_rect.size.y - title_height - hint_height
	)
	if _minimap == null or not is_instance_valid(_minimap):
		_draw_centered_text(map_area, tr("无地图数据"))
		return
	var grid_data: Dictionary = _minimap.get_grid_data()
	if grid_data.get("has_grid", false):
		_draw_grid_large_map(map_area, grid_data)
	else:
		_draw_collision_large_map(map_area, grid_data)


func _draw_pixel_border(rect: Rect2) -> void:
	var t: float = 2.0
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, t), COL_FRAME, true)
	draw_rect(Rect2(rect.position.x, rect.end.y - t, rect.size.x, t), COL_FRAME, true)
	draw_rect(Rect2(rect.position.x, rect.position.y, t, rect.size.y), COL_FRAME, true)
	draw_rect(Rect2(rect.end.x - t, rect.position.y, t, rect.size.y), COL_FRAME, true)


func _draw_centered_text(area: Rect2, text: String) -> void:
	var font_size: int = 16
	var text_size: Vector2 = PIXEL_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos: Vector2 = area.get_center() - text_size / 2.0
	pos.y += font_size * 0.5
	draw_string(PIXEL_FONT, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COL_HINT)


# ── 网格地图（地牢）──────────────────────────────────────

func _draw_grid_large_map(map_area: Rect2, grid_data: Dictionary) -> void:
	var grid: Array = grid_data.get("grid", [])
	var offset: Vector3 = grid_data.get("offset", Vector3.ZERO)
	var tile_size: float = grid_data.get("tile_size", 3.0)
	if grid.is_empty():
		_draw_centered_text(map_area, tr("无地图数据"))
		return
	var gw: int = grid[0].size() if grid.size() > 0 else 0
	var gh: int = grid.size()
	if gw == 0 or gh == 0:
		_draw_centered_text(map_area, tr("无地图数据"))
		return

	# 世界尺寸
	var world_w: float = float(gw) * tile_size
	var world_h: float = float(gh) * tile_size
	# 缩放以适应地图区域
	var sx: float = map_area.size.x / world_w
	var sy: float = map_area.size.y / world_h
	var s: float = minf(sx, sy)
	# 居中偏移
	var ox: float = map_area.position.x + (map_area.size.x - world_w * s) / 2.0
	var oy: float = map_area.position.y + (map_area.size.y - world_h * s) / 2.0

	var explored: Dictionary = _minimap.get_explored_cells()
	var player: Node = _minimap.get_player()
	var ppos: Vector3 = Vector3.ZERO
	var has_player: bool = player != null and is_instance_valid(player)
	if has_player:
		ppos = player.global_position
	var fog_r: float = _minimap.fog_vision_radius
	var fog_r_sq: float = fog_r * fog_r

	# 绘制每个已探索格子
	var cell_px: float = tile_size * s
	for gy in range(gh):
		for gx in range(gw):
			var cell_type: int = int(grid[gy][gx])
			if cell_type == 0:
				continue  # EMPTY
			if not explored.has(Vector2i(gx, gy)):
				continue  # 未探索
			# 世界坐标
			var wx: float = gx * tile_size + offset.x
			var wz: float = gy * tile_size + offset.z
			# 屏幕坐标
			var px: float = ox + (wx - offset.x) * s
			var py: float = oy + (wz - offset.z) * s
			# 判断当前是否可见
			var visible: bool = false
			if has_player:
				var dx: float = (wx + tile_size * 0.5) - ppos.x
				var dz: float = (wz + tile_size * 0.5) - ppos.z
				visible = dx * dx + dz * dz <= fog_r_sq
			# 颜色
			var color: Color
			if visible:
				color = COL_FLOOR if cell_type != 2 else COL_WALL
			else:
				color = COL_FOG_FLOOR if cell_type != 2 else COL_FOG_WALL
			# +1 像素重叠消除格子间隙
			draw_rect(Rect2(px, py, cell_px + 1, cell_px + 1), color, true)

	# 绘制敌人
	_draw_enemies(ox, oy, s, offset, ppos, has_player, fog_r_sq)

	# 绘制玩家箭头
	if has_player:
		var px: float = ox + (ppos.x - offset.x) * s
		var py: float = oy + (ppos.z - offset.z) * s
		_draw_player_arrow(Vector2(px, py), player.rotation.y, maxf(cell_px * 0.7, 8.0))


# ── 碰撞体扫描地图（酒馆/非程序化场景）──────────────────

func _draw_collision_large_map(map_area: Rect2, grid_data: Dictionary) -> void:
	var colliders: Array[AABB] = grid_data.get("colliders", [])
	if colliders.is_empty():
		_draw_centered_text(map_area, tr("无地图数据"))
		return
	# 计算所有碰撞体的世界边界
	var bounds_min := Vector3(INF, 0, INF)
	var bounds_max := Vector3(-INF, 0, -INF)
	for aabb in colliders:
		bounds_min.x = minf(bounds_min.x, aabb.position.x)
		bounds_min.z = minf(bounds_min.z, aabb.position.z)
		bounds_max.x = maxf(bounds_max.x, aabb.end.x)
		bounds_max.z = maxf(bounds_max.z, aabb.end.z)
	# 加入玩家位置扩展边界
	var player: Node = _minimap.get_player()
	var ppos: Vector3 = Vector3.ZERO
	var has_player: bool = player != null and is_instance_valid(player)
	if has_player:
		ppos = player.global_position
		bounds_min.x = minf(bounds_min.x, ppos.x - 5)
		bounds_min.z = minf(bounds_min.z, ppos.z - 5)
		bounds_max.x = maxf(bounds_max.x, ppos.x + 5)
		bounds_max.z = maxf(bounds_max.z, ppos.z + 5)
	var world_w: float = bounds_max.x - bounds_min.x
	var world_h: float = bounds_max.z - bounds_min.z
	if world_w <= 0 or world_h <= 0:
		_draw_centered_text(map_area, tr("无地图数据"))
		return
	# 缩放
	var sx: float = map_area.size.x / world_w
	var sy: float = map_area.size.y / world_h
	var s: float = minf(sx, sy)
	# 居中偏移
	var ox: float = map_area.position.x + (map_area.size.x - world_w * s) / 2.0
	var oy: float = map_area.position.y + (map_area.size.y - world_h * s) / 2.0

	var explored_cells: Dictionary = _minimap.get_explored_collision_cells()
	var fog_r: float = _minimap.fog_vision_radius
	var fog_r_sq: float = fog_r * fog_r

	# 绘制已探索的碰撞体
	for aabb in colliders:
		var center_pos := aabb.get_center()
		var cx: int = int(round(center_pos.x / _collision_cell_size))
		var cz: int = int(round(center_pos.z / _collision_cell_size))
		if not explored_cells.has("%d,%d" % [cx, cz]):
			continue  # 未探索
		# 判断当前是否可见
		var visible: bool = false
		if has_player:
			var dx: float = center_pos.x - ppos.x
			var dz: float = center_pos.z - ppos.z
			visible = dx * dx + dz * dz <= fog_r_sq
		var color: Color = COL_WALL if visible else COL_FOG_WALL
		var px: float = ox + (aabb.position.x - bounds_min.x) * s
		var py: float = oy + (aabb.position.z - bounds_min.z) * s
		var pw: float = aabb.size.x * s
		var ph: float = aabb.size.z * s
		draw_rect(Rect2(px, py, maxf(pw, 1), maxf(ph, 1)), color, true)

	# 绘制敌人
	_draw_enemies(ox, oy, s, bounds_min, ppos, has_player, fog_r_sq, true)

	# 绘制玩家箭头
	if has_player:
		var px: float = ox + (ppos.x - bounds_min.x) * s
		var py: float = oy + (ppos.z - bounds_min.z) * s
		_draw_player_arrow(Vector2(px, py), player.rotation.y, maxf(_collision_cell_size * s * 0.7, 8.0))


# ── 敌人标记 ──────────────────────────────────────────────

## 绘制敌人（仅在玩家视野范围内显示）
## offset_is_bounds: false=offset为grid_offset(地牢), true=offset为bounds_min(碰撞体)
func _draw_enemies(ox: float, oy: float, s: float, offset: Vector3, ppos: Vector3, has_player: bool, fog_r_sq: float, offset_is_bounds: bool = false) -> void:
	if not has_player:
		return
	var enemies: Array[Enemy] = _minimap.get_cached_enemies()
	# 敌人标记尺寸随缩放比例调整，最小4px
	var base_psz: float = maxf(s * 2.0, 4.0)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var epos := enemy.global_position
		var dx: float = epos.x - ppos.x
		var dz: float = epos.z - ppos.z
		if dx * dx + dz * dz > fog_r_sq:
			continue
		var ref_x: float = offset.x if not offset_is_bounds else offset.x
		var ref_z: float = offset.z if not offset_is_bounds else offset.z
		var px: float = ox + (epos.x - ref_x) * s
		var py: float = oy + (epos.z - ref_z) * s
		var psz: float = base_psz
		if "is_elite" in enemy and enemy.is_elite:
			psz = base_psz * 1.4
			draw_rect(Rect2(px - psz * 0.5 - 1, py - psz * 0.5 - 1, psz + 2, psz + 2), Color(1.0, 0.4, 0.2, 0.8), true)
		draw_rect(Rect2(px - psz * 0.5, py - psz * 0.5, psz, psz), COL_ENEMY, true)


# ── 玩家箭头（北向朝上，按朝向旋转）──────────────────────

func _draw_player_arrow(center: Vector2, yaw: float, arrow_size: float = 7.0) -> void:
	# 根据玩家朝向(yaw)计算箭头方向（北向朝上地图）
	# yaw=0 → 朝上(-Z), yaw=PI/2 → 朝左(-X)
	var dir_x: float = -sin(yaw)
	var dir_y: float = -cos(yaw)
	# 垂直方向（箭头底边）
	var perp_x: float = -dir_y
	var perp_y: float = dir_x
	var s: float = arrow_size
	var tip: Vector2 = center + Vector2(dir_x, dir_y) * s
	var base_l: Vector2 = center - Vector2(dir_x, dir_y) * s * 0.5 + Vector2(perp_x, perp_y) * s * 0.5
	var base_r: Vector2 = center - Vector2(dir_x, dir_y) * s * 0.5 - Vector2(perp_x, perp_y) * s * 0.5
	var pts: PackedVector2Array = PackedVector2Array([tip, base_l, base_r])
	# 描边（先画黑色底，再画亮色面）
	var outline_w: float = maxf(2.0, s * 0.3)
	var pts_outline: PackedVector2Array = PackedVector2Array([
		tip + Vector2(dir_x, dir_y) * outline_w,
		base_l + Vector2(-perp_x, -perp_y) * outline_w * 0.5 + Vector2(-dir_x, -dir_y) * outline_w * 0.5,
		base_r + Vector2(perp_x, perp_y) * outline_w * 0.5 + Vector2(-dir_x, -dir_y) * outline_w * 0.5,
	])
	draw_colored_polygon(pts_outline, Color.BLACK)
	draw_colored_polygon(pts, COL_PLAYER)
	# 亮色描边
	for i in range(3):
		draw_line(pts[i], pts[(i + 1) % 3], Color(0.9, 0.92, 0.95, 0.6), 1)
