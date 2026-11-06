@echo off
rem Installerar eller uppdaterar Svartboken. Lagg till "tabort" for att sluta uppdatera automatiskt.
setlocal
set "SB_SELF=%~f0"
set "SB_ARG=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:SB_SELF,[Text.Encoding]::UTF8); Invoke-Expression $s.Substring($s.IndexOf('#'+'PS-START'))"
set "SB_CODE=%ERRORLEVEL%"
if /i not "%SB_ARG%"=="tyst" if not defined SVARTBOKEN_NO_PROMPT pause
exit /b %SB_CODE%
#PS-START
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'MaxHegdal/Svartboken'
$Silent = $env:SB_ARG -eq 'tyst'
$NoPrompt = [bool]$env:SVARTBOKEN_NO_PROMPT
$DataDir = Join-Path $env:LOCALAPPDATA 'Svartboken'
$PathFile = Join-Path $DataDir 'wow-sokvag.txt'
$AskedFile = Join-Path $DataDir 'fragat-om-autostart.txt'
$LogFile = Join-Path $DataDir 'logg.txt'
$StartupFile = if ($env:SVARTBOKEN_STARTUP) { $env:SVARTBOKEN_STARTUP } else { Join-Path ([Environment]::GetFolderPath('Startup')) 'Svartboken-uppdatering.cmd' }

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

function Say($text) {
    if ($Silent) {
        Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format s)  $text" -Encoding UTF8
    } else {
        Write-Host $text
    }
}

function Test-AddOnsParent($wow) {
    return $wow -and (Test-Path -LiteralPath (Join-Path $wow '_forever_'))
}

# Hittar WoW-mappen: sparad sökväg, Battle.net:s inställning, vanliga platser och sist fråga.
function Find-AddOnsDir {
    if ($env:SVARTBOKEN_ADDONS) { return $env:SVARTBOKEN_ADDONS }

    $candidates = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $PathFile) {
        [void]$candidates.Add((Get-Content -LiteralPath $PathFile -Encoding UTF8 -TotalCount 1))
    }
    $bnetConfig = Join-Path $env:APPDATA 'Battle.net\Battle.net.config'
    if (Test-Path -LiteralPath $bnetConfig) {
        try {
            $default = (Get-Content -LiteralPath $bnetConfig -Raw | ConvertFrom-Json).Client.Install.DefaultInstallPath
            if ($default) { [void]$candidates.Add((Join-Path $default 'World of Warcraft')) }
        } catch {}
    }
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne 'Fixed') { continue }
        foreach ($rel in 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'World of Warcraft',
                         'Games\World of Warcraft', 'Spel\World of Warcraft', 'Battle.net\World of Warcraft') {
            [void]$candidates.Add((Join-Path $drive.RootDirectory.FullName $rel))
        }
    }
    foreach ($wow in $candidates) {
        if (Test-AddOnsParent $wow) {
            Set-Content -LiteralPath $PathFile -Value $wow -Encoding UTF8
            return (Join-Path $wow '_forever_\Interface\AddOns')
        }
    }
    if ($Silent) { throw 'Hittade inte World of Warcraft.' }

    Write-Host 'Hittade inte World of Warcraft. Välj mappen "World of Warcraft" i rutan som öppnas.'
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Välj mappen World of Warcraft (den som innehåller _forever_)'
    if ($dialog.ShowDialog() -eq 'OK' -and (Test-AddOnsParent $dialog.SelectedPath)) {
        Set-Content -LiteralPath $PathFile -Value $dialog.SelectedPath -Encoding UTF8
        return (Join-Path $dialog.SelectedPath '_forever_\Interface\AddOns')
    }
    throw 'Mappen innehåller inte _forever_.'
}

function Get-TocVersion($toc) {
    if (-not (Test-Path -LiteralPath $toc)) { return $null }
    foreach ($line in Get-Content -LiteralPath $toc -Encoding UTF8) {
        if ($line -match '^##\s*Version:\s*(\d+\.\d+\.\d+)\s*$') { return [version]$Matches[1] }
    }
    return $null
}

