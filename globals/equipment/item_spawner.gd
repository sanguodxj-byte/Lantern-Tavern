extends Node
## 物品放置调度器（autoload: ItemSpawner）。
##
## 基于 Tag 驱动的物品放置系统：
## 1. 启动时从 item_placement_config.json 加载所有标签的放置规则
## 2. 按区域（zone）、位置偏好（LocationPreference）、物理模式（PhysicsMode）控制生成
## 3. 与 ProceduralDungeon / PropDistributor 协作，在地牢生成阶段一次注入
##
## 核心 API：
##   spawn_items_for_room(grid_data, zone, player_spawn_pos, tile_size, offset)
##       — 对整个地牢按格子的单元格类型（floor=1, container=4, treasure=3 等）放置物品
##   spawn_item_by_tag(tag, position, parent)
##       — 在指定位置生成一个带物理的物品实例
##   get_tag_config(tag) → ItemPlacementData
##       — 查询某个标签的放置配置

const Service := preload("res://globals/core/service.gd")

const PICKABLE_ITEM_PREFAB := preload("res://scenes/equipment/pickable_item.tscn")
const PLACEMENT_DATA := preload("res://data/item_placement_data.gd")
const TAGS := preload("res://data/item_tags.gd")
const MATERIAL_MODELS := preload("res://data/material_model_registry.gd")
const MATERIAL_SURPLUS_OVER_ENEMIES := 5
const DECOR_CONFIG_FALLBACK: Dictionary = {
	"res://scenes/props/decor/bones.tscn": 20,
	"res://scenes/props/decor/lit_candles.tscn": 15,
	"res://scenes/props/decor/spiderweb.tscn": 15,
	"res://scenes/props/decor/bench.tscn": 10,
	"res://scenes/props/decor/chair.tscn": 10,
	"res://scenes/props/decor/table.tscn": 10,
	"res://scenes/props/crates/small_crate.tscn": 10,
	"res://scenes/props/barrel/barrel.tscn": 10,
}

const MATERIALS_FALLBACK: Dictionary = {
	"rat_tail": 15, "moldy_bread": 12, "rusty_nail": 10, "dungeon_moss": 10,
	"bone_shard": 8, "stale_water": 8, "prison_lichen": 5, "cellar_mushroom": 4,
	"blackberry": 15, "glowshroom": 12, "moongrass": 10, "pixie_dust": 5,
	"poison_berry": 4, "deeprock_moss": 12, "black_rye_root": 12, "stalactite_sap": 8,
	"goblin_nail": 8, "mistflower": 8, "wolfear_herb": 8, "cyclops_beard": 8,
	"geothermal_ear": 8, "luminous_fern": 8, "quartz_dust": 5, "blindfish_jerky": 4,
}

# 场景物体脚本引用（用于 StaticBody 装饰物）
const SCENE_OBJECT_SCRIPT := preload("res://scenes/props/scene_object.gd")
const SCENE_OBJECT_LAYER := 64

# ── 内部缓存 ────────────────────────────────────────────────
var _configs: Dictionary = {}    # tag → ItemPlacementData
var _loaded := false

# 装饰物场景预加载缓存
var _decor_scenes: Dictionary = {}   # path → PackedScene
var _decor_total_weight: int = 0

signal spawner_ready()

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_load_config()
	_preload_decor_scenes()
	_loaded = true
	spawner_ready.emit()
	print("[ItemSpawner] Loaded %d tag configs" % _configs.size())

# ============================================================================
# 配置文件加载
# ============================================================================

func _load_config() -> void:
	var file_path: String = "res://data/item_placement_config.json"
	if not ResourceLoader.exists(file_path):
		push_warning("[ItemSpawner] Config file not found: %s — using defaults" % file_path)
		_init_default_configs()
		return
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("[ItemSpawner] Cannot open config file: %s — using defaults" % file_path)
		_init_default_configs()
		return
	var json_str: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		push_warning("[ItemSpawner] JSON parse error: %s — using defaults" % json.get_error_message())
		_init_default_configs()
		return
	var data: Array = json.data
	if data.is_empty():
		push_warning("[ItemSpawner] Config is empty — using defaults")
		_init_default_configs()
		return
	for entry in data:
		var placement: Resource = PLACEMENT_DATA.from_dict(entry)
		placement.preload_scenes()
		_configs[placement.tag] = placement

