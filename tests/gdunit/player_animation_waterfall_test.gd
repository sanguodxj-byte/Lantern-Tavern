extends GdUnitTestSuite

const PROFILE := preload("res://globals/visual/player_animation_profile.gd")
const COMBAT_SLASH := preload("res://globals/combat/combat_slash_animator.gd")
const PLAYER_VISUAL_SCENE := "res://scenes/characters/player/player_visual_model.tscn"

const FIXTURES := [
	{"id": "unarmed", "profile": &"unarmed", "hold": &"unarmed_hold", "defense": &"unarmed_guard", "attack": &"claw_swipe", "heavy": &""},
	{"id": "shortsword", "profile": &"shortsword", "hold": &"shortsword_hold", "defense": &"shortsword_guard", "attack": &"shortsword_attack", "heavy": &""},
	{"id": "sword", "profile": &"sword", "hold": &"sword_hold", "defense": &"sword_guard", "attack": &"sword_attack", "heavy": &""},
	{"id": "dagger", "profile": &"dagger", "hold": &"dagger_hold", "defense": &"dagger_guard", "attack": &"dagger_attack", "heavy": &""},
	{"id": "greatsword", "profile": &"greatsword", "hold": &"greatsword_hold", "defense": &"greatsword_guard", "attack": &"greatsword_attack", "heavy": &"greatsword_heavy_swing"},
	{"id": "axe", "profile": &"axe", "hold": &"axe_hold", "defense": &"axe_guard", "attack": &"axe_attack", "heavy": &"axe_heavy_swing"},
	{"id": "warhammer", "profile": &"warhammer", "hold": &"warhammer_hold", "defense": &"warhammer_guard", "attack": &"warhammer_attack", "heavy": &"warhammer_heavy_swing"},
	{"id": "spear", "profile": &"spear", "hold": &"spear_hold", "defense": &"spear_guard", "attack": &"spear_attack", "heavy": &"spear_heavy_swing"},
	{"id": "longbow", "profile": &"bow", "hold": &"bow_hold", "defense": &"bow_aim", "attack": &"bow_release", "heavy": &""},
	{"id": "crossbow", "profile": &"crossbow", "hold": &"crossbow_hold", "defense": &"crossbow_aim", "attack": &"crossbow_fire", "heavy": &""},
	{"id": "staff", "profile": &"staff", "hold": &"staff_hold", "defense": &"staff_guard", "attack": &"staff_attack", "heavy": &""},
	{"id": "grimoire", "profile": &"grimoire", "hold": &"grimoire_hold", "defense": &"grimoire_guard", "attack": &"grimoire_attack", "heavy": &""},
	{"id": "shield", "profile": &"shield", "hold": &"shield_hold", "defense": &"shield_block", "attack": &"bash_shield", "heavy": &""},
]


func test_every_style_has_distinct_hold_defense_and_attack_contract() -> void:
	var hold_names: Array[StringName] = []
	var defense_names: Array[StringName] = []
	var attack_names: Array[StringName] = []
	for fixture: Dictionary in FIXTURES:
		hold_names.append(fixture["hold"])
		attack_names.append(fixture["attack"])
		if fixture["defense"] != &"":
			defense_names.append(fixture["defense"])
	_assert_unique(hold_names)
	_assert_unique(attack_names)
	_assert_unique(defense_names)


func test_real_weapon_data_resolves_to_the_declared_style() -> void:
	var registry_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json")) as Dictionary
	for entry: Dictionary in registry_data["weapons"]:
		var weapon: WeaponData = _weapon_from_entry(entry)
		var expected: StringName = _expected_profile_for_id(String(entry["id"]))
		assert_str(String(PROFILE.profile_for_weapon(weapon))).is_equal(String(expected))


func test_player_rig_contains_all_style_actions_with_nonzero_tracks() -> void:
	var packed := load(PLAYER_VISUAL_SCENE) as PackedScene
	assert_object(packed).is_not_null()
	if packed == null:
		return
	var instance: Node3D = auto_free(packed.instantiate()) as Node3D
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(animation_player).is_not_null()
	if animation_player == null:
		return
	for fixture: Dictionary in FIXTURES:
		for key in ["hold", "defense", "attack"]:
			var animation_name: StringName = fixture[key]
			if animation_name == &"":
				continue
			assert_bool(animation_player.has_animation(animation_name)) \
				.override_failure_message("player rig missing %s for %s" % [animation_name, fixture["id"]]).is_true()
			if not animation_player.has_animation(animation_name):
				continue
			var animation: Animation = animation_player.get_animation(animation_name)
			assert_float(animation.length).is_greater(0.0)
			assert_int(animation.get_track_count()).is_greater(0)


