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
#   101  orphan node leaks only (no assertion failure)                   -> YELLOW (默认) / RED（-FailOnOrphan）
#   103  headless not supported                                          -> RED
#   104  Godot version not supported                                     -> RED
#   105  script error during test discovery                              -> RED
#
# 架构审查 P2-5：orphan 不再无条件转 GREEN。默认 YELLOW（warn）兼容存量泄漏套件；
# 传入 -FailOnOrphan 时 101 直接 RED——新测试/干净基线的严格门禁必须用该开关，
# 存量泄漏套件清单见 tools/run_all_gdunit_batched.ps1（逐套件识别 PASS_ORPHAN）。
#
# Usage:  powershell -ExecutionPolicy Bypass -File .\run_ci.ps1
#         -GodotPath "C:\path\to\Godot.exe" [-FailOnOrphan]

param(
	[string]$GodotPath = "D:\123\Godot_v4.7-stable_mono_win64_console.exe",
	[switch]$FailOnOrphan
)

$ErrorActionPreference = "Stop"
$PROJECT = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $GodotPath)) {
	Write-Error "Godot executable not found: $GodotPath (pass -GodotPath)"
	exit 2
}

Write-Host "==== CI gate: export presets parse/recognize check ====" -ForegroundColor Cyan
# 平台交付基线（架构审查 P0-7）：目标平台必须可版本化复现。
# 无模板机器上 export 必然报缺模板（"due to configuration errors" + 模板路径），
# 属预期环境限制（WARN 不拦）；本门禁只校验 preset 被编辑器正确【识别】，
# 若 preset 名字写错/配置损坏（Unknown preset / Failed to load preset）则 RED。
function Test-ExportPresetRecognized([string]$presetName) {
	$log = & $GodotPath --headless --path "$PROJECT" --export-debug $presetName "$env:TEMP\lt_ci_export_test.bin" 2>&1
	$fatal = $log | Select-String -Pattern "Unknown preset|Failed to load preset|Invalid preset name"
	if ($fatal) {
		return $false
	}
	return $true
}
$presetsOk = $true
foreach ($presetName in @("Web", "Windows Desktop", "Android")) {
	if (-not (Test-ExportPresetRecognized $presetName)) {
		Write-Error "EXPORT PRESET GATE FAILED: preset '$presetName' was not recognized by the editor."
		$presetsOk = $false
	}
}
if (-not $presetsOk) {
	exit 2
}
Write-Host "Export presets gate passed: Web / Windows Desktop / Android recognized." -ForegroundColor Green

Write-Host "==== CI gate: gdUnit4 full suite (incl. scene smoke) ====" -ForegroundColor Cyan
& $GodotPath --headless --path "$PROJECT" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" -a "res://tests/gdunit" --ignoreHeadlessMode -c
$code = $LASTEXITCODE

if ($code -eq 0) {
	Write-Host "CI passed: 0 failures, 0 orphans." -ForegroundColor Green
	exit 0
}
elseif ($code -eq 101) {
	if ($FailOnOrphan) {
		Write-Error "CI FAILED: orphan node leaks detected (exit 101) and -FailOnOrphan is set. Orphan leaks are RED in strict mode."
		exit 1
	}
	Write-Warning "Tests passed (0 assertion failures) but orphan node leaks detected (exit 101). Pre-existing test hygiene debt; does not block CI in default mode. Use -FailOnOrphan for strict gates (P2-5)."
	exit 0
}
else {
	Write-Error "CI FAILED: gdUnit4 exit code $code (100=assertion/property misuse, 105=script error, 103=headless unsupported, 104=Godot version). Fix before committing."
	exit $code
}