func _init_default_configs() -> void:
	# 材料标签默认配置
	var mat: Resource = PLACEMENT_DATA.new()
	mat.tag = TAGS.MATERIAL
	mat.base_probability = 0.008
	mat.location_preference = TAGS.LocationPreference.SCATTER
	mat.physics_mode = TAGS.PhysicsMode.STATIC
	mat.spawn_min_dist_from_player = 3.0
	mat.max_per_room = 8
	_configs[TAGS.MATERIAL] = mat

	# 装饰标签默认配置
	var decor: Resource = PLACEMENT_DATA.new()
	decor.tag = TAGS.DECOR
	decor.base_probability = 0.04
	decor.location_preference = TAGS.LocationPreference.SCATTER
	decor.physics_mode = TAGS.PhysicsMode.STATIC
	decor.spawn_min_dist_from_player = 2.0
	decor.max_per_room = 6
	_configs[TAGS.DECOR] = decor

	# 容器标签默认配置
	var container: Resource = PLACEMENT_DATA.new()
	container.tag = TAGS.CONTAINER
	container.base_probability = 0.10
	container.location_preference = TAGS.LocationPreference.NEAR_WALL
	container.physics_mode = TAGS.PhysicsMode.STATIC
	container.spawn_min_dist_from_player = 4.0
	container.max_per_room = 3
	_configs[TAGS.CONTAINER] = container

	# 宝藏标签默认配置
	var treasure: Resource = PLACEMENT_DATA.new()
	treasure.tag = TAGS.TREASURE
	treasure.base_probability = 0.03
	treasure.location_preference = TAGS.LocationPreference.NEAR_WALL
	treasure.physics_mode = TAGS.PhysicsMode.STATIC
	treasure.spawn_min_dist_from_player = 6.0
	treasure.max_per_room = 1
	_configs[TAGS.TREASURE] = treasure

# ============================================================================
# 装饰场景预加载
# ============================================================================

func _preload_decor_scenes() -> void:
	_decor_scenes.clear()
	_decor_total_weight = 0
	for path in DECOR_CONFIG_FALLBACK:
		var scene: PackedScene = load(path)
		if scene != null:
			_decor_scenes[path] = scene
			_decor_total_weight += DECOR_CONFIG_FALLBACK[path]
		else:
			push_warning("[ItemSpawner] Failed to load decor scene: %s" % path)

# ============================================================================
# 核心 API
# ============================================================================

## 获取某个标签的放置配置。
## 若 tag 无注册配置，返回一个合理默认值。
func get_tag_config(tag: String) -> Resource:
	return _configs.get(tag, null)

## 获取所有已注册标签
func get_all_tags() -> Array[String]:
	var tags: Array[String] = []
	for tag in _configs.keys():
		tags.append(str(tag))
	return tags

## 注册或覆写一个标签配置（供运行时动态添加）
func register_tag_config(data: Resource) -> void:
	if data == null or data.tag.is_empty():
		return
	data.preload_scenes()
	_configs[data.tag] = data

## 移除标签配置
func unregister_tag(tag: String) -> void:
	_configs.erase(tag)

