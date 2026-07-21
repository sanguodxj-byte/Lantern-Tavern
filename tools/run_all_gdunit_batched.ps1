param(
	[string]$GodotPath = "D:\123\Godot_v4.7-stable_mono_win64_console.exe",
	[string]$ListFile = "reports\all_gdunit_tests.txt",
	[string]$ResultCsv = "reports\all_gdunit_results.csv",
	[string]$SummaryLog = "reports\all_gdunit_summary.log",
	[string]$FailLog = "reports\all_gdunit_failures.log",
	[int]$StartIndex = 0,
	[int]$MaxCount = 0,
	[int]$TimeoutSec = 120,
	[switch]$Append
)

$ErrorActionPreference = "Continue"
$PROJECT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $PROJECT

if (-not (Test-Path $GodotPath)) {
	Write-Error "Godot not found: $GodotPath"
	exit 2
}
if (-not (Test-Path $ListFile)) {
	Get-ChildItem tests\gdunit -Filter '*_test.gd' -Recurse |
		Sort-Object FullName |
		ForEach-Object { $_.FullName.Replace((Get-Location).Path + '\', '').Replace('\', '/') } |
		Set-Content -Encoding utf8 $ListFile
}

$allTests = @(Get-Content $ListFile | Where-Object { $_ -and $_.Trim() -ne "" })
$tests = $allTests
if ($MaxCount -gt 0) {
	$end = [Math]::Min($allTests.Count, $StartIndex + $MaxCount) - 1
	if ($StartIndex -le $end) { $tests = $allTests[$StartIndex..$end] } else { $tests = @() }
} elseif ($StartIndex -gt 0) {
	$tests = $allTests[$StartIndex..($allTests.Count - 1)]
}

$results = New-Object System.Collections.Generic.List[object]
if ($Append -and (Test-Path $ResultCsv)) {
	try {
		Import-Csv $ResultCsv | ForEach-Object { $results.Add($_) | Out-Null }
	} catch {}
}

$pass = 0
$orphan = 0
$fail = 0
$crash = 0
$timeoutN = 0
$other = 0
$failDetails = New-Object System.Collections.Generic.List[string]

if (-not $Append -or -not (Test-Path $SummaryLog)) {
	"==== Batched gdUnit scan start $(Get-Date -Format o) ====" | Out-File -FilePath $SummaryLog -Encoding utf8
	"" | Out-File -FilePath $FailLog -Encoding utf8
}
"---- chunk start=$(Get-Date -Format o) index=$StartIndex count=$($tests.Count) timeout=${TimeoutSec}s ----" |
	Out-File -FilePath $SummaryLog -Append -Encoding utf8

$idx = 0
foreach ($t in $tests) {
	$idx++
	$absIdx = $StartIndex + $idx - 1
	$suiteLog = Join-Path $PROJECT "reports\_suite_tmp.log"
	$suiteErr = Join-Path $PROJECT "reports\_suite_tmp.err.log"
	if (Test-Path $suiteLog) { Remove-Item $suiteLog -Force -ErrorAction SilentlyContinue }
	if (Test-Path $suiteErr) { Remove-Item $suiteErr -Force -ErrorAction SilentlyContinue }

	Write-Host ("[{0}/{1}] (abs {2}) {3}" -f $idx, $tests.Count, $absIdx, $t)
	$sw = [System.Diagnostics.Stopwatch]::StartNew()

	$p = Start-Process -FilePath $GodotPath `
		-ArgumentList @("--headless", "--path", $PROJECT, "-s", "res://tests/gdunit4_runner.gd", "--", "--ignoreHeadlessMode", "-a", $t) `
		-WorkingDirectory $PROJECT `
		-NoNewWindow -PassThru `
		-RedirectStandardOutput $suiteLog `
		-RedirectStandardError $suiteErr

	$finished = $p.WaitForExit($TimeoutSec * 1000)
	$code = -999
	$timedOut = $false
	if (-not $finished) {
		$timedOut = $true
		try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
		Get-Process Godot* -ErrorAction SilentlyContinue | Where-Object {
			$_.StartTime -gt (Get-Date).AddMinutes(-10)
		} | Stop-Process -Force -ErrorAction SilentlyContinue
		Start-Sleep -Milliseconds 300
		$code = -1
	} else {
		$code = $p.ExitCode
		if ($null -eq $code) { $code = -998 }
	}

	$sw.Stop()
	$ms = [int]$sw.Elapsed.TotalMilliseconds

	$outText = ""
	if (Test-Path $suiteLog) {
		$outText = Get-Content $suiteLog -Raw -ErrorAction SilentlyContinue
	}
	if (Test-Path $suiteErr) {
		$errText = Get-Content $suiteErr -Raw -ErrorAction SilentlyContinue
		if ($errText) { $outText = $outText + "`n" + $errText }
	}
	$clean = if ($outText) { $outText -replace '\x1b\[[0-9;]*m', '' } else { "" }

	$hasCrash = $clean -match "CrashHandlerException|signal 11"
	$hasFailedCase = $clean -match ">\s*test_\S+\s+FAILED"
	$hasFailStats = $clean -match "\|\s*[1-9]\d*\s+failures" -or $clean -match "\|\s*[1-9]\d*\s+errors"
	$hasPassStats = $clean -match "Statistics:.*0 errors \| 0 failures"
	$hasOverallPass = $clean -match "Overall Summary:.*0 errors \| 0 failures"

	$status = "OTHER"
	if ($timedOut) {
		$status = "TIMEOUT"
		$timeoutN++
	} elseif ($hasCrash -or $code -eq 3221225477 -or ($code -lt 0 -and -not $hasPassStats)) {
		$status = "CRASH"
		$crash++
	} elseif ($hasFailedCase -or $hasFailStats -or $code -eq 100 -or $code -eq 105) {
		$status = "FAIL"
		$fail++
	} elseif ($code -eq 101 -or ($hasPassStats -and $clean -match "[1-9]\d*\s+orphans")) {
		$status = "PASS_ORPHAN"
		$orphan++
	} elseif ($code -eq 0 -or $hasPassStats -or $hasOverallPass) {
		$status = "PASS"
		$pass++
	} else {
		$status = "OTHER"
		$other++
	}

	$stats = ""
	$statMatches = [regex]::Matches($clean, "Statistics:\s*([^\r\n]+)")
	if ($statMatches.Count -gt 0) {
		$stats = $statMatches[$statMatches.Count - 1].Groups[1].Value.Trim()
	}

	$cases = @([regex]::Matches($clean, ">\s*(test_\S+)\s+FAILED") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
	$failedCases = if ($cases.Count -gt 0) { $cases -join ";" } else { "" }
	if (($status -eq "CRASH" -or $status -eq "TIMEOUT") -and $failedCases -eq "") {
		$failedCases = if ($status -eq "TIMEOUT") { "timeout_${TimeoutSec}s" } else { "native_crash_or_abort" }
	}

	if ($status -eq "FAIL" -or $status -eq "CRASH" -or $status -eq "TIMEOUT" -or $status -eq "OTHER") {
		$detailLines = New-Object System.Collections.Generic.List[string]
		$lines = $clean -split "`r?`n"
		for ($i = 0; $i -lt $lines.Count; $i++) {
			if ($lines[$i] -match ">\s*test_\S+\s+FAILED" -or $lines[$i] -match "CrashHandlerException" -or $lines[$i] -match "SCRIPT ERROR|Parse Error") {
				$end = [Math]::Min($lines.Count - 1, $i + 10)
				for ($j = $i; $j -le $end; $j++) {
					$detailLines.Add($lines[$j]) | Out-Null
					if ($j -gt $i -and ($lines[$j] -match "STARTED|Run Test Suite|Statistics:|Overall")) { break }
				}
				$detailLines.Add("") | Out-Null
			}
		}
		$detailSnippet = ($detailLines -join "`n")
		if ($detailSnippet.Trim() -eq "" -and $clean.Length -gt 0) {
			$tail = ($lines | Select-Object -Last 25) -join "`n"
			$detailSnippet = $tail
		}
		$block = "==== $t  status=$status exit=$code ms=$ms ====`n$detailSnippet`n"
		$block | Out-File -FilePath $FailLog -Append -Encoding utf8
		$failDetails.Add(("{0}`t{1}`t{2}`t{3}" -f $status, $code, $t, $failedCases)) | Out-Null
		Write-Host ("  -> {0} code={1} cases={2}" -f $status, $code, $failedCases)
	} else {
		Write-Host ("  -> {0} code={1} {2}ms" -f $status, $code, $ms)
	}

	$results.Add([pscustomobject]@{
		Index = $absIdx
		Suite = $t
		Status = $status
		ExitCode = $code
		Ms = $ms
		Stats = $stats
		FailedCases = $failedCases
	}) | Out-Null

	("{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $status, $code, $ms, $t, $stats, $failedCases) |
		Out-File -FilePath $SummaryLog -Append -Encoding utf8
}

$results | Export-Csv -Path $ResultCsv -NoTypeInformation -Encoding UTF8

"" | Out-File -FilePath $SummaryLog -Append -Encoding utf8
"==== CHUNK SUMMARY ====" | Out-File -FilePath $SummaryLog -Append -Encoding utf8
"PASS=$pass PASS_ORPHAN=$orphan FAIL=$fail CRASH=$crash TIMEOUT=$timeoutN OTHER=$other TOTAL=$($tests.Count)" |
	Out-File -FilePath $SummaryLog -Append -Encoding utf8
if ($failDetails.Count -gt 0) {
	"==== FAIL INDEX (chunk) ====" | Out-File -FilePath $SummaryLog -Append -Encoding utf8
	$failDetails | Out-File -FilePath $SummaryLog -Append -Encoding utf8
}

Write-Host "==== CHUNK SUMMARY ===="
Write-Host "PASS=$pass PASS_ORPHAN=$orphan FAIL=$fail CRASH=$crash TIMEOUT=$timeoutN OTHER=$other TOTAL=$($tests.Count)"
Write-Host "CSV=$ResultCsv LOG=$SummaryLog FAIL_LOG=$FailLog"
exit $(if (($fail + $crash + $timeoutN + $other) -gt 0) { 1 } else { 0 })
