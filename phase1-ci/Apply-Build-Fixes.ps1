[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceRoot,
      [Parameter(Mandatory=$true)][string]$LogsDir)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false
$Br1OriginalPatchHash = '3d4b39ceb54abb37f5ef7d86bf67de86f24cdc0c8cfcc8198a53db9d97c94264'
$Br1SourceCommit = 'b1b35c48872b32c8bd4134f0cba759224b40f8df'
$Br1FixHash = 'a719a5ea3a9645724a23e44e980a340ff8a6f470ed88691526216a0c62987897'
$Br1FixPatch = Join-Path $PSScriptRoot 'Build-Fixes.patch'
$Br1ManifestPath = Join-Path $SourceRoot 'diagnostics\br1_phase1\SOURCE_MANIFEST.json'
$Br1Manifest = Get-Content -Raw -LiteralPath $Br1ManifestPath | ConvertFrom-Json
$Br1Head = git -C $SourceRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $Br1Head -ne $Br1SourceCommit -or
    $Br1Manifest.upstream_commit -ne $Br1SourceCommit -or $Br1Manifest.files.Count -ne 56) {
    throw 'Source commit or original manifest mismatch.'
}
foreach ($Br1Entry in $Br1Manifest.files) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $SourceRoot $Br1Entry.path)).Hash -ne $Br1Entry.sha256) {
        throw "Original source hash mismatch: $($Br1Entry.path)"
    }
}
Write-Host 'PASS: all 56 original diagnostic source hashes.'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Br1FixPatch).Hash -ne $Br1FixHash) {
    throw 'Reviewed Windows build fixes patch hash mismatch.'
}
git -C $SourceRoot apply --check $Br1FixPatch
if ($LASTEXITCODE -ne 0) { throw 'Reviewed Windows fixes do not apply cleanly.' }
git -C $SourceRoot apply $Br1FixPatch
if ($LASTEXITCODE -ne 0) { throw 'Applying reviewed Windows fixes failed.' }
$Br1FixedHashes = @{
    'diagnostics/br1_phase1/Build-Windows.ps1' = '97b49435b6f171ee820cc7d7767bbc73a564603a18a112c7bda9eac329d1fa2b'
    'source/blender/blenlib/intern/br1_diagnostics.cc' = '50f310456eb217d0f4b1d5f4f842e327e4adb1cd39dea2117338fdd60e39bdda'
    'source/blender/python/intern/bpy_app_handlers.cc' = '1090687fa95d48c8fc35f76df1c9c27970c235f0e635b913483140a8785d7c37'
    'source/blender/python/intern/bpy_app_timers.cc' = 'bf8679ba301d98083639aaf657d65f379bec754e1a14b4e4d76cc8ab78f838c4'
    'source/blender/python/intern/bpy_driver.cc' = 'b01af95df539b2d8b86b3ced5a6ed3ff06527eab3243ee0577d4a143ac3a288f'
    'source/blender/python/intern/bpy_msgbus.cc' = '70e8595d011691a7352295beff1400adc27dd32e9e5f2c2181c4f5f06807278d'
}
$Br1EffectiveFiles = @()
foreach ($Br1Entry in $Br1Manifest.files) {
    $Br1ExpectedHash = $Br1Entry.sha256
    if ($Br1FixedHashes.ContainsKey($Br1Entry.path)) { $Br1ExpectedHash = $Br1FixedHashes[$Br1Entry.path] }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $SourceRoot $Br1Entry.path)).Hash -ne $Br1ExpectedHash) {
        throw "Effective source hash mismatch before compilation: $($Br1Entry.path)"
    }
    $Br1EffectiveFiles += [ordered]@{ path = $Br1Entry.path; sha256 = $Br1ExpectedHash }
}
[ordered]@{
    upstream_commit = $Br1SourceCommit
    original_patch_sha256 = $Br1OriginalPatchHash
    build_fixes_patch_sha256 = $Br1FixHash
    files = $Br1EffectiveFiles
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $LogsDir 'EFFECTIVE_SOURCE_MANIFEST.json')
[ordered]@{
    original_source_hashes = 'PASS (56 files)'
    effective_source_hashes = 'PASS (56 files)'
    build_fixes_patch_sha256 = $Br1FixHash
    changed_files = @($Br1FixedHashes.Keys | Sort-Object)
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $LogsDir 'SOURCE_VERIFICATION.json')
Copy-Item -LiteralPath $Br1FixPatch -Destination $LogsDir
Write-Host 'PASS: all 56 effective source hashes after the reviewed Windows fixes.'
