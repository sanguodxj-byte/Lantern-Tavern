extends BaseLevel
class_name WFCVisualTest

const PILLAR_PREFAB := preload("res://scenes/props/structures/pillar.tscn")
const CRATE_PREFAB := preload("res://scenes/props/crates/small_crate.tscn")
const BARREL_PREFAB := preload("res://scenes/props/barrel/barrel.tscn")
const TORCH_PREFAB := preload("res://scenes/props/torch/torch.tscn")
const CHEST_PREFAB := preload("res://scenes/props/chest/chest.tscn")
const PICKABLE_ITEM_PREFAB := preload("res://scenes/equipment/pickable_item.tscn")

# 所有地形贴图统一采用 32x32px 规格，在 128px 贴图集内
const TILE_PIXEL_SIZE := 32.0
const DUNGEON_TEXTURE_SIZE := 128.0
const TILE_PIXEL_OFFSET_X := 16.0
const TILE_PIXEL_OFFSET_Y := 0.0

const ZONE_TEXTURES := {
	0: preload("res://assets/textures/dungeon-texture.png"),
	1: preload("res://assets/textures/ice_dungeon-texture.png")
}

var _shared_wall_mat: StandardMaterial3D = null
var _shared_floor_mat: StandardMaterial3D = null

# 用于收集 GPU 实例坐标，优化渲染性能
var floor_transforms: Array[Transform3D] = []
var ceiling_transforms: Array[Transform3D] = []
var wall_transforms: Array[Transform3D] = []

var dungeon_zone: int = 0  # 默认森林/经典

func get_zone_texture(zone_id: int) -> Texture2D:
	if ZONE_TEXTURES.has(zone_id):
		return ZONE_TEXTURES[zone_id]
	return ZONE_TEXTURES[0]

func get_terrain_uv_config(type_name: String, physical_size: Vector3) -> Dictionary:
	var ratio_x := 0.25
	if type_name == "FLOOR" or type_name == "CEILING":
		ratio_x = 0.125
		
	var offset_x := 0.125
	if type_name == "FLOOR" or type_name == "CEILING":
		offset_x = 0.25
		
	return {
		"scale": Vector3(ratio_x * physical_size.x, 0.25 * physical_size.y, 0.25 * physical_size.z),
		"offset": Vector3(offset_x, 0.0, 0.0)
	}

const MATERIALS_CONFIG = {
	"wild_glowcap": 15,
	"frost_berry": 10,
	"fire_bloom": 10,
	"cave_lichen": 15,
	"honeycomb": 8,
	"sweet_grass": 12,
	"bitter_root": 15,
	"mountain_barley": 15
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
var _heights: Array = []

func is_procedural() -> bool:
	return true

func _ready() -> void:
	# Instantiate and run BSP generator with 30x30 size for testing
	var bsp = BSP_DungeonGenerator.new()
	add_child(bsp)
	
	var start_time = Time.get_ticks_msec()
	_grid = bsp.generate_dungeon(30, 30)
	_heights = bsp.ceiling_heights.duplicate(true)
	var elapsed = Time.get_ticks_msec() - start_time
	print("[BSP Test] Generated 30x30 room in ", elapsed, " ms.")
	
	bsp.queue_free()
	
	# Spawn dungeon 3D tiles based on the generated grid
	_generate_visuals(_grid)
	
	# Set player spawn location and trigger player spawn
	player_spawn.global_position = player_spawn_pos
	spawn_player()
	
	# Add a simple debug UI label to show generation info
	_add_debug_ui(elapsed)

func _add_debug_ui(elapsed_ms: int) -> void:
	var canvas := CanvasLayer.new()
	var label := Label.new()
	label.text = "BSP 30x30 Room Test Sandbox\nGeneration time: %d ms\nPress [R] to reload and generate new map" % elapsed_ms
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 24)
	canvas.add_child(label)
	add_child(canvas)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			print("[BSP Test] Reloading scene to regenerate map...")
			get_tree().reload_current_scene()

