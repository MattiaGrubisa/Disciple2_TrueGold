<#
.SYNOPSIS
    Installs the All Campaigns mod into a GOG copy of Disciples II: Rise of the Elves (v3.01).

.DESCRIPTION
    - Checks that the game is the GOG Rise of the Elves v3.01 executable.
    - Backs up every file it changes into "_AllCampaigns_backup" inside the game folder.
    - Installs the modding toolset (mss32.dll + Scripts), keeping the original MSS32.DLL as mss23.dll.
    - Adds the Gallean's Return button to DLG_CHOOSE_RACE in interf\Interf.dlg.
    - Copies the real Gallean's Return missions from your own Dark Prophecy / Gallean's Return
      install into Rise of the Elves' scens tables, replacing the empty stubs Rise of the Elves ships.
    - Creates the SaveGame folder, which the GOG install lacks.
    - Optionally installs Lazy Mod 1.06 (from a zip or folder you downloaded from ModDB)
      and the DisciplesGL-Modern OpenGL wrapper (downloaded from its GitHub release).

    Run uninstall.ps1 to put everything back, optional mods included.

.PARAMETER GamePath
    Rise of the Elves folder. If left out, the GOG registry entry is offered as default.

.PARAMETER BasePath
    Dark Prophecy / Gallean's Return folder. If left out, the GOG registry entry is offered as default.

.PARAMETER LazyMod
    ask (default), yes or no.

.PARAMETER LazyModSource
    Downloaded Lazy Mod 1.06 zip, or the folder it was unpacked to. Asked for if left out.

.PARAMETER Wrapper
    ask (default), yes or no: install the DisciplesGL-Modern OpenGL wrapper.

.PARAMETER WrapperZip
    Use an already downloaded DisciplesGL-Modern-C4dll-R.zip instead of downloading it.
#>
param(
    [string]$GamePath,
    [string]$BasePath,
    [ValidateSet('ask', 'yes', 'no')][string]$LazyMod = 'ask',
    [string]$LazyModSource,
    [ValidateSet('ask', 'yes', 'no')][string]$Wrapper = 'ask',
    [string]$WrapperZip
)

$ErrorActionPreference = 'Stop'

$BackupName = '_AllCampaigns_backup'
# Accepted executables:
#  - GOG Rise of the Elves v3.01 as GOG ships it.
#  - Lazy Mod 1.06's Discipl2.exe. Same size and same code as the GOG one, it only blanks
#    six unit id strings in the data section, so every hooked address is unchanged.
$RoteExeSha256 = @(
    '88DC8162D60D79F394696DB5FF48C68586E21F1F99A6C4D1C2328DEA81771D8F', # GOG v3.01
    '3964DF2F9EFBE92CC9777080FA00B242557EFDB4654410BE67E50A4DBCDC85BD'  # Lazy Mod 1.06
)
$RoteGogId = '1207663713'
$BaseGogId = '1207663703'
$Files = Join-Path $PSScriptRoot 'files'

# Optional mods. Neither is shipped with this mod: Lazy Mod contains the game's (modified)
# executable, and ModDB doesn't allow scripted downloads, so the player downloads it.
# The wrapper is MIT licensed and has a GitHub release, so it's downloaded here. The version
# is pinned and checked by hash, so a later release can't change what gets installed untested.
$LazyExeSha256 = $RoteExeSha256[1]
$LazyModUrl = 'https://www.moddb.com/mods/d2rote-lazy-mod/downloads/disciples-2-lazy-mod-106'
$WrapperVersion = 'v2026.4'
$WrapperUrl = "https://github.com/gitTerebi/DisciplesGL-Modern/releases/download/$WrapperVersion/DisciplesGL-Modern-C4dll-R.zip"
$WrapperZipSha256 = '4BB25C457B5506F10B5D5E7238936028A38837BED4516BA32A146A576AB126D3'
$WrapperDllSha256 = '4256157F4D2C5B96F52C36F35F26190E2510C259079C6F3D4F0F8CC033468969'

$DlgLines = @(
    "`tBUTTON`tBTN_GALLEAN,598,496,668,543,_MENU_CONTINUE_N,_MENU_CONTINUE_H,_MENU_CONTINUE_C,_MENU_CONTINUE_D,`"`",0,0",
    "`tTEXT`tTXT_GALLEAN,672,496,800,543,\vC;\hL;\fmedium;,`"`",`"`""
)

