@tool
class_name BaseRoom
extends Node3D

const DROPPED_KEY_PREFAB := preload("res://scenes/collectibles/dropped_key/dropped_key.tscn")

@export var editor_key_indicator_mesh: MeshInstance3D
@export var key_color: Door.KeyColor:
	set(new_color):
		key_color = new_color
		editor_update_key_indicator()

@onready var ceilings: GridMap = %Ceilings
@onready var editor_key_indicator: Node3D = %EditorKeyIndicator
@onready var enemies: Node3D = %Enemies
@onready var floors: GridMap = %Floors

var cell_ids_with_no_ceiling := []

func _ready() -> void:
	if Engine.is_editor_hint():
		editor_update_key_indicator()
	else:
		fill_ceilings()
		prep_enemies()

func fill_ceilings() -> void:
	for cell_name : String in ["Ground", "Hole-Corner", "Hole-Side", "Hole-UTurn"]:
		cell_ids_with_no_ceiling.push_back(floors.mesh_library.find_item_by_name(cell_name))
	var used_cells : Array[Vector3i] = floors.get_used_cells()
	for cell_coords in used_cells:
		var tile_id: int = floors.get_cell_item(cell_coords)
		if cell_ids_with_no_ceiling.has(tile_id):
			ceilings.set_cell_item(cell_coords, 0)

func prep_enemies() -> void:
	for enemy: Enemy in enemies.get_children():
		enemy.screamed.connect(on_scream_heard)
		enemy.dead.connect(on_enemy_death)
	
func on_scream_heard() -> void:
	for enemy: Enemy in enemies.get_children():
		enemy.player = GameState.current_player

func on_enemy_death(enemy_transform: Transform3D) -> void:
	for enemy: Enemy in enemies.get_children():
		if not enemy.health.is_dead():
			return
	if key_color != Door.KeyColor.None:
		drop_key(enemy_transform)

func drop_key(key_transform: Transform3D) -> void:
	var key := DROPPED_KEY_PREFAB.instantiate() as DroppedKey
	key.color = key_color
	key.global_transform = key_transform
	GameState.current_level.add_child(key)
	var rand_angle := randf_range(0, PI)
	var launch_velocity := Vector3(cos(rand_angle) * 2.0, 5.0, sin(rand_angle) * 2.0)
	key.apply_central_impulse(launch_velocity)

func editor_update_key_indicator() -> void:
	if Engine.is_editor_hint():
		editor_key_indicator_mesh.visible = key_color != Door.KeyColor.None
		if key_color != Door.KeyColor.None:
			var material := editor_key_indicator_mesh.get_active_material(0).duplicate() as StandardMaterial3D
			material.albedo_color = Door.COLOR_MAP[key_color]
			editor_key_indicator_mesh.set_surface_override_material(0, material)
	else:
		editor_key_indicator_mesh.visible = false
	
	
	
