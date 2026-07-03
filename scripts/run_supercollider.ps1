# Launches SuperCollider headless (no IDE window) against SC_mood_reactive.scd.
# Starts in a minimized console -- check it for "Mood-reactive receiver ready on
# port 12001." or any errors. To stop it, close that window from the taskbar
# (or open it and press Ctrl+C).

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scdFile   = Join-Path $scriptDir "..\audio_playback\SC_mood_reactive.scd"

$sclangCmd = Get-Command sclang.exe -ErrorAction SilentlyContinue
if ($sclangCmd) {
    $sclangPath = $sclangCmd.Source
} else {
    $sclangPath = Get-ChildItem -Path "C:\Program Files\SuperCollider*\sclang.exe",
                                      "C:\Program Files (x86)\SuperCollider*\sclang.exe" `
                                 -ErrorAction SilentlyContinue |
                  Select-Object -First 1 -ExpandProperty FullName
}

if (-not $sclangPath) {
    Write-Host "Could not find sclang.exe on PATH or in Program Files."
    Write-Host "Edit this script and hardcode `$sclangPath` to the full path of sclang.exe."
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Path $scdFile)) {
    Write-Host "Could not find $scdFile"
    Read-Host "Press Enter to exit"
    exit 1
}

# scsynth.exe (the audio server, a separate binary from sclang.exe) is looked up by bare
# name when sclang boots the server -- the SC IDE knows its own install dir internally,
# but a bare sclang.exe launched like this doesn't, so PATH needs it added explicitly.
# It lives right alongside sclang.exe in the same install directory.
$env:PATH = "$(Split-Path -Parent $sclangPath);$env:PATH"

Write-Host "Starting SuperCollider (headless): $sclangPath `"$scdFile`""
Start-Process -FilePath $sclangPath -ArgumentList "`"$scdFile`"" -WindowStyle Minimized
