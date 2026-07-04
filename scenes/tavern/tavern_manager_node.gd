extends Node3D
class_name TavernInterior

# 酒馆 3D 视觉场景管理节点。
# 与全局 TavernManager (autoload) 协作：本节点只负责空间/座位/顾客落座，
# 数据与昼夜切换仍由 globals/tavern_manager.gd 统一管理。

const PLAYER_PREFAB := preload("res://scenes/characters/player/player.tscn")

@onready var customer_seats: Node3D = $CustomerSeats
@onready var stations: Node3D = $Stations
@onready var lights: Node3D = $Lights
@onready var decor: Node3D = $Decor
@onready var player_spawn: Marker3D = $PlayerSpawn

# 缓存手动铺设的座位 Marker3D
var seat_markers: Array[Marker3D] = []

func _ready() -> void:
	_spawn_player()
	_collect_seats()
	_setup_hud_if_night_phase()
	# 注册为当前关卡，供丢出物品等 add_child 使用
	if GameState:
		GameState.register_level(self)
	print("[TavernInterior] Ready. Seats available: ", seat_markers.size())

func _spawn_player() -> void:
	if player_spawn:
		var player: Player = PLAYER_PREFAB.instantiate()
		player.global_transform = player_spawn.global_transform
		add_child(player)
		print("[TavernInterior] Player spawned at bar counter")

# 仅在夜晚营业阶段挂载经营 HUD；主菜单背景视口等非营业场景保持纯 3D。
# 判断依据全局 TavernManager.current_phase，避免被误识别为 UI 界面。
func _setup_hud_if_night_phase() -> void:
	var tm: Node = _get_tavern_manager()
	if tm == null:
		return
	if tm.current_phase == tm.Phase.NIGHT_TAVERN:
		_mount_tavern_hud()
	elif tm.current_phase == tm.Phase.DAY_EXPEDITION:
		_mount_expedition_prompt()

## 夜晚营业阶段挂载经营 HUD
func _mount_tavern_hud() -> void:
	var hud_scene: PackedScene = load("res://scenes/ui/tavern_ui.tscn")
	if hud_scene == null:
		return
	var hud: Control = hud_scene.instantiate() as Control
	var layer := CanvasLayer.new()
	layer.name = "HUDLayer"
	layer.add_child(hud)
	add_child(layer)

## 白天探险阶段挂载出发提示（按住 F 环形进度条）
func _mount_expedition_prompt() -> void:
	var prompt_scene: PackedScene = load("res://scenes/ui/expedition_prompt.tscn")
	if prompt_scene == null:
		return
	var prompt: Control = prompt_scene.instantiate() as Control
	var layer := CanvasLayer.new()
	layer.name = "ExpeditionPromptLayer"
	layer.add_child(prompt)
	add_child(layer)

# 安全获取 autoload TavernManager（避免编辑器/测试环境无 autoload 时崩溃）。
func _get_tavern_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	# autoload 节点名为 TavernManager，挂在 root 下
	return tree.root.get_node_or_null("TavernManager")

# 收集所有命名以 "seat_" 开头的 Marker3D 作为顾客落座点。
# 顺序按节点名自然排序，保证生成器取座位的结果稳定可预测。
# 用 find_children 递归遍历所有后代（座位嵌套在 Table_xx 之下）。
func _collect_seats() -> void:
	seat_markers.clear()
	if customer_seats == null:
		return
	var found := customer_seats.find_children("seat_*", "Marker3D", true, false)
	for node in found:
		seat_markers.append(node as Marker3D)
	seat_markers.sort_custom(_compare_seat_name)

func _compare_seat_name(a: Marker3D, b: Marker3D) -> bool:
	return a.name.naturalcasecmp_to(b.name) < 0

# 返回第 idx 个座位（越界则返回 null）。供 customer_spawner 调用。
func get_seat(idx: int) -> Marker3D:
	if idx < 0 or idx >= seat_markers.size():
		return null
	return seat_markers[idx]

func seat_count() -> int:
	return seat_markers.size()
