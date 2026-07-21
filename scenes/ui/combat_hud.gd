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

const BuffIconScript := preload("res://scenes/ui/buff_icon.gd")
const Service := preload("res://globals/core/service.gd")

@onready var minimap: CombatMinimap = $MinimapContainer/Minimap
@onready var time_label: Label = $MinimapContainer/TimePanel/TimeLabel
@onready var dark_erosion_label: Label = $MinimapContainer/DarkErosionPanel/DarkErosionLabel
@onready var hp_bar: PixelBar = $BottomLeft/HPBar
@onready var mp_bar: PixelBar = $BottomLeft/MPBar
@onready var combat_log: CombatLog = $TopLeft/CombatLog
@onready var enemy_hp_bar: EnemyHealthBar = $TopCenter/EnemyHealthBar
# 武器 / 护盾（原 UI 层的战斗节点，已收口到 CombatHUD 作为唯一战斗 HUD）
@onready var weapon_icon: TextureRect = $BottomLeftExtras/WeaponIcon
@onready var weapon_indicator: StatIndicator = $BottomLeftExtras/WeaponIndicator
@onready var shield_icon: TextureRect = $BottomLeftExtras/ShieldIcon
@onready var shield_indicator: StatIndicator = $BottomLeftExtras/ShieldIndicator
@onready var buff_container: HBoxContainer = $BottomLeft/BuffContainer
@onready var magic_shield_bar: Control = $BottomLeft/MagicShieldBar
@onready var physical_shield_bar: Control = $BottomLeft/PhysicalShieldBar

var _player: Node = null
var _mana: ManaComponent = null
var latest_pressure_snapshot: Dictionary = {}
var _buff_icons: Dictionary = {}  # { buff_type: Node (BuffIcon) }

# ---- 脏标记优化：避免每帧无条件刷新所有 UI ----
var _bars_dirty := true       # 血量/蓝量变化时置位
var _shields_dirty := true    # 护盾变化时置位
var _buffs_dirty := true      # buff 变化时置位
var _last_hp_current := -1   # 上次血量值
var _last_hp_max := -1       # 上次最大血量
var _last_mp_current := -1   # 上次蓝量值
var _last_mp_max := -1       # 上次最大蓝量
var _last_shield_cond := -1  # 上次盾牌耐久
var _last_shield_max := -1   # 上次盾牌最大耐久
var _last_buffs_snapshot: Dictionary = {}  # 上次 buff 快照


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

		# 经营 HUD 打开时整层隐藏，避免战斗 UI 泄露并拦截经营面板鼠标点击
		GameEvents.tavern_hud_visibility_changed.connect(_on_tavern_hud_visibility_changed)


func _process(_delta: float) -> void:
	_ensure_player()
	_check_bars_changed()
	_check_shields_changed()
	_check_buffs_changed()
	if _bars_dirty:
		_bars_dirty = false
		_update_bars()
	if _shields_dirty:
		_shields_dirty = false
		_update_shields()
	if _buffs_dirty:
		_buffs_dirty = false
		_update_buffs()


## 检测血量/蓝量是否变化，变化时标记脏
func _check_bars_changed() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if hp_bar and "health" in _player:
		var h = _player.health
		if h:
			if h.current_life != _last_hp_current or h.max_life != _last_hp_max:
				_last_hp_current = h.current_life
				_last_hp_max = h.max_life
				_bars_dirty = true
	if mp_bar and _mana:
		if _mana.current_mana != _last_mp_current or _mana.max_mana != _last_mp_max:
			_last_mp_current = _mana.current_mana
			_last_mp_max = _mana.max_mana
			_bars_dirty = true


## 检测护盾状态是否变化
func _check_shields_changed() -> void:
	if _player == null or not is_instance_valid(_player):
		if magic_shield_bar and magic_shield_bar.is_active():
			_shields_dirty = true
		return
	# 法术护盾：buff 存在性变化时标记脏
	var buffs: Dictionary = _player.buffs.get_buffs_dict()
	var has_absorb := buffs.has("damage_absorb")
	var was_absorb := _last_buffs_snapshot.has("damage_absorb")
	if has_absorb != was_absorb:
		_shields_dirty = true
	# 物理护盾：盾牌耐久变化时标记脏
	var is_blocking: bool = _player.is_currently_blocking()
	var shield_cond := -1
	var shield_max := -1
	if is_blocking and "equipment" in _player and _player.equipment:
		var shield_data = _player.equipment.get_active_shield_data()
		if shield_data:
			shield_cond = shield_data.condition
			shield_max = shield_data.max_condition
	if shield_cond != _last_shield_cond or shield_max != _last_shield_max:
		_last_shield_cond = shield_cond
		_last_shield_max = shield_max
		_shields_dirty = true


