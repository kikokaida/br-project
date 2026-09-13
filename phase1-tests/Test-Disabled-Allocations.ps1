[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceRoot,
      [Parameter(Mandatory=$true)][string]$WorkDir,
      [Parameter(Mandatory=$true)][string]$LogsDir)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$Br1Fixture = Join-Path $PSScriptRoot 'disabled_no_allocations.cpp'
$Br1Recorder = Join-Path $SourceRoot 'source\blender\blenlib\intern\br1_diagnostics.cc'
$Br1Include = Join-Path $SourceRoot 'source\blender\blenlib'
$Br1Executable = Join-Path $WorkDir 'disabled_no_allocations.exe'
$Br1SavedFlag = $env:BR1_DIAG
try {
    Push-Location $WorkDir
    try {
        cl /nologo /std:c++17 /EHsc /MD /O2 "/I$Br1Include" $Br1Fixture $Br1Recorder "/Fe:$Br1Executable"
        if ($LASTEXITCODE -ne 0) { throw 'Compile disabled-profiler allocation regression failed.' }
    } finally { Pop-Location }
    $env:BR1_DIAG = '0'
    & $Br1Executable 2>&1 | Tee-Object -FilePath (Join-Path $LogsDir 'DISABLED_ALLOCATIONS.log')
    $Br1ExitCode = $LASTEXITCODE
    @{ status = if ($Br1ExitCode -eq 0) { 'PASS' } else { 'FAIL' }; exit_code = $Br1ExitCode } |
        ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $LogsDir 'DISABLED_ALLOCATIONS.json')
    if ($Br1ExitCode -ne 0) { throw 'Disabled profiler unexpectedly allocated heap storage.' }
} finally { $env:BR1_DIAG = $Br1SavedFlag }