# Packar upp och byter ut mappen. Går något fel ligger den gamla versionen kvar.
function Install-Zip($zipPath, $addOnsDir) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Force -Path $addOnsDir | Out-Null
    # Samma disk som AddOns, så att flytten går, men utanför så att WoW inte ser mappen.
    $work = Join-Path (Split-Path -Parent (Split-Path -Parent $addOnsDir)) ('Svartboken-uppdatering-' + [Guid]::NewGuid().ToString('N'))
    $dest = Join-Path $addOnsDir 'Svartboken'
    $old = Join-Path $work 'gammal'
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if (-not $name.StartsWith('Svartboken/') -or $name -match '(^|/)\.\.(/|$)' -or $name -match ':') {
                throw "Otillåten fil i paketet: $name"
            }
            if ($name.EndsWith('/')) { continue }
            $target = Join-Path $work ($name.Replace('/', '\'))
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
        $new = Join-Path $work 'Svartboken'
        if (-not (Get-TocVersion (Join-Path $new 'Svartboken.toc'))) { throw 'Paketet saknar en giltig Svartboken.toc.' }
        $hadOld = Test-Path -LiteralPath $dest
        if ($hadOld) { Move-Item -LiteralPath $dest -Destination $old }
        try {
            Move-Item -LiteralPath $new -Destination $dest
        } catch {
            if ($hadOld) { Move-Item -LiteralPath $old -Destination $dest }
            throw
        }
    } finally {
        $zip.Dispose()
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    }
}

function Update-Addon {
    $addOnsDir = Find-AddOnsDir
    $local = Get-TocVersion (Join-Path $addOnsDir 'Svartboken\Svartboken.toc')

    $downloaded = $null
    if ($env:SVARTBOKEN_ZIP) {
        $remote = [version]$env:SVARTBOKEN_VERSION
        $zipPath = $env:SVARTBOKEN_ZIP
    } else {
        $headers = @{ 'User-Agent' = 'Svartboken-Uppdaterare' }
        $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/latest"
        $remote = [version]($release.tag_name -replace '^v', '')
        if ($local -and $local -ge $remote) { $zipPath = $null } else {
            $asset = $release.assets | Where-Object { $_.name -eq 'Svartboken.zip' } | Select-Object -First 1
            if (-not $asset) { throw 'Versionen saknar Svartboken.zip.' }
            $downloaded = Join-Path ([IO.Path]::GetTempPath()) ('Svartboken-' + [Guid]::NewGuid().ToString('N') + '.zip')
            Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $asset.browser_download_url -OutFile $downloaded
            if ($asset.digest -match '^sha256:(.+)$') {
                if ((Get-FileHash -LiteralPath $downloaded -Algorithm SHA256).Hash -ne $Matches[1]) {
                    throw 'Filen blev skadad vid nedladdningen.'
                }
            }
            $zipPath = $downloaded
        }
    }

    if ($local -and $local -ge $remote) {
        Say "Svartboken $local är senaste versionen."
        return
    }
    try {
        Install-Zip $zipPath $addOnsDir
    } finally {
        if ($downloaded -and (Test-Path -LiteralPath $downloaded)) { Remove-Item -LiteralPath $downloaded -Force }
    }
    if ($local) { Say "Svartboken uppdaterad från $local till $remote." } else { Say "Svartboken $remote installerad." }
    Say 'Är spelet igång? Skriv /reload, eller starta om om det här var första installationen.'
}

# Kör den här filen tyst varje gång Windows startar. Går att ta bort när som helst.
function Enable-Autostart {
    $copy = Join-Path $DataDir 'Uppdatera-Svartboken.cmd'
    if ($env:SB_SELF -ne $copy) { Copy-Item -LiteralPath $env:SB_SELF -Destination $copy -Force }
    $content = "@start `"`" /min cmd /c `"`"%LOCALAPPDATA%\Svartboken\Uppdatera-Svartboken.cmd`" tyst`"`r`n"
    [IO.File]::WriteAllText($StartupFile, $content)
    Say 'Klart. Svartboken uppdateras nu när Windows startar.'
}

function Disable-Autostart {
    if (Test-Path -LiteralPath $StartupFile) { Remove-Item -LiteralPath $StartupFile -Force }
    Set-Content -LiteralPath $AskedFile -Value 'nej' -Encoding UTF8
    Say 'Automatisk uppdatering är avstängd. Addonet ligger kvar i spelet.'
}

try {
    if ($env:SB_ARG -eq 'tabort') {
        Disable-Autostart
        exit 0
    }
    Update-Addon
    if (-not $Silent -and -not $NoPrompt -and -not (Test-Path -LiteralPath $AskedFile) -and -not (Test-Path -LiteralPath $StartupFile)) {
        $answer = Read-Host 'Vill du att Svartboken uppdateras av sig självt när Windows startar? [J/n]'
        Set-Content -LiteralPath $AskedFile -Value $answer -Encoding UTF8
        if ($answer -notmatch '^[nN]') { Enable-Autostart }
    }
    exit 0
} catch {
    Say "Det gick inte: $($_.Exception.Message)"
    exit 1
}