# ---------------------------------------------------------------------------
# Scenario table converter.
#
# Scenario data lives in dBase III tables (scens\*.dbf): a header, a list of
# fixed-width columns, then fixed-width rows. Rise of the Elves added columns
# and widened others, so base-game rows can't be copied as raw bytes. Each row
# is rebuilt column by column, matched by column name.
#
# Written in C# because looping over ~100k rows in plain PowerShell is slow.
# ---------------------------------------------------------------------------
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

public static class GrScensPort
{
    class Field { public string Name; public char Type; public int Len; }

    class Table
    {
        public byte[] Header;
        public List<Field> Fields = new List<Field>();
        public int RecLen;
        public List<byte[]> Recs = new List<byte[]>();
    }

    static readonly Encoding Latin1 = Encoding.GetEncoding(28591);
    static readonly Regex Resource = new Regex(@"^G\d{4}:R\d{4}:Y\d{4}:E\d{4}:W\d{4}$");

    // Gallean's Return scenarios are S123..S134. Every row of a scenario starts with its id.
    static bool IsGr(byte[] rec)
    {
        if (rec.Length < 5 || rec[1] != (byte)'S') return false;
        int n;
        if (!int.TryParse(Latin1.GetString(rec, 2, 3), out n)) return false;
        return n >= 123 && n <= 134;
    }

    static bool IsDeleted(byte[] rec) { return rec[0] == (byte)'*'; }

    static Table Read(string path)
    {
        byte[] d = File.ReadAllBytes(path);
        Table t = new Table();
        int count = BitConverter.ToInt32(d, 4);
        int headerLen = BitConverter.ToUInt16(d, 8);
        t.RecLen = BitConverter.ToUInt16(d, 10);
        for (int o = 32; d[o] != 0x0D; o += 32)
        {
            int end = o;
            while (end < o + 11 && d[end] != 0) end++;
            Field f = new Field();
            f.Name = Latin1.GetString(d, o, end - o);
            f.Type = (char)d[o + 11];
            f.Len = d[o + 16];
            t.Fields.Add(f);
        }
        t.Header = new byte[headerLen];
        Array.Copy(d, t.Header, headerLen);
        for (int i = 0; i < count; i++)
        {
            byte[] r = new byte[t.RecLen];
            Array.Copy(d, headerLen + i * t.RecLen, r, 0, t.RecLen);
            t.Recs.Add(r);
        }
        return t;
    }

    static Dictionary<string, string> Split(byte[] rec, List<Field> fields)
    {
        Dictionary<string, string> o = new Dictionary<string, string>();
        int p = 1;
        foreach (Field f in fields) { o[f.Name] = Latin1.GetString(rec, p, f.Len); p += f.Len; }
        return o;
    }

    static string Fit(string value, char type, int len, string where)
    {
        string v = value.Trim();
        if (v.Length > len) throw new Exception(where + ": '" + v + "' does not fit in " + len);
        return type == 'C' ? v.PadRight(len) : v.PadLeft(len);
    }

    // Most common value of a column, first one seen wins a tie.
    static string MostCommon(List<Dictionary<string, string>> rows, Field f)
    {
        if (rows.Count == 0)
            return f.Type == 'C' ? new string(' ', f.Len) : (f.Type == 'L' ? "F" : "0".PadLeft(f.Len));
        Dictionary<string, int> counts = new Dictionary<string, int>();
        string best = null;
        int bestCount = 0;
        foreach (Dictionary<string, string> r in rows)
        {
            string v = r[f.Name];
            int c;
            counts.TryGetValue(v, out c);
            counts[v] = ++c;
            if (c > bestCount) { best = v; bestCount = c; }
        }
        return best;
    }

    public static List<string> FieldNames(string path)
    {
        List<string> names = new List<string>();
        foreach (Field f in Read(path).Fields) names.Add(f.Name);
        return names;
    }

    public static string FindFile(string dir, string name)
    {
        foreach (string p in Directory.GetFiles(dir))
            if (string.Equals(Path.GetFileName(p), name, StringComparison.OrdinalIgnoreCase)) return p;
        return null;
    }

