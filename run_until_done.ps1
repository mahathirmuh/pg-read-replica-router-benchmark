# Auto-restart benchmark until all 150 runs complete
$resultsDir = "results"
$totalRuns = 150

Write-Host "=== Auto-restart Benchmark Wrapper ===" -ForegroundColor Cyan

while ($true) {
    $completed = (Get-ChildItem "$resultsDir\*.json" -ErrorAction SilentlyContinue).Count
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Completed: $completed / $totalRuns" -ForegroundColor Yellow

    if ($completed -ge $totalRuns) {
        Write-Host "All $totalRuns runs completed!" -ForegroundColor Green
        break
    }

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting benchmark..." -ForegroundColor Cyan
    python -m benchmark.run_all >> benchmark_error.log 2>&1

    $exitCode = $LASTEXITCODE
    $completed = (Get-ChildItem "$resultsDir\*.json" -ErrorAction SilentlyContinue).Count

    if ($completed -ge $totalRuns) {
        Write-Host "All $totalRuns runs completed!" -ForegroundColor Green
        break
    }

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Process exited (code=$exitCode), $completed/$totalRuns done. Restarting in 10s..." -ForegroundColor Red
    Start-Sleep -Seconds 10
}

Write-Host "Benchmark finished. Run: python show_summary.py" -ForegroundColor Green