## 核心：对整个地牢按格子进行物品放置。
##
## grid_data: 二维数组，地牢网格（与 procedural_dungeon 的 _grid 格式相同）
##   - 0=void, 1=floor, 2=wall, 3=chest_spawn, 4=container_spawn, 5=pillar
## zone: 当前区域编号（BrewingData.Zone 枚举值）
## player_spawn_pos: 玩家出生点全局坐标
## tile_size: 格尺寸（默认 3.0）
## offset: 网格偏移
## parent: 物品挂在哪个节点下
##
## 返回生成的物品实例数组。
func spawn_items_for_level(grid_data: Array, zone: int, player_spawn_pos: Vector3,
		tile_size: float, offset: Vector3, parent: Node) -> Array:
	var spawned: Array = []
	if grid_data.is_empty():
		return spawned
	var grid_width: int = grid_data[0].size()
	var grid_height: int = grid_data.size()
	var material_spawn_limit := _get_material_spawn_limit(parent)
	var material_spawned := 0

	for y in range(grid_height):
		for x in range(grid_width):
			var cell_type: int = grid_data[y][x]
			var cell_pos := offset + Vector3(x * tile_size, 0.5, y * tile_size)

			match cell_type:
				1:  # FLOOR — 散落材料 + 装饰
					if _is_start_room_grid_cell(parent, x, y):
						continue
					# 排除玩家出生点附近
					if cell_pos.distance_to(player_spawn_pos) < 4.0:
						continue
					var before_count := spawned.size()
					_spawn_scatter_items(spawned, cell_pos, zone, parent, grid_data, x, y, tile_size, material_spawned < material_spawn_limit)
					if spawned.size() > before_count and _is_material_instance(spawned[spawned.size() - 1]):
						material_spawned += 1

				3:  # CHEST 槽位
					var treasure_cfg: Resource = get_tag_config(TAGS.TREASURE)
					var zone_prob := _get_zone_probability(treasure_cfg, zone)
					if randf() < zone_prob:
						var instance = _spawn_item_internal(TAGS.TREASURE, cell_pos, parent, zone)
						if instance:
							spawned.append(instance)
					else:
						# 回退为装饰
						_spawn_scatter_decor(spawned, cell_pos, parent)

				4:  # RESOURCE — 固定素材槽位
					if material_spawned >= material_spawn_limit:
						continue
					var mat_id := _pick_material_id(zone)
					var wall_direction := _find_wall_direction(grid_data, x, y)
					var spawn_pos := _position_for_material(mat_id, cell_pos, tile_size, wall_direction)
					var instance = _spawn_material_instance(mat_id, spawn_pos, parent, zone, wall_direction)
					if instance:
						spawned.append(instance)
						material_spawned += 1

	return spawned


## 阶段 9 条 4：按 DungeonLayout.item_spawn_specs 实例化物品，不再重读 grid 盲扫。
## layout: 已规划 item_spawn_specs 的 DungeonLayout（DungeonSpawnPlanner.plan_item_spawns 产出）
## spawn_root: 物品节点容器（DungeonBuildResult.spawn_root）
## player: Player 实例（供 proximity/streaming 注册；本接口暂不直接用，预留）
## spec 字段：{item_type:"material", item_id:String, cell:Vector2i, room_index:int}
## 当前仅处理 item_type=="material"（planner 只规划材料）；其余类型跳过并告警。
func spawn_items_from_layout(layout: DungeonLayout, spawn_root: Node, player: Node = null) -> Array:
	var spawned: Array = []
	if layout == null or layout.is_empty() or spawn_root == null or not is_instance_valid(spawn_root):
		return spawned
	# 重算偏移（与 procedural 的 OFFSET 公式一致：居中）
	var offset_x: float = -(float(layout.width) * layout.tile_size) / 2.0
	var offset_z: float = -(float(layout.height) * layout.tile_size) / 2.0
	var offset: Vector3 = Vector3(offset_x, 0, offset_z)
	for spec in layout.item_spawn_specs:
		var item_type: String = spec.get("item_type", "")
		match item_type:
			"material":
				var mat_id: String = spec.get("item_id", "")
				if mat_id.is_empty():
					continue
				var cell: Vector2i = spec["cell"]
				var cell_pos: Vector3 = offset + Vector3(cell.x * layout.tile_size, 0.5, cell.y * layout.tile_size)
				# wall_direction 不从 grid 重推（planner 已选 cell）；用 ZERO 让 _spawn_material_instance 走 random yaw
				var instance = _spawn_material_instance(mat_id, cell_pos, spawn_root, layout.zone, Vector3.ZERO)
				if instance != null:
					spawned.append(instance)
			_:
				push_warning("[ItemSpawner] spawn_items_from_layout: unsupported item_type '%s'" % item_type)
	print("[ItemSpawner] Spawned %d items from layout specs (zone %d, specs %d)" % [spawned.size(), layout.zone, layout.item_spawn_specs.size()])
	return spawned


