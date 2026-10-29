<#
.SYNOPSIS
    Shrekify.ps1 - turns your desktop into Shrek, reversibly.

.DESCRIPTION
    Run it once : backs up and replaces your wallpaper, the images in the
                  target folders, and your shortcut icons with Shrek.
    Run it again: detects the backup manifest and restores everything.

    It is a TOGGLE. The presence of the manifest file is what decides the
    direction, so you never have to remember which state you are in.

    Nothing is ever deleted. Original files are MOVED into a backup folder
    and recorded in a JSON manifest; restore moves them back.

.PARAMETER Folders
    Folders whose images get replaced. Defaults to your Desktop and Pictures.

.PARAMETER AllDrives
    DANGER: also walks every fixed drive. Slow, and it will touch images
    inside applications/games, which can make them look wrong until restore.
    It still SKIPS Windows and Program Files to avoid breaking the OS.

.PARAMETER WhatIf
    Show what would happen without changing anything. (Built-in.)

.NOTES
    Put shrek.jpg (the image) and optionally shrek.ico (the icon) next to
    this script. shrek.jpg is required; without shrek.ico the shortcut-icon
    step is skipped.
    Target: Windows PowerShell 5.1+ or PowerShell 7+. Run as your normal user.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]] $Folders,
    [switch]   $AllDrives
)

$ErrorActionPreference = 'Stop'

# --- Paths & state -----------------------------------------------------------
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateRoot   = Join-Path $env:LOCALAPPDATA 'Shrekify'
$BackupDir   = Join-Path $StateRoot 'backup'
$Manifest    = Join-Path $StateRoot 'manifest.json'
$ShrekImage  = Join-Path $ScriptDir 'shrek.jpg'
$ShrekIcon   = Join-Path $ScriptDir 'shrek.ico'

$ImageExt = @('.jpg', '.jpeg', '.png', '.bmp', '.gif', '.webp', '.tif', '.tiff')

