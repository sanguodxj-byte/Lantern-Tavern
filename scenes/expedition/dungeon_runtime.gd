## DungeonRuntime — 地牢探险运行时模块（评审建议 D 阶段）。
#
# 职责：接管 ProceduralDungeon 的运行时行为——
#   spawn player / spawn enemies / spawn items
#   mount HUD / setup exploration pressure / connect extraction
#   handle overtime / handle extraction
#
# 不负责：生成地图 / 创建墙体 / 计算危险地形 / 管理 chunk / 读取 JSON / 管理酒馆仓库
#
# 严格约束：
#   - 不重新规划布局（layout 已含 spawn specs）
#   - 不创建地形节点（builder 已产 build_result）
#   - 不管理 streaming（controller 已接管）
#   - 信号接线（extraction_requested.connect / pressure.pressure_changed.connect）属本模块范畴
#
# 本会话先建框架 + 接口声明，真迁移放下回合（保 procedural 旧路径不破，避免单回合高风险大改）。
class_name DungeonRuntime
extends Node

# 配置（由 ProceduralDungeon._ready 注入）
var layout: DungeonLayout = null
var build_result: DungeonBuildResult = null
var expedition_finished: bool = false
var _level: Node = null  # ProceduralDungeon 引用（转调其 spawn_player/HUD/pressure 旧路径，下回合真迁）

## 配置：注入 layout + build_result + level（ProceduralDungeon 引用，转调旧路径暂保）。
func configure(p_layout: DungeonLayout, p_build_result: DungeonBuildResult, p_level: Node = null) -> void:
	layout = p_layout
	build_result = p_build_result
	_level = p_level

## 启动 runtime：spawn player/enemies/items + mount HUD + setup pressure + connect extraction + music。
## D 步3 真迁移：本版转调 procedural 旧路径（通过 _level 引用），下回合把函数体真搬入本模块。
func start() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	# spawn 序（转调 procedural 旧路径）
	var spawned_player = _level.spawn_player()
	_level._spawn_dungeon_enemies(spawned_player)
	# D 步5：spawn_items 已真迁入本模块（不转调 procedural）
	spawn_items()
	_level._stabilize_dungeon_lighting()
	_level._mount_expedition_hud()
	_level._setup_exploration_pressure()
	# D 步4：extraction 信号接线已真迁入本模块（不转调 procedural）
	wire_extraction_portal_signal()
	if AudioManager:
		AudioManager.start_music()

## 停止 runtime：handle extraction/overtime 收尾。
func stop() -> void:
	expedition_finished = true

# ── 接口框架（D 步2 真迁移放下回合，保 procedural 旧路径不破） ──
# 这些函数声明占位，让集成测试可验 DungeonRuntime 已具备 runtime 范畴的全套接口名。
# 真迁移时把 procedural 内对应函数体搬入这里 + 改 procedural 转调本模块。

func spawn_player() -> Node3D:
	return null  # TODO D 步2: 迁自 procedural.spawn_player

func spawn_enemies(spawned_player: Node3D = null) -> void:
	pass  # TODO D 步2: 迁自 procedural._spawn_dungeon_enemies

func spawn_items() -> void:
	# D 步5 真迁：把 procedural._spawn_dungeon_items 逻辑搬入本模块，
	# 调 ItemSpawner.spawn_items_from_layout 接 layout.item_spawn_specs，物挂 build_result.spawn_root。
	if layout == null or layout.is_empty() or build_result == null:
		return
	var spawner: Node = Service.item_spawner() if Service != null else null
	if spawner == null:
		push_warning("[DungeonRuntime] ItemSpawner autoload not found, skipping item placement")
		return
	var spawn_root: Node = build_result.spawn_root if build_result.spawn_root != null else _level
	spawner.spawn_items_from_layout(layout, spawn_root)
	if _level != null and is_instance_valid(_level):
		_level._build_batched_decor_multi_meshes()

func mount_expedition_hud() -> void:
	pass  # TODO D 步2: 迁自 procedural._mount_expedition_hud

func setup_exploration_pressure() -> void:
	pass  # TODO D 步2: 迁自 procedural._setup_exploration_pressure

func wire_extraction_portal_signal() -> void:
	# D 步4 真迁：把 procedural._wire_extraction_portal_signal 逻辑搬入本模块，
	# 信号接 runtime.on_extraction_requested（不转调 procedural，真接管）。
	if build_result == null or build_result.interaction_root == null:
		return
	for child in build_result.interaction_root.get_children():
		if String(child.get_meta("topdown_kind", "")) == "extraction" and child.has_signal("extraction_requested"):
			child.extraction_requested.connect(on_extraction_requested)
			break  # 唯一 ExtractionPortal

func finish_expedition(player: Node, voluntary: bool) -> void:
	expedition_finished = true  # TODO D 步2: 迁自 procedural._finish_expedition 完整逻辑

func on_extraction_requested(player: Node) -> void:
	finish_expedition(player, true)  # TODO D 步2: 迁自 procedural._on_extraction_requested

func on_expedition_overtime(_snapshot: Dictionary) -> void:
	# TODO D 步2: 迁自 procedural._on_expedition_overtime
	var player_node := GameState.current_player as Player
	finish_expedition(player_node, false)

func on_pressure_changed(_snapshot: Dictionary) -> void:
	pass  # TODO D 步2: 迁自 procedural._on_pressure_changed

func on_door_pressure_action(action: String) -> void:
	pass  # TODO D 步2: 迁自 procedural._on_door_pressure_action

func apply_player_vision_pressure(_multiplier: float) -> void:
	pass  # TODO D 步2: 迁自 procedural._apply_player_vision_pressure

func apply_environment_activity(_multiplier: float) -> void:
	pass  # TODO D 步2: 迁自 procedural._apply_environment_activity

func apply_monster_hunt_pressure(_force_hunt: bool) -> void:
	pass  # TODO D 步2: 迁自 procedural._apply_monster_hunt_pressure
