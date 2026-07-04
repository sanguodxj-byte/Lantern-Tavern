extends BaseLevel
class_name ProceduralDungeon

const PILLAR_PREFAB := preload("res://scenes/props/structures/pillar.tscn")
const CRATE_PREFAB := preload("res://scenes/props/crates/small_crate.tscn")
const BARREL_PREFAB := preload("res://scenes/props/barrel/barrel.tscn")
const TORCH_PREFAB := preload("res://scenes/props/torch/torch.tscn")
const CHEST_PREFAB := preload("res://scenes/props/chest/chest.tscn")
const PICKABLE_ITEM_PREFAB := preload("res://scenes/equipment/pickable_item.tscn")

# 地形渲染：一张纹理集 + 一个 Shader
const DUNGEON_TEX  := preload("res://assets/textures/dungeon-texture.png")
const TERRAIN_SHADER := preload("res://assets/shaders/dungeon_terrain.gdshader")

# 每个地形类型对应纹理集中的图块位置 (col, row)。和 Python 绘制脚本中的布局完全对应。
const TILE_LAYOUT := {
	"WALL":    Vector2(1, 0),  # 石砖墙壁（正面错缝砖块）
	"FLOOR":   Vector2(2, 0),  # 原石地板（俧视不规则石板）
	"CEILING": Vector2(3, 1),  # 天花板（暗蓝灰石砖）
	"LINTEL":  Vector2(3, 0),  # 木梓门眉（棕色木纹）
	"PILLAR":  Vector2(0, 1),  # 石柱侧面
	"PORTAL":  Vector2(3, 3),  # 传送门（紫色光晕）
}

const MATERIALS_CONFIG = {
	"blackberry": 15, "glowshroom": 12, "moongrass": 10, "goblin_nail": 8,
	"mistflower": 8, "wolfear_herb": 8, "pixie_dust": 5, "poison_berry": 4
}

const DECOR_CONFIG = {
	"res://scenes/props/decor/bones.tscn": 20,
	"res://scenes/props/decor/lit_candles.tscn": 15,
	"res://scenes/props/decor/spiderweb.tscn": 15,
	"res://scenes/props/decor/bench.tscn": 10,
	"res://scenes/props/decor/chair.tscn": 10,
	"res://scenes/props/decor/table.tscn": 10,
	"res://scenes/props/crates/small_crate.tscn": 10,
	"res://scenes/props/barrel/barrel.tscn": 10
}

var _grid: Array = []
var player_spawn_pos := Vector3.ZERO

const TILE_SIZE := 3.0

var _shared_floor_mat: ShaderMaterial = null
var _shared_ceiling_mat: ShaderMaterial = null

# 用于收集 GPU 实例坐标，优化渲染性能
var floor_transforms: Array[Transform3D] = []
var ceiling_transforms: Array[Transform3D] = []
# 墙面按高度分组：key=wall_height(float), value=Array[Transform3D]
# 不同高度的墙需要不同的 tile_repeat.y 才能保证 1m = 1 tile
var wall_transforms_by_height: Dictionary = {}

