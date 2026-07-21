$ErrorActionPreference = "Continue"
Set-Location "D:\123\Lantern Tavern"

$all = @{}
function Ingest-Log($path) {
	if (-not (Test-Path $path)) { return }
	Get-Content $path | ForEach-Object {
		if ($_ -match '^(PASS|FAIL|CRASH|OTHER|PASS_ORPHAN|TIMEOUT)\t') {
			$p = $_ -split "`t"
			if ($p.Count -ge 4) {
				$suite = $p[3]
				$cases = if ($p.Count -ge 6) { $p[5] } else { "" }
				$stats = if ($p.Count -ge 5) { $p[4] } else { "" }
				$all[$suite] = [pscustomobject]@{
					Status = $p[0]
					Exit = $p[1]
					Ms = $p[2]
					Suite = $suite
					Stats = $stats
					Cases = $cases
				}
			}
		}
	}
}

Ingest-Log "reports\all_gdunit_summary.log"
Ingest-Log "reports\all_gdunit_summary_tail2.log"
Ingest-Log "reports\all_gdunit_summary_last8.log"

# weak_monster crashed and may only be in tail2 as CRASH if recorded
$list = Get-Content "reports\all_gdunit_tests.txt" | Where-Object { $_ -and $_.Trim() -ne "" }
$missing = @()
foreach ($t in $list) {
	if (-not $all.ContainsKey($t)) { $missing += $t }
}

# If weak_monster missing but we know it crashed mid-run, mark it
if ($missing -contains "tests/gdunit/weak_monster_test.gd") {
	$all["tests/gdunit/weak_monster_test.gd"] = [pscustomobject]@{
		Status = "CRASH"; Exit = -1; Ms = 0; Suite = "tests/gdunit/weak_monster_test.gd"
		Stats = ""; Cases = "native_crash_or_abort"
	}
	$missing = @($missing | Where-Object { $_ -ne "tests/gdunit/weak_monster_test.gd" })
}
# voxel_enemy_scene crash recorded in main log already hopefully

$vals = @($all.Values)
$pass = @($vals | Where-Object { $_.Status -eq "PASS" }).Count
$orphan = @($vals | Where-Object { $_.Status -eq "PASS_ORPHAN" }).Count
$fail = @($vals | Where-Object { $_.Status -eq "FAIL" }).Count
$crash = @($vals | Where-Object { $_.Status -eq "CRASH" }).Count
$other = @($vals | Where-Object { $_.Status -eq "OTHER" }).Count
$timeout = @($vals | Where-Object { $_.Status -eq "TIMEOUT" }).Count

$summary = @(
	"COVERED=$($all.Count) TOTAL_LIST=$($list.Count) MISSING=$($missing.Count)",
	"PASS=$pass PASS_ORPHAN=$orphan FAIL=$fail CRASH=$crash OTHER=$other TIMEOUT=$timeout",
	"GREEN=$($pass+$orphan) RED=$($fail+$crash+$other+$timeout)"
)
$summary | ForEach-Object { Write-Host $_; $_ } | Out-File "reports\all_gdunit_final_summary.txt" -Encoding utf8

if ($missing.Count -gt 0) {
	"==== MISSING ====" | Out-File "reports\all_gdunit_final_summary.txt" -Append -Encoding utf8
	$missing | Out-File "reports\all_gdunit_final_summary.txt" -Append -Encoding utf8
}

$bad = @($vals | Where-Object { $_.Status -in @("FAIL","CRASH","OTHER","TIMEOUT") } | Sort-Object Suite)
"==== FAIL/CRASH/OTHER ($($bad.Count)) ====" | Out-File "reports\all_gdunit_final_failures.txt" -Encoding utf8
foreach ($b in $bad) {
	$line = "{0} | {1} | {2}" -f $b.Status, $b.Suite, $b.Cases
	Write-Host $line
	$line | Out-File "reports\all_gdunit_final_failures.txt" -Append -Encoding utf8
}

$vals | Sort-Object Suite | Export-Csv "reports\all_gdunit_final_results.csv" -NoTypeInformation -Encoding UTF8
Write-Host "Wrote final_summary / final_failures / final_results.csv"
