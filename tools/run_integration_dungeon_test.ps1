# 双进程 ENet 集成测试（真实地牢 + 真实 Player + 服务器权威移动同步垂直切片）。
# Host 与 Client 加载【同一场景】，靠 ITEST_ROLE 区分。
# 环境无 bash；PowerShell 5.1 的 Start-Process 在本机存在 PATH/Path/path 大小写冲突坑，
# 故改为经 .cmd 启动器（内部用 start 后台 godot），彻底绕开 Start-Process 的环境字典冲突。
# 用法：powershell -ExecutionPolicy Bypass -File tools/run_integration_dungeon_test.ps1

$PROJ = "D:\123\Lantern Tavern"
$ITDIR = "$PROJ\.tmp_itest_dungeon"
$SRV_CMD = "$PROJ\tools\dungeon_srv.cmd"
$CLI_CMD = "$PROJ\tools\dungeon_cli.cmd"
$CLI2_CMD = "$PROJ\tools\dungeon_cli2.cmd"

if (Test-Path $ITDIR) { Remove-Item -Recurse -Force $ITDIR }
New-Item -ItemType Directory -Force -Path $ITDIR | Out-Null

# 清理残留 Godot 进程（本沙箱 taskkill 常杀不掉，靠独立 APPDATA + 端口重试规避争用）
taskkill /F /IM "Godot_v4.7-stable_mono_win64.exe" 2>$null
Start-Sleep -Seconds 3

# ---- 服务器进程（ITEST_ROLE=host）----
& cmd.exe /c $SRV_CMD
Write-Host "server launched"

$serverReady = $false
for ($i=0; $i -lt 60; $i++) {
  if (Test-Path "$ITDIR/server_ready.txt") { $serverReady = $true; break }
  Start-Sleep -Seconds 1
}
if (-not $serverReady) {
  Write-Host "SERVER FAILED TO START (no server_ready.txt)"
  Write-Host "--- server.log ---"; Get-Content "$ITDIR/server.log" -Tail 50
  taskkill /F /IM "Godot_v4.7-stable_mono_win64.exe" 2>$null
  exit 1
}
Write-Host "server ready: $(Get-Content "$ITDIR/server_ready.txt")"

# ---- 客户端1进程（ITEST_ROLE=client）----
& cmd.exe /c $CLI_CMD
Write-Host "client1 launched"

# 等待 client1 完成初始建图（client_ready），再晚到启动 client2（真实场景恢复验证）。
$clientReady = $false
for ($i=0; $i -lt 120; $i++) {
  if (Test-Path "$ITDIR/client_ready.txt") { $clientReady = $true; break }
  if (Test-Path "$ITDIR/client_ok.txt") { $clientReady = $true; break }
  Start-Sleep -Seconds 1
}
Write-Host "client1 ready for late-join: $clientReady"

# ---- 客户端2进程（ITEST_ROLE=client2，晚到/重连恢复）----
& cmd.exe /c $CLI2_CMD
Write-Host "client2 (late join) launched"

# 等待 client1 最终判定 + client2 恢复判定
$clientDone = $false
$client2Done = $false
for ($i=0; $i -lt 240; $i++) {
  if (Test-Path "$ITDIR/client_ok.txt") { $clientDone = $true }
  if (Test-Path "$ITDIR/client2_recovery.txt") { $client2Done = $true }
  if ($clientDone -and $client2Done) { break }
  Start-Sleep -Seconds 1
}