func test_style_attacks_are_not_track_identical() -> void:
	var packed := load(PLAYER_VISUAL_SCENE) as PackedScene
	var instance: Node3D = auto_free(packed.instantiate()) as Node3D
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var fingerprints: Dictionary = {}
	for fixture: Dictionary in FIXTURES:
		var animation_name: StringName = fixture["attack"]
		if not animation_player.has_animation(animation_name):
			continue
		var fingerprint: String = _fingerprint(animation_player.get_animation(animation_name))
		assert_bool(fingerprints.has(fingerprint)) \
			.override_failure_message("attack animation reuses an identical track shape: %s" % animation_name).is_false()
		fingerprints[fingerprint] = animation_name


func test_two_hand_heavy_swing_actions_are_authored_and_distinct() -> void:
	var packed := load(PLAYER_VISUAL_SCENE) as PackedScene
	var instance: Node3D = auto_free(packed.instantiate()) as Node3D
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var heavy_names: Array[StringName] = []
	for fixture: Dictionary in FIXTURES:
		var heavy_name: StringName = fixture["heavy"]
		if heavy_name == &"":
			continue
		heavy_names.append(heavy_name)
		assert_bool(animation_player.has_animation(heavy_name)) \
			.override_failure_message("missing heavy swing action: %s" % heavy_name).is_true()
		if not animation_player.has_animation(heavy_name):
			continue
		var heavy := animation_player.get_animation(heavy_name)
		assert_float(heavy.length).is_greater(0.0)
		assert_int(heavy.get_track_count()).is_greater(0)
		assert_bool(_fingerprint(heavy) != _fingerprint(animation_player.get_animation(fixture["attack"]))) \
			.override_failure_message("heavy swing reuses normal attack: %s" % heavy_name).is_true()
	_assert_unique(heavy_names)


func test_heavy_swing_profile_resolution_is_limited_to_melee_two_hand_styles() -> void:
	var greatsword := WeaponData.new()
	greatsword.weapon_class = "two_hand"
	greatsword.skill_school = "two_hand_sword"
	var axe := WeaponData.new()
	axe.weapon_class = "two_hand"
	axe.skill_school = "two_hand_axe"
	var warhammer := WeaponData.new()
	warhammer.weapon_class = "two_hand"
	warhammer.skill_school = "war_hammer"
	var spear := WeaponData.new()
	spear.weapon_class = "two_hand"
	spear.skill_school = "spear"
	var bow := WeaponData.new()
	bow.weapon_class = "longbow"
	bow.skill_school = "longbow"
	assert_str(String(PROFILE.attack_animation(greatsword, true))).is_equal("greatsword_heavy_swing")
	assert_str(String(PROFILE.attack_animation(axe, true))).is_equal("axe_heavy_swing")
	assert_str(String(PROFILE.attack_animation(warhammer, true))).is_equal("warhammer_heavy_swing")
	assert_str(String(PROFILE.attack_animation(spear, true))).is_equal("spear_heavy_swing")
	assert_str(String(PROFILE.attack_animation(bow, true))).is_equal("bow_release")
	assert_str(String(COMBAT_SLASH.player_animation_name(greatsword, true))).is_equal("greatsword_heavy_swing")


func test_heavy_swing_actions_can_finish_and_repeat() -> void:
	var packed := load(PLAYER_VISUAL_SCENE) as PackedScene
	var instance: Node3D = auto_free(packed.instantiate()) as Node3D
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for fixture: Dictionary in FIXTURES:
		var animation_name: StringName = fixture["heavy"]
		if animation_name == &"":
			continue
		for _repeat_index in 2:
			var finished := [false]
			var on_finished := func(completed: StringName) -> void:
				if String(completed) == String(animation_name):
					finished[0] = true
			animation_player.animation_finished.connect(on_finished)
			animation_player.play(animation_name)
			animation_player.advance(animation_player.get_animation(animation_name).length + 0.12)
			if animation_player.animation_finished.is_connected(on_finished):
				animation_player.animation_finished.disconnect(on_finished)
			assert_bool(finished[0]).override_failure_message(
				"%s did not finish" % animation_name
			).is_true()


