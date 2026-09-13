[CmdletBinding()]
param([string]$RunRoot = 'br1_build_job/br1_ci_work', [string]$OutputDir = 'delivery')
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest
$RunRoot = [IO.Path]::GetFullPath($RunRoot)
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$Br1Zip = Join-Path $OutputDir 'BR1_Phase1_Windows_x64.zip'
if (Test-Path -LiteralPath $Br1Zip) { throw 'Refusing to replace an existing delivery ZIP.' }
foreach ($Br1Relative in @('BR1_PHASE1_engine/blender.exe','BR1_PHASE1_engine/blenderplayer.exe','upbge/diagnostics/br1_phase1/Run-Benchmark.ps1','upbge/diagnostics/br1_phase1/analyze.py')) {
    if (!(Test-Path -LiteralPath (Join-Path $RunRoot $Br1Relative))) { throw "Missing package input: $Br1Relative" }
}
$Br1Archive = [IO.Compression.ZipFile]::Open($Br1Zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    # PDB debug symbols remain in the recovery artifact; they are not runtime dependencies.
    foreach ($Br1Directory in @('BR1_PHASE1_engine','upbge/diagnostics/br1_phase1','logs')) {
        foreach ($Br1File in Get-ChildItem -LiteralPath (Join-Path $RunRoot $Br1Directory) -Recurse -File -Force) {
            if ($Br1File.Extension -eq '.pdb') { continue }
            $Br1EntryName = [IO.Path]::GetRelativePath($RunRoot, $Br1File.FullName).Replace('\','/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Br1Archive, $Br1File.FullName, $Br1EntryName, [IO.Compression.CompressionLevel]::SmallestSize) | Out-Null
        }
    }
} finally { $Br1Archive.Dispose() }
& 7z t $Br1Zip
if ($LASTEXITCODE -ne 0) { throw 'Engine ZIP integrity check failed.' }
$Br1Archive = [IO.Compression.ZipFile]::OpenRead($Br1Zip)
try {
    foreach ($Br1Required in @('BR1_PHASE1_engine/blender.exe','BR1_PHASE1_engine/blenderplayer.exe','BR1_PHASE1_engine/5.0/python/bin/python.exe','upbge/diagnostics/br1_phase1/Run-Benchmark.ps1','upbge/diagnostics/br1_phase1/analyze.py')) {
        $Br1Entry = $Br1Archive.GetEntry($Br1Required)
        if (!$Br1Entry -or $Br1Entry.Length -eq 0) { throw "Package layout check failed: $Br1Required" }
    }
} finally { $Br1Archive.Dispose() }
$Br1ZipInfo = Get-Item -LiteralPath $Br1Zip
$Br1Manifest = [ordered]@{
    filename = $Br1ZipInfo.Name
    size_bytes = $Br1ZipInfo.Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Br1Zip).Hash.ToLowerInvariant()
    zip_integrity = 'PASS'
    source_run = $env:GITHUB_RUN_ID
    source_commit = 'b1b35c48872b32c8bd4134f0cba759224b40f8df'
    benchmark_layout = 'BR1_PHASE1_engine beside upbge/diagnostics/br1_phase1'
    omitted_debug_symbols = '*.pdb (retained separately; not required to run the engine)'
    parts = @()
}
# The authenticated artifact downloader supports at most 512 MiB per artifact.
# Transfer bounded chunks, then concatenate and verify the original ZIP SHA256.
$Br1PartLimit = 400MB
$Br1Buffer = [byte[]]::new(4MB)
$Br1Input = [IO.File]::OpenRead($Br1Zip)
try {
    $Br1PartIndex = 0
    while ($Br1Input.Position -lt $Br1Input.Length) {
        $Br1PartIndex++
        if ($Br1PartIndex -gt 4) { throw 'Package exceeds the four configured transfer parts.' }
        $Br1PartDir = Join-Path $OutputDir ('part' + $Br1PartIndex)
        New-Item -ItemType Directory -Path $Br1PartDir -Force | Out-Null
        $Br1PartName = 'BR1_Phase1_Windows_x64.zip.part' + $Br1PartIndex.ToString('000')
        $Br1PartPath = Join-Path $Br1PartDir $Br1PartName
        $Br1Output = [IO.File]::Create($Br1PartPath)
        try {
            $Br1Written = 0L
            while ($Br1Written -lt $Br1PartLimit -and $Br1Input.Position -lt $Br1Input.Length) {
                $Br1Count = $Br1Input.Read($Br1Buffer, 0, [int][Math]::Min($Br1Buffer.Length, $Br1PartLimit - $Br1Written))
                if ($Br1Count -le 0) { throw 'Unexpected end of package while splitting.' }
                $Br1Output.Write($Br1Buffer, 0, $Br1Count)
                $Br1Written += $Br1Count
            }
        } finally { $Br1Output.Dispose() }
        $Br1Manifest.parts += [ordered]@{index=$Br1PartIndex; filename=$Br1PartName; size_bytes=(Get-Item $Br1PartPath).Length; sha256=(Get-FileHash $Br1PartPath -Algorithm SHA256).Hash.ToLowerInvariant()}
        if ($env:GITHUB_OUTPUT) { ('part' + $Br1PartIndex + '=true') | Add-Content -Encoding utf8 -LiteralPath $env:GITHUB_OUTPUT }
    }
} finally { $Br1Input.Dispose() }
$Br1Manifest | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $OutputDir 'PACKAGE_TRANSFER.json')
Copy-Item -LiteralPath (Join-Path $OutputDir 'PACKAGE_TRANSFER.json') -Destination (Join-Path $RunRoot 'logs')
Write-Host "PASS: verified ZIP $($Br1Manifest.size_bytes) bytes, SHA256 $($Br1Manifest.sha256)"
