[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false
$Br1Root = Join-Path $PSScriptRoot '..\br1_build_job\br1_ci_work'
$Br1Engine = Join-Path $Br1Root 'BR1_PHASE1_engine'
$Br1Logs = Join-Path $Br1Root 'logs'
$Br1Checks = @(
    @{ name = 'blender_version'; exe = 'blender.exe'; arguments = @('--version') },
    @{ name = 'player_help'; exe = 'blenderplayer.exe'; arguments = @('-h') },
    @{ name = 'blender_background_python'; exe = 'blender.exe'; arguments = @('--background', '--factory-startup', '--python-exit-code', '1', '--python-expr', 'import bpy, mathutils, sys; print("BR1_RUNTIME_PYTHON", sys.version); print("BR1_RUNTIME_VERSION", bpy.app.version_string); print("BR1_RUNTIME_RESOURCES", bpy.utils.resource_path("LOCAL"))') }
)
$Br1Results = @()
foreach ($Br1Check in $Br1Checks) {
    $Br1Log = Join-Path $Br1Logs ($Br1Check.name + '.log')
    $Br1Arguments = $Br1Check.arguments
    $Br1Code = $null
    $Br1Error = $null
    try {
        & (Join-Path $Br1Engine $Br1Check.exe) @Br1Arguments 2>&1 | Tee-Object -FilePath $Br1Log
        $Br1Code = $LASTEXITCODE
    } catch { $Br1Error = $_.Exception.Message }
    $Br1Results += [ordered]@{
        name = $Br1Check.name
        executable = $Br1Check.exe
        status = if ($Br1Code -eq 0 -and !$Br1Error) { 'PASS' } else { 'FAIL' }
        exit_code = $Br1Code
        error = $Br1Error
    }
}
$Br1Results | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $Br1Logs 'INSTALLED_RUNTIME_TESTS.json')
if (@($Br1Results | Where-Object status -ne 'PASS').Count -gt 0) {
    throw 'Installed runtime checks failed; see INSTALLED_RUNTIME_TESTS.json and individual logs.'
}
