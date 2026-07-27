extends GdUnitTestSuite

const TAVERN_SCENE_PATH := "res://scenes/tavern/tavern.tscn"
const CROSSBOW_LAYER := 1 << 10


func test_tavern_crossbow_recovers_and_can_fire_again() -> void:
	var tavern_scene := load(TAVERN_SCENE_PATH) as PackedScene
	assert_object(tavern_scene).is_not_null()
	if tavern_scene == null:
		return
	var tavern := tavern_scene.instantiate()
	add_child(tavern)
	await _frames(12)

	var player := tavern.get_node_or_null("Player") as Player
	assert_object(player).is_not_null()
	if player == null:
		tavern.queue_free()
		return
	var registry := get_tree().root.get_node_or_null("WeaponRegistry")
	var crossbow: WeaponData = registry.get_weapon_data("crossbow") if registry != null else null
	assert_object(crossbow).is_not_null()
	if crossbow == null:
		tavern.queue_free()
		return

	player.equipment.configure_weapon_slot(0, crossbow, true)
	await _frames(8)
	player.switch_state(Player.State.SHOOTING, player.make_primary_weapon_attack_data())

	# Imported third-person crossbow_fire is about 0.333s. The state must finish
	# before the delayed first-person reload clip starts on the local ViewModel.
	await _seconds(0.8)
	assert_int(player.state).is_equal(Player.State.MOVING)

	await _seconds(1.5)
	assert_bool(player.is_crossbow_reloading()).is_false()
	player.switch_state(Player.State.SHOOTING, player.make_primary_weapon_attack_data())
	await _frames(2)
	assert_int(player.state).is_equal(Player.State.SHOOTING)

	if DisplayServer.get_name() != "headless":
		var view_model := player.view_model
		var weapon_subviewport: SubViewport = view_model.get("_weapon_subviewport")
		assert_object(weapon_subviewport).is_not_null()
		if weapon_subviewport != null:
			assert_bool(weapon_subviewport.world_3d == get_viewport().world_3d).is_true()
		var meshes: Array[Node] = player.equipment.weapon_placeholder.find_children("*", "MeshInstance3D", true, false)
		assert_bool(not meshes.is_empty()).is_true()
		if not meshes.is_empty():
			var mesh := meshes[0] as MeshInstance3D
			assert_int(mesh.layers).is_equal(CROSSBOW_LAYER)
			var material: Material = mesh.material_override
			if material == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
				material = mesh.get_surface_override_material(0)
			if material == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
				material = mesh.mesh.surface_get_material(0)
			assert_object(material).is_not_null()
			if material is StandardMaterial3D:
				assert_int((material as StandardMaterial3D).shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)

	tavern.queue_free()
	await _frames(2)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout
