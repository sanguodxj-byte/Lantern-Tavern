extends Node
## 真实地牢联机入口控制器（Phase B）：把联机会话状态映射到真实地牢场景节点。
##
## 服务器（房主）：生成权威 seed + 真实地牢；为本地玩家生成真实 Player。
## 客户端：用服务器下发的 seed 确定性重建同一张真实地牢；为本地玩家生成真实 Player。
##
## 生成管线（DungeonGenerator + DungeonSceneBuilder）与 procedural_dungeon.gd 完全一致，
## 因此产出真实地形几何 + 真实玩家出生点；不重复造轮子。DungeonRuntime 的 HUD/UI/streaming
## 为表现层，真实 Lobby 流程（Phase B 完整接入）再挂；本控制器聚焦“真实场景 + 真实 Player +
## 服务器权威移动同步”的垂直切片验证，在 headless 双进程下稳定运行。
##
## 不声明 class_name：避免 headless 类注册 / .uid 同步问题；经 preload 引用。

const DungeonGeneratorClass := preload("res://scenes/expedition/dungeon_generator.gd")
const DungeonLayoutClass := preload("res://scenes/expedition/dungeon_layout.gd")
const DungeonGenerationConfigClass := preload("res://scenes/expedition/dungeon_generation_config.gd")
const DungeonSceneBuilderClass := preload("res://scenes/expedition/dungeon_scene_builder.gd")
const PlayerScene := preload("res://scenes/characters/player/player.tscn")
const ClientCommandDriver := preload("res://scenes/multiplayer/client_command_driver.gd")
const GameStateClass := preload("res://globals/core/game_state.gd")

signal dungeon_ready(seed_value: int, layout_fingerprint: String)

var dungeon_root: Node3D = null
var local_player: Node = null
var _seed: int = 0
var _layout: DungeonLayoutClass = null
var _player_spawn_pos: Vector3 = Vector3.ZERO

## 用指定 seed 构建真实地牢并生成本地真实 Player。返回本地 Player 节点。
func build_and_enter(seed_value: int) -> Node:
	_seed = seed_value
	_build_real_dungeon()
	_spawn_local_player()
	dungeon_ready.emit(_seed, layout_fingerprint())
	return local_player

## 专用服务器（Dedicated Server，⑫）：仅构建【权威地牢状态】（seed→layout→出生点），
## 不生成可见几何、不生成本地 Player。无头专用服务器无观察者、移动为纯数学积分
## （MovementAuthority.integrate_position 不依赖碰撞几何），故只需 layout 出生点算权威实体位置。
## 与 build_and_enter 共用同一 DungeonGenerator 管线，保证专用服务器与客户端 layout 指纹一致。
func build_authority_only(seed_value: int) -> void:
	_seed = seed_value
	var config := DungeonGenerationConfigClass.new()
	config.zone = 0
	config.seed = _seed
	_layout = DungeonGeneratorClass.new().generate(config)
	if _layout.is_empty():
		push_warning("[DungeonSession] authority-only generator returned empty layout for seed=%d" % _seed)
		return
	_compute_player_spawn_pos()
	dungeon_ready.emit(_seed, layout_fingerprint())

## 真实地牢生成：复用与 procedural_dungeon 相同的生成管线，产出真实几何。
func _build_real_dungeon() -> void:
	var config := DungeonGenerationConfigClass.new()
	config.zone = 0
	config.seed = _seed
	_layout = DungeonGeneratorClass.new().generate(config)
	if _layout.is_empty():
		push_warning("[DungeonSession] generator returned empty layout for seed=%d" % _seed)
		return
	var report := _layout.validate()
	if not report.get("valid", false) and not (report.get("errors", []) as Array).is_empty():
		push_warning("[DungeonSession] layout validate errors: %s" % str(report["errors"]))
	dungeon_root = Node3D.new()
	dungeon_root.name = "RealDungeon_%d" % _seed
	add_child(dungeon_root)
	# 简单环境光，避免 headless 下全黑（不影响逻辑）。
	var amb := DirectionalLight3D.new()
	amb.rotation_degrees = Vector3(-90, 0, 0)
	amb.light_energy = 0.25
	dungeon_root.add_child(amb)
	# 真实地形几何（floor/wall/ceiling/碰撞）+ SpawnRoot（敌人/掉落挂载点）。
	DungeonSceneBuilderClass.new().build(_layout, dungeon_root)
	_compute_player_spawn_pos()