    // Returns one report line per changed table. Throws if anything doesn't fit.
    public static List<string> Port(string baseDir, string roteDir, string outDir, out int totalAdded)
    {
        Directory.CreateDirectory(outDir);
        List<string> report = new List<string>();
        totalAdded = 0;
        foreach (string path in Directory.GetFiles(roteDir))
        {
            string fn = Path.GetFileName(path);
            if (!fn.EndsWith(".dbf", StringComparison.OrdinalIgnoreCase)) continue;

            Table rote = Read(path);
            List<byte[]> outRecs = new List<byte[]>();
            List<Dictionary<string, string>> live = new List<Dictionary<string, string>>();
            foreach (byte[] r in rote.Recs)
            {
                if (!IsGr(r)) outRecs.Add(r);
                if (!IsDeleted(r)) live.Add(Split(r, rote.Fields));
            }
            int removed = rote.Recs.Count - outRecs.Count;

            Dictionary<string, string> defaults = new Dictionary<string, string>();
            foreach (Field f in rote.Fields) defaults[f.Name] = MostCommon(live, f);

            int added = 0;
            string basePath = FindFile(baseDir, fn);
            if (basePath != null)
            {
                Table bt = Read(basePath);
                HashSet<string> baseNames = new HashSet<string>();
                foreach (Field f in bt.Fields) baseNames.Add(f.Name);

                foreach (byte[] rec in bt.Recs)
                {
                    if (IsDeleted(rec) || !IsGr(rec)) continue;
                    Dictionary<string, string> src = Split(rec, bt.Fields);
                    StringBuilder sb = new StringBuilder(" ");
                    foreach (Field f in rote.Fields)
                    {
                        string v;
                        if (baseNames.Contains(f.Name))
                        {
                            v = src[f.Name];
                            // Rise of the Elves adds a 6th mana type (B = Elves).
                            if (f.Type == 'C' && Resource.IsMatch(v.Trim())) v = v.Trim() + ":B0000";
                        }
                        else v = defaults[f.Name];
                        sb.Append(Fit(v, f.Type, f.Len, fn + "." + f.Name));
                    }
                    byte[] nr = Latin1.GetBytes(sb.ToString());
                    if (nr.Length != rote.RecLen) throw new Exception(fn + ": bad row length");
                    outRecs.Add(nr);
                    added++;
                }
            }

            byte[] hdr = (byte[])rote.Header.Clone();
            Array.Copy(BitConverter.GetBytes(outRecs.Count), 0, hdr, 4, 4);
            using (FileStream fs = File.Create(Path.Combine(outDir, fn)))
            {
                fs.Write(hdr, 0, hdr.Length);
                foreach (byte[] r in outRecs) fs.Write(r, 0, r.Length);
                fs.WriteByte(0x1A);
            }
            if (removed > 0 || added > 0)
                report.Add(string.Format("{0,-14} removed {1,4} stub rows, added {2,5} GR rows", fn, removed, added));
            totalAdded += added;
        }
        return report;
    }
}
'@

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-GogPath([string]$id) {
    foreach ($key in "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\$id", "HKLM:\SOFTWARE\GOG.com\Games\$id") {
        try { return (Get-ItemProperty -Path $key -Name path -ErrorAction Stop).path } catch {}
    }
    return $null
}

function Read-Folder([string]$what, [string]$default) {
    if ($default) {
        $answer = Read-Host "$what folder [$default] (Enter to accept)"
        if (-not $answer) { $answer = $default }
    } else {
        $answer = Read-Host "$what folder"
    }
    return $answer.Trim().Trim('"')
}

# Finds a file or folder case-insensitively (the GOG installs mix "Scens" and "scens").
function Find-Child([string]$dir, [string]$name) {
    $hit = Get-ChildItem -LiteralPath $dir -Force | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Fail([string]$msg) {
    Write-Host ""
    Write-Host "ERROR: $msg" -ForegroundColor Red
    if ($script:tmpRoot -and (Test-Path -LiteralPath $script:tmpRoot)) {
        Remove-Item -LiteralPath $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 1
}

function Read-YesNo([string]$question, [bool]$default) {
    $hint = if ($default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $a = (Read-Host "$question $hint").Trim().ToLower()
        if (-not $a) { return $default }
        if ($a -in 'y', 'yes') { return $true }
        if ($a -in 'n', 'no') { return $false }
    }
}

# Plain .NET instead of Get-FileHash, which isn't always loadable in Windows PowerShell.
function Get-Sha256([string]$path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $fs = [IO.File]::OpenRead((Resolve-Path -LiteralPath $path).Path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '') }
    finally { $fs.Dispose(); $sha.Dispose() }
}

# Unpacks a zip into a new temp folder, or returns a folder as it is.
function Open-Source([string]$path, [string]$name) {
    if (Test-Path -LiteralPath $path -PathType Container) { return (Resolve-Path -LiteralPath $path).Path }
    if (-not (Test-Path -LiteralPath $path)) { Fail "'$path' not found." }
    if ([IO.Path]::GetExtension($path) -ine '.zip') {
        Fail "'$path' isn't a .zip. Unpack it first (7-Zip opens .rar and .7z) and give the folder instead."
    }
    $dir = Join-Path $script:tmpRoot $name
    # .NET's zip support instead of Expand-Archive, which isn't always loadable in Windows PowerShell.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        [IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path -LiteralPath $path).Path, $dir)
    } catch {
        Fail "Couldn't unpack '$path': $($_.Exception.Message)"
    }
    return $dir
}

