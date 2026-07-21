class_name Crosshair
extends Control

## 像素风准心（屏幕正中央）。
## 弓/弩瞄准时显示，投掷时也显示。
## 命中敌人时复用已有变红反馈（COL_TARGETING）短时闪烁。
## 近战攻击冷却指示：准心两侧像素扇形环——双持时左/右半扇分别对应左/右手武器冷却，
## 单手或双手武器时显示完整环形。就绪时常隐，进入冷却时浮现并以像素块逐步回满。

const COL_DEFAULT := Color(1.0, 1.0, 1.0, 0.85)
const COL_TARGETING := Color(1.0, 0.25, 0.15, 0.95)
const COL_AIMING := Color(0.3, 1.0, 0.4, 0.9)
const Service := preload("res://globals/core/service.gd")

# 近战冷却指示（像素风）
const RING_RADIUS := 17          # 环半径（像素）
const RING_THICK := 4            # 像素块边长
const RING_SEGS := 18            # 环分段数（越大越细）
const COL_CD_READY := Color(0.45, 1.0, 0.55, 0.95)    # 已恢复段（亮绿）
const COL_CD_COOLING := Color(0.32, 0.36, 0.42, 0.55) # 冷却中未恢复段（暗灰）
const COL_RELOAD_BRIGHT := Color(1.0, 0.72, 0.18, 0.95)   # 弩装弹已恢复段（亮琥珀）
const COL_RELOAD_DIM := Color(0.5, 0.36, 0.12, 0.5)       # 弩装弹冷却中段（暗琥珀）

## 命中反馈：复用 COL_TARGETING 变红，短时强制显示（非新 UI 系统）
const HIT_FLASH_DURATION := 0.16
const HIT_FLASH_CRIT_DURATION := 0.22
const HIT_FLASH_EXPAND_PX := 3.0

@export var arm_length: float = 8.0
@export var arm_thickness: float = 2.0
@export var center_gap: float = 3.0

var _is_targeting: bool = false
var _is_aiming: bool = false
var _player: Node = null
var _scan_timer: float = 0.0
## 上次绘制时的状态快照——用于检测是否需要重绘
var _last_drawn_targeting: bool = false
var _last_drawn_aiming: bool = false
## 冷却指示状态快照
var _cd_mode: int = 0            # 0=无/远程, 1=完整环, 2=双持半扇, 3=弩装弹环
var _cd_primary_fill: float = 1.0
var _cd_secondary_fill: float = 1.0
var _cd_reload_fill: float = 1.0
var _last_cd_sig: String = "none"

