extends Node3D
class_name ProceduralDungeon

const PLAYER_PREFAB := preload("res://scenes/characters/player/player.tscn")
const PILLAR_PREFAB := preload("res://scenes/props/structures/pillar.tscn")
const CRATE_PREFAB := preload("res://scenes/props/crates/small_crate.tscn")
const BARREL_PREFAB := preload("res://scenes/props/barrel/barrel.tscn")

var wfc = null

func _ready() -> void:
	# Instantiate and run WFC generator
	wfc = WFC_RoomGenerator.new()
	add_child(wfc)
	var grid = wfc.collapse_room()
	
	# Spawn dungeon 3D tiles based on the generated grid
	_generate_visuals(grid)
	
	# Play music/sound if available
	if AudioManager:
		AudioManager.start_music()

func _generate_visuals(grid: Array) -> void:
	var tile_size = 3.0
	var offset = Vector3(-15.0, 0, -15.0)
	var spawn_pos = Vector3(0, 0, 0)
	var player_spawned = false
	
	# Setup some warm ambient light
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 45, 0)
	sun.light_energy = 0.5
	sun.light_color = Color(0.9, 0.8, 0.7)
	add_child(sun)
	
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var cell_type = grid[y][x]
			var cell_pos = offset + Vector3(x * tile_size, 0, y * tile_size)
			
			# Always spawn a floor floor mesh
			var floor_mesh = MeshInstance3D.new()
			var floor_box = BoxMesh.new()
			floor_box.size = Vector3(tile_size, 0.1, tile_size)
			floor_mesh.mesh = floor_box
			floor_mesh.position = cell_pos - Vector3(0, 0.05, 0)
			
			# Setup standard wood/dirt material for floor
			var floor_mat = StandardMaterial3D.new()
			floor_mat.albedo_color = Color(0.2, 0.15, 0.1) # Dark brown wood
			floor_mat.roughness = 0.8
			floor_mesh.material_override = floor_mat
			add_child(floor_mesh)
			
			# Add StaticBody3D collision to the floor
			var static_body = StaticBody3D.new()
			var coll_shape = CollisionShape3D.new()
			var box_shape = BoxShape3D.new()
			box_shape.size = Vector3(tile_size, 0.1, tile_size)
			coll_shape.shape = box_shape
			static_body.add_child(coll_shape)
			static_body.position = floor_mesh.position
			add_child(static_body)
			
			if cell_type == 2: # TileType.WALL
				# Spawn standard Wall Box mesh with collision
				var wall_mesh = MeshInstance3D.new()
				var wall_box = BoxMesh.new()
				wall_box.size = Vector3(tile_size, 3.0, tile_size)
				wall_mesh.mesh = wall_box
				wall_mesh.position = cell_pos + Vector3(0, 1.5, 0)
				
				# Setup stone-like material for Wall
				var wall_mat = StandardMaterial3D.new()
				wall_mat.albedo_color = Color(0.3, 0.3, 0.35) # Gray slate stone
				wall_mat.roughness = 0.9
				wall_mesh.material_override = wall_mat
				add_child(wall_mesh)
				
				var wall_static = StaticBody3D.new()
				var wall_coll = CollisionShape3D.new()
				var wall_shape = BoxShape3D.new()
				wall_shape.size = Vector3(tile_size, 3.0, tile_size)
				wall_coll.shape = wall_shape
				wall_static.add_child(wall_coll)
				wall_static.position = wall_mesh.position
				add_child(wall_static)
				
			elif cell_type == 5: # TileType.PILLAR
				var pillar = PILLAR_PREFAB.instantiate()
				pillar.position = cell_pos
				add_child(pillar)
				
			elif cell_type == 3: # TileType.LOOT
				var crate = CRATE_PREFAB.instantiate()
				crate.position = cell_pos
				add_child(crate)
				
			elif cell_type == 4: # TileType.RESOURCE
				var barrel = BARREL_PREFAB.instantiate()
				barrel.position = cell_pos
				add_child(barrel)
				
			if cell_type == 1 and not player_spawned: # TileType.FLOOR
				spawn_pos = cell_pos + Vector3(0, 0.5, 0)
				player_spawned = true
				
	# Fallback start if WFC had corner issues
	if not player_spawned:
		spawn_pos = Vector3(0, 0.5, 0)
		
	# Instantiate player
	var player = PLAYER_PREFAB.instantiate()
	player.position = spawn_pos
	add_child(player)
	
	# Add custom HUD Return button
	var hud_layer = CanvasLayer.new()
	var quit_btn = Button.new()
	quit_btn.text = "Return to Main Menu"
	quit_btn.position = Vector2(16, 16)
	quit_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	hud_layer.add_child(quit_btn)
	add_child(hud_layer)