func _is_start_room_grid_cell(parent: Node, x: int, y: int) -> bool:
	if parent != null and parent.has_method("is_start_room_grid_cell"):
		return bool(parent.is_start_room_grid_cell(Vector2i(x, y)))
	return false


func _get_material_spawn_limit(parent: Node) -> int:
	var enemy_count := _count_enemy_nodes(parent)
	if enemy_count <= 0:
		return 999999
	return enemy_count + MATERIAL_SURPLUS_OVER_ENEMIES


func _count_enemy_nodes(node: Node) -> int:
	if node == null:
		return 0
	var count := 0
	if node is Enemy or (node.has_meta("topdown_kind") and String(node.get_meta("topdown_kind")) == "enemy"):
		count += 1
	for child in node.get_children():
		count += _count_enemy_nodes(child)
	return count


func _is_material_instance(node: Node) -> bool:
	return node != null and node.has_meta("item_tag") and String(node.get_meta("item_tag")) == TAGS.MATERIAL

## 在指定位置生成一个带标签的物品实例。
## 自动根据配置选择场景、添加 PhysicsBody3D 并设置碰撞层。
func spawn_item_by_tag(tag: String, position: Vector3, parent: Node, zone: int = 0) -> Node:
	return _spawn_item_internal(tag, position, parent, zone)

# ============================================================================
# 内部方法
# ============================================================================

## 内部：按标签生成单个物品，返回实例或 null
func _spawn_item_internal(tag: String, pos: Vector3, parent: Node, zone: int) -> Node:
	var cfg := get_tag_config(tag)
	if cfg == null:
		push_warning("[ItemSpawner] No config for tag '%s'" % tag)
		return null

	# 取场景实例
	var prefab: PackedScene = cfg.pick_scene()
	if prefab == null:
		# 如果没有配置场景，按 tag 类型 fallback
		match tag:
			TAGS.MATERIAL:
				return _spawn_material_fallback(pos, parent, zone)
			TAGS.DECOR:
				return _spawn_decor_fallback(pos, parent)
			TAGS.CONTAINER:
				return _spawn_container_fallback(pos, parent)
			TAGS.TREASURE:
				return _spawn_treasure_fallback(pos, parent, zone)
			_:
				return null

	var scene_path := String(prefab.resource_path)
	if tag == TAGS.DECOR or tag == TAGS.CONTAINER:
		var batched_instance := _spawn_batched_static_scene(scene_path, pos, parent)
		if batched_instance != null:
			_set_tag_meta(batched_instance, tag, cfg, zone)
			return batched_instance

	var instance: Node = prefab.instantiate()
	instance.position = pos
	parent.add_child(instance)

	# 按物理模式设置碰撞
	_setup_physics(instance, cfg.physics_mode)

	# 注入标签元数据
	_set_tag_meta(instance, tag, cfg, zone)
	_notify_streamed_physics_parent(instance, parent)

	return instance

## 设置 PhysicsBody3D 的碰撞
func _setup_physics(instance: Node, physics_mode: int) -> void:
	match physics_mode:
		TAGS.PhysicsMode.RIGID:
			_ensure_rigidbody(instance)
		TAGS.PhysicsMode.TRIGGER:
			_ensure_trigger(instance)
		_:
			# STATIC：用 StaticBody3D（或保持原场景已有物理）
			if instance is StaticBody3D:
				if instance is PickableItem:
					PhysicsSetup.setup_pickable(instance)
				else:
					instance.collision_layer = SCENE_OBJECT_LAYER
					instance.collision_mask = PhysicsSetup.MASK_ENVIRONMENT
			elif instance is RigidBody3D:
				PhysicsSetup.setup_rigidbody(instance, PhysicsSetup.LAYER_PICKABLE)

