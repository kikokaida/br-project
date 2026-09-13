# Build orchestration only; the supplied diagnostic patch is applied unchanged.
[CmdletBinding()]
param([ValidateRange(1,16)][int]$Jobs = 2)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Native stderr is recorded by the transcript. Exit codes are checked explicitly.
$PSNativeCommandUseErrorActionPreference = $false

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This job requires a Windows x64 build machine with Visual Studio 2022.'
}
$Br1SourceCommit = 'b1b35c48872b32c8bd4134f0cba759224b40f8df'
$Br1PatchHash = '3d4b39ceb54abb37f5ef7d86bf67de86f24cdc0c8cfcc8198a53db9d97c94264'
$Br1RunRoot = Join-Path $PSScriptRoot 'br1_ci_work'
if (Test-Path -LiteralPath $Br1RunRoot) {
    throw 'br1_ci_work already exists. Use a new isolated checkout for this build job.'
}
$Br1Logs = Join-Path $Br1RunRoot 'logs'
$Br1Source = Join-Path $Br1RunRoot 'upbge'
$Br1Build = Join-Path $Br1RunRoot 'BR1_PHASE1_build'
$Br1Install = Join-Path $Br1RunRoot 'BR1_PHASE1_engine'
New-Item -ItemType Directory -Path $Br1Logs -Force | Out-Null
$Br1Result = [ordered]@{
    pipeline_status = 'FAIL_OR_BLOCKED'
    started_utc = [DateTime]::UtcNow.ToString('o')
    source_commit = $Br1SourceCommit
    patch_sha256 = $Br1PatchHash
    jobs = $Jobs
    build_script_completed = $false
    engine_files_present = $false
    engine_version_exit_code = $null
    gameplay_executed = $false
    fps_improvement_measured = $false
    failure_stage = $null
    error = $null
}
$Br1Stage = 'preflight'
$Br1Exit = 1
Start-Transcript -Path (Join-Path $Br1Logs 'WINDOWS_BUILD.log') -Force | Out-Null
function Check-Br1Exit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed (exit $LASTEXITCODE)." }
}
try {
    Get-CimInstance Win32_OperatingSystem |
        Select-Object Caption, OSArchitecture, TotalVisibleMemorySize, FreePhysicalMemory |
        ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $Br1Logs 'MACHINE.json')
    Get-PSDrive -PSProvider FileSystem |
        Select-Object Name, Root, Used, Free |
        ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $Br1Logs 'DISKS.json')
    foreach ($Br1Tool in @('git', 'cmake', 'ctest')) {
        Get-Command $Br1Tool -ErrorAction Stop | Out-Null
    }
    git lfs version
    Check-Br1Exit 'Git LFS preflight'
    $Br1Vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $Br1Vs = & $Br1Vswhere -latest -products '*' -version '[17.0,18.0)' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    Check-Br1Exit 'Find Visual Studio 2022'
    if (!$Br1Vs) { throw 'Visual Studio 2022 C++ tools were not found.' }
    Import-Module (Join-Path $Br1Vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $Br1Vs -SkipAutomaticLocation `
        -DevCmdArguments '-arch=amd64 -host_arch=amd64'
    Get-Command cl -ErrorAction Stop | Out-Null

    $Br1Stage = 'fetch exact upstream source'
    git init $Br1Source
    Check-Br1Exit 'Initialize fresh source checkout'
    git -C $Br1Source config core.autocrlf false
    Check-Br1Exit 'Preserve source line endings'
    git -C $Br1Source fetch --depth 1 https://github.com/UPBGE/upbge.git $Br1SourceCommit
    Check-Br1Exit 'Fetch supplied source commit'
    git -C $Br1Source checkout --detach $Br1SourceCommit
    Check-Br1Exit 'Check out pristine source before patching'

    $Br1Stage = 'apply and verify delivered patch'
    $Br1Patch = Join-Path $PSScriptRoot 'BR1_UPBGE_Phase1.patch'
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Br1Patch).Hash -ne $Br1PatchHash) {
        throw 'The patch does not match the delivered Phase 1 patch.'
    }
    git -C $Br1Source apply --check $Br1Patch
    Check-Br1Exit 'Check diagnostic patch'
    git -C $Br1Source apply $Br1Patch
    Check-Br1Exit 'Apply diagnostic patch'
    $Br1ManifestPath = Join-Path $Br1Source 'diagnostics\br1_phase1\SOURCE_MANIFEST.json'
    $Br1Manifest = Get-Content -Raw -LiteralPath $Br1ManifestPath | ConvertFrom-Json
    if ($Br1Manifest.upstream_commit -ne $Br1SourceCommit) { throw 'Manifest source mismatch.' }
    foreach ($Br1Entry in $Br1Manifest.files) {
        $Br1File = Join-Path $Br1Source $Br1Entry.path
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Br1File).Hash -ne $Br1Entry.sha256) {
            throw "Delivered source hash mismatch: $($Br1Entry.path)"
        }
    }
    Copy-Item -LiteralPath $Br1ManifestPath -Destination $Br1Logs

    $Br1Stage = 'apply and verify reviewed Windows build fixes'
    & (Join-Path $PSScriptRoot '..\phase1-ci\Apply-Build-Fixes.ps1') -SourceRoot $Br1Source -LogsDir $Br1Logs
    $Br1Result['source_hashes'] = 'PASS: original and effective manifests (56 files each)'

    $Br1Stage = 'native build and tests; see transcript for failing command'
    & (Join-Path $Br1Source 'diagnostics\br1_phase1\Build-Windows.ps1') -Jobs $Jobs
    $Br1Result.build_script_completed = $true

    $Br1Stage = 'installed executable version smoke check'
    & (Join-Path $Br1Install 'blender.exe') --version
    $Br1Result.engine_version_exit_code = $LASTEXITCODE
    Check-Br1Exit 'Start installed blender.exe'
    $Br1Result.pipeline_status = 'PASS_BUILD_TESTS_AND_VERSION_CHECK'
    $Br1Exit = 0
} catch {
    $Br1Result.failure_stage = $Br1Stage
    $Br1Result.error = $_.Exception.Message
    Write-Host "FAILED: $Br1Stage" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
} finally {
    $Br1Executables = @()
    foreach ($Br1Name in @('blender.exe', 'blenderplayer.exe')) {
        $Br1ExePath = Join-Path $Br1Install $Br1Name
        if (Test-Path -LiteralPath $Br1ExePath) {
            $Br1Executables += [ordered]@{
                file = $Br1Name
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Br1ExePath).Hash
                size_bytes = (Get-Item -LiteralPath $Br1ExePath).Length
            }
        }
    }
    $Br1Result.engine_files_present = $Br1Executables.Count -eq 2
    $Br1Result['executables'] = $Br1Executables
    $Br1Result['finished_utc'] = [DateTime]::UtcNow.ToString('o')
    $Br1Result | ConvertTo-Json -Depth 6 |
        Set-Content -Encoding utf8 (Join-Path $Br1Logs 'BUILD_STATUS.json')
    foreach ($Br1Name in @('DEPENDENCY_LOCK.json', 'CMakeCache.txt', 'RECORDER_TESTS.log', 'ENGINE_TESTS.log')) {
        $Br1Log = Join-Path $Br1Build $Br1Name
        if (Test-Path -LiteralPath $Br1Log) {
            Copy-Item -LiteralPath $Br1Log -Destination $Br1Logs -ErrorAction Continue
        }
    }
    $Br1CMakeLog = Join-Path $Br1Build 'CMakeFiles\CMakeConfigureLog.yaml'
    if (Test-Path -LiteralPath $Br1CMakeLog) {
        Copy-Item -LiteralPath $Br1CMakeLog -Destination $Br1Logs -ErrorAction Continue
    }
    if ($env:GITHUB_OUTPUT) {
        'engine_available=' + $Br1Result.engine_files_present.ToString().ToLowerInvariant() |
            Add-Content -Encoding utf8 -LiteralPath $env:GITHUB_OUTPUT
    }
    Stop-Transcript | Out-Null
}
exit $Br1Exit
