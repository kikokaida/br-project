[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceRoot,
      [Parameter(Mandatory=$true)][string]$LogsDir)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false
$Br1OriginalPatchHash = '3d4b39ceb54abb37f5ef7d86bf67de86f24cdc0c8cfcc8198a53db9d97c94264'
$Br1SourceCommit = 'b1b35c48872b32c8bd4134f0cba759224b40f8df'
$Br1FixHash = '0efc4cb0a15284b39509ba491d9638677a34f71a2d33e3a62b5c2c8c5726cf54'
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
# BEGIN VERIFIED BASELINE FIXES
$Br1BaselineHashes = @{
    'source/blender/blenkernel/intern/node.cc' = 'b636585c8a121253cb2a88d3c267fe6e0c85924b2c6a4ebfe058a89e22d188b6'
    'source/gameengine/GamePlayer/GPG_ghost.cpp' = '738a694a4ef3b284670efb067f12ab3631b07c3df4f482e75f00ab2da6745fe8'
    'tests/files/asset_library/новый/blender_assets.cats.txt' = '1b63c603ea1529fff41ca1c3f1456acf6d876718b18be55cdf945eeac02e9c9a'
}
foreach ($Br1Path in $Br1BaselineHashes.Keys) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $SourceRoot $Br1Path)).Hash -ne $Br1BaselineHashes[$Br1Path]) {
        throw "Pinned baseline hash mismatch before reviewed fix: $Br1Path"
    }
}
# END VERIFIED BASELINE FIXES
git -C $SourceRoot apply --check $Br1FixPatch
if ($LASTEXITCODE -ne 0) { throw 'Reviewed Windows fixes do not apply cleanly.' }
git -C $SourceRoot apply $Br1FixPatch
if ($LASTEXITCODE -ne 0) { throw 'Applying reviewed Windows fixes failed.' }
$Br1FixedHashes = @{
    'diagnostics/br1_phase1/Build-Windows.ps1' = '3bf1aa2f4904062edd907ba7c5353214831c7117e3881797c432baf3ff91031e'
    'source/blender/blenlib/intern/br1_diagnostics.cc' = '3cf05b06fd56f52aa5c011208c42d392d69fe868e610ba27a196afd267a602e6'
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
# BEGIN EFFECTIVE BASELINE FIXES
$Br1ExtraFixedHashes = @{
    'source/blender/blenkernel/intern/node.cc' = 'ff853f9e73d834f12508e4ff1df0fb8c6178b972b5818ebbc3f139a578c1965d'
    'source/gameengine/GamePlayer/GPG_ghost.cpp' = 'a98db980b20602242fdf8d4ad4ff3a99fd24c67f2f490be35a1b10804eb3bca5'
    'tests/files/asset_library/новый/blender_assets.cats.txt' = 'e03c93f1cc5faf62e5777f1f95ec889e160bb0981c43e2a0bf8900dda3c5f931'
}
foreach ($Br1Path in $Br1ExtraFixedHashes.Keys) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $SourceRoot $Br1Path)).Hash -ne $Br1ExtraFixedHashes[$Br1Path]) {
        throw "Effective baseline-fix hash mismatch: $Br1Path"
    }
    $Br1EffectiveFiles += [ordered]@{ path = $Br1Path; sha256 = $Br1ExtraFixedHashes[$Br1Path] }
}
# END EFFECTIVE BASELINE FIXES
[ordered]@{
    upstream_commit = $Br1SourceCommit
    original_patch_sha256 = $Br1OriginalPatchHash
    build_fixes_patch_sha256 = $Br1FixHash
    files = $Br1EffectiveFiles
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $LogsDir 'EFFECTIVE_SOURCE_MANIFEST.json')
[ordered]@{
    original_source_hashes = 'PASS (56 files)'
    effective_source_hashes = 'PASS (59 files)'
    build_fixes_patch_sha256 = $Br1FixHash
    changed_files = @(@($Br1FixedHashes.Keys) + @($Br1ExtraFixedHashes.Keys) | Sort-Object)
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $LogsDir 'SOURCE_VERIFICATION.json')
Copy-Item -LiteralPath $Br1FixPatch -Destination $LogsDir
Write-Host 'PASS: all 59 effective source hashes after the reviewed Windows fixes.'