func _generate_visuals(grid: Array) -> void:
	# 清空先前收集的 Transform 数组
	floor_transforms.clear()
	ceiling_transforms.clear()
	wall_transforms.clear()

	const TILE_SIZE := 3.0
	var grid_width = grid[0].size() if grid.size() > 0 else 0
	var grid_height = grid.size()
	var offset_x = -(grid_width * TILE_SIZE) / 2.0
	var offset_z = -(grid_height * TILE_SIZE) / 2.0
	var OFFSET := Vector3(offset_x, 0, offset_z)
	
	# Setup dungeon lighting
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 45, 0)
	sun.light_energy = 0.6
	sun.light_color = Color(0.9, 0.7, 0.45)
	sun.shadow_enabled = true
	add_child(sun)
	
	# Ambient light
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_color = Color(0.25, 0.2, 0.15)
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	add_child(env)
	
	var player_spawned := false
	
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var cell_type: int = grid[y][x]
			var cell_pos := OFFSET + Vector3(x * TILE_SIZE, 0, y * TILE_SIZE)
			
			# Floor mesh (always spawned)
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
				2: # TileType.WALL
					var wall_height = 3.0
					var directions := [
						Vector2i(0, -1),
						Vector2i(0, 1),
						Vector2i(1, 0),
						Vector2i(-1, 0)
					]
					var max_h = 0.0
					for d in directions:
						var nx = x + d.x
						var ny = y + d.y
						if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
							var n_type = grid[ny][nx]
							if n_type != 2 and n_type != 0:
								var n_h = _heights[ny][nx]
								if n_h > max_h:
									max_h = n_h
					if max_h > 0.0:
						wall_height = max_h
					else:
						wall_height = _heights[y][x]
					_spawn_wall(cell_pos, TILE_SIZE, wall_height)
				5: # TileType.PILLAR
					var pillar := PILLAR_PREFAB.instantiate()
					pillar.position = cell_pos
					var room_h = _heights[y][x]
					pillar.scale.y = room_h / 3.0
					add_child(pillar)
				3: # TileType.LOOT
					if randf() < 0.7:
						_spawn_prefab(CHEST_PREFAB, cell_pos)
					else:
						_spawn_random_decor(cell_pos)
				4: # TileType.RESOURCE
					if randf() < 0.5:
						_spawn_prefab(BARREL_PREFAB, cell_pos)
					else:
						_spawn_prefab(CRATE_PREFAB, cell_pos)
			
			# Place player on first FLOOR tile encountered
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

	# Fallback spawn if no FLOOR was found
	if not player_spawned:
		player_spawn_pos = Vector3(0, 0.5, 0)

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
	t = t.scaled(Vector3(1.0, wall_height / 3.0, 1.0))
	t.origin = pos + Vector3(0, wall_height / 2.0, 0)
	wall_transforms.append(t)
	_spawn_collision(t.origin, Vector3(tile_size, wall_height, tile_size))

func _spawn_ceiling(pos: Vector3, tile_size: float, ceiling_height: float) -> void:
	var t := Transform3D()
	t.origin = pos + Vector3(0, ceiling_height + 0.05, 0)
	ceiling_transforms.append(t)
	_spawn_collision(t.origin, Vector3(tile_size, 0.1, tile_size))

func _spawn_lintel(pos: Vector3, size: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = get_zone_texture(dungeon_zone)
	mat.texture_filter = 0
	
	var uv_cfg = get_terrain_uv_config("LINTEL", size)
	mat.uv1_scale = uv_cfg["scale"]
	mat.uv1_offset = uv_cfg["offset"]
	mat.roughness = 0.9
	mesh.material_override = mat
	add_child(mesh)
	_spawn_collision(pos, size)

func _build_multi_meshes() -> void:
	var tex = get_zone_texture(dungeon_zone)
	const TILE_SIZE := 3.0
	
	# 1. 地板 MultiMesh
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
			_shared_floor_mat = StandardMaterial3D.new()
			_shared_floor_mat.albedo_texture = tex
			_shared_floor_mat.texture_filter = 0
			var uv_cfg = get_terrain_uv_config("FLOOR", Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE))
			_shared_floor_mat.uv1_scale = uv_cfg["scale"]
			_shared_floor_mat.uv1_offset = uv_cfg["offset"]
			_shared_floor_mat.roughness = 0.8
		else:
			_shared_floor_mat.albedo_texture = tex
		mm_instance.material_override = _shared_floor_mat
		add_child(mm_instance)

	# 2. 天花板 MultiMesh
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
		
		if _shared_floor_mat == null:
			_shared_floor_mat = StandardMaterial3D.new()
			_shared_floor_mat.albedo_texture = tex
			_shared_floor_mat.texture_filter = 0
			var uv_cfg = get_terrain_uv_config("CEILING", Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE))
			_shared_floor_mat.uv1_scale = uv_cfg["scale"]
			_shared_floor_mat.uv1_offset = uv_cfg["offset"]
			_shared_floor_mat.roughness = 0.8
		else:
			_shared_floor_mat.albedo_texture = tex
		mm_instance.material_override = _shared_floor_mat
		add_child(mm_instance)

	# 3. 墙面 MultiMesh
	if wall_transforms.size() > 0:
		var mm_instance := MultiMeshInstance3D.new()
		mm_instance.name = "WallMultiMesh"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		
		var base_mesh := BoxMesh.new()
		base_mesh.size = Vector3(TILE_SIZE, 3.0, TILE_SIZE)
		mm.mesh = base_mesh
		
		mm.instance_count = wall_transforms.size()
		for i in range(wall_transforms.size()):
			mm.set_instance_transform(i, wall_transforms[i])
			
		mm_instance.multimesh = mm
		
		if _shared_wall_mat == null:
			_shared_wall_mat = StandardMaterial3D.new()
			_shared_wall_mat.albedo_texture = tex
			_shared_wall_mat.texture_filter = 0
			var uv_cfg = get_terrain_uv_config("WALL", Vector3(TILE_SIZE, 3.0, TILE_SIZE))
			_shared_wall_mat.uv1_scale = uv_cfg["scale"]
			_shared_wall_mat.uv1_offset = uv_cfg["offset"]
			_shared_wall_mat.roughness = 0.9
		else:
			_shared_wall_mat.albedo_texture = tex
		mm_instance.material_override = _shared_wall_mat
		add_child(mm_instance)

func _spawn_prefab(prefab: PackedScene, pos: Vector3) -> void:
	var instance := prefab.instantiate()
	instance.position = pos
	add_child(instance)

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
	var mat_id = _pick_weighted(MATERIALS_CONFIG)
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
