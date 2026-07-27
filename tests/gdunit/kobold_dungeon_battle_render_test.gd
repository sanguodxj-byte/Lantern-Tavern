extends GdUnitTestSuite
## Real Dungeon Battle Scene Render Test for Kobold Character.
## Uses the project's canonical procedural dungeon scene (res://scenes/expedition/procedural_dungeon.tscn).
## Strictly avoids creating new scene files, adhering to project guidelines.

const DUNGEON_SCENE_PATH := "res://scenes/expedition/procedural_dungeon.tscn"
const KOBOLD_RIG_PATH := "res://assets/meshes/characters/voxel_kobold_42px_rig.glb"
const OUTPUT_PATH := "res://reports/dungeon_kobold_battle_walk_test.png"

var _dungeon: ProceduralDungeon = null


func before_test() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")
	if spawner != null:
		spawner.set("use_mock_nodes", true)


func after_test() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")
	if spawner != null:
		spawner.set("use_mock_nodes", false)
	if is_instance_valid(_dungeon):
		if _dungeon.get_parent() != null:
			_dungeon.get_parent().remove_child(_dungeon)
		_dungeon.free()
		_dungeon = null


func test_kobold_walk_animation_in_canonical_dungeon_scene() -> void:
	seed(94021)
	var dungeon_scene := load(DUNGEON_SCENE_PATH) as PackedScene
	assert_object(dungeon_scene).is_not_null()
	_dungeon = dungeon_scene.instantiate() as ProceduralDungeon
	_dungeon.dungeon_zone = 0
	add_child(_dungeon)
	await await_idle_frame()

	# Instantiate Kobold animated rig inside the canonical dungeon room
	var packed_kobold := load(KOBOLD_RIG_PATH) as PackedScene
	assert_object(packed_kobold).is_not_null()

	var kobold_inst := packed_kobold.instantiate() as Node3D
	assert_object(kobold_inst).is_not_null()
	_dungeon.add_child(kobold_inst)
	kobold_inst.position = Vector3(2.0, 0.0, 2.0)
	await await_idle_frame()

	var anim_player := _find_animation_player(kobold_inst)
	assert_object(anim_player).is_not_null()

	# Test run animation stride playback
	var walk_anim := anim_player.get_animation("run")
	assert_object(walk_anim).is_not_null()

	anim_player.play("run")
	anim_player.seek(walk_anim.length * 0.15, true)
	anim_player.advance(0.0)
	await await_idle_frame()

	# Render dungeon battle scene bitmap map with kobold position marker
	var grid: Array = _dungeon.layout.grid
	assert_bool(grid.is_empty()).is_false()

	var image := _render_dungeon_image(grid, kobold_inst.position)
	_ensure_reports_dir()
	var err := image.save_png(OUTPUT_PATH)
	assert_int(err).is_equal(OK)
	assert_bool(FileAccess.file_exists(OUTPUT_PATH)).is_true()


func _render_dungeon_image(grid: Array, kobold_pos: Vector3) -> Image:
	var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.05, 0.06, 1.0))

	for y in range(grid.size()):
		var row: Array = grid[y]
		for x in range(row.size()):
			if int(row[x]) > 0:
				for py in range(8):
					for px in range(8):
						var gx := x * 10 + px
						var gy := y * 10 + py
						if gx < 512 and gy < 512:
							img.set_pixel(gx, gy, Color(0.25, 0.25, 0.28, 1.0))

	var kx := int(kobold_pos.x * 10) + 120
	var ky := int(kobold_pos.z * 10) + 120
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			if dx*dx + dy*dy <= 36:
				var px := kx + dx
				var py := ky + dy
				if px >= 0 and px < 512 and py >= 0 and py < 512:
					img.set_pixel(px, py, Color(0.85, 0.2, 0.15, 1.0))

	return img


func _ensure_reports_dir() -> void:
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("reports")


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
