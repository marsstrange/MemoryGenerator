@echo off
REM Double-click wrapper: runs run_supercollider.ps1 without fighting PowerShell's
REM execution-policy prompt (that policy only blocks *.ps1 double-clicks, not -File).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_supercollider.ps1"
