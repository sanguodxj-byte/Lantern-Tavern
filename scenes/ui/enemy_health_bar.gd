class_name EnemyHealthBar
extends Control

## 屏幕顶部的敌人血量条。
## 使用射线检测从摄像机中心发射，命中敌人时显示其血量。
## 射线会被墙体阻挡（PhysicsDirectSpaceState3D.intersect_ray 自然处理）。
##
## 关键修复：
##   1. 持续追踪：有目标时仍定期重新射线检测，视角离开后自动淡出
##   2. 碰撞掩码：仅检测敌人+环境+场景物体，排除材料/投掷物干扰
##   3. 名称识别：优先使用 enemy_base_type metadata，避免节点名后缀导致未知怪物

const PIXEL_FONT := preload("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf")
const Service := preload("res://globals/core/service.gd")

@export var ray_length: float = 60.0
@export var bar_width: int = 240
@export var bar_height: int = 18
@export var pixel_size: int = 4  # 像素方块边长，填充对齐到此网格

var _target_enemy: Enemy = null
var _visible_timer: float = 0.0
const DISPLAY_LINGER: float = 0.5  # 失去目标后血条停留时间
const SCAN_INTERVAL: float = 0.1   # 射线扫描间隔（秒）
var _scan_timer: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(bar_width + 40, bar_height + 30)
	# 隐藏直到有目标
	modulate.a = 0.0
	set_process(true)


func _process(delta: float) -> void:
	# 目标失效（被释放）：进入淡出
	if _target_enemy != null and not is_instance_valid(_target_enemy):
		_target_enemy = null
		_visible_timer = 0.0

	# 节流射线扫描：无论有无目标，都定期重新检测
	_scan_timer -= delta
	var should_scan := _scan_timer <= 0.0
	if should_scan:
		_scan_timer = SCAN_INTERVAL

	if _target_enemy == null:
		# 无目标：淡出或扫描新目标
		if _visible_timer > 0.0:
			_visible_timer -= delta
			modulate.a = move_toward(modulate.a, 0.0, delta * 6.0)
			queue_redraw()
			return
		if should_scan:
			var enemy := _raycast_for_enemy()
			if enemy != null:
				_target_enemy = enemy
				_visible_timer = DISPLAY_LINGER
				queue_redraw()
		return

	# 有目标：定期重新射线检测，验证玩家是否仍在注视该敌人
	if should_scan:
		var hit_enemy := _raycast_for_enemy()
		if hit_enemy != _target_enemy:
			# 射线不再命中当前目标（看向别处/被墙挡住/命中其他敌人）
			# 开始淡出计时，但暂不清除目标（让 linger 机制平滑过渡）
			_visible_timer -= delta * 10.0  # 加速消耗 timer
			if _visible_timer <= 0.0:
				_target_enemy = null
				_visible_timer = 0.0
				modulate.a = move_toward(modulate.a, 0.0, delta * 6.0)
				queue_redraw()
				return
		else:
			# 仍在注视目标：重置 linger timer
			_visible_timer = DISPLAY_LINGER

	# 有目标：平滑淡入 + 数值跟踪
	modulate.a = move_toward(modulate.a, 1.0, delta * 6.0)
	queue_redraw()


func _raycast_for_enemy() -> Enemy:
	var player := _find_player()
	if player == null or not is_instance_valid(player):
		return null
	var camera = player.get("camera") if "camera" in player else null
	if camera == null or not is_instance_valid(camera):
		return null
	var cam: Camera3D = camera as Camera3D
	var from := cam.global_position
	# 摄像机正前方
	var forward := -cam.global_transform.basis.z.normalized()
	var to := from + forward * ray_length

	var space := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# 排除玩家自身
	query.exclude = [player.get_rid()]
	# 碰撞掩码：仅检测敌人 + 环境（墙） + 场景物体（柱子/家具），
	# 排除可拾取物/投掷物/投射物/触发器，避免材料干扰射线
	query.collision_mask = PhysicsSetup.LAYER_ENEMY | PhysicsSetup.LAYER_ENVIRONMENT | PhysicsSetup.LAYER_SCENE_OBJECT
	var result := space.intersect_ray(query)
	if result.is_empty():
		return null
	var collider = result["collider"]
	# 直接命中敌人
	if collider is Enemy:
		return collider as Enemy
	# 命中敌人的子节点（如 hitbox/碰撞体）— 向上查找 Enemy 父级
	var parent: Node = collider.get_parent()
	while parent != null:
		if parent is Enemy:
			return parent as Enemy
		parent = parent.get_parent()
	return null


func _find_player() -> Node:
	var gs := Service.game_state()
	if gs and gs.get("current_player") and is_instance_valid(gs.get("current_player")):
		return gs.current_player
	return null


