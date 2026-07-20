#Requires -Version 5.1
# Run all Hermes Home Server tests except Destructive
# Usage: .\tests\Run-Tests.ps1
# Option: -SkipIntegration  to skip docker backup tests

param(
    # skip Integration tag (docker backup.sh)
    [switch]$SkipIntegration,
    # verbose Pester output
    [switch]$Detailed
)

# stop on runner errors
$ErrorActionPreference = 'Stop'

# tests folder = this script directory
$testsDir = $PSScriptRoot
# project root
$projectRoot = Split-Path -Parent $testsDir
# module path for coverage
$modulePath = Join-Path $projectRoot 'modules\HermesHomeServer.psm1'

# require Pester 5+ (Windows may ship old 3.4.0)
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

# Pester 5/6 configuration
$config = New-PesterConfiguration
# test path
$config.Run.Path = $testsDir
# return result object
$config.Run.PassThru = $true
# exclude Destructive (restore / docker restart)
$exclude = @('Destructive')
# optional: also exclude Integration
if ($SkipIntegration) {
    $exclude += 'Integration'
}
$config.Filter.ExcludeTag = $exclude
# verbosity
if ($Detailed) {
    $config.Output.Verbosity = 'Detailed'
}
else {
    $config.Output.Verbosity = 'Normal'
}

# Code Coverage for .psm1 (Pester 6 requires JaCoCo or Cobertura)
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @($modulePath)
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = (Join-Path $env:TEMP 'hermes-pester-coverage.xml')

Write-Host ''
Write-Host 'Hermes Home Server - tests'
Write-Host '=========================='
Write-Host "Pester: $((Get-Module Pester).Version)"
Write-Host "ExcludeTag: $($exclude -join ', ')"
Write-Host ''

# run
$result = Invoke-Pester -Configuration $config

# counters
$passed = $result.PassedCount
$failed = $result.FailedCount
$skipped = $result.SkippedCount
$total = $result.TotalCount

Write-Host ''
Write-Host '----- Summary -----'
Write-Host "Total:   $total"
Write-Host "Passed:  $passed"
Write-Host "Failed:  $failed"
Write-Host "Skipped: $skipped"

# coverage percent (honest from result object)
$covPct = $null
if ($result.CodeCoverage) {
    if ($null -ne $result.CodeCoverage.CoveragePercent) {
        $covPct = [math]::Round($result.CodeCoverage.CoveragePercent, 1)
    }
    elseif ($result.CodeCoverage.NumberOfCommandsAnalyzed -gt 0) {
        $analyzed = $result.CodeCoverage.NumberOfCommandsAnalyzed
        $missed = $result.CodeCoverage.NumberOfCommandsMissed
        $hit = $analyzed - $missed
        $covPct = [math]::Round(100.0 * $hit / $analyzed, 1)
    }
}
if ($null -ne $covPct) {
    Write-Host "Coverage (HermesHomeServer.psm1): $covPct%"
}
else {
    Write-Host 'Coverage: not measured'
}

Write-Host ''
Write-Host 'Run: .\tests\Run-Tests.ps1'
Write-Host 'Without Integration: .\tests\Run-Tests.ps1 -SkipIntegration'
Write-Host 'Destructive restore: .\test-backup-restore.ps1 -AllowRestore'
Write-Host ''

# non-zero exit if failures
if ($failed -gt 0) {
    exit 1
}
exit 0