func test_style_holds_and_defenses_are_not_track_identical() -> void:
	var packed := load(PLAYER_VISUAL_SCENE) as PackedScene
	var instance: Node3D = auto_free(packed.instantiate()) as Node3D
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var fingerprints_by_phase := {"hold": {}, "defense": {}}
	for fixture: Dictionary in FIXTURES:
		for phase in ["hold", "defense"]:
			var animation_name: StringName = fixture[phase]
			if animation_name == &"" or not animation_player.has_animation(animation_name):
				continue
			var animation := animation_player.get_animation(animation_name)
			assert_float(animation.length).is_greater(0.0)
			assert_int(animation.get_track_count()).is_greater(0)
			var fingerprint := _fingerprint(animation)
			var fingerprints: Dictionary = fingerprints_by_phase[phase]
			assert_bool(fingerprints.has(fingerprint)) \
				.override_failure_message("%s animation reuses an identical track shape: %s" % [phase, animation_name]).is_false()
			fingerprints[fingerprint] = animation_name


func test_each_style_has_distinct_sampled_hold_defense_and_attack_poses() -> void:
	var packed := load(PLAYER_VISUAL_SCENE) as PackedScene
	var instance: Node3D = auto_free(packed.instantiate()) as Node3D
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for fixture: Dictionary in FIXTURES:
		var sampled: Dictionary = {}
		for phase in ["hold", "defense", "attack"]:
			var animation_name: StringName = fixture[phase]
			assert_bool(animation_player.has_animation(animation_name)) \
				.override_failure_message("%s missing %s clip" % [fixture["id"], animation_name]).is_true()
			if not animation_player.has_animation(animation_name):
				continue
			var animation := animation_player.get_animation(animation_name)
			animation_player.play(animation_name)
			animation_player.seek(animation.length * 0.5, true)
			sampled[phase] = _sample_bone_pose(instance)
		assert_bool(sampled.has("hold")).is_true()
		assert_bool(sampled.has("defense")).is_true()
		assert_bool(sampled.has("attack")).is_true()
		assert_bool(sampled["hold"] != sampled["defense"]) \
			.override_failure_message("%s hold and defense collapse to one pose" % fixture["id"]).is_true()
		assert_bool(sampled["defense"] != sampled["attack"]) \
			.override_failure_message("%s defense and attack collapse to one pose" % fixture["id"]).is_true()


func test_every_style_release_can_finish_then_restore_its_hold_pose() -> void:
	var packed := load(PLAYER_VISUAL_SCENE) as PackedScene
	var instance: Node3D = auto_free(packed.instantiate()) as Node3D
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for fixture: Dictionary in FIXTURES:
		var attack_name: StringName = fixture["attack"]
		var hold_name: StringName = fixture["hold"]
		animation_player.play(attack_name)
		var attack := animation_player.get_animation(attack_name)
		animation_player.advance(attack.length + 0.05)
		assert_bool(animation_player.current_animation == String(attack_name) or animation_player.current_animation == "") \
			.override_failure_message("%s attack did not reach its terminal state" % fixture["id"]).is_true()
		animation_player.play(hold_name)
		assert_str(String(animation_player.current_animation)).is_equal(String(hold_name))


func _sample_bone_pose(instance: Node3D) -> String:
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	var values: Array[String] = []
	for bone_name in ["UpperArm.R", "LowerArm.R", "Hand.R", "UpperArm.L", "LowerArm.L", "Hand.L", "Torso"]:
		var bone_index := skeleton.find_bone(bone_name)
		values.append("%s:%s" % [bone_name, str(skeleton.get_bone_pose(bone_index))])
	return "|".join(values)


func test_state_entries_use_canonical_hold_and_defense_visual_apis() -> void:
	var preparing_source := FileAccess.get_file_as_string(
		"res://scenes/characters/player/state/player_state_attack_preparing.gd"
	)
	var blocking_source := FileAccess.get_file_as_string(
		"res://scenes/characters/player/state/player_state_blocking.gd"
	)
	var aiming_source := FileAccess.get_file_as_string(
		"res://scenes/characters/player/state/player_state_aiming.gd"
	)
	assert_str(preparing_source).contains("begin_weapon_hold")
	assert_str(preparing_source).contains("PLAYER_ANIMATION_PROFILE.hold_animation")
	assert_str(blocking_source).contains("begin_weapon_defense")
	assert_str(blocking_source).contains("PLAYER_ANIMATION_PROFILE.defense_animation")
	assert_str(aiming_source).contains("begin_weapon_defense")
	assert_str(aiming_source).contains("PLAYER_ANIMATION_PROFILE.defense_animation")


