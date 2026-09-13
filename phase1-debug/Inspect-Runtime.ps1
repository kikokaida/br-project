[CmdletBinding()]
param([string]$ArtifactRoot = 'retained', [string]$LogsDir = 'runtime-debug-logs')
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest
$ArtifactRoot = [IO.Path]::GetFullPath($ArtifactRoot)
$LogsDir = [IO.Path]::GetFullPath($LogsDir)
New-Item -ItemType Directory -Force $LogsDir | Out-Null
Start-Transcript -Path (Join-Path $LogsDir 'INVESTIGATION.log') -Force | Out-Null
try {
    $Engine = Join-Path $ArtifactRoot 'BR1_PHASE1_engine'
    $Player = Join-Path $Engine 'blenderplayer.exe'
    $Blender = Join-Path $Engine 'blender.exe'
    foreach ($Exe in @($Player, $Blender)) {
        if (!(Test-Path -LiteralPath $Exe)) { throw "Missing retained executable: $Exe" }
        Get-FileHash -Algorithm SHA256 -LiteralPath $Exe | Format-List
    }
    if ((Get-FileHash $Player -Algorithm SHA256).Hash -ne '1f3f764d688ea908fd01d88532c7ca941fa97caa1008bc3e32d2a31e64d7d68a') { throw 'Unexpected player bytes.' }
    if ((Get-FileHash $Blender -Algorithm SHA256).Hash -ne '62698226d1fe5fa427155646df0701b13580430c16018b936f36ae7d120647e2') { throw 'Unexpected Blender bytes.' }
    $Cdb = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Debuggers\x64\cdb.exe'
    if (!(Test-Path $Cdb)) {
        # Install only Microsoft's debugger tools on this disposable runner.
        $Setup = Join-Path $env:RUNNER_TEMP 'br1-winsdksetup.exe'
        Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2376216' -OutFile $Setup
        $Signature = Get-AuthenticodeSignature -LiteralPath $Setup
        if ($Signature.Status -ne 'Valid' -or $Signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'SDK installer signature is not valid Microsoft code.' }
        Get-FileHash $Setup -Algorithm SHA256 | Format-List
        $Process = Start-Process -FilePath $Setup -ArgumentList '/features OptionId.WindowsDesktopDebuggers /quiet /norestart /ceip off' -PassThru
        if (!$Process.WaitForExit(600000)) { $Process.Kill(); throw 'Debugger installation exceeded ten minutes.' }
        if ($Process.ExitCode -notin @(0,3010)) { throw "Debugger installation failed: $($Process.ExitCode)" }
    }
    if (!(Test-Path $Cdb)) { throw 'CDB is not installed.' }
    (Get-Item $Cdb).VersionInfo | Format-List
    $Symbols = @($Engine)
    $Symbols += @(Get-ChildItem -Path $ArtifactRoot -Filter '*.pdb' -Recurse -File | ForEach-Object DirectoryName | Sort-Object -Unique)
    $SymbolPath = ($Symbols -join ';') + ';srv*' + (Join-Path $env:RUNNER_TEMP 'br1-symbols') + '*https://msdl.microsoft.com/download/symbols'
    $Results = @()
    function Invoke-Br1Debugger([string]$Name, [string]$Executable, [string[]]$Arguments, [string]$Module) {
        $Log = Join-Path $LogsDir ($Name + '.log')
        $Command = 'sxe -c ".echo BR1_ACCESS_VIOLATION; .ecxr; kv 50; q" av; sxe -c ".echo BR1_FAST_FAIL; .ecxr; kv 50; q" 0xc0000409; bu ' + $Module + '!MEM_trigger_error_on_memory_block ".echo BR1_ALLOCATOR_ERROR; kv 50; q"; g'
        $StartInfo = [Diagnostics.ProcessStartInfo]::new()
        $StartInfo.FileName = $Cdb
        $StartInfo.WorkingDirectory = Split-Path $Executable -Parent
        $StartInfo.UseShellExecute = $false
        foreach ($Arg in @('-o','-G','-lines','-y',$SymbolPath,'-logo',$Log,'-c',$Command,$Executable) + $Arguments) { $StartInfo.ArgumentList.Add($Arg) }
        $Process = [Diagnostics.Process]::Start($StartInfo)
        $Finished = $Process.WaitForExit(180000)
        if (!$Finished) { $Process.Kill($true); $Process.WaitForExit() }
        [ordered]@{name=$Name; debugger_exit_code=$Process.ExitCode; timed_out=(!$Finished); executable=$Executable; arguments=$Arguments}
    }
    $env:BR1_DIAG = '0'
    $Results += Invoke-Br1Debugger 'player_help' $Player @('-h') 'blenderplayer'
    $Results += Invoke-Br1Debugger 'blender_guarded_background' $Blender @('--debug-memory','--background','--factory-startup','--python-exit-code','1','--python-expr','print("BR1_GUARDED_BODY_PASSED")') 'blender'
    $TestExe = Get-ChildItem -Path (Join-Path $ArtifactRoot 'BR1_PHASE1_build\bin') -Filter 'blender_test.exe' -Recurse -File | Select-Object -First 1
    if ($TestExe) {
        $Results += Invoke-Br1Debugger 'native_blendfile_canary' $TestExe.FullName @('--gtest_filter=BlendfileLoadingTest.CanaryTest') 'blender_test'
    }
    $Results | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $LogsDir 'DEBUGGER_RESULTS.json')
    Get-ChildItem -Path $env:TEMP -Filter '*.crash.txt' -Recurse -File -ErrorAction SilentlyContinue | Copy-Item -Destination $LogsDir -ErrorAction Continue
} finally {
    Stop-Transcript | Out-Null
}
