[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest
$Br1Root = [IO.Path]::GetFullPath('player_smoke')
$Br1Logs = Join-Path $Br1Root 'logs'
$Br1Fixture = Join-Path $Br1Root 'fixture'
New-Item -ItemType Directory -Path $Br1Logs,$Br1Fixture -Force | Out-Null
$Br1Status = [ordered]@{status='FAIL'; source_run='34782679996'; project_gameplay_executed=$false; synthetic_fixture=$true; stage='verify package'; error=$null}
$Br1Exit = 1
$Br1FixtureStarted = $false

function Invoke-Br1Process([string]$Executable, [string[]]$Arguments, [string]$Label, [string]$LogDir, [int]$TimeoutSeconds = 120) {
    $Br1Start = [Diagnostics.ProcessStartInfo]::new()
    $Br1Start.FileName = $Executable
    $Br1Start.WorkingDirectory = $Br1Fixture
    $Br1Start.UseShellExecute = $false
    $Br1Start.CreateNoWindow = $true
    $Br1Start.RedirectStandardOutput = $true
    $Br1Start.RedirectStandardError = $true
    foreach ($Br1Argument in $Arguments) { $Br1Start.ArgumentList.Add($Br1Argument) }
    $Br1Process = [Diagnostics.Process]::new()
    $Br1Process.StartInfo = $Br1Start
    if (!$Br1Process.Start()) { throw "Unable to start $Label" }
    $Br1Out = $Br1Process.StandardOutput.ReadToEndAsync()
    $Br1Err = $Br1Process.StandardError.ReadToEndAsync()
    $Br1Finished = $Br1Process.WaitForExit($TimeoutSeconds * 1000)
    if (!$Br1Finished) { $Br1Process.Kill($true); $Br1Process.WaitForExit() }
    [IO.File]::WriteAllText((Join-Path $LogDir ($Label + '.stdout.log')), $Br1Out.GetAwaiter().GetResult())
    [IO.File]::WriteAllText((Join-Path $LogDir ($Label + '.stderr.log')), $Br1Err.GetAwaiter().GetResult())
    $Br1Result = [ordered]@{label=$Label; exit_code=$Br1Process.ExitCode; timed_out=(!$Br1Finished); arguments=$Arguments}
    $Br1Result | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $LogDir ($Label + '.process.json'))
    $Br1Process.Dispose()
    foreach ($Br1Crash in @(Get-ChildItem -LiteralPath $env:TEMP -Filter '*crash*.txt' -File -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $Br1Crash.FullName -Destination (Join-Path $LogDir ($Label + '.' + $Br1Crash.Name))
    }
    if (!$Br1Finished) { throw "$Label timed out after $TimeoutSeconds seconds" }
    if ($Br1Result.exit_code -ne 0) { throw "$Label exited with $($Br1Result.exit_code)" }
}

try {
    $Br1Transfer = [IO.Path]::GetFullPath('engine_transfer')
    $Br1Manifest = Get-Content -Raw -LiteralPath (Join-Path $Br1Transfer 'PACKAGE_TRANSFER.json') | ConvertFrom-Json
    if ($Br1Manifest.source_run -ne '34782679996' -or $Br1Manifest.source_commit -ne 'b1b35c48872b32c8bd4134f0cba759224b40f8df') { throw 'Unexpected package provenance' }
    $Br1Zip = Join-Path $Br1Root 'engine.zip'
    $Br1Output = [IO.File]::Create($Br1Zip)
    try {
        $Br1ExpectedIndex = 0
        foreach ($Br1Part in $Br1Manifest.parts | Sort-Object index) {
            $Br1ExpectedIndex++
            if ($Br1Part.index -ne $Br1ExpectedIndex -or $Br1Part.filename -notmatch '^BR1_Phase1_Windows_x64\.zip\.part[0-9]{3}$') { throw 'Invalid transfer part sequence' }
            $Br1PartPath = Join-Path $Br1Transfer $Br1Part.filename
            if ((Get-Item $Br1PartPath).Length -ne $Br1Part.size_bytes -or (Get-FileHash $Br1PartPath -Algorithm SHA256).Hash -ne $Br1Part.sha256) { throw "Transfer part verification failed: $Br1PartPath" }
            $Br1Input = [IO.File]::OpenRead($Br1PartPath)
            try { $Br1Input.CopyTo($Br1Output) } finally { $Br1Input.Dispose() }
        }
    } finally { $Br1Output.Dispose() }
    if ((Get-Item $Br1Zip).Length -ne $Br1Manifest.size_bytes -or (Get-FileHash $Br1Zip -Algorithm SHA256).Hash -ne $Br1Manifest.sha256) { throw 'Reassembled ZIP verification failed' }
    $Br1Runtime = Join-Path $Br1Root 'runtime'
    & 7z x $Br1Zip ('-o' + $Br1Runtime) -y *> (Join-Path $Br1Logs 'EXTRACT.log')
    if ($LASTEXITCODE -ne 0) { throw 'Engine ZIP extraction failed' }
    $Br1Engine = Join-Path $Br1Runtime 'BR1_PHASE1_engine'
    $Br1BuildStatus = Get-Content -Raw -LiteralPath (Join-Path $Br1Runtime 'logs/BUILD_STATUS.json') | ConvertFrom-Json
    foreach ($Br1Exe in $Br1BuildStatus.executables) {
        if ((Get-FileHash (Join-Path $Br1Engine $Br1Exe.file) -Algorithm SHA256).Hash -ne $Br1Exe.sha256) { throw 'Executable SHA256 mismatch' }
    }
    $Br1Status['package_sha256'] = $Br1Manifest.sha256
    $Br1Status['executables'] = $Br1BuildStatus.executables
    Copy-Item -LiteralPath (Join-Path $Br1Transfer 'PACKAGE_TRANSFER.json') -Destination $Br1Logs
    Get-CimInstance Win32_VideoController | Select-Object Name,AdapterCompatibility,DriverVersion,VideoProcessor |
        ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $Br1Logs 'VIDEO_ADAPTERS.json')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'br1_smoke_component.py') -Destination $Br1Fixture
    $env:PYTHONUTF8 = '1'
    $env:PYTHONUNBUFFERED = '1'
    $env:BR1_DIAG = '0'
    $env:BR1_SMOKE_FIXTURE_DIR = $Br1Fixture
    $Br1Status.stage = 'check relocated background runtime'
    Invoke-Br1Process (Join-Path $Br1Engine 'blender.exe') @('--background','--factory-startup','--python-exit-code','1','--python-expr','import bpy; print("BR1_RELOCATED_RUNTIME_READY", flush=True)') 'relocated_background' $Br1Logs
    $Br1Status['relocated_background'] = 'PASS'
    $Br1Status.stage = 'create synthetic fixture'
    Invoke-Br1Process (Join-Path $Br1Engine 'blender.exe') @('--background','--factory-startup','--python-exit-code','1','--python',(Join-Path $PSScriptRoot 'Create-Fixture.py')) 'create_fixture' $Br1Logs
    $Br1Blend = Join-Path $Br1Fixture 'BR1_Phase1_Smoke.blend'
    $Br1Before = (Get-FileHash $Br1Blend -Algorithm SHA256).Hash

    foreach ($Br1Mode in @('Off','Full')) {
        $Br1ModeDir = Join-Path $Br1Logs $Br1Mode
        New-Item -ItemType Directory -Path $Br1ModeDir -Force | Out-Null
        $env:BR1_SMOKE_RESULT_DIR = $Br1ModeDir
        $env:BR1_DIAG = if ($Br1Mode -eq 'Full') { '1' } else { '0' }
        $env:BR1_DIAG_PYTHON = '1'
        $env:BR1_DIAG_DIR = $Br1ModeDir
        $env:BR1_DIAG_EVENTS = '262144'
        $env:BR1_DIAG_WORKER_EVENTS = '32768'
        $env:BR1_DIAG_MAX_FRAMES = '1000'
        $env:BR1_DIAG_MAX_BYTES = '67108864'
        $Br1Status.stage = 'player ' + $Br1Mode
        Invoke-Br1Process (Join-Path $Br1Engine 'blenderplayer.exe') @('-w','640','480',$Br1Blend) 'player' $Br1ModeDir
        $Br1Component = Get-Content -Raw -LiteralPath (Join-Path $Br1ModeDir 'COMPONENT.json') | ConvertFrom-Json
        if ($Br1Component.status -ne 'PASS' -or $Br1Component.updates -lt 12) { throw 'Fixture component did not complete twelve updates' }
        $Br1FixtureStarted = $true
        if ((Get-FileHash $Br1Blend -Algorithm SHA256).Hash -ne $Br1Before) { throw 'The saved synthetic scene changed during execution' }
        $Br1Captures = @(Get-ChildItem -LiteralPath $Br1ModeDir -Filter '*.jsonl' -File)
        if ($Br1Mode -eq 'Off' -and $Br1Captures.Count -ne 0) { throw 'Disabled profiling wrote a capture' }
        if ($Br1Mode -eq 'Full') {
            if ($Br1Captures.Count -ne 1) { throw 'Expected one actual engine capture' }
            $Br1Status.stage = 'analyze actual player capture'
            $Br1Python = Join-Path $Br1Engine '5.0/python/bin/python.exe'
            Invoke-Br1Process $Br1Python @((Join-Path $Br1Runtime 'upbge/diagnostics/br1_phase1/analyze.py'),$Br1Captures[0].FullName,'--output',(Join-Path $Br1ModeDir 'report'),'--skip-frames','0') 'analyze' $Br1ModeDir
            Invoke-Br1Process $Br1Python @((Join-Path $PSScriptRoot 'Verify-Capture.py'),$Br1ModeDir) 'verify_capture' $Br1ModeDir
        }
        $Br1Status[$Br1Mode] = 'PASS'
    }
    $Br1Status.status = 'PASS'
    $Br1Status.stage = 'complete'
    $Br1Exit = 0
} catch {
    $Br1Status.error = $_.Exception.Message
    $Br1DiagnosticText = (Get-ChildItem -LiteralPath $Br1Logs -Recurse -Filter '*.log' -File | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
    if (!$Br1FixtureStarted -and $Br1Status.stage -like 'player *' -and
        $Br1DiagnosticText -match '(Unsupported Graphics Card|Unable to create[^\r\n]*(GL|GPU)[^\r\n]*context|Failed to create OpenGL context|OpenGL[^\r\n]*(not supported|required))') {
        $Br1Status.status = 'NOT_RUN'
        $Br1Status['reason'] = 'The hosted runner could not provide the required graphics context; see player logs.'
        $Br1Exit = 0
    }
    Write-Host $Br1Status.error
} finally {
    $Br1Status['finished_utc'] = [DateTime]::UtcNow.ToString('o')
    $Br1Status | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $Br1Logs 'SMOKE_STATUS.json')
    $Br1Status | ConvertTo-Json -Depth 8 | Write-Host
}
exit $Br1Exit
