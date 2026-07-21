# ⑫ Dedicated Server 集成测试（真实 ENet，双进程：专用服务器 + 真实客户端）。
# 专用服务器进程加载 scenes/multiplayer/dedicated_server.tscn（本身非玩家）；
# 客户端进程连专用服务器、spawn、验证地牢重建/实体复制/服务器权威移动闭环。
# 用法：powershell -ExecutionPolicy Bypass -File tools/run_dedicated_server_test.ps1

$PROJ = "D:\123\Lantern Tavern"
$ITDIR = "$PROJ\.tmp_itest_dedsrv"
$SRV_CMD = "$PROJ\tools\dedicated_srv.cmd"
$CLI_CMD = "$PROJ\tools\dedicated_cli.cmd"
$PORT = 30021

if (Test-Path $ITDIR) { Remove-Item -Recurse -Force $ITDIR }
New-Item -ItemType Directory -Force -Path $ITDIR | Out-Null

# 清理残留 Godot 进程（靠独立 APPDATA + 固定端口规避争用）
taskkill /F /IM "Godot_v4.7-stable_mono_win64.exe" 2>$null
Start-Sleep -Seconds 3

# ---- 专用服务器进程 ----
$env:DS_PORT = $PORT
& cmd.exe /c $SRV_CMD
Write-Host "dedicated server launched (port $PORT)"

$serverReady = $false
for ($i=0; $i -lt 60; $i++) {
  if (Test-Path "$ITDIR/ds_ready.txt") { $serverReady = $true; break }
  Start-Sleep -Seconds 1
}
if (-not $serverReady) {
  Write-Host "DEDICATED SERVER FAILED TO START (no ds_ready.txt)"
  Write-Host "--- server.log ---"; Get-Content "$ITDIR/server.log" -Tail 60
  taskkill /F /IM "Godot_v4.7-stable_mono_win64.exe" 2>$null
  exit 1
}
Write-Host "dedicated server ready: $(Get-Content "$ITDIR/ds_ready.txt")"

# ---- 客户端进程 ----
$env:DS_PORT = $PORT
& cmd.exe /c $CLI_CMD
Write-Host "client launched"

$clientDone = $false
for ($i=0; $i -lt 240; $i++) {
  if (Test-Path "$ITDIR/client_ok.txt") { $clientDone = $true; break }
  Start-Sleep -Seconds 1
}
Write-Host "client done: $clientDone"

$DS_RES = if (Test-Path "$ITDIR/ds_ready.txt") { Get-Content "$ITDIR/ds_ready.txt" } else { "MISSING" }
$DSSEED = if (Test-Path "$ITDIR/ds_seed.txt") { Get-Content "$ITDIR/ds_seed.txt" } else { "MISSING" }
$CLI_RES = if (Test-Path "$ITDIR/client_ok.txt") { Get-Content "$ITDIR/client_ok.txt" } else { "MISSING" }
$DUN_RES = if (Test-Path "$ITDIR/client_dungeon.txt") { Get-Content "$ITDIR/client_dungeon.txt" } else { "MISSING" }
$ENT_RES = if (Test-Path "$ITDIR/client_entities.txt") { Get-Content "$ITDIR/client_entities.txt" } else { "MISSING" }
$MOV_RES = if (Test-Path "$ITDIR/client_move.txt") { Get-Content "$ITDIR/client_move.txt" } else { "MISSING" }
Write-Host "DEDICATED SERVER: $DS_RES"
Write-Host "SERVER SEED/FP:    $DSSEED"
Write-Host "CLIENT: $CLI_RES"
Write-Host "DUNGEON SYNC: $DUN_RES"
Write-Host "ENTITIES: $ENT_RES"
Write-Host "MOVEMENT: $MOV_RES"

$SERVER_ERR = (Get-Content "$ITDIR/server.log" | Where-Object { $_ -match "SCRIPT ERROR" } | Measure-Object).Count

$VERDICT_FILE = "$PROJ\.ittest_dedsrv_verdict.txt"
$pass = ($DS_RES -like "OK*" -and $CLI_RES -like "OK*" -and $DUN_RES -like "*fp_match=True*" -and $ENT_RES -like "*ent_ok=True*" -and $MOV_RES -like "*moved=True*")
if ($pass -and $SERVER_ERR -eq 0) {
  Write-Host "DEDICATED SERVER TEST: PASS" | Tee-Object -FilePath $VERDICT_FILE
  Add-Content $VERDICT_FILE "ds=$DS_RES seed=$DSSEED client=$CLI_RES dungeon=$DUN_RES entities=$ENT_RES movement=$MOV_RES server_script_errors=$SERVER_ERR"
} else {
  Write-Host "DEDICATED SERVER TEST: FAIL" | Tee-Object -FilePath $VERDICT_FILE
  Add-Content $VERDICT_FILE "ds=$DS_RES seed=$DSSEED client=$CLI_RES dungeon=$DUN_RES entities=$ENT_RES movement=$MOV_RES server_script_errors=$SERVER_ERR"
  Copy-Item "$ITDIR/server.log" "$PROJ\.ittest_dedsrv_server.log" -Force -ErrorAction SilentlyContinue
  Copy-Item "$ITDIR/client.log" "$PROJ\.ittest_dedsrv_client.log" -Force -ErrorAction SilentlyContinue
}
Copy-Item "$ITDIR/server.log" "$PROJ\.ittest_dedsrv_server.log" -Force -ErrorAction SilentlyContinue
Copy-Item "$ITDIR/client.log" "$PROJ\.ittest_dedsrv_client.log" -Force -ErrorAction SilentlyContinue

taskkill /F /IM "Godot_v4.7-stable_mono_win64.exe" 2>$null
Remove-Item -Recurse -Force $ITDIR -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$PROJ/.tmp_apdata_dedsrv_srv" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$PROJ/.tmp_apdata_dedsrv_cli" -ErrorAction SilentlyContinue
exit 0