## 检测 buff 列表是否变化
func _check_buffs_changed() -> void:
	if _player == null or not is_instance_valid(_player):
		if not _last_buffs_snapshot.is_empty():
			_buffs_dirty = true
			_last_buffs_snapshot = {}
		return
	var buffs: Dictionary = _player.buffs.get_buffs_dict()
	if buffs.size() != _last_buffs_snapshot.size():
		_last_buffs_snapshot = buffs.duplicate()
		_buffs_dirty = true
		return
	for key in buffs.keys():
		if not _last_buffs_snapshot.has(key):
			_last_buffs_snapshot = buffs.duplicate()
			_buffs_dirty = true
			return


func _ensure_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var gs := Service.game_state()
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
	var ap := Service.attr_panel()
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


## 每帧同步护盾条显示
func _update_shields() -> void:
	if _player == null or not is_instance_valid(_player):
		if magic_shield_bar:
			magic_shield_bar.deactivate()
		if physical_shield_bar:
			physical_shield_bar.deactivate()
		return
	_update_magic_shield()
	_update_physical_shield()


## 法术护盾：来自 damage_absorb buff（按最大生命值百分比吸收伤害）
func _update_magic_shield() -> void:
	if magic_shield_bar == null:
		return
	var buffs: Dictionary = _player.buffs.get_buffs_dict()
	if buffs.has("damage_absorb"):
		var buff: Dictionary = buffs["damage_absorb"]
		var absorb_percent: float = float(buff.get("value", 0.0))
		var max_life: int = 100
		if "health" in _player and _player.health:
			max_life = _player.health.max_life
		var absorb_amount := int(round(max_life * absorb_percent / 100.0))
		magic_shield_bar.set_values(absorb_amount, max_life)
	else:
		magic_shield_bar.deactivate()


## 物理护盾：持盾右键格挡时显示盾牌耐久
func _update_physical_shield() -> void:
	if physical_shield_bar == null:
		return
	var is_blocking: bool = _player.is_currently_blocking()
	var has_shield: bool = false
	var shield_cond: int = 0
	var shield_max: int = 0
	if is_blocking and "equipment" in _player and _player.equipment:
		var shield_data = _player.equipment.get_active_shield_data()
		if shield_data:
			has_shield = true
			shield_cond = shield_data.condition
			shield_max = shield_data.max_condition
	if has_shield:
		physical_shield_bar.set_values(shield_cond, shield_max)
	else:
		physical_shield_bar.deactivate()


## 每帧同步玩家 buff 到图标显示
func _update_buffs() -> void:
	if buff_container == null:
		return
	if _player == null or not is_instance_valid(_player):
		_clear_all_buff_icons()
		return
	var buffs: Dictionary = _player.buffs.get_buffs_dict()
	# 移除已过期的 buff 图标
	for existing_type in _buff_icons.keys():
		if not buffs.has(existing_type):
			var icon: Node = _buff_icons[existing_type]
			if is_instance_valid(icon):
				icon.queue_free()
			_buff_icons.erase(existing_type)
	# 更新或创建 buff 图标
	for buff_type in buffs.keys():
		var buff_data: Dictionary = buffs[buff_type]
		var remain: float = float(buff_data.get("remaining", 0.0))
		if _buff_icons.has(buff_type):
			var existing: Node = _buff_icons[buff_type]
			if is_instance_valid(existing):
				existing.remaining = remain
		else:
			var new_icon: Node = BuffIconScript.new()
			buff_container.add_child(new_icon)
			new_icon.setup(buff_type, remain)
			_buff_icons[buff_type] = new_icon


func _clear_all_buff_icons() -> void:
	for buff_type in _buff_icons.keys():
		var icon: Node = _buff_icons[buff_type]
		if is_instance_valid(icon):
			icon.queue_free()
	_buff_icons.clear()


func _on_player_spawned(player: Player) -> void:
	_player = player
	_inject_mana()


func _on_player_hurt(player: Player) -> void:
	_player = player


## 武器 / 护盾显示（原 UI 战斗节点，已收口到此作为唯一战斗 HUD，所有空间通用）
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
	var suffix := tr("Stable")
	match band:
		"critical":
			suffix = tr("Out of Control")
		"leave_soon":
			suffix = tr("Evacuate")
		"tense":
			suffix = tr("Deepening")
		_:
			suffix = tr("Stable")
	if dark_erosion_label != null:
		dark_erosion_label.text = tr("Dark Erosion %03d%%  %s") % [erosion, suffix]


## 切换场景空间时调用（由 World 或 UI 调用）
func set_world_space(_space: String) -> void:
	# 战斗 HUD 在所有空间都可见（经营 HUD 打开时由
	# _on_tavern_hud_visibility_changed 临时整层隐藏）。
	visible = true


## 经营 HUD 显隐时同步切换战斗 HUD：经营界面打开时整层隐藏，
## 既消除战斗 UI 泄露，又让其边角 Control 不再拦截经营面板的鼠标点击。
func _on_tavern_hud_visibility_changed(is_tavern_hud_visible: bool) -> void:
	visible = not is_tavern_hud_visible
