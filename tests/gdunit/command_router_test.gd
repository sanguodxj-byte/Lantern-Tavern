extends GdUnitTestSuite

# Phase 3（docs/25 §3.2/§11）：CommandRouter 把已验证命令路由到权威子系统。
# 纯逻辑，无场景树依赖，用假处理器验证路由/包裹语义。

const CommandRouter := preload("res://globals/multiplayer/command_router.gd")
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

func test_route_unknown_command_returns_invalid_state() -> void:
	var router = auto_free(CommandRouter.new())
	var res = router.route({"type": "no_such_cmd"}, _ctx())
	assert_bool(res["success"]).is_false()
	assert_str(res["error_code"]).is_equal("INVALID_STATE")

func test_route_dispatches_to_registered_handler() -> void:
	var router = auto_free(CommandRouter.new())
	router.register_handler("request_pickup", func(c, c2): return {"success": true, "event": {"event": "interaction_result"}, "error_code": ""})
	var res = router.route({"type": "request_pickup", "target_entity_id": 9}, _ctx())
	assert_bool(res["success"]).is_true()
	assert_str(res["event"]["event"]).is_equal("interaction_result")

func test_route_rejects_bad_command_type() -> void:
	var router = auto_free(CommandRouter.new())
	var res = router.route({"foo": 1}, _ctx())
	assert_bool(res["success"]).is_false()
	assert_str(res["error_code"]).is_equal("INVALID_TARGET")

func test_handler_can_return_bare_event_dict() -> void:
	var router = auto_free(CommandRouter.new())
	router.register_handler("request_spawn", func(c, c2): return {"peer_id": 7})
	var res = router.route({"type": "request_spawn"}, _ctx())
	assert_bool(res["success"]).is_true()
	assert_int(int(res["event"]["peer_id"])).is_equal(7)

func test_unregister_handler_restores_unknown() -> void:
	var router = auto_free(CommandRouter.new())
	router.register_handler("request_pickup", func(c, c2): return {"success": true, "event": {}, "error_code": ""})
	router.unregister_handler("request_pickup")
	var res = router.route({"type": "request_pickup"}, _ctx())
	assert_bool(res["success"]).is_false()
	assert_str(res["error_code"]).is_equal("INVALID_STATE")
