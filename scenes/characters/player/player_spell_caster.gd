class_name PlayerSpellCaster
extends RefCounted

const SpellRuntimeScript := preload("res://globals/combat/spell_runtime.gd")
const SpellAuthorityScript := preload("res://globals/combat/spell_authority.gd")
const Service := preload("res://globals/core/service.gd")

var selected_slot := 0
var runtime := SpellRuntimeScript.new()
var authority := SpellAuthorityScript.new()

func select_slot(slot_index: int) -> void:
	selected_slot = clampi(slot_index, 0, 4)

func cast_selected(player: Node3D, world: Node = null) -> Dictionary:
	if player == null:
		return {"ok":false,"reason":"missing_player"}
	if not player.has_method("is_active_spell_focus_weapon") or not player.is_active_spell_focus_weapon():
		return {"ok":false,"reason":"invalid_spell_focus"}
	var gs := Service.game_state()
	if gs == null or not ("spell_loadout" in gs):
		return {"ok":false,"reason":"missing_loadout"}
	var camera: Camera3D = player.camera if "camera" in player else null
	var origin := camera.global_position if camera != null else player.global_position
	var direction := -camera.global_transform.basis.z if camera != null else -player.global_transform.basis.z
	if "input_mode" in player and int(player.input_mode) == 1 and "multiplayer_driver" in player and player.multiplayer_driver != null and player.multiplayer_driver.has_method("send_cast_spell"):
		player.multiplayer_driver.send_cast_spell(selected_slot, origin, direction, null)
		return {"ok":true,"submitted":true,"slot_index":selected_slot}
	var result := runtime.cast_slot(gs.spell_loadout, selected_slot, player, origin, direction)
	if not bool(result.get("ok",false)):
		return result
	return authority.execute(player, result, world)

func release_full_charge(player: Node3D, charge_ratio: float, world: Node = null) -> Dictionary:
	if charge_ratio < 1.0:
		return {"ok":false,"reason":"spell_not_fully_charged","charge_ratio":charge_ratio}
	return cast_selected(player, world)
