#!/usr/bin/env bash
# 双进程 ENet 集成测试（avatar 场景）：验证桥接层显式 RPC 真实复制远端玩家节点
# （MultiplayerSpawner 在本 Godot 4.7 构建因 SceneTree 无 .multiplayer 而复制不可靠，改用 RPC）
# + 客户端按 rpc_snapshot 插值移动。host 与 client 加载【同一场景】，靠 ITEST_ROLE 区分。
# 用法：bash tools/run_integration_avatar_test.sh
set -u

PROJ="/d/123/Lantern Tavern"
WINPROJ="D:/123/Lantern Tavern"
GODOT="D:/123/Godot_v4.7-stable_mono_win64.exe"
PORT=12399
ITDIR="$PROJ/.tmp_ittest_avatar"
WIN_ITDIR="$WINPROJ/.tmp_ittest_avatar"
SCENE="$WINPROJ/tests/integration/mp_avatar_test.tscn"

cd "$PROJ" || exit 1
rm -rf "$ITDIR"
mkdir -p "$ITDIR"

taskkill //F //IM "Godot_v4.7-stable_mono_win64.exe" 2>/dev/null
sleep 3

# 服务器进程（ITEST_ROLE=host）
ITEST_DIR="$WIN_ITDIR" ITEST_ROLE=host APPDATA="$WINPROJ/.tmp_apdata_srv" \
  "$GODOT" --headless "$SCENE" > "$ITDIR/server.log" 2>&1 &
SRV=$!
echo "server pid=$SRV"

for i in $(seq 1 60); do
  if [ -f "$ITDIR/server_ready.txt" ]; then break; fi
  sleep 1
done
if [ ! -f "$ITDIR/server_ready.txt" ]; then
  echo "SERVER FAILED TO START (no server_ready.txt)"
  echo "--- server.log ---"; tail -50 "$ITDIR/server.log"
  kill $SRV 2>/dev/null
  taskkill //F //IM "Godot_v4.7-stable_mono_win64.exe" 2>/dev/null
  exit 1
fi
echo "server ready: $(cat "$ITDIR/server_ready.txt")"

# 客户端进程（ITEST_ROLE=client）
ITEST_DIR="$WIN_ITDIR" ITEST_ROLE=client APPDATA="$WINPROJ/.tmp_apdata_cli" \
  "$GODOT" --headless "$SCENE" > "$ITDIR/client.log" 2>&1 &
CLI=$!
echo "client pid=$CLI"

for i in $(seq 1 120); do
  if [ -f "$ITDIR/client_ok.txt" ]; then break; fi
  sleep 1
done

SRV_RES="$(cat "$ITDIR/server_ok.txt" 2>/dev/null || echo MISSING)"
CLI_RES="$(cat "$ITDIR/client_ok.txt" 2>/dev/null || echo MISSING)"
AV_RES="$(cat "$ITDIR/client_avatar_ok.txt" 2>/dev/null || echo MISSING)"
MV_RES="$(cat "$ITDIR/client_move_ok.txt" 2>/dev/null || echo MISSING)"
SP_RES="$(cat "$ITDIR/server_port.txt" 2>/dev/null || echo ?)"
CP_RES="$(cat "$ITDIR/client_port.txt" 2>/dev/null || echo ?)"
echo "SERVER: $SRV_RES (port $SP_RES)"
echo "CLIENT: $CLI_RES (port $CP_RES)"
echo "AVATAR REPLICATED: $AV_RES"
echo "AVATAR MOVED: $MV_RES"

# 持久化判定结果（写项目根，不被下方 rm 清理），便于读取。
VERDICT_FILE="$PROJ/.ittest_avatar_verdict.txt"
if [[ "$SRV_RES" == OK* ]] && [[ "$CLI_RES" == OK* ]] && [[ "$AV_RES" == OK* ]] && [[ "$MV_RES" == OK* ]]; then
  echo "INTEGRATION AVATAR TEST: PASS" | tee "$VERDICT_FILE"
  echo "server=$SRV_RES client=$CLI_RES avatar=$AV_RES move=$MV_RES port_srv=$SP_RES port_cli=$CP_RES" >> "$VERDICT_FILE"
else
  echo "INTEGRATION AVATAR TEST: FAIL" | tee "$VERDICT_FILE"
  echo "server=$SRV_RES client=$CLI_RES avatar=$AV_RES move=$MV_RES port_srv=$SP_RES port_cli=$CP_RES" >> "$VERDICT_FILE"
  # 失败时把日志复制出来留存（避免被 rm 清掉）。
  cp "$ITDIR/server.log" "$PROJ/.ittest_avatar_server.log" 2>/dev/null
  cp "$ITDIR/client.log" "$PROJ/.ittest_avatar_client.log" 2>/dev/null
fi
# 无论通过失败都保留完整日志（便于排查），覆盖式写入持久文件。
cp "$ITDIR/server.log" "$PROJ/.ittest_avatar_server.log" 2>/dev/null
cp "$ITDIR/client.log" "$PROJ/.ittest_avatar_client.log" 2>/dev/null

kill $SRV $CLI 2>/dev/null
taskkill //F //IM "Godot_v4.7-stable_mono_win64.exe" 2>/dev/null

rm -rf "$ITDIR" "$PROJ/.tmp_apdata_srv" "$PROJ/.tmp_apdata_cli"
exit 0
