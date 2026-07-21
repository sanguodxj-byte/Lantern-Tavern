extends GdUnitTestSuite

# Phase 9（docs/25 §9 / §12.3）：EntitySyncAuthority 服务器实体复制权威。
# 服务器维护权威实体表，产生 spawned / snapshot / despawned 复制事件；
# build_delta 计算从 prev→curr 状态所需的复制事件集（客户端增量同步核心）。

const EntitySyncAuthority := preload("res://globals/multiplayer/entity_sync_authority.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

func test_spawn_writes_and_emits() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var ents := {}
	var r: Dictionary = esa.spawn_entity(11, {"kind": "enemy", "hp": 30}, ents)
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_ENTITY_SPAWNED)
	assert_int(int(r["event"]["entity_id"])).is_equal(11)
	assert_bool(ents.has(11)).is_true()
	assert_int(int(ents[11]["hp"])).is_equal(30)

func test_spawn_duplicate_rejected() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var ents := {}
	esa.spawn_entity(11, {"hp": 30}, ents)
	var r: Dictionary = esa.spawn_entity(11, {"hp": 99}, ents)
	assert_bool(r["success"]).is_false()
	# 原实体未被覆盖
	assert_int(int(ents[11]["hp"])).is_equal(30)

func test_despawn_removes_and_emits() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var ents := {}
	esa.spawn_entity(11, {"hp": 30}, ents)
	var r: Dictionary = esa.despawn_entity(11, ents)
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_ENTITY_DESPAWNED)
	assert_bool(ents.has(11)).is_false()

func test_despawn_missing_rejected() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var r: Dictionary = esa.despawn_entity(404, {})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_TARGET)

func test_update_merges_and_emits_snapshot() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var ents := {}
	esa.spawn_entity(11, {"hp": 30, "pos": "a"}, ents)
	var r: Dictionary = esa.update_entity(11, {"hp": 20}, ents)
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_ENTITY_SNAPSHOT)
	assert_int(int(ents[11]["hp"])).is_equal(20)
	# 未涉及字段保留
	assert_str(String(ents[11]["pos"])).is_equal("a")
	assert_int(int(r["event"]["data"]["hp"])).is_equal(20)

func test_update_missing_rejected() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var r: Dictionary = esa.update_entity(404, {"hp": 1}, {})
	assert_bool(r["success"]).is_false()

func test_build_delta_new_entity_spawns() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var prev := {}
	var curr := {7: {"hp": 15}}
	var ev: Array = esa.build_delta(prev, curr)
	assert_int(ev.size()).is_equal(1)
	assert_str(ev[0]["event"]).is_equal(NP.EVT_ENTITY_SPAWNED)
	assert_int(ev[0]["entity_id"]).is_equal(7)

func test_build_delta_changed_entity_snapshots() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var prev := {7: {"hp": 15}}
	var curr := {7: {"hp": 10}}
	var ev: Array = esa.build_delta(prev, curr)
	assert_int(ev.size()).is_equal(1)
	assert_str(ev[0]["event"]).is_equal(NP.EVT_ENTITY_SNAPSHOT)
	assert_int(int(ev[0]["data"]["hp"])).is_equal(10)

func test_build_delta_unchanged_entity_no_event() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var prev := {7: {"hp": 15, "pos": "a"}}
	var curr := {7: {"hp": 15, "pos": "a"}}
	var ev: Array = esa.build_delta(prev, curr)
	assert_int(ev.size()).is_equal(0)

func test_build_delta_removed_entity_despawned() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var prev := {7: {"hp": 15}}
	var curr := {}
	var ev: Array = esa.build_delta(prev, curr)
	assert_int(ev.size()).is_equal(1)
	assert_str(ev[0]["event"]).is_equal(NP.EVT_ENTITY_DESPAWNED)
	assert_int(ev[0]["entity_id"]).is_equal(7)

func test_build_delta_full_transition() -> void:
	var esa = auto_free(EntitySyncAuthority.new())
	var prev := {1: {"hp": 10}, 2: {"hp": 20}}          # 1 变化, 2 消失
	var curr := {1: {"hp": 5}, 3: {"hp": 30}}           # 1 快照, 3 新增
	var ev: Array = esa.build_delta(prev, curr)
	# 期望：1=snapshot, 3=spawned, 2=despawned 共 3 个事件
	assert_int(ev.size()).is_equal(3)
	var kinds := {}
	for e in ev:
		kinds[e["event"]] = true
	assert_bool(kinds.has(NP.EVT_ENTITY_SNAPSHOT)).is_true()
	assert_bool(kinds.has(NP.EVT_ENTITY_SPAWNED)).is_true()
	assert_bool(kinds.has(NP.EVT_ENTITY_DESPAWNED)).is_true()
