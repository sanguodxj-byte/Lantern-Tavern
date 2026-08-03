extends GdUnitTestSuite
const Caster := preload("res://scenes/characters/player/player_spell_caster.gd")

class FakeFocus:
	extends Node3D
	var focus := true
	func is_active_spell_focus_weapon() -> bool: return focus

func test_partial_charge_never_enters_cast_boundary() -> void:
	var caster := Caster.new()
	var player := FakeFocus.new(); add_child(player)
	var result := caster.release_full_charge(player,0.999)
	assert_bool(bool(result.get("ok",false))).is_false()
	assert_str(String(result.reason)).is_equal("spell_not_fully_charged")
	player.queue_free()

func test_non_focus_weapon_rejected_even_at_full_charge() -> void:
	var caster := Caster.new()
	var player := FakeFocus.new(); player.focus = false; add_child(player)
	var result := caster.release_full_charge(player,1.0)
	assert_str(String(result.reason)).is_equal("invalid_spell_focus")
	player.queue_free()

func test_spell_ui_prevents_player_mouse_recapture() -> void:
	var player_source := (load("res://scenes/characters/player/player.gd") as GDScript).source_code
	var section := player_source.substr(player_source.find("func _input"), 1500)
	assert_bool(section.contains("combat_hud")).is_true()
	assert_bool(section.contains("is_spell_interface_visible")).is_true()
	assert_bool(section.contains("not spell_ui_visible")).is_true()
	var hud_source := (load("res://scenes/ui/combat_hud.gd") as GDScript).source_code
	assert_bool(hud_source.contains("add_to_group(\"combat_hud\")")).is_true()

func test_full_charge_flow_uses_selected_slot_and_world() -> void:
	var caster_source := (load("res://scenes/characters/player/player_spell_caster.gd") as GDScript).source_code
	var section := caster_source.substr(caster_source.find("func release_full_charge"), 650)
	assert_bool(section.contains("charge_ratio < 1.0")).is_true()
	assert_bool(section.contains("cast_selected(player, world)")).is_true()
	var state_source := (load("res://scenes/characters/player/state/player_state_attack_preparing.gd") as GDScript).source_code
	assert_bool(state_source.contains("player.spell_caster.release_full_charge")).is_true()
	assert_bool(state_source.contains("transition_state(Player.State.MOVING)")).is_true()
