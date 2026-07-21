#!/usr/bin/env bash
# =============================================================================
# Lantern Tavern — 联机/网络层 CI 测试清单 (solidified)
# -----------------------------------------------------------------------------
# 这是联机 netcode 套件的唯一权威清单。运行方式：
#
#   本地/沙箱 :  bash tools/run_multiplayer_tests.sh
#   CI 带报告 :  bash tools/run_multiplayer_tests.sh --junit=reports/mp.xml
#   只看清单 :  bash tools/run_multiplayer_tests.sh --list
#   自检(不跑):  bash tools/run_multiplayer_tests.sh --selfcheck
#
# 设计要点（解决"清单过期"问题）：
#   1. 显式策划清单——每个套件都是经评审纳入的，顺序即依赖/分组。
#   2. 运行前存在性校验——清单里引用的文件若不存在，直接判 FAIL（杜绝静默误报 PASS）。
#   3. 覆盖率审计——扫描 tests/gdunit 下所有匹配 netcode 关键词的套件，
#      凡未被清单收录的打印 WARNING（避免新测试被沉默漏测）。
#   4. 稳健的 gdUnit 摘要解析 + 硬失败标记（Parse Error / 无用例 / 脚本错误）。
#   5. 可输出 JUnit XML，直接喂给 GitHub Actions / GitLab CI / Tencent CI。
#
# 环境约定（沙箱/Windows）：
#   - Godot 二进制位于工作区外，CI 需把 GODOT 指向可执行文件（env 覆盖）。
#   - mono 写 user:// 必须重定向 APPDATA 到工作区内（否则 signal 11）。
#   - 每个套件独立进程 + 独立日志；stdout 落盘后 grep（绝不管道接 head/tail）。
# =============================================================================
set -u

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR" || exit 1

# Godot(Windows 二进制) 需要 Windows 风格工程路径；CI Linux 用原生绝对路径。
if command -v cygpath >/dev/null 2>&1; then
  WINPROJ="$(cygpath -w "$PROJECT_DIR")"
else
  WINPROJ="$PROJECT_DIR"
fi

# Godot 可执行文件：允许 env 覆盖（CI Linux 上指向 linux 二进制）
GODOT="${GODOT:-D:/123/Godot_v4.7-stable_mono_win64.exe}"
RUNNER="tests/gdunit4_runner.gd"

# 解析参数
JUNIT=""
MODE="run"
for a in "$@"; do
  case "$a" in
    --junit=*)   JUNIT="${a#--junit=}" ;;
    --list)      MODE="list" ;;
    --selfcheck) MODE="selfcheck" ;;
    *) echo "WARN: 未知参数 '$a'" ;;
  esac
done

# ---- 联机 netcode 套件策划清单（唯一真相源）-------------------------------
# 分组仅用于可读性，运行顺序即数组顺序。新增联机套件时在此追加。
TESTS=(
  # 玩家/会话基础
  tests/gdunit/player_attributes_instance_test.gd
  tests/gdunit/player_skill_runtime_instance_test.gd
  tests/gdunit/player_context_factory_test.gd
  tests/gdunit/player_registry_test.gd
  tests/gdunit/world_state_test.gd
  # 协议 / 命令 / 校验
  tests/gdunit/network_protocol_test.gd
  tests/gdunit/command_validator_test.gd
  tests/gdunit/command_router_test.gd
  tests/gdunit/snapshot_replicator_test.gd
  # 权威层
  tests/gdunit/interaction_authority_test.gd
  tests/gdunit/loot_authority_test.gd
  tests/gdunit/combat_authority_test.gd
  tests/gdunit/movement_authority_test.gd
  tests/gdunit/entity_sync_authority_test.gd
  tests/gdunit/dungeon_authority_test.gd
  tests/gdunit/connection_authority_test.gd
  tests/gdunit/save_authority_test.gd
  # 网络层 / 会话根
  tests/gdunit/network_manager_test.gd
  tests/gdunit/network_manager_integration_test.gd
  tests/gdunit/session_root_test.gd
  # 客户端驱动 / 桥接 / 场景
  tests/gdunit/client_command_driver_test.gd
  tests/gdunit/multiplayer_scene_integration_test.gd
  tests/gdunit/multiplayer_scene_bridge_test.gd
  tests/gdunit/multiplayer_scope_test.gd
  # 安全 / 重连 / 垂直切片（本轮新增）
  tests/gdunit/security_audit_test.gd
  tests/gdunit/reconnect_recovery_test.gd
  tests/gdunit/dungeon_session_multiplayer_test.gd
  # UI 回归守卫
  tests/gdunit/combat_bridge_test.gd
  tests/gdunit/attr_panel_test.gd
)

