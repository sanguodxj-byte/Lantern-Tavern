extends Node

## WorldState —— 当前共享世界的权威状态（Phase 3/7，§3.2/§9/§13.2）。
## 持有 world_revision、当前 space、地牢 run 元数据与实体快照索引。
##
## 经 preload 访问：const WS := preload("res://globals/multiplayer/world_state.gd")
## 设计基线见 docs/25-联机总体方案.md §3.2、§9、§13.2。

const NP := preload("res://globals/multiplayer/network_protocol.gd")

var world_revision: int = 0
var current_space: String = "tavern"
var run_id: String = ""
var run_seed: int = 0
var generation_config_version: int = 0
var layout_schema_version: int = 0
var zone_id: String = ""
var difficulty: int = 0

## 自增 world_revision（场景空间切换/实体变更时调用）。返回新 revision。
func bump_revision() -> int:
	world_revision += 1
	return world_revision

## 切换当前空间（如 tavern <-> dungeon），并返回新 revision。
func transition_space(space: String) -> int:
	current_space = space
	return bump_revision()

## 应用服务器下发的地牢 run 元数据（§9.1）。
func apply_dungeon_run(meta: Dictionary) -> void:
	if meta.has("run_id"):
		run_id = String(meta["run_id"])
	if meta.has("run_seed"):
		run_seed = int(meta["run_seed"])
	if meta.has("generation_config_version"):
		generation_config_version = int(meta["generation_config_version"])
	if meta.has("layout_schema_version"):
		layout_schema_version = int(meta["layout_schema_version"])
	if meta.has("zone_id"):
		zone_id = String(meta["zone_id"])
	if meta.has("difficulty"):
		difficulty = int(meta["difficulty"])

## 构建 session_snapshot（重连用，§13.2）。
func build_session_snapshot() -> Dictionary:
	return {
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": world_revision,
		"current_space": current_space,
		"run_id": run_id,
		"run_seed": run_seed,
		"generation_config_version": generation_config_version,
		"layout_schema_version": layout_schema_version,
		"zone_id": zone_id,
		"difficulty": difficulty,
	}

## 从 snapshot 恢复（重连用）。
func apply_session_snapshot(snap: Dictionary) -> void:
	if snap.has("world_revision"):
		world_revision = int(snap["world_revision"])
	if snap.has("current_space"):
		current_space = String(snap["current_space"])
	apply_dungeon_run(snap)
