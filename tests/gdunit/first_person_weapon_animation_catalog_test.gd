extends GdUnitTestSuite

const CATALOG := preload("res://scenes/characters/player/first_person_weapon_animation_catalog.gd")
const LIBRARY := preload("res://scenes/characters/player/first_person_animation_library.gd")

func test_every_weapon_has_separate_editor_library_for_each_variant() -> void:
	for weapon_id in CATALOG.WEAPON_IDS:
		for variant in CATALOG.VARIANTS:
			var animation_library := CATALOG.load_library(String(weapon_id), String(variant))
			assert_object(animation_library).is_not_null()
			assert_str(CATALOG.resource_path(String(weapon_id), String(variant))).contains(
				"weapon_animations/%s/%s.tres" % [weapon_id, variant]
			)

func test_every_weapon_variant_has_an_animation_editor_scene() -> void:
	for weapon_id in CATALOG.WEAPON_IDS:
		for variant in CATALOG.VARIANTS:
			var path := "res://scenes/characters/player/weapon_animation_editors/%s_%s.tscn" % [weapon_id, variant]
			var scene := load(path) as PackedScene
			assert_object(scene).is_not_null()
			if scene == null:
				continue
			var instance: Node = auto_free(scene.instantiate()) as Node
			var animation_player := instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
			assert_object(animation_player).is_not_null()
			if animation_player != null:
				assert_bool(animation_player.has_animation(&"vm_idle")).is_true()
			assert_object(instance.find_child("PlayerVisualModel", true, false)).is_null()
			assert_object(instance.find_child("Skeleton3D", true, false)).is_null()
			assert_object(instance.get_node_or_null("ShieldActionPivot/ShieldImpactPivot/ShieldSocket/ShieldOrientation")).is_not_null()

func test_each_weapon_variant_contains_editable_first_person_action_tracks() -> void:
	for weapon_id in CATALOG.WEAPON_IDS:
		for variant in CATALOG.VARIANTS:
			var animation_library := CATALOG.load_library(String(weapon_id), String(variant))
			if animation_library == null:
				continue
			var animation := animation_library.get_animation(_attack_name_for(String(weapon_id)))
			assert_object(animation).is_not_null()
			if animation == null:
				continue
			assert_int(animation.get_track_count()).is_equal(3)
			var position_path := NodePath("ShieldActionPivot:position") if weapon_id == &"shield" else NodePath("ActionPivot:position")
			var socket_path := NodePath("ShieldActionPivot/ShieldImpactPivot/ShieldSocket/ShieldOrientation:rotation") if weapon_id == &"shield" else NodePath("ActionPivot/WeaponSocket:rotation")
			var position_track := animation.find_track(position_path, Animation.TYPE_VALUE)
			var socket_track := animation.find_track(socket_path, Animation.TYPE_VALUE)
			assert_int(position_track).is_greater_equal(0)
			assert_int(socket_track).is_greater_equal(0)
			if position_track >= 0:
				assert_int(animation.track_get_key_count(position_track)).is_greater_equal(6)
				assert_int(animation.track_get_interpolation_type(position_track)).is_equal(Animation.INTERPOLATION_CUBIC)


func test_authored_libraries_contain_no_character_geometry_or_bone_tracks() -> void:
	for weapon_id in CATALOG.WEAPON_IDS:
		for variant in CATALOG.VARIANTS:
			var animation_library := CATALOG.load_library(String(weapon_id), String(variant))
			if animation_library == null:
				continue
			for animation_name in animation_library.get_animation_list():
				var animation := animation_library.get_animation(animation_name)
				for track_index in animation.get_track_count():
					var path := String(animation.track_get_path(track_index))
					assert_str(path).not_contains("FirstPersonArms")
					assert_str(path).not_contains("Skeleton3D:")
					assert_bool(animation.track_get_type(track_index) == Animation.TYPE_VALUE).is_true()

func test_variants_of_one_weapon_have_distinct_authored_animation_data() -> void:
	for weapon_id in CATALOG.WEAPON_IDS:
		var fingerprints := {}
		for variant in CATALOG.VARIANTS:
			var library := CATALOG.load_library(String(weapon_id), String(variant))
			var animation := library.get_animation(_attack_name_for(String(weapon_id)))
			var fingerprint := _fingerprint(animation)
			assert_bool(fingerprints.has(fingerprint)).is_false()
			fingerprints[fingerprint] = variant

func test_unknown_weapon_library_falls_back_to_generated_compatibility_library() -> void:
	var missing_path := CATALOG.resource_path("missing_weapon", "standard")
	assert_bool(ResourceLoader.exists(missing_path)).is_false()
	assert_object(CATALOG.load_library("missing_weapon", "standard")).is_null()
	var catalog_source := FileAccess.get_file_as_string(
		"res://scenes/characters/player/first_person_weapon_animation_catalog.gd"
	)
	assert_str(catalog_source).contains("ResourceLoader.exists(path)")

	var library := LIBRARY.load_for_weapon("missing_weapon", "standard")
	assert_object(library).is_not_null()
	assert_object(library.get_animation(&"vm_slash_default")).is_not_null()

func _attack_name_for(weapon_id: String) -> StringName:
	match weapon_id:
		"shortsword": return &"vm_shortsword_thrust"
		"greatsword": return &"vm_greatsword_attack"
		"axe": return &"vm_axe_attack"
		"warhammer": return &"vm_warhammer_attack"
		"spear": return &"vm_thrust_spear"
		"dagger": return &"vm_stab_dagger"
		"longbow": return &"vm_bow_release"
		"crossbow": return &"vm_crossbow_fire"
		"staff": return &"vm_staff_attack"
		"grimoire": return &"vm_grimoire_attack"
		"shield": return &"vm_bash_shield"
		"sword": return &"vm_sword_slash"
	return &"vm_slash_default"

func _fingerprint(animation: Animation) -> String:
	var values: Array[String] = []
	for track_index in animation.get_track_count():
		values.append(String(animation.track_get_path(track_index)))
		for key_index in animation.track_get_key_count(track_index):
			values.append(str(animation.track_get_key_value(track_index, key_index)))
	return "|".join(values)