# netcode 关键词（覆盖率审计用）：匹配文件名即视为联机相关套件
NETCODE_RE='(multiplayer|network|session_root|connection|reconnect|security_audit|authority|entity_sync|snapshot_replicator|command_router|command_validator|client_command|combat_bridge|attr_panel|world_state|save_authority|player_registry|player_context|player_attributes|player_skill_runtime|dungeon_authority)'

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
manifest_set() {
  # 输出清单的 basename 集合（用于差集计算）
  for t in "${TESTS[@]}"; do basename "$t"; done
}

audit_coverage() {
  local warned=0
  local mset
  mset="$(manifest_set | sort -u | tr '\n' ' ')"
  for f in tests/gdunit/*.gd; do
    bn="$(basename "$f")"
    if echo "$bn" | grep -qE "$NETCODE_RE"; then
      if ! echo " $mset " | grep -q " $bn "; then
        echo "  WARNING: netcode 套件 '$bn' 未被清单收录（考虑加入 TESTS 数组）"
        warned=1
      fi
    fi
  done
  return $warned
}

# ---------------------------------------------------------------------------
# --list / --selfcheck 模式
# ---------------------------------------------------------------------------
if [ "$MODE" = "list" ]; then
  echo "联机 netcode 测试清单（共 ${#TESTS[@]} 个）："
  for t in "${TESTS[@]}"; do echo "  $t"; done
  echo ""
  echo "覆盖率审计："
  audit_coverage || true
  exit 0
fi

if [ "$MODE" = "selfcheck" ]; then
  echo "=== 清单自检 ==="
  rc=0
  for t in "${TESTS[@]}"; do
    if [ ! -f "$t" ]; then echo "  MISSING: $t"; rc=1; else echo "  ok: $t"; fi
  done
  echo ""
  echo "覆盖率审计："
  audit_coverage || rc=1
  exit $rc
fi

# ---------------------------------------------------------------------------
# 运行模式
# ---------------------------------------------------------------------------
if [ ! -x "$GODOT" ] && [ ! -f "$GODOT" ]; then
  echo "ERROR: Godot 不可执行: $GODOT (用 GODOT=... 覆盖)" >&2
  exit 2
fi

if command -v cygpath >/dev/null 2>&1; then
  APPDATA_DIR="$(cygpath -w "$PROJECT_DIR")/.tmp_ci_apdata"
else
  APPDATA_DIR="$PROJECT_DIR/.tmp_ci_apdata"
fi
mkdir -p "$APPDATA_DIR"
export APPDATA="$APPDATA_DIR"

PASS=0
FAIL=0
FAILLIST=""
TOTAL=${#TESTS[@]}
# JUnit 收集
JUNIT_CASES=""
START_ALL=$(date +%s)

for t in "${TESTS[@]}"; do
  name="$(basename "$t" .gd)"

  # 存在性校验（过期清单防护）
  if [ ! -f "$t" ]; then
    echo "FAIL(missing) $name  | 清单引用了不存在的文件: $t"
    FAIL=$((FAIL+1)); FAILLIST="$FAILLIST $name"
    JUNIT_CASES="${JUNIT_CASES}<testcase name=\"$name\" classname=\"multiplayer\" time=\"0\"><failure message=\"missing file\">$t</failure></testcase>"
    continue
  fi

  log="$APPDATA_DIR/$name.log"
  # 跨平台清残留（Linux CI 无 taskkill）
  command -v taskkill >/dev/null 2>&1 && taskkill //F //IM "Godot_v4.7-stable_mono_win64.exe" >/dev/null 2>&1
  START=$(date +%s)
  timeout 240 "$GODOT" --headless --path "$WINPROJ" -s "$RUNNER" -- --ignoreHeadlessMode -a "$t" > "$log" 2>&1
  RC=$?
  END=$(date +%s)
  ELAPSED=$((END-START))

  # 硬失败标记：解析/加载错误、未发现用例 → 即使无汇总行也判 FAIL
  hard=$(grep -aE "No test cases found|Script errors were detected|Parse Error|Failed to load script|SCRIPT ERROR" "$log" | head -1)
  # 汇总行（兼容 gdUnit 不同版本：Statistics: / Overall Summary）
  sum=$(grep -aE "Statistics:|Overall Summary" "$log" | tail -1)

  if [ -n "$hard" ] || [ -z "$sum" ]; then
    echo "FAIL(hard)   $name  | ${hard:-no summary line} (log: $log)"
    FAIL=$((FAIL+1)); FAILLIST="$FAILLIST $name"
    JUNIT_CASES="${JUNIT_CASES}<testcase name=\"$name\" classname=\"multiplayer\" time=\"$ELAPSED\"><failure message=\"hard fail\">${hard:-no summary}</failure></testcase>"
    continue
  fi

  # 以汇总行的 errors/failures 为权威判定（gdUnit 目录孤儿致 exit 101 仍算通过）
  ef=$(echo "$sum" | grep -oaE "[0-9]+ errors"   | grep -oaE "[0-9]+" | head -1)
  ff=$(echo "$sum" | grep -oaE "[0-9]+ failures" | grep -oaE "[0-9]+" | head -1)
  ef=${ef:-0}; ff=${ff:-0}
  if [ "$ef" -eq 0 ] && [ "$ff" -eq 0 ] && ! echo "$sum" | grep -qa "FAILED"; then
    echo "PASS        $name  | $sum"
    PASS=$((PASS+1))
    JUNIT_CASES="${JUNIT_CASES}<testcase name=\"$name\" classname=\"multiplayer\" time=\"$ELAPSED\"/>"
  else
    echo "FAIL(rc=$RC)  $name  | $sum"
    FAIL=$((FAIL+1)); FAILLIST="$FAILLIST $name"
    JUNIT_CASES="${JUNIT_CASES}<testcase name=\"$name\" classname=\"multiplayer\" time=\"$ELAPSED\"><failure message=\"errors=$ef failures=$ff\">$sum</failure></testcase>"
  fi
done

END_ALL=$(date +%s)
ELAPSED_ALL=$((END_ALL-START_ALL))

# 覆盖率审计（仅告警，不影响退出码）
echo ""
echo "覆盖率审计："
audit_coverage || true

echo "============================================"
echo "MULTIPLAYER CI: PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL  (${ELAPSED_ALL}s)"
if [ "$FAIL" -ne 0 ]; then
  echo "FAILED TESTS:$FAILLIST"
fi

# 可选 JUnit XML
if [ -n "$JUNIT" ]; then
  mkdir -p "$(dirname "$JUNIT")"
  {
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    echo "<testsuites name=\"multiplayer\" tests=\"$TOTAL\" failures=\"$FAIL\" errors=\"0\" time=\"$ELAPSED_ALL\">"
    echo "  <testsuite name=\"multiplayer\" tests=\"$TOTAL\" failures=\"$FAIL\" errors=\"0\" time=\"$ELAPSED_ALL\">"
    echo "$JUNIT_CASES"
    echo "  </testsuite>"
    echo "</testsuites>"
  } > "$JUNIT"
  echo "JUnit report: $JUNIT"
fi

# 清理 APPDATA 临时目录
rm -rf "$APPDATA_DIR" 2>/dev/null

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
