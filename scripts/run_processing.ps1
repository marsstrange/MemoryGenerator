# Opens painting_visualizer.pde in the Processing IDE (processing.exe), passing the file
# directly as an argument -- this doesn't depend on Windows having a .pde file-type
# association registered (which a portable/extracted Processing install often lacks).
# Does NOT auto-run the sketch: press the Run (play) button inside Processing yourself.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sketchDir = (Resolve-Path (Join-Path $scriptDir "..\painting_visualizer")).Path
$pdeFile   = Join-Path $sketchDir "painting_visualizer.pde"

if (-not (Test-Path $pdeFile)) {
    Write-Host "Could not find $pdeFile"
    Read-Host "Press Enter to exit"
    exit 1
}

# Processing is usually a portable extracted ZIP, not a Program Files install, so its
# location varies per machine and can't be reliably auto-discovered. Check, in order:
# an explicit env var, PATH, a Program Files guess, then a path remembered from a
# previous run on this machine. If all of those fail, ask once and remember the answer
# (in a gitignored file) so nobody has to pre-configure anything themselves.
$cacheFile = Join-Path $scriptDir ".processing_ide_path"
$procPath  = $null

if ($env:PROCESSING_APP -and (Test-Path $env:PROCESSING_APP)) {
    $procPath = $env:PROCESSING_APP
} else {
    $procCmd = Get-Command processing.exe -ErrorAction SilentlyContinue
    if ($procCmd) {
        $procPath = $procCmd.Source
    } else {
        $procPath = Get-ChildItem -Path "C:\Program Files\processing-*\processing.exe",
                                         "C:\Program Files (x86)\processing-*\processing.exe" `
                                    -ErrorAction SilentlyContinue |
                    Select-Object -First 1 -ExpandProperty FullName
    }
}

if (-not $procPath -and (Test-Path $cacheFile)) {
    $cached = (Get-Content $cacheFile -Raw -ErrorAction SilentlyContinue)
    if ($cached) { $cached = $cached.Trim() }
    if ($cached -and (Test-Path $cached)) {
        $procPath = $cached
    }
}

if (-not $procPath) {
    Write-Host "Could not find processing.exe (the Processing IDE) automatically."
    $typed = Read-Host "Enter the full path to processing.exe (inside your Processing install folder)"
    if ($typed -and (Test-Path $typed)) {
        $procPath = $typed
        Set-Content -Path $cacheFile -Value $procPath
        Write-Host "Saved -- future runs on this machine will find it automatically."
    }
}

if (-not $procPath) {
    Write-Host "No valid path given."
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Opening $pdeFile in Processing: $procPath"
Start-Process -FilePath $procPath -ArgumentList "`"$pdeFile`""
