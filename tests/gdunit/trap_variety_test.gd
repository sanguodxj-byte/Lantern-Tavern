extends GdUnitTestSuite

# Tests for trap scenes: verifies each trap scene loads as an interactive
# Area3D with a voxel model and collision shape.

func _track_node(node: Node) -> Node:
	return auto_free(node)


# ── Flame Vent Trap ─────────────────────────────────────────────────────

func test_flame_vent_trap_scene_is_interactive_area() -> void:
	var scene := load("res://scenes/traps/flame_vent_trap.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var trap := _track_node(scene.instantiate())

	assert_bool(trap is Area3D).is_true()
	assert_object(trap.get_script()).is_not_null()
	assert_object((trap as Node).find_child("CollisionShape3D", true, false)).is_not_null()
	assert_object((trap as Node).find_child("VoxelModel", true, false)).is_not_null()


# ── Spikes Trap ─────────────────────────────────────────────────────────

func test_spikes_trap_scene_is_interactive_area() -> void:
	var scene := load("res://scenes/traps/spikes_trap.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var trap := _track_node(scene.instantiate())

	assert_bool(trap is Area3D).is_true()
	assert_object(trap.get_script()).is_not_null()
	assert_object((trap as Node).find_child("CollisionShape3D", true, false)).is_not_null()
	assert_object((trap as Node).find_child("VoxelModel", true, false)).is_not_null()


func test_spikes_trap_scene_has_navigation_obstacle() -> void:
	var scene := load("res://scenes/traps/spikes_trap.tscn") as PackedScene
	var trap := _track_node(scene.instantiate())

	var obstacle := (trap as Node).find_child("NavigationObstacle3D", true, false)
	assert_object(obstacle).is_not_null()
	assert_bool(obstacle is NavigationObstacle3D).is_true()


# ── Acid Trap ───────────────────────────────────────────────────────────

func test_acid_trap_scene_is_interactive_area() -> void:
	var scene := load("res://scenes/traps/acid_trap.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var trap := _track_node(scene.instantiate())

	assert_bool(trap is Area3D).is_true()
	assert_object(trap.get_script()).is_not_null()
	assert_object((trap as Node).find_child("CollisionShape3D", true, false)).is_not_null()
	assert_object((trap as Node).find_child("VoxelModel", true, false)).is_not_null()


func test_acid_trap_scene_has_bubble_particles() -> void:
	var scene := load("res://scenes/traps/acid_trap.tscn") as PackedScene
	var trap := _track_node(scene.instantiate())

	var bubbles := (trap as Node).find_child("Bubbles", true, false)
	assert_object(bubbles).is_not_null()
	assert_bool(bubbles is GPUParticles3D).is_true()


func test_acid_trap_scene_has_audio() -> void:
	var scene := load("res://scenes/traps/acid_trap.tscn") as PackedScene
	var trap := _track_node(scene.instantiate())

	var audio := (trap as Node).find_child("AudioStreamPlayer3D", true, false)
	assert_object(audio).is_not_null()
	assert_bool(audio is AudioStreamPlayer3D).is_true()