## 如果实例不是 RigidBody3D，尝试包装为 RigidBody3D（可拾取）
func _ensure_rigidbody(instance: Node) -> void:
	if instance is RigidBody3D:
		return
	if instance is StaticBody3D:
		# 已有 StaticBody — 不强制转换，保持 Static
		return
	# 对于非物理节点，添加 RigidBody3D 子节点作为碰撞体
	_add_physics_child(instance, PhysicsSetup.LAYER_PICKABLE, PhysicsSetup.MASK_PICKABLE, true)

## 添加 Area3D 触发器
func _ensure_trigger(instance: Node) -> void:
	if instance is Area3D:
		PhysicsSetup.setup_trigger(instance)
		return
	var area := Area3D.new()
	area.name = "Trigger"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 1.0)
	col.shape = shape
	area.add_child(col)
	instance.add_child(area)
	PhysicsSetup.setup_trigger(area)

## 为节点添加物理碰撞体子节点
func _add_physics_child(node: Node, layer: int, mask: int, is_rigid: bool) -> void:
	if is_rigid:
		var body := RigidBody3D.new()
		body.name = node.name + "RigidBody"
		body.position = Vector3.ZERO
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.5, 0.5, 0.5)
		col.shape = shape
		col.position = Vector3.ZERO
		body.add_child(col, true)
		node.add_child(body, true)
		PhysicsSetup.setup_rigidbody(body, layer)
	else:
		var body := StaticBody3D.new()
		body.name = node.name + "Body"
		body.collision_layer = layer
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.5, 0.5, 0.5)
		col.shape = shape
		body.add_child(col, true)
		node.add_child(body, true)

## 在实例上设置标签元数据
func _set_tag_meta(instance: Node, tag: String, cfg: Resource, zone: int) -> void:
	instance.set_meta("item_tag", tag)
	instance.set_meta("spawn_zone", zone)
	if cfg != null:
		instance.set_meta("location_preference", cfg.location_preference)
		instance.set_meta("physics_mode", cfg.physics_mode)

## 获取区域修正后的概率
func _get_zone_probability(cfg: Resource, zone: int) -> float:
	if cfg == null:
		return 0.0
	return cfg.get_effective_probability(zone)

# ============================================================================
# 散布生成 — 在一格 floor 周围尝试生成随机物品
# ============================================================================

func _spawn_scatter_items(spawned: Array, cell_pos: Vector3, zone: int,
		parent: Node, grid: Array, x: int, y: int, tile_size: float = 3.0,
		allow_material: bool = true) -> void:
	var cfg: Resource

	# 武器/盾牌/防具散落（低概率，高价值）
	cfg = get_tag_config(TAGS.WEAPON)
	if cfg and randf() < cfg.get_effective_probability(zone):
		var instance = _spawn_scatter_equipment(cell_pos, parent, zone)
		if instance:
			spawned.append(instance)
		return  # 一席一位

	# 盾牌散落（独立概率）
	cfg = get_tag_config(TAGS.SHIELD)
	if cfg and randf() < cfg.get_effective_probability(zone):
		var instance = _spawn_scatter_equipment(cell_pos, parent, zone)
		if instance:
			spawned.append(instance)
		return  # 一席一位

	# 材料（高优先）
	cfg = get_tag_config(TAGS.MATERIAL)
	if allow_material and cfg and randf() < cfg.get_effective_probability(zone):
		var mat_id := _pick_material_id(zone)
		var wall_direction := _find_wall_direction(grid, x, y)
		var spawn_pos := _position_for_material(mat_id, cell_pos, tile_size, wall_direction)
		var instance = _spawn_material_instance(mat_id, spawn_pos, parent, zone, wall_direction)
		if instance:
			spawned.append(instance)
		return  # 一席一位

	# 装饰（低优先）
	cfg = get_tag_config(TAGS.DECOR)
	if cfg and randf() < cfg.get_effective_probability(zone):
		var scatter := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		_spawn_scatter_decor(spawned, cell_pos + scatter, parent)

