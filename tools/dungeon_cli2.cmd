@echo off
rem CI-portable launcher (2026-08-07): driven by env vars with local defaults.
if "%GODOT_EXE%"=="" set GODOT_EXE=D:\123\Godot_v4.7-stable_mono_win64.exe
if "%PROJECT_DIR%"=="" set PROJECT_DIR=D:\123\Lantern Tavern
if "%ITEST_DIR%"=="" set ITEST_DIR=%PROJECT_DIR%\.tmp_itest_dungeon
set ITEST_ROLE=client2
set APPDATA=%PROJECT_DIR%\.tmp_apdata_dungeon_cli2
start "" /min cmd /c ""%GODOT_EXE%" --headless --path "%PROJECT_DIR%" "%PROJECT_DIR%\tests\integration\mp_dungeon_test.tscn" > "%ITEST_DIR%\client2.log" 2>&1"
