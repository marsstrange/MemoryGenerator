# Opens painting_visualizer.pde in whatever app Windows associates with .pde files
# (the Processing IDE, if installed) -- same as double-clicking the file yourself.
# It does NOT auto-run the sketch: press the Run (play) button inside Processing once
# it opens. This avoids needing to locate processing-java.exe at all.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sketchDir = (Resolve-Path (Join-Path $scriptDir "..\painting_visualizer")).Path
$pdeFile   = Join-Path $sketchDir "painting_visualizer.pde"

if (-not (Test-Path $pdeFile)) {
    Write-Host "Could not find $pdeFile"
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Opening $pdeFile ..."
Start-Process -FilePath $pdeFile
