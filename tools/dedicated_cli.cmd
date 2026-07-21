@echo off
set ITEST_ROLE=client
set ITEST_DIR=D:\123\Lantern Tavern\.tmp_itest_dedsrv
set DS_PORT=%DS_PORT%
if "%DS_PORT%"=="" set DS_PORT=30021
set APPDATA=D:/123/Lantern Tavern/.tmp_apdata_dedsrv_cli
start "" /min cmd /c ""D:\123\Godot_v4.7-stable_mono_win64.exe" --headless --path "D:\123\Lantern Tavern" "D:\123\Lantern Tavern\tests\integration\mp_dedicated_server_test.tscn" > "D:\123\Lantern Tavern\.tmp_itest_dedsrv\client.log" 2>&1"
