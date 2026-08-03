extends GdUnitTestSuite

const CAPTURE_TOOL := "res://tools/sword_first_person_animation_capture.gd"
const VIEW_MODEL_SCENE: PackedScene = preload("res://scenes/characters/player/view_model.tscn")
const SWORD_SCENE: PackedScene = preload("res://assets/meshes/weapons/weapons_voxel_sword.glb")
const EDITOR_SCENES := [
	"res://scenes/characters/player/weapon_animation_editors/sword_standard.tscn",
	"res://scenes/characters/player/weapon_animation_editors/sword_alternate.tscn",
	"res://scenes/characters/player/weapon_animation_editors/sword_heavy.tscn",
]


func test_sword_editors_contain_only_weapon_and_equipment_pivots() -> void:
	for scene_path: String in EDITOR_SCENES:
		var scene := load(scene_path) as PackedScene
		assert_object(scene).is_not_null()
		if scene == null:
			continue
		var editor: Node = auto_free(scene.instantiate())
		assert_object(editor.get_node_or_null("ActionPivot/WeaponSocket/Weapon")).is_not_null()
		assert_object(editor.get_node_or_null("ShieldActionPivot/ShieldImpactPivot/ShieldSocket/ShieldOrientation")).is_not_null()
		assert_object(editor.find_child("PlayerVisualModel", true, false)).is_null()
		assert_object(editor.find_child("Skeleton3D", true, false)).is_null()


func test_sword_capture_uses_only_the_independent_runtime_view_model() -> void:
	var script := load(CAPTURE_TOOL) as GDScript
	assert_object(script).is_not_null()
	if script == null:
		return
	var source := script.source_code
	assert_str(source).contains("view_model.tscn")
	assert_str(source).contains("vm_sword_slash")
	assert_str(source).contains("weapons_voxel_sword.glb")
	assert_str(source).contains("SubViewport")
	assert_str(source).contains("first_person_capture_quality.gd")
	assert_str(source).contains("QUALITY.validate(metrics)")
	assert_str(source).contains("DEFAULT_WEAPON_CAMERA_FOV")
	assert_str(source).not_contains("player.tscn")
	assert_str(source).not_contains("sword_attack")


func test_sword_capture_declares_all_six_authored_attack_phases() -> void:
	var source := (load(CAPTURE_TOOL) as GDScript).source_code
	for phase_name in ["00_hold", "01_preparation", "02_windup", "03_strike", "04_follow_through", "05_recovery"]:
		assert_str(source).contains(phase_name)
	assert_str(source).contains("PHASES.size() * CONTACT_FRAME_SIZE.x")
	assert_str(source).not_contains("index / 3")


func test_sword_capture_samples_a_dense_runtime_timeline() -> void:
	var source := (load(CAPTURE_TOOL) as GDScript).source_code
	assert_str(source).contains("TIMELINE_FRAME_COUNT := 21")
	assert_str(source).contains("sample_action(ACTION, progress)")
	assert_str(source).contains("timeline_contact_sheet.png")
	assert_str(source).contains("TIMELINE_COLUMNS := 7")


func test_sword_runtime_view_model_instantiates_no_character_geometry() -> void:
	var view_model := auto_free(VIEW_MODEL_SCENE.instantiate()) as ViewModel
	add_child(view_model)
	await get_tree().process_frame
	var weapon := WeaponData.new()
	weapon.id = "sword"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "one_hand_melee"
	weapon.skill_school = "one_hand_sword"
	weapon.view_model_profile = "sword"
	weapon.glb_mesh = SWORD_SCENE
	view_model.set_weapon(weapon)
	assert_object(view_model._current_weapon_node).is_not_null()
	assert_object(view_model.find_child("PlayerVisualModel", true, false)).is_null()
	assert_object(view_model.find_child("Skeleton3D", true, false)).is_null()