## 玩家出生点：唯一算法来源在 DungeonLayout.calc_player_spawn_pos()。
## 两端（专用服务器 / 客户端 / 真实 ProceduralDungeon）经同一方法计算，保证一致。
func _compute_player_spawn_pos() -> void:
	if _layout == null or _layout.is_empty():
		_player_spawn_pos = Vector3(0, 0.5, 0)
	else:
		_player_spawn_pos = _layout.calc_player_spawn_pos()
	# 把权威出生点同步给服务器 SessionRoot：玩家(含房主自身)的权威起始位置随之落
	# 到地牢坐标系，而非默认原点 —— 否则射程/朝向校验会永远拒掉对附近敌人的合法攻击。
	if NetworkManager.session != null:
		NetworkManager.session.player_spawn_pos = _player_spawn_pos
		# 房主若在生成地牢前已 spawn_self（host 流程），其权威位置仍在原点，
		# 此处按地牢出生点 rebasing，避免房主被自身快照拉回原点。
		if NetworkManager.is_host and NetworkManager.session.has_method("set_player_position"):
			NetworkManager.session.set_player_position(NetworkManager.local_peer_id, _player_spawn_pos)

## 生成真实 Player（完整控制器），挂载 ClientCommandDriver（联机输入上送 + 服务器快照应用）。
func _spawn_local_player() -> void:
	local_player = PlayerScene.instantiate()
	local_player.name = "LocalPlayer"
	if dungeon_root != null:
		dungeon_root.add_child(local_player)
	else:
		add_child(local_player)
	local_player.global_position = _player_spawn_pos
	# Player._ready 内会经 GameState.register_player 设置 GameState.current_player（本地进程唯一）。
	var driver := ClientCommandDriver.new()
	driver.name = "ClientCommandDriver"
	driver.player = local_player
	local_player.add_child(driver)

## 服务器权威：在地牢中放置若干敌人实体（经 NetworkManager 广播 → 两端桥接层生成可见节点）。
## 仅房主执行；客户端不生成权威实体（它们经复制事件在本地出现）。
## 返回已生成的 entity_id 列表（测试断言用）。
func spawn_server_entities() -> Array:
	var ids: Array = []
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null or not ("is_host" in nm) or not bool(nm.is_host):
		return ids
	# 出生点确定性偏移放置：敌人围绕玩家出生点，保证两端一致（服务器权威位置）。
	var base: Vector3 = _player_spawn_pos
	var specs: Array = [
		{"id": 1001, "kind": "enemy", "label": "Rat", "hp": 12, "off": Vector3(3.0, 0.0, 0.0),
		 # 掉落表（Phase ⑤ 验证用）：高权重材料，确保击杀必掉落，便于测试断言复制+拾取。
		 "loot_table": {"goblin_tooth": {"kind": "material", "weight": 10, "min": 1, "max": 2}}},
		{"id": 1002, "kind": "enemy", "label": "Skeleton", "hp": 20, "off": Vector3(0.0, 0.0, 3.0)},
	]
	for s in specs:
		var eid: int = int(s["id"])
		var data: Dictionary = {
			"kind": String(s["kind"]),
			"label": String(s["label"]),
			"position": base + (s["off"] as Vector3),
			"current_life": int(s["hp"]),
			"max_life": int(s["hp"]),
			# 防御属性（供服务器 CombatAuthority 结算；测试敌人无护甲/体质以便攻击可见扣血）。
			"con": 0,
			"armor_def": 0,
		}
		if s.has("loot_table"):
			data["loot_table"] = s["loot_table"]
		var res: Dictionary = nm.server_spawn_entity(eid, data)
		if bool(res.get("success", false)):
			ids.append(eid)
	return ids

## 地牢布局指纹：相同 seed → 完全相同网格 → 相同指纹（跨进程确定性）。
## 用于验证 Host/Client 重建出【同一张】地牢（Phase E 同步核心断言）。
func layout_fingerprint() -> String:
	if _layout == null:
		return "none"
	return "%d|%d|%d|%s" % [
		_layout.width, _layout.height,
		int(str(_layout.grid).hash()),
		str(_layout.player_spawn_cell)
	]