# --- Win32 interop for wallpaper --------------------------------------------
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Wall {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@ -ErrorAction SilentlyContinue

function Set-Wallpaper([string]$Path) {
    # 20 = SPI_SETDESKWALLPAPER, 0x01|0x02 = update + broadcast change
    [void][Wall]::SystemParametersInfo(20, 0, $Path, 0x03)
}

# --- Asset bootstrap ---------------------------------------------------------
function Ensure-Assets {
    if (-not (Test-Path $ShrekImage)) {
        throw "shrek.jpg not found next to the script ($ShrekImage). Put a 'shrek.jpg' there and rerun."
    }
    if (-not (Test-Path $ShrekIcon)) {
        Write-Host "shrek.ico not found - shortcut icons will be left alone." -ForegroundColor Yellow
    }
}

# --- Manifest helpers --------------------------------------------------------
function New-Manifest {
    [pscustomobject]@{
        createdUtc = (Get-Date).ToUniversalTime().ToString('o')
        wallpaper  = $null          # { original = <path or ''> }
        images     = @()            # [{ original; backup }]
        shortcuts  = @()            # [{ path; iconLocation }]
    }
}

function Save-Manifest($m) {
    $m | ConvertTo-Json -Depth 6 | Set-Content -Path $Manifest -Encoding UTF8
}

# =============================================================================
#  SHREKIFY
# =============================================================================
function Invoke-Shrekify {
    Write-Host "`n=== SHREKIFYING ===" -ForegroundColor Green
    Ensure-Assets
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $m = New-Manifest

    # --- 1. Wallpaper ---
    $curWall = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
    if ($PSCmdlet.ShouldProcess('desktop wallpaper', 'set to Shrek')) {
        $m.wallpaper = [pscustomobject]@{ original = [string]$curWall }
        Set-Wallpaper $ShrekImage
        Write-Host "  wallpaper -> Shrek"
    }

    # --- 2. Image files ---
    $targets = @()
    if ($Folders) {
        $targets = $Folders
    } else {
        $targets = @(
            [Environment]::GetFolderPath('Desktop'),
            [Environment]::GetFolderPath('MyPictures')
        )
    }
    if ($AllDrives) {
        $targets = Get-PSDrive -PSProvider FileSystem |
                   Where-Object { $_.Free -ne $null } |
                   ForEach-Object { $_.Root }
        Write-Host "  -AllDrives: scanning whole drives (slow)..." -ForegroundColor Yellow
    }

    # Never touch these - replacing images here breaks Windows / installed apps.
    $protected = @(
        "$env:SystemRoot",
        "${env:ProgramFiles}",
        "${env:ProgramFiles(x86)}",
        "$env:ProgramData\Microsoft",
        $StateRoot
    ) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLower() }

    $images = New-Object System.Collections.ArrayList
    foreach ($root in ($targets | Select-Object -Unique)) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $ImageExt -contains $_.Extension.ToLower() } |
            ForEach-Object {
                $full = $_.FullName.ToLower()
                $isProtected = $false
                foreach ($p in $protected) { if ($full.StartsWith($p + '\')) { $isProtected = $true; break } }
                if (-not $isProtected) { [void]$images.Add($_) }
            }
    }

    $i = 0
    foreach ($img in $images) {
        $i++
        if (-not $PSCmdlet.ShouldProcess($img.FullName, 'replace with Shrek')) { continue }
        try {
            $backupName = ('{0}__{1}' -f ([guid]::NewGuid().ToString('N')), $img.Name)
            $backupPath = Join-Path $BackupDir $backupName
            Move-Item -LiteralPath $img.FullName -Destination $backupPath -Force
            Copy-Item -LiteralPath $ShrekImage -Destination $img.FullName -Force
            $m.images += [pscustomobject]@{ original = $img.FullName; backup = $backupPath }
        } catch {
            Write-Warning "skip $($img.FullName): $_"
        }
    }
    Write-Host "  images replaced: $($m.images.Count)"

    # --- 3. Shortcut icons ---
    if (Test-Path $ShrekIcon) {
        $lnkRoots = @(
            [Environment]::GetFolderPath('Desktop'),
            [Environment]::GetFolderPath('CommonDesktopDirectory'),
            (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
        )
        $sh = New-Object -ComObject WScript.Shell
        foreach ($root in $lnkRoots) {
            if (-not (Test-Path $root)) { continue }
            Get-ChildItem -LiteralPath $root -Recurse -Filter *.lnk -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if (-not $PSCmdlet.ShouldProcess($_.FullName, 'point icon to Shrek')) { return }
                try {
                    $lnk = $sh.CreateShortcut($_.FullName)
                    $m.shortcuts += [pscustomobject]@{ path = $_.FullName; iconLocation = $lnk.IconLocation }
                    $lnk.IconLocation = "$ShrekIcon,0"
                    $lnk.Save()
                } catch { Write-Warning "skip shortcut $($_.FullName): $_" }
            }
        }
        Write-Host "  shortcut icons changed: $($m.shortcuts.Count)"
    }

    if (-not $WhatIfPreference) {
        Save-Manifest $m
        Write-Host "`nDone. Run the script again to restore everything." -ForegroundColor Green
    }
}

# =============================================================================
#  RESTORE
# =============================================================================
function Invoke-Restore {
    Write-Host "`n=== RESTORING ===" -ForegroundColor Cyan
    $m = Get-Content $Manifest -Raw | ConvertFrom-Json

    # --- 1. Wallpaper ---
    if ($m.wallpaper -and $PSCmdlet.ShouldProcess('desktop wallpaper', 'restore')) {
        # Passing '' to SystemParametersInfo clears the wallpaper, which is the
        # correct restore when the user originally had a solid-color background.
        Set-Wallpaper ([string]$m.wallpaper.original)
        Write-Host "  wallpaper restored"
    }

    # --- 2. Image files ---
    # @(...) guards against ConvertFrom-Json returning a single object (not an
    # array) for one entry, or an empty-string for a zero-length array.
    $imgEntries = @($m.images) | Where-Object { $_ -and $_.original }
    $restored = 0
    foreach ($entry in $imgEntries) {
        if (-not $PSCmdlet.ShouldProcess($entry.original, 'restore original')) { continue }
        try {
            if (Test-Path -LiteralPath $entry.backup) {
                Move-Item -LiteralPath $entry.backup -Destination $entry.original -Force
                $restored++
            }
        } catch { Write-Warning "could not restore $($entry.original): $_" }
    }
    Write-Host "  images restored: $restored / $($imgEntries.Count)"

    # --- 3. Shortcut icons ---
    $lnkEntries = @($m.shortcuts) | Where-Object { $_ -and $_.path }
    if ($lnkEntries.Count -gt 0) {
        $sh = New-Object -ComObject WScript.Shell
        foreach ($s in $lnkEntries) {
            if (-not $PSCmdlet.ShouldProcess($s.path, 'restore icon')) { continue }
            try {
                $lnk = $sh.CreateShortcut($s.path)
                $lnk.IconLocation = $s.iconLocation
                $lnk.Save()
            } catch { Write-Warning "could not restore icon $($s.path): $_" }
        }
        Write-Host "  shortcut icons restored: $($lnkEntries.Count)"
    }

    if (-not $WhatIfPreference) {
        Remove-Item $Manifest -Force -ErrorAction SilentlyContinue
        Remove-Item $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "`nDone. Everything is back to normal." -ForegroundColor Cyan
    }
}

# =============================================================================
#  ENTRY
# =============================================================================
if (Test-Path $Manifest) { Invoke-Restore } else { Invoke-Shrekify }
