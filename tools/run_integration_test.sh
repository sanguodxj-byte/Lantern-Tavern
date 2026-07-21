#!/usr/bin/env bash
# 双进程 ENet 集成测试编排器。
# 真起两个 Godot 进程：mp_host（服务器，ENet listen）+ mp_client（连接、spawn），
# 验证 NetworkManager 的 RPC 链路在真实 ENet 下端到端通。
# 用法：bash tools/run_integration_test.sh
set -u

# bash 自身操作用 git-bash 风格路径
PROJ="/d/123/Lantern Tavern"
# 传给原生 Windows Godot 的必须用 Windows 风格路径（否则 Godot 把 /d/... 当 unix 路径崩溃）
WINPROJ="D:/123/Lantern Tavern"
GODOT="D:/123/Godot_v4.7-stable_mono_win64.exe"
PORT=17391
ITDIR="$PROJ/.tmp_ittest"          # bash 读写为 /d/123/...
WIN_ITDIR="$WINPROJ/.tmp_ittest"   # Godot(Windows) 读写为 D:/123/... （同一物理目录）

cd "$PROJ" || exit 1
rm -rf "$ITDIR"
mkdir -p "$ITDIR"

# 清掉任何残留 Godot（避免端口/进程占用）
taskkill //F //IM "Godot_v4.7-stable_mono_win64.exe" 2>/dev/null
sleep 1

# 服务器进程（独立 APPDATA，避免与客户端共享 user:// 文件竞争）
ITEST_DIR="$WIN_ITDIR" APPDATA="$WINPROJ/.tmp_apdata_srv" \
  "$GODOT" --headless "$WINPROJ/tests/integration/mp_host.tscn" > "$ITDIR/server.log" 2>&1 &
SRV=$!
echo "server pid=$SRV"

# 等待服务器就绪（最多 ~60s）
for i in $(seq 1 60); do
  if [ -f "$ITDIR/server_ready.txt" ]; then break; fi
  sleep 1
done
if [ ! -f "$ITDIR/server_ready.txt" ]; then
  echo "SERVER FAILED TO START (no server_ready.txt)"
  echo "--- server.log ---"; tail -40 "$ITDIR/server.log"
  kill $SRV 2>/dev/null
  taskkill //F //IM "Godot_v4.7-stable_mono_win64.exe" 2>/dev/null
  exit 1
fi
echo "server ready: $(cat "$ITDIR/server_ready.txt")"

# 客户端进程（独立 APPDATA）
ITEST_DIR="$WIN_ITDIR" APPDATA="$WINPROJ/.tmp_apdata_cli" \
  "$GODOT" --headless "$WINPROJ/tests/integration/mp_client.tscn" > "$ITDIR/client.log" 2>&1 &
CLI=$!
echo "client pid=$CLI"

# 等待双方结果（最多 ~120s）
for i in $(seq 1 120); do
  if [ -f "$ITDIR/client_ok.txt" ] && [ -f "$ITDIR/server_ok.txt" ]; then break; fi
  sleep 1
done

SRV_RES="$(cat "$ITDIR/server_ok.txt" 2>/dev/null || echo MISSING)"
CLI_RES="$(cat "$ITDIR/client_ok.txt" 2>/dev/null || echo MISSING)"
echo "SERVER: $SRV_RES"
echo "CLIENT: $CLI_RES"

# 清理（先 cat 日志再删，便于失败排查）
kill $SRV $CLI 2>/dev/null
taskkill //F //IM "Godot_v4.7-stable_mono_win64.exe" 2>/dev/null

if [[ "$SRV_RES" == OK* ]] && [[ "$CLI_RES" == OK* ]]; then
  echo "INTEGRATION TEST: PASS"
  rm -rf "$ITDIR" "$PROJ/.tmp_apdata_srv" "$PROJ/.tmp_apdata_cli"
  exit 0
else
  echo "INTEGRATION TEST: FAIL"
  echo "--- server.log tail ---"; tail -40 "$ITDIR/server.log"
  echo "--- client.log tail ---"; tail -40 "$ITDIR/client.log"
  rm -rf "$ITDIR" "$PROJ/.tmp_apdata_srv" "$PROJ/.tmp_apdata_cli"
  exit 2
fi
