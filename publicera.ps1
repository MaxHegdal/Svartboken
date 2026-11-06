# Publicerar en ny version av Svartboken till gänget.
#   .\publicera.ps1 1.2.0 "Vad som är nytt"
#   .\publicera.ps1 1.2.0 -BaraPaket    bygger bara Svartboken.zip, utan att publicera
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Nyheter = '',
    [switch]$BaraPaket
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Skriv versionen som till exempel 1.2.0.' }

$root = $PSScriptRoot
$toc = Join-Path $root 'Svartboken\Svartboken.toc'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not $BaraPaket) {
    if (git -C $root status --porcelain) { throw 'Det finns osparade ändringar. Committa dem först.' }
    if (git -C $root tag --list "v$Version") { throw "Version $Version finns redan." }
}

# Versionen i toc-filen är den som spelet och uppdateraren läser.
$text = [IO.File]::ReadAllText($toc, $utf8)
$updated = [regex]::Replace($text, '(?m)^## Version: .*$', "## Version: $Version")
if ($updated -ne $text) { [IO.File]::WriteAllText($toc, $updated, $utf8) }

# Egen paketering, eftersom Compress-Archive i Windows PowerShell skriver bakåtsnedstreck i zip-filen.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = Join-Path $root 'Svartboken.zip'
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    $base = Join-Path $root 'Svartboken'
    foreach ($file in Get-ChildItem -LiteralPath $base -File -Recurse) {
        $relative = $file.FullName.Substring($base.Length + 1).Replace('\', '/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, "Svartboken/$relative")
    }
} finally {
    $zip.Dispose()
}
Write-Host "Byggde Svartboken.zip ($Version)."
if ($BaraPaket) { return }

if (git -C $root status --porcelain) {
    git -C $root add Svartboken/Svartboken.toc
    git -C $root commit -m "Version $Version"
    if ($LASTEXITCODE -ne 0) { throw 'Commit misslyckades.' }
}
git -C $root tag "v$Version"
git -C $root push origin HEAD "v$Version"
if ($LASTEXITCODE -ne 0) { throw 'Push misslyckades.' }
if (-not $Nyheter) { $Nyheter = "Version $Version" }
gh release create "v$Version" $zipPath (Join-Path $root 'Uppdatera-Svartboken.cmd') --title "Svartboken $Version" --notes $Nyheter
if ($LASTEXITCODE -ne 0) { throw 'Release misslyckades.' }
Write-Host "Klart. Gänget får $Version nästa gång uppdateraren körs."
