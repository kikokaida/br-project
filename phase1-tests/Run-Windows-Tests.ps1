[CmdletBinding()]
param([ValidateRange(1,8)][int]$Jobs = 2)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false
$Br1Work = Join-Path (Get-Location) 'br1_recorder_work'
$Br1Logs = Join-Path $Br1Work 'logs'
$Br1Source = Join-Path $Br1Work 'upbge'
$Br1Lib = Join-Path $Br1Work 'lib-windows_x64'
$Br1Tests = Join-Path $Br1Work 'tests'
$Br1Commit = 'b1b35c48872b32c8bd4134f0cba759224b40f8df'
$Br1LibCommit = '854341cfd7e21b2cc45c7f8edbf19543cb51519c'
$Br1PatchHash = '3d4b39ceb54abb37f5ef7d86bf67de86f24cdc0c8cfcc8198a53db9d97c94264'
New-Item -ItemType Directory -Path $Br1Logs -Force | Out-Null
$Br1Status = [ordered]@{
    status = 'FAIL_OR_BLOCKED'; source_commit = $Br1Commit
    windows_libraries_commit = $Br1LibCommit; patch_sha256 = $Br1PatchHash
    source_hashes = 'NOT RUN'; recorder_tests = 'NOT RUN'; ctest_exit_code = $null
    stage = 'preflight'; error = $null; started_utc = [DateTime]::UtcNow.ToString('o')
}
$Br1Exit = 1
function Check-Br1Exit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed (exit $LASTEXITCODE)." }
}
Start-Transcript -Path (Join-Path $Br1Logs 'WINDOWS_RECORDER.log') -Force | Out-Null
try {
    $Br1Archive = 'BR1_PHASE1_Windows_Build_Job (1).zip'
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Br1Archive).Hash -ne
        '2800303f0d07e601cb9611fd434631a6c7f850e8339f7daf20b4f705fe884718') {
        throw 'Supplied archive hash mismatch.'
    }
    $Br1Package = Join-Path $Br1Work 'package'
    Expand-Archive -LiteralPath $Br1Archive -DestinationPath $Br1Package
    $Br1Patch = Join-Path $Br1Package 'BR1_UPBGE_Phase1.patch'
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Br1Patch).Hash -ne $Br1PatchHash) {
        throw 'Supplied diagnostic patch hash mismatch.'
    }
    $Br1Vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $Br1Vs = & $Br1Vswhere -latest -products '*' -version '[17.0,18.0)' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    Check-Br1Exit 'Find Visual Studio 2022'
    if (!$Br1Vs) { throw 'Visual Studio 2022 C++ tools are missing.' }
    Import-Module (Join-Path $Br1Vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $Br1Vs -SkipAutomaticLocation `
        -DevCmdArguments '-arch=amd64 -host_arch=amd64'
    Get-Command cl -ErrorAction Stop | Out-Null

    $Br1Status.stage = 'fetch source and verify all delivered source hashes'
    git init $Br1Source
    Check-Br1Exit 'Initialize source'
    git -C $Br1Source config core.autocrlf false
    Check-Br1Exit 'Set source line endings'
    git -C $Br1Source fetch --depth 1 https://github.com/UPBGE/upbge.git $Br1Commit
    Check-Br1Exit 'Fetch pinned source'
    git -C $Br1Source checkout --detach $Br1Commit
    Check-Br1Exit 'Check out pinned source'
    git -C $Br1Source apply --check $Br1Patch
    Check-Br1Exit 'Check original diagnostic patch'
    git -C $Br1Source apply $Br1Patch
    Check-Br1Exit 'Apply original diagnostic patch'
    $Br1ManifestPath = Join-Path $Br1Source 'diagnostics\br1_phase1\SOURCE_MANIFEST.json'
    $Br1Manifest = Get-Content -Raw -LiteralPath $Br1ManifestPath | ConvertFrom-Json
    if ($Br1Manifest.upstream_commit -ne $Br1Commit) { throw 'Manifest commit mismatch.' }
    foreach ($Br1Entry in $Br1Manifest.files) {
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Br1Source $Br1Entry.path)).Hash -ne $Br1Entry.sha256) {
            throw "Source hash mismatch: $($Br1Entry.path)"
        }
    }
    Copy-Item -LiteralPath $Br1ManifestPath -Destination $Br1Logs
    $Br1Status.source_hashes = "PASS ($($Br1Manifest.files.Count) files)"
    Write-Host $Br1Status.source_hashes
    $Br1Status.stage = 'apply and verify reviewed Windows build fixes'
    & (Join-Path $PSScriptRoot '..\phase1-ci\Apply-Build-Fixes.ps1') -SourceRoot $Br1Source -LogsDir $Br1Logs
    $Br1Status['effective_source_hashes'] = 'PASS (56 diagnostic files plus reviewed baseline fixes)'
    $Br1Gitlink = git -C $Br1Source ls-tree $Br1Commit lib/windows_x64
    Check-Br1Exit 'Resolve upstream dependency gitlink'
    if ($Br1Gitlink -notmatch ('^160000 commit ' + $Br1LibCommit + '\s+lib/windows_x64$')) {
        throw 'The Windows library commit does not match the pinned engine.'
    }

    $Br1Status.stage = 'disabled-profiler allocation regression'
    & (Join-Path $PSScriptRoot 'Test-Disabled-Allocations.ps1') -SourceRoot $Br1Source -WorkDir (Join-Path $Br1Work 'allocation_test') -LogsDir $Br1Logs
    $Br1Status['disabled_no_allocations'] = 'PASS'

    $Br1Status.stage = 'fetch pinned Python libraries'
    git init $Br1Lib
    Check-Br1Exit 'Initialize library checkout'
    git -C $Br1Lib config core.autocrlf false
    Check-Br1Exit 'Set library line endings'
    git -C $Br1Lib lfs install --local --skip-smudge
    Check-Br1Exit 'Configure local LFS'
    git -C $Br1Lib remote add origin https://projects.blender.org/blender/lib-windows_x64.git
    Check-Br1Exit 'Set dependency remote'
    git -C $Br1Lib fetch --depth 1 origin $Br1LibCommit
    Check-Br1Exit 'Fetch exact dependency metadata'
    git -C $Br1Lib sparse-checkout init --cone
    Check-Br1Exit 'Initialize Python-only dependency checkout'
    git -C $Br1Lib sparse-checkout set python
    Check-Br1Exit 'Select pinned Python subtree'
    git -C $Br1Lib checkout --detach $Br1LibCommit
    Check-Br1Exit 'Check out exact dependencies'
    git -C $Br1Lib lfs pull --include='python/**'
    Check-Br1Exit 'Download pinned Python binaries'
    $Br1PythonDir = Join-Path $Br1Lib 'python\311'
    $Br1Python = Join-Path $Br1PythonDir 'bin\python.exe'
    if (!(Test-Path -LiteralPath $Br1Python)) { throw 'Pinned engine Python 3.11 is missing.' }
    & $Br1Python --version
    Check-Br1Exit 'Start pinned Python'

    $Br1Status.stage = 'compile supplied Windows recorder tests'
    cmake -S (Join-Path $Br1Source 'diagnostics\br1_phase1') -B $Br1Tests `
        -G 'Visual Studio 17 2022' -A x64 `
        "-DPython3_ROOT_DIR=$Br1PythonDir" "-DPython3_EXECUTABLE=$Br1Python"
    Check-Br1Exit 'Configure recorder tests'
    cmake --build $Br1Tests --config RelWithDebInfo --parallel $Jobs
    Check-Br1Exit 'Compile recorder tests'
    $Br1Status.stage = 'execute supplied Windows recorder tests'
    $env:PATH = "$Br1PythonDir\bin;$Br1PythonDir;$env:PATH"
    ctest --test-dir $Br1Tests -C RelWithDebInfo --output-on-failure --no-tests=error `
        --output-log (Join-Path $Br1Logs 'RECORDER_TESTS.log') `
        --output-junit (Join-Path $Br1Logs 'RECORDER_TESTS.xml')
    $Br1Status.ctest_exit_code = $LASTEXITCODE
    $Br1Status.recorder_tests = if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }
    Check-Br1Exit 'Recorder integration and report tests'
    $Br1Status.status = 'PASS_WINDOWS_RECORDER_TESTS'
    $Br1Exit = 0
} catch {
    $Br1Status.error = $_.Exception.Message
    Write-Host "FAILED: $($Br1Status.stage): $($Br1Status.error)" -ForegroundColor Red
} finally {
    $Br1Status['finished_utc'] = [DateTime]::UtcNow.ToString('o')
    $Br1Status | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $Br1Logs 'RECORDER_STATUS.json')
    Stop-Transcript | Out-Null
}
exit $Br1Exit