$SRV_RES = if (Test-Path "$ITDIR/server_ok.txt") { Get-Content "$ITDIR/server_ok.txt" } else { "MISSING" }
$CLI_RES = if (Test-Path "$ITDIR/client_ok.txt") { Get-Content "$ITDIR/client_ok.txt" } else { "MISSING" }
$SEED_RES = if (Test-Path "$ITDIR/client_dungeon.txt") { Get-Content "$ITDIR/client_dungeon.txt" } else { "MISSING" }
$MOV_RES = if (Test-Path "$ITDIR/client_move_ok.txt") { Get-Content "$ITDIR/client_move_ok.txt" } else { "MISSING" }
$ENT_RES = if (Test-Path "$ITDIR/client_entities.txt") { Get-Content "$ITDIR/client_entities.txt" } else { "MISSING" }
$COM_RES = if (Test-Path "$ITDIR/client_combat.txt") { Get-Content "$ITDIR/client_combat.txt" } else { "MISSING" }
$LOOT_RES = if (Test-Path "$ITDIR/client_loot.txt") { Get-Content "$ITDIR/client_loot.txt" } else { "MISSING" }
$EXT_RES = if (Test-Path "$ITDIR/client_extract.txt") { Get-Content "$ITDIR/client_extract.txt" } else { "MISSING" }
$REC_RES = if (Test-Path "$ITDIR/client2_recovery.txt") { Get-Content "$ITDIR/client2_recovery.txt" } else { "MISSING" }
$SP_RES = if (Test-Path "$ITDIR/server_port.txt") { Get-Content "$ITDIR/server_port.txt" } else { "?" }
$CP_RES = if (Test-Path "$ITDIR/client_port.txt") { Get-Content "$ITDIR/client_port.txt" } else { "?" }
Write-Host "SERVER: $SRV_RES (port $SP_RES)"
Write-Host "CLIENT: $CLI_RES (port $CP_RES)"
Write-Host "DUNGEON SYNC: $SEED_RES"
Write-Host "MOVEMENT: $MOV_RES"
Write-Host "ENTITIES: $ENT_RES"
Write-Host "COMBAT: $COM_RES"
Write-Host "LOOT: $LOOT_RES"
Write-Host "EXTRACT: $EXT_RES"
Write-Host "RECOVERY: $REC_RES"

$VERDICT_FILE = "$PROJ\.ittest_dungeon_verdict.txt"
if ($SRV_RES -like "OK*" -and $CLI_RES -like "OK*" -and $SEED_RES -like "*seed_match=True*" -and $MOV_RES -like "OK*" -and $ENT_RES -like "*ent_ok=True*" -and $COM_RES -like "*combat_ok=True*" -and $LOOT_RES -like "*loot_ok=True*" -and $EXT_RES -like "*extract_ok=True*" -and $REC_RES -like "*ok=True*") {
  Write-Host "INTEGRATION DUNGEON TEST: PASS" | Tee-Object -FilePath $VERDICT_FILE
  Add-Content $VERDICT_FILE "server=$SRV_RES client=$CLI_RES dungeon=$SEED_RES move=$MOV_RES entities=$ENT_RES combat=$COM_RES loot=$LOOT_RES extract=$EXT_RES recovery=$REC_RES port_srv=$SP_RES port_cli=$CP_RES"
} else {
  Write-Host "INTEGRATION DUNGEON TEST: FAIL" | Tee-Object -FilePath $VERDICT_FILE
  Add-Content $VERDICT_FILE "server=$SRV_RES client=$CLI_RES dungeon=$SEED_RES move=$MOV_RES entities=$ENT_RES combat=$COM_RES loot=$LOOT_RES extract=$EXT_RES recovery=$REC_RES port_srv=$SP_RES port_cli=$CP_RES"
  Copy-Item "$ITDIR/server.log" "$PROJ\.ittest_dungeon_server.log" -Force -ErrorAction SilentlyContinue
  Copy-Item "$ITDIR/client.log" "$PROJ\.ittest_dungeon_client.log" -Force -ErrorAction SilentlyContinue
  Copy-Item "$ITDIR/client2.log" "$PROJ\.ittest_dungeon_client2.log" -Force -ErrorAction SilentlyContinue
}
# 保留完整日志便于排查
Copy-Item "$ITDIR/server.log" "$PROJ\.ittest_dungeon_server.log" -Force -ErrorAction SilentlyContinue
Copy-Item "$ITDIR/client.log" "$PROJ\.ittest_dungeon_client.log" -Force -ErrorAction SilentlyContinue
Copy-Item "$ITDIR/client2.log" "$PROJ\.ittest_dungeon_client2.log" -Force -ErrorAction SilentlyContinue

taskkill /F /IM "Godot_v4.7-stable_mono_win64.exe" 2>$null

Remove-Item -Recurse -Force $ITDIR -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$PROJ/.tmp_apdata_dungeon_srv" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$PROJ/.tmp_apdata_dungeon_cli" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$PROJ/.tmp_apdata_dungeon_cli2" -ErrorAction SilentlyContinue
exit 0