## 命中变红闪烁（复用 COL_TARGETING，非独立 Hitmarker 资产）
var _hit_timer: float = 0.0
var _hit_duration: float = HIT_FLASH_DURATION
var _hit_is_crit: bool = false
var _last_hit_active: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(48, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	if GameEvents != null and GameEvents.has_signal("player_hit_enemy"):
		if not GameEvents.player_hit_enemy.is_connected(_on_player_hit_enemy):
			GameEvents.player_hit_enemy.connect(_on_player_hit_enemy)


func _exit_tree() -> void:
	if GameEvents != null and GameEvents.has_signal("player_hit_enemy"):
		if GameEvents.player_hit_enemy.is_connected(_on_player_hit_enemy):
			GameEvents.player_hit_enemy.disconnect(_on_player_hit_enemy)


func _process(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer >= 0.1:
		_scan_timer = 0.0
		_update_state()
		_update_cd_state()

	# 命中变红期间每帧重绘
	var hit_active := _hit_timer > 0.0
	if hit_active:
		_hit_timer = maxf(_hit_timer - delta, 0.0)
		queue_redraw()
		_last_hit_active = _hit_timer > 0.0
		return

	if _last_hit_active:
		_last_hit_active = false
		queue_redraw()
		return

	# 仅在瞄准/锁定/冷却状态发生变化时重绘，避免每帧无意义 queue_redraw
	var cd_sig := _cd_signature()
	if _is_targeting != _last_drawn_targeting or _is_aiming != _last_drawn_aiming or cd_sig != _last_cd_sig:
		_last_drawn_targeting = _is_targeting
		_last_drawn_aiming = _is_aiming
		_last_cd_sig = cd_sig
		queue_redraw()


## 响应玩家命中敌人：触发已有准心变红反馈
func _on_player_hit_enemy(hit_data: Dictionary = {}) -> void:
	var is_crit := bool(hit_data.get("is_crit", false))
	play_hit_flash(is_crit)


## 播放命中变红（对外 API；内部复用 COL_TARGETING）
func play_hit_flash(is_crit: bool = false) -> void:
	_hit_is_crit = is_crit
	_hit_duration = HIT_FLASH_CRIT_DURATION if is_crit else HIT_FLASH_DURATION
	_hit_timer = _hit_duration
	_last_hit_active = true
	queue_redraw()


## 兼容旧测试/调用名
func play_hitmarker(is_crit: bool = false) -> void:
	play_hit_flash(is_crit)


func is_hit_flash_active() -> bool:
	return _hit_timer > 0.0


func is_hitmarker_active() -> bool:
	return is_hit_flash_active()


func _hit_progress() -> float:
	## 0 = 刚触发, 1 = 结束
	if _hit_duration <= 0.0:
		return 1.0
	return 1.0 - clampf(_hit_timer / _hit_duration, 0.0, 1.0)


func _update_state() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			return
	# 瞄准状态
	if "is_weapon_aiming" in _player:
		_is_aiming = _player.is_weapon_aiming
	else:
		_is_aiming = false
	# 射线检测是否命中敌人
	_is_targeting = _check_targeting_enemy()


## 拉取玩家近战冷却状态（每次扫描刷新，绘制时比对签名决定是否重绘）
func _update_cd_state() -> void:
	_cd_mode = 0
	_cd_primary_fill = 1.0
	_cd_secondary_fill = 1.0
	_cd_reload_fill = 1.0
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null or not is_instance_valid(_player):
		return
	# 远程武器（弓/弩）走各自装弹/蓄力逻辑，不显示近战冷却环
	if "is_active_weapon_ranged" in _player and _player.is_active_weapon_ranged():
		# 弩装弹中以琥珀色环形提示（与近战绿环同半径，二者互斥不重叠）
		if "is_active_weapon_crossbow" in _player and _player.is_active_weapon_crossbow() \
				and "is_crossbow_reloading" in _player and _player.is_crossbow_reloading():
			_cd_mode = 3
			_cd_reload_fill = _player.get_crossbow_reload_fill() if _player.has_method("get_crossbow_reload_fill") else 1.0
		return
	if "has_active_hand_equipment" in _player and not _player.has_active_hand_equipment():
		return
	_cd_primary_fill = _player.get_melee_cd_fill("primary") if _player.has_method("get_melee_cd_fill") else 1.0
	if "can_dual_wield_attack_with_active_equipment" in _player and _player.can_dual_wield_attack_with_active_equipment():
		_cd_mode = 2
		_cd_secondary_fill = _player.get_melee_cd_fill("secondary") if _player.has_method("get_melee_cd_fill") else 1.0
	else:
		_cd_mode = 1


## 冷却状态签名（量化到 1/16，避免每帧重绘；就绪/无武器恒为稳定值）
func _cd_signature() -> String:
	if _cd_mode == 0:
		return "none"
	if _cd_mode == 3:
		return "reload_%d" % int(_cd_reload_fill * 16.0)
	var qp := int(_cd_primary_fill * 16.0)
	if _cd_mode == 1:
		return "ring_%d" % qp
	var qs := int(_cd_secondary_fill * 16.0)
	return "dual_%d_%d" % [qp, qs]


func _check_targeting_enemy() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var cam = _player.get("camera") if "camera" in _player else null
	if cam == null or not is_instance_valid(cam):
		return false
	var camera: Camera3D = cam as Camera3D
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z.normalized()
	var to := from + forward * 60.0
	var space := camera.get_world_3d()
	if space == null:
		return false
	var ds := space.direct_space_state
	if ds == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	query.collision_mask = PhysicsSetup.LAYER_ENEMY
	var result := ds.intersect_ray(query)
	return not result.is_empty()


func _find_player() -> Node:
	var gs := Service.game_state()
	if gs and gs.get("current_player") and is_instance_valid(gs.get("current_player")):
		return gs.current_player
	return null


func _draw() -> void:
	var c := size / 2.0
	# 坐标取整，确保锐利像素渲染
	var cx: int = int(c.x)
	var cy: int = int(c.y)

	var hit_active := _hit_timer > 0.0
	var expand := 0.0
	if hit_active:
		# 轻微外扩后回落，仍是原十字准心，不另画 X
		var t := _hit_progress()
		var pulse := sin(clampf(t, 0.0, 1.0) * PI)
		expand = HIT_FLASH_EXPAND_PX * pulse
		if _hit_is_crit:
			expand *= 1.35

	# 命中反馈 = 已有 COL_TARGETING 变红；暴击略提亮
	var color: Color = COL_DEFAULT
	if hit_active:
		color = COL_TARGETING
		if _hit_is_crit:
			color = color.lightened(0.25)
	elif _is_targeting:
		color = COL_TARGETING
	elif _is_aiming:
		color = COL_AIMING

	# 十字准心：上下左右四条臂，中间留空隙（全部整数坐标）
	var thick: int = int(arm_thickness)
	var l: int = int(round(arm_length + expand))
	var g: int = int(round(center_gap + expand * 0.35))
	# 上
	draw_rect(Rect2(cx - thick / 2, cy - g - l, thick, l), color, true)
	# 下
	draw_rect(Rect2(cx - thick / 2, cy + g, thick, l), color, true)
	# 左
	draw_rect(Rect2(cx - g - l, cy - thick / 2, l, thick), color, true)
	# 右
	draw_rect(Rect2(cx + g, cy - thick / 2, l, thick), color, true)
	# 中心点（瞄准或命中闪时显示，2x2 像素方块）
	if _is_aiming or hit_active:
		draw_rect(Rect2(cx - 1, cy - 1, 2, 2), color, true)
	# 近战冷却指示
	_draw_cd(cx, cy)


## 绘制冷却指示（像素块环/半扇）。三种互斥模式：1=近战完整环，2=双持半扇，3=弩装弹环
func _draw_cd(cx: int, cy: int) -> void:
	if _cd_mode == 1:
		# 单手/双手：完整环形。就绪(满)时隐藏以保持画面干净
		if _cd_primary_fill >= 0.999:
			return
		_draw_pixel_arc(cx, cy, RING_RADIUS, RING_THICK, _cd_primary_fill, 0.0, TAU, RING_SEGS)
	elif _cd_mode == 2:
		# 双持：左半扇=副手(左手)，右半扇=主手(右手)。均就绪则隐藏
		if _cd_primary_fill >= 0.999 and _cd_secondary_fill >= 0.999:
			return
		# 半扇只占 180° 弧，段数减半，避免相邻像素块互相重叠(糊成色块)
		var half_segs: int = int(RING_SEGS / 2)
		_draw_pixel_arc(cx, cy, RING_RADIUS, RING_THICK, _cd_secondary_fill, PI * 0.5, PI * 1.5, half_segs)  # 左侧半扇
		_draw_pixel_arc(cx, cy, RING_RADIUS, RING_THICK, _cd_primary_fill, -PI * 0.5, PI * 0.5, half_segs)  # 右侧半扇
	elif _cd_mode == 3:
		# 弩装弹环（琥珀色，与近战绿环互斥不重叠）
		if _cd_reload_fill >= 0.999:
			return
		_draw_pixel_arc(cx, cy, RING_RADIUS, RING_THICK, _cd_reload_fill, 0.0, TAU, RING_SEGS, COL_RELOAD_BRIGHT, COL_RELOAD_DIM)
	# _cd_mode == 0：无武器/非冷却状态，不绘制


## 以像素块沿圆弧绘制冷却进度：已恢复段亮色，冷却中段暗色
## segs 控制沿弧的像素块数量——完整环用 RING_SEGS，半扇用其一半，保证块间距 > 块宽、互不重叠
## col_on/col_off 默认近战绿/灰，可覆写为装弹琥珀色等
func _draw_pixel_arc(cx: int, cy: int, radius: int, thick: int, fill: float, a0: float, a1: float, segs: int, col_on := COL_CD_READY, col_off := COL_CD_COOLING) -> void:
	var h: int = thick / 2
	var span := a1 - a0
	for i in segs:
		var tt := (float(i) + 0.5) / float(segs)   # 0..1 沿弧位置
		var on := tt <= fill
		var col := col_on if on else col_off
		var ang := a0 + span * tt
		var x := int(round(cx + cos(ang) * radius))
		var y := int(round(cy + sin(ang) * radius))
		draw_rect(Rect2(x - h, y - h, thick, thick), col, true)


## 外部设置玩家引用（供测试用）
func set_player(p: Node) -> void:
	_player = p