# Copies every file of $files (paths relative to $srcRoot) into the game folder. Files it
# replaces are backed up to $backup\optional\<label>\ first. Returns what uninstall needs.
function Install-Optional([string]$label, [string]$srcRoot, [string[]]$files) {
    $store = Join-Path $backup "optional\$label"
    $added = @(); $replaced = @()
    foreach ($rel in $files) {
        $dst = Join-Path $GamePath $rel
        if (Test-Path -LiteralPath $dst) {
            $keep = Join-Path $store $rel
            New-Item -ItemType Directory -Path (Split-Path $keep) -Force | Out-Null
            Copy-Item -LiteralPath $dst -Destination $keep
            $replaced += $rel
        } else {
            New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
            $added += $rel
        }
        Copy-Item -LiteralPath (Join-Path $srcRoot $rel) -Destination $dst -Force
    }
    return [ordered]@{ label = $label; added = $added; replaced = $replaced }
}

function Get-RelativeFiles([string]$root) {
    $prefix = $root.TrimEnd('\').Length + 1
    return @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { $_.FullName.Substring($prefix) })
}

# ---------------------------------------------------------------------------
# 1. Work out the folders and check everything before touching anything
# ---------------------------------------------------------------------------
Write-Host "All Campaigns installer" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath (Join-Path $Files 'mss32.dll'))) {
    Fail "files\mss32.dll not found next to this script. Download the release zip instead of the source code."
}

if (-not $GamePath) { $GamePath = Read-Folder 'Rise of the Elves' (Get-GogPath $RoteGogId) }
if (-not $BasePath) { $BasePath = Read-Folder "Dark Prophecy / Gallean's Return" (Get-GogPath $BaseGogId) }

$exe = Join-Path $GamePath 'Discipl2.exe'
if (-not (Test-Path -LiteralPath $exe)) { Fail "No Discipl2.exe in '$GamePath'." }
if ($RoteExeSha256 -notcontains (Get-Sha256 $exe)) {
    Fail "Discipl2.exe in '$GamePath' is not the GOG Rise of the Elves v3.01 executable. The mod only works with that exact version."
}

$backup = Join-Path $GamePath $BackupName
if (Test-Path -LiteralPath $backup) { Fail "Already installed ('$BackupName' exists). Run uninstall.ps1 first." }
if (Test-Path -LiteralPath (Join-Path $GamePath 'mss23.dll')) {
    Fail "mss23.dll already exists, so another copy of the modding toolset is installed. Remove it first."
}

$mss = Find-Child $GamePath 'mss32.dll'
$dlg = $null
$interf = Find-Child $GamePath 'interf'
if ($interf) { $dlg = Find-Child $interf 'Interf.dlg' }
$roteScens = Find-Child $GamePath 'scens'
$baseScens = $null
if (Test-Path -LiteralPath $BasePath) { $baseScens = Find-Child $BasePath 'scens' }

if (-not $mss) { Fail "MSS32.DLL not found in '$GamePath'." }
if (-not $dlg) { Fail "interf\Interf.dlg not found in '$GamePath'." }
if (-not $roteScens) { Fail "scens folder not found in '$GamePath'." }
if (-not $baseScens) { Fail "scens folder not found in '$BasePath'. Is that the Dark Prophecy / Gallean's Return folder?" }
if ((Resolve-Path -LiteralPath $GamePath).Path -eq (Resolve-Path -LiteralPath $BasePath).Path) {
    Fail "Both folders are the same. The second one must be the older Dark Prophecy / Gallean's Return game."
}
# Rise of the Elves added an ELF column to SEvent.dbf. If the "base" folder has it, it's
# another Rise of the Elves copy, whose Gallean's Return maps are only empty stubs.
$baseEvents = [GrScensPort]::FindFile($baseScens, 'SEvent.dbf')
if (-not $baseEvents) { Fail "SEvent.dbf not found in '$baseScens'." }
if ([GrScensPort]::FieldNames($baseEvents) -contains 'ELF') {
    Fail "'$BasePath' is a Rise of the Elves install. The second folder must be Dark Prophecy / Gallean's Return."
}

