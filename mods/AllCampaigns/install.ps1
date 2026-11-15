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

    Run uninstall.ps1 to put everything back.

.PARAMETER GamePath
    Rise of the Elves folder. If left out, the GOG registry entry is offered as default.

.PARAMETER BasePath
    Dark Prophecy / Gallean's Return folder. If left out, the GOG registry entry is offered as default.
#>
param(
    [string]$GamePath,
    [string]$BasePath
)

$ErrorActionPreference = 'Stop'

$BackupName = '_AllCampaigns_backup'
# Two GOG v3.01 builds exist. They only differ in six unit id strings in the data
# section, the code (and so every hooked address) is identical.
$RoteExeSha256 = @(
    '3964DF2F9EFBE92CC9777080FA00B242557EFDB4654410BE67E50A4DBCDC85BD',
    '88DC8162D60D79F394696DB5FF48C68586E21F1F99A6C4D1C2328DEA81771D8F'
)
$RoteGogId = '1207663713'
$BaseGogId = '1207663703'
$Files = Join-Path $PSScriptRoot 'files'

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
    exit 1
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
if ($RoteExeSha256 -notcontains (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash) {
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
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("AllCampaigns_" + [guid]::NewGuid().ToString('N'))
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
@{
    hadScripts  = $hadScripts
    hadSaveGame = $hadSaveGame
    mssName     = (Split-Path $mss -Leaf)
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'install.json') -Encoding ASCII

Write-Host "Installing the modding toolset..."
Rename-Item -LiteralPath $mss -NewName 'mss23.dll'
Copy-Item -LiteralPath (Join-Path $Files 'mss32.dll') -Destination (Join-Path $GamePath 'mss32.dll')
New-Item -ItemType Directory -Path $scripts -Force | Out-Null
Copy-Item -Path (Join-Path $Files 'Scripts\*') -Destination $scripts -Recurse -Force

Write-Host "Adding the Gallean's Return button to Interf.dlg..."
[IO.File]::WriteAllBytes($dlg, $latin1.GetBytes($newDlg))

Write-Host "Writing scenario tables..."
Copy-Item -Path (Join-Path $tmp '*') -Destination $roteScens -Force
Remove-Item -LiteralPath $tmp -Recurse -Force

if (-not $hadSaveGame) {
    Write-Host "Creating SaveGame folder..."
    New-Item -ItemType Directory -Path $saveGame | Out-Null
}

Write-Host ""
Write-Host "Done. Start a new campaign and use the button above Continue on the race screen." -ForegroundColor Green
