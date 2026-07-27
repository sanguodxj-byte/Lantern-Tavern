extends GdUnitTestSuite



## Complete armor sets: leather (light) + iron (heavy), four slots each.

## Body pieces already existed; head/hands/feet are new wearable set pieces.



const SETS := [

	{

		"set_id": "leather_set",

		"pieces": {

			"head": "leather_helmet",

			"body": "leather_armor",

			"hands": "leather_bracers",

			"feet": "leather_boots",

		},

		"category": "armor_light",

		"armor_type": "light",

	},

	{

		"set_id": "iron_set",

		"pieces": {

			"head": "iron_helmet",

			"body": "chain_armor",

			"hands": "iron_bracers",

			"feet": "iron_boots",

		},

		"category": "armor_heavy",

		"armor_type": "heavy",

	},

]





func test_armor_set_json_entries_are_complete_and_slotted() -> void:

	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))

	assert_that(parsed).is_not_null()

	var by_id := {}

	for entry in parsed.get("armor", []):

		by_id[String(entry.get("id", ""))] = entry

	for armor_set in SETS:

		var set_id := String(armor_set["set_id"])

		var pieces: Dictionary = armor_set["pieces"]

		for slot_name in pieces.keys():

			var piece_id := String(pieces[slot_name])

			assert_bool(by_id.has(piece_id)).override_failure_message("missing armor id %s" % piece_id).is_true()

			var entry: Dictionary = by_id[piece_id]

			assert_str(String(entry.get("armor_slot", ""))).is_equal(String(slot_name))

			assert_str(String(entry.get("set_id", ""))).is_equal(set_id)

			assert_str(String(entry.get("category", ""))).is_equal(String(armor_set["category"]))

			assert_str(String(entry.get("armor_type", ""))).is_equal(String(armor_set["armor_type"]))

			var glb_path := String(entry.get("glb_path", ""))

			assert_str(glb_path).is_not_empty()

			assert_bool(FileAccess.file_exists(glb_path)).override_failure_message("missing glb %s" % glb_path).is_true()





func test_armor_set_generators_are_single_identity() -> void:

	var generator_ids := [

		"leather_helmet", "leather_bracers", "leather_boots",

		"iron_helmet", "iron_bracers", "iron_boots",

	]

	for model_id in generator_ids:

		var gen_path := "res://tools/generate_voxel_%s.py" % model_id

		assert_bool(FileAccess.file_exists(gen_path)).is_true()

		var source := FileAccess.get_file_as_string(gen_path)

		assert_str(source).contains('MODEL_ID = "%s"' % model_id)

		assert_str(source).contains("reject_target_override(MODEL_ID)")

		assert_str(source).contains("assert_parts_no_positive_volume_overlap")

		assert_bool(source.contains("BUILDERS")).is_false()

		assert_bool(source.contains("--batch")).is_false()

		assert_bool(source.contains("for model_id in")).is_false()





func test_weapon_registry_loads_set_pieces_into_armor_slots() -> void:

	for armor_set in SETS:

		var pieces: Dictionary = armor_set["pieces"]

		for slot_name in pieces.keys():

			var piece_id := String(pieces[slot_name])

			var data: WeaponData = WeaponRegistry.get_weapon_data(piece_id)

			assert_object(data).is_not_null()

			assert_str(data.armor_slot).is_equal(String(slot_name))

			assert_str(data.equipment_category).is_equal(String(armor_set["category"]))

			assert_str(data.armor_type).is_equal(String(armor_set["armor_type"]))

			assert_int(data.armor_phys_def).is_greater(0)

			assert_object(data.glb_mesh).is_not_null()