## 在地面生成一件随机装备（武器/盾牌/防具/饰品），使用 LootTable 掉落表。
func _spawn_scatter_equipment(pos: Vector3, parent: Node, zone: int) -> Node:
	var loot_table: Node = Service.loot_table()
	if loot_table == null:
		return null
	var drop_dict: Dictionary = loot_table.roll_weapon()
	if drop_dict.is_empty():
		return null
	var weapon_data = drop_dict.get("weapon_data", null)
	if weapon_data == null:
		return null
	var pickable_scene: PackedScene = PICKABLE_ITEM_PREFAB
	var item: Node = pickable_scene.instantiate()
	item.weapon_data = weapon_data
	item.position = pos + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
	parent.add_child(item)
	_set_tag_meta(item, TAGS.WEAPON, null, zone)
	_notify_streamed_physics_parent(item, parent)
	return item

func _spawn_scatter_decor(spawned: Array, pos: Vector3, parent: Node) -> void:
	var instance = _spawn_decor_fallback(pos, parent)
	if instance:
		spawned.append(instance)

# ============================================================================
# Fallback 生成（当场景路径未配置时）
# ============================================================================

func _spawn_material_fallback(pos: Vector3, parent: Node, zone: int) -> Node:
	var mat_id := _pick_material_id(zone)
	return _spawn_material_instance(mat_id, pos, parent, zone)

func _pick_material_id(zone: int) -> String:
	# 从 ZoneManager 取当前区域材料池
	var pool: Dictionary = MATERIALS_FALLBACK
	var zm: Node = Service.zone_manager() if is_inside_tree() else null
	if zm != null:
		pool = zm.get_scatter_materials(zone)
	return _pick_weighted(pool)

func _spawn_material_instance(mat_id: String, pos: Vector3, parent: Node, zone: int,
		wall_direction: Vector3 = Vector3.ZERO) -> Node:
	if mat_id.is_empty():
		return null
	var item: Node = PICKABLE_ITEM_PREFAB.instantiate()
	item.material_id = mat_id
	item.position = pos + MATERIAL_MODELS.get_spawn_offset(mat_id)
	if wall_direction != Vector3.ZERO and MATERIAL_MODELS.should_align_to_wall(mat_id):
		item.rotation.y = atan2(wall_direction.x, wall_direction.z)
	elif MATERIAL_MODELS.should_random_yaw(mat_id):
		item.rotation.y = randf_range(0.0, TAU)
	parent.add_child(item)
	_set_tag_meta(item, TAGS.MATERIAL, null, zone)
	item.set_meta("material_id", mat_id)
	item.set_meta("material_location_preference", MATERIAL_MODELS.get_location_preference(mat_id))
	item.set_meta("material_align_to_wall", MATERIAL_MODELS.should_align_to_wall(mat_id))
	item.set_meta("material_wall_direction", wall_direction)
	_notify_streamed_physics_parent(item, parent)
	return item

func _position_for_material(mat_id: String, cell_pos: Vector3, tile_size: float,
		wall_direction: Vector3 = Vector3.ZERO) -> Vector3:
	var preference := MATERIAL_MODELS.get_location_preference(mat_id)
	if preference == "near_wall" and wall_direction != Vector3.ZERO:
		var wall_offset := minf(tile_size * 0.36, 1.1)
		var tangent := Vector3(-wall_direction.z, 0, wall_direction.x)
		return cell_pos + wall_direction * wall_offset + tangent * randf_range(-0.24, 0.24)
	var scatter_radius := minf(tile_size * 0.2, 0.6)
	return cell_pos + Vector3(randf_range(-scatter_radius, scatter_radius), 0, randf_range(-scatter_radius, scatter_radius))

func _find_wall_direction(grid: Array, x: int, y: int) -> Vector3:
	var candidates := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]
	for direction in candidates:
		var nx: int = x + direction.x
		var ny: int = y + direction.y
		if ny < 0 or ny >= grid.size():
			continue
		if nx < 0 or nx >= grid[ny].size():
			continue
		if int(grid[ny][nx]) == 2:
			return Vector3(direction.x, 0, direction.y).normalized()
	return Vector3.ZERO

