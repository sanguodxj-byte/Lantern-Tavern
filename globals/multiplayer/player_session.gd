extends RefCounted

## PlayerSession —— 单个 peer 的会话元数据（Phase 3，§3.3/§13）。
## 由 PlayerRegistry 持有，与 PlayerContext / Player 节点并列。
## 不含游戏逻辑，仅记录连接/命令/世界修订状态。

var peer_id: int = 0
var connection_state: String = "connected"
var last_command_sequence: int = 0
var last_input_tick: int = 0
var current_world_revision: int = 0
var spawned: bool = false

func _init(p_peer_id: int = 0) -> void:
	peer_id = p_peer_id
