extends Node3D
class_name TavernInterior

# 酒馆 3D 视觉场景管理节点。
# 与全局 TavernManager (autoload) 协作：本节点只负责空间/座位/顾客落座，
# 数据与昼夜切换仍由 globals/tavern_manager.gd 统一管理。

const PLAYER_PREFAB := preload("res://scenes/characters/player/player.tscn")
const SCENE_OBJECT_SCRIPT := preload("res://scenes/props/scene_object.gd")
const TAVERN_BAR_INTERACTION_SCRIPT := preload("res://scenes/tavern/tavern_bar_interaction.gd")
const TAVERN_EQUIPMENT_PANEL_SCENE := preload("res://scenes/ui/tavern_equipment_panel.tscn")
const TUTORIAL_COORDINATOR_SCRIPT := preload("res://scenes/tavern/tutorial_tavern_coordinator.gd")
const SCENE_OBJECT_LAYER := 64

@onready var customer_seats: Node3D = $CustomerSeats
@onready var stations: Node3D = $Stations
@onready var lights: Node3D = $Lights
@onready var decor: Node3D = $Decor
@onready var player_spawn: Marker3D = $PlayerSpawn

# 缓存手动铺设的座位 Marker3D
var seat_markers: Array[Marker3D] = []
var tavern_equipment_layer: CanvasLayer = null
var tavern_equipment_panel: Control = null
var tavern_hud_layer: CanvasLayer = null

func _ready() -> void:
	# 标记为酒馆场景，供子节点（如 VoxelProp._is_in_tavern）向上检测上下文。
	set_meta("is_tavern", true)
	_configure_scene_objects()
	_freeze_tavern_pickables()
	_configure_bar_interaction()
	# 先注册为当前关卡，再生成玩家：确保 player._ready() 中的
	# register_player 能正确识别酒馆为 current_level，避免
	# EquipmentPanelPlayerFinder 在旧场景中查找失效玩家。
	if GameState:
		GameState.register_level(self)
	_spawn_player()
	# 抑制已被玩家拥有的固定拾取物（如 PickableShortSword）在场景重载后重复刷新：
	# 酒馆在"下一天"/"出发返回"时会被重新实例化，若玩家已拾取并装备该武器，
	# 则场景里手放的同一物件不应再次出现，避免重复拾取。
	_suppress_owned_pickables()
	_collect_seats()
	_setup_hud_if_night_phase()
	call("_mount_tutorial_flow_if_needed")
	# 应用酒馆光照档案：把动态火把范围收束成温暖光池、启用火光闪烁。
	# 地牢副本不受影响（其火把仍保持远距离可见性所需的 range/energy）。
	if LightingController != null:
		LightingController.apply_tavern_profile(self)

func _configure_scene_objects() -> void:
	for root in [lights, decor, stations, customer_seats]:
		if root == null:
			continue
		for child in root.get_children():
			if child is Marker3D:
				continue
			_ensure_collision_on_instance(child)
			_configure_scene_object(child)

## 冻结酒馆场景中固定摆放的 PickableItem（RigidBody3D）。
## 酒馆内的酒桶/武器等摆件在场景加载时应保持静止，不受重力或同层可拾取物
## 之间的碰撞推力影响（MASK_PICKABLE 已包含 LAYER_PICKABLE，叠放的酒桶
## 会互相碰撞飞散）。玩家拾取时 PickableItem 被 queue_free 销毁，投掷时
## 生成新的 ThrownItem，因此冻结不影响拾取/投掷流程。动态生成的物品
## （教程酒桶、地牢掉落）在 _ready 之后才进树，不受此方法影响。
func _freeze_tavern_pickables() -> void:
	for node in find_children("*", "PickableItem", true, false):
		var pickable := node as PickableItem
		if pickable == null:
			continue
		pickable.freeze = true
		pickable.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC

