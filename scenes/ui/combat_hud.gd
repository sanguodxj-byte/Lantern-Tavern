class_name CombatHUD
extends CanvasLayer

## 战斗视角 UI —— 在酒馆和所有地牢场景统一使用。
## 组件：
##   右上角: 旋转小地图 (CombatMinimap)
##   左下角: 血量 + 蓝量 (PixelBar x2)
##   左上角: Roguelike 信息日志 (CombatLog)
##   顶部居中: 鼠标指向敌人血量条 (EnemyHealthBar)
##
## 自动注入 ManaComponent 到 Player（若不存在）。

const ManaComponentScript := preload("res://scenes/characters/component/mana_component.gd")
const KEY_TEXTURE_PREFAB := preload("res://scenes/ui/key_texture.tscn")

@onready var minimap: CombatMinimap = $MinimapContainer/Minimap
@onready var time_label: Label = $MinimapContainer/TimePanel/TimeLabel
@onready var dark_erosion_label: Label = $MinimapContainer/DarkErosionPanel/DarkErosionLabel
@onready var hp_bar: PixelBar = $BottomLeft/HPBar
@onready var mp_bar: PixelBar = $BottomLeft/MPBar
@onready var combat_log: CombatLog = $TopLeft/CombatLog
@onready var enemy_hp_bar: EnemyHealthBar = $TopCenter/EnemyHealthBar
# 武器 / 护盾 / 钥匙（原 UI 层的战斗节点，已收口到 CombatHUD 作为唯一战斗 HUD）
@onready var weapon_icon: TextureRect = $BottomLeftExtras/WeaponIcon
@onready var weapon_indicator: StatIndicator = $BottomLeftExtras/WeaponIndicator
@onready var shield_icon: TextureRect = $BottomLeftExtras/ShieldIcon
@onready var shield_indicator: StatIndicator = $BottomLeftExtras/ShieldIndicator
@onready var key_container: HBoxContainer = $KeyContainer

var _player: Node = null
var _mana: ManaComponent = null
var latest_pressure_snapshot: Dictionary = {}


func _ready() -> void:
	layer = 15
	_update_pressure_labels({})
	# 初始化像素条
	if hp_bar:
		hp_bar.bar_color = Color(0.85, 0.15, 0.12)
		hp_bar.label_text = tr("HP")
	if mp_bar:
		mp_bar.bar_color = Color(0.2, 0.35, 0.9)
		mp_bar.label_text = tr("MP")
	# 连接玩家事件
	if GameEvents:
		GameEvents.player_spawned.connect(_on_player_spawned)
		GameEvents.player_hurt.connect(_on_player_hurt)
		GameEvents.weapon_changed.connect(_on_weapon_changed)
		GameEvents.shield_changed.connect(_on_shield_changed)
		GameEvents.current_keys_changed.connect(_on_current_keys_changed)


func _process(_delta: float) -> void:
	_ensure_player()
	_update_bars()


func _ensure_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.get("current_player") and is_instance_valid(gs.get("current_player")):
		_player = gs.current_player
		_inject_mana()


func _inject_mana() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# 检查是否已有 ManaComponent
	if _player.has_node("ManaComponent"):
		_mana = _player.get_node("ManaComponent") as ManaComponent
		return
	_mana = ManaComponentScript.new()
	_mana.name = "ManaComponent"
	# 根据属性面板魔力属性调整最大蓝量
	var ap := get_node_or_null("/root/AttrPanel")
	if ap and ap.has_method("get_attr"):
		var mag: int = ap.get_attr("mag")
		_mana.set_max(50 + mag * 10)
		_mana.current_mana = _mana.max_mana
	_player.add_child(_mana)


func _update_bars() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# 血量
	if hp_bar and "health" in _player:
		var h = _player.health
		if h:
			hp_bar.set_values(h.current_life, h.max_life)
	# 蓝量
	if mp_bar and _mana:
		mp_bar.set_values(_mana.current_mana, _mana.max_mana)


func _on_player_spawned(player: Player) -> void:
	_player = player
	_inject_mana()


func _on_player_hurt(player: Player) -> void:
	_player = player


## 武器 / 护盾 / 钥匙显示（原 UI 战斗节点，已收口到此作为唯一战斗 HUD，所有空间通用）
func _on_weapon_changed(weapon_data: WeaponData) -> void:
	weapon_icon.visible = weapon_data != null
	weapon_indicator.visible = weapon_data != null
	if weapon_data:
		weapon_indicator.refresh(weapon_data.condition, weapon_data.max_condition)


func _on_shield_changed(shield_data: Resource) -> void:
	shield_icon.visible = shield_data != null
	shield_indicator.visible = shield_data != null
	if shield_data:
		shield_indicator.refresh(shield_data.condition, shield_data.max_condition)


func _on_current_keys_changed(_color: Door.KeyColor) -> void:
	for child: TextureRect in key_container.get_children():
		child.queue_free()
	for key_color: Door.KeyColor in Door.KeyColor.values():
		if GameState.has_key(key_color):
			var texture := KEY_TEXTURE_PREFAB.instantiate() as TextureRect
			key_container.add_child(texture)
			texture.modulate = Door.COLOR_MAP[key_color]


func update_pressure(snapshot: Dictionary) -> void:
	latest_pressure_snapshot = snapshot.duplicate()
	_update_pressure_labels(latest_pressure_snapshot)


func _update_pressure_labels(snapshot: Dictionary) -> void:
	var clock_minutes := int(snapshot.get("clock_minutes", 10 * 60))
	var hour := clock_minutes / 60
	var minute := clock_minutes % 60
	if time_label != null:
		time_label.text = "%02d:%02d / 18:00" % [hour, minute]

	var erosion := int(round(float(snapshot.get("threat_level", 0.0))))
	var band := String(snapshot.get("pressure_band", "safe"))
	var suffix := "稳定"
	match band:
		"critical":
			suffix = "失控"
		"leave_soon":
			suffix = "撤离"
		"tense":
			suffix = "加深"
		_:
			suffix = "稳定"
	if dark_erosion_label != null:
		dark_erosion_label.text = "暗蚀 %03d%%  %s" % [erosion, suffix]


## 切换场景空间时调用（由 World 或 UI 调用）
func set_world_space(_space: String) -> void:
	# 战斗 HUD 在所有空间都可见
	visible = true