func test_moving_state_keeps_every_style_hold_pose() -> void:
	var player := Player.new()
	var equipment := EquipmentComponent.new()
	player.add_child(equipment)
	player.equipment = equipment

	var animation_player := AnimationPlayer.new()
	animation_player.root_node = NodePath(".")
	var library := AnimationLibrary.new()
	var hold_names: Array[StringName] = [&"idle", &"run"]
	for fixture: Dictionary in FIXTURES:
		hold_names.append(fixture["hold"])
	for animation_name in hold_names:
		var animation := Animation.new()
		animation.length = 1.0
		var track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, NodePath(".:position"))
		animation.track_insert_key(track, 0.0, Vector3.ZERO)
		animation.track_insert_key(track, 1.0, Vector3.ZERO)
		library.add_animation(animation_name, animation)
	animation_player.add_animation_library(&"", library)
	player.add_child(animation_player)
	player.animation_player = animation_player

	var moving_state := PlayerStateMoving.new(player)
	var registry_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json")) as Dictionary
	var entries_by_id: Dictionary = {}
	for entry: Dictionary in registry_data["weapons"]:
		entries_by_id[String(entry["id"])] = entry
	for fixture: Dictionary in FIXTURES:
		var weapon: WeaponData = null
		var fixture_id := String(fixture["id"])
		if fixture_id != "unarmed":
			weapon = _weapon_from_entry(entries_by_id[fixture_id])
		equipment.configure_weapon_slot(0, weapon, true)
		moving_state._play_animation("idle")
		assert_str(String(animation_player.current_animation)).is_equal(String(fixture["hold"]))
	moving_state.free()
	player.free()


func test_persistent_hold_and_defense_states_restore_on_cancel_or_exit() -> void:
	var view_model_source := FileAccess.get_file_as_string("res://scenes/characters/player/view_model.gd")
	var blocking_source := FileAccess.get_file_as_string(
		"res://scenes/characters/player/state/player_state_blocking.gd"
	)
	assert_str(view_model_source).contains("func finish_weapon_defense")
	assert_str(view_model_source).contains("func cancel_weapon_hold")
	assert_str(blocking_source).contains("finish_weapon_defense")
	assert_str(blocking_source).contains("play(\"idle\")")


func test_each_one_shot_attack_emits_finished_and_can_repeat_three_times() -> void:
	var packed := load(PLAYER_VISUAL_SCENE) as PackedScene
	var instance: Node3D = packed.instantiate() as Node3D
	add_child(instance)
	auto_free(instance)
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for fixture: Dictionary in FIXTURES:
		var animation_name: StringName = fixture["attack"]
		if not animation_player.has_animation(animation_name):
			continue
		for repeat_index in 3:
			var finished := [false]
			var on_finished := func(completed: StringName) -> void:
				if String(completed) == String(animation_name):
					finished[0] = true
			animation_player.animation_finished.connect(on_finished)
			animation_player.play(animation_name)
			# Imported GLB players are validated deterministically with advance().
			# Waiting on a SceneTree timer alone does not guarantee that an
			# AnimationPlayer embedded in a PackedScene receives a process tick.
			animation_player.advance(animation_player.get_animation(animation_name).length + 0.12)
			if animation_player.animation_finished.is_connected(on_finished):
				animation_player.animation_finished.disconnect(on_finished)
			assert_bool(finished[0]) \
				.override_failure_message("%s did not finish on repetition %d" % [animation_name, repeat_index + 1]).is_true()


func test_first_person_release_sampling_does_not_pause_third_person_animation() -> void:
	var view_model := auto_free((load("res://scenes/characters/player/view_model.tscn") as PackedScene).instantiate()) as ViewModel
	add_child(view_model)
	var animation_player := AnimationPlayer.new()
	animation_player.root_node = NodePath(".")
	var target := Node3D.new()
	target.name = "Target"
	animation_player.add_child(target)
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("Target:position"))
	animation.track_insert_key(track, 0.0, Vector3.ZERO)
	animation.track_insert_key(track, 1.0, Vector3.ONE)
	library.add_animation(&"sword_attack", animation)
	animation_player.add_animation_library(&"", library)
	add_child(animation_player)
	animation_player.play(&"sword_attack")
	view_model.play_action(&"vm_sword_slash")
	view_model.sample_action(&"vm_sword_slash", 0.3)
	assert_bool(view_model.animation_player.has_animation(&"vm_sword_slash")).is_true()
	assert_float(view_model.animation_player.current_animation_position).is_equal_approx(view_model.animation_player.get_animation(&"vm_sword_slash").length * 0.3, 0.001)
	assert_bool(animation_player.is_playing()).is_true()
	assert_str(String(animation_player.current_animation)).is_equal("sword_attack")


