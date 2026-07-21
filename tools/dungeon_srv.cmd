@echo off
set ITEST_ROLE=host
set ITEST_DIR=D:\123\Lantern Tavern\.tmp_itest_dungeon
set APPDATA=D:/123/Lantern Tavern/.tmp_apdata_dungeon_srv
start "" /min cmd /c ""D:\123\Godot_v4.7-stable_mono_win64.exe" --headless --path "D:\123\Lantern Tavern" "D:\123\Lantern Tavern\tests\integration\mp_dungeon_test.tscn" > "D:\123\Lantern Tavern\.tmp_itest_dungeon\server.log" 2>&1"