func _draw() -> void:
	if _target_enemy == null or not is_instance_valid(_target_enemy):
		return
	var enemy := _target_enemy

	# 敌人名称
	var ename := _enemy_name(enemy)
	var health: HealthComponent = enemy.health if "health" in enemy else null
	if health == null:
		return

	# 居中绘制
	var cx := size.x / 2.0
	var bar_y: float = 24.0
	var bar_x := cx - bar_width / 2.0

	# 名称
	draw_string(PIXEL_FONT, Vector2(bar_x, bar_y - 6), ename, HORIZONTAL_ALIGNMENT_LEFT, bar_width, 12)

	# 背景框
	var bg_rect := Rect2(bar_x, bar_y, bar_width, bar_height)
	draw_rect(bg_rect, Color(0.06, 0.065, 0.075, 0.85), true)
	draw_rect(bg_rect, Color(0.3, 0.2, 0.12, 0.9), false, 2)

	# 血量填充（对齐像素网格）
	var ratio: float = float(health.current_life) / float(maxi(health.max_life, 1))
	var fill_w: int = int(bar_width * ratio)
	# 对齐到 pixel_size 网格
	fill_w = floori(fill_w / pixel_size) * pixel_size
	fill_w = maxi(fill_w, 0)
	if fill_w > 0:
		var fill_rect := Rect2(bar_x, bar_y, fill_w, bar_height)
		var hp_color: Color = _hp_color(ratio)
		draw_rect(fill_rect, hp_color, true)
		# 顶部高光（像素方块高度）
		draw_rect(Rect2(bar_x, bar_y, fill_w, pixel_size), hp_color.lightened(0.35), true)

	# 数值文本
	var hp_text := "%d / %d" % [health.current_life, health.max_life]
	draw_string(PIXEL_FONT, Vector2(bar_x + bar_width / 2.0 - 30, bar_y + bar_height + 14), hp_text, HORIZONTAL_ALIGNMENT_LEFT, 60, 12)

	# 精英怪标记
	if "is_elite" in enemy and enemy.is_elite:
		draw_string(PIXEL_FONT, Vector2(bar_x + bar_width - 30, bar_y - 6), tr("[精英]"), HORIZONTAL_ALIGNMENT_LEFT, 60, 12)


## 获取敌人显示名称。
## 优先使用 DungeonSpawner 注入的 enemy_base_type metadata，
## 避免 Godot 运行时节点名后缀（如 @Goblin@123）导致匹配失败。
func _enemy_name(enemy: Enemy) -> String:
	# 优先从 metadata + DungeonSpawner roster
	var base_type := ""
	if enemy.has_meta("enemy_base_type"):
		base_type = String(enemy.get_meta("enemy_base_type"))
	if not base_type.is_empty():
		var spawner: Node = Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")
		if spawner != null and spawner.has_method("get_display_name"):
			var dn := String(spawner.call("get_display_name", base_type))
			if not dn.is_empty() and dn != base_type:
				return tr(dn)
		match base_type:
			"goblin":
				return tr("哥布林")
			"rat":
				return tr("巨鼠")
			"skeleton":
				return tr("骷髅兵")
			"slime":
				return tr("史莱姆")
			"troll":
				return tr("巨魔")
			"necrolord":
				return tr("死灵领主")
			"dragon":
				return tr("巨龙")
			"minotaur":
				return tr("牛头怪")
			"rock_golem":
				return tr("岩石魔像")
			"zombie":
				return tr("僵尸")
	
	# 回退：解析节点名（处理 @后缀）
	var n := String(enemy.name).to_lower()
	var at_idx := n.find("@")
	if at_idx >= 0:
		n = n.substr(0, at_idx)
	if n.contains("goblin"):
		return tr("哥布林")
	if n.contains("rat"):
		return tr("巨鼠")
	if n.contains("skeleton"):
		return tr("骷髅兵")
	if n.contains("slime"):
		return tr("史莱姆")
	if n.contains("troll"):
		return tr("巨魔")
	if n.contains("necrolord"):
		return tr("死灵领主")
	if n.contains("dragon"):
		return tr("巨龙")
	if n.contains("minotaur"):
		return tr("牛头怪")
	if n.contains("rock_golem") or n.contains("golem"):
		return tr("岩石魔像")
	if n.contains("zombie"):
		return tr("僵尸")
	return tr("未知敌人")


func _hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Color(0.2, 0.8, 0.2)
	elif ratio > 0.25:
		return Color(0.9, 0.7, 0.2)
	return Color(0.9, 0.2, 0.15)


## 外部设置目标敌人（供测试用）
func set_target(enemy: Enemy) -> void:
	_target_enemy = enemy
	_visible_timer = DISPLAY_LINGER