func _ensure_collision_on_instance(instance: Node) -> void:
	if _has_physics_body(instance):
		return
	if not (instance is Node3D):
		return
	var node3d: Node3D = instance
	var meshes: Array = node3d.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var combined_aabb: AABB = AABB()
	var has_aabb := false
	for m in meshes:
		var mi: MeshInstance3D = m
		var aabb: AABB = _mesh_aabb_in_node_space(node3d, mi)
		if aabb.size != Vector3.ZERO:
			if not has_aabb:
				combined_aabb = aabb
				has_aabb = true
			else:
				combined_aabb = combined_aabb.merge(aabb)
	if not has_aabb:
		return
	var body := StaticBody3D.new()
	body.name = instance.name + "Body"
	body.collision_layer = SCENE_OBJECT_LAYER
	body.collision_mask = 0
	body.set_script(SCENE_OBJECT_SCRIPT)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = combined_aabb.size
	col.shape = shape
	col.position = combined_aabb.position + combined_aabb.size * 0.5
	body.add_child(col, true)
	node3d.add_child(body, true)

func _mesh_aabb_in_node_space(root: Node3D, mesh_instance: MeshInstance3D) -> AABB:
	var relative := Transform3D.IDENTITY
	var current: Node = mesh_instance
	while current != null and current != root:
		if current is Node3D:
			relative = (current as Node3D).transform * relative
		current = current.get_parent()
	if current != root:
		return mesh_instance.get_aabb()
	return relative * mesh_instance.get_aabb()

func _configure_scene_object(node: Node) -> void:
	if node is StaticBody3D:
		var body := node as StaticBody3D
		body.collision_layer = SCENE_OBJECT_LAYER
		body.collision_mask = 0
		if body.get_script() == null:
			body.set_script(SCENE_OBJECT_SCRIPT)
	for c in node.get_children():
		_configure_scene_object(c)

func _has_physics_body(node: Node) -> bool:
	if node is PhysicsBody3D:
		return true
	for c in node.get_children():
		if _has_physics_body(c):
			return true
	return false

func _spawn_player() -> void:
	if player_spawn:
		var player: Player = PLAYER_PREFAB.instantiate()
		player.name = "Player"
		player.global_transform = player_spawn.global_transform
		add_child(player)
		if GameState:
			GameState.register_player(player)
		if TavernManager != null and TavernManager.tutorial_completed and not TavernManager.has_confirmed_character_name:
			player.set_tutorial_input_enabled(true, true, true)

## 抑制已被玩家拥有的固定拾取物刷新。
## 仅对设置了 owner_weapon_id 的 PickableItem 生效（即场景手放的固定摆件，
## 如酒馆 PickableShortSword）。地牢宝箱 / 怪物掉落等动态战利品不设置该字段，
## 因此不受影响。主菜单背景视口中也不抑制，保持背景视觉完整。
func _suppress_owned_pickables() -> void:
	if get_viewport() is SubViewport:
		return
	if GameState == null or not GameState.has_method("is_weapon_owned"):
		return
	for node in find_children("*", "PickableItem", true, false):
		var pickable := node as PickableItem
		if pickable == null:
			continue
		if not "owner_weapon_id" in pickable:
			continue
		var wid := String(pickable.owner_weapon_id)
		if wid.is_empty():
			continue
		if GameState.is_weapon_owned(wid):
			pickable.queue_free()

# 仅在夜晚营业阶段挂载经营 HUD；主菜单背景视口等非营业场景保持纯 3D。
# 判断依据全局 TavernManager.current_phase，避免被误识别为 UI 界面。
func _setup_hud_if_night_phase() -> void:
	# 主菜单背景视口中不挂载任何交互 UI（出发提示、装备面板），
	# 否则背景中的出发提示会抢占 T 键输入，导致实际游戏中 T 无反应。
	if get_viewport() is SubViewport:
		return
	var tm: Node = _get_tavern_manager()
	if tm == null:
		return
	if tm.current_phase == tm.Phase.NIGHT_TAVERN:
		_mount_tavern_equipment_panel()
	elif tm.current_phase == tm.Phase.DAY_EXPEDITION:
		# 白天探险阶段也需要装备面板供玩家整备，同时挂载出发提示
		_mount_tavern_equipment_panel()
		_mount_expedition_prompt()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		var tm: Node = _get_tavern_manager()
		if tm != null and (tm.current_phase == tm.Phase.NIGHT_TAVERN or tm.current_phase == tm.Phase.DAY_EXPEDITION):
			get_viewport().set_input_as_handled()
			toggle_tavern_equipment_panel()

