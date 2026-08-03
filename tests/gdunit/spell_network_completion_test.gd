extends GdUnitTestSuite
const NP := preload("res://globals/multiplayer/network_protocol.gd")

func test_protocol_validates_spell_command_and_event() -> void:
	assert_bool(NP.is_valid_command(NP.CMD_CAST_SPELL)).is_true()
	assert_bool(NP.is_valid_event(NP.EVT_SPELL_RESOLVED)).is_true()

func test_session_spell_handler_uses_per_peer_state_cooldown_and_authority() -> void:
	var source := (load("res://globals/multiplayer/session_root.gd") as GDScript).source_code
	var section := source.substr(source.find("func _handle_cast_spell"), 6000)
	assert_bool(section.contains("ctx.spell_loadout")).is_true()
	assert_bool(section.contains("commit_authoritative_cooldown")).is_true()
	assert_bool(section.contains("spell_auth.execute")).is_true()
	assert_bool(section.contains("mana_remaining")).is_true()
	assert_bool(not section.contains("GameState")).is_true()

func test_reconnect_snapshot_contains_spell_state() -> void:
	var source := (load("res://globals/multiplayer/session_root.gd") as GDScript).source_code
	var build := source.substr(source.find("func build_session_snapshot"), 1600)
	assert_bool(build.contains("serialize_spell_state")).is_true()
	var apply := source.substr(source.find("func apply_session_snapshot"), 1400)
	assert_bool(apply.contains("deserialize_spell_state")).is_true()

func test_scene_bridge_consumes_spell_event_as_visual_only() -> void:
	var source := (load("res://globals/multiplayer/multiplayer_scene_bridge.gd") as GDScript).source_code
	var section := source.substr(source.find("NP.EVT_SPELL_RESOLVED"), 1200)
	assert_bool(section.contains("PixelSpellFxScript.spawn")).is_true()
	assert_bool(section.contains("mana_remaining")).is_true()
	assert_bool(not section.contains("try_receive_hit")).is_true()