## 创建地形 ShaderMaterial
## tile_name: TILE_LAYOUT 中的键（"WALL"/"FLOOR"/"CEILING"等）
## tile_repeat: 每轴平铺次数， = 该面的物理尺寸（米），1m = 1次 = 32px
func _make_terrain_mat(tile_name: String, tile_repeat: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("atlas", DUNGEON_TEX)
	mat.set_shader_parameter("tile_col_row", TILE_LAYOUT.get(tile_name, Vector2(0, 0)))
	mat.set_shader_parameter("tile_repeat", tile_repeat)
	return mat

var _heights: Array = []

## 当前地牢所属区域（BrewingData.Zone 枚举值）。
## 决定宝箱材料掉落池，由关卡入口或 ExpeditionManager 注入。
@export var dungeon_zone: int = 0  # 默认森林

func is_procedural() -> bool:
	return true

func _ready() -> void:
	# 注册为当前关卡，供 throw_weapon 等 add_child 使用
	GameState.register_level(self)
	
	# 从 ZoneManager 读取玩家选定的区域，配置宝箱 zone 与散落材料池
	var zm: Node = get_node_or_null("/root/ZoneManager")
	if zm != null:
		dungeon_zone = zm.get_zone()
	var bsp = BSP_DungeonGenerator.new()
	add_child(bsp)
	_grid = bsp.generate_dungeon(30, 30)
	_heights = bsp.ceiling_heights.duplicate(true)
	bsp.queue_free()
	_generate_visuals(_grid)
	player_spawn.global_position = player_spawn_pos
	spawn_player()
	_spawn_dungeon_enemies()
	_mount_expedition_hud()
	if AudioManager:
		AudioManager.start_music()

## 调用 DungeonSpawner autoload 按区域生成怪物，注入 player 引用
func _spawn_dungeon_enemies() -> void:
	var spawner: Node = get_node_or_null("/root/DungeonSpawner")
	if spawner == null:
		push_warning("[Dungeon] DungeonSpawner autoload not found, no enemies spawned")
		return
	var player_node: Node3D = GameState.current_player
	if player_node == null:
		push_warning("[Dungeon] Player not spawned, skip enemy generation")
		return
	spawner.spawn_enemies(self, _grid, dungeon_zone, player_node, player_spawn_pos, TILE_SIZE)

func _mount_expedition_hud() -> void:
	var hud_scene = load("res://scenes/ui/expedition_hud.tscn")
	if not hud_scene:
		return
	var hud = hud_scene.instantiate()
	var layer = CanvasLayer.new()
	layer.name = "ExpeditionHUDLayer"
	layer.add_child(hud)
	add_child(layer)

	# Mount in-game HUD (health bar, death screen, action prompts)
	var game_ui = load("res://scenes/ui/ui.tscn")
	if game_ui:
		var ui_instance = game_ui.instantiate()
		add_child(ui_instance)

func _generate_visuals(grid: Array) -> void:
	# 清空先前收集的 Transform 数组
	floor_transforms.clear()
	ceiling_transforms.clear()
	wall_transforms_by_height.clear()

	const TILE_SIZE := 3.0
	var grid_width = grid[0].size() if grid.size() > 0 else 0
	var grid_height = grid.size()
	var offset_x = -(grid_width * TILE_SIZE) / 2.0
	var offset_z = -(grid_height * TILE_SIZE) / 2.0
	var OFFSET := Vector3(offset_x, 0, offset_z)

	# 地牢内部无阳光直射——用极微弱的洞穴底光模拟环境散射
	var cave_ambient := DirectionalLight3D.new()
	cave_ambient.rotation_degrees = Vector3(-90, 0, 0)  # 正下方
	cave_ambient.light_energy = 0.02
	cave_ambient.light_color = Color(0.3, 0.35, 0.5)   # 冷蓝灰调
	cave_ambient.shadow_enabled = false
	add_child(cave_ambient)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	# 极暗的地牢环境，主要靠角色自身光源 + 火把照明
	env.environment.ambient_light_color = Color(0.04, 0.03, 0.06)  # 极暗紫黑
	env.environment.ambient_light_energy = 0.04
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.fog_enabled = true
	env.environment.fog_light_color = Color(0.05, 0.04, 0.06)
	env.environment.fog_density = 0.02  # 轻微阴槽骎雾
	add_child(env)

	var player_spawned := false

	# ── 预计算墙体高度（两遍，消除相邻墙格高度差接缝）──────────────────
	# 第一遍：每个墙格取所有 4 邻格（含其他墙格）的最大 _heights 值
	var wall_h_map: Dictionary = {}
	for wy in range(grid_height):
		for wx in range(grid_width):
			if grid[wy][wx] == 2:
				var best: float = _heights[wy][wx]
				for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]:
					var nx2 = wx + d.x
					var ny2 = wy + d.y
					if nx2 >= 0 and nx2 < grid_width and ny2 >= 0 and ny2 < grid_height:
						best = max(best, _heights[ny2][nx2])
				wall_h_map[Vector2i(wx, wy)] = best if best > 0.0 else 3.0

	# 第二遍：相邻墙格互相传播最大值（消除"隔一格"仍存在的高度差）
	for wy in range(grid_height):
		for wx in range(grid_width):
			if grid[wy][wx] == 2:
				var key := Vector2i(wx, wy)
				var cur: float = wall_h_map[key]
				for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]:
					var nk := Vector2i(wx + d.x, wy + d.y)
					if wall_h_map.has(nk) and wall_h_map[nk] > cur:
						cur = wall_h_map[nk]
				wall_h_map[key] = cur
	# ─────────────────────────────────────────────────────────────────────

	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var cell_type: int = grid[y][x]
			var cell_pos := OFFSET + Vector3(x * TILE_SIZE, 0, y * TILE_SIZE)
			_spawn_floor(cell_pos, TILE_SIZE)

			if cell_type != 2 and cell_type != 0:
				_spawn_ceiling(cell_pos, TILE_SIZE, _heights[y][x])

				# Generate lintels for ceiling height mismatches between adjacent floors
				var adj_dirs := [
					[Vector2i(0, -1), Vector3(0, 0, -TILE_SIZE / 2.0), Vector3(TILE_SIZE, 1.0, 0.2)],
					[Vector2i(0, 1), Vector3(0, 0, TILE_SIZE / 2.0), Vector3(TILE_SIZE, 1.0, 0.2)],
					[Vector2i(1, 0), Vector3(TILE_SIZE / 2.0, 0, 0), Vector3(0.2, 1.0, TILE_SIZE)],
					[Vector2i(-1, 0), Vector3(-TILE_SIZE / 2.0, 0, 0), Vector3(0.2, 1.0, TILE_SIZE)]
				]
				var current_h: float = _heights[y][x]
				for adj in adj_dirs:
					var d: Vector2i = adj[0]
					var offset_pos: Vector3 = adj[1]
					var default_size: Vector3 = adj[2]
					var nx = x + d.x
					var ny = y + d.y
					if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
						var n_type = grid[ny][nx]
						if n_type != 2 and n_type != 0:
							var n_h: float = _heights[ny][nx]
							if current_h > n_h:
								var diff = current_h - n_h
								var lintel_pos = cell_pos + offset_pos
								lintel_pos.y = n_h + diff / 2.0
								var lintel_size = Vector3(default_size.x, diff, default_size.z)
								_spawn_lintel(lintel_pos, lintel_size)

			match cell_type:
				2:
					# 直接读取预计算结果，已经过两遍传播，保证相邻墙格等高无接缝
					var wall_height: float = wall_h_map.get(Vector2i(x, y), 3.0)
					_spawn_wall(cell_pos, TILE_SIZE, wall_height)
				5:
					var pillar := PILLAR_PREFAB.instantiate()
					pillar.position = cell_pos
					var room_h = _heights[y][x]
					pillar.scale.y = room_h / 3.0
					add_child(pillar)
				3:
					if randf() < 0.7:
						_spawn_prefab(CHEST_PREFAB, cell_pos)
					else:
						_spawn_random_decor(cell_pos)
				4:
					if randf() < 0.5:
						_spawn_prefab(BARREL_PREFAB, cell_pos)
					else:
						_spawn_prefab(CRATE_PREFAB, cell_pos)

			if cell_type != 2 and cell_type != 0:
				if not player_spawned and cell_type == 1:
					player_spawn_pos = cell_pos + Vector3(0, 0.5, 0)
					player_spawned = true
				elif player_spawned:
					# Wall torches
					var directions := [
						Vector2i(0, -1),
						Vector2i(0, 1),
						Vector2i(1, 0),
						Vector2i(-1, 0)
					]
					var torch_spawned := false
					for dir in directions:
						var nx = x + dir.x
						var ny = y + dir.y
						if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
							if grid[ny][nx] == 2:
								if randf() < 0.12:
									_spawn_torch_on_wall(cell_pos, dir)
									torch_spawned = true
									break
									
					if not torch_spawned:
						# 6% probability to spawn gatherable brewing material
						if randf() < 0.06:
							var scatter = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
							_spawn_random_material(cell_pos + scatter)
						# 4% probability to spawn random scatter decor
						elif randf() < 0.04:
							var scatter = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
							_spawn_random_decor(cell_pos + scatter)

	# 一次性构建 MultiMesh 并添加到场景，实现合批极速绘制
	_build_multi_meshes()

	# Place extraction portal on a random FLOOR tile far from spawn
	if player_spawned:
		_spawn_extraction_portal(grid, OFFSET, TILE_SIZE, player_spawn_pos)

	if not player_spawned:
		player_spawn_pos = Vector3(0, 0.5, 0)

