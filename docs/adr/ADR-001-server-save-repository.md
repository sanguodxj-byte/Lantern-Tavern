# ADR-001: 服务器可信存档仓（ServerSaveRepository）

- 状态：**Accepted（已实施，2026-08-03）**
- 关联：架构审查 P1-1（远端可信存档来源）

## 背景

远端 spawn 的权威材料/装备/法术状态没有可信来源：客户端自报 `save_state` 已被服务器忽略（安全边界正确），但远端玩家只能以空默认状态进入。可玩性/持久化闭环未完成。

## 决策

1. 新增 `globals/multiplayer/server_save_repository.gd`（纯 RefCounted、目录可注入）：
   - 存档文件：`user://server_saves/<guid>.json`，按稳定身份 `player_guid` 键控；
   - GUID 白名单消毒（仅 `[A-Za-z0-9_-]`，≤128 字符）——**防路径穿越**，非法 guid 拒绝读写；
   - API：`load_save(guid)` / `save_save(guid, data)` / `delete_save(guid)`。
2. `SessionRoot.handle_spawn_request`：**服务器仓优先**——该身份在仓内有存档时以其恢复（materials/loadout/spell_state/attributes/skills）；无仓/无存档才用调用方摘要或默认状态。绝不信任客户端字典。
3. `_settle_expedition` 结算成功时把该玩家当前权威状态写回服务器仓（持久化闭环）。
4. `NetworkManager._ensure_session` 注入仓实例（默认 `user://server_saves`）。

## 后果

- 远端玩家在服务器重启/重连后恢复权威状态；结算落盘。
- 房主本地存档作为首次播种来源（`build_network_save_state`），此后以服务器仓为真相。
- 不做账号体系/云存档；同一 guid 单机可见（本仓是服务器进程级存储）。

## 关联决策

- 账号体系/存档迁移（云存档、跨进程共享）——**推迟**至产品层决策（ADR-009 预留）。