# Patch Interf.dlg in memory. Latin-1 keeps every byte exactly as it was.
$latin1 = [Text.Encoding]::GetEncoding(28591)
$dlgText = $latin1.GetString([IO.File]::ReadAllBytes($dlg))
if ($dlgText -match 'BTN_GALLEAN') { Fail "Interf.dlg already contains BTN_GALLEAN." }
$nl = if ($dlgText.Contains("`r`n")) { "`r`n" } else { "`n" }
$m = [regex]::Match($dlgText, '(?m)^DIALOG\s+DLG_CHOOSE_RACE,')
if (-not $m.Success) { Fail "DLG_CHOOSE_RACE not found in Interf.dlg." }
$end = [regex]::Match($dlgText.Substring($m.Index), '(?m)^END\s*$')
if (-not $end.Success) { Fail "End of DLG_CHOOSE_RACE not found in Interf.dlg." }
$at = $m.Index + $end.Index
$newDlg = $dlgText.Substring(0, $at) + ($DlgLines -join $nl) + $nl + $dlgText.Substring($at)

# Convert the scenario tables into a temporary folder first, so a failure changes nothing.
Write-Host "Copying Gallean's Return missions from '$BasePath'..."
$script:tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("AllCampaigns_" + [guid]::NewGuid().ToString('N'))
$tmp = Join-Path $tmpRoot 'scens'
$added = 0
try {
    $report = [GrScensPort]::Port($baseScens, $roteScens, $tmp, [ref]$added)
} catch {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Fail "Converting the scenario tables failed: $($_.Exception.Message)"
}
if ($added -eq 0) {
    Remove-Item -LiteralPath $tmp -Recurse -Force
    Fail "No Gallean's Return missions found in '$baseScens'. Is that the GOG Dark Prophecy / Gallean's Return v2.02 install?"
}
$report | ForEach-Object { Write-Host "  $_" }

# Optional: Lazy Mod 1.06 ----------------------------------------------------
Write-Host ""
$lazyRoot = $null
if ((Get-Sha256 $exe) -eq $LazyExeSha256) {
    Write-Host "Lazy Mod 1.06 is already installed in this game, skipping it."
} else {
    $want = switch ($LazyMod) {
        'yes' { $true }
        'no' { $false }
        default {
            Write-Host "Lazy Mod 1.06 is a rebalance of Rise of the Elves: stronger heroes, new skills,"
            Write-Host "reworked items, a tougher AI. The Gallean's Return missions work with it."
            Read-YesNo "Install Lazy Mod 1.06?" $false
        }
    }
    if ($want) {
        if (-not $LazyModSource) {
            Write-Host "Lazy Mod has to be downloaded by hand from ModDB. Opening the download page..."
            Write-Host "  $LazyModUrl"
            try { Start-Process $LazyModUrl } catch {}
            $LazyModSource = (Read-Host "Path to the downloaded zip, or the folder you unpacked it to").Trim().Trim('"')
        }
        $src = Open-Source $LazyModSource 'lazymod'
        $lazyExe = Get-ChildItem -LiteralPath $src -Recurse -File -Filter 'Discipl2.exe' | Select-Object -First 1
        if (-not $lazyExe) { Fail "No Discipl2.exe in '$LazyModSource'. Is that Lazy Mod 1.06?" }
        if ((Get-Sha256 $lazyExe.FullName) -ne $LazyExeSha256) {
            Fail "Discipl2.exe in '$LazyModSource' isn't the one from Lazy Mod 1.06, the only version known to work with this mod."
        }
        $lazyRoot = $lazyExe.DirectoryName
        $lazyFiles = @(Get-RelativeFiles $lazyRoot | Where-Object { $_ -notlike '*.txt' })
        Write-Host "  Found Lazy Mod 1.06 ($($lazyFiles.Count) files)."
    }
}

