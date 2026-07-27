@echo off
setlocal
cd /d "D:\123\Lantern Tavern"

copy /Y project.godot project.godot.bak >nul 2>&1

powershell -NoProfile -Command "(Get-Content project.godot) -replace 'run/main_scene=\"res://scenes/ui/main_menu.tscn\"', 'run/main_scene=\"res://tools/ui_runtime_capture_world.tscn\"' | Set-Content project.godot"

echo --- CWD: %CD% ---
"D:\123\Godot_v4.7-stable_mono_win64.exe" --rendering-driver opengl3 --resolution 1920x1080 --path "%CD%" > ui_capture.out.log 2> ui_capture.err.log
set RC=%errorlevel%

move /Y project.godot.bak project.godot >nul 2>&1

echo --- exit %RC% ---
exit /b %RC%
