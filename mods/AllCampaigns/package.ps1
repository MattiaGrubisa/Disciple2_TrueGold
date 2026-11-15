<#
.SYNOPSIS
    Builds the release zip players download: install/uninstall scripts, README, licence,
    and files\ with the built mss32.dll and the toolset's Scripts folder.

.PARAMETER Dll
    Built mss32.dll. Defaults to the one the build copied into $env:DISCIPLES2_PATH.

.PARAMETER Output
    Zip to create. Defaults to AllCampaigns-<date>.zip next to the repository folder.
#>
param(
    [string]$Dll,
    [string]$Output
)

$ErrorActionPreference = 'Stop'
if (-not $Dll) {
    $gameDir = $env:DISCIPLES2_PATH
    if (-not $gameDir) { $gameDir = [Environment]::GetEnvironmentVariable('DISCIPLES2_PATH', 'User') }
    if (-not $gameDir) { throw "Pass -Dll or set DISCIPLES2_PATH." }
    $Dll = Join-Path $gameDir 'mss32.dll'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Output) {
    $Output = Join-Path (Split-Path $repo -Parent) ("AllCampaigns-" + (Get-Date -Format 'yyyy-MM-dd') + ".zip")
}
if (-not (Test-Path -LiteralPath $Dll)) { throw "Built DLL not found: $Dll" }

$stage = Join-Path ([IO.Path]::GetTempPath()) ("AllCampaigns_pkg_" + [guid]::NewGuid().ToString('N'))
$root = Join-Path $stage 'AllCampaigns'
New-Item -ItemType Directory -Path (Join-Path $root 'files') -Force | Out-Null

foreach ($f in 'install.ps1', 'install.bat', 'uninstall.ps1', 'uninstall.bat', 'README.md') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination $root
}
Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination $root
Copy-Item -LiteralPath $Dll -Destination (Join-Path $root 'files\mss32.dll')
Copy-Item -LiteralPath (Join-Path $repo 'Scripts') -Destination (Join-Path $root 'files\Scripts') -Recurse

if (Test-Path -LiteralPath $Output) { Remove-Item -LiteralPath $Output -Force }
Compress-Archive -Path $root -DestinationPath $Output
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host "Created $Output"
