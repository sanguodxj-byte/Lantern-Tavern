extends GdUnitTestSuite

# Phase 3/4（docs/25 §6.2/§8.2/§13.2）：SnapshotReplicator 把服务器状态字典转换为
# 发给客户端的快照/事件负载。纯数据变换，无场景树依赖。

const SnapshotReplicator := preload("res://globals/multiplayer/snapshot_replicator.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

func test_build_player_snapshot_fields() -> void:
	var sr = auto_free(SnapshotReplicator.new())
	var state := {
		"position": Vector3(1, 0, 2),
		"velocity": Vector3(0, 0, -3),
		"rotation_y": 1.3,
		"movement_state": "running",
		"grounded": true,
	}
	var snap = sr.build_player_snapshot(2, state, 12022)
	assert_str(snap["event"]).is_equal(NP.EVT_PLAYER_SNAPSHOT)
	assert_int(int(snap["peer_id"])).is_equal(2)
	assert_int(int(snap["server_tick"])).is_equal(12022)
	assert_object(snap["position"]).is_equal(Vector3(1, 0, 2))
	assert_str(snap["movement_state"]).is_equal("running")
	assert_bool(snap["grounded"]).is_true()

func test_build_entity_snapshot_fields() -> void:
	var sr = auto_free(SnapshotReplicator.new())
	var ent := {
		"entity_id": 4312, "enemy_type": "rat", "position": Vector3(5, 0, 5),
		"rotation": Vector3.ZERO, "velocity": Vector3.ZERO, "state": "chase",
		"current_life": 42, "max_life": 60, "target_peer_id": 1,
		"status_effects": [], "is_dead": false,
	}
	var snap = sr.build_entity_snapshot(ent)
	assert_str(snap["event"]).is_equal(NP.EVT_ENTITY_SNAPSHOT)
	assert_int(int(snap["entity_id"])).is_equal(4312)
	assert_int(int(snap["current_life"])).is_equal(42)
	assert_str(snap["state"]).is_equal("chase")

func test_build_session_snapshot_contains_all_sections() -> void:
	var sr = auto_free(SnapshotReplicator.new())
	var snap = sr.build_session_snapshot(23, "dungeon", {}, [], [], [], [], [], {})
	assert_str(snap["event"]).is_equal("session_snapshot")
	assert_int(int(snap["world_revision"])).is_equal(23)
	assert_str(snap["current_space"]).is_equal("dungeon")
	assert_array(snap["enemies"]).is_empty()
	assert_array(snap["loot"]).is_empty()
	assert_int(int(snap["protocol_version"])).is_equal(NP.PROTOCOL_VERSION)
