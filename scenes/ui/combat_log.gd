class_name CombatLog
extends Control

## Roguelike 风格信息日志（左上角）。
## 显示游戏过程和战斗信息，自动滚动，旧条目淡出。
## 连接 GameEvents 信号和敌人死亡信号。

const PIXEL_FONT := preload("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf")

@export var max_lines: int = 9
@export var line_height: int = 16
@export var bg_alpha: float = 0.55

var _entries: Array[Dictionary] = []  # {text, color, time}
var _connected_enemies: Array[Node] = []
var _scan_timer: float = 0.0
var _dirty: bool = true  # 条目变化时置位，触发重绘


func _ready() -> void:
	custom_minimum_size = Vector2(360, max_lines * line_height + 12)
	_connect_signals()


func _connect_signals() -> void:
	if GameEvents:
		GameEvents.player_hurt.connect(_on_player_hurt)
		GameEvents.player_dead.connect(_on_player_dead)
		GameEvents.player_spawned.connect(_on_player_spawned)
		GameEvents.shield_changed.connect(_on_shield_changed)
		GameEvents.weapon_changed.connect(_on_weapon_changed)
		GameEvents.current_keys_changed.connect(_on_keys_changed)


func _process(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer >= 1.0:
		_scan_timer = 0.0
		_connect_enemy_signals()
	# 仅条目变化时重绘，而非每帧 queue_redraw
	if _dirty:
		_dirty = false
		queue_redraw()


func _connect_enemy_signals() -> void:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e is Enemy and not _connected_enemies.has(e):
			if e.has_signal("dead"):
				e.dead.connect(_on_enemy_dead.bind(e))
				_connected_enemies.append(e)
	# 清理失效引用
	_connected_enemies = _connected_enemies.filter(func(e): return is_instance_valid(e))


# ── 事件处理 ──────────────────────────────────────────────
func _on_player_spawned(_player: Player) -> void:
	push_entry(tr("你踏入了地牢深处…"), Color(0.7, 0.85, 1.0))


func _on_player_hurt(player: Player) -> void:
	var hp_before := player.health.current_life
	# current_life 已被扣减，估算伤害
	push_entry(tr("受到伤害！剩余生命: %d") % hp_before, Color(1.0, 0.4, 0.3))


func _on_player_dead() -> void:
	push_entry(tr("你倒下了…"), Color(1.0, 0.2, 0.15))


func _on_shield_changed(shield_data: Resource) -> void:
	if shield_data:
		var sname: String = ""
		if "name" in shield_data:
			sname = String(shield_data.name)
		if sname.is_empty():
			sname = tr("盾牌")
		push_entry(tr("装备盾牌: %s") % sname, Color(0.8, 0.8, 0.9))


func _on_weapon_changed(weapon_data: WeaponData) -> void:
	if weapon_data:
		push_entry(tr("装备武器: %s") % weapon_data.name, Color(0.9, 0.85, 0.5))


func _on_keys_changed(_color) -> void:
	push_entry(tr("获得钥匙"), Color(1.0, 0.85, 0.3))


func _on_enemy_dead(_transform: Transform3D, enemy: Node) -> void:
	var ename := _enemy_display_name(enemy)
	push_entry(tr("击败了 %s") % ename, Color(0.5, 1.0, 0.4))


func _enemy_display_name(enemy: Node) -> String:
	if enemy == null:
		return tr("敌人")
	if "is_elite" in enemy and enemy.is_elite:
		return tr("精英") + " " + _base_enemy_name(enemy)
	return _base_enemy_name(enemy)


func _base_enemy_name(enemy: Node) -> String:
	var n := String(enemy.name).to_lower()
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
	return tr("怪物")


# ── 日志管理 ──────────────────────────────────────────────
func push_entry(text: String, color: Color = Color.WHITE) -> void:
	if text.is_empty():
		return
	_entries.append({
		"text": text,
		"color": color,
		"time": Time.get_ticks_msec(),
	})
	while _entries.size() > max_lines:
		_entries.pop_front()
	_dirty = true


func clear() -> void:
	_entries.clear()
	_dirty = true


func get_entries() -> Array:
	return _entries.duplicate(true)


# ── 绘制 ──────────────────────────────────────────────────
func _draw() -> void:
	var panel_rect := Rect2(0, 0, size.x, size.y)
	# 半透明背景
	draw_rect(panel_rect, Color(0.04, 0.03, 0.06, bg_alpha), true)
	# 像素边框
	draw_rect(panel_rect, Color(0.25, 0.18, 0.10, 0.7), false, 2)

	if _entries.is_empty():
		return

	var y_offset: float = 6.0
	var count := _entries.size()
	for i in range(count):
		var entry: Dictionary = _entries[i]
		# 越旧越透明
		var alpha: float = 1.0
		if i < count - 5:
			alpha = 0.4
		elif i < count - 3:
			alpha = 0.7
		var color: Color = entry["color"]
		color.a *= alpha
		var text: String = entry["text"]
		# 截断过长文本
		if text.length() > 28:
			text = text.substr(0, 27) + "…"
		draw_string(PIXEL_FONT, Vector2(8, y_offset + 12), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 12, color)
		y_offset += line_height
