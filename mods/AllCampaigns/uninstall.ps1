<#
.SYNOPSIS
    Removes the All Campaigns mod, and Lazy Mod / DisciplesGL-Modern if install.ps1 added
    them, and restores the files install.ps1 backed up.

.DESCRIPTION
    Your saved games (SaveGame folder) and the toolset's .log files are left alone.

.PARAMETER GamePath
    Rise of the Elves folder. If left out, the GOG registry entry is offered as default.
#>
param(
    [string]$GamePath
)

$ErrorActionPreference = 'Stop'
$BackupName = '_AllCampaigns_backup'

function Get-GogPath([string]$id) {
    foreach ($key in "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\$id", "HKLM:\SOFTWARE\GOG.com\Games\$id") {
        try { return (Get-ItemProperty -Path $key -Name path -ErrorAction Stop).path } catch {}
    }
    return $null
}

function Find-Child([string]$dir, [string]$name) {
    $hit = Get-ChildItem -LiteralPath $dir -Force | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Fail([string]$msg) {
    Write-Host ""
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

Write-Host "All Campaigns uninstaller" -ForegroundColor Cyan
Write-Host ""

if (-not $GamePath) {
    $default = Get-GogPath '1207663713'
    if ($default) {
        $GamePath = Read-Host "Rise of the Elves folder [$default] (Enter to accept)"
        if (-not $GamePath) { $GamePath = $default }
    } else {
        $GamePath = Read-Host "Rise of the Elves folder"
    }
    $GamePath = $GamePath.Trim().Trim('"')
}

$backup = Join-Path $GamePath $BackupName
$info = Join-Path $backup 'install.json'
if (-not (Test-Path -LiteralPath $info)) { Fail "No '$BackupName' folder with install.json in '$GamePath'. Nothing to uninstall." }
$state = Get-Content -LiteralPath $info -Raw | ConvertFrom-Json

foreach ($f in 'MSS32.DLL', 'Interf.dlg', 'scens') {
    if (-not (Test-Path -LiteralPath (Join-Path $backup $f))) { Fail "Backup is incomplete: '$f' is missing. Nothing was changed." }
}

# Optional mods (Lazy Mod, DisciplesGL-Modern), newest first: delete the files they added,
# put back the files they replaced, and remove folders that are left empty.
$optional = @()
if ($state.PSObject.Properties.Name -contains 'optional' -and $state.optional) { $optional = @($state.optional) }
[array]::Reverse($optional)
foreach ($o in $optional) {
    Write-Host "Removing $($o.label)..."
    foreach ($rel in @($o.added)) {
        $p = Join-Path $GamePath $rel
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
        $dir = Split-Path $p
        while ($dir.Length -gt $GamePath.TrimEnd('\').Length -and (Test-Path -LiteralPath $dir) -and
               -not (Get-ChildItem -LiteralPath $dir -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $dir -Force
            $dir = Split-Path $dir
        }
    }
    foreach ($rel in @($o.replaced)) {
        Copy-Item -LiteralPath (Join-Path $backup "optional\$($o.label)\$rel") -Destination (Join-Path $GamePath $rel) -Force
    }
}

Write-Host "Restoring MSS32.DLL..."
$ours = Join-Path $GamePath 'mss32.dll'
if (Test-Path -LiteralPath $ours) { Remove-Item -LiteralPath $ours -Force }
$renamed = Join-Path $GamePath 'mss23.dll'
if (Test-Path -LiteralPath $renamed) { Remove-Item -LiteralPath $renamed -Force }
Copy-Item -LiteralPath (Join-Path $backup 'MSS32.DLL') -Destination (Join-Path $GamePath $state.mssName)

Write-Host "Restoring Interf.dlg..."
Copy-Item -LiteralPath (Join-Path $backup 'Interf.dlg') -Destination (Join-Path (Find-Child $GamePath 'interf') 'Interf.dlg') -Force

Write-Host "Restoring scenario tables..."
Copy-Item -Path (Join-Path $backup 'scens\*') -Destination (Find-Child $GamePath 'scens') -Force

Write-Host "Restoring Scripts..."
$scripts = Join-Path $GamePath 'Scripts'
if (Test-Path -LiteralPath $scripts) { Remove-Item -LiteralPath $scripts -Recurse -Force }
if ($state.hadScripts) { Copy-Item -LiteralPath (Join-Path $backup 'Scripts') -Destination $scripts -Recurse }

Remove-Item -LiteralPath $backup -Recurse -Force

Write-Host ""
Write-Host "Done. The game is back to how it was. Your SaveGame folder was kept." -ForegroundColor Green
