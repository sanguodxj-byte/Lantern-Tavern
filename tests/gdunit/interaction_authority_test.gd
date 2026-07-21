extends GdUnitTestSuite

# Phase 5（docs/25 §11/§5.2）：InteractionAuthority 服务器权威拾取/交互裁决。
# 校验：存活 → 目标存在 → 未消费 → 距离 → 写入背包 → 标记消费。

const InteractionAuthority := preload("res://globals/multiplayer/interaction_authority.gd")
const PlayerContextClass := preload("res://globals/core/player_context.gd")
const AttrPanelClass := preload("res://globals/combat/attr_panel.gd")
const SkillRuntimeClass := preload("res://globals/combat/skill_runtime.gd")
const InvClass := preload("res://globals/core/state/expedition_inventory.gd")
const LoClass := preload("res://globals/core/state/equipment_loadout.gd")

func _ctx() -> PlayerContext:
	var ap = AttrPanelClass.new(); ap.init_defaults()
	var sk = SkillRuntimeClass.new(); sk.init_defaults()
	var inv = InvClass.new(); var lo = LoClass.new()
	return auto_free(PlayerContextClass.for_peer(ap, sk, inv, lo))

func _live(pos := Vector3.ZERO) -> Dictionary:
	return {"peer_id": 1, "is_alive": true, "position": pos}

func test_pickup_success_material() -> void:
	var ia = auto_free(InteractionAuthority.new())
	var ctx = _ctx()
	var entities := {9001: {"item_id": "goblin_tooth", "item_kind": "material", "amount": 1, "position": Vector3.ZERO, "consumed": false}}
	var cmd := {"type": "request_pickup", "target_entity_id": 9001, "sequence": 1}
	var res = ia.resolve_interaction(cmd, ctx, _live(), entities)
	assert_bool(res["success"]).is_true()
	assert_int(int(ctx.inventory.materials.get("goblin_tooth", 0))).is_equal(1)
	assert_bool(bool(entities[9001]["consumed"])).is_true()
	assert_str(res["event"]["event"]).is_equal("interaction_result")

func test_pickup_out_of_range_rejected() -> void:
	var ia = auto_free(InteractionAuthority.new())
	var ctx = _ctx()
	var entities := {9001: {"item_id": "goblin_tooth", "item_kind": "material", "amount": 1, "position": Vector3(100, 0, 100), "consumed": false}}
	var cmd := {"type": "request_pickup", "target_entity_id": 9001, "sequence": 1}
	var res = ia.resolve_interaction(cmd, ctx, _live(), entities)
	assert_bool(res["success"]).is_false()
	assert_str(res["error_code"]).is_equal("OUT_OF_RANGE")

func test_pickup_already_consumed_rejected() -> void:
	var ia = auto_free(InteractionAuthority.new())
	var ctx = _ctx()
	var entities := {9001: {"item_id": "goblin_tooth", "item_kind": "material", "amount": 1, "position": Vector3.ZERO, "consumed": true}}
	var cmd := {"type": "request_pickup", "target_entity_id": 9001, "sequence": 1}
	var res = ia.resolve_interaction(cmd, ctx, _live(), entities)
	assert_bool(res["success"]).is_false()
	assert_str(res["error_code"]).is_equal("TARGET_ALREADY_CONSUMED")

func test_pickup_dead_player_rejected() -> void:
	var ia = auto_free(InteractionAuthority.new())
	var ctx = _ctx()
	var live := _live(); live["is_alive"] = false
	var entities := {9001: {"item_id": "g", "item_kind": "material", "amount": 1, "position": Vector3.ZERO, "consumed": false}}
	var cmd := {"type": "request_pickup", "target_entity_id": 9001, "sequence": 1}
	var res = ia.resolve_interaction(cmd, ctx, live, entities)
	assert_str(res["error_code"]).is_equal("PLAYER_NOT_ALIVE")