func _spawn_extraction_portal(grid: Array, offset: Vector3, tile_size: float, spawn_pos: Vector3) -> void:
	var best_dist = 0.0
	var best_pos = Vector3.ZERO
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if grid[y][x] == 1:
				var pos = offset + Vector3(x * tile_size, 0.5, y * tile_size)
				var dist = pos.distance_to(spawn_pos)
				if dist > best_dist:
					best_dist = dist
					best_pos = pos

	if best_pos == Vector3.ZERO:
		return

	# Extraction portal visual (glowing disc)
	var portal_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 0.2
	portal_mesh.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.8, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.5, 0.4)
	mat.emission_energy_multiplier = 2.0
	portal_mesh.material_override = mat
	portal_mesh.position = best_pos + Vector3(0, 0.3, 0)
	add_child(portal_mesh)

	# Extraction area trigger
	var area := Area3D.new()
	area.name = "ExtractionPortal"
	area.position = best_pos + Vector3(0, 0.5, 0)
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	col_shape.shape = box
	area.add_child(col_shape)
	area.body_entered.connect(_on_extraction_entered)
	add_child(area)

	print("[Dungeon] Extraction portal placed at ", best_pos)

func _on_extraction_entered(body: Node3D) -> void:
	if not body is Player:
		return
	print("[Dungeon] Extraction triggered by player!")
	# 撤离结算：携带材料/武器转入酒馆库存
	_settle_extraction_loot(body as Player)
	if TavernManager:
		TavernManager.extract_to_tavern()