func _spawn_decor_fallback(pos: Vector3, parent: Node) -> Node:
	if _decor_scenes.is_empty():
		return null
	var path: String = _pick_weighted_from_dict(DECOR_CONFIG_FALLBACK)
	if path.is_empty():
		return null
	var batched_instance := _spawn_batched_static_scene(path, pos, parent)
	if batched_instance != null:
		return batched_instance
	var prefab: PackedScene = _decor_scenes.get(path)
	if prefab == null:
		return null
	var instance: Node = prefab.instantiate()
	instance.position = pos
	parent.add_child(instance)
	# 装饰物补全碰撞
	_ensure_scene_object_collision(instance)
	_notify_streamed_physics_parent(instance, parent)
	return instance

func _spawn_container_fallback(pos: Vector3, parent: Node) -> Node:
	var paths := [
		"res://scenes/props/barrel/barrel.tscn",
		"res://scenes/props/crates/small_crate.tscn"
	]
	var path: String = paths[randi() % paths.size()]
	var batched_instance := _spawn_batched_static_scene(path, pos, parent)
	if batched_instance != null:
		_set_tag_meta(batched_instance, TAGS.CONTAINER, null, 0)
		return batched_instance
	var prefab: PackedScene = load(path)
	if prefab == null:
		return null
	var instance: Node = prefab.instantiate()
	instance.position = pos
	parent.add_child(instance)
	_ensure_scene_object_collision(instance)
	_set_tag_meta(instance, TAGS.CONTAINER, null, 0)
	_notify_streamed_physics_parent(instance, parent)
	return instance

func _spawn_treasure_fallback(pos: Vector3, parent: Node, zone: int) -> Node:
	var prefab := preload("res://scenes/props/chest/chest.tscn")
	var instance: Node = prefab.instantiate()
	instance.position = pos
	parent.add_child(instance)
	if instance is Chest:
		instance.zone = zone
	_ensure_scene_object_collision(instance)
	_set_tag_meta(instance, TAGS.TREASURE, null, zone)
	_notify_streamed_physics_parent(instance, parent)
	return instance

func _spawn_batched_static_scene(scene_path: String, pos: Vector3, parent: Node) -> Node:
	if scene_path.is_empty() or parent == null or not parent.has_method("_spawn_batched_decor"):
		return null
	var child_count := parent.get_child_count()
	if not bool(parent._spawn_batched_decor(scene_path, Transform3D(Basis.IDENTITY, pos))):
		return null
	if parent.get_child_count() <= child_count:
		return null
	return parent.get_child(parent.get_child_count() - 1)

func _notify_streamed_physics_parent(instance: Node, parent: Node) -> void:
	if parent != null and parent.has_method("register_streamed_physics_node"):
		parent.register_streamed_physics_node(instance)

# ============================================================================
# 碰撞工具
# ============================================================================

func _ensure_scene_object_collision(instance: Node) -> void:
	# 已有 PhysicsBody3D 则跳过
	if _has_physics_body(instance):
		return
	if not (instance is Node3D):
		return
	var node3d: Node3D = instance
	var meshes: Array = node3d.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var combined_aabb: AABB = AABB()
	var has_aabb: bool = false
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

func _has_physics_body(node: Node) -> bool:
	if node is PhysicsBody3D:
		return true
	for c in node.get_children():
		if _has_physics_body(c):
			return true
	return false

# ============================================================================
# 权重随机工具
# ============================================================================

func _pick_weighted(weights: Dictionary) -> String:
	var total_weight := 0
	for key in weights:
		total_weight += weights[key]
	if total_weight <= 0:
		return ""
	var r := randi() % total_weight
	var cumulative := 0
	for key in weights:
		cumulative += weights[key]
		if r < cumulative:
			return key
	return ""

func _pick_weighted_from_dict(dict: Dictionary) -> String:
	var total_weight := 0
	for key in dict:
		total_weight += dict[key]
	if total_weight <= 0:
		return ""
	var r := randi() % total_weight
	var cumulative := 0
	for key in dict:
		cumulative += dict[key]
		if r < cumulative:
			return key
	return ""
