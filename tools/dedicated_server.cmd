@echo off
REM ============================================================
REM  Lantern Tavern — 无头专用服务器 启动器（⑫）
REM  用法：
REM    tools\dedicated_server.cmd
REM    DS_PORT=30021 tools\dedicated_server.cmd
REM    DS_PORT=30021 DS_MAX_PLAYERS=12 tools\dedicated_server.cmd
REM  参数：环境变量优先，其次 --port= / --max-players= 命令行覆盖。
REM  日志：写 DS_LOG_DIR/dedicated.log（默认 .tmp_dedsrv_logs），同时 stdout。
REM ============================================================
setlocal
if "%DS_PORT%"=="" set DS_PORT=54321
if "%DS_MAX_PLAYERS%"=="" set DS_MAX_PLAYERS=8
if "%DS_IDLE_SHUTDOWN_SEC%"=="" set DS_IDLE_SHUTDOWN_SEC=0
if "%DS_LOG_DIR%"=="" set DS_LOG_DIR=D:\123\Lantern Tavern\.tmp_dedsrv_logs
if not exist "%DS_LOG_DIR%" mkdir "%DS_LOG_DIR%"
echo [dedicated_server] launching on port %DS_PORT% (max %DS_MAX_PLAYERS% players)
start "" /min cmd /c ""D:\123\Godot_v4.7-stable_mono_win64.exe" --headless --path "D:\123\Lantern Tavern" "D:\123\Lantern Tavern\scenes\multiplayer\dedicated_server.tscn" --port=%DS_PORT% --max-players=%DS_MAX_PLAYERS% --idle-shutdown=%DS_IDLE_SHUTDOWN_SEC% > "%DS_LOG_DIR%\stdout.log" 2>&1"
endlocal