# Optional: DisciplesGL-Modern wrapper -----------------------------------------
Write-Host ""
$wrapperRoot = $null
$c4 = Join-Path $GamePath 'C4dll-R.dll'
if ((Test-Path -LiteralPath $c4) -and (Get-Sha256 $c4) -eq $WrapperDllSha256) {
    Write-Host "DisciplesGL-Modern $WrapperVersion is already installed in this game, skipping it."
} else {
    $want = switch ($Wrapper) {
        'yes' { $true }
        'no' { $false }
        default {
            Write-Host "DisciplesGL-Modern is an OpenGL wrapper that makes the game display properly"
            Write-Host "on modern Windows and monitors."
            Read-YesNo "Install DisciplesGL-Modern $WrapperVersion?" $true
        }
    }
    if ($want) {
        if (-not $WrapperZip) {
            $WrapperZip = Join-Path $tmpRoot 'DisciplesGL-Modern-C4dll-R.zip'
            New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
            Write-Host "Downloading DisciplesGL-Modern $WrapperVersion from GitHub..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $oldProgress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'   # the progress bar makes Windows PowerShell download very slowly
            try {
                Invoke-WebRequest -Uri $WrapperUrl -OutFile $WrapperZip -UseBasicParsing
            } catch {
                Fail "Download failed ($($_.Exception.Message)). Download $WrapperUrl yourself and run: install.ps1 -WrapperZip <path to the zip>"
            } finally {
                $ProgressPreference = $oldProgress
            }
        }
        if ((Get-Sha256 $WrapperZip) -ne $WrapperZipSha256) {
            Fail "'$WrapperZip' isn't the DisciplesGL-Modern $WrapperVersion release zip."
        }
        $wrapperRoot = Open-Source $WrapperZip 'wrapper'
        $wrapperFiles = @(Get-RelativeFiles $wrapperRoot | Where-Object { $_ -notlike '*.txt' })
        Write-Host "  Got DisciplesGL-Modern $WrapperVersion ($($wrapperFiles.Count) files)."
    }
}
Write-Host ""

# ---------------------------------------------------------------------------
# 2. Back up, then install
# ---------------------------------------------------------------------------
Write-Host "Backing up original files to '$backup'..."
New-Item -ItemType Directory -Path $backup | Out-Null
Copy-Item -LiteralPath $mss -Destination (Join-Path $backup 'MSS32.DLL')
Copy-Item -LiteralPath $dlg -Destination (Join-Path $backup 'Interf.dlg')
Copy-Item -LiteralPath $roteScens -Destination (Join-Path $backup 'scens') -Recurse
$scripts = Join-Path $GamePath 'Scripts'
$hadScripts = Test-Path -LiteralPath $scripts
if ($hadScripts) { Copy-Item -LiteralPath $scripts -Destination (Join-Path $backup 'Scripts') -Recurse }
$saveGame = Join-Path $GamePath 'SaveGame'
$hadSaveGame = Test-Path -LiteralPath $saveGame
$state = [ordered]@{
    hadScripts  = $hadScripts
    hadSaveGame = $hadSaveGame
    mssName     = (Split-Path $mss -Leaf)
    optional    = @()
}
$stateFile = Join-Path $backup 'install.json'
$state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding ASCII

Write-Host "Installing the modding toolset..."
Rename-Item -LiteralPath $mss -NewName 'mss23.dll'
Copy-Item -LiteralPath (Join-Path $Files 'mss32.dll') -Destination (Join-Path $GamePath 'mss32.dll')
New-Item -ItemType Directory -Path $scripts -Force | Out-Null
Copy-Item -Path (Join-Path $Files 'Scripts\*') -Destination $scripts -Recurse -Force

Write-Host "Adding the Gallean's Return button to Interf.dlg..."
[IO.File]::WriteAllBytes($dlg, $latin1.GetBytes($newDlg))

Write-Host "Writing scenario tables..."
Copy-Item -Path (Join-Path $tmp '*') -Destination $roteScens -Force

if (-not $hadSaveGame) {
    Write-Host "Creating SaveGame folder..."
    New-Item -ItemType Directory -Path $saveGame | Out-Null
}

# Each optional mod is recorded in install.json straight after it's copied, so uninstall can
# undo it even if a later step fails.
if ($lazyRoot) {
    Write-Host "Installing Lazy Mod 1.06..."
    $state.optional += Install-Optional 'LazyMod' $lazyRoot $lazyFiles
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding ASCII
}
if ($wrapperRoot) {
    Write-Host "Installing DisciplesGL-Modern $WrapperVersion..."
    $state.optional += Install-Optional 'DisciplesGL' $wrapperRoot $wrapperFiles
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding ASCII
}

Remove-Item -LiteralPath $tmpRoot -Recurse -Force

Write-Host ""
Write-Host "Done. Start a new campaign and use the button above Continue on the race screen." -ForegroundColor Green