## 夜晚营业阶段挂载隐藏装备面板。经营 HUD 由吧台交互唤出。
func _mount_tavern_equipment_panel() -> void:
	if tavern_equipment_layer != null:
		return
	tavern_equipment_layer = CanvasLayer.new()
	tavern_equipment_layer.name = "TavernEquipmentLayer"
	tavern_equipment_layer.layer = 20
	tavern_equipment_panel = TAVERN_EQUIPMENT_PANEL_SCENE.instantiate() as Control
	tavern_equipment_panel.visible = false
	tavern_equipment_layer.add_child(tavern_equipment_panel)
	add_child(tavern_equipment_layer)

func toggle_tavern_equipment_panel() -> void:
	if tavern_equipment_panel == null:
		_mount_tavern_equipment_panel()
	if tavern_equipment_panel == null:
		return
	if tavern_equipment_panel.visible:
		tavern_equipment_panel.call("hide_panel")
	else:
		tavern_equipment_panel.call("show_panel")

## 吧台交互调用：唤出/关闭经营 HUD。
func toggle_tavern_hud() -> void:
	if tavern_hud_layer == null:
		_mount_tavern_hud()
	if tavern_hud_layer == null:
		return
	var will_show: bool = not tavern_hud_layer.visible
	tavern_hud_layer.visible = will_show
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if will_show else Input.MOUSE_MODE_CAPTURED)
	# 经营 HUD 打开时通知战斗 HUD 整层隐藏，避免战斗 UI 泄露到经营界面上方
	# 并拦截鼠标点击（CombatHUD 边角 Control 默认 mouse_filter=STOP 会吞掉点击）。
	if GameEvents != null:
		GameEvents.tavern_hud_visibility_changed.emit(will_show)

func _mount_tavern_hud() -> void:
	var hud_scene: PackedScene = load("res://scenes/ui/tavern_ui.tscn")
	if hud_scene == null:
		return
	var hud: Control = hud_scene.instantiate() as Control
	tavern_hud_layer = CanvasLayer.new()
	tavern_hud_layer.name = "HUDLayer"
	# 高于 CombatHUD(layer=15) 与 UI CanvasLayer(layer=20)，
	# 确保经营界面在视觉与输入层叠上都位于所有战斗/通用 UI 之上。
	# UI 层的 DeathScreen/HurtVignette 是全屏透明控件（mouse_filter=IGNORE 已修），
	# 但仍提升层级作为防御性措施，避免任何其他全屏 STOP 控件拦截经营面板点击。
	tavern_hud_layer.layer = 25
	tavern_hud_layer.visible = false
	# 加入 character_panel 组：visible 时 is_character_panel_visible() 自动返回 true，
	# player.gd 据此跳过鼠标强制捕获与移动，无需信号/标志耦合。
	tavern_hud_layer.add_to_group("character_panel")
	tavern_hud_layer.add_child(hud)
	add_child(tavern_hud_layer)

func _configure_bar_interaction() -> void:
	var bar_bodies: Array = [
		get_node_or_null("Structure/BuiltStructure/BarTopBody"),
		get_node_or_null("Structure/BuiltStructure/BarFrontBody"),
		get_node_or_null("Structure/BuiltStructure/BarBackShelfBody"),
	]
	for body in bar_bodies:
		if body == null or not (body is StaticBody3D):
			continue
		var static_body := body as StaticBody3D
		static_body.collision_layer = SCENE_OBJECT_LAYER
		static_body.collision_mask = 0
		static_body.set_script(TAVERN_BAR_INTERACTION_SCRIPT)
		static_body.set("interaction_name", "吧台")

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

func _mount_tutorial_flow_if_needed() -> void:
	if TavernManager == null:
		return
	if not TavernManager.tutorial_completed or TavernManager.has_confirmed_character_name:
		return
	var player := get_node_or_null("Player") as Player
	if player == null:
		return
	var coordinator := TUTORIAL_COORDINATOR_SCRIPT.new()
	coordinator.setup(self, player)
	add_child(coordinator)

# 安全获取 autoload TavernManager（避免编辑器/测试环境无 autoload 时崩溃）。
func _get_tavern_manager() -> Node:
	var tree: SceneTree = get_tree()
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
	var found: Array = customer_seats.find_children("seat_*", "Marker3D", true, false)
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
