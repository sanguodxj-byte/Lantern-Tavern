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
#   101  orphan node leaks only (no assertion failure)                   -> RED（默认） / YELLOW（-AllowOrphan）
#   103  headless not supported                                          -> RED
#   104  Godot version not supported                                     -> RED
#   105  script error during test discovery                              -> RED
#
# P2-4（1417 审查）：orphan 默认 RED（严格门禁）。已知引擎级泄漏套件
# （terrain_texture_test 的 headless dummy-renderer RID 泄漏）通过 -AllowOrphan
# 显式豁免；逐套件审计用 tools/run_all_gdunit_batched.ps1（PASS_ORPHAN 归类）。
# -FailOnOrphan 保留为等价严格开关（兼容旧调用）。
#
# Usage:  powershell -ExecutionPolicy Bypass -File .\run_ci.ps1
#         -GodotPath "C:\path\to\Godot.exe" [-FailOnOrphan] [-AllowOrphan]

param(
	[string]$GodotPath = "D:\123\Godot_v4.7-stable_mono_win64_console.exe",
	[switch]$FailOnOrphan,
	[switch]$AllowOrphan,
	[switch]$RunIntegration
)

$ErrorActionPreference = "Stop"
$PROJECT = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $GodotPath)) {
	Write-Error "Godot executable not found: $GodotPath (pass -GodotPath)"
	exit 2
}

Write-Host "==== CI gate: editor headless scan (stderr 精确白名单) ====" -ForegroundColor Cyan
# P2-2（0304 审查）：退出码 0 不等于 stderr 干净——对已知引擎噪声做精确白名单，
# 白名单之外的 ERROR/SCRIPT ERROR 直接 RED（不得忽略所有 stderr）。
$KNOWN_NOISE = "EditorSettings not instantiated yet when getting setting"
$scanLog = & $GodotPath --headless --path "$PROJECT" --editor --quit 2>&1
$unexpectedStderr = $scanLog | Where-Object {
	$_ -match "ERROR|SCRIPT ERROR|Parse Error" -and $_ -notlike "*$KNOWN_NOISE*"
}
if ($unexpectedStderr) {
	Write-Error "EDITOR SCAN FAILED: stderr 含白名单外错误:`n$($unexpectedStderr -join "`n")"
	exit 1
}
Write-Host "Editor scan stderr clean (known noise allowlisted)." -ForegroundColor Green

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
	# P0-1（1727 审查）：不提前退出——-RunIntegration 集成分支必须可达。
	Write-Host "gdUnit suite passed: 0 failures, 0 orphans. Continuing to integration gate." -ForegroundColor Green
}
elseif ($code -eq 101) {
	if ($AllowOrphan) {
		# P2-4（1417 审查）：显式允许清单模式——已知引擎级泄漏
		# （terrain_texture_test 的 headless dummy-renderer RID 泄漏）豁免；
		# 逐套件审计请用 tools/run_all_gdunit_batched.ps1（PASS_ORPHAN 归类）。
		# P0-1（1727 审查）：不提前退出，继续到集成门禁。
		Write-Warning "Tests passed (0 assertion failures) but orphan node leaks detected (exit 101). ALLOWED via -AllowOrphan (known engine-level leak allowlist). Continuing to integration gate."
	}
	else {
		Write-Error "CI FAILED: orphan node leaks detected (exit 101). Orphan is RED by default (P2-4). If leaks come from the known engine-level allowlist, re-run with -AllowOrphan; audit per-suite via tools/run_all_gdunit_batched.ps1."
		exit 1
	}
}
else {
	Write-Error "CI FAILED: gdUnit4 exit code $code (100=assertion/property misuse, 105=script error, 103=headless unsupported, 104=Godot version). Fix before committing."
	exit $code
}

# ============================================================
# P1-5（2251 审查）：真实双进程 ENet 集成门禁。
# 默认显式标记 NOT RUN——逻辑/场景测试绝不冒充网络验收；
# 网络可用环境必须传 -RunIntegration 执行 Listen + Dedicated 垂直切片。
# 注意：集成脚本会 taskkill 所有 Godot 进程，仅在隔离 CI 环境使用。
# ============================================================
if ($RunIntegration) {
	Write-Host "==== CI gate: real ENet integration (Listen + Dedicated) ====" -ForegroundColor Cyan
	& "$PROJECT\tools\run_integration_dungeon_test.ps1"
	if ($LASTEXITCODE -ne 0) {
		Write-Error "CI FAILED: Listen integration test exited $LASTEXITCODE."
		exit 1
	}
	& "$PROJECT\tools\run_dedicated_server_test.ps1"
	if ($LASTEXITCODE -ne 0) {
		Write-Error "CI FAILED: Dedicated server integration test exited $LASTEXITCODE."
		exit 1
	}
	Write-Host "Integration gates passed: Listen + Dedicated." -ForegroundColor Green
} else {
	Write-Warning "INTEGRATION GATE: NOT RUN — real ENet listen/dedicated tests skipped. In network-enabled CI, pass -RunIntegration (kills Godot processes; isolated runner only)."
}

Write-Host "CI passed: unit + smoke gates green." -ForegroundColor Green