func test_first_person_hold_and_defense_visual_apis_enter_and_exit_cleanly() -> void:
	var view_model := auto_free((load("res://scenes/characters/player/view_model.tscn") as PackedScene).instantiate()) as ViewModel
	add_child(view_model)
	var sword := WeaponData.new()
	sword.id = "sword"
	sword.item_tag = "weapon"
	sword.weapon_class = "one_hand_melee"
	sword.skill_school = "one_hand_sword"
	view_model.set_weapon(sword)
	assert_bool(view_model.begin_weapon_hold()).is_true()
	assert_bool(view_model.animation_player.has_animation(&"vm_sword_hold")).is_true()
	assert_float(view_model.animation_player.current_animation_position).is_equal_approx(0.0, 0.001)
	view_model.cancel_weapon_hold()
	assert_bool(view_model.begin_weapon_defense(&"vm_sword_guard")).is_true()
	assert_bool(view_model.animation_player.current_animation == &"vm_sword_guard").is_true()
	view_model.finish_weapon_defense(&"sword_guard")
	assert_bool(view_model.animation_player.current_animation.is_empty()).is_true()


func test_first_person_defense_api_translates_canonical_third_person_action() -> void:
	var view_model := auto_free((load("res://scenes/characters/player/view_model.tscn") as PackedScene).instantiate()) as ViewModel
	add_child(view_model)
	var sword := WeaponData.new()
	sword.id = "sword"
	sword.item_tag = "weapon"
	sword.weapon_class = "one_hand_melee"
	sword.skill_school = "one_hand_sword"
	view_model.set_weapon(sword)

	assert_bool(view_model.begin_weapon_defense(&"sword_guard")).is_true()
	assert_bool(view_model.animation_player.current_animation == &"vm_sword_guard").is_true()
	view_model.finish_weapon_defense(&"sword_guard")


func test_unarmed_primary_attack_has_a_prepare_and_release_state() -> void:
	var player := Player.new()
	var equipment := EquipmentComponent.new()
	player.add_child(equipment)
	player.equipment = equipment
	player.combat_input_enabled = true
	assert_int(player.get_primary_weapon_action_state()).is_equal(Player.State.ATTACK_PREPARING)
	assert_int(player.get_primary_weapon_release_state()).is_equal(Player.State.SLASHING)
	player.free()


func _weapon_from_entry(entry: Dictionary) -> WeaponData:
	var weapon := WeaponData.new()
	weapon.id = String(entry.get("id", ""))
	weapon.item_tag = String(entry.get("item_tag", "weapon"))
	weapon.weapon_class = String(entry.get("weapon_class", ""))
	weapon.attack_type = String(entry.get("attack_type", "melee"))
	weapon.skill_school = String(entry.get("skill_school", ""))
	weapon.view_model_profile = String(entry.get("view_model_profile", ""))
	weapon.tags.assign(entry.get("tags", []))
	return weapon


func _expected_profile_for_id(weapon_id: String) -> StringName:
	for fixture: Dictionary in FIXTURES:
		if fixture["id"] == weapon_id:
			return fixture["profile"]
	if weapon_id == "shield":
		return &"shield"
	return &"sword"


func _fingerprint(animation: Animation) -> String:
	var values: Array[String] = []
	for track_index in animation.get_track_count():
		values.append(String(animation.track_get_path(track_index)))
		values.append(str(animation.track_get_key_count(track_index)))
		for key_index in animation.track_get_key_count(track_index):
			values.append(str(animation.track_get_key_value(track_index, key_index)))
	return "|".join(values)


func _assert_unique(values: Array[StringName]) -> void:
	var seen: Dictionary = {}
	for value: StringName in values:
		assert_bool(seen.has(value)) \
			.override_failure_message("duplicate animation mapping: %s" % value).is_false()
		seen[value] = true