## 撤离结算：将玩家拾取的材料/武器转入 TavernManager.inventory
func _settle_extraction_loot(player: Player) -> void:
	var tm: Node = get_node_or_null("/root/TavernManager")
	if tm == null:
		return
	# 统计本局地牢拾取物（由 GameState 记录）
	var carried_materials: int = GameState.get_carried_materials()
	var carried_weapons: int = GameState.get_carried_weapons()
	var carried_shields: int = GameState.get_carried_shields()
	print("[Dungeon] Extraction loot: %d materials, %d weapons, %d shields" % [carried_materials, carried_weapons, carried_shields])
	# 材料已实时注入 TavernManager.inventory（player_state_picking_up 调用 add_material）
	# 此处仅打印结算确认，武器/盾已装备到 equipment
	# 注入 TavernManager 统计（若方法存在）
	if tm.has_method("record_expedition_loot"):
		tm.record_expedition_loot(carried_materials, carried_weapons, carried_shields)

func _spawn_collision(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)

func _spawn_floor(pos: Vector3, tile_size: float) -> void:
	var t := Transform3D()
	t.origin = pos - Vector3(0, 0.05, 0)
	floor_transforms.append(t)
	_spawn_collision(t.origin, Vector3(tile_size, 0.1, tile_size))

func _spawn_wall(pos: Vector3, tile_size: float, wall_height: float) -> void:
	var t := Transform3D()
	# 只做平移，不对实例 Transform 做 Y 缩放
	# （非均匀缩放会歪曲法线→光照失败）
	# 每组的 BoxMesh 直接使用正确高度，无需实例缩放
	t.origin = pos + Vector3(0, wall_height / 2.0, 0)
	if not wall_transforms_by_height.has(wall_height):
		wall_transforms_by_height[wall_height] = []
	wall_transforms_by_height[wall_height].append(t)
	_spawn_collision(t.origin, Vector3(tile_size, wall_height, tile_size))

