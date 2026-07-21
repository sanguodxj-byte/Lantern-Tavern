# Lantern Tavern — full gdUnit4 unit/integration suite
#
# Notes:
# - Full suite contains ~246 test files; some non-dungeon legacy suites may still fail.
# - Navigation mesh baking is skipped under headless DisplayServer for engine stability.
# - Prefer run_dungeon_tests.ps1 as the refactor merge gate.
#
# Exit codes follow gdUnit4 / run_ci.ps1 conventions.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\run_full_tests.ps1
#   powershell -ExecutionPolicy Bypass -File .\run_full_tests.ps1 -GodotPath "D:\123\Godot_v4.7-stable_mono_win64.exe"

param(
	[string]$GodotPath = "D:\123\Godot_v4.7-stable_mono_win64.exe"
)

$ErrorActionPreference = "Stop"
$PROJECT = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $GodotPath)) {
	Write-Error "Godot executable not found: $GodotPath"
	exit 2
}

Write-Host "==== Full gdUnit4 suite: tests/gdunit/ ====" -ForegroundColor Cyan
& $GodotPath --headless -s "tests/gdunit4_runner.gd" -- --ignoreHeadlessMode -a "tests/gdunit/"
$code = $LASTEXITCODE

if ($code -eq 0) {
	Write-Host "Full suite PASSED (0 failures, 0 orphans)." -ForegroundColor Green
	exit 0
}
elseif ($code -eq 101) {
	Write-Warning "Full suite assertions passed but orphan leaks detected (exit 101)."
	exit 0
}
elseif ($code -eq 3221225477 -or $code -lt 0) {
	Write-Error "Full suite aborted by native crash (exit $code). Use run_dungeon_tests.ps1 for stable refactor gate, then bisect remaining legacy suites."
	exit $code
}
else {
	Write-Error "Full suite FAILED with exit code $code"
	exit $code
}
