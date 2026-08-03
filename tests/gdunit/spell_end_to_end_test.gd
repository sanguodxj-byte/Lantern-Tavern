extends GdUnitTestSuite
const Caster := preload("res://scenes/characters/player/player_spell_caster.gd")
const Authority := preload("res://globals/combat/spell_authority.gd")
const Health := preload("res://scenes/characters/component/health_component.gd")
const Buffs := preload("res://scenes/characters/component/combat_buff_component.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

class FakePlayer:
	extends Node3D
	var health: HealthComponent
	var buffs := Buffs.new()
	func _init():
		health = Health.new(); add_child(health)

func test_spell_authority_executes_heal_barrier_and_movement() -> void:
	var player := FakePlayer.new(); add_child(player); var auth := Authority.new()
	player.health.max_life = 100; player.health.current_life = 20
	var heal := auth.execute(player,{"ok":true,"spell_id":"h","effect_plan":{"type":"heal","heal":28},"visual_event":{}})
	assert_bool(bool(heal.ok)).is_true(); assert_int(player.health.current_life).is_equal(48)
	var barrier := auth.execute(player,{"ok":true,"spell_id":"b","effect_plan":{"type":"barrier","absorb":30,"duration":5.0},"visual_event":{}})
	assert_bool(bool(barrier.ok)).is_true(); assert_bool(player.buffs.has("damage_absorb")).is_true()
	var move := auth.execute(player,{"ok":true,"spell_id":"m","direction":Vector3.RIGHT,"effect_plan":{"type":"movement","distance":5.0},"visual_event":{}})
	assert_bool(bool(move.ok)).is_true(); assert_float(player.global_position.x).is_equal_approx(5.0,0.01)
	player.queue_free()

func test_world_effects_produce_structured_requests_not_fake_damage() -> void:
	var player := FakePlayer.new(); add_child(player); var auth := Authority.new()
	# projectile 用已注册 id + 权威伤害（P1-2：执行器必读 plan.damage，缺则失败）。
	var plans := {
		"projectile": {"type": "projectile", "projectile_id": "elemental_bolt", "damage": 10},
		"ray": {"type": "ray"},
		"area": {"type": "area"},
		"ground": {"type": "ground"},
		"summon": {"type": "summon"},
	}
	for kind in plans.keys():
		var result := auth.execute(player, {"ok": true, "spell_id": "x", "origin": Vector3.ZERO,
			"direction": Vector3.FORWARD, "effect_plan": plans[kind], "visual_event": {}})
		assert_str(String(result.get("world_request", {}).get("type", ""))).is_equal(kind)
		assert_bool(not result.has("damage_applied")).is_true()
	player.queue_free()

func test_network_protocol_has_slot_only_spell_command() -> void:
	assert_str(NP.CMD_CAST_SPELL).is_equal("request_cast_spell")
	assert_str(NP.EVT_SPELL_RESOLVED).is_equal("spell_resolved")
	var source := (load("res://scenes/multiplayer/client_command_driver.gd") as GDScript).source_code
	var section := source.substr(source.find("func send_cast_spell"), 900)
	assert_bool(section.contains("slot_index")).is_true()
	assert_bool(not section.contains("spell_id")).is_true()

func test_player_has_spell_input_and_caster_boundary() -> void:
	var source := (load("res://scenes/characters/player/player.gd") as GDScript).source_code
	assert_bool(source.contains("PLAYER_SPELL_CASTER")).is_true()
	assert_bool(source.contains("cast_spell")).is_true()
	assert_bool(source.contains("spell_slot_5")).is_true()
