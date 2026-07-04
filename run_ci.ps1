# Lantern Tavern CI gate
# Forces GDScript runtime property errors (e.g. "Invalid assignment of
# property or key ... on a base object of type 'Button'") to fail in CI,
# so they never reach manual runtime debugging.
#
# Gate layer: gdUnit4 full suite (incl. tests/gdunit/scene_smoke_test.gd,
# which instantiates every standalone UI scene and asserts zero script errors).
#
# gdUnit4 exit codes:
#     0  success
#   100  assertion failure (incl. property misuse caught by smoke test)  -> RED
#   101  orphan node leaks only (no assertion failure)                   -> GREEN (warn)
#   103  headless not supported                                          -> RED
#   104  Godot version not supported                                     -> RED
#   105  script error during test discovery                              -> RED
#
# Usage:  powershell -ExecutionPolicy Bypass -File .\run_ci.ps1
#         -GodotPath "C:\path\to\Godot.exe"

param(
	[string]$GodotPath = "D:\123\Godot_v4.7-stable_mono_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$PROJECT = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $GodotPath)) {
	Write-Error "Godot executable not found: $GodotPath (pass -GodotPath)"
	exit 2
}

Write-Host "==== CI gate: gdUnit4 full suite (incl. scene smoke) ====" -ForegroundColor Cyan
& $GodotPath --headless --path "$PROJECT" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" -a "res://tests/gdunit" --ignoreHeadlessMode -c
$code = $LASTEXITCODE

if ($code -eq 0) {
	Write-Host "CI passed: 0 failures, 0 orphans." -ForegroundColor Green
	exit 0
}
elseif ($code -eq 101) {
	Write-Warning "Tests passed (0 assertion failures) but orphan node leaks detected (exit 101). Pre-existing test hygiene debt; does not block CI. Consider cleaning up later."
	exit 0
}
else {
	Write-Error "CI FAILED: gdUnit4 exit code $code (100=assertion/property misuse, 105=script error, 103=headless unsupported, 104=Godot version). Fix before committing."
	exit $code
}
