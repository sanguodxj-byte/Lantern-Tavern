extends GdUnitTestSuite

## 敌人攻击分类回归测试：人形使用装备武器，非人形使用身体攻击。

const HUMANOID_SCENES := [
	"goblin", "orc_raider", "skeleton", "troll", "minotaur", "drow_blade",
]
const BODY_SCENES := ["slime", "spider", "dragon", "rock_golem"]

func test_humanoid_enemy_prefabs_use_weapon_attack_mode() -> void:
	for enemy_id in HUMANOID_SCENES:
		var source := FileAccess.get_file_as_string("res://scenes/characters/enemies/%s.tscn" % enemy_id)
		assert_bool(source.contains('attack_mode = "body"')) \
			.override_failure_message("%s 不能被标记为 body 攻击模式" % enemy_id) \
			.is_false()
	assert_str(_roster_attack_mode("goblin")).is_equal("weapon")
	assert_str(_roster_attack_mode("orc_raider")).is_equal("weapon")
	assert_str(_roster_attack_mode("skeleton")).is_equal("weapon")
	assert_str(_roster_attack_mode("troll")).is_equal("weapon")
	assert_str(_roster_attack_mode("minotaur")).is_equal("weapon")
	assert_str(_roster_attack_mode("drow_blade")).is_equal("weapon")

func test_non_humanoid_enemy_prefabs_use_body_attack_mode_and_no_weapon_data() -> void:
	for enemy_id in BODY_SCENES:
		var source := FileAccess.get_file_as_string("res://scenes/characters/enemies/%s.tscn" % enemy_id)
		assert_bool(source.contains('attack_mode = "body"')) \
			.override_failure_message("%s 必须使用 body 攻击模式" % enemy_id) \
			.is_true()
		assert_bool(source.contains("weapon_data = null")) \
			.override_failure_message("%s 的非人形攻击不能依赖 WeaponData" % enemy_id) \
			.is_true()
	assert_str(_roster_attack_mode("slime")).is_equal("body")
	assert_str(_roster_attack_mode("spider")).is_equal("body")
	assert_str(_roster_attack_mode("dragon")).is_equal("body")
	assert_str(_roster_attack_mode("rock_golem")).is_equal("body")

func test_body_attack_reach_uses_body_range_without_weapon_ray() -> void:
	var enemy := _load_enemy("slime")
	var player := _load_player()
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(enemy)
	add_child(player)
	await get_tree().process_frame
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.0, -1.0)
	enemy.player = player
	enemy._targeting.mark_engaged_target(player)

	assert_bool(enemy.uses_weapon_attack()).is_false()
	assert_bool(enemy.is_player_within_reach()) \
		.override_failure_message("非人形敌人在身体攻击范围内应能进入攻击状态").is_true()
	player.global_position = Vector3(0.0, 0.0, -2.0)
	assert_bool(enemy.is_player_within_reach()) \
		.override_failure_message("身体攻击范围外不能提前停止追击").is_false()

	player.queue_free()
	enemy.queue_free()

func test_body_attack_hitbox_uses_body_attack_reach() -> void:
	var enemy := _load_enemy("slime")
	add_child(enemy)
	await get_tree().process_frame
	var hitbox := enemy.prepare_attack_hitbox(PhysicsSetup.LAYER_PLAYER)
	var collision := hitbox.get_node("CollisionShape3D") as CollisionShape3D
	var shape := collision.shape as BoxShape3D
	assert_object(shape).is_not_null()
	if shape != null:
		assert_float(shape.size.z).is_equal_approx(enemy.body_attack_reach, 0.001)
	enemy.queue_free()

func test_weapon_attack_still_exposes_weapon_to_damage_resolution() -> void:
	var enemy := _load_enemy("goblin")
	add_child(enemy)
	await get_tree().process_frame
	assert_bool(enemy.uses_weapon_attack()).is_true()
	assert_object(enemy.get_attack_weapon()).is_not_null()
	enemy.queue_free()

func test_spawner_provides_explicit_attack_mode_for_runtime_types() -> void:
	var spawner: Node = (load("res://globals/dungeon/dungeon_spawner.gd") as GDScript).new()
	assert_str(spawner.get_attack_mode("goblin")).is_equal("weapon")
	assert_str(spawner.get_attack_mode("slime")).is_equal("body")
	assert_str(spawner.get_attack_mode("dragon")).is_equal("body")
	assert_str(spawner.get_attack_mode("elite_rock_golem")).is_equal("body")
	spawner.free()

func test_slashing_state_uses_attack_mode_weapon_selector() -> void:
	var source := (load("res://scenes/characters/enemies/state/enemy_state_slashing.gd") as GDScript).source_code
	assert_bool(source.contains("enemy.get_attack_weapon()")).is_true()

func _load_enemy(enemy_id: String) -> Enemy:
	var scene := load("res://scenes/characters/enemies/%s.tscn" % enemy_id) as PackedScene
	return scene.instantiate() as Enemy

func _load_player() -> Player:
	var scene := load("res://scenes/characters/player/player.tscn") as PackedScene
	return scene.instantiate() as Player

func _roster_attack_mode(enemy_id: String) -> String:
	var file := FileAccess.open("res://data/enemy_roster.json", FileAccess.READ)
	var json := JSON.new()
	assert_int(json.parse(file.get_as_text())).is_equal(OK)
	file.close()
	for entry in json.data.get("enemies", []):
		if String(entry.get("id", "")) == enemy_id:
			return String(entry.get("attack_mode", ""))
	return ""
