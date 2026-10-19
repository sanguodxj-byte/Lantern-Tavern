@echo off
rem CI-portable launcher (2026-08-07): driven by env vars with local defaults.
if "%GODOT_EXE%"=="" set GODOT_EXE=D:\123\Godot_v4.7-stable_mono_win64.exe
if "%PROJECT_DIR%"=="" set PROJECT_DIR=D:\123\Lantern Tavern
if "%ITEST_DIR%"=="" set ITEST_DIR=%PROJECT_DIR%\.tmp_itest_dedsrv
set ITEST_ROLE=client
set DS_PORT=%DS_PORT%
if "%DS_PORT%"=="" set DS_PORT=30021
set APPDATA=%PROJECT_DIR%\.tmp_apdata_dedsrv_cli
start "" /min cmd /c ""%GODOT_EXE%" --headless --path "%PROJECT_DIR%" "%PROJECT_DIR%\tests\integration\mp_dedicated_server_test.tscn" > "%ITEST_DIR%\client.log" 2>&1"
