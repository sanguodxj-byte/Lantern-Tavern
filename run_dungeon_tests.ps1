# Lantern Tavern - dungeon refactor focused test gate
# Exit: 0 green, 101 orphans-only treated as pass, other = fail
param(
	[string]$GodotPath = "D:\123\Godot_v4.7-stable_mono_win64.exe"
)

$ErrorActionPreference = "Continue"
$PROJECT = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $PROJECT

if (-not (Test-Path $GodotPath)) {
	Write-Host "Godot not found: $GodotPath"
	exit 2
}

$suites = @(
	"tests/gdunit/dungeon_generation_config_test.gd",
	"tests/gdunit/dungeon_generation_determinism_test.gd",
	"tests/gdunit/dungeon_generator_test.gd",
	"tests/gdunit/dungeon_layout_test.gd",
	"tests/gdunit/dungeon_layout_snapshot_test.gd",
	"tests/gdunit/dungeon_connectivity_validator_test.gd",
	"tests/gdunit/dungeon_hazard_planner_test.gd",
	"tests/gdunit/hazard_anchor_generation_test.gd",
	"tests/gdunit/dungeon_spawn_planner_test.gd",
	"tests/gdunit/dungeon_scene_builder_test.gd",
	"tests/gdunit/dungeon_build_result_contract_test.gd",
	"tests/gdunit/dungeon_streaming_controller_test.gd",
	"tests/gdunit/dungeon_streaming_physics_test.gd",
	"tests/gdunit/dungeon_streaming_config_test.gd",
	"tests/gdunit/dungeon_runtime_test.gd",
	"tests/gdunit/dungeon_runtime_config_test.gd",
	"tests/gdunit/dungeon_rendering_config_test.gd",
	"tests/gdunit/dungeon_terrain_config_test.gd",
	"tests/gdunit/dungeon_terrain_generation_rules_test.gd",
	"tests/gdunit/procedural_dungeon_architecture_integration_test.gd",
	"tests/gdunit/procedural_dungeon_runtime_integration_test.gd",
	"tests/gdunit/full_flow_integration_test.gd",
	"tests/gdunit/dungeon_interaction_test.gd",
	"tests/gdunit/dark_erosion_dungeon_test.gd",
	"tests/gdunit/torch_optimization_test.gd",
	"tests/gdunit/network_manager_test.gd"
)

$argList = @("--headless", "-s", "tests/gdunit4_runner.gd", "--", "--ignoreHeadlessMode")
foreach ($s in $suites) {
	$argList += @("-a", $s)
}

Write-Host "==== Dungeon refactor suite ($($suites.Count) files) ===="
& $GodotPath @argList
$code = $LASTEXITCODE
Write-Host "gdUnit exit code: $code"

if ($code -eq 0) {
	Write-Host "Dungeon suite PASSED"
	exit 0
}
if ($code -eq 101) {
	Write-Host "Dungeon suite PASS with orphans (exit 101)"
	exit 0
}
Write-Host "Dungeon suite FAILED exit $code"
exit $code
