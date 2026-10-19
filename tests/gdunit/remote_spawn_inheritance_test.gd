extends GdUnitTestSuite

## B2（架构审查 0644 §发现2 / 决策 G1-A）：远端客户端经服务器侧存档仓继承单人存档。
##
## 客户端 spawn 只上送稳定身份 player_guid；服务器按 guid 从注入的 ServerSaveRepository
## 加载权威存档并构建 PlayerContext（materials/loadout/spell_state/attributes/skills），
## 绝不信任客户端自报存档字典（send_spawn/rpc_client_spawn 已移除 save_state 参数）。
## 仓无该 guid 记录 → 默认上下文（新玩家无存档，决策 A 接受）。

const SR := preload("res://globals/multiplayer/session_root.gd")
const NETWORK_MANAGER := preload("res://globals/core/network_manager.gd")
const RepoClass := preload("res://globals/multiplayer/server_save_repository.gd")

## 构造带隔离存档仓的服务器会话（unique 临时目录，避免 user:// 残留互相污染）。
func _make_server_with_repo() -> Dictionary:
	var s: SR = auto_free(SR.new())
	s.init_server()
	var repo = auto_free(RepoClass.new())
	repo.set_save_dir("user://remote_spawn_inherit_%d" % Time.get_ticks_usec())
	s.server_save_repo = repo
	return {"session": s, "repo": repo}

## 一份完整的单人存档摘要（与 GameState.build_network_save_state 的 DTO 形状一致）。
func _full_save_state() -> Dictionary:
	return {
		"materials": {"iron_ore": 7, "goblin_tooth": 3},
		"loadout": {
			"weapon_slots": ["shortsword", "", "", ""],
			"armor_slots": {"head": "leather_cap"},
		},
		"spell_state": {
			"spell_loadout": {"slot_runes": [["ember", "hima", ""], [], [], []]},
			"spell_mana": 42,
			"spell_max_mana": 100,
			"spell_runtime": {},
		},
	}

## 仓内有该 guid 记录 → 远端 spawn（客户端只上送 guid，save_state={}）恢复该存档的
## 材料 / loadout 槽位 / 法术装配 / 法力。
func test_repo_record_is_applied_to_remote_spawn_context() -> void:
	var ctx_dict := _make_server_with_repo()
	var s: SR = ctx_dict["session"]
	var repo = ctx_dict["repo"]
	repo.save_save("player_remote_1", _full_save_state())
	# 远端路径：save_state 为 {}（客户端字典已被移除/忽略），只带稳定 guid。
	var peer_ctx = s.handle_spawn_request(2, {}, "player_remote_1")
	assert_object(peer_ctx).is_not_null()
	# materials 恢复
	assert_int(int(peer_ctx.inventory.materials.get("iron_ore", 0))).is_equal(7)
	assert_int(int(peer_ctx.inventory.materials.get("goblin_tooth", 0))).is_equal(3)
	# loadout 槽位恢复
	assert_str(peer_ctx.loadout.get_weapon_slot(0)).is_equal("shortsword")
	assert_str(peer_ctx.loadout.get_armor_slot("head")).is_equal("leather_cap")
	# spell_loadout 恢复（非空）+ 权威法力
	assert_bool(not peer_ctx.spell_loadout.serialize().is_empty()).is_true()
	var runes: Array = peer_ctx.spell_loadout.get_runes(0)
	assert_bool(not runes.is_empty()).is_true()
	assert_str(runes[0]).is_equal("ember")
	assert_int(peer_ctx.spell_mana).is_equal(42)

## 仓无该 guid 记录 → 默认上下文（空材料、空槽位、默认属性），不崩溃。
func test_no_repo_record_falls_back_to_default_context() -> void:
	var ctx_dict := _make_server_with_repo()
	var s: SR = ctx_dict["session"]
	var peer_ctx = s.handle_spawn_request(3, {}, "brand_new_remote")
	assert_object(peer_ctx).is_not_null()
	assert_bool(peer_ctx.inventory.materials.is_empty()).is_true()
	assert_str(peer_ctx.loadout.get_weapon_slot(0)).is_equal("")
	assert_str(peer_ctx.loadout.get_armor_slot("head")).is_equal("")
	assert_int(peer_ctx.attributes.get_attr("str")).is_equal(5)  # init_defaults

## 负向源守卫（会话层）：即使调用方（伪造客户端）传入非空 save_state，仓内记录必须优先。
func test_repo_record_beats_client_fake_save_state() -> void:
	var ctx_dict := _make_server_with_repo()
	var s: SR = ctx_dict["session"]
	var repo = ctx_dict["repo"]
	repo.save_save("player_remote_2", {"materials": {"real_ore": 9}})
	var fake := {"materials": {"fake_ore": 999}}
	var peer_ctx = s.handle_spawn_request(4, fake, "player_remote_2")
	assert_object(peer_ctx).is_not_null()
	assert_int(int(peer_ctx.inventory.materials.get("real_ore", 0))).is_equal(9)
	assert_int(int(peer_ctx.inventory.materials.get("fake_ore", 0))).is_equal(0)

## 端到端（服务器网络入口）：远端 spawn 经 _server_handle_spawn(peer_id, player_guid) 按仓恢复。
func test_server_handle_spawn_loads_save_by_guid_from_repo() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	nm.session.server_save_repo.set_save_dir("user://remote_spawn_inherit_net_%d" % Time.get_ticks_usec())
	nm.session.server_save_repo.save_save("remote_net_1", _full_save_state())
	var res: Dictionary = nm._server_handle_spawn(5, "remote_net_1")
	assert_object(res["ctx"]).is_not_null()
	assert_int(int(res["ctx"].inventory.materials.get("iron_ore", 0))).is_equal(7)
	nm.free()

## send_spawn 不再接受/转发存档字典：签名只收 player_guid。
func test_send_spawn_takes_only_player_guid() -> void:
	var source := (load("res://globals/core/network_manager.gd") as GDScript).source_code
	assert_bool(source.contains("func send_spawn(player_guid: String) -> void:")).is_true()
	assert_bool(not source.contains("func send_spawn(_legacy_save_state")).is_true()

## rpc_client_spawn 不再携带 save_state 参数（服务器按 guid 从仓加载；wire 上无空字典占位）。
func test_rpc_client_spawn_has_no_save_state_param() -> void:
	var source := (load("res://globals/core/network_manager.gd") as GDScript).source_code
	var section := source.substr(source.find("func rpc_client_spawn"), 600)
	assert_bool(section.contains("func rpc_client_spawn(peer_id: int, player_guid: String) -> void:")).is_true()
	assert_bool(not section.contains("_untrusted_save_state")).is_true()
	assert_bool(not section.contains("_server_handle_spawn(peer_id, {}, player_guid)")).is_true()