func _spawn_ceiling(pos: Vector3, tile_size: float, ceiling_height: float) -> void:
	var t := Transform3D()
	t.origin = pos + Vector3(0, ceiling_height + 0.05, 0)
	ceiling_transforms.append(t)
	_spawn_collision(t.origin, Vector3(tile_size, 0.1, tile_size))

func _spawn_prefab(prefab: PackedScene, pos: Vector3) -> void:
	var instance := prefab.instantiate()
	instance.position = pos
	add_child(instance)
	# 宝箱注入区域属性，决定其材料掉落池
	if instance is Chest:
		instance.zone = dungeon_zone
	# 预制体补全碰撞（若本身无 PhysicsBody 则添加环境层 BoxShape）
	_ensure_collision_on_instance(instance)

## 确保实例有物理碰撞：若实例及其子节点无 PhysicsBody3D，则基于 AABB 添加 StaticBody3D。
func _ensure_collision_on_instance(instance: Node) -> void:
	# 已有 PhysicsBody3D 则跳过
	if _has_physics_body(instance):
		return
	# 仅对 Node3D 处理（基于 mesh AABB 添加碰撞）
	if not (instance is Node3D):
		return
	var node3d: Node3D = instance
	# 收集所有 MeshInstance3D 子节点，为每个添加碰撞
	var meshes: Array = node3d.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	# 用整体 AABB 创建单个碰撞体（更高效）
	var combined_aabb: AABB = AABB()
	var has_aabb: bool = false
	for m in meshes:
		var mi: MeshInstance3D = m
		var aabb: AABB = mi.get_aabb()
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
	body.collision_layer = 1  # 环境层
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = combined_aabb.size
	col.shape = shape
	col.position = combined_aabb.position + combined_aabb.size * 0.5
	body.add_child(col, true)
	node3d.add_child(body, true)

## 递归检测节点树是否已含 PhysicsBody3D
func _has_physics_body(node: Node) -> bool:
	if node is PhysicsBody3D:
		return true
	for c in node.get_children():
		if _has_physics_body(c):
			return true
	return false

func _spawn_lintel(pos: Vector3, size: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	# 门楣宽/高按物理尺寸平铺，1m = 1次 = 32px
	var mat := _make_terrain_mat("LINTEL", Vector2(size.x, size.y))
	mesh.material_override = mat
	add_child(mesh)
	_spawn_collision(pos, size)

func _build_multi_meshes() -> void:
	# 1. 地板 MultiMesh（FLOOR 图块，平面 TILE_SIZE×TILE_SIZE）
	if floor_transforms.size() > 0:
		var mm_instance := MultiMeshInstance3D.new()
		mm_instance.name = "FloorMultiMesh"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var base_mesh := BoxMesh.new()
		base_mesh.size = Vector3(TILE_SIZE, 0.1, TILE_SIZE)
		mm.mesh = base_mesh
		mm.instance_count = floor_transforms.size()
		for i in range(floor_transforms.size()):
			mm.set_instance_transform(i, floor_transforms[i])
		mm_instance.multimesh = mm
		if _shared_floor_mat == null:
			# TILE_SIZE=3m → 每轴平铺 3 次（每次 = 1m = 32px）
			_shared_floor_mat = _make_terrain_mat("FLOOR", Vector2(TILE_SIZE, TILE_SIZE))
		mm_instance.material_override = _shared_floor_mat
		add_child(mm_instance)

	# 2. 天花板 MultiMesh（CEILING 图块）
	if ceiling_transforms.size() > 0:
		var mm_instance := MultiMeshInstance3D.new()
		mm_instance.name = "CeilingMultiMesh"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var base_mesh := BoxMesh.new()
		base_mesh.size = Vector3(TILE_SIZE, 0.1, TILE_SIZE)
		mm.mesh = base_mesh
		mm.instance_count = ceiling_transforms.size()
		for i in range(ceiling_transforms.size()):
			mm.set_instance_transform(i, ceiling_transforms[i])
		mm_instance.multimesh = mm
		if _shared_ceiling_mat == null:
			_shared_ceiling_mat = _make_terrain_mat("CEILING", Vector2(TILE_SIZE, TILE_SIZE))
		mm_instance.material_override = _shared_ceiling_mat
		add_child(mm_instance)

	# 3. 墙面 MultiMesh（按高度分组，保证 tile_repeat.y = wall_height）
	# 每种独特高度建一个 MultiMesh + 独立材质，Draw Call = 高度种类数（通常 2-4 次）
	for wall_height in wall_transforms_by_height:
		var transforms: Array = wall_transforms_by_height[wall_height]
		if transforms.is_empty():
			continue
		var mm_instance := MultiMeshInstance3D.new()
		mm_instance.name = "WallMultiMesh_h%.1f" % wall_height
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var base_mesh := BoxMesh.new()
		# 屏弃缩放，改用正确高度的网格——此旹案保证法线垂直于面，光照计算正确
		base_mesh.size = Vector3(TILE_SIZE, wall_height, TILE_SIZE)
		mm.mesh = base_mesh
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])
		mm_instance.multimesh = mm
		# tile_repeat.x = TILE_SIZE（横向 3m → 3 格）
		# tile_repeat.y = wall_height（纵向 Nm → N 格，1m = 1 tile = 32px 锁死）
		var mat := _make_terrain_mat("WALL", Vector2(TILE_SIZE, wall_height))
		mm_instance.material_override = mat
		add_child(mm_instance)