func test_equipment_component_equips_full_leather_set_and_mounts_meshes() -> void:

	var player_scene: PackedScene = load("res://scenes/characters/player/player.tscn")

	var player: Node = player_scene.instantiate()

	add_child(player)

	await get_tree().process_frame

	var eq: EquipmentComponent = player.get_node("EquipmentComponent") as EquipmentComponent

	assert_object(eq).is_not_null()

	assert_object(eq.armor_head_placeholder).is_not_null()

	assert_object(eq.armor_body_placeholder).is_not_null()

	assert_object(eq.armor_hand_l_placeholder).is_not_null()

	assert_object(eq.armor_hand_r_placeholder).is_not_null()

	assert_object(eq.armor_foot_l_placeholder).is_not_null()

	assert_object(eq.armor_foot_r_placeholder).is_not_null()



	var count := eq.equip_armor_set("leather_set")

	assert_int(count).is_equal(4)

	assert_str(eq.get_armor_slot_data("head").id).is_equal("leather_helmet")

	assert_str(eq.get_armor_slot_data("body").id).is_equal("leather_armor")

	assert_str(eq.get_armor_slot_data("hands").id).is_equal("leather_bracers")

	assert_str(eq.get_armor_slot_data("feet").id).is_equal("leather_boots")

	assert_int(eq.get_armor_defense()).is_greater_equal(6)



	await get_tree().process_frame

	assert_int(eq.armor_head_placeholder.get_child_count()).is_greater_equal(1)

	assert_int(eq.armor_body_placeholder.get_child_count()).is_greater_equal(1)

	assert_int(eq.armor_hand_l_placeholder.get_child_count()).is_greater_equal(1)

	assert_int(eq.armor_hand_r_placeholder.get_child_count()).is_greater_equal(1)

	assert_int(eq.armor_foot_l_placeholder.get_child_count()).is_greater_equal(1)

	assert_int(eq.armor_foot_r_placeholder.get_child_count()).is_greater_equal(1)

	player.queue_free()





func test_equipment_component_equips_full_iron_set() -> void:

	var eq := EquipmentComponent.new()

	add_child(eq)

	var count := eq.equip_armor_set("iron_set")

	assert_int(count).is_equal(4)

	assert_str(eq.get_armor_slot_data("head").id).is_equal("iron_helmet")

	assert_str(eq.get_armor_slot_data("body").id).is_equal("chain_armor")

	assert_str(eq.get_armor_slot_data("hands").id).is_equal("iron_bracers")

	assert_str(eq.get_armor_slot_data("feet").id).is_equal("iron_boots")

	assert_str(eq.get_armor_slot_data("head").armor_type).is_equal("heavy")

	eq.queue_free()

func test_armor_mount_profile_is_noticeably_oversized_and_oriented() -> void:
	var ArmorMount := preload("res://globals/visual/armor_mount_profile.gd")
	assert_float(ArmorMount.min_oversized_scale()).is_greater_equal(1.1)
	assert_float(ArmorMount.HEAD_SCALE).is_greater_equal(ArmorMount.min_oversized_scale())
	assert_float(ArmorMount.BODY_SCALE).is_greater_equal(ArmorMount.min_oversized_scale())
	assert_float(ArmorMount.HANDS_SCALE).is_greater_equal(ArmorMount.min_oversized_scale())
	assert_float(ArmorMount.FEET_SCALE).is_greater_equal(ArmorMount.min_oversized_scale())
	# Mesh bulk carries "大一截"; mount scale must stay modest.
	assert_float(ArmorMount.HEAD_SCALE).is_less(1.35)
	assert_float(ArmorMount.BODY_SCALE).is_less(1.35)
	assert_float(ArmorMount.FEET_SCALE).is_less(1.35)

	var head := ArmorMount.local_transform("head")
	var body := ArmorMount.local_transform("body")
	var hand_l := ArmorMount.local_transform("hands", "L")
	var hand_r := ArmorMount.local_transform("hands", "R")
	var foot_l := ArmorMount.local_transform("feet", "L")
	var foot_r := ArmorMount.local_transform("feet", "R")

	# Head/body: Y180 so authored front matches character face (world -Z).
	assert_float(abs(abs(head.basis.get_euler().y) - PI)).is_less(0.2)
	assert_float(abs(abs(body.basis.get_euler().y) - PI)).is_less(0.2)
	assert_float(body.origin.y).is_greater(0.08)
	var fl_e := foot_l.basis.get_euler()
	var fr_e := foot_r.basis.get_euler()
	assert_float(abs(fl_e.y - fr_e.y)).is_greater(0.5)
	assert_float(hand_l.basis.x.x * hand_r.basis.x.x).is_less(0.0)
