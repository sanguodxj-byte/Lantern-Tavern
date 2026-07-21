@echo off
cd /d "d:\123\Lantern Tavern"
"D:\123\Godot_v4.7-stable_mono_win64.exe" --editor --quit > rebuild_output.txt 2>&1
echo REBUILD_DONE_EXIT_CODE=%ERRORLEVEL%