func _spawn_torch_on_wall(cell_pos: Vector3, wall_dir: Vector2i) -> void:
	var torch := TORCH_PREFAB.instantiate()
	const TILE_SIZE := 3.0
	var pos_offset := Vector3(wall_dir.x, 0, wall_dir.y) * (TILE_SIZE / 2.0)
	var clip_offset := -Vector3(wall_dir.x, 0, wall_dir.y) * 0.1
	torch.position = cell_pos + pos_offset + clip_offset + Vector3(0, 1.5, 0)
	
	if wall_dir == Vector2i(0, -1):
		torch.rotation.y = PI
	elif wall_dir == Vector2i(0, 1):
		torch.rotation.y = 0.0
	elif wall_dir == Vector2i(1, 0):
		torch.rotation.y = PI / 2.0
	elif wall_dir == Vector2i(-1, 0):
		torch.rotation.y = -PI / 2.0
		
	add_child(torch)

func _pick_weighted(weights: Dictionary) -> String:
	var total_weight := 0
	for key in weights:
		total_weight += weights[key]
		
	var r = randi() % total_weight
	var cumulative_weight := 0
	for key in weights:
		cumulative_weight += weights[key]
		if r < cumulative_weight:
			return key
	return ""

func _spawn_random_material(pos: Vector3) -> void:
	# 按当前区域从 ZoneManager 获取散落材料池（替换旧虚构材料）
	var scatter_pool: Dictionary = MATERIALS_CONFIG  # fallback
	var zm: Node = get_node_or_null("/root/ZoneManager")
	if zm != null:
		scatter_pool = zm.get_scatter_materials(dungeon_zone)
	var mat_id = _pick_weighted(scatter_pool)
	if mat_id != "":
		var item = PICKABLE_ITEM_PREFAB.instantiate()
		item.material_id = mat_id
		item.position = pos + Vector3(0, 0.3, 0)
		add_child(item)

func _spawn_random_decor(pos: Vector3) -> void:
	var path = _pick_weighted(DECOR_CONFIG)
	if path != "":
		var prefab = load(path)
		if prefab:
			var instance = prefab.instantiate()
			instance.position = pos
			add_child(instance)
			# 装饰物补全碰撞（若预制体本身无 PhysicsBody 则添加环境层 BoxShape）
			_ensure_collision_on_instance(instance)
